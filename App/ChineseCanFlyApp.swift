import SwiftUI
import MapKit
import CCFlyCore

@main
struct ChineseCanFlyApp: App {
    init() {
        MainThreadHitchMonitor.startMonitoring()
        // 核心优化：启动首帧静默就绪常驻单例航图与飞行数据中枢 (Metal 管线与 VectorKit 渲染器就绪)
        DispatchQueue.main.async {
            _ = AviationMapViewRepresentable.sharedMapView
            _ = FlightDataManager.shared
            print("🚀 [PREWARM] Aviation MapView & FlightDataManager pre-warmed successfully")
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
    @State private var selectedTab: Int = 0 // 默认首页：航班数据检索与管理
    @State private var isPrewarmActive: Bool = false

    var body: some View {
        ZStack {
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

            // 核心性能架构：常驻后台闲暇就绪层 (在首页就绪后 300ms 激活并永久常驻)
            // 彻底在主线程空闲时消化 AvionicsTelemetryView 与 SwiftCharts 的首次同步加载成本
            // 用户无论何时点击进入【飞行数据】，都能享受毫秒级 0 卡顿瞬开体验！
            if isPrewarmActive {
                AvionicsTelemetryView()
                    .opacity(0.0001)
                    .allowsHitTesting(false)
                    .frame(width: 1, height: 1)
            }
        }
        .task {
            // 应用启动 0.3 秒后（首页首屏已稳定呈现），在后台闲暇期静默就绪飞行数据页与图表符号解析
            try? await Task.sleep(nanoseconds: 300_000_000)
            isPrewarmActive = true
        }
    }
}
