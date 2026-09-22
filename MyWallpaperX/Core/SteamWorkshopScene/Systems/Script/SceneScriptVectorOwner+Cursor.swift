import Foundation

extension SceneScriptVectorOwner {
    func clearCursorAuthoredLayerBaselines() {
        mwx_scene_quickjs_owner_clear_authored_layer_baseline(handle)
        mwx_scene_quickjs_owner_clear_authored_layer_mutation_baselines(handle)
    }

    func configureCursorAuthoredLayerBaselines(
        _ baselines: [SceneScriptLayerMutation]
    ) -> SceneScriptScalarRuntimeFailure? {
        clearCursorAuthoredLayerBaselines()
        guard baselines.count <= 64 else {
            return .mutationOverflow("cursor authored baseline budget exceeded")
        }
        for baseline in baselines {
            guard baseline.kind == .upsert,
                  !baseline.isDynamic,
                  !baseline.fields.isEmpty,
                  baseline.fields.isSubset(of: .authoredFields),
                  baseline.origin.x.isFinite,
                  baseline.origin.y.isFinite,
                  baseline.origin.z.isFinite,
                  baseline.scale.x.isFinite,
                  baseline.scale.y.isFinite,
                  baseline.scale.z.isFinite,
                  baseline.angles.x.isFinite,
                  baseline.angles.y.isFinite,
                  baseline.angles.z.isFinite,
                  baseline.text.utf8.count <= 4_096,
                  !baseline.text.contains("\0"),
                  baseline.font.utf8.count <= 1_024,
                  !baseline.font.contains("\0") else {
                clearCursorAuthoredLayerBaselines()
                return .invalidArgument("invalid cursor authored layer baseline")
            }
            var origin = [
                baseline.origin.x, baseline.origin.y, baseline.origin.z,
            ]
            var scale = [
                baseline.scale.x, baseline.scale.y, baseline.scale.z,
            ]
            var angles = [
                baseline.angles.x, baseline.angles.y, baseline.angles.z,
            ]
            var diagnostic = [CChar](repeating: 0, count: 512)
            let raw = baseline.text.withCString { textPointer in
                baseline.font.withCString { fontPointer in
                    origin.withUnsafeMutableBufferPointer { originPointer in
                        scale.withUnsafeMutableBufferPointer { scalePointer in
                            angles.withUnsafeMutableBufferPointer { anglesPointer in
                                mwx_scene_quickjs_owner_add_authored_layer_mutation_baseline(
                                    handle,
                                    generation,
                                    Int64(baseline.layerID),
                                    baseline.fields.rawValue,
                                    originPointer.baseAddress,
                                    scalePointer.baseAddress,
                                    anglesPointer.baseAddress,
                                    baseline.visible ? 1 : 0,
                                    textPointer,
                                    baseline.text.utf8.count,
                                    fontPointer,
                                    baseline.font.utf8.count,
                                    baseline.alpha,
                                    [baseline.color.x, baseline.color.y, baseline.color.z],
                                    &diagnostic,
                                    diagnostic.count
                                )
                            }
                        }
                    }
                }
            }
            guard raw == MWX_SCENE_QUICKJS_OK else {
                clearCursorAuthoredLayerBaselines()
                return Self.failure(raw, diagnostic)
            }
        }
        return nil
    }
}
