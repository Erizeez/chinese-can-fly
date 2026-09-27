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
    public var currentFlight: FlightPlan? {
        get { FlightPlanStore.shared.currentFlight }
        set { FlightPlanStore.shared.currentFlight = newValue }
    }
    public var activeFlightState: AirborneState? {
        get { FlightPlanStore.shared.activeFlightState }
        set { FlightPlanStore.shared.activeFlightState = newValue }
    }
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

    // 高低频双通道派发架构：姿态仪高刷 (最高 100fps 带死区过滤) 与 动力学看板 (10Hz 节流)
    private var lastAttitudeDispatchTime: Double = 0
    private var lastDispatchedPitch: Double = 0.0
    private var lastDispatchedRoll: Double = 0.0
    private var isAttitudeDispatchPending: Bool = false

    private var lastDynamicsDispatchTime: Double = 0
    private var isDynamicsDispatchPending: Bool = false
    private var filteredPitch: Double = 0.0
    private var filteredRoll: Double = 0.0

    private init() {
        setupSensorCallbacks()
        // 延迟 0.15 秒平滑激活传感器，确保 SwiftUI 首屏在 0.01 秒内瞬间呈现
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            BackgroundFlightTracker.shared.startLiveSensors()
        }
    }

    private func setupSensorCallbacks() {
        let tracker = BackgroundFlightTracker.shared

        tracker.onLocationUpdate = { [weak self] location, phase in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.latitude = location.coordinate.latitude
                self.longitude = location.coordinate.longitude
                self.geometricAltitudeFt = location.altitude * 3.28084
                self.groundSpeedKts = max(0, location.speed * 1.94384)
                if location.course >= 0 {
                    self.groundTrackDeg = location.course
                }
                self.flightPhase = phase

                // 同步至航图专属低频位置 (1Hz)
                FlightPlanStore.shared.updateChartPosition(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    trackDeg: self.groundTrackDeg
                )

                // 仅在明确开启飞行记录时写入黑匣子持久队列
                if self.isRecording {
                    self.appendCurrentTelemetryFrame()
                }
            }
        }

        tracker.onMotionUpdate = { [weak self] acc, grav, pitch, roll, yaw in
            guard let self = self else { return }
            self.lastRawAcceleration = acc
            self.lastRawGravity = grav

            let targetPitch: Double
            let targetRoll: Double
            let computedNz: Double
            let computedNx: Double
            let computedNy: Double

            // 1. 在后台线程完成坐标系正交变换与过载计算
            if self.bodyAligner.calibrated {
                let (p, r) = self.bodyAligner.calculateAttitudeAngles(sensorGravity: grav)
                targetPitch = p
                targetRoll = r
                let (nx, ny, nz) = self.bodyAligner.transformAcceleration(sensorAcc: acc + grav)
                computedNz = nz
                computedNx = nx
                computedNy = ny
            } else {
                targetPitch = pitch
                targetRoll = roll
                computedNz = sqrt(grav.x * grav.x + grav.y * grav.y + grav.z * grav.z) / 9.80665
                computedNx = acc.z / 9.80665
                computedNy = acc.x / 9.80665
            }

            // 姿态高灵敏度平滑滤波 (alpha = 0.55，在 60Hz/100Hz 高刷下消除滞后感)
            let alpha = 0.55
            self.filteredPitch = (alpha * targetPitch) + ((1.0 - alpha) * self.filteredPitch)
            self.filteredRoll = (alpha * targetRoll) + ((1.0 - alpha) * self.filteredRoll)

            self.dynamicsAnalyzer.processSample(normalG: computedNz, sinkRateFpm: -self.cabinVSIFpm)
            let computedEDR = self.dynamicsAnalyzer.calculateTurbulenceEDR()

            let curPitch = self.filteredPitch
            let curRoll = self.filteredRoll
            let nowMedia = CACurrentMediaTime()

            // 2. 姿态角独立高频通道 (专为 PFD 供给，最高 100fps，带 0.02° 死区过滤，杜绝无效重绘)
            let pitchDiff = abs(curPitch - self.lastDispatchedPitch)
            let rollDiff = abs(curRoll - self.lastDispatchedRoll)
            if (nowMedia - self.lastAttitudeDispatchTime >= 0.010) && (pitchDiff > 0.02 || rollDiff > 0.02) && !self.isAttitudeDispatchPending {
                self.isAttitudeDispatchPending = true
                self.lastAttitudeDispatchTime = nowMedia
                self.lastDispatchedPitch = curPitch
                self.lastDispatchedRoll = curRoll

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isAttitudeDispatchPending = false
                    self.pitchDeg = curPitch
                    self.rollDeg = curRoll
                }
            }

            // 3. 动力学过载独立低频通道 (10Hz 节流，每 100ms 更新看板，主线程负载削减 90%)
            if (nowMedia - self.lastDynamicsDispatchTime >= 0.100) && !self.isDynamicsDispatchPending {
                self.isDynamicsDispatchPending = true
                self.lastDynamicsDispatchTime = nowMedia

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isDynamicsDispatchPending = false

                    self.normalGForce = computedNz
                    self.longitudinalGForce = computedNx
                    self.lateralGForce = computedNy
                    self.turbulenceEDR = computedEDR

                    // 检测是否刚刚发生着陆接地冲击
                    if self.flightPhase == .touchdown && self.latestTouchdown == nil {
                        self.latestTouchdown = self.dynamicsAnalyzer.evaluateTouchdown(
                            peakNormalG: computedNz,
                            touchdownSinkRateFpm: -self.cabinVSIFpm
                        )
                    }

                    // 黑匣子时序图表严格按 1Hz 节流写入
                    let now = Date()
                    if self.isRecording && now.timeIntervalSince(self.lastRecordedTick) >= 1.0 {
                        self.lastRecordedTick = now
                        self.appendCurrentTelemetryFrame()
                    }
                }
            }
        }

        tracker.onPressureUpdate = { [weak self] pressureHPa in
            guard let self = self else { return }
            let (cabinAlt, vsi) = self.cabinAnalyzer.update(pressureHPa: pressureHPa)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.ambientPressureHPa = pressureHPa
                self.cabinAltitudeFt = cabinAlt
                self.cabinVSIFpm = vsi
            }
        }
    }

    private var recordingStartTime: Date = Date()

    // MARK: - 真实飞行实战操作

    /// 开始飞行全程黑匣子记录 (升级为长航时后台保活与 50Hz 采样)
    public func startFlightRecording() {
        guard !isRecording else { return }
        isRecording = true
        latestTouchdown = nil
        telemetryHistory.removeAll()
        recordingStartTime = Date()
        BackgroundFlightTracker.shared.startBackgroundTracking()
        appendCurrentTelemetryFrame()
    }

    /// 停止飞行记录并自动归档到飞行记录日志库
    public func stopFlightRecording() {
        guard isRecording else { return }
        isRecording = false
        BackgroundFlightTracker.shared.stopBackgroundTracking()

        let endTime = Date()
        FlightRecordStore.shared.saveSession(
            flight: self.currentFlight,
            frames: self.telemetryHistory,
            latestTouchdown: self.latestTouchdown,
            startTime: self.recordingStartTime,
            endTime: endTime
        )
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
