import AppKit
import Foundation

// Test-copy seam only. AppKit still executes its real batch and invokes this
// wrapper; holding delays the unchanged product completion, never the batch.
@MainActor enum PlaylistDirectoryBatchCompletionProbe {
    private(set) static var isHolding = false
    private(set) static var arrivals = 0
    private(set) static var held = 0
    private(set) static var delivered = 0
    private static var pending: [(completion: (Bool) -> Void, finished: Bool)] = []
    static var defaultDeliveryIntact: Bool { !isHolding && pending.isEmpty && held == 0 && arrivals > 0 && arrivals == delivered }
    static var receivedAndHeld: Bool { isHolding && arrivals == 1 && held == 1 && delivered == 0 && pending.count == 1 }
    static var fullyDelivered: Bool { !isHolding && pending.isEmpty && arrivals == delivered && held == 1 }
    static var receipt: [String: Any] {
        ["holding": isHolding, "arrivals": arrivals, "held": held, "delivered": delivered, "pending": pending.count]
    }
    static func wrap(_ completion: @escaping (Bool) -> Void) -> (Bool) -> Void {
        { finished in
            arrivals += 1
            if isHolding {
                held += 1
                pending.append((completion, finished))
            } else {
                delivered += 1
                completion(finished)
            }
        }
    }
    static func beginHolding() {
        precondition(!isHolding && pending.isEmpty)
        arrivals = 0; held = 0; delivered = 0; isHolding = true
    }
    static func release() {
        isHolding = false
        let callbacks = pending
        pending.removeAll()
        for callback in callbacks {
            delivered += 1
            callback.completion(callback.finished)
        }
    }
}

@MainActor final class DirectoryDropInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let source: NSCollectionView
    var draggingSource: Any? { source }
    var draggingDestinationWindow: NSWindow? { source.window }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(source: NSCollectionView, board: NSPasteboard) { self.source = source; draggingPasteboard = board }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

extension PlaylistDirectoryHarness {
    static func checkDirectoryReordering(first: WallpaperPlaylistDirectoryEntry, second: WallpaperPlaylistDirectoryEntry,
                                        collections: UserCollectionsController, store: UserCollectionsStore,
                                        organization: PlaylistOrganizationActions, checks: inout [String: Bool]) {
        // Controlled receipts drive the real production delegate, batch moves,
        // selection and artwork demand. The genuine native source session above
        // remains an independent mouse-input assertion.
        let reorder = AppKitPlaylistDirectoryController()
        let third = WallpaperPlaylistDirectoryEntry(id: UUID(), name: "Third", count: 1, coverReference: nil)
        var authority = [first, second, third]
        var authorityRevision: Int64?
        var epoch = UUID(), reorderCalls: [[UUID]] = [], completions: [(Result<Int64, Error>) -> Void] = []
        var demands: [Set<UUID>] = []
        var reorderCovers = Dictionary(uniqueKeysWithValues: authority.map { ($0.id, WallpaperPlaylistArtwork(image: NSImage(size: .init(width: 32, height: 32)))) })
        reorder.onReorder = { order, done in reorderCalls.append(order); completions.append(done) }
        reorder.onCoverDemand = { demands.append($0) }
        let reorderWindow = NSWindow(contentViewController: reorder)
        reorderWindow.isReleasedWhenClosed = false
        reorderWindow.setContentSize(.init(width: 1000, height: 700)); reorderWindow.setFrameOrigin(.init(x: 180, y: 180))
        reorderWindow.makeKeyAndOrderFront(nil)
        defer { reorderWindow.orderOut(nil); reorderWindow.close() }
        func publishReorder(editable: Bool = true, permits: Bool = true) {
            reorder.update(entries: authority, covers: reorderCovers, preferredColumns: 5, permitsReordering: permits, canEdit: editable, resetEpoch: epoch, relationshipsRevision: authorityRevision)
            reorder.view.layoutSubtreeIfNeeded()
        }
        func settleMove(_ duration: TimeInterval = 0.2) {
            // One fixed native animation turn; no retry of a drag/action.
            RunLoop.main.run(until: Date().addingTimeInterval(duration))
            reorderWindow.contentView?.layoutSubtreeIfNeeded()
        }
        publishReorder(); settleMove()
        let reorderingCollection = descendants(reorder.view, of: NSCollectionView.self).first!
        let reorderFlow = reorderingCollection.collectionViewLayout as! NSCollectionViewFlowLayout
        reorderingCollection.selectionIndexPaths = [IndexPath(item: 2, section: 0)]
        let originalItems = Dictionary(uniqueKeysWithValues: (1...3).map { index in (authority[index - 1].id, reorderingCollection.item(at: IndexPath(item: index, section: 0))!) })
        let reorderBoard = NSPasteboard.withUniqueName()
        defer { reorderBoard.releaseGlobally() }
        func beginReorder(_ id: UUID) -> DirectoryDropInfo {
            let index = reorder.entries.firstIndex { $0.id == id }! + 1
            let writer = reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: index, section: 0))!
            reorderBoard.clearContents(); reorderBoard.writeObjects([writer])
            return DirectoryDropInfo(source: reorderingCollection, board: reorderBoard)
        }
        func hover(_ info: DirectoryDropInfo, before index: Int) -> (NSDragOperation, IndexPath, NSCollectionView.DropOperation) {
            var path: NSIndexPath = IndexPath(item: index, section: 0) as NSIndexPath
            var operation = NSCollectionView.DropOperation.on
            let result = reorder.collectionView(reorderingCollection, validateDrop: info, proposedIndexPath: &path, dropOperation: &operation)
            return (result, path as IndexPath, operation)
        }
        let moving = beginReorder(first.id)
        let demandStart = demands.count
        let proposal = hover(moving, before: 4)
        settleMove()
        checks["directory-hover-previews-native-moves-without-committing-order"] = proposal.0 == .move && proposal.2 == .before
            && reorder.entries.map(\.id) == [second.id, third.id, first.id] && reorderCalls.isEmpty
        checks["directory-hover-retains-native-items-images-selection-and-merged-cover-demand"] = reorder.entries.enumerated().allSatisfy { index, entry in
            let item = reorderingCollection.item(at: IndexPath(item: index + 1, section: 0))
            return item === originalItems[entry.id] && item.flatMap { descendants($0.view, of: NSImageView.self).last?.image } === reorderCovers[entry.id]?.image
        } && reorder.selectedPlaylistID == second.id && demands.last == Set(authority.map(\.id)) && demands.dropFirst(demandStart).allSatisfy { $0 == Set(authority.map(\.id)) }
        let gap = reorderFlow.layoutAttributesForInterItemGap(before: proposal.1)
        checks["directory-native-drop-target-has-no-visible-insertion-marker"] = gap == nil || gap?.alpha == 0
        reorder.collectionView(reorderingCollection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
        settleMove()
        checks["directory-cancel-restores-original-order-with-zero-writes"] = reorder.entries.map(\.id) == authority.map(\.id) && reorderCalls.isEmpty
        let noOp = beginReorder(first.id), noOpProposal = hover(noOp, before: 1)
        settleMove()
        checks["directory-dropping-original-order-performs-zero-transactions"] = reorder.collectionView(reorderingCollection, acceptDrop: noOp,
            indexPath: noOpProposal.1, dropOperation: noOpProposal.2) && reorderCalls.isEmpty
        let failure = beginReorder(first.id), failureProposal = hover(failure, before: 4)
        settleMove()
        let accepted = reorder.collectionView(reorderingCollection, acceptDrop: failure, indexPath: failureProposal.1, dropOperation: failureProposal.2)
        checks["directory-drop-commits-one-complete-uuid-order-and-blocks-reentrancy"] = accepted && reorderCalls == [[second.id, third.id, first.id]]
            && reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)) == nil
            && !reorder.collectionView(reorderingCollection, acceptDrop: failure, indexPath: failureProposal.1, dropOperation: failureProposal.2)
        completions[0](.failure(UserCollectionsError.invalidOrder)); settleMove()
        checks["directory-failed-receipt-restores-authority-and-retains-item-identities"] = reorder.entries.map(\.id) == authority.map(\.id)
            && reorderingCollection.item(at: IndexPath(item: 1, section: 0)) === originalItems[first.id]
        let success = beginReorder(first.id), successProposal = hover(success, before: 4)
        settleMove()
        _ = reorder.collectionView(reorderingCollection, acceptDrop: success, indexPath: successProposal.1, dropOperation: successProposal.2)
        completions[1](.success(0))
        let settledOrder = [second, third, first]
        // A stale content/cover echo cannot momentarily restore the old order.
        publishReorder(); settleMove()
        checks["directory-success-holds-preview-until-authoritative-order-echo"] = reorder.entries.map(\.id) == settledOrder.map(\.id)
            && reorderCalls.count == 2 && reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)) == nil
        authority = settledOrder; publishReorder(); settleMove()
        let resetDrag = beginReorder(second.id), resetProposal = hover(resetDrag, before: 4)
        settleMove()
        _ = reorder.collectionView(reorderingCollection, acceptDrop: resetDrag, indexPath: resetProposal.1, dropOperation: resetProposal.2)
        epoch = UUID(); publishReorder(); settleMove()
        completions[2](.success(0)); settleMove()
        checks["directory-reset-revokes-old-pending-receipt-without-reordering-new-epoch"] = reorder.entries.map(\.id) == authority.map(\.id) && reorderCalls.count == 3
        let readOnly = beginReorder(second.id); _ = hover(readOnly, before: 4)
        settleMove(); publishReorder(editable: false); settleMove()
        checks["directory-readonly-cancels-preview-and-rejects-old-drop"] = reorder.entries.map(\.id) == authority.map(\.id)
            && !reorder.collectionView(reorderingCollection, acceptDrop: readOnly, indexPath: IndexPath(item: 3, section: 0), dropOperation: .before)
            && reorderCalls.count == 3
        publishReorder(); settleMove()
        let collectionChange = beginReorder(second.id); _ = hover(collectionChange, before: 4)
        settleMove(); authority.removeAll { $0.id == third.id }; publishReorder(); settleMove()
        checks["directory-collection-change-closes-drag-and-does-not-persist-obsolete-uuid-set"] = reorder.entries.map(\.id) == authority.map(\.id)
            && !reorder.collectionView(reorderingCollection, acceptDrop: collectionChange, indexPath: IndexPath(item: 2, section: 0), dropOperation: .before)
            && reorderCalls.count == 3
        var probeRevision: Int64 = 100
        for callbackFirst in [true, false] {
            for undoToOriginal in [true, false] {
                authority = [first, second, third]; authorityRevision = probeRevision; publishReorder(); settleMove()
                let input = beginReorder(first.id), proposal = hover(input, before: 4)
                settleMove()
                _ = reorder.collectionView(reorderingCollection, acceptDrop: input, indexPath: proposal.1, dropOperation: proposal.2)
                let complete = completions.last!, preview = [second.id, third.id, first.id]
                authorityRevision = probeRevision + 1; publishReorder(); settleMove()
                let earlyMetadataHeld = reorder.entries.map(\.id) == preview
                    && reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)) == nil
                if callbackFirst { complete(.success(probeRevision + 2)) }
                let preAuthorityHeld = reorder.entries.map(\.id) == preview
                    && reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)) == nil
                authority = undoToOriginal ? [first, second, third] : [third, first, second]
                authorityRevision = probeRevision + 3; publishReorder(); settleMove()
                let waitingForReceipt = callbackFirst || reorder.entries.map(\.id) == preview
                if !callbackFirst { complete(.success(probeRevision + 2)); settleMove() }
                let released = reorder.collectionView(reorderingCollection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0)) != nil
                checks["directory-commit-revision-settles-skipped-A-\(undoToOriginal ? "undo-original" : "newer-B")-callback-\(callbackFirst ? "first" : "last")"] = earlyMetadataHeld
                    && preAuthorityHeld && waitingForReceipt && released && reorder.entries.map(\.id) == authority.map(\.id)
                reorder.collectionView(reorderingCollection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
                probeRevision += 10
            }
        }
        let fourth = WallpaperPlaylistDirectoryEntry(id: UUID(), name: "Fourth", count: 0, coverReference: nil)
        authority = [first, second, third, fourth]; authorityRevision = probeRevision
        reorderCovers[fourth.id] = WallpaperPlaylistArtwork(image: NSImage(size: .init(width: 32, height: 32)))
        publishReorder(); settleMove()
        reorderingCollection.selectionIndexPaths = [IndexPath(item: 2, section: 0)]
        let raceItems = Dictionary(uniqueKeysWithValues: (1...4).map { index in
            (authority[index - 1].id, reorderingCollection.item(at: IndexPath(item: index, section: 0))!)
        })
        let originalRaceOrder = authority.map(\.id), installedMove = [second.id, third.id, fourth.id, first.id]
        let raceLabels = [first.id: "A", second.id: "B", third.id: "C", fourth.id: "D"]
        func labelledOrder(_ ids: [UUID]) -> [String] { ids.map { raceLabels[$0] ?? $0.uuidString } }
        func proposalReceipt(_ proposal: (NSDragOperation, IndexPath, NSCollectionView.DropOperation)) -> [String: Any] {
            ["operation": proposal.0.rawValue, "path": [proposal.1.section, proposal.1.item],
             "dropOperation": String(describing: proposal.2), "isBefore": proposal.2 == .before]
        }
        func traceRace(_ phase: String, _ fields: [String: Any]) {
            var receipt = fields
            receipt["phase"] = phase
            receipt["installed"] = labelledOrder(reorder.entries.map(\.id))
            receipt["authority"] = labelledOrder(authority.map(\.id))
            receipt["onReorderCalls"] = reorderCalls.map { labelledOrder($0) }
            receipt["completionCount"] = completions.count
            receipt["reduceMotion"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            receipt["windowVisible"] = reorderWindow.isVisible
            receipt["collectionItemCount"] = reorderingCollection.numberOfItems(inSection: 0)
            receipt["nativeBatchCompletion"] = PlaylistDirectoryBatchCompletionProbe.receipt
            receipt["inputSemantics"] = "real-native-batch-with-controlled-completion-delivery"
            let data = try! JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            FileHandle.standardError.write(Data("directory-hover-diagnostic ".utf8) + data + Data("\n".utf8))
        }
        func retainsRaceItems() -> Bool {
            reorder.entries.enumerated().allSatisfy { index, entry in
                let item = reorderingCollection.item(at: IndexPath(item: index + 1, section: 0))
                return item === raceItems[entry.id]
                    && item.flatMap { descendants($0.view, of: NSImageView.self).last?.image } === reorderCovers[entry.id]?.image
            } && reorder.selectedPlaylistID == second.id
        }
        // The real native callback is held only for these race scenarios. This
        // proves asynchronous delivery semantics, not an OS timing reproduction.
        checks["directory-original-native-callbacks-retain-unmodified-delivery-outside-hold"] = PlaylistDirectoryBatchCompletionProbe.defaultDeliveryIntact
        traceRace("original-native-default-delivery", ["check": checks["directory-original-native-callbacks-retain-unmodified-delivery-outside-hold"]!])
        let raceCallCount = reorderCalls.count, raceDemandStart = demands.count
        let race = beginReorder(first.id)
        PlaylistDirectoryBatchCompletionProbe.beginHolding()
        let raceEnd = hover(race, before: 5)
        settleMove() // Receive the real animated callback, then retain its delivery.
        let installedFirst = reorder.entries.map(\.id)
        let raceLeft = hover(race, before: 2)
        let installedAfterLeft = reorder.entries.map(\.id)
        let raceRight = hover(race, before: 3)
        let installedBeforeAccept = reorder.entries.map(\.id)
        let raceAccepted = reorder.collectionView(reorderingCollection, acceptDrop: race,
            indexPath: raceRight.1, dropOperation: raceRight.2)
        let raceCallbackHeld = PlaylistDirectoryBatchCompletionProbe.receivedAndHeld
        checks["directory-unsettled-hover-resolves-native-index-to-uuid-before-queued-order"] = raceEnd.0 == .move
            && raceLeft.0 == .move && raceRight.0 == .move && raceRight.2 == .before
            && raceRight.1 == IndexPath(item: 3, section: 0) && installedFirst == installedMove
            && installedBeforeAccept == installedMove && raceAccepted && reorderCalls.count == raceCallCount + 1
            && reorderCalls.last == [second.id, third.id, first.id, fourth.id]
            && !reorder.collectionView(reorderingCollection, acceptDrop: race, indexPath: raceRight.1, dropOperation: raceRight.2)
        traceRace("consecutive-hover-accepted", ["installedFirst": labelledOrder(installedFirst),
            "installedAfterLeft": labelledOrder(installedAfterLeft), "installedBeforeAccept": labelledOrder(installedBeforeAccept),
            "expectedInstalledMove": labelledOrder(installedMove), "expectedCommit": labelledOrder([second.id, third.id, first.id, fourth.id]),
            "endProposal": proposalReceipt(raceEnd), "leftProposal": proposalReceipt(raceLeft), "rightProposal": proposalReceipt(raceRight),
            "accepted": raceAccepted, "beforeCallCount": raceCallCount, "callbackWasReceivedAndHeld": raceCallbackHeld,
            "check": checks["directory-unsettled-hover-resolves-native-index-to-uuid-before-queued-order"]!])
        completions.last!(.failure(UserCollectionsError.invalidOrder))
        PlaylistDirectoryBatchCompletionProbe.release(); settleMove(0.35)
        checks["directory-controlled-native-callback-consecutive-hold-and-release"] = raceCallbackHeld
            && PlaylistDirectoryBatchCompletionProbe.fullyDelivered
        checks["directory-unsettled-failure-retains-items-images-selection-and-merged-demand"] = reorder.entries.map(\.id) == originalRaceOrder
            && retainsRaceItems() && demands.dropFirst(raceDemandStart).allSatisfy { $0 == Set(originalRaceOrder) }
        traceRace("consecutive-hover-failed-receipt", ["expectedOriginal": labelledOrder(originalRaceOrder),
            "demandEchoes": demands.dropFirst(raceDemandStart).map { labelledOrder(Array($0)).sorted() },
            "check": checks["directory-unsettled-failure-retains-items-images-selection-and-merged-demand"]!])

        let roundTripCount = reorderCalls.count, roundTrip = beginReorder(first.id)
        PlaylistDirectoryBatchCompletionProbe.beginHolding()
        let roundEnd = hover(roundTrip, before: 5), roundInstalledEnd = reorder.entries.map(\.id)
        settleMove()
        let roundLeft = hover(roundTrip, before: 2), roundInstalledLeft = reorder.entries.map(\.id)
        let roundRight = hover(roundTrip, before: 3), roundInstalledRight = reorder.entries.map(\.id)
        let backHome = hover(roundTrip, before: 1)
        let roundTripStillMoving = reorder.entries.map(\.id) == installedMove
        let roundTripAccepted = reorder.collectionView(reorderingCollection, acceptDrop: roundTrip,
            indexPath: backHome.1, dropOperation: backHome.2)
        let roundTripCallbackHeld = PlaylistDirectoryBatchCompletionProbe.receivedAndHeld
        PlaylistDirectoryBatchCompletionProbe.release(); settleMove(0.35)
        checks["directory-controlled-native-callback-round-trip-hold-and-release"] = roundTripCallbackHeld
            && PlaylistDirectoryBatchCompletionProbe.fullyDelivered
        checks["directory-unsettled-reverse-hover-back-to-original-is-zero-write"] = backHome.0 == .move && roundTripStillMoving
            && roundTripAccepted && reorderCalls.count == roundTripCount && reorder.entries.map(\.id) == originalRaceOrder && retainsRaceItems()
        traceRace("round-trip-after-settlement", ["installedAfterEnd": labelledOrder(roundInstalledEnd),
            "installedAfterLeft": labelledOrder(roundInstalledLeft), "installedAfterRight": labelledOrder(roundInstalledRight),
            "endProposal": proposalReceipt(roundEnd), "leftProposal": proposalReceipt(roundLeft),
            "rightProposal": proposalReceipt(roundRight), "homeProposal": proposalReceipt(backHome),
            "roundTripStillMoving": roundTripStillMoving, "accepted": roundTripAccepted, "beforeCallCount": roundTripCount,
            "callbackWasReceivedAndHeld": roundTripCallbackHeld,
            "check": checks["directory-unsettled-reverse-hover-back-to-original-is-zero-write"]!])

        let selfCount = reorderCalls.count, selfTarget = beginReorder(first.id)
        PlaylistDirectoryBatchCompletionProbe.beginHolding()
        let selfEnd = hover(selfTarget, before: 5), selfInstalledEnd = reorder.entries.map(\.id)
        settleMove()
        let selfLeft = hover(selfTarget, before: 2), selfInstalledLeft = reorder.entries.map(\.id)
        let atSource = hover(selfTarget, before: 4)
        let selfInstalledBeforeAccept = reorder.entries.map(\.id)
        let selfAccepted = reorder.collectionView(reorderingCollection, acceptDrop: selfTarget,
            indexPath: atSource.1, dropOperation: atSource.2)
        let selfCallbackHeld = PlaylistDirectoryBatchCompletionProbe.receivedAndHeld
        checks["directory-unsettled-source-at-end-target-appends-once"] = atSource.0 == .move
            && atSource.1 == IndexPath(item: 5, section: 0) && selfAccepted
            && reorderCalls.count == selfCount + 1 && reorderCalls.last == installedMove
        traceRace("source-at-end-accepted", ["installedAfterEnd": labelledOrder(selfInstalledEnd),
            "installedAfterLeft": labelledOrder(selfInstalledLeft), "installedBeforeAccept": labelledOrder(selfInstalledBeforeAccept),
            "endProposal": proposalReceipt(selfEnd), "leftProposal": proposalReceipt(selfLeft), "sourceProposal": proposalReceipt(atSource),
            "accepted": selfAccepted, "beforeCallCount": selfCount, "callbackWasReceivedAndHeld": selfCallbackHeld,
            "check": checks["directory-unsettled-source-at-end-target-appends-once"]!])
        completions.last!(.failure(UserCollectionsError.invalidOrder))
        PlaylistDirectoryBatchCompletionProbe.release(); settleMove(0.35)
        checks["directory-controlled-native-callback-source-end-hold-and-release"] = selfCallbackHeld
            && PlaylistDirectoryBatchCompletionProbe.fullyDelivered

        let invalidCount = reorderCalls.count, createTarget = beginReorder(first.id)
        PlaylistDirectoryBatchCompletionProbe.beginHolding()
        let beforeInvalid = hover(createTarget, before: 5)
        settleMove()
        let invalidCreate = hover(createTarget, before: 0)
        let staleProposalAccepted = reorder.collectionView(reorderingCollection, acceptDrop: createTarget,
            indexPath: beforeInvalid.1, dropOperation: beforeInvalid.2)
        reorder.collectionView(reorderingCollection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
        let invalidCallbackHeld = PlaylistDirectoryBatchCompletionProbe.receivedAndHeld
        PlaylistDirectoryBatchCompletionProbe.release(); settleMove(0.35)
        checks["directory-controlled-native-callback-invalid-create-hold-and-release"] = invalidCallbackHeld
            && PlaylistDirectoryBatchCompletionProbe.fullyDelivered
        checks["directory-create-zero-revokes-old-valid-proposal-and-cancels-unsettled-preview"] = invalidCreate.0.isEmpty
            && !staleProposalAccepted && reorderCalls.count == invalidCount && reorder.entries.map(\.id) == originalRaceOrder && retainsRaceItems()
        traceRace("invalid-create-after-cancellation", ["validProposal": proposalReceipt(beforeInvalid),
            "invalidProposal": proposalReceipt(invalidCreate), "staleProposalAccepted": staleProposalAccepted,
            "beforeCallCount": invalidCount, "callbackWasReceivedAndHeld": invalidCallbackHeld,
            "check": checks["directory-create-zero-revokes-old-valid-proposal-and-cancels-unsettled-preview"]!])

        let cancelCount = reorderCalls.count, queuedCancel = beginReorder(first.id)
        PlaylistDirectoryBatchCompletionProbe.beginHolding()
        let cancelEnd = hover(queuedCancel, before: 5), cancelInstalledEnd = reorder.entries.map(\.id)
        settleMove()
        let cancelLeft = hover(queuedCancel, before: 2), cancelInstalledLeft = reorder.entries.map(\.id)
        let cancelRight = hover(queuedCancel, before: 3), cancelInstalledRight = reorder.entries.map(\.id)
        let cancelStillMoving = reorder.entries.map(\.id) == installedMove
        reorder.collectionView(reorderingCollection, draggingSession: DirectoryNativeDragProbe.session!, endedAt: .zero, dragOperation: [])
        let cancelCallbackHeld = PlaylistDirectoryBatchCompletionProbe.receivedAndHeld
        PlaylistDirectoryBatchCompletionProbe.release(); settleMove(0.35)
        checks["directory-controlled-native-callback-cancel-hold-and-release"] = cancelCallbackHeld
            && PlaylistDirectoryBatchCompletionProbe.fullyDelivered
        checks["directory-cancel-before-batch-completes-discards-queued-order-with-zero-writes"] = cancelStillMoving
            && reorderCalls.count == cancelCount && reorder.entries.map(\.id) == originalRaceOrder && retainsRaceItems()
        traceRace("cancel-after-settlement", ["installedAfterEnd": labelledOrder(cancelInstalledEnd),
            "installedAfterLeft": labelledOrder(cancelInstalledLeft), "installedAfterRight": labelledOrder(cancelInstalledRight),
            "endProposal": proposalReceipt(cancelEnd), "leftProposal": proposalReceipt(cancelLeft), "rightProposal": proposalReceipt(cancelRight),
            "cancelStillMoving": cancelStillMoving, "beforeCallCount": cancelCount, "callbackWasReceivedAndHeld": cancelCallbackHeld,
            "check": checks["directory-cancel-before-batch-completes-discards-queued-order-with-zero-writes"]!])

        _ = awaitValue { try await collections.createPlaylist(name: "Native rank two") }
        _ = awaitValue { try await collections.createPlaylist(name: "Native rank three") }
        let persistedBefore = collections.snapshot
        authority = persistedBefore.playlists.sorted { $0.sidebarRank < $1.sidebarRank }.map {
            .init(id: $0.id, name: $0.name, count: 0, coverReference: nil)
        }
        epoch = persistedBefore.resetEpoch; authorityRevision = persistedBefore.revision; publishReorder(); settleMove()
        var undoReceipts = 0, commitResult: Result<Int64, Error>?
        collections.onOrganizationTransaction = { before, after, name, transactionEpoch in
            if before.playlists.map(\.id) != after.playlists.map(\.id), name == "调整列表顺序", transactionEpoch == epoch { undoReceipts += 1 }
        }
        reorder.onReorder = { order, done in
            organization.reorder(order) { result in
                commitResult = result
                authority = collections.snapshot.playlists.sorted { $0.sidebarRank < $1.sidebarRank }.map {
                    .init(id: $0.id, name: $0.name, count: 0, coverReference: nil)
                }
                authorityRevision = collections.snapshot.revision
                publishReorder(); done(result)
            }
        }
        let persistedOrder = authority.map(\.id), commitDrag = beginReorder(authority[0].id)
        let commitProposal = hover(commitDrag, before: authority.count + 1)
        settleMove()
        let acceptedCommit = reorder.collectionView(reorderingCollection, acceptDrop: commitDrag,
            indexPath: commitProposal.1, dropOperation: commitProposal.2)
        pump { commitResult != nil }; settleMove()
        let persistedAfter = awaitValue { try await store.snapshot() }
        let committedOrder = Array(persistedOrder.dropFirst()) + [persistedOrder[0]]
        let commitSucceeded: Bool
        if case .success? = commitResult { commitSucceeded = true } else { commitSucceeded = false }
        checks["native-directory-drop-uses-original-actions-store-rank-and-one-undo-receipt"] = acceptedCommit && commitSucceeded
            && persistedAfter.playlists.sorted { $0.sidebarRank < $1.sidebarRank }.map(\.id) == committedOrder
            && persistedAfter.revision == persistedBefore.revision + 1 && undoReceipts == 1
            && (try? commitResult?.get()) == persistedAfter.revision
            && persistedAfter.members == persistedBefore.members && persistedAfter.favorites == persistedBefore.favorites
            && reorder.entries.map(\.id) == committedOrder
        let noWriteSnapshot = collections.snapshot
        var noWriteResult: Result<Int64, Error>?
        organization.reorder(committedOrder) { noWriteResult = $0 }
        let noWriteSucceeded: Bool
        if case .success? = noWriteResult { noWriteSucceeded = true } else { noWriteSucceeded = false }
        let noWriteDiskSnapshot = awaitValue { try await store.snapshot() }
        checks["original-actions-unchanged-order-adds-no-store-write-or-undo"] = noWriteSucceeded
            && collections.snapshot == noWriteSnapshot && noWriteDiskSnapshot == noWriteSnapshot && undoReceipts == 1
    }
}
