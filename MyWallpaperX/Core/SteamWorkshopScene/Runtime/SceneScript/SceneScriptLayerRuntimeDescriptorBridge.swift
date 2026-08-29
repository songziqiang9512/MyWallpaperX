import Foundation

nonisolated extension SceneScriptQuickJSDomain {
    func configureLayerRuntimeFields(_ descriptor: SceneRenderDescriptor) throws {
        try configureLayerCatalog(descriptor)
        for (index, layer) in descriptor.layers.enumerated() {
            let scale = (layer.scaleXYZ ?? [1, 1, 1]).map(Double.init)
            let angles = (layer.anglesXYZ ?? [0, 0, 0]).map(Double.init)
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
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    String(cString: diagnostic)
                )
            }
        }
    }
}
