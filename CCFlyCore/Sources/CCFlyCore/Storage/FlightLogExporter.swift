import Foundation

/// 飞行黑匣子日志真实文件导出引擎 (GPX, KML, CSV)
public enum FlightLogExporter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 生成标准 GPX 1.1 轨迹文件
    public static func exportGPX(frames: [TelemetryFrame], flightCallsign: String = "CCFly") -> URL? {
        guard !frames.isEmpty else { return nil }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Chinese Can Fly (中国人能飞) - iOS Avionics" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>Flight \(flightCallsign)</name>
            <time>\(isoFormatter.string(from: frames.first?.timestamp ?? Date()))</time>
          </metadata>
          <trk>
            <name>\(flightCallsign)</name>
            <trkseg>
        """

        for f in frames {
            let timeStr = isoFormatter.string(from: f.timestamp)
            xml += """
                  <trkpt lat="\(String(format: "%.6f", f.latitude))" lon="\(String(format: "%.6f", f.longitude))">
                    <ele>\(String(format: "%.1f", f.geometricAltitudeMeters))</ele>
                    <time>\(timeStr)</time>
                    <extensions>
                      <speed_kts>\(String(format: "%.1f", f.groundSpeedKts))</speed_kts>
                      <course_deg>\(String(format: "%.1f", f.groundTrackDeg))</course_deg>
                      <cabin_alt_ft>\(String(format: "%.0f", f.cabinAltitudeFt))</cabin_alt_ft>
                      <g_force>\(String(format: "%.2f", f.normalGForce))</g_force>
                    </extensions>
                  </trkpt>
            """
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>
        """

        return writeTemporaryFile(content: xml, fileName: "Flight_\(flightCallsign)_\(Date().timeIntervalSince1970).gpx")
    }

    /// 生成可直接导入 Google Earth 的 3D KML 航迹文件
    public static func exportKML(frames: [TelemetryFrame], flightCallsign: String = "CCFly") -> URL? {
        guard !frames.isEmpty else { return nil }

        var coords = ""
        for f in frames {
            coords += "\(f.longitude),\(f.latitude),\(f.geometricAltitudeMeters) "
        }

        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>Flight \(flightCallsign)</name>
            <Style id="flightPath">
              <LineStyle>
                <color>7f00ffff</color>
                <width>4</width>
              </LineStyle>
              <PolyStyle>
                <color>330000ff</color>
              </PolyStyle>
            </Style>
            <Placemark>
              <name>3D Flight Profile: \(flightCallsign)</name>
              <styleUrl>#flightPath</styleUrl>
              <LineString>
                <extrude>1</extrude>
                <tessellate>1</tessellate>
                <altitudeMode>absolute</altitudeMode>
                <coordinates>
                  \(coords.trimmingCharacters(in: .whitespaces))
                </coordinates>
              </LineString>
            </Placemark>
          </Document>
        </kml>
        """

        return writeTemporaryFile(content: kml, fileName: "Flight_\(flightCallsign)_\(Date().timeIntervalSince1970).kml")
    }

    /// 生成科研分析级 50Hz 原始力学遥测 CSV 表格
    public static func exportCSV(frames: [TelemetryFrame], flightCallsign: String = "CCFly") -> URL? {
        guard !frames.isEmpty else { return nil }

        var csv = "Timestamp,Latitude,Longitude,GeometricAlt_m,GeometricAlt_ft,GroundSpeed_kts,GroundTrack_deg,CabinAlt_ft,AmbientPressure_hPa,CabinVSI_fpm,Pitch_deg,Roll_deg,Nz_G,Nx_G,Ny_G,Turbulence_EDR,FlightPhase\n"

        for f in frames {
            let row = "\(isoFormatter.string(from: f.timestamp)),\(f.latitude),\(f.longitude),\(f.geometricAltitudeMeters),\(f.geometricAltitudeFt),\(f.groundSpeedKts),\(f.groundTrackDeg),\(f.cabinAltitudeFt),\(f.ambientPressureHPa),\(f.cabinVerticalSpeedFpm),\(f.pitchDeg),\(f.rollDeg),\(f.normalGForce),\(f.longitudinalGForce),\(f.lateralGForce),\(f.turbulenceEDR),\(f.flightPhase.rawValue)\n"
            csv.append(row)
        }

        return writeTemporaryFile(content: csv, fileName: "Telemetry_\(flightCallsign)_\(Date().timeIntervalSince1970).csv")
    }

    private static func writeTemporaryFile(content: String, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("写入导出文件失败: \(error)")
            return nil
        }
    }
}
