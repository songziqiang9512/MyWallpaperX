import Foundation
import simd

nonisolated struct SceneXRayRuntimePlan {
    let layerID: Int
    let effectIndex: Int
    let effectID: String
    let blendTexturePath: String
    let haloTexturePath: String?
    let opacityMaskPath: String?
    let blendPropertyKey: String?
    let haloPropertyKey: String?
    let size: Float
    let multiply: Float
    let blendUVScale: SIMD2<Float>
    let opacityUVScale: SIMD2<Float>
}

nonisolated enum SceneXRayRuntimeResolution {
    case identity
    case render(SceneXRayRuntimePlan)
    case unsupported
}

nonisolated enum SceneXRayRuntimePlanner {
    struct Declaration {
        let layerID: Int
        let effectIndex: Int
        let effectID: String
        let blendTexturePath: String
        let haloTexturePath: String?
        let opacityMaskPath: String?
        let blendPropertyKey: String?
        let haloPropertyKey: String?
        let fallbackVisible: Bool
        let fallbackSize: Float
        let fallbackMultiply: Float
    }

    static func declaration(
        for layer: SceneRenderDescriptor.Layer
    ) -> Declaration? {
        let candidates = layer.effects.enumerated().filter {
            normalized($0.element.file) == effectPath
        }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.element.passes.count == 1,
              let pass = candidate.element.passes.first,
              pass.passIndex == 0,
              validCombos(pass.combos),
              let paths = texturePaths(pass),
              let values = parameters(pass.constantShaderValues) else {
            return nil
        }
        return Declaration(
            layerID: layer.id,
            effectIndex: candidate.offset,
            effectID: candidate.element.id,
            blendTexturePath: paths.blend,
            haloTexturePath: paths.halo,
            opacityMaskPath: paths.opacity,
            blendPropertyKey: paths.blendProperty,
            haloPropertyKey: paths.haloProperty,
            fallbackVisible: candidate.element.visible != false,
            fallbackSize: values.size,
            fallbackMultiply: values.multiply
        )
    }

    static func plan(
        for layer: SceneRenderDescriptor.Layer,
        resources: SceneXRayEffectTextures?,
        snapshot: SceneDynamicSnapshot,
        pointerIsInside: Bool
    ) -> SceneXRayRuntimePlan? {
        guard let declaration = declaration(for: layer) else { return nil }
        if case .render(let plan) = resolve(
            declaration: declaration,
            resources: resources,
            snapshot: snapshot,
            pointerIsInside: pointerIsInside
        ) {
            return plan
        }
        return nil
    }

    static func resolve(
        declaration: Declaration,
        resources: SceneXRayEffectTextures?,
        snapshot: SceneDynamicSnapshot,
        pointerIsInside: Bool
    ) -> SceneXRayRuntimeResolution {
        guard pointerIsInside,
              resolvedVisibility(declaration, snapshot: snapshot),
              let size = resolvedSize(declaration, snapshot: snapshot),
              let multiply = resolvedMultiply(declaration, snapshot: snapshot),
              size >= 0.001 else {
            return .identity
        }
        guard let resources, resources.matches(declaration) else {
            return .unsupported
        }
        return .render(SceneXRayRuntimePlan(
            layerID: declaration.layerID,
            effectIndex: declaration.effectIndex,
            effectID: declaration.effectID,
            blendTexturePath: declaration.blendTexturePath,
            haloTexturePath: declaration.haloTexturePath,
            opacityMaskPath: declaration.opacityMaskPath,
            blendPropertyKey: declaration.blendPropertyKey,
            haloPropertyKey: declaration.haloPropertyKey,
            size: size,
            multiply: multiply,
            blendUVScale: resources.blendUVScale,
            opacityUVScale: resources.opacityUVScale
        ))
    }

    static func liveConsumerTargets(
        for layer: SceneRenderDescriptor.Layer
    ) -> Set<SceneDynamicTarget> {
        guard let declaration = declaration(for: layer) else { return [] }
        return liveConsumerTargets(for: declaration)
    }

    static func liveConsumerTargets(
        for declaration: Declaration
    ) -> Set<SceneDynamicTarget> {
        return [
            visibilityTarget(declaration),
            sizeTarget(declaration),
            multiplyTarget(declaration),
        ]
    }

    private static func resolvedVisibility(
        _ declaration: Declaration,
        snapshot: SceneDynamicSnapshot
    ) -> Bool {
        guard case .bool(let value) = snapshot[visibilityTarget(declaration)]?.value else {
            return declaration.fallbackVisible
        }
        return value
    }

    private static func resolvedSize(
        _ declaration: Declaration,
        snapshot: SceneDynamicSnapshot
    ) -> Float? {
        guard case .scalar(let value) = snapshot[sizeTarget(declaration)]?.value else {
            return declaration.fallbackSize
        }
        guard value.isFinite, (0...1).contains(value) else {
            return declaration.fallbackSize
        }
        return Float(value)
    }

    private static func resolvedMultiply(
        _ declaration: Declaration,
        snapshot: SceneDynamicSnapshot
    ) -> Float? {
        guard case .scalar(let value) = snapshot[multiplyTarget(declaration)]?.value else {
            return declaration.fallbackMultiply
        }
        guard value.isFinite, (0...10).contains(value) else {
            return declaration.fallbackMultiply
        }
        return Float(value)
    }

    private static func visibilityTarget(
        _ declaration: Declaration
    ) -> SceneDynamicTarget {
        .effectVisibility(
            layerID: declaration.layerID,
            effectIndex: declaration.effectIndex
        )
    }

    private static func sizeTarget(
        _ declaration: Declaration
    ) -> SceneDynamicTarget {
        .effectConstant(
            layerID: declaration.layerID,
            effectIndex: declaration.effectIndex,
            passIndex: 0,
            name: "size"
        )
    }

    private static func multiplyTarget(
        _ declaration: Declaration
    ) -> SceneDynamicTarget {
        .effectConstant(
            layerID: declaration.layerID,
            effectIndex: declaration.effectIndex,
            passIndex: 0,
            name: "multiply"
        )
    }

    private static func texturePaths(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> (
        blend: String,
        halo: String?,
        opacity: String?,
        blendProperty: String?,
        haloProperty: String?
    )? {
        guard (3...4).contains(pass.textureSlots.count),
              pass.textureSlots[0] == nil,
              let blend = pass.textureSlots[1],
              !blend.isEmpty else {
            return nil
        }
        let halo = pass.textureSlots[2]
        let opacity = pass.textureSlots.count == 4 ? pass.textureSlots[3] : nil
        let blendProperty = propertyKey(in: pass.userTextureInputs, slot: 1)
        let haloProperty = propertyKey(in: pass.userTextureInputs, slot: 2)
        guard halo?.isEmpty != true,
              opacity?.isEmpty != true,
              haloProperty == nil || halo != nil,
              validUserTextureInputs(pass.userTextureInputs),
              pass.texturePaths
                == [blend] + (halo.map { [$0] } ?? []) + (opacity.map { [$0] } ?? []) else {
            return nil
        }
        return (blend, halo, opacity, blendProperty, haloProperty)
    }

    private static func parameters(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> (size: Float, multiply: Float)? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        guard Set(values.keys) == Set(["size", "multiply"]),
              let size = scalar(values["size"], range: 0...1, allowsBinding: true),
              let multiply = scalar(
                  values["multiply"],
                  range: 0...10,
                  allowsBinding: true
              ) else {
            return nil
        }
        return (size, multiply)
    }

    private static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>,
        allowsBinding: Bool = false
    ) -> Float? {
        guard let value,
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              range.contains(component) else {
            return nil
        }
        if let binding = value.userBinding {
            guard allowsBinding,
                  value.valueKind.lowercased() == "binding",
                  !binding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
        } else {
            guard value.valueKind.lowercased() == "number" else { return nil }
        }
        return Float(component)
    }

    private static func validUserTextureInputs(
        _ inputs: [SceneEffectTextureInput?]
    ) -> Bool {
        inputs.enumerated().allSatisfy { index, input in
            guard let input else { return true }
            return (index == 1 || index == 2)
                && input.kind == .property
                && !input.value.isEmpty
        }
    }

    private static func propertyKey(
        in inputs: [SceneEffectTextureInput?],
        slot: Int
    ) -> String? {
        guard inputs.indices.contains(slot),
              let input = inputs[slot],
              input.kind == .property else {
            return nil
        }
        return input.value
    }

    private static func validCombos(_ authored: [String: Int]) -> Bool {
        authored.allSatisfy { key, value in
            switch key.uppercased() {
            case "BLENDMODE":
                value == 0
            case "OPACITYMASK":
                value == 0 || value == 1
            default:
                false
            }
        }
    }

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static let effectPath = "effects/xray/effect.json"
}
