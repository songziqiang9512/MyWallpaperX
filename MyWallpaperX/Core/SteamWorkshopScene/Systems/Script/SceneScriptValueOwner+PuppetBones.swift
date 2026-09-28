import Foundation

extension SceneScriptValueOwner {
    /// Installs the launch-prepared Puppet pose into thisLayer's existing
    /// callback owner. The arrays are copied once per frame generation; bone
    /// writes still leave through the normal owner mutation journal.
    func configurePuppetBones(
        layerID: Int,
        localMatrices: [Double],
        names: [String] = [],
        parents: [Int32]? = nil,
        layerToWorld: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    ) throws {
        let count = localMatrices.count / 16
        let hierarchy = parents ?? Array(repeating: Int32(-1), count: count)
        guard !localMatrices.isEmpty, localMatrices.count % 16 == 0,
              count <= 256, hierarchy.count == count, layerToWorld.count == 16 else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "invalid Puppet pose payload"
            )
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = localMatrices.withUnsafeBufferPointer { local in
            hierarchy.withUnsafeBufferPointer { parents in
                layerToWorld.withUnsafeBufferPointer { transform in
                    mwx_scene_quickjs_owner_configure_puppet_bones(
                        handle, Int64(layerID), UInt32(count), local.baseAddress,
                        parents.baseAddress, transform.baseAddress,
                        &diagnostic, diagnostic.count
                    )
                }
            }
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw Self.failure(result, diagnostic)
        }
        for (index, name) in names.enumerated()
        where index < count && !name.isEmpty {
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
