import simd

/// Script-facing Puppet bone identity is 1-based.  The format/evaluator side
/// remains dense and zero-based; zero is reserved for an unknown name/handle.
nonisolated enum ScenePuppetBoneScriptIndex {
    static func scriptIndex(
        forName name: String,
        catalog: ScenePuppetBoneCatalog
    ) -> Int {
        guard let dense = catalog.index(forName: name) else { return 0 }
        return dense + 1
    }

    static func denseIndex(
        fromScriptIndex scriptIndex: Int,
        catalog: ScenePuppetBoneCatalog
    ) -> Int? {
        guard scriptIndex > 0 else { return nil }
        let dense = scriptIndex - 1
        guard catalog.entries.indices.contains(dense) else { return nil }
        return dense
    }

    /// Name lookup used by the public `thisLayer.getBoneIndex` adapter.
    static func getBoneIndex(
        _ name: String,
        catalog: ScenePuppetBoneCatalog
    ) -> Int {
        scriptIndex(forName: name, catalog: catalog)
    }
}

/// A frame-local, transactional view of animated Puppet bone transforms.
/// `worldMatrices` are animated world transforms and intentionally do not
/// include the inverse bind matrix used by CPU skinning. The caller supplies
/// the layer-to-world transform so root bones share the scene coordinate space.
/// Local setters derive parent-relative matrices;
/// world setters derive a local matrix and then rebuild descendants.
nonisolated struct ScenePuppetBoneTransformFrame {
    let catalog: ScenePuppetBoneCatalog
    let layerToWorld: simd_float4x4
    private(set) var localMatrices: [simd_float4x4]
    private(set) var worldMatrices: [simd_float4x4]

    var boneCount: Int { catalog.boneCount }

    init(
        rig: SceneMdlPuppetRig,
        animatedLocalMatrices: [simd_float4x4],
        layerToWorld: simd_float4x4 = matrix_identity_float4x4
    ) throws {
        let catalog = try ScenePuppetBoneCatalog(rig: rig)
        guard animatedLocalMatrices.count == catalog.boneCount,
              animatedLocalMatrices.allSatisfy(Self.isFinite),
              Self.isFinite(layerToWorld) else {
            throw ScenePuppetBoneTransformError.invalidMatrix
        }
        self.catalog = catalog
        self.layerToWorld = layerToWorld
        self.localMatrices = animatedLocalMatrices
        self.worldMatrices = try Self.worldMatrices(
            for: animatedLocalMatrices, catalog: catalog, layerToWorld: layerToWorld
        )
    }

    func worldTransform(forScriptIndex scriptIndex: Int) -> simd_float4x4? {
        guard let dense = ScenePuppetBoneScriptIndex.denseIndex(
            fromScriptIndex: scriptIndex, catalog: catalog
        ) else { return nil }
        return worldMatrices[dense]
    }

    /// Corresponding typed owner operation for `thisLayer.getBoneTransform`.
    func getBoneTransform(forScriptIndex scriptIndex: Int) -> simd_float4x4? {
        worldTransform(forScriptIndex: scriptIndex)
    }

    func localTransform(forScriptIndex scriptIndex: Int) -> simd_float4x4? {
        guard let dense = ScenePuppetBoneScriptIndex.denseIndex(
            fromScriptIndex: scriptIndex, catalog: catalog
        ) else { return nil }
        return localMatrices[dense]
    }

    mutating func setLocalTransform(
        _ transform: simd_float4x4,
        forScriptIndex scriptIndex: Int,
        rig: SceneMdlPuppetRig
    ) throws {
        guard let currentCatalog = rig.boneCatalog,
              currentCatalog == catalog,
              Self.isFinite(transform),
              let dense = ScenePuppetBoneScriptIndex.denseIndex(
                  fromScriptIndex: scriptIndex, catalog: catalog
              ) else {
            throw ScenePuppetBoneTransformError.invalidHandle
        }
        try commitLocalTransform(transform, at: dense)
    }

    mutating func setWorldTransform(
        _ transform: simd_float4x4,
        forScriptIndex scriptIndex: Int,
        rig: SceneMdlPuppetRig
    ) throws {
        guard let currentCatalog = rig.boneCatalog,
              currentCatalog == catalog,
              Self.isFinite(transform),
              let dense = ScenePuppetBoneScriptIndex.denseIndex(
                  fromScriptIndex: scriptIndex, catalog: catalog
              ) else {
            throw ScenePuppetBoneTransformError.invalidHandle
        }
        let parent = catalog.entries[dense].parentIndex
        let parentWorld = parent >= 0 ? worldMatrices[parent] : layerToWorld
        let determinant = simd_determinant(parentWorld)
        guard determinant.isFinite, determinant != 0 else {
            throw ScenePuppetBoneTransformError.singularParent
        }
        let candidateLocal = simd_inverse(parentWorld) * transform
        guard Self.isFinite(candidateLocal) else {
            throw ScenePuppetBoneTransformError.invalidMatrix
        }
        // Commit only after every validation succeeds; a rejected setter
        // leaves both local and world views untouched for frame rollback.
        try commitLocalTransform(candidateLocal, at: dense)
    }

    /// Corresponding typed owner operation for `thisLayer.setBoneTransform`.
    mutating func setBoneTransform(
        _ transform: simd_float4x4,
        forScriptIndex scriptIndex: Int,
        rig: SceneMdlPuppetRig
    ) throws {
        try setWorldTransform(transform, forScriptIndex: scriptIndex, rig: rig)
    }

    private mutating func commitLocalTransform(
        _ transform: simd_float4x4, at index: Int
    ) throws {
        var locals = localMatrices
        locals[index] = transform
        let worlds = try Self.worldMatrices(
            for: locals, catalog: catalog, layerToWorld: layerToWorld
        )
        localMatrices = locals
        worldMatrices = worlds
    }

    private static func worldMatrices(
        for locals: [simd_float4x4], catalog: ScenePuppetBoneCatalog,
        layerToWorld: simd_float4x4
    ) throws -> [simd_float4x4] {
        var worlds = locals
        for bone in catalog.entries {
            let world = bone.parentIndex >= 0
                ? worlds[bone.parentIndex] * locals[bone.index]
                : layerToWorld * locals[bone.index]
            guard isFinite(world) else {
                throw ScenePuppetBoneTransformError.invalidMatrix
            }
            worlds[bone.index] = world
        }
        return worlds
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite
                    && column.z.isFinite && column.w.isFinite
            }
    }
}

nonisolated enum ScenePuppetBoneTransformError: Error, Equatable {
    case invalidHandle
    case invalidMatrix
    case singularParent
}
