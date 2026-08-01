import Metal
import simd

struct SceneMediaThumbnailTransitionTexture {
    struct Arguments {
        let texture: MTLTexture
        let uvScale: SIMD2<Float>
        let sampling: SceneTextureSampling
    }

    let path: String
    let binding: SceneTextureSlotBinding

    func arguments(
        for plan: SceneMediaThumbnailTransitionPlan
    ) -> Arguments? {
        guard normalized(path) == normalized(plan.gradientTexturePath),
              let uvScale = binding.axisAlignedUVScale(
                  expectedSlotIndex: 2,
                  expectedPurpose: .mask,
                  allowedPixelFormats: [
                      .r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
                  ]
              ) else {
            return nil
        }
        return Arguments(
            texture: binding.texture,
            uvScale: uvScale,
            sampling: binding.sampling
        )
    }

    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneMediaThumbnailTransitionTextureLoader {
    static func load(
        program: SceneMediaThumbnailBindingProgram,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (
        textures: [Int: SceneMediaThumbnailTransitionTexture],
        reportLines: [String]
    ) {
        var textures: [Int: SceneMediaThumbnailTransitionTexture] = [:]
        var reportLines: [String] = []
        for (layerID, plan) in program.previousTransitionsByLayerID.sorted(
            by: { $0.key < $1.key }
        ) {
            let url = resolver.resolveTextureFile(named: plan.gradientTexturePath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: url,
                label: "media previous gradient",
                purpose: .mask,
                loader: loader,
                device: device
            )
            guard let candidate = loaded.candidate,
                  let binding = SceneTextureSlotBinding(
                      slotIndex: 2,
                      candidate: candidate
                  ) else {
                reportLines.append(
                    "mediaThumbnailPreviousTransitionGradient layer=\(layerID) status=failed"
                        + loaded.message
                )
                continue
            }
            let resource = SceneMediaThumbnailTransitionTexture(
                path: plan.gradientTexturePath,
                binding: binding
            )
            guard resource.arguments(for: plan) != nil else {
                reportLines.append(
                    "mediaThumbnailPreviousTransitionGradient layer=\(layerID)"
                        + " status=rejected-metadata"
                )
                continue
            }
            textures[layerID] = resource
            reportLines.append(
                "mediaThumbnailPreviousTransitionGradient layer=\(layerID) status=ready"
                    + loaded.message
            )
        }
        return (textures, reportLines)
    }
}
