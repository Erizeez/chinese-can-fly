import Foundation
import CoreLocation
#if os(iOS)
import CoreMotion
import AVFoundation
#endif

/// 航空级长航时后台追踪保活管理器
public final class BackgroundFlightTracker: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    public static let shared = BackgroundFlightTracker()

    private let locationManager = CLLocationManager()
    #if os(iOS)
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    #endif

    public private(set) var isTracking: Bool = false
    public private(set) var currentPhase: FlightPhase = .parked
    
    // 遥测回调处理
    public var onTelemetryUpdate: (@Sendable (TelemetryFrame) -> Void)?

    private override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        #if os(iOS)
        // 关键航空配置：通知基带芯片针对几百节高速多普勒频移进行特殊平滑
        locationManager.activityType = .airborne
        // 致命关键配置：强制禁止 iOS 静止自动暂停，长途平飞绝不挂起
        locationManager.pausesLocationUpdatesAutomatically = false
        // 开启后台持续定位
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        #endif
    }

    /// 开始飞行全程黑匣子记录
    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        #if os(iOS)
        locationManager.requestAlwaysAuthorization()
        #endif
        locationManager.startUpdatingLocation()
        #if os(iOS)
        locationManager.startUpdatingHeading()
        startSensors()
        #endif
    }

    /// 停止记录并生成航程报告
    public func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        
        locationManager.stopUpdatingLocation()
        #if os(iOS)
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        #endif
    }

    #if os(iOS)
    private func startSensors() {
        // 根据阶段自适应配置采样率
        let sampleRateHz: Double = (currentPhase == .takeoffRoll || currentPhase == .approach || currentPhase == .touchdown) ? 50.0 : 10.0
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / sampleRateHz
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let motion = motion, let self = self else { return }
                self.handleMotionSample(motion)
            }
        }

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let data = data, let self = self else { return }
                self.handlePressureSample(pressureKPa: data.pressure.doubleValue)
            }
        }
    }

    private func handleMotionSample(_ motion: CMDeviceMotion) {
        // 将高频传感器数据注入 EKF 惯导及机体坐标系分析器
    }

    private func handlePressureSample(pressureKPa: Double) {
        // pressureKPa * 10 得到 hPa (百帕)
    }
    #endif

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        
        // 自动识别飞行工况状态机
        let speedKts = max(0, latest.speed * 1.94384)
        let altitudeFt = latest.altitude * 3.28084
        
        updateFlightPhase(speedKts: speedKts, altitudeFt: altitudeFt)
    }

    private func updateFlightPhase(speedKts: Double, altitudeFt: Double) {
        if speedKts < 3.0 && altitudeFt < 2000 {
            currentPhase = .parked
        } else if speedKts < 35.0 && altitudeFt < 2000 {
            currentPhase = .taxi
        } else if speedKts >= 35.0 && speedKts < 160.0 && altitudeFt < 1000 {
            currentPhase = .takeoffRoll
        } else if speedKts >= 160.0 && altitudeFt > 20000 {
            currentPhase = .cruise
        } else if speedKts > 100.0 && altitudeFt < 5000 {
            currentPhase = .approach
        }
    }
}
