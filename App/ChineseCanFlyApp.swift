import SwiftUI
import MapKit
import CCFlyCore

@main
struct ChineseCanFlyApp: App {
    init() {
        MainThreadHitchMonitor.startMonitoring()
        // 核心优化：启动首帧静默就绪常驻单例航图 (Metal 管线与 VectorKit 渲染器就绪)
        DispatchQueue.main.async {
            _ = AviationMapViewRepresentable.sharedMapView
            print("🚀 [PREWARM] Aviation MapView pre-warmed successfully")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

/// 主 Tab 容器视图
struct MainTabView: View {
    @State private var selectedTab: Int = 2 // 默认进入最核心的“飞行数据与惯导”

    var body: some View {
        TabView(selection: $selectedTab) {
            FlightDataView()
                .tabItem {
                    Label("航班数据", systemImage: "airplane.departure")
                }
                .tag(0)

            AeronauticalMapView()
                .tabItem {
                    Label("航图", systemImage: "map.fill")
                }
                .tag(1)

            AvionicsTelemetryView()
                .tabItem {
                    Label("飞行数据", systemImage: "speedometer")
                }
                .tag(2)

            FlightRecordsView()
                .tabItem {
                    Label("飞行记录", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(4)
        }
        .tint(.blue)
    }
}
