import Foundation

/// Launch-immutable diffuse-lighting intent for built-in image materials.
/// Custom shader sources retain their existing frontend and output authority.
nonisolated struct SceneBaseMaterialLightingProfile: Equatable, Sendable {
    let lightingEnabled: Bool
    /// Absent only for the legacy implicit-shader diffuse admission.
    var scalarMaterial: SIMD2<Float>? = nil
    /// Strength and project world-space sampling distance.
    var reflection: SIMD2<Float>? = nil
    var surfaceEnabled: Bool { lightingEnabled || reflection != nil }
    enum TextureSource: Equatable, Sendable {
        case disabled, unsupported, invalid
        case asset(SceneAssetTextureIdentity)
    }
    let normalSource: TextureSource
    var mapSource: TextureSource = .disabled
    /// Bits match the authored component metadata, excluding reflection.
    var mapAllowedComponents: UInt32 = 0
    var mapRequiredComponents: UInt32 = 0
    enum Emission: Equatable, Sendable {
        case constant(SIMD4<Float>)
        case propertyBrightness(color: SIMD3<Float>, target: SceneDynamicTarget)
    }
    var emission: Emission? = nil
    var emissionPropertyTarget: SceneDynamicTarget? {
        guard case let .propertyBrightness(_, target) = emission else { return nil }
        return target
    }
    var mapAsset: SceneAssetTextureIdentity? {
        guard case let .asset(identity) = mapSource else { return nil }
        return identity
    }
    var normalAsset: SceneAssetTextureIdentity? {
        guard case let .asset(identity) = normalSource else { return nil }
        return identity
    }

    static let disabled = SceneBaseMaterialLightingProfile(
        lightingEnabled: false, normalSource: .disabled
    )
}

enum SceneBaseMaterialLightingProfileCompiler {
    /// Material-pass combos are the authored default; the layer instance can
    /// override them. Built-in generic-image references are material identities,
    /// not authored shader sources. Source-backed passes retain their frontend.
    static func profile(
        layer: SceneRenderDescriptor.Layer,
        materialInstance: SceneDocument.SceneLayerMaterialInstance?,
        materialPasses: [SceneRenderDescriptor.MaterialPassDescriptor],
        materialPropertyTargets: Set<SceneDynamicTarget>
    ) -> SceneBaseMaterialLightingProfile {
        guard layer.isImageRenderable,
              materialInstance?.isMalformed != true,
              materialPasses.count <= 1 else { return .disabled }
        let pass = materialPasses.first
        let isBuiltin = pass?.shaderPath.map(SceneBuiltinShaderIdentity.isImage) ?? true
        let lightingEnabled = isBuiltin
            && (materialInstance?.combos["LIGHTING"] ?? pass?.combos["LIGHTING"]) == 1
        let builtinSurface = SceneMaterialPropertyBindingCompiler.supportsBuiltinImage(
            layer: layer, instance: materialInstance, passes: materialPasses
        )
        let builtinLighting = builtinSurface && lightingEnabled
        // This slice owns only the declared default environment. Empty/null
        // instance slots inherit; they cannot erase an authored provider.
        let hasExplicitEnvironment = [materialInstance?.textureSlots, pass?.textureSlots]
            .compactMap { $0 }.contains { $0.indices.contains(3) && $0[3]?.isEmpty == false }
            || [materialInstance?.userTextureInputs, pass?.userTextureInputs]
                .compactMap { $0 }.contains { $0.indices.contains(3) && $0[3] != nil }
        var reflection: SIMD2<Float>?
        if builtinSurface, layer.puppetMeshPath == nil, !hasExplicitEnvironment,
           (materialInstance?.combos["REFLECTION"] ?? pass?.combos["REFLECTION"]) == 1,
           let pass,
           let strength = SceneMaterialPropertyBindingCompiler.staticComponents(
            "reflectivity", instance: materialInstance, pass: pass, count: 1, fallback: [1])?.first,
           let distance = SceneMaterialPropertyBindingCompiler.staticComponents(
            "reflectivitydistance", instance: materialInstance, pass: pass, count: 1, fallback: [4])?.first,
           strength > 0, distance >= 0, Float(strength).isFinite, Float(distance).isFinite {
            reflection = SIMD2(Float(strength), Float(distance))
        }
        // Fixed built-in slot 1 is the normal input. Null instance slots inherit
        // the material; an explicit NORMALMAP=0 disables that optional input.
        func slot(_ slots: [String?]) -> String? {
            guard slots.indices.contains(1), let value = slots[1],
                  !value.isEmpty else { return nil }
            return value
        }
        let input = materialInstance?.hasUserTextureOverride == true
            ? materialInstance?.userTextureInputs : pass?.userTextureInputs
        let hasUnsupportedProvider = input?.indices.contains(1) == true
            && input?[1] != nil
        let normalEnabled = (builtinLighting || reflection != nil)
            && (materialInstance?.combos["NORMALMAP"] ?? pass?.combos["NORMALMAP"]) != 0
        let normalSource: SceneBaseMaterialLightingProfile.TextureSource
        if !normalEnabled { normalSource = .disabled }
        else if hasUnsupportedProvider { normalSource = .unsupported }
        else if let path = slot(materialInstance?.textureSlots ?? []) ?? slot(pass?.textureSlots ?? []) {
            normalSource = SceneAssetTextureIdentity(virtualPath: path, purpose: .normal)
                .map { .asset($0) } ?? .invalid
        } else { normalSource = .disabled }
        var profile = SceneBaseMaterialLightingProfile(
            lightingEnabled: lightingEnabled, reflection: reflection, normalSource: normalSource
        )
        if builtinLighting || reflection != nil, let pass, let shader = pass.shaderPath {
            let tierFour = shader.lowercased() == "genericimage4"
            func scalar(_ key: String, default fallback: Double) -> Float {
                guard let value = SceneMaterialPropertyBindingCompiler.staticComponents(key, instance: materialInstance, pass: pass, count: 1, fallback: [fallback])?.first else {
                    NSLog("MWX SCENE: schema=base-material-scalar component=%@ fallback=tier-default reason=invalid-or-unresolved", key)
                    return Float(fallback)
                }
                return Float(min(1, max(0, value)))
            }
            profile.scalarMaterial = SIMD2(
                scalar("metallic", default: tierFour ? 0 : 0.5),
                scalar("roughness", default: tierFour ? 0.7 : 0.5)
            )
            func combo(_ key: String) -> Int? {
                materialInstance?.combos[key] ?? pass.combos[key]
            }
            for (key, bit) in [("METALLIC_MAP", UInt32(1)), ("ROUGHNESS_MAP", 2), ("REFLECTION_MAP", 4), ("EMISSIVE_MAP", 8)] {
                switch combo(key) {
                case nil: profile.mapAllowedComponents |= bit
                case 1:
                    profile.mapAllowedComponents |= bit
                    profile.mapRequiredComponents |= bit
                case 0: break
                default:
                    NSLog("MWX SCENE: schema=base-material-map component=%@ status=unsupported fallback=component-disabled", key)
                }
            }
            if builtinLighting, let rgb = SceneMaterialPropertyBindingCompiler.emissionColor(instance: materialInstance, pass: pass) {
                let target = SceneDynamicTarget.materialConstant(
                    layerID: layer.id, passIndex: pass.passIndex,
                    name: "emissivebrightness",
                    materialPath: pass.materialPath.replacingOccurrences(of: "\\", with: "/").localizedLowercase
                )
                if materialPropertyTargets.contains(target) {
                    profile.emission = .propertyBrightness(color: rgb, target: target)
                } else if let brightness = SceneMaterialPropertyBindingCompiler.staticComponents("emissivebrightness", instance: materialInstance, pass: pass, count: 1, fallback: [1])?.first,
                          brightness >= 0, Float(brightness).isFinite {
                    profile.emission = .constant(SIMD4(rgb, Float(brightness)))
                }
            }
            if profile.emission == nil {
                NSLog("MWX SCENE: schema=base-material-emission status=invalid-or-unresolved fallback=disabled")
            }
            if profile.emission == nil { profile.mapAllowedComponents &= 7 }
            if reflection == nil { profile.mapAllowedComponents &= ~4 }
            func hasMapProvider(_ inputs: [SceneEffectTextureInput?]) -> Bool {
                inputs.indices.contains(2) && inputs[2] != nil
            }
            func mapPath(_ slots: [String?]) -> String? {
                guard slots.indices.contains(2), let path = slots[2], !path.isEmpty else { return nil }
                return path
            }
            if combo("PBRMASKS") == 0 || profile.mapAllowedComponents == 0 {
                profile.mapSource = .disabled
            } else if combo("PBRMASKS") != nil && combo("PBRMASKS") != 1 {
                profile.mapSource = .unsupported
            } else if hasMapProvider(pass.userTextureInputs)
                        || hasMapProvider(materialInstance?.userTextureInputs ?? []) {
                profile.mapSource = .unsupported
            } else if let path = mapPath(materialInstance?.textureSlots ?? []) ?? mapPath(pass.textureSlots) {
                profile.mapSource = SceneAssetTextureIdentity(virtualPath: path, purpose: .mask)
                    .map { .asset($0) } ?? .invalid
            }

        }
        return profile
    }

    /// Uses the shared prepared image association and the validated Program's
    /// targets; the profile never interprets a current property value.
    static func profiles(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance],
        materialPropertyTargets: Set<SceneDynamicTarget>
    ) -> [Int: SceneBaseMaterialLightingProfile] {
        let passes = SceneMaterialPropertyBindingCompiler.imageMaterialPasses(descriptor: descriptor)
        return descriptor.layers.reduce(into: [:]) { result, layer in
            guard layer.isImageRenderable else { return }
            result[layer.id] = profile(
                layer: layer,
                materialInstance: materialInstancesByLayerID[layer.id],
                materialPasses: passes[layer.id] ?? [],
                materialPropertyTargets: materialPropertyTargets
            )
        }
    }
}
