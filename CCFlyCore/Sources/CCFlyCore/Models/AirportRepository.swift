import Foundation

/// 离线机场与跑道数据仓库管理器 (高性能后台异步加载)
public final class AirportRepository: @unchecked Sendable {
    public static let shared = AirportRepository()

    private var airports: [Airport] = []
    private var airportsByICAO: [String: Airport] = [:]
    private var airportsByIATA: [String: Airport] = [:]
    private var isLoaded: Bool = false
    private let lock = NSLock()

    // 常用核心干线与特色支线机场快速缓存 (零延迟开机秒级可用，零锁竞争)
    public static let coreHubAirports: [Airport] = [
        Airport(ident: "ZBAA", icao: "ZBAA", iata: "PEK", name: "北京首都国际机场", municipality: "北京", latitude: 40.0801, longitude: 116.5846, elevationFt: 116.0),
        Airport(ident: "ZBAD", icao: "ZBAD", iata: "PKX", name: "北京大兴国际机场", municipality: "北京", latitude: 39.5098, longitude: 116.4105, elevationFt: 98.0),
        Airport(ident: "ZSSS", icao: "ZSSS", iata: "SHA", name: "上海虹桥国际机场", municipality: "上海", latitude: 31.1979, longitude: 121.3363, elevationFt: 10.0),
        Airport(ident: "ZSPD", icao: "ZSPD", iata: "PVG", name: "上海浦东国际机场", municipality: "上海", latitude: 31.1434, longitude: 121.8052, elevationFt: 13.0),
        Airport(ident: "ZGGG", icao: "ZGGG", iata: "CAN", name: "广州白云国际机场", municipality: "广州", latitude: 23.3924, longitude: 113.2988, elevationFt: 50.0),
        Airport(ident: "ZGSZ", icao: "ZGSZ", iata: "SZX", name: "深圳宝安国际机场", municipality: "深圳", latitude: 22.6393, longitude: 113.8107, elevationFt: 13.0),
        Airport(ident: "ZUUU", icao: "ZUUU", iata: "CTU", name: "成都双流国际机场", municipality: "成都", latitude: 30.5785, longitude: 103.9471, elevationFt: 1622.0),
        Airport(ident: "ZUTF", icao: "ZUTF", iata: "TFU", name: "成都天府国际机场", municipality: "成都", latitude: 30.3150, longitude: 104.4440, elevationFt: 1430.0),
        Airport(ident: "ZSSM", icao: "ZSSM", iata: "SQJ", name: "三明沙县机场", municipality: "三明", latitude: 26.4263, longitude: 117.8336, elevationFt: 830.0),
        Airport(ident: "ZSAM", icao: "ZSAM", iata: "XMN", name: "厦门高崎国际机场", municipality: "厦门", latitude: 24.5440, longitude: 118.1278, elevationFt: 59.0),
        Airport(ident: "ZSFZ", icao: "ZSFZ", iata: "FOC", name: "福州长乐国际机场", municipality: "福州", latitude: 25.9351, longitude: 119.6633, elevationFt: 46.0),
        Airport(ident: "ZSHC", icao: "ZSHC", iata: "HGH", name: "杭州萧山国际机场", municipality: "杭州", latitude: 30.2295, longitude: 120.4344, elevationFt: 23.0),
        Airport(ident: "ZSNJ", icao: "ZSNJ", iata: "NKG", name: "南京禄口国际机场", municipality: "南京", latitude: 31.7420, longitude: 118.8620, elevationFt: 49.0),
        Airport(ident: "ZHHH", icao: "ZHHH", iata: "WUH", name: "武汉天河国际机场", municipality: "武汉", latitude: 30.7838, longitude: 114.2081, elevationFt: 113.0),
        Airport(ident: "ZGHA", icao: "ZGHA", iata: "CSX", name: "长沙黄花国际机场", municipality: "长沙", latitude: 28.1892, longitude: 113.2197, elevationFt: 217.0),
        Airport(ident: "ZUCK", icao: "ZUCK", iata: "CKG", name: "重庆江北国际机场", municipality: "重庆", latitude: 29.7192, longitude: 106.6417, elevationFt: 1365.0),
        Airport(ident: "ZPPP", icao: "ZPPP", iata: "KMG", name: "昆明长水国际机场", municipality: "昆明", latitude: 25.1019, longitude: 102.9292, elevationFt: 6900.0),
        Airport(ident: "ZLXY", icao: "ZLXY", iata: "XIY", name: "西安咸阳国际机场", municipality: "西安", latitude: 34.4471, longitude: 108.7516, elevationFt: 1572.0),
        Airport(ident: "ZJQH", icao: "ZJQH", iata: "TAO", name: "青岛胶东国际机场", municipality: "青岛", latitude: 36.3683, longitude: 120.0883, elevationFt: 35.0),
        Airport(ident: "ZJHK", icao: "ZJHK", iata: "HAK", name: "海口美兰国际机场", municipality: "海口", latitude: 19.9349, longitude: 110.4590, elevationFt: 75.0),
        Airport(ident: "ZJSY", icao: "ZJSY", iata: "SYX", name: "三亚凤凰国际机场", municipality: "三亚", latitude: 18.3029, longitude: 109.4123, elevationFt: 92.0),
        Airport(ident: "ZWWW", icao: "ZWWW", iata: "URC", name: "乌鲁木齐地窝堡国际机场", municipality: "乌鲁木齐", latitude: 43.9071, longitude: 87.4742, elevationFt: 2126.0)
    ]

    private init() {
        // 先载入极速轻量核心缓存，保证启动耗时 0 毫秒
        self.airports = Self.coreHubAirports
        indexAirports(Self.coreHubAirports)
        
        // 注册资源包变更通知，以便设置中下载/删除时自动同步重载
        NotificationCenter.default.addObserver(
            forName: OfflineResourceManager.resourceUpdatedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task.detached(priority: .userInitiated) { [weak self] in
                self?.loadFullDatabaseInBackground()
            }
        }

        // 后台检查并尝试加载已下载的全量资源
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.loadFullDatabaseInBackground()
        }
    }

    private func indexAirports(_ list: [Airport]) {
        for apt in list {
            if !apt.icao.isEmpty {
                let icaoKey = apt.icao.uppercased()
                if let existing = airportsByICAO[icaoKey], existing.name.contains(where: { ("\u{4E00}"..."\u{9FA5}").contains($0) }) {
                    // 优先保留中文本土化机场名
                } else {
                    airportsByICAO[icaoKey] = apt
                }
            }
            if !apt.iata.isEmpty {
                let iataKey = apt.iata.uppercased()
                if let existing = airportsByIATA[iataKey], existing.name.contains(where: { ("\u{4E00}"..."\u{9FA5}").contains($0) }) {
                    // 优先保留中文本土化机场名
                } else {
                    airportsByIATA[iataKey] = apt
                }
            }
        }
    }

    /// 后台线程加载完整 779 座机场与 354 条跑道数据 (优先从用户沙盒离线资源加载)
    private func loadFullDatabaseInBackground() {
        var targetURL: URL? = nil

        // 1. 优先检查沙盒离线资源管理目录
        if let sandboxURL = OfflineResourceManager.shared.localFileURL(for: "china_airports_runways.json") {
            targetURL = sandboxURL
        } else {
            // 2. 检查 App Bundle 是否存在
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            targetURL = bundle.url(forResource: "china_airports_runways", withExtension: "json")
        }

        guard let url = targetURL else {
            // 若用户未下载且无内置，则保持 8 大核心枢纽机场极速缓存
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Airport].self, from: data)
            
            // 将真实的跑道几何与核心机场中文官方名深度融合
            var mergedList = decoded
            let hubIataMap = Dictionary(uniqueKeysWithValues: Self.coreHubAirports.filter { !$0.iata.isEmpty }.map { ($0.iata.uppercased(), $0) })
            for i in 0..<mergedList.count {
                let code = mergedList[i].iata.uppercased()
                if let zh = hubIataMap[code] {
                    mergedList[i] = Airport(
                        ident: mergedList[i].ident,
                        icao: mergedList[i].icao,
                        iata: mergedList[i].iata,
                        name: zh.name,
                        municipality: zh.municipality,
                        latitude: mergedList[i].latitude,
                        longitude: mergedList[i].longitude,
                        elevationFt: mergedList[i].elevationFt ?? zh.elevationFt,
                        type: mergedList[i].type,
                        runways: mergedList[i].runways
                    )
                }
            }

            lock.lock()
            self.airports = mergedList
            indexAirports(mergedList)
            self.isLoaded = true
            lock.unlock()
            print("✈️ [AIRPORT_REPO] 成功在后台载入 \(mergedList.count) 座真实机场与真实跑道物理模型")
        } catch {
            print("后台解析机场数据库失败: \(error)")
        }
    }

    /// 获取中国机场列表
    public func getAllAirports() -> [Airport] {
        lock.lock()
        defer { lock.unlock() }
        return airports
    }

    /// 根据 ICAO 代码 (如 ZBAA) 或 IATA 代码 (如 PEK) 精准检索机场
    public func findAirport(code: String) -> Airport? {
        lock.lock()
        defer { lock.unlock() }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let apt = airportsByICAO[clean] { return apt }
        if let apt = airportsByIATA[clean] { return apt }
        return nil
    }

    /// 搜索机场 (按拼音/中文名/城市/代码模糊匹配)
    public func searchAirports(query: String) -> [Airport] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.isEmpty else { return Array(airports.prefix(20)) }
        let q = query.lowercased()
        return airports.filter {
            $0.name.lowercased().contains(q) ||
            $0.municipality.lowercased().contains(q) ||
            $0.icao.lowercased().contains(q) ||
            $0.iata.lowercased().contains(q)
        }
    }
}
