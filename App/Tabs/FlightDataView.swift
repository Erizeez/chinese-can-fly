import SwiftUI
import CCFlyCore

/// 航班数据 Tab 页面 (完全数据驱动与多源检索)
public struct FlightDataView: View {
    @State private var dataManager = FlightDataManager.shared
    @State private var callsignInput: String = "CA1501"
    @State private var isSearchingOnline: Bool = false
    @State private var onlineResult: AirborneState? = nil
    @State private var onlineErrorMessage: String? = nil
    @State private var showWaypointsSheet: Bool = false

    // 推荐快速切换的经典干线与国产大飞机 C919 航班
    private let presetFlights = ["CA1501", "MU9191", "CZ3101", "3U8881", "HU7601"]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. 航班号离线快速检索栏
                    VStack(alignment: .leading, spacing: 10) {
                        Text("全离线国内干线检索 (输入即查)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.blue)
                            TextField("输入航班号 (如 CA1501, MU9191)", text: $callsignInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            
                            Button("查询") {
                                performOfflineLookup()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // 热门/推荐航线快捷胶囊
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(presetFlights, id: \.self) { callsign in
                                    Button(callsign) {
                                        callsignInput = callsign
                                        performOfflineLookup()
                                    }
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // 2. 当前选中航班真实计划卡片
                    if let flight = dataManager.currentFlight {
                        VStack(spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flight.callsign)
                                        .font(.system(size: 30, weight: .black, design: .monospaced))
                                    Text("\(flight.airline) · \(flight.aircraftModel)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("计划巡航 FL\(Int(flight.plannedCruiseAltitudeFt / 100))")
                                    .font(.caption.bold().monospaced())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flight.departureIATA)
                                        .font(.system(size: 34, weight: .heavy))
                                    Text(flight.departureICAO)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(getAirportCity(iata: flight.departureIATA))
                                        .font(.footnote)
                                }
                                Spacer()
                                VStack(spacing: 4) {
                                    Image(systemName: "airplane")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                    Text("\(Int(flight.distanceNM)) NM")
                                        .font(.caption2.bold().monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(flight.arrivalIATA)
                                        .font(.system(size: 34, weight: .heavy))
                                    Text(flight.arrivalICAO)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(getAirportCity(iata: flight.arrivalIATA))
                                        .font(.footnote)
                                }
                            }

                            Divider()

                            // 查看大圆航线导航点详情按钮
                            Button {
                                showWaypointsSheet = true
                            } label: {
                                Label("查看大圆航线与沿途离散航路点", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                    .font(.caption.bold())
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // 3. 在线真实 OpenSky 态势探测卡片
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("在线开放 ADS-B 态势 (OpenSky)")
                                .font(.headline)
                            Spacer()
                            Button {
                                fetchOnlineState()
                            } label: {
                                if isSearchingOnline {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("联网刷新", systemImage: "arrow.clockwise")
                                        .font(.caption2.bold())
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if let online = onlineResult {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("空中呼号: \(online.callsign)")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(online.onGround ? "地面滑行" : "空中巡航")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(online.onGround ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                                        .foregroundStyle(online.onGround ? .orange : .green)
                                        .clipShape(Capsule())
                                }
                                Text("真实地速: \(Int(online.velocityKts ?? 0)) KTS · 航向: \(Int(online.trueTrackDeg ?? 0))°")
                                    .font(.caption.monospaced())
                                if let baroAlt = online.baroAltitudeMeters {
                                    Text("ADS-B 气压高度: \(Int(baroAlt * 3.28084)) FT")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else if let error = onlineErrorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("点击“联网刷新”尝试从全球 OpenSky 开放接收基站探测该机当前空中广播报文。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .navigationTitle("航班数据")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showWaypointsSheet) {
                if let flight = dataManager.currentFlight {
                    WaypointsDetailSheet(flight: flight)
                }
            }
        }
    }

    private func performOfflineLookup() {
        if let found = OfflineFlightDatabase.shared.lookupFlight(callsign: callsignInput) {
            dataManager.currentFlight = found
            onlineResult = nil
            onlineErrorMessage = nil
        } else {
            onlineErrorMessage = "离线库暂未收录 \(callsignInput)，可通过搜索添加或在线刷新。"
        }
    }

    private func fetchOnlineState() {
        guard let flight = dataManager.currentFlight else { return }
        isSearchingOnline = true
        onlineErrorMessage = nil

        Task {
            do {
                let state = try await OpenSkyClient.shared.fetchFlightState(callsign: flight.callsign)
                await MainActor.run {
                    self.isSearchingOnline = false
                    if let state = state {
                        self.onlineResult = state
                        self.dataManager.activeFlightState = state
                    } else {
                        self.onlineErrorMessage = "当前 OpenSky 开放网络暂未捕获到呼号为 \(flight.callsign) 的实时信号 (可能未在空中起飞或处于雷达盲区)。"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSearchingOnline = false
                    self.onlineErrorMessage = "连接 OpenSky API 失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func getAirportCity(iata: String) -> String {
        return AirportRepository.shared.findAirport(code: iata)?.name ?? iata
    }
}

/// 大圆航线沿途航路点弹出抽屉
struct WaypointsDetailSheet: View {
    let flight: FlightPlan

    var body: some View {
        NavigationStack {
            let dep = AirportRepository.shared.findAirport(code: flight.departureIATA)
            let arr = AirportRepository.shared.findAirport(code: flight.arrivalIATA)
            let waypoints = NavigationMath.generateGreatCircleWaypoints(
                lat1: dep?.latitude ?? 39.9,
                lon1: dep?.longitude ?? 116.4,
                lat2: arr?.latitude ?? 31.2,
                lon2: arr?.longitude ?? 121.4,
                count: 15
            )

            List(waypoints) { wpt in
                HStack {
                    Text("航路点 #\(wpt.id + 1)")
                        .font(.subheadline.monospaced())
                    Spacer()
                    Text(String(format: "%.3f°N, %.3f°E", wpt.latitude, wpt.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("\(Int(wpt.distancePercent * 100))%")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                }
            }
            .navigationTitle("大圆航路插值点 (\(flight.callsign))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
