import Foundation

/// 统一航空遥测数据帧（传感器融合后的黑匣子单点快照）
public struct TelemetryFrame: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    
    // GNSS 几何定位参数
    public let latitude: Double
    public let longitude: Double
    public let geometricAltitudeMeters: Double   // GPS 几何高度 (米)
    public let geometricAltitudeFt: Double       // GPS 几何高度 (英尺)
    public let groundSpeedKts: Double            // 地速 (节)
    public let groundTrackDeg: Double            // 真航迹角 (0-360°)
    public let horizontalAccuracy: Double        // GPS 水平精度 (米)
    public let verticalAccuracy: Double          // GPS 垂直精度 (米)
    
    // 气压与客舱增压参数
    public let ambientPressureHPa: Double        // 客舱实测气压 (hPa)
    public let cabinAltitudeFt: Double           // 等效客舱海拔高度 (英尺)
    public let cabinVerticalSpeedFpm: Double     // 客舱升降率 (英尺/分钟)
    
    // 惯导与机体姿态参数 (已旋转对准至飞机机体坐标系)
    public let pitchDeg: Double                  // 俯仰角 (°，抬头为正)
    public let rollDeg: Double                   // 滚转角 (°，右倾为正)
    public let yawDeg: Double                    // 航向偏航角 (°)
    public let normalGForce: Double              // 垂直过载 Nz (g，平飞恒定为 1.0g)
    public let longitudinalGForce: Double        // 纵向过载 Nx (g，推力加速为正)
    public let lateralGForce: Double             // 侧向过载 Ny (g)
    
    // 飞行力学品质衍生
    public let turbulenceEDR: Double             // 湍流耗散率 EDR 指数 (0.0~1.0)
    public let flightPhase: FlightPhase          // 当前飞行阶段推断

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double,
        longitude: Double,
        geometricAltitudeMeters: Double,
        groundSpeedKts: Double,
        groundTrackDeg: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        ambientPressureHPa: Double,
        cabinAltitudeFt: Double,
        cabinVerticalSpeedFpm: Double,
        pitchDeg: Double,
        rollDeg: Double,
        yawDeg: Double,
        normalGForce: Double,
        longitudinalGForce: Double,
        lateralGForce: Double,
        turbulenceEDR: Double = 0.0,
        flightPhase: FlightPhase = .cruise
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.geometricAltitudeMeters = geometricAltitudeMeters
        self.geometricAltitudeFt = geometricAltitudeMeters * 3.28084
        self.groundSpeedKts = groundSpeedKts
        self.groundTrackDeg = groundTrackDeg
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.ambientPressureHPa = ambientPressureHPa
        self.cabinAltitudeFt = cabinAltitudeFt
        self.cabinVerticalSpeedFpm = cabinVerticalSpeedFpm
        self.pitchDeg = pitchDeg
        self.rollDeg = rollDeg
        self.yawDeg = yawDeg
        self.normalGForce = normalGForce
        self.longitudinalGForce = longitudinalGForce
        self.lateralGForce = lateralGForce
        self.turbulenceEDR = turbulenceEDR
        self.flightPhase = flightPhase
    }
}

/// 飞行工况阶段枚举
public enum FlightPhase: String, Codable, Sendable {
    case parked       // 停机坪静止
    case taxi         // 滑行
    case takeoffRoll  // 起飞滑跑
    case initialClimb // 离地爬升
    case cruise       // 巡航平飞
    case descent      // 下降
    case approach     // 进近五边截获
    case touchdown    // 接地冲击瞬间
    case landingRoll  // 着陆滑跑减速
}
