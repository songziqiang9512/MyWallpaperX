// Original Manager/transaction + the actual App restoration component. The
// fixture controls source facts and renderer publication, never restore policy.
private struct SavedPlayback: Codable {
    let schema:Int
    let status:String
    let source:WallpaperPlaybackSequence.Source?
    let sourceQuery:WallpaperLibraryQueryState?
    let reference:WallpaperReference?
    let userPaused:Bool
}
@MainActor private final class RestorationProbe {
    let manager=WallpaperManager()
    let suite="mwx-restoration-" + UUID().uuidString
    let defaults:UserDefaults
    var restoration:WallpaperLibraryPlaybackRestoration!
    var items:[WallpaperReference:WallpaperContentItem]=[:]
    var snapshot:WallpaperPlaybackSequence.Snapshot?
    var recentSnapshot:WallpaperPlaybackSequence.Snapshot?
    var snapshotQueries:[WallpaperLibraryQueryState?]=[]
    var requests:[WallpaperPlaybackSequence.Pending]=[]
    var preparedProviders:[Set<WallpaperProvider>]=[]
    var endpoints:[NativeEndpoint]=[]
    var errors:[String]=[]
    var resolverAction:(()->Void)?
    var dependencies=Set(WallpaperProvider.allCases)
    var rejects=false
    let epoch=UUID()
    let a=WallpaperReference(provider:.videoLibrary,sourceID:"/old-video")
    let b=WallpaperReference(provider:.videoLibrary,sourceID:"/new-video")
    let web=WallpaperReference(provider:.steamWorkshop,sourceID:"web")
    init(){
        defaults=UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        PlaybackCommandMultiplexer.shared.isUserPaused=false
        PlaybackCommandMultiplexer.shared.isSystemPaused=false
        PlaybackCommandMultiplexer.shared.isPlaybackPaused=false
        PlaybackCommandMultiplexer.shared.onDispatch=nil
        add(a,.video);add(b,.video);add(web,.web)
    }
    func add(_ ref:WallpaperReference,_ kind:WallpaperMediaKind,available:Bool=true){
        items[ref] = .init(reference:ref,providerReference:ref,locator:.init(mediaKind:kind),title:ref.sourceID,
            kind:kind,publishedAvailability:available ? .available : .unavailable,
            capabilities:available ? [.inspect,.play,.organize] : [.inspect],metadata:.init(),acquisition:.idle,update:.idle,aliases:[])
    }
    func start(){
        restoration = .init(manager:manager,defaults:defaults,snapshotProvider:{[unowned self] source,query in
            snapshotQueries.append(query);return source == .page(.recent) ? recentSnapshot : snapshot
        },contentResolver:{[unowned self] ref in
            let action=resolverAction;resolverAction=nil;action?();return items[ref]
        },dependencyProvider:{[unowned self] _,_ in dependencies},prepareProviders:{[unowned self] in preparedProviders.append($0)},report:{[unowned self] error in errors.append(error.localizedDescription)})
        manager.libraryPlaybackDispatcher={[unowned self] pending in
            requests.append(pending)
            if rejects{return false}
            switch pending.ticket.runtime {
            case .video:manager.switchSelections[pending.ticket.id] = .video(.init(path:pending.proposal.entry.reference.sourceID))
            case .web:manager.switchSelections[pending.ticket.id] = .web(pending.proposal.entry.reference.sourceID)
            case .scene:manager.switchSelections[pending.ticket.id] = .scene(pending.proposal.entry.reference.sourceID)
            case .systemStill:manager.switchSelections[pending.ticket.id] = .systemStill(URL(fileURLWithPath:"/image"))
            }
            let endpoint=NativeEndpoint(pending.ticket);endpoints.append(endpoint)
            manager.switchPrepared(pending.ticket,endpoint:endpoint.endpoint)
            return true
        }
        manager.libraryPlaybackCommitted={[unowned self] in restoration.onCommitted($0)}
        manager.libraryPlaybackFailed={[unowned self] in restoration.onFailed($0)}
    }
    func ready(_ providers:Set<WallpaperProvider> = Set(WallpaperProvider.allCases),ids:Set<UUID>=[],revision:UInt64=1,reset:UUID?=nil){
        restoration.updateInitialReadiness(loadedProviders:providers,existingPlaylistIDs:ids,
            resetEpoch:reset ?? epoch,catalogRevision:revision)
    }
    func save(source:WallpaperPlaybackSequence.Source,ref:WallpaperReference,query:WallpaperLibraryQueryState?=nil,paused:Bool=false){
        let value=SavedPlayback(schema:2,status:"selection",source:source,sourceQuery:query,reference:ref,userPaused:paused)
        defaults.set(try! JSONEncoder().encode(value),forKey:WallpaperLibraryPlaybackRestoration.storageKey)
    }
    func stored()->SavedPlayback?{
        defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey).flatMap{try? JSONDecoder().decode(SavedPlayback.self,from:$0)}
    }
    func close(){
        manager.autoSwitchTimer?.invalidate()
        manager.switchDeadline?.cancel()
        PlaybackCommandMultiplexer.shared.onDispatch=nil
        defaults.removePersistentDomain(forName:suite)
    }
}

@main enum WallpaperPlaybackRestorationChecks {
    @MainActor static func main()throws {
        var checks:[String:Bool]=[:]
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.items[p.a]=nil;p.start()
            p.ready([]);checks["initial-empty-projections-never-restore"] = p.requests.isEmpty
            checks["auto-replay-prepares-its-unloaded-source-before-waiting"] = p.preparedProviders == [[.videoLibrary]]
            p.add(p.a,.video);p.ready([.videoLibrary]);checks["only-required-owner-readiness-restores-exact-ref"] = p.requests.count == 1 && p.requests[0].proposal.entry.reference == p.a
            checks["restore-uses-original-ticket-and-no-recent-cause"] = p.manager.playbackSwitch.pending?.selection.ticket == p.requests[0].ticket && !p.requests[0].proposal.cause.shouldRecordRecent
            p.ready();checks["readiness-repeated-once-only"] = p.requests.count == 1
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.manager.settings.restorePlaybackOnLaunch=false;p.start();p.ready()
            checks["restore-disabled-has-no-session-timer-or-request"] = p.requests.isEmpty && p.manager.libraryPlaybackSequence.committed == nil && p.manager.autoSwitchTimer == nil && p.manager.currentWallpaper == nil && !p.manager.isPlaying
            checks["restore-disabled-preserves-last-selection"] = p.stored()?.reference == p.a
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.start();_ = p.manager.beginPlaybackIntent(runtime:.web);p.ready()
            checks["explicit-earlier-intent-revokes-delayed-restore"] = p.requests.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            let id=UUID();var query=WallpaperLibraryQueryState();query.search="filtered";query.kinds = [.video, .image];query.providers = [.videoLibrary, .steamWorkshop];query.statuses = [.playable, .unavailable];query.preferredColumns=3;query.scrollAnchor=p.b;query.scrollOffset = -21.5;query.scrollAtTop = false
            p.save(source:.page(.playlist(id)),ref:p.a,query:query)
            p.snapshot=try .init(source:.page(.playlist(id)),revision:2,entries:[.init(reference:p.a,runtime:.video,isPlayable:true)],sourceQuery:query)
            p.start();p.ready(ids:[id])
            checks["filtered-source-is-preserved-without-full-list-expansion"] = p.requests.first?.proposal.snapshot.source == .page(.playlist(id)) && p.requests.first?.proposal.snapshot.entries.count == 1 && p.snapshotQueries.first??.search == "filtered"
            checks["restored-source-retains-all-three-multiselect-dimensions"] = p.requests.first?.proposal.snapshot.sourceQuery?.providers == query.providers
                && p.requests.first?.proposal.snapshot.sourceQuery?.kinds == query.kinds
                && p.requests.first?.proposal.snapshot.sourceQuery?.statuses == query.statuses
            checks["view-only-query-fields-normalized"] = p.requests.first?.proposal.snapshot.sourceQuery?.preferredColumns == 5
                && p.requests.first?.proposal.snapshot.sourceQuery?.scrollAnchor == nil
                && p.requests.first?.proposal.snapshot.sourceQuery?.scrollOffset == nil
                && p.requests.first?.proposal.snapshot.sourceQuery?.scrollAtTop == nil
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.page(.playlist(UUID())),ref:p.a,query:.init());p.start();p.ready()
            checks["deleted-playlist-restores-single-without-auto"] = p.requests.first?.proposal.snapshot.source == .single(p.a) && p.snapshotQueries.isEmpty
            p.endpoints.last?.show(p.manager)
            checks["deleted-source-success-cannot-arm-single-timer"] = p.manager.autoSwitchTimer == nil && p.stored()?.source == .single(p.a)
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.page(.favorites),ref:p.a)
            let raw=p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey)
            p.start();p.ready()
            checks["page-descriptor-without-current-query-is-rejected-without-rewrite"] = p.requests.isEmpty
                && p.errors.count == 1 && p.snapshotQueries.isEmpty && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == raw
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            let query=WallpaperLibraryQueryState();p.save(source:.page(.favorites),ref:p.a,query:query)
            p.snapshot=try .init(source:.page(.favorites),revision:1,entries:[.init(reference:p.b,runtime:.video,isPlayable:true)],sourceQuery:query)
            p.start();p.ready()
            checks["removed-current-membership-does-not-select-other-item"] = p.requests.first?.proposal.snapshot.source == .single(p.a)
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.add(p.a,.video,available:false);p.save(source:.page(.videos),ref:p.a,query:.init());p.start();p.ready()
            checks["new-unavailable-ref-no-video-fallback"] = p.requests.isEmpty && p.errors.count == 1
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.items[p.a]=p.items[p.web];p.save(source:.single(p.a),ref:p.a);p.start();p.ready()
            checks["trusted-resolver-alias-restores-canonical-single"] = p.requests.first?.proposal.entry.reference == p.web && p.requests.first?.proposal.snapshot.source == .single(p.web)
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            let raw=Data("{\"schema\":77,\"status\":\"selection\"}".utf8)
            p.defaults.set(raw,forKey:WallpaperLibraryPlaybackRestoration.storageKey);p.start();p.ready()
            p.restoration.onStopped()
            checks["unknown-schema-preserves-raw-and-no-legacy"] = p.requests.isEmpty && p.errors.count == 1 && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == raw
            p.ready();checks["corrupt-schema-reports-once"] = p.errors.count == 1
        }
        for carriesAdmission in [false, true] {
            let p=RestorationProbe();defer{p.close()}
            let old=SavedPlayback(schema:1,status:"selection",source:.single(p.a),sourceQuery:nil,reference:p.a,userPaused:true)
            var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as! [String:Any]
            if carriesAdmission { object["legacyAdmission"]=true }
            let raw=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
            p.defaults.set(raw,forKey:WallpaperLibraryPlaybackRestoration.storageKey);p.start();p.ready()
            checks["schema-one-is-rejected-without-replay-or-rewrite-\(carriesAdmission)"] = p.requests.isEmpty
                && p.errors.count == 1 && p.restoration.rememberedReference == nil
                && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == raw
            p.restoration.onStopped()
            checks["schema-one-stop-does-not-convert-the-unread-record-\(carriesAdmission)"] = p.requests.isEmpty
                && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == raw
            let snapshot=try WallpaperPlaybackSequence.Snapshot(source:.single(p.b),revision:1,
                entries:[.init(reference:p.b,runtime:.video,isPlayable:true)])
            let ticket=p.manager.requestLibraryPlayback(reference:p.b,from:snapshot,cause:.userSelection)
            p.endpoints.last?.show(p.manager)
            checks["real-manual-success-replaces-rejected-schema-one-with-schema-two-\(carriesAdmission)"] = ticket != nil
                && p.requests.count == 1 && p.stored()?.schema == 2 && p.stored()?.reference == p.b
                && p.stored()?.source == .single(p.b)
            let reopened=RestorationProbe();defer{reopened.close()}
            reopened.defaults.set(p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey),
                forKey:WallpaperLibraryPlaybackRestoration.storageKey)
            reopened.start();reopened.ready()
            checks["rebuilt-selection-restores-on-next-launch-\(carriesAdmission)"] = reopened.restoration.rememberedReference == reopened.b
                && reopened.requests.count == 1 && reopened.requests.first?.proposal.entry.reference == reopened.b
                && reopened.requests.first?.proposal.cause == .restore && reopened.errors.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.start();p.restoration.onStopped();let raw=p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey)
            _ = p.manager.beginPlaybackIntent();p.ready()
            checks["explicit-stop-marker-survives-termination-invalidation"] = p.stored()?.status == "stopped" && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == raw && p.requests.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.web),ref:p.web);p.start();p.ready();p.manager.switchFailed(p.requests[0].ticket,reason:"new-state failure")
            checks["current-workshop-failure-never-chooses-a-different-target"] = p.requests.count == 1
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.manager.wallpapers=[];p.recentSnapshot=try .init(source:.page(.recent),revision:1,entries:[.init(reference:p.a,runtime:.video,isPlayable:true)]);p.start();p.ready()
            checks["complete-empty-index-blocks-stale-legacy-recent-revival"] = p.requests.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a,paused:true);p.start();p.ready();p.endpoints.last?.show(p.manager)
            checks["commit-saves-paused-selection-without-session-export"] = p.stored()?.userPaused == true && p.stored()?.reference == p.a
            PlaybackCommandMultiplexer.shared.isUserPaused=false
            p.restoration.onUserPauseChanged(false)
            checks["user-pause-change-persists-without-new-play"] = p.stored()?.userPaused == false && p.requests.count == 1
            PlaybackCommandMultiplexer.shared.isSystemPaused=true
            p.restoration.onUserPauseChanged(false)
            checks["system-suspension-does-not-become-user-pause"] = p.stored()?.userPaused == false
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a,paused:true);p.start()
            PlaybackCommandMultiplexer.shared.onDispatch={_ = p.manager.beginPlaybackIntent(runtime:.scene)}
            p.ready();checks["pause-subscriber-reentry-cannot-overwrite-new-intent"] = p.requests.isEmpty && p.manager.requestedRuntime == .scene
        }
        do {
            var waitsForBoth = true
            for epochFirst in [false, true] {
                let p=RestorationProbe();defer{p.close()}
                p.save(source:.single(p.a),ref:p.a);p.start();p.ready();p.endpoints.last?.show(p.manager)
                p.manager.stopCurrentPlayback();p.restoration.reset()
                let newEpoch=UUID(), preparations=p.preparedProviders.count
                p.ready(revision:epochFirst ? 1 : 2,reset:epochFirst ? newEpoch : p.epoch)
                let partial=p.preparedProviders.count
                p.ready(revision:2,reset:newEpoch)
                let complete=p.preparedProviders.count
                p.ready(revision:3,reset:newEpoch)
                waitsForBoth = waitsForBoth && partial == preparations + 1 && complete == partial + 1
                    && p.preparedProviders.count == complete
                checks["reset-clears-current-selection-without-new-admission-\(epochFirst)"] = p.requests.count == 1
                    && p.restoration.rememberedReference == nil && p.stored() == nil
                    && p.manager.libraryPlaybackSequence.pending == nil && p.manager.libraryPlaybackSequence.committed == nil
            }
            checks["reset-requires-new-catalog-and-new-relationship-epoch"] = waitsForBoth
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.start();p.ready([.videoLibrary])
            checks["failed-online-initial-scan-cannot-block-local-video"] = p.requests.first?.proposal.entry.reference == p.a
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.web),ref:p.web);p.items[p.web]=nil;p.start();p.ready([.videoLibrary])
            checks["unknown-steam-target-cannot-trigger-new-or-legacy-fallback"] = p.requests.isEmpty && p.errors.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            let id=UUID(),query=WallpaperLibraryQueryState();p.dependencies=[.videoLibrary]
            p.save(source:.page(.playlist(id)),ref:p.a,query:query)
            p.snapshot=try .init(source:.page(.playlist(id)),revision:1,entries:[.init(reference:p.a,runtime:.video,isPlayable:true),.init(reference:p.b,runtime:.video,isPlayable:true)],sourceQuery:query)
            p.start();p.ready([.videoLibrary],ids:[id])
            checks["relationship-source-uses-injected-raw-provider-dependencies"] = p.requests.first?.proposal.snapshot.entries.count == 2
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.start()
            p.resolverAction={_ = p.manager.beginPlaybackIntent(runtime:.scene)}
            p.ready()
            checks["dependency-resolution-reentry-cannot-override-new-user-intent"] = p.requests.isEmpty && p.manager.requestedRuntime == .scene
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            let id=UUID(),query=WallpaperLibraryQueryState();p.manager.settings.restorePlaybackOnLaunch=false
            p.save(source:.page(.playlist(id)),ref:p.a,query:query,paused:true)
            p.snapshot=try .init(source:.page(.playlist(id)),revision:4,entries:[.init(reference:p.a,runtime:.video,isPlayable:true),.init(reference:p.b,runtime:.video,isPlayable:true)],sourceQuery:query)
            p.start();p.ready(ids:[id]);p.restoration.resumeLastSelection()
            checks["manual-replay-with-launch-off-reuses-saved-source-and-resumes-user-intent"] = p.requests.count == 1
                && p.requests[0].proposal.snapshot.source == .page(.playlist(id)) && !PlaybackCommandMultiplexer.shared.isUserPaused
                && p.requests[0].proposal.cause == .restore
            p.restoration.resumeLastSelection()
            checks["manual-replay-does-not-duplicate-pending-ticket"] = p.requests.count == 1
            p.endpoints.last?.show(p.manager)
            p.manager.stopCurrentPlayback();p.restoration.onStopped()
            checks["stop-retains-success-for-manual-replay-without-auto-admission"] = p.stored()?.status == "stopped"
                && p.restoration.rememberedReference == p.a
            p.manager.settings.restorePlaybackOnLaunch=true;p.start();p.ready(ids:[id])
            checks["stopped-success-does-not-autoplay-on-relaunch"] = p.requests.count == 1
            p.restoration.resumeLastSelection()
            checks["stopped-success-can-replay-through-original-admission"] = p.requests.count == 2
                && p.requests.last?.proposal.entry.reference == p.a
            p.manager.stopCurrentPlayback();p.restoration.reset()
            checks["reset-clears-manual-replay-memory"] = p.restoration.rememberedReference == nil
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.save(source:.single(p.a),ref:p.a);p.items[p.a]=nil
            p.manager.settings.restorePlaybackOnLaunch=false;p.start();p.ready();p.restoration.resumeLastSelection()
            checks["unavailable-manual-replay-never-substitutes-another-target"] = p.requests.isEmpty && p.errors.count == 1
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.manager.settings.restorePlaybackOnLaunch=false;p.save(source:.single(p.a),ref:p.a)
            p.start();p.ready();var notices=0
            let accepted=p.restoration.resumeLastSelection(onFailure:{notices += 1})
            let failed=p.requests[0];p.manager.switchFailed(failed.ticket,reason:"late native load failure")
            p.restoration.onFailed(failed)
            checks["admitted-manual-replay-late-failure-reports-and-notifies-once"] = accepted
                && notices == 1 && p.errors.count == 1 && p.stored()?.reference == p.a
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.manager.settings.restorePlaybackOnLaunch=false;p.save(source:.single(p.a),ref:p.a)
            p.start();p.ready();var notices=0
            p.restoration.resumeLastSelection(onFailure:{notices += 1})
            let stale=p.requests[0];_ = p.manager.beginPlaybackIntent(runtime:.web)
            p.restoration.onFailed(stale)
            checks["superseded-manual-replay-cannot-present-stale-failure"] = notices == 0 && p.errors.isEmpty
        }
        do {
            let p=RestorationProbe();defer{p.close()}
            p.manager.settings.restorePlaybackOnLaunch=false;p.save(source:.global,ref:p.a)
            p.snapshot=try .init(source:.global,revision:1,entries:[
                .init(reference:p.a,runtime:.video,isPlayable:true),
                .init(reference:p.b,runtime:.video,isPlayable:true)])
            p.start();p.ready([.videoLibrary]);let saved=p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey)
            let early=p.restoration.resumeLastSelection()
            checks["manual-replay-requests-source-preparation-before-readiness-check"] = p.preparedProviders.last == Set(WallpaperProvider.allCases)
            checks["manual-global-replay-does-not-degrade-a-partially-loaded-source"] = !early && p.requests.isEmpty
                && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == saved
            p.ready();let ready=p.restoration.resumeLastSelection()
            checks["manual-global-replay-uses-complete-original-source-after-readiness"] = ready
                && p.requests.count == 1 && p.requests[0].proposal.snapshot.source == .global
            p.endpoints.last?.show(p.manager)
            p.manager.stopCurrentPlayback();p.restoration.onStopped();p.start();p.ready([.videoLibrary])
            let stopped=p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey)
            let stoppedEarly=p.restoration.resumeLastSelection()
            checks["stopped-global-manual-replay-waits-for-all-source-owners"] = !stoppedEarly
                && p.requests.count == 1 && p.defaults.data(forKey:WallpaperLibraryPlaybackRestoration.storageKey) == stopped
            p.ready();let stoppedReady=p.restoration.resumeLastSelection()
            checks["stopped-global-manual-replay-retains-original-source"] = stoppedReady
                && p.requests.count == 2 && p.requests.last?.proposal.snapshot.source == .global
        }
        do {
            let p = RestorationProbe(); defer { p.close() }
            let query = WallpaperLibraryQueryState(providers: [.steamWorkshop, .pixiv], kinds: [.web, .scene], statuses: [.playable, .unavailable])
            p.save(source: .page(.downloads), ref: p.web, query: query)
            p.snapshot = try .init(source: .page(.downloads), revision: 1,
                entries: [.init(reference: p.web, runtime: .web, isPlayable: true)], sourceQuery: query)
            p.start(); p.ready([.steamWorkshop])
            checks["multiselect-download-restore-waits-for-each-selected-provider"] = p.requests.isEmpty
            p.ready([.steamWorkshop, .pixiv])
            checks["multiselect-download-restore-keeps-the-scope-without-waiting-for-unselected-providers"] = p.requests.count == 1
                && p.requests[0].proposal.snapshot.sourceQuery == query && p.requests[0].proposal.entry.reference == p.web
        }
        for provider in [WallpaperProvider.wallhaven, .pixiv] {
            let p = RestorationProbe(); defer { p.close() }
            let reference = WallpaperReference(provider: provider, sourceID: provider == .pixiv ? "42:p2" : "Ab001")
            p.add(reference, .image)
            p.save(source: .page(.downloads), ref: reference, query: .init(providers: [provider]))
            p.start(); p.ready([provider])
            checks["filtered-image-download-restores-from-local-provider-without-other-source-or-login-" + provider.rawValue] = p.requests.count == 1
                && p.requests[0].proposal.entry.reference == reference && p.requests[0].ticket.runtime == .systemStill
        }
        do {
            let p = RestorationProbe(); defer { p.close() }
            p.save(source: .page(.downloads), ref: p.web, query: .init())
            p.start(); p.ready([.steamWorkshop, .pixabay])
            checks["unfiltered-download-restore-waits-for-new-local-image-scan-not-anonymous-api"] = p.requests.isEmpty
            p.ready([.steamWorkshop, .pixabay, .wallhaven, .pixiv])
            checks["successful-empty-local-image-scan-unblocks-original-download-restoration"] = p.requests.count == 1
                && p.requests[0].proposal.entry.reference == p.web
        }
        for runtime in [WallpaperRuntimeKind.video, .web, .scene] {
            let p=RestorationProbe();defer{p.close()}
            p.manager.activeWallpaperRuntime=runtime;p.manager.lastWorkshopPlaybackRecordID="web"
            p.manager.currentWallpaper = .init(path:p.a.sourceID)
            p.recentSnapshot=try .init(source:.page(.recent),revision:1,entries:[.init(reference:p.b,runtime:.video,isPlayable:true)])
            p.defaults.set(Data("old success".utf8),forKey:"CurrentWallpaper")
            p.defaults.set(false,forKey:"PlaybackState")
            p.start();p.ready()
            checks["old-manager-state-without-current-envelope-is-not-replayed-" + runtime.rawValue] = p.requests.isEmpty
                && p.restoration.rememberedReference == nil && p.stored() == nil && p.preparedProviders.allSatisfy(\.isEmpty)
            checks["old-manager-state-cannot-create-manual-replay-admission-" + runtime.rawValue] = !p.restoration.resumeLastSelection()
            p.save(source:.single(p.b),ref:p.b,paused:true);p.start();p.ready()
            checks["current-envelope-is-the-only-replay-authority-" + runtime.rawValue] = p.requests.count == 1
                && p.requests[0].proposal.entry.reference == p.b && PlaybackCommandMultiplexer.shared.isUserPaused
        }
        print(String(data:try JSONSerialization.data(withJSONObject:checks,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
