import Metal
import simd

struct SceneWaterRippleEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String
    let normal: MTLTexture?
    let normalPath: String

    func matches(_ plan: SceneWaterRippleExecutionPlan) -> Bool {
        mask != nil
            && normal != nil
            && normalized(maskPath) == normalized(plan.maskTexturePath)
            && normalized(normalPath) == normalized(plan.normalTexturePath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneWaterRippleEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterRippleEffectTextures], message: String) {
        var textures: [String: SceneWaterRippleEffectTextures] = [:]
        var messages: [String] = []
        var normalCache: [String: MTLTexture] = [:]

        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/waterripple/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.textureSlots.count == 3,
                  let maskPath = pass.textureSlots[1],
                  let normalPath = pass.textureSlots[2]
            else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loadedMask = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "waterripple effect mask",
                loader: loader,
                device: device
            )
            let normalTexture: MTLTexture?
            if let cached = normalCache[normalPath] {
                normalTexture = cached
            } else {
                let normalURL = resolver.resolveTextureFile(named: normalPath)
                    ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(for: "materials/" + normalPath)
                let loadedNormal = SceneLayerEffectTextureLoader.loadTexture(
                    url: normalURL,
                    label: "waterripple effect normal",
                    loader: loader,
                    device: device
                )
                normalTexture = loadedNormal.texture
                if let texture = loadedNormal.texture {
                    normalCache[normalPath] = texture
                }
                messages.append(normalURL == nil
                    ? "; waterripple normal missing \(normalPath)"
                    : loadedNormal.message)
            }
            textures[effect.id] = SceneWaterRippleEffectTextures(
                mask: loadedMask.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loadedMask.texture
                ),
                maskPath: maskPath,
                normal: normalTexture,
                normalPath: normalPath
            )
            messages.append(maskURL == nil
                ? "; waterripple effect mask missing \(maskPath)"
                : loadedMask.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
