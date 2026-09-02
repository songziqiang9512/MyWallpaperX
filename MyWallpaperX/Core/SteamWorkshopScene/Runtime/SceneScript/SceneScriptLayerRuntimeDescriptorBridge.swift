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
        descriptor: SceneRenderDescriptor,
        videoSnapshots: [Int: SceneScriptVideoPlaybackSnapshot] = [:]
    ) throws {
        try configureLayerCatalog(descriptor)
        for (index, layer) in descriptor.layers.enumerated() {
            let scale = layerVector3(
                layerID: layer.id, field: .scale,
                authored: layer.scaleXYZ, fallback: [1, 1, 1],
                snapshot: snapshot
            )
            let angles = layerVector3(
                layerID: layer.id, field: .angles,
                authored: layer.anglesXYZ, fallback: [0, 0, 0],
                snapshot: snapshot
            )
            let text: String
            if let resolved = snapshot[
                .text(layerID: layer.id, field: .content)
            ], case let .string(value) = resolved.value {
                text = value
            } else {
                text = layer.text ?? ""
            }
            let font = layer.textStyle?.fontPath ?? ""
            let colorTarget: SceneDynamicTarget = layer.contentKind == "text"
                ? .text(layerID: layer.id, field: .color)
                : .layer(layerID: layer.id, field: .color)
            let color = vector3(
                target: colorTarget,
                authored: layer.textStyle?.colorRGB ?? layer.colorRGB,
                fallback: [1, 1, 1], snapshot: snapshot
            )
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = text.withCString { textPointer in
                font.withCString { fontPointer in
                    scale.withUnsafeBufferPointer { scalePointer in
                        angles.withUnsafeBufferPointer { anglesPointer in
                            color.withUnsafeBufferPointer { colorPointer in
                                mwx_scene_quickjs_domain_update_layer_runtime_fields(
                                    handle, UInt32(index), scalePointer.baseAddress,
                                    anglesPointer.baseAddress,
                                    layerBool(
                                        layerID: layer.id, field: .visibility,
                                        authored: layer.visible ?? true,
                                        snapshot: snapshot
                                    ) ? 1 : 0,
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
            if let video = videoSnapshots[layer.id] {
                let videoResult = mwx_scene_quickjs_domain_update_layer_video_fields(
                    handle,
                    UInt32(index),
                    1,
                    video.duration,
                    video.rate,
                    video.loop ? 1 : 0,
                    video.currentTime,
                    video.isPlaying ? 1 : 0,
                    video.endedGeneration,
                    &diagnostic,
                    diagnostic.count
                )
                guard videoResult == MWX_SCENE_QUICKJS_OK else {
                    throw layerSnapshotFailure(
                        videoResult,
                        diagnostic: diagnostic
                    )
                }
            }
        }
    }

    private func layerVector3(
        layerID: Int,
        field: SceneDynamicLayerField,
        authored: [Float]?,
        fallback: [Double],
        snapshot: SceneDynamicSnapshot
    ) -> [Double] {
        let value = vector3(
            target: .layer(layerID: layerID, field: field),
            authored: authored,
            fallback: fallback,
            snapshot: snapshot
        )
        guard field == .angles else { return value }
        return value.map(SceneScriptAngleUnits.degrees)
    }

    private func vector3(
        target: SceneDynamicTarget,
        authored: [Float]?,
        fallback: [Double],
        snapshot: SceneDynamicSnapshot
    ) -> [Double] {
        if let resolved = snapshot[target],
           case let .vector3(x, y, z) = resolved.value,
           x.isFinite, y.isFinite, z.isFinite {
            return [x, y, z]
        }
        let values = authored?.map(Double.init) ?? fallback
        return (0..<3).map { index in
            index < values.count ? values[index] : fallback[index]
        }
    }

    private func layerBool(
        layerID: Int,
        field: SceneDynamicLayerField,
        authored: Bool,
        snapshot: SceneDynamicSnapshot
    ) -> Bool {
        guard let resolved = snapshot[.layer(layerID: layerID, field: field)],
              case let .bool(value) = resolved.value else { return authored }
        return value
    }
}
