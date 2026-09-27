import SwiftUI
import CCFlyCore

@main
struct ChineseCanFlyApp: App {
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
