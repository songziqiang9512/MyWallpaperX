#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_real_test_fixtures import sample_cache_root


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectStageCompileModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContractLoader+SourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderUniformBinder.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredScrollShaderProfile.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantEnvironment.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderDirective.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderVariantResolver+Schema.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderPreprocessor.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlanner.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlanner+Preparation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlanner+Bindings.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPipelineCache.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

final class Counter {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let components: [Double]?
        let timeline: String?
        let timelineDiagnostics: [String]
    }
}

struct SceneEffectTextureInput { let name: String }

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let sizeWH: [Float]?
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 20
    static let descriptorID = "20#effect#0"
    static let materialPath = "materials/effects/test.json"
    static let materialPassID = "materials/effects/test.json#0"

    struct Options {
        var contentKind = "solid"
        var size: [Float]? = [128, 128]
        var visible: Bool? = true
        var externalTexture = false
        var combo = false
        var userBinding = false
        var userShaderValue = false
        var alphaWriting: String?
        var blending = "normal"
    }

    static func value(_ component: Double, bound: Bool = false) -> SceneDocument.ShaderValue {
        .init(
            userBinding: bound ? "property" : nil,
            components: [component],
            timeline: nil,
            timelineDiagnostics: []
        )
    }

    static func descriptor(
        identity: String,
        options: Options = .init(),
        resolvedMaterialPath: String = materialPath,
        constantOverrides: [String: SceneDocument.ShaderValue]? = nil
    ) -> SceneRenderDescriptor {
        let textureSlots: [String?] = options.externalTexture ? ["external.png"] : []
        let constants: [String: SceneDocument.ShaderValue]
        if let constantOverrides {
            constants = constantOverrides
        } else {
            switch identity {
            case "effects/generic", "effects/legacycomboschema",
                 "effects/ambiguousinteger", "effects/suffixnumeric":
                constants = ["g_Strength": value(0.75, bound: options.userBinding)]
            case "effects/annotated":
                constants = ["Strength label": value(0.75)]
            case "effects/annotatedambiguous":
                constants = [
                    "u_Strength": value(0.25),
                    "Strength label": value(0.75),
                ]
            case "effects/annotatedbound":
                constants = ["Strength label": value(0.75, bound: true)]
            case "effects/aliascollision":
                constants = ["Strength label": value(0.75)]
            default:
                constants = [:]
            }
        }
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            textureSlots: textureSlots,
            userTextureInputs: [],
            combos: options.combo ? ["OPTION": 1] : [:],
            constantShaderValues: constants
        )
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: descriptorID,
            visible: options.visible,
            passes: [pass]
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(resolvedMaterialPath)#0",
            materialPath: resolvedMaterialPath,
            shaderPath: identity,
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: options.userShaderValue ? ["g_Strength": "property"] : [:],
            blending: options.blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: options.alphaWriting
        )
        return .init(
            layers: [.init(
                id: layerID,
                contentKind: options.contentKind,
                sizeWH: options.size,
                effects: [effect]
            )],
            materialPasses: [material]
        )
    }

    static func graph(
        priorInput: Bool = false,
        blocker: Bool = false,
        definitionPath: String = "effects/test/effect.json",
        resolvedMaterialPath: String = materialPath
    ) -> Graph {
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: descriptorID
        )
        let priorKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "prior"
        )
        let input = Graph.TextureIdentity(
            kind: priorInput ? .effectOutput : .layerSource,
            layerID: layerID,
            effect: priorInput ? priorKey : nil,
            name: nil
        )
        let output = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: key,
            name: nil
        )
        return .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: definitionPath,
                input: input,
                output: output,
                nodeIndices: [0]
            )],
            renderTargets: [],
            nodes: [.init(
                nodeIndex: 0,
                effect: key,
                definitionPassIndex: 0,
                materialOrdinal: 0,
                instancePassIndex: 0,
                kind: .material,
                materialPath: resolvedMaterialPath,
                materialPassID: "\(resolvedMaterialPath)#0",
                target: output,
                bindings: [],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )],
            finalOutput: output,
            blockers: blocker ? [.init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "fixture"
            )] : []
        )
    }

    static func contracts(_ identity: String, root: URL) -> [SceneShaderContract] {
        SceneShaderContractLoader().load(shaderReferences: [identity], rootURL: root)
    }

    static func plan(
        identity: String,
        root: URL,
        options: Options = .init(),
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false,
        definitionPath: String = "effects/test/effect.json",
        resolvedMaterialPath: String = materialPath,
        constantOverrides: [String: SceneDocument.ShaderValue]? = nil
    ) -> SceneAuthoredShaderExecutionPlan? {
        SceneAuthoredShaderExecutionPlanner.plan(
            graph: graph(
                priorInput: priorInput,
                blocker: blocker,
                definitionPath: definitionPath,
                resolvedMaterialPath: resolvedMaterialPath
            ),
            descriptor: descriptor(
                identity: identity,
                options: options,
                resolvedMaterialPath: resolvedMaterialPath,
                constantOverrides: constantOverrides
            ),
            shaderContracts: contracts(identity, root: root),
            inputRole: role
        )
    }

    static func compile(
        identity: String,
        root: URL,
        options: Options = .init(),
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false,
        definitionPath: String = "effects/test/effect.json",
        resolvedMaterialPath: String = materialPath,
        constantOverrides: [String: SceneDocument.ShaderValue]? = nil
    ) -> SceneEffectStageBackendCompileResult<SceneAuthoredShaderExecutionPlan> {
        let graph = graph(
            priorInput: priorInput,
            blocker: blocker,
            definitionPath: definitionPath,
            resolvedMaterialPath: resolvedMaterialPath
        )
        return SceneAuthoredShaderExecutionPlanner.compile(.init(
            stageGraph: graph,
            inputRole: role,
            descriptor: descriptor(
                identity: identity,
                options: options,
                resolvedMaterialPath: resolvedMaterialPath,
                constantOverrides: constantOverrides
            ),
            shaderContracts: contracts(identity, root: root)
        ))
    }

    static func preparationResult(
        identity: String,
        root: URL,
        options: Options = .init(),
        graphless: Bool = false,
        textureReadiness: [Int: Bool] = [:]
    ) -> SceneEffectStageBackendCompileResult<SceneShaderPreparedProgram>? {
        let stageGraph = graph()
        let renderDescriptor = descriptor(identity: identity, options: options)
        guard let node = stageGraph.nodes.first else { return nil }
        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: stageGraph,
            descriptor: renderDescriptor
        )
        guard resolution.isResolved,
              let material = resolution.node,
              let loadedContract = contracts(identity, root: root).first else {
            return nil
        }
        let contract = graphless
            ? SceneShaderContract(
                identity: loadedContract.identity,
                sourceKind: loadedContract.sourceKind,
                stages: loadedContract.stages,
                diagnostics: loadedContract.diagnostics,
                canonicalSHA256: loadedContract.canonicalSHA256
            )
            : loadedContract
        return SceneAuthoredShaderExecutionPlanner.prepareShaderStages(
            contract: contract,
            combos: material.combos,
            textureReadiness: textureReadiness
        )
    }

    static func preparedStages(
        identity: String,
        root: URL,
        options: Options = .init(),
        graphless: Bool = false,
        textureReadiness: [Int: Bool] = [:]
    ) -> SceneShaderPreparedProgram? {
        preparationResult(
            identity: identity,
            root: root,
            options: options,
            graphless: graphless,
            textureReadiness: textureReadiness
        )?.acceptedPlan
    }

    static func preparationFailureDetails(
        identity: String,
        root: URL,
        options: Options = .init(),
        textureReadiness: [Int: Bool] = [:]
    ) -> [String]? {
        guard case let .rejected(failure)? = preparationResult(
            identity: identity,
            root: root,
            options: options,
            textureReadiness: textureReadiness
        ) else { return nil }
        return [failure.code.rawValue] + failure.details
    }

    static func failureCode(
        identity: String,
        root: URL,
        options: Options = .init(),
        priorInput: Bool = false,
        role: SceneAuthoredEffectInputRole = .layerSource,
        blocker: Bool = false
    ) -> String? {
        guard case .rejected(let failure) = compile(
            identity: identity,
            root: root,
            options: options,
            priorInput: priorInput,
            role: role,
            blocker: blocker
        ) else {
            return nil
        }
        return failure.code.rawValue
    }

    static func failureSnapshot(
        identity: String,
        root: URL,
        options: Options = .init(),
        blocker: Bool = false
    ) -> [String]? {
        guard case .rejected(let failure) = compile(
            identity: identity,
            root: root,
            options: options,
            blocker: blocker
        ) else {
            return nil
        }
        return [
            failure.backend.rawValue,
            failure.phase.rawValue,
            failure.code.rawValue,
        ] + failure.details
    }

    static func planSnapshot(_ plan: SceneAuthoredShaderExecutionPlan?) -> [String] {
        guard let plan else { return ["nil"] }
        let fields = plan.program.uniformLayout.fields.map {
            "\($0.name):\($0.type.rawValue):\($0.offset)"
        }
        let textures = plan.program.textureBindings.map { "\($0.name):\($0.slot)" }
        let bindings = plan.uniformBindings.map { binding in
            let source: String
            switch binding.source {
            case .renderSize: source = "render-size"
            case .modelViewProjection: source = "model-view-projection"
            case .time: source = "time"
            case .dayTime: source = "day-time"
            case .frameTime: source = "frame-time"
            case .pointerPosition: source = "pointer-position"
            case .pointerPositionLast: source = "pointer-position-last"
            case .screen: source = "screen"
            case .texelSize(let scale): source = "texel-size:\(scale)"
            case .textureResolution(let slot): source = "texture-resolution:\(slot)"
            case .constant(let components): source = "constant:\(components)"
            }
            return "\(binding.field.name):\(binding.field.type.rawValue):"
                + "\(binding.field.offset):\(source)"
        }
        let profile = plan.profile == .scroll ? "scroll" : "generic-framebuffer"
        let state = plan.renderState
        let offscreen = plan.offscreenSize(for: CGSize(width: 71, height: 93))
        return [
            plan.cacheKey,
            plan.program.metalSource,
            plan.program.vertexFunctionName,
            plan.program.fragmentFunctionName,
            "uniform-byte-size=\(plan.program.uniformLayout.byteSize)",
            "static-loop-work=\(plan.program.staticLoopWork)",
            "state=\(state.blending.rawValue):\(state.depthTest.rawValue):"
                + "\(state.depthWrite.rawValue):\(state.cullMode.rawValue):"
                + "\(state.alphaWriting.rawValue)",
            "raw-state=\(state.rawValues.blending ?? "-"):"
                + "\(state.rawValues.depthTest ?? "-"):"
                + "\(state.rawValues.depthWrite ?? "-"):"
                + "\(state.rawValues.cullMode ?? "-"):"
                + "\(state.rawValues.alphaWriting ?? "-")",
            "mapped=\(plan.mappedSize.width)x\(plan.mappedSize.height)",
            "slots=\(plan.framebufferTextureSlots)",
            "profile=\(profile)",
            "offscreen=\(offscreen?.width ?? -1)x\(offscreen?.height ?? -1)",
        ] + fields + textures + bindings
    }

    static func scrollPlan(
        identity: String,
        definitionPath: String,
        resolvedMaterialPath: String,
        root: URL,
        repeatValue: [Double] = [1, 1],
        speedX: Double,
        speedY: Double,
        bound: Bool = false,
        options: Options = .init(),
        priorInput: Bool = true,
        role: SceneAuthoredEffectInputRole = .priorEffectOutput
    ) -> SceneAuthoredShaderExecutionPlan? {
        plan(
            identity: identity,
            root: root,
            options: options,
            priorInput: priorInput,
            role: role,
            definitionPath: definitionPath,
            resolvedMaterialPath: resolvedMaterialPath,
            constantOverrides: [
                "repeat": .init(
                    userBinding: bound ? "repeat-property" : nil,
                    components: repeatValue,
                    timeline: nil,
                    timelineDiagnostics: []
                ),
                "speedx": value(speedX),
                "speedy": value(speedY),
            ]
        )
    }

    static func render(
        _ plan: SceneAuthoredShaderExecutionPlan,
        dimension: Int,
        device: MTLDevice
    ) -> [String: Any]? {
        guard dimension > 0,
              let queue = device.makeCommandQueue(),
              let pipelineCache = SceneAuthoredShaderPipelineCache(device: device) else {
            return nil
        }
        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: dimension,
            height: dimension,
            mipmapped: false
        )
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = [.shaderRead, .renderTarget]
        let targetDescriptor = sourceDescriptor.copy() as! MTLTextureDescriptor
        guard let source = device.makeTexture(descriptor: sourceDescriptor),
              let target = device.makeTexture(descriptor: targetDescriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }
        let inputBytes = [UInt8](
            repeating: 255,
            count: dimension * dimension * 4
        )
        inputBytes.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            source.replace(
                region: MTLRegionMake2D(0, 0, dimension, dimension),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: dimension * 4
            )
        }
        let size = CGSize(width: dimension, height: dimension)
        let mvp = simd_float4x4(columns: (
            SIMD4(2 / Float(dimension), 0, 0, 0),
            SIMD4(0, 2 / Float(dimension), 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ))
        let inputs = SceneAuthoredShaderUniformInputs(
            frameIndex: 1,
            renderSize: size,
            screenSize: CGSize(width: 1920, height: 1080),
            modelViewProjection: mvp,
            sceneTime: 1,
            dayTime: 0.5,
            frameTime: 1.0 / 60.0,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero,
            texturePhysicalSizes: Dictionary(
                uniqueKeysWithValues: plan.framebufferTextureSlots.map { ($0, size) }
            )
        )
        guard SceneAuthoredShaderRenderer.encode(
            plan: plan,
            source: source,
            target: target,
            inputs: inputs,
            pipelineCache: pipelineCache,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        var output = [UInt8](repeating: 0, count: dimension * dimension * 4)
        target.getBytes(
            &output,
            bytesPerRow: dimension * 4,
            from: MTLRegionMake2D(0, 0, dimension, dimension),
            mipmapLevel: 0
        )
        let rgb = output.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : Int(value)
        }
        return [
            "minimumRGB": rgb.min() ?? 0,
            "maximumRGB": rgb.max() ?? 0,
            "distinctRGB": Set(rgb).count,
            "averageRGB": rgb.reduce(0, +) / max(1, rgb.count),
            "alphaMinimum": output.enumerated().compactMap {
                $0.offset % 4 == 3 ? Int($0.element) : nil
            }.min() ?? 0,
            "compilationAttempts": pipelineCache.compilationAttemptCount,
        ]
    }

    static func scrollRow(
        _ plan: SceneAuthoredShaderExecutionPlan,
        time: Float,
        device: MTLDevice
    ) -> [Int]? {
        let dimension = 8
        guard let queue = device.makeCommandQueue(),
              let pipelineCache = SceneAuthoredShaderPipelineCache(device: device) else {
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: dimension,
            height: dimension,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let source = device.makeTexture(descriptor: descriptor),
              let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }
        var input = [UInt8](repeating: 0, count: dimension * dimension * 4)
        for y in 0..<dimension {
            for x in 0..<dimension {
                let offset = (y * dimension + x) * 4
                input[offset] = 0
                input[offset + 1] = UInt8(x * 30)
                input[offset + 2] = 0
                input[offset + 3] = 255
            }
        }
        input.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            source.replace(
                region: MTLRegionMake2D(0, 0, dimension, dimension),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: dimension * 4
            )
        }
        let size = CGSize(width: dimension, height: dimension)
        let inputs = SceneAuthoredShaderUniformInputs(
            frameIndex: 1,
            renderSize: size,
            screenSize: size,
            modelViewProjection: simd_float4x4(columns: (
                SIMD4(0.25, 0, 0, 0),
                SIMD4(0, 0.25, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(0, 0, 0, 1)
            )),
            sceneTime: time,
            dayTime: 0,
            frameTime: 1.0 / 60.0,
            pointerCurrentNDC: .zero,
            pointerPreviousNDC: .zero,
            texturePhysicalSizes: [0: size]
        )
        guard SceneAuthoredShaderRenderer.encode(
            plan: plan,
            source: source,
            target: target,
            inputs: inputs,
            pipelineCache: pipelineCache,
            commandBuffer: commandBuffer
        ) else {
            return nil
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        var output = [UInt8](repeating: 0, count: input.count)
        target.getBytes(
            &output,
            bytesPerRow: dimension * 4,
            from: MTLRegionMake2D(0, 0, dimension, dimension),
            mipmapLevel: 0
        )
        return (0..<dimension).map { Int(output[$0 * 4 + 1]) }
    }

    static func failureIsCached(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let original = plan.program
        let invalidProgram = SceneAuthoredShaderProgram(
            metalSource: "this is not metal source",
            vertexFunctionName: original.vertexFunctionName,
            fragmentFunctionName: original.fragmentFunctionName,
            uniformLayout: original.uniformLayout,
            textureBindings: original.textureBindings,
            staticLoopWork: original.staticLoopWork,
            colorTransfer: .unresolved
        )
        let invalid = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: invalidProgram,
            renderState: plan.renderState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        return cache.pipeline(for: invalid) == nil
            && cache.pipeline(for: invalid) == nil
            && cache.entryCount == 1
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 1
    }

    static func concurrentCacheIsSingleAttempt(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let lock = NSLock()
        var states: [ObjectIdentifier] = []
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if let pipeline = cache.pipeline(for: plan) {
                lock.lock()
                states.append(ObjectIdentifier(pipeline.state))
                lock.unlock()
            }
        }
        return states.count == 64
            && Set(states).count == 1
            && cache.entryCount == 1
            && cache.failedEntryCount == 0
            && cache.compilationAttemptCount == 1
    }

    static func concurrentFailureIsSingleAttempt(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let cache = SceneAuthoredShaderPipelineCache(device: device) else {
            return false
        }
        let original = plan.program
        let invalid = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: SceneAuthoredShaderProgram(
                metalSource: "this is not metal source",
                vertexFunctionName: original.vertexFunctionName,
                fragmentFunctionName: original.fragmentFunctionName,
                uniformLayout: original.uniformLayout,
                textureBindings: original.textureBindings,
                staticLoopWork: original.staticLoopWork,
                colorTransfer: .unresolved
            ),
            renderState: plan.renderState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        let successes = Counter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if cache.pipeline(for: invalid) != nil {
                successes.increment()
            }
        }
        return successes.read() == 0
            && cache.entryCount == 1
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 1
    }

    static func unsupportedStateDoesNotAlias(
        _ plan: SceneAuthoredShaderExecutionPlan,
        device: MTLDevice
    ) -> Bool {
        guard let unsupportedState = SceneMaterialRenderState.compile(
                  blending: "additive",
                  depthTest: "disabled",
                  depthWrite: "disabled",
                  cullMode: "nocull",
                  alphaWriting: nil
              ),
              let cache = SceneAuthoredShaderPipelineCache(device: device),
              let supported = cache.pipeline(for: plan) else {
            return false
        }
        let unsupported = SceneAuthoredShaderExecutionPlan(
            cacheKey: plan.cacheKey,
            program: plan.program,
            renderState: unsupportedState,
            mappedSize: plan.mappedSize,
            framebufferTextureSlots: plan.framebufferTextureSlots,
            uniformBindings: plan.uniformBindings
        )
        guard cache.pipeline(for: unsupported) == nil,
              let repeated = cache.pipeline(for: plan) else {
            return false
        }
        return ObjectIdentifier(repeated.state) == ObjectIdentifier(supported.state)
            && cache.entryCount == 2
            && cache.failedEntryCount == 1
            && cache.compilationAttemptCount == 2
    }

    static func main() throws {
        let realRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let syntheticRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let generic = plan(identity: "effects/generic", root: syntheticRoot)
        let typedGeneric = compile(
            identity: "effects/generic",
            root: syntheticRoot
        ).acceptedPlan
        let annotated = plan(identity: "effects/annotated", root: syntheticRoot)
        let real = plan(identity: "effects/myfirstshader", root: realRoot)
        let stockScrollRoot = URL(
            fileURLWithPath: CommandLine.arguments[3],
            isDirectory: true
        )
        let relocatedScrollRoot = URL(
            fileURLWithPath: CommandLine.arguments[4],
            isDirectory: true
        )
        let annotatedScrollRoot = URL(
            fileURLWithPath: CommandLine.arguments[5],
            isDirectory: true
        )
        let stockScroll = scrollPlan(
            identity: "effects/scroll",
            definitionPath: "effects/scroll/effect.json",
            resolvedMaterialPath: "materials/effects/scroll.json",
            root: stockScrollRoot,
            speedX: 0.25,
            speedY: 0
        )
        let relocatedScroll = scrollPlan(
            identity: "workshop/3302578859/effects/scroll",
            definitionPath: "effects/workshop/3302578859/scroll/effect.json",
            resolvedMaterialPath:
                "materials/workshop/3302578859/effects/scroll.json",
            root: relocatedScrollRoot,
            speedX: 0,
            speedY: 0.15
        )
        let annotatedScroll = scrollPlan(
            identity: "workshop/3387825383/effects/scroll",
            definitionPath: "effects/workshop/3387825383/scroll/effect.json",
            resolvedMaterialPath:
                "materials/workshop/3387825383/effects/scroll.json",
            root: annotatedScrollRoot,
            speedX: 0.45,
            speedY: 0
        )
        var external = Options(); external.externalTexture = true
        var combo = Options(); combo.combo = true
        var bound = Options(); bound.userBinding = true
        var userShader = Options(); userShader.userShaderValue = true
        var alphaWriting = Options(); alphaWriting.alphaWriting = "enabled"
        var alphaWritingDefault = Options(); alphaWritingDefault.alphaWriting = "default"
        var alphaWritingUnknown = Options(); alphaWritingUnknown.alphaWriting = "unknown"
        var blending = Options(); blending.blending = "additive"
        var translucent = Options(); translucent.blending = "translucent"
        var missingSize = Options(); missingSize.size = nil
        var video = Options(); video.contentKind = "video"
        var composition = Options(); composition.contentKind = "composition"

        let typedFailureCodes = [
            "blocked": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                blocker: true
            ),
            "external": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: external
            ),
            "combo": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: combo
            ),
            "bound": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: bound
            ),
            "userShader": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: userShader
            ),
            "alphaWriting": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: alphaWriting
            ),
            "alphaWritingUnknown": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: alphaWritingUnknown
            ),
            "missingSize": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: missingSize
            ),
            "video": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                options: video
            ),
            "wrongRole": failureCode(
                identity: "effects/generic",
                root: syntheticRoot,
                priorInput: true,
                role: .layerSource
            ),
            "noannotation": failureCode(
                identity: "effects/noannotation",
                root: syntheticRoot
            ),
            "unknown": failureCode(
                identity: "effects/unknown",
                root: syntheticRoot
            ),
            "included": failureCode(
                identity: "effects/included",
                root: syntheticRoot
            ),
            "conditional": failureCode(
                identity: "effects/conditionalreflection",
                root: syntheticRoot
            ),
            "annotatedambiguous": failureCode(
                identity: "effects/annotatedambiguous",
                root: syntheticRoot
            ),
            "aliascollision": failureCode(
                identity: "effects/aliascollision",
                root: syntheticRoot
            ),
        ]
        let structuralGraph = graph()
        let structurallyNotApplicable: Bool
        let structuralResult = SceneAuthoredShaderExecutionPlanner.compile(.init(
            stageGraph: Graph(
                layerID: structuralGraph.layerID,
                effects: structuralGraph.effects,
                renderTargets: structuralGraph.renderTargets,
                nodes: structuralGraph.nodes + structuralGraph.nodes,
                finalOutput: structuralGraph.finalOutput,
                blockers: structuralGraph.blockers
            ),
            inputRole: .layerSource,
            descriptor: descriptor(identity: "effects/generic"),
            shaderContracts: contracts("effects/generic", root: syntheticRoot)
        ))
        switch structuralResult {
        case .notApplicable:
            structurallyNotApplicable = true
        case .accepted, .rejected:
            structurallyNotApplicable = false
        }

        let rejectedOptions = [
            external, combo, bound, userShader, alphaWriting, alphaWritingDefault,
            alphaWritingUnknown, blending, translucent, missingSize, video,
        ]
        let device = MTLCreateSystemDefaultDevice()
        let genericPixels = generic.flatMap { plan in
            device.flatMap { render(plan, dimension: 4, device: $0) }
        }
        let annotatedPixels = annotated.flatMap { plan in
            device.flatMap { render(plan, dimension: 4, device: $0) }
        }
        let realPixels = real.flatMap { plan in
            device.flatMap { render(plan, dimension: 32, device: $0) }
        }
        let scrollAtZero = stockScroll.flatMap { plan in
            device.flatMap { scrollRow(plan, time: 0, device: $0) }
        }
        let scrollAtOne = stockScroll.flatMap { plan in
            device.flatMap { scrollRow(plan, time: 1, device: $0) }
        }
        var scrollExternal = Options()
        scrollExternal.externalTexture = true
        let result: [String: Any] = [
            "genericAccepted": generic != nil,
            "typedAdapterPlanIdentical":
                planSnapshot(generic) == planSnapshot(typedGeneric),
            "typedFailureCodesStable": typedFailureCodes == [
                "blocked": "graph-blocked",
                "external": "material-texture-slot-unsupported",
                "combo": "material-combo-unsupported",
                "bound": "dynamic-uniform-unsupported",
                "userShader": "dynamic-user-shader-value-unsupported",
                "alphaWriting": "render-state-not-fullscreen-overwrite",
                "alphaWritingUnknown": "render-state-invalid",
                "missingSize": "invalid-mapped-size",
                "video": "unsupported-content-kind",
                "wrongRole": "input-role-mismatch",
                "noannotation": "framebuffer-slot-unproven",
                "unknown": "uniform-source-missing",
                "included": "shader-include-missing",
                "conditional": "shader-color-contract-unproven",
                "annotatedambiguous": "uniform-source-ambiguous",
                "aliascollision": "material-key-collision",
            ],
            "typedFailureMetadataStable": [
                "blocked": failureSnapshot(
                    identity: "effects/generic",
                    root: syntheticRoot,
                    blocker: true
                ),
                "video": failureSnapshot(
                    identity: "effects/generic",
                    root: syntheticRoot,
                    options: video
                ),
                "noannotation": failureSnapshot(
                    identity: "effects/noannotation",
                    root: syntheticRoot
                ),
            ] == [
                "blocked": [
                    "authored-shader", "graph", "graph-blocked",
                    "unsupportedCondition",
                ],
                "video": [
                    "authored-shader", "topology", "unsupported-content-kind",
                    "video",
                ],
                "noannotation": [
                    "authored-shader", "texture-binding",
                    "framebuffer-slot-unproven", "g_Texture0", "slot=0",
                ],
            ],
            "structurallyNotApplicable": structurallyNotApplicable,
            "genericContractPreserved": generic.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.uniformBindings.contains { $0.field.name == "g_Strength" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Daytime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Frametime" }
                    && $0.uniformBindings.contains { $0.field.name == "g_PointerPositionLast" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Screen" }
                    && $0.renderState.matchesFullscreenOverwrite(
                        alphaWriting: .unspecified
                    )
                    && $0.renderState.rawValues.alphaWriting == nil
            } ?? false,
            "annotatedAccepted": annotated != nil,
            "annotatedContractPreserved": annotated.map { plan in
                plan.uniformBindings.contains { binding in
                    guard binding.field.name == "u_Strength",
                          case .constant(let components) = binding.source else {
                        return false
                    }
                    return components == [0.75]
                }
            } ?? false,
            "annotatedFailuresRejected": [
                "annotatedambiguous",
                "annotatedbound",
                "annotatedmissing",
                "aliascollision",
            ].allSatisfy {
                plan(identity: "effects/\($0)", root: syntheticRoot) == nil
            },
            "includeAndComboPrepared": {
                let base = preparedStages(
                    identity: "effects/includedok",
                    root: syntheticRoot
                )
                let variant = preparedStages(
                    identity: "effects/includedok",
                    root: syntheticRoot,
                    options: combo
                )
                return base != nil && variant != nil
                    && base?.cacheKey != variant?.cacheKey
                    && base?.fragment.source != variant?.fragment.source
            }(),
            "expandedExecutionStillGuarded":
                failureCode(
                    identity: "effects/includedok",
                    root: syntheticRoot
                ) == "shader-include-unsupported"
                && failureCode(
                    identity: "effects/generic",
                    root: syntheticRoot,
                    options: combo
                ) == "material-combo-unsupported"
                && failureCode(
                    identity: "effects/conditionalreflection",
                    root: syntheticRoot
                ) == "shader-color-contract-unproven"
                && failureCode(
                    identity: "effects/duplicatedefine",
                    root: syntheticRoot
                ) == "shader-color-contract-unproven"
                && failureCode(
                    identity: "effects/crossdefine",
                    root: syntheticRoot
                ) == "shader-color-contract-unproven",
            "r1LeadingZeroAcceptancePreserved":
                plan(
                    identity: "effects/ambiguousinteger",
                    root: syntheticRoot
                ) != nil,
            "r1SuffixAcceptancePreserved":
                plan(
                    identity: "effects/suffixnumeric",
                    root: syntheticRoot
                ) != nil,
            "boundedPreparationRejectsLeadingZero":
                preparedStages(
                    identity: "effects/ambiguousinteger",
                    root: syntheticRoot
                ) == nil,
            "boundedPreparationRejectsSuffix":
                preparedStages(
                    identity: "effects/suffixnumeric",
                    root: syntheticRoot
                ) == nil,
            "legacyComboSchemaPreserved": plan(
                identity: "effects/legacycomboschema",
                root: syntheticRoot
            ) != nil,
            "graphlessFallbackBounded": {
                let loaded = preparedStages(
                    identity: "effects/generic",
                    root: syntheticRoot
                )
                let fallback = preparedStages(
                    identity: "effects/generic",
                    root: syntheticRoot,
                    graphless: true
                )
                let includedRejected = preparedStages(
                    identity: "effects/includedok",
                    root: syntheticRoot,
                    graphless: true
                ) == nil
                return loaded != nil
                    && loaded?.cacheKey == fallback?.cacheKey
                    && loaded?.vertex.source == fallback?.vertex.source
                    && loaded?.fragment.source == fallback?.fragment.source
                    && includedRejected
            }(),
            "inactiveReflectionFiltered": {
                let base = preparedStages(
                    identity: "effects/conditionalreflection",
                    root: syntheticRoot
                )
                let variant = preparedStages(
                    identity: "effects/conditionalreflection",
                    root: syntheticRoot,
                    options: combo
                )
                let baseNames = base?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                let variantNames = variant?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                return !baseNames.contains("u_Inactive")
                    && variantNames.contains("u_Inactive")
            }(),
            "activeSchemaFixedPoint": {
                let inactive = preparedStages(
                    identity: "effects/inactiveschema",
                    root: syntheticRoot
                )
                let inactiveInclude = preparedStages(
                    identity: "effects/inactiveinclude",
                    root: syntheticRoot
                )
                let included = preparedStages(
                    identity: "effects/includedschema",
                    root: syntheticRoot
                )
                let readinessMissing = preparedStages(
                    identity: "effects/includedreadiness",
                    root: syntheticRoot
                )
                let readinessReady = preparedStages(
                    identity: "effects/includedreadiness",
                    root: syntheticRoot,
                    textureReadiness: [2: true]
                )
                let oscillating = preparedStages(
                    identity: "effects/oscillatingschema",
                    root: syntheticRoot
                )
                let bootstrapped = preparedStages(
                    identity: "effects/bootstrapschema",
                    root: syntheticRoot
                )
                let positiveSelf = preparedStages(
                    identity: "effects/positiveselfschema",
                    root: syntheticRoot
                )
                let explicitPositive = preparedStages(
                    identity: "effects/positiveselfschema",
                    root: syntheticRoot,
                    options: combo
                )
                let mutual = preparedStages(
                    identity: "effects/mutualschema",
                    root: syntheticRoot
                )
                let hiddenSubset = preparedStages(
                    identity: "effects/hiddensubsetschema",
                    root: syntheticRoot
                )
                let mutuallyExclusive = preparedStages(
                    identity: "effects/mutuallyexclusiveschema",
                    root: syntheticRoot
                )
                let readinessSelfMissing = preparedStages(
                    identity: "effects/readinessselfschema",
                    root: syntheticRoot
                )
                let readinessSelfReady = preparedStages(
                    identity: "effects/readinessselfschema",
                    root: syntheticRoot,
                    textureReadiness: [2: true]
                )
                let localAnchor = preparedStages(
                    identity: "effects/localanchorschema",
                    root: syntheticRoot
                )
                let unrelatedGuard = preparedStages(
                    identity: "effects/unrelatedguardschema",
                    root: syntheticRoot
                )
                let explicitUndef = preparedStages(
                    identity: "effects/undefanchorschema",
                    root: syntheticRoot
                )
                let ambiguityBudget = preparationFailureDetails(
                    identity: "effects/ambiguitybudgetschema",
                    root: syntheticRoot
                )
                let ambiguityWorkBudget = preparationFailureDetails(
                    identity: "effects/ambiguityworkbudgetschema",
                    root: syntheticRoot
                )
                let inactiveNames = inactive?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                let includedNames = included?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                let readyNames = readinessReady?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                let bootstrappedNames = bootstrapped?.fragment.activeDeclarations.map {
                    $0.declaration.name
                } ?? []
                return !inactiveNames.contains("u_ShouldStayInactive")
                    && inactiveInclude?.fragment.dependencies.contains {
                        $0.relativePath.hasSuffix("hidden_schema.inc")
                    } == false
                    && includedNames.contains("u_FromIncludedSchema")
                    && readinessMissing == nil
                    && readyNames.contains("u_FromReadyInclude")
                    && oscillating == nil
                    && bootstrappedNames.contains("u_Bootstrapped")
                    && !bootstrappedNames.contains("u_ProvisionalBad")
                    && positiveSelf == nil
                    && preparationFailureDetails(
                        identity: "effects/positiveselfschema",
                        root: syntheticRoot
                    ) == ["shader-variant-invalid", "active-schema-ambiguous"]
                    && explicitPositive != nil
                    && mutual == nil
                    && preparationFailureDetails(
                        identity: "effects/mutualschema",
                        root: syntheticRoot
                    ) == ["shader-variant-invalid", "active-schema-ambiguous"]
                    && hiddenSubset == nil
                    && preparationFailureDetails(
                        identity: "effects/hiddensubsetschema",
                        root: syntheticRoot
                    ) == ["shader-variant-invalid", "active-schema-ambiguous"]
                    && mutuallyExclusive == nil
                    && preparationFailureDetails(
                        identity: "effects/mutuallyexclusiveschema",
                        root: syntheticRoot
                    ) == ["shader-variant-invalid", "active-schema-ambiguous"]
                    && readinessSelfMissing != nil
                    && readinessSelfReady == nil
                    && preparationFailureDetails(
                        identity: "effects/readinessselfschema",
                        root: syntheticRoot,
                        textureReadiness: [2: true]
                    ) == ["shader-variant-invalid", "active-schema-ambiguous"]
                    && localAnchor != nil
                    && unrelatedGuard != nil
                    && explicitUndef != nil
                    && ambiguityBudget == [
                        "shader-variant-invalid", "active-schema-audit-budget",
                    ]
                    && ambiguityWorkBudget == [
                        "shader-variant-invalid", "active-schema-audit-budget",
                    ]
                    && inactive?.colorContract.isResolved == false
                    && inactiveInclude?.colorContract.isResolved == false
                    && included?.colorContract.isResolved == false
                    && readinessReady?.colorContract.isResolved == false
            }(),
            "realAccepted": real != nil,
            "realContractPreserved": real.map {
                $0.framebufferTextureSlots == [0]
                    && $0.mappedSize == CGSize(width: 128, height: 128)
                    && $0.offscreenSize(for: CGSize(width: 128, height: 128)) != nil
                    && $0.uniformBindings.contains { $0.field.name == "g_Time" }
                    && $0.uniformBindings.contains { $0.field.name == "g_Texture0Resolution" }
            } ?? false,
            "scrollProfilesAccepted": [
                stockScroll, relocatedScroll, annotatedScroll,
            ].allSatisfy {
                $0?.profile == .scroll
                    && $0?.framebufferTextureSlots == [0]
                    && $0?.uniformBindings.contains {
                        $0.field.name == "g_Time"
                    } == true
            },
            "scrollInferenceBounded": scrollPlan(
                identity: "effects/scroll",
                definitionPath: "effects/unknown/scroll/effect.json",
                resolvedMaterialPath: "materials/effects/scroll.json",
                root: stockScrollRoot,
                speedX: 0.25,
                speedY: 0
            ) == nil,
            "scrollCompositionRejected": scrollPlan(
                identity: "workshop/3302578859/effects/scroll",
                definitionPath: "effects/workshop/3302578859/scroll/effect.json",
                resolvedMaterialPath:
                    "materials/workshop/3302578859/effects/scroll.json",
                root: relocatedScrollRoot,
                speedX: 0,
                speedY: 0.15,
                options: composition,
                priorInput: false,
                role: .layerSource
            ) == nil,
            "scrollDynamicRejected": scrollPlan(
                identity: "effects/scroll",
                definitionPath: "effects/scroll/effect.json",
                resolvedMaterialPath: "materials/effects/scroll.json",
                root: stockScrollRoot,
                speedX: 0.25,
                speedY: 0,
                bound: true
            ) == nil,
            "scrollRangeRejected": scrollPlan(
                identity: "effects/scroll",
                definitionPath: "effects/scroll/effect.json",
                resolvedMaterialPath: "materials/effects/scroll.json",
                root: stockScrollRoot,
                repeatValue: [0, 1],
                speedX: 3,
                speedY: 0
            ) == nil,
            "scrollExternalTextureRejected": scrollPlan(
                identity: "effects/scroll",
                definitionPath: "effects/scroll/effect.json",
                resolvedMaterialPath: "materials/effects/scroll.json",
                root: stockScrollRoot,
                speedX: 0.25,
                speedY: 0,
                options: scrollExternal
            ) == nil,
            "scrollMovesPositiveXLeft": {
                guard let before = scrollAtZero, let after = scrollAtOne,
                      before.count == 8, after.count == 8 else {
                    return false
                }
                return before != after
                    && (0..<6).allSatisfy { index in
                        after[index] > before[index]
                            && after[index] < before[index + 1]
                    }
            }(),
            "priorAccepted": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                priorInput: true,
                role: .priorEffectOutput
            ) != nil,
            "wrongRoleRejected": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                priorInput: true,
                role: .layerSource
            ) == nil,
            "unsupportedContractsRejected": ["noannotation", "unknown", "included"].allSatisfy {
                plan(identity: "effects/\($0)", root: syntheticRoot) == nil
            },
            "unsupportedMaterialRejected": rejectedOptions.allSatisfy {
                plan(identity: "effects/generic", root: syntheticRoot, options: $0) == nil
            },
            "blockedGraphRejected": plan(
                identity: "effects/generic",
                root: syntheticRoot,
                blocker: true
            ) == nil,
            "genericPixels": genericPixels ?? NSNull(),
            "annotatedPixels": annotatedPixels ?? NSNull(),
            "realPixels": realPixels ?? NSNull(),
            "compileFailureCached": generic.map {
                guard let device else { return false }
                return failureIsCached($0, device: device)
            } ?? false,
            "concurrentCacheSingleAttempt": generic.map {
                guard let device else { return false }
                return concurrentCacheIsSingleAttempt($0, device: device)
            } ?? false,
            "concurrentFailureSingleAttempt": generic.map {
                guard let device else { return false }
                return concurrentFailureIsSingleAttempt($0, device: device)
            } ?? false,
            "unsupportedStateDoesNotAlias": generic.map {
                guard let device else { return false }
                return unsupportedStateDoesNotAlias($0, device: device)
            } ?? false,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


VERTEX_SOURCE = r'''
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
'''


def fragment_source(*, annotation: bool = True, unknown: bool = False) -> str:
    sampler_annotation = (
        ' // {"material":"framebuffer","hidden":true}' if annotation else ""
    )
    extra_uniform = "uniform float g_Unsupported;" if unknown else ""
    return f'''
uniform sampler2D g_Texture0;{sampler_annotation}
uniform float g_Strength;
uniform float g_Daytime;
uniform float g_Frametime;
uniform vec2 g_PointerPositionLast;
uniform vec3 g_Screen;
{extra_uniform}
varying vec2 v_TexCoord;
void main() {{
    vec4 color = texture2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb * g_Strength, color.a);
}}
'''


def annotated_fragment_source(*, alias_collision: bool = False) -> str:
    second_uniform = (
        'uniform float u_Other; // {"material":"Strength label","default":0.25}'
        if alias_collision else ""
    )
    factor = "u_Strength * u_Other" if alias_collision else "u_Strength"
    return f'''
uniform sampler2D g_Texture0; // {{"material":"framebuffer","hidden":true}}
uniform float u_Strength; // {{"material":"Strength label","default":0.5}}
{second_uniform}
varying vec2 v_TexCoord;
void main() {{
    vec4 color = texture2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb * {factor}, color.a);
}}
'''


def included_fragment_source() -> str:
    return r'''
#include "shared.inc"
uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
varying vec2 v_TexCoord;
void main() {
    vec4 color = texture2D(g_Texture0, v_TexCoord);
#if OPTION == 1
    gl_FragColor = vec4(color.rgb, color.a);
#else
    gl_FragColor = vec4(color.rgb * SHARED_SCALE, color.a);
#endif
}
'''


def conditional_reflection_source() -> str:
    return r'''
#if OPTION
uniform float u_Inactive; // {"material":"inactive","default":1}
#endif
''' + fragment_source()


def inactive_schema_source() -> str:
    return r'''
#if SWITCH
uniform float u_HiddenCombo; // [COMBO] {"combo":"HIDDEN","default":1}
uniform float u_Disabled; // [COMBO_OFF] {"combo":"DISABLED","default":1}
uniform sampler2D g_Texture7; // {"combo":"HIDDEN_READINESS"}
uniform float u_Bad; // [COMBO] {broken
#endif
#if HIDDEN
uniform float u_ShouldStayInactive;
#endif
''' + fragment_source()


def included_schema_source() -> str:
    return r'''
#include "schema.inc"
#if INCLUDED_SCHEMA
uniform float u_FromIncludedSchema;
#endif
''' + fragment_source()


def inactive_include_source() -> str:
    return r'''
#if 0
#include "hidden_schema.inc"
#endif
''' + fragment_source()


def included_readiness_source() -> str:
    return r'''
#include "readiness_schema.inc"
#if INCLUDED_READY
uniform float u_FromReadyInclude;
#endif
''' + fragment_source()


def oscillating_schema_source() -> str:
    return r'''
#if !TOGGLE
uniform float u_Toggle; // [COMBO] {"combo":"TOGGLE","default":1}
#endif
''' + fragment_source()


def bootstrap_schema_source() -> str:
    return r'''
uniform float u_Mode; // [COMBO] {"combo":"BOOT_MODE","default":1}
#if BOOT_MODE
uniform float u_Bootstrapped;
#else
uniform float u_ProvisionalBad; // [COMBO] {broken
#endif
''' + fragment_source()


def positive_self_schema_source() -> str:
    return r'''
#if OPTION
uniform float u_Option; // [COMBO] {"combo":"OPTION","default":1}
ACTIVE_OPTION
#else
INACTIVE_OPTION
#endif
''' + fragment_source()


def mutual_schema_source() -> str:
    return r'''
#if FIRST
#include "mutual_schema.inc"
#endif
#if SECOND
uniform float u_First; // [COMBO] {"combo":"FIRST","default":1}
#endif
''' + fragment_source()


def readiness_self_schema_source() -> str:
    return r'''
#if SELF_READY
uniform sampler2D g_Texture2; // {"combo":"SELF_READY"}
#endif
''' + fragment_source()


def mutually_exclusive_schema_source() -> str:
    return r'''
#if !MODE
uniform float u_ModeZero; // [COMBO] {"combo":"MODE","default":0}
#else
uniform float u_ModeOne; // [COMBO] {"combo":"MODE","default":1}
#endif
''' + fragment_source()


def hidden_subset_schema_source() -> str:
    return r'''
#if defined(A)
uniform float u_B0; // [COMBO] {"combo":"B","default":0,"require":{"A":0}}
#endif
#if defined(B)
uniform float u_A0; // [COMBO] {"combo":"A","default":0,"require":{"B":0}}
#endif
#if defined(D)
uniform float u_A2; // [COMBO] {"combo":"A","default":2,"require":{"D":0}}
#endif
#if NEVER
uniform float u_D0; // [COMBO] {"combo":"D","default":0,"require":{"A":0}}
#endif
''' + fragment_source()


def local_anchor_schema_source() -> str:
    return r'''
#define ENABLE_LOCAL 1
#if ENABLE_LOCAL
uniform float u_LocalMode; // [COMBO] {"combo":"LOCAL_MODE","default":1}
#endif
#if LOCAL_MODE
uniform float u_LocalActive;
#endif
''' + fragment_source()


def unrelated_guard_schema_source() -> str:
    return r'''
#if UNKNOWN_FEATURE
uniform float u_Unrelated; // [COMBO] {"combo":"UNRELATED_MODE","default":1}
#endif
''' + fragment_source()


def undef_anchor_schema_source() -> str:
    return r'''
#undef OPTION
#if OPTION
uniform float u_Undefined; // [COMBO] {"combo":"OPTION","default":1}
#endif
''' + fragment_source()


def ambiguity_budget_schema_source() -> str:
    candidates = []
    for index in range(9):
        candidates.append(
            f'''#if UNKNOWN_{index}
uniform float u_Mode{index}; // [COMBO] {{"combo":"MODE_{index}","default":1}}
#endif'''
        )
    return "\n".join(candidates) + fragment_source()


def ambiguity_work_budget_schema_source() -> str:
    candidates = []
    for index in range(8):
        candidates.append(
            f'''#if UNKNOWN_{index}
uniform float u_Work{index}; // [COMBO] {{"combo":"WORK_{index}","default":1}}
#endif'''
        )
    return "\n".join(candidates) + "\n/*" + ("x" * 100_000) + "*/\n" + fragment_source()


class SceneAuthoredShaderExecutionPlannerTests(unittest.TestCase):
    def test_generic_and_real_contracts_share_bounded_admission(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        real_root = sample_cache_root("3141421197")
        if not (real_root / "shaders/effects/myfirstshader.frag").is_file():
            self.skipTest("isolated 3141421197 shader fixture is unavailable")
        scroll_roots = {
            "2974757317": (
                sample_cache_root("2974757317"),
                "shaders/effects/scroll.frag",
            ),
            "3299228616": (
                sample_cache_root("3299228616"),
                "shaders/workshop/3302578859/effects/scroll.frag",
            ),
            "3769688830": (
                sample_cache_root("3769688830"),
                "shaders/workshop/3387825383/effects/scroll.frag",
            ),
        }
        if any(
            not (root / relative_path).is_file()
            for root, relative_path in scroll_roots.values()
        ):
            self.skipTest("isolated Scroll shader fixtures are unavailable")

        with tempfile.TemporaryDirectory(prefix="mwx-authored-shader-planner-") as directory:
            root = Path(directory)
            synthetic_root = root / "synthetic"
            shader_root = synthetic_root / "shaders/effects"
            shader_root.mkdir(parents=True)
            for identity, source in {
                "generic": fragment_source(),
                "annotated": annotated_fragment_source(),
                "annotatedambiguous": annotated_fragment_source(),
                "annotatedbound": annotated_fragment_source(),
                "annotatedmissing": annotated_fragment_source(),
                "aliascollision": annotated_fragment_source(alias_collision=True),
                "noannotation": fragment_source(annotation=False),
                "unknown": fragment_source(unknown=True),
                "included": '#include "missing.inc"\n' + fragment_source(),
                "includedok": included_fragment_source(),
                "conditionalreflection": conditional_reflection_source(),
                "inactiveschema": inactive_schema_source(),
                "inactiveinclude": inactive_include_source(),
                "includedschema": included_schema_source(),
                "includedreadiness": included_readiness_source(),
                "oscillatingschema": oscillating_schema_source(),
                "bootstrapschema": bootstrap_schema_source(),
                "positiveselfschema": positive_self_schema_source(),
                "mutualschema": mutual_schema_source(),
                "hiddensubsetschema": hidden_subset_schema_source(),
                "mutuallyexclusiveschema": mutually_exclusive_schema_source(),
                "readinessselfschema": readiness_self_schema_source(),
                "localanchorschema": local_anchor_schema_source(),
                "unrelatedguardschema": unrelated_guard_schema_source(),
                "undefanchorschema": undef_anchor_schema_source(),
                "ambiguitybudgetschema": ambiguity_budget_schema_source(),
                "ambiguityworkbudgetschema": ambiguity_work_budget_schema_source(),
                "duplicatedefine": "#define DUPLICATE 1\n#define DUPLICATE 1\n"
                    + fragment_source(),
                "crossdefine": "#define CROSS_STAGE 2\n" + fragment_source(),
                "ambiguousinteger": "#define AMBIGUOUS 010\n" + fragment_source(),
                "suffixnumeric": "#define INTEGER_SUFFIX 1u\n#define FLOAT_SUFFIX 1.0f\n"
                    + fragment_source(),
                "legacycomboschema": '// [COMBO] {"combo":"LEGACY_DEFAULT","default":1}\n'
                    + fragment_source(),
            }.items():
                (shader_root / f"{identity}.vert").write_text(
                    textwrap.dedent(VERTEX_SOURCE), encoding="utf-8"
                )
                (shader_root / f"{identity}.frag").write_text(
                    textwrap.dedent(source), encoding="utf-8"
                )
            (shader_root / "crossdefine.vert").write_text(
                "#define CROSS_STAGE 1\n" + textwrap.dedent(VERTEX_SOURCE),
                encoding="utf-8",
            )
            (synthetic_root / "shaders/shared.inc").write_text(
                "#define SHARED_SCALE 0.5\n",
                encoding="utf-8",
            )
            (synthetic_root / "shaders/schema.inc").write_text(
                '// [COMBO] {"combo":"INCLUDED_SCHEMA","default":1}\n',
                encoding="utf-8",
            )
            (synthetic_root / "shaders/hidden_schema.inc").write_text(
                'uniform float u_Disabled; // [COMBO_OFF] {"combo":"DISABLED","default":1}\n'
                'uniform sampler2D g_Texture7; // {"combo":"HIDDEN_READINESS"}\n'
                'uniform float u_Bad; // [COMBO] {broken\n',
                encoding="utf-8",
            )
            (synthetic_root / "shaders/readiness_schema.inc").write_text(
                'uniform sampler2D g_Texture2; // {"combo":"INCLUDED_READY"}\n',
                encoding="utf-8",
            )
            (synthetic_root / "shaders/mutual_schema.inc").write_text(
                'uniform float u_Second; // [COMBO] {"combo":"SECOND","default":1}\n',
                encoding="utf-8",
            )

            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "authored-shader-planner"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness), "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [
                    str(binary),
                    str(real_root),
                    str(synthetic_root),
                    *(str(scroll_roots[sample_id][0]) for sample_id in (
                        "2974757317", "3299228616", "3769688830",
                    )),
                ],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

        result = json.loads(completed.stdout)
        boolean_contracts = {
            key: value for key, value in result.items()
            if key not in {"genericPixels", "annotatedPixels", "realPixels"}
        }
        self.assertTrue(all(boolean_contracts.values()), result)
        generic_pixels = result["genericPixels"]
        self.assertIsInstance(generic_pixels, dict, result)
        self.assertEqual(generic_pixels["minimumRGB"], 191, result)
        self.assertEqual(generic_pixels["maximumRGB"], 191, result)
        self.assertEqual(generic_pixels["alphaMinimum"], 255, result)
        self.assertEqual(generic_pixels["compilationAttempts"], 1, result)
        annotated_pixels = result["annotatedPixels"]
        self.assertIsInstance(annotated_pixels, dict, result)
        self.assertEqual(annotated_pixels["minimumRGB"], 191, result)
        self.assertEqual(annotated_pixels["maximumRGB"], 191, result)
        self.assertEqual(annotated_pixels["alphaMinimum"], 255, result)
        self.assertEqual(annotated_pixels["compilationAttempts"], 1, result)
        real_pixels = result["realPixels"]
        self.assertIsInstance(real_pixels, dict, result)
        self.assertGreater(real_pixels["maximumRGB"], 0, result)
        self.assertGreater(real_pixels["distinctRGB"], 1, result)
        self.assertLess(real_pixels["averageRGB"], 250, result)
        self.assertEqual(real_pixels["alphaMinimum"], 255, result)
        self.assertEqual(real_pixels["compilationAttempts"], 1, result)


if __name__ == "__main__":
    unittest.main()
