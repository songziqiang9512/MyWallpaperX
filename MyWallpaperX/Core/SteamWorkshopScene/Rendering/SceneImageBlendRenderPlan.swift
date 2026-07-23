import Foundation

nonisolated struct SceneImageBlendRenderPlan {
    nonisolated struct Operation {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let multiply: Float
        let alphaMultiply: Float
        let writesAlpha: Bool
        let textureSelection: SceneFrameTextureSelection
        let usesAuthoredInitialAlpha: Bool
    }

    let operationsByConsumerLayerID: [Int: Operation]

    nonisolated var executedUserPropertyKeys: Set<String> {
        operationsByConsumerLayerID.values.reduce(into: Set<String>()) { keys, operation in
            for case let .userProperty(key) in operation.textureSelection.candidates {
                keys.insert(key)
            }
        }
    }

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
                    layersByID: layersByID,
                    texturePropertyKeys: Set(descriptor.texturePropertyKeys)
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
                "image blend consumer \(operation.consumerLayerID): provider=\(operation.providerLayerID) source=\(operation.textureSelection.candidates.map(\.reportToken).joined(separator: " -> ")) mode=normal alphaSource=\(operation.usesAuthoredInitialAlpha ? "authored-initial" : "static") writeAlpha=\(operation.writesAlpha)"
            )
        }
        return lines
    }

    private nonisolated static func operation(
        consumer: SceneRenderDescriptor.Layer,
        effect: SceneRenderDescriptor.EffectDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        texturePropertyKeys: Set<String>
    ) -> Operation? {
        guard effect.visible != false,
              effect.file.localizedLowercase == "effects/blend/effect.json",
              effect.passes.count == 1,
              let pass = effect.passes.first,
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
                default: 1,
                allowsAuthoredInitialValue: hasTexturePropertyInput(
                    pass,
                    texturePropertyKeys: texturePropertyKeys
                )
              ),
              let provider = layersByID[reference.providerLayerID],
              consumer.dependencyLayerIDs.contains(provider.id),
              provider.contentKind == "image",
              provider.imagePath != nil,
              hasNoUtilityLayer(provider),
              provider.effects.isEmpty,
              provider.childLayerIDs.isEmpty,
              provider.dependencyLayerIDs.isEmpty,
              let textureSelection = textureSelection(
                  pass: pass,
                  fallbackLayerID: provider.id,
                  texturePropertyKeys: texturePropertyKeys
              ) else {
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
            writesAlpha: combo("WRITEALPHA", in: pass) == 1,
            textureSelection: textureSelection,
            usesAuthoredInitialAlpha: usesAuthoredInitialValue("alpha", in: pass)
        )
    }

    private nonisolated static func hasTexturePropertyInput(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        texturePropertyKeys: Set<String>
    ) -> Bool {
        pass.userTextureInputs.enumerated().contains { index, input in
            index == 1
                && input?.kind == .property
                && input.map { texturePropertyKeys.contains($0.value) } == true
        }
    }

    private nonisolated static func textureSelection(
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        fallbackLayerID: Int,
        texturePropertyKeys: Set<String>
    ) -> SceneFrameTextureSelection? {
        let inputs = pass.userTextureInputs.enumerated().compactMap { index, input in
            input.map { (index, $0) }
        }
        let fallback = SceneFrameTextureIdentity.layerSource(fallbackLayerID)
        guard !inputs.isEmpty else {
            return SceneFrameTextureSelection(candidates: [fallback])
        }
        guard inputs.count == 1,
              let input = inputs.first,
              input.0 == 1,
              input.1.kind == .property,
              texturePropertyKeys.contains(input.1.value) else {
            return nil
        }
        return SceneFrameTextureSelection(candidates: [
            .userProperty(input.1.value),
            fallback,
        ])
    }

    private nonisolated static func staticNumber(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        range: ClosedRange<Float>,
        default defaultValue: Float? = nil,
        allowsAuthoredInitialValue: Bool = false
    ) -> Float? {
        guard let value = pass.constantShaderValues.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value else {
            return defaultValue
        }
        let valueKind = value.valueKind.localizedLowercase
        guard value.userBinding == nil,
              valueKind == "number" || (allowsAuthoredInitialValue && valueKind == "binding"),
              let components = value.components, components.count == 1,
              let raw = components.first, raw.isFinite else {
            return nil
        }
        let result = Float(raw)
        return range.contains(result) ? result : nil
    }

    private nonisolated static func usesAuthoredInitialValue(
        _ key: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        pass.constantShaderValues.first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value.valueKind.localizedLowercase == "binding"
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
