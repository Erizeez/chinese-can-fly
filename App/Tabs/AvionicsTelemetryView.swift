import SwiftUI
import CCFlyCore
import Charts

/// 飞行数据与航空传感器融合 (Avionics & Telemetry) 页面
public struct AvionicsTelemetryView: View {
    @State private var isRecording: Bool = false
    @State private var pitchDeg: Double = 2.5
    @State private var rollDeg: Double = -1.2
    @State private var geometricAltFt: Double = 33020.0
    @State private var cabinAltFt: Double = 6850.0
    @State private var cabinVSIFpm: Double = +50.0
    @State private var currentNz: Double = 1.02
    @State private var groundSpeedKts: Double = 465.0
    @State private var groundTrackDeg: Double = 168.0
    @State private var turbulenceEDR: Double = 0.08
    @State private var showCalibrationDialog: Bool = false

    // 历史时序图表数据
    @State private var telemetryHistory: [TelemetryChartPoint] = (0..<30).map { i in
        TelemetryChartPoint(
            timeOffset: Double(i),
            geometricAlt: 30000.0 + Double(i) * 100.0,
            cabinAlt: 6800.0 + Double(i) * 3.0,
            gForce: 1.0 + sin(Double(i) * 0.4) * 0.08
        )
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 状态栏：飞行工况与保活模式
                    HStack {
                        Label(isRecording ? "黑匣子高频记录中 (后台保活就绪)" : "待机 (未开启记录)", systemImage: isRecording ? "record.circle.fill" : "pause.circle")
                            .font(.caption.bold())
                            .foregroundStyle(isRecording ? .red : .secondary)
                        Spacer()
                        Button(isRecording ? "停止记录" : "开始记录") {
                            isRecording.toggle()
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                        .tint(isRecording ? .red : .blue)
                    }
                    .padding(.horizontal)

                    // 1. 虚拟姿态仪 (PFD Artificial Horizon)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.08, green: 0.1, blue: 0.14))
                            .frame(height: 180)

                        // 天空与地面分界
                        GeometryReader { geo in
                            ZStack {
                                // 天空蓝与大地棕
                                VStack(spacing: 0) {
                                    Rectangle().fill(Color(red: 0.12, green: 0.38, blue: 0.65))
                                    Rectangle().fill(Color(red: 0.45, green: 0.30, blue: 0.18))
                                }
                                .frame(width: geo.size.width * 2, height: geo.size.height * 2)
                                .offset(y: CGFloat(pitchDeg * 3.0))
                                .rotationEffect(.degrees(rollDeg))

                                // 机体固定十字准星
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.yellow)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .frame(height: 180)

                        // 仪表角标数值
                        VStack {
                            HStack {
                                Text("PITCH: \(String(format: "%+.1f°", pitchDeg))")
                                Spacer()
                                Text("ROLL: \(String(format: "%+.1f°", rollDeg))")
                            }
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(.white)
                            .padding(10)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)

                    // 2. “双高”与客舱增压监测系统核心看板
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("高度解耦与客舱增压监测")
                                .font(.headline)
                            Spacer()
                            Button {
                                showCalibrationDialog = true
                            } label: {
                                Label("校准机体轴", systemImage: "gyroscope")
                                    .font(.caption2.bold())
                            }
                        }

                        HStack(spacing: 12) {
                            // 真实几何高度 (GNSS)
                            MetricBox(
                                title: "飞机真实高度 (GNSS)",
                                value: "\(Int(geometricAltFt))",
                                unit: "FT",
                                subtitle: "真地速: \(Int(groundSpeedKts)) KTS",
                                color: .blue
                            )

                            // 客舱气压高度 (iPhone Barometer)
                            MetricBox(
                                title: "客舱等效高度 (Cabin)",
                                value: "\(Int(cabinAltFt))",
                                unit: "FT",
                                subtitle: "客舱升降: \(String(format: "%+.0f", cabinVSIFpm)) FPM",
                                color: .orange
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // 3. 过载与湍流颠簸指数 (G-Load & Turbulence EDR)
                    HStack(spacing: 12) {
                        MetricBox(
                            title: "当前垂直过载 Nz",
                            value: String(format: "%.2fg", currentNz),
                            unit: "",
                            subtitle: "起落峰值监控就绪",
                            color: .purple
                        )
                        MetricBox(
                            title: "湍流强度 (EDR)",
                            value: String(format: "%.2f", turbulenceEDR),
                            unit: "EDR",
                            subtitle: turbulenceEDR < 0.15 ? "平稳 (Smooth)" : "轻度颠簸 (Light)",
                            color: turbulenceEDR < 0.15 ? .green : .yellow
                        )
                    }
                    .padding(.horizontal)

                    // 4. 全程图表：几何高 vs 客舱高剖面走势
                    VStack(alignment: .leading, spacing: 8) {
                        Text("全航程高度剖面 (真实 vs 客舱)")
                            .font(.headline)
                        
                        Chart {
                            ForEach(telemetryHistory) { point in
                                LineMark(
                                    x: .value("Time", point.timeOffset),
                                    y: .value("Altitude", point.geometricAlt),
                                    series: .value("Type", "真实飞行高度 (ft)")
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Time", point.timeOffset),
                                    y: .value("Altitude", point.cabinAlt),
                                    series: .value("Type", "客舱气压高度 (ft)")
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .frame(height: 160)
                        .chartLegend(position: .top, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // 5. 过载历史曲线 (Nz 波动)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("垂直过载 G 值波动 (着陆冲击分析)")
                            .font(.headline)

                        Chart {
                            ForEach(telemetryHistory) { point in
                                LineMark(
                                    x: .value("Time", point.timeOffset),
                                    y: .value("G-Force", point.gForce)
                                )
                                .foregroundStyle(.purple)
                            }
                        }
                        .frame(height: 120)
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
            .alert("机体轴对准校准", isPresented: $showCalibrationDialog) {
                Button("确定校准") {
                    // 执行机体对准
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请将手机固定在机舱小桌板或前方座椅网兜。在飞机滑跑加速或平稳滑行时点击校准，算法将自动解算手机与飞机机头的正交姿态。")
            }
        }
    }
}

struct MetricBox: View {
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

struct TelemetryChartPoint: Identifiable {
    let id = UUID()
    let timeOffset: Double
    let geometricAlt: Double
    let cabinAlt: Double
    let gForce: Double
}
