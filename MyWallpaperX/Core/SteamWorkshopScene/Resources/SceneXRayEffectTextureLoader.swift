import Metal
import simd

nonisolated struct SceneXRayEffectTextures {
    let effectID: String
    let blend: MTLTexture
    let halo: MTLTexture?
    let opacityMask: MTLTexture?
    let blendTexturePath: String
    let haloTexturePath: String?
    let opacityMaskPath: String?
    let blendPropertyKey: String?
    let haloPropertyKey: String?
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>

    nonisolated func matches(_ declaration: SceneXRayRuntimePlanner.Declaration) -> Bool {
        effectID == declaration.effectID
            && normalized(blendTexturePath)
                == normalized(declaration.blendTexturePath)
            && normalized(haloTexturePath)
                == normalized(declaration.haloTexturePath)
            && normalized(opacityMaskPath)
                == normalized(declaration.opacityMaskPath)
            && blendPropertyKey == declaration.blendPropertyKey
            && haloPropertyKey == declaration.haloPropertyKey
            && (declaration.opacityMaskPath == nil || opacityMask != nil)
    }

    private nonisolated func normalized(_ value: String?) -> String? {
        value?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneXRayEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        straightAlbedoUserPropertyTextures: [String: MTLTexture] = [:],
        preservedUserPropertyTextures: [String: MTLTexture] = [:]
    ) -> (textures: SceneXRayEffectTextures?, message: String) {
        guard let declaration = SceneXRayRuntimePlanner.declaration(for: layer) else {
            return (nil, "")
        }
        let blendURL = resolver.resolveTextureFile(named: declaration.blendTexturePath)
        let blend = SceneLayerEffectTextureLoader.loadTexture(
            url: blendURL,
            label: "xray blend",
            purpose: .straightAlbedo,
            loader: loader,
            device: device
        )
        let propertyBlend = declaration.blendPropertyKey.flatMap {
            straightAlbedoUserPropertyTextures[$0]
        }
        guard let blendTexture = propertyBlend ?? blend.texture else {
            let missing = blendURL == nil
                ? "; xray blend missing \(declaration.blendTexturePath)"
                : blend.message
            return (nil, missing)
        }

        let haloURL = declaration.haloTexturePath.flatMap(
            resolver.resolveTextureFile(named:)
        )
        let halo = SceneLayerEffectTextureLoader.loadTexture(
            url: haloURL,
            label: "xray halo",
            purpose: .preservedChannels,
            loader: loader,
            device: device
        )
        let propertyHalo = declaration.haloPropertyKey.flatMap {
            preservedUserPropertyTextures[$0]
        }
        if declaration.haloTexturePath != nil, propertyHalo == nil, halo.texture == nil {
            return (nil, blend.message + halo.message)
        }

        let opacityURL = declaration.opacityMaskPath.flatMap(
            resolver.resolveTextureFile(named:)
        )
        let opacity = SceneLayerEffectTextureLoader.loadTexture(
            url: opacityURL,
            label: "xray opacity",
            purpose: .mask,
            loader: loader,
            device: device
        )
        if let path = declaration.opacityMaskPath, opacity.texture == nil {
            let missing = opacityURL == nil ? "; xray opacity missing \(path)" : opacity.message
            return (nil, blend.message + missing)
        }
        return (
            SceneXRayEffectTextures(
                effectID: declaration.effectID,
                blend: blendTexture,
                halo: propertyHalo ?? halo.texture,
                opacityMask: opacity.texture,
                blendTexturePath: declaration.blendTexturePath,
                haloTexturePath: declaration.haloTexturePath,
                opacityMaskPath: declaration.opacityMaskPath,
                blendPropertyKey: declaration.blendPropertyKey,
                haloPropertyKey: declaration.haloPropertyKey,
                blendUVScale: propertyBlend == nil
                    ? SceneLayerEffectTextureLoader.mappedUVScale(
                        for: blendURL,
                        texture: blendTexture
                    )
                    : SIMD2(repeating: 1),
                opacityUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: opacityURL,
                    texture: opacity.texture
                )
            ),
            blend.message + halo.message + opacity.message
                + "; xray runtime ready effect=\(declaration.effectID)"
        )
    }
}
