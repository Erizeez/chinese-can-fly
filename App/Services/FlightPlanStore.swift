import SwiftUI
import CoreLocation
import CCFlyCore

/// 航班计划与离线航线专属状态仓储 (纯数据驱动，完全脱耦传感器高频更新，保证搜索框与UI零掉帧)
@Observable
public final class FlightPlanStore: @unchecked Sendable {
    public static let shared = FlightPlanStore()

    // 当前选定的航班计划 (默认 nil，由用户自主输入检索或选择，杜绝硬编码强塞假数据)
    public var currentFlight: FlightPlan?
    public var currentDataSource: FlightDataSource?
    public var activeFlightState: AirborneState?

    // 状态与指示
    public var isSearchingOnline: Bool = false
    public var isDownloadingRoutesPackage: Bool = false
    public var downloadProgress: Double = 0.0
    public var onlineErrorMessage: String? = nil
    public var searchErrorMessage: String? = nil
    public var notFoundCallsign: String? = nil
    public var notInstalledCallsign: String? = nil
    public var suggestedAirline: String? = nil

    // 用户真实查询历史 (取代静态假数据)
    public var recentSearches: [String] = []

    // 预计算的大圆航线折线坐标，供航图秒级直接渲染，杜绝三角函数开销
    public private(set) var precomputedRouteCoords: [CLLocationCoordinate2D] = []

    // 航图专用的 1Hz 低频位置与航向，彻底解耦 30Hz 姿态仪高频更新
    public var chartPosition: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 39.5098, longitude: 116.4105)
    public var chartTrackDeg: Double = 0.0

    // 内存城市名称极速缓存，杜绝视图每次重绘加锁查库
    private var cityCache: [String: String] = [:]
    private let cacheLock = NSLock()
    private let recentSearchesKey = "CCFly_Recent_Flight_Searches_v1"

    private init() {
        // 初始为空，由用户自主检索或录入
        self.currentFlight = nil
        self.currentDataSource = nil
        self.activeFlightState = nil
        loadRecentSearches()
    }

    /// 执行航班检索 (由 FlightDataProvider 统一分发调度)
    public func selectFlight(callsign: String) -> Bool {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            self.searchErrorMessage = "请输入航班号"
            return false
        }

        self.onlineErrorMessage = nil
        self.searchErrorMessage = nil
        self.notFoundCallsign = nil
        self.notInstalledCallsign = nil
        self.suggestedAirline = nil

        let result = FlightDataProvider.shared.lookupOffline(callsign: clean)
        switch result {
        case let .success(flight, source, state):
            self.currentFlight = flight
            self.currentDataSource = source
            self.activeFlightState = state
            addRecentSearch(callsign: clean)
            cacheCityName(iata: flight.departureIATA)
            cacheCityName(iata: flight.arrivalIATA)
            computeRouteCoords(flight: flight)
            return true

        case let .offlineNotInstalled(callsign, suggested):
            self.notInstalledCallsign = callsign
            self.suggestedAirline = suggested
            return false

        case let .notFoundInOffline(callsign, suggested):
            self.notFoundCallsign = callsign
            self.suggestedAirline = suggested
            return false

        case let .failed(_, msg):
            self.searchErrorMessage = msg
            return false

        default:
            return false
        }
    }

    /// 一键下载并激活离线航线包，下载完成后自动用新离线库重新检索当前目标航班
    public func downloadAndInstallRoutesPackage(forCallsign targetCallsign: String? = nil) {
        isDownloadingRoutesPackage = true
        downloadProgress = 0.1

        Task {
            do {
                try await FlightDataProvider.shared.installRoutesPackage { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                await MainActor.run {
                    self.isDownloadingRoutesPackage = false
                    self.downloadProgress = 1.0
                    let callsignToSearch = targetCallsign ?? self.notInstalledCallsign
                    self.notInstalledCallsign = nil

                    if let target = callsignToSearch, !target.isEmpty {
                        _ = self.selectFlight(callsign: target)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingRoutesPackage = false
                    self.searchErrorMessage = "下载离线航线库失败: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 清空当前选中航班，回到空白准备状态
    public func clearCurrentFlight() {
        self.currentFlight = nil
        self.currentDataSource = nil
        self.activeFlightState = nil
        self.precomputedRouteCoords = []
        self.onlineErrorMessage = nil
        self.searchErrorMessage = nil
        self.notFoundCallsign = nil
        self.notInstalledCallsign = nil
        self.suggestedAirline = nil
    }

    /// 用户自定义录入航班并直接设为当前航班
    public func addCustomFlightAndSelect(callsign: String, airline: String, dep: String, arr: String, model: String, alt: Double) {
        OfflineFlightDatabase.shared.saveCustomFlight(callsign: callsign, airline: airline, dep: dep, arr: arr, model: model, alt: alt)
        _ = selectFlight(callsign: callsign)
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
    public func fetchOnlineState(callsign: String? = nil) {
        let queryCallsign = callsign ?? currentFlight?.callsign ?? notFoundCallsign ?? notInstalledCallsign ?? ""
        guard !queryCallsign.isEmpty else { return }

        isSearchingOnline = true
        onlineErrorMessage = nil

        Task {
            let res = await FlightDataProvider.shared.lookupOnline(callsign: queryCallsign, basePlan: currentFlight)
            await MainActor.run {
                self.isSearchingOnline = false
                switch res {
                case let .onlineFound(flight, state):
                    self.currentFlight = flight
                    self.currentDataSource = .onlineRealtime
                    self.activeFlightState = state
                    self.notFoundCallsign = nil
                    self.notInstalledCallsign = nil
                    self.addRecentSearch(callsign: flight.callsign)
                    self.cacheCityName(iata: flight.departureIATA)
                    self.cacheCityName(iata: flight.arrivalIATA)
                    self.computeRouteCoords(flight: flight)

                case let .onlineNotFound(_, reason):
                    self.onlineErrorMessage = reason

                case let .failed(_, msg):
                    self.onlineErrorMessage = msg

                default:
                    break
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

    // MARK: - 最近搜索历史
    private func addRecentSearch(callsign: String) {
        let clean = callsign.uppercased()
        recentSearches.removeAll(where: { $0 == clean })
        recentSearches.insert(clean, at: 0)
        if recentSearches.count > 8 {
            recentSearches = Array(recentSearches.prefix(8))
        }
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    private func loadRecentSearches() {
        if let stored = UserDefaults.standard.stringArray(forKey: recentSearchesKey) {
            self.recentSearches = stored
        }
    }

    public func removeRecentSearch(callsign: String) {
        recentSearches.removeAll(where: { $0 == callsign })
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
}
