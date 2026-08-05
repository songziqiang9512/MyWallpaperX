import Foundation

/// Typed ingress admitted across adjacent single-effect graph products.
nonisolated enum SceneResolvedMaterialEffectIngress {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func accepts(
        _ identity: Graph.TextureIdentity,
        layerID: Int,
        owner: Graph.EffectKey
    ) -> Bool {
        guard identity.layerID == layerID, identity.name == nil else { return false }
        switch identity.kind {
        case .layerSource:
            return identity.effect == nil
        case .effectOutput:
            return identity.effect != nil && identity.effect != owner
        case .framebuffer, .unresolved:
            return false
        }
    }
}
