"""Execute Scene's actual service admission and parent source/token/wire owners.

Only unrelated product/UI leaves are carriers; metadata parsing, transaction FDs,
registry, source DTO, Client admission, hello and replay methods are real source.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import ROOT, CORE, SOURCES
from script.tests.test_steam_library_interactions import method

IPC = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC'
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift'


def compile_run(test, text, sources=()):
    with tempfile.TemporaryDirectory(prefix='mwx-scene-source-', dir='/private/tmp') as temporary:
        work = Path(temporary)
        swift = work / 'Probe.swift'
        swift.write_text(text)
        built = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, sources),
            str(swift), '-o', str(work / 'probe')], capture_output=True, text=True, timeout=120)
        test.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        run = subprocess.run([str(work / 'probe'), str(work / 'library')],
            capture_output=True, text=True, timeout=15)
        test.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        facts = json.loads(run.stdout)
        for name, value in facts.items():
            with test.subTest(fact=name):
                test.assertTrue(value)
        return facts


class SceneSourceAdmissionTests(unittest.TestCase):
    def test_synchronous_admission_preserves_intent_lease_and_reentry(self):
        """Execute the real frontend and ticket claim without a migration task."""
        reclamation = (CORE / 'SteamWorkshopService+LibraryReclamation.swift').read_text()
        manager = (ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+RuntimeSwitching.swift').read_text()
        app = (ROOT / 'MyWallpaperX/App/MyWallpaperXApplication.swift').read_text()
        scene = CORE.parent / 'Scene/SteamWorkshopSceneService+ScenePlayback.swift'
        text = r'''
import Foundation
protocol PlaybackResourceLifetime:AnyObject {}
final class Lease:PlaybackResourceLifetime {}
struct SceneUserPropertyValue {}
struct ScenePlaybackTextureReference {}
struct ScenePlaybackShortcutConfiguration {static let empty=Self()}
enum ContentType {case scene}
struct SteamWorkshopDownloadRecord {let id:String;let title:String;let contentType:ContentType}
extension Notification.Name {static let steamWorkshopSceneReadyToRender=Self("scene-ready")}
enum Runtime {case scene}
struct PlaybackSwitchTicket:Equatable {let id:Int;let epoch:UInt64;let runtime:Runtime}
struct Selection {let ticket:PlaybackSwitchTicket}
struct Pending {let selection:Selection}
struct Switch {var pending:Pending?;var committed:Selection?}
enum StoredSelection {case scene(String)}
@MainActor final class WallpaperManager {
    static var current:WallpaperManager!
    static var shared:WallpaperManager {get {current!} set {current=newValue}}
    var playbackSwitch=Switch(),switchSelections:[Int:StoredSelection]=[:]
    var beginCount=0,cancelCount=0
    func beginPlaybackIntent(runtime:Runtime)->PlaybackSwitchTicket {
        beginCount += 1
        let ticket=PlaybackSwitchTicket(id:beginCount,epoch:UInt64(beginCount),runtime:runtime)
        playbackSwitch.pending=Pending(selection:Selection(ticket:ticket));return ticket
    }
    func switchFailed(_ ticket:PlaybackSwitchTicket,reason:String) {
        cancelCount += 1
        if playbackSwitch.pending?.selection.ticket == ticket {playbackSwitch.pending=nil}
    }
''' + method(manager, '    func claimScenePlaybackIntent(') + r'''
}
@MainActor final class SteamWorkshopService {
    static var current:SteamWorkshopService!
    static var shared:SteamWorkshopService {get {current!} set {current=newValue}}
    var prepareScenePlaybackIntent:((String,Bool)->(intentEpoch:UInt64,isCurrent:()->Bool,cancel:()->Void)?)?
    var webLaunchIntentGeneration:UInt64=7
    var statusMessage="",downloadError:String?,cleared:[String]=[]
    var admissionCalls=0,rejectAdmission=false
    var beforeReferences:(()->Void)?
    weak var lastLease:Lease?
''' + method(reclamation, '    struct SceneSourceAdmission {') + r'''
    func sceneSourceAdmission(for record:SteamWorkshopDownloadRecord) throws -> SceneSourceAdmission {
        admissionCalls += 1
        if rejectAdmission {throw CocoaError(.fileReadNoPermission)}
        let lease=Lease();lastLease=lease
        return .init(source:.init(rootURL:URL(fileURLWithPath:"/approved/"+record.id)),resourceLifetime:lease)
    }
    func scenePropertyOverrides(for record:SteamWorkshopDownloadRecord)->[String:SceneUserPropertyValue]{[:]}
    func sceneShortcutConfiguration(for record:SteamWorkshopDownloadRecord)->ScenePlaybackShortcutConfiguration{.empty}
    func withResolvedSceneTexturePropertyReferences(for record:SteamWorkshopDownloadRecord,
        perform:([String:ScenePlaybackTextureReference])->Void) {beforeReferences?();perform([:])}
    func clearLaunchPending(matching id:String){cleared.append(id)}
}
@MainActor final class Observed {var requests:[SteamWorkshopScenePlaybackRequest]=[]}
@main enum Probe {
    @MainActor static func main() throws {
        func connect(_ service:SteamWorkshopService,_ manager:WallpaperManager) {
            SteamWorkshopService.shared=service;WallpaperManager.shared=manager
''' + method(app, '        SteamWorkshopService.shared.prepareScenePlaybackIntent =') + r'''
        }
        let record=SteamWorkshopDownloadRecord(id:"123",title:"authored",contentType:.scene)
        let service=SteamWorkshopService(),manager=WallpaperManager(),observed=Observed()
        connect(service,manager)
        let observer=NotificationCenter.default.addObserver(forName:.steamWorkshopSceneReadyToRender,
            object:nil,queue:nil) {note in MainActor.assumeIsolated {
                if let request=note.userInfo?["request"] as? SteamWorkshopScenePlaybackRequest {
                    observed.requests.append(request)
                }
            }}
        defer {NotificationCenter.default.removeObserver(observer)}
        service.requestSceneRender(record)
        let ticket=manager.playbackSwitch.pending!.selection.ticket
        var checks:[String:Bool]=[:]
        checks["sourceAdmissionPublishesWithoutMigrationTask"]=service.admissionCalls == 1 && observed.requests.count == 1
        checks["publishedSourceAndLifetimeAreCurrent"]=observed.requests.first?.source?.rootURL.path == "/approved/123"
            && observed.requests.first?.resourceLifetime != nil && service.lastLease != nil && service.downloadError == nil
        service.requestSceneRender(record,newSelection:false)
        checks["sameTicketReprepareKeepsIntent"]=manager.beginCount == 1 && manager.cancelCount == 0
            && manager.playbackSwitch.pending?.selection.ticket == ticket && observed.requests.count == 2
            && observed.requests.allSatisfy {$0.intentEpoch == ticket.epoch}
        let publishedBeforeChange=observed.requests.count
        let changed=SteamWorkshopService(),changedManager=WallpaperManager()
        connect(changed,changedManager)
        changed.beforeReferences={_ = changedManager.beginPlaybackIntent(runtime:.scene)}
        changed.requestSceneRender(record)
        checks["synchronousIntentChangeCannotPublishStaleSource"]=observed.requests.count == publishedBeforeChange
            && changedManager.cancelCount == 0 && changed.lastLease == nil
        let rejected=SteamWorkshopService(),rejectedManager=WallpaperManager()
        connect(rejected,rejectedManager);rejected.rejectAdmission=true
        rejected.requestSceneRender(record)
        checks["sourceAdmissionFailureClearsOnlyPendingIntent"]=observed.requests.count == publishedBeforeChange
            && rejected.downloadError != nil && rejected.cleared == [record.id] && rejectedManager.cancelCount == 1
        print(String(decoding:try JSONSerialization.data(withJSONObject:checks),as:UTF8.self))
    }
}
'''
        self.assertEqual(len(compile_run(self, text, [SOURCE, scene])), 5)

    def test_real_metadata_marker_and_same_actor_lease(self):
        reclamation = (CORE / 'SteamWorkshopService+LibraryReclamation.swift').read_text()
        metadata = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        text = r'''
import Foundation
struct SteamWorkshopDownloadRecord {
    let id:String;let folderURL:URL;var dependencyItemID:String?=nil
}
struct SteamWorkshopDownloadMetadataSnapshot:Codable {
    struct Item:Codable {let id:String}
    let item:Item;let commit:SteamWorkshopLibraryCommit?
    let legacyFolderURL:URL?;var legacyRemoved:Bool?=nil
}
@MainActor final class SteamWorkshopService {
    var removingDownloadIDs:Set<String>=[]
    let steamDownloadLibraryRootURL:URL
    let steamLibraryVersionLeaseRegistry=SteamWorkshopLibraryVersionLeaseRegistry()
    init(_ root:URL){steamDownloadLibraryRootURL=root}
''' + '\n'.join(method(reclamation, signature) for signature in (
            '    struct SceneSourceAdmission {', '    func sceneSourceAdmission(')) + '\n' + method(metadata, '    func loadManagedDownloadSnapshots(') + r'''
}
@main enum Probe {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]);let fm=FileManager.default
        typealias T=SteamWorkshopLibraryTransaction
        let service=SteamWorkshopService(root)
        let generation="11111111-1111-4111-8111-111111111111"
        let a=SteamWorkshopLibraryCommit(version:3,workshopId:"123",jobId:"job",attempt:1,
            directoryName:"123",manifestId:"m",contentDigest:String(repeating:"a",count:64),
            contentType:"scene",entryPath:nil,committedAt:Date(),generation:generation)
        let folder=try T.contentURL(for:a,libraryRoot:root)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        func marker(_ commit:SteamWorkshopLibraryCommit) throws {
            try JSONEncoder().encode(commit).write(to:folder.appendingPathComponent(T.ownershipMarkerName))
        }
        func publish(_ commit:SteamWorkshopLibraryCommit) throws {
            try T.publish(metadata:JSONEncoder().encode(SteamWorkshopDownloadMetadataSnapshot(
                item:.init(id:"123"),commit:commit,legacyFolderURL:folder)),itemID:"123",libraryRoot:root)
        }
        let record=SteamWorkshopDownloadRecord(id:"123",folderURL:folder)
        try marker(a);try publish(a)
        var checks:[String:Bool]=[:]
        var admitted:SteamWorkshopService.SceneSourceAdmission?=try service.sceneSourceAdmission(for:record)
        let encodedSource = try JSONSerialization.jsonObject(with: JSONEncoder().encode(admitted!.source)) as! [String: Any]
        let encodedBinding = encodedSource["managed"] as! [String: Any]
        checks["originalAcquisitionMetadataNotSentForPlayback"]=encodedBinding["contentDigest"] == nil && encodedBinding["receipt"] == nil && admitted!.source.isValid
        checks["directoryURLHintDoesNotChangeAdmission"]=try service.sceneSourceAdmission(for:
            .init(id:"123",folderURL:URL(fileURLWithPath:folder.path,isDirectory:false))).source.managed == admitted?.source.managed
        checks["sameConcreteGenerationLease"]=service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities() == [T.storageIdentity(for:a)!]
        checks["cannotReclaimCapturedSource"]=(!service.steamLibraryVersionLeaseRegistry.beginReclamation(T.storageIdentity(for:a)!))
        service.removingDownloadIDs=["123"]
        checks["announcedDeletionRejectsBeforeLease"]=(try? service.sceneSourceAdmission(for:record)) == nil
        service.removingDownloadIDs=[]
        var dependent=record;dependent.dependencyItemID="456";service.removingDownloadIDs=["456"]
        checks["actualDependencyDeletionRejects"]=(try? service.sceneSourceAdmission(for:dependent)) == nil
        service.removingDownloadIDs=[]
        var b=a;b.generation="22222222-2222-4222-8222-222222222222"
        try publish(b)
        checks["metadataMarkerDifferentGenerationsReject"]=(try? service.sceneSourceAdmission(for:record)) == nil
        checks["alreadyCapturedADoesNotRetargetB"]=admitted?.source.managed?.generation == generation
        try marker(b)
        let current=try service.sceneSourceAdmission(for:record)
        checks["samePathNewGenerationIsDistinct"]=current.source != admitted?.source
        admitted=nil
        checks["oldLeaseEndsAfterConsumerRelease"]=(!service.steamLibraryVersionLeaseRegistry.protectedStorageIdentities().contains(T.storageIdentity(for:a)!))
        var bad=b;bad.sceneReceipt = .init(schemaVersion:1,relativePath:"../receipt.json",encodedByteCount:1,
            sha256:String(repeating:"a",count:64),storageIdentity:T.storageIdentity(for:b)!,contentDigest:b.contentDigest)
        try marker(bad);try publish(bad)
        let hinted=try service.sceneSourceAdmission(for:record)
        checks["malformedAccelerationHintCannotRevokeSourceLease"]=hinted.source.managed?.generation == b.generation
            && hinted.resourceLifetime != nil
        try marker(a);try publish(a)
        let oldFolder=root.appendingPathComponent("Scene/123-33333333-3333-4333-8333-333333333333")
        try fm.createDirectory(at:oldFolder,withIntermediateDirectories:true)
        checks["oldRecordCannotBorrowLatestMetadata"]=(try? service.sceneSourceAdmission(for:.init(id:"123",folderURL:oldFolder))) == nil
        let reserved=root.appendingPathComponent("Scene/789-44444444-4444-4444-8444-444444444444")
        try fm.createDirectory(at:reserved,withIntermediateDirectories:true)
        checks["missingManagedMarkerCannotDowngrade"]=(try? service.sceneSourceAdmission(for:.init(id:"789",folderURL:reserved))) == nil
        let unmanaged=root.appendingPathComponent("Scene/777")
        try fm.createDirectory(at:unmanaged,withIntermediateDirectories:true)
        let legacy=try service.sceneSourceAdmission(for:.init(id:"777",folderURL:unmanaged))
        checks["unmanagedSeparateNoWarmTrust"]=legacy.source.managed == nil && legacy.resourceLifetime == nil
        try T.publish(metadata:JSONEncoder().encode(SteamWorkshopDownloadMetadataSnapshot(
            item:.init(id:"777"),commit:nil,legacyFolderURL:unmanaged,legacyRemoved:true)),itemID:"777",libraryRoot:root)
        checks["legacyTombstoneRejectsAdmission"]=(try? service.sceneSourceAdmission(for:.init(id:"777",folderURL:unmanaged))) == nil
        let alias=root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at:alias,withDestinationURL:folder)
        let aliasCapture=try service.sceneSourceAdmission(for:.init(id:"123",folderURL:alias))
        checks["sameRootAliasCapturesConcreteSource"]=aliasCapture.source.rootURL.path == folder.path
        try fm.removeItem(at:alias);try fm.createSymbolicLink(at:alias,withDestinationURL:unmanaged)
        checks["aliasRetargetCannotChangeCapturedSource"]=aliasCapture.source.rootURL.path == folder.path
            && (try? service.sceneSourceAdmission(for:.init(id:"123",folderURL:alias))) == nil
        print(String(decoding:try JSONSerialization.data(withJSONObject:checks),as:UTF8.self))
    }
}
'''
        sources = list(dict.fromkeys([*SOURCES, SOURCE]))
        self.assertEqual(len(compile_run(self, text, sources)), 17)

    def test_real_client_generation_matching_hello_and_wire(self):
        client = (IPC / 'SceneDaemonClient.swift').read_text()
        events = (IPC / 'SceneDaemonClient+Events.swift').read_text()
        protocol = (IPC / 'SceneDaemonProtocol.swift').read_text()
        command = (ROOT / 'MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift').read_text()
        text = r'''
import Foundation
import CoreFoundation
struct SceneUserPropertyValue:Equatable {let foundationValue:Bool}
struct ScenePlaybackTextureReference:Equatable {let url:URL;var bookmarkData:Data?=nil}
struct ScenePlaybackShortcutConfiguration:Equatable {static let empty=Self()}
''' + method(command, 'nonisolated struct ScenePlaybackLoadRequest:') + r'''
protocol PlaybackResourceLifetime:AnyObject {}
final class Lease:PlaybackResourceLifetime {}
struct Ticket:Equatable {let id:Int}
typealias PlaybackSwitchTicket=Ticket
enum Outcome {case superseded,failed(String)}
enum SceneDaemonProtocolFailure:Error {case invalidPayload(String)}
enum SceneDaemonProtocol {
    static let version=2
    static func shortcutObject(_ value:ScenePlaybackShortcutConfiguration)->[String:Any]{[:]}
''' + method(protocol, '    static func sourceObject(') + '\n' + method(protocol, '    static func boolean(_ raw: Any?) -> Bool?') + r'''
}
struct DaemonPlaybackProcessRegistry {static let shared=Self();let acceptsNewProcesses=true}
struct Backoff {mutating func reset(){}}
struct FrameBuffer {
    mutating func append(_ data:Data)->[Data]{[data]}
}
struct Admission {let generation:UInt64;func accepts(generation:UInt64)->Bool{self.generation == generation}}
struct Execution {let presented:Bool}
@MainActor final class SceneDaemonClient {
    struct RetainedResourceLifetime {
        let rootURL:URL;let recordID:String?;let source:ScenePlaybackSource?;let lifetime:PlaybackResourceLifetime
    }
    struct QueuedSwitchPreparation {let request:ScenePlaybackLoadRequest;let ticket:Ticket?;let resourceLifetime:PlaybackResourceLifetime?}
    var activeIntent:ScenePlaybackLoadRequest?,pendingIntent:ScenePlaybackLoadRequest?
    var activeResourceLifetime:RetainedResourceLifetime?,pendingResourceLifetime:RetainedResourceLifetime?
    var pendingSwitchTicket:Ticket?,activeSwitchTicket:Ticket?
    var pendingSwitchExecution:Execution?
    var queuedSwitchPreparation:QueuedSwitchPreparation?
    var pendingRequestID:UUID?,pendingPresentationRequestID:UUID?,pendingPresentationReachability:Bool?
    var pendingPropertyRevisions:[UInt64:String]=[:],latestTextureRevisions:[String:UInt64]=[:]
    var warmSessionPending=false,endpointReady=false
    var sourceSchemaVersion:Int?
    var requestRetirementSchemaVersion:Int?
    var hasRequestRetirementControl=false
    var idleTransport:Bool?=nil
    var requestResourceLifetimes:[UUID:PlaybackResourceLifetime]=[:]
    var lastPropertyRevision:UInt64=0
    var restartWorkItem:DispatchWorkItem?,handshakeWorkItem:DispatchWorkItem?
    var performanceProfile=(maxFPS:60,ignored:false)
    var isPaused=false
    var outputFrames=FrameBuffer()
    var sessionGeneration:UInt64=1
    var activeEventAdmission:Admission{.init(generation:sessionGeneration)}
    var sent:[[String:Any]]=[],failures:[[String:Any]]=[]
    func ensureSession()->Bool{true}
    func cancelPreparationForRuntimeSwitch(){pendingIntent=nil;pendingResourceLifetime=nil}
    func finishPendingShortcutUpdates(_ value:Outcome){}
    func finishPendingTextureUpdates(_ value:Outcome){}
    func sendDisplayConfiguration(){}
    func send(_ value:[String:Any]){sent.append(value)}
    func sendSimpleCommand(_ value:String){}
    func handleLaunchState(_ value:[String:Any]){failures.append(value);pendingIntent=nil;pendingResourceLifetime=nil;pendingRequestID=nil}
    func publishFailure(code:String,message:String){fatalError(message)}
    func handleCandidatePrepared(_ value:[String:Any]){}
    func handleSwitchControlResult(_ value:[String:Any],generation:UInt64){}
    func handleFirstFrame(_ value:[String:Any]){}
    func handleFrameStats(_ value:[String:Any]){}
    func handlePropertyUpdateResult(_ value:[String:Any]){}
    func handleTextureUpdateResult(_ value:[String:Any]){}
    func handleShortcutUpdateResult(_ value:[String:Any]){}
    func handleSystemMediaDemand(_ value:[String:Any],generation:UInt64){}
    func handleSystemMediaAcknowledgement(_ value:[String:Any],generation:UInt64){}
    func handleSystemMediaReplayRequest(_ value:[String:Any],generation:UInt64){}
    func handleAudioSpectrumDemand(_ value:[String:Any],generation:UInt64){}
    func handleAudioSpectrumPublication(_ value:[String:Any],generation:UInt64){}
    func handleFrameCaptured(_ value:[String:Any]){}
    func handleFrameCaptureFailure(_ value:[String:Any]){}
    static func integer(_ value:Any?)->Int?{value as? Int}
''' + '\n'.join(method(client, signature) for signature in (
            '    func retainResourceLifetime(', '    func requestLaunch(', '    func startLaunch(',
            '    func replayPendingIntent(')) + '\n' + method(events, '    static func unsignedInteger(_ raw: Any?) -> UInt64?') + '\n' + method(events, '    func consumeOutput(') + r'''
}
struct PlaybackVolumeState {static let shared=Self();var normalizedVolume:Float{1}}
struct PlaybackMuteState {static let shared=Self();var isMuted:Bool{false}}
@main enum Probe {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:"/approved")
        func source(_ generation:String)->ScenePlaybackSource{.init(rootURL:root,managed:.init(
            storageIdentity:"v2:scene:123-"+generation,generation:generation))}
        let a=source("11111111-1111-4111-8111-111111111111"),b=source("22222222-2222-4222-8222-222222222222")
        let lease=Lease();var checks:[String:Bool]=[:]
        func request(_ source:ScenePlaybackSource?)->ScenePlaybackLoadRequest{
            .init(rootURL:root,propertyOverrides:[:],userPropertyTextures:[:],recordID:"123",source:source)
        }
        let peer=SceneDaemonClient()
        peer.retainResourceLifetime(lease,rootURL:root,recordID:"123",source:a)
        peer.startLaunch(request(b),ticket:.init(id:2))
        checks["wrongGenerationTokenRejected"]=peer.pendingIntent == nil && peer.failures.count == 1 && peer.sent.isEmpty
        let legacy=SceneDaemonClient();legacy.startLaunch(request(nil),ticket:nil)
        let oldHello=try JSONSerialization.data(withJSONObject:["v":2,"role":"scene-daemon"])
        legacy.consumeOutput(oldHello,generation:1)
        checks["legacyOldChildCompatibility"]=legacy.sent.contains{$0["cmd"] as? String == "loadScene"}
        let old=SceneDaemonClient();old.retainResourceLifetime(lease,rootURL:root,recordID:"123",source:a)
        old.startLaunch(request(a),ticket:nil);old.consumeOutput(oldHello,generation:1)
        checks["oldHelloCannotDowngradeManaged"]=old.failures.count == 1 && old.sent.isEmpty
        let current=SceneDaemonClient();current.retainResourceLifetime(lease,rootURL:root,recordID:"123",source:a)
        current.startLaunch(request(a),ticket:nil)
        let hello=try JSONSerialization.data(withJSONObject:["v":2,"role":"scene-daemon","sourceSchemaVersion":1])
        current.consumeOutput(hello,generation:0)
        checks["staleTransportHelloCannotGrantCapability"]=current.sourceSchemaVersion == nil && current.sent.isEmpty
        current.consumeOutput(hello,generation:1)
        let load=current.sent.first{$0["cmd"] as? String == "loadScene"}!
        let transported=try JSONDecoder().decode(ScenePlaybackSource.self,from:JSONSerialization.data(withJSONObject:load["source"]!))
        checks["actualWirePreservesApprovedSource"]=transported == a && current.requestResourceLifetimes.values.contains{$0 === lease}
        checks["sameGenerationRebuildRetainsLifetime"]=current.pendingResourceLifetime?.source == a
        var invalid=request(a);invalid.source=source("invalid")
        let bad=SceneDaemonClient();bad.sourceSchemaVersion=1;bad.endpointReady=true
        bad.retainResourceLifetime(lease,rootURL:root,recordID:"123",source:invalid.source)
        bad.startLaunch(invalid,ticket:nil)
        checks["encodingFailureCannotSendSourceLessLoad"]=bad.failures.count == 1 && bad.sent.isEmpty && bad.requestResourceLifetimes.isEmpty
        print(String(decoding:try JSONSerialization.data(withJSONObject:checks),as:UTF8.self))
    }
}
'''
        self.assertEqual(len(compile_run(self, text, [SOURCE])), 7)


if __name__ == '__main__':
    unittest.main()
