// Controlled renderer/provider/Desktop/Timer leaves. The runner compiles the
// real Manager and App dispatch bodies with the original switch transaction.
enum ManualNavigationDirection { case previous, next }
struct WebWallpaperResourceGrant {}
struct ScenePlaybackLoadRequest { let recordID:String? }
@MainActor enum PreparedLeaf { static var web:PlaybackSwitchTicket?,scene:PlaybackSwitchTicket? }
extension WallpaperEngine {
    enum WebRuntimeProfile { case standard,diagnostic }
    func prepareWebSwitch(ticket:PlaybackSwitchTicket,requestID:UUID,entryURL:URL,rootURL:URL,
        propertiesJSON:String?,recordID:String?,language:String,runtimeProfile:WebRuntimeProfile,
        multiDisplayEnabled:Bool,resourceLifetime:PlaybackResourceLifetime?,resourceGrants:[WebWallpaperResourceGrant],
        allowedNetworkHosts:Set<String>) {
        PreparedLeaf.web=ticket
    }
    func stopPlayback(){activeVideoPlayback=nil;activeVideoExecution=nil}
}
extension SceneDaemonClient {
    func prepareSwitch(_ request:ScenePlaybackLoadRequest,ticket:PlaybackSwitchTicket,resourceLifetime:PlaybackResourceLifetime?){PreparedLeaf.scene=ticket}
    func stop(){}
}
@MainActor final class PlaybackVolumeState {
    static let shared=PlaybackVolumeState()
    func setNormalizedVolume(_ value:Float){}
}
extension PlaybackCommandMultiplexer {
    enum Command {case setVolume(Float)}
    func dispatch(_ value:Command){}
}
extension Notification.Name {static let onlineDownloadsPlaybackPathDidChange=Self("library-path")}
@MainActor final class DeliveryTimer {
    let timeInterval:TimeInterval
    let action:(DeliveryTimer)->Void
    var isValid=true
    init(timeInterval:TimeInterval,repeats:Bool,block:@escaping(DeliveryTimer)->Void){self.timeInterval=timeInterval;action=block}
    static func add(_ timer:DeliveryTimer){}
    func invalidate(){isValid=false}
    func deliverEvenIfCancelled(){action(self)}
}
struct DesktopScreen {
    let id: Int
    var deviceDescription: [NSDeviceDescriptionKey: Any] { [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: id)] }
}
@MainActor final class DesktopLeaf {
    static let shared=DesktopLeaf()
    static var screens=[DesktopScreen(id: 0), DesktopScreen(id: 1)]
    var urls:[Int:URL]=[:]
    var options: [Int: [NSWorkspace.DesktopImageOptionKey: Any]] = [:]
    var attempts: [(Int, URL)] = []
    var failURLs = Set<URL>()
    var failScreen:Int?
    func desktopImageURL(for screen: DesktopScreen)->URL?{urls[screen.id]}
    func desktopImageOptions(for screen: DesktopScreen)->[NSWorkspace.DesktopImageOptionKey: Any]?{options[screen.id] ?? [:]}
    func setDesktopImageURL(_ url:URL,for screen: DesktopScreen,options: [NSWorkspace.DesktopImageOptionKey: Any])throws {
        attempts.append((screen.id, url))
        if failScreen == screen.id || failURLs.contains(url) {throw CocoaError(.fileWriteUnknown)}
        urls[screen.id]=url; self.options[screen.id] = options
    }
}
struct SILWallpaper {let id:String;let path:String}
@MainActor final class SILService {var wallpapers:[SILWallpaper]=[]}
struct SteamWorkshopDownloadRecord {
    enum ContentType {case video,web,scene,unknown}
    let id:String
    let contentType:ContentType
}
@MainActor final class SteamWorkshopService {
    let manager:WallpaperManager
    var records:[SteamWorkshopDownloadRecord]=[]
    var calls:[WallpaperPlaybackSequence.Pending]=[]
    init(_ manager:WallpaperManager){self.manager=manager}
    func latestDownloadRecord(for id:String)->SteamWorkshopDownloadRecord?{records.first{$0.id == id}}
    func setAsWallpaper(_ value:SteamWorkshopDownloadRecord,libraryPending:WallpaperPlaybackSequence.Pending)->Bool {
        calls.append(libraryPending)
        switch value.contentType {
        case .web:
            manager.setWebWallpaper(requestID:UUID(),entryURL:URL(fileURLWithPath:"/fixture/index.html"),
                rootURL:URL(fileURLWithPath:"/fixture"),propertiesJSON:nil,recordID:value.id,language:"en-us",
                runtimeProfile:.standard,resourceLifetime:nil,intentEpoch:libraryPending.ticket.epoch,libraryPending:libraryPending)
        case .scene:
            manager.setSceneWallpaper(.init(recordID:value.id),resourceLifetime:nil,
                intentEpoch:libraryPending.ticket.epoch,libraryPending:libraryPending)
        default:return false
        }
        return true
    }
}
@MainActor final class OnlineLibraryService {
    let manager:WallpaperManager
    let video:VideoWallpaper
    var calls:[WallpaperPlaybackSequence.Pending]=[]
    init(_ manager:WallpaperManager,video:VideoWallpaper){self.manager=manager;self.video=video}
    func setLocalFileAsWallpaper(id:Int,libraryPending:WallpaperPlaybackSequence.Pending)->Bool {
        calls.append(libraryPending)
        guard let admission=manager.admitImportedVideoPlayback(reference:.init(provider:.pixabay,sourceID:String(id)),libraryPending:libraryPending)else{return false}
        manager.setAsWallpaper(video,admission:admission)
        return true
    }
}

@MainActor final class DelayedSceneEndpoint {
    let ticket:PlaybackSwitchTicket
    let id=UUID()
    var cancelDone:(()->Void)?,retireDone:(()->Void)?
    var cancellations=0,retirements=0
    var onCancel:(()->Void)?
    init(_ ticket:PlaybackSwitchTicket){self.ticket=ticket}
    var endpoint:PlaybackSwitchEndpoint {
        .init(id:id,activate:{},finalize:{},cancel:{[self] done in cancellations += 1;cancelDone=done;onCancel?()},
            setOutputActive:{_,done in done(true)},retire:{[self] _,done in retirements += 1;retireDone=done})
    }
    func show(_ manager:WallpaperManager){manager.switchVisible(ticket,executionID:id)}
}

@main enum WallpaperLibraryPlaybackChecks {
    @MainActor static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let videoURL=root.appendingPathComponent("video.mp4"),imageURL=root.appendingPathComponent("image.png")
        try Data([1]).write(to:videoURL);try Data([2]).write(to:imageURL)
        var checks:[String:Bool]=[:]
        let runtimes:[WallpaperRuntimeKind]=[.video,.web,.scene,.systemStill]
        let references:[WallpaperRuntimeKind:WallpaperReference]=[
            .video:.init(provider:.videoLibrary,sourceID:videoURL.path),
            .web:.init(provider:.steamWorkshop,sourceID:"web"),.scene:.init(provider:.steamWorkshop,sourceID:"scene"),
            .systemStill:.init(provider:.staticImageLibrary,sourceID:"image")]
        func content(_ reference:WallpaperReference,kind:WallpaperMediaKind,owner:WallpaperReference?=nil)->WallpaperContentItem {
            .init(reference:reference,providerReference:owner ?? reference,locator:.init(mediaKind:kind),title:kind.rawValue,
                kind:kind,publishedAvailability:.available,capabilities:[.play,.organize],metadata:.init(),
                acquisition:.idle,update:.idle,aliases:[])
        }
        let items:[WallpaperRuntimeKind:WallpaperContentItem]=[
            .video:content(references[.video]!,kind:.video),.web:content(references[.web]!,kind:.web),
            .scene:content(references[.scene]!,kind:.scene),.systemStill:content(references[.systemStill]!,kind:.image)]
        let source=WallpaperPlaybackSequence.Source.page(.playlist(UUID()))
        let snapshot=try WallpaperPlaybackSequence.Snapshot(source:source,revision:1,entries:runtimes.map{
            .init(reference:references[$0]!,runtime:$0,isPlayable:true)})
        func setup()->(WallpaperManager,SteamWorkshopService,OnlineLibraryService,SILService) {
            let manager=WallpaperManager();manager.wallpapers=[.init(path:videoURL.path)]
            let steam=SteamWorkshopService(manager);steam.records=[.init(id:"web",contentType:.web),.init(id:"scene",contentType:.scene)]
            let online=OnlineLibraryService(manager,video:.init(path:videoURL.path))
            let images=SILService();images.wallpapers=[.init(id:"image",path:imageURL.path)]
            manager.libraryPlaybackDispatcher={pending in
                let item=items[pending.ticket.runtime]!
                return WallpaperLibraryPlaybackRouting.dispatch(pending,content:item,manager:manager,workshop:steam,online:online,images:images)
            }
            return(manager,steam,online,images)
        }
        func show(_ manager:WallpaperManager,_ ticket:PlaybackSwitchTicket) {
            if ticket.runtime == .systemStill {return}
            let endpoint=NativeEndpoint(ticket)
            manager.switchPrepared(ticket,endpoint:endpoint.endpoint)
            endpoint.show(manager)
        }
        for from in runtimes {
            for to in runtimes where from != to {
                let(manager,_,_,_)=setup()
                var events:[WallpaperPlaybackSequence.Commit]=[]
                manager.libraryPlaybackCommitted={events.append($0)}
                let first=manager.requestLibraryPlayback(reference:references[from]!,from:snapshot)!
                show(manager,first)
                let second=manager.requestLibraryPlayback(reference:references[to]!,from:snapshot)!
                let pendingKeepsOld=to == .systemStill || manager.playbackSwitch.committed?.ticket == first && events.count == 1
                show(manager,second)
                checks["originalOwnerDirected-\(from.rawValue)-to-\(to.rawValue)"] = pendingKeepsOld
                    && second.epoch == first.epoch+1 && manager.playbackSwitch.committed?.ticket == second
                    && manager.libraryPlaybackSequence.committed?.ticket == second && events.count == 2
                    && events.last?.reference == references[to] && events.last?.source == source
                manager.stopCurrentPlayback()
            }
        }
        do {
            let(manager,steam,online,images)=setup()
            var events:[WallpaperPlaybackSequence.Commit]=[];manager.libraryPlaybackCommitted={events.append($0)}
            let first=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!
            checks["noRecentOrCommittedSourceFromPendingVideo"] = events.isEmpty && manager.libraryPlaybackSequence.committed == nil
            show(manager,first)
            let second=manager.requestLibraryPlayback(reference:references[.web]!,from:snapshot)!
            manager.switchFailed(second,reason:"controlled prepare failure")
            checks["prepareFailureKeepsOriginalSuccessfulSourceAndHistory"] = events.count == 1
                && manager.playbackSwitch.committed?.ticket == first && manager.libraryPlaybackSequence.committed?.ticket == first
                && manager.libraryPlaybackSequence.backHistory.isEmpty && manager.autoSwitchTimer != nil
            let latest=manager.requestLibraryPlayback(reference:references[.scene]!,from:snapshot)!
            manager.switchFailed(second,reason:"late obsolete failure")
            checks["lateFailureCannotReplaceOrCancelNewTypedPending"] = manager.playbackSwitch.pending?.selection.ticket == latest
                && manager.libraryPlaybackSequence.pending?.ticket == latest && events.count == 1
            let pending=manager.libraryPlaybackSequence.pending!
            let unknown=content(pending.proposal.entry.reference,kind:.unknown)
            checks["unknownKindCannotFallThroughToVideo"] =  !WallpaperLibraryPlaybackRouting.dispatch(pending,content:unknown,
                manager:manager,workshop:steam,online:online,images:images)
            let wrongOwner=content(pending.proposal.entry.reference,kind:.video,owner:references[.video])
            checks["wrongRuntimeCannotUsePlayableBacking"] =  !WallpaperLibraryPlaybackRouting.dispatch(pending,content:wrongOwner,
                manager:manager,workshop:steam,online:online,images:images)
            manager.stopCurrentPlayback()
            checks["stopRevokesSequenceClockAndLateProvider"] = manager.libraryPlaybackSequence.committed == nil
                && manager.libraryRotationDeadline.deadline == nil && manager.autoSwitchTimer == nil
                && !WallpaperLibraryPlaybackRouting.dispatch(pending,content:items[.scene]!,manager:manager,workshop:steam,online:online,images:images)
        }
        do {
            let(manager,steam,online,images)=setup()
            let canonical=WallpaperReference(provider:.steamWorkshop,sourceID:"published-video")
            let aliased=content(canonical,kind:.video,owner:references[.video])
            let input=try WallpaperPlaybackSequence.Snapshot(source:.single(canonical),revision:1,
                entries:[.init(reference:canonical,runtime:.video,isPlayable:true)])
            manager.libraryPlaybackDispatcher={WallpaperLibraryPlaybackRouting.dispatch($0,content:aliased,manager:manager,workshop:steam,online:online,images:images)}
            let ticket=manager.requestLibraryPlayback(reference:canonical,from:input)!
            checks["canonicalSourceAndActualVideoOwnerRemainSeparate"] = WallpaperEngine.shared.lastPreparedVideoTicket == ticket
                && manager.pendingWallpaper?.path == videoURL.path && steam.calls.isEmpty
            show(manager,ticket)
            checks["aliasedCommitPublishesCanonicalRelationshipIdentity"] = manager.libraryPlaybackSequence.committed?.reference == canonical
            manager.stopCurrentPlayback()
        }
        do {
            let(manager,_,_,_)=setup()
            let first=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!;show(manager,first)
            let saved=DesktopLeaf.shared.urls
            DesktopLeaf.shared.failScreen=1
            let failed=manager.requestLibraryPlayback(reference:references[.systemStill]!,from:snapshot)!
            checks["partialDesktopFailureRollsBackAndNeverCommitsImage"] = failed.epoch == first.epoch+1
                && manager.playbackSwitch.committed?.ticket == first && manager.libraryPlaybackSequence.committed?.ticket == first
                && DesktopLeaf.shared.urls[0] == saved[0] && manager.playbackSwitch.pending == nil
            DesktopLeaf.shared.failScreen=nil;manager.stopCurrentPlayback()
        }
        do {
            let(manager,_,_,_)=setup()
            let ticket=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!;show(manager,ticket)
            let oldTimer=manager.autoSwitchTimer!
            PlaybackCommandMultiplexer.shared.isPlaybackPaused=true
            manager.handleLibraryPlaybackPause(true)
            let pausedRemaining=manager.libraryRotationDeadline.remaining!
            oldTimer.deliverEvenIfCancelled()
            checks["effectivePauseFreezesClockAndRejectsCancelledTick"] = manager.autoSwitchTimer == nil
                && manager.libraryRotationDeadline.isPaused && manager.playbackSwitch.committed?.ticket == ticket
            PlaybackCommandMultiplexer.shared.isPlaybackPaused=false
            manager.handleLibraryPlaybackPause(false)
            checks["effectiveResumePreservesDisplayBudget"] = manager.libraryRotationDeadline.remaining == pausedRemaining
                && manager.autoSwitchTimer != nil
            let beforeStop=manager.autoSwitchTimer!
            manager.stopCurrentPlayback();beforeStop.deliverEvenIfCancelled()
            manager.handleLibraryPlaybackPause(false);manager.refreshAutoSwitchTimerIfNeeded()
            checks["stoppedClockCannotBeRevivedBySettingsResumeOrOldDelivery"] = manager.autoSwitchTimer == nil
                && manager.libraryPlaybackSequence.committed == nil && manager.playbackSwitch.pending == nil
        }
        do {
            let(manager,steam,online,images)=setup()
            let old=references[.video]!
            let canonical=WallpaperReference(provider:.steamWorkshop,sourceID:"same-number")
            let item=content(canonical,kind:.video,owner:old)
            let input=try WallpaperPlaybackSequence.Snapshot(source:.single(old),revision:1,
                entries:[.init(reference:old,runtime:.video,isPlayable:true)])
            manager.libraryPlaybackDispatcher={_ in true}
            manager.libraryPlaybackSnapshotProvider={ _,_,_ in
                try! WallpaperPlaybackSequence.Snapshot(source:.single(canonical),revision:2,
                    entries:[.init(reference:canonical,runtime:.video,isPlayable:true)])
            }
            let canonicalTicket=manager.requestLibraryPlayback(reference:old,cause:.restore)!
            checks["singleProviderCanonicalReferenceIsAdmittedWithoutChoosingFirstOfPage"] = manager.libraryPlaybackSequence.pending?.proposal.entry.reference == canonical
                && manager.playbackSwitch.pending?.selection.ticket == canonicalTicket
                && manager.libraryPlaybackSequence.pending?.proposal.cause == .restore
            manager.switchFailed(canonicalTicket,reason:"explicit test boundary")
            manager.libraryPlaybackSnapshotProvider={ _,_,_ in snapshot }
            checks["singleProviderCannotSubstituteUnrelatedPageFirstItem"] = manager.requestLibraryPlayback(reference:old,cause:.restore) == nil
            let ticket=manager.requestLibraryPlayback(reference:old,from:input)!
            let pending=manager.libraryPlaybackSequence.pending!
            checks["lateAliasRequiresUniqueRelationshipProof"] =  !WallpaperLibraryPlaybackRouting.dispatch(pending,content:item,
                manager:manager,workshop:steam,online:online,images:images)
            func relationships(_ target:WallpaperReference)->UserCollectionsSnapshot {
                .init(revision:1,resetEpoch:UUID(),migrationManifestID:nil,playlists:[],members:[],favorites:[],recent:[],
                    aliases:[.init(alias:old,canonical:target,proof:.publishedDownload)],locators:[])
            }
            checks["sameOpaqueIDInWrongProviderCannotAuthorizeLateAlias"] =  !WallpaperLibraryPlaybackRouting.dispatch(pending,content:item,
                manager:manager,workshop:steam,online:online,images:images,
                relationships:relationships(.init(provider:.pixabay,sourceID:"same-number")))
            let accepted=WallpaperLibraryPlaybackRouting.dispatch(pending,content:item,manager:manager,
                workshop:steam,online:online,images:images,relationships:relationships(canonical))
            checks["trustedLateAliasKeepsOriginalTicketAndSnapshotReference"] = accepted
                && WallpaperEngine.shared.lastPreparedVideoTicket == ticket
                && manager.libraryPlaybackSequence.pending == pending && manager.playbackIntentEpoch == ticket.epoch
            show(manager,ticket)
            checks["lateAliasDoesNotRewriteCommittedSessionIdentity"] = manager.libraryPlaybackSequence.committed?.reference == old
                && manager.libraryPlaybackSequence.committed?.ticket == ticket
            manager.stopCurrentPlayback()
        }
        do {
            let(manager,_,_,_)=setup()
            let initialEpoch=manager.playbackIntentEpoch
            manager.navigateLibraryPlayback(.next)
            checks["unloadedGlobalProviderCannotInventFallbackSession"] = manager.playbackIntentEpoch == initialEpoch
                && manager.libraryPlaybackSequence.committed == nil && manager.playbackSwitch.pending == nil
            var globalReads=0
            manager.libraryPlaybackSnapshotProvider={ reference,requestedSource,_ in
                globalReads += 1
                precondition(reference == nil && requestedSource == .global)
                return try! WallpaperPlaybackSequence.Snapshot(source:.global,revision:2,entries:snapshot.entries)
            }
            manager.navigateLibraryPlayback(.next)
            let selected=manager.playbackSwitch.pending!.selection.ticket
            manager.navigateLibraryPlayback(.previous)
            checks["explicitEmptySessionGlobalNavigationUsesFirstAndSuppressesPendingFallback"] = selected.runtime == .video
                && globalReads == 1 && manager.playbackSwitch.pending?.selection.ticket == selected
            show(manager,selected)
            manager.navigateLibraryPlayback(.previous)
            checks["globalPreviousUsesCapturedAdjacentLastWithoutAnotherGlobalRead"] = manager.libraryPlaybackSequence.committed?.reference == references[.systemStill]
                && globalReads == 1 && manager.libraryPlaybackSequence.committed?.snapshot.source == .global
            manager.stopCurrentPlayback()
        }
        do {
            let(manager,_,_,_)=setup()
            let reference=references[.video]!
            let input=try WallpaperPlaybackSequence.Snapshot(source:.single(reference),revision:1,
                entries:[.init(reference:reference,runtime:.video,isPlayable:true)])
            let ticket=manager.requestLibraryPlayback(reference:reference,from:input)!;show(manager,ticket)
            var fallbackReads=0
            manager.libraryPlaybackSnapshotProvider={ _,_,_ in fallbackReads += 1;return snapshot }
            manager.navigateLibraryPlayback(.next)
            let afterSingle=manager.playbackIntentEpoch
            let empty=try WallpaperPlaybackSequence.Snapshot(source:.single(reference),revision:2,entries:[])
            manager.updateLibraryPlaybackSource(empty,reason:.explicitMembers)
            manager.navigateLibraryPlayback(.previous)
            checks["singleOrDeletedSourceCannotScheduleAutomaticRotation"] = manager.autoSwitchTimer == nil
                && manager.libraryRotationDeadline.deadline == nil
            checks["legalSingleOrExplicitEmptySourceNeverEscapesToGlobal"] = fallbackReads == 0
                && manager.playbackIntentEpoch == afterSingle && manager.playbackSwitch.committed?.ticket == ticket
            var stops=0;manager.libraryPlaybackStopped={stops += 1}
            _ = manager.beginPlaybackIntent()
            checks["terminationRevocationDoesNotPublishUserStoppedMarker"] = stops == 0
                && manager.libraryPlaybackSequence.committed == nil && manager.autoSwitchTimer == nil
            manager.stopCurrentPlayback()
            checks["explicitStopPublishesStoppedMarkerAfterOriginalEpochSettles"] = stops == 1
                && manager.playbackSwitch.pending == nil && manager.currentWallpaper == nil
        }
        do {
            let(manager,_,_,_)=setup();manager.mode = .loop
            var events:[WallpaperPlaybackSequence.Commit]=[];manager.libraryPlaybackCommitted={events.append($0)}
            let first=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!;show(manager,first)
            manager.switchLost(first,reason:"controlled physical output loss")
            let next=manager.playbackSwitch.pending!.selection.ticket
            checks["actualOutputLossInLoopPreparesBoundedOriginalSourceSuccessor"] = next.runtime == .web
                && manager.playbackSwitch.committed == nil && manager.currentWallpaper == nil
                && manager.libraryPlaybackSequence.pending?.proposal.cause == .failureRecovery
                && manager.libraryPlaybackSequence.pending?.proposal.snapshot == snapshot && events.count == 1
            show(manager,next)
            checks["actualLostOutputReplacementPublishesOnlyItsNewVisibleSuccess"] = events.count == 2
                && events.last?.cause == .failureRecovery && events.last?.shouldRecordRecent == true
                && manager.libraryPlaybackSequence.committed?.ticket == next && manager.autoSwitchTimer == nil
            manager.stopCurrentPlayback()
        }
        do {
            let(manager,_,_,_)=setup();manager.mode = .loop
            let first=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!;show(manager,first)
            var attempts:[WallpaperReference]=[],stops=0
            manager.libraryPlaybackStopped={stops += 1}
            manager.libraryPlaybackDispatcher={pending in attempts.append(pending.proposal.entry.reference);return false}
            manager.switchLost(first,reason:"controlled lost output with unavailable successors")
            checks["actualLostOutputAllFailuresVisitEachSuccessorOnceThenStop"] = attempts == [references[.web]!,references[.scene]!,references[.systemStill]!]
                && manager.playbackSwitch.committed == nil && manager.playbackSwitch.pending == nil
                && manager.libraryPlaybackSequence.committed == nil && manager.libraryPlaybackSequence.pending == nil
                && manager.autoSwitchTimer == nil && manager.libraryRotationDeadline.deadline == nil && stops == 1
        }
        do {
            let(manager,_,_,_)=setup();manager.mode = .loop
            let first=manager.requestLibraryPlayback(reference:references[.video]!,from:snapshot)!;show(manager,first)
            var attempts:[WallpaperReference]=[]
            manager.libraryPlaybackDispatcher={pending in
                attempts.append(pending.proposal.entry.reference)
                if pending.ticket.runtime == .web {return false}
                manager.switchSelections[pending.ticket.id] = .scene("scene")
                return true
            }
            manager.switchLost(first,reason:"first successor fails synchronously")
            checks["synchronousLostCandidateFailureCannotStopValidFollowingPrepare"] = attempts == [references[.web]!,references[.scene]!]
                && manager.playbackSwitch.pending?.selection.ticket.runtime == .scene
                && manager.libraryPlaybackSequence.pending?.proposal.cause == .failureRecovery
        }
        func scenePair()->(WallpaperManager,WallpaperPlaybackSequence.Snapshot,PlaybackSwitchTicket,DelayedSceneEndpoint) {
            let(manager,_,_,_)=setup();manager.mode = .loop
            let refs=["old-scene","new-scene","later-scene"].map{WallpaperReference(provider:.steamWorkshop,sourceID:$0)}
            let input=try! WallpaperPlaybackSequence.Snapshot(source:.global,revision:1,
                entries:refs.map{.init(reference:$0,runtime:.scene,isPlayable:true)})
            manager.libraryPlaybackDispatcher={pending in
                manager.switchSelections[pending.ticket.id] = .scene(pending.proposal.entry.reference.sourceID);return true
            }
            let ticket=manager.requestLibraryPlayback(reference:refs[0],from:input)!
            let endpoint=DelayedSceneEndpoint(ticket)
            manager.switchPrepared(ticket,endpoint:endpoint.endpoint);endpoint.show(manager)
            return(manager,input,ticket,endpoint)
        }
        do {
            let(manager,input,old,oldEndpoint)=scenePair()
            let reference=input.entries[1].reference
            let pending=manager.requestLibraryPlayback(reference:reference,from:input)!
            let endpoint=DelayedSceneEndpoint(pending);manager.switchPrepared(pending,endpoint:endpoint.endpoint)
            var released:Bool?
            manager.prepareSceneDownloadRemoval(recordID:reference.sourceID){released=$0}
            checks["scenePendingRemovalWaitsForOriginalCancellationAcknowledgement"] = released == nil && endpoint.cancellations == 1
                && manager.playbackSwitch.committed?.ticket == old && oldEndpoint.retirements == 0
            endpoint.cancelDone?()
            checks["scenePendingRemovalPreservesHealthyOriginalOutput"] = released == true && manager.playbackSwitch.committed?.ticket == old
                && manager.libraryPlaybackSequence.committed?.ticket == old && manager.playbackSwitch.pending == nil
        }
        do {
            let(manager,_,ticket,endpoint)=scenePair()
            var released:Bool?,stops=0;manager.libraryPlaybackStopped={stops += 1}
            manager.prepareSceneDownloadRemoval(recordID:"old-scene"){released=$0}
            checks["sceneActiveRemovalUsesOriginalStopAndWaitsForRetirement"] = released == nil && endpoint.retirements == 1
                && manager.playbackSwitch.committed == nil && manager.libraryPlaybackSequence.committed == nil && stops == 1
            manager.switchVisible(ticket,executionID:endpoint.id)
            endpoint.retireDone?()
            checks["sceneRetirementReceiptCannotRecreateRemovedSession"] = released == true && manager.playbackSwitch.committed == nil
                && manager.libraryPlaybackSequence.committed == nil && manager.switchSettlementObservers.isEmpty
        }
        do {
            let(manager,input,old,endpoint)=scenePair()
            let newer=manager.requestLibraryPlayback(reference:input.entries[1].reference,from:input)!
            var released:Bool?
            manager.prepareSceneDownloadRemoval(recordID:"old-scene"){released=$0}
            checks["sceneOldActiveRemovalIsBusyWithoutStoppingNewPending"] = released == false && endpoint.retirements == 0
                && manager.playbackSwitch.committed?.ticket == old && manager.playbackSwitch.pending?.selection.ticket == newer
        }
        do {
            let(manager,input,old,_)=scenePair()
            let pending=manager.requestLibraryPlayback(reference:input.entries[1].reference,from:input)!
            let endpoint=DelayedSceneEndpoint(pending);manager.switchPrepared(pending,endpoint:endpoint.endpoint)
            var newest:PlaybackSwitchTicket?,released:Bool?
            endpoint.onCancel={newest=manager.requestLibraryPlayback(reference:input.entries[2].reference,from:input)}
            manager.prepareSceneDownloadRemoval(recordID:"new-scene"){released=$0}
            endpoint.cancelDone?()
            checks["sceneRemovalLateCancelReceiptPreservesReentrantNewTicket"] = released == true && newest != nil
                && manager.playbackSwitch.pending?.selection.ticket == newest && manager.playbackSwitch.committed?.ticket == old
                && manager.libraryPlaybackSequence.pending?.ticket == newest
        }
        for reversed in [false,true] {
            let backing=WallpaperReference(provider:.videoLibrary,sourceID:videoURL.path)
            let canonical=WallpaperReference(provider:.steamWorkshop,sourceID:"canonical-video")
            let original=reversed ? canonical : backing, target=reversed ? backing : canonical
            let image=references[.systemStill]!
            let input=try WallpaperPlaybackSequence.Snapshot(source:source,revision:1,entries:[
                .init(reference:backing,runtime:.video,isPlayable:true),.init(reference:canonical,runtime:.video,isPlayable:true),
                .init(reference:image,runtime:.systemStill,isPlayable:true)])
            for succeeds in [false,true] {
                let(manager,_,_,_)=setup()
                manager.libraryPlaybackDispatcher={pending in
                    manager.setAsWallpaper(.init(path:videoURL.path),libraryPending:pending);return true
                }
                let old=manager.requestLibraryPlayback(reference:original,from:input)!;show(manager,old)
                let newer=manager.requestLibraryPlayback(reference:target,from:input)!
                let oldProjection=try WallpaperPlaybackSequence.Snapshot(source:source,revision:2,entries:[
                    .init(reference:original,runtime:.video,isPlayable:true),.init(reference:image,runtime:.systemStill,isPlayable:true)])
                let newProjection=try WallpaperPlaybackSequence.Snapshot(source:source,revision:3,entries:[
                    .init(reference:target,runtime:.video,isPlayable:true),.init(reference:image,runtime:.systemStill,isPlayable:true)])
                manager.updateLibraryPlaybackSource(oldProjection,reason:.explicitMembers,targetTicket:old)
                manager.updateLibraryPlaybackSource(newProjection,reason:.explicitMembers,targetTicket:newer)
                let suffix="\(reversed)-\(succeeds)"
                if succeeds {
                    show(manager,newer)
                    let before=manager.libraryPlaybackSequence.committed
                    manager.updateLibraryPlaybackSource(oldProjection,reason:.sourceDeleted,targetTicket:old)
                    checks["realManagerTicketScopedSuccessAndLateOldUpdate-" + suffix] = manager.libraryPlaybackSequence.committed == before
                        && manager.libraryPlaybackSequence.committed?.snapshot == newProjection && manager.playbackSwitch.committed?.ticket == newer
                } else {
                    manager.switchFailed(newer,reason:"candidate failure after alias member projection")
                    checks["realManagerTicketScopedFailurePreservesHealthyOwnerProjection-" + suffix] = manager.libraryPlaybackSequence.committed?.snapshot == oldProjection
                        && manager.playbackSwitch.committed?.ticket == old && manager.libraryPlaybackSequence.pending == nil
                }
                manager.stopCurrentPlayback()
            }
        }
        checks.merge(try runSystemDesktopWallpaperChecks(root: root), uniquingKeysWith: { _, newer in newer })
        print(String(decoding:try JSONEncoder().encode(checks),as:UTF8.self))
    }
}
