import Foundation
import Darwin
import CryptoKit
import AVFoundation
import Metal
import QuartzCore
import simd

// Unrelated descriptor/command/renderer envelopes only. TEX admission, player,
// lifecycle, candidate/publication, registry, selection and GPU are real owners.
struct SceneFrameTiming { let frameIndex: UInt64; let hostTime: Double; let sceneTime: Double }
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
// This video-only fixture has no authored lighting or reflection surfaces.
struct SceneBaseMaterialLightingProfile { var surfaceEnabled: Bool { false } }
struct SceneOffscreenTexturePool {}
struct SceneMainPassEncoder {}
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
    var initialVideoReadiness: [Int: SceneOrdinaryVideoFrameReadiness]? = nil
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
        #if MWX_COMPLETED_WEBM_REUSE
        if CommandLine.arguments[3] == "--storage" {
            try storage(root: root, external: URL(fileURLWithPath: CommandLine.arguments[4]))
            return
        }
        if CommandLine.arguments[3] == "--completed-webm-reuse" {
            try completedWebMReuse(root: root)
            return
        }
        #endif
        #if MWX_REGISTRY_INPUT_IO
        if CommandLine.arguments[3] == "--registry-input-io" {
            try registryInputIO(root: root)
            return
        }
        #endif
        var cleanupDirectory: URL!
        weak var stoppedSource: SceneVideoTextureSource?
        weak var stoppedFile: SceneVideoOwnedFile?
        weak var stoppedAsset: AVAsset?
        var result: [String: Any] = try autoreleasepool {
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
            let catalog = try SceneMaterialAssetTextureCatalog(demands: [asset, alias, invalid, unsupported, still],
                resourceView: view, descriptor: .init(), device: device)
            guard let declaration = catalog.videoDeclarations[asset],
                  let aliasDeclaration = catalog.videoDeclarations[alias] else { fatalError("video declaration missing") }
            let loader = SceneTextureLoader()
            let registry = SceneVideoTextureSourceRegistry(epoch: 40)
            defer { registry.stop() }
            let cache = root.appendingPathComponent("cache")
            guard let source = try registry.source(declaration: declaration, owner: .asset,
                      cacheDirectory: cache, device: device, loader: loader),
                  let shared = try registry.source(declaration: aliasDeclaration, owner: .asset,
                      cacheDirectory: cache, device: device, loader: loader),
                  let layerSource = try registry.source(from: declaration.input, layerID: videoLayerID,
                      cacheDirectory: cache, device: device, loader: loader) else { fatalError("registry source missing") }
            let initialVideoFrame = registry.sceneScriptSnapshots(sceneTime: 0)
            var checks: [String: Bool] = [
                "declarationIsNotReady": catalog.launchStates[asset] == .preparedVideoColor,
                "initialStatePending": {
                    if case .pending? = catalog.makeFrameProvider().states(sceneTime: 0)[asset] { return true }
                    return false
                }(),
                "aliasesSharePhysicalDecoder": source === shared,
                "layerPlaybackIsIndependent": source !== layerSource,
                "assetHasNoLayerBinding": Set(initialVideoFrame.layerBindings.keys) == [videoLayerID]
                    && !initialVideoFrame.sources.compactMap { $0 }.contains { $0.sourceIncarnation == source.playbackSnapshot(sceneTime: 0).sourceIncarnation },
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
            checks["assetCannotPublishAsLayer"] = frame(content: .color(.resolved(.opaque))).layerPublication(for: layerID) == nil
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
            let pauseCommand = SceneScriptMediaPlaybackCommand(layerID: videoLayerID, action: .pause, videoSourceIncarnation: layerSource.sourceIncarnation), pauseTiming = timing()
            try registry.validate([pauseCommand], timing: pauseTiming).get()
            registry.applyAdmitted(pauseCommand, timing: pauseTiming)
            let pausedVideoFrame = registry.sceneScriptSnapshots(sceneTime: 3.2)
            checks["layerCommandsDoNotControlAsset"] = beforePause > 0
                && Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!.rate > 0
                && pausedVideoFrame.layerBindings[videoLayerID].flatMap { pausedVideoFrame.sources[$0] }?.isPlaying == false
            registry.pause(sceneTime: 3.2, hostTime: CACurrentMediaTime())
            checks["globalPauseControlsAsset"] = Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!.rate == 0
            registry.resume(sceneTime: 3.2, hostTime: CACurrentMediaTime())
            registry.beginSurfaceRebuild(sceneTime: 3.2, hostTime: CACurrentMediaTime())
            let reacquired = try registry.source(declaration: declaration, owner: .asset, cacheDirectory: cache,
                device: device, loader: loader)
            registry.completeSurfaceRebuild()
            checks["rebuildReusesAssetAndRetiresLayer"] = reacquired === source
                && registry.sceneScriptSnapshots(sceneTime: 3.2).layerBindings.isEmpty
            let oldDeclaration = declaration
            try Data([0x11]).appendTo(root.appendingPathComponent(assetName + ".tex"))
            do {
                _ = try registry.source(declaration: oldDeclaration, owner: .asset,
                    cacheDirectory: cache, device: device, loader: loader)
                checks["staleSourceCannotAcquire"] = false
            } catch SceneResourceView.ReadError.sourceChanged {
                checks["staleSourceCannotAcquire"] = true
            }
            stoppedSource = source
            stoppedFile = Mirror(reflecting: source).children.compactMap { $0.value as? SceneVideoOwnedFile }.first
            stoppedAsset = player(source).currentItem?.asset
            registry.stop()
            checks["stopRejectsFramesImmediately"] = source.prepareFrame(for: timing()) == nil
            cleanupDirectory = cache.appendingPathComponent(".mywallpaperx-scene-video-payloads")
            return ["checks": checks,
                "pixels": pixels, "generations": generations, "tinted": tintedPixel, "still": stillPixel,
                "afterStopInsideAVScope": ["sourceAlive": stoppedSource != nil,
                    "assetAlive": stoppedAsset != nil, "fileAlive": stoppedFile != nil]]
        }
        var checks = result["checks"] as! [String: Bool]
        checks["stopRemovesFramesAndPayloads"] = checks["stopRejectsFramesImmediately"] == true && pump(8) {
            ((try? FileManager.default.contentsOfDirectory(atPath: cleanupDirectory.path)) ?? []).isEmpty
                && stoppedFile == nil
        }
        result["checks"] = checks
        result["afterAVScopeRelease"] = ["sourceAlive": stoppedSource != nil,
            "assetAlive": stoppedAsset != nil, "fileAlive": stoppedFile != nil]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }

    static func pump(_ seconds: Double, until condition: () -> Bool) -> Bool {
        let end = CACurrentMediaTime() + seconds
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        } while CACurrentMediaTime() < end
        return condition()
    }

    static func player(_ source: SceneVideoTextureSource) -> AVPlayer {
        Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first!
    }

    static func firstFrame(_ source: SceneVideoTextureSource) -> SceneVideoTextureSource.Frame? {
        var frame: SceneVideoTextureSource.Frame?
        var index: UInt64 = 0
        let start = CACurrentMediaTime()
        _ = pump(10) {
            index += 1
            let now = CACurrentMediaTime()
            frame = source.currentFrame(for: .init(frameIndex: index, hostTime: now, sceneTime: now - start))
            return frame != nil
        }
        return frame
    }

    #if MWX_COMPLETED_WEBM_REUSE
    static func storage(root: URL, external: URL) throws {
        let fm = FileManager.default
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        let fragment = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let library = try device.makeLibrary(source: fragment, options: nil)
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .sourceOver, library: library)!
        let package = root.appendingPathComponent("scene.pkg")
        let packageBytes = try Data(contentsOf: package)
        guard let ownedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] else { fatalError("owned HOME required") }
        precondition(fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL
            == URL(fileURLWithPath: ownedHome).resolvingSymlinksInPath().standardizedFileURL, "owned HOME mismatch")
        let cache = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MyWallpaperX/SteamWorkshopScene", isDirectory: true)
        let retired = root.appendingPathComponent(".scene-extracted/textures/renamed-card.tex")
        let retiredCache = cache.appendingPathComponent("retired-package-cache/textures/renamed-card.tex")
        for path in [retired, retiredCache] {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("stale physical cache".utf8).write(to: path)
        }
        func mounted() throws -> SceneResourceView.Root {
            try .package(openedPackage: ScenePkgReader().openPackage(packageURL: package))
        }
        let first = try mounted()
        let authorBytes = try first.existingLiteralHandle(relativePath: "textures/renamed-card.tex")!.readBytes()
        let asset = SceneAssetTextureIdentity(virtualPath: "textures/renamed-card", purpose: .premultipliedColor)!
        var checks: [String: Bool] = [:]
        var pixels: [[Float]] = []
        var borrowedItem: AVPlayerItem?
        var borrowedAsset: AVAsset?
        weak var weakFile: SceneVideoOwnedFile?
        var privateURL: URL!
        try autoreleasepool {
            let view = SceneResourceView(projectRoot: .init(source: .loose, url: root), packageRoot: first, stockRoot: nil)
            let catalog = try SceneMaterialAssetTextureCatalog(demands: [asset], resourceView: view,
                descriptor: .init(), device: device)
            guard let declaration = catalog.videoDeclarations[asset] else { fatalError("missing real TEX declaration") }
            let loader = SceneTextureLoader()
            let registry = SceneVideoTextureSourceRegistry(epoch: 61)
            guard let source = try registry.source(declaration: declaration, owner: .asset,
                cacheDirectory: cache, device: device, loader: loader) else { fatalError("missing actual source") }
            guard let frame = firstFrame(source), let publication = frame.assetPublication(for: asset) else {
                fatalError("actual TEX source did not publish a frame")
            }
            let pixel = try draw(.init(texture: frame.texture, candidate: publication.candidate,
                usesSystemProvider: false, usesUserPropertyProvider: false,
                usesAuthoredLayerColor: false, rejectedProviderReason: nil), layer: .init(id: 97, contentKind: "solid"),
                tint: SIMD3(repeating: 1), device: device, queue: queue, pipeline: pipeline)
            pixels.append(pixel)
            checks["embeddedActualFrameKeepsRedPixels"] = pixel[0] > 0.7 && pixel[1] < 0.15 && pixel[2] < 0.15
            borrowedItem = player(source).currentItem
            borrowedAsset = borrowedItem?.asset
            privateURL = (borrowedAsset as? AVURLAsset)?.url
            weakFile = Mirror(reflecting: source).children.compactMap { $0.value as? SceneVideoOwnedFile }.first
            checks["embeddedBorrowsActualSourceAVAsset"] = borrowedItem != nil && privateURL != nil && weakFile != nil
            checks["embeddedPrivateOutsideAuthorAndRetiredCache"] = privateURL != nil
                && !privateURL.path.hasPrefix(root.path + "/") && !privateURL.path.hasPrefix(retiredCache.deletingLastPathComponent().path + "/")
            let payload = try Data(contentsOf: privateURL)
            registry.beginSurfaceRebuild(sceneTime: 0.2, hostTime: CACurrentMediaTime())
            let reused = try registry.source(declaration: declaration, owner: .asset,
                cacheDirectory: cache, device: device, loader: loader)
            registry.completeSurfaceRebuild()
            checks["ordinarySurfaceRebuildReusesActualSource"] = reused === source
            let warm = try mounted()
            let warmView = SceneResourceView(projectRoot: .init(source: .loose, url: root), packageRoot: warm, stockRoot: nil)
            let warmCatalog = try SceneMaterialAssetTextureCatalog(demands: [asset], resourceView: warmView,
                descriptor: .init(), device: device)
            guard let warmDeclaration = warmCatalog.videoDeclarations[asset] else { fatalError("remounted TEX declaration missing") }
            checks["independentPackageMountKeepsActualSource"] = try registry.source(declaration: warmDeclaration,
                owner: .asset, cacheDirectory: cache, device: device, loader: .init()) === source
            checks["remountKeepsEmbeddedPrivateBytes"] = (try? Data(contentsOf: privateURL)) == payload
            try Data("new stale physical cache".utf8).write(to: retired)
            try Data("new stale cache domain".utf8).write(to: retiredCache)
            let remounted = try mounted()
            let remountedBytes = try remounted.existingLiteralHandle(relativePath: "textures/renamed-card.tex")!.readBytes()
            checks["retiredCachePollutionDoesNotChangePackageBytes"] = remountedBytes == authorBytes
                && (try? Data(contentsOf: package)) == packageBytes
            checks["retiredCachePollutionKeepsBorrowedEmbeddedBytes"] = (try? Data(contentsOf: privateURL)) == payload
            checks["retiredCachePollutionKeepsCurrentDeclaration"] = try registry.source(declaration: declaration,
                owner: .asset, cacheDirectory: cache, device: device, loader: loader) === source
            registry.stop()
        }
        checks["embeddedAVBorrowerAlonePinsFile"] = weakFile != nil && fm.fileExists(atPath: privateURL.path)
        autoreleasepool { borrowedItem = nil; borrowedAsset = nil }
        checks["embeddedFinalAVBorrowerUnlinksFile"] = pump(8) { weakFile == nil && !fm.fileExists(atPath: privateURL.path) }

        try autoreleasepool {
            let loader = SceneUserPropertyTextureLoader()
            let identity = SceneUserPropertyTextureIdentity(propertyKey: "renamed-user-video", purpose: .premultipliedColor)!
            let result = loader.load(urlsByPropertyKey: [identity.propertyKey: external],
                requestedIdentities: [identity], device: device, videoCacheDirectory: cache)
            guard let declaration = result.videoDeclarations[identity.propertyKey] else { fatalError("external snapshot missing") }
            let registry = SceneVideoTextureSourceRegistry(epoch: 70)
            guard let candidate = registry.makeUserPropertyCandidate(declaration: declaration, device: device) else {
                fatalError("real external candidate missing")
            }
            var primed: Bool?
            Task { primed = await candidate.source.primeInitialFrame() }
            checks["externalCandidatePrimesActualDecoder"] = pump(12) { primed != nil } && primed == true
            checks["externalCandidateAdopts"] = registry.adoptUserPropertyCandidate(candidate,
                sceneTime: 0, hostTime: CACurrentMediaTime(), isPaused: true)
            let source = candidate.source
            borrowedItem = player(source).currentItem
            borrowedAsset = borrowedItem?.asset
            privateURL = (borrowedAsset as? AVURLAsset)?.url
            weakFile = declaration.file
            let payload = try Data(contentsOf: external)
            checks["externalSourceUsesActualSnapshotBytes"] = privateURL == declaration.file.url
                && (try? Data(contentsOf: privateURL)) == payload
            checks["externalPrivateOutsideAuthorAndRetiredCache"] = privateURL != nil
                && !privateURL.path.hasPrefix(root.path + "/") && !privateURL.path.hasPrefix(retiredCache.deletingLastPathComponent().path + "/")
            if let frame = firstFrame(source), let publication = frame.userPropertyPublication(for: identity) {
                let pixel = try draw(.init(texture: frame.texture, candidate: publication.candidate,
                    usesSystemProvider: false, usesUserPropertyProvider: true, usesAuthoredLayerColor: false,
                    rejectedProviderReason: nil), layer: .init(id: 98, contentKind: "solid"),
                    tint: SIMD3(repeating: 1), device: device, queue: queue, pipeline: pipeline)
                pixels.append(pixel)
                checks["externalActualFrameKeepsRedPixels"] = pixel[0] > 0.7 && pixel[1] < 0.15 && pixel[2] < 0.15
            } else { checks["externalActualFrameKeepsRedPixels"] = false }
            registry.beginSurfaceRebuild(sceneTime: 0.2, hostTime: CACurrentMediaTime())
            let reused = registry.userPropertySources(declarations: result.videoDeclarations, device: device)
            registry.completeSurfaceRebuild()
            checks["externalSurfaceRebuildReusesAdoptedSource"] = reused[identity] === source
            let remounted = try mounted()
            let remountedBytes = try remounted.existingLiteralHandle(relativePath: "textures/renamed-card.tex")!.readBytes()
            checks["packageRemountKeepsExternalPrivateBytes"] = remountedBytes == authorBytes
                && (try? Data(contentsOf: privateURL)) == payload
            let cancelled = loader.load(urlsByPropertyKey: [identity.propertyKey: external], requestedIdentities: [identity],
                device: device, videoCacheDirectory: cache, isCancelled: { true })
            checks["cancelledReplacementKeepsOldProvider"] = cancelled.videoDeclarations.isEmpty
                && registry.userPropertySources(declarations: result.videoDeclarations, device: device)[identity] === source
            let replacement = loader.load(urlsByPropertyKey: [identity.propertyKey: external],
                requestedIdentities: [identity], device: device, contentGeneration: 2, videoCacheDirectory: cache)
            if let nextDeclaration = replacement.videoDeclarations[identity.propertyKey],
               let next = registry.makeUserPropertyCandidate(declaration: nextDeclaration, device: device) {
                var ready: Bool?
                Task { ready = await next.source.primeInitialFrame() }
                let complete = pump(12) { ready != nil } && ready == true
                checks["liveReplacementUsesNewActualPrivateSource"] = complete
                    && registry.adoptUserPropertyCandidate(next, sceneTime: 0.3,
                        hostTime: CACurrentMediaTime(), isPaused: true)
                    && next.source !== source && nextDeclaration.file.url != declaration.file.url
                    && registry.userPropertySources(declarations: replacement.videoDeclarations, device: device)[identity] === next.source
                checks["liveReplacementPrivateOutsideAuthor"] = !nextDeclaration.file.url.path.hasPrefix(root.path + "/")
                    && !nextDeclaration.file.url.path.hasPrefix(retiredCache.deletingLastPathComponent().path + "/")
            } else {
                checks["liveReplacementUsesNewActualPrivateSource"] = false
                checks["liveReplacementPrivateOutsideAuthor"] = false
            }
            registry.stop()
        }
        checks["externalAVBorrowerAlonePinsFile"] = weakFile != nil && fm.fileExists(atPath: privateURL.path)
        autoreleasepool { borrowedItem = nil; borrowedAsset = nil }
        checks["externalFinalAVBorrowerUnlinksFile"] = pump(8) { weakFile == nil && !fm.fileExists(atPath: privateURL.path) }
        for kind in ["failed", "missing"] {
            let loose = root.appendingPathComponent(kind + "-loose")
            try fm.createDirectory(at: loose.appendingPathComponent("textures"), withIntermediateDirectories: true)
            let leaf = loose.appendingPathComponent("textures/renamed-card.tex")
            try authorBytes.write(to: leaf)
            let pkg = loose.appendingPathComponent("scene.pkg")
            if kind == "failed" { try Data("invalid pkg".utf8).write(to: pkg) }
            let retiredLoose = loose.appendingPathComponent(".scene-extracted/textures/renamed-card.tex")
            try fm.createDirectory(at: retiredLoose.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("stale loose cache".utf8).write(to: retiredLoose)
            var unavailable = false
            do { _ = try ScenePkgReader().openPackage(packageURL: pkg) }
            catch ScenePkgReader.ReadError.fileTooSmall { unavailable = kind == "failed" }
            catch let error as POSIXError { unavailable = kind == "missing" && error.code == .ENOENT }
            let before = (fm.enumerator(at: loose, includingPropertiesForKeys: nil)!.allObjects as! [URL]).map(\.path).sorted()
            let view = SceneResourceView(projectRoot: .init(source: .loose, url: loose), packageRoot: nil, stockRoot: nil)
            checks[kind + "PackageUnavailableKeepsLooseSelection"] = unavailable
                && view.resolvedResource(relativePath: "textures/renamed-card.tex")?.source == .loose
            let catalog = try SceneMaterialAssetTextureCatalog(demands: [asset], resourceView: view, descriptor: .init(), device: device)
            let registry = SceneVideoTextureSourceRegistry(epoch: 81)
            let source = try registry.source(declaration: catalog.videoDeclarations[asset]!, owner: .asset,
                cacheDirectory: cache, device: device, loader: .init())
            let url = source.flatMap { player($0).currentItem?.asset as? AVURLAsset }?.url
            let after = (fm.enumerator(at: loose, includingPropertiesForKeys: nil)!.allObjects as! [URL]).map(\.path).sorted()
            checks[kind + "LoosePrivateOutsideAuthor"] = url != nil && !url!.path.hasPrefix(loose.path + "/")
            checks[kind + "LooseAuthorNamespaceUnchanged"] = before == after && (try? Data(contentsOf: leaf)) == authorBytes
            registry.stop()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks, "pixels": pixels,
            "storageMapping": "actual package Root with explicit App-private media domain"],
            options: [.sortedKeys]), as: UTF8.self))
    }
    #endif

    #if MWX_COMPLETED_WEBM_REUSE
    static func completedWebMReuse(root: URL) throws {
        let fm = FileManager.default
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        let fragment = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let library = try device.makeLibrary(source: fragment, options: nil)
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .sourceOver, library: library)!
        let packageURL = root.appendingPathComponent("scene.pkg")
        let privateBase = root.deletingLastPathComponent().appendingPathComponent("completed-private")
        let cache = privateBase.appendingPathComponent("media")
        // Independent Roots share files by the actual opened package revision.
        func mounted(_ name: String = "scene.pkg") throws -> SceneResourceView.Root {
            try .package(openedPackage: ScenePkgReader().openPackage(packageURL: root.appendingPathComponent(name)))
        }
        let package = try mounted()
        let view = SceneResourceView(projectRoot: .init(source: .loose, url: root), packageRoot: package, stockRoot: nil)
        let handle = view.resolvedResource(relativePath: "textures/first.tex")!
        guard case let .package(identity) = try handle.currentIdentity() else { fatalError("not a package identity") }
        let asset = SceneAssetTextureIdentity(virtualPath: "textures/first", purpose: .premultipliedColor)!
        let ledger = SceneVideoOwnedFile.DiskBudget.shared
        var checks: [String: Bool] = [:], pixels: [[Float]] = []
        var borrowedAsset: AVAsset?
        var stoppedSources: [SceneVideoTextureSource] = []
        weak var weakFile: SceneVideoOwnedFile?
        var privateURL: URL!
        var converted = Data()
        checks["startsWithNoPrivateReservation"] = ledger.reservedBytes == 0
        try autoreleasepool {
            let loaderA = SceneTextureLoader(), loaderB = SceneTextureLoader()
            let declarationA = try loaderA.videoSourceDeclaration(from: .resource(handle))!
            let registryA = SceneVideoTextureSourceRegistry(epoch: 101)
            let sourceA = try registryA.source(declaration: declarationA, owner: .asset,
                cacheDirectory: cache, device: device, loader: loaderA)!
            guard declarationA.isWebM, let frameA = firstFrame(sourceA),
                  let publicationA = frameA.assetPublication(for: asset) else { fatalError("first actual WebM frame missing") }
            let fileA = Mirror(reflecting: sourceA).children.compactMap { $0.value as? SceneVideoOwnedFile }.first!
            privateURL = fileA.url; weakFile = fileA
            checks["actualFileOutsideAuthorRoot"] = !fileA.url.path.hasPrefix(root.path + "/")
            converted = try Data(contentsOf: fileA.url)
            let charge = ledger.reservedBytes
            checks["completedFileHasOneActualReservation"] = charge == UInt64(converted.count) && charge > 0
            let declarationB = try loaderB.videoSourceDeclaration(from: .resource(handle))!
            let registryB = SceneVideoTextureSourceRegistry(epoch: 202)
            let sourceB = try registryB.source(declaration: declarationB, owner: .asset,
                cacheDirectory: cache, device: device, loader: loaderB)!
            let fileB = Mirror(reflecting: sourceB).children.compactMap { $0.value as? SceneVideoOwnedFile }.first!
            checks["independentSourcesAndPlayers"] = sourceA !== sourceB && player(sourceA) !== player(sourceB)
            checks["secondSourceUsesCompletedFileSynchronously"] = player(sourceB).currentItem != nil &&
                fileA === fileB && fileB.url == privateURL && ledger.reservedBytes == charge
            let bStarted = CACurrentMediaTime()
            var bIndex: UInt64 = 0
            var firstB: SceneVideoTextureSource.Frame?
            guard pump(10, until: {
                bIndex += 1
                let now = CACurrentMediaTime()
                firstB = sourceB.currentFrame(for: .init(frameIndex: bIndex, hostTime: now, sceneTime: now - bStarted))
                return firstB != nil
            }), let frameB = firstB, let publicationB = frameB.assetPublication(for: asset) else {
                fatalError("second actual WebM frame missing")
            }
            for (frame, publication) in [(frameA, publicationA), (frameB, publicationB)] {
                pixels.append(try draw(.init(texture: frame.texture, candidate: publication.candidate,
                    usesSystemProvider: false, usesUserPropertyProvider: false, usesAuthoredLayerColor: false,
                    rejectedProviderReason: nil), layer: .init(id: 97, contentKind: "solid"),
                    tint: SIMD3(repeating: 1), device: device, queue: queue, pipeline: pipeline))
            }
            checks["bothActualPlayersPublishRedPixels"] = pixels.count == 2 && pixels.allSatisfy {
                $0[0] > 0.7 && $0[1] < 0.15 && $0[2] < 0.15
            }
            registryA.stop()
            checks["firstStopDoesNotStopSecondPublication"] = pump(4) {
                bIndex += 1
                let now = CACurrentMediaTime()
                return sourceB.currentFrame(for: .init(frameIndex: bIndex, hostTime: now,
                    sceneTime: now - bStarted)).map { $0.contentGeneration > frameB.contentGeneration } == true
            } && player(sourceA).currentItem == nil && player(sourceB).currentItem != nil &&
                ledger.reservedBytes == charge && fm.fileExists(atPath: privateURL.path)
            borrowedAsset = player(sourceB).currentItem?.asset
            registryB.stop()
            stoppedSources = [sourceA, sourceB]
        }
        checks["lastActualAssetAloneKeepsFileAndCharge"] = borrowedAsset != nil && weakFile != nil &&
            fm.fileExists(atPath: privateURL.path) && ledger.reservedBytes == UInt64(converted.count)
        autoreleasepool { borrowedAsset = nil }
        checks["lastAssetReleaseUnlinksAndReturnsReservation"] = pump(8) {
            weakFile == nil && !fm.fileExists(atPath: privateURL.path) && ledger.reservedBytes == 0
        }
        checks["stoppedSourcesRemainAliveAfterFinalBorrow"] = stoppedSources.count == 2 &&
            stoppedSources.allSatisfy { player($0).currentItem == nil }

        let boundaryCache = privateBase.appendingPathComponent("boundaries")
        let budget = SceneVideoOwnedFile.DiskBudget.shared
        let sourceCopy = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: boundaryCache,
            fileExtension: "mp4", diskBudget: budget)
        checks["sourceSnapshotCannotServeRemuxPurpose"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: identity, cacheDirectory: boundaryCache, diskBudget: budget) == nil
        let writer = try SceneVideoOwnedFile.makeWriter(cacheDirectory: boundaryCache,
            expectedBytes: UInt64(converted.count), diskBudget: budget)
        try writer.append(converted)
        let completed = try writer.finish()
        try SceneVideoOwnedFile.publishCompletedWebM(writer, identity: identity,
            cacheDirectory: boundaryCache, diskBudget: budget)
        checks["closedWriterPublishesExactFile"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: identity, cacheDirectory: boundaryCache, diskBudget: budget) === completed
        checks["remuxCannotReplaceSourceSnapshotPurpose"] = try SceneVideoOwnedFile.snapshot(from: handle,
            cacheDirectory: boundaryCache, fileExtension: "mp4", diskBudget: budget) === sourceCopy
        for (name, candidate, path) in [
            ("packagePath", try mounted("peer.pkg"), "textures/first.tex"),
            ("rawEntry", package, "textures/peer.tex")
        ] {
            let selected = try candidate.existingLiteralHandle(relativePath: path)!
            guard case let .package(key) = try selected.currentIdentity() else { fatalError("not package") }
            checks[name + "CannotBorrowOtherCompletedIdentity"] = try SceneVideoOwnedFile.borrowCompletedWebM(
                identity: key, cacheDirectory: boundaryCache, diskBudget: budget) == nil
        }
        let otherCache = privateBase.appendingPathComponent("other")
        let other = try SceneVideoOwnedFile.makeWriter(cacheDirectory: otherCache, expectedBytes: 0, diskBudget: budget)
        _ = try other.finish()
        let otherBudget = SceneVideoOwnedFile.DiskBudget(maximumBytes: budget.maximumBytes)
        checks["actualPrivateDomainPartitionsBorrow"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: identity, cacheDirectory: otherCache, diskBudget: budget) == nil
        checks["budgetInstancePartitionsBorrow"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: identity, cacheDirectory: boundaryCache, diskBudget: otherBudget) == nil
        let peer = try package.existingLiteralHandle(relativePath: "textures/peer.tex")!
        guard case let .package(peerIdentity) = try peer.currentIdentity() else { fatalError("not package") }
        let partial = try SceneVideoOwnedFile.makeWriter(cacheDirectory: boundaryCache, diskBudget: budget)
        try partial.append(Data(converted.prefix(64)))
        try SceneVideoOwnedFile.publishCompletedWebM(partial, identity: peerIdentity,
            cacheDirectory: boundaryCache, diskBudget: budget)
        checks["partialWriterNeverRegistersSuccess"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: peerIdentity, cacheDirectory: boundaryCache, diskBudget: budget) == nil
        partial.abort()
        let rejected = try SceneVideoOwnedFile.makeWriter(cacheDirectory: boundaryCache,
            expectedBytes: UInt64(converted.count), diskBudget: budget)
        try rejected.append(converted); _ = try rejected.finish()
        enum Cancel: Error { case now }
        do {
            try SceneVideoOwnedFile.publishCompletedWebM(rejected, identity: peerIdentity,
                cacheDirectory: boundaryCache, diskBudget: budget, checkCancellation: { throw Cancel.now })
            checks["cancelledPublicationEscapes"] = false
        } catch Cancel.now { checks["cancelledPublicationEscapes"] = true }
        checks["cancelledPublicationDoesNotRegister"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: peerIdentity, cacheDirectory: boundaryCache, diskBudget: budget) == nil
        do {
            _ = try SceneVideoOwnedFile.borrowCompletedWebM(identity: identity,
                cacheDirectory: boundaryCache, diskBudget: budget, checkCancellation: { throw Cancel.now })
            checks["cancelledHitCannotBorrow"] = false
        } catch Cancel.now { checks["cancelledHitCannotBorrow"] = true }
        let loader = SceneTextureLoader()
        let declaration = try loader.videoSourceDeclaration(from: .resource(handle))!
        let registry = SceneVideoTextureSourceRegistry(epoch: 203)
        let source = try registry.source(declaration: declaration, owner: .asset,
            cacheDirectory: boundaryCache, device: device, loader: loader)!
        let layerSource = try registry.source(from: .resource(handle), layerID: 17,
            cacheDirectory: boundaryCache, device: device, loader: loader)!
        try Data([0x11]).appendTo(packageURL)
        do {
            _ = try registry.source(from: .resource(handle), layerID: 17,
                cacheDirectory: boundaryCache, device: device, loader: loader)
            checks["changedAuthorInputEscapesAtRegistryEntry"] = false
        } catch SceneResourceView.ReadError.sourceChanged { checks["changedAuthorInputEscapesAtRegistryEntry"] = true }
        do {
            _ = try registry.source(declaration: declaration, owner: .asset,
                cacheDirectory: boundaryCache, device: device, loader: loader)
            checks["changedAuthorDeclarationEscapesAtRegistryEntry"] = false
        } catch SceneResourceView.ReadError.sourceChanged { checks["changedAuthorDeclarationEscapesAtRegistryEntry"] = true }
        checks["completedFileRemainsUsableAfterAuthorChange"] =
            try SceneVideoOwnedFile.borrowCompletedWebM(identity: identity,
                cacheDirectory: boundaryCache, diskBudget: budget) === completed
            && (player(source).currentItem?.asset as? AVURLAsset)?.url == completed.url
            && (player(layerSource).currentItem?.asset as? AVURLAsset)?.url == completed.url
            && firstFrame(source) != nil
        let refreshed = try mounted().existingLiteralHandle(relativePath: "textures/first.tex")!
        guard case let .package(refreshedIdentity) = try refreshed.currentIdentity() else {
            fatalError("not a refreshed package identity")
        }
        let refreshedRegistry = SceneVideoTextureSourceRegistry(epoch: 204)
        let refreshedSource = try refreshedRegistry.source(from: .resource(refreshed), layerID: 17,
            cacheDirectory: boundaryCache, device: device, loader: SceneTextureLoader())!
        let refreshedFile = Mirror(reflecting: refreshedSource).children.compactMap { $0.value as? SceneVideoOwnedFile }.first!
        checks["freshRootUsesNewRevisionAndPrivateFile"] = refreshedIdentity != identity
            && refreshedFile !== completed && refreshedFile.url != completed.url
            && firstFrame(refreshedSource) != nil
        registry.stop(); refreshedRegistry.stop()
        try converted.write(to: completed.url, options: .atomic)
        checks["replacedOutputCannotHitOldSuccess"] = try SceneVideoOwnedFile.borrowCompletedWebM(
            identity: identity, cacheDirectory: boundaryCache, diskBudget: budget) == nil
        withExtendedLifetime((stoppedSources, writer, completed, rejected, other, sourceCopy)) {}
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks, "pixels": pixels,
            "scope": "real package Root/Loader/Registry and independent AV players; low-level table negatives use original controlled Writer"],
            options: [.sortedKeys]), as: UTF8.self))
    }
    #endif

    #if MWX_REGISTRY_INPUT_IO
    static func registryInputIO(root: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        func count() -> UInt64 {
            let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "mwx_video_entry_bytes")!
            return unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)()
        }
        func watch(_ handle: SceneResourceView.Handle) throws -> UInt64 {
            let backing = handle.owner.packageBacking!
            guard case let .package(key) = try handle.currentIdentity(),
                  let fd = Mirror(reflecting: backing.opened).children.first(where: { $0.label == "descriptor" })?.value as? Int32
            else { fatalError("actual Root descriptor missing") }
            let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "mwx_video_entry_observe")!
            let configure = unsafeBitCast(symbol, to: (@convention(c) (Int32, UInt64, UInt64) -> Int32).self)
            precondition(configure(fd, UInt64(backing.opened.index.dataStartOffset) + UInt64(key.offset), UInt64(key.byteCount)) == 0)
            return UInt64(key.byteCount)
        }
        func mount(_ name: String = "scene.pkg") throws -> SceneResourceView {
            let opened = try ScenePkgReader().openPackage(packageURL: root.appendingPathComponent(name))
            return .init(projectRoot: .init(source: .loose, url: root),
                packageRoot: try .package(openedPackage: opened), stockRoot: nil)
        }
        let view = try mount(), input = SceneResourceView.FileInput.resource(view.resolvedResource(relativePath: "textures/first.tex")!)
        guard case let .resource(handle) = input else { fatalError("not selected package") }
        let privateCache = root.deletingLastPathComponent().appendingPathComponent("input-io-private")
        var checks: [String: Bool] = [:], reads: [String: UInt64] = [:]
        weak var weakFile: SceneVideoOwnedFile?
        var borrowedAsset: AVAsset?, fileURL: URL!
        var preparedBorrowedAsset: AVAsset?
        weak var lastPayloadAsset: AVAsset?
        let initialReservation = SceneVideoOwnedFile.DiskBudget.shared.reservedBytes
        let entryBytes = try watch(handle)
        try autoreleasepool {
            let budget = SceneTextureDecodeCacheBudget(maximumBytes: 0), loader = SceneTextureLoader(decodeCacheBudget: budget)
            let aRegistry = SceneVideoTextureSourceRegistry(epoch: 301)
            let a = try aRegistry.source(from: input, layerID: 17, cacheDirectory: privateCache, device: device, loader: loader)!
            reads["cold"] = count()
            checks["coldPositiveControl"] = reads["cold"] == entryBytes && budget.residentBytes == 0 && budget.rejectionCount == 1
            guard firstFrame(a) != nil else { fatalError("cold WebM did not finish and publish") }
            weakFile = Mirror(reflecting: a).children.compactMap { $0.value as? SceneVideoOwnedFile }.first
            fileURL = (player(a).currentItem!.asset as! AVURLAsset).url
            loader.evictDecodedCaches(); _ = try watch(handle)
            let existing = try aRegistry.source(from: input, layerID: 17, cacheDirectory: privateCache, device: device, loader: loader)
            reads["liveHit"] = count()
            checks["sameLiveSourceAndExpectedIO"] = existing === a && reads["liveHit"] == 0 && budget.residentBytes == 0
            let bRegistry = SceneVideoTextureSourceRegistry(epoch: 302), bLoader = SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 0))
            _ = try watch(handle)
            let b = try bRegistry.source(from: input, layerID: 17, cacheDirectory: privateCache, device: device, loader: bLoader)!
            reads["completedHit"] = count()
            checks["completedHitExpectedIO"] = reads["completedHit"] == 0 && b !== a && player(b) !== player(a)
                && (player(b).currentItem?.asset as? AVURLAsset)?.url == fileURL
            let revisionURL = root.appendingPathComponent("different-revision.pkg")
            try FileManager.default.copyItem(at: root.appendingPathComponent("scene.pkg"), to: revisionURL)
            let changedView = try mount("different-revision.pkg")
            let changed = changedView.resolvedResource(relativePath: "textures/first.tex")!
            _ = try watch(changed)
            try autoreleasepool {
                let registry = SceneVideoTextureSourceRegistry(epoch: 303)
                let next = try registry.source(from: .resource(changed), layerID: 17, cacheDirectory: privateCache,
                    device: device, loader: SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 0)))!
                reads["differentRevision"] = count()
                checks["differentIdentityReadsOriginalPayload"] = reads["differentRevision"] == entryBytes
                    && (firstFrame(next) != nil)
                registry.stop()
            }
            for (name, expectedRead) in [("not-tex.bin", false), ("not-video.tex", true), ("malformed.tex", true)] {
                let selected = view.resolvedResource(relativePath: "textures/" + name)!
                let size = try watch(selected)
                let registry = SceneVideoTextureSourceRegistry(epoch: 304)
                let source = try registry.source(from: .resource(selected), layerID: 18, cacheDirectory: privateCache,
                    device: device, loader: SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 0)))
                reads[name] = count()
                checks[name + "KeepsOriginalResult"] = source == nil && count() == (expectedRead ? size : 0)
            }
            _ = try watch(handle)
            var cancelled = false, finished = false
            Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try SceneVideoTextureSourceRegistry(epoch: 305).source(from: input, layerID: 17,
                        cacheDirectory: privateCache, device: device, loader: SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 0)))
                } catch is CancellationError { cancelled = true }
                catch { cancelled = false }
                finished = true
            }
            checks["cancelledRequestIsRejected"] = pump(4) { finished } && cancelled
            reads["cancelled"] = count()
            checks["cancelledRequestExpectedIO"] = reads["cancelled"] == 0
            let brokenView = try mount("changed.pkg"), broken = brokenView.resolvedResource(relativePath: "textures/first.tex")!
            _ = try watch(broken)
            try Data([17]).appendTo(root.appendingPathComponent("changed.pkg"))
            do {
                _ = try SceneVideoTextureSourceRegistry(epoch: 306).source(from: .resource(broken), layerID: 17,
                    cacheDirectory: privateCache, device: device, loader: loader)
                checks["sourceChangedEscapesBeforePayload"] = false
            } catch SceneResourceView.ReadError.sourceChanged { checks["sourceChangedEscapesBeforePayload"] = count() == 0 }
            borrowedAsset = player(b).currentItem?.asset
            aRegistry.stop(); bRegistry.stop()
        }
        checks["actualAssetKeepsCompletedFile"] = borrowedAsset != nil && weakFile != nil
        autoreleasepool { borrowedAsset = nil }
        checks["lastBorrowActuallyReleased"] = pump(8) { weakFile == nil && !FileManager.default.fileExists(atPath: fileURL.path) }
        _ = try watch(handle)
        try autoreleasepool {
            let lastRegistry = SceneVideoTextureSourceRegistry(epoch: 307)
            let last = try lastRegistry.source(from: input, layerID: 17, cacheDirectory: privateCache,
                device: device, loader: SceneTextureLoader(decodeCacheBudget: .init(maximumBytes: 0)))!
            reads["lastBorrowMiss"] = count()
            checks["lastBorrowMissReadsOriginalPayload"] = reads["lastBorrowMiss"] == entryBytes && firstFrame(last) != nil
            let preparedFile = Mirror(reflecting: last).children.compactMap { $0.value as? SceneVideoOwnedFile }.first!
            weakFile = preparedFile; fileURL = preparedFile.url
            let sourceKey = try input.currentIdentity(), preparedRegistry = SceneVideoTextureSourceRegistry(epoch: 308)
            let preparedReservation = SceneVideoOwnedFile.DiskBudget.shared.reservedBytes
            _ = try watch(handle)
            let preparedSource = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                owner: .asset, device: device)!
            reads["preparedCold"] = count()
            let actualPreparedFile = Mirror(reflecting: preparedSource).children.compactMap { $0.value as? SceneVideoOwnedFile }.first
            checks["preparedColdAvoidsPayloadAndDuplicateFile"] = reads["preparedCold"] == 0
                && actualPreparedFile === preparedFile && (player(preparedSource).currentItem?.asset as? AVURLAsset)?.url == fileURL
                && SceneVideoOwnedFile.DiskBudget.shared.reservedBytes == preparedReservation
            checks["preparedActualFrameUsesCompletedMP4"] = firstFrame(preparedSource) != nil
            _ = try watch(handle)
            let preparedHit = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                owner: .asset, device: device)
            reads["preparedLiveHit"] = count()
            checks["preparedLiveCacheHitAvoidsPayload"] = preparedHit === preparedSource && reads["preparedLiveHit"] == 0
            let timing = SceneFrameTiming(frameIndex: 1, hostTime: CACurrentMediaTime(), sceneTime: 0)
            let layerSource = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                owner: .ordinary, layerID: 811, device: device)!
            let obsoleteLayer = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                owner: .ordinary, layerID: 812, device: device)!
            let revisionView = try mount("different-revision.pkg")
            let replacementKey = try revisionView.resolvedResource(relativePath: "textures/first.tex")!.currentIdentity()
            let replacementLayer = try preparedRegistry.source(sourceKey: replacementKey, preparedFile: preparedFile,
                owner: .ordinary, layerID: 811, device: device)!
            checks["layerIndexExcludesAssetAndKeepsBothLayers"] = Set(preparedRegistry.sceneScriptSnapshots(sceneTime: 0).layerBindings.keys) == [811, 812]
            let commands: [SceneScriptMediaPlaybackCommand] = [.init(layerID: 811, action: .setRate(2), videoSourceIncarnation: replacementLayer.sourceIncarnation), .init(layerID: 812, action: .setRate(3), videoSourceIncarnation: layerSource.sourceIncarnation)]
            try preparedRegistry.validate(commands, timing: timing).get()
            for command in commands { preparedRegistry.applyAdmitted(command, timing: timing) }
            checks["layerIndexSharesResourceAndTargetsDistinctRevision"] = layerSource === obsoleteLayer
                && layerSource.playbackSnapshot(sceneTime: 0).rate == 3 && replacementLayer.playbackSnapshot(sceneTime: 0).rate == 2
            guard firstFrame(replacementLayer) != nil else { fatalError("actual Native duration did not become available") }
            let nativeDuration = CMTimeGetSeconds(player(replacementLayer).currentItem!.duration)
            let rejectedCases: [(String, [SceneScriptMediaPlaybackCommand], SceneVideoCommandApplicationFailure)] = [
                ("wrongLayerRejectedAtomically", [.init(layerID: 811, action: .setRate(4), videoSourceIncarnation: replacementLayer.sourceIncarnation), .init(layerID: 999, action: .pause)], .unavailableLayer(999)),
                ("knownNativeDurationRejectedAtomically", [.init(layerID: 811, action: .setRate(4), videoSourceIncarnation: replacementLayer.sourceIncarnation), .init(layerID: 811, action: .setCurrentTime(nativeDuration + 1), videoSourceIncarnation: replacementLayer.sourceIncarnation)], .invalidCommand(1)),
                ("staleSourceCommandRejected", [.init(layerID: 811, action: .pause, videoSourceIncarnation: layerSource.sourceIncarnation)], .unavailableLayer(811)),
                ("missingSourceCommandRejected", [.init(layerID: 811, action: .pause)], .unavailableLayer(811))]
            for (name, rejectedCommands, expected) in rejectedCases {
                if case let .failure(actual) = preparedRegistry.validate(rejectedCommands, timing: timing) {
                    checks[name] = nativeDuration.isFinite && nativeDuration > 0 && actual == expected && replacementLayer.playbackSnapshot(sceneTime: 0).rate == 2
                } else { checks[name] = false }
            }
            let catalogModel = "models/catalog-video.json", catalogState = replacementLayer.playbackSnapshot(sceneTime: 0)
            try preparedRegistry.prepareDynamicVideoSources(resources: [catalogModel: .init(product: .video(
                source: replacementKey, file: preparedFile, sizeWH: [32, 24]))], modelPaths: [catalogModel], device: device)
            preparedRegistry.retire(layerIDs: [811, 812])
            preparedRegistry.beginSurfaceRebuild(sceneTime: 0, hostTime: CACurrentMediaTime())
            _ = try watch(handle)
            try preparedRegistry.prepareDynamicVideoSources(resources: [catalogModel: .init(product: .video(
                source: replacementKey, file: preparedFile, sizeWH: [32, 24]))], modelPaths: [catalogModel], device: device)
            let preparedRebuild = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                owner: .asset, device: device)
            preparedRegistry.completeSurfaceRebuild()
            let rebuiltCatalogState = replacementLayer.playbackSnapshot(sceneTime: 0)
            checks["catalogZeroCarrierReusesSourceAndFile"] = preparedRegistry.layerSources(deviceRegistryID: device.registryID).isEmpty
                && rebuiltCatalogState.sourceIncarnation == catalogState.sourceIncarnation && rebuiltCatalogState.currentTime == catalogState.currentTime
                && rebuiltCatalogState.rate == catalogState.rate && rebuiltCatalogState.isPlaying == catalogState.isPlaying
                && (player(replacementLayer).currentItem?.asset as? AVURLAsset)?.url == fileURL
            preparedRegistry.bindPreparedVideoConsumers([811: catalogModel])
            reads["preparedRebuild"] = count()
            checks["preparedRebuildKeepsReachableSource"] = preparedRebuild === preparedSource
                && player(preparedSource).currentItem != nil && reads["preparedRebuild"] == 0
                && SceneVideoOwnedFile.DiskBudget.shared.reservedBytes == preparedReservation
            checks["layerIndexRebuildKeepsSiblingAndRemovesObsolete"] = Set(preparedRegistry.sceneScriptSnapshots(sceneTime: 0).layerBindings.keys) == [811]
                && player(layerSource).currentItem == nil && player(obsoleteLayer).currentItem == nil
                && preparedRegistry.layerSources(deviceRegistryID: device.registryID)[811] === replacementLayer
            if case .failure(.unavailableLayer(812)) = preparedRegistry.validate([.init(layerID: 812, action: .play)], timing: timing) {
                checks["layerIndexRetiredCommandsAreUnavailable"] = true
            } else { checks["layerIndexRetiredCommandsAreUnavailable"] = false }
            var cancelled = false, finished = false
            _ = try watch(handle)
            Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try preparedRegistry.source(sourceKey: sourceKey, preparedFile: preparedFile,
                        owner: .asset, device: device)
                } catch is CancellationError { cancelled = true }
                catch { cancelled = false }
                finished = true
            }
            checks["preparedCancelledCacheHitIsRejected"] = pump(4) { finished } && cancelled && count() == 0
            preparedBorrowedAsset = player(preparedSource).currentItem?.asset
            lastPayloadAsset = player(last).currentItem?.asset
            preparedRegistry.stop()
            checks["preparedStopRetiresActualPlayer"] = player(preparedSource).currentItem == nil
            if case .failure(.unavailableLayer(811)) = preparedRegistry.validate([.init(layerID: 811, action: .play)], timing: timing) {
                checks["layerIndexStopClearsBindings"] = preparedRegistry.sceneScriptSnapshots(sceneTime: 0).layerBindings.isEmpty
            } else { checks["layerIndexStopClearsBindings"] = false }
            lastRegistry.stop()
        }
        checks["preparedAssetAlonePinsCompletedFile"] = pump(8) { lastPayloadAsset == nil }
            && preparedBorrowedAsset != nil && weakFile != nil && (preparedBorrowedAsset as? AVURLAsset)?.url == fileURL
            && FileManager.default.fileExists(atPath: fileURL.path)
        autoreleasepool { preparedBorrowedAsset = nil }
        checks["preparedFinalBorrowReturnsReservation"] = pump(8) {
            weakFile == nil && !FileManager.default.fileExists(atPath: fileURL.path)
                && SceneVideoOwnedFile.DiskBudget.shared.reservedBytes == initialReservation
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["checks": checks, "payloadReadBytes": reads,
            "entryBytes": entryBytes],
            options: [.sortedKeys]), as: UTF8.self))
    }
    #endif

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
