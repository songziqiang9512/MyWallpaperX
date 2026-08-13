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
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetTable+Mapped.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphNodeScheduler.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var cursorRipple: SceneCursorRippleExecutionPlan? { nil }
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias TargetPlan = SceneGraphRenderTargetPlan
    typealias TargetTable = SceneGraphRenderTargetTable

    static func identity(
        _ kind: Graph.TextureKind,
        layerID: Int = 10,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func logicalTarget(
        _ identity: Graph.TextureIdentity,
        width: Int,
        height: Int,
        format: TargetPlan.TextureFormat = .rgbaBackbuffer,
        isUnique: Bool = false,
        firstWrite: Int,
        lastWrite: Int,
        firstRead: Int?,
        lastRead: Int?,
        historySeed: Bool = false,
        initialClear: TargetPlan.ClearColor? = nil
    ) -> TargetPlan.LogicalTarget {
        var lifetime = TargetPlan.Lifetime(
            firstWriteNodeIndex: firstWrite,
            lastWriteNodeIndex: lastWrite,
            firstReadNodeIndex: firstRead,
            lastReadNodeIndex: lastRead
        )
        lifetime.requiresHistorySeed = historySeed
        return TargetPlan.LogicalTarget(
            identity: identity,
            extent: .init(width: width, height: height),
            format: format,
            isUnique: isUnique,
            lifetime: lifetime,
            initialClear: initialClear
        )
    }

    static func failure(
        _ result: Result<TargetTable, TargetTable.Failure>
    ) -> String {
        switch result {
        case .success:
            return "success"
        case .failure(let reason):
            return reason.rawValue
        }
    }

    static func scheduledBytes(
        device: MTLDevice,
        queue: MTLCommandQueue,
        commandKind: TargetPlan.CommandKind
    ) throws -> [UInt8] {
        let effect = Graph.EffectKey(
            layerID: 44,
            effectIndex: 0,
            descriptorID: "44#effect#0"
        )
        let input = identity(.layerSource, layerID: 44)
        let output = identity(.effectOutput, layerID: 44, effect: effect)
        let first = identity(.framebuffer, layerID: 44, effect: effect, name: "first")
        let second = identity(.framebuffer, layerID: 44, effect: effect, name: "second")
        let plan = TargetPlan.testingPlan(
            layerID: 44,
            input: input,
            output: output,
            inputExtent: .init(width: 2, height: 2),
            logicalTargets: [
                logicalTarget(
                    first, width: 2, height: 2,
                    firstWrite: 0, lastWrite: commandKind == .swap ? 1 : 0,
                    firstRead: 1, lastRead: 1
                ),
                logicalTarget(
                    second, width: 2, height: 2,
                    firstWrite: 1, lastWrite: 1, firstRead: 1, lastRead: 2,
                    historySeed: commandKind == .swap
                ),
            ],
            commands: [
                .init(nodeIndex: 1, kind: commandKind, source: first, target: second),
            ]
        )
        guard case .success(let table) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: 128
        ), let upload = device.makeBuffer(length: 16, options: .storageModeShared),
        let readback = device.makeBuffer(length: 16, options: .storageModeShared),
        let commandBuffer = queue.makeCommandBuffer(),
        table.encodeInitialTargetClear(commandBuffer: commandBuffer),
        let uploadEncoder = commandBuffer.makeBlitCommandEncoder() else {
            fatalError("scheduler setup failed")
        }
        let pattern = Array(0..<16).map { UInt8($0 * 7) }
        pattern.withUnsafeBytes { bytes in
            memcpy(upload.contents(), bytes.baseAddress!, bytes.count)
        }
        uploadEncoder.copy(
            from: upload,
            sourceOffset: 0,
            sourceBytesPerRow: 8,
            sourceBytesPerImage: 16,
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: table.inputTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        uploadEncoder.endEncoding()

        let graph = Graph(
            layerID: 44,
            effects: [
                .init(
                    key: effect,
                    definitionPath: "effects/test/effect.json",
                    input: input,
                    output: output,
                    nodeIndices: [0, 1, 2]
                ),
            ],
            renderTargets: [],
            nodes: [
                .init(
                    nodeIndex: 0, effect: effect, definitionPassIndex: 0,
                    materialOrdinal: 0, instancePassIndex: 0, kind: .material,
                    materialPath: "materials/first.json", materialPassID: "first#0",
                    target: first, bindings: [], commandSource: nil, commandTarget: nil,
                    compose: nil, conditions: nil
                ),
                .init(
                    nodeIndex: 1, effect: effect, definitionPassIndex: 1,
                    materialOrdinal: nil, instancePassIndex: nil,
                    kind: commandKind == .copy ? .copy : .swap,
                    materialPath: nil, materialPassID: nil, target: nil, bindings: [],
                    commandSource: first, commandTarget: second,
                    compose: nil, conditions: nil
                ),
                .init(
                    nodeIndex: 2, effect: effect, definitionPassIndex: 2,
                    materialOrdinal: 1, instancePassIndex: 1, kind: .material,
                    materialPath: "materials/second.json", materialPassID: "second#0",
                    target: output,
                    bindings: [
                        .init(
                            slot: 0, authoredName: "second", texture: second,
                            conditions: nil
                        ),
                    ],
                    commandSource: nil, commandTarget: nil,
                    compose: nil, conditions: nil
                ),
            ],
            finalOutput: output,
            blockers: []
        )
        let scheduled = SceneGraphNodeScheduler.encode(
            graph: graph,
            targets: table,
            commandBuffer: commandBuffer
        ) { node, textures in
            let sourceIdentity: Graph.TextureIdentity
            let targetIdentity: Graph.TextureIdentity
            switch node.materialOrdinal {
            case 0:
                sourceIdentity = input
                targetIdentity = first
            case 1:
                sourceIdentity = second
                targetIdentity = output
            default:
                return false
            }
            guard let source = textures.texture(for: sourceIdentity),
                  let target = textures.texture(for: targetIdentity),
                  let encoder = commandBuffer.makeBlitCommandEncoder() else {
                return false
            }
            encoder.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: 2, height: 2, depth: 1),
                to: target,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: .init(x: 0, y: 0, z: 0)
            )
            encoder.endEncoding()
            return true
        }
        guard case .success = scheduled,
              let readbackEncoder = commandBuffer.makeBlitCommandEncoder() else {
            fatalError("scheduler encoding failed")
        }
        readbackEncoder.copy(
            from: table.outputTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 8,
            destinationBytesPerImage: 16
        )
        readbackEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            fatalError("scheduler command buffer failed")
        }
        return Array(
            UnsafeBufferPointer(
                start: readback.contents().assumingMemoryBound(to: UInt8.self),
                count: 16
            )
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }

        let effect = Graph.EffectKey(
            layerID: 10,
            effectIndex: 2,
            descriptorID: "10#effect#2"
        )
        let input = identity(.layerSource)
        let output = identity(.effectOutput, effect: effect)
        let quarterA = identity(.framebuffer, effect: effect, name: "quarterA")
        let quarterB = identity(.framebuffer, effect: effect, name: "quarterB")
        let plan = TargetPlan.testingPlan(
            layerID: 10,
            input: input,
            output: output,
            inputExtent: .init(width: 9, height: 7),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 2, height: 1,
                    format: .rgba8888,
                    firstWrite: 0, lastWrite: 2, firstRead: 1, lastRead: 3
                ),
                logicalTarget(
                    quarterB, width: 2, height: 1,
                    format: .rgba8888,
                    firstWrite: 1, lastWrite: 1, firstRead: 2, lastRead: 2
                ),
            ]
        )
        let historyPlan = TargetPlan.testingPlan(
            layerID: 10,
            input: input,
            output: output,
            inputExtent: .init(width: 2, height: 2),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 2, height: 2,
                    firstWrite: 1, lastWrite: 1, firstRead: 0, lastRead: 1,
                    historySeed: true
                )
            ]
        )
        let authoredClearPlan = TargetPlan.testingPlan(
            layerID: 10,
            input: input,
            output: output,
            inputExtent: .init(width: 1, height: 1),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 1, height: 1,
                    format: .rgba8888,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil,
                    initialClear: .init(red: 0, green: 0, blue: 0, alpha: 0)
                )
            ]
        )
        let r8Plan = TargetPlan.testingPlan(
            layerID: 10,
            input: input,
            output: output,
            inputExtent: .init(width: 1, height: 1),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 1, height: 1,
                    format: .r8,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil,
                    initialClear: .init(red: 0, green: 0, blue: 0, alpha: 0)
                )
            ]
        )

        let exactBudget = 520
        guard case .success(let table) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: exactBudget
        ), case .success(let secondTable) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: exactBudget
        ), let quarterATexture = table.texture(for: quarterA),
        let quarterBTexture = table.texture(for: quarterB) else {
            fatalError("valid table allocation failed")
        }
        guard case .success(let historyTable) = TargetTable.make(
            plan: historyPlan,
            device: device,
            byteBudget: 64
        ), let historyTexture = historyTable.texture(for: quarterA),
        let historyQueue = device.makeCommandQueue(),
        let historyReadback = device.makeBuffer(length: 16, options: .storageModeShared),
        let historyCommandBuffer = historyQueue.makeCommandBuffer(),
        historyTable.encodeInitialTargetClear(commandBuffer: historyCommandBuffer),
        let historyReadbackEncoder = historyCommandBuffer.makeBlitCommandEncoder() else {
            fatalError("history initialization setup failed")
        }
        historyReadbackEncoder.copy(
            from: historyTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: historyReadback,
            destinationOffset: 0,
            destinationBytesPerRow: 8,
            destinationBytesPerImage: 16
        )
        historyReadbackEncoder.endEncoding()
        historyCommandBuffer.commit()
        historyCommandBuffer.waitUntilCompleted()
        let historyBytes = [UInt8](
            UnsafeBufferPointer(
                start: historyReadback.contents().assumingMemoryBound(to: UInt8.self),
                count: 16
            )
        )
        guard case .success(let authoredClearTable) = TargetTable.make(
            plan: authoredClearPlan,
            device: device,
            byteBudget: 12
        ), let authoredClearTexture = authoredClearTable.texture(for: quarterA),
        let authoredClearQueue = device.makeCommandQueue(),
        let initialReadback = device.makeBuffer(length: 4, options: .storageModeShared),
        let initialCommandBuffer = authoredClearQueue.makeCommandBuffer(),
        authoredClearTable.encodeInitialTargetClear(commandBuffer: initialCommandBuffer),
        let initialReadbackEncoder = initialCommandBuffer.makeBlitCommandEncoder() else {
            fatalError("authored clear initialization setup failed")
        }
        initialReadbackEncoder.copy(
            from: authoredClearTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 1, height: 1, depth: 1),
            to: initialReadback,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
        )
        initialReadbackEncoder.endEncoding()
        initialCommandBuffer.commit()
        initialCommandBuffer.waitUntilCompleted()
        let initialClearBytes = [UInt8](
            UnsafeBufferPointer(
                start: initialReadback.contents().assumingMemoryBound(to: UInt8.self),
                count: 4
            )
        )

        guard let secondReadback = device.makeBuffer(length: 4, options: .storageModeShared),
              let secondCommandBuffer = authoredClearQueue.makeCommandBuffer() else {
            fatalError("authored clear one-shot setup failed")
        }
        let overwriteDescriptor = MTLRenderPassDescriptor()
        overwriteDescriptor.colorAttachments[0].texture = authoredClearTexture
        overwriteDescriptor.colorAttachments[0].loadAction = .clear
        overwriteDescriptor.colorAttachments[0].storeAction = .store
        overwriteDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
        guard let overwriteEncoder = secondCommandBuffer.makeRenderCommandEncoder(
            descriptor: overwriteDescriptor
        ) else {
            fatalError("authored clear overwrite encoder failed")
        }
        overwriteEncoder.endEncoding()
        guard authoredClearTable.encodeInitialTargetClear(commandBuffer: secondCommandBuffer),
              let secondReadbackEncoder = secondCommandBuffer.makeBlitCommandEncoder() else {
            fatalError("authored clear repeated initialization failed")
        }
        secondReadbackEncoder.copy(
            from: authoredClearTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 1, height: 1, depth: 1),
            to: secondReadback,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
        )
        secondReadbackEncoder.endEncoding()
        secondCommandBuffer.commit()
        secondCommandBuffer.waitUntilCompleted()
        let repeatedClearBytes = [UInt8](
            UnsafeBufferPointer(
                start: secondReadback.contents().assumingMemoryBound(to: UInt8.self),
                count: 4
            )
        )

        guard case .success(let r8Table) = TargetTable.make(
            plan: r8Plan,
            device: device,
            byteBudget: 9
        ), let r8Texture = r8Table.texture(for: quarterA),
        let r8Queue = device.makeCommandQueue(),
        let r8Readback = device.makeBuffer(length: 256, options: .storageModeShared),
        let r8CommandBuffer = r8Queue.makeCommandBuffer(),
        r8Table.encodeInitialTargetClear(commandBuffer: r8CommandBuffer),
        let r8ReadbackEncoder = r8CommandBuffer.makeBlitCommandEncoder() else {
            fatalError("r8 allocation or initialization failed")
        }
        r8ReadbackEncoder.copy(
            from: r8Texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 1, height: 1, depth: 1),
            to: r8Readback,
            destinationOffset: 0,
            destinationBytesPerRow: 256,
            destinationBytesPerImage: 256
        )
        r8ReadbackEncoder.endEncoding()
        r8CommandBuffer.commit()
        r8CommandBuffer.waitUntilCompleted()
        let r8InitialByte = r8Readback.contents().assumingMemoryBound(to: UInt8.self).pointee

        let textures = [
            table.inputTexture,
            quarterATexture,
            quarterBTexture,
            table.outputTexture,
        ]
        let objectIDs = Set(textures.map(ObjectIdentifier.init))
        let secondObjectIDs = Set([
            secondTable.inputTexture,
            secondTable.texture(for: quarterA)!,
            secondTable.texture(for: quarterB)!,
            secondTable.outputTexture,
        ].map(ObjectIdentifier.init))
        let mappedTextures: [Graph.TextureIdentity: MTLTexture] = [
            input: table.inputTexture,
            quarterA: quarterATexture,
            quarterB: quarterBTexture,
            output: table.outputTexture,
        ]
        let mappedValid: Bool
        switch TargetTable.makeMapped(
            plan: plan, device: device, texturesByIdentity: mappedTextures
        ) {
        case .success(let mapped):
            mappedValid = mapped.inputTexture === table.inputTexture
                && mapped.outputTexture === table.outputTexture
                && mapped.residentTextureCount == 4
                && mapped.residentByteCost == exactBudget
        case .failure:
            mappedValid = false
        }
        var aliasedMappedTextures = mappedTextures
        aliasedMappedTextures[output] = table.inputTexture
        let controlledEndpointAliasValid: Bool
        switch TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: aliasedMappedTextures,
            fullFramePair: .init(
                first: table.inputTexture,
                second: table.outputTexture
            ),
            expectsInputOutputAlias: true
        ) {
        case .success(let mapped):
            controlledEndpointAliasValid = mapped.inputOutputAliased
                && mapped.inputTexture === mapped.outputTexture
                && mapped.fullFramePair.first === table.inputTexture
                && mapped.fullFramePair.second === table.outputTexture
                && mapped.residentTextureCount == 4
                && mapped.residentByteCost == exactBudget
        case .failure:
            controlledEndpointAliasValid = false
        }
        let mappedAliasFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: aliasedMappedTextures
        ))
        let unexpectedDistinctEndpointFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: mappedTextures,
            fullFramePair: .init(
                first: table.inputTexture,
                second: table.outputTexture
            ),
            expectsInputOutputAlias: true
        ))
        var pairAliasedFramebufferTextures = aliasedMappedTextures
        pairAliasedFramebufferTextures[quarterA] = table.outputTexture
        let pairAliasedFramebufferFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: pairAliasedFramebufferTextures,
            fullFramePair: .init(
                first: table.inputTexture,
                second: table.outputTexture
            ),
            expectsInputOutputAlias: true
        ))
        var siblingAliasedFramebufferTextures = aliasedMappedTextures
        siblingAliasedFramebufferTextures[quarterB] = quarterATexture
        let siblingAliasedFramebufferFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: siblingAliasedFramebufferTextures,
            fullFramePair: .init(
                first: table.inputTexture,
                second: table.outputTexture
            ),
            expectsInputOutputAlias: true
        ))
        var incompleteMappedTextures = mappedTextures
        incompleteMappedTextures.removeValue(forKey: quarterB)
        let mappedIncompleteFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: incompleteMappedTextures
        ))
        let invalidUsageDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: plan.inputExtent.width,
            height: plan.inputExtent.height,
            mipmapped: false
        )
        invalidUsageDescriptor.usage = [.shaderRead]
        invalidUsageDescriptor.storageMode = .private
        guard let invalidUsageTexture = device.makeTexture(
            descriptor: invalidUsageDescriptor
        ) else { fatalError("mapped invalid-usage fixture failed") }
        var invalidUsageMappedTextures = mappedTextures
        invalidUsageMappedTextures[output] = invalidUsageTexture
        let mappedUsageFailure = failure(TargetTable.makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: invalidUsageMappedTextures
        ))
        let otherEffect = Graph.EffectKey(
            layerID: 10,
            effectIndex: 3,
            descriptorID: "10#effect#3"
        )
        let unknown = identity(.framebuffer, effect: otherEffect, name: "quarterA")
        let copyPlan = TargetPlan.testingPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: .init(width: 2, height: 2),
            logicalTargets: [
                logicalTarget(
                    quarterA, width: 2, height: 2,
                    firstWrite: 0, lastWrite: 0, firstRead: 2, lastRead: 2
                ),
                logicalTarget(
                    quarterB, width: 2, height: 2,
                    firstWrite: 1, lastWrite: 2, firstRead: nil, lastRead: nil
                ),
            ],
            commands: [
                .init(nodeIndex: 2, kind: .copy, source: quarterA, target: quarterB),
            ]
        )
        guard case .success(let copyTable) = TargetTable.make(
            plan: copyPlan,
            device: device,
            byteBudget: 128
        ), var copyRuntime = copyTable.makeCommandRuntime(),
        let queue = device.makeCommandQueue(),
        let upload = device.makeBuffer(length: 16, options: .storageModeShared),
        let readback = device.makeBuffer(length: 16, options: .storageModeShared),
        let copyCommandBuffer = queue.makeCommandBuffer(),
        let uploadEncoder = copyCommandBuffer.makeBlitCommandEncoder(),
        let copySource = copyRuntime.texture(for: quarterA),
        let copyTarget = copyRuntime.texture(for: quarterB) else {
            fatalError("command runtime setup failed")
        }
        let pattern = Array(0..<16).map(UInt8.init)
        pattern.withUnsafeBytes { bytes in
            memcpy(upload.contents(), bytes.baseAddress!, bytes.count)
        }
        uploadEncoder.copy(
            from: upload,
            sourceOffset: 0,
            sourceBytesPerRow: 8,
            sourceBytesPerImage: 16,
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: copySource,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        uploadEncoder.endEncoding()
        let wrongOrderFailure: String
        switch copyRuntime.encodeCommand(at: 99, commandBuffer: copyCommandBuffer) {
        case .success:
            wrongOrderFailure = "success"
        case .failure(let reason):
            wrongOrderFailure = reason.rawValue
        }
        let copyResult = copyRuntime.encodeCommand(
            at: 2,
            commandBuffer: copyCommandBuffer
        )
        guard case .success = copyResult,
              let readbackEncoder = copyCommandBuffer.makeBlitCommandEncoder() else {
            fatalError("copy command failed")
        }
        readbackEncoder.copy(
            from: copyTarget,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 2, height: 2, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 8,
            destinationBytesPerImage: 16
        )
        readbackEncoder.endEncoding()
        copyCommandBuffer.commit()
        copyCommandBuffer.waitUntilCompleted()
        let copiedBytes = Array(
            UnsafeBufferPointer(
                start: readback.contents().assumingMemoryBound(to: UInt8.self),
                count: 16
            )
        )

        let swapPlan = TargetPlan.testingPlan(
            layerID: copyPlan.layerID,
            input: copyPlan.input,
            output: copyPlan.output,
            inputExtent: copyPlan.inputExtent,
            logicalTargets: copyPlan.logicalTargets,
            commands: [
                .init(nodeIndex: 3, kind: .swap, source: quarterA, target: quarterB),
            ]
        )
        guard case .success(let swapTable) = TargetTable.make(
            plan: swapPlan,
            device: device,
            byteBudget: 128
        ), var swapRuntime = swapTable.makeCommandRuntime(),
        let swapSourceBefore = swapRuntime.texture(for: quarterA),
        let swapTargetBefore = swapRuntime.texture(for: quarterB),
        let swapCommandBuffer = queue.makeCommandBuffer() else {
            fatalError("swap command setup failed")
        }
        let swapResult = swapRuntime.encodeCommand(
            at: 3,
            commandBuffer: swapCommandBuffer
        )
        guard case .success = swapResult else {
            fatalError("swap command failed")
        }
        let swapBindingsExchanged =
            swapRuntime.texture(for: quarterA) === swapTargetBefore
                && swapRuntime.texture(for: quarterB) === swapSourceBefore

        let incompatiblePlan = TargetPlan.testingPlan(
            layerID: copyPlan.layerID,
            input: copyPlan.input,
            output: copyPlan.output,
            inputExtent: copyPlan.inputExtent,
            logicalTargets: [
                copyPlan.logicalTargets[0],
                logicalTarget(
                    quarterB, width: 2, height: 2,
                    format: .rgba8888,
                    firstWrite: 1, lastWrite: 2, firstRead: nil, lastRead: nil
                ),
            ],
            commands: copyPlan.commands
        )
        guard case .success(let incompatibleTable) = TargetTable.make(
            plan: incompatiblePlan,
            device: device,
            byteBudget: 128
        ), var incompatibleRuntime = incompatibleTable.makeCommandRuntime(),
        let incompatibleCommandBuffer = queue.makeCommandBuffer() else {
            fatalError("incompatible command setup failed")
        }
        let incompatibleFailure: String
        switch incompatibleRuntime.encodeCommand(
            at: 2,
            commandBuffer: incompatibleCommandBuffer
        ) {
        case .success:
            incompatibleFailure = "success"
        case .failure(let reason):
            incompatibleFailure = reason.rawValue
        }
        let scheduledCopyBytes = try scheduledBytes(
            device: device,
            queue: queue,
            commandKind: .copy
        )
        let scheduledSwapBytes = try scheduledBytes(
            device: device,
            queue: queue,
            commandKind: .swap
        )
        let scheduledPattern = Array(0..<16).map { UInt8($0 * 7) }

        let duplicatePlan = TargetPlan.testingPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                plan.logicalTargets[0],
                plan.logicalTargets[0],
            ]
        )
        let overflowPlan = TargetPlan.testingPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: .init(width: Int.max, height: 2),
            logicalTargets: []
        )
        let wrongEffect = Graph.EffectKey(
            layerID: 11,
            effectIndex: 2,
            descriptorID: "11#effect#2"
        )
        let invalidIdentityPlan = TargetPlan.testingPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                logicalTarget(
                    identity(.framebuffer, effect: wrongEffect, name: "foreign"),
                    width: 2, height: 1,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil
                ),
            ]
        )
        let whitespaceNamePlan = TargetPlan.testingPlan(
            layerID: plan.layerID,
            input: input,
            output: output,
            inputExtent: plan.inputExtent,
            logicalTargets: [
                logicalTarget(
                    identity(.framebuffer, effect: effect, name: "  \t"),
                    width: 2, height: 1,
                    firstWrite: 0, lastWrite: 0, firstRead: nil, lastRead: nil
                ),
            ]
        )

        let result: [String: Any] = [
            "metalUnavailable": false,
            "residentCount": table.residentTextureCount,
            "residentBytes": table.residentByteCost,
            "inputSize": [table.inputTexture.width, table.inputTexture.height],
            "outputSize": [table.outputTexture.width, table.outputTexture.height],
            "quarterASize": [quarterATexture.width, quarterATexture.height],
            "quarterBSize": [quarterBTexture.width, quarterBTexture.height],
            "identityMappingComplete": table.texture(for: input) === table.inputTexture
                && table.texture(for: output) === table.outputTexture,
            "unknownIdentityIsNil": table.texture(for: unknown) == nil,
            "allResourcesDistinct": objectIDs.count == textures.count,
            "separateAllocationsDistinct": objectIDs.isDisjoint(with: secondObjectIDs),
            "mappedValid": mappedValid,
            "controlledEndpointAliasValid": controlledEndpointAliasValid,
            "mappedAliasFailure": mappedAliasFailure,
            "unexpectedDistinctEndpointFailure": unexpectedDistinctEndpointFailure,
            "pairAliasedFramebufferFailure": pairAliasedFramebufferFailure,
            "siblingAliasedFramebufferFailure": siblingAliasedFramebufferFailure,
            "mappedIncompleteFailure": mappedIncompleteFailure,
            "mappedUsageFailure": mappedUsageFailure,
            "inputOutputFormat": table.inputTexture.pixelFormat == .bgra8Unorm
                && table.outputTexture.pixelFormat == .bgra8Unorm,
            "framebufferFormats": quarterATexture.pixelFormat == .rgba8Unorm
                && quarterBTexture.pixelFormat == .rgba8Unorm,
            "historyClearBytesZero": historyBytes.allSatisfy { $0 == 0 },
            "historyTargetPersistent":
                historyTable.plan.logicalTargets[0].lifetime.requiresHistorySeed,
            "authoredClearBytesZero": initialClearBytes.allSatisfy { $0 == 0 },
            "authoredClearOneShot": repeatedClearBytes == [255, 0, 0, 255],
            "r8ResidentBytes": r8Table.residentByteCost,
            "r8ResidentCount": r8Table.residentTextureCount,
            "r8PixelFormat": r8Texture.pixelFormat == .r8Unorm,
            "r8InitialClearZero": r8CommandBuffer.status == .completed
                && r8CommandBuffer.error == nil && r8InitialByte == 0,
            "r8BudgetFailure": failure(TargetTable.make(
                plan: r8Plan, device: device, byteBudget: 8
            )),
            "textureContract": textures.allSatisfy {
                $0.storageMode == .private
                    && $0.usage.contains(.renderTarget)
                    && $0.usage.contains(.shaderRead)
            },
            "copyBytesMatch": copiedBytes == pattern,
            "copyRuntimeComplete": copyRuntime.isComplete
                && copyRuntime.remainingCommandCount == 0,
            "wrongOrderFailure": wrongOrderFailure,
            "swapBindingsExchanged": swapBindingsExchanged,
            "swapRuntimeComplete": swapRuntime.isComplete,
            "incompatibleCommandFailure": incompatibleFailure,
            "scheduledCopyMatches": scheduledCopyBytes == scheduledPattern,
            "scheduledSwapMatches": scheduledSwapBytes == scheduledPattern,
            "budgetFailure": failure(TargetTable.make(
                plan: plan, device: device, byteBudget: exactBudget - 1
            )),
            "negativeBudgetFailure": failure(TargetTable.make(
                plan: plan, device: device, byteBudget: -1
            )),
            "duplicateFailure": failure(TargetTable.make(
                plan: duplicatePlan, device: device, byteBudget: exactBudget
            )),
            "overflowFailure": failure(TargetTable.make(
                plan: overflowPlan, device: device, byteBudget: Int.max
            )),
            "invalidIdentityFailure": failure(TargetTable.make(
                plan: invalidIdentityPlan, device: device, byteBudget: exactBudget
            )),
            "whitespaceNameFailure": failure(TargetTable.make(
                plan: whitespaceNamePlan, device: device, byteBudget: exactBudget
            )),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphRenderTargetTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-rt-table-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-rt-table"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-D",
                "SCENE_GRAPH_TESTING",
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
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_allocates_every_logical_identity_without_aliasing(self) -> None:
        self.assertEqual(self.result["residentCount"], 4)
        self.assertTrue(self.result["identityMappingComplete"])
        self.assertTrue(self.result["unknownIdentityIsNil"])
        self.assertTrue(self.result["allResourcesDistinct"])
        self.assertTrue(self.result["separateAllocationsDistinct"])

    def test_preserves_input_output_and_scaled_target_extents(self) -> None:
        self.assertEqual(self.result["inputSize"], [9, 7])
        self.assertEqual(self.result["outputSize"], [9, 7])
        self.assertEqual(self.result["quarterASize"], [2, 1])
        self.assertEqual(self.result["quarterBSize"], [2, 1])

    def test_mapped_entry_revalidates_complete_physical_contract(self) -> None:
        self.assertTrue(self.result["mappedValid"])
        self.assertTrue(self.result["controlledEndpointAliasValid"])
        self.assertEqual(self.result["mappedAliasFailure"], "mappedTextureAliased")
        self.assertEqual(
            self.result["unexpectedDistinctEndpointFailure"],
            "mappedTextureAliased",
        )
        self.assertEqual(
            self.result["pairAliasedFramebufferFailure"],
            "mappedTextureInvalid",
        )
        self.assertEqual(
            self.result["siblingAliasedFramebufferFailure"],
            "mappedTextureAliased",
        )
        self.assertEqual(self.result["mappedIncompleteFailure"], "mappedTextureInvalid")
        self.assertEqual(self.result["mappedUsageFailure"], "mappedTextureInvalid")

    def test_reports_exact_resident_cost_and_texture_contract(self) -> None:
        self.assertEqual(self.result["residentBytes"], 520)
        self.assertTrue(self.result["inputOutputFormat"])
        self.assertTrue(self.result["framebufferFormats"])
        self.assertTrue(self.result["textureContract"])
        self.assertTrue(self.result["historyClearBytesZero"])
        self.assertTrue(self.result["historyTargetPersistent"])
        self.assertTrue(self.result["authoredClearBytesZero"])
        self.assertTrue(self.result["authoredClearOneShot"])

    def test_r8_uses_single_channel_storage_and_exact_logical_budget(self) -> None:
        self.assertEqual(self.result["r8ResidentBytes"], 9)
        self.assertEqual(self.result["r8ResidentCount"], 3)
        self.assertTrue(self.result["r8PixelFormat"])
        self.assertTrue(self.result["r8InitialClearZero"])
        self.assertEqual(self.result["r8BudgetFailure"], "byteBudgetExceeded")

    def test_copy_blits_bytes_and_swap_exchanges_logical_bindings(self) -> None:
        self.assertTrue(self.result["copyBytesMatch"])
        self.assertTrue(self.result["copyRuntimeComplete"])
        self.assertEqual(self.result["wrongOrderFailure"], "commandOrderMismatch")
        self.assertTrue(self.result["swapBindingsExchanged"])
        self.assertTrue(self.result["swapRuntimeComplete"])
        self.assertEqual(
            self.result["incompatibleCommandFailure"],
            "incompatibleTextures",
        )

    def test_scheduler_interleaves_materials_with_copy_and_swap_on_gpu(self) -> None:
        self.assertTrue(self.result["scheduledCopyMatches"])
        self.assertTrue(self.result["scheduledSwapMatches"])

    def test_refuses_the_whole_allocation_before_exceeding_budget(self) -> None:
        self.assertEqual(self.result["budgetFailure"], "byteBudgetExceeded")
        self.assertEqual(self.result["negativeBudgetFailure"], "invalidByteBudget")

    def test_rejects_invalid_or_overflowing_resource_sets(self) -> None:
        self.assertEqual(self.result["duplicateFailure"], "invalidPlan")
        self.assertEqual(self.result["overflowFailure"], "byteCostOverflow")
        self.assertEqual(self.result["invalidIdentityFailure"], "invalidPlan")
        self.assertEqual(self.result["whitespaceNameFailure"], "invalidPlan")


if __name__ == "__main__":
    unittest.main()
