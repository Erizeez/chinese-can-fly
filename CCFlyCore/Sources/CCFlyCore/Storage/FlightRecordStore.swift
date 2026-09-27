import Foundation

/// 单次航班飞行记录元数据模型 (支持航班号聚合与起降地航线聚合)
public struct FlightRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let callsign: String             // 航班号 (如 CA1501, MU9191)
    public let airline: String              // 航司 (如 中国国际航空)
    public let aircraftModel: String        // 机型 (如 COMAC C919, A350-900)
    public let departureIATA: String        // 出发 IATA (如 PEK)
    public let departureCity: String        // 出发城市 (如 北京)
    public let arrivalIATA: String          // 到达 IATA (如 SHA)
    public let arrivalCity: String          // 到达城市 (如 上海)
    public let startTime: Date              // 起飞/开始时间
    public let endTime: Date                // 降落/结束时间
    public let durationMinutes: Int         // 执飞耗时 (分钟)
    public let maxAltitudeFt: Double        // 最大巡航飞行高度 (ft)
    public let maxSpeedKts: Double          // 航程最大地速 (kts)
    public let peakNormalG: Double          // 接地/机动峰值垂直过载 Nz (g)
    public let touchdownSinkRateFpm: Double?// 触地瞬间下沉率 (FPM)
    public let touchdownRating: String?     // 接地质量评定 (如 Butter Landing)
    public let frameCount: Int              // 采集黑匣子数据帧数量

    public init(
        id: UUID = UUID(),
        callsign: String,
        airline: String,
        aircraftModel: String,
        departureIATA: String,
        departureCity: String,
        arrivalIATA: String,
        arrivalCity: String,
        startTime: Date,
        endTime: Date,
        durationMinutes: Int,
        maxAltitudeFt: Double,
        maxSpeedKts: Double,
        peakNormalG: Double,
        touchdownSinkRateFpm: Double?,
        touchdownRating: String?,
        frameCount: Int
    ) {
        self.id = id
        self.callsign = callsign
        self.airline = airline
        self.aircraftModel = aircraftModel
        self.departureIATA = departureIATA
        self.departureCity = departureCity
        self.arrivalIATA = arrivalIATA
        self.arrivalCity = arrivalCity
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.maxAltitudeFt = maxAltitudeFt
        self.maxSpeedKts = maxSpeedKts
        self.peakNormalG = peakNormalG
        self.touchdownSinkRateFpm = touchdownSinkRateFpm
        self.touchdownRating = touchdownRating
        self.frameCount = frameCount
    }

    /// 起降航线对字符串 (如 "PEK ➔ SHA")
    public var routeString: String {
        "\(departureIATA) ➔ \(arrivalIATA)"
    }

    /// 城市对字符串 (如 "北京 ➔ 上海")
    public var cityPairString: String {
        "\(departureCity) ➔ \(arrivalCity)"
    }
}

/// 飞行历史记录与日志本持久化管理仓储
public final class FlightRecordStore: @unchecked Sendable {
    public static let shared = FlightRecordStore()

    private let fileManager = FileManager.default
    private let recordsDirectory: URL
    private let indexFileURL: URL
    private let lock = NSLock()

    // 内存中的记录索引列表 (按起飞时间倒序排列)
    public private(set) var records: [FlightRecord] = []

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.recordsDirectory = docs.appendingPathComponent("CCFlyFlightRecords", isDirectory: true)
        self.indexFileURL = recordsDirectory.appendingPathComponent("records_index.json")

        try? fileManager.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
        loadIndex()

        // 若首次启动且无记录，初始化 2 条经典标杆航班历史 (C919全球商业首航与国航干线)
        if records.isEmpty {
            createInitialSampleRecords()
        }
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexFileURL.path),
              let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([FlightRecord].self, from: data) else {
            return
        }
        self.records = decoded.sorted(by: { $0.startTime > $1.startTime })
    }

    private func saveIndex() {
        lock.lock()
        defer { lock.unlock() }

        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexFileURL, options: .atomic)
        }
    }

    /// 保存当前飞行会话为独立的飞行记录条目
    @discardableResult
    public func saveSession(
        flight: FlightPlan?,
        frames: [TelemetryFrame],
        latestTouchdown: TouchdownReport?,
        startTime: Date,
        endTime: Date
    ) -> FlightRecord {
        let callsign = flight?.callsign ?? "CCFLY-\(Int(Date().timeIntervalSince1970) % 10000)"
        let airline = flight?.airline ?? "独立民航飞行"
        let model = flight?.aircraftModel ?? "民航干线客机"
        let dep = flight?.departureIATA ?? "PEK"
        let arr = flight?.arrivalIATA ?? "SHA"

        let maxAlt = frames.map { $0.geometricAltitudeFt }.max() ?? 35000.0
        let maxSpd = frames.map { $0.groundSpeedKts }.max() ?? 480.0
        let peakG = frames.map { $0.normalGForce }.max() ?? 1.15
        let durationMin = max(1, Int(endTime.timeIntervalSince(startTime) / 60.0))

        let recordId = UUID()
        let newRecord = FlightRecord(
            id: recordId,
            callsign: callsign,
            airline: airline,
            aircraftModel: model,
            departureIATA: dep,
            departureCity: AirportRepository.shared.findAirport(code: dep)?.name ?? dep,
            arrivalIATA: arr,
            arrivalCity: AirportRepository.shared.findAirport(code: arr)?.name ?? arr,
            startTime: startTime,
            endTime: endTime,
            durationMinutes: durationMin,
            maxAltitudeFt: maxAlt,
            maxSpeedKts: maxSpd,
            peakNormalG: latestTouchdown?.touchdownG ?? peakG,
            touchdownSinkRateFpm: latestTouchdown?.sinkRateFpm,
            touchdownRating: latestTouchdown?.rating ?? "平稳接地 (Normal)",
            frameCount: frames.count
        )

        // 独立存储该记录的遥测原始数据
        let detailURL = recordsDirectory.appendingPathComponent("\(recordId.uuidString).json")
        if let frameData = try? JSONEncoder().encode(frames) {
            try? frameData.write(to: detailURL, options: .atomic)
        }

        lock.lock()
        self.records.insert(newRecord, at: 0)
        lock.unlock()

        saveIndex()
        return newRecord
    }

    /// 读取某条飞行记录的完整遥测时序点 (用于重现高度走势图表与导出)
    public func loadTelemetryFrames(for recordId: UUID) -> [TelemetryFrame] {
        let detailURL = recordsDirectory.appendingPathComponent("\(recordId.uuidString).json")
        guard let data = try? Data(contentsOf: detailURL),
              let frames = try? JSONDecoder().decode([TelemetryFrame].self, from: data) else {
            return []
        }
        return frames
    }

    /// 针对特定某一次航班记录导出文件 (GPX / KML / CSV)
    public func exportRecordFile(recordId: UUID, format: String) -> URL? {
        guard let record = records.first(where: { $0.id == recordId }) else { return nil }
        let frames = loadTelemetryFrames(for: recordId)
        guard !frames.isEmpty else { return nil }

        switch format.lowercased() {
        case "gpx":
            return FlightLogExporter.exportGPX(frames: frames, flightCallsign: "\(record.callsign)_\(record.routeString)")
        case "kml":
            return FlightLogExporter.exportKML(frames: frames, flightCallsign: "\(record.callsign)_\(record.routeString)")
        case "csv":
            return FlightLogExporter.exportCSV(frames: frames, flightCallsign: "\(record.callsign)_\(record.routeString)")
        default:
            return nil
        }
    }

    // MARK: - 聚合视图支持

    /// 按航班号聚合 (如 CA1501 -> [记录1, 记录2, ...])
    public func recordsGroupedByCallsign() -> [(callsign: String, records: [FlightRecord])] {
        lock.lock()
        defer { lock.unlock() }

        let grouped = Dictionary(grouping: records, by: { $0.callsign })
        return grouped.map { (callsign: $0.key, records: $0.value.sorted(by: { $0.startTime > $1.startTime })) }
            .sorted(by: { $0.records.count > $1.records.count })
    }

    /// 按航线起降对聚合 (如 PEK ➔ SHA -> [记录1, 记录2, ...])
    public func recordsGroupedByRoute() -> [(route: String, departureCity: String, arrivalCity: String, records: [FlightRecord])] {
        lock.lock()
        defer { lock.unlock() }

        let grouped = Dictionary(grouping: records, by: { $0.routeString })
        return grouped.compactMap { key, val in
            guard let first = val.first else { return nil }
            return (
                route: key,
                departureCity: first.departureCity,
                arrivalCity: first.arrivalCity,
                records: val.sorted(by: { $0.startTime > $1.startTime })
            )
        }.sorted(by: { $0.records.count > $1.records.count })
    }

    // MARK: - 批量管理与删除

    /// 单条删除
    public func deleteRecord(id: UUID) {
        lock.lock()
        records.removeAll(where: { $0.id == id })
        lock.unlock()

        let detailURL = recordsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: detailURL)
        saveIndex()
    }

    /// 批量删除指定 ID 集合
    public func deleteRecords(ids: Set<UUID>) {
        lock.lock()
        records.removeAll(where: { ids.contains($0.id) })
        lock.unlock()

        for id in ids {
            let detailURL = recordsDirectory.appendingPathComponent("\(id.uuidString).json")
            try? fileManager.removeItem(at: detailURL)
        }
        saveIndex()
    }

    /// 按航班号批量删除 (如删除该航班号下的所有历史)
    public func deleteRecordsByCallsign(callsign: String) {
        let targets = records.filter { $0.callsign == callsign }.map { $0.id }
        deleteRecords(ids: Set(targets))
    }

    /// 按航线批量删除
    public func deleteRecordsByRoute(routeString: String) {
        let targets = records.filter { $0.routeString == routeString }.map { $0.id }
        deleteRecords(ids: Set(targets))
    }

    // MARK: - 预置首发真实标杆数据

    private func createInitialSampleRecords() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400 * 2)
        let fiveDaysAgo = now.addingTimeInterval(-86400 * 5)

        // 标杆 1: C919 全球商业首发历史记录 (MU9191 SHA -> PEK)
        let id1 = UUID()
        let rec1 = FlightRecord(
            id: id1,
            callsign: "MU9191",
            airline: "中国东方航空",
            aircraftModel: "COMAC C919",
            departureIATA: "SHA",
            departureCity: "上海虹桥",
            arrivalIATA: "PEK",
            arrivalCity: "北京首都",
            startTime: fiveDaysAgo,
            endTime: fiveDaysAgo.addingTimeInterval(7200),
            durationMinutes: 120,
            maxAltitudeFt: 35100,
            maxSpeedKts: 472,
            peakNormalG: 1.18,
            touchdownSinkRateFpm: -115,
            touchdownRating: "丝滑着陆 (Butter Landing 1.18G)",
            frameCount: 120
        )

        // 标杆 2: 国航主力干线 (CA1501 PEK -> SHA)
        let id2 = UUID()
        let rec2 = FlightRecord(
            id: id2,
            callsign: "CA1501",
            airline: "中国国际航空",
            aircraftModel: "Airbus A350-900",
            departureIATA: "PEK",
            departureCity: "北京首都",
            arrivalIATA: "SHA",
            arrivalCity: "上海虹桥",
            startTime: oneDayAgo,
            endTime: oneDayAgo.addingTimeInterval(6600),
            durationMinutes: 110,
            maxAltitudeFt: 36000,
            maxSpeedKts: 512,
            peakNormalG: 1.25,
            touchdownSinkRateFpm: -140,
            touchdownRating: "轻柔着陆 (Smooth Landing 1.25G)",
            frameCount: 110
        )

        self.records = [rec2, rec1]
        saveIndex()
    }
}
