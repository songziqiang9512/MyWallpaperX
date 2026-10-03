#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RENDERER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
COMPOSITOR = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
BASE_IMAGE_TEXTURE_LOAD = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad.swift"
TRANSACTION = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneSourceUpdateTransaction.swift"
EFFECT_EXECUTION = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+EffectExecution.swift"
UTILITY_PLAN = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityPlanFrameRenderer.swift"
UTILITY_LAYER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRenderer.swift"
VIEW = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
FRAME_DRIVER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
FRAME_DRIVER_LIFECYCLE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriverLifecycle.swift"
SCALAR_PROGRAM = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarProgram.swift"
STRING_PROGRAM = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptStringProgram.swift"
VECTOR_PROGRAM = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptVectorProgram.swift"
MEDIA_EVENT_BRIDGE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptMediaEventBridge.swift"
TIMER_HOST = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSTimerHost.c"
AUDIO_SPECTRUM = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"
PUPPET = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState.swift"
SPRITE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneMultiImageSpritePlayback.swift"
PARTICLE_PLAYBACK = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift"
PARTICLE_VIEW = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView+ParticlePlayback.swift"
DYNAMIC_TEXT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextTextureStore.swift"
DYNAMIC_IMAGE_PROVIDER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneDynamicImageTextureProvider.swift"
TEXTURE_REGISTRY = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift"
TEXTURE_FRAME = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+TextureFrame.swift"
ASSET_CATALOG = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneMaterialAssetTextureCatalog.swift"
RUNTIME_BRIDGE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
GRAPH_COMPOSITION = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneResolvedMaterialGraphComposition.swift"


# Host all-surface rollback source checks retired with D10.
# Actual presentation/VM behavior: test_scene_frame_presentation_integration.
# GPU source ownership: test_scene_surface_submission and the FIFO harness below.
class SceneSourceUpdateTransactionTests(unittest.TestCase):
    def test_dynamic_image_provider_reuses_publications_for_value_only_updates(self) -> None:
        source = DYNAMIC_IMAGE_PROVIDER.read_text(encoding="utf-8")
        for token in (
            "private var cachedRevision: UInt64?",
            "private var cachedSnapshot: SceneDynamicImageTextureProviderSnapshot?",
            "topology: SceneScriptLayerTopologySnapshot",
            "if cachedRevision == topology.topologyRevision, let cachedSnapshot",
            "cachedRevision = topology.topologyRevision",
            "cachedSnapshot = snapshot",
        ):
            self.assertIn(token, source)
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("dynamicImageTextures?.snapshot(", view)
        self.assertIn("topology: layerTopology", view)


    def test_transaction_rolls_back_in_reverse_once_and_commit_closes_it(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        declaration = TRANSACTION.read_text(encoding="utf-8").replace(
            "private func resolveSubmitted", "func resolveSubmitted"
        ).replace(
            "    func arm(on commandBuffer: MTLCommandBuffer) {",
            "    func testArmWithoutCommandBuffer() {\n"
            "        lock.lock()\n"
            "        state = .armed\n"
            "        lock.unlock()\n"
            "    }\n\n"
            "    func arm(on commandBuffer: MTLCommandBuffer) {",
        )
        harness = declaration + r'''

@main
enum Harness {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        var cancelled: [String] = []
        let abandoned = SceneSourceUpdateTransaction()
        abandoned.registerRollback { cancelled.append("first") }
        abandoned.registerRollback { cancelled.append("second") }
        abandoned.cancel()
        abandoned.cancel()

        let completion = DispatchSemaphore(value: 0)
        var completedCount = 0
        var submittedRolledBack = false
        let submitted = SceneSourceUpdateTransaction()
        submitted.registerResolution(
            completed: {
                completedCount += 1
                completion.signal()
            },
            rollback: {
                submittedRolledBack = true
                completion.signal()
            }
        )
        let completedBuffer = queue.makeCommandBuffer()!
        submitted.arm(on: completedBuffer)
        completedBuffer.commit()
        submitted.didSubmit()
        guard completion.wait(timeout: .now() + 5) == .success else {
            fatalError("completion timed out")
        }
        submitted.resolveSubmitted(succeeded: true)
        submitted.cancel()

        var failedSignature: Int? = 7
        var failedRollbackCount = 0
        let failed = SceneSourceUpdateTransaction()
        failed.registerRollback {
            failedSignature = nil
            failedRollbackCount += 1
        }
        failed.testArmWithoutCommandBuffer()
        failed.didSubmit()
        failed.resolveSubmitted(succeeded: false)
        failed.cancel()

        func markSubmitted(_ transaction: SceneSourceUpdateTransaction) {
            transaction.testArmWithoutCommandBuffer()
            transaction.didSubmit()
        }
        let fifo = SceneSourceUpdateStateFIFO<Int>(initial: 0)
        let ancestor = SceneSourceUpdateTransaction()
        let ancestorCandidate = fifo.update(transaction: ancestor) {
            $0 += 1
            return $0
        }
        markSubmitted(ancestor)
        let abandonedDescendant = SceneSourceUpdateTransaction()
        fifo.update(transaction: abandonedDescendant) {
            $0 += 10
        }
        abandonedDescendant.cancel()
        var baseAfterDescendantCancel = -1
        let firstProbe = SceneSourceUpdateTransaction()
        fifo.update(transaction: firstProbe) {
            baseAfterDescendantCancel = $0
        }
        firstProbe.cancel()
        ancestor.resolveSubmitted(succeeded: true)

        let failedAncestor = SceneSourceUpdateTransaction()
        fifo.update(transaction: failedAncestor) { $0 += 2 }
        markSubmitted(failedAncestor)
        let dependent = SceneSourceUpdateTransaction()
        fifo.update(transaction: dependent) { $0 += 4 }
        markSubmitted(dependent)
        dependent.resolveSubmitted(succeeded: true)
        failedAncestor.resolveSubmitted(succeeded: false)
        var baseAfterAncestorFailure = -1
        let secondProbe = SceneSourceUpdateTransaction()
        fifo.update(transaction: secondProbe) {
            baseAfterAncestorFailure = $0
        }
        secondProbe.cancel()

        print(cancelled.joined(separator: ","))
        print(
            completedCount == 1 && !submittedRolledBack
                ? "completed" : "invalid"
        )
        print(failedSignature == nil && failedRollbackCount == 1 ? "retry" : "stuck")
        print(
            ancestorCandidate == 1 && baseAfterDescendantCancel == 1
                && baseAfterAncestorFailure == 1 ? "fifo" : "corrupt"
        )
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-source-update-") as directory:
            source = Path(directory) / "main.swift"
            binary = Path(directory) / "transaction"
            source.write_text(harness, encoding="utf-8")
            subprocess.run(
                ["swiftc", "-parse-as-library", str(source), "-o", str(binary)],
                check=True,
                cwd=ROOT,
            )
            output = subprocess.check_output([str(binary)], text=True).splitlines()
        self.assertEqual(
            output,
            ["second,first", "completed", "retry", "fifo"],
        )

    def test_renderer_wires_exact_layer_source_publication_without_consuming_dependency(self) -> None:
        source = read_source_family(RENDERER)
        compositor = COMPOSITOR.read_text(encoding="utf-8")
        texture_load = BASE_IMAGE_TEXTURE_LOAD.read_text(encoding="utf-8")
        snapshot = texture_load.split(
            "struct SceneBaseImageTextureSnapshot", maxsplit=1
        )[1].split("struct SceneBaseImageTextureStore", maxsplit=1)[0]

        self.assertIn("func explicitLayerSourcePublication(", snapshot)
        self.assertIn("publication.texture === texture", snapshot)
        self.assertIn(
            "publication.requestIdentity == .layerSource(layerID)", snapshot
        )
        self.assertIn("publication.isComplete", snapshot)

        publication = source.index(
            "let explicitLayerSourcePublication = imageTextures"
        )
        publication_lookup = source.index(
            ".explicitLayerSourcePublication(", publication
        )
        missing_dependency_guard = source.index(
            "if request.requiresDependencyEffect,",
            publication_lookup,
        )
        draw_outcome = source.index(
            "let drawOutcome = imageCompositor.drawOutcome(",
            missing_dependency_guard,
        )
        # The image stage returns its outcome to the ordered-loop caller before
        # binding publication; inspect each real body instead of concatenation order.
        ordered = RENDERER.with_name("SceneMetalRenderer+OrderedLayerEncoding.swift").read_text(encoding="utf-8")
        image_call = ordered.index("let imageResult = encodeImageLayer(")
        returned_outcome = ordered.index("guard let drawOutcome = imageResult.outcome", image_call)
        binding_record = ordered.index("dependencyRuntime.recordBindingIfRequired(", returned_outcome)
        claimed_failure_stop = ordered.index(
            "resolvedMaterialFrameTargetPlans[layer.id] != nil", binding_record
        )
        image_return = source.index("return (false, drawOutcome)", draw_outcome)

        self.assertLess(publication, publication_lookup)
        self.assertLess(publication_lookup, missing_dependency_guard)
        self.assertLess(missing_dependency_guard, draw_outcome)
        self.assertLess(image_call, returned_outcome)
        self.assertLess(returned_outcome, binding_record)
        self.assertLess(draw_outcome, image_return)
        self.assertLess(binding_record, claimed_failure_stop)
        self.assertIn(
            "for: layer.id,\n                matching: texture",
            source[publication:missing_dependency_guard],
        )
        self.assertIn("request.dependencyEffects.isEmpty", source[
            missing_dependency_guard:draw_outcome
        ])
        self.assertIn(
            "explicitLayerSourcePublication: explicitLayerSourcePublication",
            source[draw_outcome:image_return],
        )
        self.assertIn(
            "encoded: drawOutcome.consumedDependency",
            ordered[binding_record:],
        )

        outcome = compositor.split("enum DrawOutcome: Equatable", maxsplit=1)[1]
        outcome = outcome.split(
            "let authoredEffectPipelines:", maxsplit=1
        )[0]
        self.assertIn("case layerSourcePassthrough", outcome)
        self.assertIn(
            "case let .normal(consumedDependency),\n"
            "                 let .geometryEncoded(consumedDependency):",
            outcome,
        )
        self.assertIn("return false", outcome)

    def test_base_snapshot_preserves_legacy_video_but_requires_atomic_text_extent(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        snapshot = BASE_IMAGE_TEXTURE_LOAD.read_text(encoding="utf-8").split(
            "struct SceneBaseImageTextureStore", maxsplit=1
        )[0]
        harness = snapshot + r'''

enum SceneFrameTextureIdentity: Equatable {
    case layerSource(Int)
}

struct SceneGeometryProduct {
    func matchesInstalledSource(
        layerID: Int,
        texture: MTLTexture
    ) -> Bool {
        _ = layerID
        _ = texture
        return false
    }
}

struct SceneTextureCandidate {
    let texture: MTLTexture
}

struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let texture: MTLTexture
    let isComplete: Bool

    var candidate: SceneTextureCandidate {
        SceneTextureCandidate(texture: texture)
    }
}

struct SceneLayerSourcePublication {
    let publication: SceneTextureProviderPublication
    let renderSizeWH: [Float]?
    let effectRenderSizeWH: [Float]? = nil

    static func supportsDirectTextureLane(
        layerID: Int,
        publication: SceneTextureProviderPublication
    ) -> Bool {
        publication.requestIdentity == .layerSource(layerID)
    }

    func isComplete(layerID: Int, matching texture: MTLTexture) -> Bool {
        publication.requestIdentity == .layerSource(layerID)
            && publication.texture === texture
            && publication.isComplete
    }
}

@main
enum Harness {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal unavailable")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        let video = device.makeTexture(descriptor: descriptor)!
        let replacement = device.makeTexture(descriptor: descriptor)!
        let unresolvedVideo = SceneTextureProviderPublication(
            requestIdentity: .layerSource(13),
            texture: video,
            isComplete: false
        )
        let videoSnapshot = SceneBaseImageTextureSnapshot(
            textures: [13: video],
            explicitLayerSources: [13: unresolvedVideo],
            candidates: [:]
        )
        guard videoSnapshot[13] === video,
              videoSnapshot.layerSourceRenderSize(for: 13) == nil,
              videoSnapshot.explicitLayerSourcePublication(
                for: 13, matching: video
              ) == nil else {
            fatalError("legacy video lane regressed")
        }

        let completeText = SceneTextureProviderPublication(
            requestIdentity: .layerSource(13),
            texture: replacement,
            isComplete: true
        )
        let textAtom = SceneLayerSourcePublication(
            publication: completeText,
            renderSizeWH: [640, 320]
        )
        let textSnapshot = SceneBaseImageTextureSnapshot(
            textures: [13: replacement],
            explicitLayerSources: [13: unresolvedVideo],
            layerSourcePublications: [13: textAtom],
            candidates: [:]
        )
        guard textSnapshot[13] === replacement,
              textSnapshot.layerSourceRenderSize(for: 13) == [640, 320],
              textSnapshot.candidate(
                  for: 13, matching: replacement
              )?.texture === replacement,
              textSnapshot.explicitLayerSourcePublication(
                for: 13, matching: replacement
              )?.texture === replacement else {
            fatalError("atomic text lane was not preferred")
        }
        let mismatchedAtomSnapshot = SceneBaseImageTextureSnapshot(
            textures: [13: video],
            layerSourcePublications: [13: textAtom],
            candidates: [:]
        )
        guard mismatchedAtomSnapshot[13] == nil,
              mismatchedAtomSnapshot.layerSourceRenderSize(for: 13) == nil else {
            fatalError("mismatched atom did not fail closed")
        }
        let pendingVideoSnapshot = SceneBaseImageTextureSnapshot(
            textures: [:],
            candidates: [:],
            pendingLayerSourceIDs: [21]
        )
        guard pendingVideoSnapshot.isLayerSourcePending(21),
              !pendingVideoSnapshot.isLayerSourcePending(22) else {
            fatalError("pending layer-source identity was not preserved")
        }
        print("preserved")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-base-layer-source-") as directory:
            source = Path(directory) / "main.swift"
            binary = Path(directory) / "base-layer-source"
            source.write_text(harness, encoding="utf-8")
            subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    "-parse-as-library", str(source), "-o", str(binary),
                ],
                check=True,
                cwd=ROOT,
            )
            output = subprocess.check_output([str(binary)], text=True).strip()
        self.assertEqual(output, "preserved")


    def test_dynamic_text_provider_publishes_only_after_frame_submission(self) -> None:
        view = VIEW.read_text(encoding="utf-8")
        dynamic_text = DYNAMIC_TEXT.read_text(encoding="utf-8")
        prepare = view.index(
            "let dynamicTextSnapshot = dynamicTextTextures?.prepareFrame()"
        )
        local_discard = view.index(
            "dynamicTextTextures?.discardPreparedFrame()", prepare
        )
        outcome = view.index("let outcome = renderer.renderFrame(", prepare)
        pending = view.index("pendingDynamicTextUpdate = (", outcome)
        commit = view.index("func commitPreparedDynamicTextUpdate()")
        update = view.index("dynamicTextTextures?.update(", commit)

        self.assertLess(prepare, outcome)
        self.assertLess(outcome, local_discard)
        self.assertLess(commit, update)
        self.assertIn("func discardPreparedDynamicTextUpdate()", view)
        self.assertIn("Dynamic text is asynchronous", view)
        self.assertIn("private var generationState", dynamic_text)
        self.assertIn("generationState.finish(request", dynamic_text)





if __name__ == "__main__":
    unittest.main()
