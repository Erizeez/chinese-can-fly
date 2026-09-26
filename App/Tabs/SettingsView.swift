import SwiftUI

/// 设置与系统配置 Tab 页面
public struct SettingsView: View {
    @AppStorage("sensorRate") private var sensorRate: Int = 50
    @AppStorage("unitSystem") private var unitSystem: String = "aviation"
    @AppStorage("autoBlackbox") private var autoBlackbox: Bool = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio: Bool = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("传感器融合与采样率") {
                    Picker("采样刷新率", selection: $sensorRate) {
                        Text("50 Hz (极客高精/着陆黑匣)").tag(50)
                        Text("10 Hz (平衡模式)").tag(10)
                        Text("1 Hz (长途超低功耗)").tag(1)
                    }
                    Toggle("自动识别飞行阶段调整采样率", isOn: $autoBlackbox)
                    Toggle("起降关键阶段启用微音保活通道", isOn: $keepAliveAudio)
                }

                Section("离线数据包管理") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("中国区域机场与跑道数据库")
                                .font(.subheadline)
                            Text("包含 250+ 运输机场、400+ 通航跑道参数 (OurAirports)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("已安装 (v2026.09)")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("离线全国矢量底图 (省界与水系)")
                                .font(.subheadline)
                            Text("MapLibre 离线切片 (MBTiles)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("检查更新") {}
                            .font(.caption)
                    }
                }

                Section("计量单位体系") {
                    Picker("单位制", selection: $unitSystem) {
                        Text("民航标准制 (FT, KTS, NM, hPa)").tag("aviation")
                        Text("国际公制 (米, 公里/小时, KM)").tag("metric")
                    }
                }

                Section("黑匣子飞行日志导出") {
                    Button {
                        // 导出 GPX
                    } label: {
                        Label("导出 GPX 轨迹 (适配 Google Earth / 两步路)", systemImage: "arrow.down.doc")
                    }

                    Button {
                        // 导出 KML 3D
                    } label: {
                        Label("导出 3D KML 彩色高度轨迹", systemImage: "map")
                    }

                    Button {
                        // 导出 CSV
                    } label: {
                        Label("导出 50Hz 原始传感器 CSV (用于科研分析)", systemImage: "tablecells")
                    }
                }

                Section("关于“中国人能飞”") {
                    LabeledContent("版本号", value: "1.0.0 (Build 2026.09)")
                    LabeledContent("设计理念", value: "纯端侧 · 全离线 · 航空级传感器融合")
                    LabeledContent("GitHub", value: "Erizeez/chinese-can-fly")
                }
            }
            .navigationTitle("设置与工具")
        }
    }
}
