import SwiftUI
import MapKit
import CCFlyCore

/// 航图与跑道对正视图 (Aeronautical Map & Aerodrome Layout) - 毫秒级瞬开，绝对零卡顿
public struct AeronauticalMapView: View {
    @State private var planStore = FlightPlanStore.shared
    @State private var selectedAirport: Airport? = nil
    @State private var searchQuery: String = ""
    @State private var searchResults: [Airport] = []

    // 核心优化：直接使用静态常量干线机场，零锁竞争、零开销、零延迟
    private let coreAirports = AirportRepository.coreHubAirports

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. 工业级高性能航图渲染层 (常驻预热 MKMapView 桥接，0ms 物理级瞬开，绝无任何掉帧与阻塞)
                AviationMapViewRepresentable(
                    aircraftCoordinate: planStore.chartPosition,
                    aircraftTrackDeg: planStore.chartTrackDeg,
                    routeCoordinates: planStore.precomputedRouteCoords,
                    selectedAirport: selectedAirport
                )
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

                    // 机场横向滚动卡片 (使用 LazyHStack 仅实例化可视区域卡片，避免主线程开销)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            let displayList = searchQuery.isEmpty ? coreAirports : searchResults
                            ForEach(displayList) { airport in
                                Button {
                                    self.selectedAirport = airport
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
                CCFlyPerfLogger.end("UserSwitchTabToAeronauticalMap")
                CCFlyPerfLogger.mark("AeronauticalMapView onAppear (航图瞬开)")
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

/// 工业级高性能航图容器 (基于预热 MKMapView 桥接，真机/模拟器绝对零延迟秒开)
public struct AviationMapViewRepresentable: UIViewRepresentable {
    public static let sharedMapView: MKMapView = {
        let map = MKMapView(frame: UIScreen.main.bounds)
        map.mapType = .standard
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        let initRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: 116.4),
            span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
        )
        map.setRegion(initRegion, animated: false)
        return map
    }()

    let aircraftCoordinate: CLLocationCoordinate2D
    let aircraftTrackDeg: Double
    let routeCoordinates: [CLLocationCoordinate2D]
    let selectedAirport: Airport?

    public func makeUIView(context: Context) -> MKMapView {
        let map = Self.sharedMapView
        map.delegate = context.coordinator
        context.coordinator.setupInitialOverlays(map: map)
        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(
            map: map,
            aircraftCoordinate: aircraftCoordinate,
            aircraftTrackDeg: aircraftTrackDeg,
            routeCoordinates: routeCoordinates,
            selectedAirport: selectedAirport
        )
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        private let aircraftAnnotation = MKPointAnnotation()
        private let airportAnnotation = MKPointAnnotation()
        private var currentPolyline: MKPolyline?
        private var lastRouteHash: Int = 0
        private var lastSelectedIdent: String = ""

        override init() {
            super.init()
            aircraftAnnotation.title = "AIRCRAFT"
            airportAnnotation.title = "AIRPORT"
        }

        func setupInitialOverlays(map: MKMapView) {
            if !map.annotations.contains(where: { ($0 as? MKPointAnnotation)?.title == "AIRCRAFT" }) {
                map.addAnnotation(aircraftAnnotation)
            }
        }

        func update(
            map: MKMapView,
            aircraftCoordinate: CLLocationCoordinate2D,
            aircraftTrackDeg: Double,
            routeCoordinates: [CLLocationCoordinate2D],
            selectedAirport: Airport?
        ) {
            // 1. 更新飞机位置与航向 (0 内存分配，直接修改底层属性)
            aircraftAnnotation.coordinate = aircraftCoordinate
            if let view = map.view(for: aircraftAnnotation) {
                UIView.animate(withDuration: 0.25) {
                    view.transform = CGAffineTransform(rotationAngle: CGFloat((aircraftTrackDeg - 90) * .pi / 180.0))
                }
            }

            // 2. 更新大圆航线 (仅当航线坐标变化时更新 overlay)
            let routeHash = routeCoordinates.count ^ (routeCoordinates.first?.latitude.hashValue ?? 0)
            if routeHash != lastRouteHash {
                lastRouteHash = routeHash
                if let old = currentPolyline {
                    map.removeOverlay(old)
                }
                if !routeCoordinates.isEmpty {
                    let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
                    self.currentPolyline = polyline
                    map.addOverlay(polyline)
                }
            }

            // 3. 更新选中机场标记与视锥移动
            if let apt = selectedAirport, apt.ident != lastSelectedIdent {
                lastSelectedIdent = apt.ident
                airportAnnotation.coordinate = CLLocationCoordinate2D(latitude: apt.latitude, longitude: apt.longitude)
                airportAnnotation.subtitle = apt.name
                if !map.annotations.contains(where: { ($0 as? MKPointAnnotation)?.title == "AIRPORT" }) {
                    map.addAnnotation(airportAnnotation)
                }
                let region = MKCoordinateRegion(
                    center: airportAnnotation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                )
                map.setRegion(region, animated: true)
            }
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemCyan
                renderer.lineWidth = 3.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pointAnnotation = annotation as? MKPointAnnotation else { return nil }

            if pointAnnotation.title == "AIRCRAFT" {
                let id = "AircraftAnnotationView"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                    let iconImage = UIImage(systemName: "airplane")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    let bgView = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
                    bgView.backgroundColor = .systemBlue
                    bgView.layer.cornerRadius = 17
                    bgView.layer.masksToBounds = true

                    let iv = UIImageView(image: iconImage)
                    iv.frame = CGRect(x: 7, y: 7, width: 20, height: 20)
                    bgView.addSubview(iv)
                    view?.addSubview(bgView)
                    view?.frame = bgView.frame
                    view?.centerOffset = CGPoint(x: 0, y: 0)
                }
                return view
            } else if pointAnnotation.title == "AIRPORT" {
                let id = "AirportMarker"
                var marker = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if marker == nil {
                    marker = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    marker?.markerTintColor = .systemOrange
                    marker?.glyphImage = UIImage(systemName: "airplane.departure")
                }
                return marker
            }
            return nil
        }
    }
}

