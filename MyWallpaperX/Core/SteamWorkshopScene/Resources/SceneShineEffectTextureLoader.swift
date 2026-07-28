import Metal
import simd

struct SceneShineEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneShineExecutionPlan) -> Bool {
        guard noise != nil,
              normalized(noisePath) == normalized(plan.noiseTexturePath)
        else {
            return false
        }
        guard let planPath = plan.maskTexturePath else { return maskPath == nil }
        return mask != nil && maskPath.map(normalized) == normalized(planPath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneShineEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneShineEffectTextures], message: String) {
        var textures: [String: SceneShineEffectTextures] = [:]
        var messages: [String] = []
        var noiseCache: [String: MTLTexture] = [:]

        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard SceneAuthoredShinePlanner.normalized(effect.file)
                    == SceneAuthoredShinePlanner.definitionPath,
                  effect.passes.count == 5,
                  let pass = effect.passes.first
            else {
                continue
            }
            let maskPath = pass.textureSlots.indices.contains(1)
                ? pass.textureSlots[1]
                : nil
            let noisePath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2] ?? SceneAuthoredShinePlanner.noiseAssetPath
                : SceneAuthoredShinePlanner.noiseAssetPath

            let noiseTexture: MTLTexture?
            if let cached = noiseCache[noisePath] {
                noiseTexture = cached
            } else {
                let noiseURL = resolver.resolveTextureFile(named: noisePath)
                    ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(for: "materials/" + noisePath)
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: noiseURL,
                    label: "shine noise",
                    loader: loader,
                    device: device
                )
                noiseTexture = loaded.texture
                if let texture = loaded.texture { noiseCache[noisePath] = texture }
                messages.append(noiseURL == nil
                    ? "; shine noise missing \(noisePath)"
                    : loaded.message)
            }

            var mask: MTLTexture?
            var maskUVScale = SIMD2<Float>(repeating: 1)
            if let maskPath {
                let maskURL = resolver.resolveTextureFile(named: maskPath)
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: maskURL,
                    label: "shine effect mask",
                    loader: loader,
                    device: device
                )
                mask = loaded.texture
                maskUVScale = SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                )
                messages.append(maskURL == nil
                    ? "; shine effect mask missing \(maskPath)"
                    : loaded.message)
            }

            textures[effect.id] = SceneShineEffectTextures(
                mask: mask,
                maskUVScale: maskUVScale,
                maskPath: maskPath,
                noise: noiseTexture,
                noisePath: noisePath
            )
        }
        return (textures, messages.joined())
    }
}
