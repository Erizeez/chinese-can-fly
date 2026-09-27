import Foundation
import Observation

/// 航空度量衡系统体系枚举
public enum AviationUnitSystem: String, CaseIterable, Identifiable, Codable, Sendable {
    case aviation = "aviation" // 民航标准制 (英尺 FT, 节 KTS, 海里 NM, 英尺/分 FPM)
    case metric = "metric"     // 国际公制 (米 m, 公里/时 km/h, 公里 km, 米/秒 m/s)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aviation:
            return "民航标准制 (FT, KTS, NM, FPM)"
        case .metric:
            return "国际公制 (米 m, 公里/时 km/h, 公里 km)"
        }
    }
}

/// 全局航空度量衡管理与格式化引擎 (支持全应用即时响应式切换与高精度物理转换)
@Observable
public final class UnitManager: @unchecked Sendable {
    public static let shared = UnitManager()

    public static let unitChangedNotification = Notification.Name("CCFlyUnitSystemChanged")

    public var currentSystem: AviationUnitSystem {
        didSet {
            UserDefaults.standard.set(currentSystem.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: Self.unitChangedNotification, object: currentSystem)
        }
    }

    private let storageKey = "CCFly_UnitSystem_Setting_v1"

    private init() {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let system = AviationUnitSystem(rawValue: stored) {
            self.currentSystem = system
        } else {
            self.currentSystem = .aviation
        }
    }

    // MARK: - 1. 高度格式化 (基于英尺基准输入)

    /// 格式化高度 (输入为基准英尺 feet)
    public func altitude(feet: Double) -> (value: String, unit: String, full: String, converted: Double) {
        switch currentSystem {
        case .aviation:
            let val = "\(Int(round(feet)))"
            return (val, "FT", "\(val) FT", feet)
        case .metric:
            let meters = feet * 0.3048
            let val = "\(Int(round(meters)))"
            return (val, "m", "\(val) m", meters)
        }
    }

    /// 格式化高度 (输入为基准米 meters)
    public func altitude(meters: Double) -> (value: String, unit: String, full: String, converted: Double) {
        let feet = meters * 3.28084
        return altitude(feet: feet)
    }

    // MARK: - 2. 速度格式化 (基于节 KTS 基准输入)

    /// 格式化速度 (输入为节 KTS)
    public func speed(knots: Double) -> (value: String, unit: String, full: String, converted: Double) {
        switch currentSystem {
        case .aviation:
            let val = "\(Int(round(knots)))"
            return (val, "KTS", "\(val) KTS", knots)
        case .metric:
            let kmh = knots * 1.852
            let val = "\(Int(round(kmh)))"
            return (val, "km/h", "\(val) km/h", kmh)
        }
    }

    // MARK: - 3. 升降率 / 垂直速度格式化 (基于 FPM 英尺/分钟 基准输入)

    /// 格式化垂直升降速度 (输入为 FPM)
    public func verticalSpeed(fpm: Double) -> (value: String, unit: String, full: String, converted: Double) {
        switch currentSystem {
        case .aviation:
            let val = String(format: "%+.0f", fpm)
            return (val, "FPM", "\(val) FPM", fpm)
        case .metric:
            let ms = fpm * 0.00508
            let val = String(format: "%+.1f", ms)
            return (val, "m/s", "\(val) m/s", ms)
        }
    }

    // MARK: - 4. 水平距离 / 航程格式化 (基于海里 NM 基准输入)

    /// 格式化距离 (输入为海里 NM)
    public func distance(nm: Double) -> (value: String, unit: String, full: String, converted: Double) {
        switch currentSystem {
        case .aviation:
            let val = "\(Int(round(nm)))"
            return (val, "NM", "\(val) NM", nm)
        case .metric:
            let km = nm * 1.852
            let val = "\(Int(round(km)))"
            return (val, "km", "\(val) km", km)
        }
    }

    // MARK: - 5. 机场标高格式化 (基于英尺基准输入)

    /// 格式化机场标高 (输入为英尺 elevationFt)
    public func elevation(feet: Double?) -> String {
        guard let ft = feet else { return "标高未知" }
        switch currentSystem {
        case .aviation:
            return "标高 \(Int(round(ft))) FT"
        case .metric:
            let m = ft * 0.3048
            return "标高 \(Int(round(m))) m"
        }
    }

    // MARK: - 6. 跑道尺寸格式化 (基于英尺长宽输入)

    /// 格式化跑道尺寸 (输入为长宽英尺)
    public func runwayDimension(lengthFt: Double?, widthFt: Double?) -> String {
        guard let l = lengthFt, l > 0 else { return "尺寸未知" }
        switch currentSystem {
        case .aviation:
            if let w = widthFt, w > 0 {
                return "\(Int(round(l)))×\(Int(round(w))) FT"
            }
            return "\(Int(round(l))) FT"
        case .metric:
            let lm = l * 0.3048
            if let w = widthFt, w > 0 {
                let wm = w * 0.3048
                return "\(Int(round(lm)))×\(Int(round(wm))) m"
            }
            return "\(Int(round(lm))) m"
        }
    }

    // MARK: - 7. 巡航高度层格式化 (如 FL350 与 米制高度)

    /// 格式化巡航高度层 (输入为计划巡航高度英尺)
    public func flightLevel(feet: Double) -> String {
        let fl = Int(round(feet / 100))
        switch currentSystem {
        case .aviation:
            return "FL\(fl)"
        case .metric:
            let m = Int(round(feet * 0.3048))
            return "\(m)m (FL\(fl))"
        }
    }
}
