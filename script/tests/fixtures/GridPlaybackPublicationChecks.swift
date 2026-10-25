import Foundation
import Combine

// The original transaction/Manager/Sequence methods and Workspace publisher are
// production. Only provider preparation, renderer bookkeeping and metadata I/O
// are recording leaves. No media, desktop or process renderer runs here.
@MainActor final class PublicationTimer {
    var isValid = true
    init(timeInterval: TimeInterval, repeats: Bool, block: @escaping (PublicationTimer) -> Void) {}
    static func add(_ timer: PublicationTimer) {}
    func invalidate() { isValid = false }
}
@MainActor final class SteamWorkshopService {}
@MainActor final class OnlineLibraryService {}
@MainActor final class SILService {}
extension WallpaperEngine { func stopPlayback() { activeVideoPlayback = nil; activeVideoExecution = nil } }
extension SceneDaemonClient { func stop() {} }
@MainActor final class RecordedCollections {
    var successes: [(WallpaperReference, UInt64)] = []
    func recordSuccessfulUse(_ reference: WallpaperReference, locator: WallpaperLocator?, sequence: UInt64) { successes.append((reference, sequence)) }
}
@MainActor final class RecordedRestoration {
    func onCommitted(_ commit: WallpaperPlaybackSequence.Commit) {}
    func onStopped() {}
    func onFailed(_ pending: WallpaperPlaybackSequence.Pending) {}
    func reset() {}
}
@MainActor enum ExecutionFacts { static var active: WallpaperReference? }
@MainActor enum WallpaperLibraryPlaybackRouting {
    static func dispatch(_ pending: WallpaperPlaybackSequence.Pending, content: WallpaperContentItem, manager: WallpaperManager,
                         workshop: SteamWorkshopService, online: OnlineLibraryService, images: SILService,
                         relationships: UserCollectionsSnapshot) -> Bool {
        switch pending.ticket.runtime {
        case .video: manager.switchSelections[pending.ticket.id] = .video(.init(path: content.reference.sourceID))
        case .web: manager.switchSelections[pending.ticket.id] = .web(content.reference.sourceID)
        case .scene: manager.switchSelections[pending.ticket.id] = .scene(content.reference.sourceID)
        case .systemStill: manager.switchSelections[pending.ticket.id] = .systemStill(URL(fileURLWithPath: content.reference.sourceID))
        }
        return true
    }
}
@MainActor final class WallpaperLibraryWorkspace {
    let manager: WallpaperManager
    let steam = SteamWorkshopService(), online = OnlineLibraryService(), images = SILService()
    let collections: RecordedCollections? = RecordedCollections()
    let restoration = RecordedRestoration()
    let playbackChanges = PassthroughSubject<Void, Never>()
    var relationships = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil, playlists: [], members: [], favorites: [], recent: [], aliases: [], locators: [])
    let items: [WallpaperContentItem]
    init(_ manager: WallpaperManager, items: [WallpaperContentItem]) { self.manager = manager; self.items = items; installPlaybackBindings() }
    func playbackSnapshot(reference: WallpaperReference?, source: WallpaperPlaybackSequence.Source,
                          cause: WallpaperPlaybackCause) -> WallpaperPlaybackSequence.Snapshot? { nil }
    func playbackContent(for reference: WallpaperReference) throws -> WallpaperContentItem { try content(for: reference) }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem { items.first { $0.reference == reference }! }
    func refreshPlaybackAvailability() {}
    func acceptBacking(_ publication: WallpaperContentBackingPublication) {}
    // WORKSPACE_BINDINGS
}
// CARD_STATE_PROJECTION

@MainActor final class GridObserver {
    let workspace: WallpaperLibraryWorkspace
    let manager: WallpaperManager
    var cancellables = Set<AnyCancellable>()
    var visiblePlaying: Set<WallpaperReference> = []
    var refreshes = 0
    var synchronousReads: [Set<WallpaperReference>] = []
    var renderedStates: [Set<WallpaperReference>] = []
    init(_ workspace: WallpaperLibraryWorkspace) {
        self.workspace = workspace; manager = workspace.manager
        // GRID_SUBSCRIPTION
        workspace.playbackChanges.sink { [weak self] in
            guard let self else { return }; self.synchronousReads.append(self.readProjection())
        }.store(in: &cancellables)
    }
    func readProjection() -> Set<WallpaperReference> {
        let committed = manager.libraryPlaybackSequence.committed
        let projection = try! WallpaperLibraryCardStateProjection(items: workspace.items, relationships: workspace.relationships,
            committedReference: committed?.reference, sequenceTicket: committed?.ticket, runtimeTicket: manager.playbackSwitch.committed?.ticket)
        return Set(workspace.items.filter { projection.isPlaying($0.reference) }.map(\.reference))
    }
    func render() { refreshes += 1; visiblePlaying = readProjection(); renderedStates.append(visiblePlaying) }
}
@MainActor final class PublicationEndpoint {
    let id = UUID()
    let ticket: PlaybackSwitchTicket
    let reference: WallpaperReference
    var retirement: (() -> Void)?
    var delayedRetirement = true
    var finalized = false
    init(_ reference: WallpaperReference, _ ticket: PlaybackSwitchTicket) { self.reference = reference; self.ticket = ticket }
    var endpoint: PlaybackSwitchEndpoint {
        .init(id: id, activate: {}, finalize: { [self] in finalized = true; ExecutionFacts.active = reference },
            cancel: { $0() }, setOutputActive: { _, done in done(true) }, retire: { [self] _, done in
                if delayedRetirement { retirement = done } else { done() }
            })
    }
    func finishRetirement() {
        let callback = retirement; retirement = nil
        if ExecutionFacts.active == reference { ExecutionFacts.active = nil }
        callback?()
    }
}
@main enum GridPlaybackPublicationChecks {
    static func reference(_ id: String, _ kind: WallpaperRuntimeKind) -> WallpaperReference {
        .init(provider: kind == .video ? .videoLibrary : kind == .systemStill ? .staticImageLibrary : .steamWorkshop,
              sourceID: id + "." + kind.rawValue)
    }
    static func item(_ reference: WallpaperReference, _ kind: WallpaperRuntimeKind) -> WallpaperContentItem {
        .init(reference: reference, providerReference: reference, locator: .init(), title: reference.sourceID,
            kind: kind == .video ? .video : kind == .web ? .web : kind == .scene ? .scene : .image,
            publishedAvailability: .available, capabilities: [.play], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    @MainActor static func main() async throws {
        var cases = 0
        func drain() async throws { try await Task.sleep(nanoseconds: 25_000_000) }
        for source in [WallpaperRuntimeKind.video, .web, .scene, .systemStill] {
            for target in [WallpaperRuntimeKind.video, .web, .scene, .systemStill] {
                ExecutionFacts.active = nil
                let manager = WallpaperManager()
                let a = reference("A", source), b = reference("B", target), c = reference("C", target)
                let items = [item(a, source), item(b, target), item(c, target)]
                let workspace = WallpaperLibraryWorkspace(manager, items: items)
                let grid = GridObserver(workspace), secondGrid = GridObserver(workspace)
                let snapshot = try WallpaperPlaybackSequence.Snapshot(source: .global, revision: 1,
                    entries: zip([a, b, c], [source, target, target]).map { .init(reference: $0.0, runtime: $0.1, isPlayable: true) })
                func begin(_ reference: WallpaperReference) -> PublicationEndpoint {
                    let ticket = manager.requestLibraryPlayback(reference: reference, from: snapshot)!
                    let endpoint = PublicationEndpoint(reference, ticket)
                    manager.switchPrepared(ticket, endpoint: endpoint.endpoint)
                    return endpoint
                }
                func visible(_ endpoint: PublicationEndpoint) { manager.switchVisible(endpoint.ticket, executionID: endpoint.id) }
                let first = begin(a); visible(first); try await drain()
                precondition(grid.visiblePlaying == [a] && first.finalized, "initial committed selection was not published")
                let next = begin(b); try await drain()
                precondition(grid.visiblePlaying == [a] && manager.libraryPlaybackSequence.pending?.ticket == next.ticket,
                    "unseen pending candidate changed the playing card")
                visible(next); try await drain()
                // Canonical lifecycle: desktop-visible confirmation -> unique
                // transaction/Sequence commit -> old cleanup -> finalize. The
                // old private-grid engine mirror waiting for cleanup is retired.
                precondition(manager.playbackSwitch.committed?.ticket == next.ticket
                    && manager.libraryPlaybackSequence.committed?.ticket == next.ticket && !next.finalized)
                precondition(grid.visiblePlaying == [b] && secondGrid.visiblePlaying == [b] && ExecutionFacts.active == a,
                    "retiring engine bookkeeping took ownership away from the successful commit")
                precondition(workspace.collections!.successes.count == 2)
                let reads = grid.refreshes, successes = workspace.collections!.successes.count
                first.finishRetirement(); try await drain()
                precondition(next.finalized && ExecutionFacts.active == b && grid.visiblePlaying == [b])
                precondition(grid.refreshes == reads && workspace.collections!.successes.count == successes,
                    "retirement/finalize duplicated the committed UI or recent publication")
                let rejected = begin(a)
                manager.switchFailed(rejected.ticket, reason: "injected candidate failure"); visible(rejected); try await drain()
                precondition(grid.visiblePlaying == [b] && !rejected.finalized && workspace.collections!.successes.count == successes)
                let stale = begin(a), latest = begin(c)
                visible(stale); try await drain()
                precondition(!stale.finalized && grid.visiblePlaying == [b])
                visible(latest); try await drain()
                precondition(!stale.finalized && !latest.finalized && grid.visiblePlaying == [c])
                let latestSuccesses = workspace.collections!.successes.count
                next.finishRetirement(); try await drain()
                precondition(latest.finalized && grid.visiblePlaying == [c] && workspace.collections!.successes.count == latestSuccesses)
                latest.delayedRetirement = false
                manager.stopCurrentPlayback(); try await drain()
                precondition(grid.visiblePlaying.isEmpty && secondGrid.visiblePlaying.isEmpty, "Stop retained a stale playing card")
                let lost = begin(a); visible(lost); try await drain()
                precondition(grid.visiblePlaying == [a])
                manager.runSwitchEffects(manager.playbackSwitch.lost(lost.ticket, reason: "injected output loss")); try await drain()
                precondition(manager.playbackSwitch.committed == nil && grid.visiblePlaying.isEmpty,
                    "lost output without a source successor invented an active playing card")
                let lostSuccesses = workspace.collections!.successes.count
                lost.finishRetirement(); try await drain()
                precondition(grid.visiblePlaying.isEmpty && secondGrid.visiblePlaying.isEmpty
                    && workspace.collections!.successes.count == lostSuccesses, "terminal retirement resurrected or duplicated publication")
                let retiring = begin(a); visible(retiring); try await drain()
                let waiting = begin(b)
                manager.runSwitchEffects(manager.playbackSwitch.lost(retiring.ticket, reason: "loss with newer selection"))
                try await drain()
                precondition(!waiting.finalized && grid.visiblePlaying == [a])
                let rendered = grid.renderedStates.count
                visible(waiting); try await drain()
                precondition(grid.visiblePlaying == [a] && !waiting.finalized,
                    "an output-loss barrier published an uncommitted successor")
                retiring.finishRetirement()
                precondition(waiting.finalized && grid.synchronousReads.last == [b])
                try await drain()
                precondition(Array(grid.renderedStates.dropFirst(rendered)) == [[b]], "retirement rendered an empty or stale intermediate card state")
                waiting.delayedRetirement = false; manager.stopCurrentPlayback(); try await drain()
                precondition(grid.visiblePlaying.isEmpty)
                cases += 1
            }
        }
        print("playback publication passed: \(cases) runtime pairs, committed UI authority, delayed finalize, failure, supersession, Stop and output loss")
    }
}
