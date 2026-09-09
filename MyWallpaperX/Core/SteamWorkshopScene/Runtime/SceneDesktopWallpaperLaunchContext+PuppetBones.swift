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
                worldMatrices: bones.worldMatrices,
                localMatrices: bones.localMatrices,
                names: bones.names, parents: bones.parentIndices.map(Int32.init)
            )
        }
    }

    /// Installs launch-stable Puppet rig metadata into the already-created
    /// SceneScript owners. Vector and cursor programs may share an owner, so
    /// both paths are queried while retaining one underlying journal.
    @discardableResult
    func configurePuppetBones(
        layerID: Int,
        worldMatrices: [Double],
        localMatrices: [Double],
        names: [String],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws -> Bool {
        let vectorConfigured = try propertyVectorScriptProgram
            .configurePuppetBones(
                layerID: layerID,
                worldMatrices: worldMatrices,
                localMatrices: localMatrices,
                names: names, parents: parents, layerToWorld: layerToWorld
            )
        let cursorConfigured = try sceneScriptCursorProgram
            .configurePuppetBones(
                layerID: layerID,
                worldMatrices: worldMatrices,
                localMatrices: localMatrices,
                names: names, parents: parents, layerToWorld: layerToWorld
            )
        return vectorConfigured || cursorConfigured
    }
}
