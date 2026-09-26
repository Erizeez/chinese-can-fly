# iOS 严格后台保活与断电保护机制设计 (Background Resilience & Blackbox Storage)

---

## 一、 iOS 后台机制与航空长航时痛点

在民航洲际或国内干线飞行中，单次飞行时长通常在 2 小时至 14 小时不等。在长航时记录过程中，面临以下严峻的系统级限制：
1. **Watchdog 内存与 CPU 监视器**：后台如果持续占用大量主线程 CPU 或内存泄漏，iOS 会直接强杀进程（0x8badf00d 代码）。
2. **位置更新自动暂停 (Auto-pause)**：iOS 的 `pausesLocationUpdatesAutomatically` 机制会在传感器判定设备“静止”时切断 GPS。在 10,000 米巡航平飞时，由于飞机航向平直且无剧烈震动，iOS 极易发生致命误判并彻底暂停定位。
3. **传感器后台节流 (CoreMotion Throttling)**：在未开启任何保活音频或后台管道时，屏幕熄灭后 CoreMotion 会在数秒内被操作系统冻结挂起。
4. **长途电池耗尽断电**：乘客手机若在降落前意外断电关机，若采用传统非事务型文件存储，整个飞行的记录文件会损坏或数据丢失。

---

## 二、 复合级后台保活技术方案

为了确保 App 在息屏或切后台状态下**100% 稳定运行全航程**，构建三层立体保活防护网：

```
+---------------------------------------------------------------------------------+
|                         复合后台保活立体架构 (Resilience Mesh)                   |
+---------------------------------------------------------------------------------+
                                         |
     +-----------------------------------+-----------------------------------+
     |                                                                       |
     v                                                                       v
[核心通道 1: CoreLocation 航空模式]                     [关键阶段通道 2: 微底噪 Audio 守护]
• `activityType = .airborne` (航空高动态专用)          • 起飞 (加速>30节) 与进近 (<3000ft) 触发
• `pausesLocationUpdatesAutomatically = false`       • `AVAudioSession(.playback, .mixWithOthers)`
• `allowsBackgroundLocationUpdates = true`           • 维持 CoreMotion 50Hz 高刷新率不被系统挂起
• `showsBackgroundLocationIndicator = true`          • 降落滑行完毕后自动休眠，杜绝多余耗电
     |                                                                       |
     +-----------------------------------+-----------------------------------+
                                         |
                                         v
                         [中央调度: 飞行工况自适应状态机]
                                         |
         +-------------+-----------------+---------------+-------------+
         v             v                                 v             v
      [停机坪]       [起飞滑跑]                       [巡航平飞]     [进近接地]
       1 Hz           50 Hz                             1~5 Hz        50 Hz
      超低功耗       高精姿态/G值拉起                 自适应节能     捕获触地瞬间
                                         |
                                         v
                         [存储引擎: SQLite WAL 事务流]
                         • 零丢失预写式日志，秒级自动刷盘
                         • 手机断电关机后，重启即刻自愈读取
```

### 1. 深度定制 CoreLocation 航空属性
- **启用系统航空定位专属管道**：
  ```swift
  locationManager.activityType = .airborne // 专门通知 iOS 底层 baseband，针对几百节高速多普勒频移进行特殊平滑
  locationManager.pausesLocationUpdatesAutomatically = false // 强制关闭自动休眠，长途平飞不失联
  locationManager.allowsBackgroundLocationUpdates = true
  locationManager.showsBackgroundLocationIndicator = true // 状态栏常驻蓝色胶囊图标，符合 App Store 审核准则
  locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
  locationManager.distanceFilter = kCLDistanceFilterNone
  ```

### 2. 关键飞行阶段“高精黑匣子模式” (Dynamic Blackbox Pump)
- **平飞巡航时**：CoreLocation 的每秒回调足以驱动轻量 EKF 计算与气压采集，此时关闭高耗电线程，整机后台功耗每小时仅消耗约 2%~3% 电量。
- **起飞与着陆阶段（关键 15 分钟）**：
  - 启动极低码率无声白噪声音频缓冲（Audio Background Mode），获得不受系统节流的连续线程执行权。
  - 将 CoreMotion 加速度计与陀螺仪提升至 50Hz/100Hz，毫秒级采样起飞抬头拉起 G 值与着陆接地瞬间的冲击跳跃。
  - 着陆减速至 20 节以下时，自动降级并退出音频守护，回归低功耗。

---

## 三、 零丢失断电保护机制 (Blackbox Storage Engine)

1. **SQLite 预写式日志 (Write-Ahead Logging, WAL)**：
   - 相比传统 CoreData 或全量 JSON 写入，WAL 模式下所有写入追加到 `.wal` 文件中，不阻塞读取，且每次事务提交具备物理持久性（ACID）。
   - 写入策略：
     - 高频传感器帧（50Hz）缓存在内存 RingBuffer（环形缓冲区）中；
     - 每秒（1Hz）执行一次批量事务刷盘（Batch Transaction Commit）；
     - 即使长途飞行中手机电池完全耗尽瞬间黑屏，最大数据损失小于 1 秒，重新开机后数据库毫秒级自动重放（Roll-forward recovery）。
2. **标准航空格式一键导出**：
   - 数据保存在沙盒后，可随时离线导出为通用格式：
     - `.gpx`（航迹记录与海拔）
     - `.kml`（Google Earth 3D 航线拉伸）
     - `.csv`（高频力学原始传感器数据分析）
     - `.igc`（国际航联通用滑翔记录）
