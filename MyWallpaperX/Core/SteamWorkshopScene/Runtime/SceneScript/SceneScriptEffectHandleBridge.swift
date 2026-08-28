import Foundation

/// Bridges callback-scoped `thisLayer -> IEffect` handles to the existing
/// frame-scoped material-function mutation carrier. Descriptor ordinals and
/// authored names are the only lookup authority; JavaScript cannot invent an
/// effect identity.
nonisolated enum SceneScriptEffectHandleBridge {
    static func configure(
        owner: OpaquePointer,
        effectNames: [String?]
    ) throws {
        guard effectNames.count <= 1_024 else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "effect catalog exceeds owner budget"
            )
        }
        var diagnostic = [CChar](repeating: 0, count: 256)
        let configured = mwx_scene_quickjs_owner_configure_effect_catalog(
            owner,
            UInt32(effectNames.count),
            &diagnostic,
            diagnostic.count
        )
        guard configured == MWX_SCENE_QUICKJS_OK else {
            throw failure(configured, diagnostic)
        }
        for (index, name) in effectNames.enumerated() {
            guard let name, !name.isEmpty,
                  !name.utf8.contains(0), name.utf8.count <= 256 else { continue }
            let result = name.withCString { pointer in
                mwx_scene_quickjs_owner_set_effect_name(
                    owner,
                    UInt32(index),
                    pointer,
                    name.utf8.count,
                    &diagnostic,
                    diagnostic.count
                )
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw failure(result, diagnostic)
            }
        }
    }

    static func mutations(
        owner: OpaquePointer,
        layerID: Int
    ) -> Result<[SceneScriptMaterialFunctionMutation], SceneScriptScalarRuntimeFailure> {
        var result: [SceneScriptMaterialFunctionMutation] = []
        let count = mwx_scene_quickjs_owner_material_function_count(owner)
        for index in 0..<count {
            var effectIndex: UInt32 = 0
            var name = [CChar](repeating: 0, count: 128)
            var diagnostic = [CChar](repeating: 0, count: 256)
            let raw = mwx_scene_quickjs_owner_material_function_at(
                owner,
                index,
                &effectIndex,
                &name,
                name.count,
                &diagnostic,
                diagnostic.count
            )
            guard raw == MWX_SCENE_QUICKJS_OK else {
                return .failure(failure(raw, diagnostic))
            }
            let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let functionName = String(decoding: bytes, as: UTF8.self)
            guard !functionName.isEmpty else {
                return .failure(.invalidArgument("empty material function mutation"))
            }
            result.append(.init(
                layerID: layerID,
                effectIndex: Int(effectIndex),
                functionName: functionName
            ))
        }
        return .success(result)
    }

    private static func failure(
        _ raw: MWXSceneQuickJSResult,
        _ buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return switch raw {
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        default: .invalidArgument(diagnostic)
        }
    }
}
