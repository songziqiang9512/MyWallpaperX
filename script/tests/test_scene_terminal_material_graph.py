"""Production terminal replay retains input and rasterizes authored overflow.

Overflow cases use the existing bounded route: the bare Swift carrier has no
signed compiler license bundle. They exercise real Program/Metal output, not
App generic compilation, text rasterization, or FramePreflight admission.
Named cases use the production capability/finalizer and same-frame reserved
publication; the unequal provider remains a read-only input to terminal replay.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import unittest
from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests import test_scene_resolved_material_graph_executor as graph_fixture
from script.tests import test_scene_effect_draw_alpha as alpha_fixture


# Reuse the graph/compiler scaffold. Only the input shader and extent change.
HELPERS = graph_fixture.HARNESS.split('@main', 1)[0]
HELPERS = HELPERS.replace('Plan.PixelExtent(width: 2, height: 2)',
                          'Plan.PixelExtent(width: 10, height: 10)')
HELPERS = HELPERS.replace('precondition(graph.effects.count >= 2)',
                          'precondition(!graph.effects.isEmpty)', 1)
HELPERS = HELPERS.replace('private let vertexSource = """\n',
    'private let vertexSource = """\nuniform mat4 g_ModelViewProjectionMatrix;\n', 1)
HELPERS = HELPERS.replace('gl_Position = vec4(a_Position, 1.0);',
    'gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);', 1)
HELPERS = HELPERS.replace('explicitPreviousSampler: explicitPreviousSampler\n    )', r'''
        explicitPreviousSampler: explicitPreviousSampler,
        fragmentOverride: namedProvider != nil ? """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1;
        void main() {
            gl_FragColor = mix(texSample2D(g_Texture0, v_TexCoord),
                texSample2D(g_Texture1, vec2(fract(v_TexCoord.x * 64.0), v_TexCoord.y)), 0.5);
        }
        """ : """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            \(node.nodeIndex == 0
                ? "color.rgb *= step(0.5, fract(v_TexCoord.x * 64.0));" : "")
            gl_FragColor = color;
        }
        """
    )''', 1)

# Replace publication-only adapters with the production pool/cache/residency.
PUBLICATION_SUPPORT = graph_fixture.PUBLICATION_FIXTURE['SUPPORT']
SUPPORT = graph_fixture.SUPPORT.replace(PUBLICATION_SUPPORT,
    PUBLICATION_SUPPORT.rsplit('final class SceneOffscreenTexturePool {', 1)[0], 1)
SUPPORT = SUPPORT.replace('''final class SceneGraphRenderTargetResidencyPin {
    func release() {}
}
''', '', 1)
SUPPORT = SUPPORT.replace(SUPPORT[SUPPORT.index('final class ScenePreparedPersistentGraphTargets {'):
    SUPPORT.index('extension SceneResolvedMaterialExecutionCapabilityCatalog {')], '', 1)
# Reuse the existing production FrameInputs/copy carrier. The convenience
# initializer only supplies fixture defaults; withDependencyEffects is real.
FRAME_SOURCE = alpha_fixture.finalizer_fixture.SCENE_ROOT / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
frame_support = alpha_fixture.runtime_frame_support()
frame_start = frame_support.index('struct SceneAudioSpectrumSnapshot { static let silent = Self() }')
frame_end = frame_support.index('\nstruct SceneDependencyEffectInput', frame_start)
actual_frame = frame_support[frame_start:frame_end].replace(
    'effectDrawColor: SIMD3<Float> = .init(repeating: 1)) {',
    'effectDrawColor: SIMD3<Float> = .init(repeating: 1),\n'
    '        effectOutputModelViewProjection: simd_float4x4 = matrix_identity_float4x4,\n'
    '        terminalReplayModelViewProjection: simd_float4x4? = nil) {', 1)
actual_frame = actual_frame.replace(
    'effectOutputModelViewProjection: matrix_identity_float4x4,',
    'effectOutputModelViewProjection: effectOutputModelViewProjection,\n'
    '            terminalReplayModelViewProjection: terminalReplayModelViewProjection,', 1)
frame_start = SUPPORT.index('final class SceneResolvedMaterialRuntimeBridge {')
frame_end = SUPPORT.index('\nstruct SceneDependencyEffectInput', frame_start)
SUPPORT = SUPPORT[:frame_start] + actual_frame + SUPPORT[frame_end:]

HARNESS = HELPERS + r'''
private func terminalChain(_ count: Int) -> Graph {
    let full = chainedGraph()
    let effects = Array(full.effects.prefix(count))
    return .init(layerID: full.layerID, effects: effects, renderTargets: [],
        nodes: Array(full.nodes.prefix(count)), finalOutput: effects.last!.output, blockers: [])
}

private func dependencySizingChecks(
    _ capability: SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability,
    binding: SceneDependencyRenderPlan.Binding
) -> [String: Bool] {
    func supports(_ ownership: SceneResolvedMaterialDependencyOwnership) -> Bool {
        let admitted = SceneResolvedMaterialAdmittedLayer(layerID: capability.layerID,
            products: capability.admittedProducts, pairPlan: capability.pairPlan,
            dependencyOwnership: ownership, sourceRoute: capability.sourceRoute,
            isVisibleExecutionRoot: capability.isVisibleExecutionRoot,
            isGraphOutputProvider: capability.isGraphOutputProvider,
            requiresGraphOutputProvider: capability.requiresGraphOutputProvider)
        let sizing = SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability.solidEffectSizingCapabilities(
            admitted: admitted, stages: capability.stages, materials: capability.materials,
            dependencyOwnership: ownership, sceneBackgroundRequirement: capability.sceneBackgroundRequirement)
        return sizing.intermediates || sizing.terminal
    }
    let geometry = SceneDependencyRenderPlan.Binding(consumerLayerID: binding.consumerLayerID,
        providerLayerID: binding.providerLayerID, slot: binding.slot, blendMode: 0,
        kind: .geometryLayer, requiresResolvedMaterialProgram: true)
    let advanced = SceneDependencyRenderPlan.Binding(consumerLayerID: binding.consumerLayerID,
        providerLayerID: binding.providerLayerID, slot: binding.slot, blendMode: 30, kind: binding.kind)
    let other = SceneDependencyRenderPlan.Binding(consumerLayerID: binding.consumerLayerID,
        providerLayerID: binding.providerLayerID + 1,
        slot: .init(effectID: binding.slot.effectID, passIndex: 0, slotIndex: 2),
        blendMode: 0, kind: binding.kind)
    let aggregate = SceneDependencyRenderPlan.MultiProviderAggregate(consumerLayerID: binding.consumerLayerID,
        bindings: [binding, other], authoredSlotOrder: [binding.slot, other.slot])
    return ["ordinaryExternalAccepted": supports(.externalPrimary(binding)),
        "geometryDependencyRejected": !supports(.externalPrimary(geometry)),
        "advancedDependencyBlendRejected": !supports(.externalPrimary(advanced)),
        "internalDependencyRejected": !supports(.graphInternal(referenceCount: 1)),
        "aggregateDependencyRejected": !supports(.externalAggregate(aggregate))]
}

private func overflowCase(
    device: MTLDevice, queue: MTLCommandQueue, skew: Float, offset: Float,
    alpha: Float = 1, probeX: Int, probeY: Int, attachmentReplay: Bool? = nil
) throws -> [String: Any] {
    // Match the existing bare-Swift effect host gate; no Program is manufactured.
    let previousRoute = getenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES").map { String(cString: $0) }
    setenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", "ordinary-shader=disable-generic", 1)
    defer {
        if let previousRoute { setenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES", previousRoute, 1) }
        else { unsetenv("MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES") }
    }
    let graph = terminalChain(1), admitted = orderedLayerGraph(graph), node = graph.nodes[0]
    let base = template(for: node)
    let original = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
            vec4 color = texSample2D(g_Texture0, v_TexCoord);
            gl_FragColor = color;
        }
        """)
    let stages = original.stages.map { stage -> SceneShaderContract.Stage in
        guard stage.kind == .vertex else { return stage }
        let source = stage.source.replacingOccurrences(
            of: "gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);",
            with: "vec3 point = a_Position; point.x += \(skew) * point.y + \(offset); "
                + "gl_Position = mul(vec4(point, 1.0), g_ModelViewProjectionMatrix);")
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: stage.relativePath)
        return .init(kind: stage.kind, relativePath: stage.relativePath, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let sourceGraph = SceneShaderSourceGraph(roots: stages.map {
        .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
    }, nodes: stages.map {
        .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
            rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
    }, edges: [], diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(stages))
    let shader = SceneShaderContract(identity: original.identity, sourceKind: original.sourceKind,
        stages: stages, diagnostics: [], canonicalSHA256: SceneShaderStableDigest.hash(stages),
        sourceGraph: sourceGraph)
    let custom = Template.validated(textureSlots: base.textureSlots, combos: [], uniformDeclarations: [],
        renderState: base.renderState, graphRole: base.graphRole, shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: node.nodeIndex, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
    let catalog = SceneResolvedMaterialRuntimeCatalog(entries: [
        .init(effect: node.effect, nodeIndex: node.nodeIndex): .template(custom)
    ], resourceDemandIssues: [])
    let caps = capabilities(admitted, catalog: catalog)
    guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
          let executor = Executor(device: device, capabilities: caps),
          let leases = makeChainedLeases(capability, device: device) else {
        return ["failure": "overflow-setup", "reports": caps.reportLines]
    }
    let channel = UInt8((alpha * 255).rounded())
    let source = makeSource(device, width: 10, height: 10, bgra: [0, 0, channel, channel])
    let replayTarget = makeSource(device, width: 64, height: 64, usage: [.renderTarget])
    let graphTarget = makeSource(device, width: 64, height: 64, usage: [.renderTarget])
    // targetPixels supplies a_Position in [-5,5]; terminal replay converts it
    // back to the unit quad through the production render-size binding.
    var placement = matrix_identity_float4x4
    var rasterPlacement: simd_float4x4?
    if let attachmentReplay {
        // Distinct nonoverlapping destinations: world center at pixel16,16;
        // attachment center at48,48. No camera or world chain is compensated.
        placement.columns.0.x = 0.5; placement.columns.1.y = 0.5
        placement.columns.3.x = -0.5; placement.columns.3.y = 0.5
        if attachmentReplay {
            var raster = placement
            raster.columns.3.x = 0.5; raster.columns.3.y = -0.5
            rasterPlacement = raster
        }
    }
    let originalInputs = SceneResolvedMaterialRuntimeBridge.FrameInputs(
        effectOutputModelViewProjection: placement,
        terminalReplayModelViewProjection: rasterPlacement)
    let copiedInputs = originalInputs.withDependencyEffects([])
    let command = queue.makeCommandBuffer()!
    let prepared = try executor.prepare(token: claim.token, leases: leases,
        historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
        sourceUniforms: .neutral(), sourcePipeline: makeSourcePipeline(device),
        terminalReplayTarget: replayTarget,
        frameInputs: copiedInputs, commandBuffer: command,
        previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1).get()
    let weightsSourceAlpha = prepared.finalResource.publication.candidate.content
        == .color(.resolved(.straightAlpha))
    var graphUniforms = SceneLayerFragmentUniforms.neutral()
    graphUniforms.sourceSampling.y = weightsSourceAlpha ? 1 : 0
    guard let compositor = makeProductionSourcePipeline(device)
    else { return ["failure": "overflow-compositor-pipeline"] }
    let encoded = executor.encode(prepared, commandBuffer: command)
    let clear = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
    let graphMain = SceneMainPassEncoder(commandBuffer: command, target: graphTarget,
        clearColor: clear, clearEnabled: true)
    let graphDraw = graphMain.encodePreparedDraw { _, _ in
        { encoder in
            compositor.bind(encoder: encoder)
            compositor.drawLayer(texture: prepared.finalTexture, mvp: placement,
                uniforms: graphUniforms, encoder: encoder)
        }
    }
    let graphFinished = graphMain.finishEnsuringClear()
    let replayMain = SceneMainPassEncoder(commandBuffer: command, target: replayTarget,
        clearColor: clear, clearEnabled: true)
    let replayDraw = executor.encodeTerminalReplay(prepared, mainPass: replayMain, commandBuffer: command)
    let replayFinished = replayMain.finishEnsuringClear()
    guard let textureRead = appendReadback(prepared.finalTexture, commandBuffer: command),
          let graphRead = appendReadback(graphTarget, commandBuffer: command),
          let replayRead = appendReadback(replayTarget, commandBuffer: command) else {
        return ["failure": "overflow-readback"]
    }
    command.commit(); command.waitUntilCompleted()
    let graphProbe = graphRead.pixel(x: probeX, y: probeY)
    let replayProbe = replayRead.pixel(x: probeX, y: probeY)
    let center = replayRead.pixel(x: 32, y: 32)
    let expected: [UInt8] = alpha == 1 ? [0, 0, 255, 255] : [128, 0, 128, 255]
    let blue: [UInt8] = [255, 0, 0, 255]
    if let attachmentReplay {
        let red: [UInt8] = [0, 0, 255, 255]
        let graphWorld = graphRead.pixel(x: 16, y: 16)
        let graphAttachment = graphRead.pixel(x: 48, y: 48)
        let replayWorld = replayRead.pixel(x: 16, y: 16)
        let replayAttachment = replayRead.pixel(x: 48, y: 48)
        let copiedRasterMatches: Bool
        if let rasterPlacement, let copied = copiedInputs.terminalReplayModelViewProjection {
            copiedRasterMatches = copied == rasterPlacement
        } else {
            copiedRasterMatches = rasterPlacement == nil
                && copiedInputs.terminalReplayModelViewProjection == nil
        }
        return ["override": attachmentReplay,
            "graphWorldPixel": graphWorld, "graphAttachmentPixel": graphAttachment,
            "replayWorldPixel": replayWorld, "replayAttachmentPixel": replayAttachment,
            "results": ["graphEncoded": encoded,
                "terminalReplayAvailable": prepared.terminalMaterialReplay != nil,
                "bothMainDrawsEncoded": graphDraw && replayDraw && graphFinished && replayFinished,
                "gpuCompleted": command.status == .completed && command.error == nil,
                "worldPlacementRetained": copiedInputs.effectOutputModelViewProjection == placement,
                "rasterOptionalSurvivesDependencyCopy": copiedRasterMatches,
                "dependencyReplacementIsEmpty": copiedInputs.dependencyEffects.isEmpty,
                "graphStillUsesWorld": matches(graphWorld, red) && matches(graphAttachment, blue),
                "terminalUsesExpectedAttachment": matches(replayWorld, attachmentReplay ? blue : red)
                    && matches(replayAttachment, attachmentReplay ? red : blue),
                "nilRetainsLegacyPixels": attachmentReplay || replayRead.allPixels == graphRead.allPixels,
                "backgroundPreserved": matches(replayRead.pixel(x: 1, y: 1), blue),
                "sourceExtentRetained": source.width == 10 && source.height == 10
                    && prepared.finalTexture.width == 10 && prepared.finalTexture.height == 10,
                "noFallback": prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil }]]
    }
    let identity = skew == 0 && offset == 0
    return ["skew": skew, "offset": offset, "alpha": alpha, "probe": [probeX, probeY],
        "graphProbe": graphProbe, "replayProbe": replayProbe, "expected": expected,
        "center": center, "graphCenter": graphRead.pixel(x: 32, y: 32),
        "graphExtent": [textureRead.width, textureRead.height],
        "failureReasons": prepared.stages.map { $0.effectLocalFailureReasonCode ?? "none" },
        "graphSourceAlphaWeighted": weightsSourceAlpha,
        "capabilityReports": caps.reportLines,
        "results": ["graphEncoded": encoded, "terminalReplayAvailable": prepared.terminalMaterialReplay != nil,
            "bothMainDrawsEncoded": graphDraw && replayDraw && graphFinished && replayFinished,
            "gpuCompleted": command.status == .completed && command.error == nil,
            "sourceExtentRetained": source.width == 10 && source.height == 10
                && prepared.finalTexture.width == 10 && prepared.finalTexture.height == 10,
            "graphClipsOriginalRectangle": matches(graphProbe, blue),
            "terminalPreservesOverflow": matches(replayProbe, identity ? blue : expected),
            "healthyCenter": matches(center, expected),
            "healthyGraphCenter": matches(graphRead.pixel(x: 32, y: 32), expected),
            "identityMatchesGraph": !identity || replayRead.allPixels == graphRead.allPixels,
            "backgroundPreserved": matches(replayRead.pixel(x: 1, y: 1), blue),
            "noFallback": prepared.stages.allSatisfy { $0.effectLocalFailureReasonCode == nil }]]
}

private func terminalCase(
    device: MTLDevice, queue: MTLCommandQueue, count: Int,
    inactive: Set<Int> = [], failed: Set<Int> = [], budget: Int = 4096,
    named: Bool = false
) throws -> [String: Any] {
    let graph = terminalChain(count), admitted = orderedLayerGraph(graph)
    let targets = graph.effects.map {
        SceneDynamicTarget.effectVisibility(layerID: layerID, effectIndex: $0.key.effectIndex)
    }
    let reference = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
    let binding = SceneDependencyRenderPlan.Binding(consumerLayerID: layerID,
        providerLayerID: reference.providerLayerID,
        slot: .init(effectID: graph.effects[0].key.descriptorID, passIndex: 0, slotIndex: 1),
        blendMode: 0, kind: .resolvedMaterial)
    let caps = capabilities(admitted, catalog: catalog(for: graph,
        namedProvidersByNode: named ? [0: reference] : [:]), dynamicProducers: .init(
        userProperties: Set(targets.enumerated().map {
            SceneDynamicUserPropertyProducer(propertyKey: "show\($0.offset)",
                target: $0.element, valueType: .bool)
        }), authoredFallbackTargets: Set(targets), timelineTargets: [], sceneScriptTargets: []),
        namedProvider: named ? reference : nil, dependencyBinding: named ? binding : nil)
    guard let claim = caps.claim(admitted), let capability = caps.resolve(claim.token),
          let executor = Executor(device: device, capabilities: caps),
          let leases = makeChainedLeases(capability, device: device) else {
        throw NSError(domain: "terminal-fixture", code: 1)
    }
    let source = makeSource(device, width: named ? 10 : 1, height: named ? 10 : 1)
    let pipeline = makeSourcePipeline(device)
    let providerRow: [UInt8] = (0..<7).flatMap { x in
        [UInt8(64), 128, x < 3 ? 0 : 255, 255]
    }
    let providerPixels = (0..<3).flatMap { _ in providerRow }
    let provider = makeSource(device, width: 7, height: 3,
        usage: [.shaderRead, .renderTarget], pixelsBGRA: providerPixels)
    let resource = SceneFrameTextureResource.reservedNamedLayerTarget(
        reference: reference, frameEpoch: 1, texture: provider)!
    let dependencies: [SceneDependencyEffectInput] = named ? [.init(
        consumerLayerID: binding.consumerLayerID, providerLayerID: binding.providerLayerID,
        slot: binding.slot, frameEpoch: 1, texture: provider,
        namedReference: reference, reservedMaterialResource: resource)] : []
    let target = makeSource(device, width: 256, height: 64, usage: [.renderTarget])
    let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .bgra8Unorm,
        residentByteBudget: budget)
    func prepare(_ command: MTLCommandBuffer, active: Bool) throws -> Executor.PreparedGraph {
        let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
            definitions: targets.map { .init(target: $0, valueType: .bool, authoredValue: .bool(true)) },
            userValues: Dictionary(uniqueKeysWithValues: targets.enumerated().map {
                ($0.element, SceneDynamicValue.bool(active || !inactive.contains($0.offset)))
            })).snapshot
        return try executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: frame(1), sourceTexture: source,
            sourceUniforms: .neutral(), sourcePipeline: pipeline, terminalReplayTarget: target,
            pool: pool, frameInputs: .init(dependencyEffects: dependencies, dynamicValues: dynamic),
            commandBuffer: command,
            previousStates: [:], previousGraphResources: [:], effectGeneration: 1,
            resetGeneration: 1).get()
    }
    if !failed.isEmpty {
        let warm = try prepare(queue.makeCommandBuffer()!, active: true)
        for index in failed {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "terminal tail regression"),
                preparedKey: warm.stages[index].programCacheKeys[0])
        }
    }
    let command = queue.makeCommandBuffer()!, prepared = try prepare(command, active: false)
    let main = SceneMainPassEncoder(commandBuffer: command, target: target,
        clearColor: .init(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
    let lastActive = (0..<count).last { !inactive.contains($0) && !failed.contains($0) }
    var originalReadback: Readback?
    let copyBefore = ScenePerformanceCounterHub.shared.snapshot()[.textureCopyPasses]!
    let encoded = executor.encode(prepared, commandBuffer: command,
        stageBoundaryObserver: { index, _, buffer in
            if index == lastActive {
                originalReadback = appendReadback(leases[index].table.inputTexture, commandBuffer: buffer)
            }
            return true
        })
    let copyCount = ScenePerformanceCounterHub.shared.snapshot()[.textureCopyPasses]! - copyBefore
    let snapshotTexture: MTLTexture? = pool.allocationCache.locked {
        guard let entry = pool.allocationCache.residents[.current(.terminalInput(
            layerID: layerID, slot: 0, width: 10, height: 10))],
              case let .composition(texture, _) = entry.allocation else { return nil }
        return texture
    }
    let snapshotReadback = snapshotTexture.flatMap { appendReadback($0, commandBuffer: command) }
    let providerReadback = named ? appendReadback(provider, commandBuffer: command) : nil
    let pinsBeforeCompletion = pool.allocationCache.locked {
        pool.allocationCache.residents.values.reduce(0) { $0 + $1.submissionPins.count }
    }
    let wrongCommandRejected = !executor.encodeTerminalReplay(prepared,
        mainPass: main, commandBuffer: queue.makeCommandBuffer()!)
    let hasReplay = prepared.terminalMaterialReplay != nil
    let replayEncoded = hasReplay ? executor.encodeTerminalReplay(prepared,
        mainPass: main, commandBuffer: command) : main.encodePreparedDraw { _, _ in
            { encoder in
                pipeline.bind(encoder: encoder)
                pipeline.drawLayer(texture: prepared.finalTexture, mvp: matrix_identity_float4x4,
                    uniforms: .neutral(), encoder: encoder)
            }
        }
    let finished = main.finishEnsuringClear()
    command.commit(); command.waitUntilCompleted()
    var bytes = [UInt8](repeating: 0, count: 256 * 64 * 4)
    target.getBytes(&bytes, bytesPerRow: 256 * 4,
        from: MTLRegionMake2D(0, 0, 256, 64), mipmapLevel: 0)
    let red = (64..<192).map { Int(bytes[(32 * 256 + $0) * 4 + 2]) }
    let peakX = red.indices.max { red[$0] < red[$1] }! + 64
    let peakPixel = Array(bytes[(32 * 256 + peakX) * 4..<(32 * 256 + peakX) * 4 + 4])
    // A missing/blank/replaced named input changes G and B even when the red
    // stripe-density oracle still passes. Both inputs have alpha one, so the
    // 50% mix has B=32/G=64/alpha=255 while R varies between 128 and
    // 255. The named UV repeats provide the high-frequency stripe input.
    let namedColorSurvives = !named || ((red.max() ?? 0) > 200 && (64..<192).allSatisfy { x in
        let pixel = (32 * 256 + x) * 4
        return abs(Int(bytes[pixel]) - 32) <= 1
            && abs(Int(bytes[pixel + 1]) - 64) <= 1
            && bytes[pixel + 3] == 255
    })
    let providerUnchanged = !named || (providerReadback?.width == 7 && providerReadback?.height == 3
        && providerReadback?.allPixels == (0..<3).map { _ in providerRow })
    let threshold = named ? 191 : 127
    let transitions = zip(red, red.dropFirst()).filter { ($0 > threshold) != ($1 > threshold) }.count
    let bypassCount = inactive.union(failed).count
    let expectedPins = lastActive != nil && bypassCount > 0 && budget > 0 ? 1 : 0
    let highDensity = lastActive == 0 && hasReplay
    let snapshotMatches = expectedPins == 0 || (snapshotReadback != nil && originalReadback != nil
        && snapshotReadback!.allPixels == originalReadback!.allPixels)
    let snapshotDistinct: Bool
    if let snapshotTexture, let lastActive {
        snapshotDistinct = snapshotTexture !== leases[lastActive].table.inputTexture
            && snapshotTexture.pixelFormat == .bgra8Unorm && snapshotTexture.width == 10
            && snapshotTexture.height == 10 && snapshotTexture.mipmapLevelCount == 1
    } else { snapshotDistinct = expectedPins == 0 }
    prepared.terminalInputPins.forEach { $0.release() }

    // The same still-unsubmitted buffer/main pass isolates reset rejection.
    let staleCommand = queue.makeCommandBuffer()!
    let stale = try prepare(staleCommand, active: true)
    let staleMain = SceneMainPassEncoder(commandBuffer: staleCommand, target: target,
        clearColor: .init(red: 0, green: 0, blue: 1, alpha: 1), clearEnabled: true)
    executor.reset()
    let staleRejected = !executor.encodeTerminalReplay(stale, mainPass: staleMain,
        commandBuffer: staleCommand)
    stale.terminalInputPins.forEach { $0.release() }
    return ["transitions": transitions, "copyCount": copyCount,
        "pinCount": prepared.terminalInputPins.count, "snapshotPixels": snapshotReadback?.allPixels ?? [],
        "providerExtent": named ? [provider.width, provider.height] : [],
        "peakPixel": peakPixel, "providerFirstPixel": providerReadback?.firstPixel ?? [],
        "failureReasons": prepared.stages.map { $0.effectLocalFailureReasonCode ?? "none" },
        "dependencySizing": named ? dependencySizingChecks(capability, binding: binding) : [:],
        "results": ["chainAdmitted": capability.supportsTerminalMaterialReplay,
            "exactExternalPrimaryAdmitted": !named || capability.dependencyOwnership == .externalPrimary(binding),
            "namedColorSurvives": namedColorSurvives, "namedProviderUnchanged": providerUnchanged,
            "sourceRemainsTenPixels": prepared.stages.allSatisfy {
                $0.inputWidth == 10 && $0.inputHeight == 10
            } && prepared.finalTexture.width == 10 && prepared.finalTexture.height == 10,
            "lastActiveDensity": lastActive == nil ? transitions == 0
                : highDensity ? transitions >= 120 : (1...20).contains(transitions),
            "sourceOrStripesPresent": lastActive == nil ? red.allSatisfy { $0 == 255 }
                : red.min()! < (named ? 160 : 16) && red.max()! > 239,
            "noActiveMaterialUsesGraph": lastActive != nil || (!hasReplay
                && prepared.terminalInputPins.isEmpty && snapshotTexture == nil),
            "necessaryCopiesOnly": copyCount == UInt64(bypassCount + expectedPins),
            "necessaryPinsOnly": prepared.terminalInputPins.count == expectedPins,
            "snapshotIsExactRealInput": snapshotMatches && snapshotDistinct,
            "pinHeldUntilCompletion": pinsBeforeCompletion == expectedPins,
            "budgetFailureUsesGraph": budget > 0 || (!hasReplay && expectedPins == 0),
            "activationIsLocal": inactive.allSatisfy {
                prepared.stages[$0].effectLocalActivationBypassReasonCode != nil
            }, "failureIsLocal": failed.allSatisfy {
                prepared.stages[$0].effectLocalFailureReasonCode == "material-pass-preparation-library-compilation"
            }, "graphEncoded": encoded, "terminalOrFallbackEncoded": replayEncoded,
            "mainFinished": finished, "gpuCompleted": command.status == .completed && command.error == nil,
            "outsideBackgroundPreserved": bytes[(32*256 + 10)*4] == 255
                && bytes[(32*256 + 10)*4 + 2] == 0,
            "wrongCommandRejected": wrongCommandRejected, "stalePreparationRejected": staleRejected]]
}

@main struct TerminalRasterHarness {
 static func main() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
        print("{\"metalAvailable\":false}"); return
    }
    let rows: [String: [String: Any]] = [
        "single": try terminalCase(device: device, queue: queue, count: 1),
        "singleInactive": try terminalCase(device: device, queue: queue, count: 1, inactive: [0]),
        "active": try terminalCase(device: device, queue: queue, count: 2),
        "inactive": try terminalCase(device: device, queue: queue, count: 2, inactive: [1]),
        "failed": try terminalCase(device: device, queue: queue, count: 2, failed: [1]),
        "twoInactive": try terminalCase(device: device, queue: queue, count: 3, inactive: [1,2]),
        "identityThenInactive": try terminalCase(device: device, queue: queue, count: 3, inactive: [2]),
        "snapshotBudgetRejected": try terminalCase(device: device, queue: queue, count: 2,
            inactive: [1], budget: 0)]
    let overflow = [
        "positiveSkew": try overflowCase(device: device, queue: queue, skew: 0.75, offset: 2.5,
            probeX: 50, probeY: 22),
        "negativeSkew": try overflowCase(device: device, queue: queue, skew: -0.75, offset: -2.5,
            probeX: 13, probeY: 22),
        "offset": try overflowCase(device: device, queue: queue, skew: 0, offset: 2.5,
            probeX: 50, probeY: 32),
        "identity": try overflowCase(device: device, queue: queue, skew: 0, offset: 0,
            probeX: 50, probeY: 32),
        "halfAlpha": try overflowCase(device: device, queue: queue, skew: 0.75, offset: 2.5,
            alpha: 0.5, probeX: 50, probeY: 22)]
    let attachment = [
        "localRaster": try overflowCase(device: device, queue: queue, skew: 0, offset: 0,
            probeX: 48, probeY: 48, attachmentReplay: true),
        "nilWorld": try overflowCase(device: device, queue: queue, skew: 0, offset: 0,
            probeX: 16, probeY: 16, attachmentReplay: false)]
    let named = [
        "active": try terminalCase(device: device, queue: queue, count: 2, named: true),
        "inactive": try terminalCase(device: device, queue: queue, count: 2, inactive: [1], named: true),
        "failed": try terminalCase(device: device, queue: queue, count: 2, failed: [1], named: true)]
    let data = try JSONSerialization.data(withJSONObject:
        ["metalAvailable": true, "rows": rows, "overflow": overflow, "named": named,
            "attachment": attachment], options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
 }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'swiftc is required')
class TerminalMaterialGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sources = graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES']
        graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES'] = list(dict.fromkeys(
            sources + pool_fixture.SWIFT_SOURCES))
        try:
            compilation, run = graph_fixture.compile_lit_harness(SUPPORT, HARNESS)
        finally:
            graph_fixture.CONTRACT_FIXTURE['SWIFT_SOURCES'] = sources
        if destination := os.environ.get('MWX_TERMINAL_GRAPH_EVIDENCE'):
            root = Path(destination)
            root.mkdir(parents=True, exist_ok=True)
            (root/'compile.log').write_text(compilation.stderr)
            if run is not None:
                (root/'result.json').write_text(run.stdout)
                (root/'runtime.log').write_text(run.stderr)
            (root/'Support.swift').write_text(SUPPORT)
            (root/'Harness.swift').write_text(HARNESS)
            (root/'source-sha.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [Path(__file__), FRAME_SOURCE,
                          *dict.fromkeys(sources + pool_fixture.SWIFT_SOURCES)]}, indent=2))
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        if run is None or run.returncode:
            raise RuntimeError(run.stderr if run is not None else 'harness did not run')
        cls.result = json.loads(run.stdout)
        if not cls.result['metalAvailable']:
            raise unittest.SkipTest('Metal unavailable')

    def check_cases(self, names):
        for name in names:
            with self.subTest(case=name):
                row = self.result['rows'][name]
                self.assertEqual([k for k,v in row['results'].items() if not v], [], row)

    def test_active_identity_samples_the_small_graph_output(self):
        self.check_cases(['single', 'active'])

    def test_inactive_and_failed_suffix_retain_last_active_input(self):
        self.check_cases(['inactive', 'failed', 'twoInactive', 'identityThenInactive'])

    def test_no_active_material_or_snapshot_storage_uses_the_real_graph_route(self):
        self.check_cases(['singleInactive', 'snapshotBudgetRejected'])

    def test_terminal_replay_preserves_positive_and_negative_vertex_overflow(self):
        for name in ('positiveSkew', 'negativeSkew', 'offset', 'halfAlpha'):
            with self.subTest(case=name):
                row = self.result['overflow'][name]
                self.assertEqual([k for k, v in row['results'].items() if not v], [], row)
                self.assertEqual(row['graphExtent'], [10, 10], row)

    def test_identity_terminal_replay_matches_the_unclipped_graph(self):
        row = self.result['overflow']['identity']
        self.assertEqual([k for k, v in row['results'].items() if not v], [], row)

    def test_attachment_raster_override_and_nil_survive_dependency_copy(self):
        for name in ('localRaster', 'nilWorld'):
            with self.subTest(case=name):
                row = self.result['attachment'][name]
                self.assertEqual([k for k, v in row['results'].items() if not v], [], row)

    def test_named_input_survives_active_inactive_and_failed_terminal_suffixes(self):
        for name in ('active', 'inactive', 'failed'):
            with self.subTest(case=name):
                row = self.result['named'][name]
                if name == 'active':
                    self.assertTrue(1 <= row['transitions'] <= 20, row)
                else:
                    self.assertGreaterEqual(row['transitions'], 120, row)
                self.assertEqual([k for k, v in row['results'].items() if not v], [], row)
                self.assertEqual(row['providerExtent'], [7, 3], row)
                self.assertEqual([k for k, v in row['dependencySizing'].items() if not v], [], row)
