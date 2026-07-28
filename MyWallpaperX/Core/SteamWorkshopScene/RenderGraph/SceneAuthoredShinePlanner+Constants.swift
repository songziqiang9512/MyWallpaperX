import Foundation
import simd

extension SceneAuthoredShinePlanner {
    nonisolated struct DownsampleConstants {
        let threshold: Float
        let noiseAmount: Float
        let noiseScale: Float
        let noiseSpeed: Float
    }

    nonisolated struct CastConstants {
        let direction: Float
        let speed: Float
        let length: Float
        let intensity: Float
        let color: SIMD3<Float>
    }

    nonisolated struct EffectResources {
        let maskPath: String?
        let noisePath: String
    }

    nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "shine",
              definition.name == "ui_editor_effect_shine_title",
              definition.description == "ui_editor_effect_shine_description",
              definition.group == "enhance",
              definition.performance == "expensive",
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.count == 2,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 5,
              definition.dependencies.map(normalized) == expectedDependencies
        else {
            return false
        }
        return true
    }

    nonisolated static func validMaterial(
        _ material: SceneResolvedMaterialNode,
        ordinal: Int,
        bindings: [(Int, String, Graph.TextureIdentity)]
    ) -> Bool {
        let shaders = [
            "effects/shine_downsample2",
            "effects/shine_cast",
            "effects/shine_gaussian",
            "effects/shine_gaussian",
            "effects/shine_combine",
        ]
        guard normalized(material.shaderPath) == shaders[ordinal],
              material.renderState.blending?.lowercased() == "normal",
              material.renderState.depthTest?.lowercased() == "disabled",
              material.renderState.depthWrite?.lowercased() == "disabled",
              material.renderState.cullMode?.lowercased() == "nocull",
              validCombos(material.combos, ordinal: ordinal)
        else {
            return false
        }

        let expectedBySlot = Dictionary(uniqueKeysWithValues: bindings.map { ($0.0, $0.2) })
        for index in material.textureSlots.indices {
            if let expected = expectedBySlot[index] {
                guard let slot = material.textureSlots[index],
                      slot.candidates.count == 1,
                      slot.provenance == .explicitBinding,
                      case let .graph(actual) = slot.source,
                      actual == expected
                else {
                    return false
                }
                continue
            }
            guard let slot = material.textureSlots[index] else { continue }
            guard ordinal == 0, [1, 2].contains(index),
                  slot.provenance == .instance,
                  case let .asset(assetPath) = slot.source
            else {
                return false
            }
            if index == 2 {
                guard normalized(assetPath) == noiseAssetPath else { return false }
            } else if assetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private nonisolated static func validCombos(
        _ authored: [String: Int],
        ordinal: Int
    ) -> Bool {
        guard let combos = normalizedCombos(authored) else { return false }
        switch ordinal {
        case 0:
            return combos.keys.allSatisfy { ["NOISE", "MASK"].contains($0) }
                && combos["NOISE", default: 1] == 1
                && [0, 1].contains(combos["MASK", default: 0])
        case 1:
            return combos.keys.allSatisfy { ["EDGES", "SAMPLES"].contains($0) }
                && (2 ... 5).contains(combos["EDGES", default: 4])
                && (0 ... 4).contains(combos["SAMPLES", default: 1])
        case 2, 3:
            return combos.keys.allSatisfy { ["KERNEL", "VERTICAL"].contains($0) }
                && (0 ... 2).contains(combos["KERNEL", default: 0])
                && combos["VERTICAL", default: 0] == (ordinal == 3 ? 1 : 0)
        case 4:
            return combos.keys.allSatisfy { ["BLENDMODE", "COPYBG"].contains($0) }
                && combos["COPYBG", default: 0] == 0
                && (0 ... SceneBlendModeShaderSource.maximumMode)
                .contains(combos["BLENDMODE", default: defaultBlendMode])
        default:
            return false
        }
    }

    nonisolated static func downsampleConstants(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> DownsampleConstants? {
        guard let values = staticScalars(
            constants,
            allowed: [
                "raythreshold": (0 ... 1, 0.5),
                "noiseamount": (0.01 ... 1, 0.4),
                "noisescale": (0.01 ... 10, 3),
                "noisespeed": (0.01 ... 1, 0.15),
            ]
        ) else {
            return nil
        }
        return DownsampleConstants(
            threshold: values["raythreshold"]!,
            noiseAmount: values["noiseamount"]!,
            noiseScale: values["noisescale"]!,
            noiseSpeed: values["noisespeed"]!
        )
    }

    nonisolated static func castConstants(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> CastConstants? {
        var scalars: [String: SceneDocument.ShaderValue] = [:]
        var color = SIMD3<Float>(repeating: 1)
        for (key, value) in constants {
            if key.lowercased() == "color" {
                guard let components = staticVector(value, count: 3, range: 0 ... 1) else {
                    return nil
                }
                color = SIMD3(components[0], components[1], components[2])
            } else if scalars.updateValue(value, forKey: key.lowercased()) != nil {
                return nil
            }
        }
        guard let values = staticScalars(
            scalars,
            allowed: [
                "direction": (-Double.pi * 2 ... Double.pi * 2, 0),
                "speed": (-1 ... 1, 0),
                "raylength": (0.01 ... 1, 0.1),
                "rayintensity": (0.01 ... 2, 1),
            ]
        ) else {
            return nil
        }
        return CastConstants(
            direction: values["direction"]!,
            speed: values["speed"]!,
            length: values["raylength"]!,
            intensity: values["rayintensity"]!,
            color: color
        )
    }

    nonisolated static func blurScale(
        _ constants: [String: SceneDocument.ShaderValue]
    ) -> SIMD2<Float>? {
        if constants.isEmpty { return SIMD2(repeating: 1) }
        guard constants.count == 1,
              let value = constants.first(where: { $0.key.lowercased() == "scale" })?.value,
              let components = staticVector(value, count: 2, range: 0.01 ... 2)
        else {
            return nil
        }
        return SIMD2(components[0], components[1])
    }

    nonisolated static func castEdgeCount(_ authored: [String: Int]) -> Int? {
        guard let combos = normalizedCombos(authored) else { return nil }
        let value = combos["EDGES", default: 4]
        return (2 ... 5).contains(value) ? value : nil
    }

    nonisolated static func castSampleCount(_ authored: [String: Int]) -> Int? {
        guard let combos = normalizedCombos(authored) else { return nil }
        return [4, 8, 15, 30, 50][safe: combos["SAMPLES", default: 1]]
    }

    nonisolated static func gaussianKernelRadius(
        _ horizontal: [String: Int],
        vertical: [String: Int]
    ) -> Int? {
        guard let x = normalizedCombos(horizontal),
              let y = normalizedCombos(vertical)
        else {
            return nil
        }
        let xKernel = x["KERNEL", default: 0]
        let yKernel = y["KERNEL", default: 0]
        guard xKernel == yKernel else { return nil }
        return [6, 3, 1][safe: xKernel]
    }

    nonisolated static func combineBlendMode(_ authored: [String: Int]) -> Int? {
        guard let combos = normalizedCombos(authored) else { return nil }
        let mode = combos["BLENDMODE", default: defaultBlendMode]
        return (0 ... SceneBlendModeShaderSource.maximumMode).contains(mode) ? mode : nil
    }

    nonisolated static func effectResources(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> EffectResources? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              descriptor.visible != false,
              descriptor.passes.count == 5
        else {
            return nil
        }
        for (index, pass) in descriptor.passes.enumerated() {
            guard pass.userTextureInputs.isEmpty else { return nil }
            if index == 0 { continue }
            guard pass.texturePaths.isEmpty, pass.textureSlots.isEmpty else { return nil }
        }

        let pass = descriptor.passes[0]
        if pass.texturePaths.isEmpty && pass.textureSlots.isEmpty {
            return EffectResources(maskPath: nil, noisePath: noiseAssetPath)
        }
        guard (2 ... 3).contains(pass.textureSlots.count),
              pass.textureSlots[0] == nil
        else {
            return nil
        }
        let mask = pass.textureSlots[1]
        let authoredNoise = pass.textureSlots.count == 3 ? pass.textureSlots[2] : nil
        if let mask, mask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        if let authoredNoise, normalized(authoredNoise) != noiseAssetPath {
            return nil
        }
        let expectedPaths = [mask, authoredNoise].compactMap { $0 }
        guard pass.texturePaths == expectedPaths else { return nil }
        return EffectResources(
            maskPath: mask,
            noisePath: authoredNoise ?? noiseAssetPath
        )
    }

    private nonisolated static func staticScalars(
        _ constants: [String: SceneDocument.ShaderValue],
        allowed: [String: (ClosedRange<Double>, Float)]
    ) -> [String: Float]? {
        var values: [String: Float] = [:]
        for (key, value) in constants {
            let lower = key.lowercased()
            guard let (range, _) = allowed[lower],
                  values[lower] == nil,
                  let components = staticVector(value, count: 1, range: range)
            else {
                return nil
            }
            values[lower] = components[0]
        }
        for (key, (_, fallback)) in allowed where values[key] == nil {
            values[key] = fallback
        }
        return values
    }

    private nonisolated static func staticVector(
        _ value: SceneDocument.ShaderValue,
        count: Int,
        range: ClosedRange<Double>
    ) -> [Float]? {
        guard value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.valueKind.lowercased() == (count == 1 ? "number" : "vector"),
              let components = value.components,
              components.count == count
        else {
            return nil
        }
        let floatRange = ClosedRange(
            uncheckedBounds: (Float(range.lowerBound), Float(range.upperBound))
        )
        return components.compactMap { component in
            let value = Float(component)
            return value.isFinite && floatRange.contains(value) ? value : nil
        }.count == count ? components.map(Float.init) : nil
    }

    private nonisolated static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        return result
    }

    private nonisolated static let expectedDependencies = [
        "materials/effects/shine_downsample2.json",
        "materials/effects/shine_cast.json",
        "materials/effects/shine_gaussian_x.json",
        "materials/effects/shine_gaussian_y.json",
        "materials/effects/shine_combine.json",
        "shaders/effects/shine_downsample2.frag",
        "shaders/effects/shine_downsample2.vert",
        "shaders/effects/shine_cast.frag",
        "shaders/effects/shine_cast.vert",
        "shaders/effects/shine_gaussian.frag",
        "shaders/effects/shine_gaussian.vert",
        "shaders/effects/shine_combine.frag",
        "shaders/effects/shine_combine.vert",
    ]

    nonisolated static let defaultBlendMode = 9
    nonisolated static let noiseAssetPath = "util/clouds_256"
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
