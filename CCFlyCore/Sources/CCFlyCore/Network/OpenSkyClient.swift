import Foundation

/// 实时空中航空器态势向量 (OpenSky State Vector)
public struct AirborneState: Codable, Identifiable, Sendable {
    public var id: String { icao24 }
    public let icao24: String
    public let callsign: String
    public let originCountry: String
    public let longitude: Double?
    public let latitude: Double?
    public let baroAltitudeMeters: Double?
    public let geoAltitudeMeters: Double?
    public let velocityKts: Double?
    public let trueTrackDeg: Double?
    public let verticalRateFpm: Double?
    public let onGround: Bool
    public let lastContactTime: Date

    public init(
        icao24: String,
        callsign: String,
        originCountry: String,
        longitude: Double?,
        latitude: Double?,
        baroAltitudeMeters: Double?,
        geoAltitudeMeters: Double?,
        velocityKts: Double?,
        trueTrackDeg: Double?,
        verticalRateFpm: Double?,
        onGround: Bool,
        lastContactTime: Date = Date()
    ) {
        self.icao24 = icao24
        self.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        self.originCountry = originCountry
        self.longitude = longitude
        self.latitude = latitude
        self.baroAltitudeMeters = baroAltitudeMeters
        self.geoAltitudeMeters = geoAltitudeMeters
        self.velocityKts = velocityKts
        self.trueTrackDeg = trueTrackDeg
        self.verticalRateFpm = verticalRateFpm
        self.onGround = onGround
        self.lastContactTime = lastContactTime
    }
}

/// OpenSky Network 开放航空数据客户端
public final class OpenSkyClient: Sendable {
    public static let shared = OpenSkyClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 根据呼号检索空中实时态势 (如 "CCA1501" 或 "CES5101")
    public func fetchFlightState(callsign: String) async throws -> AirborneState? {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // OpenSky API: /api/states/all (公共接口)
        guard let url = URL(string: "https://opensky-network.org/api/states/all") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("ChineseCanFly/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        // 解析 OpenSky JSON 格式
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[Any]] else {
            return nil
        }

        for item in states {
            guard item.count >= 14 else { continue }
            let icao24 = (item[0] as? String) ?? ""
            let itemCallsign = (item[1] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            
            // 匹配呼号 (IATA如CA1501对应ICAO呼号CCA1501，支持前缀模糊或全等)
            if itemCallsign.contains(clean) || clean.contains(itemCallsign) || isCallsignMatched(userCallsign: clean, adsbCallsign: itemCallsign) {
                let country = (item[2] as? String) ?? ""
                let lon = item[5] as? Double
                let lat = item[6] as? Double
                let baroAlt = item[7] as? Double
                let onGnd = (item[8] as? Bool) ?? false
                let velocityMps = item[9] as? Double
                let track = item[10] as? Double
                let vRateMps = item[11] as? Double
                let geoAlt = item[13] as? Double

                let speedKts = velocityMps.map { $0 * 1.94384 }
                let vRateFpm = vRateMps.map { $0 * 196.85 }

                return AirborneState(
                    icao24: icao24,
                    callsign: itemCallsign,
                    originCountry: country,
                    longitude: lon,
                    latitude: lat,
                    baroAltitudeMeters: baroAlt,
                    geoAltitudeMeters: geoAlt,
                    velocityKts: speedKts,
                    trueTrackDeg: track,
                    verticalRateFpm: vRateFpm,
                    onGround: onGnd
                )
            }
        }

        return nil
    }

    /// 本地便携式 SDR 接收机 (Dump1090) 局域网接入客户端
    public func fetchDump1090Aircraft(host: String = "192.168.10.1", port: Int = 8080) async throws -> [AirborneState] {
        guard let url = URL(string: "http://\(host):\(port)/dump1090/data/aircraft.json") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        let (data, _) = try await session.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let aircraftList = json["aircraft"] as? [[String: Any]] else {
            return []
        }

        var result: [AirborneState] = []
        for ac in aircraftList {
            let hex = (ac["hex"] as? String) ?? ""
            let flight = (ac["flight"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let lat = ac["lat"] as? Double
            let lon = ac["lon"] as? Double
            let altFt = ac["altitude"] as? Double
            let speed = ac["speed"] as? Double
            let track = ac["track"] as? Double
            let vRate = ac["vert_rate"] as? Double

            if lat != nil && lon != nil {
                result.append(AirborneState(
                    icao24: hex,
                    callsign: flight.isEmpty ? hex.uppercased() : flight,
                    originCountry: "Local SDR",
                    longitude: lon,
                    latitude: lat,
                    baroAltitudeMeters: altFt.map { $0 * 0.3048 },
                    geoAltitudeMeters: nil,
                    velocityKts: speed,
                    trueTrackDeg: track,
                    verticalRateFpm: vRate,
                    onGround: false
                ))
            }
        }

        return result
    }

    private func isCallsignMatched(userCallsign: String, adsbCallsign: String) -> Bool {
        // CA1501 匹配 CCA1501
        // MU5101 匹配 CES5101
        // CZ3101 匹配 CSN3101
        let numPart = userCallsign.filter { $0.isNumber }
        return !numPart.isEmpty && adsbCallsign.contains(numPart)
    }
}
