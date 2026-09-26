import Foundation
import simd

/// 手机传感器坐标系 (Sensor Frame) -> 飞机机体坐标系 (Aircraft Body Frame) 正交对准器
public final class BodyFrameAligner: @unchecked Sendable {
    // 旋转变换矩阵 3x3 (从传感器系转至飞机机体坐标系)
    // 飞机机体轴约定: X 轴向前 (机头), Y 轴向右 (右机翼), Z 轴向下 (机腹)
    private var rotationMatrix: simd_double3x3 = matrix_identity_double3x3
    private var isCalibrated: Bool = false

    public init() {}

    /// 重置为初始单位矩阵
    public func reset() {
        rotationMatrix = matrix_identity_double3x3
        isCalibrated = false
    }

    /// 执行机体轴对准校准
    /// - Parameters:
    ///   - gravitySensor: 手机测量到的静止或平稳滑行时的重力加速度矢量 (Gx, Gy, Gz)
    ///   - forwardAccSensor: 直线起飞加速时去除重力后的推力前向加速度矢量 (Ax, Ay, Az)
    public func calibrate(gravitySensor: simd_double3, forwardAccSensor: simd_double3) {
        // 1. Z 轴: 机体垂直向下方向 = 重力方向
        let zBody = simd_normalize(gravitySensor)

        // 2. 投影前向加速度到垂直于 Z 轴的平面，消除重力残余
        let dotProduct = simd_dot(forwardAccSensor, zBody)
        let forwardProjected = forwardAccSensor - (zBody * dotProduct)
        
        guard simd_length(forwardProjected) > 1e-4 else {
            // 前向加速度过微弱，无法解算机头方向
            return
        }
        let xBody = simd_normalize(forwardProjected)

        // 3. Y 轴: 叉乘求出机体右向轴 (右手定则: Z cross X = Y)
        let yBody = simd_cross(zBody, xBody)

        // 4. 构建旋转矩阵: R = [xBody, yBody, zBody]^T
        // 使 v_body = R * v_sensor
        self.rotationMatrix = simd_double3x3(rows: [xBody, yBody, zBody])
        self.isCalibrated = true
    }

    /// 将手机传感器测量的 3 轴加速度变换为飞机机体 3 轴过载 (Nx, Ny, Nz)
    /// - Parameter sensorAcc: 手机传感器测得的加速度矢量 (包括重力)
    /// - Returns: 飞机机体加速度 (X: 前向拉力/刹车, Y: 侧滑侧向力, Z: 垂向过载)
    public func transformAcceleration(sensorAcc: simd_double3) -> (nx: Double, ny: Double, nz: Double) {
        let bodyAcc = rotationMatrix * sensorAcc
        // 归一化为 G 值 (1g = 9.80665 m/s^2)
        let gConst = 9.80665
        let nx = bodyAcc.x / gConst
        let ny = bodyAcc.y / gConst
        let nz = bodyAcc.z / gConst
        return (nx, ny, nz)
    }

    /// 提取等效机体俯仰角与滚转角 (度)
    public func calculateAttitudeAngles(sensorGravity: simd_double3) -> (pitchDeg: Double, rollDeg: Double) {
        let bodyGravity = rotationMatrix * sensorGravity
        let gx = bodyGravity.x
        let gy = bodyGravity.y
        let gz = bodyGravity.z

        // 俯仰角 Pitch: 抬头为正 (arctan of -gx / sqrt(gy^2 + gz^2))
        let pitchRad = atan2(-gx, sqrt(gy * gy + gz * gz))
        // 滚转角 Roll: 右滚为正 (arctan of gy / gz)
        let rollRad = atan2(gy, gz)

        let pitchDeg = pitchRad * (180.0 / .pi)
        let rollDeg = rollRad * (180.0 / .pi)

        return (pitchDeg, rollDeg)
    }

    public var calibrated: Bool { isCalibrated }
}
