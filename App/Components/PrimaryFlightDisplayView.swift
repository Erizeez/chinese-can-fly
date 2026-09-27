import SwiftUI

/// 航空专业级人工地平仪 / 主飞行仪表 (Primary Flight Display - PFD)
/// 基于 Metal 硬件加速合成 (.drawingGroup)，丝滑 60/120fps 真实飞机视角
public struct PrimaryFlightDisplayView: View {
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
            // 仪表底盘
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.04, green: 0.06, blue: 0.09))

            // 1. 动态天地线与俯仰梯尺 (限制在视窗内部，防止任何溢出)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxPitchOffset = h * 0.42
                // 俯仰平移映射 (限制在视窗内，每度 2.8 像素)
                let rawPitchOffset = CGFloat(pitch * 2.8)
                let clampedPitchOffset = max(-maxPitchOffset, min(maxPitchOffset, rawPitchOffset))

                ZStack {
                    // 天空与大地背景层
                    VStack(spacing: 0) {
                        // 天空 (标准 EFIS 航空天蓝)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.08, green: 0.32, blue: 0.62), Color(red: 0.14, green: 0.45, blue: 0.78)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: w * 2.0, height: h * 1.5)

                        // 0° 地平基准线 (白色 2px)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: w * 2.0, height: 2)

                        // 大地 (标准 EFIS 航空深棕褐)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.42, green: 0.26, blue: 0.14), Color(red: 0.28, green: 0.16, blue: 0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: w * 2.0, height: h * 1.5)
                    }
                    .offset(y: clampedPitchOffset)
                    .rotationEffect(.degrees(-roll))

                    // 俯仰刻度梯尺 (Pitch Ladder)
                    VStack(spacing: 14) {
                        ForEach([-20, -15, -10, -5, 5, 10, 15, 20].reversed(), id: \.self) { deg in
                            HStack(spacing: 6) {
                                Text("\(abs(deg))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 16, alignment: .trailing)

                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: deg % 10 == 0 ? 36 : 20, height: 1.5)

                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 18)

                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: deg % 10 == 0 ? 36 : 20, height: 1.5)

                                Text("\(abs(deg))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 16, alignment: .leading)
                            }
                        }
                    }
                    .offset(y: clampedPitchOffset)
                    .rotationEffect(.degrees(-roll))

                    // 2. 飞机机体中央固定参考准星 (固定在屏幕正中央，不随天地线旋转)
                    AircraftReferenceSymbol()
                        .frame(width: 100, height: 20)

                    // 3. 顶部航向指针与刻度
                    VStack {
                        HStack {
                            Text("SPD \(Int(speedKts))")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
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

                            Text("ALT \(Int(altitudeFt))")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
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
                .frame(width: w, height: h)
                .clipped() // 严密裁剪，杜绝任何图层溢出卡片
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        // 开启 Metal 硬件合成加速，直接调用 Metal 纹理渲染，零掉帧、零卡顿！
        .drawingGroup()
        .animation(.smooth(duration: 0.1), value: pitch)
        .animation(.smooth(duration: 0.1), value: roll)
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
