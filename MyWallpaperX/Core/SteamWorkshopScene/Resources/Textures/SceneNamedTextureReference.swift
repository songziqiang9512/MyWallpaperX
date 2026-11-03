import Foundation

nonisolated struct SceneNamedTextureReference: Hashable, Sendable {
    nonisolated enum Variant: String, Sendable {
        case primary = "a"
        case secondary = "b"
        case unspecified
    }

    let providerLayerID: Int
    let variant: Variant

    nonisolated static func parse(_ rawValue: String?) -> SceneNamedTextureReference? {
        guard var suffix = rawValue, suffix.hasPrefix(prefix) else { return nil }
        suffix.removeFirst(prefix.count)

        let variant: Variant
        if suffix.hasSuffix("_a") {
            variant = .primary
            suffix.removeLast(2)
        } else if suffix.hasSuffix("_b") {
            variant = .secondary
            suffix.removeLast(2)
        } else {
            variant = .unspecified
        }
        guard let layerID = Int(suffix), layerID >= 0 else { return nil }
        return SceneNamedTextureReference(providerLayerID: layerID, variant: variant)
    }

    nonisolated private static let prefix = "_rt_imageLayerComposite_"
}

/// Prepared classification of an authored render-target reference; resource
/// allocation and publication remain with their current runtime owners.
nonisolated enum SceneRenderTargetReferenceKind: Hashable {
    case typedFrameInput
    case sceneEnvironment
    case namedLayerTarget(SceneNamedTextureReference)
    /// Preserve an unknown or malformed spelling for the admitting caller.
    case unadmitted(String)
}

nonisolated struct SceneEffectPassSlot: Hashable {
    let effectID: String
    let passIndex: Int
    let slotIndex: Int
}
