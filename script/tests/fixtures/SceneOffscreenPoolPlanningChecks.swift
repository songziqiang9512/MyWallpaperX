

import Foundation
import Metal

extension Harness {
    static func budgetPolicyChecks(
        _ device: MTLDevice
    ) -> (
        checks: [String: Any],
        automaticBudgetFloor: Int,
        defaultBudgetPool: SceneOffscreenTexturePool,
        explicit128Pool: SceneOffscreenTexturePool
    ) {
        let mebibyte = 1_024 * 1_024
        let automaticBudgetFloor = SceneOffscreenTexturePool
            .automaticResidentByteBudget(recommendedMaxWorkingSetSize: 0)
        let automaticBudgetMiddle = SceneOffscreenTexturePool
            .automaticResidentByteBudget(
                recommendedMaxWorkingSetSize: UInt64(8) * 1_024 * 1_024 * 1_024
            )
        let automaticBudgetCeiling = SceneOffscreenTexturePool
            .automaticResidentByteBudget(
                recommendedMaxWorkingSetSize: UInt64(32) * 1_024 * 1_024 * 1_024
            )
        let automaticBudgetBoundsAreStable =
            automaticBudgetFloor == 192 * mebibyte
            && automaticBudgetMiddle == 512 * mebibyte
            && automaticBudgetCeiling == 1_536 * mebibyte

        let defaultBudgetPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 2_048
        )
        let expectedDeviceBudget = SceneOffscreenTexturePool
            .automaticResidentByteBudget(
                recommendedMaxWorkingSetSize: device.recommendedMaxWorkingSetSize
            )
        let defaultPoolUsesDeviceBudget =
            defaultBudgetPool.residentByteBudget == expectedDeviceBudget
            && defaultBudgetPool.allocationCache.preflightByteBudget
                == expectedDeviceBudget
        let explicit128Pool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 2_048,
            residentByteBudget: 128 * mebibyte
        )
        let explicit128BudgetIsPreserved =
            explicit128Pool.residentByteBudget == 128 * mebibyte
            && explicit128Pool.allocationCache.preflightByteBudget
                == 128 * mebibyte

        let checks: [String: Any] = [
            "automaticBudgetBoundsAreStable": automaticBudgetBoundsAreStable,
            "defaultPoolUsesDeviceBudget": defaultPoolUsesDeviceBudget,
            "explicit128BudgetIsPreserved": explicit128BudgetIsPreserved,
        ]
        return (checks, automaticBudgetFloor, defaultBudgetPool, explicit128Pool)
    }

    static func copyExtentChecks(
        _ device: MTLDevice
    ) -> [String: Any] {
        let incompatibleCopy = incompatibleCopyFixture()
        let incompatibleCopyGraphs = admittedGraphs([incompatibleCopy])
        let incompatibleCopyPair = pairPlan([incompatibleCopy])
        let incompatibleCopyPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 2_048
        )
        let incompatibleCopyProbeAccepted: Bool
        switch incompatibleCopyPool.persistentTargetPlansResult(
            admittedGraphs: incompatibleCopyGraphs,
            pairPlan: incompatibleCopyPair,
            requestedWidth: 1,
            requestedHeight: 1
        ) {
        case .success: incompatibleCopyProbeAccepted = true
        case .failure: incompatibleCopyProbeAccepted = false
        }
        let incompatibleCopyFrameReason: String
        switch incompatibleCopyPool.framePlanResultForPersistentGraphTargets(
            admittedGraphs: incompatibleCopyGraphs,
            pairPlan: incompatibleCopyPair,
            requestedWidth: 2_048,
            requestedHeight: 1_152,
            usesSharedFullFrameWorkingPair: true
        ) {
        case .success: incompatibleCopyFrameReason = "accepted"
        case let .failure(failure):
            incompatibleCopyFrameReason = failure.localFallbackReasonCode
        }

        let fit256 = Graph.TargetExtent(
            kind: .fit, first: 256, second: nil
        )
        let fit128 = Graph.TargetExtent(
            kind: .fit, first: 128, second: nil
        )
        let fitCopy = copyExtentFixture(
            layerID: 534,
            firstExtent: fit256,
            secondExtent: fit256
        )
        let fitCopyPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 2_048
        )
        let fitCopyFrameExtents: [[Int]]
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: admittedGraphs([fitCopy]),
            pairPlan: pairPlan([fitCopy]),
            requestedWidth: 2_048,
            requestedHeight: 1_152
        ) {
        case let .success(value):
            fitCopyFrameExtents = value.plans.flatMap(\.logicalTargets).map {
                [$0.extent.width, $0.extent.height]
            }.sorted { lhs, rhs in
                lhs.lexicographicallyPrecedes(rhs)
            }
        case .failure:
            fitCopyFrameExtents = []
        }

        let incompatibleFitCopy = copyExtentFixture(
            layerID: 535,
            firstExtent: fit256,
            secondExtent: fit128
        )
        let incompatibleFitGraphs = admittedGraphs([incompatibleFitCopy])
        let incompatibleFitPair = pairPlan([incompatibleFitCopy])
        let incompatibleFitPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 2_048
        )
        let incompatibleFitProbeAccepted: Bool
        switch incompatibleFitPool.persistentTargetPlansResult(
            admittedGraphs: incompatibleFitGraphs,
            pairPlan: incompatibleFitPair,
            requestedWidth: 1,
            requestedHeight: 1
        ) {
        case .success: incompatibleFitProbeAccepted = true
        case .failure: incompatibleFitProbeAccepted = false
        }
        let incompatibleFitFrameReason: String
        switch incompatibleFitPool.framePlanResultForPersistentGraphTargets(
            admittedGraphs: incompatibleFitGraphs,
            pairPlan: incompatibleFitPair,
            requestedWidth: 2_048,
            requestedHeight: 1_152,
            usesSharedFullFrameWorkingPair: true
        ) {
        case .success: incompatibleFitFrameReason = "accepted"
        case let .failure(failure):
            incompatibleFitFrameReason = failure.localFallbackReasonCode
        }

        let fitScale = Graph.TargetExtent(
            width: nil,
            height: nil,
            fit: 256,
            scale: 2
        )
        let fitScaleCopy = copyExtentFixture(
            layerID: 536,
            firstExtent: fitScale,
            secondExtent: fitScale
        )
        let fitScaleFrameExtents: [[Int]]
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: admittedGraphs([fitScaleCopy]),
            pairPlan: pairPlan([fitScaleCopy]),
            requestedWidth: 2_048,
            requestedHeight: 1_152
        ) {
        case let .success(value):
            fitScaleFrameExtents = value.plans.flatMap(\.logicalTargets).map {
                [$0.extent.width, $0.extent.height]
            }.sorted { lhs, rhs in
                lhs.lexicographicallyPrecedes(rhs)
            }
        case .failure:
            fitScaleFrameExtents = []
        }

        let fitScaleOne = Graph.TargetExtent(
            width: nil,
            height: nil,
            fit: 256,
            scale: 1
        )
        let incompatibleFitScaleCopy = copyExtentFixture(
            layerID: 540,
            firstExtent: fitScale,
            secondExtent: fitScaleOne
        )
        let incompatibleFitScaleGraphs = admittedGraphs([
            incompatibleFitScaleCopy
        ])
        let incompatibleFitScalePair = pairPlan([
            incompatibleFitScaleCopy
        ])
        let incompatibleFitScaleProbeAccepted: Bool
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: incompatibleFitScaleGraphs,
            pairPlan: incompatibleFitScalePair,
            requestedWidth: 1,
            requestedHeight: 1
        ) {
        case .success: incompatibleFitScaleProbeAccepted = true
        case .failure: incompatibleFitScaleProbeAccepted = false
        }
        let incompatibleFitScaleFrameReason: String
        switch fitCopyPool.framePlanResultForPersistentGraphTargets(
            admittedGraphs: incompatibleFitScaleGraphs,
            pairPlan: incompatibleFitScalePair,
            requestedWidth: 2_048,
            requestedHeight: 1_152,
            usesSharedFullFrameWorkingPair: true
        ) {
        case .success: incompatibleFitScaleFrameReason = "accepted"
        case let .failure(failure):
            incompatibleFitScaleFrameReason = failure.localFallbackReasonCode
        }

        let absolute640x360 = Graph.TargetExtent(
            kind: .absolute, first: 640, second: 360
        )
        let absolute320x180 = Graph.TargetExtent(
            kind: .absolute, first: 320, second: 180
        )
        let absoluteCopy = copyExtentFixture(
            layerID: 537,
            firstExtent: absolute640x360,
            secondExtent: absolute640x360
        )
        let absoluteCopyFrameExtents: [[Int]]
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: admittedGraphs([absoluteCopy]),
            pairPlan: pairPlan([absoluteCopy]),
            requestedWidth: 2_048,
            requestedHeight: 1_152
        ) {
        case let .success(value):
            absoluteCopyFrameExtents = value.plans.flatMap(\.logicalTargets).map {
                [$0.extent.width, $0.extent.height]
            }.sorted { lhs, rhs in
                lhs.lexicographicallyPrecedes(rhs)
            }
        case .failure:
            absoluteCopyFrameExtents = []
        }

        let incompatibleAbsoluteCopy = copyExtentFixture(
            layerID: 538,
            firstExtent: absolute640x360,
            secondExtent: absolute320x180
        )
        let incompatibleAbsoluteGraphs = admittedGraphs([
            incompatibleAbsoluteCopy
        ])
        let incompatibleAbsolutePair = pairPlan([
            incompatibleAbsoluteCopy
        ])
        let incompatibleAbsoluteProbeAccepted: Bool
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: incompatibleAbsoluteGraphs,
            pairPlan: incompatibleAbsolutePair,
            requestedWidth: 1,
            requestedHeight: 1
        ) {
        case .success: incompatibleAbsoluteProbeAccepted = true
        case .failure: incompatibleAbsoluteProbeAccepted = false
        }
        let incompatibleAbsoluteFrameReason: String
        switch fitCopyPool.framePlanResultForPersistentGraphTargets(
            admittedGraphs: incompatibleAbsoluteGraphs,
            pairPlan: incompatibleAbsolutePair,
            requestedWidth: 2_048,
            requestedHeight: 1_152,
            usesSharedFullFrameWorkingPair: true
        ) {
        case .success: incompatibleAbsoluteFrameReason = "accepted"
        case let .failure(failure):
            incompatibleAbsoluteFrameReason = failure.localFallbackReasonCode
        }

        let singleAxisWidth = Graph.TargetExtent(
            width: 640, height: nil, fit: nil, scale: nil
        )
        let singleAxisCopy = copyExtentFixture(
            layerID: 539,
            firstExtent: singleAxisWidth,
            secondExtent: singleAxisWidth
        )
        let singleAxisFrameExtents: [[Int]]
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: admittedGraphs([singleAxisCopy]),
            pairPlan: pairPlan([singleAxisCopy]),
            requestedWidth: 2_048,
            requestedHeight: 1_152
        ) {
        case let .success(value):
            singleAxisFrameExtents = value.plans.flatMap(\.logicalTargets).map {
                [$0.extent.width, $0.extent.height]
            }.sorted { lhs, rhs in
                lhs.lexicographicallyPrecedes(rhs)
            }
        case .failure:
            singleAxisFrameExtents = []
        }

        let singleAxisWidth320 = Graph.TargetExtent(
            width: 320, height: nil, fit: nil, scale: nil
        )
        let incompatibleSingleAxisCopy = copyExtentFixture(
            layerID: 541,
            firstExtent: singleAxisWidth,
            secondExtent: singleAxisWidth320
        )
        let incompatibleSingleAxisGraphs = admittedGraphs([
            incompatibleSingleAxisCopy
        ])
        let incompatibleSingleAxisPair = pairPlan([
            incompatibleSingleAxisCopy
        ])
        let incompatibleSingleAxisProbeAccepted: Bool
        switch fitCopyPool.persistentTargetPlansResult(
            admittedGraphs: incompatibleSingleAxisGraphs,
            pairPlan: incompatibleSingleAxisPair,
            requestedWidth: 1,
            requestedHeight: 1
        ) {
        case .success: incompatibleSingleAxisProbeAccepted = true
        case .failure: incompatibleSingleAxisProbeAccepted = false
        }
        let incompatibleSingleAxisFrameReason: String
        switch fitCopyPool.framePlanResultForPersistentGraphTargets(
            admittedGraphs: incompatibleSingleAxisGraphs,
            pairPlan: incompatibleSingleAxisPair,
            requestedWidth: 2_048,
            requestedHeight: 1_152,
            usesSharedFullFrameWorkingPair: true
        ) {
        case .success: incompatibleSingleAxisFrameReason = "accepted"
        case let .failure(failure):
            incompatibleSingleAxisFrameReason = failure.localFallbackReasonCode
        }

        let checks: [String: Any] = [
            "incompatibleCopyProbeAccepted": incompatibleCopyProbeAccepted,
            "incompatibleCopyFrameReason": incompatibleCopyFrameReason,
            "fitCopyFrameExtents": fitCopyFrameExtents,
            "incompatibleFitProbeAccepted": incompatibleFitProbeAccepted,
            "incompatibleFitFrameReason": incompatibleFitFrameReason,
            "fitScaleFrameExtents": fitScaleFrameExtents,
            "incompatibleFitScaleProbeAccepted":
                incompatibleFitScaleProbeAccepted,
            "incompatibleFitScaleFrameReason":
                incompatibleFitScaleFrameReason,
            "absoluteCopyFrameExtents": absoluteCopyFrameExtents,
            "incompatibleAbsoluteProbeAccepted":
                incompatibleAbsoluteProbeAccepted,
            "incompatibleAbsoluteFrameReason": incompatibleAbsoluteFrameReason,
            "singleAxisFrameExtents": singleAxisFrameExtents,
            "incompatibleSingleAxisProbeAccepted":
                incompatibleSingleAxisProbeAccepted,
            "incompatibleSingleAxisFrameReason":
                incompatibleSingleAxisFrameReason,
        ]
        return checks
    }

    static func sampleBudgetChecks(
        _ device: MTLDevice,
        automaticBudgetFloor: Int,
        defaultBudgetPool: SceneOffscreenTexturePool,
        explicit128Pool: SceneOffscreenTexturePool
    ) -> [String: Any] {
        func directChain(layerID: Int, count: Int) -> [Fixture] {
            var result: [Fixture] = []
            var input: Graph.TextureIdentity?
            for effectIndex in 0..<count {
                let next = directFixture(
                    effectIndex: effectIndex,
                    layerID: layerID,
                    input: input
                )
                result.append(next)
                input = next.execution.renderGraph.finalOutput
            }
            return result
        }

        let layer13First = directFixture(effectIndex: 0, layerID: 13)
        let layer13Second = directFixture(
            effectIndex: 1,
            layerID: 13,
            input: layer13First.execution.renderGraph.finalOutput
        )
        let layer13Quarter = fixture(
            effectIndex: 2,
            layerID: 13,
            framebufferNamePrefix: "quarter-",
            framebufferScale: 4,
            input: layer13Second.execution.renderGraph.finalOutput
        )
        let layer13Fourth = directFixture(
            effectIndex: 3,
            layerID: 13,
            input: layer13Quarter.execution.renderGraph.finalOutput
        )
        let layer13Half = fixture(
            effectIndex: 4,
            layerID: 13,
            framebufferNamePrefix: "half-",
            framebufferScale: 2,
            input: layer13Fourth.execution.renderGraph.finalOutput
        )
        let sample302Chains: [([Fixture], Int, Int)] = [
            ([
                layer13First, layer13Second, layer13Quarter, layer13Fourth,
                layer13Half,
            ], 2_048, 1_211),
            (directChain(layerID: 82, count: 1), 1_002, 982),
            (directChain(layerID: 86, count: 1), 2_048, 1_782),
            (directChain(layerID: 111, count: 6), 2_048, 1_887),
            (directChain(layerID: 129, count: 2), 2_048, 1_152),
            (directChain(layerID: 666, count: 1), 2_048, 1_330),
        ]
        let sample302Plans = sample302Chains.map { fixtures, width, height in
            let plans = targetPlans(fixtures, width: width, height: height)
            switch SceneLayerGraphTargetPlan.make(
                plans: plans,
                pairPlan: pairPlan(fixtures),
                byteBudget: automaticBudgetFloor
            ) {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("sample 302 target plan failed: \(failure.rawValue)")
            }
        }
        let sample302RequiredBytes = sample302Plans.reduce(0) {
            $0 + $1.residentByteCost
        }
        let sample302ShapeIsExact = sample302Plans.count == 6
            && sample302Plans.reduce(0, { $0 + $1.stages.count }) == 16
            && sample302RequiredBytes == 134_683_872
        let sample302FitsAutomaticBudget = defaultBudgetPool.allocationCache
            .preflightGraphs(sample302Plans) == .ready
            && defaultBudgetPool.residentAllocationCount == 0
            && defaultBudgetPool.residentTextureCount == 0
            && defaultBudgetPool.residentByteCost == 0
        let sample302Explicit128RejectedWithoutMutation =
            explicit128Pool.allocationCache.preflightGraphs(sample302Plans)
                == .rejected(reasonCode: "frame-target-byte-budget-exceeded")
            && explicit128Pool.residentAllocationCount == 0
            && explicit128Pool.residentTextureCount == 0
            && explicit128Pool.residentByteCost == 0

        let zeroResidentFixture = directFixture(
            effectIndex: 580,
            layerID: 580
        )
        let incomingResidentFixture = directFixture(
            effectIndex: 581,
            layerID: 581
        )
        guard case .success(let zeroResidentPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans([zeroResidentFixture], width: 8, height: 8),
                pairPlan: pairPlan([zeroResidentFixture]),
                byteBudget: 512,
                pairStorage: .shared
            ), case .success(let incomingResidentPlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans([incomingResidentFixture], width: 8, height: 8),
                pairPlan: pairPlan([incomingResidentFixture]),
                byteBudget: 512
            ) else { fatalError("zero-byte resident preflight fixture failed") }
        let zeroByteResidentDoesNotStopLRUEviction =
            zeroResidentPlan.residentByteCost == 0
                && incomingResidentPlan.residentByteCost == 512
                && SceneOffscreenTextureFramePreflight.evaluate(
                    plans: [incomingResidentPlan],
                    residents: [
                        .init(
                            id: 1,
                            location: .currentGraph(zeroResidentPlan.key),
                            graphPlan: zeroResidentPlan,
                            history: nil,
                            demotedHistory: nil,
                            byteCost: 0,
                            submissionPinCount: 0,
                            historyPinCount: 0,
                            permitsOrderedReuse: false,
                            isResetInvalidated: false,
                            lastAccess: 1,
                            existedBeforeFrame: true,
                            requiredByFrame: false
                        ),
                        .init(
                            id: 2,
                            location: .currentOther,
                            graphPlan: nil,
                            history: nil,
                            demotedHistory: nil,
                            byteCost: 512,
                            submissionPinCount: 0,
                            historyPinCount: 0,
                            permitsOrderedReuse: false,
                            isResetInvalidated: false,
                            lastAccess: 2,
                            existedBeforeFrame: true,
                            requiredByFrame: false
                        ),
                    ],
                    byteBudget: 512
                ) == .ready

        let checks: [String: Any] = [
            "sample302RequiredBytes": sample302RequiredBytes,
            "sample302ShapeIsExact": sample302ShapeIsExact,
            "sample302FitsAutomaticBudget": sample302FitsAutomaticBudget,
            "sample302Explicit128RejectedWithoutMutation":
                sample302Explicit128RejectedWithoutMutation,
            "zeroByteResidentDoesNotStopLRUEviction":
                zeroByteResidentDoesNotStopLRUEviction,
        ]
        return checks
    }

    static func directChainChecks(
        _ device: MTLDevice
    ) -> (
        checks: [String: Any],
        rotationPool: SceneOffscreenTexturePool,
        directFixtures: [Fixture],
        directPairPlan: SceneLayerFullFramePairPlan,
        directGraphs: [Graph],
        defaultBudget: Int,
        directBudgetPool: SceneOffscreenTexturePool
    ) {
        let rotationPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 1_000
        )
        let directFirst = directFixture(effectIndex: 50)
        let directSecond = directFixture(
            effectIndex: 51,
            input: directFirst.execution.renderGraph.finalOutput
        )
        let directThird = directFixture(
            effectIndex: 52,
            input: directSecond.execution.renderGraph.finalOutput
        )
        let directFixtures = [directFirst, directSecond, directThird]
        let directPairPlan = pairPlan(directFixtures)
        let directGraphs = admittedGraphs(directFixtures)
        let defaultBudget = 128 * 1_024 * 1_024
        let directBudgetPlans = targetPlans(
            directFixtures, width: 4_000, height: 4_000
        )
        guard case .success(let directBudgetPlan) = SceneLayerGraphTargetPlan.make(
            plans: directBudgetPlans,
            pairPlan: directPairPlan,
            byteBudget: defaultBudget
        ) else { fatalError("near-budget reuse plan rejected") }
        let directBudgetPool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 4_096,
            residentByteBudget: defaultBudget
        )
        let poolLimitPolicy = SceneFullFrameExtentPolicy(
            maximumDimensionClass: .poolLimit,
            requiresExactInputExtent: false
        )
        let exactStandardPolicy = SceneFullFrameExtentPolicy(
            maximumDimensionClass: .standard,
            requiresExactInputExtent: true
        )
        let exactSamplingTextureExtent = SceneOffscreenResolutionPolicy
            .resolvedDimensions(
                width: 5_000,
                height: 2_200,
                hardLimit: 8_192,
                policy: SceneEffectSourceExtentContract.exactSamplingTexture
                    .targetPolicy
            )
        let oversizedExactSamplingTextureRejected =
            SceneOffscreenResolutionPolicy.resolvedDimensions(
                width: 8_193,
                height: 2_200,
                hardLimit: 8_192,
                policy: SceneEffectSourceExtentContract.exactSamplingTexture
                    .targetPolicy
            ) == nil
        guard let standardExtent = directBudgetPool.persistentTargetPlans(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            requestedWidth: 4_000,
            requestedHeight: 3_000
        ), let poolLimitExtent = directBudgetPool.persistentTargetPlans(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            extentPolicy: poolLimitPolicy,
            requestedWidth: 4_000,
            requestedHeight: 3_000
        ), let exactChainExtent = directBudgetPool.persistentTargetPlans(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            extentPolicy: SceneEffectSourceExtentContract.exactSamplingTexture
                .targetPolicy,
            requestedWidth: 4_000,
            requestedHeight: 3_000
        ), directBudgetPool.persistentTargetPlans(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            extentPolicy: exactStandardPolicy,
            requestedWidth: 4_000,
            requestedHeight: 3_000
        ) == nil else { fatalError("typed extent policy fixture failed") }
        guard let directBudgetPrepared = directBudgetPool.preparePersistentGraphTargets(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            extentPolicy: poolLimitPolicy,
            requestedWidth: 4_000,
            requestedHeight: 4_000
        ) else { fatalError("near-budget reused chain allocation failed") }
        let persistentPrepareNoMutation = directBudgetPool.residentAllocationCount == 0
            && directBudgetPool.residentTextureCount == 0
            && directBudgetPool.residentByteCost == 0
        let directPhysicalObjects = Set(directBudgetPrepared.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
        let directStageHandoffContinuous = zip(
            directBudgetPrepared.leases,
            directBudgetPrepared.leases.dropFirst()
        ).allSatisfy { prior, next in
            prior.allocation.resources[prior.table.plan.output]?.token
                == next.allocation.resources[next.table.plan.input]?.token
        }
        guard let directBudgetCommit = directBudgetPrepared.commitAndPin(
            historyTokensByEffect: [:]
        ) else { fatalError("near-budget chain commit failed") }
        let persistentRepeatedCommitRejected = directBudgetPrepared.commitAndPin(
            historyTokensByEffect: [:]
        ) == nil
        let persistentSubmissionAndHistorySeparated =
            directBudgetCommit.submissionPin.effect == nil
            && directBudgetCommit.historyPinsByEffect.isEmpty
        directBudgetCommit.submissionPin.release()
        guard let directBudgetHit = directBudgetPool.preparePersistentGraphTargets(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            extentPolicy: poolLimitPolicy,
            requestedWidth: 4_000,
            requestedHeight: 4_000
        ) else { fatalError("near-budget cache hit failed") }
        let persistentStable = zip(
            directBudgetCommit.leases, directBudgetHit.leases
        ).allSatisfy {
            $0.generation == $1.generation
                && $0.table.inputTexture === $1.table.inputTexture
                && $0.table.outputTexture === $1.table.outputTexture
        }
        guard let directBudgetHitCommit = directBudgetHit.commitAndPin(
            historyTokensByEffect: [:]
        ) else { fatalError("near-budget cache hit commit failed") }
        directBudgetHitCommit.submissionPin.release()
        let persistentCommittedAllocationCount = directBudgetPool.residentAllocationCount
        let persistentCommittedTextureCount = directBudgetPool.residentTextureCount
        let persistentCommittedBytes = directBudgetPool.residentByteCost

        let checks: [String: Any] = [
            "persistentGraphStable": persistentStable,
            "persistentPrepareNoMutation": persistentPrepareNoMutation,
            "persistentRepeatedCommitRejected": persistentRepeatedCommitRejected,
            "persistentSubmissionAndHistorySeparated":
                persistentSubmissionAndHistorySeparated,
            "persistentGraphAllocationCount": persistentCommittedAllocationCount,
            "persistentGraphTextureCount": persistentCommittedTextureCount,
            "persistentGraphBytes": persistentCommittedBytes,
            "graphPlanNearBudgetBytes": directBudgetPlan.residentByteCost,
            "graphPlanSlotCount": directBudgetPlan.slots.count,
            "chainPhysicalObjectCount": directPhysicalObjects.count,
            "chainStageHandoffContinuous": directStageHandoffContinuous,
            "typedStandardExtent": [standardExtent.width, standardExtent.height],
            "typedPoolLimitExtent": [poolLimitExtent.width, poolLimitExtent.height],
            "typedExactChainExtent": [exactChainExtent.width, exactChainExtent.height],
            "typedExactStandardClampRejected": true,
            "exactSamplingTextureExtent": exactSamplingTextureExtent.map {
                [$0.0, $0.1]
            },
            "oversizedExactSamplingTextureRejected":
                oversizedExactSamplingTextureRejected,
        ]
        return (checks, rotationPool, directFixtures, directPairPlan, directGraphs, defaultBudget, directBudgetPool)
    }

    static func planIdentityChecks(
        _ device: MTLDevice,
        defaultBudget: Int
    ) -> [String: Any] {
        let oversized = fixture(effectIndex: 80, precise: true)
        let oversizedPlans = targetPlans([oversized], width: 4_096, height: 4_096)
        let oversizedPairPlan = pairPlan([oversized])
        let defaultBudgetFailure: String
        switch SceneLayerGraphTargetPlan.make(
            plans: oversizedPlans,
            pairPlan: oversizedPairPlan,
            byteBudget: defaultBudget
        ) {
        case .success: defaultBudgetFailure = "success"
        case .failure(let failure): defaultBudgetFailure = failure.rawValue
        }
        guard case .success(let oversizedPlan) = SceneLayerGraphTargetPlan.make(
            plans: oversizedPlans,
            pairPlan: oversizedPairPlan,
            byteBudget: Int.max
        ) else { fatalError("oversized plan construction failed") }
        let zeroAllocationCache = SceneOffscreenTextureAllocationCache(
            byteBudget: defaultBudget
        )
        var overBudgetFactoryAttempts = 0
        let zeroAllocationAllocator = ScenePersistentGraphTargetAllocator(
            device: device,
            cache: zeroAllocationCache
        ) { descriptor, _ in
            overBudgetFactoryAttempts += 1
            return device.makeTexture(descriptor: descriptor)
        }
        let overBudgetZeroPhysicalAllocation = zeroAllocationAllocator.prepare(
            plan: oversizedPlan
        ) == nil && overBudgetFactoryAttempts == 0
            && zeroAllocationCache.residentAllocationCount == 0

        let uniqueFirst = fixture(
            effectIndex: 90, uniqueFirstTarget: true
        )
        let uniqueSecond = fixture(
            effectIndex: 91,
            input: uniqueFirst.execution.renderGraph.finalOutput
        )
        let uniqueFixtures = [uniqueFirst, uniqueSecond]
        guard case .success(let uniquePlan) = SceneLayerGraphTargetPlan.make(
            plans: targetPlans(uniqueFixtures, width: 8, height: 8),
            pairPlan: pairPlan(uniqueFixtures),
            byteBudget: defaultBudget
        ), let uniqueSlot = uniquePlan.stages[0].slotByIdentity[
            uniqueFirst.framebufferIdentities[0]
        ] else { fatalError("unique slot plan failed") }
        let uniqueNeverCrossEffectReused = !uniquePlan.stages[1]
            .slotByIdentity.values.contains(uniqueSlot)
        let ordinarySlots = Set(uniquePlan.stages[0].plan.logicalTargets.compactMap {
            $0.isUnique ? nil : uniquePlan.stages[0].slotByIdentity[$0.identity]
        })
        let secondOrdinarySlots = Set(
            uniquePlan.stages[1].plan.logicalTargets.compactMap {
                $0.isUnique ? nil : uniquePlan.stages[1].slotByIdentity[$0.identity]
            }
        )
        let ordinaryCrossStageReuse = !ordinarySlots.isDisjoint(
            with: secondOrdinarySlots
        )
        let distinctNameSecond = fixture(
            effectIndex: 92,
            framebufferNamePrefix: "other-",
            input: uniqueFirst.execution.renderGraph.finalOutput
        )
        guard case .success(let distinctNamePlan) =
            SceneLayerGraphTargetPlan.make(
                plans: targetPlans(
                    [uniqueFirst, distinctNameSecond], width: 8, height: 8
                ),
                pairPlan: pairPlan([uniqueFirst, distinctNameSecond]),
                byteBudget: defaultBudget
            ) else { fatalError("distinct name slot plan failed") }
        let distinctFirstSlots = Set(
            distinctNamePlan.stages[0].plan.logicalTargets.compactMap {
                distinctNamePlan.stages[0].slotByIdentity[$0.identity]
            }
        )
        let distinctSecondSlots = Set(
            distinctNamePlan.stages[1].plan.logicalTargets.compactMap {
                distinctNamePlan.stages[1].slotByIdentity[$0.identity]
            }
        )
        let differentNamesNeverAlias = distinctFirstSlots.isDisjoint(
            with: distinctSecondSlots
        )
        let ordinaryCacheIdentityOmitsEffect = uniquePlan.slots.allSatisfy { slot in
            guard let identity = slot.framebufferCacheIdentity,
                  !slot.isEffectUnique else { return true }
            return identity.uniqueEffect == nil
                && ["sharedA", "sharedB"].contains(identity.authoredName)
        }
        let uniqueCacheIdentityIncludesEffect = uniquePlan.slots.contains { slot in
            slot.framebufferCacheIdentity?.uniqueEffect
                == uniqueFirst.execution.renderGraph.effects.first?.key
        }

        let checks: [String: Any] = [
            "defaultBudgetFailure": defaultBudgetFailure,
            "overBudgetZeroPhysicalAllocation": overBudgetZeroPhysicalAllocation,
            "uniqueNeverCrossEffectReused": uniqueNeverCrossEffectReused,
            "ordinaryCrossStageReuse": ordinaryCrossStageReuse,
            "differentFramebufferNamesNeverAlias": differentNamesNeverAlias,
            "ordinaryCacheIdentityOmitsEffect": ordinaryCacheIdentityOmitsEffect,
            "uniqueCacheIdentityIncludesEffect": uniqueCacheIdentityIncludesEffect,
        ]
        return checks
    }

    static func pairMappingChecks(
        _ device: MTLDevice,
        rotationPool: SceneOffscreenTexturePool,
        directPairPlan: SceneLayerFullFramePairPlan,
        directGraphs: [Graph],
        historyFixture: Fixture,
        historyLease1: SceneGraphRenderTargetLease
    ) -> [String: Any] {
        guard let pairPrepared = rotationPool.preparePersistentGraphTargets(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            requestedWidth: 8,
            requestedHeight: 8
        ), pairPrepared.leases.count == directGraphs.count else {
            fatalError("persistent pair allocation failed")
        }
        let pairLeases = pairPrepared.leases
        let pairTokens = Set([
            pairLeases[0].fullFramePair.first,
            pairLeases[0].fullFramePair.second,
        ])
        let persistentPairSharedAcrossStages = pairTokens.count == 2
            && pairLeases.allSatisfy {
                Set([$0.fullFramePair.first, $0.fullFramePair.second]) == pairTokens
            }
        let persistentPairHasTwoPhysicalObjects = Set(pairLeases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        }).count == 2
        let persistentStateProjectionExcludesPair = pairLeases.allSatisfy {
            $0.framebufferAllocation.resources.isEmpty
        } && Set(historyLease1.framebufferAllocation.resources.keys)
            == Set(historyFixture.framebufferIdentities)
            && Set(historyLease1.framebufferAllocation.resources.values.map(\.token))
                .isDisjoint(with: Set([
                    historyLease1.fullFramePair.first,
                    historyLease1.fullFramePair.second,
                ]))
        let persistentPairHandoffContinuous = zip(
            pairLeases, pairLeases.dropFirst()
        ).allSatisfy { prior, next in
            prior.allocation.resources[prior.table.plan.output]?.token
                == next.allocation.resources[next.table.plan.input]?.token
        }
        let baseMemberToken = directPairPlan.baseCaptureMember == .zero
            ? pairLeases[0].fullFramePair.first
            : pairLeases[0].fullFramePair.second
        let persistentPairBaseMapped = pairLeases[0].allocation.resources[
            pairLeases[0].table.plan.input
        ]?.token == baseMemberToken
        let terminalLease = pairLeases[pairLeases.count - 1]
        let persistentPairTerminalFixed = terminalLease.allocation.resources[
            terminalLease.table.plan.output
        ]?.token == terminalLease.fullFramePair.first
            && directPairPlan.terminalMember == .zero
        guard let pairCommit = pairPrepared.commitAndPin(historyTokensByEffect: [:]) else {
            fatalError("persistent pair commit failed")
        }
        let pairGeneration = pairCommit.leases[0].generation
        pairCommit.submissionPin.release()
        guard let pairHit = rotationPool.preparePersistentGraphTargets(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            requestedWidth: 8,
            requestedHeight: 8
        ), let pairHitCommit = pairHit.commitAndPin(historyTokensByEffect: [:]) else {
            fatalError("persistent pair cache hit failed")
        }
        let persistentPairHitStable = pairHitCommit.leases.allSatisfy {
            $0.generation == pairGeneration
        }
        pairHitCommit.submissionPin.release()
        rotationPool.reset()
        let persistentPairResetAllocationCount = rotationPool.residentAllocationCount
        guard let pairAfterReset = rotationPool.preparePersistentGraphTargets(
            admittedGraphs: directGraphs,
            pairPlan: directPairPlan,
            requestedWidth: 8,
            requestedHeight: 8
        ), let pairAfterResetLease = pairAfterReset.leases.first else {
            fatalError("persistent pair reset allocation failed")
        }
        let persistentPairResetGenerationAdvanced = pairAfterResetLease.generation
            > pairGeneration
        let persistentPairResetTokensChanged = pairTokens.isDisjoint(with: Set([
            pairAfterResetLease.fullFramePair.first,
            pairAfterResetLease.fullFramePair.second,
        ]))

        let checks: [String: Any] = [
            "persistentPairSharedAcrossStages": persistentPairSharedAcrossStages,
            "persistentPairHasTwoPhysicalObjects": persistentPairHasTwoPhysicalObjects,
            "persistentStateProjectionExcludesPair":
                persistentStateProjectionExcludesPair,
            "persistentPairHandoffContinuous": persistentPairHandoffContinuous,
            "persistentPairBaseMapped": persistentPairBaseMapped,
            "persistentPairTerminalFixed": persistentPairTerminalFixed,
            "persistentPairHitGenerationStable": persistentPairHitStable,
            "persistentPairResetAllocationCount": persistentPairResetAllocationCount,
            "persistentPairResetGenerationAdvanced":
                persistentPairResetGenerationAdvanced,
            "persistentPairResetTokensChanged": persistentPairResetTokensChanged,
        ]
        return checks
    }

    static func composeMappingChecks(
        _ device: MTLDevice
    ) -> [String: Any] {
        let composePool = SceneOffscreenTexturePool(
            device: device,
            maxDimension: 64,
            residentByteBudget: 2_048
        )
        var composeEndpointAliases: [Bool] = []
        var composePairBijection = true
        var composeTerminalFixed = true
        for composeCount in 0...2 {
            let fixture = composeFixture(
                effectIndex: 120 + composeCount,
                composeCount: composeCount
            )
            let fixtures = [fixture]
            let plan = pairPlan(fixtures)
            guard let prepared = composePool.preparePersistentGraphTargets(
                admittedGraphs: admittedGraphs(fixtures),
                pairPlan: plan,
                requestedWidth: 8,
                requestedHeight: 8
            ), let lease = prepared.leases.first,
                  let inputToken = lease.allocation.resources[
                      lease.table.plan.input
                  ]?.token,
                  let outputToken = lease.allocation.resources[
                      lease.table.plan.output
                  ]?.token else {
                fatalError("compose pair allocation failed")
            }
            composeEndpointAliases.append(inputToken == outputToken)
            composePairBijection = composePairBijection
                && lease.fullFramePair.first != lease.fullFramePair.second
                && lease.texturesByToken.count == 2
            composeTerminalFixed = composeTerminalFixed
                && plan.terminalMember == .zero
                && outputToken == lease.fullFramePair.first
        }

        let checks: [String: Any] = [
            "composeEndpointAliases": composeEndpointAliases,
            "composePairBijection": composePairBijection,
            "composeTerminalFixed": composeTerminalFixed,
        ]
        return checks
    }
}
