import SwiftUI
import CCFlyCore

/// 航班计划与离线航线专属状态仓储 (纯数据驱动，完全脱耦传感器高频更新，保证搜索框与UI零掉帧)
@Observable
public final class FlightPlanStore: @unchecked Sendable {
    public static let shared = FlightPlanStore()

    public var currentFlight: FlightPlan?
    public var activeFlightState: AirborneState?
    public var isSearchingOnline: Bool = false
    public var onlineErrorMessage: String? = nil

    // 预计算的大圆航线折线坐标，供航图秒级直接渲染，杜绝三角函数开销
    public private(set) var precomputedRouteCoords: [CLLocationCoordinate2D] = []

    // 航图专用的 1Hz 低频位置与航向，彻底解耦 30Hz 姿态仪高频更新
    public var chartPosition: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 39.5098, longitude: 116.4105)
    public var chartTrackDeg: Double = 0.0

    // 内存城市名称极速缓存，杜绝视图每次重绘加锁查库
    private var cityCache: [String: String] = [:]
    private let cacheLock = NSLock()

    private init() {
        // 默认预选国航主力干线
        let initial = OfflineFlightDatabase.shared.lookupFlight(callsign: "CA1501")
        self.currentFlight = initial
        if let f = initial {
            cacheCityName(iata: f.departureIATA)
            cacheCityName(iata: f.arrivalIATA)
            computeRouteCoords(flight: f)
        }
    }

    /// 离线航班号精准检索
    public func selectFlight(callsign: String) -> Bool {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let found = OfflineFlightDatabase.shared.lookupFlight(callsign: clean) {
            self.currentFlight = found
            self.activeFlightState = nil
            self.onlineErrorMessage = nil
            cacheCityName(iata: found.departureIATA)
            cacheCityName(iata: found.arrivalIATA)
            computeRouteCoords(flight: found)
            return true
        } else {
            self.onlineErrorMessage = "离线库暂未收录 \(clean)，可通过搜索添加或在线刷新。"
            return false
        }
    }

    /// 极速获取机场所在城市 (带内存缓存，0纳秒访问)
    public func getCityName(iata: String) -> String {
        cacheLock.lock()
        if let cached = cityCache[iata] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let name = AirportRepository.shared.findAirport(code: iata)?.name ?? iata
        cacheLock.lock()
        cityCache[iata] = name
        cacheLock.unlock()
        return name
    }

    private func cacheCityName(iata: String) {
        let name = AirportRepository.shared.findAirport(code: iata)?.name ?? iata
        cacheLock.lock()
        cityCache[iata] = name
        cacheLock.unlock()
    }

    /// 在线开放 ADS-B 态势查询
    public func fetchOnlineState() {
        guard let flight = currentFlight else { return }
        isSearchingOnline = true
        onlineErrorMessage = nil

        Task {
            do {
                let state = try await OpenSkyClient.shared.fetchFlightState(callsign: flight.callsign)
                await MainActor.run {
                    self.isSearchingOnline = false
                    if let state = state {
                        self.activeFlightState = state
                    } else {
                        self.onlineErrorMessage = "当前 OpenSky 开放网络暂未捕获到呼号为 \(flight.callsign) 的实时信号 (可能未起飞或处于盲区)。"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSearchingOnline = false
                    self.onlineErrorMessage = "连接 OpenSky API 失败: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 在后台线程预计算大圆航线坐标
    public func computeRouteCoords(flight: FlightPlan) {
        Task.detached(priority: .userInitiated) {
            let dep = AirportRepository.shared.findAirport(code: flight.departureIATA)
            let arr = AirportRepository.shared.findAirport(code: flight.arrivalIATA)
            let waypoints = NavigationMath.generateGreatCircleWaypoints(
                lat1: dep?.latitude ?? 39.9,
                lon1: dep?.longitude ?? 116.4,
                lat2: arr?.latitude ?? 31.2,
                lon2: arr?.longitude ?? 121.4,
                count: 20
            )
            let coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            await MainActor.run {
                self.precomputedRouteCoords = coords
            }
        }
    }

    /// 接收 1Hz GPS 经纬度并更新航图标注 (低频节流，绝不影响姿态仪)
    public func updateChartPosition(latitude: Double, longitude: Double, trackDeg: Double) {
        self.chartPosition = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.chartTrackDeg = trackDeg
    }
}
