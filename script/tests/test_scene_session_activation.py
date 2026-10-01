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
final class SceneFirstFramePresentationRegistration {}
enum SceneDesktopWallpaperHostLaunchError: Error { case firstFrameFailed, firstFrameTimeout }
final class SceneScriptLocalStorageSession {
    func retirePersistence() {}
    func activatePersistence(replacing: SceneScriptLocalStorageSession?) {}
}
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
    var audioDemand = (spectrum:false,currentProcess:false)
    var visible = false
    var stopped = false
    var drains: [@MainActor (Bool)->Void] = []
    init(textureDecodeCacheBudget: SceneTextureDecodeCacheBudget) {}
    func activate(_ context: SceneDesktopWallpaperLaunchContext) throws { launchContext=context }
    func promote(firstPresentation: SceneFirstFramePresentationRegistration?) { visible=true }
    func stopAndDrainGPU(completion: @escaping @MainActor (Bool)->Void) { stopped=true;visible=false;drains.append(completion) }
    @MainActor func finishDrain() { let pending=drains;drains=[];pending.forEach{$0(true)} }
}
@MainActor final class SceneDesktopWallpaperHost {
    let textureDecodeCacheBudget=SceneTextureDecodeCacheBudget()
    var activeSession: SceneDesktopWallpaperSession?
    var candidateSession: SceneDesktopWallpaperSession?
    var retiringSessions:[ObjectIdentifier:SceneDesktopWallpaperSession]=[:]
    var candidateDeadline:DispatchWorkItem?
    var candidateCompletion:((Result<Void,Error>)->Void)?
    func configure(_ session:SceneDesktopWallpaperSession) {}
    func stop() { discardCandidate();if let activeSession {self.activeSession=nil;retire(activeSession)} }
}
@main enum Harness {
    @MainActor static func main() throws {
        let host=SceneDesktopWallpaperHost()
        var outcomes:[Bool]=[]
        func begin() throws -> SceneDesktopWallpaperSession {
            try host.beginCandidate(.init(),firstPresentation:.init()) { result in
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
        var drained=false
        host.stopAndDrainGPU {drained=$0}
        result["stopWaitsForGPU"] = !drained && !c.visible && host.activeSession == nil
        c.finishDrain()
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
