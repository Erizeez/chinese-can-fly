import Foundation

/// 国际标准大气 (ICAO ISA Standard Atmosphere) 物理计算模型
public enum ISAAtmosphere {
    // 物理常数
    public static let standardPressureHPa: Double = 1013.25       // 海平面标淮气压 P0
    public static let standardTemperatureK: Double = 288.15      // 海平面标准温度 T0 (15°C)
    public static let lapseRateKPerM: Double = 0.0065            // 对流层垂直温度递减率 L
    public static let gasConstantAir: Double = 287.05287         // 干空气气体常数 R
    public static let gravity: Double = 9.80665                  // 重力加速度 g0
    public static let feetPerMeter: Double = 3.28084
    public static let metersPerFoot: Double = 0.3048

    /// 根据气压计算标准气压高度 (米)
    public static func altitudeFromPressure(hPa: Double) -> Double {
        guard hPa > 0 else { return 0 }
        let exponent = (gasConstantAir * lapseRateKPerM) / gravity
        let ratio = hPa / standardPressureHPa
        let altitudeMeters = (standardTemperatureK / lapseRateKPerM) * (1.0 - pow(ratio, exponent))
        return altitudeMeters
    }

    /// 根据气压计算标准气压高度 (英尺)
    public static func altitudeFtFromPressure(hPa: Double) -> Double {
        return altitudeFromPressure(hPa: hPa) * feetPerMeter
    }

    /// 根据高度反算标准大气压 (hPa)
    public static func pressureFromAltitude(meters: Double) -> Double {
        let base = 1.0 - (lapseRateKPerM * meters) / standardTemperatureK
        guard base > 0 else { return 0 }
        let exponent = gravity / (gasConstantAir * lapseRateKPerM)
        return standardPressureHPa * pow(base, exponent)
    }
}
