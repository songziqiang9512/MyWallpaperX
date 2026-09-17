#!/usr/bin/env python3

from __future__ import annotations

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
FRAME_DRIVER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriver.swift"
FRAME_DRIVER_LIFECYCLE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+FrameDriverLifecycle.swift"
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

    def test_scene_script_program_state_retries_after_host_drop(self) -> None:
        driver = FRAME_DRIVER.read_text(encoding="utf-8")
        lifecycle = FRAME_DRIVER_LIFECYCLE.read_text(encoding="utf-8")
        scalar = SCALAR_PROGRAM.read_text(encoding="utf-8")
        string = STRING_PROGRAM.read_text(encoding="utf-8")
        vector = VECTOR_PROGRAM.read_text(encoding="utf-8")
        events = MEDIA_EVENT_BRIDGE.read_text(encoding="utf-8")
        timer_host = TIMER_HOST.read_text(encoding="utf-8")
        audio_spectrum = AUDIO_SPECTRUM.read_text(encoding="utf-8")
        scalar_runtime = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptScalarRuntime.swift"
        ).read_text(encoding="utf-8")
        layer_bridge = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift"
        ).read_text(encoding="utf-8")

        timer_snapshot = driver.index("let sceneScriptProgramTimerFrameState")
        snapshot = driver.index(
            "let sceneScriptProgramFrameState", timer_snapshot
        )
        timer_guard = driver.index(
            "sceneScriptProgramTimerFrameState.scalar.isComplete"
        )
        cursor_dispatch = driver.index(
            "launchContext.sceneScriptCursorProgram.dispatch(", snapshot
        )
        coordinator = driver.index(
            "launchContext.frameSchema.mediaFrameCoordinator.evaluate(",
            cursor_dispatch,
        )
        host_barrier = driver.index("let allSurfacesSubmitted", coordinator)
        restore = driver.index(
            "restoreSceneScriptProgramFrameState(", host_barrier
        )
        timer_restore = driver.index(
            "restoreSceneScriptProgramTimerFrameState(", host_barrier
        )
        storage_discard = driver.index(
            "sceneScriptStorageSession?.discardFrameTransaction()", restore
        )
        commit = driver.index("commitSubmittedSceneFrame(", host_barrier)
        snapshot_discard = driver.index(
            "discardSceneScriptFrameOutcome(launchContext)", host_barrier
        )
        snapshot_finalize = lifecycle.index(
            "finalizeSceneScriptLayerSnapshot(context)",
        )
        timer_discard = driver.index(
            "discardSceneScriptProgramTimerFrameState(", commit
        )
        audio_prepare = driver.index(
            "let audioSpectrumFrame = SceneAudioSpectrumInbox.shared.prepareFrame()"
        )
        audio_commit = driver.index(
            "SceneAudioSpectrumInbox.shared.commitFrame(audioSpectrumFrame)",
            commit,
        )
        self.assertLess(snapshot, cursor_dispatch)
        self.assertLess(timer_snapshot, snapshot)
        self.assertLess(timer_guard, cursor_dispatch)
        self.assertLess(timer_snapshot, cursor_dispatch)
        self.assertLess(cursor_dispatch, coordinator)
        self.assertLess(coordinator, host_barrier)
        self.assertLess(host_barrier, restore)
        self.assertLess(restore, storage_discard)
        self.assertLess(timer_restore, storage_discard)
        self.assertGreater(commit, host_barrier)
        self.assertGreater(snapshot_discard, restore)
        self.assertLess(snapshot_discard, commit)
        self.assertIn("discardSceneScriptFrameOutcome(launchContext)", driver)
        self.assertGreater(snapshot_finalize, lifecycle.index("commitSceneScriptLayerPlan("))
        self.assertGreater(timer_discard, commit)
        self.assertLess(audio_prepare, cursor_dispatch)
        self.assertLess(host_barrier, audio_commit)
        self.assertLess(commit, audio_commit)
        self.assertIn("struct FrameSnapshot", audio_spectrum)
        self.assertIn("func prepareFrame()", audio_spectrum)
        self.assertIn("func commitFrame(_ frame: FrameSnapshot)", audio_spectrum)
        self.assertIn("sourceGeneration", audio_spectrum)

        self.assertIn("frameStateSnapshot()", lifecycle)
        self.assertIn("func restoreSceneScriptProgramFrameState(", lifecycle)
        for source in (scalar, string, vector):
            self.assertIn("consumedMediaThumbnailGenerations", source)
            self.assertIn("appliedUserProperties", source)
            self.assertIn("func frameStateSnapshot()", source)
        self.assertIn("func restoreFrameState(", source)
        self.assertIn("discardCommittedLayerSnapshot()", scalar_runtime)
        self.assertIn("finalizeCommittedLayerSnapshot()", scalar_runtime)
        self.assertIn("awaitingHostFrameOutcome: Bool = false", layer_bridge)
        self.assertIn("if !awaitingHostFrameOutcome", layer_bridge)
        self.assertIn("awaitingHostFrameOutcome: true", driver)
        self.assertIn("func snapshot() -> Event?", events)
        self.assertIn("mutating func restore(_ snapshot: Event?)", events)
        self.assertIn("struct SceneScriptProgramFrameState: Sendable", events)
        self.assertIn("struct SceneScriptProgramTimerFrameState", events)
        self.assertIn("mwx_scene_quickjs_owner_timer_snapshot", timer_host)
        self.assertIn("mwx_scene_quickjs_owner_timer_restore", timer_host)
        self.assertIn("mwx_scene_quickjs_owner_timer_snapshot_destroy", timer_host)

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

    def test_renderer_cancels_every_uncommitted_exit_and_closes_after_submit(self) -> None:
        source = RENDERER.read_text(encoding="utf-8")
        transaction = source.index(
            "let sourceUpdateTransaction = SceneSourceUpdateTransaction()"
        )
        deferred_cancel = source.index(
            "defer {\n            sourceUpdateTransaction.cancel()", transaction
        )
        source_updates = source.index(
            "let puppetAttachmentFrames = encodeSourceUpdates?(",
            deferred_cancel,
        )
        seal = source.index(
            "guard imageCompositor.endResolvedMaterialFrame(on: commandBuffer)",
            source_updates,
        )
        transaction_arm = source.index(
            "sourceUpdateTransaction.arm(on: commandBuffer)", seal
        )
        command_commit = source.index("commandBuffer.commit()", transaction_arm)
        did_submit = source.index(
            "sourceUpdateTransaction.didSubmit()", command_commit
        )
        self.assertLess(transaction, deferred_cancel)
        self.assertLess(deferred_cancel, source_updates)
        self.assertLess(source_updates, seal)
        self.assertLess(seal, transaction_arm)
        self.assertLess(transaction_arm, command_commit)
        self.assertLess(command_commit, did_submit)
        self.assertEqual(source.count("commandBuffer.commit()"), 1)
        self.assertNotIn("finishUnsubmittedCommandBuffer", source)
        self.assertNotIn("frameTransaction: sourceUpdateTransaction", source)
        claimed_failure_stop = source.index(
            "request.resolvedMaterialFrameTargetPlan != nil"
        )
        draw_outcome = source.index(
            "let drawOutcome = imageCompositor.drawOutcome("
        )
        self.assertGreater(claimed_failure_stop, draw_outcome)
        self.assertLess(claimed_failure_stop, source.index("mainPass.finishEnsuringClear()"))
        self.assertIn("break frameLayers", source)
        utility_defer = source.index("defer {")
        utility_guard = source.index(
            "if !stopsAfterClaimedFailure {", utility_defer
        )
        self.assertLess(
            utility_guard,
            source.index("renderUtilityPlans(", utility_guard),
        )
        transaction_source = TRANSACTION.read_text(encoding="utf-8")
        self.assertIn("case pending", transaction_source)
        self.assertIn("case armed", transaction_source)
        self.assertIn("case submitted", transaction_source)
        self.assertIn("case resolved", transaction_source)
        self.assertIn("buffer.status == .completed", transaction_source)
        self.assertIn("private let lock = NSLock()", transaction_source)

        compositor = COMPOSITOR.read_text(encoding="utf-8")
        self.assertNotIn("frameTransaction:", compositor)
        self.assertNotIn("frameTransaction.registerResolution(", compositor)
        self.assertNotIn(
            "commandBuffer.addCompletedHandler { _ in commit.releaseAll() }",
            compositor,
        )
        self.assertNotIn("prepareAndRegisterLegacyAuthoredBatch(", source)
        self.assertNotIn("legacyAuthoredFrameTables", source)
        for path in (EFFECT_EXECUTION, UTILITY_PLAN, UTILITY_LAYER):
            utility_source = path.read_text(encoding="utf-8")
            self.assertNotIn("frameTransaction: SceneSourceUpdateTransaction", utility_source)
            self.assertNotIn("frameTransaction: frameTransaction", utility_source)

    def test_renderer_wires_exact_layer_source_publication_without_consuming_dependency(self) -> None:
        source = RENDERER.read_text(encoding="utf-8")
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
        binding_record = source.index(
            "dependencyRuntime.recordBindingIfRequired(", draw_outcome
        )
        claimed_failure_stop = source.index(
            "request.resolvedMaterialFrameTargetPlan != nil", binding_record
        )

        self.assertLess(publication, publication_lookup)
        self.assertLess(publication_lookup, missing_dependency_guard)
        self.assertLess(missing_dependency_guard, draw_outcome)
        self.assertLess(draw_outcome, binding_record)
        self.assertLess(binding_record, claimed_failure_stop)
        self.assertIn(
            "for: layer.id,\n                        matching: texture",
            source[publication:missing_dependency_guard],
        )
        self.assertIn("request.dependencyEffect == nil", source[
            missing_dependency_guard:draw_outcome
        ])
        self.assertIn(
            "explicitLayerSourcePublication: explicitLayerSourcePublication",
            source[draw_outcome:binding_record],
        )
        self.assertIn(
            "encoded: drawOutcome.consumedDependency",
            source[binding_record:claimed_failure_stop],
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

    def test_every_mutating_source_producer_registers_exact_rollback(self) -> None:
        view = VIEW.read_text(encoding="utf-8")
        puppet = PUPPET.read_text(encoding="utf-8")
        sprite = SPRITE.read_text(encoding="utf-8")
        particle_playback = PARTICLE_PLAYBACK.read_text(encoding="utf-8")
        particle_view = PARTICLE_VIEW.read_text(encoding="utf-8")

        source_closure = view.split("encodeSourceUpdates:", maxsplit=1)[1]
        source_closure = source_closure.split(
            "encodeFrameReadback:", maxsplit=1
        )[0]
        self.assertEqual(source_closure.count("transaction: transaction"), 2)
        self.assertNotIn("encodeLayerSourceUpdates", view)

        self.assertIn("SceneSourceUpdateStateFIFO(", puppet)
        self.assertIn("submissions.update(transaction: transaction)", puppet)
        self.assertIn(
            "guard signature != submission.frameSignature\n"
            "                    || submission.boneRevision != boneRevision else {\n"
            "                return submission.attachmentFrames\n"
            "            }",
            puppet,
        )
        self.assertIn("submission.frameSignature = signature", puppet)

        sprite_encode = sprite.index("conversion.encode(")
        sprite_rollback = sprite.index("transaction.registerRollback", sprite_encode)
        completion = sprite.index("commandBuffer.addCompletedHandler", sprite_rollback)
        self.assertIn("submissionTracker.cancel(submission)", sprite[sprite_rollback:completion])
        self.assertIn("if latest?.id == token.id", sprite)
        self.assertIn("func discardLatest()", sprite)
        self.assertIn("submissionTracker.discardLatest()", sprite)
        self.assertIn("func discardPreparedSpriteFrames()", view)
        frame_driver = FRAME_DRIVER.read_text(encoding="utf-8")
        barrier = frame_driver.index("let allSurfacesSubmitted =")
        self.assertIn("func prepareFrame()", particle_playback)
        self.assertIn("func commitPreparedFrame()", particle_playback)
        self.assertIn("func discardPreparedFrame()", particle_playback)
        self.assertIn("particlePlayback.prepareFrame()", particle_view)
        self.assertIn("particlePlayback?.discardPreparedFrame()", view)
        self.assertIn("func commitPreparedParticleFrame()", particle_view)
        self.assertIn("func discardPreparedParticleFrame()", particle_view)
        particle_discard = frame_driver.index("discardPreparedParticleFrame()", barrier)
        sprite_discard = frame_driver.index("discardPreparedSpriteFrames()", barrier)
        asset_discard = frame_driver.index("discardPreparedMaterialAssetFrame()", barrier)
        self.assertLess(particle_discard, sprite_discard)
        self.assertLess(sprite_discard, asset_discard)
        particle_commit = frame_driver.index("commitPreparedParticleFrame()", barrier)
        asset_commit = frame_driver.index("commitPreparedMaterialAssetFrame()", barrier)
        self.assertLess(particle_commit, asset_commit)

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
        submitted = view.index("if outcome.isSubmitted {", outcome)
        pending = view.index("pendingDynamicTextUpdate = (", submitted)
        commit = view.index("func commitPreparedDynamicTextUpdate()")
        update = view.index("dynamicTextTextures?.update(", commit)

        self.assertLess(prepare, outcome)
        self.assertLess(outcome, local_discard)
        self.assertLess(outcome, submitted)
        self.assertLess(submitted, pending)
        self.assertLess(commit, update)
        self.assertIn("func discardPreparedDynamicTextUpdate()", view)
        self.assertIn("Dynamic text is asynchronous", view)
        self.assertIn("private var generationState", dynamic_text)
        self.assertIn("generationState.finish(request", dynamic_text)

    def test_video_provider_publication_waits_for_host_submission_barrier(self) -> None:
        view = VIEW.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER.read_text(encoding="utf-8")
        outcome = view.index("let outcome = renderer.renderFrame(")
        submitted = view.index("if outcome.isSubmitted {", outcome)
        video_commit = view.index("func commitPreparedVideoFrames()")
        video_discard = view.index("func discardPreparedVideoFrames()")
        self.assertNotIn("commitPreparedFrame()", view[outcome:submitted])
        self.assertNotIn("discardPreparedFrame()", view[outcome:submitted])
        self.assertIn("videoTextureSources.values.forEach { $0.commitPreparedFrame() }", view[video_commit:])
        self.assertIn("videoTextureSources.values.forEach { $0.discardPreparedFrame() }", view[video_discard:])
        barrier = frame_driver.index("let allSurfacesSubmitted =")
        discard = frame_driver.index("discardPreparedVideoFrames()", barrier)
        commit = frame_driver.index("commitPreparedVideoFrames()", barrier)
        dynamic_commit = frame_driver.index("commitPreparedDynamicTextUpdate()", barrier)
        self.assertLess(barrier, discard)
        self.assertLess(barrier, commit)
        self.assertLess(commit, dynamic_commit)

    def test_media_thumbnail_request_waits_for_host_submission_barrier(self) -> None:
        view = VIEW.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER.read_text(encoding="utf-8")
        prepare = view.index("func prepareMediaThumbnail(")
        outcome = view.index("let outcome = renderer.renderFrame(")
        self.assertLess(prepare, outcome)
        self.assertIn("pendingMediaThumbnailInput = input", view[prepare:outcome])
        self.assertNotIn(
            "mediaThumbnailCoordinator.update(from: input)", view[prepare:outcome]
        )
        commit = view.index("func commitPreparedMediaThumbnailUpdate()")
        discard = view.index("func discardPreparedMediaThumbnailUpdate()")
        self.assertIn(
            "mediaThumbnailCoordinator.update(from: pendingMediaThumbnailInput)",
            view[commit:],
        )
        self.assertIn(
            "mediaThumbnailCoordinator.commitPreparedFrame()",
            view[commit:],
        )
        self.assertIn(
            "mediaThumbnailCoordinator.discardPreparedFrame()",
            view[discard:],
        )
        barrier = frame_driver.index("let allSurfacesSubmitted =")
        barrier_discard = frame_driver.index(
            "discardPreparedMediaThumbnailUpdate()", barrier
        )
        barrier_commit = frame_driver.index(
            "commitPreparedMediaThumbnailUpdate()", barrier
        )
        frame_commit = frame_driver.index("commitSubmittedSceneFrame(", barrier)
        self.assertLess(barrier, barrier_discard)
        self.assertLess(barrier, barrier_commit)
        self.assertLess(barrier_commit, frame_commit)

    def test_frame_texture_publication_waits_for_host_submission_barrier(self) -> None:
        registry = TEXTURE_REGISTRY.read_text(encoding="utf-8")
        texture_frame = TEXTURE_FRAME.read_text(encoding="utf-8")
        renderer = RENDERER.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER.read_text(encoding="utf-8")

        begin = registry.index("func beginFrame(")
        commit = registry.index("func commitFramePublication()", begin)
        discard = registry.index("func discardFramePublication()", commit)
        self.assertIn("framePublicationBaseline = FramePublicationBaseline(", registry[begin:commit])
        self.assertIn("if framePublicationBaseline != nil", registry[begin:commit])
        self.assertIn("committedPublications = baseline.committedPublications", registry[discard:])
        self.assertIn("entries.removeAll(keepingCapacity: true)", registry[discard:])

        self.assertIn("textureRegistry.commitFramePublication()", texture_frame)
        self.assertIn("textureRegistry.discardFramePublication()", texture_frame)
        source_transaction = renderer.index("let sourceUpdateTransaction =")
        renderer_defer = renderer.index("Unsubmitted source and registry state", source_transaction)
        self.assertIn("discardUnsubmittedFrameResources()", renderer[renderer_defer:])
        self.assertLess(renderer.index("commandBuffer.commit()"), renderer.index("didCommitParticleSubmission = true"))

        view_commit = view.index("func commitPreparedFrameTexturePublication()")
        view_discard = view.index("func discardPreparedFrameTexturePublication()")
        self.assertIn("renderer.commitFrameTexturePublication()", view[view_commit:])
        self.assertIn("renderer.discardFrameTexturePublication()", view[view_discard:])
        barrier = frame_driver.index("let allSurfacesSubmitted =")
        barrier_discard_asset = frame_driver.index(
            "discardPreparedMaterialAssetFrame()", barrier
        )
        barrier_discard = frame_driver.index("discardPreparedFrameTexturePublication()", barrier)
        barrier_commit_asset = frame_driver.index(
            "commitPreparedMaterialAssetFrame()", barrier
        )
        barrier_commit = frame_driver.index("commitPreparedFrameTexturePublication()", barrier)
        frame_commit = frame_driver.index("commitSubmittedSceneFrame(", barrier)
        self.assertLess(barrier_discard_asset, barrier_discard)
        self.assertLess(barrier_commit_asset, barrier_commit)
        self.assertLess(barrier, barrier_discard)
        self.assertLess(barrier, barrier_commit)
        self.assertLess(barrier_commit, frame_commit)

    def test_animated_asset_cursor_waits_for_host_submission_barrier(self) -> None:
        catalog = ASSET_CATALOG.read_text(encoding="utf-8")
        bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        composition = GRAPH_COMPOSITION.read_text(encoding="utf-8")
        texture_frame = TEXTURE_FRAME.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        renderer = RENDERER.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER.read_text(encoding="utf-8")

        states = catalog.index("func states(sceneTime:")
        self.assertIn("if frameCursorBaseline != nil { commitFrame() }", catalog[states:])
        self.assertIn("frameCursorBaseline = cursors", catalog[states:])
        self.assertIn("func commitFrame()", catalog)
        discard = catalog.index("func discardFrame()")
        self.assertIn("cursors = frameCursorBaseline", catalog[discard:])
        self.assertIn("assetProvider.commitFrame()", bridge)
        self.assertIn("assetProvider.discardFrame()", bridge)
        self.assertIn("resolvedMaterialRuntime?.commitResolvedAssetFrame()", composition)
        self.assertIn("resolvedMaterialRuntime?.discardResolvedAssetFrame()", composition)

        self.assertIn("imageCompositor.commitResolvedMaterialAssetFrame()", texture_frame)
        self.assertIn("imageCompositor.discardResolvedMaterialAssetFrame()", texture_frame)
        helper = texture_frame.index("func discardUnsubmittedFrameResources()")
        self.assertLess(
            texture_frame.index("discardResolvedMaterialAssetFrame()", helper),
            texture_frame.index("discardFrameTexturePublication()", helper),
        )
        self.assertIn("renderer.commitResolvedMaterialAssetFrame()", view)
        self.assertIn("renderer.discardResolvedMaterialAssetFrame()", view)
        self.assertIn("discardUnsubmittedFrameResources()", renderer)

        barrier = frame_driver.index("let allSurfacesSubmitted =")
        discard_asset = frame_driver.index("discardPreparedMaterialAssetFrame()", barrier)
        discard_registry = frame_driver.index("discardPreparedFrameTexturePublication()", barrier)
        commit_asset = frame_driver.index("commitPreparedMaterialAssetFrame()", barrier)
        commit_registry = frame_driver.index("commitPreparedFrameTexturePublication()", barrier)
        self.assertLess(discard_asset, discard_registry)
        self.assertLess(commit_asset, commit_registry)

if __name__ == "__main__":
    unittest.main()
