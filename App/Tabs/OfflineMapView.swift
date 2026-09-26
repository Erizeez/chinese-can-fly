import SwiftUI
import CCFlyCore

/// 离线地图与机场跑道 Tab 页面
public struct OfflineMapView: View {
    @State private var selectedAirport: Airport? = nil
    @State private var showAirportSheet: Bool = false
    @State private var sampleAirports: [Airport] = [
        Airport(ident: "ZBAA", icao: "ZBAA", iata: "PEK", name: "北京首都国际机场", municipality: "北京", latitude: 40.080111, longitude: 116.584556, elevationFt: 116.0, runways: [
            Runway(id: "01-19", lengthFt: 12467, widthFt: 197, surface: "ASP", leIdent: "01", leHeadingDegT: 7.0, heIdent: "19", heHeadingDegT: 187.0),
            Runway(id: "18L-36R", lengthFt: 12467, widthFt: 197, surface: "CON", leIdent: "18L", leHeadingDegT: 178.0, heIdent: "36R", heHeadingDegT: 358.0)
        ]),
        Airport(ident: "ZSSS", icao: "ZSSS", iata: "SHA", name: "上海虹桥国际机场", municipality: "上海", latitude: 31.197875, longitude: 121.336319, elevationFt: 10.0, runways: [
            Runway(id: "18L-36R", lengthFt: 10827, widthFt: 148, surface: "ASP", leIdent: "18L", leHeadingDegT: 180.0, heIdent: "36R", heHeadingDegT: 360.0)
        ]),
        Airport(ident: "ZGGG", icao: "ZGGG", iata: "CAN", name: "广州白云国际机场", municipality: "广州", latitude: 23.392400, longitude: 113.298800, elevationFt: 50.0, runways: [
            Runway(id: "02L-20R", lengthFt: 12467, widthFt: 197, surface: "CON", leIdent: "02L", leHeadingDegT: 20.0, heIdent: "20R", heHeadingDegT: 200.0)
        ])
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 离线地图画布 (底层对接 MapLibre Native 矢量切片)
                ZStack {
                    Color(red: 0.10, green: 0.12, blue: 0.16) // 航空夜盘暗黑风格
                        .ignoresSafeArea()

                    // 离线地图网格与模拟航迹
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("离线矢量模式 (MapLibre Metal)", systemImage: "antenna.radiowaves.left.and.right.slash")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                                Text("全国省界、主要水系及机场跑道 100% 离线就绪")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 120)
                    }
                }

                // 悬浮机场与跑道快速查看抽屉
                VStack(alignment: .leading, spacing: 10) {
                    Text("核心机场与跑道要素 (离线库)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(sampleAirports) { airport in
                                Button {
                                    self.selectedAirport = airport
                                    self.showAirportSheet = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(airport.iata)
                                                .font(.headline.monospaced())
                                                .foregroundStyle(.blue)
                                            Spacer()
                                            Text("\(airport.runways.count) 条跑道")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(airport.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Text("标高: \(Int(airport.elevationFt ?? 0)) ft · \(airport.municipality)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 170)
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 10, y: -5)
            }
            .navigationTitle("离线地图与跑道")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAirport) { airport in
                AirportDetailSheet(airport: airport)
            }
        }
    }
}

/// 机场跑道几何详情弹出卡片
struct AirportDetailSheet: View {
    let airport: Airport

    var body: some View {
        NavigationStack {
            List {
                Section("机场基本信息") {
                    LabeledContent("ICAO / IATA", value: "\(airport.icao) / \(airport.iata)")
                    LabeledContent("名称", value: airport.name)
                    LabeledContent("坐标", value: String(format: "%.4f, %.4f", airport.latitude, airport.longitude))
                    LabeledContent("机场标高", value: "\(Int(airport.elevationFt ?? 0)) 英尺 (MSL)")
                }

                Section("跑道配置与对正参数 (Runways)") {
                    ForEach(airport.runways) { rwy in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("跑道 \(rwy.leIdent) / \(rwy.heIdent)")
                                    .font(.headline)
                                Spacer()
                                Text(rwy.surface ?? "道面未标")
                                    .font(.caption2.bold())
                                    .padding(4)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            HStack {
                                Label("长: \(Int(rwy.lengthFt ?? 0)) ft", systemImage: "arrow.up.and.down")
                                Spacer()
                                Label("宽: \(Int(rwy.widthFt ?? 0)) ft", systemImage: "arrow.left.and.right")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Text("\(rwy.leIdent) 端真航向: \(Int(rwy.leHeadingDegT ?? 0))°")
                                Spacer()
                                Text("\(rwy.heIdent) 端真航向: \(Int(rwy.heHeadingDegT ?? 0))°")
                            }
                            .font(.caption2.monospaced())
                            .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(airport.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
