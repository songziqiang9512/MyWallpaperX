#!/usr/bin/env python3
"""Run current product transaction, timer, termination and deferred EOF owners."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from script.tests.test_steam_library_interactions import method

REPO_ROOT = Path(__file__).resolve().parents[2]
CONTROL = REPO_ROOT / "MyWallpaperX/Core/PlaybackControl"
MANAGER = REPO_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core"
GATE_SOURCES = [CONTROL / name for name in (
    "PlaybackResourceLifetime.swift", "ImportedVideoAutoplayGate.swift", "WallpaperRuntimeSwitch.swift",
)]

# Storage, persistence, native endpoint actions and process IPC are leaves.
# Selection, commit, failure, timer policy and EOF delivery are production code.
SUPPORT = r'''
import Foundation
import Combine
@MainActor enum Trace {static var values:[String]=[]}
struct VideoWallpaper {let path:String}
@MainActor final class PlaybackCommandMultiplexer {
    static let shared=PlaybackCommandMultiplexer();var isPlaybackPaused=false
}
@MainActor final class WebDaemonHostAdapter {var hasPendingRequest=false}
@MainActor final class SceneDaemonClient {
    static let shared=SceneDaemonClient()
    func cancelSwitch(ticket:PlaybackSwitchTicket,completion:@escaping()->Void){completion()}
}
@MainActor final class WallpaperEngine {
    static let shared=WallpaperEngine()
    static let playbackFailedNotification=Notification.Name("failed")
    static let playbackEndedNotification=Notification.Name("ended")
    static let playbackReadyNotification=Notification.Name("legacy-ready")
    enum Kind {case video,web}
    struct Active {let id=UUID();let path:String}
    struct Execution {let id:UUID;let ticket:PlaybackSwitchTicket}
    var activeVideoPlayback:Active?
    var activeVideoExecution:Execution?
    var videoEndState:(playbackID:UUID,delivered:Bool)?
    var videoEndDeliveryAdmission:(()->Bool)?
    var currentPlaybackContentKind:Kind = .video
    var currentContentPath:String?
    var videoCandidate:Int?
    let dedicatedWebHostAdapter:Any=WebDaemonHostAdapter()
    var lastPreparedVideoTicket:PlaybackSwitchTicket?
    var videoPreparations=0
    var epoch:UInt64=0,cleanups=0
    var cancellation:((PlaybackSwitchTicket)->Void)?
    func prepareVideoSwitch(_ wallpaper:VideoWallpaper,ticket:PlaybackSwitchTicket,
        multiDisplayEnabled:Bool,videoFillMode:String,shouldLoopCurrentItem:Bool) {
        lastPreparedVideoTicket=ticket;videoPreparations += 1
    }
    func cancelSwitch(ticket:PlaybackSwitchTicket,completion:@escaping()->Void) {
        Trace.values.append("cancelEndpoint");cancellation?(ticket);completion()
    }
    func adoptIntentEpoch(_ value:UInt64){epoch=value;Trace.values.append("adopt")}
    func cleanup(){cleanups += 1;Trace.values.append("cleanup")}
    // ENGINE_METHOD
}
extension Notification.Name {static let wallpaperSwitchDidFail=Self("switch-failed")}
@MainActor final class WallpaperManager {
    static let shared=WallpaperManager()
    let objectWillChange=ObservableObjectPublisher()
    var playbackIntentDidAdvance:((WallpaperRuntimeKind?)->Void)?
    init() { WallpaperEngine.shared.videoEndDeliveryAdmission = { [weak self] in self?.admitsDeferredVideoEnd() ?? false } }
    // SELECTION
    struct Settings {
        enum Unit {case seconds;var secondsValue:Int{1}}
        enum Fill {case fill;var ipcValue:String{"fill"}}
        var autoSwitchEnabled=true,randomInterval=3600,syncSystemWallpaper=false,multiDisplayEnabled=true
        var timeUnit=Unit.seconds,videoFillMode=Fill.fill
    }
    var settings=Settings()
    var playbackSwitch=PlaybackSwitchTransaction()
    var switchEndpoints:[UUID:PlaybackSwitchEndpoint]=[:]
    var switchSelections:[UUID:RuntimeSwitchSelection]=[:]
    var switchDeadline:DispatchWorkItem?,pendingSystemWallpaperSyncWorkItem:DispatchWorkItem?
    var switchEffectQueue:[PlaybackSwitchTransaction.Effect]=[]
    var drainingSwitchEffects=false
    var playbackIntentEpoch:UInt64{playbackSwitch.epoch}
    var requestedRuntime:WallpaperRuntimeKind?{playbackSwitch.requestedRuntime}
    var pendingWallpaper:VideoWallpaper?,currentWallpaper:VideoWallpaper?
    var effectiveCurrentWallpaper:VideoWallpaper?{pendingWallpaper ?? currentWallpaper}
    var activeWallpaperRuntime=WallpaperRuntimeKind.video
    var lastWorkshopPlaybackRecordID:String?
    var isPlaying=false
    var wallpapers=[VideoWallpaper(path:"/old-video"),VideoWallpaper(path:"/new-video")]
    var autoSwitchTimer:Timer?
    var timerFires=0,snapshots=0
    var endedPaths:[String]=[],failedPaths:[String]=[]
    var onFlush:(()->Void)?,onPersist:(()->Void)?
    func isSwitchingPlaybackMode()->Bool{true}
    func shouldLoopCurrentItemInEngine()->Bool{true}
    func normalizedPath(_ path:String)->String{path}
    func timerDidFire(){timerFires += 1}
    func persistCurrentWallpaperSnapshot(){snapshots += 1;onPersist?()}
    func syncSystemWallpaper(with wallpaper:VideoWallpaper){}
    func scheduleRuntimeFrameSystemWallpaperSync(kind:WallpaperRuntimeKind,recordID:String){}
    func handlePlaybackEnded(forPath path:String){endedPaths.append(path)}
    func handlePlaybackFailure(forPath path:String){failedPaths.append(path)}
    func flushPersistentState(){onFlush?();Trace.values.append("flush")}
    // MANAGER_METHODS
}
@MainActor final class NativeEndpoint {
    let id=UUID(),ticket:PlaybackSwitchTicket
    var activations=0,finalizations=0,cancellations=0,retirements=0
    var replacements:[PlaybackSwitchTicket?]=[]
    var onCancel:(()->Void)?,onFinalize:(()->Void)?
    init(_ ticket:PlaybackSwitchTicket){self.ticket=ticket}
    var endpoint:PlaybackSwitchEndpoint {
        .init(id:id,activate:{[self] in activations += 1},finalize:{[self] in
            finalizations += 1;onFinalize?()
        },cancel:{[self] done in cancellations += 1;onCancel?();done()},
        setOutputActive:{_,done in done(true)},retire:{[self] replacement,done in
            replacements.append(replacement);retirements += 1;done()})
    }
    func show(_ manager:WallpaperManager){manager.switchVisible(ticket,executionID:id)}
}
@MainActor func candidate(_ manager:WallpaperManager,_ runtime:WallpaperRuntimeKind,
                          path:String="/new-video")->NativeEndpoint {
    let ticket:PlaybackSwitchTicket
    if runtime == .video {
        manager.pendingWallpaper = .init(path:path)
        manager.prepareVideoSwitch(.init(path:path))
        ticket=WallpaperEngine.shared.lastPreparedVideoTicket!
    } else {
        _=manager.beginPlaybackIntent(runtime:runtime)
        ticket=manager.playbackSwitch.pending!.selection.ticket
        if runtime == .web {manager.switchSelections[ticket.id] = .web("web")}
        else {manager.switchSelections[ticket.id] = .scene("scene")}
    }
    let native=NativeEndpoint(ticket)
    if runtime == .video {
        native.onFinalize={
            let engine=WallpaperEngine.shared
            engine.activeVideoPlayback = .init(path:path)
            engine.activeVideoExecution = .init(id:native.id,ticket:ticket)
            engine.videoEndState=nil;engine.currentPlaybackContentKind = .video;engine.currentContentPath=path
        }
    }
    manager.switchPrepared(ticket,endpoint:native.endpoint)
    return native
}
@MainActor func drainMainQueue() async {
    await withCheckedContinuation{continuation in DispatchQueue.main.async{continuation.resume()}}
}
'''


def product_harness():
    manager = (MANAGER / "WallpaperManager.swift").read_text()
    routing = (MANAGER / "WallpaperManager+RuntimeSwitching.swift").read_text()
    settings = (MANAGER / "WallpaperManager+PlaybackSettings.swift").read_text()
    events = (MANAGER / "WallpaperManager+PlaybackEvents.swift").read_text()
    methods = [method(manager, signature) for signature in (
        "func beginPlaybackIntent(runtime: WallpaperRuntimeKind? = nil) -> UInt64",
        "func restoreCommittedPlaybackIntent()",
    )]
    methods += [method(routing, signature) for signature in (
        "func admitsDeferredVideoEnd(", "func prepareVideoSwitch(", "func switchPrepared(", "func switchVisible(", "func switchFailed(",
        "func scheduleSwitchDeadline(", "func runSwitchEffects(", "private func commitSwitch(",
        "private func pruneSwitchSelection(",
    )]
    methods += [method(settings, signature) for signature in (
        "func shouldRunAutoSwitchTimer()", "func startAutoSwitchTimer()", "func stopAutoSwitchTimer()",
        "func refreshAutoSwitchTimerIfNeeded(",
    )]
    methods += [method(events, signature) for signature in (
        "func observePlaybackEvents(", "private func handleEnginePlaybackFailure(",
    )]
    engine = (REPO_ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift").read_text()
    return SUPPORT.replace("// SELECTION", method(routing, "enum RuntimeSwitchSelection")) \
        .replace("// MANAGER_METHODS", "\n".join(methods)) \
        .replace("// ENGINE_METHOD", method(engine, "func replayDeferredVideoEndIfNeeded()"))


class ImportedVideoAutoplayGateTests(unittest.TestCase):
    def run_product_harness(self, program, expected):
        with tempfile.TemporaryDirectory(prefix="mwx-autoplay-transaction-") as directory:
            folder=Path(directory)
            source,binary=folder / "Harness.swift",folder / "harness"
            source.write_text(product_harness() + program)
            # Snapshot shared sources so another lane's integration save cannot
            # invalidate an in-progress Swift compilation.
            sources=[]
            for original in [*GATE_SOURCES, CONTROL / "PlaybackSwitchTransaction.swift"]:
                copy=folder / original.name
                copy.write_bytes(original.read_bytes());sources.append(str(copy))
            built=subprocess.run(["xcrun","swiftc","-swift-version","5","-parse-as-library",
                *sources,str(source),"-o",str(binary)],capture_output=True,text=True,timeout=60)
            self.assertEqual(built.returncode,0,built.stdout+built.stderr)
            result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn(expected,result.stdout)

    def test_preparation_revoke_and_failed_intent_restore(self):
        self.run_product_harness(r'''
@main enum Check {
    @MainActor static func main() {
        let manager=WallpaperManager()
        let committed=candidate(manager,.video,path:"/old-video");committed.show(manager)
        precondition(manager.shouldRunAutoSwitchTimer() && manager.autoSwitchTimer != nil)
        let scene=candidate(manager,.scene)
        let oldAutoplay=ImportedVideoAutoplayGate.shared.claim(),oldEpoch=manager.playbackIntentEpoch
        var installedBeforeCancel=false
        scene.onCancel={installedBeforeCancel=manager.requestedRuntime == .web
            && manager.playbackIntentEpoch == oldEpoch+1}
        let epoch=manager.beginPlaybackIntent(runtime:.web)
        precondition(epoch == oldEpoch+1 && installedBeforeCancel && scene.cancellations == 1)
        precondition(!ImportedVideoAutoplayGate.shared.isCurrent(oldAutoplay))
        precondition(manager.pendingWallpaper == nil && manager.autoSwitchTimer == nil)
        manager.refreshAutoSwitchTimerIfNeeded()
        precondition(!manager.shouldRunAutoSwitchTimer() && manager.autoSwitchTimer == nil,
            "settings refresh cannot restart retained Video timer while Web is pending")
        manager.restoreCommittedPlaybackIntent()
        precondition(manager.requestedRuntime == .video && manager.activeWallpaperRuntime == .video
            && manager.currentWallpaper?.path == "/old-video" && manager.autoSwitchTimer != nil)
        let failedVideo=candidate(manager,.video)
        manager.refreshAutoSwitchTimerIfNeeded()
        precondition(!manager.shouldRunAutoSwitchTimer() && manager.autoSwitchTimer == nil)
        manager.switchFailed(failedVideo.ticket,reason:"video failed")
        precondition(manager.pendingWallpaper == nil && manager.autoSwitchTimer != nil
            && manager.currentWallpaper?.path == "/old-video")
        let committedScene=candidate(manager,.scene);committedScene.show(manager)
        _=manager.beginPlaybackIntent(runtime:.web);manager.restoreCommittedPlaybackIntent()
        precondition(manager.requestedRuntime == .scene && manager.autoSwitchTimer == nil)
        manager.stopAutoSwitchTimer()
        print("preparation-intent-restore-pass")
    }
}
''', "preparation-intent-restore-pass")

    def test_termination_revokes_delayed_web_completion_before_cleanup(self):
        service=(REPO_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService.swift").read_text()
        web=(REPO_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift").read_text()
        delegate=(REPO_ROOT / "MyWallpaperX/App/AppDelegate.swift").read_text()
        guards=web[web.index("                guard !Task.isCancelled, launchGeneration == self.webLaunchIntentGeneration"):
                   web.index("                guard let preparation else")]
        program=r'''
struct Preparation {var isCurrent:()->Bool}
struct Record {let id="fixture"}
@MainActor final class SteamWorkshopService {
    static let shared=SteamWorkshopService()
    var webLaunchIntentGeneration:UInt64=0
    var webLaunchPreparationTask:Task<Void,Never>?
    var cancelWebProcessPreparation:(()->Void)?
    var launches=0,cleared=0
    func clearLaunchPending(matching:String){cleared += 1}
    // SERVICE
    func complete(_ launchGeneration:UInt64,_ processPreparation:Preparation?) {
        let record=Record()
        // GUARDS
        launches += 1
    }
}
@MainActor final class AppDelegate {
    var didPrepareProductTermination=false
    var pendingInitialWindowOpen:DispatchWorkItem?,statusBarController:Int?
    // DELEGATE
}
@main enum Check {
    @MainActor static func main() async {
        let manager=WallpaperManager.shared,service=SteamWorkshopService.shared,engine=WallpaperEngine.shared
        let currentEpoch=manager.beginPlaybackIntent(runtime:.web)
        let currentGeneration=service.advanceWebLaunchIntentGeneration()
        service.complete(currentGeneration,.init(isCurrent:{manager.playbackIntentEpoch == currentEpoch}))
        precondition(service.launches == 1,"current completion positive control")
        service.complete(currentGeneration,.init(isCurrent:{false}))
        precondition(service.launches == 1 && service.cleared == 1,"same generation still needs current product intent")
        let pendingEpoch=manager.beginPlaybackIntent(runtime:.web)
        let pendingGeneration=service.advanceWebLaunchIntentGeneration()
        let preparation=Preparation(isCurrent:{manager.playbackIntentEpoch == pendingEpoch})
        let importToken=ImportedVideoAutoplayGate.shared.claim()
        var cancellations=0
        Trace.values=[]
        engine.cancellation={_ in precondition(manager.playbackIntentEpoch > pendingEpoch
            && manager.requestedRuntime == nil,"stop must install revoked epoch before endpoint cancellation")}
        service.cancelWebProcessPreparation={
            precondition(manager.playbackIntentEpoch > pendingEpoch && manager.requestedRuntime == nil)
            precondition(!ImportedVideoAutoplayGate.shared.isCurrent(importToken))
            Trace.values.append("steamCancel");cancellations += 1
        }
        manager.onFlush={precondition(cancellations == 1 && service.webLaunchIntentGeneration > pendingGeneration
            && manager.requestedRuntime == nil,"flush follows product and asynchronous Steam revocation")}
        let deferred=Task{@MainActor in await Task.yield();service.complete(pendingGeneration,preparation)}
        let app=AppDelegate();app.prepareProductTermination();await deferred.value
        precondition(service.launches == 1 && cancellations == 1 && engine.epoch == manager.playbackIntentEpoch)
        precondition(Trace.values == ["cancelEndpoint","adopt","steamCancel","flush","cleanup"])
        app.prepareProductTermination()
        precondition(engine.cleanups == 1 && cancellations == 1 && Trace.values.count == 5)
        print("termination-revoke-pass")
    }
}
'''
        program=program.replace("// SERVICE",method(service,"func advanceWebLaunchIntentGeneration() -> UInt64"))
        program=program.replace("// GUARDS",guards)
        program=program.replace("// DELEGATE",method(delegate,"private func prepareProductTermination()"))
        self.run_product_harness(program,"termination-revoke-pass")

    def test_video_ready_rearms_timer_after_candidate_commits(self):
        self.run_product_harness(r'''
@main enum Check {
    @MainActor static func main() async {
        let manager=WallpaperManager(),engine=WallpaperEngine.shared
        var cancellables=Set<AnyCancellable>();manager.observePlaybackEvents(storeIn:&cancellables)
        let web=candidate(manager,.web);web.show(manager)
        let video=candidate(manager,.video)
        precondition(video.activations == 1 && manager.currentWallpaper == nil
            && manager.activeWallpaperRuntime == .web && manager.autoSwitchTimer == nil)
        NotificationCenter.default.post(name:WallpaperEngine.playbackReadyNotification,
            object:nil,userInfo:["videoPath":"/new-video"])
        manager.switchVisible(video.ticket,executionID:UUID())
        precondition(manager.autoSwitchTimer == nil,"legacy ready and wrong native identity cannot commit")
        let installVideo=video.onFinalize
        video.onFinalize={
            precondition(manager.playbackSwitch.committed?.ticket == video.ticket
                && manager.currentWallpaper?.path == "/new-video" && manager.pendingWallpaper == nil
                && manager.autoSwitchTimer != nil,"product commit and timer rearm precede native finalize")
            installVideo?()
        }
        video.show(manager)
        let timer=manager.autoSwitchTimer!
        precondition(video.finalizations == 1 && web.retirements == 1 && manager.snapshots == 2)
        video.show(manager)
        NotificationCenter.default.post(name:WallpaperEngine.playbackReadyNotification,
            object:nil,userInfo:["videoPath":"/new-video"])
        precondition(manager.autoSwitchTimer === timer && video.finalizations == 1,
            "duplicate proof cannot restart committed Video timer")
        let retainedID=engine.activeVideoPlayback!.id
        let pendingWeb=candidate(manager,.web)
        let adapter=engine.dedicatedWebHostAdapter as! WebDaemonHostAdapter
        adapter.hasPendingRequest=true
        pendingWeb.onCancel={adapter.hasPendingRequest=false}
        engine.videoEndState=(retainedID,false);engine.replayDeferredVideoEndIfNeeded()
        await drainMainQueue()
        precondition(manager.endedPaths.isEmpty && engine.videoEndState?.delivered == false,
            "retained Video EOF cannot steal pending Web selection")
        manager.switchFailed(pendingWeb.ticket,reason:"web preparation failed")
        await drainMainQueue()
        precondition(manager.requestedRuntime == .video && manager.autoSwitchTimer != nil
            && manager.endedPaths == ["/new-video"] && engine.videoEndState?.delivered == true)
        engine.replayDeferredVideoEndIfNeeded();await drainMainQueue()
        precondition(manager.endedPaths.count == 1,"deferred EOF must be delivered once")
        manager.endedPaths=[]
        let pendingScene=candidate(manager,.scene)
        engine.videoEndState=(retainedID,false);engine.replayDeferredVideoEndIfNeeded()
        await drainMainQueue()
        precondition(manager.endedPaths.isEmpty && engine.videoEndState?.delivered == false,
            "Scene preparation consumed an EOF that the product owner cannot accept")
        manager.switchFailed(pendingScene.ticket,reason:"scene preparation failed")
        await drainMainQueue()
        precondition(manager.endedPaths == ["/new-video"] && engine.videoEndState?.delivered == true,
            "Scene rollback lost retained Video EOF")
        let previousPreparations=engine.videoPreparations
        let explicitSameVideo=candidate(manager,.video)
        precondition(explicitSameVideo.ticket != video.ticket && engine.videoPreparations == previousPreparations+1
            && manager.pendingWallpaper != nil,"same URL is a new typed execution, including an ended slot")
        explicitSameVideo.show(manager)
        precondition(manager.pendingWallpaper == nil && manager.autoSwitchTimer != nil
            && engine.activeVideoPlayback?.id != retainedID && engine.videoEndState == nil)
        manager.stopAutoSwitchTimer()
        print("video-ready-timer-pass")
    }
}
''',"video-ready-timer-pass")

    def test_latest_runtime_intent_controls_autoplay(self) -> None:
        program = """
        import Foundation

        let gate = ImportedVideoAutoplayGate.shared
        final class TestLifetime: PlaybackResourceLifetime {}

        let firstRequest = gate.claim()
        let latestRequest = gate.claim()
        precondition(!gate.isCurrent(firstRequest))
        precondition(gate.isCurrent(latestRequest))

        // A delayed import cannot replace the latest explicit playback intent.
        precondition(!gate.isCurrent(firstRequest))

        let staleAfterNewIntent = gate.claim()
        gate.invalidate() // Accepted product intent revokes before preparation.
        precondition(!gate.isCurrent(staleAfterNewIntent))
        // A previous output can finish its handoff after a newer import was
        // selected. Visible-output retirement must not revoke that new ticket.
        let pendingAfterEarlierHandoff = gate.claim()
        postWallpaperRuntimeWillSwitch(to: .web)
        precondition(gate.isCurrent(pendingAfterEarlierHandoff))

        let replacedSameItem = gate.claim()
        let currentSameItem = gate.claim()
        precondition(!gate.isCurrent(replacedSameItem))
        precondition(gate.isCurrent(currentSameItem))

        var decodedRequest: ImportedVideoPlaybackRequest?
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("AutoplayGateTest"), object: nil, queue: nil
        ) { notification in
            decodedRequest = ImportedVideoPlaybackRequest(notification: notification)
        }
        let lifetime = TestLifetime()
        ImportedVideoPlaybackRequest(
            localURL: URL(fileURLWithPath: "/tmp/latest.mp4"),
            autoplayToken: currentSameItem,
            resourceLifetime: lifetime
        ).post(name: Notification.Name("AutoplayGateTest"))
        NotificationCenter.default.removeObserver(observer)
        precondition(decodedRequest?.localURL.path == "/tmp/latest.mp4")
        precondition(decodedRequest?.autoplayToken == currentSameItem)
        precondition(decodedRequest?.resourceLifetime === lifetime)

        print("imported-video-autoplay-gate-pass")
        """
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            main_source = directory_path / "main.swift"
            executable = directory_path / "gate-test"
            main_source.write_text(program, encoding="utf-8")
            subprocess.run(
                [
                    "/usr/bin/xcrun",
                    "swiftc",
                    *(str(source) for source in GATE_SOURCES),
                    str(main_source),
                    "-o",
                    str(executable),
                ],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.stdout.strip(), "imported-video-autoplay-gate-pass")

    def test_reentrant_commit_revokes_only_stale_handoff_retention(self):
        self.run_product_harness(r'''
@main enum Check {
    @MainActor static func main() {
        let cases:[(String,Bool,WallpaperRuntimeKind?)]=[
            ("current",false,nil),("web",true,.web),("video",true,.video),
            ("scene",true,.scene),("stop",true,nil)]
        for (name,reenters,runtime) in cases {
            let manager=WallpaperManager()
            let old=candidate(manager,.scene);old.show(manager)
            let successor=candidate(manager,.web)
            var latestEpoch:UInt64?
            manager.onPersist={
                manager.onPersist=nil
                if reenters {latestEpoch=manager.beginPlaybackIntent(runtime:runtime)}
            }
            successor.show(manager)
            precondition(old.retirements == 1 && old.replacements.count == 1,
                "old handoff and barrier must not be dropped: "+name)
            let expected=(!reenters || runtime == .scene) ? successor.ticket : nil
            precondition(old.replacements[0] == expected,
                "only current successor or newer Scene may retain the old helper: "+name)
            precondition(manager.playbackSwitch.retirements.isEmpty
                && manager.switchEndpoints[old.id] == nil,
                "optional retention refusal still completes exact old retirement: "+name)
            if let latestEpoch {
                precondition(manager.playbackIntentEpoch == latestEpoch
                    && manager.requestedRuntime == runtime)
            }
            manager.stopAutoSwitchTimer()
        }
        print("reentrant-handoff-retention-pass")
    }
}
''',"reentrant-handoff-retention-pass")


if __name__ == "__main__":
    unittest.main()
