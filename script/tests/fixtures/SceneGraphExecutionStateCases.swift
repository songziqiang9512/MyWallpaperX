import Foundation

extension Harness {
    static func main() throws {
        let q1 = identity(.framebuffer, effect: key, name: "q1")
        let q2 = identity(.framebuffer, effect: key, name: "q2")

        // Full-frame-only effects must produce no persistent resource mapping.
        let ordinaryGraph = graph(
            targets: [],
            nodes: [material(0, ordinal: 0, target: output, reads: [input])]
        )
        let ordinaryPlan = requirePlan(ordinaryGraph)
        let ordinaryPair = requirePair(ordinaryGraph)
        let ordinaryAllocation = allocation(
            plan: ordinaryPlan, generation: 1, prefix: "ordinary"
        )
        let ordinary = require(State.reduce(
            graph: ordinaryGraph,
            targetPlan: ordinaryPlan,
            pairStep: ordinaryPair,
            allocation: ordinaryAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let ordinaryReprepared = require(State.reduce(
            graph: ordinaryGraph,
            targetPlan: ordinaryPlan,
            pairStep: ordinaryPair,
            allocation: allocation(
                plan: ordinaryPlan, generation: 2, prefix: "ordinary-reprepared"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: ordinary.nextState
        ))
        // Admission removes condition-false passes without renumbering their
        // authored material ordinals, which still select instance overlays.
        let prunedOrdinalGraph = graph(
            targets: [],
            nodes: [material(7, ordinal: 2, target: output, reads: [input])]
        )
        let prunedOrdinalPlan = requirePlan(prunedOrdinalGraph)
        let prunedOrdinal = require(State.reduce(
            graph: prunedOrdinalGraph,
            targetPlan: prunedOrdinalPlan,
            pairStep: requirePair(prunedOrdinalGraph),
            allocation: allocation(
                plan: prunedOrdinalPlan, generation: 1, prefix: "pruned-ordinal"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let endpointDescriptor = State.ResourceDescriptor(
            extent: ordinaryPlan.inputExtent,
            format: .rgbaBackbuffer,
            addressMode: .clampToEdge,
            isUnique: false,
            initialClear: nil
        )
        let endpointAllocation = State.Allocation(
            generation: 1,
            resources: [
                input: .init(
                    token: .init(rawValue: "forbidden-input"),
                    descriptor: endpointDescriptor
                ),
                output: .init(
                    token: .init(rawValue: "forbidden-output"),
                    descriptor: endpointDescriptor
                ),
            ]
        )

        // Compose is routing-only state, including multiple rotations.
        let singleComposeGraph = graph(
            targets: [],
            nodes: [
                material(
                    0, ordinal: 0, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(1, ordinal: 1, target: output, reads: [input]),
            ]
        )
        let singleComposePlan = requirePlan(singleComposeGraph)
        let singleComposePair = requirePair(singleComposeGraph)
        let singleCompose = require(State.reduce(
            graph: singleComposeGraph,
            targetPlan: singleComposePlan,
            pairStep: singleComposePair,
            allocation: allocation(
                plan: singleComposePlan, generation: 1, prefix: "single-compose"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let multipleComposeGraph = graph(
            targets: [],
            nodes: [
                material(
                    0, ordinal: 0, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(
                    1, ordinal: 1, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(2, ordinal: 2, target: output, reads: [input]),
            ]
        )
        let multipleComposePlan = requirePlan(multipleComposeGraph)
        let multipleComposePair = requirePair(multipleComposeGraph)
        let multipleCompose = require(State.reduce(
            graph: multipleComposeGraph,
            targetPlan: multipleComposePlan,
            pairStep: multipleComposePair,
            allocation: allocation(
                plan: multipleComposePlan, generation: 1, prefix: "multi-compose"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let originalPairNode = singleComposePair.nodes[0]
        let mismatchedPairNode = Pair.NodeStep(
            nodeIndex: originalPairNode.nodeIndex,
            definitionPassIndex: originalPairNode.definitionPassIndex,
            kind: originalPairNode.kind,
            currentMemberBeforeNode: originalPairNode.currentMemberBeforeNode,
            fullFrameReadMember: originalPairNode.fullFrameReadMember,
            fullFrameWriteMember: originalPairNode.fullFrameWriteMember,
            rotatesAfterNode: false,
            currentMemberAfterNode: originalPairNode.currentMemberBeforeNode
        )
        let mismatchedPair = Pair.EffectStep(
            effect: singleComposePair.effect,
            inputIdentity: singleComposePair.inputIdentity,
            outputIdentity: singleComposePair.outputIdentity,
            inputMember: singleComposePair.inputMember,
            outputMember: singleComposePair.outputMember,
            composeTransitionCount: singleComposePair.composeTransitionCount,
            fullFrameOutputWriteCount: singleComposePair.fullFrameOutputWriteCount,
            nodes: [mismatchedPairNode] + singleComposePair.nodes.dropFirst()
        )

        // Persistent authored FBO copy/swap mapping survives across frames.
        let swapGraph = graph(
            targets: [rawTarget(q1), rawTarget(q2)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                material(1, ordinal: 1, target: q2, reads: [input]),
                command(2, kind: .swap, source: q1, target: q2),
                material(3, ordinal: 2, target: output, reads: [q1]),
            ]
        )
        let swapPlan = requirePlan(swapGraph)
        let swapPair = requirePair(swapGraph)
        let swapAllocation = allocation(
            plan: swapPlan, generation: 1, prefix: "swap"
        )
        let swap1 = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let unchangedFBOsWithFreshGenerationFailure = failure(
            graph: swapGraph,
            plan: swapPlan,
            pair: swapPair,
            allocation: .init(
                generation: 2,
                resources: swapAllocation.resources
            ),
            previous: swap1.nextState
        )
        let swap2 = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: swap1.nextState
        ))
        let resetSwap = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: swap1.nextState
        ))
        let reparsedSwap = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 2,
            resetGeneration: 1,
            previous: swap1.nextState
        ))

        let copyGraph = graph(
            targets: [rawTarget(q1), rawTarget(q2)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                command(1, kind: .copy, source: q1, target: q2),
                material(2, ordinal: 1, target: output, reads: [q2]),
            ]
        )
        let copyPlan = requirePlan(copyGraph)
        let copied = require(State.reduce(
            graph: copyGraph,
            targetPlan: copyPlan,
            pairStep: requirePair(copyGraph),
            allocation: allocation(plan: copyPlan, generation: 1, prefix: "copy"),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let zeroClear = SceneJSONValue.array(Array(
            repeating: SceneJSONValue.number(0), count: 4
        ))
        let clearGraph = graph(
            targets: [rawTarget(q1, clear: zeroClear)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                material(1, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let clearPlan = requirePlan(clearGraph)
        let clearPair = requirePair(clearGraph)
        let clearAllocation = allocation(
            plan: clearPlan, generation: 1, prefix: "clear"
        )
        let clear1 = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let clear2 = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: clear1.nextState
        ))
        let clearReset = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: clear1.nextState
        ))
        let clearFresh = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: allocation(
                plan: clearPlan, generation: 2, prefix: "clear-fresh"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: clear1.nextState
        ))

        let functionGraph = graph(
            targets: [rawTarget(q1, unique: true)],
            nodes: [
                material(0, ordinal: 0, target: output, reads: [q1, input]),
            ]
        )
        let functionPlan = requirePlan(
            functionGraph,
            materialFunctionTargets: [q1]
        )
        let functionPair = requirePair(functionGraph)
        let functionAllocation = allocation(
            plan: functionPlan, generation: 1, prefix: "function"
        )
        let duplicateInvocation = State.MaterialFunctionInvocation(
            name: "reset",
            targets: [q1, q1]
        )
        let functionTransition = require(State.reduce(
            graph: functionGraph,
            targetPlan: functionPlan,
            pairStep: functionPair,
            allocation: functionAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            materialFunctionInvocations: [duplicateInvocation, duplicateInvocation]
        ))
        let missingFunctionTargetFailure = failure(
            graph: functionGraph,
            plan: functionPlan,
            pair: functionPair,
            allocation: functionAllocation,
            materialFunctionInvocations: [.init(name: "reset", targets: [q2])]
        )

        // A descriptor resize gets a disjoint allocation and keeps the swap
        // permutation, while its content versions restart from zero.
        let resizeGraph = graph(
            targets: [
                rawTarget(q1, extent: dynamicExtent),
                rawTarget(q2, extent: dynamicExtent),
            ],
            nodes: swapGraph.nodes
        )
        let resizeSmallPlan = requirePlan(resizeGraph)
        let resizeLargePlan = requirePlan(resizeGraph, width: 200, height: 100)
        let resizePair = requirePair(resizeGraph)
        let resizeSmall = require(State.reduce(
            graph: resizeGraph,
            targetPlan: resizeSmallPlan,
            pairStep: resizePair,
            allocation: allocation(
                plan: resizeSmallPlan, generation: 1, prefix: "resize-small"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let resizeLarge = require(State.reduce(
            graph: resizeGraph,
            targetPlan: resizeLargePlan,
            pairStep: resizePair,
            allocation: allocation(
                plan: resizeLargePlan, generation: 2, prefix: "resize-large"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: resizeSmall.nextState
        ))

        // q1 is the direct history identity; q1/q2 form its swap closure.
        let historyGraph = graph(
            targets: [
                rawTarget(q1, unique: true),
                rawTarget(q2, unique: true),
            ],
            nodes: [
                material(0, ordinal: 0, target: q2, reads: [q1, input]),
                command(1, kind: .swap, source: q1, target: q2),
                material(2, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let historyPlan = requirePlan(historyGraph)
        let historyPair = requirePair(historyGraph)
        let historyAllocation = allocation(
            plan: historyPlan, generation: 1, prefix: "history-old"
        )
        let history1 = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: historyAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let oldSelected = history1.nextState.logicalMapping[q1]!
        let freshHistoryAllocation = allocation(
            plan: historyPlan, generation: 2, prefix: "history-new"
        )
        let expectedNewToken = freshHistoryAllocation.resources[q2]!.token
        let rehydration = [oldSelected.token: expectedNewToken]
        let rehydrated = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState,
            historyRehydration: rehydration
        ))
        let rehydratedAgain = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState,
            historyRehydration: rehydration
        ))
        let missingRehydration = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState
        ))
        let wrongTarget = freshHistoryAllocation.resources[q1]!.token
        let invalidRehydration = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: freshHistoryAllocation,
            previous: history1.nextState,
            historyRehydration: [oldSelected.token: wrongTarget]
        )
        let outsideRehydration = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: freshHistoryAllocation,
            previous: history1.nextState,
            historyRehydration: [
                .init(rawValue: "not-in-history-closure"): expectedNewToken
            ]
        )
        let reusedTokenAllocation = allocation(
            plan: historyPlan,
            generation: 3,
            prefix: "history-reuse",
            tokenOverrides: [q1: historyAllocation.resources[q1]!.token.rawValue]
        )
        let reusedTokenFailure = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: reusedTokenAllocation,
            previous: history1.nextState
        )
        let historyReset = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: historyAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: history1.nextState
        ))

        let repeatHistoryGraph = graph(
            targets: [
                rawTarget(q1, unique: true, uvs: .string("repeat")),
                rawTarget(q2, unique: true, uvs: .string("repeat")),
            ],
            nodes: historyGraph.nodes
        )
        let repeatHistoryPlan = requirePlan(repeatHistoryGraph)
        let repeatHistoryPair = requirePair(repeatHistoryGraph)
        let repeatHistoryAllocation = allocation(
            plan: repeatHistoryPlan,
            generation: 4,
            prefix: "history-repeat"
        )
        let clampToRepeat = require(State.reduce(
            graph: repeatHistoryGraph,
            targetPlan: repeatHistoryPlan,
            pairStep: repeatHistoryPair,
            allocation: repeatHistoryAllocation,
            effectGeneration: 2,
            resetGeneration: 1,
            previous: history1.nextState
        ))
        let clampToRepeatRehydrationFailure = failure(
            graph: repeatHistoryGraph,
            plan: repeatHistoryPlan,
            pair: repeatHistoryPair,
            allocation: repeatHistoryAllocation,
            effectGeneration: 2,
            previous: history1.nextState,
            historyRehydration: [
                oldSelected.token: repeatHistoryAllocation.resources[q2]!.token
            ]
        )
        let repeatHistory1 = require(State.reduce(
            graph: repeatHistoryGraph,
            targetPlan: repeatHistoryPlan,
            pairStep: repeatHistoryPair,
            allocation: repeatHistoryAllocation,
            effectGeneration: 2,
            resetGeneration: 1
        ))
        let freshClampAllocation = allocation(
            plan: historyPlan,
            generation: 5,
            prefix: "history-clamp"
        )
        let repeatToClamp = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshClampAllocation,
            effectGeneration: 3,
            resetGeneration: 1,
            previous: repeatHistory1.nextState
        ))
        let repeatSelected = repeatHistory1.nextState.logicalMapping[q1]!
        let repeatToClampRehydrationFailure = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: freshClampAllocation,
            effectGeneration: 3,
            previous: repeatHistory1.nextState,
            historyRehydration: [
                repeatSelected.token: freshClampAllocation.resources[q2]!.token
            ]
        )

        // State validation still rejects FBO hazards and malformed allocation.
        let aliasAllocation = allocation(
            plan: swapPlan,
            generation: 1,
            prefix: "alias",
            tokenOverrides: [q1: "same", q2: "same"]
        )
        let hazardGraph = graph(
            targets: [rawTarget(q1, unique: true)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [q1, input]),
                material(1, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let hazardPlan = requirePlan(hazardGraph)
        let hazardFailure = failure(
            graph: hazardGraph,
            plan: hazardPlan,
            pair: requirePair(hazardGraph),
            allocation: allocation(
                plan: hazardPlan, generation: 1, prefix: "hazard"
            )
        )
        let noSeedTargets = historyPlan.logicalTargets.map { target in
            Plan.LogicalTarget(
                identity: target.identity,
                extent: target.extent,
                format: target.format,
                addressMode: target.addressMode,
                isUnique: target.isUnique,
                lifetime: .init(
                    firstWriteNodeIndex: target.lifetime.firstWriteNodeIndex,
                    lastWriteNodeIndex: target.lifetime.lastWriteNodeIndex,
                    firstReadNodeIndex: target.lifetime.firstReadNodeIndex,
                    lastReadNodeIndex: target.lifetime.lastReadNodeIndex,
                    requiresHistorySeed: false
                ),
                initialClear: nil
            )
        }
        let noSeedPlan = Plan.testingPlan(
            layerID: layerID,
            input: input,
            output: output,
            inputRole: .layerSource,
            inputExtent: historyPlan.inputExtent,
            logicalTargets: noSeedTargets,
            commands: historyPlan.commands
        )
        let readBeforeWriteFailure = failure(
            graph: historyGraph,
            plan: noSeedPlan,
            pair: historyPair,
            allocation: allocation(
                plan: noSeedPlan, generation: 1, prefix: "no-seed"
            )
        )

        // A diagnostic format's 512-entry cap is not a playback limit.
        let largeNodeGraph = graph(targets: [], nodes: (0 ..< 513).map {
            material($0, ordinal: $0, target: output, reads: [input],
                compose: $0 < 512 ? .bool(true) : nil)
        })
        let largeNodePlan = requirePlan(largeNodeGraph)
        let largeNodePair = requirePair(largeNodeGraph)
        let largeNodeAllocation = allocation(plan: largeNodePlan, generation: 1, prefix: "large-node")
        let largeNodes = require(State.reduce(graph: largeNodeGraph, targetPlan: largeNodePlan,
            pairStep: largeNodePair, allocation: largeNodeAllocation,
            effectGeneration: 1, resetGeneration: 1))
        let largeNodesPrepared = require(State.reduce(
            preparedExecution: prepared(largeNodeGraph, largeNodePlan, largeNodePair),
            allocation: largeNodeAllocation, effectGeneration: 1, resetGeneration: 1))
        let largeTargetIdentities = (0 ..< 513).map {
            identity(.framebuffer, effect: key, name: "large-target-\($0)")
        }
        let largeTargetGraph = graph(targets: largeTargetIdentities.map { rawTarget($0) },
            nodes: largeTargetIdentities.enumerated().map {
                material($0.offset, ordinal: $0.offset, target: $0.element, reads: [input])
            } + [material(513, ordinal: 513, target: output, reads: [largeTargetIdentities.last!])])
        let largeTargetPlan = requirePlan(largeTargetGraph)
        let largeTargetPair = requirePair(largeTargetGraph)
        let largeTargetAllocation = allocation(plan: largeTargetPlan, generation: 1, prefix: "large-target")
        let largeTargets = require(State.reduce(graph: largeTargetGraph, targetPlan: largeTargetPlan,
            pairStep: largeTargetPair, allocation: largeTargetAllocation,
            effectGeneration: 1, resetGeneration: 1))
        let largeTargetsPrepared = require(State.reduce(
            preparedExecution: prepared(largeTargetGraph, largeTargetPlan, largeTargetPair),
            allocation: largeTargetAllocation, effectGeneration: 1, resetGeneration: 1))

        // The production prepared route must emit the same commands and
        // preserve dynamic rejection after moving topology work off the frame.
        let staticOrdinary = prepared(ordinaryGraph, ordinaryPlan, ordinaryPair)
        let staticSwap = prepared(swapGraph, swapPlan, swapPair)
        let staticHistory = prepared(historyGraph, historyPlan, historyPair)
        let preparedSwap1 = require(State.reduce(preparedExecution: staticSwap,
            allocation: swapAllocation, effectGeneration: 1, resetGeneration: 1))
        let preparedHistory1 = require(State.reduce(preparedExecution: staticHistory,
            allocation: historyAllocation, effectGeneration: 1, resetGeneration: 1))
        let missingAllocation = State.Allocation(generation: swapAllocation.generation,
            resources: swapAllocation.resources.filter { $0.key != q1 })
        var extraResources = swapAllocation.resources
        extraResources[identity(.framebuffer, effect: key, name: "extra")] = .init(
            token: .init(rawValue: "swap-extra"), descriptor: endpointDescriptor)
        let extraAllocation = State.Allocation(generation: swapAllocation.generation,
            resources: extraResources)
        let preparedChecks: [String: Bool] = [
            "ordinary": require(State.reduce(preparedExecution: staticOrdinary,
                allocation: ordinaryAllocation, effectGeneration: 1, resetGeneration: 1)) == ordinary,
            "swap-first": preparedSwap1 == swap1,
            "swap-next": require(State.reduce(preparedExecution: staticSwap,
                allocation: swapAllocation, effectGeneration: 1, resetGeneration: 1,
                previous: preparedSwap1.nextState)).transaction == swap2.transaction,
            "history-first": preparedHistory1 == history1,
            "history-rehydrated": require(State.reduce(preparedExecution: staticHistory,
                allocation: freshHistoryAllocation, effectGeneration: 1, resetGeneration: 1,
                previous: preparedHistory1.nextState, historyRehydration: rehydration)) == rehydrated,
            "history-reset": require(State.reduce(preparedExecution: staticHistory,
                allocation: historyAllocation, effectGeneration: 1, resetGeneration: 2,
                previous: preparedHistory1.nextState)) == historyReset,
            "resize": require(State.reduce(
                preparedExecution: prepared(resizeGraph, resizeLargePlan, resizePair),
                allocation: allocation(plan: resizeLargePlan, generation: 2, prefix: "resize-large"),
                effectGeneration: 1, resetGeneration: 1,
                previous: resizeSmall.nextState)).transaction == resizeLarge.transaction,
            "function-clear": require(State.reduce(
                preparedExecution: prepared(functionGraph, functionPlan, functionPair, targets: [q1]),
                allocation: functionAllocation, effectGeneration: 1, resetGeneration: 1,
                materialFunctionInvocations: [duplicateInvocation, duplicateInvocation])) == functionTransition,
            "node-lookup": staticSwap.nodesByIndex[2]?.kind == .swap,
            "binding-order": staticSwap.framebufferBindingsByNode[3]?.map(\.slot) == [0],
            "negative-material-ordinal": failureCode(State.prepareExecution(
                graph: graph(targets: [], nodes: [material(0, ordinal: -1, target: output, reads: [input])]),
                plan: ordinaryPlan, pairStep: ordinaryPair)) == "ordinalMismatch",
            "pair-mismatch": failureCode(State.prepareExecution(graph: singleComposeGraph,
                plan: singleComposePlan, pairStep: mismatchedPair)) == "pairStepMismatch",
            "missing-allocation": failureCode(State.reduce(preparedExecution: staticSwap,
                allocation: missingAllocation, effectGeneration: 1, resetGeneration: 1)) == "missingIdentity"
                && failure(graph: swapGraph, plan: swapPlan, pair: swapPair,
                    allocation: missingAllocation) == "missingIdentity",
            "extra-allocation": failureCode(State.reduce(preparedExecution: staticSwap,
                allocation: extraAllocation, effectGeneration: 1, resetGeneration: 1)) == "missingIdentity"
                && failure(graph: swapGraph, plan: swapPlan, pair: swapPair,
                    allocation: extraAllocation) == "missingIdentity",
            "alias": failureCode(State.reduce(preparedExecution: staticSwap,
                allocation: aliasAllocation, effectGeneration: 1, resetGeneration: 1)) == "physicalAlias",
            "hazard": failureCode(State.reduce(
                preparedExecution: prepared(hazardGraph, hazardPlan, requirePair(hazardGraph)),
                allocation: allocation(plan: hazardPlan, generation: 1, prefix: "hazard"),
                effectGeneration: 1, resetGeneration: 1)) == "readWriteHazard",
            "read-before-write": failureCode(State.reduce(
                preparedExecution: prepared(historyGraph, noSeedPlan, historyPair),
                allocation: allocation(plan: noSeedPlan, generation: 1, prefix: "no-seed"),
                effectGeneration: 1, resetGeneration: 1)) == "readBeforeWrite",
            "function-target-change": failureCode(State.reduce(
                preparedExecution: prepared(functionGraph, functionPlan, functionPair, targets: [q1]),
                allocation: functionAllocation, effectGeneration: 1, resetGeneration: 1,
                materialFunctionInvocations: [.init(name: "reset", targets: [q2])])) == "functionUnavailable",
            "fresh-token-reuse": failureCode(State.reduce(preparedExecution: staticHistory,
                allocation: reusedTokenAllocation, effectGeneration: 1, resetGeneration: 1,
                previous: preparedHistory1.nextState)) == "freshAllocationTokenReuse",
            "same-generation-resource-change": failureCode(State.reduce(preparedExecution: staticHistory,
                allocation: allocation(plan: historyPlan, generation: 1, prefix: "changed-history"),
                effectGeneration: 1, resetGeneration: 1,
                previous: preparedHistory1.nextState)) == "allocationGenerationMismatch",
            "history-rehydration-mismatch": failureCode(State.reduce(preparedExecution: staticHistory,
                allocation: freshHistoryAllocation, effectGeneration: 1, resetGeneration: 1,
                previous: preparedHistory1.nextState,
                historyRehydration: [oldSelected.token: wrongTarget])) == "historyRehydrationMismatch",
        ]

        let result: [String: Any] = [
            "preparedChecks": preparedChecks,
            "ordinaryKinds": kinds(ordinary.transaction.intents),
            "ordinaryMappings": [
                ordinary.transaction.mappingBefore.count,
                ordinary.transaction.mappingAfter.count,
            ],
            "ordinaryRepreparedGeneration": ordinaryReprepared.nextState
                .allocationGeneration ?? 0,
            "ordinaryRepreparedMappings": [
                ordinaryReprepared.transaction.mappingBefore.count,
                ordinaryReprepared.transaction.mappingAfter.count,
            ],
            "ordinaryRepreparedKinds": kinds(
                ordinaryReprepared.transaction.intents
            ),
            "ordinaryMaterialShapes": materialShapes(ordinary.transaction.intents),
            "prunedMaterialOrdinals": materialOrdinals(
                prunedOrdinal.transaction.intents
            ),
            "endpointAllocationFailure": failure(
                graph: ordinaryGraph,
                plan: ordinaryPlan,
                pair: ordinaryPair,
                allocation: endpointAllocation
            ),
            "singleComposeKinds": kinds(singleCompose.transaction.intents),
            "singleComposeMappingCount": singleCompose.nextState.logicalMapping.count,
            "multipleComposeKinds": kinds(multipleCompose.transaction.intents),
            "multipleComposeMappingCount": multipleCompose.nextState.logicalMapping.count,
            "pairMismatchFailure": failure(
                graph: singleComposeGraph,
                plan: singleComposePlan,
                pair: mismatchedPair,
                allocation: allocation(
                    plan: singleComposePlan, generation: 1, prefix: "bad-pair"
                )
            ),
            "swapKinds": kinds(swap1.transaction.intents),
            "swapAfter1": [
                token(swap1.transaction.mappingAfter, q1),
                token(swap1.transaction.mappingAfter, q2),
            ],
            "swapBefore2": [
                token(swap2.transaction.mappingBefore, q1),
                token(swap2.transaction.mappingBefore, q2),
            ],
            "swapAfter2": [
                token(swap2.transaction.mappingAfter, q1),
                token(swap2.transaction.mappingAfter, q2),
            ],
            "swapTransactionGenerations": [
                generation(swap1.transaction.mappingAfter, q1),
                generation(swap1.transaction.mappingAfter, q2),
            ],
            "swapCommittedGenerations": [
                generation(swap1.nextState.logicalMapping, q1),
                generation(swap1.nextState.logicalMapping, q2),
            ],
            "swapCommittedInitialized": swap1.nextState
                .initializedPhysicalTokens.count,
            "unchangedFBOsWithFreshGenerationFailure":
                unchangedFBOsWithFreshGenerationFailure,
            "copyKinds": kinds(copied.transaction.intents),
            "clearInitializations": [
                initializationTokens(clear1.transaction.intents),
                initializationTokens(clear2.transaction.intents),
                initializationTokens(clearReset.transaction.intents),
                initializationTokens(clearFresh.transaction.intents),
            ],
            "clearCommittedGeneration": generation(
                clear1.nextState.logicalMapping, q1
            ),
            "clearCommittedInitialized": clear1.nextState
                .initializedPhysicalTokens.count,
            "functionClearReasons": functionClearReasons(
                functionTransition.transaction.intents
            ),
            "functionClearGeneration": generation(
                functionTransition.transaction.mappingAfter, q1
            ),
            "functionClearMissingTargetFailure": missingFunctionTargetFailure,
            "resetMappingBefore": [
                token(resetSwap.transaction.mappingBefore, q1),
                token(resetSwap.transaction.mappingBefore, q2),
            ],
            "reparseMappingBefore": [
                token(reparsedSwap.transaction.mappingBefore, q1),
                token(reparsedSwap.transaction.mappingBefore, q2),
            ],
            "resizeExtents": resizeLargePlan.logicalTargets.map {
                "\($0.extent.width)x\($0.extent.height)"
            },
            "resizeMappingBefore": [
                token(resizeLarge.transaction.mappingBefore, q1),
                token(resizeLarge.transaction.mappingBefore, q2),
            ],
            "historyDirectCount": history1.nextState.historyLogicalIdentities.count,
            "historyClosureCount": history1.nextState.historyClosureIdentities.count,
            "historyCommittedGenerations": [
                generation(history1.nextState.logicalMapping, q1),
                generation(history1.nextState.logicalMapping, q2),
            ],
            "historyFirstInitializations": initializationTokens(
                history1.transaction.intents
            ),
            "rehydratedInitializations": initializationTokens(
                rehydrated.transaction.intents
            ),
            "rehydratedGenerationBefore": generation(
                rehydrated.transaction.mappingBefore, q1
            ),
            "rehydratedExpectedGeneration": oldSelected.contentGeneration,
            "missingRehydrationInitializations": initializationTokens(
                missingRehydration.transaction.intents
            ),
            "invalidRehydration": invalidRehydration,
            "outsideRehydration": outsideRehydration,
            "reusedTokenFailure": reusedTokenFailure,
            "pureCandidateEqual": rehydrated == rehydratedAgain,
            "previousStateUnchanged": history1.nextState.logicalMapping[q1]
                == oldSelected,
            "historyResetInitializations": initializationTokens(
                historyReset.transaction.intents
            ),
            "clampToRepeatHistoryResets": clampToRepeat.transaction.mappingBefore
                .values.allSatisfy { value in
                    value.contentGeneration == 0
                        && value.descriptor.addressMode == .repeatWrap
                },
            "repeatToClampHistoryResets": repeatToClamp.transaction.mappingBefore
                .values.allSatisfy { value in
                    value.contentGeneration == 0
                        && value.descriptor.addressMode == .clampToEdge
                },
            "clampToRepeatRehydrationFailure":
                clampToRepeatRehydrationFailure,
            "repeatToClampRehydrationFailure":
                repeatToClampRehydrationFailure,
            "aliasFailure": failure(
                graph: swapGraph,
                plan: swapPlan,
                pair: swapPair,
                allocation: aliasAllocation
            ),
            "hazardFailure": hazardFailure,
            "readBeforeWriteFailure": readBeforeWriteFailure,
            "largeNodeCount": largeNodes.transaction.intents.count,
            "largeNodeRawPreparedMatch": largeNodes == largeNodesPrepared,
            "largeTargetCount": largeTargetPlan.logicalTargets.count,
            "largeTargetRawPreparedMatch": largeTargets == largeTargetsPrepared,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
