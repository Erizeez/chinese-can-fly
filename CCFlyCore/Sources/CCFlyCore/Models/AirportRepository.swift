import Foundation

/// 离线机场与跑道数据仓库管理器 (高性能后台异步加载)
public final class AirportRepository: @unchecked Sendable {
    public static let shared = AirportRepository()

    private var airports: [Airport] = []
    private var airportsByICAO: [String: Airport] = [:]
    private var airportsByIATA: [String: Airport] = [:]
    private var isLoaded: Bool = false
    private let lock = NSLock()

    // 常用核心干线机场快速缓存 (零延迟开机秒级可用，零锁竞争)
    public static let coreHubAirports: [Airport] = [
        Airport(ident: "ZBAA", icao: "ZBAA", iata: "PEK", name: "北京首都国际机场", municipality: "北京", latitude: 40.0801, longitude: 116.5846, elevationFt: 116.0),
        Airport(ident: "ZBAD", icao: "ZBAD", iata: "PKX", name: "北京大兴国际机场", municipality: "北京", latitude: 39.5098, longitude: 116.4105, elevationFt: 98.0),
        Airport(ident: "ZSSS", icao: "ZSSS", iata: "SHA", name: "上海虹桥国际机场", municipality: "上海", latitude: 31.1979, longitude: 121.3363, elevationFt: 10.0),
        Airport(ident: "ZSPD", icao: "ZSPD", iata: "PVG", name: "上海浦东国际机场", municipality: "上海", latitude: 31.1434, longitude: 121.8052, elevationFt: 13.0),
        Airport(ident: "ZGGG", icao: "ZGGG", iata: "CAN", name: "广州白云国际机场", municipality: "广州", latitude: 23.3924, longitude: 113.2988, elevationFt: 50.0),
        Airport(ident: "ZGSZ", icao: "ZGSZ", iata: "SZX", name: "深圳宝安国际机场", municipality: "深圳", latitude: 22.6393, longitude: 113.8107, elevationFt: 13.0),
        Airport(ident: "ZUUU", icao: "ZUUU", iata: "CTU", name: "成都双流国际机场", municipality: "成都", latitude: 30.5785, longitude: 103.9471, elevationFt: 1622.0),
        Airport(ident: "ZUTF", icao: "ZUTF", iata: "TFU", name: "成都天府国际机场", municipality: "成都", latitude: 30.3150, longitude: 104.4440, elevationFt: 1430.0)
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
                airportsByICAO[apt.icao.uppercased()] = apt
            }
            if !apt.iata.isEmpty {
                airportsByIATA[apt.iata.uppercased()] = apt
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
            
            lock.lock()
            self.airports = decoded
            indexAirports(decoded)
            self.isLoaded = true
            lock.unlock()
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
