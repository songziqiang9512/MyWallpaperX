import Foundation
import AVFoundation
import Metal
import QuartzCore
import simd

// Unrelated descriptor/command/renderer envelopes only. TEX admission, player,
// lifecycle, candidate/publication, registry, selection and GPU are real owners.
struct SceneFrameTiming { let frameIndex: UInt64; let hostTime: Double; let sceneTime: Double }
struct SceneScriptVideoPlaybackSnapshot {
    let layerID: Int; let duration: Double; let rate: Double; let loop: Bool
    let currentTime: Double; let isPlaying: Bool; let endedGeneration: UInt64
}
struct SceneScriptMediaPlaybackCommand {
    enum Destination { case videoTexture }
    enum Action { case play, pause, stop, setCurrentTime(Double), setRate(Double), setLoop(Bool) }
    let layerID: Int; let action: Action
    var destination: Destination { .videoTexture }
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int; let contentKind: String
        var imagePath: String? = nil; var staticBaseTexturePath: String? = nil
        var clampUVs: Bool? = nil; var noInterpolation: Bool? = nil
        var brightness: Double? = nil
        var effects: [EffectDescriptor] = []
    }
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int; let texturePaths: [String]; let textureSlots: [String?]
            let userTextureInputs: [String]; let combos: [String: Int]
        }
        let file: String; let visible: Bool?; let passes: [PassDescriptor]
    }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String }
    struct MaterialPass { let materialPath: String; let texturePaths: [String] }
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPass] = []
}
enum SceneMaterialPropertyBindingCompiler {
    struct SourceMaterialAlpha {
        let propertyTarget: SceneDynamicTarget?
        nonisolated func resolve(snapshot: SceneDynamicSnapshot) -> Float { fatalError("unrelated alpha route") }
    }
}
struct SceneBaseMaterialLightingProfile {}
struct SceneOffscreenTexturePool {}
struct SceneResolvedMaterialFrameTargetPlan {}
struct SceneLayerEffectSourceExtent { let pixelSize: CGSize }
struct SceneAudioSpectrumSnapshot { static let silent = Self() }
struct SceneAuthoredShaderFrameInputs {}
struct SceneGeometryProduct {}
struct SceneBaseMaterialLitCapturePayload {}
enum SceneGraphExecutionResetReason { case surfaceStop }
final class SceneResolvedMaterialRuntimeBridge {
    var shouldDeferFrame: Bool { fatalError("unrelated graph route") }
    func invalidate(reason: SceneGraphExecutionResetReason) { fatalError("unrelated graph route") }
}
// Only graph storage is stubbed. The compositor's source-sample and fragment
// uniform methods compile unchanged and drive the actual image GPU shader.
struct SceneImageLayerCompositor { let resolvedMaterialRuntime: SceneResolvedMaterialRuntimeBridge? = nil }
struct SceneBaseImageTextureSnapshot {
    var textures: [Int: MTLTexture] = [:]
    subscript(id: Int) -> MTLTexture? { textures[id] }
    func candidate(for id: Int, matching texture: MTLTexture) -> SceneTextureCandidate? { nil }
}
struct SceneMetalRenderer {
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let textureRegistry: SceneFrameTextureRegistry
}
enum ScenePerformanceCounter { case pipelineStateBinds }
enum SceneGPUStageTimestampHook { static func drew(_ encoder: MTLRenderCommandEncoder) {} }
final class ScenePerformanceCounterHub {
    static let shared = ScenePerformanceCounterHub()
    func bump(_ value: ScenePerformanceCounter) {}
    func recordDraw(usesGeometry: Bool) {}
}

@main enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let assetName = CommandLine.arguments[3], propertyName = CommandLine.arguments[4]
        let layerID = Int(CommandLine.arguments[5])!, videoLayerID = Int(CommandLine.arguments[6])!
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        let view = SceneResourceView(projectRootURL: root, packageRootURL: nil, stockAssetsRootURL: nil)
        let asset = SceneAssetTextureIdentity(virtualPath: assetName, purpose: .premultipliedColor)!
        let alias = SceneAssetTextureIdentity(virtualPath: "./" + assetName + ".tex", purpose: .premultipliedColor)!
        let invalid = SceneAssetTextureIdentity(virtualPath: "bad/truncated", purpose: .premultipliedColor)!
        let unsupported = SceneAssetTextureIdentity(virtualPath: assetName, purpose: .normal)!
        let still = SceneAssetTextureIdentity(virtualPath: "still.png", purpose: .premultipliedColor)!
        let catalog = SceneMaterialAssetTextureCatalog(demands: [asset, alias, invalid, unsupported, still],
            resourceView: view, descriptor: .init(), device: device)
        guard let declaration = catalog.videoDeclarations[asset],
              let aliasDeclaration = catalog.videoDeclarations[alias] else { fatalError("video declaration missing") }
        let loader = SceneTextureLoader()
        let registry = SceneVideoTextureSourceRegistry(epoch: 40)
        defer { registry.stop() }
        let cache = root.appendingPathComponent("cache")
        guard let source = registry.source(declaration: declaration, owner: .asset,
                  cacheDirectory: cache, device: device, loader: loader),
              let shared = registry.source(declaration: aliasDeclaration, owner: .asset,
                  cacheDirectory: cache, device: device, loader: loader),
              let layerSource = registry.source(from: declaration.url, layerID: videoLayerID,
                  cacheDirectory: cache, device: device, loader: loader) else { fatalError("registry source missing") }
        var checks: [String: Bool] = [
            "declarationIsNotReady": catalog.launchStates[asset] == .preparedVideoColor,
            "initialStatePending": {
                if case .pending? = catalog.makeFrameProvider().states(sceneTime: 0)[asset] { return true }
                return false
            }(),
            "aliasesSharePhysicalDecoder": source === shared,
            "layerPlaybackIsIndependent": source !== layerSource,
            "assetHasNoLayerSnapshot": source.playbackSnapshot(sceneTime: 0) == nil
                && Set(registry.sceneScriptSnapshots(sceneTime: 0).keys) == [videoLayerID],
            "unsupportedPurposeUnavailable": catalog.launchStates[unsupported] == .unavailable,
            "badTexUnavailable": catalog.launchStates[invalid] == .unavailable,
        ]
        let fragment = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let library = try device.makeLibrary(source: fragment, options: nil)
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .sourceOver, library: library)!
        let frameRegistry = SceneFrameTextureRegistry()
        let peerRegistry = SceneFrameTextureRegistry()
        let property = SceneUserPropertyTextureIdentity(propertyKey: propertyName, purpose: .premultipliedColor)!
        let binding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(layerID: layerID,
            source: .layerInstance, slotIndex: 0, provider: .userProperty(property), fallbackAsset: asset)
        let renderer = SceneMetalRenderer(baseMaterialProviderBindings: .init(baseMaterialBindings: [layerID: binding]),
            textureRegistry: frameRegistry)
        let layer = SceneRenderDescriptor.Layer(id: layerID, contentKind: "solid")
        var pixels: [[Float]] = [], generations: [UInt64] = []
        var firstPublication: SceneTextureProviderPublication?
        var latestPublication: SceneTextureProviderPublication?
        let start = CACurrentMediaTime()
        var frameIndex: UInt64 = 0
        func timing() -> SceneFrameTiming {
            frameIndex += 1; let now = CACurrentMediaTime()
            return .init(frameIndex: frameIndex, hostTime: now, sceneTime: now - start)
        }
        func select(_ publication: SceneTextureProviderPublication,
                    propertyState: SceneTextureProviderState = .absent,
                    override: Bool = false) -> SceneBaseMaterialTextureSource? {
            frameRegistry.beginFrame(frameIndex: frameIndex, layerSources: [:],
                assetStates: [asset: .ready(publication)], userPropertyStates: [property: propertyState])
            let result = renderer.baseMaterialTextureSelection(for: layer, imageTextures: .init(),
                readyProviderUsesAuthoredLayerColor: override).source
            frameRegistry.commitFramePublication()
            return result
        }
        while CACurrentMediaTime() - start < 3.2 {
            let time = timing()
            if let frame = source.prepareFrame(for: time),
               let publication = frame.assetPublication(for: asset), publication.isComplete,
               generations.last != frame.contentGeneration {
                guard let selected = select(publication) else { fatalError("asset resolver rejected frame") }
                let peer = shared.prepareFrame(for: time)!
                let aliasPublication = peer.assetPublication(for: alias)!
                peerRegistry.beginFrame(frameIndex: frameIndex, layerSources: [:], assetStates: [alias: .ready(aliasPublication)])
                checks["sameFrameSharedGeneration"] = checks["sameFrameSharedGeneration", default: true]
                    && peer.contentGeneration == frame.contentGeneration
                    && peer.texture === frame.texture
                checks["peerPublicationIsExact"] = checks["peerPublicationIsExact", default: true]
                    && peerRegistry.resource(for: .asset(alias))?.publication.requestIdentity == .asset(alias)
                pixels.append(try draw(selected, layer: layer, tint: selected.usesAuthoredLayerColor
                    ? .zero : SIMD3(repeating: 1), device: device, queue: queue, pipeline: pipeline))
                generations.append(frame.contentGeneration)
                if firstPublication == nil { firstPublication = publication }
                latestPublication = publication
                peerRegistry.commitFramePublication()
            }
            registry.commitPreparedFrame()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
        }
        guard let first = firstPublication else { fatalError("no complete decoded frame") }
        guard let latest = latestPublication else { fatalError("latest publication missing") }
        checks["videoBypassesBlackPlaceholder"] = pixels.contains { $0[0] > 0.9 && $0[2] < 0.1 }
            && pixels.contains { $0[2] > 0.9 && $0[0] < 0.1 }
        let tinted = select(latest, override: true)!
        let tintedPixel = try draw(tinted, layer: layer, tint: SIMD3(0.25, 0.5, 0.75), device: device, queue: queue, pipeline: pipeline)
        checks["dynamicColorOverrideRemainsActive"] = tinted.usesAuthoredLayerColor
            && zip(tintedPixel.prefix(3), zip(pixels.last!.prefix(3), [Float(0.25), 0.5, 0.75]))
                .allSatisfy { abs($0.0 - $0.1.0 * $0.1.1) < 0.02 }
        guard case let .ready(stillPublication)? = catalog.makeFrameProvider().states(sceneTime: 0)[still] else {
            fatalError("still fixture missing")
        }
        let selectedStill = SceneTextureProviderPublication(requestIdentity: .materialUserProperty(property),
            candidate: stillPublication.candidate, contentGeneration: 1)
        let stillSource = select(latest, propertyState: .ready(selectedStill))!
        let stillPixel = try draw(stillSource, layer: layer, tint: .init(repeating: 1), device: device, queue: queue, pipeline: pipeline)
        checks["selectedStillWins"] = stillSource.usesUserPropertyProvider && stillPixel[1] > 0.9
        let reset = select(latest)!
        checks["resetSelectsSameVideoAtom"] = reset.texture === latest.texture && !reset.usesAuthoredLayerColor
        let stale = select(first)!
        checks["oldGenerationCannotReplaceCurrent"] = stale.texture === latest.texture
        guard case let .provider(.videoAsset(_, incarnation, epoch)) = latest.candidate.identity else {
            fatalError("asset frame has no video identity")
        }
        func relabeled(_ identity: SceneTextureResourceIdentity,
                       purpose: SceneTextureLoadPurpose = .premultipliedColor) -> SceneTextureCandidate {
            let original = latest.candidate
            return .init(texture: original.texture, identity: identity, generation: original.generation,
                purpose: purpose, content: original.content, physicalSize: original.physicalSize,
                mappedSize: original.mappedSize, uvTransform: original.uvTransform,
                sampling: original.sampling, authoredFormat: original.authoredFormat)
        }
        func accepts(_ candidate: SceneTextureCandidate, kind: String = "solid", id: Int? = nil) -> Bool {
            let request = request(texture: candidate.texture, candidate: candidate,
                layer: .init(id: id ?? layerID, contentKind: kind), tint: .init(repeating: 1))
            return request.resolvedBaseTextureSample() != nil
                && SceneImageLayerCompositor().sourceFragmentUniforms(for: request, routesOffscreen: false) != nil
        }
        checks["solidRejectsLayerVideo"] = !accepts(relabeled(.provider(.video(layerID: layerID, lifecycleEpoch: epoch))))
        checks["solidRejectsDynamicText"] = !accepts(relabeled(.provider(.dynamicText(layerID: layerID))))
        checks["solidRejectsPreviousThumbnail"] = !accepts(relabeled(.provider(.mediaThumbnailPrevious)))
        checks["solidKeepsCurrentThumbnail"] = accepts(relabeled(.provider(.mediaThumbnailCurrent)))
        checks["textRejectsAssetVideo"] = !accepts(latest.candidate, kind: "text")
        let glyph = relabeled(.provider(.dynamicText(layerID: layerID)))
        checks["textKeepsExactGlyphOwner"] = accepts(glyph, kind: "text")
            && !accepts(glyph, kind: "text", id: layerID + 1)
        checks["zeroEpochRejectedByDrawRequest"] = !accepts(relabeled(.provider(.videoAsset(
            asset: asset, sourceIncarnation: incarnation, lifecycleEpoch: 0))))
        checks["wrongPurposeRejectedByDrawRequest"] = !accepts(relabeled(.provider(.videoAsset(
            asset: unsupported, sourceIncarnation: incarnation, lifecycleEpoch: epoch))))
        func frame(content: SceneTextureContent, epoch: UInt64 = 40) -> SceneVideoTextureSource.Frame {
            .init(texture: latest.texture, content: content, contentGeneration: latest.contentGeneration + 1,
                requestedItemTime: 0, decodedItemTime: 0, epoch: epoch, owner: .asset,
                sourceIncarnation: incarnation)
        }
        checks["assetCannotPublishAsLayer"] = frame(content: .color(.resolved(.opaque))).publication == nil
        checks["dataPurposeCannotRelabelVideo"] = frame(content: .color(.resolved(.opaque)))
            .assetPublication(for: unsupported) == nil
        for (name, content) in [("unknownAlpha", SceneTextureContent.color(.unresolved)),
                                ("straightAlpha", .color(.resolved(.straightAlpha)))] {
            let unproven = frame(content: content).assetPublication(for: asset)!
            let isolatedRegistry = SceneFrameTextureRegistry()
            isolatedRegistry.beginFrame(frameIndex: 1, layerSources: [:], assetStates: [asset: .ready(unproven)])
            if case .rejected = SceneBaseMaterialTextureResolver.resolveFallback(binding: binding, registry: isolatedRegistry) {
                checks[name + "CannotBecomeReady"] = !unproven.isComplete
            } else { checks[name + "CannotBecomeReady"] = false }
        }
        let wrongRequest = SceneTextureProviderPublication(requestIdentity: .asset(alias),
            candidate: latest.candidate, contentGeneration: latest.contentGeneration)
        checks["logicalRequestCannotAliasDifferentAsset"] = !wrongRequest.isComplete
        let olderEpoch = frame(content: .color(.resolved(.opaque)), epoch: epoch - 1)
            .assetPublication(for: asset)!
        frameRegistry.beginFrame(frameIndex: frameIndex + 1, layerSources: [:], assetStates: [asset: .ready(olderEpoch)])
        checks["olderEpochCannotReplaceCurrent"] = frameRegistry.resource(for: .asset(asset))?
            .publication.isSameAtom(as: latest) == true
        frameRegistry.commitFramePublication()
        let staticBinding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(layerID: layerID + 1,
            source: .layerInstance, slotIndex: 0, provider: .userProperty(property), fallbackAsset: still)
        frameRegistry.beginFrame(frameIndex: frameIndex + 1, layerSources: [:], assetStates: [still: .ready(stillPublication)],
            userPropertyStates: [property: .absent])
        let staticRenderer = SceneMetalRenderer(baseMaterialProviderBindings: .init(baseMaterialBindings: [layerID + 1: staticBinding]),
            textureRegistry: frameRegistry)
        let staticSource = staticRenderer.baseMaterialTextureSelection(for: .init(id: layerID + 1, contentKind: "solid"),
            imageTextures: .init()).source!
        let blackStatic = try draw(staticSource, layer: layer, tint: .zero, device: device, queue: queue, pipeline: pipeline)
        checks["staticFallbackKeepsAuthoredColor"] = staticSource.usesAuthoredLayerColor && blackStatic.prefix(3).allSatisfy { abs($0) < 0.001 }
        frameRegistry.commitFramePublication()
        let beforePause = Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!.rate
        _ = registry.apply([.init(layerID: videoLayerID, action: .pause)], timing: timing())
        checks["layerCommandsDoNotControlAsset"] = beforePause > 0
            && Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!.rate > 0
            && registry.sceneScriptSnapshots(sceneTime: 3.2)[videoLayerID]?.isPlaying == false
        registry.pause(sceneTime: 3.2, hostTime: CACurrentMediaTime())
        checks["globalPauseControlsAsset"] = Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!.rate == 0
        registry.resume(sceneTime: 3.2, hostTime: CACurrentMediaTime())
        registry.beginSurfaceRebuild(sceneTime: 3.2, hostTime: CACurrentMediaTime())
        let reacquired = registry.source(declaration: declaration, owner: .asset, cacheDirectory: cache,
            device: device, loader: loader)
        registry.completeSurfaceRebuild()
        checks["rebuildReusesAssetAndRetiresLayer"] = reacquired === source
            && registry.sceneScriptSnapshots(sceneTime: 3.2).isEmpty
        let oldDeclaration = declaration
        try Data([0x11]).appendTo(declaration.url)
        checks["staleSourceCannotAcquire"] = registry.source(declaration: oldDeclaration, owner: .asset,
            cacheDirectory: cache, device: device, loader: loader) == nil
        registry.stop()
        checks["stopRemovesFramesAndPayloads"] = source.prepareFrame(for: timing()) == nil
            && ((try? FileManager.default.contentsOfDirectory(atPath: cache
                .appendingPathComponent(".mywallpaperx-scene-video-payloads").path)) ?? []).isEmpty
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks,
            "pixels": pixels, "generations": generations, "tinted": tintedPixel, "still": stillPixel],
            options: [.sortedKeys]), as: UTF8.self))
    }

    static func draw(_ source: SceneBaseMaterialTextureSource, layer: SceneRenderDescriptor.Layer, tint: SIMD3<Float>, device: MTLDevice,
                     queue: MTLCommandQueue, pipeline: SceneImageLayerPipeline) throws -> [Float] {
        let request = request(texture: source.texture, candidate: source.candidate, layer: layer, tint: tint)
        let compositor = SceneImageLayerCompositor()
        guard request.resolvedBaseTextureSample() != nil,
              let uniforms = compositor.sourceFragmentUniforms(for: request,
                routesOffscreen: false) else { fatalError("production request/compositor rejected source") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
            width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
        let output = device.makeTexture(descriptor: descriptor)!
        let command = queue.makeCommandBuffer()!, pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output; pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(texture: request.texture, mvp: request.mvp,
            uniforms: uniforms, encoder: encoder)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        guard command.status == .completed, command.error == nil else { fatalError("GPU composition failed") }
        var pixel = [Float16](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 8,
            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }
        return pixel.map(Float.init)
    }

    static func request(texture: MTLTexture, candidate: SceneTextureCandidate?,
                        layer: SceneRenderDescriptor.Layer, tint: SIMD3<Float>) -> SceneImageLayerDrawRequest {
        .init(layer: layer, texture: texture, baseTextureCandidate: candidate,
            masks: .empty, textureFrame: .identity,
            mvp: simd_float4x4(diagonal: SIMD4(2, 2, 1, 1)),
            uniforms: .init(time: 0, alpha: 1, cursorUV: .zero, tint: tint),
            offscreenTexturePool: nil, effectSourceExtent: nil,
            requiresSourceCopy: false, finalCompositeAlpha: nil)
    }
}

extension Data {
    func appendTo(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: self)
    }
}
