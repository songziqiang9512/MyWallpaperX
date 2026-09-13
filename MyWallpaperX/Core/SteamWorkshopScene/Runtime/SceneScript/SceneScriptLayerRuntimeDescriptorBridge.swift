import Foundation
import simd

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
        videoSnapshots: [Int: SceneScriptVideoPlaybackSnapshot] = [:],
        textureAnimationSnapshots: [
            Int: SceneTextureAnimationSnapshot
        ] = [:],
        destroyedAuthoredLayerIDs: Set<Int> = [],
        runtimeFieldLayerIDs: Set<Int>? = nil,
        diagnostic: inout [CChar]
    ) throws {
        for (index, layer) in descriptor.layers.enumerated() {
            if let runtimeFieldLayerIDs,
               !runtimeFieldLayerIDs.contains(layer.id),
               !destroyedAuthoredLayerIDs.contains(layer.id),
               videoSnapshots[layer.id] == nil,
               textureAnimationSnapshots[layer.id] == nil {
                let result = mwx_scene_quickjs_domain_reuse_layer_runtime_fields(
                    handle,
                    UInt32(index),
                    &diagnostic,
                    diagnostic.count
                )
                guard result == MWX_SCENE_QUICKJS_OK else {
                    throw layerSnapshotFailure(result, diagnostic: diagnostic)
                }
                continue
            }
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
            let font: String
            if let resolved = snapshot[
                .text(layerID: layer.id, field: .font)
            ], case let .string(value) = resolved.value {
                font = value
            } else {
                font = layer.textStyle?.fontPath ?? ""
            }
            let colorTarget: SceneDynamicTarget = layer.contentKind == "text"
                ? .text(layerID: layer.id, field: .color)
                : .layer(layerID: layer.id, field: .color)
            let color = vector3(
                target: colorTarget,
                authored: layer.textStyle?.colorRGB ?? layer.colorRGB,
                fallback: [1, 1, 1], snapshot: snapshot
            )
            let result = text.withCString { textPointer in
                font.withCString { fontPointer in
                    scale.withUnsafeBufferPointer { scalePointer in
                        angles.withUnsafeBufferPointer { anglesPointer in
                            color.withUnsafeBufferPointer { colorPointer in
                                mwx_scene_quickjs_domain_update_layer_runtime_fields(
                                    handle, UInt32(index), scalePointer.baseAddress,
                                    anglesPointer.baseAddress,
                                    destroyedAuthoredLayerIDs.contains(layer.id)
                                        ? 1 : 0,
                                    layerBool(
                                        layerID: layer.id, field: .visibility,
                                        authored: layer.visible ?? true,
                                        snapshot: snapshot
                                    ) ? 1 : 0,
                                    {
                                        if let resolved = snapshot[.layer(layerID: layer.id, field: .alpha)],
                                           case let .scalar(value) = resolved.value, value.isFinite {
                                            return min(max(value, 0), 1)
                                        }
                                        return layer.alpha ?? 1
                                    }(),
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
            if let animation = textureAnimationSnapshots[layer.id] {
                let animationResult =
                    mwx_scene_quickjs_domain_update_layer_texture_animation_fields(
                        handle,
                        UInt32(index),
                        1,
                        UInt32(animation.frameCount),
                        animation.duration,
                        animation.rate,
                        animation.currentFrame,
                        animation.isPlaying ? 1 : 0,
                        animation.sharedRate,
                        animation.sharedCurrentFrame,
                        animation.sharedIsPlaying ? 1 : 0,
                        &diagnostic,
                        diagnostic.count
                    )
                guard animationResult == MWX_SCENE_QUICKJS_OK else {
                    throw layerSnapshotFailure(
                        animationResult,
                        diagnostic: diagnostic
                    )
                }
            }
        }
    }

    func publishLayerWorldTransforms(
        _ worldFrames: [Int: simd_float4x4],
        descriptor: SceneRenderDescriptor,
        diagnostic: inout [CChar]
    ) throws {
        for (index, layer) in descriptor.layers.enumerated() {
            guard let worldFrame = worldFrames[layer.id] else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer world transform is missing"
                )
            }
            let values = SceneScriptLayerWorldTransformProjection
                .columnMajorValues(worldFrame)
            guard values.count == 16, values.allSatisfy(\.isFinite) else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer world transform is non-finite"
                )
            }
            let result = values.withUnsafeBufferPointer { pointer in
                mwx_scene_quickjs_domain_update_layer_world_transform(
                    handle,
                    UInt32(index),
                    pointer.baseAddress,
                    &diagnostic,
                    diagnostic.count
                )
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw layerSnapshotFailure(result, diagnostic: diagnostic)
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
