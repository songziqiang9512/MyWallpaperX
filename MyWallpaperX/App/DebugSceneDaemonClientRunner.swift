#if DEBUG
import AppKit
import Foundation

/// Isolated product-control smoke: App command -> Scene client -> same-binary
/// daemon. It also kills the first child after present so restart/replay is
/// exercised without reaching into renderer internals.
@MainActor
enum DebugSceneDaemonClientRunner {
    private static let flag = "--mwx-debug-scene-daemon-client"
    private static let rootFlag = "--mwx-debug-scene-root"
    private static let evidenceFlag = "--mwx-debug-scene-evidence-dir"
    private static let durationFlag = "--mwx-debug-scene-duration"
    private static let propertyKeyFlag = "--mwx-debug-scene-property-key"
    private static let propertyValueFlag = "--mwx-debug-scene-property-value"
    private static let propertyTypeFlag = "--mwx-debug-scene-property-type"
    private static let recordID = "debug-scene-daemon-client"

    private static var observers: [NSObjectProtocol] = []
    private static var firstPresentRequestIDs: [String] = []
    private static var daemonProcessIDs: [Int32] = []
    private static var latestStats: SceneDaemonFrameStats?
    private static var failures: [String] = []
    private static var didForceTerminate = false
    private static var evidenceDirectory: URL?

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
            && argumentValue(after: rootFlag) != nil
    }

    static func scheduleIfRequested() {
        guard isRequested, let rootPath = argumentValue(after: rootFlag) else {
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let realSampleRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/MyWallpaperX/创意工坊/Scene")
            .standardizedFileURL.path
        guard !rootURL.path.hasPrefix(realSampleRoot + "/") else {
            NSLog("MWX SCENE CLIENT: phase=precondition-failed reason=isolated-root-required")
            NSApp.terminate(nil)
            return
        }
        evidenceDirectory = argumentValue(after: evidenceFlag).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        if let evidenceDirectory {
            try? FileManager.default.createDirectory(
                at: evidenceDirectory,
                withIntermediateDirectories: true
            )
        }
        installObservers()
        let accepted = PlaybackCommandMultiplexer.shared.dispatch(
            .loadScene(.init(
                rootURL: rootURL,
                propertyOverrides: [:],
                userPropertyTextures: [:],
                recordID: recordID
            )),
            to: .scene
        )
        NSLog(
            "MWX SCENE CLIENT: phase=load-dispatched accepted=%@ root=%@",
            accepted ? "true" : "false",
            rootURL.path
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            finish()
        }
    }

    private static func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let state = notification.object as? SceneWallpaperLaunchState,
                      state.recordID == recordID else { return }
                NSLog(
                    "MWX SCENE CLIENT: phase=launch-state state=%@ request=%@",
                    state.phase.rawValue,
                    state.requestID.uuidString
                )
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperFirstFrameDidPresent,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let presentation = notification.object
                        as? SceneFramePresentation,
                      presentation.recordID == recordID else { return }
                firstPresentRequestIDs.append(
                    presentation.requestID.uuidString
                )
                if let processIdentifier = SceneDaemonClient.shared
                    .debugProcessIdentifier {
                    daemonProcessIDs.append(processIdentifier)
                }
                NSLog(
                    "MWX SCENE CLIENT: phase=first-present count=%d request=%@ pid=%d",
                    firstPresentRequestIDs.count,
                    presentation.requestID.uuidString,
                    SceneDaemonClient.shared.debugProcessIdentifier ?? -1
                )
                guard !didForceTerminate else {
                    PlaybackCommandMultiplexer.shared.dispatch(
                        .setPerformanceProfile(maxFPS: 60),
                        to: .scene
                    )
                    return
                }
                didForceTerminate = true
                if let propertyKey = argumentValue(after: propertyKeyFlag),
                   let propertyValue = debugPropertyValue {
                    let propertyAccepted = PlaybackCommandMultiplexer.shared.dispatch(
                        .setProperty(
                            [propertyKey: propertyValue],
                            revision: 1,
                            recordID: recordID
                        ),
                        to: .scene
                    )
                    NSLog(
                        "MWX SCENE CLIENT: phase=property-update key=%@ accepted=%@ revision=1",
                        propertyKey,
                        propertyAccepted ? "true" : "false"
                    )
                }
                PlaybackCommandMultiplexer.shared.dispatch(
                    .setPerformanceProfile(maxFPS: 30),
                    to: .scene
                )
                PlaybackCommandMultiplexer.shared.dispatch(
                    .setMuted(true),
                    to: .scene
                )
                PlaybackCommandMultiplexer.shared.dispatch(.pause, to: .scene)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    PlaybackCommandMultiplexer.shared.dispatch(
                        .setMuted(false),
                        to: .scene
                    )
                    PlaybackCommandMultiplexer.shared.dispatch(.resume, to: .scene)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let killed = SceneDaemonClient.shared
                        .debugForceTerminateDaemon()
                    NSLog(
                        "MWX SCENE CLIENT: phase=forced-termination sent=%@",
                        killed ? "true" : "false"
                    )
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneDaemonFrameStatsDidChange,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                latestStats = notification.object as? SceneDaemonFrameStats
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneDaemonClientDidFail,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let failure = notification.object
                        as? SceneDaemonClientFailure else { return }
                failures.append("\(failure.code):\(failure.message)")
                NSLog(
                    "MWX SCENE CLIENT: phase=client-event code=%@ message=%@",
                    failure.code,
                    failure.message
                )
            }
        })
    }

    private static func finish() {
        let uniqueRequests = Set(firstPresentRequestIDs)
        let uniquePIDs = Set(daemonProcessIDs)
        let recovered = uniqueRequests.count >= 2 && uniquePIDs.count >= 2
        var result: [String: Any] = [
            "firstPresentCount": firstPresentRequestIDs.count,
            "uniqueRequestCount": uniqueRequests.count,
            "daemonProcessIDs": daemonProcessIDs,
            "recoveredAfterForcedTermination": recovered,
            "failures": failures
        ]
        if let latestStats {
            result["latestStats"] = [
                "rendered": latestStats.rendered,
                "busy": latestStats.busy,
                "dropped": latestStats.dropped,
                "drawCalls": latestStats.drawCalls,
                "cpuFrameMs": latestStats.cpuFrameMs.map { $0 as Any }
                    ?? NSNull()
            ]
        }
        if let evidenceDirectory,
           let data = try? JSONSerialization.data(
                withJSONObject: result,
                options: [.prettyPrinted, .sortedKeys]
           ) {
            try? data.write(
                to: evidenceDirectory.appendingPathComponent(
                    "scene-daemon-client-result.json"
                )
            )
        }
        NSLog(
            "MWX SCENE CLIENT: phase=finished recovered=%@ presents=%d pids=%d",
            recovered ? "true" : "false",
            firstPresentRequestIDs.count,
            uniquePIDs.count
        )
        SceneDaemonClient.shared.shutdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    private static var duration: TimeInterval {
        guard let raw = argumentValue(after: durationFlag),
              let value = TimeInterval(raw), value >= 5 else { return 15 }
        return value
    }

    private static var debugPropertyValue: SceneUserPropertyValue? {
        guard let rawValue = argumentValue(after: propertyValueFlag) else {
            return nil
        }
        switch argumentValue(after: propertyTypeFlag) ?? "string" {
        case "number":
            guard let value = Double(rawValue), value.isFinite else { return nil }
            return .number(value)
        case "bool":
            switch rawValue.lowercased() {
            case "true", "1": return .bool(true)
            case "false", "0": return .bool(false)
            default: return nil
            }
        case "string":
            return .string(rawValue)
        default:
            return nil
        }
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
