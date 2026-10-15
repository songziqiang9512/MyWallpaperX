import Foundation

/// Immutable CPU model preparation retained by the existing launch resources.
/// Actual authored poses and default creation poses never share a selection.
struct ScenePreparedPuppetResources {
    let assetsByMeshPath: [String: ScenePuppetLayerLoad.AssetPreparation]
    let posesByLayerID: [Int: ScenePuppetLayerLoad.PreparedPose]
    private let defaultPosesByMeshPath: [String: ScenePuppetLayerLoad.PreparedPose]

    static func prepare(
        descriptor: SceneRenderDescriptor,
        cacheDirectory: URL,
        cancellationCheck: () throws -> Void
    ) throws -> Self {
        let layers = descriptor.layers.filter { $0.puppetMeshPath != nil }
        var demands: [String: (path: String, animations: Bool)] = [:]
        for layer in layers {
            guard let path = layer.puppetMeshPath else { continue }
            let key = path.lowercased()
            let previous = demands[key]
            demands[key] = (previous?.path ?? path,
                previous?.animations == true || !layer.puppetAnimationLayers.isEmpty)
        }
        var assets: [String: ScenePuppetLayerLoad.AssetPreparation] = [:]
        for (key, demand) in demands {
            try cancellationCheck()
            assets[key] = ScenePuppetLayerLoad.prepareAsset(meshPath: demand.path,
                cacheDirectory: cacheDirectory, needsAnimations: demand.animations)
        }
        var poses: [Int: ScenePuppetLayerLoad.PreparedPose] = [:]
        var defaults: [String: ScenePuppetLayerLoad.PreparedPose] = [:]
        for layer in layers {
            try cancellationCheck()
            guard let key = layer.puppetMeshPath?.lowercased(), let asset = assets[key] else { continue }
            poses[layer.id] = ScenePuppetLayerLoad.preparePose(for: layer, asset: asset)
            // An unavailable mesh does not qualify a newly created geometry.
            guard defaults[key] == nil, case .ready = asset else { continue }
            defaults[key] = ScenePuppetLayerLoad.preparePose(for: layer, asset: asset,
                usesDefaultConfiguration: true)
        }
        return .init(assetsByMeshPath: assets, posesByLayerID: poses,
            defaultPosesByMeshPath: defaults)
    }

    func defaultPose(for layer: SceneRenderDescriptor.Layer) -> ScenePuppetLayerLoad.PreparedPose? {
        layer.puppetMeshPath.flatMap { defaultPosesByMeshPath[$0.lowercased()] }
    }
}
