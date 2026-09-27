import Foundation
import CoreLocation

/// 航路点与大圆航线工具
public struct RouteWaypoint: Codable, Identifiable, Sendable {
    public let id: Int
    public let latitude: Double
    public let longitude: Double
    public let distancePercent: Double // 进度比例 (0.0 ~ 1.0)

    public init(id: Int, latitude: Double, longitude: Double, distancePercent: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.distancePercent = distancePercent
    }
}

/// 空间地理与大圆航线算法
public enum NavigationMath {
    private static let earthRadiusKM = 6371.0
    private static let kmToNM = 0.539957

    /// 计算两点间大圆航距 (海里 NM)
    public static func greatCircleDistanceNM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let rLat1 = lat1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return (earthRadiusKM * c) * kmToNM
    }

    /// 计算起始初始真航向 (0-360°)
    public static func initialBearingDeg(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let rLat1 = lat1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let y = sin(dLon) * cos(rLat2)
        let x = cos(rLat1) * sin(rLat2) - sin(rLat1) * cos(rLat2) * cos(dLon)
        let bearingRad = atan2(y, x)
        var deg = bearingRad * 180.0 / .pi
        if deg < 0 { deg += 360.0 }
        return deg
    }

    /// 在两点大圆航线之间插值生成指定数量的离散航路点 (用于航路绘制与巡航导航)
    public static func generateGreatCircleWaypoints(lat1: Double, lon1: Double, lat2: Double, lon2: Double, count: Int = 20) -> [RouteWaypoint] {
        guard count >= 2 else { return [] }
        var waypoints: [RouteWaypoint] = []

        let rLat1 = lat1 * .pi / 180.0
        let rLon1 = lon1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0
        let rLon2 = lon2 * .pi / 180.0

        // 角距离 d
        let d = 2.0 * asin(sqrt(pow(sin((rLat1 - rLat2) / 2.0), 2.0) +
                                cos(rLat1) * cos(rLat2) * pow(sin((rLon1 - rLon2) / 2.0), 2.0)))

        for i in 0..<count {
            let f = Double(i) / Double(count - 1)
            let a = sin((1.0 - f) * d) / sin(d)
            let b = sin(f * d) / sin(d)

            let x = a * cos(rLat1) * cos(rLon1) + b * cos(rLat2) * cos(rLon2)
            let y = a * cos(rLat1) * sin(rLon1) + b * cos(rLat2) * sin(rLon2)
            let z = a * sin(rLat1) + b * sin(rLat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180.0 / .pi
            let lon = atan2(y, x) * 180.0 / .pi

            waypoints.append(RouteWaypoint(id: i, latitude: lat, longitude: lon, distancePercent: f))
        }

        return waypoints
    }
}

/// 离线航班号检索数据库
/// 用户自定义创建的离线航班航线记录
public struct CustomFlightEntry: Codable, Sendable {
    public let callsign: String
    public let airline: String
    public let dep: String
    public let arr: String
    public let model: String
    public let alt: Double

    public init(callsign: String, airline: String, dep: String, arr: String, model: String, alt: Double) {
        self.callsign = callsign
        self.airline = airline
        self.dep = dep
        self.arr = arr
        self.model = model
        self.alt = alt
    }
}

/// 离线航班号检索数据库 (内置高频干线 + 用户自定义持久化航线 + 智能航司推断)
public final class OfflineFlightDatabase: @unchecked Sendable {
    public static let shared = OfflineFlightDatabase()

    private let storageKey = "CCFly_CustomFlights_Store_v1"
    private var customSchedules: [String: CustomFlightEntry] = [:]
    private let lock = NSLock()

    // 预置国内核心干线与热门支线网络 (航司、航班号、起降 IATA、机型、预设计划巡航高度)
    private let staticSchedules: [String: (airline: String, dep: String, arr: String, model: String, alt: Double)] = [
        // 国航 Air China
        "CA1501": ("中国国际航空", "PEK", "SHA", "Airbus A350-900", 35000),
        "CA1502": ("中国国际航空", "SHA", "PEK", "Airbus A350-900", 36000),
        "CA1831": ("中国国际航空", "PEK", "CAN", "Boeing 777-300ER", 38000),
        "CA1301": ("中国国际航空", "PEK", "CAN", "Airbus A330-300", 36000),
        "CA4101": ("中国国际航空", "PEK", "CTU", "Boeing 787-9", 37000),
        "CA1405": ("中国国际航空", "PEK", "CKG", "Boeing 737-800", 34000),
        
        // 东航 China Eastern (含用户查询的沙县至上海核心班次 MU6594)
        "MU6594": ("中国东方航空", "SQJ", "SHA", "Boeing 737-800", 28000),
        "MU6593": ("中国东方航空", "SHA", "SQJ", "Boeing 737-800", 27000),
        "MU5101": ("中国东方航空", "SHA", "PEK", "Boeing 777-300ER", 36000),
        "MU5102": ("中国东方航空", "PEK", "SHA", "Airbus A350-900", 35000),
        "MU5183": ("中国东方航空", "PVG", "CAN", "Airbus A330-200", 34000),
        "MU5301": ("中国东方航空", "SHA", "CAN", "Airbus A320neo", 33000),
        "MU9191": ("中国东方航空 (C919全球首发)", "SHA", "PEK", "COMAC C919", 35000),
        "MU9192": ("中国东方航空 (C919全球首发)", "PEK", "SHA", "COMAC C919", 36000),
        
        // 南航 China Southern
        "CZ3101": ("中国南方航空", "CAN", "PEK", "Airbus A350-900", 37000),
        "CZ3002": ("中国南方航空", "PKX", "CAN", "Boeing 787-8", 36000),
        "CZ3523": ("中国南方航空", "CAN", "SHA", "Boeing 787-9", 35000),
        "CZ3907": ("中国南方航空", "CAN", "CTU", "Airbus A330-300", 34000),
        "CZ3401": ("中国南方航空", "CAN", "WUH", "Boeing 737-800", 32000),
        
        // 海航 Hainan Airlines
        "HU7601": ("海南航空", "PEK", "SHA", "Boeing 787-9", 35000),
        "HU7181": ("海南航空", "PEK", "HAK", "Boeing 787-9", 38000),
        "HU7701": ("海南航空", "PEK", "SZX", "Airbus A330-300", 36000),

        // 川航 Sichuan Airlines
        "3U8881": ("四川航空", "CTU", "PEK", "Airbus A350-900 (熊猫涂装)", 36000),
        "3U8882": ("四川航空", "PEK", "CTU", "Airbus A350-900", 37000),

        // 厦航 Xiamen Air
        "MF8101": ("厦门航空", "XMN", "PEK", "Boeing 787-8", 36000),
        "MF8102": ("厦门航空", "PEK", "XMN", "Boeing 737-800", 35000),

        // 吉祥 & 春秋
        "HO1251": ("吉祥航空", "SHA", "PEK", "Boeing 787-9 (吉享丝路)", 35000),
        "9C8801": ("春秋航空", "SHA", "SZX", "Airbus A320neo", 33000),

        // 深航 & 山航 & 联航
        "ZH9101": ("深圳航空", "SZX", "PEK", "Airbus A330-300", 36000),
        "SC1151": ("山东航空", "TNA", "PEK", "Boeing 737-800", 28000),
        "KN5988": ("中国联合航空", "PKX", "SHA", "Boeing 737-800", 31000)
    ]

    private init() {
        loadCustomFlightsFromDisk()
    }

    /// 根据航班号前缀自动推断航空公司官方全称
    public static func detectAirline(callsign: String) -> String {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("CA") || clean.hasPrefix("CCA") { return "中国国际航空" }
        if clean.hasPrefix("MU") || clean.hasPrefix("CES") { return "中国东方航空" }
        if clean.hasPrefix("CZ") || clean.hasPrefix("CSN") { return "中国南方航空" }
        if clean.hasPrefix("HU") || clean.hasPrefix("CHH") { return "海南航空" }
        if clean.hasPrefix("3U") || clean.hasPrefix("CSC") { return "四川航空" }
        if clean.hasPrefix("MF") || clean.hasPrefix("CXA") { return "厦门航空" }
        if clean.hasPrefix("HO") || clean.hasPrefix("DKH") { return "吉祥航空" }
        if clean.hasPrefix("9C") || clean.hasPrefix("CQH") { return "春秋航空" }
        if clean.hasPrefix("ZH") || clean.hasPrefix("CSZ") { return "深圳航空" }
        if clean.hasPrefix("SC") || clean.hasPrefix("CDG") { return "山东航空" }
        if clean.hasPrefix("FM") || clean.hasPrefix("CSH") { return "上海航空" }
        if clean.hasPrefix("KN") || clean.hasPrefix("CUA") { return "中国联合航空" }
        if clean.hasPrefix("JD") || clean.hasPrefix("CBJ") { return "首都航空" }
        if clean.hasPrefix("GS") || clean.hasPrefix("GCR") { return "天津航空" }
        if clean.hasPrefix("8L") || clean.hasPrefix("LKE") { return "祥鹏航空" }
        if clean.hasPrefix("KY") || clean.hasPrefix("KNA") { return "昆明航空" }
        if clean.hasPrefix("EU") || clean.hasPrefix("UEA") { return "成都航空" }
        if clean.hasPrefix("TV") || clean.hasPrefix("TBR") { return "西藏航空" }
        if clean.hasPrefix("GJ") || clean.hasPrefix("CDC") { return "长龙航空" }
        if clean.hasPrefix("QW") || clean.hasPrefix("QDA") { return "青岛航空" }
        if clean.hasPrefix("DZ") || clean.hasPrefix("EPA") { return "东海航空" }
        if clean.hasPrefix("NS") || clean.hasPrefix("HBC") { return "河北航空" }
        if clean.hasPrefix("AQ") || clean.hasPrefix("JYH") { return "九元航空" }
        if clean.hasPrefix("PN") || clean.hasPrefix("CHB") { return "西部航空" }
        if clean.hasPrefix("G5") || clean.hasPrefix("HXA") { return "华夏航空" }
        return "民航定期客运"
    }

    /// 根据航班号检索航线计划 (优先匹配用户自定义库，其次匹配内置库)
    public func lookupFlight(callsign: String) -> FlightPlan? {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var airline = ""
        var dep = ""
        var arr = ""
        var model = ""
        var alt: Double = 35000.0

        lock.lock()
        if let custom = customSchedules[clean] {
            airline = custom.airline
            dep = custom.dep
            arr = custom.arr
            model = custom.model
            alt = custom.alt
        } else if let entry = staticSchedules[clean] {
            airline = entry.airline
            dep = entry.dep
            arr = entry.arr
            model = entry.model
            alt = entry.alt
        } else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let airportRepo = AirportRepository.shared
        let depAirport = airportRepo.findAirport(code: dep)
        let arrAirport = airportRepo.findAirport(code: arr)

        let depLat = depAirport?.latitude ?? 39.9
        let depLon = depAirport?.longitude ?? 116.4
        let arrLat = arrAirport?.latitude ?? 31.2
        let arrLon = arrAirport?.longitude ?? 121.4

        let distance = NavigationMath.greatCircleDistanceNM(lat1: depLat, lon1: depLon, lat2: arrLat, lon2: arrLon)

        return FlightPlan(
            callsign: clean,
            airline: airline,
            aircraftModel: model,
            departureIATA: dep,
            departureICAO: depAirport?.icao ?? dep,
            arrivalIATA: arr,
            arrivalICAO: arrAirport?.icao ?? arr,
            distanceNM: distance,
            plannedCruiseAltitudeFt: alt
        )
    }

    /// 保存用户自定义航班计划并持久化
    public func saveCustomFlight(callsign: String, airline: String, dep: String, arr: String, model: String, alt: Double) {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDep = dep.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanArr = arr.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let finalAirline = airline.isEmpty ? Self.detectAirline(callsign: clean) : airline
        let finalModel = model.isEmpty ? "民航通用机型" : model
        let finalAlt = alt > 0 ? alt : 31000.0

        let entry = CustomFlightEntry(
            callsign: clean,
            airline: finalAirline,
            dep: cleanDep,
            arr: cleanArr,
            model: finalModel,
            alt: finalAlt
        )

        lock.lock()
        customSchedules[clean] = entry
        persistCustomFlightsToDisk()
        lock.unlock()
    }

    /// 获取所有支持的航班号列表 (含内置及自定义)
    public func getAvailableCallsigns() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let allKeys = Set(staticSchedules.keys).union(customSchedules.keys)
        return Array(allKeys).sorted()
    }

    private func loadCustomFlightsFromDisk() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let decoded = try? JSONDecoder().decode([String: CustomFlightEntry].self, from: data) {
                self.customSchedules = decoded
            }
        }
    }

    private func persistCustomFlightsToDisk() {
        if let encoded = try? JSONEncoder().encode(customSchedules) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
