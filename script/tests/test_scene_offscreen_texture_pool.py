#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetFormat.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Validation.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Identity.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable+Mapped.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneLayerFullFramePairPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneLayerGraphTargetPlan.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetLease.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetLease+Publication.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureResidency.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+SharedPair.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache+Batch.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureFramePreflight.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool+PersistentGraphTargets.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/ScenePersistentGraphTargetAllocator.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenResolutionPolicy.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let requiresExactInputExtent: Bool
    let inputRole: SceneAuthoredEffectInputRole

    var authoredShader: Int? {
        renderGraph.effects.first?.definitionPath.contains("/direct/") == true ? 1 : nil
    }
    var cursorRipple: SceneCursorRippleExecutionPlan? { nil }
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
}

struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
}

struct SceneFrameTextureResource {
    let publication: SceneTextureProviderPublication
    let resourceGeneration: UInt64

    var isCompleteGraphResource: Bool {
        resourceGeneration > 0
            && resourceGeneration == publication.contentGeneration
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct Fixture {
        let execution: SceneEffectStageExecutionPlan
        let framebufferIdentities: [Graph.TextureIdentity]
    }

    static func texture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func binding(
        _ texture: Graph.TextureIdentity,
        slot: Int
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: texture.name ?? "previous",
            texture: texture,
            conditions: nil
        )
    }

    static func node(
        index: Int,
        effect: Graph.EffectKey,
        ordinal: Int? = nil,
        target: Graph.TextureIdentity,
        reads: [(Int, Graph.TextureIdentity)],
        compose: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: ordinal ?? index,
            instancePassIndex: ordinal ?? index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "materials/\(index).json#0",
            target: target,
            bindings: reads.map { binding($0.1, slot: $0.0) },
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }

    static func command(
        index: Int,
        effect: Graph.EffectKey,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: effect,
            definitionPassIndex: index,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func fixture(
        effectIndex: Int,
        layerID: Int = 10,
        precise: Bool = false,
        framebufferNamePrefix: String = "",
        framebufferFormat: String = "rgba_backbuffer",
        uniqueFirstTarget: Bool = false,
        clearFirstTarget: Bool = false,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let targets: [Graph.RenderTarget]
        let nodes: [Graph.Node]
        let identities: [Graph.TextureIdentity]

        if precise {
            let full = texture(.framebuffer, layerID: layerID, effect: key, name: "shared")
            identities = [full]
            targets = [.init(
                texture: full,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )]
            nodes = [
                node(index: 0, effect: key, target: full, reads: []),
                node(
                    index: 1,
                    effect: key,
                    target: output,
                    reads: [(0, full), (1, input)]
                ),
            ]
        } else {
            let quarterA = texture(
                .framebuffer,
                layerID: layerID,
                effect: key,
                name: "\(framebufferNamePrefix)sharedA"
            )
            let quarterB = texture(
                .framebuffer,
                layerID: layerID,
                effect: key,
                name: "\(framebufferNamePrefix)sharedB"
            )
            identities = [quarterA, quarterB]
            let scaled = Graph.TargetExtent(kind: .scale, first: 4, second: nil)
            targets = [quarterA, quarterB].enumerated().map { index, texture in
                .init(
                    texture: texture,
                    extent: scaled,
                    format: framebufferFormat,
                    declaredUnique: uniqueFirstTarget && index == 0,
                    clear: clearFirstTarget && index == 0
                        ? .array([.number(0), .number(0), .number(0), .number(0)])
                        : nil,
                    uvs: nil,
                    conditions: nil
                )
            }
            nodes = [
                node(index: 0, effect: key, target: quarterA, reads: [(0, input)]),
                node(index: 1, effect: key, target: quarterB, reads: [(0, quarterA)]),
                node(index: 2, effect: key, target: quarterA, reads: [(0, quarterB)]),
                node(
                    index: 3,
                    effect: key,
                    target: output,
                    reads: [(0, quarterA), (2, input)]
                ),
            ]
        }

        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: precise
                    ? "effects/blurprecise/effect.json"
                    : "effects/blur/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return Fixture(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: nodes.count,
                logicalRenderTargetCount: targets.count,
                requiresExactInputExtent: precise,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: identities
        )
    }

    static func directFixture(
        effectIndex: Int,
        layerID: Int = 10,
        precise: Bool = false,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let nodes = [node(index: 0, effect: key, target: output, reads: [(0, input)])]
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/direct/effect.json",
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: 1,
                logicalRenderTargetCount: 0,
                requiresExactInputExtent: precise,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: []
        )
    }

    static func composeFixture(
        effectIndex: Int,
        composeCount: Int,
        input authoredInput: Graph.TextureIdentity? = nil
    ) -> Fixture {
        precondition(composeCount >= 0)
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = authoredInput ?? texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let nodes = (0...composeCount).map { index in
            node(
                index: index,
                effect: key,
                ordinal: index,
                target: output,
                reads: [(0, input)],
                compose: index < composeCount ? .bool(true) : nil
            )
        }
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/compose/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: [],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: nodes.count,
                logicalRenderTargetCount: 0,
                requiresExactInputExtent: false,
                inputRole: input.kind == .layerSource
                    ? .layerSource
                    : .priorEffectOutput
            ),
            framebufferIdentities: []
        )
    }

    static func historySwapFixture(
        effectIndex: Int,
        namePrefix: String = "",
        framebufferFormat: String = "rgba_backbuffer",
        extent: Graph.TargetExtent = .init(
            kind: .input,
            first: nil,
            second: nil
        )
    ) -> Fixture {
        let layerID = 10
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = texture(.layerSource, layerID: layerID)
        let output = texture(.effectOutput, layerID: layerID, effect: key)
        let history = texture(
            .framebuffer,
            layerID: layerID,
            effect: key,
            name: "\(namePrefix)history"
        )
        let scratch = texture(
            .framebuffer,
            layerID: layerID,
            effect: key,
            name: "\(namePrefix)scratch"
        )
        let targets = [
            Graph.RenderTarget(
                texture: history,
                extent: extent,
                format: framebufferFormat,
                declaredUnique: true,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
            Graph.RenderTarget(
                texture: scratch,
                extent: extent,
                format: framebufferFormat,
                declaredUnique: true,
                clear: nil,
                uvs: nil,
                conditions: nil
            ),
        ]
        let nodes = [
            node(index: 0, effect: key, target: scratch, reads: [(0, history)]),
            command(
                index: 1,
                effect: key,
                kind: .swap,
                source: history,
                target: scratch
            ),
            node(
                index: 2,
                effect: key,
                ordinal: 1,
                target: output,
                reads: [(0, history)]
            ),
        ]
        let graph = Graph(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/history-swap/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
        return .init(
            execution: .init(
                layerID: layerID,
                renderGraph: graph,
                materialNodeCount: 2,
                logicalRenderTargetCount: 2,
                requiresExactInputExtent: false,
                inputRole: .layerSource
            ),
            framebufferIdentities: [history, scratch]
        )
    }

    static func targetPlans(
        _ fixtures: [Fixture],
        width: Int,
        height: Int
    ) -> [SceneGraphRenderTargetPlan] {
        fixtures.enumerated().map { index, fixture in
            let result = SceneGraphRenderTargetPlan.make(
                graph: fixture.execution.renderGraph,
                inputRole: index == 0 ? .layerSource : .priorEffectOutput,
                inputWidth: width,
                inputHeight: height
            )
            switch result {
            case .success(let plan): return plan
            case .failure(let failure):
                fatalError("target plan fixture rejected: \(failure.rawValue)")
            }
        }
    }

    static func pairPlan(_ fixtures: [Fixture]) -> SceneLayerFullFramePairPlan {
        switch SceneLayerFullFramePairPlan.make(
            conditionPrunedGraphs: fixtures.map { $0.execution.renderGraph }
        ) {
        case .success(let plan): return plan
        case .failure(let failure):
            fatalError("pair plan fixture rejected: \(failure.rawValue)")
        }
    }

    static func admittedGraphs(_ fixtures: [Fixture]) -> [Graph] {
        fixtures.map { $0.execution.renderGraph }
    }

    static func clear(
        _ texture: MTLTexture,
        color: MTLClearColor,
        device: MTLDevice
    ) -> Bool {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return commandBuffer.status == .completed
    }

    static func pixel(_ texture: MTLTexture, device: MTLDevice) -> [UInt8]? {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let readback = device.makeBuffer(length: 4, options: .storageModeShared),
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return nil }
        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 1, height: 1, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return Array(UnsafeBufferPointer(
            start: readback.contents().assumingMemoryBound(to: UInt8.self),
            count: 4
        ))
    }

    static func physicalObjects(
        _ prepared: ScenePreparedPersistentGraphTargets
    ) -> Set<ObjectIdentifier> {
        Set(prepared.leases.flatMap {
            $0.texturesByToken.values.map(ObjectIdentifier.init)
        })
    }

    static func completedOrderedAllocation(
        allocator: ScenePersistentGraphTargetAllocator,
        plan: SceneLayerGraphTargetPlan,
        queue: MTLCommandQueue
    ) -> (
        prepared: ScenePreparedPersistentGraphTargets,
        commit: ScenePreparedPersistentGraphTargets.Commit,
        commandBuffer: MTLCommandBuffer
    )? {
        guard let commandBuffer = queue.makeCommandBuffer(),
              let prepared = allocator.prepare(
                  plan: plan,
                  orderingContext: .init(commandBuffer: commandBuffer)
              ), let commit = prepared.commitAndPin(
                  historyTokensByEffect: [:],
                  commandBuffer: commandBuffer
              ) else { return nil }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status != .notEnqueued else { return nil }
        return (prepared, commit, commandBuffer)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }

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
                sharesFullFramePairWhenHistoryFree: true,
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
                sharesFullFramePairWhenHistoryFree: true,
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
                      sharesFullFramePairWhenHistoryFree: true,
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
                      sharesFullFramePairWhenHistoryFree: true,
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
                sharesFullFramePairWhenHistoryFree: true,
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
                      sharesFullFramePairWhenHistoryFree: true,
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
                sharesFullFramePairWhenHistoryFree: true,
                orderingContext: sharedResolvedContext
            ), let sharedResolvedPlanB = sharedResolvedPool
            .framePlanForPersistentGraphTargets(
                admittedGraphs: admittedGraphs([staleB]),
                pairPlan: pairPlan([staleB]),
                requestedWidth: 8,
                requestedHeight: 8,
                sharesFullFramePairWhenHistoryFree: true,
                orderingContext: sharedResolvedContext
            ), sharedResolvedPool.preflightPersistentGraphTargets([
                sharedResolvedPlanA, sharedResolvedPlanB,
            ]) == .ready,
              sharedResolvedPool.residentAllocationCount == 0,
              let sharedResolvedPrepared = sharedResolvedPool
                .preparePersistentGraphTargets(framePlans: [
                    sharedResolvedPlanA, sharedResolvedPlanB,
                ]) else { fatalError("resolved shared pair fixture failed") }
        let batchPlansShareOneHistoryFreePair =
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
                sharesFullFramePairWhenHistoryFree: true,
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

        let result: [String: Any] = [
            "metalUnavailable": false,
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
            "r8PersistentAllocationTyped": r8PersistentAllocationTyped,
            "r8BudgetRejectsBeforeAllocation": r8BudgetRejectsBeforeAllocation,
            "r8HistoryCurrentCostExact": r8HistoryCurrentCostExact,
            "r8HistoryRetiredCostExact": r8HistoryRetiredCostExact,
            "r8HistoryReleaseRestoresCurrentCost":
                r8HistoryReleaseRestoresCurrentCost,
            "r8HistoryFinalReleaseClearsResidency":
                r8HistoryFinalReleaseClearsResidency,
            "batchPlansShareOneHistoryFreePair":
                batchPlansShareOneHistoryFreePair,
            "sharedResolvedPublicationsUseChainGeneration":
                sharedResolvedPublicationsUseChainGeneration,
            "batchPrepareOnlyPublishesSharedPair":
                batchPrepareOnlyPublishesSharedPair,
            "sharedPairBudgetRejectsBeforeAllocation":
                sharedPairBudgetRejectsBeforeAllocation,
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
            "composeEndpointAliases": composeEndpointAliases,
            "composePairBijection": composePairBijection,
            "composeTerminalFixed": composeTerminalFixed,
            "persistentGraphStable": persistentStable,
            "persistentPrepareNoMutation": persistentPrepareNoMutation,
            "persistentRepeatedCommitRejected": persistentRepeatedCommitRejected,
            "persistentSubmissionAndHistorySeparated":
                persistentSubmissionAndHistorySeparated,
            "persistentGraphAllocationCount": persistentCommittedAllocationCount,
            "persistentGraphTextureCount": persistentCommittedTextureCount,
            "persistentGraphBytes": persistentCommittedBytes,
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
            "historyOwnershipAlwaysUsesCopyOnWrite":
                historyOwnershipAlwaysUsesCopyOnWrite,
            "untrackedStaysCopyOnWrite": untrackedStaysCopyOnWrite,
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
            "inFlightHistoryPreservesPinnedSeed":
                inFlightHistoryPreservesPinnedSeed,
            "graphPlanNearBudgetBytes": directBudgetPlan.residentByteCost,
            "graphPlanSlotCount": directBudgetPlan.slots.count,
            "chainPhysicalObjectCount": directPhysicalObjects.count,
            "chainStageHandoffContinuous": directStageHandoffContinuous,
            "typedStandardExtent": [standardExtent.width, standardExtent.height],
            "typedPoolLimitExtent": [poolLimitExtent.width, poolLimitExtent.height],
            "typedExactStandardClampRejected": true,
            "defaultBudgetFailure": defaultBudgetFailure,
            "overBudgetZeroPhysicalAllocation": overBudgetZeroPhysicalAllocation,
            "uniqueNeverCrossEffectReused": uniqueNeverCrossEffectReused,
            "ordinaryCrossStageReuse": ordinaryCrossStageReuse,
            "differentFramebufferNamesNeverAlias": differentNamesNeverAlias,
            "ordinaryCacheIdentityOmitsEffect": ordinaryCacheIdentityOmitsEffect,
            "uniqueCacheIdentityIncludesEffect": uniqueCacheIdentityIncludesEffect,
            "historySwapPinnedFinalMapping": historySwapPinnedFinalMapping,
            "historyClosureContractAligned": historyClosureContractAligned,
            "historyMissingTokenRejected": historyMissingTokenRejected,
            "historyExtraTokenRejected": historyExtraTokenRejected,
            "historyCopyOnWriteIsolated": historyCopyOnWriteIsolated,
            "partialGPUWritePreservedCommittedPixels":
                partialGPUWritePreservedCommittedPixels,
            "gpuFailurePreservedCommittedHistory":
                gpuFailurePreservedCommittedHistory,
            "rehydrateGenerationChanged": rehydrateGenerationChanged,
            "resetRetainedOnlyDynamicHistory": resetRetainedOnlyDynamicHistory,
            "finalReleaseClearedResidency": finalReleaseClearedResidency,
            "fixedHistorySurvivesPairResize": fixedHistorySurvivesPairResize,
            "dynamicHistoryResizeStartsFresh": dynamicHistoryResizeStartsFresh,
            "changedHistorySemanticsDoNotSeed": changedHistorySemanticsDoNotSeed,
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
            "standardMaximumDimension": SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: 4096, includesAuthoredShader: false
            ),
            "authoredShaderMaximumDimension": SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: 4096, includesAuthoredShader: true
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneOffscreenTexturePoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-pool-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-offscreen-pool"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=False, capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_shared_fbo_graphs_share_pair_with_separate_residency(self) -> None:
        self.assertTrue(self.result["sharedFBOFramePairShared"])
        self.assertTrue(self.result["sharedFBOFramebuffersDistinct"])
        self.assertTrue(self.result["sharedFBOStateOwnsOnlyFBO"])
        self.assertTrue(self.result["sharedFBOBudgetExact"])
        self.assertTrue(self.result["sharedFBOPairRetainedAfterOneRelease"])
        self.assertTrue(self.result["sharedFBOPairRetainedAfterAllRelease"])
        self.assertTrue(self.result["overBudgetSharedFBORejected"])
        self.assertTrue(self.result["unsafeUnsubmittedSharedPairRejected"])
        self.assertTrue(self.result["differentQueueSharedPairRejected"])
        self.assertTrue(self.result["sharedPairOrderedReuseAndReleaseStable"])

    def test_resolved_batch_shares_history_free_full_frame_pair(self) -> None:
        self.assertTrue(self.result["batchPlansShareOneHistoryFreePair"])
        self.assertTrue(
            self.result["sharedResolvedPublicationsUseChainGeneration"]
        )
        self.assertTrue(self.result["batchPrepareOnlyPublishesSharedPair"])
        self.assertTrue(self.result["sharedPairBudgetRejectsBeforeAllocation"])

    def test_persistent_chain_uses_one_two_member_full_frame_pair(self) -> None:
        self.assertTrue(self.result["persistentPairSharedAcrossStages"])
        self.assertTrue(self.result["persistentPairHasTwoPhysicalObjects"])
        self.assertTrue(self.result["persistentStateProjectionExcludesPair"])
        self.assertTrue(self.result["persistentPairHandoffContinuous"])
        self.assertTrue(self.result["persistentPairBaseMapped"])
        self.assertTrue(self.result["persistentPairTerminalFixed"])
        self.assertTrue(self.result["persistentPairHitGenerationStable"])
        self.assertEqual(self.result["persistentPairResetAllocationCount"], 0)
        self.assertTrue(self.result["persistentPairResetGenerationAdvanced"])
        self.assertTrue(self.result["persistentPairResetTokensChanged"])

    def test_r8_persistent_targets_use_single_channel_budget_and_allocation(self) -> None:
        self.assertTrue(self.result["r8PersistentAllocationTyped"])
        self.assertTrue(self.result["r8BudgetRejectsBeforeAllocation"])

    def test_r8_history_retire_and_rehydrate_preserve_single_channel_budget(self) -> None:
        self.assertTrue(self.result["r8HistoryCurrentCostExact"])
        self.assertTrue(self.result["r8HistoryRetiredCostExact"])
        self.assertTrue(self.result["r8HistoryReleaseRestoresCurrentCost"])
        self.assertTrue(self.result["r8HistoryFinalReleaseClearsResidency"])

    def test_compose_parity_controls_only_endpoint_aliasing(self) -> None:
        self.assertEqual(self.result["composeEndpointAliases"], [False, True, False])
        self.assertTrue(self.result["composePairBijection"])
        self.assertTrue(self.result["composeTerminalFixed"])

    def test_whole_chain_reuses_two_slots_at_the_128mib_boundary(self) -> None:
        self.assertTrue(self.result["persistentGraphStable"])
        self.assertTrue(self.result["persistentPrepareNoMutation"])
        self.assertTrue(self.result["persistentRepeatedCommitRejected"])
        self.assertTrue(self.result["persistentSubmissionAndHistorySeparated"])
        self.assertTrue(self.result["chainStageHandoffContinuous"])
        self.assertEqual(self.result["graphPlanNearBudgetBytes"], 128_000_000)
        self.assertEqual(self.result["graphPlanSlotCount"], 2)
        self.assertEqual(self.result["chainPhysicalObjectCount"], 2)
        self.assertEqual(self.result["persistentGraphAllocationCount"], 1)
        self.assertEqual(self.result["persistentGraphTextureCount"], 2)
        self.assertEqual(self.result["persistentGraphBytes"], 128_000_000)

    def test_typed_persistent_extent_policy_defaults_to_standard_cap(self) -> None:
        self.assertEqual(self.result["typedStandardExtent"], [2_048, 1_536])
        self.assertEqual(self.result["typedPoolLimitExtent"], [4_000, 3_000])
        self.assertTrue(self.result["typedExactStandardClampRejected"])

    def test_two_inflight_generations_are_bounded_and_reusable(self) -> None:
        self.assertTrue(self.result["inFlightAllocationsAreDistinct"])
        self.assertTrue(self.result["inFlightCapacityFailsBeforeAllocation"])
        self.assertTrue(
            self.result[
                "requiredSharedResidencySurvivesTransientCapacityDeferral"
            ]
        )
        self.assertTrue(self.result["stableTwoSlotRingAvoidsTextureChurn"])
        self.assertTrue(self.result["resetInvalidatedSlotNeverReentersRing"])
        self.assertTrue(self.result["pinnedSecondSlotBudgetFailsBeforeAllocation"])
        self.assertTrue(self.result["pinnedOneSlotFramePreflightDefers"])
        self.assertTrue(self.result["releasedOneSlotFramePreflightReady"])
        self.assertTrue(self.result["reverseReleaseNeverReusesPinnedSlot"])
        self.assertTrue(
            self.result["idleRetiredLRUEvictableUnderOtherChainPressure"]
        )
        self.assertTrue(self.result["aggregateFrameHardOverBudget"])
        self.assertTrue(self.result["aggregateFrameReadyAtExactBudget"])
        self.assertTrue(
            self.result["mixedHistoryAndTransientRejectsImmediately"]
        )
        self.assertTrue(
            self.result["mixedHistoryRemainsHardAfterTransientRelease"]
        )
        self.assertTrue(self.result["mixedFrameReadyAfterHistoryRelease"])
        self.assertTrue(self.result["inFlightHistoryPreservesPinnedSeed"])

    def test_same_queue_reuse_is_bounded_and_fail_closed(self) -> None:
        self.assertTrue(
            self.result["sameQueueReusesOneTrackedPhysicalAllocation"]
        )
        self.assertTrue(
            self.result["sharedResetRetainsOneInvalidatedGeneration"]
        )
        self.assertTrue(self.result["forwardReleasePreservesNewerPin"])
        self.assertTrue(self.result["forwardFinalReleaseReturnsIdle"])
        self.assertTrue(
            self.result["submittedCurrentBufferRejectsSharedCommit"]
        )
        self.assertTrue(
            self.result["completedOrderingContextRejectedBeforeAllocation"]
        )
        self.assertTrue(self.result["differentSameQueueBufferRejectsCommit"])
        self.assertTrue(self.result["differentQueueBufferRejectsCommit"])
        self.assertTrue(self.result["reverseReleasePreservesOlderPin"])
        self.assertTrue(self.result["reverseFinalReleaseReturnsIdle"])
        self.assertTrue(self.result["thirdPinRejectedBeforeAllocation"])
        self.assertTrue(
            self.result["releasingOneSharedPinKeepsOtherGenerationResident"]
        )
        self.assertTrue(self.result["differentQueueStaysCopyOnWrite"])
        self.assertTrue(self.result["oldNotEnqueuedStaysCopyOnWrite"])
        self.assertTrue(self.result["historyOwnershipAlwaysUsesCopyOnWrite"])
        self.assertTrue(self.result["untrackedStaysCopyOnWrite"])

    def test_true_overbudget_rejects_before_any_texture_factory_call(self) -> None:
        self.assertEqual(self.result["defaultBudgetFailure"], "byteBudgetExceeded")
        self.assertTrue(self.result["overBudgetZeroPhysicalAllocation"])

    def test_unique_slots_are_not_reused_across_effects(self) -> None:
        self.assertTrue(self.result["uniqueNeverCrossEffectReused"])
        self.assertTrue(self.result["ordinaryCrossStageReuse"])
        self.assertTrue(self.result["differentFramebufferNamesNeverAlias"])
        self.assertTrue(self.result["ordinaryCacheIdentityOmitsEffect"])
        self.assertTrue(self.result["uniqueCacheIdentityIncludesEffect"])

    def test_dynamic_history_uses_copy_on_write_and_survives_gpu_failure(self) -> None:
        self.assertTrue(self.result["historySwapPinnedFinalMapping"])
        self.assertTrue(self.result["historyClosureContractAligned"])
        self.assertTrue(self.result["historyMissingTokenRejected"])
        self.assertTrue(self.result["historyExtraTokenRejected"])
        self.assertTrue(self.result["historyCopyOnWriteIsolated"])
        self.assertTrue(self.result["partialGPUWritePreservedCommittedPixels"])
        self.assertTrue(self.result["gpuFailurePreservedCommittedHistory"])
        self.assertTrue(self.result["rehydrateGenerationChanged"])
        self.assertTrue(self.result["resetRetainedOnlyDynamicHistory"])
        self.assertTrue(self.result["finalReleaseClearedResidency"])

    def test_history_resize_preserves_only_storage_compatible_semantics(self) -> None:
        self.assertTrue(self.result["fixedHistorySurvivesPairResize"])
        self.assertTrue(self.result["dynamicHistoryResizeStartsFresh"])
        self.assertTrue(self.result["changedHistorySemanticsDoNotSeed"])

    def test_stale_prepared_token_is_one_shot_and_zero_mutation(self) -> None:
        self.assertTrue(self.result["stalePreparedRejected"])

    def test_whole_frame_target_batch_is_atomic_and_revision_bound(self) -> None:
        self.assertTrue(self.result["batchPrepareHasNoVisibleMutation"])
        self.assertTrue(self.result["batchCommitPublishesAtomically"])
        self.assertTrue(self.result["secondCandidateFailureHasZeroMutation"])
        self.assertTrue(self.result["secondMaterializationFailureHasZeroMutation"])
        self.assertTrue(self.result["unrelatedReleaseRevalidatesWholeBatch"])
        self.assertTrue(self.result["resetInvalidatesWholePreparedBatch"])

    def test_residency_counters_fail_closed_instead_of_wrapping(self) -> None:
        source = (
            SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTextureAllocationCache.swift"
        ).read_text(encoding="utf-8")
        issuer = (
            SOURCE_ROOT / "RenderGraph/GraphTargets/SceneOffscreenTexturePool.swift"
        ).read_text(encoding="utf-8")
        self.assertNotIn("&+=", source)
        self.assertIn("addingReportingOverflow(1)", source)
        self.assertNotIn("preservedTokensByTexture", source + issuer)

    def test_authored_shader_resolution_policy_does_not_raise_standard_effect_extent(self) -> None:
        self.assertEqual(self.result["standardMaximumDimension"], 2048)
        self.assertEqual(self.result["authoredShaderMaximumDimension"], 4096)


if __name__ == "__main__":
    unittest.main()
