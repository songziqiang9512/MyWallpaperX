#!/usr/bin/env python3
"""Scalar opacity-mask reads retain each selected two-dimensional data purpose."""
from __future__ import annotations

import json
import unittest
from script.tests import test_scene_resolved_material_graph_executor as fixture

HARNESS = r'''
import Foundation
import CoreGraphics
import Metal
import simd

private typealias Schema = SceneResolvedMaterialShaderSchema
private typealias Template = SceneResolvedMaterialTemplate
private let normalPath = SceneVFSAssetPath("effects/waterripplenormal")!
private let noisePath = SceneVFSAssetPath("util/noise")!

private func shader(renamed: Bool = false, expression: String = "red", mode: String = "opacitymask",
    defaultPath: SceneVFSAssetPath = noisePath) -> SceneShaderContract {
    let slot = renamed ? 4 : 2, varying = renamed ? "v_Map" : "v_UV"
    let carrier = renamed ? "shade" : "density"
    let coordinate = renamed ? "(\(varying))" : varying
    let sample = "texSample2D(g_Texture\(slot), \(coordinate))"
    let body: String
    switch expression {
    case "whole": body = "gl_FragColor = \(sample);"
    case "rg": body = "vec2 pair = \(sample).rg; gl_FragColor = vec4(pair, 0.25, 1.0);"
    case "alpha": body = "float \(carrier) = \(sample).a; gl_FragColor = vec4(\(carrier), 0.0, 0.25, 1.0);"
    default:
        body = "float \(carrier) = \(sample).r; gl_FragColor = vec4(\(carrier), \(carrier) * 0.5, 0.25, 1.0);"
    }
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 \(varying);
    void main() { \(varying) = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
    """
    let fragment = """
    varying vec2 \(varying);
    uniform sampler2D g_Texture\(slot); // {"mode":"\(mode)","default":"\(defaultPath.value)"}
    void main() { \(body) }
    """
    let prefix = renamed ? "fixtures/moved/scalar-paint" : "fixtures/scalar-mask"
    func stage(_ kind: SceneShaderContract.StageKind, _ suffix: String, _ source: String) -> SceneShaderContract.Stage {
        let path = prefix + suffix
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
        return .init(kind: kind, relativePath: path, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let stages = [stage(.vertex, ".vert", vertex), stage(.fragment, ".frag", fragment)]
    let digest = SceneShaderStableDigest.hash(stages)
    return .init(identity: prefix, sourceKind: .authoredSource, stages: stages, diagnostics: [],
        canonicalSHA256: digest, sourceGraph: .init(roots: stages.map {
            .init(label: $0.kind == .vertex ? "vertex" : "fragment", virtualPath: $0.relativePath)
        }, nodes: stages.map {
            .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
                rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
        }, edges: [], diagnostics: [], dependencySHA256: digest))
}

private func preparedSampler(_ contract: SceneShaderContract, slot: Int) -> Schema.Sampler? {
    guard case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract, combos: [:], textureReadiness: [slot: true]) else { return nil }
    return try? Schema.activeSamplers(prepared)[slot]
}

private func template(_ contract: SceneShaderContract, path: SceneVFSAssetPath, slot: Int,
    lowerPath: SceneVFSAssetPath? = nil) -> Template {
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    var candidates: [Template.TextureCandidate] = []
    if let lowerPath { candidates.append(.init(reference: .asset(lowerPath), provenance: .material)) }
    candidates.append(.init(reference: .asset(path), provenance: .instance))
    slots[slot] = .init(index: slot, candidates: candidates)
    return Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
        renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .effectOutput, bindings: []), shaderContract: contract,
        diagnosticProvenance: .init(nodeIndex: slot, authoredShaderPath: contract.identity,
            contractIdentity: contract.identity, contractCanonicalSHA256: contract.canonicalSHA256,
            textureSources: [], uniformSources: []))!
}

private func token(_ purpose: SceneTextureLoadPurpose?) -> String { purpose?.reportToken ?? "nil" }
private func failure(_ value: SceneResolvedMaterialFailure) -> String {
    "\(value.phase.rawValue):\(value.code.rawValue):\(value.boundedDetails.joined(separator: ","))"
}

private func upload(_ device: MTLDevice, purpose: SceneTextureLoadPurpose, frame: UInt64, noise: Bool = false) -> MTLTexture {
    let red: [UInt8] = noise ? [16,48,80,112] : frame == 1 ? [32,96,160,224] : [224,160,96,32]
    let alpha: [UInt8] = [0,128,255,0]
    var bytes: [UInt8] = []
    for index in 0..<4 {
        bytes.append(contentsOf: [red[index], UInt8(192-index*24), UInt8(24+index*16), alpha[index]])
    }
    let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent)!
    guard case let .loaded(texture) = SceneImageTextureUploader.upload(image: image, purpose: purpose,
        maxDimension: 2, mipmapGeneration: .baseLevelOnly, device: device) else {
        fatalError("own data upload failed")
    }
    return texture
}

private func resource(_ texture: MTLTexture, request: SceneAssetTextureIdentity, frame: UInt64,
    purpose: SceneTextureLoadPurpose? = nil, wrongIdentity: Bool = false,
    generationMismatch: Bool = false, unknownContent: Bool = false) -> SceneFrameTextureLookupStatus {
    let revision = SceneTextureFileRevision(fileSystemID: 3, fileID: 9,
        statusChangedAtSeconds: Int64(frame), statusChangedAtNanoseconds: 0)
    let candidate = SceneTextureCandidate(texture: texture, identity: .file(path: request.path.value),
        generation: generationMismatch ? .provider(contentGeneration: frame + 1)
            : .file(byteCount: 16, modifiedAtBits: frame, revision: revision),
        purpose: purpose ?? request.purpose, content: unknownContent ? .color(.unresolved) : .data,
        physicalSize: CGSize(width: 2, height: 2), mappedSize: CGSize(width: 2, height: 2),
        uvTransform: .identity, sampling: .linearClamp)
    let identity = wrongIdentity ? SceneAssetTextureIdentity(path: SceneVFSAssetPath("fixtures/wrong-request")!, purpose: request.purpose) : request
    return .ready(.init(publication: .init(requestIdentity: .asset(identity), candidate: candidate,
        contentGeneration: frame), resourceGeneration: frame))
}

private func systemNoise(_ texture: MTLTexture, path: SceneVFSAssetPath, frame: UInt64) -> SceneFrameTextureResource {
    let candidate = SceneTextureCandidate(texture: texture, identity: .builtIn(name: "own-noise-substitute"),
        generation: .immutable(revision: frame), purpose: .noise, content: .data, physicalSize: CGSize(width: 2,height: 2),
        mappedSize: CGSize(width: 2,height: 2), uvTransform: .identity, sampling: .linearClamp)
    return .init(publication: .init(requestIdentity: .system(.init(name:path.value,purpose:.noise)),
        candidate: candidate, contentGeneration: frame), resourceGeneration: frame)
}

private func input(_ template: Template, frame: UInt64,
    entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus]) -> SceneResolvedMaterialFinalizationInput {
    let dynamic = SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: frame,
        definitions: [], timelineValues: [:]).snapshot
    let frameInputs = SceneAuthoredShaderFrameInputs(frameIndex: frame, screenSize: CGSize(width: 2, height: 2),
        sceneTime: 0, dayTime: 0, frameTime: 1/60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero)
    guard case let .success(snapshot) = SceneResolvedMaterialFrameSnapshot.validated(
        textureSnapshot: .init(frameEpoch: frame, frameIndex: frame, entries: entries),
        dynamicSnapshot: dynamic, frameInputs: frameInputs) else { fatalError("own frame invalid") }
    return snapshot.finalizationInput(template: template, layerID: 0, renderSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4)
}

private func run(device: MTLDevice, queue: MTLCommandQueue, renamed: Bool,
    candidatePath: SceneVFSAssetPath, candidatePurpose: SceneTextureLoadPurpose, ready: Bool,
    noiseDefault: SceneVFSAssetPath = noisePath, defaultReady: Bool = true,
    corruption: String = "none", lowerNoise: Bool = false,
    candidateState: SceneAssetTextureLaunchState? = nil) -> [String: Any] {
    let slot = renamed ? 4 : 2
    let contract = shader(renamed: renamed, defaultPath: noiseDefault)
    let value = template(contract, path: candidatePath, slot: slot, lowerPath: lowerNoise ? noiseDefault : nil)
    let sampler = preparedSampler(contract, slot: slot)!
    let authored = SceneAssetTextureIdentity(path: candidatePath, purpose: candidatePurpose)
    let fallback = SceneAssetTextureIdentity(path: noiseDefault, purpose: .noise)
    let ordinal = value.textureSlots[slot]!.candidates.count - 1
    let state = candidateState ?? (ready ? .ready(.data) : .absent)
    var row: [String: Any] = ["renamed": renamed, "candidateReady": ready, "defaultReady": defaultReady,
        "candidateState": String(describing: state), "lowerNoise": lowerNoise, "candidateOrdinal": ordinal,
        "candidatePath": candidatePath.value, "candidatePurpose": candidatePurpose.reportToken,
        "defaultPath": noiseDefault.value, "corruption": corruption,
        "channelUse": sampler.channelUse.rawValue, "sourcePurpose": token(sampler.sourceProvenPurpose),
        "directCandidatePurpose": token(sampler.purpose(for: .asset(candidatePath))),
        "directDefaultPurpose": token(sampler.purpose(for: .asset(noiseDefault))),
        "slotFact": token(SceneResolvedMaterialTextureSlotPurpose.fact(in: value.textureSlots[slot]!,
            candidateOrdinal: ordinal, sampler: sampler)?.purpose),
        "typedStaticDataSlot": SceneResolvedMaterialVariantCache.typedStaticDataAuxiliarySlots(
            template: value, samplers: [slot:sampler], graphInputSlots: []).contains(slot)]
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(template: value,
        maximumVariantCount: 8) else { row["launch"] = "cache-invalid"; return row }
    let launchNoise = systemNoise(upload(device,purpose:.noise,frame:1,noise:true), path:noiseDefault,frame:1)
    let launch = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil,
        assetStates: [authored: state, fallback: defaultReady ? .ready(.data) : .absent],
        systemProviderStates: [.init(name:noiseDefault.value,purpose:.noise):.ready(launchNoise.publication)])
    switch launch {
    case .success: row["launch"] = "success"
    case .failure(.capacity): row["launch"] = "capacity"; return row
    case let .failure(.material(error)): row["launch"] = failure(error); return row
    }
    let baselineCounters = cache.counters
    let passEncoder = SceneResolvedMaterialPassEncoder(device: device)!
    var frames: [[String: Any]] = []
    for frame in [UInt64(1),2] {
        var source = upload(device, purpose: candidatePurpose, frame: frame)
        if corruption == "volume" {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D; descriptor.pixelFormat = .rgba8Unorm
            descriptor.width = 2; descriptor.height = 2; descriptor.depth = 2
            descriptor.storageMode = .shared; descriptor.usage = .shaderRead
            source = device.makeTexture(descriptor:descriptor)!
        }
        let defaultTexture = upload(device, purpose: .noise, frame: frame, noise: true)
        let published = resource(source, request: authored, frame: frame,
            purpose: corruption == "purpose" ? .mask : corruption == "color" ? .straightAlbedo
                : corruption == "lut" ? .lookupTable : nil,
            wrongIdentity: corruption == "identity", generationMismatch: corruption == "generation",
            unknownContent: corruption == "unknown")
        let entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
            .asset(authored): ready ? published : .absent,
            .asset(fallback): defaultReady ? resource(defaultTexture, request: fallback, frame: frame) : .absent,
            .system(.init(name:noiseDefault.value,purpose:.noise)): .ready(systemNoise(defaultTexture,path:noiseDefault,frame:frame)),
        ]
        let frameInput = input(value, frame: frame, entries: entries)
        var observation: [String: Any] = ["frame": frame]
        do {
            let snapshot = cache.launchEnvelopeCapabilitySnapshot()
            let variant = snapshot.variants[0]
            let selections = try SceneResolvedMaterialTextureSelection.resolve(frameInput,
                samplers: variant.activeSamplers, reachableSamplers: snapshot.reachableSamplers ?? [:],
                channelUses: Dictionary(uniqueKeysWithValues: variant.frontendProgram.textureBindings.map { ($0.slot,$0.channelUse) }),
                allowPresenceIndependentDefaults: true)
            observation["selection"] = String(describing: selections[slot])
        } catch let error as SceneResolvedMaterialFailure { observation["selectionFailure"] = failure(error) }
        catch { observation["selectionFailure"] = String(describing: error) }
        switch SceneResolvedMaterialProgramFinalizer.finalize(frameInput, variantCache: cache) {
        case let .failure(error): observation["finalization"] = failure(error)
        case let .success(program):
            observation["finalization"] = "success"
            let bound = program.textureSlots[slot]!
            observation["selectedPurpose"] = bound.expectedPurpose.reportToken
            observation["publicationPurpose"] = bound.resource.publication.candidate.purpose.reportToken
            observation["selectedIdentity"] = String(describing: bound.registryIdentity)
            observation["generation"] = bound.resource.resourceGeneration
            observation["content"] = String(describing: bound.resource.publication.candidate.content)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead,.renderTarget]
            let target = device.makeTexture(descriptor: descriptor)!
            if let command = queue.makeCommandBuffer(), let pass = passEncoder.prepare(program: program, target: target),
               passEncoder.encode(pass, commandBuffer: command) {
                command.commit(); command.waitUntilCompleted()
                observation["gpuCompleted"] = command.status == .completed && command.error == nil
                var bytes = Array<UInt8>(repeating: 0, count: 16)
                target.getBytes(&bytes, bytesPerRow: 8, from: MTLRegionMake2D(0,0,2,2), mipmapLevel: 0)
                observation["pixelsRGBA"] = bytes
            }
        }
        frames.append(observation)
    }
    row["frames"] = frames
    row["variantCompilationStable"] = cache.counters.frontendCompilationCount == baselineCounters.frontendCompilationCount
        && cache.counters.shaderPreparationCount == baselineCounters.shaderPreparationCount
    return row
}

@main
private enum Main {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        var matrix: [[String: Any]] = []
        for renamed in [false,true] {
            let path = renamed ? SceneVFSAssetPath("fixtures/moved/mask-image")! : normalPath
            let purpose: SceneTextureLoadPurpose = renamed ? .mask : .normal
            let fallback = renamed ? SceneVFSAssetPath("pattern/voronoi")! : noisePath
            for ready in [true,false] {
              for defaultReady in [true,false] {
                matrix.append(run(device: device, queue: queue, renamed: renamed,
                    candidatePath: path, candidatePurpose: purpose, ready: ready, noiseDefault: fallback,
                    defaultReady:defaultReady))
              }
            }
        }
        var neighboring: [[String: Any]] = []
        for (expression, mode) in [("whole","opacitymask"),("rg","opacitymask"),("alpha","opacitymask"),("red","rgbmask")] {
            let contract = shader(expression: expression, mode: mode)
            let sampler = preparedSampler(contract, slot: 2)!
            neighboring.append(["expression": expression, "mode": mode, "channelUse": sampler.channelUse.rawValue,
                "sourcePurpose": token(sampler.sourceProvenPurpose), "normalPurpose": token(sampler.purpose(for: .asset(normalPath)))])
        }
        let plain = preparedSampler(shader(), slot: 2)!
        let conflict = plain.withSourceProvenPurpose(.mask)
        let wrongSource = plain.withSourceProvenPurpose(.straightAlbedo)
        let conflicts = ["maskNormal":token(conflict.purpose(for:.asset(normalPath))),
            "maskNoise":token(conflict.purpose(for:.asset(noisePath))),
            "colorNormal":token(wrongSource.purpose(for:.asset(normalPath)))]
        let oldNoise = Schema.Sampler(name:"g_Texture2",slot:2,mode:.regular,materialKey:"albedo",
            isHidden:false,defaultTexture:nil,readinessCombo:nil,channelUse:.redOnly)
        var corruptions: [[String: Any]] = []
        for name in ["purpose","color","identity","generation","unknown","volume","lut"] {
            corruptions.append(run(device: device, queue: queue, renamed:false,
                candidatePath:normalPath,candidatePurpose:.normal,ready:true,corruption:name))
        }
        let domains: [SceneTextureLoadPurpose] = [.normal,.noise,.mask,.preservedChannels,.lookupTable,.straightAlbedo,.premultipliedColor]
        let output: [String: Any] = ["matrix":matrix,"neighboring":neighboring,"sourceConflicts":conflicts,
            "purposeDomains": domains.map { ["purpose":$0.reportToken,"data":$0.isDataPurpose,"volume":$0.requiresVolumeTexture] },
            "oldNoiseRedRule":token(oldNoise.purpose(for:.asset(noisePath))),"corruptions":corruptions,
            "selectionCounterexamples": [
                run(device:device,queue:queue,renamed:false,candidatePath:normalPath,
                    candidatePurpose:.normal,ready:true,lowerNoise:true),
                run(device:device,queue:queue,renamed:false,candidatePath:normalPath,
                    candidatePurpose:.normal,ready:true,candidateState:.pending),
                run(device:device,queue:queue,renamed:false,candidatePath:normalPath,
                    candidatePurpose:.normal,ready:true,candidateState:.unavailable),
            ]]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options:[.sortedKeys]),encoding:.utf8)!)
    }
}
'''


class SceneScalarMaskDataPurposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compilation, completed = fixture.compile_harness(fixture.SUPPORT, HARNESS)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        if completed is None or completed.returncode:
            raise RuntimeError(completed.stderr if completed else "own scalar fixture did not run")
        cls.result = json.loads(completed.stdout)

    def test_scalar_candidate_default_and_two_frame_gpu_keep_original_data(self) -> None:
        self.assertEqual(len(self.result["matrix"]), 8)
        for row in self.result["matrix"]:
            with self.subTest(renamed=row["renamed"], ready=row["candidateReady"], default=row["defaultReady"]):
                self.assertEqual(row["channelUse"], "redOnly", row)
                self.assertEqual(row["sourcePurpose"], "nil", row)
                self.assertEqual(row["directCandidatePurpose"], row["candidatePurpose"], row)
                self.assertEqual(row["slotFact"], row["candidatePurpose"], row)
                self.assertEqual(row["directDefaultPurpose"], "noise", row)
                self.assertEqual(row["launch"], "success", row)
                self.assertTrue(row["typedStaticDataSlot"], row)
                self.assertTrue(row["variantCompilationStable"], row)
                self.assertEqual(len(row["frames"]), 2, row)
                for frame in row["frames"]:
                    self.assertEqual(frame["finalization"], "success", row)
                    self.assertTrue(frame["gpuCompleted"], row)
                    expected_purpose = row["candidatePurpose"] if row["candidateReady"] else "noise"
                    self.assertEqual(frame["selectedPurpose"], expected_purpose, row)
                    self.assertEqual(frame["publicationPurpose"], expected_purpose, row)
                    if not row["candidateReady"]:
                        self.assertIn("asset" if row["defaultReady"] else "system", frame["selectedIdentity"], row)
                    self.assertEqual(frame["content"], "data", row)
                    self.assertEqual(frame["generation"], frame["frame"], row)
                    red = ([32,96,160,224] if frame["frame"] == 1 else [224,160,96,32]) if row["candidateReady"] else [16,48,80,112]
                    self.assertEqual(frame["pixelsRGBA"], [value for r in red for value in [r,r//2,64,255]], row)

    def test_variable_resource_and_equivalent_red_expression_have_same_pixels(self) -> None:
        for ready in [True, False]:
            for default_ready in [True,False]:
                rows = [row for row in self.result["matrix"] if row["candidateReady"] == ready and row["defaultReady"] == default_ready]
                self.assertNotEqual(rows[0]["candidatePath"], rows[1]["candidatePath"])
                self.assertNotEqual(rows[0]["candidatePurpose"], rows[1]["candidatePurpose"])
                self.assertNotEqual(rows[0]["defaultPath"], rows[1]["defaultPath"])
                self.assertEqual([frame["pixelsRGBA"] for frame in rows[0].get("frames",[])],
                    [frame["pixelsRGBA"] for frame in rows[1].get("frames",[])])

    def test_neighboring_reads_source_conflicts_and_old_noise_contract(self) -> None:
        self.assertEqual(self.result["oldNoiseRedRule"], "noise")
        self.assertEqual(self.result["sourceConflicts"], {"maskNormal":"nil","maskNoise":"nil","colorNormal":"nil"})
        for row in self.result["neighboring"]:
            self.assertEqual(row["normalPurpose"], "nil", row)
        domains = {row["purpose"]: row for row in self.result["purposeDomains"]}
        self.assertFalse(domains["straight-albedo"]["data"])
        self.assertFalse(domains["premultiplied-color"]["data"])
        self.assertTrue(domains["lookup-table"]["data"])
        self.assertTrue(domains["lookup-table"]["volume"])

    def test_wrong_resource_atoms_stay_hard(self) -> None:
        for row in self.result["corruptions"]:
            self.assertEqual(row["launch"], "success", row)
            for frame in row["frames"]:
                self.assertTrue(frame["finalization"].startswith("texture:textureMetadataIncomplete:"), row)
                self.assertNotIn("gpuCompleted", frame)

    def test_lower_candidate_conflict_and_unready_asset_are_not_hidden_by_default(self) -> None:
        rows = self.result["selectionCounterexamples"]
        self.assertEqual(len(rows), 3)
        conflict = next(row for row in rows if row["lowerNoise"])
        self.assertEqual(conflict["candidateOrdinal"], 1, conflict)
        self.assertEqual(conflict["directCandidatePurpose"], "normal", conflict)
        self.assertEqual(conflict["directDefaultPurpose"], "noise", conflict)
        self.assertEqual(conflict["slotFact"], "nil", conflict)
        self.assertEqual(conflict["launch"], "success", conflict)
        self.assertEqual(len(conflict["frames"]), 2, conflict)
        for frame in conflict["frames"]:
            self.assertEqual(frame["finalization"],
                "texture:texturePurposeUnproven:variant-purpose-slot-2-non-graph", conflict)
            self.assertNotIn("selectedPurpose", frame)
            self.assertNotIn("gpuCompleted", frame)
        for row in rows:
            if row["lowerNoise"]:
                continue
            self.assertIn(row["candidateState"], ["pending", "unavailable"], row)
            self.assertTrue(row["defaultReady"], row)
            self.assertEqual(row["directCandidatePurpose"], "normal", row)
            self.assertEqual(row["slotFact"], "normal", row)
            self.assertEqual(row["launch"], "texture:textureBindingInvalid:", row)
            self.assertNotIn("frames", row)


if __name__ == "__main__":
    unittest.main()
