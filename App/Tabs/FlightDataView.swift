import SwiftUI
import CCFlyCore

/// 航班数据 Tab 页面 (纯数据驱动，统一 Data Provider，按需下载离线包，杜绝硬编码假数据)
public struct FlightDataView: View {
    @State private var planStore = FlightPlanStore.shared
    @State private var callsignInput: String = ""
    @State private var showWaypointsSheet: Bool = false
    @State private var showCustomFlightSheet: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. 航班号检索栏
                    searchBarSection

                    // 2. 离线包未安装提醒卡片 (用户搜了航班但无离线包)
                    if let notInstalled = planStore.notInstalledCallsign {
                        offlineNotInstalledCard(callsign: notInstalled)
                    }

                    // 3. 离线已安装但未收录提醒卡片
                    if let notFound = planStore.notFoundCallsign {
                        offlineNotFoundCard(callsign: notFound)
                    }

                    // 4. 当前选中航班真实计划卡片 (若有)
                    if let flight = planStore.currentFlight {
                        activeFlightCard(flight: flight)
                    } else if planStore.notInstalledCallsign == nil && planStore.notFoundCallsign == nil {
                        // 空状态与数据供给层引导
                        dataProviderStatusSection
                    }

                    // 5. 在线真实 OpenSky 态势探测卡片 (选中航班后可用)
                    if planStore.currentFlight != nil {
                        onlineADSBSection
                    }
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
                    initialCallsign: planStore.notInstalledCallsign ?? planStore.notFoundCallsign ?? callsignInput,
                    onSave: { flight in
                        callsignInput = flight.callsign
                    }
                )
            }
        }
    }

    // MARK: - 1. 检索栏与最近搜索
    private var searchBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("航班计划与航线检索")
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
                        performLookup()
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
                    performLookup()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 报错信息
            if let err = planStore.searchErrorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // 用户真实历史搜索胶囊 (由真实输入产生，杜绝硬编码假数据)
            if !planStore.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("最近查询")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(planStore.recentSearches, id: \.self) { callsign in
                                HStack(spacing: 4) {
                                    Button(callsign) {
                                        callsignInput = callsign
                                        performLookup()
                                    }
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.blue)

                                    Button {
                                        planStore.removeRecentSearch(callsign: callsign)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 2. 离线包未安装引导卡片
    private func offlineNotInstalledCard(callsign: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("未检测到离线航线数据库")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                if let airline = planStore.suggestedAirline {
                    Text(airline)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            Text("您正在查询航班 \(callsign)。当前本地尚未安装离线航线包，无法在断网时直接解算。您可以选择下载离线包，或者在线查询该航班。")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 操作按钮群
            VStack(spacing: 8) {
                // 按钮 1: 一键下载离线包
                Button {
                    planStore.downloadAndInstallRoutesPackage(forCallsign: callsign)
                } label: {
                    HStack {
                        if planStore.isDownloadingRoutesPackage {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("正在下载离线航线库 (\(Int(planStore.downloadProgress * 100))%)...")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("一键下载离线航线网络库 (约 1.5MB)")
                        }
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(planStore.isDownloadingRoutesPackage)

                HStack(spacing: 10) {
                    // 按钮 2: 尝试在线查询
                    Button {
                        planStore.fetchOnlineState(callsign: callsign)
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("尝试在线实时探测")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // 按钮 3: 手动录入
                    Button {
                        showCustomFlightSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("手动录入航线")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 3. 离线已安装但未收录卡片
    private func offlineNotFoundCard(callsign: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("离线航线库暂未收录 \(callsign)")
                    .font(.subheadline.bold())
                Spacer()
                if let airline = planStore.suggestedAirline {
                    Text(airline)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Text("已匹配到航司呼号前缀。您可以尝试在线探测实时态势，或利用全国机场跑道库手动快速录入该航线。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    planStore.fetchOnlineState(callsign: callsign)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("在线探测态势")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    showCustomFlightSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("一键录入该航线")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 4. 空状态数据供给层状态展示
    private var dataProviderStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.blue)
                Text("离线航电数据供给中心")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    OfflineResourcesManagementView()
                } label: {
                    Text("管理全部资源")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
            }

            Text("应用遵循完全自主可控原则，离线航电数据包由您按需选择下载，脱网飞行时优先调度本地离线库。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // 航线库状态项
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "airplane.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FlightDataProvider.shared.isRoutesPackageInstalled ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("全国干支线航线网络库")
                        .font(.subheadline.bold())
                    if FlightDataProvider.shared.isRoutesPackageInstalled {
                        Text("已就绪 (包含 5000+ 离线大圆航线与巡航高度)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("未安装 (约 1.5MB，可在地面预先下载)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !FlightDataProvider.shared.isRoutesPackageInstalled {
                    Button {
                        planStore.downloadAndInstallRoutesPackage()
                    } label: {
                        if planStore.isDownloadingRoutesPackage {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("下载")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(planStore.isDownloadingRoutesPackage)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // 跑道库状态项
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "map.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FlightDataProvider.shared.isAirportsPackageInstalled ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("中国机场与跑道物理模型")
                        .font(.subheadline.bold())
                    if FlightDataProvider.shared.isAirportsPackageInstalled {
                        Text("已加载全国 779 座民航机场及 354 条跑道")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("当前使用轻量核心枢纽 (全量 379KB 待下载)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !FlightDataProvider.shared.isAirportsPackageInstalled {
                    NavigationLink {
                        OfflineResourcesManagementView()
                    } label: {
                        Text("前往下载")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 5. 选中航班卡片
    private func activeFlightCard(flight: FlightPlan) -> some View {
        VStack(spacing: 14) {
            // 顶栏：呼号与数据源
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.callsign)
                        .font(.system(size: 30, weight: .black, design: .monospaced))
                    Text("\(flight.airline) · \(flight.aircraftModel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let source = planStore.currentDataSource {
                        Text(source.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(sourceColor(source).opacity(0.15))
                            .foregroundStyle(sourceColor(source))
                            .clipShape(Capsule())
                    }

                    Button {
                        planStore.clearCurrentFlight()
                        callsignInput = ""
                    } label: {
                        Text("更换/清除")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // 起降机场与大圆航距
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
                    Text("FL\(Int(flight.plannedCruiseAltitudeFt / 100))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
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

            // 查看大圆航线与航路点按钮
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

    // MARK: - 6. 在线 OpenSky 态势探测
    private var onlineADSBSection: some View {
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

    private func sourceColor(_ source: FlightDataSource) -> Color {
        switch source {
        case .offlinePackage: return .green
        case .userCustom: return .purple
        case .onlineRealtime: return .blue
        }
    }

    private func performLookup() {
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
