import SwiftUI
import CCFlyCore
import Charts

/// 飞行数据与航空传感器融合 (Avionics & Telemetry) 页面 - 纯实战专业级
public struct AvionicsTelemetryView: View {
    @State private var dataManager = FlightDataManager.shared
    @State private var showCalibrationDialog: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. 核心控制与黑匣子状态栏
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(dataManager.isRecording ? Color.red : Color.green)
                                        .frame(width: 8, height: 8)
                                    Text(dataManager.isRecording ? "黑匣子后台高频记录中 (50Hz)" : "真实传感器感知中 (待机就绪)")
                                        .font(.caption.bold())
                                        .foregroundStyle(dataManager.isRecording ? .red : .primary)
                                }
                                Text("当前工况: \(flightPhaseTitle(dataManager.flightPhase))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                            }
                            Spacer()

                            // 机体轴对准快速校准按钮
                            Button {
                                showCalibrationDialog = true
                            } label: {
                                Label("校准机体轴", systemImage: "gyroscope")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                        }

                        // 开始 / 停止飞行记录大按钮
                        Button {
                            if dataManager.isRecording {
                                dataManager.stopFlightRecording()
                            } else {
                                dataManager.startFlightRecording()
                            }
                        } label: {
                            Label(dataManager.isRecording ? "停止并保存飞行记录" : "开始全航程飞行记录 (后台保活)", systemImage: dataManager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                                .font(.headline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(dataManager.isRecording ? .red : .blue)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // 2. 航空专业级主飞行姿态仪 (PFD) - Metal 硬件加速，零卡顿零溢出
                    PrimaryFlightDisplayView(
                        pitch: dataManager.pitchDeg,
                        roll: dataManager.rollDeg,
                        heading: dataManager.groundTrackDeg,
                        speedKts: dataManager.groundSpeedKts,
                        altitudeFt: dataManager.geometricAltitudeFt
                    )
                    .padding(.horizontal)

                    // 3. 真实“双高”与客舱增压系统看板
                    VStack(alignment: .leading, spacing: 10) {
                        Text("双高系统与客舱增压监测")
                            .font(.headline)

                        HStack(spacing: 12) {
                            // 真实几何高度 (GNSS)
                            AvionicsRealMetricBox(
                                title: "飞机真实高度 (GNSS)",
                                value: "\(Int(dataManager.geometricAltitudeFt))",
                                unit: "FT",
                                subtitle: "真地速: \(Int(dataManager.groundSpeedKts)) KTS",
                                color: .blue
                            )

                            // 客舱等效高度 (iPhone 气压计)
                            AvionicsRealMetricBox(
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

                    // 4. 真实过载与颠簸强度
                    HStack(spacing: 12) {
                        AvionicsRealMetricBox(
                            title: "垂直过载 Nz",
                            value: String(format: "%.2fg", dataManager.normalGForce),
                            unit: "",
                            subtitle: dataManager.normalGForce > 1.25 ? "抬头/机动" : "平飞恒定",
                            color: .purple
                        )
                        AvionicsRealMetricBox(
                            title: "纵向过载 Nx",
                            value: String(format: "%+.2fg", dataManager.longitudinalGForce),
                            unit: "",
                            subtitle: dataManager.longitudinalGForce > 0.15 ? "推力加速" : "匀速巡航",
                            color: .teal
                        )
                    }
                    .padding(.horizontal)

                    // 5. 接地触地质量报告 (真实触地时显示)
                    if let touchdown = dataManager.latestTouchdown {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("着陆触地力学分析 (Touchdown)", systemImage: "checkmark.seal.fill")
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
                            Text("接地峰值过载: \(String(format: "%.2f", touchdown.touchdownG)) g · 下沉率: \(String(format: "%.0f", touchdown.sinkRateFpm)) FPM")
                                .font(.caption.monospaced())
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }

                    // 6. 飞行全程高度剖面走势 (真实黑匣子采样点)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("全航程双高走势 (真实高 vs 客舱高)")
                            .font(.headline)

                        if dataManager.telemetryHistory.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "chart.xyaxis.line")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("点击上方“开始全航程飞行记录”，即刻按高频时序采样并绘制真实飞行剖面。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .padding()
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
                }
                .padding(.vertical)
            }
            .navigationTitle("飞行数据与惯导")
            .background(Color(.systemGroupedBackground))
            .alert("机体轴正交对准校准", isPresented: $showCalibrationDialog) {
                Button("对准机头并校准") {
                    dataManager.calibrateBodyAxis()
                }
                Button("恢复默认零位") {
                    dataManager.resetBodyCalibration()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请将手机固定在前排座椅网兜或小桌板。校准算法将利用滑跑直线加速推力与重力正交投影，消除手机倾角，使姿态仪完全契合飞机机体。")
            }
        }
    }

    private func flightPhaseTitle(_ phase: FlightPhase) -> String {
        switch phase {
        case .parked: return "地面就绪"
        case .taxi: return "滑行中"
        case .takeoffRoll: return "起飞滑跑 (加速)"
        case .initialClimb: return "离地爬升"
        case .cruise: return "高空巡航"
        case .descent: return "下降进近"
        case .approach: return "进近对正"
        case .touchdown: return "主轮接地"
        case .landingRoll: return "着陆减速滑跑"
        }
    }
}

struct AvionicsRealMetricBox: View {
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
