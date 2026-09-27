import SwiftUI
import CoreLocation
#if os(iOS)
import CoreMotion
#endif
import CCFlyCore

/// 全局飞行数据中枢与状态调度器
@Observable
public final class FlightDataManager: @unchecked Sendable {
    public static let shared = FlightDataManager()

    // MARK: - 核心态势变量 (全面驱动 UI)
    public var currentFlight: FlightPlan?
    public var activeFlightState: AirborneState?
    public var isRecording: Bool = false
    public var isSimulationRunning: Bool = false

    // 空间定位与地速
    public var latitude: Double = 39.5098        // 默认北京大兴 (PKX)
    public var longitude: Double = 116.4105
    public var geometricAltitudeFt: Double = 116.0
    public var groundSpeedKts: Double = 0.0
    public var groundTrackDeg: Double = 18.0

    // 气压与客舱增压 (双高系统)
    public var ambientPressureHPa: Double = 1013.25
    public var cabinAltitudeFt: Double = 116.0
    public var cabinVSIFpm: Double = 0.0

    // 姿态仪与力学过载 (机体坐标系)
    public var pitchDeg: Double = 0.0
    public var rollDeg: Double = 0.0
    public var normalGForce: Double = 1.0        // 垂直过载 Nz
    public var longitudinalGForce: Double = 0.0  // 纵向过载 Nx
    public var lateralGForce: Double = 0.0       // 侧向过载 Ny
    public var turbulenceEDR: Double = 0.02
    public var flightPhase: FlightPhase = .parked

    // 触地着陆报告
    public var latestTouchdown: TouchdownReport?

    // 遥测时序历史队列 (环形缓冲区，供图表与黑匣子导出)
    public var telemetryHistory: [TelemetryFrame] = []
    private let maxHistoryFrames = 500

    // 核心算法与分析器引用
    private let cabinAnalyzer = CabinAltitudeAnalyzer()
    private let dynamicsAnalyzer = FlightDynamicsAnalyzer()
    private let bodyAligner = BodyFrameAligner()
    private let ekfEngine = EKFNavEngine()

    // 仿真定时器
    private var simTimer: Timer?
    private var simStep: Double = 0.0

    private init() {
        // 默认加载国内经典干线 CA1501 航线
        self.currentFlight = OfflineFlightDatabase.shared.lookupFlight(callsign: "CA1501")
        // 初始填充若干点
        appendCurrentTelemetryFrame()
    }

    // MARK: - 真实传感器硬件接入与启停

    public func startLiveBlackbox() {
        guard !isRecording else { return }
        isRecording = true
        BackgroundFlightTracker.shared.startTracking()
    }

    public func stopLiveBlackbox() {
        guard isRecording else { return }
        isRecording = false
        BackgroundFlightTracker.shared.stopTracking()
        if isSimulationRunning {
            stopFlightSimulation()
        }
    }

    // MARK: - 高保真航空物理力学仿真引擎 (供非机舱 / 模拟器环境测试)

    /// 启动从北京大兴 (PKX) 至 广州白云 (CAN) 的真实航空飞行力学仿真
    public func startFlightSimulation() {
        stopFlightSimulation()
        isSimulationRunning = true
        isRecording = true
        simStep = 0.0
        telemetryHistory.removeAll()

        // 设定初始起点：大兴 01L 跑道头
        latitude = 39.4950
        longitude = 116.4100
        geometricAltitudeFt = 116.0
        cabinAltitudeFt = 116.0
        ambientPressureHPa = 1008.0
        groundSpeedKts = 0.0
        groundTrackDeg = 10.0
        flightPhase = .parked

        simTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.advanceSimulationTick()
        }
    }

    public func stopFlightSimulation() {
        simTimer?.invalidate()
        simTimer = nil
        isSimulationRunning = false
    }

    private func advanceSimulationTick() {
        simStep += 0.5
        let t = simStep

        // 真实多阶段飞行剖面演进
        if t < 10.0 {
            // 阶段 1: 停机坪与滑行
            flightPhase = .taxi
            groundSpeedKts = min(25.0, t * 2.5)
            longitudinalGForce = 0.05
            normalGForce = 1.0 + Double.random(in: -0.02...0.02)
            pitchDeg = 0.5
            rollDeg = 0.0
        } else if t < 25.0 {
            // 阶段 2: 起飞滑跑 (Takeoff Roll) - 强力推背感
            flightPhase = .takeoffRoll
            let rollProgress = (t - 10.0) / 15.0
            groundSpeedKts = 25.0 + rollProgress * 135.0 // 加速至 160 节
            longitudinalGForce = 0.32 + Double.random(in: -0.03...0.03) // 0.32G 纵向推力
            normalGForce = 1.02 + Double.random(in: -0.04...0.04)
            pitchDeg = 1.0
        } else if t < 35.0 {
            // 阶段 3: 抬轮离地 (Rotation) - 抬头拉杆过载
            flightPhase = .initialClimb
            groundSpeedKts = 160.0 + (t - 25.0) * 5.0
            longitudinalGForce = 0.15
            normalGForce = 1.22 + Double.random(in: -0.02...0.03) // 1.22G 拉起垂直过载！
            pitchDeg = min(15.0, 1.0 + (t - 25.0) * 1.4) // 抬头角拉升至 15 度
            geometricAltitudeFt += 180.0 // 剧烈爬升
            cabinAltitudeFt += 20.0
            cabinVSIFpm = 450.0
            ambientPressureHPa = ISAAtmosphere.pressureFromAltitude(meters: geometricAltitudeFt * 0.3048)
        } else if t < 70.0 {
            // 阶段 4: 爬升与客舱阶梯增压
            flightPhase = .cruise
            groundSpeedKts = min(480.0, 210.0 + (t - 35.0) * 8.0)
            geometricAltitudeFt = min(35000.0, geometricAltitudeFt + 600.0)
            // 客舱增压规律: 飞机爬升至 35000ft，客舱平缓加压升至 6800ft
            cabinAltitudeFt = min(6800.0, cabinAltitudeFt + 100.0)
            ambientPressureHPa = ISAAtmosphere.pressureFromAltitude(meters: cabinAltitudeFt * 0.3048)
            cabinVSIFpm = 380.0
            pitchDeg = 3.5
            rollDeg = sin(t * 0.2) * 3.0
            normalGForce = 1.0 + Double.random(in: -0.05...0.05)
            longitudinalGForce = 0.02
        } else if t < 100.0 {
            // 阶段 5: 高空巡航与晴空颠簸
            flightPhase = .cruise
            geometricAltitudeFt = 35000.0 + sin(t * 0.1) * 30.0
            cabinAltitudeFt = 6800.0 // 恒定客舱气压
            cabinVSIFpm = 0.0
            groundSpeedKts = 475.0 + Double.random(in: -5...5)
            // 模拟遭遇轻度湍流 EDR
            let bump = sin(t * 1.5) * 0.14
            normalGForce = 1.0 + bump
            turbulenceEDR = 0.18 // 轻度颠簸
            pitchDeg = 2.0
            rollDeg = cos(t * 0.15) * 4.0
        } else if t < 130.0 {
            // 阶段 6: 进近下滑 (Approach)
            flightPhase = .approach
            geometricAltitudeFt = max(200.0, geometricAltitudeFt - 1100.0)
            cabinAltitudeFt = max(200.0, cabinAltitudeFt - 220.0)
            cabinVSIFpm = -750.0
            groundSpeedKts = max(140.0, groundSpeedKts - 10.0)
            pitchDeg = 1.5
            rollDeg = sin(t * 0.5) * 2.0
            normalGForce = 1.02
            turbulenceEDR = 0.05
        } else if t < 135.0 {
            // 阶段 7: 接地触地冲击瞬间 (Touchdown!)
            flightPhase = .touchdown
            geometricAltitudeFt = 50.0
            groundSpeedKts = 135.0
            pitchDeg = 4.0 // 仰头拉平接地
            normalGForce = 1.28 // 1.28G 黄油接地！
            longitudinalGForce = -0.35 // 反推与主轮刹车减速

            if latestTouchdown == nil {
                latestTouchdown = dynamicsAnalyzer.evaluateTouchdown(peakNormalG: 1.28, touchdownSinkRateFpm: -140.0)
            }
        } else {
            // 阶段 8: 脱离跑道滑行至停机位
            flightPhase = .landingRoll
            groundSpeedKts = max(0.0, groundSpeedKts - 8.0)
            longitudinalGForce = -0.15
            normalGForce = 1.0
            pitchDeg = 0.0
            rollDeg = 0.0
            if groundSpeedKts <= 0.0 {
                flightPhase = .parked
                stopFlightSimulation()
            }
        }

        // 经纬度航向递进
        let rad = groundTrackDeg * .pi / 180.0
        let distStep = (groundSpeedKts * 0.5 / 3600.0) / 60.0 // 经纬度微小推进
        latitude += cos(rad) * distStep
        longitude += sin(rad) * distStep

        appendCurrentTelemetryFrame()
    }

    private func appendCurrentTelemetryFrame() {
        let frame = TelemetryFrame(
            latitude: latitude,
            longitude: longitude,
            geometricAltitudeMeters: geometricAltitudeFt * 0.3048,
            groundSpeedKts: groundSpeedKts,
            groundTrackDeg: groundTrackDeg,
            horizontalAccuracy: 3.0,
            verticalAccuracy: 5.0,
            ambientPressureHPa: ambientPressureHPa,
            cabinAltitudeFt: cabinAltitudeFt,
            cabinVerticalSpeedFpm: cabinVSIFpm,
            pitchDeg: pitchDeg,
            rollDeg: rollDeg,
            yawDeg: groundTrackDeg,
            normalGForce: normalGForce,
            longitudinalGForce: longitudinalGForce,
            lateralGForce: lateralGForce,
            turbulenceEDR: turbulenceEDR,
            flightPhase: flightPhase
        )

        telemetryHistory.append(frame)
        if telemetryHistory.count > maxHistoryFrames {
            telemetryHistory.removeFirst()
        }
    }

    /// 导出当前记录的黑匣子为 GPX / KML / CSV
    public func exportCurrentFlight(format: String) -> URL? {
        let callsign = currentFlight?.callsign ?? "CCFly"
        switch format.lowercased() {
        case "gpx":
            return FlightLogExporter.exportGPX(frames: telemetryHistory, flightCallsign: callsign)
        case "kml":
            return FlightLogExporter.exportKML(frames: telemetryHistory, flightCallsign: callsign)
        case "csv":
            return FlightLogExporter.exportCSV(frames: telemetryHistory, flightCallsign: callsign)
        default:
            return nil
        }
    }
}
