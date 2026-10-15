import Foundation
import AVFoundation
import Metal
import QuartzCore
import simd

// Only envelopes for the unrelated layer/text assembly branch are replaced.
// The user-property assembly below is compiled from production unchanged.
struct SceneBaseImageTextureStore {
    let textures: [Int: MTLTexture] = [:]
    func snapshot(textures: [Int: MTLTexture],
                  explicitLayerSources: [Int: SceneTextureProviderPublication],
                  layerSourcePublications: [Int: SceneLayerSourcePublication],
                  pendingLayerSourceIDs: Set<Int>) -> SceneBaseImageTextureSnapshot {
        fatalError("unrelated layer assembly executed")
    }
}
struct SceneDynamicImageTextureProviderSnapshot {
    let layerSources: [Int: SceneLayerSourcePublication]
    let pendingLayerSourceIDs: Set<Int>
}
enum SceneDynamicTextTextureStore {
    struct Snapshot { let layerSources: [Int: SceneLayerSourcePublication] }
}
enum SceneMediaThumbnailTextureStore { struct Snapshot {} }

@main enum SceneUserPropertyVideoHarness {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        if CommandLine.arguments.contains("--format-owner") {
            let rows = await formatOwnerFacts(root: root, device: device)
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["rows": rows],
                options: [.sortedKeys]), as: UTF8.self))
            return
        }
        let library = try await device.makeLibrary(source: String(contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8), options: nil)
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float,
            blendMode: .sourceOver, library: library)!
        var variants: [[String: Any]] = []
        for (index, names) in [("background", "clip.mp4"),
                               ("renamed-picture", "arbitrary-renamed.mp4")].enumerated() {
            variants.append(try await exercise(root: root, propertyKey: names.0, filename: names.1,
                layerID: 91 + index * 302, device: device, queue: queue, pipeline: pipeline))
        }
        let rejections = await rejectionChecks(root: root, device: device)
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "variants": variants, "rejections": rejections,
        ], options: [.sortedKeys]), as: UTF8.self))
    }

    static func exercise(root: URL, propertyKey: String, filename: String, layerID: Int,
                         device: MTLDevice, queue: MTLCommandQueue,
                         pipeline: SceneImageLayerPipeline) async throws -> [String: Any] {
        let property = SceneUserPropertyTextureIdentity(propertyKey: propertyKey, purpose: .premultipliedColor)!
        let hidden = SceneUserPropertyTextureIdentity(propertyKey: propertyKey + "-hidden", purpose: .premultipliedColor)!
        let declarations = SceneUserPropertyTextureLoader().load(
            urlsByPropertyKey: [property.propertyKey: root.appendingPathComponent(filename),
                               hidden.propertyKey: root.appendingPathComponent(filename)],
            requestedIdentities: [property, hidden], device: device, videoCacheDirectory: root)
        let a = declarations.videoDeclarations[property.propertyKey]!
        let b = declarations.videoDeclarations[hidden.propertyKey]!
        var checks: [String: Bool] = [:]
        checks["loaderReturnsOnlyOwnedPreparedDeclarations"] = declarations.textures.isEmpty
            && !declarations.hasCompletePublications(for: [property, hidden])
            && declarations.hasPreparedResources(for: [property, hidden])
            && a.file.url != root.appendingPathComponent(filename) && a.file.url != b.file.url
        checks["preparedDoesNotSatisfyRequiredReady"] = declarations.satisfiesPreparedProperties(
            [property.propertyKey, hidden.propertyKey], selectedKeys: [property.propertyKey, hidden.propertyKey],
            demands: [property, hidden]) && !declarations.satisfiesRequiredProperties(
                [property.propertyKey, hidden.propertyKey], selectedKeys: [property.propertyKey, hidden.propertyKey],
                demands: [property, hidden])
        let registry = SceneVideoTextureSourceRegistry(epoch: 70)
        defer { registry.stop() }
        let firstTime = SceneFrameTiming(frameIndex: 1, hostTime: CACurrentMediaTime(), sceneTime: 0)
        checks["declarationAloneDefersSurface"] = SceneFrameUserPropertyTextureAssembly.make(
            prepared: declarations, videoSources: [:], timing: firstTime) == nil
        let candidate = registry.makeUserPropertyCandidate(declaration: a, device: device)!
        checks["candidateRequiresActualPrime"] = !registry.canAdoptUserPropertyCandidate(candidate)
        let primed = await candidate.source.primeInitialFrame()
        registry.commitPreparedFrame()
        registry.discardPreparedFrame()
        checks["unregisteredSeedSurvivesActiveCommit"] = primed
            && candidate.source.hasCompletePrimedPublication(for: property)
            && registry.userPropertySources(declarations: declarations.videoDeclarations, device: device).isEmpty
            && player(candidate.source)?.rate == 0
        checks["sameSourceAdoptedPaused"] = registry.adoptUserPropertyCandidate(candidate,
            sceneTime: 0, hostTime: firstTime.hostTime, isPaused: true)
            && registry.userPropertySources(declarations: declarations.videoDeclarations, device: device)[property]
                === candidate.source
        var sources = registry.userPropertySources(declarations: declarations.videoDeclarations, device: device)
        checks["hiddenSelectedDeclarationAlsoDefers"] = SceneFrameUserPropertyTextureAssembly.make(
            prepared: declarations, videoSources: sources, timing: firstTime) == nil
        registry.discardPreparedFrame()
        let peerCandidate = registry.makeUserPropertyCandidate(declaration: b, device: device)!
        let peerPrimed = await peerCandidate.source.primeInitialFrame()
        checks["sameURLKeysHaveIndependentSources"] = peerPrimed && candidate.source !== peerCandidate.source
            && registry.adoptUserPropertyCandidate(peerCandidate,
                sceneTime: 0, hostTime: CACurrentMediaTime(), isPaused: true)
        sources = registry.userPropertySources(declarations: declarations.videoDeclarations, device: device)
        let paused = SceneFrameUserPropertyTextureAssembly.make(prepared: declarations,
            videoSources: sources, timing: firstTime)!
        let pausedPublication = publication(paused, property)
        checks["externalVideoHasNoAuthoredTEXFormat"] = pausedPublication.candidate.authoredFormat == nil
        registry.discardPreparedFrame()
        let retried = SceneFrameUserPropertyTextureAssembly.make(prepared: declarations,
            videoSources: sources, timing: firstTime)!
        checks["discardPreservesUnconsumedSeed"] = publication(retried, property).texture === pausedPublication.texture
            && publication(retried, property).contentGeneration == 1
            && candidate.source.hasCompletePrimedPublication(for: property)
        checks["pauseBeforeFirstKeepsReadySeed"] = player(candidate.source)?.rate == 0
            && player(peerCandidate.source)?.rate == 0 && publication(retried, hidden).isComplete
        registry.commitPreparedFrame()
        checks["commitConsumesSeedOnce"] = !candidate.source.hasCompletePrimedPublication(for: property)

        let frameRegistry = SceneFrameTextureRegistry()
        let peerRegistry = SceneFrameTextureRegistry()
        let binding = SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding(layerID: layerID,
            source: .layerInstance, slotIndex: 0, provider: .userProperty(property))
        let renderer = SceneMetalRenderer(baseMaterialProviderBindings: .init(baseMaterialBindings: [layerID: binding]),
            textureRegistry: frameRegistry)
        let layer = SceneRenderDescriptor.Layer(id: layerID, contentKind: "solid")
        let start = CACurrentMediaTime()
        registry.resume(sceneTime: 0, hostTime: start)
        var frameIndex: UInt64 = 1
        var pixels: [[Float]] = []
        var generations: Set<UInt64> = []
        var latest = pausedPublication
        while CACurrentMediaTime() - start < 2.25 {
            frameIndex += 1
            let now = CACurrentMediaTime()
            let timing = SceneFrameTiming(frameIndex: frameIndex, hostTime: now, sceneTime: now - start)
            let first = SceneFrameUserPropertyTextureAssembly.make(prepared: declarations,
                videoSources: sources, timing: timing)!
            let second = SceneFrameUserPropertyTextureAssembly.make(prepared: declarations,
                videoSources: sources, timing: timing)!
            latest = publication(first, property)
            frameRegistry.beginFrame(frameIndex: frameIndex, layerSources: [:], userPropertyStates: first.states)
            peerRegistry.beginFrame(frameIndex: frameIndex, layerSources: [:], userPropertyStates: second.states)
            checks["twoSurfacesUseSameCompleteAtom"] = checks["twoSurfacesUseSameCompleteAtom", default: true]
                && latest.isComplete && latest.generationIsCurrent
                && publication(second, property).texture === latest.texture
                && publication(second, property).contentGeneration == latest.contentGeneration
                && first.textures[property.propertyKey] === latest.texture
                && peerRegistry.resource(for: .materialUserProperty(property))?.publication.candidate.identity
                    == latest.candidate.identity
                && frameRegistry.texture(for: .userProperty(property.propertyKey)) === latest.texture
            let selected = renderer.baseMaterialTextureSelection(for: layer, imageTextures: .init()).source!
            pixels.append(try MaterialVideoFixtureSupport.draw(selected, layer: layer,
                tint: .init(repeating: 1), device: device, queue: queue, pipeline: pipeline))
            generations.insert(latest.contentGeneration)
            frameRegistry.commitFramePublication()
            peerRegistry.commitFramePublication()
            registry.commitPreparedFrame()
            try await Task.sleep(for: .milliseconds(35))
        }
        checks["actualGPUSamplesAdvanceRedToBlue"] = pixels.contains { $0[0] > 0.9 && $0[2] < 0.1 }
            && pixels.contains { $0[2] > 0.9 && $0[0] < 0.1 } && generations.count > 10

        registry.beginSurfaceRebuild(sceneTime: 2.25, hostTime: CACurrentMediaTime())
        let rebuilt = registry.userPropertySources(declarations: declarations.videoDeclarations, device: device)
        registry.completeSurfaceRebuild()
        checks["rebuildReusesBothDecoders"] = rebuilt[property] === candidate.source
            && rebuilt[hidden] === peerCandidate.source
        let staleCandidate = registry.makeUserPropertyCandidate(declaration: a, device: device)!
        let replacement = registry.makeUserPropertyCandidate(declaration: a, device: device)!
        let replacementPrimed = await replacement.source.primeInitialFrame()
        checks["supersededCandidateCannotAdopt"] = !registry.canAdoptUserPropertyCandidate(staleCandidate)
            && staleCandidate.source.prepareFrame(for: firstTime) == nil
        let foreign = SceneVideoTextureSourceRegistry(epoch: 80)
        checks["foreignRegistryCannotAdopt"] = !foreign.canAdoptUserPropertyCandidate(replacement)
        foreign.stop()
        checks["replacementAdoptsWithoutReplacingPeer"] = replacementPrimed
            && registry.adoptUserPropertyCandidate(replacement,
                sceneTime: 2.25, hostTime: CACurrentMediaTime(), isPaused: true)
            && candidate.source.prepareFrame(for: firstTime) == nil
        let replacementTime = SceneFrameTiming(frameIndex: frameIndex + 1,
            hostTime: CACurrentMediaTime(), sceneTime: 2.25)
        let replaced = SceneFrameUserPropertyTextureAssembly.make(prepared: declarations,
            videoSources: registry.userPropertySources(declarations: declarations.videoDeclarations, device: device),
            timing: replacementTime)!
        let current = publication(replaced, property)
        frameRegistry.beginFrame(frameIndex: frameIndex + 1, layerSources: [:], userPropertyStates: replaced.states)
        frameRegistry.commitFramePublication()
        frameRegistry.beginFrame(frameIndex: frameIndex + 2, layerSources: [:], userPropertyStates: [property: .ready(latest)])
        checks["oldProviderCannotOverwriteReplacement"] = frameRegistry.resource(for: .materialUserProperty(property))?
            .publication.candidate.identity == current.candidate.identity
        frameRegistry.discardFramePublication()
        registry.commitPreparedFrame()

        let still = SceneUserPropertyTextureLoader().load(urlsByPropertyKey: [property.propertyKey:
            root.appendingPathComponent("still.png")], requestedIdentities: [property], device: device)
        let reset = declarations.replacing(propertyKeys: [property.propertyKey], with: still)
        registry.retireUserPropertySources(propertyKeys: [property.propertyKey])
        let resetSources = registry.userPropertySources(declarations: reset.videoDeclarations, device: device)
        let resetFrame = SceneFrameUserPropertyTextureAssembly.make(prepared: reset,
            videoSources: resetSources, timing: .init(frameIndex: frameIndex + 3,
                hostTime: CACurrentMediaTime(), sceneTime: 2.25))!
        frameRegistry.beginFrame(frameIndex: frameIndex + 3, layerSources: [:], userPropertyStates: resetFrame.states)
        let stillSelected = renderer.baseMaterialTextureSelection(for: layer, imageTextures: .init()).source!
        let stillPixel = try MaterialVideoFixtureSupport.draw(stillSelected, layer: layer,
            tint: .init(repeating: 1), device: device, queue: queue, pipeline: pipeline)
        checks["imageReplacementRetiresOnlySelectedVideo"] = reset.videoDeclarations[property.propertyKey] == nil
            && resetSources[property] == nil && resetSources[hidden] === peerCandidate.source
            && replacement.source.prepareFrame(for: firstTime) == nil && stillPixel[1] > 0.9
        frameRegistry.commitFramePublication()
        let cleared = reset.replacing(propertyKeys: [property.propertyKey], with: .empty)
        checks["resetRemovesPreparedImageAndVideo"] = cleared.textures[property.propertyKey] == nil
            && cleared.providerStates[property] == nil && cleared.videoDeclarations[property.propertyKey] == nil
        registry.stop()
        checks["stopRejectsOldSourcesAndNewCandidates"] = peerCandidate.source.prepareFrame(for: firstTime) == nil
            && registry.makeUserPropertyCandidate(declaration: a, device: device) == nil
        return ["property": propertyKey, "filename": filename, "checks": checks,
            "frames": pixels.count, "generations": generations.count,
            "red": pixels.first(where: { $0[0] > 0.9 && $0[2] < 0.1 }) ?? [],
            "blue": pixels.first(where: { $0[2] > 0.9 && $0[0] < 0.1 }) ?? [], "still": stillPixel]
    }

    static func rejectionChecks(root: URL, device: MTLDevice) async -> [String: Bool] {
        let identity = SceneUserPropertyTextureIdentity(propertyKey: "negative-case", purpose: .premultipliedColor)!
        let normal = SceneUserPropertyTextureIdentity(propertyKey: identity.propertyKey, purpose: .normal)!
        let loader = SceneUserPropertyTextureLoader()
        let url = root.appendingPathComponent("clip.mp4")
        let wrongPurpose = loader.load(urlsByPropertyKey: [identity.propertyKey: url],
            requestedIdentities: [normal], device: device, videoCacheDirectory: root)
        let cancelled = loader.load(urlsByPropertyKey: [identity.propertyKey: url],
            requestedIdentities: [identity], device: device, videoCacheDirectory: root, isCancelled: { true })
        let invalid = loader.load(urlsByPropertyKey: [identity.propertyKey: root.appendingPathComponent("invalid.mp4")],
            requestedIdentities: [identity], device: device, videoCacheDirectory: root)
        let registry = SceneVideoTextureSourceRegistry(epoch: 900)
        let candidate = registry.makeUserPropertyCandidate(declaration: invalid.videoDeclarations[identity.propertyKey]!,
            device: device)!
        let invalidPrimed = await candidate.source.primeInitialFrame()
        let valid = loader.load(urlsByPropertyKey: [identity.propertyKey: url],
            requestedIdentities: [identity], device: device, videoCacheDirectory: root)
        let cancelledCandidate = registry.makeUserPropertyCandidate(declaration: valid.videoDeclarations[identity.propertyKey]!,
            device: device)!
        let cancelledPrime = await cancelledCandidate.source.primeInitialFrame(isCancelled: { true })
        cancelledCandidate.cancel()
        let late = registry.makeUserPropertyCandidate(declaration: valid.videoDeclarations[identity.propertyKey]!, device: device)!
        let latePrime = Task { await late.source.primeInitialFrame() }
        registry.stop()
        let lateResult = await latePrime.value
        let lease = await leaseRoundTrip(root: root, device: device)
        var metadata: [String: Bool] = [:]
        for filename in ["clip.mp4", "remux.mov", "remux.m4v", "audio-only.mp4", "invalid.mp4"] {
            do {
                try await SceneVideoPayloadPreparation.validateLocalVideo(at: root.appendingPathComponent(filename))
                metadata["metadata-" + filename] = !["audio-only.mp4", "invalid.mp4"].contains(filename)
            } catch {
                metadata["metadata-" + filename] = ["audio-only.mp4", "invalid.mp4"].contains(filename)
            }
        }
        return ["wrongPurposeIsRejected": wrongPurpose.videoDeclarations.isEmpty,
            "cancelledLoaderPublishesNothing": cancelled.videoDeclarations.isEmpty && cancelled.textures.isEmpty,
            "invalidContainerCannotPrimeOrAdopt": !invalidPrimed && !registry.canAdoptUserPropertyCandidate(candidate),
            "cancelledPrimeCannotAdopt": !cancelledPrime && !registry.canAdoptUserPropertyCandidate(cancelledCandidate),
            "stopRejectsLatePrime": !lateResult && !registry.canAdoptUserPropertyCandidate(late),
            "fileLeaseRetainedUntilFinalDeclaration": lease.retained,
            "fileLeaseRetiresExactPrivateSnapshot": !FileManager.default.fileExists(atPath: lease.url.path)]
            .merging(metadata) { _, new in new }
    }

    static func formatOwnerFacts(root: URL, device: MTLDevice) async -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (key, filename) in [("format-picture", "clip.mp4"),
                                ("renamed-format-picture", "arbitrary-renamed.mp4")] {
            let identity = SceneUserPropertyTextureIdentity(propertyKey: key, purpose: .premultipliedColor)!
            let loaded = SceneUserPropertyTextureLoader().load(urlsByPropertyKey: [key:
                root.appendingPathComponent(filename)], requestedIdentities: [identity], device: device,
                videoCacheDirectory: root)
            let registry = SceneVideoTextureSourceRegistry(epoch: 1500)
            let candidate = registry.makeUserPropertyCandidate(declaration: loaded.videoDeclarations[key]!, device: device)!
            guard await candidate.source.primeInitialFrame(),
                  registry.adoptUserPropertyCandidate(candidate, sceneTime: 0,
                    hostTime: CACurrentMediaTime(), isPaused: true),
                  let frame = SceneFrameUserPropertyTextureAssembly.make(prepared: loaded,
                    videoSources: registry.userPropertySources(declarations: loaded.videoDeclarations, device: device),
                    timing: .init(frameIndex: 1, hostTime: CACurrentMediaTime(), sceneTime: 0)) else {
                fatalError("real Source failed format-owner preparation")
            }
            let value = publication(frame, identity)
            let format: Any
            if let authored = value.candidate.authoredFormat { format = Int(authored.rawValue) }
            else { format = NSNull() }
            rows.append(["property": key, "authoredFormat": format,
                "isComplete": value.isComplete, "generationIsCurrent": value.generationIsCurrent])
            registry.discardPreparedFrame()
            registry.stop()
        }
        return rows
    }

    static func leaseRoundTrip(root: URL, device: MTLDevice) async -> (url: URL, retained: Bool) {
        let identity = SceneUserPropertyTextureIdentity(propertyKey: "lease", purpose: .premultipliedColor)!
        let loaded = SceneUserPropertyTextureLoader().load(urlsByPropertyKey: [identity.propertyKey:
            root.appendingPathComponent("clip.mp4")], requestedIdentities: [identity], device: device,
            videoCacheDirectory: root)
        let declaration = loaded.videoDeclarations[identity.propertyKey]!
        let registry = SceneVideoTextureSourceRegistry(epoch: 990)
        let candidate = registry.makeUserPropertyCandidate(declaration: declaration, device: device)!
        _ = await candidate.source.primeInitialFrame()
        registry.stop()
        return (declaration.file.url, FileManager.default.fileExists(atPath: declaration.file.url.path))
    }

    static func publication(_ snapshot: SceneFrameUserPropertyTextureAssembly.Snapshot,
                            _ identity: SceneUserPropertyTextureIdentity) -> SceneTextureProviderPublication {
        guard case let .ready(value)? = snapshot.states[identity] else { fatalError("typed frame missing") }
        return value
    }

    static func player(_ source: SceneVideoTextureSource) -> AVPlayer? {
        Mirror(reflecting: source).children.compactMap { $0.value as? AVPlayer }.first
    }
}
