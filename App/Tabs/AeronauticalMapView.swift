import SwiftUI
import MapKit
import CCFlyCore

/// 航图与跑道对正视图 (Aeronautical Map & Aerodrome Layout) - 毫秒级瞬开，零卡顿
public struct AeronauticalMapView: View {
    @State private var planStore = FlightPlanStore.shared
    @State private var dataManager = FlightDataManager.shared
    @State private var selectedAirport: Airport? = nil
    @State private var searchQuery: String = ""
    @State private var searchResults: [Airport] = []

    // 初始航图摄像机平滑聚焦在飞机位置或默认中心，避免 automatic 跨全国全量计算卡死
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: 116.4),
        span: MKCoordinateSpan(latitudeDelta: 1.8, longitudeDelta: 1.8)
    ))

    // 预计算的大圆航线坐标点 (缓存)，避免在 Map 闭包内高频重复三角函数运算
    @State private var cachedRouteCoords: [CLLocationCoordinate2D] = []

    // 快速干线机场列表 (非全量)，首屏零耗时
    @State private var displayedAirports: [Airport] = []

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. 真实航图视图 (标准离线平面渲染，轻量极速)
                Map(position: $mapPosition) {
                    // 当前飞机物理位置标注 (带真实航向指示)
                    Annotation("当前飞机位置", coordinate: CLLocationCoordinate2D(latitude: dataManager.latitude, longitude: dataManager.longitude)) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 44, height: 44)
                            Image(systemName: "airplane")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .rotationEffect(.degrees(dataManager.groundTrackDeg - 90))
                        }
                    }

                    // 缓存的大圆航线折线 (直接使用已计算坐标数组)
                    if !cachedRouteCoords.isEmpty {
                        MapPolyline(coordinates: cachedRouteCoords)
                            .stroke(.cyan, lineWidth: 3.5)
                    }

                    // 聚焦选中的机场与跑道头标记
                    if let airport = selectedAirport {
                        Marker(airport.iata.isEmpty ? airport.icao : airport.iata, coordinate: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude))
                            .tint(.orange)
                    }
                }
                .mapStyle(.standard)
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
                            let displayList = searchQuery.isEmpty ? displayedAirports : searchResults
                            ForEach(displayList) { airport in
                                Button {
                                    self.selectedAirport = airport
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        self.mapPosition = .region(MKCoordinateRegion(
                                            center: CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude),
                                            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
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
            .navigationTitle("航图与跑道")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAirport) { airport in
                AirportRunwayDetailSheet(airport: airport)
            }
            .onAppear {
                setupInitialData()
            }
            .onChange(of: planStore.currentFlight?.callsign) { _, _ in
                recomputeFlightRoute()
            }
        }
    }

    private func setupInitialData() {
        if displayedAirports.isEmpty {
            // 首屏直接展示快速缓存，完全不阻塞主线程
            displayedAirports = Array(AirportRepository.shared.getAllAirports().prefix(15))
        }
        recomputeFlightRoute()
    }

    private func recomputeFlightRoute() {
        guard let flight = planStore.currentFlight else {
            cachedRouteCoords = []
            return
        }

        Task.detached(priority: .userInitiated) {
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

            await MainActor.run {
                self.cachedRouteCoords = coords
            }
        }
    }

    private func updateSearch(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        Task.detached(priority: .userInitiated) {
            let results = AirportRepository.shared.searchAirports(query: query)
            await MainActor.run {
                self.searchResults = results
            }
        }
    }
}

/// 机场跑道详细信息卡片抽屉 (展开物理走向与材质)
struct AirportRunwayDetailSheet: View {
    let airport: Airport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("机场基本信息") {
                    LabeledContent("ICAO / IATA", value: "\(airport.icao) / \(airport.iata.isEmpty ? "无" : airport.iata)")
                    LabeledContent("名称", value: airport.name)
                    LabeledContent("城市 / 地区", value: "\(airport.municipality), 中国")
                    LabeledContent("场面基准标高", value: "\(Int(airport.elevationFt ?? 0)) FT")
                    LabeledContent("地理坐标", value: String(format: "%.4f°N, %.4f°E", airport.latitude, airport.longitude))
                }

                Section("真实跑道物理几何 (\(airport.runways.count) 条)") {
                    if airport.runways.isEmpty {
                        Text("暂无跑道物理数据或为水上/直升机起降点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(airport.runways) { rwy in
                            AirportRunwayRowView(rwy: rwy)
                        }
                    }
                }
            }
            .navigationTitle(airport.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 单条跑道几何行视图 (独立类型拆分，优化 Swift 编译时性能)
struct AirportRunwayRowView: View {
    let rwy: Runway

    private var surfaceText: String {
        if let s = rwy.surface, !s.isEmpty {
            return s
        }
        return "沥青/混凝土"
    }

    private var dimensionsText: String {
        let lengthInt = Int(rwy.lengthFt ?? 0)
        let widthInt = Int(rwy.widthFt ?? 0)
        return "\(lengthInt) × \(widthInt) FT"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("跑道 \(rwy.leIdent) / \(rwy.heIdent)")
                    .font(.headline.monospaced())
                    .foregroundStyle(.blue)
                Spacer()
                Text(dimensionsText)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack {
                Text("道面: \(surfaceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let heading = rwy.leHeadingDegT {
                    let reciprocal = Int((heading + 180).truncatingRemainder(dividingBy: 360))
                    Text("真航向: \(Int(heading))° / \(reciprocal)°")
                        .font(.caption2.monospaced())
                }
            }

            if let leAlt = rwy.leElevationFt {
                Text("跑道头标高: \(Int(leAlt)) ft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
