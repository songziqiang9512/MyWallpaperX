#!/usr/bin/env python3
"""Source-proven graph color uses the current atom and typed color boundary."""
from __future__ import annotations

import json
import unittest
from script.tests import test_scene_resolved_material_graph_executor as fixture

HARNESS = r'''
private func diagnostic(_ failure: SceneResolvedMaterialFailure) -> String {
    "\(failure.phase.rawValue):\(failure.code.rawValue):\(failure.boundedDetails.joined(separator: ","))"
}

private func graphAtom(_ device: MTLDevice, identity: Graph.TextureIdentity,
    purpose: SceneTextureLoadPurpose = .premultipliedColor,
    content: SceneTextureContent = .color(.resolved(.premultipliedAlpha)),
    pixelFormat: MTLPixelFormat = .bgra8Unorm,
    generation: UInt64 = 1, candidateGeneration: UInt64 = 1,
    requestOverride: Graph.TextureIdentity? = nil) -> SceneFrameTextureResource {
    let texture = makeSource(device, width: 2, height: 2,
        usage: [.renderTarget, .shaderRead],
        pixelsBGRA: [0,0,0,0, 16,32,64,128, 32,64,128,255, 0,0,0,0],
        pixelFormat: pixelFormat)
    let candidate = SceneTextureCandidate(texture: texture,
        identity: .provider(.graph(allocationGeneration: 1, physicalToken: "own-probe-atom")),
        generation: .provider(contentGeneration: candidateGeneration), purpose: purpose,
        content: content, physicalSize: CGSize(width: 2, height: 2),
        mappedSize: CGSize(width: 2, height: 2), uvTransform: .identity,
        sampling: .linearClamp)
    return .init(publication: .init(requestIdentity: .graph(requestOverride ?? identity),
        candidate: candidate, contentGeneration: generation), resourceGeneration: generation)
}

private func inputFor(_ template: Template, entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus],
    graphInput: Graph.TextureIdentity) -> SceneResolvedMaterialFinalizationInput {
    frame(1, width: 2, height: 2, textureEntries: entries).finalizationInput(template: template,
        layerID: graphInput.layerID, renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        implicitFramebufferIdentity: graphInput)
}

private func traceMaterial(_ cache: SceneResolvedMaterialVariantCache,
    device: MTLDevice, graphInput: Graph.TextureIdentity,
    extraEntries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus],
    graphStatus: SceneFrameTextureLookupStatus? = nil,
    queue: MTLCommandQueue? = nil) -> [String: Any] {
    let snapshot = cache.launchEnvelopeCapabilitySnapshot()
    let resource = graphAtom(device, identity: graphInput)
    var entries = extraEntries
    entries[.graph(graphInput)] = graphStatus ?? .ready(resource)
    let input = inputFor(snapshot.template, entries: entries, graphInput: graphInput)
    var result: [String: Any] = ["allLaunchEntriesReady": snapshot.allEntriesReady,
        "wholeTemplate": String(describing: snapshot.template.graphRole),
        "graphAtomComplete": resource.isCompleteGraphResource,
        "graphAtomPurpose": String(describing: resource.publication.candidate.purpose)]
    result["variants"] = snapshot.variants.map { variant -> [String: Any] in
        let channels = Dictionary(uniqueKeysWithValues: variant.frontendProgram.textureBindings.map {
            ($0.slot, $0.channelUse)
        })
        var value: [String: Any] = ["readinessMask": variant.readinessMask,
            "route": String(describing: variant.routeDecision),
            "wholeFrontendColorTransfer": String(describing: variant.frontendProgram.colorTransfer),
            "wholeFrontendColorBoundary": String(describing: variant.frontendProgram.colorBoundary),
            "inputConversions": String(describing: variant.premultipliedColorInputSlots),
            "graphSourceFacts": String(describing: variant.graphInputSourceSlotFacts)]
        value["samplers"] = variant.activeSamplers.values.sorted { $0.slot < $1.slot }.map { sampler -> [String: Any] in
            let slot = snapshot.template.textureSlots[sampler.slot]!
            return ["slot": sampler.slot, "schema": String(describing: sampler),
                "sourcePurpose": sampler.sourceProvenPurpose?.reportToken ?? "nil",
                "candidatePurposes": slot.candidates.indices.map { ordinal -> [String: Any] in
                    let reference = slot.candidates[ordinal].reference
                    return ["ordinal": ordinal, "reference": String(describing: reference),
                        "directPurpose": String(describing: sampler.purpose(for: reference)),
                        "factPurpose": SceneResolvedMaterialTextureSlotPurpose.fact(in: slot,
                            candidateOrdinal: ordinal, sampler: sampler)?.purpose.reportToken ?? "nil",
                        "fact": String(describing: SceneResolvedMaterialTextureSlotPurpose.fact(in: slot,
                            candidateOrdinal: ordinal, sampler: sampler)),
                        "frameSelectionPurpose": String(describing: SceneResolvedMaterialTextureResolver.selectionPurpose(
                            in: slot, candidateOrdinal: ordinal, activeSampler: sampler,
                            reachableSamplers: snapshot.reachableSamplers?[sampler.slot] ?? [],
                            channelUse: channels[sampler.slot], input: input))]
                }]
        }
        do {
            value["frameEntries"] = String(describing: try SceneResolvedMaterialTextureSelection.resolve(input,
                samplers: variant.activeSamplers, reachableSamplers: snapshot.reachableSamplers ?? [:],
                channelUses: channels, allowPresenceIndependentDefaults: true,
                graphInputSourceSlotFacts: variant.graphInputSourceSlotFacts))
        } catch let failure as SceneResolvedMaterialFailure { value["frameEntryError"] = diagnostic(failure) }
        catch { value["frameEntryError"] = String(describing: error) }
        return value
    }
    switch cache.resolveSelection(input) {
    case .success: result["variantSelection"] = "success"
    case let .failure(failure): result["variantSelection"] = diagnostic(failure)
    }
    switch SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache) {
    case let .success(program):
        result["finalization"] = "success"
        result["programOutput"] = String(describing: program.outputContract)
        result["programResourcePurposes"] = program.textureSlots.map {
            $0.map { String(describing: $0.resource.publication.candidate.purpose) } ?? "absent"
        }
        result["inputMask"] = program.resolvedUniforms.first {
            $0.field.name == "mwxPremultipliedColorInputMask"
        }.map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } ?? 0
        result["selectedReferences"] = program.textureSlots.map {
            $0.map { String(describing: $0.reference) } ?? "absent"
        }
        if let queue, let encoder = SceneResolvedMaterialPassEncoder(device: device),
           let command = queue.makeCommandBuffer() {
            let target = makeSource(device, width: 2, height: 2, usage: [.renderTarget, .shaderRead])
            if let pass = encoder.prepare(program: program, target: target),
               encoder.encode(pass, commandBuffer: command),
               let read = appendReadback(target, commandBuffer: command) {
                command.commit(); command.waitUntilCompleted()
                result["gpuCompleted"] = command.status == .completed && command.error == nil
                result["pixelsBGRA"] = read.allPixels
            }
        }
    case let .failure(failure): result["finalization"] = diagnostic(failure)
    }
    return result
}

private func ownGraph(renamed: Bool) -> Graph {
    guard renamed else { return chainedGraph() }
    let source = Graph.TextureIdentity(kind: .layerSource, layerID: 919, effect: nil, name: nil)
    let keys = (0..<3).map { Graph.EffectKey(layerID: 919, effectIndex: $0,
        descriptorID: "own-relocated-effect-\($0)") }
    let outputs = keys.map { Graph.TextureIdentity(kind: .effectOutput, layerID: 919, effect: $0, name: nil) }
    let effects = keys.enumerated().map { index, key in
        Graph.Effect(key: key, definitionPath: "fixtures/relocated/effect-\(index).json",
            input: index == 0 ? source : outputs[index-1], output: outputs[index], nodeIndices: [index])
    }
    let nodes = keys.enumerated().map { index, key in
        Graph.Node(nodeIndex: index, effect: key, definitionPassIndex: 0, materialOrdinal: 0,
            instancePassIndex: 0, kind: .material, materialPath: "fixtures/relocated/material-\(index).json",
            materialPassID: "own-relocated-material-\(index)", target: outputs[index],
            bindings: [.init(slot: 0, authoredName: "own-relocated-input-\(index)",
                texture: index == 0 ? source : outputs[index-1], conditions: nil)],
            commandSource: nil, commandTarget: nil, compose: nil, conditions: nil)
    }
    return Graph(layerID: 919, effects: effects, renderTargets: [], nodes: nodes,
        finalOutput: outputs[2], blockers: [])
}

private func ownCatalog(_ graph: Graph, renamed: Bool,
    fallback: SceneAssetTextureIdentity) -> SceneResolvedMaterialRuntimeCatalog {
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    for node in graph.nodes {
        let original = template(for: node, pixelTransform: 1,
            systemProvider: node.nodeIndex == 1 ? systemProviderName : nil)
        var slots = original.textureSlots
        if node.nodeIndex == 1, let slot = slots[1] {
            slots[1] = .init(index: 1, candidates: slot.candidates.map { candidate in
                if case .asset = candidate.reference {
                    return .init(reference: .asset(fallback.path), provenance: candidate.provenance)
                }
                return candidate
            })
        }
        let pigment = renamed ? "ink" : "color", amount = renamed ? "weight" : "auxiliary"
        let coordinate = renamed ? "(v_TexCoord)" : "v_TexCoord"
        let fragment = node.nodeIndex == 1 ? """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1; // {"mode":"rgbmask"}
        void main() {
            vec4 \(pigment) = texSample2D(g_Texture0, \(coordinate));
            float \(amount) = texSample2D(g_Texture1, \(coordinate)).r;
            \(pigment).rgb *= \(amount);
            gl_FragColor = \(pigment);
        }
        """ : fragmentSource(pass: false, pixelTransform: 1)
        let basic = shaderContract(nodeIndex: node.nodeIndex, pass: false, fragmentOverride: fragment)
        let shader: SceneShaderContract
        if renamed {
            let prefix = "fixtures/relocated/paint-\(node.nodeIndex)"
            let stages = basic.stages.map { stage in
                let path = prefix + (stage.kind == .vertex ? ".vert" : ".frag")
                let parsed = SceneShaderContractSourceParser().parse(stage.source, stageRelativePath: path)
                return SceneShaderContract.Stage(kind: stage.kind, relativePath: path, source: stage.source,
                    rawSHA256: stage.rawSHA256, includes: parsed.includes,
                    annotations: parsed.annotations, declarations: parsed.declarations)
            }
            let digest = SceneShaderStableDigest.hash(stages)
            shader = .init(identity: prefix, sourceKind: .authoredSource, stages: stages, diagnostics: [],
                canonicalSHA256: digest, sourceGraph: .init(roots: stages.map {
                    .init(label: $0.kind == .vertex ? "vertex" : "fragment", virtualPath: $0.relativePath)
                }, nodes: stages.map {
                    .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
                        rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
                }, edges: [], diagnostics: [], dependencySHA256: digest))
        } else { shader = basic }
        let effect = graph.effects.first { $0.key == node.effect }!
        let value = Template.validated(textureSlots: slots, combos: original.combos,
            uniformDeclarations: [], renderState: original.renderState,
            graphRole: .init(effectInput: role(effect.input), effectOutput: role(effect.output),
                nodeTarget: role(node.target!), bindings: node.bindings.map { .init(slot: $0.slot!, texture: role($0.texture)) }),
            shaderContract: shader, diagnosticProvenance: .init(nodeIndex: node.nodeIndex,
                authoredShaderPath: shader.identity, contractIdentity: shader.identity,
                contractCanonicalSHA256: shader.canonicalSHA256, textureSources: [], uniformSources: []))!
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)] = .template(value)
    }
    return .init(entries: entries, resourceDemandIssues: [])
}

private func neighborTrace(_ device: MTLDevice, template: Template) -> [[String: Any]] {
    let identity = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID, effect: effect, name: "self-neighbor")
    let slot = Template.TextureSlot(index: 0, candidates: [.init(reference: .graph(identity), provenance: .explicitBinding)])
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8); slots[0] = slot
    let neighborTemplate = Template.validated(textureSlots: slots, combos: template.combos,
        uniformDeclarations: template.uniformDeclarations, renderState: template.renderState,
        graphRole: .init(effectInput: .framebuffer, effectOutput: .effectOutput, nodeTarget: .effectOutput,
            bindings: [.init(slot: 0, texture: .framebuffer)]), shaderContract: template.shaderContract,
        diagnosticProvenance: template.diagnosticProvenance)!
    let cases: [(String, SceneResolvedMaterialShaderSchema.TextureMode, SceneTextureLoadPurpose?,
        SceneTextureLoadPurpose, SceneTextureContent, MTLPixelFormat, UInt64, Graph.TextureIdentity?)] = [
        ("straight-color", .regular, .straightAlbedo, .premultipliedColor, .color(.resolved(.premultipliedAlpha)), .bgra8Unorm, 1, nil),
        ("mask-source", .opacityMask, .mask, .mask, .data, .r8Unorm, 1, nil),
        ("preserved-R", .regular, .preservedChannels, .preservedChannels, .scalarRedUnorm, .r8Unorm, 1, nil),
        ("preserved-RG", .regular, .preservedChannels, .preservedChannels, .redGreenUnorm, .rg8Unorm, 1, nil),
        ("preserved-data", .regular, .preservedChannels, .preservedChannels, .data, .bgra8Unorm, 1, nil),
        ("unknown-color", .regular, .straightAlbedo, .premultipliedColor, .color(.unresolved), .bgra8Unorm, 1, nil),
        ("stale-generation", .regular, .straightAlbedo, .premultipliedColor, .color(.resolved(.premultipliedAlpha)), .bgra8Unorm, 2, nil),
        ("wrong-request", .regular, .straightAlbedo, .premultipliedColor, .color(.resolved(.premultipliedAlpha)), .bgra8Unorm, 1, chainedSecondOutput),
        ("regular-unproven", .regular, nil, .premultipliedColor, .color(.resolved(.premultipliedAlpha)), .bgra8Unorm, 1, nil)
    ]
    return cases.map { name, mode, source, purpose, content, format, candidateGen, request in
        let sampler = SceneResolvedMaterialShaderSchema.Sampler(name: "g_Texture0", slot: 0, mode: mode,
            materialKey: nil, isHidden: true, defaultTexture: nil, readinessCombo: nil,
            channelUse: .wholeVector, sourceProvenPurpose: source)
        let resource = graphAtom(device, identity: identity, purpose: purpose, content: content,
            pixelFormat: format, candidateGeneration: candidateGen, requestOverride: request)
        let input = inputFor(neighborTemplate, entries: [.graph(identity): .ready(resource)], graphInput: identity)
        var value: [String: Any] = ["name": name, "publicationComplete": resource.publication.isComplete,
            "graphComplete": resource.isCompleteGraphResource,
            "schema": String(describing: sampler),
            "fact": String(describing: SceneResolvedMaterialTextureSlotPurpose.fact(in: slot,
                candidateOrdinal: 0, sampler: sampler)),
            "factPurpose": SceneResolvedMaterialTextureSlotPurpose.fact(in: slot,
                candidateOrdinal: 0, sampler: sampler)?.purpose.reportToken ?? "nil",
            "selectionPurpose": String(describing: SceneResolvedMaterialTextureResolver.selectionPurpose(in: slot,
                candidateOrdinal: 0, activeSampler: sampler, reachableSamplers: [sampler],
                channelUse: .wholeVector, input: input)),
            "selectionPurposeToken": SceneResolvedMaterialTextureResolver.selectionPurpose(in: slot,
                candidateOrdinal: 0, activeSampler: sampler, reachableSamplers: [sampler],
                channelUse: .wholeVector, input: input)?.reportToken ?? "nil"]
        do {
            value["selection"] = String(describing: try SceneResolvedMaterialTextureSelection.resolve(input,
                samplers: [0: sampler], reachableSamplers: [0: [sampler]], channelUses: [0: .wholeVector],
                allowPresenceIndependentDefaults: true))
            value["variantKey"] = String(describing: try SceneResolvedMaterialTextureResolver.variantKey(input,
                samplers: [0: sampler], reachableSamplers: [0: [sampler]], formatSlots: [],
                channelUses: [0: .wholeVector], allowPresenceIndependentDefaults: true))
        } catch let failure as SceneResolvedMaterialFailure { value["failure"] = diagnostic(failure) }
        catch { value["failure"] = String(describing: error) }
        return value
    }
}

@main
private enum Probe {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        let sourcePipeline = makeSourcePipeline(device)
        var output: [String: Any] = ["probe": "own-graph-purpose-red-v1", "metalDevice": device.name,
            "sourcePixelsBGRA": [[0,0,0,0], [16,32,64,128], [32,64,128,255], [0,0,0,0]]]
        let sourceGraph = ownGraph(renamed: false)
        let sourceCatalog = ownCatalog(sourceGraph, renamed: false, fallback: systemProviderFallbackIdentity)
        let sourceKey = SceneResolvedMaterialRuntimeCatalog.Key(effect: sourceGraph.nodes[1].effect, nodeIndex: 1)
        guard case let .template(sourceTemplate)? = sourceCatalog.entries[sourceKey] else {
            fatalError("self counterexample source template unavailable")
        }
        let counterIdentity = Graph.TextureIdentity(kind: .framebuffer, layerID: layerID,
            effect: effect, name: "own-counterexample-ingress")
        let lowerDefinitions: [(String, SceneTextureLoadPurpose, MTLPixelFormat)] = [
            ("util/noise", .noise, .r8Unorm),
            ("gradient/gradient_fire", .preservedChannels, .bgra8Unorm),
        ]
        var counterexamples: [[String: Any]] = []
        for lower in lowerDefinitions {
          let path = SceneVFSAssetPath(lower.0)!, lowerIdentity = SceneAssetTextureIdentity(path: path, purpose: lower.1)
          let texture = makeSource(device, width: 2, height: 2, pixelFormat: lower.2)
          let candidate = SceneTextureCandidate(texture: texture, identity: .provider(.mediaThumbnailCurrent),
              generation: .provider(contentGeneration: 1), purpose: lower.1, content: .data,
              physicalSize: CGSize(width: 2, height: 2), mappedSize: CGSize(width: 2, height: 2),
              uvTransform: .identity, sampling: .linearClamp)
          let lowerResource = SceneFrameTextureResource(publication: .init(requestIdentity: .asset(lowerIdentity),
              candidate: candidate, contentGeneration: 1), resourceGeneration: 1)
          let provenances: [SceneResolvedMaterialNode.TextureProvenance] = [.explicitBinding, .instance]
          for provenance in provenances {
            var slots = sourceTemplate.textureSlots
            slots[0] = .init(index: 0, candidates: [
                .init(reference: .asset(path), provenance: .material),
                .init(reference: .graph(counterIdentity), provenance: provenance),
            ])
            let value = Template.validated(textureSlots: slots, combos: sourceTemplate.combos,
                uniformDeclarations: sourceTemplate.uniformDeclarations, renderState: sourceTemplate.renderState,
                graphRole: .init(effectInput: .framebuffer, effectOutput: .effectOutput,
                    nodeTarget: .effectOutput, bindings: [.init(slot: 0, texture: .framebuffer)]),
                shaderContract: sourceTemplate.shaderContract, diagnosticProvenance: sourceTemplate.diagnosticProvenance)!
            guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
                template: value, maximumVariantCount: 8) else { fatalError("counterexample cache unavailable") }
            let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: counterIdentity,
                assetStates: [lowerIdentity: .ready(.data), systemProviderFallbackIdentity: .ready(.data)])
            let extra: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
                .asset(lowerIdentity): .ready(lowerResource),
                .asset(systemProviderFallbackIdentity): systemProviderFallbackStatus(device: device, generation: 1),
                .system(systemProviderIdentity): .absent,
            ]
            for ready in [true, false] {
                var row = traceMaterial(cache, device: device, graphInput: counterIdentity, extraEntries: extra,
                    graphStatus: ready ? .ready(graphAtom(device, identity: counterIdentity)) : .absent,
                    queue: ready ? queue : nil)
                row["kind"] = "lower-candidate"; row["lowerPath"] = lower.0
                row["lowerPublicationComplete"] = lowerResource.publication.isComplete
                row["lowerPurpose"] = lower.1.reportToken; row["graphReady"] = ready
                row["graphProvenance"] = provenance.rawValue
                row["launch"] = launchEnvelopeFailureCode(launch)
                counterexamples.append(row)
            }
          }
        }
        var colorSlots = sourceTemplate.textureSlots
        colorSlots[0] = .init(index: 0, candidates: [
            .init(reference: .graph(counterIdentity), provenance: .explicitBinding),
        ])
        let colorTemplate = Template.validated(textureSlots: colorSlots, combos: sourceTemplate.combos,
            uniformDeclarations: sourceTemplate.uniformDeclarations, renderState: sourceTemplate.renderState,
            graphRole: .init(effectInput: .framebuffer, effectOutput: .effectOutput,
                nodeTarget: .effectOutput, bindings: [.init(slot: 0, texture: .framebuffer)]),
            shaderContract: sourceTemplate.shaderContract, diagnosticProvenance: sourceTemplate.diagnosticProvenance)!
        guard case let .success(colorCache) = SceneResolvedMaterialVariantCache.launchValidated(
            template: colorTemplate, maximumVariantCount: 8) else { fatalError("color counterexample cache unavailable") }
        let colorLaunch = colorCache.precompileLaunchEnvelope(implicitFramebufferIdentity: counterIdentity,
            assetStates: [systemProviderFallbackIdentity: .ready(.data)])
        let dataRepresentations: [(String, SceneTextureContent, MTLPixelFormat)] = [
            ("R", .scalarRedUnorm, .r8Unorm), ("RG", .redGreenUnorm, .rg8Unorm), ("data", .data, .bgra8Unorm),
        ]
        for (name, content, format) in dataRepresentations {
            let atom = graphAtom(device, identity: counterIdentity, purpose: .preservedChannels,
                content: content, pixelFormat: format)
            var row = traceMaterial(colorCache, device: device, graphInput: counterIdentity,
                extraEntries: [.asset(systemProviderFallbackIdentity): systemProviderFallbackStatus(device: device, generation: 1),
                    .system(systemProviderIdentity): .absent], graphStatus: .ready(atom))
            row["kind"] = "source-straight-data"; row["content"] = name
            row["publicationPurpose"] = atom.publication.candidate.purpose.reportToken
            row["publicationComplete"] = atom.publication.isComplete; row["graphComplete"] = atom.isCompleteGraphResource
            row["launch"] = launchEnvelopeFailureCode(colorLaunch)
            counterexamples.append(row)
        }
        output["counterexamples"] = counterexamples
        var scenarios: [[String: Any]] = []
        for renamed in [false, true] {
          let raw = ownGraph(renamed: renamed), chain = orderedLayerGraph(raw)
          let graphInput = raw.effects[0].input, middleInput = raw.effects[1].input
          let fallback = renamed ? SceneAssetTextureIdentity(path: SceneVFSAssetPath("fixtures/relocated/aux.tex")!,
              purpose: .preservedChannels) : systemProviderFallbackIdentity
          for assetReady in [true, false] {
            let caps = capabilities(chain, catalog: ownCatalog(raw, renamed: renamed, fallback: fallback),
                assetStates: [fallback: assetReady ? .ready(.data) : .absent],
                assetFormatFacts: [fallback.reportToken: SceneShaderTextureFormat.r8.macroValue])
            for providerReady in [true, false] {
                var value: [String: Any] = ["renamed": renamed, "assetReady": assetReady, "providerReady": providerReady,
                    "graph": String(describing: raw), "fallback": fallback.reportToken]
                guard let claim = caps.claim(chain), let capability = caps.resolve(claim.token, for: chain),
                    let leases = makeChainedLeases(capability, device: device),
                    let executor = Executor(device: device, capabilities: caps), let command = queue.makeCommandBuffer()
                else { value["setup"] = "unclaimed"; scenarios.append(value); continue }
                let originalFallback = systemProviderFallbackStatus(device: device, generation: 1)
                let fallbackStatus: SceneFrameTextureLookupStatus
                if assetReady, case let .ready(resource) = originalFallback {
                    fallbackStatus = .ready(.init(publication: resource.publication.publication(for: .asset(fallback)),
                        resourceGeneration: resource.resourceGeneration))
                } else { fallbackStatus = .absent }
                let entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
                    .system(systemProviderIdentity): systemProviderStatus(providerReady ? .ready : .absent, device: device, generation: 1),
                    .asset(fallback): fallbackStatus]
                if let material = capability.material(for: raw.nodes[0]) {
                    value["firstMaterial"] = traceMaterial(material.variants, device: device, graphInput: graphInput, extraEntries: entries)
                    if scenarios.isEmpty { output["neighbors"] = neighborTrace(device, template: material.template) }
                }
                if let material = capability.material(for: raw.nodes[1]) {
                    value["middleMaterial"] = traceMaterial(material.variants, device: device, graphInput: middleInput, extraEntries: entries)
                }
                let preparation = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
                    frame: frame(1, textureEntries: entries), sourceTexture: graphAtom(device, identity: graphInput).publication.texture,
                    sourceUniforms: .neutral(), sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: command,
                    previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
                value["preparation"] = failureCode(preparation)
                if case let .success(prepared) = preparation {
                    value["stageFailures"] = prepared.stages.map { $0.effectLocalFailureReasonCode ?? "none" }
                    value["programKeys"] = prepared.stages.map(\.programCacheKeys)
                    if let material = capability.material(for: raw.nodes[1]),
                       let overlaid = frame(1, textureEntries: entries).overlayingGraphResources([
                           middleInput: prepared.stages[0].effectOutputResource
                       ]), case let .success(program) = SceneResolvedMaterialProgramFinalizer.finalize(
                           overlaid.finalizationInput(template: material.template, layerID: raw.layerID,
                               renderSize: CGSize(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
                               layerModelMatrix: matrix_identity_float4x4,
                               effectOutputModelViewProjection: matrix_identity_float4x4,
                               effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                               implicitFramebufferIdentity: middleInput), variantCache: material.variants),
                       let bound = program.textureSlots[0] {
                        value["actualMiddleInputContent"] = String(describing: bound.resource.publication.candidate.content)
                        value["actualMiddleInputSameAtom"] = bound.resource.publication.isSameAtom(
                            as: prepared.stages[0].effectOutputResource.publication)
                        value["actualMiddleInputMask"] = program.resolvedUniforms.first {
                            $0.field.name == "mwxPremultipliedColorInputMask"
                        }.map { $0.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } } ?? 0
                    }
                    value["stageContents"] = prepared.stages.map { String(describing: $0.effectOutputResource.publication.candidate.content) }
                    value["stagePurposes"] = prepared.stages.map { $0.effectOutputResource.publication.candidate.purpose.reportToken }
                    value["finalPurpose"] = prepared.finalResource.publication.candidate.purpose.reportToken
                    var reads: [Readback] = []
                    let encoded = executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { _, stage, buffer in
                        guard let read = appendReadback(stage.effectOutputResource.publication.texture, commandBuffer: buffer) else { return false }
                        reads.append(read); return true
                    })
                    value["encoded"] = encoded
                    let read = encoded ? appendReadback(prepared.finalTexture, commandBuffer: command) : nil
                    command.commit(); command.waitUntilCompleted()
                    value["gpuCompleted"] = command.status == .completed && command.error == nil
                    value["cornerPixelsBGRA"] = read.map { read in
                        [read.pixel(x: 0, y: 0), read.pixel(x: read.width-1, y: 0),
                         read.pixel(x: 0, y: read.height-1), read.pixel(x: read.width-1, y: read.height-1)]
                    } ?? []
                    value["stagePixelsBGRA"] = reads.map(\.allPixels)
                }
                scenarios.append(value)
            }
          }
        }
        output["scenarios"] = scenarios
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneGraphSourceColorPurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        prefix, separator, _ = fixture.HARNESS.partition("@main\nprivate enum Harness")
        if not separator:
            raise RuntimeError("owned graph fixture entry boundary unavailable")
        compilation, completed = fixture.compile_harness(fixture.SUPPORT, prefix + HARNESS)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        if completed is None or completed.returncode:
            raise RuntimeError(completed.stderr if completed else "owned graph probe did not run")
        cls.result = json.loads(completed.stdout)

    def test_complete_graph_source_color_reaches_program_and_gpu(self) -> None:
        rows = self.result["scenarios"]
        self.assertEqual(len(rows), 8)
        for row in rows:
            with self.subTest(renamed=row["renamed"], asset=row["assetReady"], provider=row["providerReady"]):
                self.assertEqual(row["preparation"], "success", row)
                self.assertTrue(row["encoded"], row)
                self.assertTrue(row["gpuCompleted"], row)
                self.assertEqual(row["firstMaterial"]["finalization"], "success", row)
                if row["assetReady"] or row["providerReady"]:
                    self.assertEqual(row["middleMaterial"]["finalization"], "success", row)
                    self.assertTrue(row["actualMiddleInputSameAtom"], row)
                    self.assertEqual(row["actualMiddleInputMask"], 0, row)
                    self.assertEqual(row["stageFailures"], ["none"] * 3, row)
                else:
                    self.assertEqual(row["stageFailures"],
                        ["none", "material-variant-selection-key-unstable", "none"], row)
                for variant in row["middleMaterial"]["variants"]:
                    color = next(item for item in variant["samplers"] if item["slot"] == 0)
                    self.assertEqual(color["sourcePurpose"], "straight-albedo", row)
                    self.assertEqual(color["candidatePurposes"][0]["factPurpose"], "premultiplied-color", row)

    def test_alpha_raster_and_available_or_absent_auxiliary_have_actual_pixels(self) -> None:
        for row in self.result["scenarios"]:
            with self.subTest(renamed=row["renamed"], asset=row["assetReady"], provider=row["providerReady"]):
                expected = [[0, 0, 0, 0], [0, 0, 0, 128], [0, 0, 0, 255], [0, 0, 0, 0]] if row["providerReady"] else [
                    [0, 0, 0, 0], [64, 128, 32, 128], [64, 128, 32, 255], [0, 0, 0, 0]]
                self.assertEqual(row["cornerPixelsBGRA"], expected, row)
                self.assertEqual(row["finalPurpose"], "straight-albedo", row)
                self.assertEqual(row["stagePurposes"], ["straight-albedo"] * 3, row)
                self.assertEqual(len(row["stagePixelsBGRA"]), 3, row)
                self.assertTrue(all("straightAlpha" in value for value in row["stageContents"]), row)

    def test_variable_resource_identity_and_expression_variants_are_equivalent(self) -> None:
        rows = self.result["scenarios"]
        for asset in [False, True]:
            for provider in [False, True]:
                matching = [row for row in rows if row["assetReady"] == asset and row["providerReady"] == provider]
                self.assertEqual(len(matching), 2)
                self.assertNotEqual(matching[0]["graph"], matching[1]["graph"])
                self.assertNotEqual(matching[0]["fallback"], matching[1]["fallback"])
                self.assertEqual(matching[0]["cornerPixelsBGRA"], matching[1]["cornerPixelsBGRA"])
                self.assertEqual(matching[0]["stagePixelsBGRA"], matching[1]["stagePixelsBGRA"])

    def test_scalar_data_mask_and_incomplete_atoms_keep_existing_boundaries(self) -> None:
        cases = {item["name"]: item for item in self.result["neighbors"]}
        self.assertEqual(cases["straight-color"]["factPurpose"], "premultiplied-color")
        self.assertNotIn("failure", cases["straight-color"])
        self.assertEqual(cases["mask-source"]["factPurpose"], "mask")
        self.assertEqual(cases["mask-source"]["selectionPurposeToken"], "nil")
        self.assertTrue(cases["mask-source"]["failure"].startswith("texture:texturePurposeUnproven"))
        for name in ["preserved-R", "preserved-RG", "preserved-data"]:
            self.assertEqual(cases[name]["selectionPurposeToken"], "preserved-channels")
            self.assertTrue(cases[name]["graphComplete"])
            self.assertNotIn("failure", cases[name])
        for name in ["unknown-color", "stale-generation", "wrong-request"]:
            self.assertTrue(cases[name]["failure"].startswith("texture:textureMetadataIncomplete"))
        self.assertEqual(cases["regular-unproven"]["factPurpose"], "premultiplied-color")
        self.assertNotIn("failure", cases["regular-unproven"])

    def test_candidate_chain_and_actual_data_stay_separate_from_source_color(self) -> None:
        rows = self.result["counterexamples"]
        self.assertEqual(len(rows), 11)
        for row in rows:
            with self.subTest(kind=row["kind"], lower=row.get("lowerPath"), ready=row.get("graphReady"), content=row.get("content")):
                self.assertEqual(row["launch"], "success", row)
                self.assertTrue(row["allLaunchEntriesReady"], row)
                variant = row["variants"][0]
                sampler = next(item for item in variant["samplers"] if item["slot"] == 0)
                self.assertEqual(sampler["sourcePurpose"], "straight-albedo", row)
                if row["kind"] == "lower-candidate":
                    self.assertTrue(row["lowerPublicationComplete"], row)
                    self.assertEqual(sampler["candidatePurposes"][0]["factPurpose"], "nil", row)
                    self.assertEqual(sampler["candidatePurposes"][1]["factPurpose"], "premultiplied-color", row)
                    if row["graphReady"]:
                        self.assertEqual(row["finalization"], "success", row)
                        self.assertTrue(row["gpuCompleted"], row)
                        self.assertIn("graph", row["selectedReferences"][0])
                        self.assertEqual(row["programResourcePurposes"][0], "premultipliedColor", row)
                    else:
                        rejection = "texture:resourceSnapshotUnresolved:" if row["graphProvenance"] == "explicitBinding" else "texture:texturePurposeUnproven:"
                        self.assertTrue(row["variantSelection"].startswith(rejection), row)
                        self.assertTrue(row["finalization"].startswith(rejection), row)
                        self.assertNotIn("selectedReferences", row)
                else:
                    self.assertTrue(row["publicationComplete"], row)
                    self.assertTrue(row["graphComplete"], row)
                    self.assertEqual(row["publicationPurpose"], "preserved-channels", row)
                    self.assertEqual(sampler["candidatePurposes"][0]["factPurpose"], "premultiplied-color", row)
                    self.assertIn("preservedChannels", sampler["candidatePurposes"][0]["frameSelectionPurpose"])
                    self.assertEqual(row["variantSelection"], "success", row)
                    self.assertTrue(row["finalization"].startswith("color:colorContractUnproven:"), row)


if __name__ == "__main__":
    unittest.main()
