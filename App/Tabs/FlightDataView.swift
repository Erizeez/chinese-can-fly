import SwiftUI
import CCFlyCore

/// 航班数据 Tab 页面 (纯数据驱动，完全解耦高频传感器，保证搜索输入丝滑零卡顿)
public struct FlightDataView: View {
    @State private var planStore = FlightPlanStore.shared
    @State private var callsignInput: String = "MU6594"
    @State private var showWaypointsSheet: Bool = false
    @State private var showCustomFlightSheet: Bool = false

    // 推荐快速切换的经典干线、特色支线 (含用户常查的 MU6594) 与国产大飞机 C919 航班
    private let presetFlights = ["MU6594", "CA1501", "MU9191", "CZ3101", "3U8881", "HU7601"]

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
                            
                            TextField("输入航班号 (如 MU6594, CA1501)", text: $callsignInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit {
                                    performOfflineLookup()
                                }
                            
                            if !callsignInput.isEmpty {
                                Button {
                                    callsignInput = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Button("查询") {
                                performOfflineLookup()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // 未收录时的引导与快捷录入卡片
                        if let notFound = planStore.notFoundCallsign {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("离线推荐库暂未收录 \(notFound)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                }
                                
                                let airline = OfflineFlightDatabase.detectAirline(callsign: notFound)
                                Text("已智能识别呼号航司：\(airline)。您可以快速录入该航线，系统将自动利用 779 座全国机场跑道库解算大圆航距与航路点，并持久化到本地。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Button {
                                    showCustomFlightSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("一键录入 \(notFound) 航班航线")
                                    }
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

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
                    if let flight = planStore.currentFlight {
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
                                    Text(planStore.getCityName(iata: flight.departureIATA))
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
                                    Text(planStore.getCityName(iata: flight.arrivalIATA))
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
                                planStore.fetchOnlineState()
                            } label: {
                                if planStore.isSearchingOnline {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("联网刷新", systemImage: "arrow.clockwise")
                                        .font(.caption2.bold())
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if let online = planStore.activeFlightState {
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
                        } else if let error = planStore.onlineErrorMessage {
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
                if let flight = planStore.currentFlight {
                    WaypointsDetailSheet(flight: flight)
                }
            }
            .sheet(isPresented: $showCustomFlightSheet) {
                CustomFlightEntrySheet(
                    initialCallsign: planStore.notFoundCallsign ?? callsignInput,
                    onSave: { flight in
                        callsignInput = flight.callsign
                    }
                )
            }
        }
    }

    private func performOfflineLookup() {
        _ = planStore.selectFlight(callsign: callsignInput)
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

/// 用户自定义录入航线计划表单
struct CustomFlightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialCallsign: String
    var onSave: ((FlightPlan) -> Void)? = nil

    @State private var callsign: String = ""
    @State private var airline: String = ""
    @State private var departureIATA: String = "SQJ"
    @State private var arrivalIATA: String = "SHA"
    @State private var aircraftModel: String = "Boeing 737-800"
    @State private var cruiseAltFt: Double = 28000
    @State private var errorMessage: String? = nil

    private let commonModels = [
        "Boeing 737-800", "Airbus A320neo", "Airbus A321neo",
        "Airbus A350-900", "Boeing 787-9", "COMAC C919",
        "Airbus A330-300", "Boeing 777-300ER", "ARJ21-700"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("航班基本信息") {
                    HStack {
                        Text("航班号")
                            .frame(width: 80, alignment: .leading)
                        TextField("如 MU6594", text: $callsign)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: callsign) { _, newV in
                                airline = OfflineFlightDatabase.detectAirline(callsign: newV)
                            }
                    }
                    HStack {
                        Text("航空公司")
                            .frame(width: 80, alignment: .leading)
                        TextField("如 中国东方航空", text: $airline)
                    }
                }

                Section("起降机场 (三字码/ICAO)") {
                    HStack {
                        Text("起飞机场")
                            .frame(width: 80, alignment: .leading)
                        TextField("如 SQJ (三明沙县)", text: $departureIATA)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("到达机场")
                            .frame(width: 80, alignment: .leading)
                        TextField("如 SHA (上海虹桥)", text: $arrivalIATA)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }

                Section("巡航力学与机型") {
                    Picker("执飞机型", selection: $aircraftModel) {
                        ForEach(commonModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    HStack {
                        Text("计划巡航高度")
                        Spacer()
                        Text("FL\(Int(cruiseAltFt / 100)) (\(Int(cruiseAltFt)) FT)")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.blue)
                    }
                    Slider(value: $cruiseAltFt, in: 10000...41000, step: 1000)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("录入自定义航班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并载入") {
                        saveFlight()
                    }
                    .bold()
                }
            }
            .onAppear {
                callsign = initialCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                airline = OfflineFlightDatabase.detectAirline(callsign: callsign)
            }
        }
    }

    private func saveFlight() {
        let cleanCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDep = departureIATA.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanArr = arrivalIATA.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !cleanCallsign.isEmpty else {
            errorMessage = "请输入有效的航班号"
            return
        }
        guard !cleanDep.isEmpty && !cleanArr.isEmpty else {
            errorMessage = "请输入起降机场三字码"
            return
        }

        FlightPlanStore.shared.addCustomFlightAndSelect(
            callsign: cleanCallsign,
            airline: airline,
            dep: cleanDep,
            arr: cleanArr,
            model: aircraftModel,
            alt: cruiseAltFt
        )

        if let current = FlightPlanStore.shared.currentFlight {
            onSave?(current)
        }
        dismiss()
    }
}

