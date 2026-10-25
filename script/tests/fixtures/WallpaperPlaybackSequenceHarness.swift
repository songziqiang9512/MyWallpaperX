import Foundation

typealias Sequence = WallpaperPlaybackSequence

@main struct WallpaperPlaybackSequenceHarness {
    static func main() throws {
        var checks: [String: Bool] = [:]
        var epoch: UInt64 = 0
        func ticket(_ runtime: WallpaperRuntimeKind) -> PlaybackSwitchTicket {
            epoch += 1
            return .init(epoch: epoch, id: UUID(), runtime: runtime)
        }
        func ref(_ id: String, _ provider: WallpaperProvider = .videoLibrary) -> WallpaperReference { .init(provider: provider, sourceID: id) }
        func entry(_ id: String, _ runtime: WallpaperRuntimeKind = .video, playable: Bool = true) -> Sequence.Entry {
            .init(reference: ref(id, runtime == .systemStill ? .staticImageLibrary : runtime == .video ? .videoLibrary : .steamWorkshop),
                  runtime: runtime, isPlayable: playable)
        }
        let a = entry("a"), b = entry("b"), c = entry("c"), d = entry("d")
        let source = Sequence.Source.page(.playlist(UUID()))
        func snapshot(_ entries: [Sequence.Entry], _ revision: UInt64 = 1, source selectedSource: Sequence.Source? = nil) throws -> Sequence.Snapshot {
            try .init(source: selectedSource ?? source, revision: revision, entries: entries)
        }
        let all = try snapshot([a, b, c, d])
        func commit(_ model: inout Sequence, _ proposal: Sequence.Proposal) -> Sequence.Commit {
            let value = ticket(proposal.entry.runtime!)
            precondition(model.stage(proposal, ticket: value))
            return model.commit(value)!
        }
        func start(_ item: Sequence.Entry = a, from input: Sequence.Snapshot? = nil) -> Sequence {
            var result = Sequence()
            _ = commit(&result, result.proposeSelection(item.reference, from: input ?? all)!)
            return result
        }
        var empty = Sequence()
        checks["noSessionNeverInventsGlobalFallback"] = empty.proposeAdvance(mode: .random, chooseIndex: { _ in 0 }) == nil
        do { _ = try snapshot([a], source: .page(.workshop)); checks["remoteBrowseCannotBecomeWholeRemoteQueue"] = false }
        catch { checks["remoteBrowseCannotBecomeWholeRemoteQueue"] = true }
        do { _ = try snapshot([a, b], source: .single(a.reference)); checks["singleSourceCannotContainForeignItem"] = false }
        catch { checks["singleSourceCannotContainForeignItem"] = true }
        let unicode = [Sequence.Entry(reference: ref("\u{E9}"), runtime: .video, isPlayable: true),
                       Sequence.Entry(reference: ref("e\u{301}"), runtime: .video, isPlayable: true),
                       Sequence.Entry(reference: ref("\u{E9}", .pixabay), runtime: .video, isPlayable: true)]
        checks["canonicalOpaqueIdentityDedupsExactBytesOnly"] = try snapshot(unicode + [unicode[0]]).entries == unicode
        var model = start()
        let old = model.committed!, oldBack = model.backHistory
        let proposal = model.proposeAdvance(policy: .adjacent, mode: .random, chooseIndex: { _ in 3 })!
        checks["globalRandomNavigationStillMeansAdjacent"] = proposal.entry == b
        let badRuntime = ticket(.web)
        checks["wrongRuntimeCannotAttachOriginalTicketToProposal"] = !model.stage(proposal, ticket: badRuntime) && model.pending == nil
        let bTicket = ticket(.video)
        model.stage(proposal, ticket: bTicket)
        checks["prepareDoesNotChangeSourceCursorOrHistory"] = model.committed == old && model.backHistory == oldBack && model.forwardHistory.isEmpty
        checks["pendingSuppressesTimerEndedAndRepeatedAdvance"] = model.proposeAdvance(mode: .random, cause: .timer, chooseIndex: { _ in 0 }) == nil
            && model.proposeAdvance(mode: .sequential, cause: .ended, chooseIndex: { _ in 0 }) == nil
        checks["lateFailureCannotClearCurrentPending"] = !model.fail(ticket(.video)) && model.pending?.ticket == bTicket
        let committedB = model.commit(bTicket)!
        checks["onlyRealCommitUpdatesCursorAndSuccessfulBackHistory"] = model.committed?.reference == b.reference && model.backHistory == [a.reference]
            && committedB.ticket == bTicket && committedB.cause == .manualNavigation && committedB.shouldRecordRecent
        checks["duplicateSelectionCommitDoesNotPublishNewSuccess"] = model.commit(bTicket) == nil
        _ = commit(&model, model.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!)
        checks["successHistoryKeepsActualVisitOrder"] = model.committed?.reference == c.reference && model.backHistory == [a.reference, b.reference]
        let backProposal = model.proposeAdvance(.previous, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!
        let beforeBack = model.backHistory
        let backTicket = ticket(.video)
        model.stage(backProposal, ticket: backTicket)
        checks["randomPreviousDoesNotPopUntilSuccessfulCommit"] = backProposal.entry == b && model.backHistory == beforeBack && model.forwardHistory.isEmpty
        model.fail(backTicket)
        checks["failedRandomHistoryLeavesBothCommittedStacksUntouched"] = model.backHistory == beforeBack && model.forwardHistory.isEmpty && model.committed?.reference == c.reference
        _ = commit(&model, model.proposeAdvance(.previous, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!)
        checks["successfulRandomBackPushesCurrentToForwardOnly"] = model.committed?.reference == b.reference && model.backHistory == [a.reference] && model.forwardHistory == [c.reference]
        let forwardProposal = model.proposeAdvance(.next, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!
        checks["randomNextConsumesForwardBeforeSampling"] = forwardProposal.entry == c
        _ = commit(&model, forwardProposal)
        checks["forwardCommitRestoresSuccessfulBackBranch"] = model.backHistory == [a.reference, b.reference] && model.forwardHistory.isEmpty
        _ = commit(&model, model.proposeAdvance(.previous, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!)
        _ = commit(&model, model.proposeSelection(a.reference, from: all)!)
        checks["explicitSelectionResetsForwardBranchOnlyAtCommit"] = model.forwardHistory.isEmpty && model.backHistory == [b.reference]
        let repeated = commit(&model, model.proposeSelection(a.reference, from: all)!)
        checks["explicitSameContentNewTicketRecordsRecentAgain"] = repeated.shouldRecordRecent && model.committed?.reference == a.reference
        let beforeRecovery = model.committed!, historyBeforeRecovery = model.backHistory
        let another = model.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!
        let newer = ticket(.video)
        model.stage(another, ticket: newer)
        let recovery = model.commit(beforeRecovery.ticket, recovery: true)
        checks["oldCommittedRecoveryCannotConsumeNewerPendingOrWriteRecent"] = recovery?.shouldRecordRecent == false && recovery?.isRecovery == true
            && model.pending?.ticket == newer && model.committed == beforeRecovery && model.backHistory == historyBeforeRecovery
        model.cancel(newer)
        for _ in 0..<25 { _ = commit(&model, model.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!) }
        checks["successHistoryHasOriginalTenItemBound"] = model.backHistory.count == 10 && Sequence.historyLimit == 10
        var withoutHistory = start()
        let fallbackPrevious = withoutHistory.proposeAdvance(.previous, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!
        checks["exhaustedRandomBackUsesSequentialPrevious"] = fallbackPrevious.entry == d
        _ = commit(&withoutHistory, fallbackPrevious)
        let randomized = withoutHistory.proposeAdvance(.next, policy: .randomHistory, mode: .random, chooseIndex: { $0 - 1 })!
        checks["forwardExhaustionUsesInjectedRandomChoice"] = randomized.entry == c

        var failed = start()
        let failedOriginal = failed.committed!, failedHistory = failed.backHistory
        let firstAttempt = failed.proposeAdvance(mode: .sequential, cause: .timer, chooseIndex: { _ in 0 })!
        let firstTicket = ticket(.video)
        failed.stage(firstAttempt, ticket: firstTicket)
        let secondAttempt = failed.retryAfterFailure(firstTicket, chooseIndex: { _ in 0 })!
        let secondTicket = ticket(.video)
        failed.stage(secondAttempt, ticket: secondTicket)
        checks["automaticFailureSkipsWithinOriginalSourceWithoutCommitting"] = firstAttempt.entry == b && secondAttempt.entry == c
            && failed.committed == failedOriginal && failed.backHistory == failedHistory
        checks["oldCandidateFailureDoesNotChangeNextAttempt"] = failed.retryAfterFailure(firstTicket, chooseIndex: { _ in 0 }) == nil && failed.pending?.ticket == secondTicket
        let thirdAttempt = failed.retryAfterFailure(secondTicket, chooseIndex: { _ in 0 })!
        let thirdTicket = ticket(.video)
        failed.stage(thirdAttempt, ticket: thirdTicket)
        checks["failureRoundVisitsEachOtherCandidateAtMostOnce"] = thirdAttempt.entry == d && failed.retryAfterFailure(thirdTicket, chooseIndex: { _ in 0 }) == nil
            && failed.isExhausted && failed.committed == failedOriginal && failed.backHistory == failedHistory
        checks["allFailedBlocksAutomaticRetryUntilExplicitActionOrResourceChange"] = failed.proposeAdvance(mode: .random, cause: .timer, chooseIndex: { _ in 0 }) == nil
        let exhaustedGeneration = failed.rotationGeneration
        failed.updateSource(try snapshot(all.entries, 2), reason: .availability)
        checks["unchangedResourceRefreshCannotReviveExhaustedRound"] = failed.isExhausted && failed.rotationGeneration == exhaustedGeneration
            && failed.proposeAdvance(mode: .sequential, cause: .timer, chooseIndex: { _ in 0 }) == nil
        var onlyCurrentChanged = failed
        let replacedA = Sequence.Entry(reference: a.reference, runtime: .video, isPlayable: true, resourceRevision: "current-v2")
        onlyCurrentChanged.updateSource(try snapshot([replacedA, b, c, d], 3), reason: .availability)
        checks["healthyCurrentVersionChangeCannotReviveOtherFailedCandidates"] = onlyCurrentChanged.isExhausted
        var resourceRevived = failed
        let replacedB = Sequence.Entry(reference: b.reference, runtime: .video, isPlayable: true, resourceRevision: "published-v2")
        resourceRevived.updateSource(try snapshot([a, replacedB, c, d], 3), reason: .availability)
        checks["newPublishedResourceVersionPermitsOneNewBoundedRound"] = !resourceRevived.isExhausted
            && resourceRevived.proposeAdvance(mode: .sequential, cause: .timer, chooseIndex: { _ in 0 })?.entry == replacedB
        let explicitRetry = failed.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!
        checks["explicitManualRetryStartsNewBoundedRound"] = explicitRetry.entry == b
        let retryTicket = ticket(.video)
        failed.stage(explicitRetry, ticket: retryTicket)
        failed.cancel(retryTicket)

        var edited = start()
        let preparingB = edited.proposeAdvance(mode: .sequential, cause: .timer, chooseIndex: { _ in 0 })!
        let preparingTicket = ticket(.video)
        edited.stage(preparingB, ticket: preparingTicket)
        edited.updateSource(try snapshot([a, c, d], 2), reason: .explicitMembers)
        checks["memberEditDoesNotCancelAlreadyAdmittedOriginalTicket"] = edited.pending?.ticket == preparingTicket && edited.committed?.reference == a.reference
        _ = edited.commit(preparingTicket)
        checks["pendingSuccessCannotOverwriteNewerMemberSnapshot"] = edited.committed?.reference == b.reference && edited.committed?.snapshot.revision == 2
            && edited.committed?.snapshot.entries.map(\.reference) == [a.reference, c.reference, d.reference] && edited.committed?.cursor == nil
        edited.updateSource(all, reason: .explicitMembers)
        checks["lateLowerRevisionCannotRestoreDeletedMembers"] = edited.committed?.snapshot.revision == 2 && edited.committed?.snapshot.entries.map(\.reference) == [a.reference, c.reference, d.reference]
        var endedAfterRemoval = edited
        checks["removedCurrentVideoEndedStillUsesResolvedSuccessor"] = endedAfterRemoval.proposeAdvance(mode: .sequential, cause: .ended, chooseIndex: { _ in 0 })?.entry == c
        let successor = edited.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!
        checks["removedCurrentKeepsOutputAndChoosesResolvedSuccessor"] = successor.entry == c
        let successorTicket = ticket(.video)
        edited.stage(successor, ticket: successorTicket)
        edited.fail(successorTicket)
        let predecessor = edited.proposeAdvance(.previous, mode: .sequential, chooseIndex: { _ in 0 })!
        checks["removedCurrentRetainsResolvedPreviousBoundary"] = predecessor.entry == a
        let predecessorTicket = ticket(.video)
        edited.stage(predecessor, ticket: predecessorTicket)
        edited.cancel(predecessorTicket)
        var changedDuringFailure = start()
        let obsolete = changedDuringFailure.proposeAdvance(mode: .sequential, cause: .timer, chooseIndex: { _ in 0 })!
        let obsoleteTicket = ticket(.video)
        changedDuringFailure.stage(obsolete, ticket: obsoleteTicket)
        changedDuringFailure.updateSource(try snapshot([a, d], 3), reason: .explicitMembers)
        checks["revisionChangeRevokesOldVisitedRoundWithoutGlobalRetry"] = changedDuringFailure.retryAfterFailure(obsoleteTicket, chooseIndex: { _ in 0 }) == nil && changedDuringFailure.pending == nil
        checks["newRoundUsesOnlyLatestExplicitMembers"] = changedDuringFailure.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == d
        var detached = start(b)
        detached.updateSource(try snapshot([], 2), reason: .sourceDeleted)
        checks["deletedPlaylistKeepsSessionSnapshotWithoutLibraryFallback"] = detached.committed?.isDetached == true && detached.committed?.snapshot.entries == all.entries
            && detached.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == c
        detached.updateSource(try snapshot([a, b, entry("c", playable: false), d], 3), reason: .availability)
        checks["detachedSnapshotStillReceivesResourceAvailability"] = detached.committed?.snapshot.entries.first(where: { $0.reference == c.reference })?.isPlayable == false
        var recent = start(b, from: try snapshot([a, b, c], source: .page(.recent)))
        recent.updateSource(try snapshot([b, a, c], 2, source: .page(.recent)), reason: .recentSuccessReorder)
        checks["recentSuccessfulMoveToFrontDoesNotReorderActiveSnapshot"] = recent.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == c
        var availability = start()
        let beforeResourceGeneration = availability.rotationGeneration
        availability.updateSource(try snapshot([a, entry("b", playable: false), c, d, entry("foreign")], 4), reason: .availability)
        checks["resourceRefreshCannotAppendForeignMembers"] = availability.committed?.snapshot.entries.map(\.reference) == all.entries.map(\.reference)
            && availability.proposeAdvance(mode: .sequential, expectedGeneration: beforeResourceGeneration, chooseIndex: { _ in 0 }) == nil
            && availability.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == c
        var scoped = start(from: try snapshot([a], source: .single(a.reference)))
        checks["singleItemOrEmptySourceNeverEscapesToOtherLibrary"] = scoped.proposeAdvance(mode: .random, cause: .timer, chooseIndex: { _ in 0 }) == nil
        var invalidChoice = start()
        let beforeInvalid = invalidChoice.committed
        checks["invalidRandomIndexDoesNotClampOrPickArbitraryFallback"] = invalidChoice.proposeAdvance(mode: .random, cause: .timer, chooseIndex: { _ in -1 }) == nil && invalidChoice.committed == beforeInvalid
        var loop = start()
        checks["loopNeverInventsAutomaticOrEndedAdvance"] = loop.proposeAdvance(mode: .loop, cause: .timer, chooseIndex: { _ in 0 }) == nil
            && loop.proposeAdvance(mode: .loop, cause: .ended, chooseIndex: { _ in 0 }) == nil
        checks["loopManualAdjacentRemainsAvailable"] = loop.proposeAdvance(mode: .loop, chooseIndex: { _ in 0 })?.entry == b
        let still = entry("still", .systemStill)
        var staticSession = start(still, from: try snapshot([still, a]))
        checks["staticImageDoesNotPretendToHaveNaturalEnded"] = staticSession.proposeAdvance(mode: .sequential, cause: .ended, chooseIndex: { _ in 0 }) == nil
        var unavailableHistory = start()
        _ = commit(&unavailableHistory, unavailableHistory.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!)
        _ = commit(&unavailableHistory, unavailableHistory.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!)
        unavailableHistory.updateSource(try snapshot([a, entry("b", playable: false), c, d], 2), reason: .availability)
        let skipUnavailable = unavailableHistory.proposeAdvance(.previous, policy: .randomHistory, mode: .random, chooseIndex: { _ in 0 })!
        let skipTicket = ticket(.video)
        unavailableHistory.stage(skipUnavailable, ticket: skipTicket)
        unavailableHistory.fail(skipTicket)
        checks["unavailableHistorySkippedWithoutPrematureStackMutation"] = skipUnavailable.entry == a && unavailableHistory.backHistory == [a.reference, b.reference]
        var stopped = start()
        let stale = stopped.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })!
        let staleTicket = ticket(.video)
        stopped.stage(stale, ticket: staleTicket)
        let stoppedGeneration = stopped.rotationGeneration
        stopped.stop()
        stopped.updateSource(all, reason: .availability)
        checks["stopRevokesPendingSuccessFailureAndQueuedAdvance"] = stopped.rotationGeneration != stoppedGeneration && stopped.committed == nil && stopped.pending == nil
            && stopped.commit(staleTicket) == nil && !stopped.fail(staleTicket) && !stopped.stage(stale, ticket: staleTicket)
            && stopped.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 }) == nil
        checks["settingsOrAutomaticCauseCannotRecreateStoppedSession"] = stopped.proposeSelection(a.reference, from: all, cause: .settingsReload) == nil
            && stopped.proposeSelection(a.reference, from: all, cause: .timer) == nil && stopped.proposeSelection(a.reference, from: all, cause: .ended) == nil
        checks["lateRestoreGenerationCannotRecreateStoppedSession"] = stopped.proposeSelection(a.reference, from: all, cause: .restore, expectedGeneration: stoppedGeneration) == nil
        for cause in [WallpaperPlaybackCause.restore, .settingsReload] {
            var restored = cause == .restore ? Sequence() : start()
            let event = commit(&restored, restored.proposeSelection(a.reference, from: all, cause: cause)!)
            checks["internalCauseDoesNotCreateNewRecent-\(cause.rawValue)"] = !event.shouldRecordRecent && event.cause == cause
        }
        var settingsPending = start()
        let userPending = settingsPending.proposeSelection(b.reference, from: all)!
        let pendingUserTicket = ticket(.video)
        settingsPending.stage(userPending, ticket: pendingUserTicket)
        checks["settingsReloadCannotSupersedeNewerUserPending"] = settingsPending.proposeSelection(a.reference, from: all, cause: .settingsReload) == nil && settingsPending.pending?.ticket == pendingUserTicket
        // A new source can change synchronously while the original Manager
        // accepts an intent, before its ticket is staged in this pure value.
        let otherSource = Sequence.Source.page(.playlist(UUID()))
        let otherSnapshot = try snapshot([b, c], source: otherSource)
        var reservedEdit = start()
        let reservedOriginal = reservedEdit.committed!
        let reservedProposal = reservedEdit.proposeSelection(b.reference, from: otherSnapshot)!
        let reservedGeneration = reservedEdit.rotationGeneration
        reservedEdit.updateSource(try snapshot([c], 2, source: otherSource), reason: .explicitMembers)
        checks["differentSourceMemberEditRevokesUnstagedReservation"] = reservedEdit.rotationGeneration != reservedGeneration
            && !reservedEdit.stage(reservedProposal, ticket: ticket(.video)) && reservedEdit.pending == nil
            && reservedEdit.committed == reservedOriginal
        var reservedOffline = start()
        let offlineProposal = reservedOffline.proposeSelection(b.reference, from: otherSnapshot)!
        reservedOffline.updateSource(try snapshot([entry("b", playable: false), c], 2, source: otherSource), reason: .availability)
        checks["differentSourceResourceLossRevokesUnstagedReservation"] = !reservedOffline.stage(offlineProposal, ticket: ticket(.video))
            && reservedOffline.committed?.reference == a.reference
        var reservedDeleted = start()
        let deletedProposal = reservedDeleted.proposeSelection(b.reference, from: otherSnapshot)!
        reservedDeleted.updateSource(try snapshot([], 2, source: otherSource), reason: .sourceDeleted)
        checks["differentSourceDeletionRevokesUnstagedReservationWithoutDetachingOldSource"] = !reservedDeleted.stage(deletedProposal, ticket: ticket(.video))
            && reservedDeleted.committed?.reference == a.reference && reservedDeleted.committed?.isDetached == false
        var reservedHeartbeat = start()
        let heartbeatProposal = reservedHeartbeat.proposeSelection(b.reference, from: otherSnapshot)!
        let heartbeatGeneration = reservedHeartbeat.rotationGeneration
        reservedHeartbeat.updateSource(try snapshot([b, c], 2, source: otherSource), reason: .availability)
        checks["sameResourceFactsKeepUnstagedReservationAndGeneration"] = reservedHeartbeat.rotationGeneration == heartbeatGeneration
            && reservedHeartbeat.stage(heartbeatProposal, ticket: ticket(.video))
        var reservedStale = start()
        let newestReserved = try snapshot([b, c], 4, source: otherSource)
        let currentProposal = reservedStale.proposeSelection(b.reference, from: newestReserved)!
        reservedStale.updateSource(try snapshot([c], 3, source: otherSource), reason: .explicitMembers)
        checks["olderDifferentSourceEditCannotRevokeNewerReservation"] = reservedStale.stage(currentProposal, ticket: ticket(.video))
        let types: [WallpaperRuntimeKind] = [.video, .web, .scene, .systemStill]
        let mixed = try snapshot(types.map { entry($0.rawValue, $0) })
        for from in types {
            for to in types where from != to {
                var directed = start(entry(from.rawValue, from), from: mixed)
                let selection = directed.proposeSelection(entry(to.rawValue, to).reference, from: mixed)!
                let result = commit(&directed, selection)
                checks["pureDirectedTypeTransition-\(from.rawValue)-to-\(to.rawValue)"] = result.reference == entry(to.rawValue, to).reference
                    && result.ticket.runtime == to && result.shouldRecordRecent && directed.committed?.reference == result.reference
            }
        }

        var failedOutput = start()
        let failedOutputOriginal = failedOutput.committed!
        let loopRecovery = failedOutput.proposeAdvance(mode: .loop, cause: .failureRecovery, chooseIndex: { _ in 0 })!
        let loopRecoveryTicket = ticket(.video)
        _ = failedOutput.stage(loopRecovery, ticket: loopRecoveryTicket)
        checks["lostLoopOutputMayTryBoundedSameSourceSuccessor"] = loopRecovery.entry == b
            && loopRecovery.snapshot.source == source && loopRecovery.cause == .failureRecovery
            && failedOutput.committed == failedOutputOriginal && failedOutput.backHistory.isEmpty
        let recoveredOutput = failedOutput.commit(loopRecoveryTicket)!
        checks["replacementAfterOutputLossRecordsOnlyActualNewSuccess"] = recoveredOutput.shouldRecordRecent
            && !recoveredOutput.isRecovery && recoveredOutput.cause == .failureRecovery
            && recoveredOutput.ticket == loopRecoveryTicket && failedOutput.committed?.reference == b.reference
        var exhaustedOutput = start(from: try snapshot([a, b, c]))
        var lostAttempt = exhaustedOutput.proposeAdvance(mode: .loop, cause: .failureRecovery, chooseIndex: { _ in 0 })!
        var attemptedLost: [WallpaperReference] = []
        while true {
            attemptedLost.append(lostAttempt.entry.reference)
            let t = ticket(lostAttempt.entry.runtime!)
            _ = exhaustedOutput.stage(lostAttempt, ticket: t)
            guard let next = exhaustedOutput.retryAfterFailure(t, chooseIndex: { _ in 0 }) else { break }
            lostAttempt = next
        }
        checks["lostOutputExhaustionNeverRetriesHealthyIdentityOrLeavesSource"] = attemptedLost == [b.reference, c.reference]
            && exhaustedOutput.isExhausted && exhaustedOutput.pending == nil
            && exhaustedOutput.committed?.reference == a.reference && exhaustedOutput.backHistory.isEmpty
            && exhaustedOutput.proposeAdvance(mode: .loop, cause: .failureRecovery, chooseIndex: { _ in 0 }) == nil
        var lostAfterStop = Sequence()
        checks["failureRecoveryCannotInventStoppedOrForeignSelection"] = lostAfterStop.proposeAdvance(mode: .loop,
            cause: .failureRecovery, chooseIndex: { _ in 0 }) == nil
            && lostAfterStop.proposeSelection(b.reference, from: all, cause: .failureRecovery) == nil
        var randomLost = start()
        checks["randomLostOutputUsesInjectedChoiceWithinSameSource"] = randomLost.proposeAdvance(mode: .random,
            cause: .failureRecovery, chooseIndex: { $0 - 1 })?.entry == d

        var filteredQuery = WallpaperLibraryQueryState()
        filteredQuery.search = "blue"
        filteredQuery.kind = .video
        filteredQuery.sort = .name
        filteredQuery.preferredColumns = 3
        filteredQuery.scrollAnchor = a.reference
        filteredQuery.scrollOffset = -17.5
        filteredQuery.scrollAtTop = false
        let filteredSnapshot = try Sequence.Snapshot(source: source, revision: 1, entries: [a, c], sourceQuery: filteredQuery)
        var filteredSession = start(from: filteredSnapshot)
        let filteredOriginal = filteredSession.committed!
        checks["playbackSnapshotKeepsQueryWithoutViewOnlyState"] = filteredOriginal.snapshot.sourceQuery?.search == "blue"
            && filteredOriginal.snapshot.sourceQuery?.kind == .video && filteredOriginal.snapshot.sourceQuery?.sort == .name
            && filteredOriginal.snapshot.sourceQuery?.preferredColumns == 5 && filteredOriginal.snapshot.sourceQuery?.scrollAnchor == nil
            && filteredOriginal.snapshot.sourceQuery?.scrollOffset == nil && filteredOriginal.snapshot.sourceQuery?.scrollAtTop == nil
        filteredSession.updateSource(all, reason: .explicitMembers)
        checks["unfilteredMemberEditCannotExpandFilteredPlaybackSource"] = filteredSession.committed == filteredOriginal
        filteredSession.updateSource(try Sequence.Snapshot(source: source, revision: 2, entries: [c, d], sourceQuery: filteredQuery),
            reason: .explicitMembers)
        checks["matchingFilteredEditUsesOnlyReprojectedMembers"] = filteredSession.committed?.snapshot.entries == [c, d]
            && filteredSession.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == c
        var filteredAvailability = start(from: filteredSnapshot)
        filteredAvailability.updateSource(try snapshot([a, b, c, d], 3), reason: .availability)
        checks["broadAvailabilityRefreshRetainsFilteredMembershipAndQuery"] = filteredAvailability.committed?.snapshot.entries == [a, c]
            && filteredAvailability.committed?.snapshot.sourceQuery == filteredOriginal.snapshot.sourceQuery
        let recoveredQuery = try JSONDecoder().decode(WallpaperLibraryQueryState.self,
            from: JSONEncoder().encode(filteredOriginal.snapshot.sourceQuery!))
        var restoredFilter = Sequence()
        let restoreSnapshot = try Sequence.Snapshot(source: source, revision: 9, entries: [c], sourceQuery: recoveredQuery)
        let restoredFilterCommit = commit(&restoredFilter, restoredFilter.proposeSelection(c.reference, from: restoreSnapshot, cause: .restore)!)
        checks["restoredFilteredDescriptorDoesNotBecomeUnfilteredOrWriteRecent"] = restoredFilter.committed?.snapshot.sourceQuery == filteredOriginal.snapshot.sourceQuery
            && restoredFilter.committed?.snapshot.entries == [c] && !restoredFilterCommit.shouldRecordRecent
        do {
            _ = try Sequence.Snapshot(source: .global, revision: 1, entries: [a], sourceQuery: filteredQuery)
            checks["pageQueryCannotBeSmuggledIntoGlobalSource"] = false
        } catch { checks["pageQueryCannotBeSmuggledIntoGlobalSource"] = true }

        for (oldEntry, newEntry) in [(a, b), (b, a)] {
            let suffix = oldEntry.reference.sourceID + "-to-" + newEntry.reference.sourceID
            var targeted = start(oldEntry)
            let oldTicket = targeted.committed!.ticket
            let next = targeted.proposeSelection(newEntry.reference, from: all)!
            let pendingTicket = ticket(.video)
            precondition(targeted.stage(next, ticket: pendingTicket))
            let pendingProjection = try snapshot([newEntry, c], 50)
            let committedProjection = try snapshot([oldEntry, c], 2)
            targeted.updateSource(pendingProjection, reason: .explicitMembers, targetTicket: pendingTicket)
            targeted.updateSource(committedProjection, reason: .explicitMembers, targetTicket: oldTicket)
            checks["ticketScopedRevisionDoesNotCompareOtherSession-" + suffix] = targeted.committed?.snapshot == committedProjection
                && targeted.pending?.proposal == next
            var failed = targeted
            _ = failed.fail(pendingTicket)
            checks["ticketScopedPendingFailurePreservesOriginalOwnerSlots-" + suffix] = failed.committed?.snapshot.entries == [oldEntry, c]
                && failed.proposeAdvance(mode: .sequential, chooseIndex: { _ in 0 })?.entry == c
            _ = targeted.commit(pendingTicket)
            checks["ticketScopedSuccessUsesItsOwnPendingProjection-" + suffix] = targeted.committed?.snapshot == pendingProjection
                && targeted.committed?.reference == newEntry.reference
            let beforeLate = targeted.committed, generationBeforeLate = targeted.rotationGeneration
            let late = try snapshot([d], 99)
            targeted.updateSource(late, reason: .explicitMembers, targetTicket: oldTicket)
            targeted.updateSource(late, reason: .sourceDeleted, targetTicket: oldTicket)
            checks["lateTicketScopedUpdateCannotChangeNewCommittedSource-" + suffix] = targeted.committed == beforeLate
                && targeted.rotationGeneration == generationBeforeLate
            let reservation = targeted.proposeSelection(c.reference, from: pendingProjection)!
            targeted.updateSource(late, reason: .availability, targetTicket: oldTicket)
            let reservedTicket = ticket(.video)
            checks["lateTicketScopedUpdateCannotRevokeNewReservation-" + suffix] = targeted.stage(reservation, ticket: reservedTicket)
        }

        var clock = WallpaperRotationDeadline()
        clock.configure(now: 0, interval: 10, eligible: true)
        checks["settingsCannotInventInitialSessionTimer"] = clock.deadline == nil && !clock.hasCommittedSession
        clock.commitSuccess(now: 0, interval: 10, eligible: true)
        let unchangedClock = clock
        clock.configure(now: 1.25, interval: 10, eligible: true)
        checks["unchangedSettingsPreserveExactScheduledDeadline"] = clock == unchangedClock
        clock.freezeForPreparation(now: 3)
        checks["prepareFreezesOldRemainingDisplayTime"] = clock.deadline == nil && clock.remaining == 7 && clock.isPreparing
        clock.setPause(effective: true, now: 4)
        clock.preparationFailed(now: 8)
        checks["failedPreparePreservesRemainingAndEffectivePause"] = clock.remaining == 7 && clock.deadline == nil && clock.isPaused
        clock.setPause(effective: false, now: 10)
        checks["resumeContinuesFrozenRemainingInsteadOfFullInterval"] = clock.deadline == 17
        checks["tickMustBeDueAndCanBeTakenOnlyOnce"] = !clock.takeDue(now: 16, scheduledDeadline: 17)
            && clock.takeDue(now: 17, scheduledDeadline: 17) && !clock.takeDue(now: 18, scheduledDeadline: 17)
        clock.commitSuccess(now: 30, interval: 10, eligible: true)
        checks["newSuccessStartsFullIntervalAfterAllPrepareTime"] = clock.deadline == 40 && clock.remaining == 10
        clock.setPause(effective: true, now: 35)
        clock.setPause(effective: false, now: 40)
        checks["oldScheduledDeadlineCannotFireAfterPauseResume"] = clock.deadline == 45 && !clock.takeDue(now: 45, scheduledDeadline: 40)
        checks["wakeDoesNotCatchUpMultipleMissedItems"] = clock.takeDue(now: 1000, scheduledDeadline: 45) && !clock.takeDue(now: 1000, scheduledDeadline: 45)
        clock.commitSuccess(now: 1001, interval: 10, eligible: true)
        checks["wakeSuccessStartsOneNewDisplayBudget"] = clock.deadline == 1011
        clock.stop()
        clock.setPause(effective: true, now: 1002)
        clock.setPause(effective: false, now: 1003)
        clock.configure(now: 1004, interval: 50, eligible: true)
        clock.preparationFailed(now: 1005)
        checks["stopCannotBeRevivedByResumeSettingsOrLateFailure"] = clock.deadline == nil && !clock.hasCommittedSession && clock.remaining == nil
        var adjusted = WallpaperRotationDeadline()
        adjusted.commitSuccess(now: 0, interval: 10, eligible: true)
        adjusted.configure(now: 2, interval: 20, eligible: true)
        checks["intervalChangePreservesElapsedRatherThanRestartingFullBudget"] = adjusted.remaining == 18 && adjusted.deadline == 20
        adjusted.setPause(effective: true, now: 4)
        adjusted.configure(now: 5, interval: 8, eligible: true)
        adjusted.setPause(effective: false, now: 10)
        checks["pausedIntervalChangePreservesElapsedAndPauseBudget"] = adjusted.remaining == 4 && adjusted.deadline == 14
        let beforeInvalidClock = adjusted
        adjusted.commitSuccess(now: .nan, interval: 1, eligible: true)
        adjusted.configure(now: 12, interval: 0, eligible: true)
        checks["invalidClockInputsDoNotCorruptExistingDeadline"] = adjusted == beforeInvalidClock
        adjusted.configure(now: 11, interval: 8, eligible: false)
        checks["loopOrDisabledAutoSwitchDisarmsWithoutInventedEnded"] = adjusted.deadline == nil
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
