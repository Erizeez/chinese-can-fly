import Foundation

/// 机场实体模型
public struct Airport: Codable, Identifiable, Sendable {
    public var id: String { ident }
    public let ident: String
    public let icao: String
    public let iata: String
    public let name: String
    public let municipality: String
    public let latitude: Double
    public let longitude: Double
    public let elevationFt: Double?
    public let type: String
    public var runways: [Runway]

    enum CodingKeys: String, CodingKey {
        case ident, icao, iata, name, municipality, latitude, longitude, type, runways
        case elevationFt = "elevation_ft"
    }

    public init(
        ident: String,
        icao: String,
        iata: String,
        name: String,
        municipality: String,
        latitude: Double,
        longitude: Double,
        elevationFt: Double? = nil,
        type: String = "large_airport",
        runways: [Runway] = []
    ) {
        self.ident = ident
        self.icao = icao
        self.iata = iata
        self.name = name
        self.municipality = municipality
        self.latitude = latitude
        self.longitude = longitude
        self.elevationFt = elevationFt
        self.type = type
        self.runways = runways
    }
}

/// 跑道几何与物理参数模型
public struct Runway: Codable, Identifiable, Sendable {
    public let id: String
    public let lengthFt: Double?
    public let widthFt: Double?
    public let surface: String?
    public let lighted: Bool
    
    // 低端 (Low End) 跑道参数 (如 36L)
    public let leIdent: String
    public let leLatitude: Double?
    public let leLongitude: Double?
    public let leElevationFt: Double?
    public let leHeadingDegT: Double?
    
    // 高端 (High End) 跑道参数 (如 18R)
    public let heIdent: String
    public let heLatitude: Double?
    public let heLongitude: Double?
    public let heElevationFt: Double?
    public let heHeadingDegT: Double?

    enum CodingKeys: String, CodingKey {
        case id, surface, lighted
        case lengthFt = "length_ft"
        case widthFt = "width_ft"
        case leIdent = "le_ident"
        case leLatitude = "le_latitude"
        case leLongitude = "le_longitude"
        case leElevationFt = "le_elevation_ft"
        case leHeadingDegT = "le_heading_degT"
        case heIdent = "he_ident"
        case heLatitude = "he_latitude"
        case heLongitude = "he_longitude"
        case heElevationFt = "he_elevation_ft"
        case heHeadingDegT = "he_heading_degT"
    }

    public init(
        id: String,
        lengthFt: Double? = nil,
        widthFt: Double? = nil,
        surface: String? = nil,
        lighted: Bool = true,
        leIdent: String,
        leLatitude: Double? = nil,
        leLongitude: Double? = nil,
        leElevationFt: Double? = nil,
        leHeadingDegT: Double? = nil,
        heIdent: String,
        heLatitude: Double? = nil,
        heLongitude: Double? = nil,
        heElevationFt: Double? = nil,
        heHeadingDegT: Double? = nil
    ) {
        self.id = id
        self.lengthFt = lengthFt
        self.widthFt = widthFt
        self.surface = surface
        self.lighted = lighted
        self.leIdent = leIdent
        self.leLatitude = leLatitude
        self.leLongitude = leLongitude
        self.leElevationFt = leElevationFt
        self.leHeadingDegT = leHeadingDegT
        self.heIdent = heIdent
        self.heLatitude = heLatitude
        self.heLongitude = heLongitude
        self.heElevationFt = heElevationFt
        self.heHeadingDegT = heHeadingDegT
    }
}
