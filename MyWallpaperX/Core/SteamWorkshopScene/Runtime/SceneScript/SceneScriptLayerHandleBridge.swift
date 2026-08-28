import Foundation

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
                        handle,
                        UInt32(index),
                        Int64(layer.id),
                        namePointer,
                        name.utf8.count,
                        originPointer.baseAddress,
                        &diagnostic,
                        diagnostic.count
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
