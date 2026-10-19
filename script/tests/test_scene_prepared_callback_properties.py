"""Prepared callback rows and launch identity use the real responsible methods.

VM export discovery is covered by the existing QuickJS owner/live-property gates.
This gate supplies their prepared consumer tables and transport/UI leaves only;
it executes production session projection, Client launch/stop/replay/termination,
and the original LiveState type/atomic/revision authority without creating an App.
"""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
MODELS = SCENE / 'Runtime/Session/SceneDesktopWallpaperLaunchModels.swift'
CLIENT = SCENE / 'Runtime/IPC/SceneDaemonClient.swift'
EVENTS = SCENE / 'Runtime/IPC/SceneDaemonClient+Events.swift'


PROJECTION = r'''
import Foundation
struct PreparedScriptProgram { var generation: UInt64 = 7 }
struct SceneDesktopWallpaperLaunchContext {
    var liveState: ScenePropertyLiveUpdateState
    var propertyVectorScriptProgram = PreparedScriptProgram()
    var sceneScriptScalarProgram = PreparedScriptProgram()
    var sceneScriptStringProgram = PreparedScriptProgram()
}
final class SceneDesktopWallpaperSession {
    struct Surface { var scriptGeneration: UInt64 = 7 }
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var surfaces: [Int: Surface] = [1: .init(), 2: .init()]
    var preparedSurfaceIDs: Set<Int> = [1, 2]
    var unavailable: Set<SceneDynamicTarget> = []
    var retired: Set<SceneDynamicTarget> = []
    func unavailableLiveConsumerTargets(in context: SceneDesktopWallpaperLaunchContext) -> Set<SceneDynamicTarget> { unavailable }
    func retiredPropertyCallbackTargets(in context: SceneDesktopWallpaperLaunchContext,
        propertyKeys: Set<String>) -> Set<SceneDynamicTarget> { retired }
    __PROJECTION__
}
@main enum ProjectionProbe {
    static func main() throws {
        var results: [String: Bool] = [:]
        let target = SceneDynamicTarget.layer(layerID: 17, field: .visibility)
        let second = SceneDynamicTarget.layer(layerID: 23, field: .alpha)
        func definition(_ key: String, _ kind: SceneUserPropertyKind, _ value: SceneUserPropertyValue?) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue, order: 0, index: nil,
                minimumValue: nil, maximumValue: nil, stepValue: nil, allowsFractionalValues: true,
                fractionalPrecision: nil, displayCondition: nil, defaultValue: value, options: [])
        }
        let definitions = [definition("choice", .combo, .string("play")),
            definition("renamed_choice", .combo, .number(0)), definition("flag", .bool, .bool(false)),
            definition("rate", .slider, .number(1)), definition("tint", .color, .string("1 1 1")),
            definition("caption", .textInput, .string("own")), definition("cover", .sceneTexture, .string("own.png")),
            definition("future", .unsupported, .string("x")), definition("missing_default", .bool, nil),
            definition("wrong_type", .bool, .number(0)), definition("duplicate", .bool, .bool(false)),
            definition("duplicate", .bool, .bool(true)), definition("empty", .combo, .string("off"))]
        var values = Dictionary(definitions.compactMap { d in d.defaultValue.map { (d.key, $0) } }, uniquingKeysWith: { a, _ in a })
        values["empty"] = .string("off")
        let program = ScenePropertyBindingProgram(definitions: [], instructions: [])
        var consumers = Dictionary(uniqueKeysWithValues: Set(definitions.map(\.key)).map { ($0, Set([target])) })
        consumers["empty"] = []
        let session = SceneDesktopWallpaperSession()
        func state(_ replacementProgram: ScenePropertyBindingProgram? = nil,
                   _ active: Set<SceneDynamicTarget>? = nil) -> ScenePropertyLiveUpdateState {
            .init(program: replacementProgram ?? program, effectiveValues: values, activeConsumerTargets: active ?? [target],
                scriptUserPropertyConsumerTargetsByKey: consumers, propertyDefinitions: definitions)
        }
        session.launchContext = .init(liveState: state())
        let ordinary: Set<String> = ["choice", "renamed_choice", "flag", "rate", "tint", "caption"]
        results["ordinary-callback-only-keys"] = session.preparedCallbackPropertyKeys(definitions: definitions) == ordinary
        results["projection-does-not-edit-values-or-revision"] = session.launchContext!.liveState.revision == 0
            && session.launchContext!.liveState.effectiveValues == values
        var live = session.launchContext!.liveState
        results["same-value-stable"] = live.apply(.string("play"), forPropertyKey: "choice") && live.revision == 0
        results["ordinary-change-and-reset"] = live.apply(.string("pause"), forPropertyKey: "choice")
            && live.apply(.string("play"), forPropertyKey: "choice") && live.revision == 2
        let before = live
        results["wrong-type-remains-atomic"] = !live.apply(.number(1), forPropertyKey: "choice")
            && live.revision == before.revision && live.effectiveValues == before.effectiveValues
        session.unavailable = [target]
        results["unavailable-owner-withdraws-all-keys"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        results["unavailable-update-still-rejected"] = !live.apply(.string("pause"), forPropertyKey: "choice", unavailableConsumerTargets: [target])
        session.unavailable = []
        session.retired = [target]
        results["retired-callbacks-not-advertised"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        session.retired = []
        session.surfaces.removeValue(forKey: 2)
        results["partial-surfaces-rejected"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        session.surfaces[2] = .init(scriptGeneration: 6)
        results["stale-surface-rejected"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        session.surfaces[2] = .init()
        session.launchContext!.sceneScriptStringProgram.generation = 6
        results["mixed-program-generation-rejected"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        let rebuilt = ScenePropertyBindingProgram(definitions: [], instructions: [], rebuildRequiredPropertyKeys: ["choice"])
        session.launchContext = .init(liveState: state(rebuilt))
        results["rebuild-key-not-advertised-even-at-default"] = !session.preparedCallbackPropertyKeys(definitions: definitions).contains("choice")
        let mixed = ScenePropertyBindingProgram(definitions: [.init(target: second, valueType: .scalar, authoredValue: .scalar(1))],
            instructions: [.init(propertyKey: "rate", path: .init(components: [.key("rate")]), target: second, valueType: .scalar)])
        session.launchContext = .init(liveState: state(mixed))
        results["mixed-static-consumer-must-also-be-active"] = !session.preparedCallbackPropertyKeys(definitions: definitions).contains("rate")
        consumers["choice"] = [target, second]
        session.launchContext = .init(liveState: state())
        results["all-callback-consumers-required"] = !session.preparedCallbackPropertyKeys(definitions: definitions).contains("choice")
        consumers = [:]
        session.launchContext = .init(liveState: state())
        results["no-callback-does-not-advertise-catalog"] = session.preparedCallbackPropertyKeys(definitions: definitions).isEmpty
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
'''


CLIENT_LEAVES = r'''
import Foundation
struct ScenePlaybackLoadRequest {
    var rootURL: URL; var recordID: String?
    var propertyOverrides: [String: SceneUserPropertyValue] = [:]
    var userPropertyTextures: [String: Texture] = [:]
    var requiredUserTextureKeys: Set<String> = []
    struct Texture { var url: URL; var bookmarkData: Data? }
}
enum ScenePlaybackTextureUpdateOutcome { case superseded, failed(String) }
enum SceneDaemonProtocol { static let version = 1 }
enum DaemonNewlineJSON { static func encodeJSONObject(_ value: [String: Any], options: JSONSerialization.WritingOptions) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: options) } }
struct PlaybackVolumeState { static let shared = Self(); let normalizedVolume = 1.0 }
struct PlaybackMuteState { static let shared = Self(); let isMuted = false }
struct SceneFramePresentation {let requestID:UUID;let recordID:String?;let uptimeMicros:UInt64}
extension Notification.Name {static let sceneWallpaperFirstFrameDidPresent=Notification.Name("first-present")}
@MainActor final class SceneDaemonClient {
    final class Transport {
        var isRunning = true
        func closeIO() {}; func send(_ data: Data) {}; func closeInput() {}
        func terminate() {}; func scheduleForcedTermination(after: Double) {}
        func requestGracefulStop(_ data: Data?) { isRunning = false }
    }
    struct Lifetime { let lifetime: Int }
    struct Backoff { mutating func reset() {} }
    var transport: Transport? = .init(), retiringTransports: [UInt64: Transport] = [:]
    var retiringResourceLifetimes: [UInt64: [Int]] = [:]
    var expectedTerminationGenerations: Set<UInt64> = []
    var sessionGeneration: UInt64 = 1
    var endpointReady = true
    var launchState: SceneWallpaperLaunchState?
    var activeIntent: ScenePlaybackLoadRequest?, pendingIntent: ScenePlaybackLoadRequest?
    var activeResourceLifetime: Lifetime?, pendingResourceLifetime: Lifetime?
    var activeRecordID: String?, activeRequestID: UUID?, pendingRequestID: UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:ScenePreparedCallbackPropertyReachability?
    // The supported DEBUG client path has no product switch coordinator here.
    final class Execution {
        let generation: UInt64 = 0; let requestID = UUID(); let id = UUID(); let ticket = 0
        var activated = false; var presented = false
    }
    struct Recovery { let ticket: Int }
    var pendingSwitchTicket: Int?, activeSwitchTicket: Int?
    var pendingSwitchExecution: Execution?, activeSwitchExecution: Execution?
    var queuedSwitchPreparation: Any?, committedSwitchRecovery: Recovery?
    var switchPrepared: Any?, switchVisible: ((Int, UUID) -> Void)?
    var switchLost: ((Int, String) -> Void)?, switchFailed: ((Int, String) -> Void)?
    var requestResourceLifetimes:[UUID:Int]=[:]
    var pendingPropertyRevisions: [UInt64: String] = [:]
    var handshakeWorkItem: DispatchWorkItem?, restartWorkItem: DispatchWorkItem?
    var latestFrameStats: Int?
    var restartBackoff = Backoff()
    var sent: [[String: Any]] = []
    var restarts = 0
    var isPaused = false
    var performanceProfile: (maxFPS: Int, unused: Int) = (60, 0)
    __ACTIVE_FACT_TYPE__
    __ACTIVE_FACT_PROPERTY__
    func failPendingFrameCaptures() {}; func revokeAudioSpectrumDemand(generation: UInt64) {}
    func revokeSystemMediaDemand(generation:UInt64) {}
    func finishShutdownIfPossible() {}; func finishPendingTextureUpdates(_ outcome: ScenePlaybackTextureUpdateOutcome) {}
    func fallbackReplayIntent(requestID: UUID) -> ScenePlaybackLoadRequest? { nil }
    func bindDeferredTextureUpdates(recordID: String?, requestID: UUID) {}
    func resumeDeferredTextureUpdates(recordID:String?,requestID:UUID) {}
    func finishTextureReload(recordID: String?, outcome: ScenePlaybackTextureUpdateOutcome) {}
    func scheduleRestart(reason: String) { restarts += 1 }
    func publishFailure(code: String, message: String) { preconditionFailure(code + message) }
    func sendDisplayConfiguration() {}; func sendSimpleCommand(_ value: String) {}
    func send(_ payload: [String: Any]) { sent.append(payload) }
    func finishSwitchControlsAfterExit(generation: UInt64) { precondition(activeSwitchExecution == nil) }
    func rememberCommittedSwitchForRecovery() { precondition(activeSwitchTicket == nil) }
    func adoptQueuedSwitchPreparationForRecovery() { precondition(queuedSwitchPreparation == nil) }
    func resumeCommittedSwitchRecoveryIfPossible(after ticket: Int?) { precondition(committedSwitchRecovery == nil) }
    static func double(_ raw:Any?)->Double? {raw as? Double}
    __CLIENT_METHODS__
}
@main enum ClientProbe {
    @MainActor static func main() throws {
        var results: [String: Bool] = [:]
        let client = SceneDaemonClient()
        let source = ScenePreparedCallbackPropertyReachability.Source(rootPath: "/own", projectWitness: "p1", sceneWitness: "s1")
        func request() -> ScenePlaybackLoadRequest { .init(rootURL: URL(fileURLWithPath: "/own"), recordID: "record") }
        func payload(_ id: UUID, _ phase: String, record: String = "record", sourceOverride: ScenePreparedCallbackPropertyReachability.Source? = nil) throws -> [String: Any] {
            var result: [String: Any] = ["phase": phase, "requestID": id.uuidString, "message": "fixture", "recordID": record]
            result["callbackPropertyReachability"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                ScenePreparedCallbackPropertyReachability(source: sourceOverride ?? source, scriptGeneration: 7, propertyKeys: ["choice"])))
            return result
        }
        func launch() throws -> UUID {
            client.pendingIntent = request(); client.replayPendingIntent()
            let id = client.pendingRequestID!
            client.handleLaunchState(try payload(id, "accepted"))
            client.handleLaunchState(try payload(id, "launched"))
            client.handleFirstFrame(["requestID":id.uuidString,"recordID":"record","uptimeMs":1.0])
            return id
        }
        let first = try launch()
        let loadCommands = client.sent.filter { $0["cmd"] as? String == "loadScene" }
        results["launched-facts-source-bound"] = client.preparedCallbackPropertyKeys(for: "record", source: source) == ["choice"]
            && loadCommands.count == 1 && loadCommands.first?["requestID"] as? String == first.uuidString
        let wrongSource = ScenePreparedCallbackPropertyReachability.Source(rootPath: "/own", projectWitness: "p2", sceneWitness: "s1")
        results["same-path-changed-project-rejected"] = client.preparedCallbackPropertyKeys(for: "record", source: wrongSource).isEmpty
        results["same-path-changed-scene-rejected"] = client.preparedCallbackPropertyKeys(for: "record", source: .init(
            rootPath: "/own", projectWitness: "p1", sceneWitness: "s2")).isEmpty
        results["missing-source-rejected"] = client.preparedCallbackPropertyKeys(for: "record", source: nil).isEmpty
        results["other-record-rejected"] = client.preparedCallbackPropertyKeys(for: "other", source: source).isEmpty
        client.pendingIntent = request(); client.replayPendingIntent()
        let next = client.pendingRequestID!
        client.handleLaunchState(try payload(first, "accepted"))
        client.handleLaunchState(try payload(first, "launched"))
        results["same-record-old-accepted-and-launched-ignored"] = client.pendingRequestID == next && client.activeRequestID == first
        client.handleLaunchState(try payload(next, "launched", record: "other"))
        results["wrong-record-with-current-id-rejected"] = client.pendingRequestID == next && client.activeRequestID == first
        client.handleLaunchState(try payload(next, "failed"))
        results["failed-candidate-keeps-old-active-facts"] = client.activeRequestID == first
            && client.preparedCallbackPropertyKeys(for: "record", source: source) == ["choice"]
        client.pendingIntent = request(); client.replayPendingIntent()
        let cancelled = client.pendingRequestID!
        client.handleLaunchState(try payload(cancelled, "cancelled"))
        results["cancelled-candidate-keeps-old-active-facts"] = client.activeRequestID == first
            && client.preparedCallbackPropertyKeys(for: "record", source: source) == ["choice"]
        var notifications: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .sceneDaemonActiveSessionFactsDidChange, object: nil, queue: nil) { notification in
            if let change = notification.object as? SceneDaemonActiveSessionFactsChange { notifications.append(contentsOf: change.recordIDs) }
        }
        client.stop(postsLaunchState: false)
        results["silent-stop-clears-and-notifies-facts"] = client.activeCallbackPropertyFacts == nil && notifications == ["record"]
        client.handleLaunchState(try payload(first, "launched"))
        results["late-after-stop-cannot-revive"] = client.activeCallbackPropertyFacts == nil
        NotificationCenter.default.removeObserver(observer)
        client.sessionGeneration += 1; client.transport = .init(); client.endpointReady = true
        let beforeDisconnect = try launch()
        client.handleTermination(status: 9, generation: client.sessionGeneration)
        results["disconnect-clears-before-restart"] = client.activeCallbackPropertyFacts == nil && client.pendingIntent != nil && client.restarts == 1
        client.sessionGeneration += 1; client.transport = .init(); client.endpointReady = true
        client.replayPendingIntent()
        let afterRestart = client.pendingRequestID!
        client.handleLaunchState(try payload(beforeDisconnect, "accepted"))
        client.handleLaunchState(try payload(beforeDisconnect, "launched"))
        results["restart-replay-new-id-old-events-rejected"] = beforeDisconnect != afterRestart
            && client.pendingRequestID == afterRestart && client.activeCallbackPropertyFacts == nil
        client.handleLaunchState(try payload(afterRestart, "accepted"))
        client.handleLaunchState(try payload(afterRestart, "launched"))
        results["restart-waits-real-presentation"] = client.preparedCallbackPropertyKeys(for: "record", source: source).isEmpty
        client.handleFirstFrame(["requestID":afterRestart.uuidString,"recordID":"record","uptimeMs":2.0])
        results["restart-needs-new-presentation"] = client.preparedCallbackPropertyKeys(for: "record", source: source) == ["choice"]
        client.sessionGeneration += 1
        results["transport-generation-mismatch-rejected"] = client.preparedCallbackPropertyKeys(for: "record", source: source).isEmpty
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
class ScenePreparedCallbackPropertyTests(unittest.TestCase):
    def run_probe(self, source: str, sources: list[Path]) -> None:
        with tempfile.TemporaryDirectory(prefix='mwx-prepared-callback-') as directory:
            work = Path(directory)
            probe = work / 'Probe.swift'
            probe.write_text(source)
            binary = work / 'probe'
            build = subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-D', 'DEBUG',
                *map(str, sources), str(probe), '-module-cache-path', str(work / 'cache'), '-o', str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            facts = json.loads(run.stdout)
            for name, passed in facts.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)

    def test_prepared_cohort_and_existing_live_authority(self) -> None:
        session = SCENE / 'Runtime/Session/SceneDesktopWallpaperSession+LiveConsumers.swift'
        source = PROJECTION.replace('__PROJECTION__', method_body(session.read_text(), '    func preparedCallbackPropertyKeys('))
        self.run_probe(source, SWIFT_SOURCES)

    def test_active_facts_request_source_stop_and_restart(self) -> None:
        client, events = CLIENT.read_text(), EVENTS.read_text()
        source = CLIENT_LEAVES.replace('__ACTIVE_FACT_TYPE__', method_body(client, '    struct ActiveCallbackPropertyFacts:'))
        source = source.replace('__ACTIVE_FACT_PROPERTY__', method_body(client, '    var activeCallbackPropertyFacts:'))
        event_types = method_body(client, 'nonisolated struct SceneDaemonActiveSessionFactsChange:')
        notification_name = method_body(client, 'extension Notification.Name {')
        source = '\n'.join([event_types, notification_name, source])
        methods = [method_body(client, signature) for signature in [
            '    func preparedCallbackPropertyKeys(', '    func stop(postsLaunchState:', '    func replayPendingIntent()']]
        endpoint = (SCENE / 'Runtime/IPC/SceneDaemonClient+SwitchEndpoint.swift').read_text()
        methods.append(method_body(endpoint, '    func commitPresentedScene('))
        methods += [method_body(events, signature) for signature in [
            '    private func handleLaunchState(', '    private func handleFirstFrame(', '    func handleTermination(']]
        source = source.replace('__CLIENT_METHODS__', '\n'.join(methods).replace('private ', ''))
        self.run_probe(source, [MODELS, SCENE / 'Systems/Properties/SceneUserProperty.swift'])
