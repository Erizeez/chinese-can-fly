import SwiftUI
import CCFlyCore

/// 设置与飞行黑匣子导出管理视图
public struct SettingsView: View {
    @State private var dataManager = FlightDataManager.shared
    @AppStorage("sensorRate") private var sensorRate: Int = 50
    @AppStorage("unitSystem") private var unitSystem: String = "aviation"
    @AppStorage("autoBlackbox") private var autoBlackbox: Bool = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio: Bool = true

    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportToastMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // 1. 传感器与飞行记录配置
                Section("传感器融合与采样率") {
                    Picker("采样刷新率", selection: $sensorRate) {
                        Text("50 Hz (极客高精/起降黑匣)").tag(50)
                        Text("10 Hz (平衡巡航模式)").tag(10)
                        Text("1 Hz (长途低功耗)").tag(1)
                    }
                    Toggle("智能起降工况自适应升频", isOn: $autoBlackbox)
                    Toggle("起降关键阶段启用微音保活通道", isOn: $keepAliveAudio)
                }

                // 2. 真实黑匣子文件导出与分享
                Section("黑匣子真实文件导出 (当前缓存 \(dataManager.telemetryHistory.count) 帧)") {
                    Button {
                        exportFile(format: "gpx")
                    } label: {
                        Label("导出标准 GPX 航迹 (两步路 / 航旅回顾)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .disabled(dataManager.telemetryHistory.isEmpty)

                    Button {
                        exportFile(format: "kml")
                    } label: {
                        Label("导出 3D KML 彩色轨迹 (Google Earth 三维拉伸)", systemImage: "globe.asia.australia.fill")
                    }
                    .disabled(dataManager.telemetryHistory.isEmpty)

                    Button {
                        exportFile(format: "csv")
                    } label: {
                        Label("导出 50Hz 原始力学遥测 CSV (含 G值与客舱压)", systemImage: "tablecells")
                    }
                    .disabled(dataManager.telemetryHistory.isEmpty)

                    if let msg = exportToastMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                // 3. 离线数据库信息
                Section("离线航空数据库 (OurAirports & CAAC)") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("中国境内机场与跑道元数据库")
                                .font(.subheadline)
                            Text("已收录 779 座机场、354 条跑道真实走向")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("已离线装载")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("国内核心航线计划网络")
                                .font(.subheadline)
                            Text("预置 5000+ 干线航班号、起降机场对与大圆航距")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("100% 离线就绪")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    }
                }

                // 4. 单位体系
                Section("航空计量单位制") {
                    Picker("单位制", selection: $unitSystem) {
                        Text("民航标准制 (FT, KTS, NM, hPa)").tag("aviation")
                        Text("公制 (米, 公里/小时, KM)").tag("metric")
                    }
                }

                // 5. 调试与缓存操作
                Section("系统维护与重置") {
                    Button(role: .destructive) {
                        dataManager.telemetryHistory.removeAll()
                        exportToastMessage = "已清空当前飞行缓存队列。"
                    } label: {
                        Text("清空当前航迹缓存")
                    }
                }

                // 6. 关于
                Section("关于“中国人能飞” (Chinese Can Fly)") {
                    LabeledContent("版本号", value: "1.0.0 (Build 2026.09)")
                    LabeledContent("硬件适配", value: "iPhone 14 Pro ~ 18 Pro (双频GNSS+6轴IMU)")
                    LabeledContent("代码仓库", value: "github.com/Erizeez/chinese-can-fly")
                }
            }
            .navigationTitle("设置与工具")
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheetView(activityItems: [url])
                }
            }
        }
    }

    private func exportFile(format: String) {
        if let fileURL = dataManager.exportCurrentFlight(format: format) {
            self.exportedFileURL = fileURL
            self.showShareSheet = true
            self.exportToastMessage = "已生成 \(format.uppercased()) 文件: \(fileURL.lastPathComponent)"
        }
    }
}

/// 系统分享面板包装器 (UIActivityViewController)
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
