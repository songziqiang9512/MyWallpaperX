import Foundation

nonisolated struct SceneImageBlendRenderPlan {
    nonisolated struct Operation {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let multiply: Float
        let alphaMultiply: Float
        let writesAlpha: Bool
    }

    let operationsByConsumerLayerID: [Int: Operation]

    nonisolated init(
        descriptor: SceneRenderDescriptor,
        visibleLayerIDs: Set<Int>
    ) {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        var operations: [Int: Operation] = [:]
        for layer in descriptor.layers where visibleLayerIDs.contains(layer.id) {
            let candidates = layer.effects.compactMap { effect in
                Self.operation(
                    consumer: layer,
                    effect: effect,
                    layersByID: layersByID
                )
            }
            if candidates.count == 1 {
                operations[layer.id] = candidates[0]
            }
        }
        self.operationsByConsumerLayerID = operations
    }

    nonisolated func reportLines() -> [String] {
        var lines = ["imageBlendPlannedCount: \(operationsByConsumerLayerID.count)"]
        for operation in operationsByConsumerLayerID.values.sorted(by: {
            $0.consumerLayerID < $1.consumerLayerID
        }) {
            lines.append(
                "image blend consumer \(operation.consumerLayerID): provider=\(operation.providerLayerID) mode=normal writeAlpha=\(operation.writesAlpha)"
            )
        }
        return lines
    }

    private nonisolated static func operation(
        consumer: SceneRenderDescriptor.Layer,
        effect: SceneRenderDescriptor.EffectDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> Operation? {
        guard effect.visible != false,
              effect.file.localizedLowercase == "effects/blend/effect.json",
              effect.passes.count == 1,
              let pass = effect.passes.first,
              pass.userTextureInputs.allSatisfy({ $0 == nil }),
              pass.textureSlots.indices.contains(1),
              let reference = SceneNamedTextureReference.parse(pass.textureSlots[1]),
              reference.variant == .primary,
              combo("BLENDMODE", in: pass) == 0,
              combo("TRANSFORMUV", in: pass) ?? 0 == 0,
              combo("NUMBLENDTEXTURES", in: pass) ?? 1 == 1,
              combo("OPACITYMASK", in: pass) ?? 0 == 0,
              pass.constantShaderValues.keys.allSatisfy({
                  $0.caseInsensitiveCompare("multiply") == .orderedSame
                      || $0.caseInsensitiveCompare("alpha") == .orderedSame
                      || $0.caseInsensitiveCompare("blendangle") == .orderedSame
                      || $0.caseInsensitiveCompare("blendoffset") == .orderedSame
                      || $0.caseInsensitiveCompare("blendscale") == .orderedSame
              }),
              supportsNeutralTransformConstants(in: pass),
              let multiply = staticNumber("multiply", in: pass, range: 0...1),
              let alphaMultiply = staticNumber(
                "alpha",
                in: pass,
                range: 0...1,
                default: 1
              ),
              let provider = layersByID[reference.providerLayerID],
              consumer.dependencyLayerIDs.contains(provider.id),
              provider.contentKind == "image",
              provider.imagePath != nil,
              hasNoUtilityLayer(provider),
              provider.effects.isEmpty,
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty else {
            return nil
        }
        return Operation(
            consumerLayerID: consumer.id,
            providerLayerID: provider.id,
            slot: SceneEffectPassSlot(
                effectID: effect.id,
                passIndex: pass.passIndex,
                slotIndex: 1
            ),
            multiply: multiply,
            alphaMultiply: alphaMultiply,
            writesAlpha: combo("WRITEALPHA", in: pass) == 1
        )
    }

    private nonisolated static func staticNumber(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        range: ClosedRange<Float>,
        default defaultValue: Float? = nil
    ) -> Float? {
        guard let value = pass.constantShaderValues.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value else {
            return defaultValue
        }
        guard value.valueKind == "number", value.userBinding == nil,
              let components = value.components, components.count == 1,
              let raw = components.first, raw.isFinite else {
            return nil
        }
        let result = Float(raw)
        return range.contains(result) ? result : nil
    }

    private nonisolated static func supportsNeutralTransformConstants(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        guard staticNumber(
            "blendangle",
            in: pass,
            range: 0...0,
            default: 0
        ) != nil, staticNumber(
            "blendscale",
            in: pass,
            range: 1...1,
            default: 1
        ) != nil else {
            return false
        }
        guard let offset = pass.constantShaderValues.first(where: {
            $0.key.caseInsensitiveCompare("blendoffset") == .orderedSame
        })?.value else {
            return true
        }
        guard offset.valueKind == "vector", offset.userBinding == nil,
              let components = offset.components, components.count == 2 else {
            return false
        }
        return components.allSatisfy { $0.isFinite && abs($0) < 0.000_001 }
    }

    private nonisolated static func combo(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    private nonisolated static func hasNoUtilityLayer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if case nil = layer.utilityLayer { return true }
        return false
    }
}
