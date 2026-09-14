import AppKit
import Darwin
import Foundation

/// Serializes daemon output away from the Scene main thread. At most one
/// frame-stats payload waits behind a blocked write; newer samples replace it.
private final class SceneDaemonEventWriter: @unchecked Sendable {
    private let output: FileHandle
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-daemon-events",
        qos: .utility
    )
    private let lock = NSLock()
    private var latestStats: Data?
    private var statsWriteScheduled = false

    init(output: FileHandle) {
        self.output = output
    }

    func sendCritical(_ data: Data, completion: (() -> Void)? = nil) {
        queue.async { [output] in
            output.write(data)
            completion?()
        }
    }

    func sendLatestStats(_ data: Data) {
        lock.lock()
        latestStats = data
        let shouldSchedule = !statsWriteScheduled
        statsWriteScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        queue.async { [weak self] in
            self?.writeLatestStatsUntilEmpty()
        }
    }

    private func writeLatestStatsUntilEmpty() {
        while true {
            lock.lock()
            guard let data = latestStats else {
                statsWriteScheduled = false
                lock.unlock()
                return
            }
            latestStats = nil
            lock.unlock()
            output.write(data)
        }
    }
}

/// Scene-specific daemon endpoint. Generic process spawning and retry policy
/// remain M5.3 work; this type owns only the Scene command/event projection.
@MainActor
final class SceneDaemonRuntime {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(
            SceneDaemonProtocol.commandFlag
        )
    }

    private let writer = SceneDaemonEventWriter(output: .standardOutput)
    private var observers: [NSObjectProtocol] = []
    private var statsTimer: DispatchSourceTimer?
    private var currentRequestID: UUID?
    private var lastPropertyRevision: UInt64 = 0
    private var isShuttingDown = false

    deinit {
        statsTimer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure() {
        NSApplication.shared.setActivationPolicy(.accessory)
        emit([
            "v": SceneDaemonProtocol.version,
            "role": "scene-daemon"
        ])
        installObservers()
        installStatsTimer()
        startCommandLoop()
    }

    func loadSceneFromArgumentsIfPresent() {
        guard let rootPath = Self.argumentValue(
            after: SceneDaemonProtocol.sceneRootFlag
        ) else { return }
        handle(.loadScene(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL,
            propertyOverrides: [:],
            profile: .current,
            recordID: nil
        ))
    }

    private func startCommandLoop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty else { continue }
                let result = SceneDaemonProtocol.decodeCommand(Data(line.utf8))
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isShuttingDown else { return }
                    switch result {
                    case let .success(command): self.handle(command)
                    case let .failure(failure):
                        self.emitError(
                            code: failure.code,
                            message: String(describing: failure)
                        )
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.shutdown(exitCode: 0)
            }
        }
    }

    private func handle(_ command: SceneDaemonCommand) {
        switch command {
        case let .loadScene(rootURL, overrides, profile, recordID):
            lastPropertyRevision = 0
            SceneDesktopWallpaperHost.shared.applyPerformanceProfile(profile)
            SceneDesktopWallpaperHost.shared.requestLaunch(
                rootURL: rootURL,
                propertyOverrides: overrides,
                recordID: recordID
            ) { _ in }
        case let .setProperty(values, revision):
            guard revision > lastPropertyRevision,
                  SceneDesktopWallpaperHost.shared.applyUserPropertyValues(
                    values,
                    changedPropertyKeys: Set(values.keys),
                    recordID: SceneDesktopWallpaperHost.shared.activeRecordID
                  ) else {
                emitError(
                    code: "command-rejected",
                    message: "setProperty was stale or unavailable"
                )
                return
            }
            lastPropertyRevision = revision
        case let .setPerformanceProfile(profile):
            SceneDesktopWallpaperHost.shared.applyPerformanceProfile(profile)
        case let .setMuted(muted):
            guard SceneDesktopWallpaperHost.shared.handle(.setMuted(muted)) else {
                emitError(code: "command-rejected", message: "setMuted")
                return
            }
        case .pause:
            guard SceneDesktopWallpaperHost.shared.handle(.pause) else {
                emitError(code: "command-rejected", message: "pause")
                return
            }
        case .resume:
            guard SceneDesktopWallpaperHost.shared.handle(.resume) else {
                emitError(code: "command-rejected", message: "resume")
                return
            }
        case .shutdown:
            shutdown(exitCode: 0)
        }
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let state = notification.object
                    as? SceneWallpaperLaunchState else { return }
            if state.phase == .accepted {
                self.currentRequestID = state.requestID
            }
            self.emit([
                "v": SceneDaemonProtocol.version,
                "event": "launchStateChanged",
                "phase": state.phase.rawValue,
                "message": state.message,
                "requestID": state.requestID.uuidString,
                "recordID": state.recordID ?? NSNull()
            ])
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperFirstFrameDidPresent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let presentation = notification.object
                    as? SceneFramePresentation,
                  presentation.requestID == self.currentRequestID else { return }
            self.emit([
                "v": SceneDaemonProtocol.version,
                "event": "firstFramePresented",
                "requestID": presentation.requestID.uuidString,
                "recordID": presentation.recordID ?? NSNull(),
                "uptimeMs": Double(presentation.uptimeMicros) / 1_000
            ])
        })
    }

    private func installStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            let counters = ScenePerformanceCounterHub.shared.snapshot()
            let rendered = counters[.framesRendered] ?? 0
            var event: [String: Any] = [
                "v": SceneDaemonProtocol.version,
                "event": "frameStats",
                "rendered": rendered,
                "busy": counters[.framesBusy] ?? 0,
                "dropped": counters[.framesDropped] ?? 0,
                "drawCalls": counters[.drawCalls] ?? 0
            ]
            if rendered > 0 {
                event["cpuFrameMs"] = Double(
                    counters[.cpuFrameMicros] ?? 0
                ) / Double(rendered) / 1_000
            }
            guard let data = Self.encode(event) else { return }
            writer.sendLatestStats(data)
        }
        timer.resume()
        statsTimer = timer
    }

    private func shutdown(exitCode: Int32) {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        statsTimer?.cancel()
        statsTimer = nil
        SceneDesktopWallpaperHost.shared.stopAndDrainGPU { [writer] drained in
            let resolvedCode: Int32 = drained ? exitCode : 70
            guard let data = Self.encode([
                "v": SceneDaemonProtocol.version,
                "event": "exited",
                "code": resolvedCode,
                "gpuDrained": drained
            ]) else {
                Darwin.exit(resolvedCode)
            }
            writer.sendCritical(data) {
                Darwin.exit(resolvedCode)
            }
        }
    }

    private func emitError(code: String, message: String) {
        emit([
            "v": SceneDaemonProtocol.version,
            "event": "error",
            "code": code,
            "message": message
        ])
    }

    private func emit(_ payload: [String: Any]) {
        guard let data = Self.encode(payload) else { return }
        writer.sendCritical(data)
    }

    private static func encode(_ payload: [String: Any]) -> Data? {
        try? DaemonNewlineJSON.encodeJSONObject(
            payload,
            options: [.sortedKeys]
        )
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
