"""Execute the product reducer; identities and event order are the assertions."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]

HARNESS = r'''
import Foundation
@main enum Harness {
    static func verifyWithdrawal(newUserSelection: Bool) {
        var state = PlaybackSwitchTransaction()
        let (a, _) = state.begin(.scene)
        let aid = UUID()
        let active = PlaybackSwitchTransaction.Selection(ticket: a, executionID: aid)
        _ = state.prepared(a, executionID: aid)
        _ = state.visible(a, executionID: aid)

        let (b, _) = state.begin(.scene)
        let bid = UUID()
        let candidate = PlaybackSwitchTransaction.Selection(ticket: b, executionID: bid)
        guard case let .output(off)? = state.prepared(b, executionID: bid).first else { fatalError() }
        precondition(state.activityCompleted(off, succeeded: true) == [.activate(candidate)])
        let wrongTicket = PlaybackSwitchTicket(epoch: b.epoch, id: UUID(), runtime: b.runtime)
        precondition(state.withdraw(a).isEmpty && state.withdraw(wrongTicket).isEmpty,
            "Only the exact pending ticket can be withdrawn")
        precondition(state.pending?.selection == candidate)

        let effects = state.withdraw(b)
        guard effects.count == 1, case let .cancel(barrier, withdrawn)? = effects.first else {
            fatalError("Withdrawal must emit only an exact cancellation")
        }
        precondition(withdrawn == candidate && state.committed == active && state.pending == nil)
        precondition(state.cancellations[barrier] == candidate && !state.committedOutputActive)
        precondition(state.withdraw(b).isEmpty)
        precondition(state.cancelled(UUID()).isEmpty)
        precondition(state.prepared(b, executionID: bid).isEmpty)
        precondition(state.visible(b, executionID: bid).isEmpty)
        precondition(state.failed(b, reason: "late failure").isEmpty)
        precondition(state.activity == nil, "Old output must wait for the exact cancellation acknowledgment")

        if newUserSelection {
            let (d, newerEffects) = state.begin(.web)
            let did = UUID()
            let newer = PlaybackSwitchTransaction.Selection(ticket: d, executionID: did)
            precondition(newerEffects.isEmpty && state.withdraw(b).isEmpty)
            precondition(state.prepared(d, executionID: did).isEmpty)
            precondition(state.visible(d, executionID: did).isEmpty)
            precondition(state.cancelled(barrier) == [.activate(newer)],
                "A prepared newer user selection must win when the old cancellation settles")
            let commit = state.visible(d, executionID: did)
            guard commit.first == .commit(newer, recovery: false),
                  case let .handoff(retirement, previous, replacement)? = commit.last else { fatalError() }
            precondition(previous == active && replacement == newer)
            precondition(state.retired(retirement) == [.finalize(newer)])
            precondition(state.committed == newer && state.pending == nil)
        } else {
            let restoration = state.cancelled(barrier)
            guard restoration.count == 1, case let .output(on)? = restoration.first else {
                fatalError("Acknowledged withdrawal must restore the committed output")
            }
            precondition(on.active && on.executionID == active.executionID)
            precondition(state.activityCompleted(on, succeeded: true).isEmpty)
            precondition(state.committedOutputActive && state.committed == active && state.pending == nil)
        }
        precondition(state.cancelled(barrier).isEmpty)
    }

    static func verifyWithdrawalBeforePreparation() {
        var state = PlaybackSwitchTransaction()
        let (a, _) = state.begin(.scene)
        let aid = UUID()
        let active = PlaybackSwitchTransaction.Selection(ticket: a, executionID: aid)
        _ = state.prepared(a, executionID: aid)
        _ = state.visible(a, executionID: aid)

        let (b, _) = state.begin(.scene)
        let effects = state.withdraw(b)
        guard effects.count == 1, case let .cancel(barrier, withdrawn)? = effects.first else {
            fatalError("A preparing ticket must be withdrawn before it has an execution")
        }
        precondition(withdrawn == .init(ticket: b) && state.pending == nil)
        precondition(state.cancelled(barrier).isEmpty, "An active incumbent needs no restoration")
        let bid = UUID()
        let late = state.prepared(b, executionID: bid)
        guard late.count == 1, case let .cancel(lateBarrier, endpoint)? = late.first else {
            fatalError("A late native endpoint must be canceled instead of admitted")
        }
        precondition(endpoint == .init(ticket: b, executionID: bid))
        precondition(state.cancelled(lateBarrier).isEmpty)
        precondition(state.committed == active && state.committedOutputActive && state.pending == nil)
    }

    static func verifyWithdrawalDuringDeactivation() {
        var state = PlaybackSwitchTransaction()
        let (a, _) = state.begin(.scene)
        let aid = UUID()
        _ = state.prepared(a, executionID: aid)
        _ = state.visible(a, executionID: aid)

        let (b, _) = state.begin(.scene)
        let bid = UUID()
        guard case let .output(off)? = state.prepared(b, executionID: bid).first,
              case let .cancel(barrier, withdrawn)? = state.withdraw(b).first else { fatalError() }
        precondition(withdrawn.ticket == b && withdrawn.executionID == bid)
        precondition(state.cancelled(barrier).isEmpty,
            "Cancellation acknowledgment cannot bypass the in-flight deactivation")
        let restoration = state.activityCompleted(off, succeeded: true)
        guard restoration.count == 1, case let .output(on)? = restoration.first else {
            fatalError("Late deactivation must restore A without activating the withdrawn candidate")
        }
        precondition(on.active && on.executionID == aid)
        precondition(state.activityCompleted(on, succeeded: true).isEmpty)
        precondition(state.committed == .init(ticket: a, executionID: aid) && state.pending == nil
            && state.committedOutputActive)
    }

    static func main() {
        verifyWithdrawal(newUserSelection: false)
        verifyWithdrawal(newUserSelection: true)
        verifyWithdrawalBeforePreparation()
        verifyWithdrawalDuringDeactivation()
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
