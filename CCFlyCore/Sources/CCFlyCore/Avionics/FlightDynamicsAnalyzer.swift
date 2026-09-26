import Foundation

/// 着陆质量与过载分析结果
public struct TouchdownReport: Codable, Sendable {
    public let touchdownG: Double
    public let sinkRateFpm: Double
    public let rating: String
    public let timestamp: Date
}

/// 飞行力学分析器（过载捕获、接地冲击评估、湍流 EDR 估算）
public final class FlightDynamicsAnalyzer: @unchecked Sendable {
    private var maxRecordedG: Double = 1.0
    private var minRecordedG: Double = 1.0
    private var gHistory: [Double] = []
    private let historyCapacity = 50 // 保留最近 1 秒 (50Hz) 的加速度以计算方差

    public init() {}

    /// 处理新的机体三轴过载与垂直沉降率
    public func processSample(normalG: Double, sinkRateFpm: Double) {
        if normalG > maxRecordedG { maxRecordedG = normalG }
        if normalG < minRecordedG { minRecordedG = normalG }

        gHistory.append(normalG)
        if gHistory.count > historyCapacity {
            gHistory.removeFirst()
        }
    }

    /// 评估着陆接地冲击质量
    public func evaluateTouchdown(peakNormalG: Double, touchdownSinkRateFpm: Double) -> TouchdownReport {
        let rating: String
        if peakNormalG < 1.30 && touchdownSinkRateFpm > -180.0 {
            rating = "卓越 (Butter Smooth)"
        } else if peakNormalG <= 1.60 && touchdownSinkRateFpm >= -360.0 {
            rating = "标准稳健 (Firm & Safe)"
        } else if peakNormalG <= 1.90 {
            rating = "偏重接地 (Heavy Impact)"
        } else {
            rating = "严重重着陆警示 (Hard Landing)"
        }

        return TouchdownReport(
            touchdownG: peakNormalG,
            sinkRateFpm: touchdownSinkRateFpm,
            rating: rating,
            timestamp: Date()
        )
    }

    /// 估算湍流能量耗散率指数 (Turbulence EDR)
    /// 基于垂直过载波动标准差的轻量估计
    public func calculateTurbulenceEDR() -> Double {
        guard gHistory.count >= 20 else { return 0.0 }
        let mean = gHistory.reduce(0.0, +) / Double(gHistory.count)
        let sumSquaredDiff = gHistory.reduce(0.0) { $0 + pow($1 - mean, 2) }
        let stdDev = sqrt(sumSquaredDiff / Double(gHistory.count))
        
        // 将过载标准差映射为 ICAO 颠簸 EDR 估值 (0.0 ~ 1.0)
        let edr = min(1.0, stdDev * 2.5)
        return edr
    }

    public func getExtremes() -> (maxG: Double, minG: Double) {
        return (maxRecordedG, minRecordedG)
    }

    public func reset() {
        maxRecordedG = 1.0
        minRecordedG = 1.0
        gHistory.removeAll()
    }
}
