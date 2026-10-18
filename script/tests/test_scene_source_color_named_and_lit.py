#!/usr/bin/env python3
"""Real named-source publication and lit capture representation regressions.

Prepared plan scaffolding is reused; capture, registry, allocation and Metal
are production owners. Every production input is frozen before compilation.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from script.tests import test_scene_named_model_shadow as named
from script.tests import test_scene_texture_candidate as textures
from script.tests.test_scene_directional_shadow import run_swift

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def run_frozen(sources, support, label, metal_sources, read_inputs=()):
    with tempfile.TemporaryDirectory(prefix="mwx-source-color-final-") as temporary:
        work = Path(temporary)
        frozen, identities = {}, {}
        metal_headers = {metal.parent / header for metal in metal_sources
                         for header in ("SceneDistanceFog.metalh", "SceneSurfaceResponse.metalh")
                         if (metal.parent / header).is_file()}
        for source in dict.fromkeys([*sources, *metal_sources, *sorted(metal_headers), *read_inputs]):
            destination = work / "production" / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = source.read_bytes()
            destination.write_bytes(data)
            frozen[source] = destination
            identities[str(source.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
        if callable(support):
            support = support(frozen)
        keys = ("MWX_DIRECTIONAL_SHADOW_EVIDENCE", "MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT")
        previous = {key: os.environ.get(key) for key in keys}
        os.environ[keys[0]] = str(work)
        os.environ.pop(keys[1], None)
        try:
            report = run_swift([frozen[p] for p in sources], support, label=label,
                               metal_sources=[frozen[p] for p in metal_sources])
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        drift = [path for path, digest in identities.items()
                 if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest]
        if drift:
            raise AssertionError(f"production source changed during gate: {drift}")
        if parent := os.environ.get("MWX_SOURCE_COLOR_FINAL_EVIDENCE"):
            destination = Path(parent)
            destination.mkdir(parents=True, exist_ok=True)
            (destination / f"{label}.json").write_text(json.dumps({
                "inputs": identities, "harnessSHA256": hashlib.sha256(support.encode()).hexdigest(),
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "productSourceDrift": drift, "result": report,
            }, indent=2) + "\n")
        return report


PROVIDER_HELPER = SCENE / "Rendering/Frame/SceneMetalRenderer+DependencyProviders.swift"
COMPLETED_SOURCE_UNIFORMS = SCENE / "Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift"


def local_named_support(frozen):
    support = named.dependency_support()
    start = support.index("enum SceneCaptureGeometryResolver")
    support = support[:start] + support[support.index("enum SceneTextureLoadOutcome", start):]
    support = support.replace("enum Kind { case composition }", "enum Kind { case composition, fullscreen, project }")
    source = frozen[PROVIDER_HELPER].read_text()
    method = source[source.index("    func captureRawDependencyProvider("):
                    source.index("    func prepareForwardDependencyProviders(")]
    uniforms = frozen[COMPLETED_SOURCE_UNIFORMS].read_text().split("extension SceneImageLayerCompositor {", 1)[0]
    return support + uniforms + LOCAL_NAMED_DTOS + "\nextension SceneMetalRenderer {\n" + method + "}\n" + LOCAL_NAMED_MAIN


# Only adjacent DTOs are supplied. The selected production helper is compiled
# unchanged from its frozen input; capture, geometry, pool and publication are real.
LOCAL_NAMED_DTOS = r'''
struct SceneFrameContext { let dynamicValues = 0; let cameraParallaxPosition = SIMD2<Float>.zero }
struct SceneParticleCameraFrame {
    let coverHalfExtents = SIMD2<Float>(128, 128)
    func resolvesPerspective(for layer: SceneRenderDescriptor.Layer) -> Bool { false }
    func captureViewProjection(for layer: SceneRenderDescriptor.Layer) -> simd_float4x4 { matrix_identity_float4x4 }
}
enum SceneLayerParallax { struct Configuration {} }
enum SceneDynamicLayerValues {
    static func alpha(layerID: Int, authoredValue: Double?, snapshot: Int) -> Double { authoredValue ?? 1 }
    static func color(layerID: Int, authoredValue: [Double]?, snapshot: Int) -> SIMD3<Float> {
        SIMD3(authoredValue ?? [1, 1, 1], fill: 1)
    }
}
struct SceneBaseMaterialTextureSource {
    let texture: MTLTexture; let candidate: SceneTextureCandidate?; let usesAuthoredLayerColor: Bool
}
struct SceneBaseImageTextureSnapshot {
    let geometryProducts: [Int: SceneGeometryProduct] = [:]
    func layerSourceRenderSize(for id: Int) -> [Float]? { nil }
    func layerSourceTextCenterOffsetY(for id: Int) -> Float? { nil }
}
final class SceneMetalRenderer {
    let dependencyRuntime: SceneDependencyFrameRuntime; let textureRegistry: SceneFrameTextureRegistry
    init(_ runtime: SceneDependencyFrameRuntime, _ registry: SceneFrameTextureRegistry) {
        dependencyRuntime = runtime; textureRegistry = registry
    }
    // Canonical world MVP is supplied by the probe; this DTO does not implement
    // camera, parent or layer transformation behavior a second time.
    func imageModelMatrix(for layer: SceneRenderDescriptor.Layer,
        worldFramesByLayerID: [Int: simd_float4x4], renderSizeOverride: [Float]?,
        textCenterOffsetY: Float, parallaxMouseNormalized: SIMD2<Float>,
        configuration: SceneLayerParallax.Configuration, visibleHalfExtents: SIMD2<Float>,
        usesPerspective: Bool) -> simd_float4x4 { worldFramesByLayerID[layer.id]! }
}
'''

LOCAL_NAMED_MAIN = r'''
@main enum LocalNamedProviderProbe {
    static func texture(_ device: MTLDevice, _ width: Int, _ height: Int,
                        marker: Bool = false) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .renderTarget]
        let result = device.makeSceneTexture(descriptor: d)!
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4, red = marker && (40..<48).contains(x)
            bytes[i] = red ? 0 : 255; bytes[i+1] = 0; bytes[i+2] = red ? 255 : 0
        } }
        bytes.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return result
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device) else {
            print("{\"metalUnavailable\":true}"); return
        }
        func binding(_ provider: Int, _ consumer: Int, _ kind: SceneDependencyRenderPlan.Binding.Kind)
            -> SceneDependencyRenderPlan.Binding {
            .init(consumerLayerID: consumer, providerLayerID: provider,
                slot: .init(effectID: "own-local-named", passIndex: 0, slotIndex: 1), blendMode: 0, kind: kind)
        }
        let provider = SceneRenderDescriptor.Layer(id: 500, contentKind: "composition",
            utilityLayer: .init(kind: .composition), alpha: 1, colorRGB: [1, 1, 1])
        let link = binding(500, 501, .resolvedMaterial), registry = SceneFrameTextureRegistry()
        let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider],
            bindings: [501: link], graphOutputProviderLayerIDs: []), visibleLayerIDs: [500, 501],
            executableUtilityConsumerLayerIDs: [], device: device)
        let renderer = SceneMetalRenderer(runtime, registry), command = queue.makeCommandBuffer()!
        let attachment = texture(device, 128, 128, marker: true)
        let parentGeometry = SceneCompositionSourceGeometry(authoredRenderSizeWH: [128, 128],
            worldMVP: matrix_identity_float4x4)!
        let main = SceneMainPassEncoder(commandBuffer: command, target: attachment,
            clearColor: MTLClearColor(), clearEnabled: false,
            worldClipToTargetClip: parentGeometry.worldClipToSourceClip)
        let worldMVP = SceneMatrix.scale(SIMD3(0.5, 0.5, 1))
        func capture(_ capacity: Bool) -> SceneGraphOutputPublicationResult? {
            renderer.captureRawDependencyProvider(layer: provider, source: nil,
                imageTextures: .init(), imagePipeline: pipeline, frameContext: .init(),
                worldFrames: [500: worldMVP], cameraFrame: .init(), parallax: .init(),
                viewportSize: CGSize(width: 256, height: 256), mainPass: main, preparesCapacityOnly: capacity)
        }
        var facts = ["utilityCapacityUsesAttachment": capture(true) == nil,
                     "utilityPublicationSucceeded": capture(false) == .published]
        let reference = SceneNamedTextureReference(providerLayerID: 500, variant: .primary)
        let output = registry.completeNamedLayerTargetResource(reference: reference, frameEpoch: epoch)!.publication.texture
        facts["utilityPhysicalExtent"] = output.width == 64 && output.height == 64
        let pixels = device.makeBuffer(length: 64 * 256, options: .storageModeShared)!
        main.closeForOffscreen()
        let blit = command.makeBlitCommandEncoder()!
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: output.width, height: output.height, depth: 1), to: pixels,
            destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 64 * 256)
        blit.endEncoding(); precondition(main.finishEnsuringClear())
        main.armCompositionPins(); command.commit(); command.waitUntilCompleted()
        let bytes = pixels.contents().assumingMemoryBound(to: UInt8.self)
        func rgba(_ x: Int) -> [UInt8] { let i = 20 * 256 + x * 4
            return [bytes[i+2], bytes[i+1], bytes[i], bytes[i+3]] }
        facts["utilitySamplesEnclosingLocalCoordinates"] = rgba(10) == [255, 0, 0, 255]
            && rgba(30) == [0, 0, 255, 255]
        facts["utilityGPUCompleted"] = command.status == .completed && command.error == nil

        // A graph's prepared output extent supersedes projected utility size.
        var graphProvider = provider; graphProvider.effects = [.init(visible: true)]
        let graphRuntime = SceneDependencyFrameRuntime(descriptor: .init(layers: [graphProvider],
            bindings: [501: link], graphOutputProviderLayerIDs: [500]), visibleLayerIDs: [500, 501],
            executableUtilityConsumerLayerIDs: [], device: device)
        let graphRegistry = SceneFrameTextureRegistry()
        let graphEpoch = graphRegistry.beginFrame(frameIndex: 2, layerSources: [:])
        var reason: String?
        let reserved = graphRuntime.reserveEffectInput(for: link, providerLayer: graphProvider,
            providerTexture: nil, providerCandidate: nil, layerMVP: worldMVP,
            viewportSize: CGSize(width: 256, height: 256), preparedOutputExtent: (32, 16),
            frameEpoch: graphEpoch, failureReason: &reason)
        let graphCommand = queue.makeCommandBuffer()!, graphOutput = texture(device, 32, 16)
        facts["preparedUtilityGraphExtentPreserved"] = reason == nil
            && reserved?.texture.width == 32 && reserved?.texture.height == 16
        facts["preparedUtilityGraphPublished"] = graphRuntime.publishGraphOutputIfRequired(layerID: 500,
            texture: graphOutput, publicationRole: .namedProviderPrepass,
            textureRegistry: graphRegistry, commandBuffer: graphCommand) == .published
        graphCommand.commit(); graphCommand.waitUntilCompleted()
        facts["graphGPUCompleted"] = graphCommand.status == .completed && graphCommand.error == nil

        // The enclosing mapping must not redefine independent asset publication.
        let asset = SceneRenderDescriptor.Layer(id: 610, contentKind: "image", utilityLayer: nil,
            alpha: 1, colorRGB: [1, 1, 1]), assetLink = binding(610, 611, .imageLayerBlend)
        let assetRegistry = SceneFrameTextureRegistry(), assetSource = texture(device, 8, 4)
        let assetEpoch = assetRegistry.beginFrame(frameIndex: 3, layerSources: [:])
        let atom = SceneTextureCandidate(texture: assetSource, identity: .builtIn(name: "own-independent-asset"),
            generation: .immutable(revision: 1), purpose: .premultipliedColor,
            content: .color(.resolved(.premultipliedAlpha)), physicalSize: CGSize(width: 8, height: 4),
            mappedSize: CGSize(width: 8, height: 4), uvTransform: .identity, sampling: .linearClamp)
        let assetRuntime = SceneDependencyFrameRuntime(descriptor: .init(layers: [asset],
            bindings: [611: assetLink], graphOutputProviderLayerIDs: []), visibleLayerIDs: [610, 611],
            executableUtilityConsumerLayerIDs: [], device: device)
        let assetCommand = queue.makeCommandBuffer()!
        let assetMain = SceneMainPassEncoder(commandBuffer: assetCommand, target: attachment,
            clearColor: MTLClearColor(), clearEnabled: false,
            worldClipToTargetClip: parentGeometry.worldClipToSourceClip)
        facts["independentAssetPublicationPreserved"] = SceneMetalRenderer(assetRuntime, assetRegistry)
            .captureRawDependencyProvider(layer: asset,
                source: .init(texture: assetSource, candidate: atom, usesAuthoredLayerColor: true),
                imageTextures: .init(), imagePipeline: pipeline, frameContext: .init(),
                worldFrames: [610: worldMVP], cameraFrame: .init(), parallax: .init(),
                viewportSize: CGSize(width: 256, height: 256), mainPass: assetMain) == .published
        let assetOutput = assetRegistry.completeNamedLayerTargetResource(reference:
            .init(providerLayerID: 610, variant: .primary), frameEpoch: assetEpoch)?.publication.texture
        facts["independentAssetExtentPreserved"] = assetOutput?.width == 8 && assetOutput?.height == 4
        precondition(assetMain.finishEnsuringClear()); assetMain.armCompositionPins()
        assetCommand.commit(); assetCommand.waitUntilCompleted()
        facts["assetGPUCompleted"] = assetCommand.status == .completed && assetCommand.error == nil
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


NAMED_MAIN = r'''
@main enum NamedSourceColorProbe {
    static func texture(_ d: MTLDevice, bytes: [UInt8]) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
        let result = d.makeSceneTexture(descriptor: descriptor)!
        let data = Array(repeating: bytes, count: 4).flatMap { $0 }
        data.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
        return result
    }
    static func candidate(_ t: MTLTexture, _ representation: SceneShaderColorRepresentation) -> SceneTextureCandidate {
        .init(texture: t, identity: .builtIn(name: "own-named-source"), generation: .immutable(revision: 1),
            purpose: representation == .straightAlpha ? .straightAlbedo : .premultipliedColor,
            content: .color(.resolved(representation)), physicalSize: CGSize(width: 2, height: 2),
            mappedSize: CGSize(width: 2, height: 2), uvTransform: .identity, sampling: .linearClamp)
    }
    static func read(_ t: MTLTexture, _ d: MTLDevice, _ cb: MTLCommandBuffer) -> MTLBuffer {
        let buffer = d.makeBuffer(length: 512, options: .storageModeShared)!, blit = cb.makeBlitCommandEncoder()!
        blit.copy(from: t, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: 2, height: 2, depth: 1), to: buffer, destinationOffset: 0,
            destinationBytesPerRow: 256, destinationBytesPerImage: 512)
        blit.endEncoding(); return buffer
    }
    static func pixels(_ buffer: MTLBuffer) -> [[UInt8]] {
        [0, 260].map { offset in Array(UnsafeBufferPointer(start:
            buffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: 4)) }
    }
    static func main() throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue(),
              let image = SceneImageLayerPipeline(device: d) else {
            print("{\"metalUnavailable\":true}"); return
        }
        let provider = SceneRenderDescriptor.Layer(id: 500, contentKind: "image", utilityLayer: nil,
            alpha: 1, colorRGB: [1, 1, 1])
        let binding = SceneDependencyRenderPlan.Binding(consumerLayerID: 501, providerLayerID: 500,
            slot: .init(effectID: "own-named", passIndex: 0, slotIndex: 1), blendMode: 0, kind: .imageLayerBlend)
        let reference = SceneNamedTextureReference(providerLayerID: 500, variant: .primary)
        func runtime(_ model: Bool) -> SceneDependencyFrameRuntime {
            .init(descriptor: .init(layers: [provider], bindings: model ? [:] : [501: binding],
                graphOutputProviderLayerIDs: [], staticModelConsumerProviders: model ? [610: 500] : [:]),
                visibleLayerIDs: [500, 501], executableUtilityConsumerLayerIDs: [], device: d)
        }
        let modelReader = runtime(true), authored: [UInt8] = [51, 102, 204]
        let tint: [Float] = [0.6, 0.4, 0.2]
        func byte(_ value: Float) -> UInt8 { UInt8(clamping: Int(value.rounded())) }
        var rows: [[String: Any]] = []
        for model in [false, true] {
            for representation: SceneShaderColorRepresentation in [.straightAlpha, .premultipliedAlpha, .opaque] {
                for alpha: UInt8 in [0, 128, 255] where representation != .opaque || alpha == 255 {
                    for opacity: Float in [0, 0.4, 1] {
                        let producer = runtime(model), registry = SceneFrameTextureRegistry()
                        let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:]), cb = q.makeCommandBuffer()!
                        let straight = representation == .straightAlpha
                        let rgb = representation == .premultipliedAlpha
                            ? authored.map { byte(Float($0) * Float(alpha) / 255) } : authored
                        let source = texture(d, bytes: rgb + [alpha]), atom = candidate(source, representation)
                        var reason: String?
                        let reserved = model ? nil : producer.reserveEffectInput(for: binding, providerLayer: provider,
                            providerTexture: source, providerCandidate: atom, layerMVP: matrix_identity_float4x4,
                            viewportSize: CGSize(width: 2, height: 2), frameEpoch: epoch, failureReason: &reason)
                        let main = SceneMainPassEncoder(commandBuffer: cb, target: texture(d, bytes: [0, 0, 0, 0]),
                            clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true)
                        let published = producer.captureProviderIfRequired(layer: provider, sourceTexture: source,
                            sourceCandidate: atom, providerAlpha: opacity, providerColor: SIMD3(0.2, 0.4, 0.6),
                            layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 2, height: 2),
                            pipeline: image, textureRegistry: registry, mainPass: main)
                        guard let resource = registry.completeNamedLayerTargetResource(reference: reference, frameEpoch: epoch) else {
                            rows.append(["published": false, "model": model, "straight": straight]); continue
                        }
                        let modelInput = modelReader.staticModelNamedAlbedo(for: 610,
                            materialPath: "materials/unseen/runtime.json", expectedReference: reference, textureRegistry: registry)
                        // A reserved provider must recognize straight as already complete.
                        let repeated = producer.captureProviderIfRequired(layer: provider, sourceTexture: source,
                            sourceCandidate: atom, providerAlpha: 0, providerColor: .zero,
                            layerMVP: matrix_identity_float4x4, viewportSize: CGSize(width: 2, height: 2),
                            pipeline: image, textureRegistry: registry, mainPass: main)
                        // A fresh, unreserved provider also recognizes the same typed publication.
                        let unreservedRepeat = runtime(model).captureProviderIfRequired(layer: provider,
                            sourceTexture: nil, sourceCandidate: nil, layerMVP: matrix_identity_float4x4,
                            viewportSize: CGSize(width: 2, height: 2), pipeline: image,
                            textureRegistry: registry, mainPass: main)
                        let output = read(resource.publication.texture, d, cb)
                        main.armCompositionPins(); precondition(main.finishEnsuringClear())
                        cb.commit(); cb.waitUntilCompleted()
                        let expectedRGB = model ? (0..<3).map { byte(Float(rgb[$0]) * tint[$0] * (straight ? 1 : opacity)) } : rgb
                        let expected = expectedRGB + [model ? byte(Float(alpha) * opacity) : alpha]
                        let content: SceneTextureContent = .color(.resolved(straight ? .straightAlpha : .premultipliedAlpha))
                        rows.append(["model": model, "straight": straight, "opaqueInput": representation == .opaque,
                            "alpha": alpha, "opacity": opacity, "published": published == .published,
                            "reservedIdentity": model || (reason == nil && reserved?.texture === resource.publication.texture),
                            "actualContent": resource.publication.candidate.content == content,
                            "actualPurpose": resource.publication.candidate.purpose == (straight ? .straightAlbedo : .premultipliedColor),
                            "modelInputReady": modelInput?.texture === resource.publication.texture,
                            "modelInputRepresentation": modelInput?.isPremultiplied == !straight,
                            "repeatReady": repeated == .published && unreservedRepeat == .published,
                            "bareTextureStaysPMAOnly": (registry.completeNamedLayerTargetTexture(reference: reference,
                                frameEpoch: epoch) != nil) == !straight,
                            "completed": cb.status == .completed && cb.error == nil,
                            "pixels": pixels(output), "expected": expected])
                    }
                }
            }
        }
        let registry = SceneFrameTextureRegistry(), target = texture(d, bytes: [51, 102, 204, 128])
        let epoch = registry.beginFrame(frameIndex: 1, layerSources: [:])
        _ = registry.publishReservedNamedLayerTarget(reference: reference, frameEpoch: epoch, texture: target, content: .data)
        let dataRejected = modelReader.staticModelNamedAlbedo(for: 610, materialPath: "materials/unseen/runtime.json",
            expectedReference: reference, textureRegistry: registry) == nil
        // A publication generation is immutable. Each independent content
        // probe receives its own registry rather than reinterpreting DATA.
        let opaqueRegistry = SceneFrameTextureRegistry()
        let opaqueEpoch = opaqueRegistry.beginFrame(frameIndex: 1, layerSources: [:])
        let opaqueTarget = texture(d, bytes: [51, 102, 204, 255])
        _ = opaqueRegistry.publishReservedNamedLayerTarget(reference: reference, frameEpoch: opaqueEpoch, texture: opaqueTarget,
            content: .color(.resolved(.opaque)))
        let opaqueIsStraight = modelReader.staticModelNamedAlbedo(for: 610, materialPath: "materials/unseen/runtime.json",
            expectedReference: reference, textureRegistry: opaqueRegistry)?.isPremultiplied == false
        let signalRegistry = SceneFrameTextureRegistry()
        let signalEpoch = signalRegistry.beginFrame(frameIndex: 1, layerSources: [:])
        let signalRejected = !signalRegistry.publishReservedNamedLayerTarget(reference: reference, frameEpoch: signalEpoch, texture: target,
            content: .color(.resolved(.independentAlphaSignal)))
        let foreignReferenceRejected = modelReader.staticModelNamedAlbedo(for: 610,
            materialPath: "materials/unseen/runtime.json", expectedReference: .init(providerLayerID: 999, variant: .primary),
            textureRegistry: registry) == nil
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows, "dataRejected": dataRejected,
            "opaqueInputUnassociated": opaqueIsStraight, "signalPublicationRejected": signalRejected,
            "foreignReferenceRejected": foreignReferenceRejected], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


LIT_MAIN = r'''
@main enum LitSourceColorProbe {
    static func texture(_ d: MTLDevice, _ value: SIMD4<Float>) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
        let result = d.makeTexture(descriptor: descriptor)!, bytes = [value.x, value.y, value.z, value.w].map(Float16.init)
        bytes.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 8) }; return result
    }
    static func pixel(_ t: MTLTexture) -> [Float] {
        var values = [Float16](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { t.getBytes($0.baseAddress!, bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }; return values.map(Float.init)
    }
    static func main() throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue(), let library = d.makeDefaultLibrary(),
              let base = SceneImageLayerPipeline(device: d, pixelFormat: .rgba16Float, library: library),
              let lit = SceneLitImageLayerPipeline(device: d, pixelFormat: .rgba16Float, library: library),
              let wrong = SceneLitImageLayerPipeline(device: d, pixelFormat: .bgra8Unorm, library: library) else {
            print("{\"metalUnavailable\":true}"); return
        }
        typealias Capture = SceneBaseMaterialLitCapturePayload
        let authored = SIMD3<Float>(2, 0.6, 0.25), tint = SIMD3<Float>(0.5, 0.25, 0.75), ambient = SIMD3<Float>(0.2, 0.3, 0.4)
        let lights = Capture.packLights(pointLights: [], spotLights: [], ambient: ambient, material: .zero,
            view: SIMD4(0, 0, 1, 0), layerModelMatrix: matrix_identity_float4x4,
            normalModelMatrix: matrix_identity_float4x4)!
        var rows: [[String: Any]] = []
        for valid in [true, false] { for straight in [false, true] { for alpha: Float in [0, 0.5, 1] {
            for opacity: Float in [0, 0.4, 1] {
                let rgb = straight ? authored : authored * alpha
                let source = texture(d, SIMD4(rgb, alpha)), output = texture(d, .zero), original = pixel(source)
                let payload = Capture(pipeline: valid ? lit : wrong, lights: lights, normal: .disabled)!
                let uniforms = SceneLayerFragmentUniforms(time: 0, alpha: opacity, dependencyBlendMode: 0,
                    usesDependencyBlend: 0, cursorUV: .zero, sourceSampling: SIMD2(0, straight ? 1 : 0),
                    tint: SIMD4(tint, 1), textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
                let encoder = SceneGraphResourcePassEncoder(commandQueue: q), cb = q.makeCommandBuffer()!
                let prepared = encoder.prepareSourceCapture(source: source, target: output, uniforms: uniforms,
                    pipeline: base, sourceLighting: payload)!
                let accepted = encoder.encode(prepared, commandBuffer: cb)
                cb.commit(); cb.waitUntilCompleted()
                let expectedRGB = valid ? authored * alpha * ambient * tint * opacity
                    : authored * tint * (straight ? 1 : alpha * opacity)
                rows.append(["validLighting": valid, "straight": straight, "alpha": alpha, "opacity": opacity,
                    "completed": accepted && cb.status == .completed && cb.error == nil,
                    "actualOutputContract": prepared.preservesStraightSourceColor == (!valid && straight),
                    "sourceUnchanged": pixel(source) == original, "actual": pixel(output),
                    "expected": [expectedRGB.x, expectedRGB.y, expectedRGB.z, alpha * opacity]])
            }
        } } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSourceColorNamedAndLitTests(unittest.TestCase):
    def test_actual_local_utility_named_capture_and_prepared_graph_extent(self):
        sources = list(dict.fromkeys([*named.DEPENDENCY_SOURCES, *[SCENE / path for path in (
            "Rendering/Geometry/SceneCaptureGeometry.swift", "Rendering/Geometry/SceneLayerCursorGeometry.swift")]]))
        report = run_frozen(sources, local_named_support, "local-utility-named",
                            [SCENE / "Rendering/Composition/SceneImageLayer.metal"],
                            read_inputs=[PROVIDER_HELPER, COMPLETED_SOURCE_UNIFORMS])
        self.assertEqual(len(report), 11, report)
        self.assertTrue(all(report.values()), report)

    def test_actual_named_capture_readiness_model_representation_and_data_rejection(self):
        report = run_frozen(named.DEPENDENCY_SOURCES, named.dependency_support() + NAMED_MAIN,
                            "named-source-color", [SCENE / "Rendering/Composition/SceneImageLayer.metal"])
        self.assertEqual(len(report["rows"]), 42)
        for row in report["rows"]:
            for key, value in row.items():
                if isinstance(value, bool) and key not in {"model", "straight", "opaqueInput"}:
                    self.assertTrue(value, (key, row))
            for pixel in row["pixels"]:
                for actual, expected in zip(pixel, row["expected"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=1, msg=row)
        for key in ("dataRejected", "opaqueInputUnassociated", "signalPublicationRejected", "foreignReferenceRejected"):
            self.assertTrue(report[key], report)

    def test_actual_lit_straight_association_and_unlit_fallback_publication_contract(self):
        sources = list(dict.fromkeys([*textures.SWIFT_SOURCES, *[SCENE / path for path in (
            "Rendering/Metal/SceneMetalPipeline.swift", "Rendering/Metal/SceneLitImageLayerPipeline.swift",
            "Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift",
            "Rendering/Graph/SceneGraphResourcePassEncoder.swift", "Diagnostics/ScenePerformanceCounterHub.swift",
            "Diagnostics/SceneGPUCensus.swift")]]))
        support = textures.HARNESS.split("@main", 1)[0] + r'''
import simd
struct SceneGraphRenderTargetPlan { struct ClearColor { let red: Double; let green: Double; let blue: Double; let alpha: Double } }
enum SceneMatrix { static func scale(_ value: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(value, 1)) } }
''' + LIT_MAIN
        report = run_frozen(sources, support, "lit-source-color", [SCENE / f"Rendering/Composition/{name}.metal"
                            for name in ("SceneImageLayer", "SceneLitImageLayer")])
        self.assertEqual(len(report["rows"]), 36)
        for row in report["rows"]:
            for key in ("completed", "actualOutputContract", "sourceUnchanged"):
                self.assertTrue(row[key], (key, row))
            for actual, expected in zip(row["actual"], row["expected"], strict=True):
                self.assertAlmostEqual(actual, expected, delta=0.002, msg=row)


if __name__ == "__main__":
    unittest.main()
