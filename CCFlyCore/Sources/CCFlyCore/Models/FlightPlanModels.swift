import Foundation

/// 航班信息与计划模型
public struct FlightPlan: Codable, Identifiable, Sendable {
    public let id: String
    public let callsign: String          // 如 CA1501
    public let airline: String           // 如 中国国际航空
    public let aircraftModel: String     // 如 A350-900 / B787-9
    public let departureIATA: String     // PEK
    public let departureICAO: String     // ZBAA
    public let arrivalIATA: String       // SHA
    public let arrivalICAO: String       // ZSSS
    public let distanceNM: Double        // 大圆航线距离 (海里)
    public let plannedCruiseAltitudeFt: Double // 计划巡航高度 (如 36000 ft)

    public init(
        id: String = UUID().uuidString,
        callsign: String,
        airline: String,
        aircraftModel: String,
        departureIATA: String,
        departureICAO: String,
        arrivalIATA: String,
        arrivalICAO: String,
        distanceNM: Double,
        plannedCruiseAltitudeFt: Double = 35000
    ) {
        self.id = id
        self.callsign = callsign
        self.airline = airline
        self.aircraftModel = aircraftModel
        self.departureIATA = departureIATA
        self.departureICAO = departureICAO
        self.arrivalIATA = arrivalIATA
        self.arrivalICAO = arrivalICAO
        self.distanceNM = distanceNM
        self.plannedCruiseAltitudeFt = plannedCruiseAltitudeFt
    }
}
