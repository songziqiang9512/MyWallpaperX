import CoreGraphics
import simd

/// Frame-local proof that a captured-main composition subtree has already
/// established an opaque full-viewport source before its effect chain runs.
/// Without this proof, direct descendant draws would flatten a transparent
/// group against the main clear target and destroy group RGBA semantics.
nonisolated enum SceneUtilityLayerSourceCoverage {
    struct LayerFrame {
        let content: SceneTextureContent
        let alpha: Float
        let modelViewProjection: simd_float4x4
    }

    static func hasOpaqueFullViewportSource(
        route: SceneUtilityLayerSourceRoute.Resolution,
        descriptor: SceneRenderDescriptor,
        framesByLayerID: [Int: LayerFrame],
        viewportSize: CGSize
    ) -> Bool {
        guard route.capturesCompositionSubtree,
              !route.orderedCompositionSubtreeLayerIDs.isEmpty else {
            return true
        }
        let layersByID = Dictionary(
            uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) }
        )
        return route.orderedCompositionSubtreeLayerIDs.dropFirst().contains {
            layerID in
            guard let layer = layersByID[layerID],
                  ["image", "solid"].contains(layer.contentKind),
                  layer.childLayerIDs.isEmpty,
                  layer.effects.isEmpty,
                  (layer.colorBlendMode ?? 0) == 0,
                  let frame = framesByLayerID[layerID],
                  frame.content == .color(.resolved(.opaque)),
                  frame.alpha == 1 else {
                return false
            }
            return SceneCaptureGeometryResolver
                .isAxisAlignedFullViewportCoverage(
                    layerMVP: frame.modelViewProjection,
                    viewportSize: viewportSize
                )
        }
    }
}
