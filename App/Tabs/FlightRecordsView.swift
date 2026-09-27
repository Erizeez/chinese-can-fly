import SwiftUI
import Charts
import CCFlyCore

/// 飞行记录与日志本视图 (支持按时间时序、按航班号聚合、按航线起降地聚合及批量管理导出)
public struct FlightRecordsView: View {
    @State private var recordStore = FlightRecordStore.shared
    @State private var aggregationMode: AggregationMode = .timeline
    @State private var isEditing: Bool = false
    @State private var selectedRecordIDs: Set<UUID> = []
    @State private var showDeleteConfirm: Bool = false
    @State private var targetRecordForExport: FlightRecord? = nil
    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet: Bool = false

    public enum AggregationMode: String, CaseIterable, Identifiable {
        case timeline = "时间时序"
        case byCallsign = "按航班号"
        case byRoute = "按航线"
        public var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. 顶部聚合模式切换分段器
                Picker("展示模式", selection: $aggregationMode) {
                    ForEach(AggregationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))

                // 2. 列表内容
                if recordStore.records.isEmpty {
                    emptyRecordsPlaceholder
                } else {
                    List(selection: $selectedRecordIDs) {
                        // 顶部统计看板
                        if !isEditing {
                            Section {
                                statisticsSummaryHeader
                            }
                        }

                        // 根据聚合模式渲染
                        switch aggregationMode {
                        case .timeline:
                            timelineSection
                        case .byCallsign:
                            callsignGroupedSection
                        case .byRoute:
                            routeGroupedSection
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                }

                // 3. 批量删除底部操作栏 (在编辑模式下呈现)
                if isEditing && !recordStore.records.isEmpty {
                    VStack(spacing: 8) {
                        Divider()
                        HStack {
                            Text("已选择 \(selectedRecordIDs.count) 条记录")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("删除所选", systemImage: "trash.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(selectedRecordIDs.isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                    }
                    .background(Color(.secondarySystemBackground))
                }
            }
            .navigationTitle("飞行记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !recordStore.records.isEmpty {
                        Button(isEditing ? "完成" : "批量管理") {
                            isEditing.toggle()
                            if !isEditing {
                                selectedRecordIDs.removeAll()
                            }
                        }
                        .font(.subheadline.bold())
                    }
                }
            }
            .confirmationDialog("确定删除选中的 \(selectedRecordIDs.count) 条飞行记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    recordStore.deleteRecords(ids: selectedRecordIDs)
                    selectedRecordIDs.removeAll()
                    isEditing = false
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后对应的本地遥测轨迹与黑匣子采样点将被彻底移除。")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    // MARK: - 统计看板

    private var statisticsSummaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("累计飞行总计")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(recordStore.records.count) 架次")
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                Spacer()
                let totalMin = recordStore.records.reduce(0) { $0 + $1.durationMinutes }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计巡航时长")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(totalMin / 60)h \(totalMin % 60)m")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 模式 1: 时间倒序时序列表

    private var timelineSection: some View {
        Section("所有飞行记录 (\(recordStore.records.count))") {
            ForEach(recordStore.records) { record in
                NavigationLink {
                    FlightRecordDetailView(record: record)
                } label: {
                    FlightRecordRowView(record: record)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        recordStore.deleteRecord(id: record.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        exportSingle(record: record, format: "gpx")
                    } label: {
                        Label("导出GPX", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
        }
    }

    // MARK: - 模式 2: 按航班号聚合列表

    private var callsignGroupedSection: some View {
        let groups = recordStore.recordsGroupedByCallsign()
        return ForEach(groups, id: \.callsign) { group in
            Section {
                ForEach(group.records) { record in
                    NavigationLink {
                        FlightRecordDetailView(record: record)
                    } label: {
                        FlightRecordRowView(record: record)
                    }
                }
            } header: {
                HStack {
                    Text(group.callsign)
                        .font(.headline.monospaced())
                        .foregroundStyle(.blue)
                    Text("· \(group.records.count) 次执飞")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isEditing {
                        Button(role: .destructive) {
                            recordStore.deleteRecordsByCallsign(callsign: group.callsign)
                        } label: {
                            Text("删除该航班")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 模式 3: 按航线起降对聚合列表

    private var routeGroupedSection: some View {
        let groups = recordStore.recordsGroupedByRoute()
        return ForEach(groups, id: \.route) { group in
            Section {
                ForEach(group.records) { record in
                    NavigationLink {
                        FlightRecordDetailView(record: record)
                    } label: {
                        FlightRecordRowView(record: record)
                    }
                }
            } header: {
                HStack {
                    Text(group.route)
                        .font(.headline.monospaced())
                        .foregroundStyle(.blue)
                    Text("(\(group.departureCity) ➔ \(group.arrivalCity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(group.records.count) 次")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyRecordsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("暂无飞行记录")
                .font(.headline)
            Text("在【飞行数据】中点击“开始全航程记录”，飞行结束停止后将在此自动归档完整的黑匣子轨迹与力学报告。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func exportSingle(record: FlightRecord, format: String) {
        if let url = recordStore.exportRecordFile(recordId: record.id, format: format) {
            self.exportedFileURL = url
            self.showShareSheet = true
        }
    }
}

/// 飞行记录单行卡片视图
struct FlightRecordRowView: View {
    let record: FlightRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.callsign)
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                Spacer()
                Text(record.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(record.routeString)
                    .font(.subheadline.bold().monospaced())
                    .foregroundStyle(.blue)
                Text("(\(record.cityPairString))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(record.durationMinutes) 分钟")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(record.aircraftModel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let rating = record.touchdownRating {
                    Text(rating)
                        .font(.caption2.bold())
                        .foregroundStyle(rating.contains("Butter") ? .green : .blue)
                }

                Spacer()

                Text("FL\(Int(record.maxAltitudeFt / 100)) · \(Int(record.maxSpeedKts)) kts")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 单次航班详细力学报告与针对性导出页面
struct FlightRecordDetailView: View {
    let record: FlightRecord
    @State private var frames: [TelemetryFrame] = []
    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportToast: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 航班主卡片
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.callsign)
                                .font(.system(size: 32, weight: .black, design: .monospaced))
                            Text("\(record.airline) · \(record.aircraftModel)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(record.durationMinutes) 分钟")
                            .font(.headline.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.departureIATA)
                                .font(.system(size: 28, weight: .heavy))
                            Text(record.departureCity)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(record.arrivalIATA)
                                .font(.system(size: 28, weight: .heavy))
                            Text(record.arrivalCity)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 2. 力学关键极值看板
                VStack(alignment: .leading, spacing: 10) {
                    Text("航程动力学关键指标")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        metricTile(title: "最大巡航高度", value: "\(Int(record.maxAltitudeFt)) FT", subtitle: "FL\(Int(record.maxAltitudeFt / 100))", color: .blue)
                        metricTile(title: "最大空速/地速", value: "\(Int(record.maxSpeedKts)) KTS", subtitle: "高空平飞", color: .cyan)
                        metricTile(title: "着陆垂直过载", value: String(format: "%.2f g", record.peakNormalG), subtitle: record.touchdownRating ?? "正常", color: .purple)
                        metricTile(title: "触地下沉率", value: String(format: "%.0f FPM", record.touchdownSinkRateFpm ?? -120), subtitle: "接地瞬时", color: .orange)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 3. 飞行双高走势图表
                if !frames.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("全航程双高时序剖面")
                            .font(.headline)

                        Chart {
                            ForEach(Array(frames.enumerated()), id: \.offset) { idx, f in
                                LineMark(
                                    x: .value("Index", idx),
                                    y: .value("Altitude", f.geometricAltitudeFt),
                                    series: .value("Series", "真实飞行高度")
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Index", idx),
                                    y: .value("Altitude", f.cabinAltitudeFt),
                                    series: .value("Series", "客舱气压高度")
                                )
                                .foregroundStyle(.orange)
                            }
                        }
                        .frame(height: 160)
                        .chartLegend(position: .top, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // 4. 针对当次航班记录的导出中心
                VStack(alignment: .leading, spacing: 12) {
                    Text("针对该航班导出黑匣子数据")
                        .font(.headline)

                    Text("将本次 \(record.callsign) (\(record.routeString)) 的高精实测力学与空间航迹导出为标准外部文件：")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Button {
                            export(format: "gpx")
                        } label: {
                            Label("导出标准 GPX 航迹 (两步路 / 航旅回顾)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            export(format: "kml")
                        } label: {
                            Label("导出 3D KML 彩色轨迹 (Google Earth 三维拉伸)", systemImage: "globe.asia.australia.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            export(format: "csv")
                        } label: {
                            Label("导出 50Hz 原始力学时序 CSV (含过载与客舱压)", systemImage: "tablecells")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let msg = exportToast {
                        Text(msg)
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle(record.callsign)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            self.frames = FlightRecordStore.shared.loadTelemetryFrames(for: record.id)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func metricTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func export(format: String) {
        if let url = FlightRecordStore.shared.exportRecordFile(recordId: record.id, format: format) {
            self.exportedFileURL = url
            self.showShareSheet = true
            self.exportToast = "已生成 \(format.uppercased()) 文件并准备分享。"
        }
    }
}

/// 系统分享面板包装器 (UIActivityViewController)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

