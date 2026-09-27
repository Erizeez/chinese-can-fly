import SwiftUI
import CCFlyCore
import Charts

/// 飞行数据与航空传感器融合 (Avionics & Telemetry) 页面
public struct AvionicsTelemetryView: View {
    @State private var dataManager = FlightDataManager.shared
    @State private var showCalibrationDialog: Bool = false
    @State private var showTouchdownAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. 核心控制与工况状态栏
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(dataManager.isRecording ? Color.red : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text(dataManager.isSimulationRunning ? "飞行仿真演练中 (PKX -> CAN)" : (dataManager.isRecording ? "真机黑匣子高频记录中" : "待机中 (未记录)"))
                                        .font(.caption.bold())
                                        .foregroundStyle(dataManager.isRecording ? .red : .secondary)
                                }
                                Text("阶段: \(flightPhaseTitle(dataManager.flightPhase))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            // 真机硬件传感器录制开关
                            Button {
                                if dataManager.isRecording && !dataManager.isSimulationRunning {
                                    dataManager.stopLiveBlackbox()
                                } else {
                                    dataManager.startLiveBlackbox()
                                }
                            } label: {
                                Label(dataManager.isRecording && !dataManager.isSimulationRunning ? "停止真机记录" : "开启真机传感器", systemImage: "record.circle")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(dataManager.isRecording && !dataManager.isSimulationRunning ? .red : .blue)

                            // 航空动力学仿真演练开关
                            Button {
                                if dataManager.isSimulationRunning {
                                    dataManager.stopFlightSimulation()
                                } else {
                                    dataManager.startFlightSimulation()
                                }
                            } label: {
                                Label(dataManager.isSimulationRunning ? "停止演练" : "仿真演练", systemImage: dataManager.isSimulationRunning ? "stop.fill" : "play.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                    .padding(.horizontal)

                    // 2. 航空主飞行仪表 (PFD Artificial Horizon)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.06, green: 0.08, blue: 0.12))
                            .frame(height: 190)

                        GeometryReader { geo in
                            ZStack {
                                // 天空蓝与大地棕
                                VStack(spacing: 0) {
                                    Rectangle().fill(Color(red: 0.12, green: 0.38, blue: 0.68))
                                    Rectangle().fill(Color(red: 0.42, green: 0.28, blue: 0.15))
                                }
                                .frame(width: geo.size.width * 2.2, height: geo.size.height * 2.2)
                                // 俯仰角平移 (每度 3.2 像素)
                                .offset(y: CGFloat(dataManager.pitchDeg * 3.2))
                                // 滚转角旋转
                                .rotationEffect(.degrees(-dataManager.rollDeg))

                                // 水平俯仰刻度标尺 (Pitch Ladder)
                                VStack(spacing: 16) {
                                    ForEach([-20, -10, 0, 10, 20], id: \.self) { deg in
                                        HStack {
                                            Rectangle().frame(width: 20, height: 2)
                                            Text("\(abs(deg))")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            Rectangle().frame(width: 20, height: 2)
                                        }
                                        .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                .offset(y: CGFloat(dataManager.pitchDeg * 3.2))
                                .rotationEffect(.degrees(-dataManager.rollDeg))

                                // 机体固定准星十字 (Aircraft Symbol)
                                Image(systemName: "plus")
                                    .font(.system(size: 26, weight: .heavy))
                                    .foregroundStyle(.yellow)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .frame(height: 190)

                        // 仪表角标数值 (实时 Pitch / Roll)
                        VStack {
                            HStack {
                                Text("PITCH: \(String(format: "%+.1f°", dataManager.pitchDeg))")
                                Spacer()
                                Text("ROLL: \(String(format: "%+.1f°", dataManager.rollDeg))")
                            }
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(.white)
                            .padding(10)
                            Spacer()
                            HStack {
                                Text("HDG: \(Int(dataManager.groundTrackDeg))°")
                                Spacer()
                                Text("SPD: \(Int(dataManager.groundSpeedKts)) KTS")
                            }
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(.white)
                            .padding(10)
                        }
                    }
                    .padding(.horizontal)

                    // 3. “双高”与客舱增压系统看板 (核心解耦模型)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("高度解耦与客舱增压系统")
                                .font(.headline)
                            Spacer()
                            Button {
                                showCalibrationDialog = true
                            } label: {
                                Label("机体轴校准", systemImage: "gyroscope")
                                    .font(.caption2.bold())
                            }
                        }

                        HStack(spacing: 12) {
                            // 真实几何飞行高度 (GNSS)
                            AvionicsMetricBox(
                                title: "飞机真实高度 (GNSS)",
                                value: "\(Int(dataManager.geometricAltitudeFt))",
                                unit: "FT",
                                subtitle: "真地速: \(Int(dataManager.groundSpeedKts)) KTS",
                                color: .blue
                            )

                            // 客舱等效高度 (iPhone 气压计)
                            AvionicsMetricBox(
                                title: "客舱等效高度 (Cabin)",
                                value: "\(Int(dataManager.cabinAltitudeFt))",
                                unit: "FT",
                                subtitle: "客舱升降: \(String(format: "%+.0f", dataManager.cabinVSIFpm)) FPM",
                                color: .orange
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // 4. 过载 Nz/Nx 与晴空颠簸 EDR 看板
                    HStack(spacing: 12) {
                        AvionicsMetricBox(
                            title: "垂直过载 Nz",
                            value: String(format: "%.2fg", dataManager.normalGForce),
                            unit: "",
                            subtitle: dataManager.normalGForce > 1.25 ? "抬头/机动中" : "平飞巡航",
                            color: .purple
                        )
                        AvionicsMetricBox(
                            title: "纵向推力/刹车 Nx",
                            value: String(format: "%+.2fg", dataManager.longitudinalGForce),
                            unit: "",
                            subtitle: dataManager.longitudinalGForce > 0.2 ? "起飞推背加速" : "巡航阻力平衡",
                            color: .teal
                        )
                    }
                    .padding(.horizontal)

                    // 5. 接地触地质量报告 (如果产生)
                    if let touchdown = dataManager.latestTouchdown {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("着陆触地力学分析报告 (Touchdown)", systemImage: "checkmark.seal.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.green)
                                Spacer()
                                Text(touchdown.rating)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                            Text("接地过载峰值: \(String(format: "%.2f", touchdown.touchdownG)) g · 触地垂直下沉率: \(String(format: "%.0f", touchdown.sinkRateFpm)) FPM")
                                .font(.caption.monospaced())
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }

                    // 6. 真实历史图表：双高剖面走势
                    VStack(alignment: .leading, spacing: 8) {
                        Text("全航程双高剖面走势 (真实 vs 客舱)")
                            .font(.headline)

                        if dataManager.telemetryHistory.isEmpty {
                            Text("等待数据点累积中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(height: 140)
                        } else {
                            Chart {
                                ForEach(Array(dataManager.telemetryHistory.enumerated()), id: \.offset) { index, point in
                                    LineMark(
                                        x: .value("Frame", index),
                                        y: .value("Altitude", point.geometricAltitudeFt),
                                        series: .value("Type", "真实飞行高度 (ft)")
                                    )
                                    .foregroundStyle(.blue)

                                    LineMark(
                                        x: .value("Frame", index),
                                        y: .value("Altitude", point.cabinAltitudeFt),
                                        series: .value("Type", "客舱气压高度 (ft)")
                                    )
                                    .foregroundStyle(.orange)
                                }
                            }
                            .frame(height: 160)
                            .chartLegend(position: .top, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // 7. 垂直过载 G 值波动走势图
                    VStack(alignment: .leading, spacing: 8) {
                        Text("垂直过载 G 波动曲线")
                            .font(.headline)

                        if dataManager.telemetryHistory.isEmpty {
                            Text("等待数据点累积中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(height: 120)
                        } else {
                            Chart {
                                ForEach(Array(dataManager.telemetryHistory.enumerated()), id: \.offset) { index, point in
                                    LineMark(
                                        x: .value("Frame", index),
                                        y: .value("G-Force", point.normalGForce)
                                    )
                                    .foregroundStyle(.purple)
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("飞行数据与惯导")
            .background(Color(.systemGroupedBackground))
            .alert("机体轴正交对准校准", isPresented: $showCalibrationDialog) {
                Button("确定校准") {
                    // 执行机体轴校准
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请将手机固定在前排座椅网兜或小桌板。校准算法将利用滑跑加速推力与重力正交投影，消除手机摆放倾角。")
            }
        }
    }

    private func flightPhaseTitle(_ phase: FlightPhase) -> String {
        switch phase {
        case .parked: return "停机坪静止"
        case .taxi: return "滑行道滑行"
        case .takeoffRoll: return "起飞滑跑 (推背加速)"
        case .initialClimb: return "抬轮离地爬升"
        case .cruise: return "高空巡航平飞"
        case .descent: return "下降阶段"
        case .approach: return "进近对正五边"
        case .touchdown: return "主轮接地瞬间"
        case .landingRoll: return "着陆刹车滑跑"
        }
    }
}

struct AvionicsMetricBox: View {
    let title: String
    let value: String
    let unit: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
