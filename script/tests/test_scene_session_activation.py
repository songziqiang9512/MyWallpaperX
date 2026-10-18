"""Execute the production candidate/active transition owner with controlled GPU terminals."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift'
HARNESS = r'''
import AppKit
import Foundation
final class SceneTextureDecodeCacheBudget {}
final class SceneFirstFramePresentationRegistration { let requestID=UUID() }
enum SceneDesktopWallpaperHostLaunchError: Error { case firstFrameFailed, firstFrameTimeout }
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
    init(textureDecodeCacheBudget: SceneTextureDecodeCacheBudget) {}
    func activate(_ context: SceneDesktopWallpaperLaunchContext) throws { launchContext=context }
    func promote(firstPresentation: SceneFirstFramePresentationRegistration?) { visible=true }
    func suspendPresentationForHandoff() { visible=false }
    func stopAndDrainGPU(completion: @escaping @MainActor (Bool)->Void) { stopped=true;visible=false;drains.append(completion) }
    @MainActor func finishDrain() { let pending=drains;drains=[];pending.forEach{$0(true)} }
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
    var requestResourcesReleasedHandler:((UUID)->Void)?
    var candidatePromotion:(requestID:UUID,promote:()->Void)?
    var unconfirmedPromotion:(requestID:UUID,previous:SceneDesktopWallpaperSession?)?
    enum Phase { case preparing, cancelled, failed }
    struct State { let requestID:UUID;let recordID:String?;let phase:Phase;let message:String }
    var launchState:State?
    func publishLaunchState(_ state:State) { launchState=state }
    func cancelPendingLaunch() { discardCandidate() }
    var paused=false
    func configure(_ session:SceneDesktopWallpaperSession) {session.paused=paused}
    func stop() { discardCandidate();if let activeSession {self.activeSession=nil;retire(activeSession)} }
}
@main enum Harness {
    @MainActor static func main() throws {
        let host=SceneDesktopWallpaperHost()
        var outcomes:[Bool]=[]
        func begin() throws -> SceneDesktopWallpaperSession {
            let presentation=SceneFirstFramePresentationRegistration()
            host.launchState = .init(requestID:presentation.requestID,recordID:nil,phase:.preparing,message:"")
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
        host.requestResourcesReleasedHandler={released.append($0)}
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
        result["stopFinishesAfterGPU"] = drained && host.retiringSessions.isEmpty
        print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''

class SceneSessionActivationTests(unittest.TestCase):
    def test_candidate_failures_completion_order_and_drain(self):
        with tempfile.TemporaryDirectory(prefix='mwx-session-activation-') as temp:
            root=Path(temp); main=root/'main.swift'; main.write_text(HARNESS)
            binary=root/'test'
            compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',str(main),str(SOURCE),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=json.loads(subprocess.check_output([str(binary)],text=True))
            for name,passed in result.items():
                with self.subTest(name=name): self.assertTrue(passed)
