"""Execute the production candidate/active transition owner with controlled GPU terminals."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift'
LAUNCH_MODELS = SOURCE.with_name('SceneDesktopWallpaperLaunchModels.swift')
HARNESS = r'''
import AppKit
import Foundation
final class SceneTextureDecodeCacheBudget {}
final class SceneFirstFramePresentationRegistration { let requestID=UUID() }
final class SceneScriptLocalStorageSession {
    func retirePersistence() {}
    func activatePersistence(replacing: SceneScriptLocalStorageSession?) {}
}
final class SoundRegistry {func setMuted(_ muted:Bool) {}}
struct SceneDesktopWallpaperLaunchContext { let sceneScriptStorageSession: SceneScriptLocalStorageSession? = nil }
final class SceneAudioSpectrumInbox {
    static let shared = SceneAudioSpectrumInbox()
    var demand = false
    var includesCurrentProcess = false
    func setDemand(_ demand: Bool, requiresCurrentProcessAudioCapture: Bool) {
        self.demand = demand
        includesCurrentProcess = demand && requiresCurrentProcessAudioCapture
    }
}
final class SceneDesktopWallpaperSession {
    let lifecycleID=UUID()
    var surfaces: [CGDirectDisplayID: Int] = [1:1, 2:2]
    var onFirstFrameCompletion: ((CGDirectDisplayID, Bool)->Void)?
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var soundPlaybackRegistry:SoundRegistry?
    var launchRequestID:UUID?
    var activeRecordID:String? { nil }
    var audioDemand = (spectrum:false,currentProcess:false)
    var isOutputActive = true
    var visible = false
    var paused = false
    var stopped = false
    var drains: [@MainActor (Bool)->Void] = []
    var drainResult:Bool?
    init(textureDecodeCacheBudget: SceneTextureDecodeCacheBudget) {}
    func activate(_ context: SceneDesktopWallpaperLaunchContext) throws { launchContext=context }
    func promote(firstPresentation: SceneFirstFramePresentationRegistration?) { visible=true }
    func suspendPresentationForHandoff() { visible=false }
    @MainActor func stopAndDrainGPU(completion: @escaping @MainActor (Bool)->Void) {
        stopped=true;visible=false
        if let drainResult {completion(drainResult)} else {drains.append(completion)}
    }
    @MainActor func finishDrain(_ success:Bool = true) {
        guard drainResult == nil else {return}
        drainResult=success;let pending=drains;drains=[];pending.forEach{$0(success)}
    }
}
@MainActor final class SceneDesktopWallpaperHost {
    let textureDecodeCacheBudget=SceneTextureDecodeCacheBudget()
    var activeSession: SceneDesktopWallpaperSession?
    var candidateSession: SceneDesktopWallpaperSession?
    var retiringSessions:[ObjectIdentifier:SceneDesktopWallpaperSession]=[:]
    var candidateDeadline:DispatchWorkItem?
    var presentationDeadline:DispatchWorkItem?
    var candidateCompletion:((Result<Void,Error>)->Void)?
    let launchPreparationQueue=DispatchQueue(label:"test-preparation")
    var candidatePreparedHandler:((UUID)->Void)?
    var requestResourcesReleasedHandler:((UUID,Bool)->Void)?
    var launchCancellation:Bool?
    var pendingLaunchCompletion:(()->Void)?
    var candidatePromotion:(requestID:UUID,promote:()->Void)?
    var unconfirmedPromotion:(requestID:UUID,previous:SceneDesktopWallpaperSession?)?
    var launchState:SceneWallpaperLaunchState?
    func cancelPendingLaunch() { discardCandidate() }
    var paused=false
    func configure(_ session:SceneDesktopWallpaperSession) {session.paused=paused}
    func stop() { discardCandidate();if let activeSession {self.activeSession=nil;retire(activeSession)} }
}
@main enum Harness {
    @MainActor static func main() async throws {
        let host=SceneDesktopWallpaperHost()
        var outcomes:[Bool]=[]
        func begin() throws -> SceneDesktopWallpaperSession {
            let presentation=SceneFirstFramePresentationRegistration()
            host.launchState = .init(requestID:presentation.requestID,recordID:nil,phase:.preparingModel,message:"")
            try host.beginCandidate(.init(),firstPresentation:presentation) { result in
                if case .success=result {outcomes.append(true)} else {outcomes.append(false)}
            }
            return host.candidateSession!
        }
        let a=try begin()
        a.onFirstFrameCompletion?(1,true)
        var result:[String:Bool]=[:]
        result["allRequiredScreensGatePromotion"] = host.activeSession == nil && !a.visible
        a.onFirstFrameCompletion?(2,true)
        result["firstCandidatePromoted"] = host.activeSession === a && a.visible && outcomes == [true]
        a.audioDemand = (true, false)
        let b=try begin()
        b.audioDemand = (false, true)
        host.reconcileAudioDemand()
        result["candidateDoesNotRevokeActiveAudio"] = SceneAudioSpectrumInbox.shared.demand

        let lateB=b.onFirstFrameCompletion!
        result["oldVisibleDuringCandidate"] = host.activeSession === a && a.visible && !b.visible
        b.onFirstFrameCompletion?(1,false)
        result["failedCandidateLeavesActiveAudio"] = SceneAudioSpectrumInbox.shared.demand
        result["gpuFailureRetainsActive"] = host.activeSession === a && a.visible && !a.stopped && b.stopped
        result["failedCandidateRetainedUntilDrain"] = host.retiringSessions[ObjectIdentifier(b)] === b
        b.finishDrain()
        result["failedCandidateReleasedAfterDrain"] = host.retiringSessions[ObjectIdentifier(b)] == nil
        let c=try begin()
        lateB(2,true)
        result["staleCompletionCannotPromote"] = host.candidateSession === c && host.activeSession === a
        c.onFirstFrameCompletion?(1,true);c.onFirstFrameCompletion?(2,true)
        result["replacementPromotesBeforeOldRetires"] = host.activeSession === c && c.visible && a.stopped && outcomes == [true,false,true]
        result["oldSessionRetainedUntilDrain"] = host.retiringSessions[ObjectIdentifier(a)] === a
        a.finishDrain()
        let timeout=try begin()
        host.candidateDeadline?.perform()
        result["timeoutRetainsCurrent"] = host.activeSession === c && c.visible && timeout.stopped && outcomes.last == false
        timeout.finishDrain()
        let cancelled=try begin();let late=cancelled.onFirstFrameCompletion!
        host.discardCandidate();late(1,true);late(2,true)
        result["cancelCannotLaterReplaceCurrent"] = host.activeSession === c && c.visible && cancelled.stopped
        cancelled.finishDrain()
        var admitted:[UUID]=[]
        var released:[UUID]=[]
        host.candidatePreparedHandler={admitted.append($0)}
        host.requestResourcesReleasedHandler={if $1 {released.append($0)}}
        let revoked=try begin()
        revoked.onFirstFrameCompletion?(1,true);revoked.onFirstFrameCompletion?(2,true)
        let revokedID=revoked.launchRequestID!
        result["GPUReadyWaitsForParentAdmission"] = admitted == [revokedID] && host.activeSession === c && !revoked.visible
        host.commitCandidate(requestID:UUID())
        result["WrongRequestCannotCommit"] = host.activeSession === c && !revoked.visible
        host.cancelCandidate(requestID:revokedID)
        host.commitCandidate(requestID:revokedID)
        result["RevokedAdmissionCannotPromote"] = host.activeSession === c && c.visible && revoked.stopped
        result["RevokedLeaseWaitsForGPUDrain"] = !released.contains(revokedID)
        revoked.finishDrain()
        result["RevokedLeaseReleasedAfterGPUDrain"] = released.contains(revokedID)
        let rollback=try begin()
        rollback.onFirstFrameCompletion?(1,true);rollback.onFirstFrameCompletion?(2,true)
        let rollbackID=rollback.launchRequestID!
        host.commitCandidate(requestID:rollbackID)
        result["CommitKeepsRollbackStandby"] = host.activeSession === rollback && rollback.visible && !c.visible && !c.stopped
        host.paused=true
        host.cancelCandidate(requestID:rollbackID)
        host.finalizeCandidate(requestID:rollbackID)
        result["SupersedeAfterCommitRestoresPrevious"] = host.activeSession === c && c.visible && !c.stopped && rollback.stopped
        result["RollbackReplaysCurrentPausePolicy"] = c.paused
        rollback.finishDrain()
        let unpresented=try begin()
        unpresented.onFirstFrameCompletion?(1,true);unpresented.onFirstFrameCompletion?(2,true)
        let unpresentedID=unpresented.launchRequestID!
        host.commitCandidate(requestID:unpresentedID)
        let lateDeadline=host.presentationDeadline!
        host.noteCandidatePresentation(requestID:UUID())
        result["WrongPresentationCannotCancelDeadline"] = host.presentationDeadline != nil
        lateDeadline.perform()
        result["PresentationTimeoutRestoresPrevious"] = host.activeSession === c && c.visible
            && unpresented.stopped && host.launchState?.phase == .failed
            && host.launchState?.requestID == unpresentedID && host.presentationDeadline == nil
        unpresented.finishDrain()
        let confirmed=try begin()
        confirmed.onFirstFrameCompletion?(1,true);confirmed.onFirstFrameCompletion?(2,true)
        let confirmedID=confirmed.launchRequestID!
        host.commitCandidate(requestID:confirmedID)
        let observedDeadline=host.presentationDeadline!
        host.noteCandidatePresentation(requestID:unpresentedID)
        lateDeadline.perform()
        result["LatePresentationCannotTouchReplacement"] = host.activeSession === confirmed
            && host.presentationDeadline != nil
        host.noteCandidatePresentation(requestID:confirmedID)
        observedDeadline.perform()
        result["PresentedCandidateWaitsForParentWithoutTimeout"] = host.activeSession === confirmed
            && !c.stopped && host.presentationDeadline == nil
        host.finalizeCandidate(requestID:UUID())
        result["WrongFinalizeKeepsStandby"] = !c.stopped
        host.finalizeCandidate(requestID:confirmedID)
        host.cancelCandidate(requestID:confirmedID)
        result["ConfirmedPresentationRetiresOnlyPrevious"] = host.activeSession === confirmed && confirmed.visible && c.stopped
        c.finishDrain()
        var drained=false
        host.stopAndDrainGPU {drained=$0}
        result["stopWaitsForGPU"] = !drained && !confirmed.visible && host.activeSession == nil
        confirmed.finishDrain()
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            host.launchPreparationQueue.async {DispatchQueue.main.async {continuation.resume()}}
        }
        result["stopFinishesAfterGPU"] = drained && host.retiringSessions.isEmpty

        // A separate Host keeps this delayed-parent case independent of the
        // preceding handoff outcomes. These are controlled terminal callbacks,
        // not a real command-buffer failure or a second rendering harness.
        do {
            let delayedHost=SceneDesktopWallpaperHost()
            let previous=SceneDesktopWallpaperSession(textureDecodeCacheBudget:delayedHost.textureDecodeCacheBudget)
            previous.visible=true
            delayedHost.activeSession=previous
            var delayedOutcomes:[Bool]=[]
            var prepared:[UUID]=[]
            var delayedReleased:[UUID]=[]
            delayedHost.candidatePreparedHandler={prepared.append($0)}
            delayedHost.requestResourcesReleasedHandler={if $1 {delayedReleased.append($0)}}
            let presentation=SceneFirstFramePresentationRegistration()
            let requestID=presentation.requestID
            delayedHost.launchState = .init(requestID:requestID,recordID:nil,phase:.preparingModel,message:"")
            try delayedHost.beginCandidate(.init(),firstPresentation:presentation) { outcome in
                if case .success=outcome {delayedOutcomes.append(true)} else {delayedOutcomes.append(false)}
            }
            let candidate=delayedHost.candidateSession!
            let staleSuccess=candidate.onFirstFrameCompletion!
            // A previously submitted GPU terminal forwards through the Session's
            // current callback, as production does when that terminal arrives.
            let oldSubmittedFailure={ candidate.onFirstFrameCompletion?(1,false) }
            candidate.onFirstFrameCompletion?(1,true)
            candidate.onFirstFrameCompletion?(2,true)
            let oldPromotion=delayedHost.candidatePromotion?.promote
            result["DelayedParentHasPreparedCandidateWithoutPromotion"] = prepared == [requestID]
                && delayedHost.candidateSession === candidate && delayedHost.activeSession === previous
                && previous.visible && !candidate.visible && delayedOutcomes.isEmpty && oldPromotion != nil
            result["DelayedParentStillObservesGPUFailure"] = candidate.onFirstFrameCompletion != nil
            candidate.onFirstFrameCompletion?(1,true)
            candidate.onFirstFrameCompletion?(2,true)
            result["RepeatedSuccessDoesNotRepeatParentPreparedHandler"] = prepared == [requestID]
                && delayedOutcomes.isEmpty && delayedHost.candidateSession === candidate
            oldSubmittedFailure()
            result["LateGPUFailureCancelsPreparedCandidate"] = delayedHost.candidateSession == nil
                && candidate.stopped && !candidate.visible && delayedOutcomes == [false]
                && delayedHost.candidatePromotion == nil && delayedHost.candidateDeadline == nil
            result["LateGPUFailureKeepsPreviousActive"] = delayedHost.activeSession === previous
                && previous.visible && !previous.stopped && delayedHost.unconfirmedPromotion == nil
            result["LateGPUFailureRetainsCandidateUntilDrain"] = delayedReleased.isEmpty
                && delayedHost.retiringSessions[ObjectIdentifier(candidate)] === candidate
            staleSuccess(2,true)
            oldPromotion?()
            delayedHost.commitCandidate(requestID:requestID)
            delayedHost.finalizeCandidate(requestID:requestID)
            result["FailedPreparedCandidateCannotPromoteFromStaleParentCommit"] = delayedHost.activeSession === previous
                && previous.visible && !previous.stopped && !candidate.visible
                && delayedHost.candidateSession == nil && delayedHost.unconfirmedPromotion == nil
                && delayedOutcomes == [false] && prepared == [requestID]
            candidate.finishDrain()
            candidate.finishDrain()
            result["LateGPUFailureReleasesOnlyAfterSingleDrain"] = delayedReleased == [requestID]
                && delayedHost.retiringSessions[ObjectIdentifier(candidate)] == nil
            delayedHost.stop()
            previous.finishDrain()
        }
        // A normal exit can have a cancelled preparation and no Session yet.
        // Hold the actual Host queue and observe main-loop progress before release.
        let preparingHost=SceneDesktopWallpaperHost()
        let preparationEntered=DispatchSemaphore(value:0),allowPreparation=DispatchSemaphore(value:0)
        preparingHost.launchPreparationQueue.async {preparationEntered.signal();allowPreparation.wait()}
        precondition(preparationEntered.wait(timeout:.now()+5) == .success)
        var queueDrained=false
        preparingHost.stopAndDrainGPU {_ in queueDrained=true}
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in DispatchQueue.main.async {c.resume()}}
        result["NoSessionStopDoesNotReleaseBlockedPreparation"] = !queueDrained
        allowPreparation.signal()
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in
            preparingHost.launchPreparationQueue.async {DispatchQueue.main.async {c.resume()}}
        }
        result["NoSessionStopFinishesAfterPreparation"] = queueDrained
        let failedHost=SceneDesktopWallpaperHost()
        let failedSession=SceneDesktopWallpaperSession(textureDecodeCacheBudget:failedHost.textureDecodeCacheBudget)
        failedHost.activeSession=failedSession
        var failedResult:Bool?
        failedHost.stopAndDrainGPU {failedResult=$0}
        failedSession.finishDrain(false)
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in
            failedHost.launchPreparationQueue.async {DispatchQueue.main.async {c.resume()}}
        }
        result["PreparationFenceDoesNotHideGPUFailure"] = failedResult == false
        let retirementHost=SceneDesktopWallpaperHost()
        let retiredID=UUID()
        let retired=SceneDesktopWallpaperSession(textureDecodeCacheBudget:retirementHost.textureDecodeCacheBudget)
        retired.launchRequestID=retiredID;retirementHost.activeSession=retired
        let workerEntered=DispatchSemaphore(value:0),workerRelease=DispatchSemaphore(value:0)
        retirementHost.launchPreparationQueue.async {workerEntered.signal();workerRelease.wait()}
        precondition(workerEntered.wait(timeout:.now()+5) == .success)
        let known=retirementHost.hasRequestOutput(requestID:retiredID)
        let withdrew=retirementHost.retireOutput(requestID:retiredID)
        var releasedResult:Bool?
        retirementHost.whenRequestResourcesReleased(requestID:retiredID) {releasedResult=$0}
        retired.finishDrain()
        result["KnownRequestRetirementStillWaitsForPreparationFence"] = known && withdrew && releasedResult == nil
        workerRelease.signal()
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in
            retirementHost.launchPreparationQueue.async {DispatchQueue.main.async {c.resume()}}
        }
        result["KnownRequestRetirementQualifiesOnlyAfterActualOwnersEnd"] = releasedResult == true
            && retirementHost.isEmptyForRequestRetirement
        result["UnknownRequestCannotCertifyRetirementFromAbsence"] =
            !retirementHost.hasRequestOutput(requestID:UUID()) && retirementHost.isEmptyForRequestRetirement
        let failedRetirementHost=SceneDesktopWallpaperHost()
        let failedID=UUID(),failedRetirement=SceneDesktopWallpaperSession(textureDecodeCacheBudget:failedRetirementHost.textureDecodeCacheBudget)
        failedRetirement.launchRequestID=failedID;failedRetirementHost.activeSession=failedRetirement
        var terminalResults:[Bool]=[]
        failedRetirementHost.requestResourcesReleasedHandler={_,succeeded in terminalResults.append(succeeded)}
        _=failedRetirementHost.retireOutput(requestID:failedID)
        failedRetirement.finishDrain(false)
        var truthfulFailure:Bool?
        failedRetirementHost.whenRequestResourcesReleased(requestID:failedID) {truthfulFailure=$0}
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in
            failedRetirementHost.launchPreparationQueue.async {DispatchQueue.main.async {c.resume()}}
        }
        result["FailedRetirementKeepsSessionAndReportsFalse"] = terminalResults == [false]
            && truthfulFailure == false && !failedRetirementHost.isEmptyForRequestRetirement
            && failedRetirementHost.retiringSessions[ObjectIdentifier(failedRetirement)] === failedRetirement
        let occupied=SceneDesktopWallpaperSession(textureDecodeCacheBudget:retirementHost.textureDecodeCacheBudget)
        occupied.launchRequestID=UUID();retirementHost.activeSession=occupied
        result["NewOwnerPreventsEmptyCertificateWithoutStoppingIt"] =
            !retirementHost.isEmptyForRequestRetirement && !occupied.stopped
        retirementHost.unconfirmedPromotion=(UUID(),occupied);retirementHost.activeSession=nil
        var standbyResult:Bool?
        retirementHost.whenRequestResourcesReleased(requestID:occupied.launchRequestID!) {standbyResult=$0}
        await withCheckedContinuation {(c:CheckedContinuation<Void,Never>) in
            retirementHost.launchPreparationQueue.async {DispatchQueue.main.async {c.resume()}}
        }
        result["RollbackStandbyCannotReleaseItsRequest"] = standbyResult == false
            && !retirementHost.isEmptyForRequestRetirement && !occupied.stopped
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class SceneSessionActivationTests(unittest.TestCase):
    def test_candidate_failures_completion_order_and_drain(self):
        with tempfile.TemporaryDirectory(prefix='mwx-session-activation-') as temp:
            root=Path(temp); main=root/'main.swift'; main.write_text(HARNESS)
            binary=root/'test'
            compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',str(main),str(SOURCE),str(LAUNCH_MODELS),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=json.loads(subprocess.check_output([str(binary)],text=True))
            for name,passed in result.items():
                with self.subTest(name=name): self.assertTrue(passed)
