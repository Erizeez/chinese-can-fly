# 中国人能飞 (Chinese Can Fly / CCFly)

> **面向高阶飞行爱好者的专业级 iOS 航空传感器融合与飞行黑匣子系统**  
> 纯端侧 · 全离线可用 · 双高双升降率解耦 · 航空级 GNSS/INS 惯性参考系统

[![Swift](https://img.shields.io/badge/Swift-6.0%20%7C%205.9-orange?logo=swift)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue?logo=apple)](https://apple.com)
[![Platform](https://img.shields.io/badge/Platform-iPhone%2014%20Pro%20~%2018%20Pro-black)](https://apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🌟 项目缘起与核心理念

在民航客舱中，大多数常旅客只能看着前方座椅背后的简陋航线图（Airshow）或在落地联网后等待商业软件的模糊轨迹。然而对于**飞行员、滑翔爱好者、模拟机极客与常旅客航空迷**而言，飞行中的真实动力学参数才是最迷人的核心：

- 飞机起飞抬轮（Rotation）拉起了多少 G？
- 这次降落是轻如鸿毛的“黄油着陆（Butter Landing）”还是重重砸地的“重着陆”？触地瞬间下沉率（Touchdown FPM）是多少？
- 现在的客舱增压系统控制得如何？为什么在 10,000 米巡航时，普通气压高度计会“撒谎”？
- 没有外网信号的高空，能否拥有一张秒级离线渲染的中国各省份空域底图与机场跑道对正走向？

**“中国人能飞” (Chinese Can Fly)** 充分挖掘最新 iPhone（含 iPhone 18 Pro 等新机型）内置的顶级微机电传感器阵列（双频 GNSS、6轴高动态 IMU、精密数字气压计、磁力计），构建了完整的民航客机级惯性参考系统（IRS）与飞行黑匣子。

---

## 📱 四大核心页面 (Key Features)

### 1. 航班数据 (Flight Data)
- **全离线静态航线网络**：内置国内各大航司（国航、东航、南航、海航等）5000+ 主力航线基线库，无网飞行模式下输入航班号即可离线获知起降机场、大圆航距与预计航路。
- **离线航路推算与大圆计划**：输入航班号自动计算大圆航距、初始磁航向、离散航路点及剩余航程，即使高空断网也能全程追踪航迹进度。

### 2. 航图与机场跑道 (Aeronautical Chart & Aerodrome Layout)
- **极速航图渲染与跑道走向**：无需在线地图服务，轻量离线底图瞬间呈现，支持跑道号（如 36L/18R）、物理长宽尺寸、真方位角与跑道头标高。
- **动态大圆航迹叠加**：自动解算起降机场大圆航线与离散航路点，航迹平滑聚焦，告别卡顿。

### 3. 飞行数据与航空惯导 (Flight Telemetry & Avionics Fusion)
- **航空级虚拟姿态仪 (PFD)**：基于捷联惯导（SINS）四元数解算，实时输出飞机俯仰角（Pitch）与滚转角（Roll）。
- **“客舱增压悖论”双高解耦系统**：
  - **真实飞行高度 (GNSS MSL)** 与 **客舱气压高度 (Cabin Altitude)** 并行显示；
  - 实时解析客舱升降率（Cabin VSI）与增压系统工况。
- **G 值力学与触地冲击黑匣子**：
  - 实时垂直过载 $N_z$ 与纵向推力/刹车加速度 $N_x$；
  - 50Hz 采样捕捉起飞抬头拉起 G 值与着陆接地冲击峰值，智能评定接地质量（Butter / Firm / Heavy）；
  - 基于垂直振动功率谱的晴空颠簸指数（Turbulence EDR - Eddy Dissipation Rate）。
- **全航程力学图表化**：高度剖面走势、过载时序图、客舱升降率对比图。

### 4. 设置与飞行黑匣子工具 (Settings & Toolbox)
- **机体轴自动校准向导**：滑跑起飞阶段自动解算手机放置方位与飞机机头的正交矩阵（无论手机平放、倾斜插在前方座椅网兜还是手持）。
- **传感器动态采样控制**：50Hz（极客黑匣子模式）、10Hz（平衡模式）、1Hz（超低功耗模式）。
- **离线资源包管理**：机场跑道数据库与离线矢量切片下载与更新。
- **专业格式离线导出**：一键导出 `.gpx`（航迹）、`.kml`（Google Earth 3D 彩色轨迹）、`.csv`（50Hz 原始力学数据）、`.igc`（国际航联通用格式）。

---

## 🧠 深度技术架构与算法突破

```
+---------------------------------------------------------------------------------+
|                       “中国人能飞” 底层软硬件拓扑与算法流                       |
+---------------------------------------------------------------------------------+
                                         |
     +-----------------------------------+-----------------------------------+
     |                                                                       |
     v                                                                       v
[空间几何与离线跑道]                                                [传感器高动态融合 EKF]
• OurAirports 跑道参数                                              • 6-Axis IMU (50-100Hz)
• OSM 跑道轮廓矢量                                                  • Dual-band GNSS (1Hz)
• 大圆航线航程与下滑偏离                                            • Barometer (10-50Hz)
     |                                                                       |
     +-----------------------------------+-----------------------------------+
                                         |
                                         v
                         [核心航空动力学与解耦层]
       ┌────────────────────────────────────────────────────────┐
       │ 1. 客舱增压解耦: 飞机真实高度 vs 客舱等效高度           │
       │ 2. 坐标系正交投影: 手机姿态 -> 飞机机体坐标系 (X/Y/Z) │
       │ 3. 冲击分析: 接地 Touchdown FPM & 接地冲击 G 峰值       │
       │ 4. EDR 湍流分析: 垂直过载方差频响谱估算                │
       └────────────────────────────────────────────────────────┘
                                         |
                                         v
                         [高可靠航空保活与 WAL 存储]
       ┌────────────────────────────────────────────────────────┐
       │ • CoreLocation `activityType = .airborne`               │
       │ • 禁用自动休眠 `pausesLocationUpdatesAutomatically = false│
       │ • 起降关键 15 分钟高频黑匣子录制                        │
       │ • SQLite WAL 事务引擎: 飞机落地手机断电零丢帧自愈       │
       └────────────────────────────────────────────────────────┘
```

详见技术文档：
- 📐 [架构提案与全局蓝图 (ARCHITECTURE_PROPOSAL.md)](docs/ARCHITECTURE_PROPOSAL.md)
- 🛰️ [航空与地理数据源调研报告 (DATA_SOURCES_SURVEY.md)](docs/DATA_SOURCES_SURVEY.md)
- 🧭 [传感器融合与惯导算法推导 (AVIONICS_SENSOR_FUSION.md)](docs/AVIONICS_SENSOR_FUSION.md)
- 🔋 [iOS 严格后台保活与断电保护机制 (BACKGROUND_RESILIENCE.md)](docs/BACKGROUND_RESILIENCE.md)

---

## 🛠️ 项目目录结构

```
chinese-can-fly/
├── README.md                           # 项目总览
├── docs/                               # 深度技术方案与调研文档
│   ├── ARCHITECTURE_PROPOSAL.md        # 架构提案
│   ├── DATA_SOURCES_SURVEY.md          # 跑道/航班/离线地图数据源调研
│   ├── AVIONICS_SENSOR_FUSION.md       # 惯导EKF、客舱增压、机体对准推导
│   └── BACKGROUND_RESILIENCE.md        # iOS 后台保活与断电保护
├── scripts/
│   └── fetch_ourairports_data.py       # OurAirports 中国跑道数据提取脚本
├── CCFlyCore/                          # 核心算法 Swift Package
│   ├── Package.swift
│   ├── Sources/CCFlyCore/
│   │   ├── Models/                     # 机场、跑道、遥测帧、航班计划
│   │   ├── Sensor/                     # 机体轴对准器 (BodyFrameAligner)
│   │   ├── EKF/                        # 扩展卡尔曼滤波惯导引擎 (EKFNavEngine)
│   │   ├── Avionics/                   # 标准大气ISA、客舱高度分析、过载分析
│   │   ├── Background/                 # 后台长航时保活跟踪器
│   │   └── Resources/                  # 内置离线机场跑道数据库
│   └── Tests/CCFlyCoreTests/           # 单元测试 (ISA公式、对准器、冲击评估)
└── App/                                # SwiftUI 应用层原型
    ├── ChineseCanFlyApp.swift          # 应用主入口与 Tab 容器
    └── Tabs/
        ├── FlightDataView.swift        # 1. 航班数据视图
        ├── OfflineMapView.swift        # 2. 离线地图与跑道视图
        ├── AvionicsTelemetryView.swift # 3. 飞行数据与惯导姿态视图
        └── SettingsView.swift          # 4. 设置与导出工具视图
```

---

## 🚀 快速开始与项目入口

### 1. 直接通过 Xcode 打开项目 (推荐)
仓库根目录下已生成标准的 **`ChineseCanFly.xcodeproj`**：
- **方式一（Finder 双击）**：在 Finder 中进入本目录，双击打开 [`ChineseCanFly.xcodeproj`](file:///Users/sail/Workspace/chinese-can-fly/ChineseCanFly.xcodeproj)。
- **方式二（终端一键唤起）**：
  ```bash
  open ChineseCanFly.xcodeproj
  ```
- **运行配置**：选择 Target **`ChineseCanFly`**，选择目标设备为任一 iPhone 模拟器（如 iPhone 16 Pro / iPhone 17 Pro）或你的真实 iPhone，直接点击 **Run (⌘R)** 即可编译并启动应用。

### 2. 代码组织与模块关系
- **应用层入口**：[`App/ChineseCanFlyApp.swift`](file:///Users/sail/Workspace/chinese-can-fly/App/ChineseCanFlyApp.swift)（包含 SwiftUI 主 Tab 容器及 4 个页面视图）；
- **权限与后台配置**：[`App/Info.plist`](file:///Users/sail/Workspace/chinese-can-fly/App/Info.plist)（已配置后台定位 `location` 与后台音频微通道 `audio`，以及运动传感器权限）；
- **核心算法包**：[`CCFlyCore/`](file:///Users/sail/Workspace/chinese-can-fly/CCFlyCore/)（独立 Swift Package，负责 EKF 滤波、ISA 大气、客舱高度分析及机场数据）；
- **工程自动化**：[`project.yml`](file:///Users/sail/Workspace/chinese-can-fly/project.yml)（使用 XcodeGen 配置，随时可重新生成 `.xcodeproj`）。

### 3. 运行核心算法单元测试
本项目核心算法采用独立 Swift Package 架构，在 macOS / iOS 环境下均可一键测试：
```bash
cd CCFlyCore
swift test
```
**测试输出：**
- `testISAStandardAtmosphere`: 验证 ICAO 标准大气反解与客舱气压换算精度；
- `testBodyFrameAlignment`: 验证手机任意摆放时机身正交重力与推力对齐算法；
- `testFlightDynamicsAnalyzer`: 验证触地冲击 Butter / Heavy 评估。

### 2. 提取最新中国机场跑道离线包
```bash
python3 scripts/fetch_ourairports_data.py
```
脚本将自动拉取 OurAirports 最新全球数据并提取中国区全量民用机场与跑道参数。

---

## 📜 开源协议

本项目采用 [MIT License](LICENSE) 协议开源。
欢迎广大飞行爱好者、民航飞行员与 iOS 极客提交 Issue 与 Pull Request！
