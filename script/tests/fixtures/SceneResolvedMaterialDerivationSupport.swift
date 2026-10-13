// Shared self-authored Program derivation inputs and builders.

import Foundation
import Metal

nonisolated enum SceneTextureLoadPurpose: Hashable, Sendable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var requiresVolumeTexture: Bool { self == .lookupTable }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored
    case userProperty
    case timeline
    case sceneScript
}

nonisolated struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case sceneEnvironment
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(SceneSystemProviderTextureIdentity)
}
