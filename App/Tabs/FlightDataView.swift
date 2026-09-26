import SwiftUI
import CCFlyCore

/// 航班数据 Tab 页面
public struct FlightDataView: View {
    @State private var callsignInput: String = "CA1501"
    @State private var selectedTab: Int = 0
    @State private var currentFlight: FlightPlan = FlightPlan(
        callsign: "CA1501",
        airline: "中国国际航空 (Air China)",
        aircraftModel: "Airbus A350-941",
        departureIATA: "PEK",
        departureICAO: "ZBAA",
        arrivalIATA: "SHA",
        arrivalICAO: "ZSSS",
        distanceNM: 588.0,
        plannedCruiseAltitudeFt: 35000
    )

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 航班号快速检索卡片
                    VStack(alignment: .leading, spacing: 10) {
                        Text("航班计划检索 (支持离线库)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.blue)
                            TextField("输入航班号 (如 CA1501, MU5101)", text: $callsignInput)
                                .textInputAutocapitalization(.characters)
                            Button("查询") {
                                // 离线/在线多源检索
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.05), radius: 5)

                    // 航班基本信息卡片
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(currentFlight.callsign)
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                Text("\(currentFlight.airline) · \(currentFlight.aircraftModel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("已安排")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading) {
                                Text(currentFlight.departureIATA)
                                    .font(.system(size: 32, weight: .heavy))
                                Text(currentFlight.departureICAO)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("北京首都")
                                    .font(.footnote)
                            }
                            Spacer()
                            VStack {
                                Image(systemName: "airplane")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text("\(Int(currentFlight.distanceNM)) NM")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(currentFlight.arrivalIATA)
                                    .font(.system(size: 32, weight: .heavy))
                                Text(currentFlight.arrivalICAO)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("上海虹桥")
                                    .font(.footnote)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.05), radius: 5)

                    // 数据来源接入状态卡片
                    VStack(alignment: .leading, spacing: 12) {
                        Text("数据通道状态 (Data Link)")
                            .font(.headline)
                        
                        DataSourceStatusRow(
                            title: "本地离线航线数据库",
                            detail: "内置全国 5000+ 热门航班离线基线",
                            status: "可用 (100% 离线)",
                            isGreen: true
                        )
                        DataSourceStatusRow(
                            title: "OpenSky Network 在线 ADS-B",
                            detail: "全球开放科研航空网络",
                            status: "在线连接中",
                            isGreen: true
                        )
                        DataSourceStatusRow(
                            title: "极客便携 SDR / WiFi 接收机",
                            detail: "Dump1090 / GDL90 本地局域网广播",
                            status: "未配置 (可选)",
                            isGreen: false
                        )
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.05), radius: 5)
                }
                .padding()
            }
            .navigationTitle("航班数据")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct DataSourceStatusRow: View {
    let title: String
    let detail: String
    let status: String
    let isGreen: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isGreen ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                .foregroundStyle(isGreen ? .green : .secondary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
