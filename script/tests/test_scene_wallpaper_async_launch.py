#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCH = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
)
HOST = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
)
FRAME_DRIVER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
SURFACE_TEARDOWN = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
COORDINATOR = ROOT / "MyWallpaperX" / "App" / "MainWindowCoordinator+PlaybackRouting.swift"
DEBUG_RUNNER = ROOT / "MyWallpaperX" / "App" / "Debug" / "DebugScenePlaybackRunner.swift"
INSPECTION = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "UI"
    / "SteamWorkshopSceneInspectionController.swift"
)
SPOT_LIGHT_RUNTIME = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneSpotLightRuntime.swift"
)
PREPARED_DEVICE_RESOURCES = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift"
)
METAL_VIEW = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
)
METAL_RENDERER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
)
RENDERER_DIAGNOSTICS = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Diagnostics.swift"
)
RENDERER_EXECUTION_EVIDENCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+ExecutionEvidence.swift"
)
TEXT_LOADER = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextTextureLoader.swift"
)
DEFERRED_BASE_IMAGES = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+DeferredBaseImages.swift"
)
SHADER_REACHABILITY = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema+Reachability.swift"
)
VARIANT_CACHE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant.swift"
)
def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]
    raise AssertionError(f"unterminated function: {signature}")


class SceneWallpaperAsyncLaunchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.launch = LAUNCH.read_text(encoding="utf-8")
        cls.host = HOST.read_text(encoding="utf-8")
        cls.frame_driver = (
            FRAME_DRIVER.read_text(encoding="utf-8")
            + "\n"
            + SURFACE_TEARDOWN.read_text(encoding="utf-8")
        )
        cls.coordinator = COORDINATOR.read_text(encoding="utf-8")
        cls.debug_runner = DEBUG_RUNNER.read_text(encoding="utf-8")
        cls.inspection = INSPECTION.read_text(encoding="utf-8")
        cls.spot_light_runtime = SPOT_LIGHT_RUNTIME.read_text(encoding="utf-8")
        cls.prepared_device_resources = PREPARED_DEVICE_RESOURCES.read_text(
            encoding="utf-8"
        )
        cls.metal_view = METAL_VIEW.read_text(encoding="utf-8") + "\n" + METAL_VIEW.with_name("SceneMetalView+Debug.swift").read_text(encoding="utf-8")
        cls.metal_renderer = read_source_family(METAL_RENDERER)
        cls.renderer_diagnostics = RENDERER_DIAGNOSTICS.read_text(encoding="utf-8")
        cls.text_loader = TEXT_LOADER.read_text(encoding="utf-8")
        cls.deferred_base_images = DEFERRED_BASE_IMAGES.read_text(
            encoding="utf-8"
        )
        cls.shader_reachability = SHADER_REACHABILITY.read_text(encoding="utf-8")
        cls.variant_cache = VARIANT_CACHE.read_text(encoding="utf-8")

    def test_product_request_uses_single_transaction_and_native_presentation(self) -> None:
        configure = function_body(self.coordinator, "static func configure(")
        self.assertIn("manager.setSceneWallpaper(", configure)
        self.assertNotIn("SceneDesktopWallpaperHost.shared", configure)
        self.assertNotIn("sceneHandoff", self.coordinator)
        self.assertNotIn("postWallpaperRuntimeWillSwitch", self.coordinator)
        owner = (ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift").read_text()
        self.assertIn("SceneDaemonClient.shared.prepareSwitch(", owner)
        self.assertIn("playbackSwitch.visible(ticket, executionID:", owner)
        self.assertIn("postWallpaperRuntimeWillSwitch", function_body(owner, "private func commitSwitch("))

    def test_main_window_projects_central_launch_state(self) -> None:
        configure = function_body(self.coordinator, "static func configure(")
        self.assertIn(".sceneWallpaperLaunchStateDidChange", configure)
        self.assertIn("SteamWorkshopService.shared.statusMessage", configure)
        self.assertIn("当前壁纸会继续播放", configure)
        self.assertIn("正在等待首帧显示", configure)

    def test_progress_uses_truthful_indeterminate_stages(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        self.assertIn(".preparingModel", prepare)
        self.assertIn("SceneRuntimeModelBuilder().build", prepare)
        self.assertNotIn("SceneDiagnosticsBuilder", prepare)
        self.assertNotIn("model.diagnostics", prepare)
        self.assertIn(".preparingPrograms", prepare)
        self.assertIn(".preparingResources", prepare)
        self.assertNotIn("percent", prepare.lower())

    def test_launch_envelope_projects_only_relevant_availability_masks(self) -> None:
        """The envelope must share the bounded mask projection with reachability."""
        self.assertNotIn(
            "for rawAvailability in UInt16(0) ... UInt16(UInt8.max)",
            self.variant_cache,
        )
        self.assertIn("readinessComboSlotMask(template)", self.shader_reachability)
        self.assertIn("Array(UInt8.min ... UInt8.max)", self.shader_reachability)

    def test_launch_availability_projection_preserves_fail_closed_fallback(self) -> None:
        """Unknown or out-of-range schema metadata keeps exhaustive rejection semantics."""
        projection = function_body(
            self.shader_reachability,
            "nonisolated static func launchAvailabilityMasks(",
        )
        self.assertIn("guard let readinessSlots = readinessComboSlotMask(template)", projection)
        self.assertIn("guard (0 ..< 8).contains(slot.index)", projection)
        self.assertGreaterEqual(projection.count("Array(UInt8.min ... UInt8.max)"), 2)
        self.assertIn("availability & ~relevantSlots == 0", projection)



    def test_first_surface_runtime_warmup_overlaps_program_compilation(self) -> None:
        prepare = function_body(self.launch, "private static func prepareLaunch(")
        make_runtime = function_body(
            self.launch, "func makeResolvedMaterialRuntime()"
        )
        self.assertIn("ScenePreparedFirstSurfaceRuntimeTask(", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.start()", prepare)
        self.assertIn("firstSurfaceRuntimePreparation.value()", prepare)
        self.assertLess(
            prepare.index("firstSurfaceRuntimePreparation.start()"),
            prepare.index("SceneScriptQuickJSProgramCandidate.compile("),
        )
        self.assertIn("preparedFirstSurfaceRuntime.take() ??", make_runtime)
        self.assertIn(
            "final class ScenePreparedFirstSurfaceRuntime",
            self.prepared_device_resources,
        )
        self.assertIn("private let lock = NSLock()", self.prepared_device_resources)
        self.assertIn("runtime = nil", self.prepared_device_resources)

    def test_optional_spot_light_pipeline_is_not_built_without_authored_plans(self) -> None:
        self.assertIn(
            "pipeline: @autoclosure () -> SceneSpotLightPipeline?",
            self.spot_light_runtime,
        )
        self.assertIn(
            "self.pipeline = plansByLayerID.isEmpty ? nil : pipeline()",
            self.spot_light_runtime,
        )

    def test_product_launch_does_not_construct_startup_diagnostics(self) -> None:
        load = function_body(self.metal_view, "func loadImageLayers(")
        install = function_body(
            RENDERER_EXECUTION_EVIDENCE.read_text(encoding="utf-8"),
            "func installResolvedMaterialExecutionEvidence()",
        )
        runtime_report = function_body(
            self.renderer_diagnostics,
            "func runtimeReportLines()",
        )

        self.assertIn(
            "SceneStartupReportBuffer(enabled: logURL != nil)",
            load,
        )
        self.assertIn("@autoclosure () -> String", self.metal_view)
        self.assertIn("@autoclosure () -> [String]", self.metal_view)
        self.assertIn("if report.isEnabled", load)
        # Execute the actual conditional input in both configurations. This
        # checks the Release value and lazy summary rather than their spelling.
        start = load.index("#if DEBUG")
        branch = load[start:load.index("#endif", start) + len("#endif")]
        buffer = "struct SceneStartupReportBuffer " + function_body(
            self.metal_view, "struct SceneStartupReportBuffer"
        )
        harness = r'''
        import Foundation
        enum SceneRenderDescriptor { struct Layer {} }
        final class Renderer {
            var summaries = 0
            func effectRuntimeSummary(for layer: SceneRenderDescriptor.Layer) -> String? {
                summaries += 1
                return "effect"
            }
        }
        @main enum Check {
            static func main() {
                let renderer = Renderer()
                let logURLs: [URL?] = [nil, URL(fileURLWithPath: "/unused-report")]
                for logURL in logURLs {
        ''' + branch + r'''
        #if DEBUG
                    report.append("probe")
                    precondition(recordsDiagnostics == (logURL != nil))
                    let previousSummaries = renderer.summaries
                    precondition(textEffectSummary(.init()) == "effect")
                    precondition(renderer.summaries == previousSummaries + 1)
        #else
                    precondition(!recordsDiagnostics)
                    precondition(textEffectSummary(.init()) == nil)
                    precondition(renderer.summaries == 0)
        #endif
                }
                print("launch-diagnostic-input-pass")
            }
        }
        '''
        for debug in [False, True]:
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-launch-input-") as raw:
                directory = Path(raw)
                source = directory / "Check.swift"
                source.write_text("#if DEBUG\n" + buffer + "\n#endif\n" + harness)
                binary = directory / "check"
                command = ["xcrun", "swiftc", "-parse-as-library", "-O"]
                if debug:
                    command += ["-D", "DEBUG"]
                command += [str(source), "-o", str(binary)]
                compiled = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True)
                self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
                self.assertIn("launch-diagnostic-input-pass", executed.stdout)
        self.assertIn("recordsDiagnostics: recordsDiagnostics", load)
        self.assertGreaterEqual(self.text_loader.count("if recordsDiagnostics"), 2)
        self.assertIn("renderer.installResolvedMaterialExecutionEvidence()", load)
        self.assertIn("installExecutionEvidence(", install)
        self.assertNotIn("installExecutionEvidence(", runtime_report)


    def test_detail_projects_progress_and_user_cancellation(self) -> None:
        self.assertIn("sceneWallpaperLaunchStateDidChange", self.inspection)
        self.assertIn("launchState.isInProgress", self.inspection)
        self.assertIn("当前壁纸会继续播放", self.inspection)
        self.assertIn(".cancelSceneLaunch(recordID: record.id)", self.inspection)
        self.assertIn("to: .scene", self.inspection)

    def test_host_stop_cancels_pending_preparation(self) -> None:
        stop = function_body(self.host, "func stop()")
        self.assertIn("cancelPendingLaunch()", stop)

    def test_surface_teardown_reports_after_surfaces_are_cleared(self) -> None:
        teardown = function_body(self.frame_driver, "func teardownSurfaces(")
        clear_index = teardown.index("surfaces.removeAll()")
        log_index = teardown.index('phase=surface-teardown')
        self.assertGreater(
            log_index,
            clear_index,
            "teardown evidence must report the post-close surface count",
        )
        self.assertIn("surfaces.count", teardown[log_index:])

    def test_debug_smoke_exercises_the_async_product_entrypoint(self) -> None:
        self.assertIn("--mwx-debug-scene-async-launch-smoke", self.debug_runner)
        self.assertIn("runtimeHost.requestLaunch(", self.debug_runner)
        self.assertIn("phase=async-launch-request-returned", self.debug_runner)
        self.assertIn("phase=async-launch-ready", self.debug_runner)

    def test_property_edit_restarts_pending_full_intent_before_active_commit(self) -> None:
        source = property_launch_harness(self.host)
        with tempfile.TemporaryDirectory(prefix="mwx-property-launch-") as directory:
            path = Path(directory)
            harness = path / "Harness.swift"
            harness.write_text(source)
            binary = path / "harness"
            compilation = subprocess.run([
                "xcrun", "swiftc", "-D", "DEBUG", "-swift-version", "5", "-parse-as-library",
                str(LAUNCH.with_name("SceneDesktopWallpaperLaunchModels.swift")),
                str(harness), "-o", str(binary),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            print(result.stdout, end="")
            for name, passed in output["facts"].items():
                with self.subTest(name=name, trace=output["trace"]):
                    self.assertTrue(passed)


def property_launch_harness(host_source: str) -> str:
    """Execute real Host arbitration/epochs and Client merge/ack, with leaf doubles.

    Preparation deliberately finishes after cancellation. No parser, renderer,
    transport process or GPU is created; session acceptance is a controlled leaf.
    """
    launch = LAUNCH.read_text()
    ipc = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC"

    def method(source: str, signature: str) -> str:
        start = source.index(signature)
        opening = source.index("{", start)
        return source[start:opening] + function_body(source, signature)

    host_methods = "\n".join([
        method(host_source, "func applyUserPropertyValues("),
        method(host_source, "func sessionForCommittedPropertyUpdate("),
        method(launch, "func requestLaunch("),
        method(launch, "func cancelPendingLaunch("),
    ])
    client = (ipc / "SceneDaemonClient.swift").read_text()
    events = (ipc / "SceneDaemonClient+Events.swift").read_text()
    textures = (ipc / "SceneDaemonClient+UserTextures.swift").read_text()
    client_methods = "\n".join([
        method(client, "func requestLaunch("),
        method(client, "func startLaunch("),
        method(client, "func cancelPreparationForRuntimeSwitch("),
        method(client, "private func applyPropertyValues("),
        method(client, "func hasIntent("),
        method(events, "private func handlePropertyUpdateResult("),
        method(events, "private func handleLaunchState("),
        method(events, "private func handleFirstFrame("),
        method((ipc / "SceneDaemonClient+SwitchEndpoint.swift").read_text(), "func commitPresentedScene("),
        method(client, "func preparedCallbackPropertyKeys("),
    ] + [method(textures, signature) for signature in [
        "func applyUserTextureUpdate(", "func reloadUserTextureUpdate(",
        "private func admitTextureRevision(", "private func textureRevisionKey(",
        "private func sendTextureUpdate(", "func bindDeferredTextureUpdates(",
        "func fallbackReplayIntent(", "func resumeDeferredTextureUpdates(",
        "func finishTextureReload(", "private func restoreFallbackIntent(",
        "func finishPendingTextureUpdates(", "private func applying(",
    ]])
    values = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift").read_text()
    commands = (ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift").read_text()
    control_types = "\n".join([
        method(values, "nonisolated enum SceneUserPropertyValue:"),
    ] + [method(commands, signature) for signature in [
        "nonisolated struct ScenePlaybackTextureReference:",
        "nonisolated struct ScenePlaybackTextureUpdate:",
        "nonisolated enum ScenePlaybackTextureUpdateOutcome:",
        "nonisolated struct ScenePlaybackLoadRequest:",
    ]])
    return (PROPERTY_LAUNCH_SUPPORT.replace("__HOST_METHODS__", host_methods)
            .replace("__CLIENT_METHODS__", client_methods)
            .replace("__CONTROL_TYPES__", control_types)
            .replace("__PENDING_TEXTURE_UPDATE__", method(textures, "struct PendingTextureUpdate {")))


PROPERTY_LAUNCH_SUPPORT = r'''
import CoreFoundation
import Foundation

__CONTROL_TYPES__
struct SceneRuntimeModel {
    struct Project {
        let rootURL = URL(fileURLWithPath: "/own")
        let sourceWitness: String? = nil
        struct Catalog { let definitions: [String] = [] }
        let userProperties = Catalog()
    }
    struct Document { let sourceWitness: String? = nil }
    let values: [String: SceneUserPropertyValue]
    let project = Project(), sceneDocument = Document()
}
struct SceneDesktopWallpaperLaunchContext {
    let values: [String: SceneUserPropertyValue]
    let generation: UInt64
}
struct SceneFirstFramePresentationRegistration { let requestID: UUID; let recordID: String? }
struct SceneFramePresentation { let requestID:UUID;let recordID:String?;let uptimeMicros:UInt64 }
extension Notification.Name { static let sceneWallpaperFirstFrameDidPresent=Notification.Name("first-present") }
struct RestartBackoff { mutating func reset() {} }
enum SceneDaemonProtocol { static let version = 1 }

final class PreparationControl: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var first = true
    func prepare() {
        lock.lock(); let wait = first; first = false; lock.unlock()
        if wait { entered.signal(); release.wait() }
    }
}
struct SceneTextureDecodeCacheBudget: Sendable { let control: PreparationControl }
@MainActor final class SceneDesktopWallpaperSession {
    var values: [String: SceneUserPropertyValue]
    var calls = 0
    let acceptsJ: Bool
    let activeRecordID:String?
    func cancelPendingUserTextureUpdates() {}
    func preparedCallbackPropertyKeys(definitions: [String]) -> Set<String> { [] }
    init(_ values: [String: SceneUserPropertyValue], acceptsJ: Bool = true, recordID:String="record") {
        self.values = values; self.acceptsJ = acceptsJ;self.activeRecordID=recordID
    }
    func applyUserPropertyValues(_ replacements: [String: SceneUserPropertyValue],
        changedPropertyKeys: Set<String>, recordID: String?) -> Bool {
        calls += 1
        guard recordID == activeRecordID else { return false }
        if changedPropertyKeys.contains("K"), replacements["K"] != values["K"] { return false }
        if changedPropertyKeys.contains("J"), !acceptsJ { return false }
        for key in changedPropertyKeys { values[key] = replacements[key] }
        return true
    }
}
@MainActor final class SceneDesktopWallpaperHost {
    struct PreparedLaunch { let context: SceneDesktopWallpaperLaunchContext; let model: SceneRuntimeModel }
    let launchPreparationQueue = DispatchQueue(label: "self-authored-launch-boundary")
    let textureDecodeCacheBudget: SceneTextureDecodeCacheBudget
    var nextLaunchRequestGeneration: UInt64 = 0, nextSceneScriptGeneration: UInt64 = 0
    var pendingLaunchCompletion: (@MainActor (Result<SceneRuntimeModel, Error>) -> Void)?
    var launchCancellation: SceneWallpaperLaunchCancellation?
    var launchState: SceneWallpaperLaunchState?
    var activeSession: SceneDesktopWallpaperSession?
    var unconfirmedPromotion:(requestID:UUID,previous:SceneDesktopWallpaperSession?)?
    var onState: ((SceneWallpaperLaunchState) -> Void)?
    var began: [UInt64] = [], trace: [String] = []
    init(_ control: PreparationControl) { textureDecodeCacheBudget = .init(control: control) }
    nonisolated static func prepareLaunch(rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue], userPropertyTextureURLs: [String: URL],
        requiredUserTextureKeys: Set<String>, logURL: URL?, recordID: String?,
        sceneScriptGeneration: UInt64, textureDecodeCacheBudget: SceneTextureDecodeCacheBudget,
        cancellation: SceneWallpaperLaunchCancellation?,
        progress: ((SceneWallpaperLaunchState.Phase, String) -> Void)?) throws -> PreparedLaunch {
        textureDecodeCacheBudget.control.prepare()
        // A noncooperative leaf probes the production generation guards too.
        progress?(.preparingPrograms, "controlled late preparation")
        return .init(context: .init(values: propertyOverrides, generation: sceneScriptGeneration),
                     model: .init(values: propertyOverrides))
    }
    func publishLaunchState(_ state: SceneWallpaperLaunchState) {
        launchState = state
        trace.append("\(state.phase.rawValue):\(nextLaunchRequestGeneration)")
        onState?(state)
    }
    func discardCandidate() { trace.append("discard:\(nextLaunchRequestGeneration)") }
    func rollbackUnconfirmedPromotion() {}
    func cancelCandidate(requestID:UUID) {
        guard unconfirmedPromotion?.requestID == requestID else {return}
        activeSession=unconfirmedPromotion?.previous;unconfirmedPromotion=nil
        trace.append("rollback-unconfirmed")
    }
    func beginCandidate(_ context: SceneDesktopWallpaperLaunchContext,
        firstPresentation: SceneFirstFramePresentationRegistration,
        completion: @escaping (Result<Void, Error>) -> Void) throws {
        began.append(context.generation)
        activeSession = .init(context.values)
        completion(.success(()))
    }
    func finishLaunchFailure(_ error: Error, requestID: UUID, recordID: String?,
        completion: @MainActor (Result<SceneRuntimeModel, Error>) -> Void) {
        publishLaunchState(.init(requestID: requestID, recordID: recordID,
            phase: .failed, message: error.localizedDescription))
        completion(.failure(error))
    }
    __HOST_METHODS__
}

@MainActor final class SceneDaemonClient {
    typealias PlaybackSwitchTicket = Int
    final class SwitchExecution {
        let generation:UInt64=0,requestID=UUID(),id=UUID(),ticket=0
        var activated=false,presented=false
    }
    var pendingSwitchTicket:Int?,activeSwitchTicket:Int?
    var pendingSwitchExecution:SwitchExecution?,activeSwitchExecution:SwitchExecution?
    struct QueuedSwitchPreparation {
        let request:ScenePlaybackLoadRequest;let ticket:Int;let resourceLifetime:Int?
    }
    var queuedSwitchPreparation:QueuedSwitchPreparation?
    struct CommittedSwitchRecovery {let ticket:Int}
    var committedSwitchRecovery:CommittedSwitchRecovery?
    var switchPrepared:Bool?
    var switchVisible:((Int,UUID)->Void)?
    var switchFailed:((Int,String)->Void)?
    var switchLost:((Int,String)->Void)?
    func cancelSwitch(ticket:Int,completion:()->Void){completion()}
    func resumeCommittedSwitchRecoveryIfPossible(after ticket:Int?){}
    func reportPreparedSwitch(requestID:UUID)->Bool{false}
    struct Lifetime { let rootURL: URL; let recordID: String?;var lifetime:Int? = nil }
    final class Transport { var isRunning = true }
    __PENDING_TEXTURE_UPDATE__
    let host: SceneDesktopWallpaperHost
    var transport: Transport? = .init()
    var pendingTextureUpdates: [UInt64: PendingTextureUpdate] = [:]
    var sessionGeneration: UInt64 = 1
    var textureUpdateAdmissionClosed = false
    var holdAllLaunchStates = false, holdLaunched = false, holdAcks = false
    var heldLaunchStates: [SceneWallpaperLaunchState] = []
    var heldAcks: [[String: Any]] = []
    var textureSends = 0
    var activeIntent: ScenePlaybackLoadRequest?, pendingIntent: ScenePlaybackLoadRequest?
    var activeResourceLifetime: Lifetime?, pendingResourceLifetime: Lifetime?
    var activeRecordID: String?, activeRequestID: UUID?, pendingRequestID: UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:ScenePreparedCallbackPropertyReachability?
    struct ActiveCallbackPropertyFacts: Equatable {
        let transportGeneration: UInt64; let requestID: UUID; let recordID: String?
        let reachability: ScenePreparedCallbackPropertyReachability
    }
    var activeCallbackPropertyFacts: ActiveCallbackPropertyFacts?
    var launchState: SceneWallpaperLaunchState?
    var pendingPropertyRevisions: [UInt64: String] = [:], latestTextureRevisions: [String: UInt64] = [:]
    var lastPropertyRevision: UInt64 = 0
    var warmSessionPending = false, endpointReady = true
    var restartWorkItem: DispatchWorkItem?
    var restartBackoff=RestartBackoff()
    var replayed: [ScenePlaybackLoadRequest] = [], completions: [Bool] = []
    init(_ host: SceneDesktopWallpaperHost) { self.host = host }
    func edit(_ values: [String: SceneUserPropertyValue], revision: UInt64) -> Bool {
        applyPropertyValues(values, revision: revision, recordID: "record")
    }
    func receive(_ state: SceneWallpaperLaunchState) {
        if holdAllLaunchStates || (holdLaunched && state.phase == .launched) {
            heldLaunchStates.append(state); return
        }
        receiveNow(state)
    }
    func receiveNow(_ state: SceneWallpaperLaunchState) {
        handleLaunchState(["phase": state.phase.rawValue, "requestID": state.requestID.uuidString,
                           "message": state.message, "recordID": state.recordID ?? ""])
        if state.phase == .launched {
            // GPU/presentation is a controlled leaf here; production admission
            // still runs its real pending -> active first-present method.
            handleFirstFrame(["requestID":state.requestID.uuidString,"recordID":state.recordID ?? "", "uptimeMs":1.0])
        }
    }
    func flushLaunchStates() {
        holdAllLaunchStates = false; holdLaunched = false
        let states = heldLaunchStates; heldLaunchStates.removeAll()
        states.forEach(receiveNow)
    }
    func flushAcks() {
        holdAcks = false
        let acks = heldAcks; heldAcks.removeAll()
        acks.forEach(handlePropertyUpdateResult)
    }
    func send(_ payload: [String: Any]) {
        if payload["cmd"] as? String == "finalizeCandidate" { return }
        if payload["cmd"] as? String == "cancelCandidate" { host.cancelPendingLaunch();return }
        if payload["cmd"] as? String == "setUserTextures" { textureSends += 1; return }
        let values = (payload["values"] as! [String: Any]).mapValues {
            SceneUserPropertyValue.parse($0)!
        }
        let accepted = host.applyUserPropertyValues(values, changedPropertyKeys: Set(values.keys),
            recordID: payload["recordID"] as? String)
        let ack: [String: Any] = ["revision": payload["revision"]!,
            "recordID": payload["recordID"]!, "accepted": accepted]
        if holdAcks { heldAcks.append(ack) } else { handlePropertyUpdateResult(ack) }
    }
    func ensureSession() -> Bool { true }
    func stop() {
        pendingIntent=nil;pendingResourceLifetime=nil;pendingRequestID=nil
        pendingPresentationRequestID=nil;pendingPresentationReachability=nil
        host.cancelPendingLaunch()
    }
    func replayPendingIntent() {
        guard let request = pendingIntent else { return }
        let requestID = UUID()
        pendingRequestID = requestID
        replayed.append(request)
        host.requestLaunch(rootURL: request.rootURL, propertyOverrides: request.propertyOverrides,
            recordID: request.recordID, requestID: requestID) { [weak self] outcome in
            if case .success = outcome { self?.completions.append(true) }
            else { self?.completions.append(false) }
        }
    }
    func publishFailure(code: String, message: String) { preconditionFailure(message) }
    static func unsignedInteger(_ value: Any?) -> UInt64? { value as? UInt64 }
    static func double(_ value:Any?)->Double? { value as? Double }
    __CLIENT_METHODS__
}

@main enum Harness {
    @MainActor static func entered(_ control: PreparationControl) async -> Bool {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                done.resume(returning: control.entered.wait(timeout: .now() + 5) == .success)
            }
        }
    }
    @MainActor static func queueDrained(_ queue: DispatchQueue) async {
        await withCheckedContinuation { done in
            queue.async { DispatchQueue.main.async { done.resume() } }
        }
    }
    @MainActor static func intent(_ values: [String: SceneUserPropertyValue], root: String = "/active",
                                  record: String = "record") -> ScenePlaybackLoadRequest {
        .init(rootURL: URL(fileURLWithPath: root), propertyOverrides: values,
              userPropertyTextures: [:], recordID: record)
    }
    static func textureUpdate(_ revision: UInt64, name: String) -> ScenePlaybackTextureUpdate {
        let url = URL(fileURLWithPath: "/self-authored/" + name + ".png")
        return .init(references: ["T": .init(url: url, bookmarkData: nil)], resetKeys: [],
                     values: ["T": .string(url.path)], revision: revision, recordID: "record")
    }
    @MainActor static func delayedIntentCases() async -> ([String: Bool], [String: [String]]) {
        let initial: [String: SceneUserPropertyValue] = ["K": .number(0), "J": .number(0)]
        var facts: [String: Bool] = [:], traces: [String: [String]] = [:]
        for sameRecord in [false,true] {
            let host=SceneDesktopWallpaperHost(PreparationControl())
            let previous=SceneDesktopWallpaperSession(initial)
            let replacement=SceneDesktopWallpaperSession(initial,recordID:sameRecord ? "record" : "other")
            host.activeSession=replacement
            host.unconfirmedPromotion=(UUID(),previous)
            let accepted=host.applyUserPropertyValues(["J":.number(7)],changedPropertyKeys:["J"],recordID:"record")
            facts["standby-edit-\(sameRecord)-updatesCommittedSession"] = accepted && previous.values["J"] == .number(7) && replacement.values == initial
            facts["standby-edit-\(sameRecord)-preservesCorrectCandidate"] = sameRecord
                ? host.unconfirmedPromotion == nil && host.activeSession === previous
                : host.unconfirmedPromotion != nil && host.activeSession === replacement
        }
        for mode in ["ordinary", "texture-bound", "texture-unbound"] {
            for ackFirst in [false, true] {
                let name = mode + (ackFirst ? "-ack-first" : "-launched-first")
                let control = PreparationControl(), host = SceneDesktopWallpaperHost(control)
                host.activeSession = .init(initial)
                let client = SceneDaemonClient(host)
                client.activeIntent = intent(initial)
                host.onState = { [weak client] in client?.receive($0) }
                client.holdAcks = true
                client.holdAllLaunchStates = mode == "texture-unbound"
                client.holdLaunched = mode != "texture-unbound"
                let update = textureUpdate(7, name: "selected")
                var outcomes: [ScenePlaybackTextureUpdateOutcome] = []
                if mode == "ordinary" {
                    var requested = initial; requested["K"] = .number(1)
                    client.requestLaunch(intent(requested, root: "/new-authored"))
                } else {
                    facts[name + "-realReloadAccepted"] = client.reloadUserTextureUpdate(update) { outcomes.append($0) }
                }
                guard await entered(control) else { fatalError("preparation leaf not entered") }
                if mode != "ordinary" {
                    let pending = client.pendingTextureUpdates[7]
                    facts[name + "-currentReloadCohort"] = client.pendingIntent?.recordID == "record"
                        && pending?.generation == client.sessionGeneration && pending?.waitsForFirstPresent == true
                        && pending?.isLaunchRetry == true && pending?.fallbackBaseIntent != nil
                        && pending?.requestID == client.pendingRequestID
                        && client.pendingRequestID != nil
                }
                control.release.signal()
                await queueDrained(host.launchPreparationQueue)
                facts[name + "-windowReached"] = host.launchState?.phase == .launched
                    && !client.heldLaunchStates.isEmpty && client.pendingIntent != nil
                facts[name + "-editAccepted"] = client.edit(["J": .number(3)], revision: 1)
                    && host.activeSession?.values["J"] == .number(3)
                let pendingID = client.pendingRequestID
                client.receiveNow(.init(requestID: UUID(), recordID: "record", phase: .launched, message: "foreign request"))
                facts[name + "-foreignRequestIgnored"] = client.pendingRequestID == pendingID && client.pendingIntent != nil
                if ackFirst { client.flushAcks(); client.flushLaunchStates() }
                else { client.flushLaunchStates(); client.flushAcks() }
                facts[name + "-launchRetainsEdit"] = client.activeIntent?.propertyOverrides["J"] == .number(3)
                    && host.activeSession?.values["J"] == .number(3)
                facts[name + "-ackDoesNotRelaunch"] = client.replayed.count == 1 && client.pendingIntent == nil
                if mode == "ordinary" {
                    facts[name + "-candidateOwnsInitialFacts"] = client.activeIntent?.rootURL.path == "/new-authored"
                        && client.activeIntent?.propertyOverrides["K"] == .number(1)
                } else if let requestID = client.activeRequestID {
                    client.resumeDeferredTextureUpdates(recordID: "record", requestID: requestID)
                    facts[name + "-textureCommitRemainsPerKey"] = outcomes == [.applied]
                        && client.pendingTextureUpdates.isEmpty && client.activeIntent?.requiredUserTextureKeys.isEmpty == true
                        && client.activeIntent?.userPropertyTextures == update.references
                        && client.activeIntent?.propertyOverrides["J"] == .number(3)
                } else { facts[name + "-textureCommitRemainsPerKey"] = false }
                facts[name + "-structuralDispatch"] = client.edit(["K": .number(2)], revision: 2)
                await queueDrained(host.launchPreparationQueue)
                facts[name + "-laterRebuildRetainsEdit"] = client.replayed.last?.propertyOverrides["J"] == .number(3)
                    && host.activeSession?.values["J"] == .number(3)
                    && host.activeSession?.values["K"] == .number(2)
                traces[name] = host.trace
            }
        }
        do {
            let control = PreparationControl(), host = SceneDesktopWallpaperHost(control)
            host.activeSession = .init(initial)
            let client = SceneDaemonClient(host)
            client.activeIntent = intent(initial)
            host.onState = { [weak client] in client?.receive($0) }
            client.holdAllLaunchStates = true
            var oldOutcomes: [ScenePlaybackTextureUpdateOutcome] = [], reentries: [ScenePlaybackTextureUpdateOutcome] = []
            var dispatches: [Bool] = [], nestedStayedClosed = false
            let old = textureUpdate(1, name: "old"), replacement = textureUpdate(4, name: "replacement")
            let started = client.applyUserTextureUpdate(old) { outcome in
                oldOutcomes.append(outcome)
                dispatches.append(client.reloadUserTextureUpdate(textureUpdate(2, name: "reentrant-reload")) { reentries.append($0) })
                client.finishPendingTextureUpdates(.superseded)
                nestedStayedClosed = client.textureUpdateAdmissionClosed
                dispatches.append(client.applyUserTextureUpdate(textureUpdate(3, name: "reentrant-apply")) { reentries.append($0) })
            }
            var finalOutcomes: [ScenePlaybackTextureUpdateOutcome] = []
            let replaced = client.reloadUserTextureUpdate(replacement) { finalOutcomes.append($0) }
            guard await entered(control) else { fatalError("reload leaf not entered") }
            facts["drain-reentryClosed"] = started && replaced && dispatches == [true, true]
                && oldOutcomes == [.superseded] && reentries == [.superseded, .superseded]
                && nestedStayedClosed && !client.textureUpdateAdmissionClosed
            facts["drain-onlyNewBoundCohort"] = Set(client.pendingTextureUpdates.keys) == [4]
                && client.pendingTextureUpdates[4]?.requestID == client.pendingRequestID && client.pendingRequestID != nil
                && client.pendingTextureUpdates[4]?.fallbackBaseIntent != nil
                && client.pendingTextureUpdates[4]?.isLaunchRetry == true
                && client.replayed.count == 1 && client.textureSends == 1
            control.release.signal(); await queueDrained(host.launchPreparationQueue)
            client.flushLaunchStates()
            if let requestID = client.activeRequestID {
                client.resumeDeferredTextureUpdates(recordID: "record", requestID: requestID)
            }
            facts["drain-replacementCompletesOnce"] = finalOutcomes == [.applied] && client.pendingTextureUpdates.isEmpty
            traces["drain"] = host.trace
        }
        for phase in [SceneWallpaperLaunchState.Phase.failed, .cancelled] {
            let host = SceneDesktopWallpaperHost(PreparationControl()), requestID = UUID()
            host.activeSession = .init(initial)
            host.launchState = .init(requestID: requestID, recordID: "record", phase: phase, message: "fixture")
            let client = SceneDaemonClient(host)
            client.activeIntent = intent(initial); client.pendingIntent = intent(initial, root: "/pending")
            client.pendingRequestID = requestID; client.holdAcks = true
            _ = client.edit(["J": .number(3)], revision: 1)
            client.receiveNow(host.launchState!); client.flushAcks()
            facts[phase.rawValue + "-retainsActiveEdit"] = client.activeIntent?.propertyOverrides["J"] == .number(3)
                && client.activeIntent?.rootURL.path == "/active" && client.pendingIntent == nil && client.replayed.isEmpty
        }
        do {
            let host = SceneDesktopWallpaperHost(PreparationControl()), requestID = UUID()
            host.activeSession = .init(initial)
            let client = SceneDaemonClient(host)
            client.activeIntent = intent(initial)
            let foreign: [String: SceneUserPropertyValue] = ["K": .number(9), "J": .number(9)]
            client.pendingIntent = intent(foreign, root: "/other", record: "other"); client.pendingRequestID = requestID
            _ = client.edit(["J": .number(3)], revision: 1)
            facts["foreignRecordNotEdited"] = client.pendingIntent?.propertyOverrides == foreign
            client.receiveNow(.init(requestID: requestID, recordID: "other", phase: .launched, message: "other scene"))
            facts["foreignRecordOwnsItsValues"] = client.activeIntent?.propertyOverrides == foreign
        }
        return (facts, traces)
    }
    @MainActor static func main() async throws {
        var facts: [String: Bool] = [:], traces: [String: [String]] = [:]
        let initial: [String: SceneUserPropertyValue] = ["K": .number(0), "J": .number(0)]
        for kind in ["same", "hot", "structural"] {
            let control = PreparationControl()
            // Each scenario uses one serial preparation queue and one controlled first leaf.
            let runtime = SceneDesktopWallpaperHost(control)
            let session = SceneDesktopWallpaperSession(initial, acceptsJ: kind != "structural")
            runtime.activeSession = session
            let client = SceneDaemonClient(runtime)
            client.activeIntent = .init(rootURL: URL(fileURLWithPath: "/self-authored"),
                propertyOverrides: initial, userPropertyTextures: [:], recordID: "record")
            runtime.onState = { [weak client] in client?.receive($0) }
            facts[kind + "-initialDispatched"] = client.edit(["K": .number(1)], revision: 1)
            guard await entered(control) else { fatalError("preparation leaf not entered") }
            let oldGeneration = runtime.nextLaunchRequestGeneration
            let oldCancellation = runtime.launchCancellation!
            let oldCalls = session.calls
            let next: SceneUserPropertyValue = .number(kind == "same" ? 0 : 3)
            facts[kind + "-secondDispatched"] = client.edit(["J": next], revision: 2)
            facts[kind + "-activeNotDelegated"] = session.calls == oldCalls && session.values == initial
            facts[kind + "-fullIntentReplayed"] = client.replayed.count == 2
                && client.replayed.last?.propertyOverrides == ["K": .number(1), "J": next]
            facts[kind + "-generationCancelledAndReplaced"] = runtime.nextLaunchRequestGeneration == oldGeneration + 2
            do { try oldCancellation.check(); facts[kind + "-cancelToken"] = false }
            catch { facts[kind + "-cancelToken"] = true }
            control.release.signal()
            await queueDrained(runtime.launchPreparationQueue)
            facts[kind + "-oldCompletionCannotPublish"] = !runtime.began.contains(1)
                && !runtime.trace.contains("preparingPrograms:\(oldGeneration)")
            facts[kind + "-replacementCompletesOnce"] = runtime.began == [2]
                && client.completions == [false, true]
            facts[kind + "-latestActivated"] = runtime.activeSession?.values == ["K": .number(1), "J": next]
                && client.activeIntent?.propertyOverrides == runtime.activeSession?.values
                && client.pendingIntent == nil && runtime.launchState?.phase == .launched
            traces[kind] = runtime.trace
        }
        for phase in [SceneWallpaperLaunchState.Phase.launched, .cancelled, .failed, .stopped] {
            let host = SceneDesktopWallpaperHost(PreparationControl())
            let session = SceneDesktopWallpaperSession(initial)
            host.activeSession = session
            host.launchState = .init(requestID: UUID(), recordID: "record", phase: phase, message: "fixture")
            facts["terminal-" + phase.rawValue] = host.applyUserPropertyValues(["J": .number(0)],
                changedPropertyKeys: ["J"], recordID: "record") && session.calls == 1
                && host.nextLaunchRequestGeneration == 0
        }
        for kind in ["no-pending", "different-record", "empty"] {
            let host = SceneDesktopWallpaperHost(PreparationControl())
            let session = SceneDesktopWallpaperSession(initial)
            host.activeSession = session
            if kind != "no-pending" {
                host.launchState = .init(requestID: UUID(),
                    recordID: kind == "different-record" ? "other" : "record",
                    phase: .preparingPrograms, message: "fixture")
            }
            facts[kind + "-delegates"] = host.applyUserPropertyValues(
                kind == "empty" ? [:] : ["J": .number(3)],
                changedPropertyKeys: kind == "empty" ? [] : ["J"], recordID: "record")
                && session.calls == 1 && host.nextLaunchRequestGeneration == 0
            facts[kind + "-pendingPreserved"] = kind == "no-pending" || host.launchState?.isInProgress == true
        }
        let delayed = await delayedIntentCases()
        facts.merge(delayed.0) { _, new in new }; traces.merge(delayed.1) { _, new in new }
        print(String(decoding: try JSONSerialization.data(withJSONObject:
            ["facts": facts, "trace": traces], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


if __name__ == "__main__":
    unittest.main()
