import Foundation

extension SceneScriptCursorProgram {
    @discardableResult
    func configurePuppetBones(
        layerID: Int,
        worldMatrices: [Double],
        localMatrices: [Double],
        names: [String],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws -> Bool {
        var configured = false
        for binding in bindings where binding.layerID == layerID {
            try binding.owner.configurePuppetBones(
                layerID: layerID,
                worldMatrices: worldMatrices,
                localMatrices: localMatrices,
                names: names, parents: parents, layerToWorld: layerToWorld
            )
            configured = true
        }
        return configured
    }
}
