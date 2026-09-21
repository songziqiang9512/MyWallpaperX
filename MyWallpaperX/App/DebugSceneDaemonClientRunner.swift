#if DEBUG
import AppKit
import Foundation

/// Isolated shared daemon-control smoke. The default path dispatches directly to
/// the Scene client for control-plane recovery/switch tests. Product-entry mode
/// instead uses SteamWorkshopService -> notification -> MainWindowCoordinator ->
/// multiplexer -> Scene client -> same-binary daemon.
@MainActor
enum DebugSceneDaemonClientRunner {
    private static let flag = "--mwx-debug-scene-daemon-client"
    private static let rootFlag = "--mwx-debug-scene-root"
    private static let evidenceFlag = "--mwx-debug-scene-evidence-dir"
    private static let durationFlag = "--mwx-debug-scene-duration"
    private static let switchRootFlag = "--mwx-debug-scene-switch-root"
    private static let propertyKeyFlag = "--mwx-debug-scene-property-key"
    private static let propertyValueFlag = "--mwx-debug-scene-property-value"
    private static let propertyTypeFlag = "--mwx-debug-scene-property-type"
    private static let startupPropertiesFlag =
        "--mwx-debug-scene-properties-json"
    private static let stableDaemonClientFlag =
        "--mwx-debug-scene-daemon-stable"
    private static let preserveAudioCaptureFlag =
        "--mwx-debug-scene-preserve-audio-capture"
    private static let recordID = "debug-scene-daemon-client"
    private static let switchRecordID = "debug-scene-daemon-client-switch"

    private static var observers: [NSObjectProtocol] = []
    private static var firstPresentRequestIDs: [String] = []
    private static var firstPresentRecordIDs: [String] = []
    private static var daemonProcessIDs: [Int32] = []
    private static var latestStats: SceneDaemonFrameStats?
    private static var failures: [String] = []
    private static var didForceTerminate = false
    private static var didRequestSwitch = false
    private static var audioSpectrumDemand: SceneAudioSpectrumCaptureDemand?
    private static var audioSpectrumDemandEvents: [
        SceneAudioSpectrumCaptureDemand
    ] = []
    private static var audioSpectrumPublications: [
        SceneDaemonAudioSpectrumPublication
    ] = []
    private static var evidenceDirectory: URL?

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
            && argumentValue(after: rootFlag) != nil
    }

    static var requiresProductCoordinator: Bool {
        DebugSceneProductEntryPolicy.requiresProductCoordinator(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    static func scheduleIfRequested() {
        guard isRequested, let rootPath = argumentValue(after: rootFlag) else {
            return
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard let realWorkshopRoot = DebugSceneProductEntryPolicy
            .protectedWorkshopRootURL() else {
            NSLog("MWX SCENE CLIENT: phase=precondition-failed reason=account-home-unavailable")
            NSApp.terminate(nil)
            return
        }
        let realSampleRoot = realWorkshopRoot
            .appendingPathComponent("Scene", isDirectory: true).path
        guard !rootURL.path.hasPrefix(realSampleRoot + "/") else {
            NSLog("MWX SCENE CLIENT: phase=precondition-failed reason=isolated-root-required")
            NSApp.terminate(nil)
            return
        }
        if let switchRootURL,
           switchRootURL.path.hasPrefix(realSampleRoot + "/") {
            NSLog("MWX SCENE CLIENT: phase=precondition-failed reason=isolated-switch-root-required")
            NSApp.terminate(nil)
            return
        }
        evidenceDirectory = argumentValue(after: evidenceFlag).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        guard let startupPropertyOverrides = DebugScenePlaybackRunner
                .strictRequestedPropertyValues(
                    after: startupPropertiesFlag
                ) else {
            NSLog("MWX SCENE CLIENT: phase=precondition-failed reason=invalid-startup-properties")
            NSApp.terminate(nil)
            return
        }
        if let evidenceDirectory {
            try? FileManager.default.createDirectory(
                at: evidenceDirectory,
                withIntermediateDirectories: true
            )
            NSApp.activate(ignoringOtherApps: true)
            WallpaperEngine.shared.updateSettings(
                pauseWhenOtherAppFocused: false,
                pauseWhenOtherAppFullscreen: false,
                pauseWhenUnplugged: false,
                pauseWhenIdle: false,
                idleTimeoutMinutes: 10
            )
        }
        installObservers()
        let issued: Bool
        if runsProductEntry {
            issued = requestThroughSteamWorkshopProductEntry(
                rootURL: rootURL,
                propertyOverrides: startupPropertyOverrides
            )
        } else {
            issued = PlaybackCommandMultiplexer.shared.dispatch(
                .loadScene(.init(
                    rootURL: rootURL,
                    propertyOverrides: [:],
                    userPropertyTextures: [:],
                    recordID: recordID
                )),
                to: .scene
            )
        }
        NSLog(
            "MWX SCENE CLIENT: phase=load-dispatched entry=%@ issued=%@ root=%@",
            runsProductEntry ? "steam-workshop-product" : "direct-client",
            issued ? "true" : "false",
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
                      validRecordIDs.contains(state.recordID ?? "") else { return }
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
                      let presentedRecordID = presentation.recordID,
                      validRecordIDs.contains(presentedRecordID) else { return }
                firstPresentRequestIDs.append(
                    presentation.requestID.uuidString
                )
                firstPresentRecordIDs.append(presentedRecordID)
                if let processIdentifier = SceneDaemonClient.shared
                    .debugProcessIdentifier {
                    daemonProcessIDs.append(processIdentifier)
                }
                NSLog(
                    "MWX SCENE CLIENT: phase=first-present count=%d record=%@ request=%@ pid=%d",
                    firstPresentRequestIDs.count,
                    presentedRecordID,
                    presentation.requestID.uuidString,
                    SceneDaemonClient.shared.debugProcessIdentifier ?? -1
                )
                if let switchRootURL {
                    guard presentedRecordID == recordID,
                          !didRequestSwitch else {
                        PlaybackCommandMultiplexer.shared.dispatch(
                            .setPerformanceProfile(maxFPS: 60),
                            to: .scene
                        )
                        return
                    }
                    didRequestSwitch = true
                    exerciseControlCommands(
                        preservingAudioCapture:
                            preservesAudioCaptureDuringSwitch
                    )
                    let switchDelay = preservesAudioCaptureDuringSwitch
                        ? 2.0
                        : 1.0
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + switchDelay
                    ) {
                        let accepted = PlaybackCommandMultiplexer.shared.dispatch(
                            .loadScene(.init(
                                rootURL: switchRootURL,
                                propertyOverrides: [:],
                                userPropertyTextures: [:],
                                recordID: switchRecordID
                            )),
                            to: .scene
                        )
                        NSLog(
                            "MWX SCENE CLIENT: phase=switch-dispatched accepted=%@ root=%@",
                            accepted ? "true" : "false",
                            switchRootURL.path
                        )
                    }
                    return
                }
                // Stable mode preserves the shared daemon-client downstream.
                // Ordinary UI/Steam entry and daemon recovery remain separate
                // probes with distinct evidence ceilings.
                if runsStableDaemonClient {
                    return
                }
                guard !didForceTerminate else {
                    PlaybackCommandMultiplexer.shared.dispatch(
                        .setPerformanceProfile(maxFPS: 60),
                        to: .scene
                    )
                    return
                }
                didForceTerminate = true
                exerciseControlCommands(preservingAudioCapture: false)
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
            forName: .sceneDaemonAudioSpectrumDemandDidChange,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let demand = notification.object
                        as? SceneAudioSpectrumCaptureDemand else { return }
                audioSpectrumDemand = demand
                audioSpectrumDemandEvents.append(demand)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneDaemonAudioSpectrumDidPublish,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let publication = notification.object
                        as? SceneDaemonAudioSpectrumPublication else { return }
                audioSpectrumPublications.append(publication)
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
        let client = SceneDaemonClient.shared
        let observedDemand = audioSpectrumDemand ?? client.audioSpectrumDemand
        let observedStats = latestStats ?? client.latestFrameStats
        let uniqueRequests = Set(firstPresentRequestIDs)
        let uniquePIDs = Set(daemonProcessIDs)
        let switchCompleted = switchRootURL != nil
            && Set(firstPresentRecordIDs) == [recordID, switchRecordID]
            && uniqueRequests.count >= 2 && uniquePIDs.count == 1
        let recovered = switchRootURL == nil
            && uniqueRequests.count >= 2 && uniquePIDs.count >= 2
        var result: [String: Any] = [
            "firstPresentCount": firstPresentRequestIDs.count,
            "firstPresentRecordIDs": firstPresentRecordIDs,
            "uniqueRequestCount": uniqueRequests.count,
            "daemonProcessIDs": daemonProcessIDs,
            "recoveredAfterForcedTermination": recovered,
            "switchCompletedInSameDaemon": switchCompleted,
            "stableDaemonClientRequested": runsStableDaemonClient,
            "preserveAudioCaptureDuringSwitch":
                preservesAudioCaptureDuringSwitch,
            "sampleID": requestedSampleID,
            "startupPropertyOverrides": (
                DebugScenePlaybackRunner.strictRequestedPropertyValues(
                    after: startupPropertiesFlag
                ) ?? [:]
            ).mapValues(\.foundationValue),
            "launchEntry": runsProductEntry
                ? "steam-workshop-product"
                : "direct-client",
            "launchPhase": client.launchState?.phase.rawValue ?? "none",
            "activeRecordID": client.activeRecordID ?? NSNull(),
            "daemonProcessID": client.debugProcessIdentifier.map { Int($0) }
                ?? NSNull(),
            "audioSpectrumDemanded": observedDemand.requiresSpectrum,
            "audioSpectrumScopeEpoch": observedDemand.scopeEpoch,
            "audioSpectrumDemandEvents": audioSpectrumDemandEvents.map {
                [
                    "requiresSpectrum": $0.requiresSpectrum,
                    "includesCurrentProcessOutput":
                        $0.includesCurrentProcessOutput,
                    "scopeEpoch": $0.scopeEpoch
                ] as [String: Any]
            },
            "audioSpectrumPublicationCount": audioSpectrumPublications.count,
            "audioSpectrumPublicationPeaks": audioSpectrumPublications.map(\.peak),
            "failures": failures
        ]
        if let observedStats {
            result["latestStats"] = [
                "rendered": observedStats.rendered,
                "busy": observedStats.busy,
                "dropped": observedStats.dropped,
                "drawCalls": observedStats.drawCalls,
                "pipelineStateBinds": observedStats.pipelineStateBinds,
                "geometryDrawCalls": observedStats.geometryDrawCalls,
                "fallbackBranches": observedStats.fallbackBranches,
                "gpuAllocatedBytes": observedStats.gpuAllocatedBytes,
                "renderTargetPoolBytes": observedStats.renderTargetPoolBytes,
                "cpuFrameMs": observedStats.cpuFrameMs.map { $0 as Any }
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
        if switchRootURL != nil {
            NSApp.terminate(nil)
        } else {
            SceneDaemonClient.shared.shutdown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }

    private static var duration: TimeInterval {
        guard let raw = argumentValue(after: durationFlag),
              let value = TimeInterval(raw), value >= 5 else { return 15 }
        return value
    }

    private static var switchRootURL: URL? {
        argumentValue(after: switchRootFlag).map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
        }
    }

    private static var validRecordIDs: Set<String> {
        switchRootURL == nil ? [recordID] : [recordID, switchRecordID]
    }

    private static var runsStableDaemonClient: Bool {
        ProcessInfo.processInfo.arguments.contains(stableDaemonClientFlag)
    }

    /// The general switch smoke deliberately exercises pause/resume, which
    /// suspends the system tap by contract. Audio-demand continuity evidence
    /// opts out of only those controls so an unexpected tap retirement cannot
    /// be hidden by the runner itself.
    private static var preservesAudioCaptureDuringSwitch: Bool {
        switchRootURL != nil
            && ProcessInfo.processInfo.arguments.contains(
                preserveAudioCaptureFlag
            )
    }

    private static var runsProductEntry: Bool {
        requiresProductCoordinator
    }

    private static var requestedSampleID: String {
        argumentValue(after: rootFlag).map {
            URL(fileURLWithPath: $0, isDirectory: true).lastPathComponent
        } ?? ""
    }

    private static func requestThroughSteamWorkshopProductEntry(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue]
    ) -> Bool {
        let fileManager = FileManager.default
        guard let realUserHome = DebugSceneProductEntryPolicy
                .protectedUserHomeURL(),
              let realWorkshopRoot = DebugSceneProductEntryPolicy
                .protectedWorkshopRootURL(),
              runsStableDaemonClient,
              switchRootURL == nil,
              let rawWorkshopRoot = argumentValue(
                after: "--mwx-debug-workshop-root"
              ),
              DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: rawWorkshopRoot,
                disjointFrom: realWorkshopRoot,
                fileManager: fileManager
              ) != nil,
              DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: rootURL.path,
                disjointFrom: realWorkshopRoot,
                fileManager: fileManager
              ) != nil,
              let fixedHome = ProcessInfo.processInfo.environment[
                "CFFIXED_USER_HOME"
              ],
              DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: fixedHome,
                disjointFrom: realUserHome,
                fileManager: fileManager
              ) != nil,
              argumentValue(after: "--mwx-debug-user-defaults-suite")
                .map({ $0.hasPrefix("com.songziqiang.MyWallpaperX.Debug.") })
                == true,
              fileManager.fileExists(
                atPath: rootURL.appendingPathComponent("project.json").path
              ) else { return false }
        let record = SteamWorkshopDownloadRecord(
            id: recordID,
            title: rootURL.lastPathComponent,
            description: "Isolated Scene product-entry evidence",
            tags: ["Scene"],
            folderURL: rootURL,
            projectFileURL: rootURL.appendingPathComponent("project.json"),
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: nil,
            sourceVideoURL: nil,
            exportedVideoURL: nil,
            updatedAt: Date(),
            sizeText: "",
            status: .ready,
            browserItem: nil,
            contentType: .scene,
            dependencyItemID: nil,
            dependencyStatus: .none
        )
        let service = SteamWorkshopService.shared
        if propertyOverrides.isEmpty {
            service.requestSceneRender(record)
            return true
        }
        return service.debugRequestSceneRender(
            record,
            temporaryPropertyOverrides: propertyOverrides
        )
    }

    private static func exerciseControlCommands(
        preservingAudioCapture: Bool
    ) {
        DebugSceneDaemonSwitchControlPolicy.exercise(
            preservingAudioCapture: preservingAudioCapture,
            dispatchPropertyUpdate: dispatchRequestedPropertyUpdate,
            dispatchPerformanceProfile: {
                PlaybackCommandMultiplexer.shared.dispatch(
                    .setPerformanceProfile(maxFPS: 30),
                    to: .scene
                )
            },
            dispatchAudioLifecycleControls: {
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
                    PlaybackCommandMultiplexer.shared.dispatch(
                        .resume,
                        to: .scene
                    )
                }
            }
        )
    }

    private static func dispatchRequestedPropertyUpdate() {
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
