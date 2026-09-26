import XCTest
import simd
@testable import CCFlyCore

final class CCFlyCoreTests: XCTestCase {
    
    func testISAStandardAtmosphere() {
        // 海平面标准气压 1013.25 hPa 高度应约为 0
        let seaLevelAlt = ISAAtmosphere.altitudeFromPressure(hPa: 1013.25)
        XCTAssertEqual(seaLevelAlt, 0.0, accuracy: 1.0)
        
        // 巡航常见客舱气压 750 hPa，对应客舱高度约在 7500~8000 ft 之间
        let cabinAltFt = ISAAtmosphere.altitudeFtFromPressure(hPa: 752.6)
        XCTAssertGreaterThan(cabinAltFt, 7500.0)
        XCTAssertLessThan(cabinAltFt, 8500.0)
    }

    func testBodyFrameAlignment() {
        let aligner = BodyFrameAligner()
        XCTAssertFalse(aligner.calibrated)
        
        // 假设手机垂直插在前方座椅网兜（重力沿手机Y轴负方向，机身前向沿手机Z轴）
        let gravitySensor = simd_double3(0, -9.80665, 0)
        let forwardAccSensor = simd_double3(0, 0, 2.5) // 起飞推力
        
        aligner.calibrate(gravitySensor: gravitySensor, forwardAccSensor: forwardAccSensor)
        XCTAssertTrue(aligner.calibrated)
        
        // 测试将重力输入转换，飞机机体垂直过载 Nz 应约为 1.0g
        let (_, _, nz) = aligner.transformAcceleration(sensorAcc: gravitySensor)
        XCTAssertEqual(nz, 1.0, accuracy: 0.05)
    }

    func testFlightDynamicsAnalyzer() {
        let analyzer = FlightDynamicsAnalyzer()
        
        // 测试轻柔着陆 (Butter Landing)
        let smoothReport = analyzer.evaluateTouchdown(peakNormalG: 1.18, touchdownSinkRateFpm: -120)
        XCTAssertTrue(smoothReport.rating.contains("Butter"))
        
        // 测试重着陆警示
        let hardReport = analyzer.evaluateTouchdown(peakNormalG: 1.95, touchdownSinkRateFpm: -500)
        XCTAssertTrue(hardReport.rating.contains("重着陆"))
    }
}
