import Foundation

/// 离线机场与跑道数据仓库管理器
public final class AirportRepository: @unchecked Sendable {
    public static let shared = AirportRepository()

    private var airports: [Airport] = []
    private var airportsByICAO: [String: Airport] = [:]
    private var airportsByIATA: [String: Airport] = [:]

    private init() {
        loadEmbeddedDatabase()
    }

    /// 从 Package Resources 中加载预置的全国机场跑道真实数据
    private func loadEmbeddedDatabase() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        if let url = bundle.url(forResource: "china_airports_runways", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([Airport].self, from: data)
                self.airports = decoded
                for apt in decoded {
                    if !apt.icao.isEmpty {
                        airportsByICAO[apt.icao.uppercased()] = apt
                    }
                    if !apt.iata.isEmpty {
                        airportsByIATA[apt.iata.uppercased()] = apt
                    }
                }
            } catch {
                print("加载内置机场数据库失败: \(error)")
            }
        }
    }

    /// 获取中国全量机场列表
    public func getAllAirports() -> [Airport] {
        return airports
    }

    /// 根据 ICAO 代码 (如 ZBAA) 或 IATA 代码 (如 PEK) 精准检索机场
    public func findAirport(code: String) -> Airport? {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let apt = airportsByICAO[clean] { return apt }
        if let apt = airportsByIATA[clean] { return apt }
        return nil
    }

    /// 搜索机场 (按拼音/中文名/城市/代码模糊匹配)
    public func searchAirports(query: String) -> [Airport] {
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
