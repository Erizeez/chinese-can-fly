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

    func testOfflineFlightDatabaseAndDataProvider() async throws {
        let provider = FlightDataProvider.shared
        let db = OfflineFlightDatabase.shared
        
        // 1. 验证智能航司推断 (无网络无离线包亦可用)
        XCTAssertEqual(OfflineFlightDatabase.detectAirline(callsign: "MU6594"), "中国东方航空")
        XCTAssertEqual(OfflineFlightDatabase.detectAirline(callsign: "CA1501"), "中国国际航空")
        XCTAssertEqual(OfflineFlightDatabase.detectAirline(callsign: "CZ3101"), "中国南方航空")

        // 2. 验证用户自定义录入航线 (无需下载离线包，优先即时命中)
        db.saveCustomFlight(
            callsign: "TEST999",
            airline: "测试虚拟航空",
            dep: "PEK",
            arr: "SHA",
            model: "C919",
            alt: 35000
        )
        let customLookup = provider.lookupOffline(callsign: "TEST999")
        if case let .success(flight, source, _) = customLookup {
            XCTAssertEqual(source, .userCustom)
            XCTAssertEqual(flight.callsign, "TEST999")
            XCTAssertEqual(flight.departureIATA, "PEK")
        } else {
            XCTFail("用户自定义录入航班应可离线直接命中")
        }

        // 3. 验证未安装离线包时，查询国内未收录航班返回 offlineNotInstalled 并提供航司推断
        // 先确保离线包未安装 (清除可能残留的包)
        try? OfflineResourceManager.shared.deletePackage(packageId: "db_flight_routes")
        db.reloadOfflineRoutesFromDisk()
        XCTAssertFalse(db.isOfflinePackageInstalled, "初始状态下离线航线包不应被强行安装")
        
        let beforeInstallLookup = provider.lookupOffline(callsign: "MU6594")
        if case let .offlineNotInstalled(callsign, suggested) = beforeInstallLookup {
            XCTAssertEqual(callsign, "MU6594")
            XCTAssertEqual(suggested, "中国东方航空")
        } else {
            XCTFail("未安装离线包时应当返回 offlineNotInstalled 提示")
        }

        // 4. 验证按需下载离线包并成功检索 MU6594
        try await provider.installRoutesPackage()
        XCTAssertTrue(db.isOfflinePackageInstalled, "安装离线包后应当标记为已安装")
        
        let afterInstallLookup = provider.lookupOffline(callsign: "MU6594")
        if case let .success(flight, source, _) = afterInstallLookup {
            XCTAssertEqual(source, .offlinePackage)
            XCTAssertEqual(flight.airline, "中国东方航空")
            XCTAssertEqual(flight.departureIATA, "SQJ")
            XCTAssertEqual(flight.arrivalIATA, "SHA")
            XCTAssertEqual(flight.aircraftModel, "Boeing 737-800")
            XCTAssertGreaterThan(flight.distanceNM, 200)
        } else {
            XCTFail("安装离线包后应当能够直接检索到 MU6594 航班")
        }

        // 5. 验证已安装离线包但查询不存在的未知航班号时，返回 notFoundInOffline
        let notFoundLookup = provider.lookupOffline(callsign: "HU999999")
        if case let .notFoundInOffline(callsign, suggested) = notFoundLookup {
            XCTAssertEqual(callsign, "HU999999")
            XCTAssertEqual(suggested, "海南航空")
        } else {
            XCTFail("离线库中未收录的航班应返回 notFoundInOffline")
        }
    }

    func testUnitSystemConversionAndNotification() {
        let unitMgr = UnitManager.shared

        // 1. 验证民航标准制输出
        unitMgr.currentSystem = .aviation
        let altAviation = unitMgr.altitude(feet: 35000)
        XCTAssertEqual(altAviation.value, "35000")
        XCTAssertEqual(altAviation.unit, "FT")

        let spdAviation = unitMgr.speed(knots: 480)
        XCTAssertEqual(spdAviation.value, "480")
        XCTAssertEqual(spdAviation.unit, "KTS")

        let vsAviation = unitMgr.verticalSpeed(fpm: -120)
        XCTAssertEqual(vsAviation.value, "-120")
        XCTAssertEqual(vsAviation.unit, "FPM")

        let distAviation = unitMgr.distance(nm: 358)
        XCTAssertEqual(distAviation.value, "358")
        XCTAssertEqual(distAviation.unit, "NM")

        let rwyAviation = unitMgr.runwayDimension(lengthFt: 8000, widthFt: 150)
        XCTAssertEqual(rwyAviation, "8000×150 FT")

        // 2. 验证切换到国际公制 (响应式生效)
        unitMgr.currentSystem = .metric
        let altMetric = unitMgr.altitude(feet: 35000) // 35000 * 0.3048 = 10668m
        XCTAssertEqual(altMetric.value, "10668")
        XCTAssertEqual(altMetric.unit, "m")

        let spdMetric = unitMgr.speed(knots: 480) // 480 * 1.852 = 888.96 -> 889 km/h
        XCTAssertEqual(spdMetric.value, "889")
        XCTAssertEqual(spdMetric.unit, "km/h")

        let vsMetric = unitMgr.verticalSpeed(fpm: -120) // -120 * 0.00508 = -0.6096 m/s
        XCTAssertEqual(vsMetric.value, "-0.6")
        XCTAssertEqual(vsMetric.unit, "m/s")

        let distMetric = unitMgr.distance(nm: 358) // 358 * 1.852 = 663.016 -> 663 km
        XCTAssertEqual(distMetric.value, "663")
        XCTAssertEqual(distMetric.unit, "km")

        let rwyMetric = unitMgr.runwayDimension(lengthFt: 8000, widthFt: 150) // 8000*0.3048=2438, 150*0.3048=46
        XCTAssertEqual(rwyMetric, "2438×46 m")

        // 3. 复原为民航标准制
        unitMgr.currentSystem = .aviation
    }
}



