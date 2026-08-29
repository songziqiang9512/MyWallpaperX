import Foundation

nonisolated struct SceneScriptLayerMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case upsert, destroy }

    struct Fields: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let origin = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN.rawValue
        ))
        static let scale = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE.rawValue
        ))
        static let angles = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES.rawValue
        ))
        static let authoredTransform: Self = [.origin, .scale, .angles]
    }

    let kind: Kind
    let isDynamic: Bool
    let fields: Fields
    let layerID: Int
    let orderIndex: Int
    let visible: Bool
    let alpha: Double
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let angles: SIMD3<Double>
    let color: SIMD3<Double>
    let pointSize: Double
    let text: String
    let font: String
}

nonisolated enum SceneScriptLayerMutationBridge {
    static func configure(owner: OpaquePointer, target: SceneDynamicTarget) throws {
        guard let layerID = layerID(for: target) else { return }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_owner_configure_layer_identity(
            owner, Int64(layerID), &diagnostic, diagnostic.count
        )
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
    }

    static func layerID(for target: SceneDynamicTarget) -> Int? {
        switch target {
        case let .layer(id, _), let .text(id, _), let .particle(id, _),
             let .effectConstant(id, _, _, _), let .effectVisibility(id, _),
             let .scriptInstanceProperty(id, _):
            id
        default:
            nil
        }
    }

    static func mutations(
        owner: OpaquePointer
    ) -> Result<[SceneScriptLayerMutation], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_layer_mutation_count(owner)
        guard count <= 64 else { return .failure(.mutationOverflow("layer mutation buffer exceeded")) }
        var output: [SceneScriptLayerMutation] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSLayerMutation()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_layer_mutation_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.layer_id >= Int64(Int.min), raw.layer_id <= Int64(Int.max),
                  raw.alpha.isFinite, raw.point_size.isFinite,
                  raw.origin.0.isFinite, raw.origin.1.isFinite, raw.origin.2.isFinite,
                  raw.scale.0.isFinite, raw.scale.1.isFinite, raw.scale.2.isFinite,
                  raw.angles.0.isFinite, raw.angles.1.isFinite, raw.angles.2.isFinite,
                  raw.color.0.isFinite, raw.color.1.isFinite, raw.color.2.isFinite,
                  let textPointer = raw.text, let fontPointer = raw.font else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let fields = SceneScriptLayerMutation.Fields(rawValue: raw.fields)
            guard raw.dynamic != 0 || (
                !fields.isEmpty && fields.isSubset(of: .authoredTransform)
            ) else {
                return .failure(.invalidArgument("invalid authored layer mutation fields"))
            }
            output.append(.init(
                kind: raw.kind == UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY.rawValue)
                    ? .destroy : .upsert,
                isDynamic: raw.dynamic != 0, fields: fields,
                layerID: Int(raw.layer_id), orderIndex: Int(raw.order_index),
                visible: raw.visible != 0, alpha: raw.alpha,
                origin: .init(raw.origin.0, raw.origin.1, raw.origin.2),
                scale: .init(raw.scale.0, raw.scale.1, raw.scale.2),
                angles: .init(raw.angles.0, raw.angles.1, raw.angles.2),
                color: .init(raw.color.0, raw.color.1, raw.color.2),
                pointSize: raw.point_size,
                text: String(cString: textPointer), font: String(cString: fontPointer)
            ))
        }
        return .success(output)
    }
}

/// Publishes the existing frame snapshot into the callback-scoped SceneScript
/// handle projection. This is not a second property store: every frame starts
/// from descriptor-authored origins and overlays only resolved current values.
nonisolated extension SceneScriptQuickJSDomain {
    func configureLayerCatalog(_ descriptor: SceneRenderDescriptor) throws {
        guard descriptor.layers.count <= 4096,
              descriptor.layers.allSatisfy({ layer in
                  let layerID = Int64(layer.id)
                  let validOrigin = layer.originXYZ.map {
                      $0.count == 3 && $0.allSatisfy(\.isFinite)
                  } ?? true
                  return layerID >= -9_007_199_254_740_991
                    && layerID <= 9_007_199_254_740_991
                    && (layer.name?.utf8.count ?? 0) <= 256
                    && !(layer.name?.contains("\0") ?? false)
                    && validOrigin
              }) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer catalog exceeds its identity contract"
            )
        }
        let signature = descriptor.layers.enumerated().map { index, layer in
            let origin = layer.originXYZ ?? [0, 0, 0]
            return "\(index):\(layer.id):\(layer.name ?? ""):\(origin)"
        }.joined(separator: "|")
        if let configured = layerCatalogSignature {
            guard configured == signature else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer catalog identity changed"
                )
            }
            return
        }

        var diagnostic = [CChar](repeating: 0, count: 512)
        guard mwx_scene_quickjs_domain_configure_layer_catalog(
            handle,
            UInt32(descriptor.layers.count),
            &diagnostic,
            diagnostic.count
        ) == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                Self.layerDiagnostic(diagnostic)
            )
        }
        for (index, layer) in descriptor.layers.enumerated() {
            let name = layer.name ?? ""
            let authored = layer.originXYZ ?? [0, 0, 0]
            let origin = authored.map(Double.init)
            let result = name.withCString { namePointer in
                origin.withUnsafeBufferPointer { originPointer in
                    mwx_scene_quickjs_domain_set_layer_descriptor(
                        handle, UInt32(index), Int64(layer.id),
                        namePointer, name.utf8.count,
                        originPointer.baseAddress,
                        &diagnostic, diagnostic.count
                    )
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    Self.layerDiagnostic(diagnostic)
                )
            }
        }
        layerCatalogSignature = signature
    }

    func publishLayerSnapshot(
        _ snapshot: SceneDynamicSnapshot,
        descriptor: SceneRenderDescriptor
    ) throws {
        try configureLayerCatalog(descriptor)
        guard layerSnapshotGeneration < UInt64.max else {
            throw SceneScriptScalarRuntimeFailure.staleOwner
        }
        layerSnapshotGeneration += 1
        var diagnostic = [CChar](repeating: 0, count: 512)
        guard mwx_scene_quickjs_domain_begin_layer_snapshot(
            handle,
            layerSnapshotGeneration,
            &diagnostic,
            diagnostic.count
        ) == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                Self.layerDiagnostic(diagnostic)
            )
        }
        try publishLayerRuntimeFields(snapshot, descriptor: descriptor)
        for (index, layer) in descriptor.layers.enumerated() {
            guard let resolved = snapshot[.layer(layerID: layer.id, field: .origin)],
                  case let .vector3(x, y, z) = resolved.value,
                  x.isFinite, y.isFinite, z.isFinite else { continue }
            let origin = [x, y, z]
            let result = origin.withUnsafeBufferPointer { pointer in
                mwx_scene_quickjs_domain_set_layer_origin(
                    handle,
                    UInt32(index),
                    pointer.baseAddress,
                    &diagnostic,
                    diagnostic.count
                )
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    Self.layerDiagnostic(diagnostic)
                )
            }
        }
    }

    private static func layerDiagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
