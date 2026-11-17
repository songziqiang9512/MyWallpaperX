

import Foundation
import Metal

extension Harness {
    static func inFlightSlotChecks(
        _ device: MTLDevice,
        directFixtures: [Fixture],
        directPairPlan: SceneLayerFullFramePairPlan
    ) -> (
        checks: [String: Any],
        inflightPlan: SceneLayerGraphTargetPlan,
        inflightSlotCount: Int,
        orderedQueue: MTLCommandQueue
    ) {
        guard case .success(let inflightPlan) = SceneLayerGraphTargetPlan.make(
            plans: targetPlans(directFixtures, width: 8, height: 8),
            pairPlan: directPairPlan,
            byteBudget: 10_000
        ) else { fatalError("in-flight plan failed") }
        let inflightCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 3
        )
        let inflightSlotCount = inflightPlan.slots.count
        var inflightFactoryAttempts = 0
        let inflightAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: inflightCache
        ) { descriptor, label in
            inflightFactoryAttempts += 1
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = label
            return texture
        }
        guard let inflightPrepared1 = inflightAllocator.prepare(plan: inflightPlan),
              let inflightCommit1 = inflightPrepared1.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("first in-flight allocation failed") }
        let inflightTokens1 = Set(inflightPrepared1.leases.flatMap {
            Array($0.texturesByToken.keys)
        })
        let inflightObjects1 = Set(inflightPrepared1.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        guard let inflightPrepared2 = inflightAllocator.prepare(plan: inflightPlan),
              let inflightCommit2 = inflightPrepared2.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("second in-flight allocation failed") }
        let inflightTokens2 = Set(inflightPrepared2.leases.flatMap {
            Array($0.texturesByToken.keys)
        })
        let inflightObjects2 = Set(inflightPrepared2.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let inFlightAllocationsAreDistinct =
            inflightPrepared1.leases[0].generation
                != inflightPrepared2.leases[0].generation
            && inflightTokens1.isDisjoint(with: inflightTokens2)
            && inflightObjects1.isDisjoint(with: inflightObjects2)
            && inflightCache.residentAllocationCount == 2
        let attemptsAtCapacity = inflightFactoryAttempts
        let inFlightCapacityFailsBeforeAllocation =
            inflightAllocator.prepare(plan: inflightPlan) == nil
            && inflightFactoryAttempts == attemptsAtCapacity
            && SceneResolvedMaterialInFlightCapacity.maximumSubmissions == 2
        let requiredSharedResidencySurvivesTransientCapacityDeferral =
            SceneOffscreenTextureFramePreflight.evaluate(
                plans: [inflightPlan],
                residents: [
                    .init(
                        id: 0, location: .currentGraph(inflightPlan.key),
                        graphPlan: inflightPlan, history: nil,
                        demotedHistory: nil,
                        byteCost: inflightPlan.residentByteCost,
                        submissionPinCount: 1, historyPinCount: 0,
                        permitsOrderedReuse: false,
                        isResetInvalidated: false, lastAccess: 1,
                        existedBeforeFrame: true, requiredByFrame: false
                    ),
                    .init(
                        id: 1, location: .retired,
                        graphPlan: inflightPlan, history: nil,
                        demotedHistory: nil,
                        byteCost: inflightPlan.residentByteCost,
                        submissionPinCount: 1, historyPinCount: 0,
                        permitsOrderedReuse: false,
                        isResetInvalidated: false, lastAccess: 2,
                        existedBeforeFrame: true, requiredByFrame: false
                    ),
                    .init(
                        id: 2, location: .currentOther,
                        graphPlan: nil, history: nil, demotedHistory: nil,
                        byteCost: 128, submissionPinCount: 2,
                        historyPinCount: 0, permitsOrderedReuse: true,
                        isResetInvalidated: false, lastAccess: 3,
                        existedBeforeFrame: true, requiredByFrame: true
                    ),
                ],
                byteBudget: inflightPlan.residentByteCost * 2 + 128
            ) == .temporarilyBlocked
        inflightCommit1.submissionPin.release()
        guard let inflightPrepared3 = inflightAllocator.prepare(plan: inflightPlan),
              let inflightCommit3 = inflightPrepared3.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("first ring reuse failed") }
        let inflightTokens3 = Set(inflightPrepared3.leases.flatMap {
            Array($0.texturesByToken.keys)
        })
        let inflightObjects3 = Set(inflightPrepared3.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let firstIdleSlotReissuedFresh = inflightObjects3 == inflightObjects1
            && inflightPrepared3.leases[0].generation
                != inflightPrepared1.leases[0].generation
            && inflightTokens3.isDisjoint(with: inflightTokens1)
            && inflightTokens3.isDisjoint(with: inflightTokens2)
            && inflightFactoryAttempts == attemptsAtCapacity
            && inflightAllocator.prepare(plan: inflightPlan) == nil
        inflightCommit2.submissionPin.release()
        guard let inflightPrepared4 = inflightAllocator.prepare(plan: inflightPlan),
              let inflightCommit4 = inflightPrepared4.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("second ring reuse failed") }
        let inflightTokens4 = Set(inflightPrepared4.leases.flatMap {
            Array($0.texturesByToken.keys)
        })
        let inflightObjects4 = Set(inflightPrepared4.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let secondIdleSlotReissuedFresh = inflightObjects4 == inflightObjects2
            && inflightPrepared4.leases[0].generation
                != inflightPrepared2.leases[0].generation
            && inflightTokens4.isDisjoint(with: inflightTokens1)
            && inflightTokens4.isDisjoint(with: inflightTokens2)
            && inflightTokens4.isDisjoint(with: inflightTokens3)
        let stableTwoSlotRingAvoidsTextureChurn = firstIdleSlotReissuedFresh
            && secondIdleSlotReissuedFresh
            && inflightFactoryAttempts == inflightSlotCount * 2
            && Set([
                inflightPrepared1.leases[0].generation,
                inflightPrepared2.leases[0].generation,
                inflightPrepared3.leases[0].generation,
                inflightPrepared4.leases[0].generation,
            ]).count == 4

        inflightCache.reset()
        let resetRetainsOnlyPinnedGenerations =
            inflightCache.residentAllocationCount == 2
        inflightCommit3.submissionPin.release()
        let attemptsBeforeResetReplacement = inflightFactoryAttempts
        guard let resetPrepared = inflightAllocator.prepare(plan: inflightPlan),
              let resetCommit = resetPrepared.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("post-reset replacement failed") }
        let resetObjects = Set(resetPrepared.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let resetInvalidatedSlotNeverReentersRing =
            resetRetainsOnlyPinnedGenerations
            && inflightFactoryAttempts
                == attemptsBeforeResetReplacement + inflightSlotCount
            && resetObjects.isDisjoint(with: inflightObjects1)
            && resetObjects.isDisjoint(with: inflightObjects2)
        inflightCommit4.submissionPin.release()
        resetCommit.submissionPin.release()
        inflightCache.reset()

        let oneSlotBudgetCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        var oneSlotBudgetFactoryAttempts = 0
        let oneSlotBudgetAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: oneSlotBudgetCache
        ) { descriptor, _ in
            oneSlotBudgetFactoryAttempts += 1
            return device.makeTexture(descriptor: descriptor)
        }
        guard let oneSlotPrepared = oneSlotBudgetAllocator.prepare(plan: inflightPlan),
              let oneSlotCommit = oneSlotPrepared.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("single-budget first allocation failed") }
        let attemptsBeforeBudgetRejection = oneSlotBudgetFactoryAttempts
        let pinnedOneSlotFramePreflightDefers =
            oneSlotBudgetCache.preflightGraphs([inflightPlan])
                == .temporarilyBlocked
        let pinnedSecondSlotBudgetFailsBeforeAllocation =
            oneSlotBudgetAllocator.prepare(plan: inflightPlan) == nil
            && oneSlotBudgetFactoryAttempts == attemptsBeforeBudgetRejection
        oneSlotCommit.submissionPin.release()
        let releasedOneSlotFramePreflightReady =
            oneSlotBudgetCache.preflightGraphs([inflightPlan]) == .ready
        oneSlotBudgetCache.reset()

        guard let orderedQueue = device.makeCommandQueue() else {
            fatalError("same-queue fixture unavailable")
        }
        let pinnedPool = SceneOffscreenTexturePool(device: device,
            residentByteBudget: inflightPlan.residentByteCost)
        let ownBuffer = orderedQueue.makeCommandBuffer()!
        let ownTarget = pinnedPool.compositionGroupTarget(layerID: 42,
            width: 1, height: 1, commandBuffer: ownBuffer)!
        let ownPinRejects = pinnedPool.allocationCache.preflightGraphs([inflightPlan],
            orderingContext: .init(commandBuffer: ownBuffer))
                == .rejected(reasonCode: "frame-target-byte-budget-exceeded")
        let peerBuffer = orderedQueue.makeCommandBuffer()!
        let peerPinDefers = pinnedPool.allocationCache.preflightGraphs([inflightPlan],
            orderingContext: .init(commandBuffer: peerBuffer)) == .temporarilyBlocked
        ownTarget.pin.release()
        let releasedPinAdmits = pinnedPool.allocationCache.preflightGraphs([inflightPlan],
            orderingContext: .init(commandBuffer: ownBuffer)) == .ready
        let checks: [String: Any] = [
            "currentBufferPinMustFitBeforeSubmission": ownPinRejects && peerPinDefers && releasedPinAdmits,
            "inFlightAllocationsAreDistinct": inFlightAllocationsAreDistinct,
            "inFlightCapacityFailsBeforeAllocation":
                inFlightCapacityFailsBeforeAllocation,
            "requiredSharedResidencySurvivesTransientCapacityDeferral":
                requiredSharedResidencySurvivesTransientCapacityDeferral,
            "stableTwoSlotRingAvoidsTextureChurn":
                stableTwoSlotRingAvoidsTextureChurn,
            "resetInvalidatedSlotNeverReentersRing":
                resetInvalidatedSlotNeverReentersRing,
            "pinnedSecondSlotBudgetFailsBeforeAllocation":
                pinnedSecondSlotBudgetFailsBeforeAllocation,
            "pinnedOneSlotFramePreflightDefers":
                pinnedOneSlotFramePreflightDefers,
            "releasedOneSlotFramePreflightReady":
                releasedOneSlotFramePreflightReady,
        ]
        return (checks, inflightPlan, inflightSlotCount, orderedQueue)
    }

    static func queueOrderingChecks(
        _ device: MTLDevice,
        inflightPlan: SceneLayerGraphTargetPlan,
        orderedQueue: MTLCommandQueue
    ) -> [String: Any] {
        let orderedCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        let orderedAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: orderedCache
        )
        guard let orderedFirst = completedOrderedAllocation(
            allocator: orderedAllocator,
            plan: inflightPlan,
            queue: orderedQueue
        ), let orderedSecondBuffer = orderedQueue.makeCommandBuffer() else {
            fatalError("same-queue first submission failed")
        }
        let orderedSecondContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: orderedSecondBuffer
        )
        let orderedDryRunReady = orderedCache.preflightGraphs(
            [inflightPlan], orderingContext: orderedSecondContext
        ) == .ready
        guard let orderedSecondPrepared = orderedAllocator.prepare(
            plan: inflightPlan,
            orderingContext: orderedSecondContext
        ), let orderedSecondCommit = orderedSecondPrepared.commitAndPin(
            historyTokensByEffect: [:],
            commandBuffer: orderedSecondBuffer
        ) else { fatalError("same-queue reuse failed") }
        let sameQueueReusesOneTrackedPhysicalAllocation = orderedDryRunReady
            && orderedFirst.commandBuffer.status != .notEnqueued
            && orderedSecondBuffer.status == .notEnqueued
            && orderedFirst.prepared.leases[0].generation
                == orderedSecondPrepared.leases[0].generation
            && physicalObjects(orderedFirst.prepared)
                == physicalObjects(orderedSecondPrepared)
            && orderedCache.residentAllocationCount == 1
        orderedCache.reset()
        let sharedResetRetainsOneInvalidatedGeneration =
            orderedCache.residentAllocationCount == 1
            && orderedCache.preflightGraphs([inflightPlan])
                == .temporarilyBlocked
        orderedFirst.commit.submissionPin.release()
        let forwardReleasePreservesNewerPin =
            orderedCache.residentAllocationCount == 1
            && orderedCache.preflightGraphs([inflightPlan])
                == .temporarilyBlocked
        orderedSecondCommit.submissionPin.release()
        let forwardFinalReleaseReturnsIdle =
            orderedCache.residentAllocationCount == 0
            && orderedCache.preflightGraphs([inflightPlan]) == .ready

        let lateCommitCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        let lateCommitAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: lateCommitCache
        )
        guard let lateCommitFirst = completedOrderedAllocation(
            allocator: lateCommitAllocator,
            plan: inflightPlan,
            queue: orderedQueue
        ), let lateCommitBuffer = orderedQueue.makeCommandBuffer(),
              let lateCommitPrepared = lateCommitAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(commandBuffer: lateCommitBuffer)
              ) else { fatalError("late-commit setup failed") }
        lateCommitBuffer.commit()
        lateCommitBuffer.waitUntilCompleted()
        let submittedCurrentBufferRejectsSharedCommit = lateCommitPrepared
                .commitAndPin(
                    historyTokensByEffect: [:],
                    commandBuffer: lateCommitBuffer
                ) == nil
            && lateCommitCache.residentAllocationCount == 1
        lateCommitFirst.commit.submissionPin.release()
        let completedOrderingContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: lateCommitBuffer
        )
        var invalidOrderingFactoryAttempts = 0
        let invalidOrderingAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: lateCommitCache
        ) { descriptor, _ in
            invalidOrderingFactoryAttempts += 1
            return device.makeTexture(descriptor: descriptor)
        }
        let completedIdleContextRejected = lateCommitCache.preflightGraphs(
            [inflightPlan], orderingContext: completedOrderingContext
        ) == .rejected(reasonCode: "frame-target-ordering-context-invalid")
            && invalidOrderingAllocator.prepare(
                plan: inflightPlan,
                orderingContext: completedOrderingContext
            ) == nil
            && invalidOrderingFactoryAttempts == 0
        lateCommitCache.reset()
        let completedEmptyContextRejected = lateCommitCache.preflightGraphs(
            [inflightPlan], orderingContext: completedOrderingContext
        ) == .rejected(reasonCode: "frame-target-ordering-context-invalid")
            && invalidOrderingAllocator.prepare(
                plan: inflightPlan,
                orderingContext: completedOrderingContext
            ) == nil
            && invalidOrderingFactoryAttempts == 0
        let completedOrderingContextRejectedBeforeAllocation =
            completedIdleContextRejected && completedEmptyContextRejected

        let sameBufferBindingCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        let sameBufferBindingAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: sameBufferBindingCache
        )
        guard let preparedBufferA = orderedQueue.makeCommandBuffer(),
              let actualBufferB = orderedQueue.makeCommandBuffer() else {
            fatalError("same-queue binding buffers unavailable")
        }
        let preparedContextA = SceneGraphCommandQueueOrderingContext(
            commandBuffer: preparedBufferA
        )
        guard sameBufferBindingCache.preflightGraphs(
            [inflightPlan], orderingContext: preparedContextA
        ) == .ready,
              let preparedOnBufferA = sameBufferBindingAllocator.prepare(
                  plan: inflightPlan, orderingContext: preparedContextA
              ) else { fatalError("same-queue binding prepare failed") }
        let differentSameQueueBufferRejectsCommit = preparedOnBufferA.commitAndPin(
            historyTokensByEffect: [:], commandBuffer: actualBufferB
        ) == nil && sameBufferBindingCache.residentAllocationCount == 0

        guard let differentBindingQueue = device.makeCommandQueue(),
              let preparedDifferentQueueA = orderedQueue.makeCommandBuffer(),
              let actualDifferentQueueB = differentBindingQueue.makeCommandBuffer()
        else { fatalError("different-queue binding buffers unavailable") }
        let differentPreparedContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: preparedDifferentQueueA
        )
        guard let preparedForDifferentQueue = sameBufferBindingAllocator.prepare(
            plan: inflightPlan, orderingContext: differentPreparedContext
        ) else { fatalError("different-queue binding prepare failed") }
        let differentQueueBufferRejectsCommit = preparedForDifferentQueue.commitAndPin(
            historyTokensByEffect: [:], commandBuffer: actualDifferentQueueB
        ) == nil && sameBufferBindingCache.residentAllocationCount == 0

        let reverseOrderedCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        let reverseOrderedAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: reverseOrderedCache
        )
        guard let reverseOrderedFirst = completedOrderedAllocation(
            allocator: reverseOrderedAllocator,
            plan: inflightPlan,
            queue: orderedQueue
        ), let reverseOrderedBuffer = orderedQueue.makeCommandBuffer(),
              let reverseOrderedPrepared = reverseOrderedAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(
                      commandBuffer: reverseOrderedBuffer
                  )
              ), let reverseOrderedCommit = reverseOrderedPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: reverseOrderedBuffer
              ) else { fatalError("reverse ordered reuse failed") }
        reverseOrderedCommit.submissionPin.release()
        let reverseReleasePreservesOlderPin =
            reverseOrderedCache.residentAllocationCount == 1
            && reverseOrderedCache.preflightGraphs([inflightPlan])
                == .temporarilyBlocked
        reverseOrderedFirst.commit.submissionPin.release()
        let reverseFinalReleaseReturnsIdle =
            reverseOrderedCache.preflightGraphs([inflightPlan]) == .ready
        reverseOrderedCache.reset()

        let thirdPinCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        var thirdPinFactoryAttempts = 0
        let thirdPinAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: thirdPinCache
        ) { descriptor, _ in
            thirdPinFactoryAttempts += 1
            return device.makeTexture(descriptor: descriptor)
        }
        guard let thirdPinFirst = completedOrderedAllocation(
            allocator: thirdPinAllocator,
            plan: inflightPlan,
            queue: orderedQueue
        ), let thirdPinSecondBuffer = orderedQueue.makeCommandBuffer(),
              let thirdPinSecondPrepared = thirdPinAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(
                      commandBuffer: thirdPinSecondBuffer
                  )
              ), let thirdPinSecondCommit = thirdPinSecondPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: thirdPinSecondBuffer
              ) else { fatalError("third-pin setup failed") }
        thirdPinSecondBuffer.commit()
        thirdPinSecondBuffer.waitUntilCompleted()
        guard let thirdPinBuffer = orderedQueue.makeCommandBuffer() else {
            fatalError("third-pin buffer unavailable")
        }
        let thirdPinContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: thirdPinBuffer
        )
        let attemptsBeforeThirdPin = thirdPinFactoryAttempts
        let thirdPinRejectedBeforeAllocation =
            thirdPinCache.preflightGraphs(
                [inflightPlan], orderingContext: thirdPinContext
            ) == .temporarilyBlocked
            && thirdPinAllocator.prepare(
                plan: inflightPlan,
                orderingContext: thirdPinContext
            ) == nil
            && thirdPinFactoryAttempts == attemptsBeforeThirdPin
            && thirdPinFirst.prepared.leases[0].generation
                == thirdPinSecondPrepared.leases[0].generation
            && physicalObjects(thirdPinFirst.prepared)
                == physicalObjects(thirdPinSecondPrepared)
            && thirdPinCache.residentAllocationCount == 1
        thirdPinFirst.commit.submissionPin.release()
        let releasingOneSharedPinKeepsOtherGenerationResident =
            thirdPinCache.residentAllocationCount == 1
        thirdPinSecondCommit.submissionPin.release()
        thirdPinCache.reset()

        guard let differentQueueA = device.makeCommandQueue(),
              let differentQueueB = device.makeCommandQueue() else {
            fatalError("different-queue fixture unavailable")
        }
        let differentQueueCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        let differentQueueAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: differentQueueCache
        )
        guard let differentQueueFirst = completedOrderedAllocation(
            allocator: differentQueueAllocator,
            plan: inflightPlan,
            queue: differentQueueA
        ), let differentQueueBuffer = differentQueueB.makeCommandBuffer(),
              let differentQueuePrepared = differentQueueAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(commandBuffer: differentQueueBuffer)
              ), let differentQueueCommit = differentQueuePrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: differentQueueBuffer
              ) else { fatalError("different-queue COW failed") }
        let differentQueueStaysCopyOnWrite =
            differentQueueFirst.prepared.leases[0].generation
                != differentQueuePrepared.leases[0].generation
            && physicalObjects(differentQueueFirst.prepared).isDisjoint(
                with: physicalObjects(differentQueuePrepared)
            )
        differentQueueFirst.commit.submissionPin.release()
        differentQueueCommit.submissionPin.release()
        differentQueueCache.reset()

        let notEnqueuedCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        let notEnqueuedAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: notEnqueuedCache
        )
        guard let oldNotEnqueuedBuffer = orderedQueue.makeCommandBuffer(),
              let oldNotEnqueuedPrepared = notEnqueuedAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(commandBuffer: oldNotEnqueuedBuffer)
              ), let oldNotEnqueuedCommit = oldNotEnqueuedPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: oldNotEnqueuedBuffer
              ), let newNotEnqueuedBuffer = orderedQueue.makeCommandBuffer(),
              let newNotEnqueuedPrepared = notEnqueuedAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(commandBuffer: newNotEnqueuedBuffer)
              ), let newNotEnqueuedCommit = newNotEnqueuedPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: newNotEnqueuedBuffer
              ) else { fatalError("not-enqueued COW failed") }
        let oldNotEnqueuedStaysCopyOnWrite =
            oldNotEnqueuedBuffer.status == .notEnqueued
            && oldNotEnqueuedPrepared.leases[0].generation
                != newNotEnqueuedPrepared.leases[0].generation
            && physicalObjects(oldNotEnqueuedPrepared).isDisjoint(
                with: physicalObjects(newNotEnqueuedPrepared)
            )
        oldNotEnqueuedCommit.submissionPin.release()
        newNotEnqueuedCommit.submissionPin.release()
        notEnqueuedCache.reset()

        let untrackedCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        let untrackedAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: untrackedCache
        ) { descriptor, _ in
            descriptor.hazardTrackingMode = .untracked
            return device.makeTexture(descriptor: descriptor)
        }
        guard let untrackedFirst = completedOrderedAllocation(
            allocator: untrackedAllocator,
            plan: inflightPlan,
            queue: orderedQueue
        ), let untrackedBuffer = orderedQueue.makeCommandBuffer(),
              let untrackedPrepared = untrackedAllocator.prepare(
                  plan: inflightPlan,
                  orderingContext: .init(commandBuffer: untrackedBuffer)
              ) else { fatalError("untracked COW failed") }
        let untrackedStaysCopyOnWrite = untrackedFirst.prepared.leases
                .flatMap(\.texturesByToken.values)
                .allSatisfy { $0.hazardTrackingMode == .untracked }
            && untrackedFirst.prepared.leases[0].generation
                != untrackedPrepared.leases[0].generation
            && physicalObjects(untrackedFirst.prepared).isDisjoint(
                with: physicalObjects(untrackedPrepared)
            )
        untrackedFirst.commit.submissionPin.release()
        untrackedCache.reset()

        let checks: [String: Any] = [
            "sameQueueReusesOneTrackedPhysicalAllocation":
                sameQueueReusesOneTrackedPhysicalAllocation,
            "sharedResetRetainsOneInvalidatedGeneration":
                sharedResetRetainsOneInvalidatedGeneration,
            "forwardReleasePreservesNewerPin":
                forwardReleasePreservesNewerPin,
            "forwardFinalReleaseReturnsIdle":
                forwardFinalReleaseReturnsIdle,
            "submittedCurrentBufferRejectsSharedCommit":
                submittedCurrentBufferRejectsSharedCommit,
            "completedOrderingContextRejectedBeforeAllocation":
                completedOrderingContextRejectedBeforeAllocation,
            "differentSameQueueBufferRejectsCommit":
                differentSameQueueBufferRejectsCommit,
            "differentQueueBufferRejectsCommit":
                differentQueueBufferRejectsCommit,
            "reverseReleasePreservesOlderPin":
                reverseReleasePreservesOlderPin,
            "reverseFinalReleaseReturnsIdle":
                reverseFinalReleaseReturnsIdle,
            "thirdPinRejectedBeforeAllocation":
                thirdPinRejectedBeforeAllocation,
            "releasingOneSharedPinKeepsOtherGenerationResident":
                releasingOneSharedPinKeepsOtherGenerationResident,
            "differentQueueStaysCopyOnWrite":
                differentQueueStaysCopyOnWrite,
            "oldNotEnqueuedStaysCopyOnWrite":
                oldNotEnqueuedStaysCopyOnWrite,
            "untrackedStaysCopyOnWrite": untrackedStaysCopyOnWrite,
        ]
        return checks
    }

    static func residencyPressureChecks(
        _ device: MTLDevice,
        inflightPlan: SceneLayerGraphTargetPlan,
        inflightSlotCount: Int
    ) -> [String: Any] {
        let reverseCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        let reverseAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: reverseCache
        )
        guard let reversePrepared1 = reverseAllocator.prepare(plan: inflightPlan),
              let reverseCommit1 = reversePrepared1.commitAndPin(
                  historyTokensByEffect: [:]
              ), let reversePrepared2 = reverseAllocator.prepare(plan: inflightPlan),
              let reverseCommit2 = reversePrepared2.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("reverse-release setup failed") }
        let reverseObjects1 = Set(reversePrepared1.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let reverseObjects2 = Set(reversePrepared2.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        reverseCommit2.submissionPin.release()
        guard let reversePrepared3 = reverseAllocator.prepare(plan: inflightPlan),
              let reverseCommit3 = reversePrepared3.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("reverse-release reuse failed") }
        let reverseObjects3 = Set(reversePrepared3.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let reverseReleaseNeverReusesPinnedSlot =
            reverseObjects3 == reverseObjects2
            && reverseObjects3.isDisjoint(with: reverseObjects1)
            && reversePrepared3.leases[0].generation
                == reversePrepared2.leases[0].generation
            && reverseAllocator.prepare(plan: inflightPlan) == nil
        reverseCommit1.submissionPin.release()
        reverseCommit3.submissionPin.release()
        reverseCache.reset()

        let idleLRUCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost * 2
        )
        var idleLRUFactoryAttempts = 0
        let idleLRUAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: idleLRUCache
        ) { descriptor, _ in
            idleLRUFactoryAttempts += 1
            return device.makeTexture(descriptor: descriptor)
        }
        guard let idlePrepared1 = idleLRUAllocator.prepare(plan: inflightPlan),
              let idleCommit1 = idlePrepared1.commitAndPin(
                  historyTokensByEffect: [:]
              ), let idlePrepared2 = idleLRUAllocator.prepare(plan: inflightPlan),
              let idleCommit2 = idlePrepared2.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("idle LRU setup failed") }
        idleCommit1.submissionPin.release()
        idleCommit2.submissionPin.release()
        let pressureFirst = directFixture(effectIndex: 53)
        let pressureSecond = directFixture(
            effectIndex: 54,
            input: pressureFirst.execution.renderGraph.finalOutput
        )
        let pressureThird = directFixture(
            effectIndex: 55,
            input: pressureSecond.execution.renderGraph.finalOutput
        )
        let pressureFixtures = [pressureFirst, pressureSecond, pressureThird]
        guard case .success(let pressurePlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(pressureFixtures, width: 8, height: 8),
                pairPlan: pairPlan(pressureFixtures),
                byteBudget: 10_000
            ), pressurePlan.key != inflightPlan.key,
              pressurePlan.residentByteCost == inflightPlan.residentByteCost,
              let pressurePrepared = idleLRUAllocator.prepare(plan: pressurePlan),
              let pressureCommit = pressurePrepared.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("idle LRU pressure failed") }
        let aggregateFrameCache = SceneOffscreenTextureAllocationCache(
            byteBudget: inflightPlan.residentByteCost
        )
        let aggregateFrameHardOverBudget =
            aggregateFrameCache.preflightGraphs([inflightPlan, pressurePlan])
                == .rejected(reasonCode: "frame-target-byte-budget-exceeded")
        let aggregateFrameReadyAtExactBudget =
            SceneOffscreenTextureAllocationCache(
                byteBudget: inflightPlan.residentByteCost * 2
            ).preflightGraphs([inflightPlan, pressurePlan]) == .ready

        let mixedHistoryFixture = historySwapFixture(effectIndex: 56)
        let mixedHistoryFixtures = [mixedHistoryFixture]
        guard case .success(let mixedHistoryPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(mixedHistoryFixtures, width: 8, height: 8),
                pairPlan: pairPlan(mixedHistoryFixtures),
                byteBudget: 10_000
            ) else { fatalError("mixed history plan failed") }
        let mixedBudget = mixedHistoryPlan.residentByteCost
        let mixedCache = SceneOffscreenTextureAllocationCache(
            byteBudget: mixedBudget
        )
        let mixedAllocator = ScenePersistentGraphTargetAllocator(
            device: device, cache: mixedCache
        )
        guard let mixedHistoryPrepared = mixedAllocator.prepare(
            plan: mixedHistoryPlan
        ), let mixedHistoryLease = mixedHistoryPrepared.leases.first,
              let mixedHistoryEffect = mixedHistoryLease.table.plan.output.effect
        else { fatalError("mixed history allocation failed") }
        let mixedHistoryTokens = Set(
            mixedHistoryLease.framebufferAllocation.resources.values.map(\.token)
        )
        guard let mixedHistoryCommit = mixedHistoryPrepared.commitAndPin(
            historyTokensByEffect: [mixedHistoryEffect: mixedHistoryTokens]
        ) else { fatalError("mixed history commit failed") }
        mixedHistoryCommit.submissionPin.release()

        let mixedTransientFixture = directFixture(effectIndex: 57)
        let mixedTransientFixtures = [mixedTransientFixture]
        guard case .success(let mixedTransientPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(
                    mixedTransientFixtures, width: 4, height: 4
                ),
                pairPlan: pairPlan(mixedTransientFixtures),
                byteBudget: 10_000
            ), let mixedTransientPrepared = mixedAllocator.prepare(
                plan: mixedTransientPlan
            ), let mixedTransientCommit = mixedTransientPrepared.commitAndPin(
                historyTokensByEffect: [:]
            ) else { fatalError("mixed transient allocation failed") }
        let residualHistoryCost = mixedCache.residentByteCost
            - mixedTransientPlan.residentByteCost

        let mixedIncomingFixture = directFixture(effectIndex: 58)
        let mixedIncomingFixtures = [mixedIncomingFixture]
        guard case .success(let mixedIncomingPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(
                    mixedIncomingFixtures, width: 11, height: 11
                ),
                pairPlan: pairPlan(mixedIncomingFixtures),
                byteBudget: 10_000
            ) else { fatalError("mixed incoming plan failed") }
        let mixedHistoryAndTransientRejectsImmediately =
            residualHistoryCost > 0
            && mixedIncomingPlan.residentByteCost <= mixedBudget
            && residualHistoryCost + mixedIncomingPlan.residentByteCost
                > mixedBudget
            && mixedCache.preflightGraphs([mixedIncomingPlan])
                == .rejected(
                    reasonCode: "frame-target-residency-unavailable"
                )
        mixedTransientCommit.submissionPin.release()
        let mixedHistoryRemainsHardAfterTransientRelease =
            mixedCache.preflightGraphs([mixedIncomingPlan])
                == .rejected(
                    reasonCode: "frame-target-residency-unavailable"
                )
        mixedHistoryCommit.historyPinsByEffect.values.forEach { $0.release() }
        let mixedFrameReadyAfterHistoryRelease =
            mixedCache.preflightGraphs([mixedIncomingPlan]) == .ready
        mixedCache.reset()

        let attemptsAfterPressure = idleLRUFactoryAttempts
        guard let cachedIdlePrepared = idleLRUAllocator.prepare(plan: inflightPlan),
              let cachedIdleCommit = cachedIdlePrepared.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("idle LRU current hit failed") }
        pressureCommit.submissionPin.release()
        guard let replacementPrepared = idleLRUAllocator.prepare(plan: inflightPlan),
              let replacementCommit = replacementPrepared.commitAndPin(
                  historyTokensByEffect: [:]
              ) else { fatalError("idle LRU replacement failed") }
        let idleRetiredLRUEvictableUnderOtherChainPressure =
            attemptsAfterPressure == inflightSlotCount * 3
            && idleLRUFactoryAttempts == inflightSlotCount * 4
            && idleLRUCache.residentAllocationCount == 2
            && idleLRUCache.residentByteCost
                <= inflightPlan.residentByteCost * 2
        cachedIdleCommit.submissionPin.release()
        replacementCommit.submissionPin.release()
        idleLRUCache.reset()

        let checks: [String: Any] = [
            "reverseReleaseNeverReusesPinnedSlot":
                reverseReleaseNeverReusesPinnedSlot,
            "idleRetiredLRUEvictableUnderOtherChainPressure":
                idleRetiredLRUEvictableUnderOtherChainPressure,
            "aggregateFrameHardOverBudget": aggregateFrameHardOverBudget,
            "aggregateFrameReadyAtExactBudget":
                aggregateFrameReadyAtExactBudget,
            "mixedHistoryAndTransientRejectsImmediately":
                mixedHistoryAndTransientRejectsImmediately,
            "mixedHistoryRemainsHardAfterTransientRelease":
                mixedHistoryRemainsHardAfterTransientRelease,
            "mixedFrameReadyAfterHistoryRelease":
                mixedFrameReadyAfterHistoryRelease,
        ]
        return checks
    }

    static func frameScratchOrderingChecks(_ device: MTLDevice) throws -> [[String: Any]] {
        enum ProbeFailure: Error { case failed(String) }
        typealias Target = SceneOffscreenTexturePool.PinnedTexture

        func queue(_ device: MTLDevice) throws -> MTLCommandQueue {
            guard let queue = device.makeCommandQueue() else { throw ProbeFailure.failed("queue") }
            return queue
        }
        func buffer(_ queue: MTLCommandQueue, _ buffers: inout [MTLCommandBuffer]) throws -> MTLCommandBuffer {
            guard let buffer = queue.makeCommandBuffer() else { throw ProbeFailure.failed("buffer") }
            buffers.append(buffer)
            return buffer
        }
        func drain(_ buffers: [MTLCommandBuffer]) {
            for buffer in buffers where buffer.status == .notEnqueued || buffer.status == .enqueued { buffer.commit() }
            for buffer in buffers { buffer.waitUntilCompleted() }
        }
        func complete(_ buffers: [MTLCommandBuffer]) throws {
            for buffer in buffers { buffer.waitUntilCompleted() }
            guard buffers.allSatisfy({ $0.status == .completed && $0.error == nil }) else {
                throw ProbeFailure.failed("GPU completion: \(buffers.map { String(describing: $0.error) })")
            }
        }
        func reserve(_ pool: SceneOffscreenTexturePool, _ buffer: MTLCommandBuffer,
                            factory: ((MTLTextureDescriptor) -> MTLTexture?)? = nil, composition: Bool = false) throws -> Target {
            if composition {
                guard let target = pool.compositionTarget(width: 64, height: 64, commandBuffer: buffer),
                      let pin = target.pin else { throw ProbeFailure.failed("compositionTarget") }
                return Target(texture: target.texture, pin: pin)
            }
            guard let target = pool.reserveModelShadow(slot: 0, width: 64, height: 64,
                commandBuffer: buffer, textureFactory: factory) else { throw ProbeFailure.failed("reserveModelShadow") }
            return target
        }
        func clearAndRead(_ target: Target, value: Double, buffer: MTLCommandBuffer,
                                 device: MTLDevice, color: MTLClearColor? = nil) throws -> MTLBuffer {
            let descriptor = MTLRenderPassDescriptor()
            if let color {
                descriptor.colorAttachments[0].texture = target.texture
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].storeAction = .store
                descriptor.colorAttachments[0].clearColor = color
            } else {
                descriptor.depthAttachment.texture = target.texture
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.storeAction = .store
                descriptor.depthAttachment.clearDepth = value
            }
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                throw ProbeFailure.failed("depth encoder")
            }
            encoder.endEncoding()
            guard let bytes = device.makeBuffer(length: 256, options: .storageModeShared),
                  let blit = buffer.makeBlitCommandEncoder() else { throw ProbeFailure.failed("readback") }
            bytes.contents().initializeMemory(as: UInt8.self, repeating: 0xA5, count: 256)
            blit.copy(from: target.texture, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                to: bytes, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
            blit.endEncoding()
            buffer.addCompletedHandler { _ in target.pin.release() }
            return bytes
        }
        func bits(_ bytes: MTLBuffer) -> [String: Any] {
            let value = bytes.contents().load(as: Float.self)
            return ["value": Double(value), "bits": UInt64(value.bitPattern)]
        }
        func observation(_ pool: SceneOffscreenTexturePool, _ targets: [Target]) -> [String: Any] {
            ["logicalResidentBytes": pool.residentByteCost, "residentTextures": pool.residentTextureCount,
             "residentAllocations": pool.residentAllocationCount,
             "textureTokens": targets.map { String(UInt(bitPattern: ObjectIdentifier($0.texture))) },
             "uniqueTextureCount": Set(targets.map { ObjectIdentifier($0.texture) }).count,
             "tracked": targets.map { $0.texture.hazardTrackingMode == .tracked },
             "pixelFormats": targets.map { $0.texture.pixelFormat.rawValue },
             "privateRT64Single": targets.allSatisfy { $0.texture.storageMode == .private
                 && $0.texture.sampleCount == 1 && $0.texture.usage.contains(.renderTarget)
                 && $0.texture.width == 64 && $0.texture.height == 64 },
             "depth32PrivateRT": targets.allSatisfy {
                 $0.texture.pixelFormat == .depth32Float && $0.texture.storageMode == .private
                     && $0.texture.sampleCount == 1 && $0.texture.usage.contains(.renderTarget)
             }]
        }
        func finish(_ name: String, pool: SceneOffscreenTexturePool, targets: [Target],
                           buffers: [MTLCommandBuffer], reads: [MTLBuffer], before: [String: Any], color: Bool = false) -> [String: Any] {
            let readbacks: [[String: Any]]
            if color {
                readbacks = reads.map { ["bgra8": Array(UnsafeBufferPointer(start:
                    $0.contents().assumingMemoryBound(to: UInt8.self), count: 4))] }
            } else { readbacks = reads.map(bits) }
            return ["name": name, "beforeCommit": before, "afterCompletion": observation(pool, targets),
             "readbacks": readbacks,
             "completedCBs": buffers.filter { $0.status == .completed && $0.error == nil }.count,
             "commandBuffers": buffers.count]
        }
        func pair(_ device: MTLDevice, mode: String) throws -> [String: Any] {
            let firstQueue = try queue(device)
            let secondQueue: MTLCommandQueue
            if mode == "cross-queue" { secondQueue = try queue(device) } else { secondQueue = firstQueue }
            let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 64 * 64 * 4)
            var buffers: [MTLCommandBuffer] = []; defer { drain(buffers) }
            let a = try buffer(firstQueue, &buffers)
            if mode != "prior-not-enqueued" { a.enqueue() }
            let factory: ((MTLTextureDescriptor) -> MTLTexture?)? = mode == "untracked-factory" ? { descriptor in
                descriptor.hazardTrackingMode = .untracked
                return device.makeTexture(descriptor: descriptor)
            } : nil
            let composition = mode == "composition-ordered"
            let x = try reserve(pool, a, factory: factory, composition: composition)
            var reads: [MTLBuffer] = []
            if mode != "untracked-factory" { reads.append(try clearAndRead(x, value: 0.75, buffer: a, device: device,
                color: composition ? MTLClearColorMake(1, 0, 0, 1) : nil)) }
            let b = try buffer(secondQueue, &buffers)
            let y = try reserve(pool, b, factory: factory, composition: composition)
            if mode != "untracked-factory" { reads.append(try clearAndRead(y, value: 0.25, buffer: b, device: device,
                color: composition ? MTLClearColorMake(0, 0, 1, 1) : nil)) }
            else {
                a.addCompletedHandler { _ in x.pin.release() }
                b.addCompletedHandler { _ in y.pin.release() }
            }
            var before = observation(pool, [x, y])
            before["statuses"] = [a.status.rawValue, b.status.rawValue]
            before["sameQueue"] = firstQueue === secondQueue
            before["sameBuffer"] = a === b
            b.commit(); a.commit()
            try complete(buffers)
            var row = finish(mode, pool: pool, targets: [x, y], buffers: buffers, reads: reads, before: before, color: composition)
            row["untrackedScope"] = mode == "untracked-factory"
                ? "Allocation identity and pin ownership only; no untracked GPU read/write or inferred hazard synchronization."
                : (composition ? "Default BGRA8 literal red/blue clear/store/blit." : "Tracked literal depth clear/store/blit.")
            return row
        }
        func cancelNew(_ device: MTLDevice) throws -> [String: Any] {
            let q = try queue(device), other = try queue(device)
            let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 64 * 64 * 4)
            var buffers: [MTLCommandBuffer] = []; defer { drain(buffers) }
            let a = try buffer(q, &buffers); a.enqueue()
            let x = try reserve(pool, a)
            let rx = try clearAndRead(x, value: 0.75, buffer: a, device: device)
            let b = try buffer(q, &buffers), cancelled = try reserve(pool, b)
            cancelled.pin.release()
            let c = try buffer(other, &buffers), z = try reserve(pool, c)
            let rz = try clearAndRead(z, value: 0.25, buffer: c, device: device)
            var before = observation(pool, [x, cancelled, z])
            before["oldAndCrossQueueDistinct"] = x.texture !== z.texture
            before["cancelledStatus"] = b.status.rawValue
            c.commit(); b.commit(); a.commit(); try complete(buffers)
            return finish("cancel-new-preserves-old", pool: pool, targets: [x, cancelled, z],
                buffers: buffers, reads: [rx, rz], before: before)
        }
        func completionKeepsPending(_ device: MTLDevice) throws -> [String: Any] {
            let q = try queue(device), other = try queue(device)
            let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 64 * 64 * 4)
            var buffers: [MTLCommandBuffer] = []; defer { drain(buffers) }
            let a = try buffer(q, &buffers); a.enqueue()
            let x = try reserve(pool, a)
            let rx = try clearAndRead(x, value: 0.75, buffer: a, device: device)
            let b = try buffer(q, &buffers), pending = try reserve(pool, b)
            a.commit(); try complete([a])
            let rb = try clearAndRead(pending, value: 0.25, buffer: b, device: device)
            let c = try buffer(other, &buffers), z = try reserve(pool, c)
            let rz = try clearAndRead(z, value: 0.5, buffer: c, device: device)
            var before = observation(pool, [x, pending, z])
            before["pendingAndCrossQueueDistinct"] = pending.texture !== z.texture
            before["oldCompleted"] = a.status == .completed
            before["pendingStatus"] = b.status.rawValue
            c.commit(); b.commit(); try complete(buffers)
            return finish("old-completion-preserves-pending", pool: pool, targets: [x, pending, z],
                buffers: buffers, reads: [rx, rb, rz], before: before)
        }

        var rows: [[String: Any]] = []
        for mode in ["ordered-tracked", "cross-queue", "prior-not-enqueued", "untracked-factory", "composition-ordered"] {
            rows.append(try autoreleasepool { try pair(device, mode: mode) })
        }
        rows.append(try autoreleasepool { try cancelNew(device) })
        rows.append(try autoreleasepool { try completionKeepsPending(device) })
        return rows
    }
}
