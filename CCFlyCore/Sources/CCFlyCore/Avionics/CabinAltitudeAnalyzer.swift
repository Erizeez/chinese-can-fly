import Foundation

/// 客舱增压环境与高度分析器
public final class CabinAltitudeAnalyzer: @unchecked Sendable {
    private var lastTimestamp: Date?
    private var lastCabinAltitudeFt: Double?
    private var filteredVSIFpm: Double = 0.0
    private let filterAlpha: Double = 0.2 // 一阶低通滤波系数

    public init() {}

    /// 处理最新的气压采样点
    /// - Parameters:
    ///   - pressureHPa: iPhone 气压计采样的环境气压 (百帕)
    ///   - timestamp: 采样时间
    /// - Returns: (客舱等效高度 ft, 客舱升降率 fpm)
    public func update(pressureHPa: Double, timestamp: Date = Date()) -> (cabinAltitudeFt: Double, cabinVSIFpm: Double) {
        let cabinAltFt = ISAAtmosphere.altitudeFtFromPressure(hPa: pressureHPa)
        
        guard let prevTime = lastTimestamp, let prevAlt = lastCabinAltitudeFt else {
            self.lastTimestamp = timestamp
            self.lastCabinAltitudeFt = cabinAltFt
            return (cabinAltFt, 0.0)
        }

        let dt = timestamp.timeIntervalSince(prevTime)
        if dt > 0.05 { // 避免除零或过于高频的微抖动
            let deltaAltitude = cabinAltFt - prevAlt
            let rawVSIFpm = (deltaAltitude / dt) * 60.0 // 转换为英尺/分钟
            
            // 一阶低通滤波，滤除机舱空调微气流波动
            filteredVSIFpm = (filterAlpha * rawVSIFpm) + ((1.0 - filterAlpha) * filteredVSIFpm)
            
            self.lastTimestamp = timestamp
            self.lastCabinAltitudeFt = cabinAltFt
        }

        return (cabinAltFt, filteredVSIFpm)
    }

    /// 重置分析器状态
    public func reset() {
        lastTimestamp = nil
        lastCabinAltitudeFt = nil
        filteredVSIFpm = 0.0
    }
}
