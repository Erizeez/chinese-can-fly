import Foundation
import CoreLocation

/// 航班数据来源标识
public enum FlightDataSource: String, Sendable, CaseIterable {
    case userCustom = "用户录入"
    case offlinePackage = "离线航线库"
    case onlineRealtime = "在线实时态势"
}

/// 航班数据检索调度结果
public enum FlightLookupResult: Sendable {
    /// 成功获取航班数据
    case success(flight: FlightPlan, source: FlightDataSource, state: AirborneState?)
    /// 未检测到离线航线数据库（引导用户下载或在线查询）
    case offlineNotInstalled(callsign: String, suggestedAirline: String)
    /// 已安装离线航线库，但未收录该航班
    case notFoundInOffline(callsign: String, suggestedAirline: String)
    /// 联网查询成功捕获到空中态势
    case onlineFound(flight: FlightPlan, state: AirborneState)
    /// 联网查询未捕获到信号
    case onlineNotFound(callsign: String, reason: String)
    /// 检索失败或格式错误
    case failed(callsign: String, message: String)
}

/// 统一航班数据调度中枢 (Data Provider)
/// 负责协调：本地持久化库 -> 离线航电资源包 -> 在线实时 ADS-B -> 引导按需下载
public final class FlightDataProvider: Sendable {
    public static let shared = FlightDataProvider()

    private let offlineDb = OfflineFlightDatabase.shared
    private let resourceManager = OfflineResourceManager.shared
    private let openSkyClient = OpenSkyClient.shared

    public init() {}

    /// 检查离线航线网络包是否已安装就绪
    public var isRoutesPackageInstalled: Bool {
        offlineDb.isOfflinePackageInstalled
    }

    /// 检查全量机场与跑道物理模型包是否已安装就绪
    public var isAirportsPackageInstalled: Bool {
        AirportRepository.shared.isFullDatabaseInstalled
    }

    /// 执行首选离线快速检索 (优先匹配用户自定义库 -> 离线航线包 -> 未就绪提醒)
    public func lookupOffline(callsign: String) -> FlightLookupResult {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            return .failed(callsign: clean, message: "请输入有效的航班号")
        }

        // 1. 优先检查用户自定义/已保存航班表
        if offlineDb.isCustomFlight(callsign: clean), let plan = offlineDb.lookupFlight(callsign: clean) {
            return .success(flight: plan, source: .userCustom, state: nil)
        }

        // 2. 检查离线航线数据库是否已安装
        if !offlineDb.isOfflinePackageInstalled {
            let suggestedAirline = OfflineFlightDatabase.detectAirline(callsign: clean)
            return .offlineNotInstalled(callsign: clean, suggestedAirline: suggestedAirline)
        }

        // 3. 离线数据库已安装，尝试匹配
        if let plan = offlineDb.lookupFlight(callsign: clean) {
            return .success(flight: plan, source: .offlinePackage, state: nil)
        } else {
            let suggestedAirline = OfflineFlightDatabase.detectAirline(callsign: clean)
            return .notFoundInOffline(callsign: clean, suggestedAirline: suggestedAirline)
        }
    }

    /// 执行在线实时态势检索 (通过 OpenSky 开放航空网络探测空中广播)
    public func lookupOnline(callsign: String, basePlan: FlightPlan? = nil) async -> FlightLookupResult {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            return .failed(callsign: clean, message: "请输入有效的航班号")
        }

        do {
            if let state = try await openSkyClient.fetchFlightState(callsign: clean) {
                // 如果已有航线计划，直接将在线态势融合
                if let plan = basePlan ?? offlineDb.lookupFlight(callsign: clean) {
                    return .onlineFound(flight: plan, state: state)
                }

                // 若此前完全无计划，利用智能航司与实时坐标推断生成临时态势计划
                let airline = OfflineFlightDatabase.detectAirline(callsign: clean)
                let alt = (state.baroAltitudeMeters ?? 10000.0) * 3.28084
                let plan = FlightPlan(
                    callsign: clean,
                    airline: airline,
                    aircraftModel: "实时在线目标 (ADS-B)",
                    departureIATA: "DEP",
                    departureICAO: "----",
                    arrivalIATA: "ARR",
                    arrivalICAO: "----",
                    distanceNM: 0.0,
                    plannedCruiseAltitudeFt: alt > 0 ? alt : 35000.0
                )
                return .onlineFound(flight: plan, state: state)
            } else {
                return .onlineNotFound(callsign: clean, reason: "当前 OpenSky 开放网络暂未接收到呼号为 \(clean) 的空中信号广播。")
            }
        } catch {
            return .onlineNotFound(callsign: clean, reason: "连接在线航电网络失败: \(error.localizedDescription)")
        }
    }

    /// 一键下载并激活离线航线数据库
    public func installRoutesPackage(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await resourceManager.downloadPackage(packageId: "db_flight_routes", onProgress: onProgress)
        offlineDb.reloadOfflineRoutesFromDisk()
    }

    /// 一键下载并激活全量机场与跑道物理模型数据库
    public func installAirportsPackage(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await resourceManager.downloadPackage(packageId: "db_airports_runways", onProgress: onProgress)
    }
}
