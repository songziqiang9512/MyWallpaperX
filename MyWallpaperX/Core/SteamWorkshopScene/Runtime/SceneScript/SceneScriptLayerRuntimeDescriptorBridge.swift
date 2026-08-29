import Foundation

nonisolated extension SceneScriptQuickJSDomain {
    func configureLayerRuntimeFields(_ descriptor: SceneRenderDescriptor) throws {
        try publishLayerSnapshot(
            .empty(frameIndex: 0),
            descriptor: descriptor
        )
    }

    func publishLayerRuntimeFields(
        _ snapshot: SceneDynamicSnapshot,
        descriptor: SceneRenderDescriptor
    ) throws {
        try configureLayerCatalog(descriptor)
        for (index, layer) in descriptor.layers.enumerated() {
            let scale = layerTransform(
                layerID: layer.id, field: .scale,
                authored: layer.scaleXYZ, fallback: [1, 1, 1],
                snapshot: snapshot
            )
            let angles = layerTransform(
                layerID: layer.id, field: .angles,
                authored: layer.anglesXYZ, fallback: [0, 0, 0],
                snapshot: snapshot
            )
            let text = layer.text ?? ""
            let font = layer.textStyle?.fontPath ?? ""
            let color = (layer.textStyle?.colorRGB ?? layer.colorRGB ?? [1, 1, 1])
                .map(Double.init)
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = text.withCString { textPointer in
                font.withCString { fontPointer in
                    scale.withUnsafeBufferPointer { scalePointer in
                        angles.withUnsafeBufferPointer { anglesPointer in
                            color.withUnsafeBufferPointer { colorPointer in
                                mwx_scene_quickjs_domain_update_layer_runtime_fields(
                                    handle, UInt32(index), scalePointer.baseAddress,
                                    anglesPointer.baseAddress,
                                    layer.visible == false ? 0 : 1,
                                    layer.alpha ?? 1,
                                    textPointer, text.utf8.count,
                                    fontPointer, font.utf8.count,
                                    Double(layer.textStyle?.pointSize ?? 32),
                                    colorPointer.baseAddress,
                                    &diagnostic, diagnostic.count
                                )
                            }
                        }
                    }
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw layerSnapshotFailure(result, diagnostic: diagnostic)
            }
        }
    }

    private func layerTransform(
        layerID: Int,
        field: SceneDynamicLayerField,
        authored: [Float]?,
        fallback: [Double],
        snapshot: SceneDynamicSnapshot
    ) -> [Double] {
        if let resolved = snapshot[.layer(layerID: layerID, field: field)],
           case let .vector3(x, y, z) = resolved.value,
           x.isFinite, y.isFinite, z.isFinite {
            return [x, y, z]
        }
        let values = authored?.map(Double.init) ?? fallback
        return (0..<3).map { index in
            index < values.count ? values[index] : fallback[index]
        }
    }
}
