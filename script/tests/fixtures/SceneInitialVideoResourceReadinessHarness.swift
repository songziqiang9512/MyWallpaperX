// Controlled resource inputs; no AVPlayer, command buffer, or visible output.
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

struct SceneGeometryProduct {
    func installing(resourceGeneration: UInt64) -> Self { fatalError("geometry outside this resource gate") }
    func matchesInstalledSource(layerID: Int, texture: MTLTexture) -> Bool { fatalError("geometry outside gate") }
}
struct SceneRenderDescriptor { struct Layer { let id: Int; var contentKind = "image" } }
struct SceneMetalRenderer {
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let textureRegistry: SceneFrameTextureRegistry
}
struct SceneFrameTiming { let frameIndex: UInt64 }
struct SceneDynamicImageTextureProviderSnapshot {
    let layerSources: [Int: SceneLayerSourcePublication]
    let pendingLayerSourceIDs: Set<Int>
    var videoLayerRenderSizesWH: [Int: [Float]] = [:]
}
enum SceneDynamicTextTextureStore { struct Snapshot { let layerSources: [Int: SceneLayerSourcePublication] } }
enum SceneMediaThumbnailTextureStore { struct Snapshot {} }

// Only the backend facts are controlled. The observation method compiled into
// this shell is read unchanged from SceneVideoTextureSource.swift.
final class SceneVideoTextureSource {
    struct Frame {
        let texture: MTLTexture; let publication: SceneTextureProviderPublication?
        var owner: SceneVideoTexturePlaybackOwner = .ordinary
        func layerPublication(for layerID: Int) -> SceneTextureProviderPublication? { publication }
    }
    enum Status { case unknown, ready, failed }
    struct Item { let status: Status }
    let item: Item?
    let payloadPreparationFailed: Bool
    let frame: Frame?
    private(set) var prepares = 0
    init(frame: Frame? = nil, status: Status? = nil, payloadFailed: Bool = false) {
        self.frame = frame; item = status.map(Item.init); payloadPreparationFailed = payloadFailed
    }
    func prepareFrame(for timing: SceneFrameTiming) -> Frame? { prepares += 1; return frame }
}

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain:"noMetal",code:1) }
        func texture() -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:2,height:2,mipmapped:false)
            d.usage = .shaderRead
            return device.makeTexture(descriptor:d)!
        }
        let video = texture(), still = texture()
        func publication(_ texture: MTLTexture, layerID: Int = 41,
                         request: SceneFrameTextureIdentity? = nil,
                         identity: SceneTextureProviderIdentity? = nil) -> SceneTextureProviderPublication {
            .init(requestIdentity:request ?? .layerSource(layerID),candidate:.init(
                texture:texture,identity:.provider(identity ?? .video(layerID:layerID,lifecycleEpoch:1)),
                generation:.provider(contentGeneration:1),purpose:.premultipliedColor,
                content:.color(.resolved(.premultipliedAlpha)),physicalSize:.init(width:2,height:2),
                mappedSize:.init(width:2,height:2),uvTransform:.identity,sampling:.linearClamp),contentGeneration:1)
        }
        let frame = SceneVideoTextureSource.Frame(texture:video,publication:publication(video))
        let ready = SceneVideoTextureSource(frame:frame), pending = SceneVideoTextureSource(status:.unknown)
        let failed = SceneVideoTextureSource(status:.failed), payloadFailed = SceneVideoTextureSource(payloadFailed:true)
        let timing = SceneFrameTiming(frameIndex:1)
        let base = SceneBaseImageTextureStore()
        func assemble(_ source: SceneVideoTextureSource, collect: Bool = true,
                      store: SceneBaseImageTextureStore? = nil) -> SceneBaseImageTextureSnapshot {
            SceneFrameLayerTextureAssembly.make(base:store ?? base,dynamicText:nil,
                videoSources:[41:source],timing:timing,collectsInitialVideoReadiness:collect)
        }
        let pendingSnapshot = assemble(pending)
        let readySnapshot = assemble(ready)
        var checks: [String: Bool] = [
            "collectionDisabledIsNil": assemble(pending,collect:false).initialVideoReadiness == nil,
            "pendingFact": pendingSnapshot.initialVideoReadiness?[41] == .pending,
            "unknownAndNoCopyStayPending": pending.initialFrameReadiness(preparedFrame:nil) == .pending,
            "readyPhysicalFrame": readySnapshot.initialVideoReadiness?[41] == .ready && readySnapshot[41] === video,
            "realFailureFactsTerminal": assemble(failed).initialVideoReadiness?[41] == .unavailable
                && assemble(payloadFailed).initialVideoReadiness?[41] == .unavailable,
            "lastReadyFrameWinsFailure": failed.initialFrameReadiness(preparedFrame:frame) == .ready,
        ]
        var unavailable = SceneBaseImageTextureStore()
        unavailable.markOrdinaryVideoUnavailable(layerID:41)
        let unavailableSnapshot = SceneFrameLayerTextureAssembly.make(base:unavailable,dynamicText:nil,
            videoSources:[:],timing:timing,collectsInitialVideoReadiness:true)
        checks["loadFailureRetainedWithoutSource"] = unavailableSnapshot.initialVideoReadiness?[41] == .unavailable
        let retiredSource = SceneVideoTextureSource(frame: frame)
        let retired = SceneFrameLayerTextureAssembly.make(base: unavailable, dynamicText: nil,
            videoSources: [41: retiredSource], retiredLayerIDs: [41], timing: timing, collectsInitialVideoReadiness: true)
        checks["retiredAuthoredVideoDoesNotHoldFirstFrame"] = retired.initialVideoReadiness?[41] == nil && retiredSource.prepares == 0
        let dynamic = SceneDynamicImageTextureProviderSnapshot(layerSources: [:], pendingLayerSourceIDs: [],
            videoLayerRenderSizesWH: [-7: [200, 100]])
        let missingDynamic = SceneFrameLayerTextureAssembly.make(base: base, dynamicImage: dynamic, dynamicText: nil,
            videoSources: [:], timing: timing, collectsInitialVideoReadiness: true)
        checks["preparedFileWithoutSourceIsUnavailable"] = missingDynamic.initialVideoReadiness?[-7] == .unavailable
            && missingDynamic[-7] == nil
        let dynamicSource = SceneVideoTextureSource(frame: .init(texture: video, publication: publication(video, layerID: -7)))
        let readyDynamic = SceneFrameLayerTextureAssembly.make(base: base, dynamicImage: dynamic, dynamicText: nil,
            videoSources: [-7: dynamicSource], timing: timing, collectsInitialVideoReadiness: true)
        checks["dynamicVideoKeepsPublicationAndLogicalQuad"] = readyDynamic.initialVideoReadiness?[-7] == .ready
            && readyDynamic[-7] === video && readyDynamic.layerSourceRenderSize(for: -7) == [200, 100]
        unavailable.set(still,candidate:nil,layerID:41)
        checks["selectedStillReplacesLoadFailure"] = unavailable.unavailableOrdinaryVideoLayerIDs.isEmpty
        let direct = SceneMetalRenderer(baseMaterialProviderBindings:.empty,textureRegistry:.init())
        let layer = SceneRenderDescriptor.Layer(id:41)
        checks["selectedPendingAuthoredVideo"] = direct.baseMaterialTextureSelection(for:layer,
            imageTextures:pendingSnapshot).hasPendingAuthoredVideo
        checks["terminalFallbackIsNotPending"] = !direct.baseMaterialTextureSelection(for:layer,
            imageTextures:unavailableSnapshot).hasPendingAuthoredVideo
        let selectedStill = SceneBaseImageTextureSnapshot(textures:[41:still],candidates:[:],
            initialVideoReadiness:[41:.pending])
        checks["readyStillDoesNotWaitForUnselectedVideo"] = direct.baseMaterialTextureSelection(for:layer,
            imageTextures:selectedStill).source?.texture === still
            && !direct.baseMaterialTextureSelection(for:layer,imageTextures:selectedStill).hasPendingAuthoredVideo
        let dynamicOnly = SceneBaseImageTextureSnapshot(textures:[:],candidates:[:],pendingLayerSourceIDs:[41])
        checks["pendingDynamicImageIsNotVideo"] = !direct.baseMaterialTextureSelection(for:layer,
            imageTextures:dynamicOnly).hasPendingAuthoredVideo
        let binding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(layerID:41,
            source:.materialPass,slotIndex:0,provider:.current)
        let registry = SceneFrameTextureRegistry()
        registry.beginFrame(frameIndex:1,layerSources:[:])
        registry.set(.pending,for:binding.provider.frameIdentity)
        let bound = SceneMetalRenderer(baseMaterialProviderBindings:.init(baseMaterialBindings:[41:binding]),
            textureRegistry:registry)
        checks["providerFallbackStillSelectsPendingVideo"] = bound.baseMaterialTextureSelection(for:layer,
            imageTextures:pendingSnapshot).hasPendingAuthoredVideo
        // A bare provider atom is rejected by the original resolver. Its
        // authored video fallback remains typed pending; no reason parsing.
        registry.set(.ready(still),for:binding.provider.frameIdentity)
        let rejected = bound.baseMaterialTextureSelection(for:layer,imageTextures:pendingSnapshot)
        checks["rejectedProviderRetainsPendingChoice"] = rejected.hasPendingAuthoredVideo
            && rejected.rejectedProviderReason == "base-material-current-publication-incomplete"
        registry.beginFrame(frameIndex:2,layerSources:[:],systemTextures:[
            binding.provider.systemProviderIdentity!:still],explicitSystemTextures:[
            binding.provider.systemProviderIdentity!:publication(still,request:binding.provider.frameIdentity,
                                                                  identity:.mediaThumbnailCurrent)])
        let provider = bound.baseMaterialTextureSelection(for:layer,imageTextures:pendingSnapshot)
        checks["readyProviderDoesNotWaitForUnselectedVideo"] = provider.source?.texture === still
            && !provider.hasPendingAuthoredVideo
        let invalidReady = SceneBaseImageTextureSnapshot(textures:[:],candidates:[:],initialVideoReadiness:[41:.ready])
        checks["readyWithoutInstalledTextureRemainsPending"] = invalidReady.initialVideoReadiness?[41] == .pending
        let replaced = pendingSnapshot.replacingLayerSources([41:SceneLayerSourcePublication(layerID:41,
            publication:publication(still))!])
        checks["replacementKeepsFactsButSelectsReadySource"] = replaced.initialVideoReadiness?[41] == .pending
            && direct.baseMaterialTextureSelection(for:layer,imageTextures:replaced).source?.texture === still
            && !direct.baseMaterialTextureSelection(for:layer,imageTextures:replaced).hasPendingAuthoredVideo
        print(String(data:try JSONSerialization.data(withJSONObject:checks),encoding:.utf8)!)
    }
}
