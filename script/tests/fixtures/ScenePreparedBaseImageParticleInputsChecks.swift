import Foundation
import Metal

// The existing carrier controls loader/compiler boundaries; the preparation
// owner and its final-outcome publication are the production implementation.
func particleImageInputChecks(root: URL, device: MTLDevice) throws -> [String: [String: Bool]] {
    for name in ["retry-decode.png", "retry-upload.png"] {
        try Data(name.utf8).write(to: root.appendingPathComponent("materials/" + name))
    }
    let provider = SceneRenderDescriptor.Layer(id: 1)
    let consumer = SceneRenderDescriptor.Layer(id: 2, contentKind: "particle",
        authoredDependencies: [.init(layerID: 1, index: 0, type: "emitterimage")])
    var facts: [String: [String: Bool]] = [:]
    for (name, texture, expectedLoads, expectedLoaded, expectedFailed) in [
        ("loaded", "canonical.png", 1, 1, 0),
        ("decodeRetry", "retry-decode.png", 2, 1, 0),
        ("uploadRetry", "retry-upload.png", 2, 1, 0),
        ("failedRetry", "decode-failure.png", 3, 1, 1),
        ("specialAnimation", "animated.tex", 1, 1, 0),
        ("loadedAnimation", "loaded-animation.png", 1, 1, 0)
    ] {
        let layers = name == "failedRetry"
            ? [provider, consumer, .init(id: 3, staticBaseTexturePath: "materials/canonical.png")]
            : [provider, consumer]
        let descriptor = SceneRenderDescriptor(layers: layers, materialPasses: [
            .init(materialPath: "materials/shared.json", texturePaths: ["materials/" + texture],
                textureSlots: ["materials/" + texture])])
        let view = SceneResourceView(projectRootURL: root, packageRootURL: nil)
        let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
            resourceView: view, device: device, spriteTextureLoader: .init(), sceneGeneration: 1,
            cacheDirectory: root, cancellationCheck: {})
        defer { prepared.cancelDeferredPreparation() }
        let input = SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
            .resolvePrimaryTexture(for: provider)!
        let first = prepared.outcome(for: 1, url: input, device: device)
        let second = prepared.outcome(for: 1, url: input, device: device)
        let compilation = prepared.particleLayerImageCompilation(descriptor: descriptor)
        let destroyed = prepared.particleLayerImageCompilation(descriptor: descriptor, destroyedIDs: [1, 2])
        let animated = name.contains("Animation")
        var finalOutcome = false
        switch (first, second) {
        case let (.loaded(a)?, .loaded(b)?):
            finalOutcome = a.texture === b.texture && compilation.textures[1] === a.texture
        case (.failed?, .failed?): finalOutcome = compilation.textures[1] == nil
        default: break
        }
        facts[name] = ["oneFinalOutcome": finalOutcome,
            "noThirdLoad": prepared.textureLoader.loadCount == expectedLoads,
            "loadedAccounting": prepared.loadedCount == expectedLoaded,
            "failedAccounting": prepared.failedCount == expectedFailed,
            "animationIdentity": compilation.animated == (animated ? [1] : []),
            "destroyedProvidersExcluded": destroyed.textures[1] == nil && !destroyed.animated.contains(1),
            "destroyedConsumersForwarded": destroyed.destroyed == [1, 2]]
        if name == "decodeRetry" || name == "uploadRetry" {
            facts[name]!["naturalSizeRetained"] = prepared.dynamicImageResources["models/shared.json"]?.naturalSizeWH == [20, 10]
        }
        if name == "failedRetry" { facts[name]!["healthyPeerRetained"] = compilation.textures[3] != nil }
    }
    let unrelated = SceneRenderDescriptor.Layer(id: 2, contentKind: "particle",
        authoredDependencies: [.init(layerID: 1, index: 0, type: "other")])
    for (name, layers, deferred, expectedLoads) in [
        ("notProvider", [provider, unrelated], Set<Int>(), 1),
        ("deferredProvider", [provider, consumer], Set([1]), 0)
    ] {
        let descriptor = SceneRenderDescriptor(layers: layers, materialPasses: [
            .init(materialPath: "materials/shared.json", texturePaths: ["materials/decode-failure.png"],
                textureSlots: ["materials/decode-failure.png"])])
        let prepared = try ScenePreparedBaseImageResources.prepare(descriptor: descriptor,
            resourceView: .init(projectRootURL: root, packageRootURL: nil), device: device,
            spriteTextureLoader: .init(), sceneGeneration: 1, cacheDirectory: root,
            deferredBaseImageLayerIDs: deferred, cancellationCheck: {})
        defer { prepared.cancelDeferredPreparation() }
        facts[name] = ["noNewLoad": prepared.textureLoader.loadCount == expectedLoads,
            "noTextureProjection": prepared.particleLayerImageCompilation(descriptor: descriptor).textures.isEmpty]
        if name == "deferredProvider" { facts[name]!["stillPending"] = prepared.deferredStatus(for: 1) == .pending }
    }
    let cancelDescriptor = SceneRenderDescriptor(layers: [provider, consumer], materialPasses: [
        .init(materialPath: "materials/shared.json", texturePaths: ["materials/retry-decode.png"],
            textureSlots: ["materials/retry-decode.png"])])
    var calls = 0, cancelled = false, returned = false
    SceneTextureLoader.loadHook = { calls += 1 }
    defer { SceneTextureLoader.loadHook = nil }
    do {
        _ = try ScenePreparedBaseImageResources.prepare(descriptor: cancelDescriptor,
            resourceView: .init(projectRootURL: root, packageRootURL: nil), device: device,
            spriteTextureLoader: .init(), sceneGeneration: 1, cacheDirectory: root,
            cancellationCheck: { if calls == 2 { throw CancellationError() } })
        returned = true
    } catch is CancellationError { cancelled = true }
    facts["retryCancellation"] = ["cancelled": cancelled, "noPreparedPublication": !returned, "twoCalls": calls == 2]
    return facts
}
