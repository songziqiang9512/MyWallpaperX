import Foundation

extension SceneScriptVectorOwner {
    /// Installs the launch-prepared Puppet pose into thisLayer's existing
    /// callback owner. The arrays are copied once per frame generation; bone
    /// writes still leave through the normal owner mutation journal.
    func configurePuppetBones(
        layerID: Int,
        worldMatrices: [Double],
        localMatrices: [Double],
        names: [String] = [],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws {
        guard worldMatrices.count == localMatrices.count,
              worldMatrices.count % 16 == 0,
              !worldMatrices.isEmpty else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "invalid Puppet bone matrix payload"
            )
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = worldMatrices.withUnsafeBufferPointer { world in
            localMatrices.withUnsafeBufferPointer { local in
                mwx_scene_quickjs_owner_configure_puppet_bones(
                    handle, Int64(layerID), UInt32(worldMatrices.count / 16),
                    world.baseAddress, local.baseAddress,
                    &diagnostic, diagnostic.count
                )
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
        let hierarchy = parents ?? Array(repeating: Int32(-1), count: worldMatrices.count / 16)
        guard hierarchy.count == worldMatrices.count / 16, layerToWorld.count == 16 else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid Puppet hierarchy payload")
        }
        let hierarchyResult = hierarchy.withUnsafeBufferPointer { parents in
            layerToWorld.withUnsafeBufferPointer { transform in
                mwx_scene_quickjs_owner_configure_puppet_hierarchy(
                    handle, parents.baseAddress, transform.baseAddress,
                    &diagnostic, diagnostic.count
                )
            }
        }
        guard hierarchyResult == MWX_SCENE_QUICKJS_OK else {
            throw Self.failure(hierarchyResult, diagnostic)
        }
        for (index, name) in names.enumerated()
        where index < worldMatrices.count / 16 && !name.isEmpty {
            var nameDiagnostic = [CChar](repeating: 0, count: 512)
            let nameResult = name.withCString {
                mwx_scene_quickjs_owner_set_puppet_bone_name(
                    handle, UInt32(index), $0, name.utf8.count,
                    &nameDiagnostic, nameDiagnostic.count
                )
            }
            guard nameResult == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    String(cString: nameDiagnostic)
                )
            }
        }
    }

}
