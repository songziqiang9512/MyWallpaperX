import Foundation

/// Typed definitions and value projection for the existing topology transaction.
nonisolated extension SceneScriptDynamicLayerRuntime {
    static func staticCameraDefinitions(
        for camera: SceneRenderDescriptor.CameraDescriptor
    ) -> [SceneDynamicTargetDefinition] {
        let native = camera.orthoWidth == nil && camera.orthoHeight == nil
        let vectors: [(SceneDynamicCameraField, [Float])] = [
            (.eye, native ? camera.eye : [0, 0, 0]),
            (.center, native ? camera.center : [0, 0, -1]),
            (.up, native ? camera.up : [0, 1, 0])]
        var definitions = vectors.compactMap { field, value -> SceneDynamicTargetDefinition? in
            guard value.count == 3 else { return nil }
            return .init(target: .camera(field), valueType: .vector3,
                authoredValue: .vector3(Double(value[0]), Double(value[1]), Double(value[2])))
        }
        definitions.append(.init(target: .camera(.zoom), valueType: .scalar, authoredValue: .scalar(1)))
        return definitions
    }

    /// The ABI bridge has typed the provided members. Keep source ownership in
    /// the effects bundle; camera targets never acquire a synthetic layer ID.
    static func applyCameraCommand(
        _ command: SceneScriptCameraCommand,
        to values: inout [SceneDynamicTarget: SceneDynamicValue]
    ) {
        if command.fields.contains(.eye) {
            values[.camera(.eye)] = .vector3(command.eye.x, command.eye.y, command.eye.z)
        }
        if command.fields.contains(.center) {
            values[.camera(.center)] = .vector3(command.center.x, command.center.y, command.center.z)
        }
        if command.fields.contains(.up) {
            values[.camera(.up)] = .vector3(command.up.x, command.up.y, command.up.z)
        }
        if command.fields.contains(.zoom) { values[.camera(.zoom)] = .scalar(command.zoom) }
    }

    static func layerID(
        for target: SceneDynamicTarget, cameraOriginInputLayerID: Int? = nil
    ) -> Int? {
        switch target {
        case let .layer(layerID, _), let .text(layerID, _), let .effectVisibility(layerID, _),
             let .effectConstant(layerID, _, _, _), let .materialConstant(layerID, _, _, _),
             let .particle(layerID, _), let .scriptInstanceProperty(layerID, _):
            layerID
        case .camera(.origin):
            cameraOriginInputLayerID
        default:
            nil
        }
    }

    static func authoredTransformTarget(
        layerID: Int, field: SceneDynamicLayerField, cameraOriginInputLayerID: Int?
    ) -> SceneDynamicTarget {
        field == .origin && layerID == cameraOriginInputLayerID
            ? .camera(.origin) : .layer(layerID: layerID, field: field)
    }

    /// Multiple authored owners may intentionally publish the same field and
    /// value (for example, duplicated controller layers in one authored
    /// scene). Such writes are idempotent and preserve authored order. A later
    /// owner that disagrees remains a hard conflict because accepting it would
    /// make the final value depend on an implicit last-writer policy.
    static func authoredValues(
        _ mutation: SceneScriptLayerMutation, cameraOriginInputLayerID: Int? = nil
    ) -> [(SceneDynamicTarget, SceneDynamicValue)] {
        guard !mutation.isDynamic, mutation.kind == .upsert else { return [] }
        var values: [(SceneDynamicTarget, SceneDynamicValue)] = []
        if mutation.fields.contains(.alpha) {
            values.append((.layer(layerID: mutation.layerID, field: .alpha), .scalar(mutation.alpha)))
        }
        if mutation.fields.contains(.particleAlpha) {
            values.append((.particle(layerID: mutation.layerID, field: .alpha), .scalar(mutation.particleAlpha)))
        }
        if mutation.fields.contains(.color) {
            values.append((.layer(layerID: mutation.layerID, field: .color),
                .vector3(mutation.color.x, mutation.color.y, mutation.color.z)))
        }
        if mutation.fields.contains(.origin) {
            values.append((
                authoredTransformTarget(layerID: mutation.layerID, field: .origin,
                    cameraOriginInputLayerID: cameraOriginInputLayerID),
                .vector3(mutation.origin.x, mutation.origin.y, mutation.origin.z)
            ))
        }
        if mutation.fields.contains(.scale) {
            values.append((
                .layer(layerID: mutation.layerID, field: .scale),
                .vector3(mutation.scale.x, mutation.scale.y, mutation.scale.z)
            ))
        }
        if mutation.fields.contains(.angles) {
            values.append((
                .layer(layerID: mutation.layerID, field: .angles),
                .vector3(mutation.angles.x, mutation.angles.y, mutation.angles.z)
            ))
        }
        if mutation.fields.contains(.perspective), let perspective = mutation.perspective {
            values.append((.layer(layerID: mutation.layerID, field: .perspective), .bool(perspective)))
        }
        if mutation.fields.contains(.solid) {
            values.append((.layer(layerID: mutation.layerID, field: .solid), .bool(mutation.solid)))
        }
        if mutation.fields.contains(.visibility) {
            values.append((
                .layer(layerID: mutation.layerID, field: .visibility),
                .bool(mutation.visible)
            ))
        }
        if mutation.fields.contains(.text) {
            values.append((
                .text(layerID: mutation.layerID, field: .content),
                .string(mutation.text)
            ))
        }
        if mutation.fields.contains(.font) {
            values.append((
                .text(layerID: mutation.layerID, field: .font),
                .string(mutation.font)
            ))
        }
        if mutation.fields.contains(.pointSize) {
            values.append((
                .text(layerID: mutation.layerID, field: .pointSize),
                .scalar(mutation.pointSize)
            ))
        }
        values += mutation.effectVisibilities.sorted { $0.key < $1.key }.map {
            (.effectVisibility(layerID: mutation.layerID, effectIndex: $0.key), .bool($0.value))
        }
        return values
    }

    /// Dynamic upserts carry their complete frame value record, but that does
    /// not make them a new graph topology. Only identity/order or the
    /// structural resource lane or immutable creation size invalidates the renderer's prepared
    /// descriptor projection. Position, scale, angles, visibility, alpha,
    /// color, text, font and point size are applied to the cached projection per frame.
    static func dynamicTopologyChanged(
        currentOrder: [Int],
        currentLayers: [Int: SceneRenderDescriptor.Layer],
        candidateOrder: [Int],
        candidateLayers: [Int: SceneRenderDescriptor.Layer]
    ) -> Bool {
        guard currentOrder == candidateOrder,
              currentLayers.count == candidateLayers.count,
              currentLayers.keys == candidateLayers.keys else {
            return true
        }
        for layerID in currentLayers.keys {
            guard let current = currentLayers[layerID],
                  let candidate = candidateLayers[layerID],
                  current.id == candidate.id,
                  current.contentKind == candidate.contentKind,
                  current.imagePath == candidate.imagePath,
                  current.sizeWH == candidate.sizeWH else {
                return true
            }
        }
        return false
    }

    static func initialAuthoredDefinitions(
        for layer: SceneRenderDescriptor.Layer
    ) -> [SceneDynamicTargetDefinition] {
        [
            .layer(layerID: layer.id, field: .origin),
            .layer(layerID: layer.id, field: .scale),
            .layer(layerID: layer.id, field: .angles),
            .layer(layerID: layer.id, field: .visibility),
        ].compactMap { definition(for: $0, layer: layer) }
    }

    static func ensureDefinition(
        for target: SceneDynamicTarget,
        layer: SceneRenderDescriptor.Layer,
        cameraOriginInputLayerID: Int? = nil,
        order: inout [SceneDynamicTarget],
        definitions: inout [SceneDynamicTarget: SceneDynamicTargetDefinition]
    ) {
        guard definitions[target] == nil,
              let definition = definition(for: target, layer: layer,
                  cameraOriginInputLayerID: cameraOriginInputLayerID) else {
            return
        }
        definitions[target] = definition
        order.append(target)
    }

    static func definition(
        for target: SceneDynamicTarget,
        layer: SceneRenderDescriptor.Layer,
        cameraOriginInputLayerID: Int? = nil
    ) -> SceneDynamicTargetDefinition? {
        switch target {
        case let .particle(layerID, .alpha) where layerID == layer.id && layer.contentKind == "particle":
            .init(target: target, valueType: .scalar,
                  authoredValue: .scalar(layer.particleInstanceOverride?.alpha?.value?.scalarValue ?? 1))
        case let .effectVisibility(layerID, effectIndex)
            where layerID == layer.id && layer.effects.indices.contains(effectIndex):
            .init(target: target, valueType: .bool, authoredValue: .bool(layer.effects[effectIndex].visible ?? true))
        case let .layer(layerID, .alpha) where layerID == layer.id:
            .init(target: target, valueType: .scalar, authoredValue: .scalar(layer.alpha ?? 1))
        case let .layer(layerID, .color) where layerID == layer.id:
            .init(target: target, valueType: .vector3,
                  authoredValue: vector3(layer.colorRGB, fallback: [1, 1, 1]))
        case let .layer(layerID, .origin) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.originXYZ, fallback: [0, 0, 0])
            )
        case .camera(.origin) where layer.id == cameraOriginInputLayerID:
            .init(target: target, valueType: .vector3,
                  authoredValue: vector3(layer.originXYZ, fallback: [0, 0, 0]))
        case let .layer(layerID, .scale) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.scaleXYZ, fallback: [1, 1, 1])
            )
        case let .layer(layerID, .angles) where layerID == layer.id:
            .init(
                target: target, valueType: .vector3,
                authoredValue: vector3(layer.anglesXYZ, fallback: [0, 0, 0])
            )
        case let .layer(layerID, .perspective) where layerID == layer.id:
            .init(target: target, valueType: .bool, authoredValue: .bool(layer.usesPerspective ?? false))
        case let .layer(layerID, .solid) where layerID == layer.id:
            .init(target: target, valueType: .bool, authoredValue: .bool(layer.solid ?? true))
        case let .layer(layerID, .visibility) where layerID == layer.id:
            .init(
                target: target, valueType: .bool,
                authoredValue: .bool(layer.visible ?? true)
            )
        case let .text(layerID, .content)
            where layerID == layer.id && layer.contentKind == "text"
                && layer.textStyle != nil:
            .init(
                target: target, valueType: .string,
                authoredValue: .string(layer.text ?? "")
            )
        case let .text(layerID, .font)
            where layerID == layer.id && layer.contentKind == "text"
                && layer.textStyle != nil:
            .init(
                target: target, valueType: .string,
                authoredValue: .string(layer.textStyle?.fontPath ?? "")
            )
        case let .text(layerID, .color) where layerID == layer.id && layer.contentKind == "text":
            .init(target: target, valueType: .vector3,
                  authoredValue: vector3(layer.textStyle?.colorRGB, fallback: [1, 1, 1]))
        case let .text(layerID, .pointSize)
            where layerID == layer.id && layer.contentKind == "text"
                && layer.textStyle != nil:
            .init(
                target: target, valueType: .scalar,
                authoredValue: .scalar(Double(layer.textStyle?.pointSize ?? 32))
            )
        default:
            nil
        }
    }

    static func vector3(
        _ values: [Float]?,
        fallback: [Double]
    ) -> SceneDynamicValue {
        let resolved = values?.map(Double.init) ?? fallback
        let padded = (0..<3).map { index in
            index < resolved.count ? resolved[index] : fallback[index]
        }
        return .vector3(padded[0], padded[1], padded[2])
    }
}
