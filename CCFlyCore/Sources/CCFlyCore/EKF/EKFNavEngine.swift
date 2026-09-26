import Foundation
import simd

/// 惯导状态估计输出
public struct NavState: Sendable {
    public let positionNED: simd_double3  // 北东地 (North, East, Down) 坐标 (米)
    public let velocityNED: simd_double3  // 北东地 速度 (m/s)
    public let pitchDeg: Double           // 俯仰角 (度)
    public let rollDeg: Double            // 滚转角 (度)
    public let headingDeg: Double         // 真航向 (度)
    public let isDeadReckoning: Bool      // 是否处于纯惯导死推算模式 (GNSS 失锁)
}

/// 简化扩展卡尔曼滤波 (EKF) 惯导融合引擎
public final class EKFNavEngine: @unchecked Sendable {
    // 状态量: 位置(3), 速度(3), 加速度偏置(3)
    private var posNED: simd_double3 = .zero
    private var velNED: simd_double3 = .zero
    private var accelBias: simd_double3 = .zero
    
    // 姿态四元数 (从机体 Body 到导航 NED)
    private var q_b_to_n: simd_quatd = simd_quatd(vector: simd_double4(0, 0, 0, 1))

    // 协方差估计 (对角矩阵简化加速运算)
    private var pPos: simd_double3 = simd_double3(10.0, 10.0, 20.0)
    private var pVel: simd_double3 = simd_double3(1.0, 1.0, 2.0)
    private var pBias: simd_double3 = simd_double3(0.01, 0.01, 0.01)

    // 噪声参数
    private let qAccNoise: Double = 0.05
    private let qGyroNoise: Double = 0.005

    // 上次 GNSS 观测时间
    private var lastGNSSUpdateTime: Date?
    private var lastIMUTime: Date?
    private let gnssTimeoutThreshold: TimeInterval = 3.0 // 超过 3 秒未收到 GPS 视作死推算

    public init() {}

    /// 惯导预测阶段 (由高频 IMU 加速度与陀螺仪驱动，通常 50Hz)
    /// - Parameters:
    ///   - bodyAcc: 机体坐标系下的无重力线加速度 (m/s^2)
    ///   - bodyGyro: 机体坐标系下的三轴角速度 (rad/s)
    ///   - timestamp: 采样时间
    public func predict(bodyAcc: simd_double3, bodyGyro: simd_double3, timestamp: Date = Date()) {
        guard let prevTime = lastIMUTime else {
            lastIMUTime = timestamp
            return
        }
        let dt = min(0.1, max(0.001, timestamp.timeIntervalSince(prevTime)))
        lastIMUTime = timestamp

        // 1. 陀螺仪积分姿态四元数
        let angleIncrement = (bodyGyro) * dt
        let angleMag = simd_length(angleIncrement)
        if angleMag > 1e-6 {
            let dq = simd_quatd(angle: angleMag, axis: simd_normalize(angleIncrement))
            q_b_to_n = simd_normalize(q_b_to_n * dq)
        }

        // 2. 将去偏后的加速度旋转到 NED 导航坐标系
        let correctedAccBody = bodyAcc - accelBias
        let accNED = q_b_to_n.act(correctedAccBody)

        // 3. 速度与位置积分 (机械编排)
        posNED += velNED * dt + 0.5 * accNED * (dt * dt)
        velNED += accNED * dt

        // 4. 协方差传播 (考虑时间步进与加速度计过程噪声)
        pPos += pVel * dt + simd_double3(repeating: 0.5 * qAccNoise * (dt * dt))
        pVel += simd_double3(repeating: qAccNoise * dt)
        pBias += simd_double3(repeating: 1e-5 * dt)
    }

    /// GNSS 观测更新阶段 (由 1Hz GPS 触发)
    /// - Parameters:
    ///   - gnssPosNED: GPS 测量到的 NED 坐标
    ///   - gnssVelNED: GPS 测量到的 NED 速度
    ///   - posAccuracy: GPS 标称位置精度 (米)
    ///   - velAccuracy: GPS 标称速度精度 (m/s)
    public func updateGNSS(
        gnssPosNED: simd_double3,
        gnssVelNED: simd_double3,
        posAccuracy: Double,
        velAccuracy: Double,
        timestamp: Date = Date()
    ) {
        lastGNSSUpdateTime = timestamp

        let rPos = max(0.5, posAccuracy * posAccuracy)
        let rVel = max(0.1, velAccuracy * velAccuracy)

        // 简易卡尔曼增益解算 (每个轴独立解耦更新)
        for i in 0..<3 {
            // 位置卡尔曼更新
            let kPos = pPos[i] / (pPos[i] + rPos)
            let posResidual = gnssPosNED[i] - posNED[i]
            posNED[i] += kPos * posResidual
            pPos[i] = (1.0 - kPos) * pPos[i]

            // 速度卡尔曼更新
            let kVel = pVel[i] / (pVel[i] + rVel)
            let velResidual = gnssVelNED[i] - velNED[i]
            velNED[i] += kVel * velResidual
            pVel[i] = (1.0 - kVel) * pVel[i]

            // 零偏协同微调
            let kBias = 0.05 * kVel
            accelBias[i] -= kBias * velResidual
        }
    }

    /// 输出当前最佳融合姿态与位置状态
    public func getNavState(now: Date = Date()) -> NavState {
        let isDR: Bool
        if let lastGNSS = lastGNSSUpdateTime {
            isDR = now.timeIntervalSince(lastGNSS) > gnssTimeoutThreshold
        } else {
            isDR = true
        }

        // 从四元数提取欧拉角 (Euler Angles)
        let q = q_b_to_n.vector
        let qx = q.x, qy = q.y, qz = q.z, qw = q.w

        // 滚转角 Roll (phi)
        let sinr_cosp = 2.0 * (qw * qx + qy * qz)
        let cosr_cosp = 1.0 - 2.0 * (qx * qx + qy * qy)
        let rollRad = atan2(sinr_cosp, cosr_cosp)

        // 俯仰角 Pitch (theta)
        let sinp = 2.0 * (qw * qy - qz * qx)
        let pitchRad: Double
        if abs(sinp) >= 1 {
            pitchRad = copysign(.pi / 2.0, sinp)
        } else {
            pitchRad = asin(sinp)
        }

        // 偏航角 Yaw (psi)
        let siny_cosp = 2.0 * (qw * qz + qx * qy)
        let cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
        let yawRad = atan2(siny_cosp, cosy_cosp)

        var headingDeg = yawRad * (180.0 / .pi)
        if headingDeg < 0 { headingDeg += 360.0 }

        return NavState(
            positionNED: posNED,
            velocityNED: velNED,
            pitchDeg: pitchRad * (180.0 / .pi),
            rollDeg: rollRad * (180.0 / .pi),
            headingDeg: headingDeg,
            isDeadReckoning: isDR
        )
    }

    public func reset() {
        posNED = .zero
        velNED = .zero
        accelBias = .zero
        q_b_to_n = simd_quatd(vector: simd_double4(0, 0, 0, 1))
        lastGNSSUpdateTime = nil
        lastIMUTime = nil
    }
}
