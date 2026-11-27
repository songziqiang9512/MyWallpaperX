"""Execute Scene's production endpoint closures, receipts, and activity policy."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.scene.test_scene_wallpaper_async_launch import function_body

ROOT = Path(__file__).resolve().parents[3]
IPC = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC"
SESSION = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session"


def method(source, signature):
    return signature.removeprefix("private ") + " " + function_body(source, signature)


SUPPORT = r'''
import Foundation
import CoreFoundation
@MainActor final class DaemonPlaybackProcessRegistry {static let shared=DaemonPlaybackProcessRegistry();var acceptsNewProcesses=true}
struct ScenePlaybackLoadRequest {let recordID:String?; var rootURL=URL(fileURLWithPath:"/version");var source:ScenePlaybackSource?=nil}
final class PlaybackResourceLifetime {}
final class DaemonProcessTransport {
    var isRunning=true;var terminations=0;func terminate(){terminations += 1};func closeIO(){}
}
struct SceneWallpaperLaunchState {
    enum Phase:String {case accepted,launched,cancelled,failed}
    let requestID:UUID;let recordID:String?;let phase:Phase;let message:String
    var callbackPropertyReachability:Reachability?=nil
}
struct SceneFramePresentation {let requestID:UUID;let recordID:String?;let uptimeMicros:UInt64}
struct Reachability:Codable {
    struct Source:Codable {var rootPath="/version"}
    var source=Source();var scriptGeneration=1
}
typealias ScenePreparedCallbackPropertyReachability=Reachability
enum Outcome {case superseded,failed(String)}
struct Backoff {mutating func reset(){}}
enum SceneDaemonProtocol {static let version=2
// PROTOCOL_METHODS
}
@MainActor struct NSScreen {
    let displayID: Int
    static let screens = [Self(displayID: 1), Self(displayID: 2)]
    static var modeRefreshRate: Double = 120
}
struct SceneScreenTopology:Equatable {
    let displayID:Int
    let modeRefreshRate:Double?
    let frame=0
    let backingScaleFactor:Double=1
    let unknownModeRefreshLimit:Double?=nil
    @MainActor static func capture(screens:[NSScreen])->[Self] {
        screens.map{.init(displayID:$0.displayID,modeRefreshRate:NSScreen.modeRefreshRate)}
    }
    // DISPLAY_CADENCE_METHODS
}
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange=Notification.Name("state")
    static let sceneWallpaperFirstFrameDidPresent=Notification.Name("frame")
}
@MainActor final class SceneDaemonClient {
    struct Lifetime {let lifetime:PlaybackResourceLifetime;var source:ScenePlaybackSource?=nil}
    struct Facts {let transportGeneration:UInt64;let requestID:UUID;let recordID:String?;let reachability:Reachability}
    var activeIntent:ScenePlaybackLoadRequest?
    var pendingIntent:ScenePlaybackLoadRequest?
    var activeResourceLifetime:Lifetime?
    var pendingResourceLifetime:Lifetime?
    var pendingRequestID:UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:Reachability?
    var pendingPropertyRevisions:[UInt64:String]=[:]
    var activeCallbackPropertyFacts:Facts?
    var activeRecordID:String?
    var activeRequestID:UUID?
    var sessionGeneration:UInt64=1
    #if DEBUG
    var debugStartupObserver:((SceneDaemonStartupObservation)->Void)?
    var debugStartupPrefixObserver:((SceneDaemonStartupPrefixObservation)->Void)?
    var debugProcessIdentifier:Int32? {123}
    #endif
    var requestRetirementSchemaVersion:Int?
    var idleTransport:IdleTransport?
    var sourceSchemaVersion:Int?
    var endpointReady=true
    var transport:DaemonProcessTransport?=DaemonProcessTransport()
    var activeSwitchTicket:PlaybackSwitchTicket?
    var pendingSwitchTicket:PlaybackSwitchTicket?
    var activeSwitchExecution:SwitchExecution?
    var pendingSwitchExecution:SwitchExecution?
    var switchControls:[UUID:SwitchControl]=[:]
    var queuedSwitchPreparation:QueuedSwitchPreparation?
    var committedSwitchRecovery:CommittedSwitchRecovery?
    var deferredDisplayConfigurationUpdate=false
    var multiDisplayEnabled=false
    var displayConfiguration=[SceneScreenTopology(displayID:1,modeRefreshRate:120)]
    var configuredAnimationCadenceLimit:Double {SceneScreenTopology.cadenceLimit(for:displayConfiguration)}
    var cadenceNotifications=0
    func notifyAnimationCadenceChanged() {cadenceNotifications += 1}
    var displayUpdates=0
    var switchPrepared:((PlaybackSwitchTicket,PlaybackSwitchEndpoint)->Void)?
    var switchVisible:((PlaybackSwitchTicket,UUID)->Void)?
    var switchFailed:((PlaybackSwitchTicket,String)->Void)?
    var switchLost:((PlaybackSwitchTicket,String)->Void)?
    var sent:[[String:Any]]=[]
    var launchState:SceneWallpaperLaunchState?
    var restartBackoff=Backoff()
    var resumed:[UUID]=[]
    var stopped=0
    var retiringTransports:[UInt64:DaemonProcessTransport]=[:]
    var retiringResourceLifetimes:[UInt64:[PlaybackResourceLifetime]]=[:]
    var expectedTerminationGenerations:Set<UInt64>=[]
    var handshakeWorkItem:DispatchWorkItem?
    var latestFrameStats:Int?
    var requestResourceLifetimes:[UUID:PlaybackResourceLifetime]=[:]
    var restarts:[String]=[]
    var captureCompletion:(()->Void)?
    func retainResourceLifetime(_ value:PlaybackResourceLifetime?,rootURL:URL,recordID:String?,source:ScenePlaybackSource?=nil) {
        pendingResourceLifetime=value.map{Lifetime(lifetime:$0,source:source)}
    }
    func startLaunch(_ request:ScenePlaybackLoadRequest,ticket:PlaybackSwitchTicket?) {
        pendingIntent=request;pendingSwitchTicket=ticket
    }
    func finishPendingTextureUpdates(_ result:Outcome) {}
    func finishPendingShortcutUpdates(_ outcome: Outcome) {}
    func send(_ value:[String:Any]) {sent.append(value)}
    func stop() {
        discardIdleTransport();requestRetirementSchemaVersion=nil
        stopped += 1;pendingIntent=nil;pendingRequestID=nil;pendingSwitchTicket=nil
        pendingSwitchExecution=nil;activeSwitchExecution=nil;activeIntent=nil;transport=nil
        queuedSwitchPreparation=nil
        committedSwitchRecovery=nil
    }
    func sendDisplayConfiguration() {displayUpdates += 1}
    func cancelPreparationForRuntimeSwitch() {pendingIntent=nil;pendingSwitchTicket=nil}
    func finishShutdownIfPossible(){}
    func revokeAudioSpectrumDemand(generation:UInt64){}
    func revokeSystemMediaDemand(generation:UInt64){}
    func failPendingFrameCaptures(){captureCompletion?();captureCompletion=nil}
    func scheduleRestart(reason:String){restarts.append(reason)}
    func bindDeferredTextureUpdates(recordID:String?,requestID:UUID){}
    func finishTextureReload(recordID:String?,outcome:Outcome){}
    func publishFailure(code:String,message:String){fatalError(message)}
    func fallbackReplayIntent(requestID:UUID)->ScenePlaybackLoadRequest? {nil}
    func resumeDeferredTextureUpdates(recordID:String?,requestID:UUID) {resumed.append(requestID)}
    static func double(_ raw:Any?)->Double? {raw as? Double}
    // EVENTS
}
'''

HARNESS = r'''
@main enum Harness {
    static func preparedPayload(_ request:UUID,_ quality:SceneRenderQuality)->[String:Any] {
        var payload:[String:Any]=["requestID":request.uuidString]
        SceneDaemonProtocol.writeRenderQuality(quality,to:&payload)
        return payload
    }

    @MainActor static func main() {
        let ticket=PlaybackSwitchTicket(epoch:1,id:UUID(),runtime:.scene)
        let next=PlaybackSwitchTicket(epoch:2,id:UUID(),runtime:.scene)
        let oldID=UUID(),id=UUID()
        let client=SceneDaemonClient()
        client.activeIntent = .init(recordID:"old");client.activeRequestID=oldID
        client.pendingIntent = .init(recordID:"new");client.pendingRequestID=id
        client.pendingSwitchTicket=ticket
        client.handleLaunchState(["phase":"accepted","requestID":UUID().uuidString,
                                  "recordID":"new","message":"accepted"])
        client.handleLaunchState(["phase":"accepted","requestID":id.uuidString,
                                  "recordID":"old","message":"accepted"])
        precondition(client.launchState == nil && client.pendingRequestID == id,
                     "wrong request or record must not publish launch state")
        client.handleLaunchState(["phase":"accepted","requestID":id.uuidString,
                                  "recordID":"new","message":"accepted"])
        precondition(client.launchState?.phase == .accepted && client.launchState?.recordID == "new")
        var endpoint:PlaybackSwitchEndpoint?
        var observed=0
        client.switchPrepared={observed += 1;precondition($0 == ticket);endpoint=$1}
        let sdrQuality=SceneRenderQuality(shadows:.medium,volumeLighting:.ultra,
            reflections:.disabled,textures:.performance,antiAliasing:.msaa4)
        var hdrQuality=sdrQuality;hdrQuality.postProcessing = .ultraDisplayHDR
        client.handleCandidatePrepared(preparedPayload(UUID(),hdrQuality))
        precondition(endpoint == nil && client.pendingSwitchExecution == nil && client.sent.isEmpty)
        client.handleCandidatePrepared(preparedPayload(id,hdrQuality))
        let first=endpoint!
        client.handleCandidatePrepared(preparedPayload(id,.init()))
        precondition(observed == 1 && client.sent.isEmpty,"prepared cannot activate itself")
        precondition(client.pendingSwitchExecution?.preparationQuality == sdrQuality
            && client.activePreparedRenderQuality == nil,"first prepared fact is frozen and HDR shares the SDR Ultra domain")
        first.finalize()
        precondition(client.sent.isEmpty,"finalize before actual presentation is rejected")
        first.activate();first.activate()
        precondition(client.sent.count == 1 && client.sent[0]["cmd"] as? String == "commitCandidate")
        client.pendingPresentationRequestID=id
        var visible=0
        client.switchVisible={precondition($0 == ticket && $1 == first.id);visible += 1}
        client.handleFirstFrame(["requestID":UUID().uuidString,"recordID":"new","uptimeMs":1.0])
        precondition(visible == 0 && client.activeRequestID == oldID
            && client.pendingRequestID == id && client.sent.count == 1,
            "wrong request must not publish candidate visibility")
        client.handleFirstFrame(["requestID":id.uuidString,"recordID":"new","uptimeMs":1.0])
        precondition(visible == 1 && client.activeRequestID == oldID && client.sent.count == 1
            && client.activePreparedRenderQuality == nil,
                     "drawable proof reports visibility but cannot commit/finalize product state")
        first.finalize()
        precondition(client.activeRequestID == id && client.activeSwitchTicket == ticket
            && client.pendingIntent == nil && client.sent.last?["cmd"] as? String == "finalizeCandidate"
            && client.activePreparedRenderQuality == sdrQuality)
        client.activeRequestID=oldID
        precondition(client.activePreparedRenderQuality == nil,"another request cannot inherit a quality fact")
        client.activeRequestID=id

        var activity:Bool?
        first.setOutputActive(false){activity=$0}
        let activityCommand=client.sent.last!
        let op=activityCommand["operationID"] as! String
        precondition(activity == nil && client.activeSwitchExecution?.outputActive == true)
        func receipt(_ request:UUID,_ operation:String,_ accepted:Bool=true)->[String:Any] {
            ["operationID":operation,"requestID":request.uuidString,"accepted":accepted]
        }
        client.handleSwitchControlResult(receipt(UUID(),op),generation:1)
        client.handleSwitchControlResult(receipt(id,op),generation:9)
        precondition(activity == nil,"wrong request and generation cannot acknowledge activity")
        client.handleSwitchControlResult(receipt(id,op),generation:1)
        precondition(activity == true && client.activeSwitchExecution?.outputActive == false)

        let secondID=UUID()
        client.pendingIntent = .init(recordID:"second");client.pendingRequestID=secondID
        client.pendingSwitchTicket=next
        client.switchPrepared={_,value in endpoint=value}
        client.handleCandidatePrepared(preparedPayload(secondID,.init()))
        let second=endpoint!
        precondition(client.activePreparedRenderQuality == sdrQuality,"pending replacement does not own active quality")
        second.activate()
        var cancelled=0
        second.cancel{cancelled += 1}
        let cancellation=client.sent.last!
        precondition(cancelled == 0 && client.pendingRequestID == nil && client.activeRequestID == id)
        precondition(client.activePreparedRenderQuality == sdrQuality)
        let thirdID=UUID()
        client.pendingIntent = .init(recordID:"third");client.pendingRequestID=thirdID
        client.pendingSwitchTicket=next // same product, newer native execution
        var legacyPrepared=preparedPayload(thirdID,.init())
        legacyPrepared.removeValue(forKey:"antiAliasingMode")
        client.handleCandidatePrepared(legacyPrepared)
        let third=endpoint!
        precondition(client.pendingSwitchExecution?.preparationQuality == nil
            && client.activePreparedRenderQuality == sdrQuality)
        second.cancel{cancelled += 1}
        let repeated=client.sent.last!
        precondition(repeated["requestID"] as? String == secondID.uuidString
            && client.pendingRequestID == thirdID,"stale endpoint cancel cannot revoke same-ticket replacement")
        client.handleSwitchControlResult(receipt(secondID,cancellation["operationID"] as! String),generation:1)
        precondition(cancelled == 1 && client.pendingRequestID == thirdID)
        client.handleSwitchControlResult(receipt(secondID,repeated["operationID"] as! String),generation:1)
        precondition(cancelled == 2)
        third.activate();client.pendingPresentationRequestID=thirdID
        client.switchVisible={_,_ in}
        client.handleFirstFrame(["requestID":thirdID.uuidString,"uptimeMs":2.0])
        let queuedTicket=PlaybackSwitchTicket(epoch:3,id:UUID(),runtime:.scene)
        client.prepareSwitch(.init(recordID:"queued"),ticket:queuedTicket,resourceLifetime:nil)
        precondition(client.queuedSwitchPreparation?.ticket == queuedTicket && client.pendingRequestID == thirdID,
            "new Scene preparation cannot cancel already visible execution before product finalize")
        var queueCancelled=false
        client.cancelSwitch(ticket:queuedTicket){
            if case .cancelled? = client.launchState?.phase {
                queueCancelled = client.launchState?.recordID == "queued"
            }
        }
        precondition(queueCancelled && client.queuedSwitchPreparation == nil && client.pendingRequestID == thirdID)
        client.prepareSwitch(.init(recordID:"after-finalize"),ticket:queuedTicket,resourceLifetime:nil)
        NSScreen.modeRefreshRate=59.94
        client.updateDisplayConfiguration(multiDisplayEnabled:false)
        precondition(!client.deferredDisplayConfigurationUpdate && client.displayUpdates == 1
            && client.pendingRequestID == thirdID && client.cadenceNotifications == 1
            && client.configuredAnimationCadenceLimit == 59.94,"same geometry sends a cadence change while finalize is pending")
        client.updateDisplayConfiguration(multiDisplayEnabled:true)
        precondition(client.deferredDisplayConfigurationUpdate && client.displayUpdates == 1
            && client.pendingRequestID == thirdID,"topology must not revoke visible product commitment")
        var oldRetired=false
        first.retire(nil) {oldRetired=true}
        let retirement=client.sent.last!
        precondition(!oldRetired && client.activeRequestID == id && client.stopped == 0,
            "same-engine old standby remains until activity ACK and successor finalize")
        client.handleSwitchControlResult(receipt(id,retirement["operationID"] as! String),generation:1)
        precondition(oldRetired && client.activeRequestID == id && client.pendingRequestID == thirdID)
        third.finalize()
        precondition(client.queuedSwitchPreparation == nil && client.pendingSwitchTicket == queuedTicket
            && client.pendingIntent?.recordID == "after-finalize", "finalize releases queued native preparation")
        precondition(client.activeRequestID == thirdID && client.activePreparedRenderQuality == nil,
            "an old daemon can finalize without synthesizing an active quality fact")
        precondition(!client.deferredDisplayConfigurationUpdate && client.displayUpdates == 2
            && client.displayConfiguration.count == 2,"finalize flushes latest display policy before queued prepare")
        client.pendingIntent=nil;client.pendingSwitchTicket=nil // leaf startLaunch in this harness does no IPC
        var retired=false
        first.retire(nil) {retired=true}
        precondition(retired && client.stopped == 0 && client.activeRequestID == thirdID,
                     "retire of replaced endpoint cannot stop newer same-engine execution")

        let oldChild=client.transport!
        var exitedRetirement=false
        third.retire(nil) {exitedRetirement=true}
        precondition(!exitedRetirement && client.stopped == 1,
            "cross-engine retirement waits for actual child exit")
        oldChild.isRunning=false
        client.finishSwitchControlsAfterExit(generation:1)
        precondition(exitedRetirement)
        client.sessionGeneration=2;client.transport=DaemonProcessTransport()
        var deactivated=false
        third.setOutputActive(false){deactivated=$0}
        precondition(deactivated,"physical exit proves old output deactivated during recovery")
        third.setOutputActive(true){precondition(!$0,"old generation cannot restore itself")}

        let cold=SceneDaemonClient(),child=cold.transport!
        cold.pendingIntent = .init(recordID:"cold");cold.pendingSwitchTicket=ticket
        var coldCancelled=false
        cold.cancelSwitch(ticket:ticket){coldCancelled=true}
        precondition(!coldCancelled && cold.stopped == 1,"pre-hello cancellation awaits actual exit")
        cold.switchControls.values.first!.deadline!.perform()
        precondition(child.terminations == 1 && !coldCancelled,"deadline requests termination, not fake completion")
        child.isRunning=false;cold.finishSwitchControlsAfterExit(generation:1)
        precondition(coldCancelled && cold.switchControls.isEmpty)
        exerciseCrashRecovery()

        let standalone=SceneDaemonClient(),directID=UUID()
        standalone.pendingIntent = .init(recordID:"debug");standalone.pendingRequestID=directID
        standalone.handleCandidatePrepared(["requestID":directID.uuidString])
#if DEBUG
        precondition(standalone.sent.last?["cmd"] as? String == "commitCandidate")
#else
        precondition(standalone.sent.isEmpty,"production without product owner must not auto-activate")
#endif
        do {
            let a=PlaybackSwitchTicket(epoch:40,id:UUID(),runtime:.scene)
            let b=PlaybackSwitchTicket(epoch:41,id:UUID(),runtime:.scene)
            let lease=PlaybackResourceLifetime()
            let capturedSource=ScenePlaybackSource(rootURL:URL(fileURLWithPath:"/version"),managed:.init(
                storageIdentity:"v2:scene:123-11111111-1111-4111-8111-111111111111",
                generation:"11111111-1111-4111-8111-111111111111"))
            let sourceClient=SceneDaemonClient()
            let visible=SceneDaemonClient.SwitchExecution(ticket:a,requestID:UUID(),generation:1,
                transport:sourceClient.transport!,quality:nil)
            visible.presented=true;sourceClient.pendingSwitchExecution=visible
            var selected=ScenePlaybackLoadRequest(recordID:"same-path");selected.source=capturedSource
            sourceClient.prepareSwitch(selected,ticket:b,resourceLifetime:lease)
            precondition(sourceClient.queuedSwitchPreparation?.request.source == capturedSource)
            sourceClient.adoptQueuedSwitchPreparationForRecovery()
            precondition(sourceClient.pendingIntent?.source == capturedSource
                && sourceClient.pendingResourceLifetime?.source == capturedSource
                && sourceClient.pendingResourceLifetime?.lifetime === lease,
                "queued recovery cannot drop or reselect source/lease")
            sourceClient.rememberCommittedSwitchForRecovery()
            precondition(sourceClient.committedSwitchRecovery?.request.source == capturedSource
                && sourceClient.committedSwitchRecovery?.resourceLifetime === lease,
                "committed recovery keeps captured generation with original lease")
        }
        print("scene-switch-endpoint-ok")
    }
    @MainActor static func exerciseCrashRecovery() {
        let a=PlaybackSwitchTicket(epoch:10,id:UUID(),runtime:.scene)
        let b=PlaybackSwitchTicket(epoch:11,id:UUID(),runtime:.scene)
        let c=PlaybackSwitchTicket(epoch:12,id:UUID(),runtime:.scene)
        let lease=PlaybackResourceLifetime()
        let initialQuality=SceneRenderQuality(shadows:.high,textures:.automatic)
        let recoveryQuality=SceneRenderQuality(shadows:.medium,textures:.performance,antiAliasing:.msaa2)
        func active() -> (SceneDaemonClient,PlaybackSwitchEndpoint,DaemonProcessTransport) {
            let client=SceneDaemonClient(),id=UUID()
            client.pendingIntent = .init(recordID:"A");client.pendingSwitchTicket=a;client.pendingRequestID=id
            client.pendingResourceLifetime = .init(lifetime:lease)
            var endpoint:PlaybackSwitchEndpoint?
            client.switchPrepared={_,value in endpoint=value}
            client.handleCandidatePrepared(preparedPayload(id,initialQuality))
            client.pendingSwitchExecution!.presented=true;endpoint!.finalize()
            precondition(client.activePreparedRenderQuality == initialQuality)
            return (client,endpoint!,client.transport!)
        }
        func crashWithPendingB(_ client:SceneDaemonClient,_ child:DaemonProcessTransport) {
            client.pendingIntent = .init(recordID:"B");client.pendingSwitchTicket=b;client.pendingRequestID=UUID()
            child.isRunning=false;client.handleTermination(status:1,generation:1)
            precondition(client.pendingSwitchTicket == b && client.activeIntent == nil
                && client.committedSwitchRecovery?.ticket == a
                && client.committedSwitchRecovery?.resourceLifetime === lease
                && client.activePreparedRenderQuality == nil,
                "crash preserves committed authored input and lease while pending B is retried")
            client.sessionGeneration=2;client.transport=DaemonProcessTransport();client.endpointReady=true
            client.pendingRequestID=UUID()
        }
        func failPending(_ client:SceneDaemonClient,_ record:String) {
            client.handleLaunchState(["phase":"failed","requestID":client.pendingRequestID!.uuidString,
                "recordID":record,"message":"candidate failed"])
        }
        let (newGeneration,_,_)=active()
        newGeneration.sessionGeneration += 1
        precondition(newGeneration.activeRequestID != nil && newGeneration.activeSwitchExecution != nil
            && newGeneration.activePreparedRenderQuality == nil,"a new transport generation invalidates the old fact before termination")

        let (restored,oldA,dead)=active()
        let deadRequest=restored.activeRequestID!
        crashWithPendingB(restored,dead)
        restored.handleCandidatePrepared(preparedPayload(restored.pendingRequestID!,.init()))
        precondition(restored.pendingSwitchExecution != nil && restored.activePreparedRenderQuality == nil)
        failPending(restored,"B")
        precondition(restored.pendingSwitchTicket == a && restored.pendingIntent?.recordID == "A"
            && restored.pendingResourceLifetime?.lifetime === lease && restored.pendingSwitchExecution == nil
            && restored.activePreparedRenderQuality == nil,"failed B recovers A with original product ticket")
        let recoveredID=UUID();restored.pendingRequestID=recoveredID
        var recovered:PlaybackSwitchEndpoint?
        restored.switchPrepared={ticket,value in precondition(ticket == a);recovered=value}
        restored.handleCandidatePrepared(preparedPayload(deadRequest,initialQuality))
        precondition(recovered == nil && restored.activePreparedRenderQuality == nil)
        restored.handleCandidatePrepared(preparedPayload(recoveredID,recoveryQuality))
        recovered!.activate();restored.pendingPresentationRequestID=recoveredID;restored.switchVisible={_,_ in}
        restored.handleFirstFrame(["requestID":recoveredID.uuidString,"recordID":"A","uptimeMs":3.0])
        var oldRetired=false;oldA.retire(nil) {oldRetired=true}
        precondition(oldRetired && restored.pendingRequestID == recoveredID && restored.activePreparedRenderQuality == nil,
            "retiring dead old endpoint cannot cancel already visible recovery accepted by product")
        recovered!.finalize()
        precondition(restored.activeSwitchTicket == a && restored.committedSwitchRecovery == nil
            && restored.activeRequestID == recoveredID && restored.activePreparedRenderQuality == recoveryQuality)

        let (revoked,oldRevoked,deadRevoked)=active()
        crashWithPendingB(revoked,deadRevoked);failPending(revoked,"B")
        let recoveringChild=revoked.transport!
        var revokedDone=false;oldRevoked.retire(nil) {revokedDone=true}
        precondition(!revokedDone && revoked.pendingIntent == nil && revoked.committedSwitchRecovery == nil,
            "old dead endpoint retirement revokes same-ticket recovery before its prepared event")
        recoveringChild.isRunning=false;revoked.finishSwitchControlsAfterExit(generation:2)
        precondition(revokedDone && revoked.pendingIntent == nil,"retired selection cannot resurrect after exit")

        let (cancelled,_,deadCancelled)=active()
        crashWithPendingB(cancelled,deadCancelled)
        let cancelledChild=cancelled.transport!
        var cancelDone=false;cancelled.cancelSwitch(ticket:b){cancelDone=true}
        precondition(!cancelDone && cancelled.pendingIntent == nil)
        cancelledChild.isRunning=false;cancelled.finishSwitchControlsAfterExit(generation:2)
        precondition(cancelDone && cancelled.pendingSwitchTicket == a,"cancelled B recovers A after actual exit")

        let (reentry,_,deadReentry)=active()
        crashWithPendingB(reentry,deadReentry)
        reentry.switchFailed={ticket,_ in
            precondition(ticket == b);reentry.prepareSwitch(.init(recordID:"C"),ticket:c,resourceLifetime:nil)
        }
        failPending(reentry,"B")
        precondition(reentry.pendingSwitchTicket == c && reentry.pendingIntent?.recordID == "C",
            "a failure callback's newer product prepare wins over committed recovery")

        let (completionReentry,_,completionChild)=active()
        completionReentry.pendingIntent = .init(recordID:"B");completionReentry.pendingSwitchTicket=b
        completionReentry.captureCompletion={
            completionReentry.prepareSwitch(.init(recordID:"C"),ticket:c,resourceLifetime:nil)
        }
        completionChild.isRunning=false;completionReentry.handleTermination(status:1,generation:1)
        precondition(completionReentry.pendingSwitchTicket == c && completionReentry.pendingIntent?.recordID == "C",
            "termination completion reentry cannot be overwritten by captured old recovery intent")

        let (retiredInput,retiredOld,deadInput)=active()
        crashWithPendingB(retiredInput,deadInput)
        var inputRetired=false;retiredOld.retire(nil) {inputRetired=true}
        precondition(inputRetired && retiredInput.pendingSwitchTicket == b
            && retiredInput.committedSwitchRecovery == nil,"retirement preserves another ticket's preparation")
        failPending(retiredInput,"B")
        precondition(retiredInput.pendingIntent == nil,"retired A cannot recover after B failure")

        cancelled.pendingRequestID=UUID();failPending(cancelled,"A")
        precondition(cancelled.pendingIntent == nil,"failed recovery cannot spin another unconditional A reload")

        let (queued,_,queuedChild)=active(),visibleID=UUID(),queuedLease=PlaybackResourceLifetime()
        queued.pendingIntent = .init(recordID:"B");queued.pendingSwitchTicket=b;queued.pendingRequestID=visibleID
        let visible=SceneDaemonClient.SwitchExecution(ticket:b,requestID:visibleID,generation:1,
            transport:queuedChild,quality:nil)
        visible.presented=true;queued.pendingSwitchExecution=visible
        queued.prepareSwitch(.init(recordID:"C"),ticket:c,resourceLifetime:queuedLease)
        queuedChild.isRunning=false;queued.handleTermination(status:1,generation:1)
        precondition(queued.queuedSwitchPreparation == nil && queued.pendingSwitchTicket == c
            && queued.pendingIntent?.recordID == "C" && queued.pendingResourceLifetime?.lifetime === queuedLease
            && queued.committedSwitchRecovery?.ticket == b,
            "crash starts queued C instead of reviving B; already visible B remains the committed recovery input")
        queued.sessionGeneration=2;queued.transport=DaemonProcessTransport();queued.endpointReady=true;queued.pendingRequestID=UUID()
        failPending(queued,"C")
        precondition(queued.pendingSwitchTicket == b && queued.pendingIntent?.recordID == "B")
        queued.stop()
        precondition(queued.committedSwitchRecovery == nil && queued.pendingIntent == nil,
            "explicit stop releases authored recovery input and its version lease")
    }
}
'''


class SceneSwitchEndpointTests(unittest.TestCase):
    def test_native_identity_receipts_cancellation_and_explicit_commit(self):
        events = (IPC / "SceneDaemonClient+Events.swift").read_text()
        protocol = (IPC / "SceneDaemonProtocol.swift").read_text()
        support = SUPPORT.replace("// PROTOCOL_METHODS", "\n".join(method(protocol, signature) for signature in (
            "static func boolean(_ raw: Any?) -> Bool?",
            "static func preparedRenderQuality(_ payload: [String: Any]) -> SceneRenderQuality?",
            "private static func renderQuality(_ payload: [String: Any], fallback: SceneRenderQuality? = nil) -> SceneRenderQuality?",
            "static func writeRenderQuality(_ quality: SceneRenderQuality, to payload: inout [String: Any])",
        )))
        screen = (IPC.parent / "Frame/SceneScreenTopology.swift").read_text()
        support = support.replace("// DISPLAY_CADENCE_METHODS", "\n".join([
            next(line for line in screen.splitlines() if "static let conservativeCadenceLimit:" in line),
            method(screen, "static func hasSameGeometry(_ lhs: [Self], _ rhs: [Self]) -> Bool"),
            method(screen, "static func cadenceLimit(for screens: [Self]) -> Double"),
        ]))
        source = support.replace("// EVENTS", "\n".join(method(events, signature) for signature in (
            "private func handleCandidatePrepared(_ payload: [String: Any])",
            "private func handleFirstFrame(_ payload: [String: Any])",
            "func handleLaunchState(_ payload: [String: Any])",
            "func handleTermination(status: Int32, generation: UInt64)",
        )))
        topology = (IPC / "SceneDaemonClient+DisplayConfiguration.swift").read_text()
        source += "\nextension SceneDaemonClient {\n" + "\n".join(method(topology, signature) for signature in (
            "var configuredWallpaperScreens: [NSScreen]",
            "func updateDisplayConfiguration(multiDisplayEnabled: Bool)",
            "func flushDeferredDisplayConfigurationUpdate()",
            "private func installDisplayConfiguration(_ configuration: [SceneScreenTopology])",
        )) + "\n}\n" + HARNESS
        with tempfile.TemporaryDirectory(prefix="mwx-scene-endpoint-") as directory:
            directory = Path(directory)
            harness = directory / "Harness.swift"
            harness.write_text(source)
            shared = []
            for name in ("WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift", "PlaybackPerformanceProfile.swift"):
                path = directory / name
                path.write_bytes((ROOT / "MyWallpaperX/Core/PlaybackControl" / name).read_bytes())
                shared.append(str(path))
            for debug in (False, True):
                executable = directory / ("debug" if debug else "product")
                command = ["swiftc", "-swift-version", "6", "-parse-as-library"]
                if debug:
                    command += ["-D", "DEBUG"]
                command += [
                    *shared,
                    str(ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift"),
                 str(IPC / "SceneDaemonClient+SwitchEndpoint.swift"), str(harness), "-o", str(executable),
                ]
                built = subprocess.run(command, capture_output=True, text=True, timeout=60)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
                result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("scene-switch-endpoint-ok", result.stdout)

    def test_output_activity_keeps_frame_and_applies_current_pause_mute_input_media(self):
        session = (SESSION / "SceneDesktopWallpaperSession.swift").read_text()
        providers = (SESSION / "SceneDesktopWallpaperSession+VideoProviders.swift").read_text()
        host = (SESSION / "SceneDesktopWallpaperHost.swift").read_text()
        support = r'''
import Foundation
import QuartzCore
@MainActor final class PlaybackMuteState {static let shared=PlaybackMuteState();var isMuted=false}
@MainActor final class SceneSystemMediaDemandRegistry {
    static let shared=SceneSystemMediaDemandRegistry();var consumers:Set<UUID>=[]
    func acquire(_ id:UUID,requestID:UUID){consumers.insert(id)}
    func release(_ id:UUID){consumers.remove(id)}
}
final class Sound {var muted=false;var paused=false;func setMuted(_ value:Bool){muted=value}
    func pause(){paused=true};func resume(){paused=false}}
final class Clock {var isPaused=false;func pause(hostTime:Double){isPaused=true}
    func resume(hostTime:Double){isPaused=false};func currentSceneTime(hostTime:Double)->Double{0}}
final class Video {func pause(hostTime:Double){};func resume(hostTime:Double){}}
struct LayerTopology {var destroyedAuthoredLayerIDs:Set<Int>=[];func snapshot()->Self{self}}
struct Context {
    var usesSystemMedia=true
    var sceneScriptDynamicLayerRuntime=LayerTopology()
    func requiresSystemMedia(excludingLayerIDs:Set<Int>)->Bool{usesSystemMedia}
}
final class Surface {var pendingPausedFrame:Int?}
@MainActor final class SceneDesktopWallpaperSession {
    let lifecycleID=UUID();var launchRequestID:UUID?=UUID()
    var launchContext:Context?=Context();var isVisible=true;var isOutputActive=true
    var soundPlaybackRegistry:Sound?=Sound();var videoTextureSourceRegistry:Video?=Video()
    let sceneClock=Clock();var pausedFrameRetryDeadline:Double?
    var surfaces:[Int:Surface]=[:];var frameTimer:Timer?;var frameDriverDeadline:Double?
    var monitors=true
    func installPointerEventMonitorsIfNeeded(){monitors=isVisible && isOutputActive}
    func removePointerEventMonitors(){monitors=false}
    func startFrameDriver(){}
    // SESSION
}
@MainActor final class SceneDesktopWallpaperHost {
    var activeSession:SceneDesktopWallpaperSession?
    var candidateSession:SceneDesktopWallpaperSession?
    var unconfirmedPromotion:(requestID:UUID,previous:SceneDesktopWallpaperSession?)?
    var playbackPaused=false
    func reconcileAudioDemand(){}
    // HOST
}
@main enum Harness {
    @MainActor static func main() {
        let host=SceneDesktopWallpaperHost(),session=SceneDesktopWallpaperSession()
        host.activeSession=session
        let id=session.launchRequestID!
        precondition(host.setOutputActive(false,requestID:id))
        precondition(session.isVisible && !session.isOutputActive && session.sceneClock.isPaused
            && session.soundPlaybackRegistry!.muted && !session.monitors
            && !SceneSystemMediaDemandRegistry.shared.consumers.contains(session.lifecycleID),
            "deactivation freezes visible output and revokes audio/input/media")
        host.setPlaybackPaused(false)
        host.setMuted(false)
        precondition(session.sceneClock.isPaused && session.soundPlaybackRegistry!.muted,
            "policy broadcasts cannot resume or unmute a deactivated output")
        host.setPlaybackPaused(true);PlaybackMuteState.shared.isMuted=true
        precondition(host.setOutputActive(true,requestID:id))
        precondition(session.sceneClock.isPaused && session.soundPlaybackRegistry!.muted
            && session.monitors && SceneSystemMediaDemandRegistry.shared.consumers.contains(session.lifecycleID),
            "restoration uses current user pause/mute and reacquires input/media")
        precondition(!host.setOutputActive(false,requestID:UUID()) && session.isOutputActive,
            "foreign request cannot change active output")
        session.launchContext?.usesSystemMedia=false
        session.reconcileSystemMediaDemand()
        precondition(!SceneSystemMediaDemandRegistry.shared.consumers.contains(session.lifecycleID),
            "last consumer change releases the existing visible-session lease")
        session.launchContext?.usesSystemMedia=true
        session.reconcileSystemMediaDemand()
        precondition(SceneSystemMediaDemandRegistry.shared.consumers.contains(session.lifecycleID),
            "consumer recovery reacquires the same visible-session lease")
        print("scene-output-activity-ok")
    }
}
'''
        support = support.replace("// SESSION", "\n".join((
            method(session, "func setOutputActive(_ active: Bool, playbackPaused: Bool)"),
            method(session, "func reconcileSystemMediaDemand(requestID: UUID? = nil)"),
            method(providers, "func setPlaybackPaused(_ paused: Bool)"),
        )))
        support = support.replace("// HOST", "\n".join((
            method(host, "func setOutputActive(_ active: Bool, requestID: UUID) -> Bool"),
            method(host, "func setPlaybackPaused(_ paused: Bool)"),
            method(host, "func setMuted(_ muted: Bool)"),
        )))
        with tempfile.TemporaryDirectory(prefix="mwx-scene-output-activity-") as directory:
            directory = Path(directory)
            source = directory / "Harness.swift"
            source.write_text(support)
            executable = directory / "harness"
            built = subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library",
                                    str(source), "-o", str(executable)],
                                   capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("scene-output-activity-ok", result.stdout)


if __name__ == "__main__":
    unittest.main()
