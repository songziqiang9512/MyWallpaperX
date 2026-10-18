"""Execute the product reducer; identities and event order are the assertions."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

HARNESS = r'''
import Foundation
@main enum Harness {
    static func main() {
        for source in [WallpaperRuntimeKind.video, .web, .scene] {
            for target in [WallpaperRuntimeKind.video, .web, .scene, .systemStill] {
                var state = PlaybackSwitchTransaction()
                let (a, _) = state.begin(source)
                let aid = UUID()
                precondition(state.prepared(a, executionID: aid) == [.activate(.init(ticket: a, executionID: aid))])
                _ = state.visible(a, executionID: aid)
                let (b, _) = state.begin(target)
                let bid = UUID()
                let effects = state.prepared(b, executionID: bid)
                guard case let .output(operation) = effects.first else { fatalError("no exclusive output barrier") }
                precondition(!operation.active && operation.executionID == aid)
                precondition(state.committed?.ticket == a)
                precondition(state.visible(b, executionID: bid).isEmpty, "visible before activation")
                let activation = state.activityCompleted(operation, succeeded: true)
                precondition(activation == [.activate(.init(ticket: b, executionID: bid))])
                let commit = state.visible(b, executionID: bid)
                precondition(commit.first == .commit(.init(ticket: b, executionID: bid), recovery: false))
                guard case let .handoff(retirement, previous, next) = commit.last else { fatalError("missing retirement barrier") }
                precondition(previous.ticket == a && next.ticket == b)
                precondition(state.retired(retirement) == [.finalize(.init(ticket: b, executionID: bid))])
                precondition(state.committed?.ticket == b && state.pending == nil)
                precondition(state.visible(b, executionID: bid).isEmpty)
                precondition(state.activityCompleted(operation, succeeded: true).isEmpty)
            }
        }
        // New intent is installed before cancellation; a delayed activation is
        // unable to commit, and C waits until B's exact cancellation ACK.
        var state = PlaybackSwitchTransaction()
        let (a, _) = state.begin(.video); let aid = UUID()
        _ = state.prepared(a, executionID: aid); _ = state.visible(a, executionID: aid)
        let (b, _) = state.begin(.web); let bid = UUID()
        guard case let .output(off) = state.prepared(b, executionID: bid).first else { fatalError() }
        _ = state.activityCompleted(off, succeeded: true)
        let (c, revoke) = state.begin(.scene); let cid = UUID()
        guard case let .cancel(barrier, old) = revoke.first else { fatalError() }
        precondition(old.ticket == b && old.executionID == bid)
        precondition(state.prepared(c, executionID: cid).isEmpty)
        precondition(state.visible(b, executionID: bid).isEmpty)
        precondition(state.failed(b, reason: "late error").isEmpty)
        precondition(state.cancelled(barrier) == [.activate(.init(ticket: c, executionID: cid))])
        precondition(state.cancelled(barrier).isEmpty)
        // Failure must stop the candidate before restoring old media/input.
        let failed = state.failed(c, reason: "presentation timed out")
        guard case let .cancel(cancelC, _) = failed.first else { fatalError() }
        precondition(state.committed?.ticket == a && state.pending == nil)
        guard case let .output(on) = state.cancelled(cancelC).first else { fatalError() }
        precondition(on.active && on.executionID == aid)
        _ = state.activityCompleted(on, succeeded: true)
        precondition(state.committedOutputActive)
        // A failed deactivation never activates B or retires A.
        let (d, _) = state.begin(.web); let did = UUID()
        guard case let .output(offD) = state.prepared(d, executionID: did).first else { fatalError() }
        let rejected = state.activityCompleted(offD, succeeded: false)
        precondition(!rejected.contains(.activate(.init(ticket: d, executionID: did))))
        precondition(state.committed?.ticket == a)
        for effect in rejected { if case let .cancel(key, _) = effect { _ = state.cancelled(key) } }
        // Same selection crash recovery uses a fresh execution, preserving the
        // selection ticket and never taking priority over a new user selection.
        let recoveryID = UUID()
        let recoveryEffects = state.prepared(a, executionID: recoveryID)
        guard case let .output(offR) = recoveryEffects.first else { fatalError("recovery must deactivate obsolete output") }
        _ = state.activityCompleted(offR, succeeded: true)
        let (e, cancelledRecovery) = state.begin(.web)
        precondition(state.prepared(e, executionID: UUID()).isEmpty)
        precondition(state.visible(a, executionID: recoveryID).isEmpty)
        precondition(cancelledRecovery.count == 1)
        // Stop invalidates all late completions and retires the exact committed
        // output while retaining cancellation barriers until their ACKs arrive.
        _ = state.stop()
        precondition(state.committed == nil && state.pending == nil)
        precondition(state.visible(e, executionID: UUID()).isEmpty)
        precondition(state.activityCompleted(offR, succeeded: true).isEmpty)
        // Preparing requests without a native endpoint are cancellable too.
        var pending = PlaybackSwitchTransaction()
        let (p, _) = pending.begin(.scene)
        let (q, cancellation) = pending.begin(.video)
        guard case let .cancel(key, selection) = cancellation.first else { fatalError() }
        precondition(selection.ticket == p && selection.executionID == nil)
        let qid = UUID()
        precondition(pending.prepared(q, executionID: qid).isEmpty)
        precondition(pending.cancelled(key) == [.activate(.init(ticket: q, executionID: qid))])
        var stopped = PlaybackSwitchTransaction()
        let (s, _) = stopped.begin(.web); let sid = UUID()
        _ = stopped.prepared(s, executionID: sid); _ = stopped.visible(s, executionID: sid)
        guard case let .retire(stopBarrier, _) = stopped.stop().first else { fatalError() }
        let (restart, _) = stopped.begin(.scene); let rid = UUID()
        precondition(stopped.prepared(restart, executionID: rid).isEmpty,
            "Stop then Play overlapped a still-retiring output")
        precondition(stopped.retired(stopBarrier) == [.activate(.init(ticket: restart, executionID: rid))])
        var loss = PlaybackSwitchTransaction()
        let (lostTicket, _) = loss.begin(.web); let lostID = UUID()
        _ = loss.prepared(lostTicket, executionID: lostID); _ = loss.visible(lostTicket, executionID: lostID)
        let (replacement, _) = loss.begin(.scene); let replacementID = UUID()
        let lossEffects = loss.lost(lostTicket, reason: "native recovery exhausted")
        precondition(loss.committed == nil && loss.pending?.selection.ticket == replacement)
        precondition(loss.prepared(replacement, executionID: replacementID).isEmpty)
        guard case let .retire(lossBarrier, _) = lossEffects.last else { fatalError() }
        precondition(loss.retired(lossBarrier) == [.activate(.init(ticket: replacement, executionID: replacementID))])
        precondition(loss.lost(lostTicket, reason: "duplicate terminal").isEmpty)
        var lateLoss = PlaybackSwitchTransaction()
        let (oldVisible, _) = lateLoss.begin(.web); let oldVisibleID = UUID()
        _ = lateLoss.prepared(oldVisible, executionID: oldVisibleID)
        _ = lateLoss.visible(oldVisible, executionID: oldVisibleID)
        let (incoming, _) = lateLoss.begin(.video); let incomingID = UUID()
        guard case let .output(deactivation) = lateLoss.prepared(incoming, executionID: incomingID).first else { fatalError() }
        _ = lateLoss.activityCompleted(deactivation, succeeded: true)
        let lostAfterActivation = lateLoss.lost(oldVisible, reason: "late terminal")
        guard case let .retire(retiringOld, _) = lostAfterActivation.last else { fatalError() }
        precondition(lateLoss.visible(incoming, executionID: incomingID).isEmpty,
            "incoming window lowered before the old window physically withdrew")
        precondition(lateLoss.committed == nil)
        precondition(lateLoss.retired(retiringOld) == [
            .commit(.init(ticket: incoming, executionID: incomingID), recovery: false),
            .finalize(.init(ticket: incoming, executionID: incomingID))],
            "one-shot visible proof was lost behind the retirement barrier")
        print("transaction behavior passed")
    }
}
'''

class PlaybackSwitchTransactionTests(unittest.TestCase):
    def test_reducer_behavior(self):
        with tempfile.TemporaryDirectory(prefix="mwx-switch-state-") as directory:
            folder = Path(directory)
            main = folder / "Harness.swift"
            main.write_text(HARNESS)
            executable = folder / "test"
            sources = ROOT / "MyWallpaperX/Core/PlaybackControl"
            subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                            str(sources / "WallpaperRuntimeSwitch.swift"),
                            str(sources / "PlaybackSwitchTransaction.swift"), str(main),
                            "-o", str(executable)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("transaction behavior passed", result.stdout)
