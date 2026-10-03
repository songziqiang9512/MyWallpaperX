

import Foundation
import Metal

extension Harness {
    static func inFlightHistoryChecks(
        _ device: MTLDevice
    ) -> (
        checks: [String: Any],
        inflightHistoryPlan: SceneLayerGraphTargetPlan,
        inflightHistoryCache: SceneOffscreenTextureAllocationCache,
        inflightHistoryEffect: Graph.EffectKey,
        inflightHistoryCommit1: ScenePreparedPersistentGraphTargets.Commit,
        inflightHistoryCommit2: ScenePreparedPersistentGraphTargets.Commit,
        inflightHistoryCommit3: ScenePreparedPersistentGraphTargets.Commit
    ) {
        let inflightHistoryFixture = historySwapFixture(effectIndex: 49)
        let inflightHistoryFixtures = [inflightHistoryFixture]
        let inflightHistoryPairPlan = pairPlan(inflightHistoryFixtures)
        guard case .success(let inflightHistoryPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(inflightHistoryFixtures, width: 8, height: 8),
                pairPlan: inflightHistoryPairPlan,
                byteBudget: 10_000
            ) else { fatalError("in-flight history plan failed") }
        let inflightHistoryCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightHistoryPlan.residentByteCost * 3
        )
        let inflightHistoryAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: inflightHistoryCache
        )
        guard let inflightHistoryPrepared1 = inflightHistoryAllocator.prepare(
            plan: inflightHistoryPlan
        ), let inflightHistoryLease1 = inflightHistoryPrepared1.leases.first,
              let inflightHistoryEffect = inflightHistoryLease1.table.plan.output.effect
        else { fatalError("first in-flight history allocation failed") }
        let inflightHistoryTokens1 = Set(
            inflightHistoryLease1.framebufferAllocation.resources.values.map(\.token)
        )
        guard let inflightHistoryCommit1 = inflightHistoryPrepared1.commitAndPin(
            historyTokensByEffect: [inflightHistoryEffect: inflightHistoryTokens1]
        ), let inflightHistoryPrepared2 = inflightHistoryAllocator.prepare(
            plan: inflightHistoryPlan
        ), let inflightHistoryCopies2 = inflightHistoryPrepared2
            .historyRehydrateCopiesByEffect[inflightHistoryEffect],
              Set(inflightHistoryCopies2.map(\.sourceToken)) == inflightHistoryTokens1,
              Set(inflightHistoryCopies2.map(\.targetToken))
                .isDisjoint(with: inflightHistoryTokens1),
              let inflightHistoryCommit2 = inflightHistoryPrepared2.commitAndPin(
                  historyTokensByEffect: [
                      inflightHistoryEffect: Set(
                          inflightHistoryCopies2.map(\.targetToken)
                      )
                  ]
              ) else { fatalError("second in-flight history allocation failed") }
        let inflightHistoryTokens2 = Set(
            inflightHistoryCopies2.map(\.targetToken)
        )
        inflightHistoryCommit1.submissionPin.release()
        guard let inflightHistoryPrepared3 = inflightHistoryAllocator.prepare(
            plan: inflightHistoryPlan
        ), let inflightHistoryCopies3 = inflightHistoryPrepared3
            .historyRehydrateCopiesByEffect[inflightHistoryEffect],
              Set(inflightHistoryCopies3.map(\.sourceToken)) == inflightHistoryTokens2,
              Set(inflightHistoryCopies3.map(\.targetToken))
                .isDisjoint(with: inflightHistoryTokens1.union(inflightHistoryTokens2)),
              let inflightHistoryCommit3 = inflightHistoryPrepared3.commitAndPin(
                  historyTokensByEffect: [
                      inflightHistoryEffect: Set(
                          inflightHistoryCopies3.map(\.targetToken)
                      )
                  ]
              ) else { fatalError("third in-flight history allocation failed") }
        let inFlightHistoryPreservesPinnedSeed =
            inflightHistoryPrepared1.leases[0].generation
                != inflightHistoryPrepared2.leases[0].generation
            && inflightHistoryPrepared2.leases[0].generation
                != inflightHistoryPrepared3.leases[0].generation
            && inflightHistoryCache.residentAllocationCount == 3

        let checks: [String: Any] = [
            "inFlightHistoryPreservesPinnedSeed":
                inFlightHistoryPreservesPinnedSeed,
        ]
        return (checks, inflightHistoryPlan, inflightHistoryCache, inflightHistoryEffect, inflightHistoryCommit1, inflightHistoryCommit2, inflightHistoryCommit3)
    }

    static func orderedHistoryChecks(
        _ device: MTLDevice,
        orderedQueue: MTLCommandQueue,
        inflightHistoryPlan: SceneLayerGraphTargetPlan,
        inflightHistoryCache: SceneOffscreenTextureAllocationCache,
        inflightHistoryEffect: Graph.EffectKey,
        inflightHistoryCommit1: ScenePreparedPersistentGraphTargets.Commit,
        inflightHistoryCommit2: ScenePreparedPersistentGraphTargets.Commit,
        inflightHistoryCommit3: ScenePreparedPersistentGraphTargets.Commit
    ) -> [String: Any] {
        let orderedHistoryCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightHistoryPlan.residentByteCost * 2
        )
        let orderedHistoryAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: orderedHistoryCache
        )
        guard let orderedHistoryFirstBuffer = orderedQueue.makeCommandBuffer(),
              let orderedHistoryFirstPrepared = orderedHistoryAllocator.prepare(
                  plan: inflightHistoryPlan,
                  orderingContext: .init(
                      commandBuffer: orderedHistoryFirstBuffer
                  )
              ), let orderedHistoryLease = orderedHistoryFirstPrepared.leases.first,
              let orderedHistoryEffect = orderedHistoryLease.table.plan.output.effect
        else { fatalError("ordered history setup failed") }
        let orderedHistoryTokens = Set(
            orderedHistoryLease.framebufferAllocation.resources.values.map(\.token)
        )
        guard !orderedHistoryTokens.isEmpty,
              let orderedHistoryFirstCommit = orderedHistoryFirstPrepared.commitAndPin(
                  historyTokensByEffect: [
                      orderedHistoryEffect: orderedHistoryTokens
                  ],
                  commandBuffer: orderedHistoryFirstBuffer
              ) else { fatalError("ordered history commit failed") }
        orderedHistoryFirstBuffer.commit()
        orderedHistoryFirstBuffer.waitUntilCompleted()
        guard let orderedHistorySecondBuffer = orderedQueue.makeCommandBuffer(),
              let orderedHistorySecondPrepared = orderedHistoryAllocator.prepare(
                  plan: inflightHistoryPlan,
                  orderingContext: .init(
                      commandBuffer: orderedHistorySecondBuffer
                  )
              ) else { fatalError("ordered history COW failed") }
        let historyOwnershipAlwaysUsesCopyOnWrite =
            !orderedHistoryFirstCommit.historyPinsByEffect.isEmpty
            && orderedHistoryFirstPrepared.leases[0].generation
                != orderedHistorySecondPrepared.leases[0].generation
            && physicalObjects(orderedHistoryFirstPrepared).isDisjoint(
                with: physicalObjects(orderedHistorySecondPrepared)
            )
        orderedHistoryFirstCommit.releaseAll()
        orderedHistoryCache.reset()

        inflightHistoryCommit1.historyPinsByEffect[inflightHistoryEffect]?.release()
        inflightHistoryCommit2.releaseAll()
        inflightHistoryCommit3.releaseAll()
        inflightHistoryCache.reset()

        let checks: [String: Any] = [
            "historyOwnershipAlwaysUsesCopyOnWrite":
                historyOwnershipAlwaysUsesCopyOnWrite,
        ]
        return checks
    }

    static func historyFailureChecks(
        _ device: MTLDevice
    ) -> (
        checks: [String: Any],
        historyFixture: Fixture,
        historyLease1: SceneGraphRenderTargetLease
    ) {
        let historyFixture = historySwapFixture(effectIndex: 100)
        let historyFixtures = [historyFixture]
        let historyPairPlan = pairPlan(historyFixtures)
        let historyGraphs = admittedGraphs(historyFixtures)
        let historyTargetPlans = targetPlans(
            historyFixtures, width: 64, height: 64
        )
        guard case .success(let historyPhysicalPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: historyTargetPlans,
                pairPlan: historyPairPlan,
                byteBudget: 100_000
            ) else { fatalError("history physical plan failed") }
        let historyPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        guard let historyPrepared1 = historyPool.preparePersistentGraphTargets(
            admittedGraphs: historyGraphs,
            pairPlan: historyPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ) else { fatalError("history first allocation failed") }
        guard historyPrepared1.historyRehydrateCopiesByEffect.isEmpty,
              let historyLease1 = historyPrepared1.leases.first,
              let historyEffect = historyLease1.table.plan.output.effect else {
            fatalError("history first lease failed")
        }
        let historyTransitionResult1 = SceneGraphExecutionState.reduce(
            graph: historyFixture.execution.renderGraph,
            targetPlan: historyLease1.table.plan,
            pairStep: historyPairPlan.effects[0],
            allocation: historyLease1.framebufferAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        )
        guard case .success(let historyTransition1) = historyTransitionResult1 else {
            if case .failure(let failure) = historyTransitionResult1 {
                fatalError("history first state failed: \(failure.rawValue)")
            }
            fatalError("history first transition failed")
        }
        let historyIdentity = historyFixture.framebufferIdentities[0]
        let scratchIdentity = historyFixture.framebufferIdentities[1]
        let historyClosure1 = historyTransition1.nextState.historyClosureIdentities
        let actualHistoryTokens1 = Set(historyClosure1.compactMap {
            historyTransition1.transaction.mappingAfter[$0]?.token
        })
        guard historyClosure1 == Set([historyIdentity, scratchIdentity]),
              historyPhysicalPlan.stages[0].historyClosureIdentities == historyClosure1,
              actualHistoryTokens1.count == historyClosure1.count,
              let actualHistoryToken1 = historyTransition1.transaction
                .mappingAfter[historyIdentity]?.token,
              let authoredHistoryToken = historyLease1.allocation
                .resources[historyIdentity]?.token,
              let authoredScratchToken = historyLease1.allocation
                .resources[scratchIdentity]?.token,
              let historyTexture1 = historyLease1.texturesByToken[actualHistoryToken1],
              let historyCommit1 = historyPrepared1.commitAndPin(
                  historyTokensByEffect: [historyEffect: actualHistoryTokens1]
              ), clear(
                  historyTexture1,
                  color: MTLClearColorMake(1, 0, 0, 1),
                  device: device
              ), let committedHistoryPixel = pixel(
                  historyTexture1, device: device
              ) else { fatalError("dynamic history commit failed") }
        let historySwapPinnedFinalMapping = actualHistoryToken1 != authoredHistoryToken
            && actualHistoryToken1 == authoredScratchToken
            && historyCommit1.historyPinsByEffect[historyEffect]?.purpose
                == .history(historyEffect, actualHistoryTokens1)
        let historyClosureContractAligned = historyClosure1.count == 2
            && historyPhysicalPlan.historyEffects == Set([historyEffect])
        historyCommit1.submissionPin.release()

        let sharedHistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        guard let sharedHistoryQueue = device.makeCommandQueue(),
              let sharedHistoryBuffer1 = sharedHistoryQueue.makeCommandBuffer(),
              let sharedHistoryPlan1 = sharedHistoryPool
                .framePlanForPersistentGraphTargets(
                    admittedGraphs: historyGraphs,
                    pairPlan: historyPairPlan,
                    requestedWidth: 64,
                    requestedHeight: 64,
                    usesSharedFullFrameWorkingPair: true,
                    orderingContext: .init(commandBuffer: sharedHistoryBuffer1)
                ), sharedHistoryPool.preflightPersistentGraphTargets([
                    sharedHistoryPlan1,
                ]) == .ready,
              let sharedHistoryPrepared1 = sharedHistoryPool
                .preparePersistentGraphTargets(framePlan: sharedHistoryPlan1),
              let sharedHistoryLease1 = sharedHistoryPrepared1.leases.first else {
            fatalError("shared history first frame failed")
        }
        let sharedHistoryTransitionResult1 = SceneGraphExecutionState.reduce(
            graph: historyFixture.execution.renderGraph,
            targetPlan: sharedHistoryLease1.table.plan,
            pairStep: historyPairPlan.effects[0],
            allocation: sharedHistoryLease1.framebufferAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        )
        guard case .success(let sharedHistoryTransition1) =
                sharedHistoryTransitionResult1 else {
            fatalError("shared history first transition failed")
        }
        let sharedHistoryTokens1 = Set(
            sharedHistoryTransition1.nextState.historyClosureIdentities.compactMap {
                sharedHistoryTransition1.transaction.mappingAfter[$0]?.token
            }
        )
        guard sharedHistoryTokens1.count == 2,
              let sharedHistoryCommit1 = sharedHistoryPrepared1.commitAndPin(
                  historyTokensByEffect: [historyEffect: sharedHistoryTokens1],
                  commandBuffer: sharedHistoryBuffer1
              ) else { fatalError("shared history first commit failed") }
        let sharedPairGeneration1 = sharedHistoryLease1.fullFramePairGeneration
        sharedHistoryBuffer1.commit()
        sharedHistoryBuffer1.waitUntilCompleted()
        sharedHistoryCommit1.submissionPin.release()
        sharedHistoryCommit1.sharedPairPin?.release()

        guard let sharedHistoryBuffer2 = sharedHistoryQueue.makeCommandBuffer(),
              let sharedHistoryPlan2 = sharedHistoryPool
                .framePlanForPersistentGraphTargets(
                    admittedGraphs: historyGraphs,
                    pairPlan: historyPairPlan,
                    requestedWidth: 64,
                    requestedHeight: 64,
                    usesSharedFullFrameWorkingPair: true,
                    orderingContext: .init(commandBuffer: sharedHistoryBuffer2)
                ), sharedHistoryPool.preflightPersistentGraphTargets([
                    sharedHistoryPlan2,
                ]) == .ready,
              let sharedHistoryPrepared2 = sharedHistoryPool
                .preparePersistentGraphTargets(framePlan: sharedHistoryPlan2),
              let sharedHistoryLease2 = sharedHistoryPrepared2.leases.first,
              let sharedHistoryCopies2 = sharedHistoryPrepared2
                .historyRehydrateCopiesByEffect[historyEffect],
              sharedHistoryCopies2.count == 2 else {
            fatalError("shared history second frame failed")
        }
        let sharedPairSlots = Set([
            sharedHistoryPlan2.graphPlan.fullFramePair.zeroSlot,
            sharedHistoryPlan2.graphPlan.fullFramePair.oneSlot,
        ])
        let sharedHistorySlots = Set(
            sharedHistoryPlan2.graphPlan.slots.compactMap {
                $0.historyEffect == nil ? nil : $0.id
            }
        )
        let sharedPairTokens2 = Set([
            sharedHistoryLease2.fullFramePair.first,
            sharedHistoryLease2.fullFramePair.second,
        ])
        let sharedHistoryTargetTokens2 = Set(
            sharedHistoryCopies2.map(\.targetToken)
        )
        guard let sharedHistoryCommit2 = sharedHistoryPrepared2.commitAndPin(
            historyTokensByEffect: [historyEffect: sharedHistoryTargetTokens2],
            commandBuffer: sharedHistoryBuffer2
        ) else { fatalError("shared history second commit failed") }
        let sharedHistoryUsesPrivateFBOResidency =
            sharedHistoryPlan1.graphPlan.pairStorage == .shared
                && sharedHistoryPlan2.graphPlan.pairStorage == .shared
                && sharedHistoryPlan2.graphPlan.residentByteCost
                    == sharedHistoryPlan2.graphPlan.historyByteCost
                && sharedHistoryPool.allocationCache.locked {
                    sharedHistoryPool.allocationCache.residents[
                        .current(.sharedGraphPair(width: 64, height: 64))
                    ]?.byteCost == 32_768
                }
                && sharedHistorySlots.isDisjoint(with: sharedPairSlots)
                && sharedHistoryTargetTokens2.isDisjoint(with: sharedPairTokens2)
                && Set(sharedHistoryCopies2.map(\.sourceToken))
                    == sharedHistoryTokens1
                && sharedHistoryLease2.fullFramePairGeneration
                    == sharedPairGeneration1
                && sharedHistoryLease2.generation
                    != sharedHistoryLease1.generation
        sharedHistoryBuffer2.commit()
        sharedHistoryBuffer2.waitUntilCompleted()
        sharedHistoryCommit1.historyPinsByEffect[historyEffect]?.release()
        sharedHistoryCommit2.releaseAll()
        sharedHistoryPool.reset()

        // A launch-time visual fallback may discard this frame's entire
        // uncommitted history candidate. The disposition is explicit so a
        // missing token cannot silently turn into the same operation.
        let discardHistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        guard let discardMissingMarker = discardHistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: historyGraphs,
                pairPlan: historyPairPlan,
                requestedWidth: 64,
                requestedHeight: 64
            ) else { fatalError("discard missing-marker fixture failed") }
        let discardHistoryRequiresTypedDisposition = discardMissingMarker
            .commitAndPin(historyTokensByEffect: [:]) == nil
                && discardHistoryPool.residentAllocationCount == 0

        guard let discardWithTokens = discardHistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: historyGraphs,
                pairPlan: historyPairPlan,
                requestedWidth: 64,
                requestedHeight: 64
            ), let discardWithTokensLease = discardWithTokens.leases.first else {
            fatalError("discard token conflict fixture failed")
        }
        let discardTokens = Set(
            discardWithTokensLease.framebufferAllocation.resources.values.map(\.token)
        )
        let discardHistoryRejectsSimultaneousPublication = discardWithTokens
            .commitAndPin(
                historyTokensByEffect: [historyEffect: discardTokens],
                discardedHistoryEffects: [historyEffect]
            ) == nil && discardHistoryPool.residentAllocationCount == 0

        guard let discardUnexpected = discardHistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: historyGraphs,
                pairPlan: historyPairPlan,
                requestedWidth: 64,
                requestedHeight: 64
            ) else { fatalError("discard unexpected-effect fixture failed") }
        let unexpectedDiscardEffect = Graph.EffectKey(
            layerID: historyEffect.layerID,
            effectIndex: historyEffect.effectIndex + 1,
            descriptorID: "unexpected-discard"
        )
        let discardHistoryRejectsUnexpectedEffect = discardUnexpected.commitAndPin(
            historyTokensByEffect: [:],
            discardedHistoryEffects: [unexpectedDiscardEffect]
        ) == nil && discardHistoryPool.residentAllocationCount == 0

        guard let discardedPrepared = discardHistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: historyGraphs,
                pairPlan: historyPairPlan,
                requestedWidth: 64,
                requestedHeight: 64
            ), let discardedCommit = discardedPrepared.commitAndPin(
                historyTokensByEffect: [:],
                discardedHistoryEffects: [historyEffect]
            ) else { fatalError("typed history discard commit failed") }
        let typedHistoryDiscardKeepsSubmissionWithoutHistoryPin =
            discardedCommit.historyPinsByEffect.isEmpty
                && discardedCommit.submissionPin.purpose == .submission
                && discardHistoryPool.residentAllocationCount == 1
        discardedCommit.releaseAll()
        guard let discardedRecovery = discardHistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: historyGraphs,
                pairPlan: historyPairPlan,
                requestedWidth: 64,
                requestedHeight: 64
            ) else { fatalError("typed history discard recovery failed") }
        let typedHistoryDiscardDoesNotPublishHistorySeed =
            discardedRecovery.historyRehydrateCopiesByEffect.isEmpty
        discardHistoryPool.reset()
        guard let historyMissingPrepared = historyPool.preparePersistentGraphTargets(
            admittedGraphs: historyGraphs,
            pairPlan: historyPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ), let historyMissingCopies = historyMissingPrepared
            .historyRehydrateCopiesByEffect[historyEffect],
              historyMissingCopies.count == 2,
              let missingToken = historyMissingCopies.first?.targetToken else {
            fatalError("history missing-token fixture failed")
        }
        let historyMissingTokenRejected = historyMissingPrepared.commitAndPin(
            historyTokensByEffect: [historyEffect: [missingToken]]
        ) == nil
        guard let historyExtraPrepared = historyPool.preparePersistentGraphTargets(
            admittedGraphs: historyGraphs,
            pairPlan: historyPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ), let historyExtraCopies = historyExtraPrepared
            .historyRehydrateCopiesByEffect[historyEffect],
              historyExtraCopies.count == 2,
              let historyExtraLease = historyExtraPrepared.leases.first else {
            fatalError("history extra-token fixture failed")
        }
        var extraHistoryTokens = Set(historyExtraCopies.map(\.targetToken))
        extraHistoryTokens.insert(historyExtraLease.fullFramePair.first)
        let historyExtraTokenRejected = historyExtraPrepared.commitAndPin(
            historyTokensByEffect: [historyEffect: extraHistoryTokens]
        ) == nil
        guard let historyPrepared2 = historyPool.preparePersistentGraphTargets(
            admittedGraphs: historyGraphs,
            pairPlan: historyPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ), let historyLease2 = historyPrepared2.leases.first,
              let historyCopies2 = historyPrepared2
                .historyRehydrateCopiesByEffect[historyEffect],
              historyCopies2.count == 2,
              let historyCopy2 = historyCopies2.first(where: {
                  $0.sourceToken == actualHistoryToken1
              }),
              historyCopy2.sourceToken == actualHistoryToken1,
              historyCopy2.sourceTexture === historyTexture1,
              historyCopy2.targetToken != actualHistoryToken1,
              historyCopy2.targetTexture !== historyTexture1,
              historyLease2.texturesByToken[historyCopy2.targetToken]
                === historyCopy2.targetTexture,
              clear(
                  historyCopy2.targetTexture,
                  color: MTLClearColorMake(0, 1, 0, 1),
                  device: device
              ), let sourcePixelAfterCurrentWrite = pixel(
                  historyCopy2.sourceTexture, device: device
              ), let targetPixelAfterCurrentWrite = pixel(
                  historyCopy2.targetTexture, device: device
              ),
              let historyCommit2 = historyPrepared2.commitAndPin(
                  historyTokensByEffect: [
                      historyEffect: Set(historyCopies2.map(\.targetToken))
                  ]
              ) else { fatalError("history copy-on-write prepare failed") }
        let rehydrateGenerationChanged = historyLease2.generation
            > historyLease1.generation
        let historyCopyOnWriteIsolated = historyCopy2.sourceTexture !== historyCopy2.targetTexture
            && historyCopy2.sourceToken != historyCopy2.targetToken
        let partialGPUWritePreservedCommittedPixels = sourcePixelAfterCurrentWrite
                == committedHistoryPixel
            && targetPixelAfterCurrentWrite != committedHistoryPixel
        // Simulate GPU failure: discard every pin produced by submission 2.
        historyCommit2.historyPinsByEffect[historyEffect]?.release()
        historyCommit2.submissionPin.release()
        guard let historyPrepared3 = historyPool.preparePersistentGraphTargets(
            admittedGraphs: historyGraphs,
            pairPlan: historyPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ), let historyLease3 = historyPrepared3.leases.first,
              let historyCopies3 = historyPrepared3
                .historyRehydrateCopiesByEffect[historyEffect],
              historyCopies3.count == 2,
              let historyCopy3 = historyCopies3.first(where: {
                  $0.sourceToken == actualHistoryToken1
              }),
              historyCopy3.sourceToken == actualHistoryToken1,
              historyCopy3.sourceTexture === historyTexture1,
              pixel(historyCopy3.sourceTexture, device: device)
                == committedHistoryPixel,
              historyCopy3.targetToken != historyCopy2.targetToken,
              historyLease3.generation > historyLease2.generation,
              let historyCommit3 = historyPrepared3.commitAndPin(
                  historyTokensByEffect: [
                      historyEffect: Set(historyCopies3.map(\.targetToken))
                  ]
              ) else { fatalError("history failure rollback seed was polluted") }
        let gpuFailurePreservedCommittedHistory = historyCopy3.sourceToken
                == actualHistoryToken1
            && historyCopy3.sourceTexture === historyTexture1
        historyCommit1.historyPinsByEffect[historyEffect]?.release()
        historyCommit3.submissionPin.release()
        historyPool.reset()
        let resetRetainedOnlyDynamicHistory = historyPool.residentAllocationCount == 1
            && historyPool.residentTextureCount == 2
            && historyPool.residentByteCost == 32_768
        historyCommit3.historyPinsByEffect[historyEffect]?.release()
        let finalReleaseClearedResidency = historyPool.residentAllocationCount == 0
            && historyPool.residentTextureCount == 0
            && historyPool.residentByteCost == 0

        let checks: [String: Any] = [
            "historySwapPinnedFinalMapping": historySwapPinnedFinalMapping,
            "historyClosureContractAligned": historyClosureContractAligned,
            "sharedHistoryUsesPrivateFBOResidency":
                sharedHistoryUsesPrivateFBOResidency,
            "historyMissingTokenRejected": historyMissingTokenRejected,
            "historyExtraTokenRejected": historyExtraTokenRejected,
            "discardHistoryRequiresTypedDisposition":
                discardHistoryRequiresTypedDisposition,
            "discardHistoryRejectsSimultaneousPublication":
                discardHistoryRejectsSimultaneousPublication,
            "discardHistoryRejectsUnexpectedEffect":
                discardHistoryRejectsUnexpectedEffect,
            "typedHistoryDiscardKeepsSubmissionWithoutHistoryPin":
                typedHistoryDiscardKeepsSubmissionWithoutHistoryPin,
            "typedHistoryDiscardDoesNotPublishHistorySeed":
                typedHistoryDiscardDoesNotPublishHistorySeed,
            "historyCopyOnWriteIsolated": historyCopyOnWriteIsolated,
            "partialGPUWritePreservedCommittedPixels":
                partialGPUWritePreservedCommittedPixels,
            "gpuFailurePreservedCommittedHistory":
                gpuFailurePreservedCommittedHistory,
            "rehydrateGenerationChanged": rehydrateGenerationChanged,
            "resetRetainedOnlyDynamicHistory": resetRetainedOnlyDynamicHistory,
            "finalReleaseClearedResidency": finalReleaseClearedResidency,
        ]
        return (checks, historyFixture, historyLease1)
    }

    static func historyResizeChecks(
        _ device: MTLDevice
    ) -> [String: Any] {
        let fixedHistoryFixture = historySwapFixture(
            effectIndex: 103,
            extent: .init(kind: .absolute, first: 16, second: 16)
        )
        let fixedHistoryFixtures = [fixedHistoryFixture]
        let fixedHistoryGraphs = admittedGraphs(fixedHistoryFixtures)
        let fixedHistoryPairPlan = pairPlan(fixedHistoryFixtures)
        let fixedHistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        guard let fixedPrepared1 = fixedHistoryPool.preparePersistentGraphTargets(
            admittedGraphs: fixedHistoryGraphs,
            pairPlan: fixedHistoryPairPlan,
            requestedWidth: 64,
            requestedHeight: 64
        ), let fixedLease1 = fixedPrepared1.leases.first,
              let fixedEffect = fixedLease1.table.plan.output.effect,
              let fixedCommit1 = fixedPrepared1.commitAndPin(
                  historyTokensByEffect: [
                      fixedEffect: Set(fixedLease1.framebufferAllocation
                          .resources.values.map(\.token))
                  ]
              ) else { fatalError("fixed history first allocation failed") }
        let fixedHistoryTokens1 = Set(
            fixedLease1.framebufferAllocation.resources.values.map(\.token)
        )
        fixedCommit1.submissionPin.release()
        guard let fixedPrepared2 = fixedHistoryPool.preparePersistentGraphTargets(
            admittedGraphs: fixedHistoryGraphs,
            pairPlan: fixedHistoryPairPlan,
            requestedWidth: 32,
            requestedHeight: 32
        ), let fixedLease2 = fixedPrepared2.leases.first,
              let fixedCopies = fixedPrepared2
                .historyRehydrateCopiesByEffect[fixedEffect],
              fixedCopies.count == 2,
              let fixedPairTexture = fixedLease2.texturesByToken[
                  fixedLease2.fullFramePair.first
              ], let fixedCommit2 = fixedPrepared2.commitAndPin(
                  historyTokensByEffect: [
                      fixedEffect: Set(fixedCopies.map(\.targetToken))
                  ]
              ) else { fatalError("fixed history resize rehydrate failed") }
        let fixedHistorySurvivesPairResize =
            Set(fixedCopies.map(\.sourceToken)) == fixedHistoryTokens1
            && fixedCopies.allSatisfy {
                $0.sourceTexture.width == 16 && $0.sourceTexture.height == 16
                    && $0.targetTexture.width == 16
                    && $0.targetTexture.height == 16
            }
            && fixedPairTexture.width == 32 && fixedPairTexture.height == 32
        fixedCommit1.historyPinsByEffect[fixedEffect]?.release()
        fixedCommit2.releaseAll()
        fixedHistoryPool.reset()

        let resizedHistoryFixture = historySwapFixture(effectIndex: 104)
        let resizedHistoryFixtures = [resizedHistoryFixture]
        let resizedHistoryGraphs = admittedGraphs(resizedHistoryFixtures)
        let resizedHistoryPairPlan = pairPlan(resizedHistoryFixtures)
        let resizedHistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        guard let resizedPrepared1 =
            resizedHistoryPool.preparePersistentGraphTargets(
                admittedGraphs: resizedHistoryGraphs,
                pairPlan: resizedHistoryPairPlan,
                requestedWidth: 32,
                requestedHeight: 32
            ), let resizedLease1 = resizedPrepared1.leases.first,
              let resizedEffect = resizedLease1.table.plan.output.effect,
              let resizedCommit1 = resizedPrepared1.commitAndPin(
                  historyTokensByEffect: [
                      resizedEffect: Set(resizedLease1.framebufferAllocation
                          .resources.values.map(\.token))
                  ]
              ) else { fatalError("dynamic resize first allocation failed") }
        let resizedHistoryTokens1 = Set(
            resizedLease1.framebufferAllocation.resources.values.map(\.token)
        )
        resizedCommit1.submissionPin.release()
        guard let resizedPrepared2 =
            resizedHistoryPool.preparePersistentGraphTargets(
                admittedGraphs: resizedHistoryGraphs,
                pairPlan: resizedHistoryPairPlan,
                requestedWidth: 16,
                requestedHeight: 16
            ), resizedPrepared2.historyRehydrateCopiesByEffect.isEmpty,
              let resizedLease2 = resizedPrepared2.leases.first,
              let resizedCommit2 = resizedPrepared2.commitAndPin(
                  historyTokensByEffect: [
                      resizedEffect: Set(resizedLease2.framebufferAllocation
                          .resources.values.map(\.token))
                  ]
              ) else { fatalError("dynamic resize fresh allocation failed") }
        let resizedHistoryTokens2 = Set(
            resizedLease2.framebufferAllocation.resources.values.map(\.token)
        )
        let dynamicHistoryResizeStartsFresh =
            resizedHistoryTokens1.isDisjoint(with: resizedHistoryTokens2)
            && resizedLease2.framebufferAllocation.resources.values.allSatisfy {
                $0.descriptor.extent == .init(width: 16, height: 16)
            }
        resizedCommit1.historyPinsByEffect[resizedEffect]?.release()
        resizedCommit2.releaseAll()
        resizedHistoryPool.reset()

        let semanticHistoryV1 = historySwapFixture(
            effectIndex: 105,
            extent: .init(kind: .absolute, first: 16, second: 16)
        )
        let semanticHistoryV2 = historySwapFixture(
            effectIndex: 105,
            namePrefix: "v2-",
            extent: .init(kind: .absolute, first: 16, second: 16)
        )
        let semanticHistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 100_000
        )
        let semanticPlanV1 = pairPlan([semanticHistoryV1])
        guard let semanticPrepared1 =
            semanticHistoryPool.preparePersistentGraphTargets(
                admittedGraphs: admittedGraphs([semanticHistoryV1]),
                pairPlan: semanticPlanV1,
                requestedWidth: 32,
                requestedHeight: 32
            ), let semanticLease1 = semanticPrepared1.leases.first,
              let semanticEffect = semanticLease1.table.plan.output.effect,
              let semanticCommit1 = semanticPrepared1.commitAndPin(
                  historyTokensByEffect: [
                      semanticEffect: Set(semanticLease1.framebufferAllocation
                          .resources.values.map(\.token))
                  ]
              ) else { fatalError("semantic history first allocation failed") }
        semanticCommit1.submissionPin.release()
        let semanticPlanV2 = pairPlan([semanticHistoryV2])
        guard let semanticPrepared2 =
            semanticHistoryPool.preparePersistentGraphTargets(
                admittedGraphs: admittedGraphs([semanticHistoryV2]),
                pairPlan: semanticPlanV2,
                requestedWidth: 32,
                requestedHeight: 32
            ), semanticPrepared2.historyRehydrateCopiesByEffect.isEmpty,
              let semanticLease2 = semanticPrepared2.leases.first,
              let semanticCommit2 = semanticPrepared2.commitAndPin(
                  historyTokensByEffect: [
                      semanticEffect: Set(semanticLease2.framebufferAllocation
                          .resources.values.map(\.token))
                  ]
              ) else { fatalError("semantic history replacement failed") }
        let changedHistorySemanticsDoNotSeed = Set(
            semanticLease1.framebufferAllocation.resources.keys
        ).isDisjoint(with: Set(
            semanticLease2.framebufferAllocation.resources.keys
        ))
        semanticCommit1.historyPinsByEffect[semanticEffect]?.release()
        semanticCommit2.releaseAll()
        semanticHistoryPool.reset()

        let checks: [String: Any] = [
            "fixedHistorySurvivesPairResize": fixedHistorySurvivesPairResize,
            "dynamicHistoryResizeStartsFresh": dynamicHistoryResizeStartsFresh,
            "changedHistorySemanticsDoNotSeed": changedHistorySemanticsDoNotSeed,
        ]
        return checks
    }
}
