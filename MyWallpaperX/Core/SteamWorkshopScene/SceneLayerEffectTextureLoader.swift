import Metal

struct SceneLayerEffectTextures {
    let irisMask: MTLTexture?
    let opacityMask: MTLTexture?
    let waterMask: MTLTexture?
    let foliageMask: MTLTexture?
    let waterRippleNormal: MTLTexture?
    let message: String

    func merge(
        layerID: Int,
        irisMasks: inout [Int: MTLTexture],
        opacityMasks: inout [Int: MTLTexture],
        waterMasks: inout [Int: MTLTexture],
        foliageMasks: inout [Int: MTLTexture],
        waterRippleNormals: inout [Int: MTLTexture]
    ) {
        irisMasks[layerID] = irisMask
        opacityMasks[layerID] = opacityMask
        waterMasks[layerID] = waterMask
        foliageMasks[layerID] = foliageMask
        waterRippleNormals[layerID] = waterRippleNormal
    }
}

enum SceneLayerEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneLayerEffectTextures {
        let iris = loadTexture(
            url: resolveFirstTexture(for: layer, effectFragment: "iris", resolver: resolver),
            label: "iris mask",
            loader: loader,
            device: device
        )
        let opacity = loadTexture(
            url: resolveFirstTexture(for: layer, effectFragment: "opacity", resolver: resolver),
            label: "opacity mask",
            loader: loader,
            device: device
        )
        let water = loadTexture(
            url: resolveMaskedTexture(
                for: layer,
                effectFragments: ["waterwaves", "waterripple"],
                resolver: resolver
            ),
            label: "water mask",
            loader: loader,
            device: device
        )
        let foliage = loadTexture(
            url: resolveMaskedTexture(
                for: layer,
                effectFragments: ["foliagesway", "cursorripple"],
                resolver: resolver
            ),
            label: "foliage mask",
            loader: loader,
            device: device
        )
        let normal = loadTexture(
            url: resolveTextureSlot(
                for: layer,
                effectFragment: "waterripple",
                slot: 2,
                resolver: resolver
            ),
            label: "waterripple normal",
            loader: loader,
            device: device
        )
        return SceneLayerEffectTextures(
            irisMask: iris.texture,
            opacityMask: opacity.texture,
            waterMask: water.texture,
            foliageMask: foliage.texture,
            waterRippleNormal: normal.texture,
            message: [iris.message, opacity.message, water.message, foliage.message, normal.message].joined()
        )
    }

    private static func resolveFirstTexture(
        for layer: SceneRenderDescriptor.Layer,
        effectFragment: String,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false
            && effect.file.localizedLowercase.contains(effectFragment) {
            for path in effect.passes.flatMap(\.texturePaths) {
                if let url = resolver.resolveTextureFile(named: path) { return url }
            }
        }
        return nil
    }

    private static func resolveMaskedTexture(
        for layer: SceneRenderDescriptor.Layer,
        effectFragments: [String],
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false {
            guard effectFragments.contains(where: effect.file.localizedLowercase.contains) else { continue }
            for pass in effect.passes {
                if let path = SceneEffectMaskSemantics.maskPath(in: pass),
                   let url = resolver.resolveTextureFile(named: path) {
                    return url
                }
            }
        }
        return nil
    }

    private static func resolveTextureSlot(
        for layer: SceneRenderDescriptor.Layer,
        effectFragment: String,
        slot: Int,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false
            && effect.file.localizedLowercase.contains(effectFragment) {
            for pass in effect.passes where pass.textureSlots.indices.contains(slot) {
                if let path = pass.textureSlots[slot],
                   let url = resolver.resolveTextureFile(named: path) {
                    return url
                }
            }
        }
        return nil
    }

    private static func loadTexture(
        url: URL?,
        label: String,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (texture: MTLTexture?, message: String) {
        guard let url else { return (nil, "") }
        switch loader.load(from: url, device: device) {
        case .loaded(let texture):
            return (texture, "; \(label) OK \(url.lastPathComponent) → \(texture.width)×\(texture.height)")
        case .unsupportedFormat(let ext):
            return (nil, "; \(label) unsupported \(ext) (\(url.lastPathComponent))")
        case .unsupportedTexFormat(let code):
            return (nil, "; \(label) unsupported .tex format \(code) (\(url.lastPathComponent))")
        case .texNoEmbeddedImage:
            return (nil, "; \(label) has no embedded JPEG/PNG (\(url.lastPathComponent))")
        case .texContainsVideoPayload:
            return (nil, "; \(label) is mp4 payload (\(url.lastPathComponent))")
        case .decodeFailed(let message):
            return (nil, "; \(label) decode failed (\(message))")
        case .textureAllocationFailed(let width, let height):
            return (nil, "; \(label) allocation failed at \(width)×\(height)")
        }
    }
}
