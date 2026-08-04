#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RENDERER = SCENE / "Rendering/SceneMetalRenderer.swift"
COMPOSITOR = SCENE / "Rendering/SceneImageLayerCompositor.swift"
LEGACY_COMPOSITOR = SCENE / "Rendering/SceneImageLayerCompositor+LegacyAuthored.swift"
LEGACY_BATCH = SCENE / "Rendering/SceneMetalRenderer+LegacyAuthoredBatch.swift"
TRANSACTION = SCENE / "Rendering/SceneSourceUpdateTransaction.swift"
EFFECT_EXECUTION = SCENE / "Rendering/SceneMetalRenderer+EffectExecution.swift"
UTILITY_PLAN = SCENE / "Rendering/SceneUtilityPlanFrameRenderer.swift"
UTILITY_LAYER = SCENE / "Rendering/SceneUtilityLayerRenderer.swift"
VIEW = SCENE / "Rendering/SceneMetalView.swift"
PUPPET = SCENE / "Rendering/ScenePuppetPlaybackState.swift"
SPRITE = SCENE / "Resources/SceneMultiImageSpritePlayback.swift"
MEDIA = SCENE / "Rendering/SceneMediaThumbnailTransitionRenderer.swift"


class SceneSourceUpdateTransactionTests(unittest.TestCase):
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
            "defer { sourceUpdateTransaction.cancel() }", transaction
        )
        source_updates = source.index(
            "encodeSourceUpdates?(commandBuffer, sourceUpdateTransaction)",
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
        self.assertIn("frameTransaction: sourceUpdateTransaction", source)
        claimed_failure_stop = source.index(
            "request.resolvedMaterialFrameTargetPlan != nil"
        )
        self.assertGreater(claimed_failure_stop, source.index("let encoded ="))
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
        compositor += LEGACY_COMPOSITOR.read_text(encoding="utf-8")
        self.assertIn(
            "frameTransaction: SceneSourceUpdateTransaction",
            compositor,
        )
        self.assertNotIn("frameTransaction.registerResolution(", compositor)
        self.assertNotIn(
            "commandBuffer.addCompletedHandler { _ in commit.releaseAll() }",
            compositor,
        )
        legacy_batch = LEGACY_BATCH.read_text(encoding="utf-8")
        self.assertEqual(legacy_batch.count("transaction.registerResolution("), 1)
        self.assertIn("prepareAndRegisterLegacyAuthoredBatch(", source)
        for path in (EFFECT_EXECUTION, UTILITY_PLAN, UTILITY_LAYER):
            utility_source = path.read_text(encoding="utf-8")
            self.assertIn("frameTransaction: SceneSourceUpdateTransaction", utility_source)
            self.assertIn("frameTransaction: frameTransaction", utility_source)

    def test_every_mutating_source_producer_registers_exact_rollback(self) -> None:
        view = VIEW.read_text(encoding="utf-8")
        puppet = PUPPET.read_text(encoding="utf-8")
        sprite = SPRITE.read_text(encoding="utf-8")
        media = MEDIA.read_text(encoding="utf-8")

        source_closure = view.split("encodeSourceUpdates:", maxsplit=1)[1]
        source_closure = source_closure.split(
            "encodeLayerSourceUpdates:", maxsplit=1
        )[0]
        media_closure = view.split("encodeLayerSourceUpdates:", maxsplit=1)[1]
        media_closure = media_closure.split("encodeFrameReadback:", maxsplit=1)[0]
        self.assertEqual(source_closure.count("transaction: transaction"), 2)
        self.assertEqual(media_closure.count("transaction: transaction"), 1)

        self.assertIn("SceneSourceUpdateStateFIFO(", puppet)
        self.assertIn("submissions.update(transaction: transaction)", puppet)
        self.assertIn(
            "guard signature != submission.frameSignature else { return }",
            puppet,
        )
        self.assertIn("submission.frameSignature = signature", puppet)

        sprite_encode = sprite.index("conversion.encode(")
        sprite_rollback = sprite.index("transaction.registerRollback", sprite_encode)
        completion = sprite.index("commandBuffer.addCompletedHandler", sprite_rollback)
        self.assertIn("submissionTracker.cancel(submission)", sprite[sprite_rollback:completion])
        self.assertIn("if latest?.id == token.id", sprite)

        self.assertIn("SceneSourceUpdateStateFIFO<[Int: PlaybackState]>", media)
        self.assertIn("submissions.update(transaction: transaction)", media)
        self.assertIn("states: inout [Int: PlaybackState]", media)
        self.assertIn("lastIssuedPublicationGenerations", media)
        self.assertIn("< UInt64.max", media)
        self.assertNotIn("publicationGeneration &+=", media)


if __name__ == "__main__":
    unittest.main()
