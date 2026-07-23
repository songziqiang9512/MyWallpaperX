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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SOURCE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SOURCE_ROOT / "Rendering/SceneMainPassEncoder.swift",
    SOURCE_ROOT / "RenderGraph/SceneOffscreenTexturePool.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurPipeline.swift",
    SOURCE_ROOT / "Effects/SceneStandardBlurRenderer.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastPipeline.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastRenderer.swift",
    SOURCE_ROOT / "Effects/SceneOpacityPipeline.swift",
    SOURCE_ROOT / "Effects/SceneOpacityRenderer.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShadowRenderer.swift",
    SOURCE_ROOT / "Rendering/SceneImageBlendPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGradientColorPipeline.swift",
    SOURCE_ROOT / "Effects/SceneBloomPipeline.swift",
    SOURCE_ROOT / "Effects/SceneWaterRipplePipeline.swift",
    SOURCE_ROOT / "Effects/ScenePerspectiveOpacityPipeline.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneFoliageSwayRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGradientColorRuntimePlan.swift",
    SOURCE_ROOT / "Rendering/SceneTextureMappedUVScale.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneInlineEffectRuntime.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeSupport.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneOffscreenEffectRenderer.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainRenderer.swift",
    SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift",
    SOURCE_ROOT / "Runtime/SceneGPUCompletionTelemetry.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import Metal
import simd

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [Int?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]

            init(
                texturePaths: [String],
                textureSlots: [String?],
                userTextureInputs: [Int?] = [],
                combos: [String: Int],
                constantShaderValues: [String: SceneDocument.ShaderValue]
            ) {
                self.texturePaths = texturePaths
                self.textureSlots = textureSlots
                self.userTextureInputs = userTextureInputs
                self.combos = combos
                self.constantShaderValues = constantShaderValues
            }
        }

        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let contentKind: String
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        let effects: [EffectDescriptor]
    }
}

struct SceneTexContainer {
    struct SpriteFrame {
        let imageIndex: Int
        let duration: Float
        let origin: SIMD2<Float>
        let xAxis: SIMD2<Float>
        let yAxis: SIMD2<Float>
    }
    let spriteFrames: [SpriteFrame]
}

struct SceneTexContainerReader {
    func read(data: Data) throws -> SceneTexContainer {
        SceneTexContainer(spriteFrames: [])
    }
}

struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

struct SceneOpacityExecutionPlan: Equatable, Sendable {
    let staticOrFallbackAlpha: Float
    let liveEffectIndex: Int?

    init(staticOrFallbackAlpha: Float, liveEffectIndex: Int? = nil) {
        self.staticOrFallbackAlpha = staticOrFallbackAlpha
        self.liveEffectIndex = liveEffectIndex
    }

    func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float {
        liveEffectIndex.flatMap { snapshot.opacitiesByEffectIndex[$0] }
            ?? staticOrFallbackAlpha
    }
}

struct SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
    }

    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
    }

    var gaussianBlur: SceneGaussianBlurPlan? {
        guard case .preciseGaussian(let plan) = backend else { return nil }
        return plan
    }

    var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
        return plan
    }

    var localContrast: SceneLocalContrastPlan? {
        guard case .localContrast(let plan) = backend else { return nil }
        return plan
    }

    var opacity: SceneOpacityExecutionPlan? {
        guard case .opacity(let plan) = backend else { return nil }
        return plan
    }

    var workshopShadow: SceneWorkshopShadowExecutionPlan? {
        guard case .workshopShadow(let plan) = backend else { return nil }
        return plan
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend { return true }
        return false
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        guard let localContrast else { return nil }
        let effectIndex = renderGraph.effects.first?.key.effectIndex ?? -1
        return snapshot.strengthsByEffectIndex[effectIndex]
            ?? localContrast.staticOrFallbackStrength
    }

    func opacityAlpha(in snapshot: SceneDynamicSnapshot) -> Float? {
        opacity?.resolvedAlpha(in: snapshot)
    }
}

struct SceneAuthoredEffectExecutionChain {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let stages: [SceneAuthoredEffectExecutionPlan]

    var singleStage: SceneAuthoredEffectExecutionPlan? {
        stages.count == 1 ? stages[0] : nil
    }
}

struct SceneDynamicSnapshot {
    let strengthsByEffectIndex: [Int: Float]
    let opacitiesByEffectIndex: [Int: Float]

    static func empty(frameIndex: UInt64, generation: UInt64 = 0) -> Self {
        Self(strengthsByEffectIndex: [:], opacitiesByEffectIndex: [:])
    }
}

struct SceneStandardBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let renderTargetScale: Int
}

struct SceneLocalContrastPlan {
    let firstQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let secondQuarterTarget: SceneAuthoredEffectRenderPlan.TextureIdentity
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticOrFallbackStrength: Float
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func graphTexture(
        _ kind: Graph.TextureKind,
        layerID: Int,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func preciseBlurGraph(layerID: Int = 10) -> Graph {
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let full = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "full"
        )
        let nodes = [
            Graph.Node(
                nodeIndex: 0,
                effect: effectKey,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: "materials/blur_precise_x.json",
                materialPassID: "materials/blur_precise_x.json#0",
                target: full,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            ),
            Graph.Node(
                nodeIndex: 1,
                effect: effectKey,
                definitionPassIndex: 1,
                materialOrdinal: 1,
                instancePassIndex: 1,
                kind: .material,
                materialPath: "materials/blur_precise_y.json",
                materialPassID: "materials/blur_precise_y.json#0",
                target: output,
                bindings: [
                    .init(slot: 0, authoredName: "full", texture: full, conditions: nil),
                    .init(slot: 1, authoredName: "previous", texture: input, conditions: nil),
                ],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            ),
        ]
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blurprecise/effect.json",
            input: input,
            output: output,
            nodeIndices: [0, 1]
        )
        return Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [
                .init(
                    texture: full,
                    extent: .init(kind: .input, first: nil, second: nil),
                    format: "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                ),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func standardBlurGraph(
        layerID: Int = 530,
        effectIndex: Int = 0,
        input priorOutput: Graph.TextureIdentity? = nil
    ) -> Graph {
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let input = priorOutput ?? graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let quarterA = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_QuarterCompoBuffer1"
        )
        let quarterB = graphTexture(
            .framebuffer,
            layerID: layerID,
            effect: effectKey,
            name: "_rt_QuarterCompoBuffer2"
        )
        let materialPaths = [
            "materials/effects/blur_downsample4.json",
            "materials/effects/blur_gaussian_x.json",
            "materials/effects/blur_gaussian_y.json",
            "materials/effects/blur_combine.json",
        ]
        let targets = [quarterA, quarterB, quarterA, output]
        let bindings: [[Graph.Binding]] = [
            [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)],
            [.init(slot: 0, authoredName: quarterA.name, texture: quarterA, conditions: nil)],
            [.init(slot: 0, authoredName: quarterB.name, texture: quarterB, conditions: nil)],
            [
                .init(slot: 0, authoredName: quarterA.name, texture: quarterA, conditions: nil),
                .init(slot: 2, authoredName: "previous", texture: input, conditions: nil),
            ],
        ]
        let nodes = materialPaths.indices.map { index in
            Graph.Node(
                nodeIndex: (effectIndex * materialPaths.count) + index,
                effect: effectKey,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: materialPaths[index],
                materialPassID: "\(materialPaths[index])#0",
                target: targets[index],
                bindings: bindings[index],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/blur/effect.json",
            input: input,
            output: output,
            nodeIndices: materialPaths.indices.map { (effectIndex * materialPaths.count) + $0 }
        )
        return Graph(
            layerID: layerID,
            effects: [effect],
            // Declaration order is intentionally not execution order.
            renderTargets: [quarterB, quarterA].map { texture in
                .init(
                    texture: texture,
                    extent: .init(kind: .scale, first: 4, second: nil),
                    format: "rgba_backbuffer",
                    declaredUnique: false,
                    clear: nil,
                    uvs: nil,
                    conditions: nil
                )
            },
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func authoredPreciseBlurPlan() -> SceneAuthoredEffectExecutionPlan {
        let graph = preciseBlurGraph()
        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .preciseGaussian(SceneGaussianBlurPlan(
                horizontalStep: 1,
                verticalStep: 1,
                sampleResolutionScale: 1,
                isPrecise: true
            )),
            materialNodeCount: 2,
            logicalRenderTargetCount: 1
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device),
              let imageBlendPipeline = SceneImageBlendPipeline(device: device),
              let compositor = SceneImageLayerCompositor(device: device),
              let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillQuadrants(source)

        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 1)
        )
        guard let baseEncoder = mainPass.encoder() else { throw HarnessError.encoderUnavailable }
        pipeline.bind(encoder: baseEncoder)
        pipeline.drawLayer(
            texture: source,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
            uniforms: .neutral(),
            encoder: baseEncoder
        )

        let layer = SceneRenderDescriptor.Layer(
            contentKind: "composition",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let pool = SceneOffscreenTexturePool(device: device)
        let refusedWithoutPool = mainPass.withReadableTarget { readableTarget, _ in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: nil,
                    offscreenSize: nil,
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? true
        let drew = mainPass.withReadableTarget { readableTarget, _ in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: SceneTextureUVTransform(
                        origin: .zero,
                        xAxis: SIMD2(0.5, 0),
                        yAxis: SIMD2(0, 0.5)
                    ),
                    mvp: SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: pool,
                    offscreenSize: CGSize(width: 4, height: 4),
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? false
        let telemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
        telemetry.record(layerID: 701, encoded: drew, on: commandBuffer)
        telemetry.record(layerID: 702, encoded: false, on: commandBuffer)
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let noDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: nil, alpha: 1
        )
        let normalDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 0, alpha: 1
        )
        let darkenDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 1
        )
        let darkenHalfAlpha = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 0.5
        )
        let solidTint = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "solid"
        )
        let imageTint = try layerTintPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            contentKind: "image"
        )
        let coarseBlur = blurPlan(path: "effects/blur/effect.json", scale: 0.6)
        let preciseBlur = blurPlan(path: "effects/blurprecise/effect.json", scale: 0.45)
        let blockedPreciseBlur = blurPlan(
            path: "effects/blurprecise/effect.json",
            scale: 0.45,
            blocksLegacyGaussianBlur: true
        )
        let authoredExtentMismatchRefused = try authoredExtentMismatchIsRefused(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredPreciseImpulse = try authoredPreciseBlurImpulseEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredStandardCheckerboard = try authoredStandardBlurCheckerboardEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredTwoStageChain = try authoredTwoStageChainEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredOpacityLivePixels = try authoredOpacityLivePixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredFailedChain = try authoredFailedChainEvidence(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        let authoredStandardBlurOverridesLegacy = standardBlurOverridesLegacy()
        let standardBlurAlphaAwareDownsample = try alphaAwareDownsamplePixel(
            device: device,
            queue: queue
        )
        let foliage = foliageInputs(mode: 0)
        let unsupportedFoliage = foliageInputs(mode: 1)
        let mappedMaskScale = SceneTextureMappedUVScale.resolve(
            physicalWidth: 4096,
            physicalHeight: 4096,
            mappedWidth: 3840,
            mappedHeight: 2160
        )
        let imageBlend = try imageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline,
            multiply: 1
        )
        let halfImageBlend = try imageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline,
            multiply: 0.5
        )
        let partialAlphaImageBlend = try partialAlphaImageBlendPixel(
            device: device,
            queue: queue,
            pipeline: imageBlendPipeline
        )
        let standaloneGradientPixels = try gradientPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            sourceBGRA: [255, 255, 255, 255],
            dependencyBGRA: nil
        )
        let clippedGradientPixels = try gradientPixels(
            device: device,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor,
            sourceBGRA: [128, 128, 128, 128],
            dependencyBGRA: [0, 255, 0, 255]
        )

        let result: [String: Any] = [
            "drew": drew,
            "refusedWithoutPool": refusedWithoutPool,
            "centerBGRA": pixel(target, x: 4, y: 4),
            "bottomRightBGRA": pixel(target, x: 7, y: 7),
            "noDependencyBGRA": noDependency,
            "normalDependencyBGRA": normalDependency,
            "darkenDependencyBGRA": darkenDependency,
            "darkenHalfAlphaBGRA": darkenHalfAlpha,
            "solidTintBGRA": solidTint,
            "imageTintBGRA": imageTint,
            "fragmentUniformSize": MemoryLayout<SceneLayerFragmentUniforms>.size,
            "dependencyBlendModeOffset": MemoryLayout<SceneLayerFragmentUniforms>.offset(
                of: \SceneLayerFragmentUniforms.dependencyBlendMode
            ) ?? -1,
            "coarseBlur": [
                coarseBlur?.horizontalStep ?? -1,
                coarseBlur?.verticalStep ?? -1,
                coarseBlur?.sampleResolutionScale ?? -1,
            ],
            "coarseBlurIsPrecise": coarseBlur?.isPrecise ?? true,
            "preciseBlur": [
                preciseBlur?.horizontalStep ?? -1,
                preciseBlur?.verticalStep ?? -1,
                preciseBlur?.sampleResolutionScale ?? -1,
            ],
            "preciseBlurIsPrecise": preciseBlur?.isPrecise ?? false,
            "blockedPreciseBlurIsNil": blockedPreciseBlur == nil,
            "authoredExtentMismatchRefused": authoredExtentMismatchRefused,
            "authoredPreciseImpulse": authoredPreciseImpulse,
            "authoredStandardCheckerboard": authoredStandardCheckerboard,
            "authoredTwoStageChain": authoredTwoStageChain,
            "authoredOpacityLivePixels": authoredOpacityLivePixels,
            "authoredFailedChain": authoredFailedChain,
            "authoredStandardBlurOverridesLegacy": authoredStandardBlurOverridesLegacy,
            "standardBlurAlphaAwareDownsampleBGRA": standardBlurAlphaAwareDownsample,
            "foliageFlags": foliage.flags.rawValue,
            "foliageParams3": [
                foliage.params3.x, foliage.params3.y, foliage.params3.z, foliage.params3.w,
            ],
            "foliageParams4": [
                foliage.params4.x, foliage.params4.y, foliage.params4.z, foliage.params4.w,
            ],
            "unsupportedFoliageFlags": unsupportedFoliage.flags.rawValue,
            "mappedMaskScale": [mappedMaskScale.x, mappedMaskScale.y],
            "imageBlendBGRA": imageBlend,
            "halfImageBlendBGRA": halfImageBlend,
            "partialAlphaImageBlendBGRA": partialAlphaImageBlend,
            "gradientTopBGRA": standaloneGradientPixels[0],
            "gradientBottomBGRA": standaloneGradientPixels[1],
            "clippedGradientTopBGRA": clippedGradientPixels[0],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func dependencyBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        blendMode: Int?,
        alpha: Float
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let dependency = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [32, 64, 128, 128])
        fill(dependency, bgra: [192, 32, 64, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: alpha, cursorUV: .zero
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: blendMode.map {
                    SceneDependencyEffectInput(texture: dependency, blendMode: $0)
                },
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func layerTintPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        contentKind: String
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 1, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [255, 255, 255, 255])
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: SceneRenderDescriptor.Layer(
                    contentKind: contentKind, colorRGB: nil, colorBlendMode: nil, effects: []
                ),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0,
                    alpha: 1,
                    cursorUV: .zero,
                    tint: SIMD3<Float>(0.25, 0.5, 0.75)
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }

    static func imageBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageBlendPipeline,
        multiply: Float
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let blend = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 0, 0])
        fill(blend, bgra: [192, 32, 64, 255])
        guard pipeline.encode(
            source: source,
            blend: blend,
            target: target,
            multiply: multiply,
            alphaMultiply: 1,
            writesAlpha: true,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func partialAlphaImageBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageBlendPipeline
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let blend = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 128, 128])
        fill(blend, bgra: [128, 0, 0, 128])
        guard pipeline.encode(
            source: source,
            blend: blend,
            target: target,
            multiply: 1,
            alphaMultiply: 1,
            writesAlpha: true,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
    }

    static func gradientPixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        sourceBGRA: [UInt8],
        dependencyBGRA: [UInt8]?
    ) throws -> [[UInt8]] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: sourceBGRA)
        let dependency = dependencyBGRA.flatMap { color -> MTLTexture? in
            guard let texture = makeTexture(device: device, size: 8, usage: .shaderRead) else {
                return nil
            }
            fill(texture, bgra: color)
            return texture
        }
        let layer = gradientLayer(includesClipping: dependency != nil)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: dependency.map {
                    SceneDependencyEffectInput(texture: $0, blendMode: 0)
                },
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return [pixel(target, x: 4, y: 0), pixel(target, x: 4, y: 7)]
    }

    static func gradientLayer(includesClipping: Bool) -> SceneRenderDescriptor.Layer {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: ["AXIS": 1, "BLENDMODE": 0],
            constantShaderValues: [
                "Amount": .init(components: [1]),
                "Color 1": .init(components: [1, 0, 0]),
                "Color 2": .init(components: [0, 0, 1]),
                "Hue Speed": .init(components: [0]),
                "Opacity": .init(components: [1]),
                "Oscillate": .init(components: [0]),
            ]
        )
        var effects = [SceneRenderDescriptor.EffectDescriptor(
            file: "effects/workshop/2552475732/gradient_color/effect.json",
            visible: true,
            passes: [pass]
        )]
        if includesClipping {
            effects.append(.init(
                file: "effects/workshop/2800594362/clipping_mask/effect.json",
                visible: true,
                passes: []
            ))
        }
        return SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: effects
        )
    }

    static func blurPlan(
        path: String,
        scale: Double,
        blocksLegacyGaussianBlur: Bool = false
    ) -> SceneGaussianBlurPlan? {
        let empty = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [], textureSlots: [], combos: [:], constantShaderValues: [:]
        )
        let scaled = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: [:],
            constantShaderValues: ["scale": .init(components: [scale, scale])]
        )
        let passes = path.contains("blurprecise")
            ? [scaled, scaled]
            : [empty, scaled, scaled, empty]
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(file: path, visible: true, passes: passes)]
        )
        return SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        ).gaussianBlur
    }

    static func authoredExtentMismatchIsRefused(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> Bool {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device,
                  size: 8,
                  usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [0, 0, 255, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(time: 0, alpha: 1, cursorUV: .zero),
                offscreenTexturePool: SceneOffscreenTexturePool(device: device, maxDimension: 4),
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: authoredPreciseBlurPlan(),
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return !encoded
    }

    static func authoredPreciseBlurImpulseEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 8
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let referenceHorizontal = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let referenceOutput = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let blurPipeline = SceneGaussianBlurPipeline(device: device) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedImpulse(source)
        let plan = authoredPreciseBlurPlan()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        try drawAuthoredBlur(
            source: source,
            target: target,
            layer: layer,
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard let table = pool.graphTargets(
            for: plan, requestedWidth: size, requestedHeight: size
        ), let intermediateIdentity = table.plan.logicalTargets.first?.identity,
        let intermediate = table.texture(for: intermediateIdentity),
        let blur = plan.gaussianBlur,
        let commandBuffer = queue.makeCommandBuffer(), blurPipeline.encode(
            source: table.inputTexture,
            target: referenceHorizontal,
            step: SIMD2(
                blur.horizontalStep * blur.sampleResolutionScale / Float(size), 0
            ),
            commandBuffer: commandBuffer
        ), blurPipeline.encode(
            source: referenceHorizontal,
            target: referenceOutput,
            step: SIMD2(
                0, blur.verticalStep * blur.sampleResolutionScale / Float(size)
            ),
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let sourceBytes = try textureBytes(source, queue: queue)
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        let horizontalBytes = try textureBytes(intermediate, queue: queue)
        let expectedHorizontalBytes = try textureBytes(referenceHorizontal, queue: queue)
        let outputBytes = try textureBytes(table.outputTexture, queue: queue)
        let expectedOutputBytes = try textureBytes(referenceOutput, queue: queue)
        let mainBytes = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "inputMaxDelta": maxDifference(inputBytes, sourceBytes),
            "horizontalMaxDelta": maxDifference(
                horizontalBytes, expectedHorizontalBytes
            ),
            "outputMaxDelta": maxDifference(outputBytes, expectedOutputBytes),
            "mainMaxDelta": maxDifference(mainBytes, expectedOutputBytes),
            "horizontalToOutputDelta": maxDifference(horizontalBytes, outputBytes),
            "sourceToOutputDelta": maxDifference(sourceBytes, outputBytes),
            "sourceHasMixedAlpha": hasMixedAlpha(sourceBytes),
            "outputIsPremultiplied": isPremultiplied(outputBytes),
        ]
    }

    static func authoredStandardBlurCheckerboardEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        let quarterSize = 4
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let referenceQuarterA = makeTexture(
                  device: device, size: quarterSize,
                  usage: [.renderTarget, .shaderRead]
              ),
              let referenceQuarterB = makeTexture(
                  device: device, size: quarterSize,
                  usage: [.renderTarget, .shaderRead]
              ),
              let referenceOutput = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ),
              let blurPipeline = SceneStandardBlurPipeline(device: device) else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let plan = authoredStandardBlurPlan()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        try drawAuthoredBlur(
            source: source,
            target: target,
            layer: standardBlurLayer(),
            plan: plan,
            pool: pool,
            queue: queue,
            pipeline: pipeline,
            compositor: compositor
        )
        guard let table = pool.graphTargets(
            for: plan, requestedWidth: size, requestedHeight: size
        ) else {
            throw HarnessError.drawRefused
        }
        let intermediates = table.plan.logicalTargets.sorted {
            $0.lifetime.firstWriteNodeIndex < $1.lifetime.firstWriteNodeIndex
        }
        guard intermediates.count == 2,
        let quarterA = table.texture(for: intermediates[0].identity),
        let quarterB = table.texture(for: intermediates[1].identity),
        let blur = plan.standardBlur,
        let commandBuffer = queue.makeCommandBuffer(), blurPipeline.encodeDownsample(
            source: table.inputTexture,
            target: referenceQuarterA,
            commandBuffer: commandBuffer
        ), blurPipeline.encodeGaussian(
            source: referenceQuarterA,
            target: referenceQuarterB,
            step: SIMD2(blur.horizontalStep / Float(quarterSize), 0),
            commandBuffer: commandBuffer
        ), blurPipeline.encodeGaussian(
            source: referenceQuarterB,
            target: referenceQuarterA,
            step: SIMD2(0, blur.verticalStep / Float(quarterSize)),
            commandBuffer: commandBuffer
        ), blurPipeline.encodeCombine(
            blurred: referenceQuarterA,
            previous: table.inputTexture,
            target: referenceOutput,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.drawRefused
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let sourceBytes = try textureBytes(source, queue: queue)
        let inputBytes = try textureBytes(table.inputTexture, queue: queue)
        let horizontalBytes = try textureBytes(quarterB, queue: queue)
        let expectedHorizontalBytes = try textureBytes(referenceQuarterB, queue: queue)
        let verticalBytes = try textureBytes(quarterA, queue: queue)
        let expectedVerticalBytes = try textureBytes(referenceQuarterA, queue: queue)
        let outputBytes = try textureBytes(table.outputTexture, queue: queue)
        let expectedOutputBytes = try textureBytes(referenceOutput, queue: queue)
        let mainBytes = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "inputMaxDelta": maxDifference(inputBytes, sourceBytes),
            "horizontalMaxDelta": maxDifference(
                horizontalBytes, expectedHorizontalBytes
            ),
            "verticalMaxDelta": maxDifference(verticalBytes, expectedVerticalBytes),
            "horizontalToExpectedVerticalDelta": maxDifference(
                horizontalBytes, expectedVerticalBytes
            ),
            "verticalToExpectedHorizontalDelta": maxDifference(
                verticalBytes, expectedHorizontalBytes
            ),
            "outputMaxDelta": maxDifference(outputBytes, expectedOutputBytes),
            "mainMaxDelta": maxDifference(mainBytes, expectedOutputBytes),
            "horizontalToVerticalDelta": maxDifference(horizontalBytes, verticalBytes),
            "inputToOutputDelta": maxDifference(inputBytes, outputBytes),
            "sourceHasMixedAlpha": hasMixedAlpha(sourceBytes),
            "outputIsPremultiplied": isPremultiplied(outputBytes),
        ]
    }

    static func authoredTwoStageChainEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let chain = authoredTwoStageBlurChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        guard compositor.draw(
            SceneImageLayerDrawRequest(
                layer: standardBlurLayer(),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 3, alpha: 0.5, cursorUV: SIMD2(0.25, 0.75)
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: .empty(frameIndex: 17)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        ) else {
            throw HarnessError.drawRefused
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let tables = pool.graphTargets(
                for: chain, requestedWidth: size, requestedHeight: size
              ), tables.count == 2 else {
            throw HarnessError.commandFailed
        }

        let sourceBytes = try textureBytes(source, queue: queue)
        let firstInput = try textureBytes(tables[0].inputTexture, queue: queue)
        let firstOutput = try textureBytes(tables[0].outputTexture, queue: queue)
        let secondInput = try textureBytes(tables[1].inputTexture, queue: queue)
        let secondOutput = try textureBytes(tables[1].outputTexture, queue: queue)
        let mainOutput = try textureBytes(target, queue: queue)
        return [
            "encoded": true,
            "sourceToFirstInputDelta": maxDifference(sourceBytes, firstInput),
            "firstOutputToSecondInputDelta": maxDifference(firstOutput, secondInput),
            "firstToSecondOutputDelta": maxDifference(firstOutput, secondOutput),
            "secondOutputToMainDelta": maxDifference(secondOutput, mainOutput),
        ]
    }

    static func authoredOpacityLivePixels(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [[UInt8]] {
        try [Float?.none, Float(0.2)].map { liveAlpha in
            guard let source = makeTexture(device: device, size: 1, usage: .shaderRead),
                  let target = makeTexture(
                      device: device, size: 1, usage: [.renderTarget, .shaderRead]
                  ), let commandBuffer = queue.makeCommandBuffer() else {
                throw HarnessError.metalUnavailable
            }
            fill(source, bgra: [40, 80, 160, 200])
            let mainPass = SceneMainPassEncoder(
                commandBuffer: commandBuffer,
                target: target,
                clearColor: MTLClearColorMake(0, 0, 0, 0)
            )
            let snapshot = SceneDynamicSnapshot(
                strengthsByEffectIndex: [:],
                opacitiesByEffectIndex: liveAlpha.map { [0: $0] } ?? [:]
            )
            guard compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: SceneRenderDescriptor.Layer(
                        contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
                    ),
                    texture: source,
                    masks: .empty,
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: SceneOffscreenTexturePool(
                        device: device, maxDimension: 1
                    ),
                    offscreenSize: nil,
                    requiresSourceCopy: false,
                    finalCompositeAlpha: nil,
                    dependencyEffect: nil,
                    authoredEffectPlan: nil,
                    blocksLegacyGaussianBlur: false,
                    authoredEffectChain: authoredOpacityChain(),
                    dynamicValues: snapshot
                ),
                pipeline: pipeline,
                mainPass: mainPass
            ) else {
                throw HarnessError.drawRefused
            }
            mainPass.finishEnsuringClear()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else {
                throw HarnessError.commandFailed
            }
            return pixel(target, x: 0, y: 0)
        }
    }

    static func authoredFailedChainEvidence(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws -> [String: Any] {
        let size = 16
        guard let source = makeTexture(device: device, size: size, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: size, usage: [.renderTarget, .shaderRead]
              ), let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillPremultipliedCheckerboard(source)
        let chain = authoredFailingSecondStageChain()
        let pool = SceneOffscreenTexturePool(device: device, maxDimension: size)
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: standardBlurLayer(),
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: nil,
                blocksLegacyGaussianBlur: false,
                authoredEffectChain: chain,
                dynamicValues: .empty(frameIndex: 18)
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              let tables = pool.graphTargets(
                for: chain, requestedWidth: size, requestedHeight: size
              ), tables.count == 2 else {
            throw HarnessError.commandFailed
        }
        let firstOutput = try textureBytes(tables[0].outputTexture, queue: queue)
        return [
            "encoded": encoded,
            "mainPixel": pixel(target, x: size / 2, y: size / 2),
            "firstStageProducedPixels": firstOutput.contains(where: { $0 != 0 }),
        ]
    }

    static func drawAuthoredBlur(
        source: MTLTexture,
        target: MTLTexture,
        layer: SceneRenderDescriptor.Layer,
        plan: SceneAuthoredEffectExecutionPlan,
        pool: SceneOffscreenTexturePool,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor
    ) throws {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        guard compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: 1, cursorUV: .zero
                ),
                offscreenTexturePool: pool,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: nil,
                authoredEffectPlan: plan,
                blocksLegacyGaussianBlur: false
            ),
            pipeline: pipeline,
            mainPass: mainPass
        ) else {
            throw HarnessError.drawRefused
        }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
    }

    static func alphaAwareDownsamplePixel(
        device: MTLDevice,
        queue: MTLCommandQueue
    ) throws -> [UInt8] {
        guard let pipeline = SceneStandardBlurPipeline(device: device),
              let source = makeTexture(device: device, size: 4, usage: .shaderRead),
              let target = makeTexture(
                  device: device,
                  size: 1,
                  usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        let colors: [[UInt8]] = [
            [0, 0, 255, 255],
            [0, 255, 0, 128],
            [255, 0, 0, 64],
            [255, 255, 255, 0],
        ]
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let quadrant = (y >= source.height / 2 ? 2 : 0)
                    + (x >= source.width / 2 ? 1 : 0)
                let offset = (y * source.width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: colors[quadrant])
            }
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, source.width, source.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: source.width * 4
        )
        guard pipeline.encodeDownsample(
            source: source,
            target: target,
            commandBuffer: commandBuffer
        ) else {
            throw HarnessError.encoderUnavailable
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 0, y: 0)
    }

    static func standardBlurOverridesLegacy() -> Bool {
        let layer = standardBlurLayer()
        let legacy = SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false
        )
        let authored = SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: false,
            hasWaterRippleNormal: false,
            authoredEffectPlan: authoredStandardBlurPlan()
        )
        return legacy.gaussianBlur != nil
            && authored.standardBlur != nil
            && authored.gaussianBlur == nil
            && authored.offscreenPassCount == 4
    }

    static func standardBlurLayer() -> SceneRenderDescriptor.Layer {
        let empty = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [], textureSlots: [], combos: [:], constantShaderValues: [:]
        )
        let scaled = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: [],
            textureSlots: [],
            combos: [:],
            constantShaderValues: ["scale": .init(components: [0.6, 0.6])]
        )
        return SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(
                file: "effects/blur/effect.json",
                visible: true,
                passes: [empty, scaled, scaled, empty]
            )]
        )
    }

    static func authoredStandardBlurPlan(
        layerID: Int = 530,
        effectIndex: Int = 0,
        input: Graph.TextureIdentity? = nil
    ) -> SceneAuthoredEffectExecutionPlan {
        let graph = standardBlurGraph(
            layerID: layerID,
            effectIndex: effectIndex,
            input: input
        )
        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .standardBlur(SceneStandardBlurPlan(
                horizontalStep: 0.6,
                verticalStep: 0.6,
                renderTargetScale: 4
            )),
            materialNodeCount: 4,
            logicalRenderTargetCount: 2,
            inputRole: input == nil ? .layerSource : .priorEffectOutput
        )
    }

    static func authoredTwoStageBlurChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 840
        let first = authoredStandardBlurPlan(layerID: layerID)
        let second = authoredStandardBlurPlan(
            layerID: layerID,
            effectIndex: 1,
            input: first.renderGraph.finalOutput
        )
        let graph = Graph(
            layerID: layerID,
            effects: first.renderGraph.effects + second.renderGraph.effects,
            renderTargets: first.renderGraph.renderTargets + second.renderGraph.renderTargets,
            nodes: first.renderGraph.nodes + second.renderGraph.nodes,
            finalOutput: second.renderGraph.finalOutput,
            blockers: []
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [first, second]
        )
    }

    static func authoredOpacityChain() -> SceneAuthoredEffectExecutionChain {
        let layerID = 850
        let effectKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
        )
        let input = graphTexture(.layerSource, layerID: layerID)
        let output = graphTexture(.effectOutput, layerID: layerID, effect: effectKey)
        let node = Graph.Node(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: "materials/effects/opacity.json",
            materialPassID: "materials/effects/opacity.json#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
        let effect = Graph.Effect(
            key: effectKey,
            definitionPath: "effects/opacity/effect.json",
            input: input,
            output: output,
            nodeIndices: [0]
        )
        let graph = Graph(
            layerID: layerID,
            effects: [effect],
            renderTargets: [],
            nodes: [node],
            finalOutput: output,
            blockers: []
        )
        let stage = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            renderGraph: graph,
            backend: .opacity(SceneOpacityExecutionPlan(
                staticOrFallbackAlpha: 1,
                liveEffectIndex: 0
            )),
            materialNodeCount: 1,
            logicalRenderTargetCount: 0
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: layerID,
            renderGraph: graph,
            stages: [stage]
        )
    }

    static func authoredFailingSecondStageChain() -> SceneAuthoredEffectExecutionChain {
        let valid = authoredTwoStageBlurChain()
        let first = valid.stages[0]
        let second = valid.stages[1]
        let duplicateTarget = second.renderGraph.renderTargets[0].texture
        let invalidContrast = SceneLocalContrastPlan(
            firstQuarterTarget: duplicateTarget,
            secondQuarterTarget: duplicateTarget,
            renderGraph: second.renderGraph,
            staticOrFallbackStrength: 1
        )
        let failingSecond = SceneAuthoredEffectExecutionPlan(
            layerID: second.layerID,
            renderGraph: second.renderGraph,
            backend: .localContrast(invalidContrast),
            materialNodeCount: second.materialNodeCount,
            logicalRenderTargetCount: second.logicalRenderTargetCount,
            inputRole: second.inputRole
        )
        return SceneAuthoredEffectExecutionChain(
            layerID: valid.layerID,
            renderGraph: valid.renderGraph,
            stages: [first, failingSecond]
        )
    }

    static func foliageInputs(mode: Int) -> SceneLayerEffectInputs {
        let values: [String: SceneDocument.ShaderValue] = [
            "strength": .init(components: [0.4]),
            "speeduv": .init(components: [5]),
            "phase": .init(components: [0.57]),
            "power": .init(components: [1]),
            "scale": .init(components: [0.05]),
            "ratio": .init(components: [0.3]),
            "scrolldirection": .init(components: [-0.5]),
        ]
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            texturePaths: ["mask"],
            textureSlots: [nil, "mask"],
            combos: ["MODE": mode],
            constantShaderValues: values
        )
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: [.init(
                file: "effects/foliagesway/effect.json",
                visible: true,
                passes: [pass]
            )]
        )
        return SceneEffectRuntimePlanner.plan(
            for: layer,
            hasIrisMask: false,
            hasOpacityMask: false,
            hasWaterMask: false,
            hasFoliageMask: true,
            hasWaterRippleNormal: false
        ).inputs
    }

    static func makeTexture(
        device: MTLDevice,
        size: Int,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    static func fillPremultipliedImpulse(_ texture: MTLTexture) {
        fillPixels(texture) { x, y in
            switch (x, y) {
            case (1, 1): return [0, 0, 224, 255]
            case (5, 2): return [96, 0, 0, 128]
            case (2, 6): return [0, 48, 0, 64]
            case (6, 5): return [0, 180, 180, 255]
            default: return [0, 0, 0, 0]
            }
        }
    }

    static func fillPremultipliedCheckerboard(_ texture: MTLTexture) {
        let colors: [[UInt8]] = [
            [0, 0, 96, 255],
            [0, 40, 0, 128],
            [12, 0, 0, 64],
            [0, 0, 0, 0],
        ]
        fillPixels(texture) { x, y in
            let asymmetric = x > y ? 1 : 0
            return colors[((x / 2) + ((y / 3) * 2) + asymmetric) % colors.count]
        }
    }

    static func fillPixels(
        _ texture: MTLTexture,
        colorAt: (Int, Int) -> [UInt8]
    ) {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let offset = ((y * texture.width) + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: colorAt(x, y))
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func textureBytes(
        _ texture: MTLTexture,
        queue: MTLCommandQueue
    ) throws -> [UInt8] {
        let byteCount = texture.width * texture.height * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if texture.storageMode == .shared {
            texture.getBytes(
                &bytes,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
            return bytes
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let staging = texture.device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw HarnessError.readbackFailed
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: staging,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        staging.getBytes(
            &bytes,
            bytesPerRow: staging.width * 4,
            from: MTLRegionMake2D(0, 0, staging.width, staging.height),
            mipmapLevel: 0
        )
        return bytes
    }

    static func maxDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return Int.max }
        return zip(lhs, rhs).reduce(0) { difference, values in
            max(difference, abs(Int(values.0) - Int(values.1)))
        }
    }

    static func hasMixedAlpha(_ bytes: [UInt8]) -> Bool {
        let alphaValues = Set(stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] })
        return [UInt8(0), 64, 128, 255].allSatisfy(alphaValues.contains)
    }

    static func isPremultiplied(_ bytes: [UInt8]) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
            let alpha = Int(bytes[offset + 3]) + 1
            return Int(bytes[offset]) <= alpha
                && Int(bytes[offset + 1]) <= alpha
                && Int(bytes[offset + 2]) <= alpha
        }
    }

    static func fillQuadrants(_ texture: MTLTexture) {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let color: [UInt8]
                switch (x >= texture.width / 2, y >= texture.height / 2) {
                case (false, false): color = [0, 0, 255, 255]
                case (true, false): color = [0, 255, 0, 255]
                case (false, true): color = [255, 0, 0, 255]
                case (true, true): color = [255, 255, 255, 255]
                }
                let offset = (y * texture.width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: color)
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func fill(_ texture: MTLTexture, bgra: [UInt8]) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(texture.width * texture.height * 4)
        for _ in 0..<(texture.width * texture.height) {
            bytes.append(contentsOf: bgra)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func pixel(_ texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var value = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &value,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return value
    }

    enum HarnessError: Error {
        case metalUnavailable
        case encoderUnavailable
        case commandFailed
        case drawRefused
        case readbackFailed
    }
}
'''


class SceneFramebufferCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-framebuffer-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-framebuffer-capture"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        cls.stderr = completed.stderr

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_current_frame_can_be_captured_without_read_write_aliasing(self) -> None:
        self.assertTrue(self.result["drew"])
        self.assertFalse(self.result["refusedWithoutPool"])
        self.assertEqual(self.result["centerBGRA"], [0, 0, 255, 255])
        self.assertEqual(self.result["bottomRightBGRA"], [255, 255, 255, 255])

    def test_capture_telemetry_waits_for_gpu_completion(self) -> None:
        self.assertIn("phase=utility-capture layer=701 status=succeeded", self.stderr)
        self.assertIn("phase=utility-capture layer=702 status=failed", self.stderr)

    def test_dependency_blend_modes_preserve_source_alpha(self) -> None:
        self.assert_pixel_close(self.result["noDependencyBGRA"], [32, 64, 128, 128])
        self.assert_pixel_close(self.result["normalDependencyBGRA"], [112, 48, 96, 128])
        self.assert_pixel_close(self.result["darkenDependencyBGRA"], [32, 32, 64, 128])
        self.assert_pixel_close(self.result["darkenHalfAlphaBGRA"], [16, 16, 32, 64])

    def test_layer_tint_is_applied_only_to_solid_content_on_gpu(self) -> None:
        self.assert_pixel_close(self.result["solidTintBGRA"], [191, 128, 64, 255])
        self.assert_pixel_close(self.result["imageTintBGRA"], [255, 255, 255, 255])

    def test_blur_scales_remain_authored_pixels_until_target_normalization(self) -> None:
        for actual, expected in zip(self.result["coarseBlur"], [0.6, 0.6, 4]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertFalse(self.result["coarseBlurIsPrecise"])
        for actual, expected in zip(self.result["preciseBlur"], [0.45, 0.45, 1]):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertTrue(self.result["preciseBlurIsPrecise"])
        self.assertTrue(self.result["blockedPreciseBlurIsNil"])
        self.assertTrue(self.result["authoredExtentMismatchRefused"])

    def test_precise_graph_blur_runs_horizontal_then_vertical_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredPreciseImpulse"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["sourceHasMixedAlpha"])
        self.assertTrue(evidence["outputIsPremultiplied"])
        for key in ("inputMaxDelta", "horizontalMaxDelta", "outputMaxDelta"):
            self.assertLessEqual(evidence[key], 1, (key, evidence))
        self.assertLessEqual(evidence["mainMaxDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToOutputDelta"], 2, evidence)
        self.assertGreater(evidence["sourceToOutputDelta"], 20, evidence)

    def test_standard_graph_blur_runs_full_ping_pong_chain_on_mixed_alpha(self) -> None:
        evidence = self.result["authoredStandardCheckerboard"]
        self.assertTrue(evidence["encoded"])
        self.assertTrue(evidence["sourceHasMixedAlpha"])
        self.assertTrue(evidence["outputIsPremultiplied"])
        for key in (
            "inputMaxDelta",
            "horizontalMaxDelta",
            "verticalMaxDelta",
            "outputMaxDelta",
        ):
            self.assertLessEqual(evidence[key], 1, (key, evidence))
        self.assertLessEqual(evidence["mainMaxDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToExpectedVerticalDelta"], 2, evidence)
        self.assertGreater(evidence["verticalToExpectedHorizontalDelta"], 2, evidence)
        self.assertGreater(evidence["horizontalToVerticalDelta"], 2, evidence)
        self.assertGreater(evidence["inputToOutputDelta"], 20, evidence)
        self.assertTrue(self.result["authoredStandardBlurOverridesLegacy"])

    def test_authored_effect_chain_runs_in_order_without_reapplying_layer_alpha(self) -> None:
        evidence = self.result["authoredTwoStageChain"]
        self.assertTrue(evidence["encoded"])
        self.assertGreater(evidence["sourceToFirstInputDelta"], 20, evidence)
        self.assertLessEqual(evidence["firstOutputToSecondInputDelta"], 1, evidence)
        self.assertGreater(evidence["firstToSecondOutputDelta"], 1, evidence)
        self.assertLessEqual(evidence["secondOutputToMainDelta"], 2, evidence)

    def test_chain_renderer_resolves_live_values_per_stage_and_neutralizes_recapture(self) -> None:
        source = (SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectChainRenderer.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("masks: isFirstStage ? masks : .empty", source)
        self.assertIn("sourceUniforms: isFirstStage ? sourceUniforms : .neutral()", source)
        self.assertIn("stage.localContrastStrength(in: dynamicValues)", source)
        self.assertIn("stage.opacityAlpha(in: dynamicValues)", source)

    def test_opacity_chain_consumes_live_snapshot_on_gpu(self) -> None:
        authored, live = self.result["authoredOpacityLivePixels"]
        self.assertLessEqual(max(abs(a - b) for a, b in zip(authored, [40, 80, 160, 200])), 1)
        self.assertLessEqual(max(abs(a - b) for a, b in zip(live, [8, 16, 32, 40])), 1)

    def test_failed_later_stage_never_composites_an_earlier_stage(self) -> None:
        evidence = self.result["authoredFailedChain"]
        self.assertFalse(evidence["encoded"])
        self.assertTrue(evidence["firstStageProducedPixels"])
        self.assertEqual(evidence["mainPixel"], [0, 0, 0, 0])

    def test_standard_blur_downsample_is_alpha_aware(self) -> None:
        self.assert_pixel_close(
            self.result["standardBlurAlphaAwareDownsampleBGRA"],
            [37, 73, 146, 84],
            3,
        )

    def test_single_builtin_foliage_plan_preserves_authored_parameters(self) -> None:
        self.assertNotEqual(self.result["foliageFlags"] & 1, 0)
        expected3 = [0.4, 5, 0.57, 1]
        expected4 = [0.05, 0.3, -0.5, 0]
        for actual, expected in zip(self.result["foliageParams3"], expected3):
            self.assertAlmostEqual(actual, expected, places=6)
        for actual, expected in zip(self.result["foliageParams4"], expected4):
            self.assertAlmostEqual(actual, expected, places=6)
        self.assertEqual(self.result["unsupportedFoliageFlags"] & 1, 0)

    def test_foliage_mask_uses_mapped_to_physical_uv_scale(self) -> None:
        self.assertAlmostEqual(self.result["mappedMaskScale"][0], 0.9375, places=6)
        self.assertAlmostEqual(self.result["mappedMaskScale"][1], 0.52734375, places=6)

    def test_static_image_blend_writes_provider_color_and_alpha(self) -> None:
        self.assert_pixel_close(self.result["imageBlendBGRA"], [192, 32, 64, 255])
        self.assert_pixel_close(self.result["halfImageBlendBGRA"], [96, 16, 32, 128])
        self.assert_pixel_close(
            self.result["partialAlphaImageBlendBGRA"], [128, 0, 64, 192]
        )

    def test_gradient_color_runs_before_dependency_clipping_and_preserves_alpha(self) -> None:
        self.assert_pixel_close(self.result["gradientTopBGRA"], [16, 0, 239, 255], 2)
        self.assert_pixel_close(self.result["gradientBottomBGRA"], [239, 0, 16, 255], 2)
        self.assert_pixel_close(self.result["clippedGradientTopBGRA"], [4, 128, 60, 128], 2)

    def test_dependency_mode_reuses_uniform_padding_without_layout_growth(self) -> None:
        self.assertEqual(self.result["fragmentUniformSize"], 176)
        self.assertEqual(self.result["dependencyBlendModeOffset"], 12)

    def assert_pixel_close(
        self, actual: list[int], expected: list[int], tolerance: int = 1
    ) -> None:
        self.assertEqual(len(actual), len(expected))
        for component, wanted in zip(actual, expected):
            self.assertLessEqual(abs(component - wanted), tolerance)


if __name__ == "__main__":
    unittest.main()
