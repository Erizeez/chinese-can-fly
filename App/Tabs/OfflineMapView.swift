import SwiftUI
import MapKit
import CCFlyCore

/// 离线地图与机场跑道视图 (基于 MapKit 原生离线渲染与真实 779 座机场数据库)
public struct OfflineMapView: View {
    @State private var dataManager = FlightDataManager.shared
    @State private var allAirports: [Airport] = []
    @State private var selectedAirport: Airport? = nil
    @State private var searchQuery: String = ""
    @State private var mapPosition: MapCameraPosition = .automatic

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. 真实地图视图
                Map(position: $mapPosition) {
                    // 标记当前飞机实时位置
                    Annotation("当前飞机位置", coordinate: CLLocationCoordinate2D(latitude: dataManager.latitude, longitude: dataManager.longitude)) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 44, height: 44)
                            Image(systemName: "airplane")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .rotationEffect(.degrees(dataManager.groundTrackDeg - 90))
                        }
                    }

                    // 标记当前航班的大圆航线
                    if let flight = dataManager.currentFlight {
                        let dep = AirportRepository.shared.findAirport(code: flight.departureIATA)
                        let arr = AirportRepository.shared.findAirport(code: flight.arrivalIATA)
                        let waypoints = NavigationMath.generateGreatCircleWaypoints(
                            lat1: dep?.latitude ?? 39.9,
                            lon1: dep?.longitude ?? 116.4,
                            lat2: arr?.latitude ?? 31.2,
                            lon2: arr?.longitude ?? 121.4,
                            count: 25
                        )
                        let coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

                        MapPolyline(coordinates: coords)
                            .stroke(.cyan, lineWidth: 3)
                    }

                    // 标记全国主要机场点位 (展示前 40 个或搜索匹配的机场)
                    ForEach(filteredAirports.prefix(40)) { airport in
                        Marker(airport.iata.isEmpty ? airport.icao : airport.iata, coordinate: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude))
                            .tint(.orange)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea(edges: .top)

                // 2. 悬浮底栏：机场跑道快速检索与详情面板
                VStack(spacing: 10) {
                    // 搜索框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索全国 779 座机场/跑道 (如 首都, 虹桥, ZBAA)", text: $searchQuery)
                            .textFieldStyle(.plain)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 水平机场滚动卡片
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filteredAirports.prefix(15)) { airport in
                                Button {
                                    self.selectedAirport = airport
                                    withAnimation {
                                        self.mapPosition = .region(MKCoordinateRegion(
                                            center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
                                            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                                        ))
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(airport.iata.isEmpty ? airport.icao : airport.iata)
                                                .font(.headline.monospaced())
                                                .foregroundStyle(.blue)
                                            Spacer()
                                            Text("\(airport.runways.count) 跑道")
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
                .background(.ultraThinMaterial)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 8, y: -4)
            }
            .navigationTitle("离线地图与跑道")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                self.allAirports = AirportRepository.shared.getAllAirports()
            }
            .sheet(item: $selectedAirport) { airport in
                AirportRunwayDetailSheet(airport: airport)
            }
        }
    }

    private var filteredAirports: [Airport] {
        if searchQuery.isEmpty {
            return allAirports
        } else {
            return AirportRepository.shared.searchAirports(query: searchQuery)
        }
    }
}

/// 机场真实跑道几何与盲降延长线参数详情
struct AirportRunwayDetailSheet: View {
    let airport: Airport

    var body: some View {
        NavigationStack {
            List {
                Section("机场概要 (OurAirports 离线库)") {
                    LabeledContent("ICAO / IATA 代码", value: "\(airport.icao) / \(airport.iata.isEmpty ? "无" : airport.iata)")
                    LabeledContent("中文全称", value: airport.name)
                    LabeledContent("所在城市", value: airport.municipality)
                    LabeledContent("基准坐标", value: String(format: "%.4f°N, %.4f°E", airport.latitude, airport.longitude))
                    LabeledContent("场面标高", value: "\(Int(airport.elevationFt ?? 0)) 英尺 (MSL)")
                }

                Section("真实跑道物理参数与真航向 (共 \(airport.runways.count) 条)") {
                    if airport.runways.isEmpty {
                        Text("该机场为通航起降点，暂未配置标准化硬化跑道。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(airport.runways) { rwy in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("跑道 \(rwy.leIdent) / \(rwy.heIdent)")
                                        .font(.headline.monospaced())
                                    Spacer()
                                    Text(rwy.surface ?? "道面材质")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                HStack {
                                    Text("长: \(Int(rwy.lengthFt ?? 0)) ft (\(Int((rwy.lengthFt ?? 0) * 0.3048))m)")
                                    Spacer()
                                    Text("宽: \(Int(rwy.widthFt ?? 0)) ft (\(Int((rwy.widthFt ?? 0) * 0.3048))m)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Divider()

                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(rwy.leIdent) 跑道头")
                                            .font(.caption2.bold())
                                        Text("真航向: \(Int(rwy.leHeadingDegT ?? 0))°")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("\(rwy.heIdent) 跑道头")
                                            .font(.caption2.bold())
                                        Text("真航向: \(Int(rwy.heHeadingDegT ?? 0))°")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(airport.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
