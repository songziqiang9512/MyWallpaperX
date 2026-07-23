import Metal
import simd

struct SceneLayerEffectTextures {
    let irisMask: MTLTexture?
    let opacityMask: MTLTexture?
    let waterMask: MTLTexture?
    let foliageMask: MTLTexture?
    let foliageUVScale: SIMD2<Float>
    let waterRippleNormal: MTLTexture?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var irisMasks: [Int: MTLTexture] = [:]
    var opacityMasks: [Int: MTLTexture] = [:]
    var waterMasks: [Int: MTLTexture] = [:]
    var foliageMasks: [Int: MTLTexture] = [:]
    var foliageUVScales: [Int: SIMD2<Float>] = [:]
    var waterRippleNormals: [Int: MTLTexture] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        irisMasks[layerID] = textures.irisMask
        opacityMasks[layerID] = textures.opacityMask
        waterMasks[layerID] = textures.waterMask
        foliageMasks[layerID] = textures.foliageMask
        foliageUVScales[layerID] = textures.foliageUVScale
        waterRippleNormals[layerID] = textures.waterRippleNormal
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
        let foliageURL = resolveMaskedTexture(
            for: layer,
            effectFragments: ["foliagesway", "cursorripple"],
            resolver: resolver
        )
        let foliage = loadTexture(
            url: foliageURL,
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
        let foliageUVScale = mappedUVScale(for: foliageURL)
        let foliageScaleMessage = foliage.texture == nil || foliageUVScale == SIMD2(repeating: 1)
            ? ""
            : String(
                format: "; foliage mapped UV scale=(%.6f, %.6f)",
                foliageUVScale.x,
                foliageUVScale.y
            )
        return SceneLayerEffectTextures(
            irisMask: iris.texture,
            opacityMask: opacity.texture,
            waterMask: water.texture,
            foliageMask: foliage.texture,
            foliageUVScale: foliageUVScale,
            waterRippleNormal: normal.texture,
            message: [
                iris.message, opacity.message, water.message, foliage.message,
                foliageScaleMessage, normal.message,
            ].joined()
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

    private static func mappedUVScale(for url: URL?) -> SIMD2<Float> {
        guard let url, url.pathExtension.localizedLowercase == "tex",
              let data = try? Data(contentsOf: url),
              let container = try? SceneTexContainerReader().read(data: data) else {
            return SIMD2(repeating: 1)
        }
        return SceneTextureMappedUVScale.resolve(
            physicalWidth: container.textureWidth,
            physicalHeight: container.textureHeight,
            mappedWidth: container.imageWidth,
            mappedHeight: container.imageHeight
        )
    }
}
