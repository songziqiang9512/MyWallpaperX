#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextGenerationState.swift"
STORE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextTextureStore.swift"
)
DRAW_REQUEST_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerDrawRequest.swift"
)
HOST_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let authored = SceneDynamicTextSignature(
            content: "A", fontPath: nil,
            pointSize: 8, colorRGB: [1, 1, 1], maxWidth: 100
        )
        let second = SceneDynamicTextSignature(
            content: "B", fontPath: "fonts/second.ttf",
            pointSize: 9, colorRGB: [1, 0, 0], maxWidth: 200
        )
        let latest = SceneDynamicTextSignature(
            content: "C", fontPath: "fonts/latest.ttf",
            pointSize: 10, colorRGB: [0, 1, 0], maxWidth: 300
        )
        var state = SceneDynamicTextGenerationState()
        state.registerInitial(layerID: 1, signature: authored, isReady: true)
        let initialReadyGeneration = state.readyGeneration(layerID: 1)
        let duplicate = state.request(layerID: 1, signature: authored)
        let generationB = state.request(layerID: 1, signature: second)!
        let generationC = state.request(layerID: 1, signature: latest)!
        let staleAccepted = state.complete(layerID: 1, generation: generationB, succeeded: true)
        let failureAccepted = state.complete(layerID: 1, generation: generationC, succeeded: false)
        let readyAfterFailure = state.readySignature(layerID: 1)!
        let generationAfterFailure = state.readyGeneration(layerID: 1)
        let latestAccepted = state.complete(layerID: 1, generation: generationC, succeeded: true)
        let readyAfterSuccess = state.readySignature(layerID: 1)!
        let generationAfterSuccess = state.readyGeneration(layerID: 1)

        var scheduledState = SceneDynamicTextGenerationState()
        scheduledState.registerInitial(layerID: 2, signature: authored, isReady: true)
        let scheduledSecond = scheduledState.schedule(layerID: 2, signature: second)!
        let queuedLatest = scheduledState.schedule(layerID: 2, signature: latest)
        let staleCompletion = scheduledState.finish(scheduledSecond, succeeded: true)
        let latestCompletion = scheduledState.finish(staleCompletion.next!, succeeded: true)
        state.reset()
        let payload: [String: Any] = [
            "duplicate": duplicate as Any,
            "initialReadyGeneration": initialReadyGeneration as Any,
            "ordered": generationC > generationB,
            "staleAccepted": staleAccepted,
            "failureAccepted": failureAccepted,
            "readyAfterFailure": readyAfterFailure.content,
            "generationAfterFailure": generationAfterFailure as Any,
            "latestAccepted": latestAccepted,
            "readyAfterSuccess": readyAfterSuccess.content,
            "generationAfterSuccess": generationAfterSuccess as Any,
            "queuedLatestStartedImmediately": queuedLatest != nil,
            "scheduledStaleAccepted": staleCompletion.accepted,
            "scheduledNextContent": staleCompletion.next?.signature.content as Any,
            "scheduledLatestAccepted": latestCompletion.accepted,
            "scheduledHasThirdTask": latestCompletion.next != nil,
            "scheduledReadyWidth": scheduledState.readySignature(layerID: 2)?.maxWidth as Any,
            "readyAfterReset": state.readySignature(layerID: 1) as Any,
            "generationAfterReset": state.readyGeneration(layerID: 1) as Any,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

# Execute the production Store and generation scheduler. Only the non-target
# descriptor/input/publication shells and raster producer are substituted; no
# Store locking, ready/prepared/submitted state, or generation logic is copied.
STORE_HARNESS = r'''
import Foundation
import Metal

enum SceneDynamicTextField: Hashable { case content, font, pointSize, color, maxWidth }
enum SceneDynamicValue { case string(String), scalar(Double), vector3(Double,Double,Double) }
enum SceneDynamicTarget: Hashable { case text(layerID: Int,field: SceneDynamicTextField) }
struct SceneDynamicSnapshot {
    struct Entry { let value: SceneDynamicValue }
    let values: [SceneDynamicTarget: Entry]
    subscript(_ key: SceneDynamicTarget) -> Entry? { values[key] }
}
struct SceneRenderDescriptor {
    struct TextStyle {
        let fontPath: String? = nil
        let pointSize: Float = 8
        let colorRGB: [Float] = [1,1,1]
        let maxWidth: Float = 100
        let limitWidth = true
    }
    struct Layer {
        let id: Int
        let contentKind = "text"
        let text: String? = "A"
        let textStyle: TextStyle? = .init()
    }
    let layers: [Layer]
}
enum SceneFrameTextureIdentity { case layerSource(Int) }
enum SceneTextureResourceIdentity { enum Provider { case dynamicText(layerID: Int) }; case provider(Provider) }
enum SceneTextureResourceGeneration { case provider(contentGeneration: UInt64) }
enum SceneTextureLoadPurpose { case premultipliedColor }
enum SceneTextureContent {
    enum Color { case resolved(Representation) }
    enum Representation { case premultipliedAlpha }
    case color(Color)
}
struct SceneTextureUVTransform { static let identity = Self() }
struct SceneTextureSampling { static let linearClamp = Self() }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureResourceIdentity
    let generation: SceneTextureResourceGeneration
    let purpose: SceneTextureLoadPurpose
    let content: SceneTextureContent
    let physicalSize: CGSize
    let mappedSize: CGSize
    let uvTransform: SceneTextureUVTransform
    let sampling: SceneTextureSampling
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
}
struct SceneLayerSourcePublication {
    let layerID: Int
    let publication: SceneTextureProviderPublication
    let renderSizeWH: [Float]
    let textCenterOffsetY: Float
    var texture: MTLTexture { publication.candidate.texture }
    init?(layerID: Int,publication: SceneTextureProviderPublication,
          renderSizeWH: [Float],textCenterOffsetY: Float) {
        self.layerID = layerID; self.publication = publication
        self.renderSizeWH = renderSizeWH; self.textCenterOffsetY = textCenterOffsetY
    }
}
final class ControlledRasterProducer: @unchecked Sendable {
    let startedB = DispatchSemaphore(value: 0), startedC = DispatchSemaphore(value: 0)
    let startedD = DispatchSemaphore(value: 0), allowB = DispatchSemaphore(value: 0)
    let allowC = DispatchSemaphore(value: 0), allowD = DispatchSemaphore(value: 0)
    let published = DispatchSemaphore(value: 0)
    let rasterB: SceneTextTextureLoader.RasterizedTexture
    let rasterD: SceneTextTextureLoader.RasterizedTexture
    private let lock = NSLock()
    private var calls: [String] = []
    init(_ b: SceneTextTextureLoader.RasterizedTexture,_ d: SceneTextTextureLoader.RasterizedTexture) {
        rasterB = b; rasterD = d
    }
    func render(_ content: String) -> SceneTextTextureLoader.RasterizedTexture? {
        lock.lock(); calls.append(content); lock.unlock()
        switch content {
        case "B": startedB.signal(); wait(allowB); return rasterB
        case "C": startedC.signal(); wait(allowC); return nil
        case "D": startedD.signal(); wait(allowD); return rasterD
        default: preconditionFailure("unexpected raster request: \(content)")
        }
    }
    func renderedContents() -> [String] { lock.lock(); defer { lock.unlock() }; return calls }
    func wait(_ semaphore: DispatchSemaphore) {
        precondition(semaphore.wait(timeout: .now()+5) == .success,"producer deadline")
    }
}
enum SceneTextTextureLoader {
    struct RasterizedTexture { let texture: MTLTexture; let renderSizeWH: [Float]; let centerOffsetY: Float }
    static var producer: ControlledRasterProducer!
    static func makeDynamicTexture(for layer: SceneRenderDescriptor.Layer,content: String,
        fontPath: String?,pointSize: Float,colorRGB: [Float],maxWidth: Float,
        cacheDirectory: URL,device: MTLDevice) -> RasterizedTexture? {
        producer.render(content)
    }
}
@main enum StoreProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}"); return
        }
        func raster(_ name: String,_ width: Int,_ height: Int,_ size: [Float],_ offset: Float)
            -> SceneTextTextureLoader.RasterizedTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: width,height: height,mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .shaderRead
            let texture = device.makeTexture(descriptor: descriptor)!
            texture.label = name
            return .init(texture: texture,renderSizeWH: size,centerOffsetY: offset)
        }
        let a = raster("g1",2,3,[120,30],3), b = raster("g2",4,5,[240,50],-11)
        let d = raster("g4",6,7,[360,70],19)
        let producer = ControlledRasterProducer(b,d)
        SceneTextTextureLoader.producer = producer
        let store = SceneDynamicTextTextureStore(descriptor: .init(layers: [.init(id: 7)]),
            cacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),device: device,
            initialRasters: [7:a],dynamicTextFieldsByLayerID: [7:[.content]],
            onPublication: { _ in producer.published.signal() })
        func update(_ content: String) {
            store.update(from: .init(values: [.text(layerID: 7,field: .content): .init(value: .string(content))]),
                dynamicTextFieldsByLayerID: [7:[.content]])
        }
        func atom(_ snapshot: SceneDynamicTextTextureStore.Snapshot?) -> [String: Any] {
            guard let source = snapshot?.layerSources[7] else { return [:] }
            let candidate = source.publication.candidate
            let generation: UInt64
            switch candidate.generation { case .provider(let value): generation = value }
            return ["texture": source.texture.label!,"physicalSize": [source.texture.width,source.texture.height],
                "renderSize": source.renderSizeWH,"offset": source.textCenterOffsetY,
                "generation": generation,"publicationGeneration": source.publication.contentGeneration]
        }
        var result: [String: Any] = ["initialSubmitted": atom(store.submittedSnapshot())]
        _ = store.prepareFrame(); store.commitPreparedFrame()
        result["initialCommitted"] = atom(store.submittedSnapshot())
        _ = store.prepareFrame()
        update("B"); producer.wait(producer.startedB)
        producer.allowB.signal(); producer.wait(producer.published)
        result["preparedWhileBReady"] = atom(store.snapshot())
        result["submittedWhileBReady"] = atom(store.submittedSnapshot())
        store.discardPreparedFrame()
        result["readyAfterDiscard"] = atom(store.snapshot())
        result["submittedAfterDiscard"] = atom(store.submittedSnapshot())
        result["preparedB"] = atom(store.prepareFrame())
        store.commitPreparedFrame()
        result["committedB"] = atom(store.submittedSnapshot())
        store.commitPreparedFrame()
        result["commitWithoutPrepared"] = atom(store.submittedSnapshot())
        update("C"); producer.wait(producer.startedC)
        update("D"); producer.allowC.signal()
        // D can enter only after the real serial Store finished failed C.
        // Keep D blocked while checking the complete previous raster atom.
        producer.wait(producer.startedD)
        result["readyAfterFailure"] = atom(store.snapshot())
        result["submittedAfterFailure"] = atom(store.submittedSnapshot())
        producer.allowD.signal(); producer.wait(producer.published)
        result["readyAfterRecovery"] = atom(store.snapshot())
        result["submittedAfterRecovery"] = atom(store.submittedSnapshot())
        result["renderCalls"] = producer.renderedContents()
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,options: [.sortedKeys]),as: UTF8.self))
    }
}
'''


class SceneDynamicTextGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-text-generation-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "text-generation"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_same_value_is_deduplicated_and_generations_are_monotonic(self) -> None:
        self.assertIsNone(self.result["duplicate"])
        self.assertTrue(self.result["ordered"])

    def test_store_submitted_atom_survives_async_ready_discard_and_failure(self) -> None:
        parent = os.environ.get("MWX_DYNAMIC_TEXT_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="mwx-text-store-", dir=parent))
        try:
            harness = directory / "StoreHarness.swift"
            harness.write_text(STORE_HARNESS, encoding="utf-8")
            binary = directory / "text-store"
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (SOURCE, STORE_SOURCE, Path(__file__), harness)}
            (directory / "source-identity.json").write_text(json.dumps(identity, indent=2))
            compiled = subprocess.run(
                ["swiftc", str(SOURCE), str(STORE_SOURCE), str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            (directory / "compile.log").write_text(compiled.stdout + compiled.stderr)
            self.assertEqual(compiled.returncode, 0, f"{directory}\n{compiled.stderr}")
            completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            (directory / "run.log").write_text(completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, f"{directory}\n{completed.stderr}")
            self.assertEqual(identity, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
                                        for path in identity})
            result = json.loads(completed.stdout)
            (directory / "result.json").write_text(json.dumps(result, indent=2))
            if result.get("metalUnavailable"):
                self.skipTest("Metal is unavailable")
            g1 = result["initialCommitted"]
            g2 = result["committedB"]
            self.assertEqual(result["initialSubmitted"], {})
            for key in ("preparedWhileBReady", "submittedWhileBReady", "submittedAfterDiscard"):
                self.assertEqual(result[key], g1, key)
            for key in ("readyAfterDiscard", "preparedB", "commitWithoutPrepared",
                        "readyAfterFailure", "submittedAfterFailure", "submittedAfterRecovery"):
                self.assertEqual(result[key], g2, key)
            self.assertEqual(g1["texture"], "g1")
            self.assertEqual(g1["physicalSize"], [2, 3])
            self.assertEqual(g1["renderSize"], [120, 30])
            self.assertEqual(g1["offset"], 3)
            self.assertEqual(g2["texture"], "g2")
            self.assertEqual(g2["physicalSize"], [4, 5])
            self.assertEqual(g2["renderSize"], [240, 50])
            self.assertEqual(g2["offset"], -11)
            self.assertGreater(g2["generation"], g1["generation"])
            for atom in (g1, g2, result["readyAfterRecovery"]):
                self.assertEqual(atom["generation"], atom["publicationGeneration"])
            self.assertEqual(result["readyAfterRecovery"]["texture"], "g4")
            self.assertEqual(result["readyAfterRecovery"]["renderSize"], [360, 70])
            self.assertEqual(result["readyAfterRecovery"]["offset"], 19)
            self.assertEqual(result["renderCalls"], ["B", "C", "D"])
        finally:
            if not parent:
                shutil.rmtree(directory)

    def test_stale_or_failed_results_never_replace_the_last_ready_value(self) -> None:
        self.assertFalse(self.result["staleAccepted"])
        self.assertFalse(self.result["failureAccepted"])
        self.assertEqual(self.result["readyAfterFailure"], "A")
        self.assertEqual(
            self.result["generationAfterFailure"],
            self.result["initialReadyGeneration"],
        )
        self.assertTrue(self.result["latestAccepted"])
        self.assertEqual(self.result["readyAfterSuccess"], "C")
        self.assertGreater(
            self.result["generationAfterSuccess"],
            self.result["generationAfterFailure"],
        )
        self.assertIsNone(self.result["readyAfterReset"])
        self.assertIsNone(self.result["generationAfterReset"])

    def test_continuous_updates_keep_only_one_render_in_flight_and_then_latest(self) -> None:
        self.assertFalse(self.result["queuedLatestStartedImmediately"])
        # 单在途调度保证按 generation 完成；中间结果可安全发布，随后只追最新，
        # 避免连续 Timeline 因永远落后一帧而饿死。
        self.assertTrue(self.result["scheduledStaleAccepted"])
        self.assertEqual(self.result["scheduledNextContent"], "C")
        self.assertTrue(self.result["scheduledLatestAccepted"])
        self.assertFalse(self.result["scheduledHasThirdTask"])
        self.assertEqual(self.result["scheduledReadyWidth"], 300)

    def test_ready_texture_publication_declares_premultiplied_metadata(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        for token in (
            "SceneTextureProviderPublication(",
            "requestIdentity: .layerSource(layerID)",
            "candidate: SceneTextureCandidate(",
            "identity: .provider(.dynamicText(layerID: layerID))",
            "generation: .provider(contentGeneration: generation)",
            "purpose: .premultipliedColor",
            "content: .color(.resolved(.premultipliedAlpha))",
            "SceneLayerSourcePublication(",
            "renderSizeWH: raster.renderSizeWH",
            "let snapshot = Snapshot(layerSources: layerSources)",
        ):
            self.assertIn(token, source)
        self.assertNotIn("let renderSizes:", source)

    def test_dynamic_text_candidate_is_an_exact_same_layer_graph_source(self) -> None:
        source = DRAW_REQUEST_SOURCE.read_text(encoding="utf-8")
        for token in (
            'case let ("text", .provider(.dynamicText(candidateLayerID)))',
            "acceptsCandidate = candidateLayerID == layer.id",
            "SceneBaseImageTextureCandidateResolver.sample(",
        ):
            self.assertIn(token, source)

    def test_text_provider_consumes_prepared_target_interest_before_signature_projection(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        for token in (
            "dynamicTextFieldsByLayerID",
            "dynamicTextFieldsByLayerID: [Int: Set<SceneDynamicTextField>] = [:]",
            "dynamicFields: Set<SceneDynamicTextField>",
            "dynamicFields.contains(.content)",
            "dynamicFields.contains(.font)",
            "dynamicFields.contains(.pointSize)",
            "dynamicFields.contains(.color)",
            "dynamicFields.contains(.maxWidth)",
        ):
            self.assertIn(token, source)
        host_source = HOST_SOURCE.read_text(encoding="utf-8")
        self.assertIn("dynamicTextFieldsByLayerID:", host_source)
        self.assertIn(
            "launchContext.frameSchema.dynamicTextFieldsByLayerID", host_source
        )

    def test_text_provider_reuses_ready_publication_snapshot_until_completion_or_retirement(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        for token in (
            "private var cachedSnapshot: Snapshot?",
            "private var snapshotDirty = true",
            "private var preparedFrameSnapshot: Snapshot?",
            "func prepareFrame() -> Snapshot",
            "if let preparedFrameSnapshot { return preparedFrameSnapshot }",
            "func commitPreparedFrame()",
            "func discardPreparedFrame()",
            "if !snapshotDirty, let cachedSnapshot { return cachedSnapshot }",
            "cachedSnapshot = snapshot",
            "snapshotDirty = true",
        ):
            self.assertIn(token, source)

    def test_text_provider_frame_pin_is_cleared_only_at_host_outcome(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        view = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift")
        view_source = view.read_text(encoding="utf-8")
        self.assertIn("let dynamicTextSnapshot = dynamicTextTextures?.prepareFrame()", view_source)
        self.assertIn("dynamicTextTextures?.discardPreparedFrame()", view_source)
        self.assertIn("dynamicTextTextures?.commitPreparedFrame()", view_source)
        self.assertIn("return makeSnapshotLocked()", source)

    def test_static_text_layers_leave_generation_state_untouched_after_preparation(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        self.assertIn("var signatureRefreshLayerIDs: Set<Int> = []", source)
        self.assertIn(
            "guard !dynamicFields.isEmpty",
            source,
        )
        self.assertIn(
            "|| signatureRefreshLayerIDs.contains(layer.id) else { continue }",
            source,
        )

    def test_static_text_update_has_a_quiescent_gate_without_bypassing_dynamic_state(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        gate = source.index("let incomingHasDynamicTextFields")
        normal_path = source.index("let admittedDynamic =", gate)
        gate_source = source[gate:normal_path]
        self.assertIn("dynamicLayers.isEmpty && !incomingHasDynamicTextFields", gate_source)
        self.assertIn("hasAdmittedDynamicLayer", gate_source)
        self.assertIn("hasAuthoredDynamicFields", gate_source)
        self.assertIn("if !hasAdmittedDynamicLayer && !hasAuthoredDynamicFields", gate_source)
        self.assertIn("return", gate_source)


if __name__ == "__main__":
    unittest.main()
