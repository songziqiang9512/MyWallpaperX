"""Execute the real Scene client cancellation and first-present admission methods."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from script.tests.test_scene_wallpaper_async_launch import function_body


ROOT = Path(__file__).resolve().parents[2]
IPC = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC"


def method(source: str, signature: str) -> str:
    return signature.removeprefix("private ") + " " + function_body(source, signature)


SUPPORT = r'''
import CoreFoundation
import Foundation
@MainActor final class DaemonPlaybackProcessRegistry {static let shared=DaemonPlaybackProcessRegistry();var acceptsNewProcesses=true}
struct Property {let foundationValue:Int}
struct TextureReference {let url:URL;var bookmarkData:Data?=nil}
struct ScenePlaybackLoadRequest {
    let recordID:String?;var rootURL=URL(fileURLWithPath:"/version");var source:ScenePlaybackSource?=nil
    var propertyOverrides:[String:Property]=[:];var userPropertyTextures:[String:TextureReference]=[:]
    var userShortcuts=0;var requiredUserTextureKeys:Set<String>=[]
}
final class PlaybackResourceLifetime {var onDeinit:(()->Void)?;deinit{onDeinit?()}}
final class DaemonProcessTransport {
    var isRunning=true;var terminations=0;var gracefulStops=0
    func terminate(){terminations += 1};func closeIO(){}
    func requestGracefulStop(_ value:Data?){gracefulStops += 1}
}
struct Reachability {}
struct SceneWallpaperLaunchState {
    enum Phase { case cancelled,stopped,failed }
    let requestID:UUID;let recordID:String?;let phase:Phase;let message:String
}
struct SceneFramePresentation { let requestID:UUID;let recordID:String?;let uptimeMicros:UInt64 }
extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange=Notification.Name("state")
    static let sceneWallpaperFirstFrameDidPresent=Notification.Name("frame")
}
struct Backoff { var resets=0;mutating func reset(){resets += 1} }
enum Outcome { case superseded,failed(String) }
@MainActor final class PlaybackVolumeState {static let shared=PlaybackVolumeState();var normalizedVolume:Float=0.5}
@MainActor final class PlaybackMuteState {static let shared=PlaybackMuteState();var isMuted=false}
enum SceneDaemonProtocol {
    static let version=2
    static func sourceObject(_ source:ScenePlaybackSource)throws->[String:Any] {
        try JSONSerialization.jsonObject(with:JSONEncoder().encode(source)) as! [String:Any]
    }
    static func shortcutObject(_ value:Int)->[String:Any]{[:]}
    // PROTOCOL_BOOLEAN
}
@MainActor final class SceneDaemonClient {
    struct Lifetime {
        let lifetime:PlaybackResourceLifetime
        var rootURL=URL(fileURLWithPath:"/version")
        var recordID:String?
        var source:ScenePlaybackSource?
        init(lifetime:PlaybackResourceLifetime,recordID:String?=nil) {self.lifetime=lifetime;self.recordID=recordID}
    }
    struct Facts { let transportGeneration:UInt64;let requestID:UUID;let recordID:String?;let reachability:Reachability }
    var activeIntent:ScenePlaybackLoadRequest?
    var pendingIntent:ScenePlaybackLoadRequest?
    var activeSwitchTicket:PlaybackSwitchTicket?
    var pendingSwitchTicket:PlaybackSwitchTicket?
    var activeSwitchExecution:SwitchExecution?
    var pendingSwitchExecution:SwitchExecution?
    var switchControls:[UUID:SwitchControl]=[:]
    var queuedSwitchPreparation:QueuedSwitchPreparation?
    var committedSwitchRecovery:CommittedSwitchRecovery?
    var switchPrepared:((PlaybackSwitchTicket,PlaybackSwitchEndpoint)->Void)?
    var switchVisible:((PlaybackSwitchTicket,UUID)->Void)?
    var switchFailed:((PlaybackSwitchTicket,String)->Void)?
    var switchLost:((PlaybackSwitchTicket,String)->Void)?
    var transport:DaemonProcessTransport?
    var activeResourceLifetime:Lifetime?
    var pendingResourceLifetime:Lifetime?
    var activeRecordID:String?
    var activeRequestID:UUID?
    var pendingRequestID:UUID?
    var pendingPresentationRequestID:UUID?
    var pendingPresentationReachability:Reachability?
    var activeCallbackPropertyFacts:Facts?
    var requestResourceLifetimes:[UUID:PlaybackResourceLifetime]=[:]
    var pendingPropertyRevisions:[UInt64:String]=[:]
    var requestRetirementSchemaVersion:Int?
    var idleTransport:IdleTransport?
    var sourceSchemaVersion:Int?
    var endpointReady=false
    var warmSessionPending=false
    var debugStartupObserver:((SceneDaemonStartupObservation)->Void)?
    var debugStartupPrefixObserver:((SceneDaemonStartupPrefixObservation)->Void)?
    var debugStartupWireObserver:((UInt64,Int32?,UInt64,[String:Any])->Void)?
    var outputFrames=DaemonNewlineFrameBuffer()
    var debugProcessIdentifier:Int32? {123}
    var lastPropertyRevision:UInt64=0
    var latestTextureRevisions:[String:UInt64]=[:]
    var restartWorkItem:DispatchWorkItem?
    var handshakeWorkItem:DispatchWorkItem?
    var expectedTerminationGenerations:Set<UInt64>=[]
    var retiringTransports:[UInt64:DaemonProcessTransport]=[:]
    var retiringResourceLifetimes:[UInt64:[PlaybackResourceLifetime]]=[:]
    var spawns=0
    var performanceProfile=(maxFPS:30,other:0)
    var isPaused=false
    var sessionGeneration:UInt64=7
    var launchState:SceneWallpaperLaunchState?
    var sent:[[String:Any]]=[]
    var stopped=false
    var retiredLeases:[PlaybackResourceLifetime]=[]
    var restartBackoff=Backoff()
    var resumed:[UUID]=[]
    func send(_ value:[String:Any]) { sent.append(value) }
    func finishPendingTextureUpdates(_ result:Outcome) {}
    func finishPendingShortcutUpdates(_ outcome: Outcome) {}
    func stop() {
        discardIdleTransport();requestRetirementSchemaVersion=nil
        stopped=true;endpointReady=false
        retiredLeases += requestResourceLifetimes.values
        if let pendingResourceLifetime { retiredLeases.append(pendingResourceLifetime.lifetime) }
        requestResourceLifetimes=[:];pendingIntent=nil;pendingResourceLifetime=nil
        pendingRequestID=nil;pendingPresentationRequestID=nil;pendingPresentationReachability=nil
    }
    func fallbackReplayIntent(requestID:UUID)->ScenePlaybackLoadRequest? { nil }
    func ensureSession()->Bool {false}
    func spawnSession(silentHandshakeFailure:Bool)->Bool {
        spawns += 1;transport=DaemonProcessTransport();endpointReady=true;return true
    }
    func replayPendingIntent() {}
    func sendSimpleCommand(_ command:String){send(["cmd":command])}
    func sendDisplayConfiguration(){}
    func finishShutdownIfPossible(){}
    var restartReasons:[String]=[]
    func scheduleRestart(reason:String){restartReasons.append(reason)}
    func handleLaunchState(_ value:[String:Any]) {fatalError("unexpected managed failure")}
    func retainResourceLifetime(_ value:PlaybackResourceLifetime?,rootURL:URL,recordID:String?,source:ScenePlaybackSource?=nil) {
        pendingResourceLifetime=value.map{Lifetime(lifetime:$0,recordID:recordID)}
    }
    func failPendingFrameCaptures() {}
    func revokeAudioSpectrumDemand(generation:UInt64) {}
    func revokeSystemMediaDemand(generation:UInt64) {}
    var latestFrameStats:Int?
    func flushDeferredDisplayConfigurationUpdate() {}
    func resumeDeferredTextureUpdates(recordID:String?,requestID:UUID) { resumed.append(requestID) }
    static func double(_ raw:Any?)->Double? { raw as? Double }
'''

TAIL = r'''
}
@main enum Harness {
    @MainActor static func main() throws {
        let a=UUID(),b=UUID()
        let lifetime=PlaybackResourceLifetime()
        func pending(_ client:SceneDaemonClient) {
            client.pendingIntent = .init(recordID:"B")
            client.pendingRequestID=b
            client.pendingResourceLifetime = .init(lifetime:lifetime)
            client.requestResourceLifetimes[b]=lifetime
        }
        var checks:[String:Bool]=[:]
        let cold=SceneDaemonClient();pending(cold)
        cold.cancelPreparationForRuntimeSwitch()
        checks["coldCancellationRetiresBeforeHello"] = cold.stopped && cold.pendingIntent == nil && cold.pendingRequestID == nil
        checks["coldCancellationPinsLeaseUntilExit"] = cold.retiredLeases.contains { $0 === lifetime }
        cold.handleCandidatePrepared(["requestID":b.uuidString])
        checks["latePreparedCannotReplayColdLaunch"] = cold.sent.isEmpty
        let beforeHello=SceneDaemonClient();pending(beforeHello);beforeHello.pendingRequestID=nil
        beforeHello.cancelPreparationForRuntimeSwitch()
        checks["beforeHelloCancellationPublishesTerminalRecord"] = beforeHello.stopped
            && beforeHello.pendingIntent == nil && beforeHello.launchState?.recordID == "B"

        let client=SceneDaemonClient();client.endpointReady=true
        client.activeIntent = .init(recordID:"A");client.activeRecordID="A";client.activeRequestID=a
        pending(client)
        client.handleCandidatePrepared(["requestID":UUID().uuidString])
        checks["wrongPreparedCannotCommit"] = client.sent.isEmpty
        client.handleCandidatePrepared(["requestID":b.uuidString])
        checks["matchingPreparedRequestsCommit"] = client.sent.last?["cmd"] as? String == "commitCandidate"
        client.pendingPresentationRequestID=b;client.pendingPresentationReachability=Reachability()
        client.cancelPreparationForRuntimeSwitch()
        checks["cancelAfterChildCommitKeepsPreviousTruth"] = !client.stopped && client.activeRequestID == a && client.pendingIntent == nil
        checks["cancelCommandsExactCandidate"] = client.sent.last?["cmd"] as? String == "cancelCandidate" && client.sent.last?["requestID"] as? String == b.uuidString
        checks["cancelledLeaseAwaitsChildDrain"] = client.requestResourceLifetimes[b] === lifetime
        let count=client.sent.count
        client.handleFirstFrame(["requestID":b.uuidString,"recordID":"B","uptimeMs":1.0])
        client.handleCandidatePrepared(["requestID":b.uuidString])
        checks["latePresentationCannotCommitRevokedCandidate"] = client.activeRequestID == a && client.sent.count == count && client.resumed.isEmpty

        pending(client);client.pendingPresentationRequestID=b;client.pendingPresentationReachability=Reachability()
        client.handleFirstFrame(["requestID":b.uuidString,"recordID":"B","uptimeMs":2.0])
        checks["realPresentationCommitsMatchingPending"] = client.activeRequestID == b && client.activeRecordID == "B" && client.pendingIntent == nil && client.pendingRequestID == nil
        checks["realPresentationFinalizesStandby"] = client.sent.last?["cmd"] as? String == "finalizeCandidate" && client.resumed == [b]
        let confirmedCount=client.sent.count
        client.cancelPreparationForRuntimeSwitch()
        checks["newIntentRetainsAlreadyConfirmedScene"] = client.activeRequestID == b && client.sent.count == confirmedCount && !client.stopped
        client.activeResourceLifetime = .init(lifetime:lifetime,recordID:"B")
        client.requestLaunch(.init(recordID:"B"))
        checks["sameVersionRebuildInheritsActiveLease"] = client.pendingResourceLifetime?.lifetime === lifetime
        client.cancelPreparationForRuntimeSwitch()
        var foreign=ScenePlaybackLoadRequest(recordID:"C");foreign.rootURL=URL(fileURLWithPath:"/foreign")
        client.requestLaunch(foreign)
        checks["foreignVersionDoesNotBorrowActiveLease"] = client.pendingResourceLifetime == nil
        let visibleTicket=PlaybackSwitchTicket(epoch:5,id:UUID(),runtime:.scene)
        let newerTicket=PlaybackSwitchTicket(epoch:6,id:UUID(),runtime:.scene)
        let queuedClient=SceneDaemonClient();queuedClient.endpointReady=true
        queuedClient.transport=DaemonProcessTransport()
        queuedClient.activeIntent = .init(recordID:"A");queuedClient.activeSwitchTicket=visibleTicket
        queuedClient.pendingIntent = .init(recordID:"B");queuedClient.pendingSwitchTicket=visibleTicket
        queuedClient.pendingRequestID=b
        let execution=SceneDaemonClient.SwitchExecution(ticket:visibleTicket,requestID:b,
            generation:queuedClient.sessionGeneration,transport:queuedClient.transport!)
        execution.presented=true;queuedClient.pendingSwitchExecution=execution
        queuedClient.prepareSwitch(.init(recordID:"C"),ticket:newerTicket,resourceLifetime:nil)
        queuedClient.requestLaunch(.init(recordID:"B"))
        checks["internalRebuildCannotOverwriteNewerQueuedProduct"] = queuedClient.queuedSwitchPreparation?.ticket == newerTicket
            && queuedClient.queuedSwitchPreparation?.request.recordID == "C" && queuedClient.pendingRequestID == b
        let measured=SceneDaemonClient();pending(measured);measured.endpointReady=true
        measured.transport=DaemonProcessTransport();measured.pendingSwitchTicket=visibleTicket
        var observations:[SceneDaemonStartupObservation]=[]
        measured.debugStartupObserver={ observations.append($0) }
        var endpoint:PlaybackSwitchEndpoint?
        measured.switchPrepared={ _,value in endpoint=value }
        measured.handleCandidatePrepared(["requestID":UUID().uuidString])
        checks["startupObserverRejectsWrongPrepared"]=observations.isEmpty
        measured.handleCandidatePrepared(["requestID":b.uuidString])
        measured.handleCandidatePrepared(["requestID":b.uuidString])
        checks["startupObserverPreparedOnce"]=observations.count == 1
            && observations.first?.phase == .prepared && observations.first?.requestID == b
            && observations.first?.ticketID == visibleTicket.id
            && observations.first?.transportGeneration == measured.sessionGeneration
            && observations.first?.daemonPID == 123
        endpoint?.finalize()
        checks["startupObserverCannotFinalizeBeforePresentation"]=observations.count == 1
        measured.pendingSwitchExecution?.presented=true
        endpoint?.finalize();endpoint?.finalize()
        checks["startupObserverFinalizesExactExecutionOnce"]=observations.count == 2
            && observations.last?.phase == .parentFinalized
            && observations.last?.executionID == observations.first?.executionID
            && measured.activeRequestID == b
        var prefix:[SceneDaemonStartupPrefixObservation]=[]
        measured.debugStartupPrefixObserver={prefix.append($0)}
        measured.prepareSwitch(.init(recordID:"C"),ticket:newerTicket,resourceLifetime:nil)
        checks["prefixPreparationUsesIncomingNotOldPendingTicket"]=prefix.count == 1
            && prefix[0].phase == .preparationReceived && prefix[0].ticketID == newerTicket.id
            && prefix[0].intentEpoch == newerTicket.epoch && prefix[0].requestID == nil
            && measured.pendingSwitchTicket == newerTicket
        measured.pendingRequestID=b
        measured.observeDebugStartupPrefix(.loadEnqueueAttempted)
        checks["prefixLoadUsesExistingWireIdentityOnly"]=prefix.count == 2
            && prefix[1].phase == .loadEnqueueAttempted && prefix[1].requestID == b
            && prefix[1].transportGeneration == measured.sessionGeneration && prefix[1].daemonPID == 123
            && prefix[0].uptimeMicros <= prefix[1].uptimeMicros
        let wireCount=measured.sent.count
        measured.debugStartupPrefixObserver=nil
        measured.observeDebugStartupPrefix(.helloObserved)
        checks["removedPrefixObserverHasNoCallbackOrWireEffect"]=prefix.count == 2 && measured.sent.count == wireCount
        let helloJSON = #"{"schemaVersion":1,"pid":123,"entryObserved":10,"appKitBegin":11,"appKitReturned":12,"runtimeBegin":13,"runtimeReturned":14,"helloSnapshotCaptured":15}"#
        let helloValues=try JSONSerialization.jsonObject(with:Data(helloJSON.utf8)) as! [String:Any]
        let decoded=SceneDaemonClient.debugStartupUptimes(helloValues)
        checks["helloChildIntegersUseActualStrictDecoder"]=decoded?.count == 8
            && decoded?["pid"] == 123 && decoded?["runtimeReturned"] == 14
        checks["missingOrNonDictionaryChildPayloadCannotQualify"]=SceneDaemonClient.debugStartupUptimes(nil) == nil
            && SceneDaemonClient.debugStartupUptimes("invalid") == nil
        var malformed=helloValues;malformed.removeValue(forKey:"runtimeBegin")
        checks["missingChildKeyIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["extra"]=1
        checks["extraChildKeyIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["entryObserved"]=true
        checks["booleanChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["schemaVersion"]=NSNumber(value:1.0)
        checks["integralDoubleChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["entryObserved"]=NSNumber(value:Float(10))
        checks["integralFloatChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["entryObserved"] = -1
        checks["negativeChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["entryObserved"]="10"
        checks["stringChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        malformed=helloValues;malformed["entryObserved"]=NSNumber(value:Double.greatestFiniteMagnitude)
        checks["overflowingChildValueIsRejected"]=SceneDaemonClient.debugStartupUptimes(malformed) == nil
        measured.observeDebugStartupPrefix(.helloObserved,childStartupUptimes:decoded)
        checks["removedObserverCannotRetainChildPayloadOrSend"]=prefix.count == 2 && measured.sent.count == wireCount
        measured.debugStartupPrefixObserver={prefix.append($0)}
        measured.observeDebugStartupPrefix(.helloObserved,childStartupUptimes:decoded)
        checks["childValuesTravelOnSameTicketGenerationAndPID"]=prefix.count == 3
            && prefix.last?.childStartupUptimes == decoded && decoded != nil
            && prefix.last?.ticketID == newerTicket.id && prefix.last?.intentEpoch == newerTicket.epoch
            && prefix.last?.transportGeneration == measured.sessionGeneration && prefix.last?.daemonPID == 123
            && prefix.last?.phase == .helloObserved && prefix.last?.requestID == nil
            && measured.sent.count == wireCount
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:.sortedKeys),encoding:.utf8)!)
    }
}
'''


IDLE_TAIL = r'''
}
@main enum Harness {
    @MainActor static func main() throws {
        var checks:[String:Bool]=[:]
        let registry=DaemonPlaybackProcessRegistry.shared
        let web=PlaybackSwitchTicket(epoch:2,id:UUID(),runtime:.web)
        let next=PlaybackSwitchTicket(epoch:3,id:UUID(),runtime:.scene)
        func active()->(SceneDaemonClient,PlaybackSwitchEndpoint,UUID,DaemonProcessTransport) {
            let client=SceneDaemonClient(),request=UUID(),child=DaemonProcessTransport()
            let ticket=PlaybackSwitchTicket(epoch:1,id:UUID(),runtime:.scene)
            client.transport=child;client.endpointReady=true;client.requestRetirementSchemaVersion=1
            client.pendingIntent = .init(recordID:"A");client.pendingRequestID=request;client.pendingSwitchTicket=ticket
            client.pendingResourceLifetime = .init(lifetime:PlaybackResourceLifetime(),recordID:"A")
            client.requestResourceLifetimes[request]=client.pendingResourceLifetime!.lifetime
            var endpoint:PlaybackSwitchEndpoint?
            client.switchPrepared={_,value in endpoint=value}
            _=client.reportPreparedSwitch(requestID:request)
            client.pendingSwitchExecution!.presented=true;endpoint!.finalize();client.sent=[]
            return (client,endpoint!,request,child)
        }
        func ack(_ client:SceneDaemonClient,_ request:UUID,_ operation:String,retired:Any?=true,
                 accepted:Any=true,generation:UInt64=7) {
            var payload:[String:Any]=["operationID":operation,"requestID":request.uuidString,"accepted":accepted]
            if let retired {payload["requestRetired"]=retired}
            client.handleSwitchControlResult(payload,generation:generation)
        }
        func operation(_ client:SceneDaemonClient)->String {client.sent.last!["operationID"] as! String}
        func exit(_ client:SceneDaemonClient,_ child:DaemonProcessTransport) {
            child.isRunning=false;client.handleTermination(status:0,generation:7)
        }
        func demand(_ client:SceneDaemonClient,_ requires:Bool,_ epoch:UInt64) {
            client.handleAudioSpectrumDemand(["requiresSpectrum":requires,
                "includesDaemonProcessOutput":false,"scopeEpoch":epoch],generation:7)
        }
        let (rollback,_,_,rollbackChild)=active()
        rollback.invalidateRetainedTransport(for:.web)
        checks["newNonSceneIntentPreservesCommittedRollbackOutput"]=rollback.activeIntent?.recordID == "A"
            && rollback.transport === rollbackChild && rollbackChild.gracefulStops == 0
            && !rollback.hasRetainedOrRetiringTransport
        rollback.stop();exit(rollback,rollbackChild)
        let (invalidated,invalidatedEndpoint,invalidatedRequest,invalidatedChild)=active()
        var invalidatedDone=0
        invalidatedEndpoint.retire(web){invalidatedDone += 1}
        let invalidatedOperation=operation(invalidated)
        invalidated.invalidateRetainedTransport(for:.scene)
        checks["sceneIntentPreservesInFlightRetirementForAdoption"]=invalidated.hasRequestRetirementControl
            && invalidated.transport === invalidatedChild && invalidatedChild.gracefulStops == 0
        invalidated.invalidateRetainedTransport(for:.video)
        ack(invalidated,invalidatedRequest,invalidatedOperation)
        checks["newNonSceneIntentRevokesStrongRetentionAndLateAck"]=invalidatedDone == 0
            && invalidated.transport == nil && invalidated.idleTransport == nil
            && invalidatedChild.gracefulStops == 1 && invalidated.hasRetainedOrRetiringTransport
        exit(invalidated,invalidatedChild)
        checks["retiringPredicateClearsOnlyAtPhysicalExit"]=invalidatedDone == 1
            && !invalidated.hasRetainedOrRetiringTransport
        let otherRuntimes:[WallpaperRuntimeKind?]=[.web,.video,.systemStill,nil]
        for runtime in otherRuntimes {
            let (client,endpoint,request,child)=active()
            endpoint.retire(web){};ack(client,request,operation(client))
            let token=client.idleTransport!
            client.invalidateRetainedTransport(for:.scene)
            checks["scenePreservesIdle_"+String(describing:runtime)]=client.idleTransport === token
                && child.gracefulStops == 0 && client.hasRetainedOrRetiringTransport
            client.invalidateRetainedTransport(for:runtime)
            token.deadline?.perform()
            checks["nonSceneRetiresIdle_"+String(describing:runtime)]=client.transport == nil
                && client.idleTransport == nil && child.gracefulStops == 1
                && client.hasRetainedOrRetiringTransport
            exit(client,child)
            checks["idleExitEndsOptionalSuppression_"+String(describing:runtime)] = !client.hasRetainedOrRetiringTransport
        }
        let (a,ea,ra,ca)=active();weak var oldLease=a.activeResourceLifetime?.lifetime
        let audio=WallpaperEngine.shared
        demand(a,true,1)
        checks["activeScopeCanRequestSpectrum"]=audio.demands.last?.0.scopeEpoch == 1
            && audio.demands.last?.0.requiresSpectrum == true
        var retiredA=0;ea.retire(web){retiredA += 1}
        let opa=operation(a)
        let pendingAudioCount=audio.demands.count
        demand(a,true,1)
        checks["retirementRejectsLatePositiveSpectrum"]=audio.demands.count == pendingAudioCount
            && !a.audioSpectrumDemand.requiresSpectrum && a.audioSpectrumDemandGeneration == nil
            && audio.demands.last?.0 == SceneAudioSpectrumCaptureDemand.none
        demand(a,false,0)
        checks["retirementStillAcceptsCurrentNone"]=audio.demands.count == pendingAudioCount + 1
            && a.audioSpectrumDemand == .none && a.audioSpectrumDemandGeneration == 7
        checks["qualifiedHandoffUsesSameRequestAndControl"]=retiredA == 0 && a.switchControls.count == 1
            && a.sent.last?["cmd"] as? String == "retireOutput"
            && a.sent.last?["requireRequestRetirement"] as? Bool == true
            && a.sent.last?["requestID"] as? String == ra.uuidString && a.activeIntent == nil
            && a.transport === ca && ca.gracefulStops == 0
        a.requestResourceLifetimes.removeValue(forKey:ra)
        checks["strongControlRetainsOldLeaseDespiteOrdinaryRelease"]=oldLease != nil
        ack(a,ra,UUID().uuidString);ack(a,UUID(),opa);ack(a,ra,opa,generation:6)
        checks["foreignAckCannotCreateIdle"]=retiredA == 0 && a.idleTransport == nil && a.switchControls.count == 1
        var cancelledQueued=false
        let b=PlaybackSwitchTicket(epoch:2,id:UUID(),runtime:.scene)
        a.prepareSwitch(.init(recordID:"B"),ticket:b,resourceLifetime:PlaybackResourceLifetime())
        a.cancelSwitch(ticket:b){cancelledQueued=true}
        a.prepareSwitch(.init(recordID:"C"),ticket:next,resourceLifetime:PlaybackResourceLifetime())
        a.replayPendingIntent()
        checks["queueAndCancellationDoNotSendLoadBeforeRetirement"]=cancelledQueued
            && a.queuedSwitchPreparation?.ticket == next
            && !a.sent.contains{$0["cmd"] as? String == "loadScene"}
        ack(a,ra,opa)
        let newRequest=a.pendingRequestID
        checks["successfulRetirementAdoptsSameProcessWithFreshRequest"]=retiredA == 1 && oldLease == nil
            && a.switchControls.isEmpty && a.idleTransport == nil && a.transport === ca
            && a.sessionGeneration == 7 && a.pendingIntent?.recordID == "C"
            && newRequest != nil && newRequest != ra && a.spawns == 0
            && a.sent.filter{$0["cmd"] as? String == "loadScene"}.count == 1
        ack(a,ra,opa)
        checks["duplicateAckDoesNotReplayOrFinishTwice"]=retiredA == 1 && a.pendingRequestID == newRequest
        a.stop();exit(a,ca)

        let (legacy,el,rl,cl)=active();var legacyDone=false;el.retire(web){legacyDone=true}
        let opl=operation(legacy);legacy.requestLaunch(.init(recordID:"legacy"));legacy.replayPendingIntent()
        checks["legacyLoadUsesOriginalQueueAndWaits"]=legacy.queuedSwitchPreparation?.ticket == nil
            && legacy.queuedSwitchPreparation?.request.recordID == "legacy" && legacy.pendingRequestID == nil
            && !legacy.sent.contains{$0["cmd"] as? String == "loadScene"}
        ack(legacy,rl,opl)
        checks["legacyLoadResumesOnlyAfterPositiveRetirement"]=legacyDone && legacy.transport === cl
            && legacy.pendingIntent?.recordID == "legacy" && legacy.pendingRequestID != nil && legacy.spawns == 0
        legacy.stop();exit(legacy,cl)

        for (name,value) in [("missing",nil),("false",false as Any?),("numeric",1 as Any?)] {
            let (client,endpoint,request,child)=active();var done=0
            endpoint.retire(web){done += 1};let op=operation(client)
            ack(client,request,op,retired:value)
            checks["unqualifiedAckWaitsForExit_"+name]=done == 0 && client.idleTransport == nil
                && child.terminations == 1 && client.switchControls.count == 1
            exit(client,child)
            checks["physicalExitSettlesFailedRetirement_"+name]=done == 1 && client.switchControls.isEmpty
                && client.transport == nil && client.idleTransport == nil
        }
        let (old,eo,_,co)=active();old.requestRetirementSchemaVersion=nil;var oldDone=false
        eo.retire(web){oldDone=true}
        checks["oldChildUsesOriginalPhysicalExit"]=old.transport == nil && co.gracefulStops == 1 && !oldDone
        exit(old,co);checks["oldChildCompletesAfterExit"]=oldDone
        let (normal,en,_,cn)=active();var normalDone=false;en.retire(nil){normalDone=true}
        checks["ordinaryRetireNeverBecomesIdle"]=normal.transport == nil && cn.gracefulStops == 1 && !normalDone
        exit(normal,cn);checks["ordinaryRetireWaitsForPhysicalExit"]=normalDone

        let (idle,ei,ri,ci)=active();var idleDone=false;ei.retire(web){idleDone=true};ack(idle,ri,operation(idle))
        let oldToken=idle.idleTransport!,oldTimer=oldToken.deadline!
        let idleAudioCount=audio.demands.count
        demand(idle,true,11)
        checks["idleRejectsLatePositiveSpectrum"]=audio.demands.count == idleAudioCount
            && !idle.audioSpectrumDemand.requiresSpectrum
        demand(idle,false,0)
        checks["idleStillAcceptsCurrentNone"]=audio.demands.count == idleAudioCount + 1
            && idle.audioSpectrumDemand == .none && idle.audioSpectrumDemandGeneration == 7
        checks["positiveAckCreatesOneBoundedIdleIdentity"]=idleDone && idle.idleTransport?.transport === ci
            && idle.activeIntent == nil && idle.pendingIntent == nil && idle.switchControls.isEmpty
        idle.prepareSwitch(.init(recordID:"new"),ticket:next,resourceLifetime:PlaybackResourceLifetime())
        oldTimer.perform()
        checks["oldIdleTimerCannotStopAdoptedTransport"]=idle.idleTransport == nil && idle.transport === ci
            && !idle.stopped && idle.pendingIntent?.recordID == "new" && ci.gracefulStops == 0
        demand(idle,true,12)
        checks["newAdoptedScopeCanRequestSpectrum"]=audio.demands.count == idleAudioCount + 2
            && idle.audioSpectrumDemand.scopeEpoch == 12 && idle.audioSpectrumDemand.requiresSpectrum
            && audio.demands.last?.0.scopeEpoch == 12 && audio.demands.last?.1 == 7
        idle.stop();exit(idle,ci)
        let (expiry,ee,re,ce)=active();ee.retire(web){};ack(expiry,re,operation(expiry))
        let expiryTimer=expiry.idleTransport!.deadline!;expiryTimer.perform();expiryTimer.perform()
        checks["exactIdleExpiryUsesOriginalStopOnce"]=expiry.idleTransport == nil && expiry.transport == nil
            && ce.gracefulStops == 1 && expiry.retiringTransports[7] === ce
        exit(expiry,ce)
        let (stopped,es,rs,cs)=active();weak var stoppedLease=stopped.activeResourceLifetime?.lifetime
        var stoppedDone=0;es.retire(web){stoppedDone += 1};let ops=operation(stopped)
        stopped.requestResourceLifetimes.removeValue(forKey:rs);stopped.stop();ack(stopped,rs,ops)
        checks["stopAndLateAckDoNotReleaseControlOrCreateIdle"]=stoppedDone == 0 && stoppedLease != nil
            && stopped.transport == nil && stopped.idleTransport == nil && cs.gracefulStops == 1
        exit(stopped,cs)
        checks["stopReleasesOldControlLeaseOnlyAfterExit"]=stoppedDone == 1 && stoppedLease == nil
        let (reentrant,er,rr,cr)=active()
        let latest=PlaybackSwitchTicket(epoch:4,id:UUID(),runtime:.scene)
        er.retire(web){reentrant.prepareSwitch(.init(recordID:"latest"),ticket:latest,resourceLifetime:nil)}
        let opr=operation(reentrant)
        reentrant.prepareSwitch(.init(recordID:"queued-old"),ticket:next,resourceLifetime:nil)
        ack(reentrant,rr,opr)
        checks["reentrantCompletionCannotReplayOlderQueuedSelection"]=reentrant.pendingIntent?.recordID == "latest"
            && reentrant.pendingSwitchTicket == latest && reentrant.queuedSwitchPreparation == nil
            && reentrant.sent.filter{$0["cmd"] as? String == "loadScene"}.count == 1
        reentrant.stop();exit(reentrant,cr)
        let (closed,ec,rc,cc)=active();ec.retire(web){};registry.acceptsNewProcesses=false
        ack(closed,rc,operation(closed))
        checks["registryCloseCannotCreateOrAdoptIdle"]=closed.transport == nil && closed.idleTransport == nil
            && cc.gracefulStops == 1 && !closed.ensureSession()
        exit(closed,cc);registry.acceptsNewProcesses=true
        let hello=SceneDaemonClient();hello.transport=DaemonProcessTransport()
        var wireCount=0;hello.debugStartupWireObserver={generation,pid,_,_ in
            precondition(generation == 7 && pid == 123);wireCount += 1
        }
        for (name,raw,expected) in [("integer","1",true),("bool","true",false),
            ("float","1.0",false),("string","\"1\"",false),("other","2",false),("negative","-1",false)] {
            let json="{\"v\":2,\"role\":\"scene-daemon\",\"requestRetirementSchemaVersion\":"+raw+"}\n"
            hello.consumeOutput(Data(json.utf8),generation:7)
            checks["helloCapabilityStrict_"+name]=(hello.requestRetirementSchemaVersion == 1) == expected
                && hello.endpointReady
        }
        let observed=wireCount
        hello.consumeOutput(Data("{\"v\":2,\"role\":\"scene-daemon\",\"requestRetirementSchemaVersion\":1}\n".utf8),generation:6)
        checks["originalGenerationAdmissionStillOwnsWireTap"]=wireCount == observed
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:.sortedKeys),encoding:.utf8)!)
    }
}
'''

class SceneDaemonSwitchCancellationTests(unittest.TestCase):

    def test_request_retirement_idle_adoption_queue_and_physical_exit(self):
        client = (IPC / "SceneDaemonClient.swift").read_text()
        events = (IPC / "SceneDaemonClient+Events.swift").read_text()
        protocol = (IPC / "SceneDaemonProtocol.swift").read_text()
        support = SUPPORT.replace("// PROTOCOL_BOOLEAN", method(protocol, "static func boolean(_ raw: Any?) -> Bool?"))
        for signature in ("func ensureSession()->Bool", "func replayPendingIntent()"):
            support = support.replace(signature + " " + function_body(support, signature), "")
        support = support.replace("func stop() " + function_body(support, "func stop()"),
                                  "func stop(){stopped=true;stop(postsLaunchState:false)}")
        signature = "func revokeAudioSpectrumDemand(generation:UInt64)"
        support = support.replace(signature + " " + function_body(support, signature), "")
        support = support.replace("@MainActor final class SceneDaemonClient", r'''
struct SceneAudioSpectrumCaptureDemand:Equatable,Sendable {
    let requiresSpectrum:Bool
    let includesCurrentProcessOutput:Bool
    let scopeEpoch:UInt64
    static let none=Self(requiresSpectrum:false,includesCurrentProcessOutput:false,scopeEpoch:0)
}
@MainActor final class WallpaperEngine {
    static let shared=WallpaperEngine()
    var demands:[(SceneAudioSpectrumCaptureDemand,UInt64)]=[]
    func setSceneDaemonAudioSpectrumDemand(_ demand:SceneAudioSpectrumCaptureDemand,generation:UInt64) {
        demands.append((demand,generation))
    }
}
extension Notification.Name {
    static let sceneDaemonAudioSpectrumDemandDidChange=Notification.Name("audio-demand")
}
@MainActor final class SceneDaemonClient''')
        support = support.replace("    var sourceSchemaVersion:Int?",
            "    var audioSpectrumDemand=SceneAudioSpectrumCaptureDemand.none\n"
            "    var audioSpectrumDemandGeneration:UInt64?\n    var sourceSchemaVersion:Int?")
        actual = [method(client, signature) for signature in (
            "func cancelPreparationForRuntimeSwitch()",
            "func requestLaunch(_ request: ScenePlaybackLoadRequest)",
            "func startLaunch(_ request: ScenePlaybackLoadRequest, ticket: PlaybackSwitchTicket?)",
            "func ensureSession() -> Bool", "func replayPendingIntent()",
            "func stop(postsLaunchState: Bool)",
        )]
        actual += [method(events, signature) for signature in (
            "func handleTermination(status: Int32, generation: UInt64)",
            "func consumeOutput(_ data: Data, generation: UInt64)",
            "private var activeEventAdmission: SceneDaemonEventAdmission",
            "private static func integer(_ raw: Any?) -> Int?",
            "static func unsignedInteger(_ raw: Any?) -> UInt64?",
            "static func debugStartupUptimes(_ raw: Any?) -> [String: UInt64]?",
            "private func handleAudioSpectrumDemand(\n        _ payload: [String: Any],\n        generation: UInt64\n    )",
            "func revokeAudioSpectrumDemand(generation: UInt64)",
        )]
        for name in ("handleCandidatePrepared", "handleFirstFrame", "handleFrameStats",
                     "handlePropertyUpdateResult", "handleTextureUpdateResult", "handleShortcutUpdateResult",
                     "handleFrameCaptured", "handleFrameCaptureFailure"):
            actual.append(f"func {name}(_ payload:[String:Any]){{fatalError(\"unexpected event\")}}")
        for name in ("handleSystemMediaDemand", "handleSystemMediaAcknowledgement", "handleSystemMediaReplayRequest",
                     "handleAudioSpectrumPublication"):
            actual.append(f"func {name}(_ payload:[String:Any],generation:UInt64){{fatalError(\"unexpected event\")}}")
        actual.append("func publishFailure(code:String,message:String){fatalError(message)}")
        admission = method(protocol, "nonisolated struct SceneDaemonEventAdmission: Equatable, Sendable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-idle-retirement-") as directory:
            root = Path(directory)
            source = root / "Harness.swift"
            source.write_text(admission + "\n" + support + "\n".join(actual) + IDLE_TAIL)
            binary = root / "idle"
            shared = [str(ROOT / "MyWallpaperX/Core/PlaybackControl" / name) for name in (
                "WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift")]
            built = subprocess.run(
                ["xcrun", "swiftc", "-swift-version", "6", "-D", "DEBUG", "-parse-as-library",
                 *shared, str(ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift"),
                 str(ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"),
                 str(IPC / "SceneDaemonClient+SwitchEndpoint.swift"), str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)

    def test_pending_revoke_before_hello_after_commit_and_real_presentation(self):
        client = (IPC / "SceneDaemonClient.swift").read_text()
        events = (IPC / "SceneDaemonClient+Events.swift").read_text()
        methods = [
            method(client, "func cancelPreparationForRuntimeSwitch()"),
            method(client, "func requestLaunch(_ request: ScenePlaybackLoadRequest)"),
            method(client, "func startLaunch(_ request: ScenePlaybackLoadRequest, ticket: PlaybackSwitchTicket?)"),
            method(events, "private func handleCandidatePrepared(_ payload: [String: Any])"),
            method(events, "private func handleFirstFrame(_ payload: [String: Any])"),
            method(events, "static func debugStartupUptimes(_ raw: Any?) -> [String: UInt64]?"),
            method(events, "static func unsignedInteger(_ raw: Any?) -> UInt64?"),
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-scene-switch-cancel-") as directory:
            root = Path(directory)
            source = root / "Harness.swift"
            protocol = (IPC / "SceneDaemonProtocol.swift").read_text()
            support = SUPPORT.replace("// PROTOCOL_BOOLEAN", method(protocol, "static func boolean(_ raw: Any?) -> Bool?"))
            source.write_text(support + "\n".join(methods) + TAIL)
            binary = root / "harness"
            shared = []
            for name in ("WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift"):
                path = root / name
                path.write_bytes((ROOT / "MyWallpaperX/Core/PlaybackControl" / name).read_bytes())
                shared.append(str(path))
            compilation = subprocess.run(
                ["xcrun", "swiftc", "-D", "DEBUG", "-parse-as-library",
                 *shared,
                 str(ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift"),
                 str(ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"),
                 str(IPC / "SceneDaemonClient+SwitchEndpoint.swift"), str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            checks = json.loads(result.stdout)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
