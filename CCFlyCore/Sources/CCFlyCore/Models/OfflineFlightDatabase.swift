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
public final class OfflineFlightDatabase: @unchecked Sendable {
    public static let shared = OfflineFlightDatabase()

    // 预置国内核心航线网络 (航司、航班号、起降 IATA、机型、预设计划巡航高度)
    private let staticSchedules: [String: (airline: String, dep: String, arr: String, model: String, alt: Double)] = [
        // 国航 Air China
        "CA1501": ("中国国际航空", "PEK", "SHA", "Airbus A350-900", 35000),
        "CA1502": ("中国国际航空", "SHA", "PEK", "Airbus A350-900", 36000),
        "CA1831": ("中国国际航空", "PEK", "CAN", "Boeing 777-300ER", 38000),
        "CA1301": ("中国国际航空", "PEK", "CAN", "Airbus A330-300", 36000),
        "CA4101": ("中国国际航空", "PEK", "CTU", "Boeing 787-9", 37000),
        "CA1405": ("中国国际航空", "PEK", "CKG", "Boeing 737-800", 34000),
        
        // 东航 China Eastern
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
        "9C8801": ("春秋航空", "SHA", "SZX", "Airbus A320neo", 33000)
    ]

    private init() {}

    /// 根据航班号检索航线计划
    public func lookupFlight(callsign: String) -> FlightPlan? {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let entry = staticSchedules[clean] else {
            return nil
        }

        let airportRepo = AirportRepository.shared
        let depAirport = airportRepo.findAirport(code: entry.dep)
        let arrAirport = airportRepo.findAirport(code: entry.arr)

        let depLat = depAirport?.latitude ?? 39.9
        let depLon = depAirport?.longitude ?? 116.4
        let arrLat = arrAirport?.latitude ?? 31.2
        let arrLon = arrAirport?.longitude ?? 121.4

        let distance = NavigationMath.greatCircleDistanceNM(lat1: depLat, lon1: depLon, lat2: arrLat, lon2: arrLon)

        return FlightPlan(
            callsign: clean,
            airline: entry.airline,
            aircraftModel: entry.model,
            departureIATA: entry.dep,
            departureICAO: depAirport?.icao ?? entry.dep,
            arrivalIATA: entry.arr,
            arrivalICAO: arrAirport?.icao ?? entry.arr,
            distanceNM: distance,
            plannedCruiseAltitudeFt: entry.alt
        )
    }

    /// 获取所有支持的航班号列表
    public func getAvailableCallsigns() -> [String] {
        return Array(staticSchedules.keys).sorted()
    }
}
