import AppKit
import Foundation

/// M5.2：同二进制 daemon 模式的运行时（契约
/// docs/scene/scene-runtime-daemon-contract.md §2-§4）。
/// stdin 逐行命令 → WallpaperEngineCommand → Scene 引擎处理端；
/// 引擎事件（launch 阶段/首帧/frameStats）→ stdout 逐行 JSON。
/// 本类型仅运行于 daemon 进程（`--mwx-scene-daemon`），不进主程序路径。
@MainActor
final class SceneDaemonRuntime {
    struct ProtocolConstants {
        static let versionLine = #"{"v":1,"role":"scene-daemon"}"#
        static let commandFlag = "--mwx-scene-daemon"
        static let sceneRootFlag = "--mwx-scene-root"
    }

    private let stdout = FileHandle.standardOutput
    private let writeLock = NSLock()
    private var hasEmittedVersionHandshake = false
    /// launch 阶段观测者；daemon 生命周期内常驻。
    private var launchStateObserver: NSObjectProtocol?
    private var firstFrameObserver: NSObjectProtocol?
    private var statsTimer: DispatchSourceTimer?
    /// launch 入口的单调时间，用于 firstFramePresented 相对耗时。
    private var launchStartUptime: UInt64?
    private var hasEmittedFirstFrame = false

    var isDaemonModeRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(
            ProtocolConstants.commandFlag
        )
    }

    func sceneRootArgument() -> String? {
        Self.argumentValue(after: ProtocolConstants.sceneRootFlag)
    }

    /// daemon 主入口：配置 accessory App、装订事件流、启动 stdin 循环。
    /// 调用方随后进入 NSApp.run()（主线程 runloop 承载帧驱动与事件分发）。
    func configureAndRun() -> NSApplication {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        hasEmittedVersionHandshake = false
        emitHandshakeIfNeeded()
        installLaunchStateObserver()
        installFirstFrameForwarding()
        installStatsTimer()
        startStdinCommandLoop()
        return app
    }

    /// 由 launch 参数直接装载场景（daemon 启动即播）。
    func loadSceneFromArguments() {
        guard let rootPath = sceneRootArgument() else { return }
        launchStartUptime = ScenePerformanceCounterHub.nowUptimeMicros()
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        SceneDesktopWallpaperHost.shared.handle(.loadScene(
            rootURL: rootURL, propertyOverrides: [:]
        ))
    }

    // MARK: - 命令循环（stdin）

    private func startStdinCommandLoop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine(strippingNewline: true) {
                guard let self, !line.isEmpty else { continue }
                guard let data = line.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(
                          with: data
                      ) as? [String: Any],
                      let command = Self.command(from: payload) else {
                    Self.emitRaw(
                        #"{"v":1,"event":"error","message":"unparseable-command"}"#
                    )
                    continue
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    _ = SceneDesktopWallpaperHost.shared.handle(command)
                    if command == .stop {
                        self.emitShutdownAndTerminate()
                    }
                }
            }
            // stdin EOF（主程序关闭管道）：有序退出。
            DispatchQueue.main.async { [weak self] in
                self?.emitShutdownAndTerminate()
            }
        }
    }

    private static func command(
        from payload: [String: Any]
    ) -> WallpaperEngineCommand? {
        guard let action = payload["cmd"] as? String else { return nil }
        switch action {
        case "loadScene":
            guard let root = payload["rootURL"] as? String else { return nil }
            let overrides = payload["propertyOverrides"]
                as? [String: String] ?? [:]
            return .loadScene(
                rootURL: URL(fileURLWithPath: root),
                propertyOverrides: overrides
            )
        case "setProperty":
            guard let values = payload["values"] as? [String: String] else {
                return nil
            }
            return .setProperty(
                values, revision: payload["revision"] as? UInt64 ?? 0
            )
        case "setPerformanceProfile":
            guard let fps = payload["maxFPS"] as? Int else { return nil }
            return .setPerformanceProfile(maxFPS: fps)
        case "setMuted":
            guard let muted = payload["muted"] as? Bool else { return nil }
            return .setMuted(muted)
        case "pause": return .pause
        case "resume": return .resume
        case "switchNext": return .switchNext
        case "shutdown": return .stop
        default: return nil
        }
    }

    // MARK: - 事件输出

    private func emitHandshakeIfNeeded() {
        writeLock.lock()
        defer { writeLock.unlock() }
        if !hasEmittedVersionHandshake {
            stdout.write(Data(ProtocolConstants.versionLine.utf8) + Data([0x0A]))
            hasEmittedVersionHandshake = true
        }
    }

    private func emitEvent(_ payload: [String: Any]) {
        var envelope: [String: Any] = ["v": 1]
        for (key, value) in payload { envelope[key] = value }
        guard let data = try? JSONSerialization.data(
            withJSONObject: envelope, options: [.sortedKeys]
        ) else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        stdout.write(data + Data([0x0A]))
    }

    private static func emitRaw(_ line: String) {
        FileHandle.standardOutput.write(Data(line.utf8) + Data([0x0A]))
    }

    private func installLaunchStateObserver() {
        launchStateObserver = NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let state = notification.object
                      as? SceneWallpaperLaunchState else { return }
            emitEvent([
                "event": "launchStateChanged",
                "phase": state.phase.rawValue,
                "recordID": state.recordID ?? "",
                "message": state.message
            ])
        }
    }

    private func installFirstFrameForwarding() {
        firstFrameObserver = NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            // 首帧事件由 hub 首次 firstVisibleFrame 记录驱动（1Hz tick
            // 内），此处直接查 hub，避免与 5s 结构化日志争拍。
            guard let self,
                  let first = ScenePerformanceCounterHub.shared
                      .launchPhaseSnapshot()[.firstVisibleFrame],
                  self.launchStartUptime == nil || self
                      .hasEmittedVersionHandshake else { return }
            _ = first
        }
        // 首帧转发以 1Hz stats 计时器轮询 hub 首次记录为准（见下）。
    }

    private func installStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let snapshot = ScenePerformanceCounterHub.shared.snapshot()
            var payload: [String: Any] = [
                "event": "frameStats",
                "rendered": snapshot[.framesRendered] ?? 0,
                "busy": snapshot[.framesBusy] ?? 0,
                "dropped": snapshot[.framesDropped] ?? 0,
                "drawCalls": snapshot[.drawCalls] ?? 0
            ]
            if let cpu = snapshot[.cpuFrameMicros],
               let frames = snapshot[.framesRendered], frames > 0 {
                payload["cpuFrameMs"] = Double(cpu) / Double(frames) / 1000
            }
            emitEvent(payload)

            if hasEmittedFirstFrame { return }
            if ScenePerformanceCounterHub.shared
                .launchPhaseSnapshot()[.firstVisibleFrame] != nil {
                hasEmittedFirstFrame = true
                emitEvent([
                    "event": "firstFramePresented"
                ])
            }
        }
        timer.resume()
        statsTimer = timer
    }

    private func emitShutdownAndTerminate() {
        emitEvent(["event": "exited"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exit(0)
        }
    }

    static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
