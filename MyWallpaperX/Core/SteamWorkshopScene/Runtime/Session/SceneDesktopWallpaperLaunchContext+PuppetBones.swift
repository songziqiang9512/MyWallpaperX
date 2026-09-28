import Foundation

extension SceneDesktopWallpaperLaunchContext {
    func configurePreparedPuppetBones() throws {
        for layer in runtimeInput.renderDescriptor.layers
        where layer.puppetMeshPath != nil {
            guard let bones = ScenePuppetLayerLoad.boneConfiguration(
                for: layer, cacheDirectory: cacheDirectory
            ) else { continue }
            _ = try configurePuppetBones(
                layerID: layer.id,
                localMatrices: bones.localMatrices,
                names: bones.names, parents: bones.parentIndices.map(Int32.init)
            )
        }
    }

    /// Installs rig metadata once per existing VM, regardless of its return
    /// type or whether cursor callbacks borrow that VM.
    @discardableResult
    func configurePuppetBones(
        layerID: Int,
        localMatrices: [Double],
        names: [String],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws -> Bool {
        let owners = propertyVectorScriptProgram.bindings.map(\.owner)
            + sceneScriptScalarProgram.bindings + sceneScriptStringProgram.bindings
            + sceneScriptCursorProgram.bindings.map(\.owner)
        var visited: Set<ObjectIdentifier> = []
        var configured = false
        for owner in owners where SceneScriptLayerMutationBridge.layerID(for: owner.target) == layerID {
            guard visited.insert(ObjectIdentifier(owner)).inserted else { continue }
            try owner.configurePuppetBones(
                layerID: layerID, localMatrices: localMatrices, names: names,
                parents: parents, layerToWorld: layerToWorld
            )
            configured = true
        }
        return configured
    }
}
