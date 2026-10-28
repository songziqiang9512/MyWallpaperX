import Foundation

extension SceneDesktopWallpaperLaunchContext {
    func configurePreparedPuppetBones() throws {
        for layer in runtimeInput.renderDescriptor.layers
        where layer.puppetMeshPath != nil || layer.staticModelPath != nil {
            if layer.staticModelPath != nil {
                if let bones = preparedDeviceResources.staticModels.animation(for: layer.id)?.initialBones {
                    _ = try configurePuppetBones(layerID: layer.id,
                        localMatrices: bones.localMatrices, names: bones.names,
                        parents: bones.parentIndices.map(Int32.init),
                        impulseUnavailable: bones.impulseUnavailable)
                }
                continue
            }
            guard let meshPath = layer.puppetMeshPath,
                  case let .ready(asset)? = preparedDeviceResources.baseImages.puppets.assetsByMeshPath[meshPath.lowercased()],
                  let bones = ScenePuppetLayerLoad.boneConfiguration(for: asset, layerID: layer.id)
            else { continue }
            _ = try configurePuppetBones(
                layerID: layer.id,
                localMatrices: bones.localMatrices,
                names: bones.names, parents: bones.parentIndices.map(Int32.init),
                impulseUnavailable: bones.impulseUnavailable
            )
        }
    }

    /// Installs rig metadata once per existing VM, regardless of its return
    /// type or whether cursor callbacks borrow that VM.
    @discardableResult
    func configurePuppetBones(
        layerID: Int,
        localMatrices: [Double],
        renderLocalMatrices: [Double]? = nil,
        names: [String],
        parents: [Int32]? = nil,
        impulseUnavailable: [UInt8]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws -> Bool {
        let owners = propertyVectorScriptProgram.bindings.map(\.owner)
            + sceneScriptScalarProgram.bindings + sceneScriptStringProgram.bindings
            + sceneScriptCursorProgram.bindings.map(\.owner)
        var visited: Set<ObjectIdentifier> = []
        var configured = false
        for owner in owners where owner.layerID == layerID {
            guard visited.insert(ObjectIdentifier(owner)).inserted else { continue }
            try owner.configurePuppetBones(
                layerID: layerID, localMatrices: localMatrices,
                renderLocalMatrices: renderLocalMatrices, names: names,
                parents: parents, impulseUnavailable: impulseUnavailable,
                layerToWorld: layerToWorld
            )
            configured = true
        }
        return configured
    }
}
