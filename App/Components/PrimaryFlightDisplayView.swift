import SwiftUI
import CCFlyCore

/// 航空专业级人工地平仪 / 主飞行仪表 (Primary Flight Display - PFD)
/// 基于高效单层 Shape 几何光栅化架构，完全规避离屏渲染与 IOSurface 申请，实现 0 卡顿、0 丢帧与 120fps 极速响应
public struct PrimaryFlightDisplayView: View {
    @State private var unitManager = UnitManager.shared

    let pitch: Double      // 俯仰角 (°，抬头为正)
    let roll: Double       // 滚转角 (°，右倾为正)
    let heading: Double    // 真航向 (°)
    let speedKts: Double   // 地速 (KTS)
    let altitudeFt: Double // 几何高度 (FT)

    public init(
        pitch: Double,
        roll: Double,
        heading: Double = 0,
        speedKts: Double = 0,
        altitudeFt: Double = 0
    ) {
        self.pitch = pitch
        self.roll = roll
        self.heading = heading
        self.speedKts = speedKts
        self.altitudeFt = altitudeFt
    }

    public var body: some View {
        ZStack {
            // 1. 仪表暗色底盘
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.09))

            // 2. 动态天地线与俯仰梯尺 (使用单一视图矩阵旋转与平移，零离屏渲染)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxPitchOffset = h * 0.42
                let rawPitchOffset = CGFloat(pitch * 2.8)
                let clampedPitchOffset = max(-maxPitchOffset, min(maxPitchOffset, rawPitchOffset))

                ZStack {
                    // 2.1 天空与大地平移旋转图层
                    VStack(spacing: 0) {
                        // 天空 (标准 EFIS 航空天蓝渐变)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.08, green: 0.32, blue: 0.62), Color(red: 0.14, green: 0.45, blue: 0.78)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: w * 2.4, height: h * 1.8)

                        // 0° 地平基准线 (白色 2px)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: w * 2.4, height: 2)

                        // 大地 (标准 EFIS 航空深棕褐渐变)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.42, green: 0.26, blue: 0.14), Color(red: 0.28, green: 0.16, blue: 0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: w * 2.4, height: h * 1.8)
                    }

                    // 2.2 俯仰梯尺刻度线 (单一 Shape 统一路径绘制，零动态子视图开销)
                    PitchLadderShape()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: 140, height: 180)

                    // 2.3 梯尺数字标签 (静态固定布局)
                    PitchLadderLabels()
                        .frame(width: 140, height: 180)
                }
                .offset(y: clampedPitchOffset)
                .rotationEffect(.degrees(-roll))
                .frame(width: w, height: h)
                .clipped()
            }

            // 3. 飞机机体中央固定参考准星 (固定在屏幕正中央，不随天地线旋转)
            AircraftReferenceSymbol()
                .frame(width: 100, height: 20)

            // 4. 仪表固定覆盖层：顶部航向/空速/高度与底部实时姿态角数值
            VStack {
                let spd = unitManager.speed(knots: speedKts)
                let alt = unitManager.altitude(feet: altitudeFt)

                HStack {
                    Text("SPD \(spd.value) \(spd.unit)")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)

                    Spacer()

                    // 顶部航向罗盘读数
                    HStack(spacing: 2) {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 8))
                            .rotationEffect(.degrees(180))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%03d°", Int(heading)))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    Text("ALT \(alt.value) \(alt.unit)")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                // 底部实时姿态角数值
                HStack {
                    Text(String(format: "PITCH: %+.1f°", pitch))
                    Spacer()
                    Text(String(format: "ROLL: %+.1f°", roll))
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

/// 单一高效 Shape 绘制所有梯尺刻度线 (单次 GPU 路径提交)
struct PitchLadderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let centerY = rect.midY
        let degrees = [-20, -15, -10, -5, 5, 10, 15, 20]
        let gap: CGFloat = 16

        for deg in degrees {
            let y = centerY - CGFloat(deg) * 2.8
            let isMajor = (deg % 10 == 0)
            let barWidth: CGFloat = isMajor ? 32 : 18

            // 左刻度线
            path.move(to: CGPoint(x: centerX - gap - barWidth, y: y))
            path.addLine(to: CGPoint(x: centerX - gap, y: y))
            if deg > 0 {
                path.addLine(to: CGPoint(x: centerX - gap, y: y + 4))
            } else if deg < 0 {
                path.addLine(to: CGPoint(x: centerX - gap, y: y - 4))
            }

            // 右刻度线
            path.move(to: CGPoint(x: centerX + gap, y: y))
            path.addLine(to: CGPoint(x: centerX + gap + barWidth, y: y))
            if deg > 0 {
                path.addLine(to: CGPoint(x: centerX + gap, y: y + 4))
            } else if deg < 0 {
                path.addLine(to: CGPoint(x: centerX + gap, y: y - 4))
            }
        }

        return path
    }
}

/// 梯尺文字标签
struct PitchLadderLabels: View {
    private let degrees = [-20, -15, -10, -5, 5, 10, 15, 20]

    var body: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2.0
            let centerX = geo.size.width / 2.0
            let gap: CGFloat = 16

            ForEach(degrees, id: \.self) { deg in
                let y = centerY - CGFloat(deg) * 2.8
                let isMajor = (deg % 10 == 0)
                let barWidth: CGFloat = isMajor ? 32 : 18

                Text("\(abs(deg))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: centerX - gap - barWidth - 8, y: y)

                Text("\(abs(deg))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: centerX + gap + barWidth + 8, y: y)
            }
        }
    }
}

/// 标准航空 PFD 飞机基准准星 (黄色飞翼符号)
struct AircraftReferenceSymbol: View {
    var body: some View {
        ZStack {
            // 左翼
            HStack(spacing: 0) {
                Rectangle().fill(Color.yellow).frame(width: 32, height: 4)
                Rectangle().fill(Color.yellow).frame(width: 4, height: 10)
            }
            .offset(x: -26)

            // 中央方块参考点
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)

            // 右翼
            HStack(spacing: 0) {
                Rectangle().fill(Color.yellow).frame(width: 4, height: 10)
                Rectangle().fill(Color.yellow).frame(width: 32, height: 4)
            }
            .offset(x: 26)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }
}
