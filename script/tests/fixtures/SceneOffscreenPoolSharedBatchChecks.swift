

import Foundation
import Metal

extension Harness {
    static func sourceMaterialResidencyChecks(_ device: MTLDevice) -> [String: Any] {
        let queue = device.makeCommandQueue()!
        let firstFrame = queue.makeCommandBuffer()!
        let nextFrame = queue.makeCommandBuffer()!
        let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 4 * 4 * 4)
        let first = pool.reserveSourceMaterial(layerID: 1, width: 4, height: 4,
            commandBuffer: firstFrame)!
        let second = pool.reserveSourceMaterial(layerID: 2, width: 4, height: 4,
            commandBuffer: firstFrame)!
        let reuse = pool.reserveSourceMaterial(layerID: 1, width: 4, height: 4,
            commandBuffer: firstFrame)!
        let next = pool.reserveSourceMaterial(layerID: 1, width: 4, height: 4,
            commandBuffer: nextFrame)!
        let isolated = first.texture !== second.texture && first.texture !== next.texture
            && first.texture === reuse.texture
        pool.reset()
        let retained = pool.residentByteCost == 3 * 4 * 4 * 4
        first.pin.release(); second.pin.release(); reuse.pin.release(); next.pin.release()
        let released = pool.residentByteCost == 0
        let tight = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 4 * 4)
        let kept = tight.reserveSourceMaterial(layerID: 1, width: 4, height: 4,
            commandBuffer: firstFrame)!
        let failed = tight.reserveSourceMaterial(layerID: 2, width: 4, height: 4,
            commandBuffer: firstFrame)
        let noEviction = failed == nil && tight.residentByteCost == 4 * 4 * 4
        tight.reset(); kept.pin.release()
        let terminalPool = SceneOffscreenTexturePool(device: device, residentByteBudget: 4 * 4 * 4)
        let terminal = terminalPool.reserveCompositionTargets(dimensions: [(4, 4)], commandBuffer: firstFrame)![0]
        let optional = terminalPool.reserveSourceMaterial(layerID: 7, width: 4, height: 4, commandBuffer: firstFrame)
        let exported = terminalPool.compositionTarget(width: 4, height: 4, commandBuffer: firstFrame)!
        let displayProtected = optional == nil && exported.texture === terminal.texture
        terminalPool.reset(); exported.pin?.release(); terminal.pin.release()
        return ["sourceMaterialLayerAndSubmissionIsolation": isolated,
                "sourceMaterialCannotEvictTerminalCapacity": displayProtected,
                "sourceMaterialPinsSurviveReset": retained,
                "sourceMaterialCancellationReleases": released,
                "sourceMaterialBudgetFailureKeepsPinnedSource": noEviction]
    }

    static func sharedFramebufferChecks(
        _ device: MTLDevice
    ) -> [String: Any] {
        let sharedFBOFixtures: [Fixture] = (0..<6).map { offset in
            fixture(
                effectIndex: 600 + offset,
                layerID: 100 + offset,
                precise: true
            )
        }
        let sharedFBOPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 2_048,
            residentByteBudget: 128 * 1_024 * 1_024
        )
        guard let sharedFBOCommandBuffer = device.makeCommandQueue()?
            .makeCommandBuffer() else {
            fatalError("shared FBO command buffer unavailable")
        }
        let sharedFBOOrdering = SceneGraphCommandQueueOrderingContext(
            commandBuffer: sharedFBOCommandBuffer
        )
        let sharedFBOPlans = sharedFBOFixtures.compactMap { fixture in
            sharedFBOPool.framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([fixture]),
                pairPlan: pairPlan([fixture]),
                requestedWidth: 2_048,
                requestedHeight: 2_048,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: sharedFBOOrdering
            )
        }
        guard sharedFBOPlans.count == sharedFBOFixtures.count,
              sharedFBOPlans.allSatisfy({ $0.graphPlan.pairStorage == .shared }),
              let sharedFBOPrepared = sharedFBOPool.preparePersistentGraphTargets(
                  framePlans: sharedFBOPlans
              ) else {
            fatalError("shared FBO batch preparation failed")
        }
        let sharedFBOHistory: [[
            ScenePreparedPersistentGraphTargets.EffectKey:
                Set<ScenePreparedPersistentGraphTargets.Token>
        ]] = Array(repeating: [:], count: sharedFBOPrepared.count)
        guard let sharedFBOCommits = sharedFBOPool
            .commitAndPinPersistentGraphTargets(
                sharedFBOPrepared,
                historyTokensByTarget: sharedFBOHistory,
                commandBuffer: sharedFBOCommandBuffer
            ), sharedFBOCommits.count == sharedFBOPrepared.count else {
            fatalError("shared FBO batch commit failed")
        }
        let sharedFBOPairObjects = sharedFBOPrepared.map { prepared in
            Set(prepared.leases.flatMap { lease in
                [
                    ObjectIdentifier(lease.table.fullFramePair.first),
                    ObjectIdentifier(lease.table.fullFramePair.second),
                ]
            })
        }
        let sharedFBOFramePairShared = sharedFBOPairObjects.dropFirst().allSatisfy {
            $0 == sharedFBOPairObjects.first
        } && sharedFBOPairObjects.first?.count == 2
        let sharedFBOFramebuffers = sharedFBOPrepared.compactMap { prepared in
            prepared.leases.first.flatMap { lease in
                lease.table.plan.logicalTargets.first.flatMap {
                    lease.table.texture(for: $0.identity)
                }
            }
        }
        let sharedFBOFramebuffersDistinct = Set(
            sharedFBOFramebuffers.map(ObjectIdentifier.init)
        ).count == sharedFBOFramebuffers.count
            && sharedFBOFramebuffers.count == sharedFBOPrepared.count
        let sharedFBOStateOwnsOnlyFBO = sharedFBOPrepared.allSatisfy { prepared in
            prepared.leases.allSatisfy { lease in
                lease.framebufferAllocation.resources.count == 1
                    && lease.generation != lease.fullFramePairGeneration
            }
        }
        let sharedFBOBudgetExact = sharedFBOPool.residentByteCost
            == 128 * 1_024 * 1_024
        sharedFBOCommandBuffer.commit()
        sharedFBOCommandBuffer.waitUntilCompleted()
        let sharedPairKey = SceneOffscreenTextureAllocationCache.Key
            .sharedGraphPair(width: 2_048, height: 2_048)
        func currentSharedFBOPair() -> SceneOffscreenTexturePool.SharedGraphPair? {
            guard case let .sharedGraphPair(pair, _) = sharedFBOPool
                .allocationCache.allocation(for: sharedPairKey) else { return nil }
            return pair
        }
        let sharedFBOPairBeforeRelease = currentSharedFBOPair()?.first
        sharedFBOCommits[0].releaseAll()
        let sharedFBOPairAfterOneRelease = currentSharedFBOPair()?.first
        let sharedFBOPairRetainedAfterOneRelease =
            sharedFBOPairBeforeRelease === sharedFBOPairAfterOneRelease
        sharedFBOCommits.dropFirst().forEach { $0.releaseAll() }
        let sharedFBOPairAfterAllRelease = currentSharedFBOPair()?.first
        let sharedFBOPairRetainedAfterAllRelease =
            sharedFBOPairAfterOneRelease === sharedFBOPairAfterAllRelease

        let overBudgetSharedFBOPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 2_048,
            // 2-texture shared pair (33,554,432) + 1 FBO (16,777,216) fits
            // but 2+ FBOs exceed 50 MiB.
            residentByteBudget: 50 * 1_024 * 1_024
        )
        guard let overBudgetCommandBuffer = device.makeCommandQueue()?
            .makeCommandBuffer() else {
            fatalError("over-budget shared FBO command buffer unavailable")
        }
        let overBudgetPlans = sharedFBOFixtures.compactMap { fixture in
            overBudgetSharedFBOPool.framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([fixture]),
                pairPlan: pairPlan([fixture]),
                requestedWidth: 2_048,
                requestedHeight: 2_048,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: .init(commandBuffer: overBudgetCommandBuffer)
            )
        }
        let overBudgetSharedFBORejected = overBudgetPlans.count == sharedFBOFixtures.count
            && overBudgetSharedFBOPool.preparePersistentGraphTargets(
                framePlans: overBudgetPlans
            ) == nil
            && overBudgetSharedFBOPool.residentAllocationCount == 1
            && overBudgetSharedFBOPool.residentTextureCount == 2

        let sharedPairOrderingPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 2_000
        )
        guard let sharedPairQueue = device.makeCommandQueue(),
              let differentSharedPairQueue = device.makeCommandQueue(),
              let firstSharedPairBuffer = sharedPairQueue.makeCommandBuffer(),
              let firstSharedPairPlan = sharedPairOrderingPool
                  .framePlanForPersistentGraphTargets(
                      admittedGraphs: admittedGraphs([sharedFBOFixtures[0]]),
                      pairPlan: pairPlan([sharedFBOFixtures[0]]),
                      requestedWidth: 8,
                      requestedHeight: 8,
                      usesSharedFullFrameWorkingPair: true,
                      orderingContext: .init(commandBuffer: firstSharedPairBuffer)
                  ), let firstSharedPairPrepared = sharedPairOrderingPool
                  .preparePersistentGraphTargets(framePlan: firstSharedPairPlan),
              let firstSharedPairCommit = firstSharedPairPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: firstSharedPairBuffer
              ), let unsafeSharedPairBuffer = sharedPairQueue.makeCommandBuffer(),
              let unsafeSharedPairPlan = sharedPairOrderingPool
                  .framePlanForPersistentGraphTargets(
                      admittedGraphs: admittedGraphs([sharedFBOFixtures[1]]),
                      pairPlan: pairPlan([sharedFBOFixtures[1]]),
                      requestedWidth: 8,
                      requestedHeight: 8,
                      usesSharedFullFrameWorkingPair: true,
                      orderingContext: .init(commandBuffer: unsafeSharedPairBuffer)
                  ) else {
            fatalError("shared pair ordering fixture unavailable")
        }
        let unsafeUnsubmittedSharedPairRejected = sharedPairOrderingPool
            .preflightPersistentGraphTargets([unsafeSharedPairPlan])
                == .rejected(
                    reasonCode: "frame-target-shared-pair-ordering-rejected"
                )
            && sharedPairOrderingPool.preparePersistentGraphTargets(
                framePlan: unsafeSharedPairPlan
            ) == nil
        firstSharedPairBuffer.commit()
        firstSharedPairBuffer.waitUntilCompleted()
        guard let differentQueueSharedPairBuffer = differentSharedPairQueue
            .makeCommandBuffer(), let differentQueueSharedPairPlan =
            sharedPairOrderingPool.framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([sharedFBOFixtures[1]]),
                pairPlan: pairPlan([sharedFBOFixtures[1]]),
                requestedWidth: 8,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: .init(
                    commandBuffer: differentQueueSharedPairBuffer
                )
            ) else {
            fatalError("different-queue shared pair fixture unavailable")
        }
        let differentQueueSharedPairRejected = sharedPairOrderingPool
            .preflightPersistentGraphTargets([differentQueueSharedPairPlan])
                == .rejected(
                    reasonCode: "frame-target-shared-pair-ordering-rejected"
                )
            && sharedPairOrderingPool.preparePersistentGraphTargets(
                framePlan: differentQueueSharedPairPlan
            ) == nil
        guard let orderedSharedPairBuffer = sharedPairQueue.makeCommandBuffer(),
              let orderedSharedPairPlan = sharedPairOrderingPool
                  .framePlanForPersistentGraphTargets(
                      admittedGraphs: admittedGraphs([sharedFBOFixtures[1]]),
                      pairPlan: pairPlan([sharedFBOFixtures[1]]),
                      requestedWidth: 8,
                      requestedHeight: 8,
                      usesSharedFullFrameWorkingPair: true,
                      orderingContext: .init(commandBuffer: orderedSharedPairBuffer)
                  ), sharedPairOrderingPool.preflightPersistentGraphTargets([
                      orderedSharedPairPlan
                  ]) == .ready,
              let orderedSharedPairPrepared = sharedPairOrderingPool
                  .preparePersistentGraphTargets(framePlan: orderedSharedPairPlan),
              let orderedSharedPairCommit = orderedSharedPairPrepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: orderedSharedPairBuffer
              ) else {
            fatalError("same-queue shared pair reuse failed")
        }
        orderedSharedPairBuffer.commit()
        orderedSharedPairBuffer.waitUntilCompleted()
        let orderedSharedPairKey = SceneOffscreenTextureAllocationCache.Key
            .sharedGraphPair(width: 8, height: 8)
        let sharedPairBeforeIdempotentRelease: MTLTexture? = {
            guard case let .sharedGraphPair(pair, _) = sharedPairOrderingPool
                .allocationCache.allocation(for: orderedSharedPairKey) else { return nil }
            return pair.first
        }()
        firstSharedPairCommit.releaseAll()
        firstSharedPairCommit.releaseAll()
        orderedSharedPairCommit.releaseAll()
        orderedSharedPairCommit.releaseAll()
        let sharedPairAfterIdempotentRelease: MTLTexture? = {
            guard case let .sharedGraphPair(pair, _) = sharedPairOrderingPool
                .allocationCache.allocation(for: orderedSharedPairKey) else { return nil }
            return pair.first
        }()
        let sharedPairOrderedReuseAndReleaseStable =
            sharedPairBeforeIdempotentRelease === sharedPairAfterIdempotentRelease

        let checks: [String: Any] = [
            "sharedFBOFramePairShared": sharedFBOFramePairShared,
            "sharedFBOFramebuffersDistinct": sharedFBOFramebuffersDistinct,
            "sharedFBOStateOwnsOnlyFBO": sharedFBOStateOwnsOnlyFBO,
            "sharedFBOBudgetExact": sharedFBOBudgetExact,
            "sharedFBOPairRetainedAfterOneRelease":
                sharedFBOPairRetainedAfterOneRelease,
            "sharedFBOPairRetainedAfterAllRelease":
                sharedFBOPairRetainedAfterAllRelease,
            "overBudgetSharedFBORejected": overBudgetSharedFBORejected,
            "unsafeUnsubmittedSharedPairRejected":
                unsafeUnsubmittedSharedPairRejected,
            "differentQueueSharedPairRejected": differentQueueSharedPairRejected,
            "sharedPairOrderedReuseAndReleaseStable":
                sharedPairOrderedReuseAndReleaseStable,
        ]
        return checks
    }

    static func singleChannelChecks(
        _ device: MTLDevice
    ) -> [String: Any] {
        let r8Fixture = fixture(effectIndex: 49, framebufferFormat: "r8")
        let r8TargetPlans = targetPlans([r8Fixture], width: 8, height: 8)
        let r8PairPlan = pairPlan([r8Fixture])
        guard case .success(let r8GraphPlan) = SceneLayerGraphTargetPlan.make(
            plans: r8TargetPlans,
            pairPlan: r8PairPlan,
            byteBudget: 520
        ) else { fatalError("r8 graph plan rejected") }
        let r8BudgetRejectsBeforeAllocation: Bool
        switch SceneLayerGraphTargetPlan.make(
            plans: r8TargetPlans,
            pairPlan: r8PairPlan,
            byteBudget: 519
        ) {
        case .failure(.byteBudgetExceeded):
            r8BudgetRejectsBeforeAllocation = true
        default:
            r8BudgetRejectsBeforeAllocation = false
        }
        let r8Cache = SceneOffscreenTextureAllocationCache(byteBudget: 520)
        var r8AllocatedFormats: [MTLPixelFormat] = []
        let r8Allocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: r8Cache
        ) { descriptor, _ in
            r8AllocatedFormats.append(descriptor.pixelFormat)
            return device.makeTexture(descriptor: descriptor)
        }
        guard let r8Prepared = r8Allocator.prepare(plan: r8GraphPlan),
              let r8Lease = r8Prepared.leases.first else {
            fatalError("r8 persistent allocation failed")
        }
        let r8PersistentAllocationTyped = r8GraphPlan.residentByteCost == 520
            && r8GraphPlan.historyByteCost == 0
            && r8AllocatedFormats.filter({ $0 == .bgra8Unorm }).count == 2
            && r8AllocatedFormats.filter({ $0 == .r8Unorm }).count == 2
            && r8Fixture.framebufferIdentities.allSatisfy {
                r8Lease.texture(for: $0)?.pixelFormat == .r8Unorm
            }
            && r8Lease.table.residentByteCost == 520

        let r8HistoryFixture = historySwapFixture(
            effectIndex: 106,
            framebufferFormat: "r8",
            extent: .init(kind: .absolute, first: 8, second: 8)
        )
        let r8HistoryPairPlan = pairPlan([r8HistoryFixture])
        let r8HistoryGraphs = admittedGraphs([r8HistoryFixture])
        let r8HistoryTargetPlans = targetPlans(
            [r8HistoryFixture], width: 8, height: 8
        )
        guard case .success(let r8HistoryPlan) = SceneLayerGraphTargetPlan.make(
            plans: r8HistoryTargetPlans,
            pairPlan: r8HistoryPairPlan,
            byteBudget: 768
        ) else { fatalError("r8 history plan rejected") }
        let r8HistoryPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 768
        )
        guard let r8HistoryPrepared1 = r8HistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: r8HistoryGraphs,
                pairPlan: r8HistoryPairPlan,
                requestedWidth: 8,
                requestedHeight: 8
            ), let r8HistoryLease1 = r8HistoryPrepared1.leases.first,
              let r8HistoryEffect = r8HistoryLease1.table.plan.output.effect,
              let r8HistoryCommit1 = r8HistoryPrepared1.commitAndPin(
                historyTokensByEffect: [
                    r8HistoryEffect: Set(r8HistoryLease1.framebufferAllocation
                        .resources.values.map(\.token))
                ]
              ) else { fatalError("r8 history first allocation failed") }
        let r8HistoryCurrentCostExact = r8HistoryPlan.residentByteCost == 640
            && r8HistoryPlan.historyByteCost == 128
            && r8HistoryPool.residentByteCost == 640
        r8HistoryCommit1.submissionPin.release()
        guard let r8HistoryPrepared2 = r8HistoryPool
            .preparePersistentGraphTargets(
                admittedGraphs: r8HistoryGraphs,
                pairPlan: r8HistoryPairPlan,
                requestedWidth: 8,
                requestedHeight: 8
            ), let r8HistoryCopies = r8HistoryPrepared2
                .historyRehydrateCopiesByEffect[r8HistoryEffect],
              r8HistoryCopies.count == 2,
              let r8HistoryCommit2 = r8HistoryPrepared2.commitAndPin(
                historyTokensByEffect: [
                    r8HistoryEffect: Set(r8HistoryCopies.map(\.targetToken))
                ]
              ) else { fatalError("r8 history rehydrate failed") }
        let r8HistoryRetiredCostExact = r8HistoryPool.residentByteCost == 768
            && r8HistoryCopies.allSatisfy {
                $0.sourceTexture.pixelFormat == .r8Unorm
                    && $0.targetTexture.pixelFormat == .r8Unorm
            }
        r8HistoryCommit1.historyPinsByEffect[r8HistoryEffect]?.release()
        let r8HistoryReleaseRestoresCurrentCost =
            r8HistoryPool.residentByteCost == 640
        r8HistoryCommit2.releaseAll()
        r8HistoryPool.reset()
        let r8HistoryFinalReleaseClearsResidency =
            r8HistoryPool.residentByteCost == 0

        let checks: [String: Any] = [
            "r8PersistentAllocationTyped": r8PersistentAllocationTyped,
            "r8BudgetRejectsBeforeAllocation": r8BudgetRejectsBeforeAllocation,
            "r8HistoryCurrentCostExact": r8HistoryCurrentCostExact,
            "r8HistoryRetiredCostExact": r8HistoryRetiredCostExact,
            "r8HistoryReleaseRestoresCurrentCost":
                r8HistoryReleaseRestoresCurrentCost,
            "r8HistoryFinalReleaseClearsResidency":
                r8HistoryFinalReleaseClearsResidency,
        ]
        return checks
    }

    static func batchCommitChecks(
        _ device: MTLDevice,
        directBudgetPool: SceneOffscreenTexturePool
    ) -> [String: Any] {
        let stalePool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 2_000
        )
        let staleA = directFixture(effectIndex: 110)
        let staleB = directFixture(effectIndex: 111)
        let stalePairPlan = pairPlan([staleA])
        guard let stalePrepared = stalePool.preparePersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleA]),
            pairPlan: stalePairPlan,
            requestedWidth: 8,
            requestedHeight: 8
        ) else { fatalError("stale prepared fixture failed") }
        stalePool.reset()
        let stalePreparedRejected = stalePrepared.commitAndPin(
            historyTokensByEffect: [:]
        ) == nil && stalePrepared.commitAndPin(historyTokensByEffect: [:]) == nil
            && stalePool.residentAllocationCount == 0
            && stalePool.residentByteCost == 0

        let batchPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 8_192
        )
        let batchBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        let batchContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: batchBuffer
        )
        guard let batchPlanA = batchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleA]),
            pairPlan: pairPlan([staleA]),
            requestedWidth: 8,
            requestedHeight: 8,
            orderingContext: batchContext
        ), let batchPlanB = batchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleB]),
            pairPlan: pairPlan([staleB]),
            requestedWidth: 8,
            requestedHeight: 8,
            orderingContext: batchContext
        ), let batchPrepared = batchPool.preparePersistentGraphTargets(
            framePlans: [batchPlanA, batchPlanB]
        ) else { fatalError("whole-frame batch prepare failed") }
        let batchPrepareHasNoVisibleMutation =
            batchPool.residentAllocationCount == 0
                && batchPool.allocationCache.accessCounter == 0
        let batchRevisionBeforeCommit = batchPool.allocationCache.revision
        guard let batchCommits = batchPool.commitAndPinPersistentGraphTargets(
            batchPrepared,
            historyTokensByTarget: [[:], [:]],
            commandBuffer: batchBuffer
        ) else { fatalError("whole-frame batch commit failed") }
        let batchCommitPublishesAtomically = batchCommits.count == 2
            && batchPool.residentAllocationCount == 2
            && batchPool.allocationCache.accessCounter == 2
            && batchPool.allocationCache.revision != batchRevisionBeforeCommit
        batchCommits.forEach { $0.releaseAll() }

        let protectedSharedPairPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 960
        )
        let protectedPairAKey = SceneOffscreenTextureAllocationCache.Key
            .sharedGraphPair(width: 7, height: 8)
        let protectedPairBKey = SceneOffscreenTextureAllocationCache.Key
            .sharedGraphPair(width: 8, height: 8)
        let unrelatedPairKey = SceneOffscreenTextureAllocationCache.Key
            .sharedGraphPair(width: 6, height: 8)
        guard let protectedPairA = protectedSharedPairPool.sharedPairCandidate(
            width: 7, height: 8
        ), let unrelatedPair = protectedSharedPairPool.sharedPairCandidate(
            width: 6, height: 8
        ), protectedSharedPairPool.allocationCache.commit([protectedPairA]),
              protectedSharedPairPool.allocationCache.commit([unrelatedPair]) else {
            fatalError("shared pair atomic protection seed failed")
        }
        let protectedFixtureA = directFixture(effectIndex: 113, layerID: 113)
        let protectedFixtureB = directFixture(effectIndex: 114, layerID: 114)
        guard let protectedPairPlanA = protectedSharedPairPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([protectedFixtureA]),
                pairPlan: pairPlan([protectedFixtureA]),
                requestedWidth: 7,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true
            ), let protectedPairPlanB = protectedSharedPairPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([protectedFixtureB]),
                pairPlan: pairPlan([protectedFixtureB]),
                requestedWidth: 8,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true
            ), protectedSharedPairPool.preflightPersistentGraphTargets([
                protectedPairPlanA, protectedPairPlanB,
            ]) == .ready,
              let protectedPairPrepared = protectedSharedPairPool
                .preparePersistentGraphTargets(framePlans: [
                    protectedPairPlanA, protectedPairPlanB,
                ]) else {
            fatalError("whole-frame shared pair residency set failed")
        }
        let wholeFrameSharedPairSetIsAtomic =
            protectedPairPrepared.count == 2
                && protectedSharedPairPool.allocationCache
                    .allocation(for: protectedPairAKey) != nil
                && protectedSharedPairPool.allocationCache
                    .allocation(for: protectedPairBKey) != nil
                && protectedSharedPairPool.allocationCache
                    .allocation(for: unrelatedPairKey) == nil

        let sharedResolvedPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 8_192
        )
        let sharedResolvedBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        let sharedResolvedContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: sharedResolvedBuffer
        )
        guard let sharedResolvedPlanA = sharedResolvedPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([staleA]),
                pairPlan: pairPlan([staleA]),
                requestedWidth: 8,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: sharedResolvedContext
            ), let sharedResolvedPlanB = sharedResolvedPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([staleB]),
                pairPlan: pairPlan([staleB]),
                requestedWidth: 8,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: sharedResolvedContext
            ), sharedResolvedPool.preflightPersistentGraphTargets([
                sharedResolvedPlanA, sharedResolvedPlanB,
            ]) == .ready,
              sharedResolvedPool.residentAllocationCount == 0,
              let sharedResolvedPrepared = sharedResolvedPool
                .preparePersistentGraphTargets(framePlans: [
                    sharedResolvedPlanA, sharedResolvedPlanB,
                ]) else { fatalError("resolved shared pair fixture failed") }
        let batchPlansShareOneWorkingPair =
            sharedResolvedPlanA.graphPlan.pairStorage == .shared
                && sharedResolvedPlanB.graphPlan.pairStorage == .shared
                && sharedResolvedPrepared.allSatisfy {
                    $0.leases.first?.fullFramePairGeneration
                        == sharedResolvedPrepared.first?.leases.first?
                            .fullFramePairGeneration
                }
        let sharedResolvedPublicationsUseChainGeneration =
            sharedResolvedPrepared.allSatisfy { prepared in
                guard let lease = prepared.leases.first else { return false }
                switch lease.fullFrameResource(
                    for: lease.table.plan.output,
                    member: .zero,
                    contentGeneration: 1,
                    fragmentColorRepresentation: .resolved(.premultipliedAlpha)
                ) {
                case .success(let resource):
                    guard case let .provider(.graph(generation, _)) =
                        resource.publication.candidate.identity else {
                        return false
                    }
                    return generation == lease.generation
                        && generation != lease.fullFramePairGeneration
                case .failure:
                    return false
                }
            }
        let batchPrepareOnlyPublishesSharedPair =
            sharedResolvedPool.residentAllocationCount == 1
                && sharedResolvedPool.residentTextureCount == 2

        let rejectedSharedResolvedPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 511
        )
        let rejectedSharedBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        guard let rejectedSharedPlan = rejectedSharedResolvedPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([staleA]),
                pairPlan: pairPlan([staleA]),
                requestedWidth: 8,
                requestedHeight: 8,
                usesSharedFullFrameWorkingPair: true,
                orderingContext: .init(commandBuffer: rejectedSharedBuffer)
            ) else { fatalError("resolved shared rejection fixture failed") }
        let sharedPairBudgetRejectsBeforeAllocation =
            rejectedSharedResolvedPool.preflightPersistentGraphTargets([
                rejectedSharedPlan,
            ]) == .rejected(reasonCode: "frame-target-byte-budget-exceeded")
                && rejectedSharedResolvedPool.residentAllocationCount == 0
                && rejectedSharedResolvedPool.residentTextureCount == 0

        let failingBatchPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 8_192
        )
        let failingBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        let failingContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: failingBuffer
        )
        guard let failingPlanA = failingBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleA]),
            pairPlan: pairPlan([staleA]),
            requestedWidth: 8,
            requestedHeight: 8,
            orderingContext: failingContext
        ), let failingPlanB = failingBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleB]),
            pairPlan: pairPlan([staleB]),
            requestedWidth: 8,
            requestedHeight: 8,
            orderingContext: failingContext
        ), let failingPrepared = failingBatchPool.preparePersistentGraphTargets(
            framePlans: [failingPlanA, failingPlanB]
        ) else { fatalError("failing batch fixture prepare failed") }
        let failingRevision = failingBatchPool.allocationCache.revision
        let invalidEffect = staleB.execution.renderGraph.effects[0].key
        let secondCandidateFailureHasZeroMutation =
            failingBatchPool.commitAndPinPersistentGraphTargets(
                failingPrepared,
                historyTokensByTarget: [
                    [:], [invalidEffect: [.init(rawValue: "unexpected-history")]],
                ],
                commandBuffer: failingBuffer
            ) == nil
                && failingBatchPool.residentAllocationCount == 0
                && failingBatchPool.allocationCache.accessCounter == 0
                && failingBatchPool.allocationCache.revision == failingRevision

        let materializationCache = SceneOffscreenTextureAllocationCache(
            byteBudget: 8_192
        )
        var materializationAttempts = 0
        let materializationAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: materializationCache,
            textureFactory: { descriptor, _ in
                materializationAttempts += 1
                guard materializationAttempts <= failingPlanA.graphPlan.slots.count
                else { return nil }
                return device.makeTexture(descriptor: descriptor)
            }
        )
        let materializationRevision = materializationCache.revision
        let secondMaterializationFailureHasZeroMutation =
            materializationAllocator.prepare(
                plans: [failingPlanA.graphPlan, failingPlanB.graphPlan],
                orderingContext: failingContext
            ) == nil
                && materializationCache.residentAllocationCount == 0
                && materializationCache.accessCounter == 0
                && materializationCache.revision == materializationRevision

        let staleBatchPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 8_192
        )
        let staleC = directFixture(effectIndex: 112)
        guard let unrelatedPrepared = staleBatchPool.preparePersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleC]),
            pairPlan: pairPlan([staleC]),
            requestedWidth: 8,
            requestedHeight: 8
        ), let unrelatedCommit = unrelatedPrepared.commitAndPin(
            historyTokensByEffect: [:]
        ) else { fatalError("unrelated revision fixture failed") }
        let staleBatchBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        let staleBatchContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: staleBatchBuffer
        )
        guard let staleBatchPlanA = staleBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleA]),
            pairPlan: pairPlan([staleA]), requestedWidth: 8, requestedHeight: 8,
            orderingContext: staleBatchContext
        ), let staleBatchPlanB = staleBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleB]),
            pairPlan: pairPlan([staleB]), requestedWidth: 8, requestedHeight: 8,
            orderingContext: staleBatchContext
        ), let staleBatchPrepared = staleBatchPool.preparePersistentGraphTargets(
            framePlans: [staleBatchPlanA, staleBatchPlanB]
        ) else { fatalError("stale batch fixture failed") }
        unrelatedCommit.releaseAll()
        let externalRevision = staleBatchPool.allocationCache.revision
        let externalGenerations = staleBatchPool.allocationCache.residents.values
            .map { $0.allocation.generation }.sorted()
        guard let rebasedCommits = staleBatchPool
            .commitAndPinPersistentGraphTargets(
                staleBatchPrepared,
                historyTokensByTarget: [[:], [:]],
                commandBuffer: staleBatchBuffer
            ) else { fatalError("unrelated revision should revalidate") }
        let unrelatedReleaseRevalidatesWholeBatch =
            staleBatchPool.allocationCache.revision != externalRevision
                && staleBatchPool.residentAllocationCount == 3
                && Set(externalGenerations).isSubset(of: Set(
                    staleBatchPool.allocationCache.residents.values.map {
                        $0.allocation.generation
                    }
                ))
        rebasedCommits.forEach { $0.releaseAll() }

        let resetBatchPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 8_192
        )
        let resetBatchBuffer = device.makeCommandQueue()!.makeCommandBuffer()!
        let resetBatchContext = SceneGraphCommandQueueOrderingContext(
            commandBuffer: resetBatchBuffer
        )
        guard let resetPlanA = resetBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleA]), pairPlan: pairPlan([staleA]),
            requestedWidth: 8, requestedHeight: 8,
            orderingContext: resetBatchContext
        ), let resetPlanB = resetBatchPool.framePlanForPersistentGraphTargets(
            admittedGraphs: admittedGraphs([staleB]), pairPlan: pairPlan([staleB]),
            requestedWidth: 8, requestedHeight: 8,
            orderingContext: resetBatchContext
        ), let resetPrepared = resetBatchPool.preparePersistentGraphTargets(
            framePlans: [resetPlanA, resetPlanB]
        ) else { fatalError("reset batch fixture failed") }
        resetBatchPool.reset()
        let resetRevision = resetBatchPool.allocationCache.revision
        let resetInvalidatesWholePreparedBatch =
            resetBatchPool.commitAndPinPersistentGraphTargets(
                resetPrepared,
                historyTokensByTarget: [[:], [:]],
                commandBuffer: resetBatchBuffer
            ) == nil
                && resetBatchPool.residentAllocationCount == 0
                && resetBatchPool.allocationCache.accessCounter == 0
                && resetBatchPool.allocationCache.revision == resetRevision
        directBudgetPool.reset()
        stalePool.reset()
        let checks: [String: Any] = [
            "wholeFrameSharedPairSetIsAtomic": wholeFrameSharedPairSetIsAtomic,
            "batchPlansShareOneWorkingPair":
                batchPlansShareOneWorkingPair,
            "sharedResolvedPublicationsUseChainGeneration":
                sharedResolvedPublicationsUseChainGeneration,
            "batchPrepareOnlyPublishesSharedPair":
                batchPrepareOnlyPublishesSharedPair,
            "sharedPairBudgetRejectsBeforeAllocation":
                sharedPairBudgetRejectsBeforeAllocation,
            "stalePreparedRejected": stalePreparedRejected,
            "batchPrepareHasNoVisibleMutation": batchPrepareHasNoVisibleMutation,
            "batchCommitPublishesAtomically": batchCommitPublishesAtomically,
            "secondCandidateFailureHasZeroMutation":
                secondCandidateFailureHasZeroMutation,
            "secondMaterializationFailureHasZeroMutation":
                secondMaterializationFailureHasZeroMutation,
            "unrelatedReleaseRevalidatesWholeBatch":
                unrelatedReleaseRevalidatesWholeBatch,
            "resetInvalidatesWholePreparedBatch":
                resetInvalidatesWholePreparedBatch,
        ]
        return checks
    }
}
