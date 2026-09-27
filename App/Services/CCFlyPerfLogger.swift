import Foundation
import OSLog

public final class CCFlyPerfLogger {
    private static var startTimes: [String: ContinuousClock.Instant] = [:]
    private static let lock = NSLock()

    public static func begin(_ name: String) {
        lock.lock()
        startTimes[name] = ContinuousClock.now
        lock.unlock()
        print("⏱️ [PERF_BEGIN] [\(name)]")
    }

    public static func end(_ name: String) {
        lock.lock()
        let start = startTimes[name]
        lock.unlock()
        if let start = start {
            let duration = start.duration(to: .now)
            let ms = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
            print("⏱️ [PERF_END] [\(name)] 耗时: \(String(format: "%.2f", ms)) ms (主线程: \(Thread.isMainThread))")
        } else {
            print("⏱️ [PERF_END] [\(name)] (无起始时间)")
        }
    }

    public static func mark(_ message: String) {
        print("⏱️ [PERF_MARK] \(message) (主线程: \(Thread.isMainThread))")
    }
}

/// 主线程卡顿阻塞探针 (捕获任何 >50ms 的主线程冻结)
public final class MainThreadHitchMonitor {
    private static var isRunning = false
    private static let thresholdMs: Double = 50.0

    public static func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true

        let thread = Thread {
            while true {
                let sema = DispatchSemaphore(value: 0)
                let start = ContinuousClock.now
                DispatchQueue.main.async {
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 10.0)
                let duration = start.duration(to: .now)
                let elapsedMs = Double(duration.components.seconds) * 1000.0 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0

                if elapsedMs > thresholdMs {
                    print("🚨 [HITCH_DETECTED] 主线程严重卡顿挂起! 耗时: \(String(format: "%.1f", elapsedMs)) ms (当前时间: \(Date()))")
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "CCFlyMainThreadHitchMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

