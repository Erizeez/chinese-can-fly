import SwiftUI
import MapKit
import CCFlyCore

/// 离线地图与跑道对正视图 (极速冷启动渲染，无白屏无卡顿)
public struct OfflineMapView: View {
    @State private var dataManager = FlightDataManager.shared
    @State private var selectedAirport: Airport? = nil
    @State private var searchQuery: String = ""
    @State private var searchResults: [Airport] = []
    @State private var mapPosition: MapCameraPosition = .automatic

    // 默认精选干线机场列表 (快速离线展示，不占用首屏地图负载)
    private let quickAirports: [Airport] = AirportRepository.shared.getAllAirports()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. 真实地图视图 (轻量极速渲染)
                Map(position: $mapPosition) {
                    // 当前飞机物理位置标注 (带真航向箭头)
                    Annotation("当前飞机位置", coordinate: CLLocationCoordinate2D(latitude: dataManager.latitude, longitude: dataManager.longitude)) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.25))
                                .frame(width: 42, height: 42)
                            Image(systemName: "airplane")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .rotationEffect(.degrees(dataManager.groundTrackDeg - 90))
                        }
                    }

                    // 当前选中航班的大圆航线折线
                    if let flight = dataManager.currentFlight {
                        let dep = AirportRepository.shared.findAirport(code: flight.departureIATA)
                        let arr = AirportRepository.shared.findAirport(code: flight.arrivalIATA)
                        let waypoints = NavigationMath.generateGreatCircleWaypoints(
                            lat1: dep?.latitude ?? 39.9,
                            lon1: dep?.longitude ?? 116.4,
                            lat2: arr?.latitude ?? 31.2,
                            lon2: arr?.longitude ?? 121.4,
                            count: 20
                        )
                        let coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

                        MapPolyline(coordinates: coords)
                            .stroke(.cyan, lineWidth: 3)
                    }

                    // 聚焦选中的机场与跑道头标记
                    if let airport = selectedAirport {
                        Marker(airport.iata.isEmpty ? airport.icao : airport.iata, coordinate: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude))
                            .tint(.orange)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea(edges: .top)

                // 2. 悬浮底栏：机场搜索与跑道几何详情
                VStack(spacing: 8) {
                    // 快速搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("离线检索机场 (如 首都, 虹桥, ZBAA, PEK)", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .onChange(of: searchQuery) { _, query in
                                updateSearch(query: query)
                            }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                updateSearch(query: "")
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // 机场横向滚动卡片
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            let displayList = searchQuery.isEmpty ? Array(quickAirports.prefix(12)) : searchResults
                            ForEach(displayList) { airport in
                                Button {
                                    self.selectedAirport = airport
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        self.mapPosition = .region(MKCoordinateRegion(
                                            center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
                                            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                                        ))
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(airport.iata.isEmpty ? airport.icao : airport.iata)
                                                .font(.headline.monospaced())
                                                .foregroundStyle(selectedAirport?.ident == airport.ident ? .white : .blue)
                                            Spacer()
                                            Text("\(airport.runways.count) 跑道")
                                                .font(.caption2)
                                                .foregroundStyle(selectedAirport?.ident == airport.ident ? .white.opacity(0.8) : .secondary)
                                        }
                                        Text(airport.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(selectedAirport?.ident == airport.ident ? .white : .primary)
                                        Text("标高: \(Int(airport.elevationFt ?? 0)) ft · \(airport.municipality)")
                                            .font(.caption2)
                                            .foregroundStyle(selectedAirport?.ident == airport.ident ? .white.opacity(0.8) : .secondary)
                                    }
                                    .frame(width: 165)
                                    .padding(9)
                                    .background(selectedAirport?.ident == airport.ident ? Color.blue : Color(.secondarySystemBackground))
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
            .sheet(item: $selectedAirport) { airport in
                AirportRunwayDetailSheet(airport: airport)
            }
        }
    }

    private func updateSearch(query: String) {
        if query.isEmpty {
            searchResults = []
        } else {
            searchResults = AirportRepository.shared.searchAirports(query: query)
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

