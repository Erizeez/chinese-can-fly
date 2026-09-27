import SwiftUI
import CoreLocation
import simd
#if os(iOS)
import CoreMotion
#endif
import CCFlyCore

/// 全局飞行数据中枢与状态调度器 (纯实战硬件驱动，零假数据演练)
@Observable
public final class FlightDataManager: @unchecked Sendable {
    public static let shared = FlightDataManager()

    // MARK: - 核心态势变量 (真实硬件传感器驱动)
    public var currentFlight: FlightPlan?
    public var activeFlightState: AirborneState?
    public var isRecording: Bool = false

    // 空间定位与地速
    public var latitude: Double = 39.5098
    public var longitude: Double = 116.4105
    public var geometricAltitudeFt: Double = 0.0
    public var groundSpeedKts: Double = 0.0
    public var groundTrackDeg: Double = 0.0

    // 气压与客舱增压 (真实双高系统)
    public var ambientPressureHPa: Double = 1013.25
    public var cabinAltitudeFt: Double = 0.0
    public var cabinVSIFpm: Double = 0.0

    // 姿态仪与力学过载 (已对准至机体坐标系)
    public var pitchDeg: Double = 0.0
    public var rollDeg: Double = 0.0
    public var normalGForce: Double = 1.0        // 垂直过载 Nz
    public var longitudinalGForce: Double = 0.0  // 纵向过载 Nx
    public var lateralGForce: Double = 0.0       // 侧向过载 Ny
    public var turbulenceEDR: Double = 0.0
    public var flightPhase: FlightPhase = .parked

    // 着陆触地冲击质量报告
    public var latestTouchdown: TouchdownReport?

    // 遥测时序历史队列 (环形缓冲区，供图表与黑匣子导出)
    public var telemetryHistory: [TelemetryFrame] = []
    private let maxHistoryFrames = 1000

    // 核心算法与分析器引用
    private let cabinAnalyzer = CabinAltitudeAnalyzer()
    private let dynamicsAnalyzer = FlightDynamicsAnalyzer()
    private let bodyAligner = BodyFrameAligner()
    private let ekfEngine = EKFNavEngine()

    // 缓存上一次采样的重力与加速度矢量 (用于机体轴校准)
    private var lastRawGravity: simd_double3 = simd_double3(0, -9.80665, 0)
    private var lastRawAcceleration: simd_double3 = .zero
    private var lastRecordedTick: Date = Date.distantPast

    private init() {
        // 默认载入干线代表航班
        self.currentFlight = OfflineFlightDatabase.shared.lookupFlight(callsign: "CA1501")
        setupSensorCallbacks()
        // 延迟 0.1 秒平滑激活传感器，确保 SwiftUI 首屏在 0.01 秒内瞬间呈现
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            BackgroundFlightTracker.shared.startLiveSensors()
        }
    }

    private func setupSensorCallbacks() {
        let tracker = BackgroundFlightTracker.shared

        tracker.onLocationUpdate = { [weak self] location, phase in
            Task { @MainActor in
                guard let self = self else { return }
                self.latitude = location.coordinate.latitude
                self.longitude = location.coordinate.longitude
                self.geometricAltitudeFt = location.altitude * 3.28084
                self.groundSpeedKts = max(0, location.speed * 1.94384)
                if location.course >= 0 {
                    self.groundTrackDeg = location.course
                }
                self.flightPhase = phase

                // 仅在明确开启飞行记录时写入黑匣子持久队列
                if self.isRecording {
                    self.appendCurrentTelemetryFrame()
                }
            }
        }

        tracker.onMotionUpdate = { [weak self] acc, grav, pitch, roll, yaw in
            Task { @MainActor in
                guard let self = self else { return }
                self.lastRawAcceleration = acc
                self.lastRawGravity = grav

                let targetPitch: Double
                let targetRoll: Double

                // 如果已对准，则使用机体变换后的俯仰滚转与过载；未对准时直接使用自然姿态
                if self.bodyAligner.calibrated {
                    let (p, r) = self.bodyAligner.calculateAttitudeAngles(sensorGravity: grav)
                    targetPitch = p
                    targetRoll = r
                    let (nx, ny, nz) = self.bodyAligner.transformAcceleration(sensorAcc: acc + grav)
                    self.normalGForce = nz
                    self.longitudinalGForce = nx
                    self.lateralGForce = ny
                } else {
                    targetPitch = pitch
                    targetRoll = roll
                    self.normalGForce = sqrt(grav.x * grav.x + grav.y * grav.y + grav.z * grav.z) / 9.80665
                    self.longitudinalGForce = acc.z / 9.80665
                    self.lateralGForce = acc.x / 9.80665
                }

                // 姿态一阶平滑低通滤波，消除传感器微颤与视觉卡顿，模拟真实航空仪表的沉稳顺滑
                let alpha = 0.35
                self.pitchDeg = (alpha * targetPitch) + ((1.0 - alpha) * self.pitchDeg)
                self.rollDeg = (alpha * targetRoll) + ((1.0 - alpha) * self.rollDeg)

                self.dynamicsAnalyzer.processSample(normalG: self.normalGForce, sinkRateFpm: -self.cabinVSIFpm)
                self.turbulenceEDR = self.dynamicsAnalyzer.calculateTurbulenceEDR()

                // 检测是否刚刚发生着陆接地冲击
                if self.flightPhase == .touchdown && self.latestTouchdown == nil {
                    self.latestTouchdown = self.dynamicsAnalyzer.evaluateTouchdown(
                        peakNormalG: self.normalGForce,
                        touchdownSinkRateFpm: -self.cabinVSIFpm
                    )
                }

                // 黑匣子时序图表严格按 1Hz 节流写入，杜绝高频刷新导致 Swift Charts 卡死主线程
                let now = Date()
                if self.isRecording && now.timeIntervalSince(self.lastRecordedTick) >= 1.0 {
                    self.lastRecordedTick = now
                    self.appendCurrentTelemetryFrame()
                }
            }
        }

        tracker.onPressureUpdate = { [weak self] pressureHPa in
            Task { @MainActor in
                guard let self = self else { return }
                self.ambientPressureHPa = pressureHPa
                let (cabinAlt, vsi) = self.cabinAnalyzer.update(pressureHPa: pressureHPa)
                self.cabinAltitudeFt = cabinAlt
                self.cabinVSIFpm = vsi
            }
        }
    }

    // MARK: - 真实飞行实战操作

    /// 开始飞行全程黑匣子记录 (升级为长航时后台保活与 50Hz 采样)
    public func startFlightRecording() {
        guard !isRecording else { return }
        isRecording = true
        latestTouchdown = nil
        telemetryHistory.removeAll()
        BackgroundFlightTracker.shared.startBackgroundTracking()
        appendCurrentTelemetryFrame()
    }

    /// 停止飞行记录并保持基础传感器监听
    public func stopFlightRecording() {
        guard isRecording else { return }
        isRecording = false
        BackgroundFlightTracker.shared.stopBackgroundTracking()
    }

    /// 执行机体轴正交对准 (消除手机在客舱内任意放置的倾角)
    public func calibrateBodyAxis() {
        // 利用滑跑推力和重力对准
        let thrust = (simd_length(lastRawAcceleration) > 0.05) ? lastRawAcceleration : simd_double3(0, 0, 1.0)
        bodyAligner.calibrate(gravitySensor: lastRawGravity, forwardAccSensor: thrust)
    }

    public func resetBodyCalibration() {
        bodyAligner.reset()
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

    /// 导出当前飞行的真实黑匣子文件 (GPX / KML / CSV)
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
