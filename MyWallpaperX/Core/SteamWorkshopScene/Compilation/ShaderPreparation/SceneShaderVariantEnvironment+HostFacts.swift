import Foundation

nonisolated extension SceneShaderVariantEnvironment {
    static func unresolvedRequirement(
        for identifier: String
    ) -> SceneShaderEnvironmentRequirement? {
        if ["GLSL", "HLSL", "HLSL_SM30", "HLSL_SM40", "HLSL_GS40"]
            .contains(identifier) {
            return .backendLanguage
        }
        if identifier == "VERSION" || identifier == "SHADERVERSION" {
            return .clientVersion
        }
        if identifier.hasPrefix("PLATFORM_") { return .platform }
        if identifier == "THICKFORMAT"
            || identifier.range(
                of: #"^TEX[0-9]+FORMAT$"#,
                options: .regularExpression
            ) != nil {
            return .textureFormat
        }
        return nil
    }

    static func isHostOwned(_ identifier: String) -> Bool {
        guard let requirement = unresolvedRequirement(for: identifier) else {
            return false
        }
        return requirement == .backendLanguage || requirement == .platform
    }

    /// Wallpaper Engine texture-format macros are ordinary preprocessor
    /// identifiers until a sampler's `formatcombo` gives the host an exact
    /// value. In `#if` expressions an absent identifier therefore has the
    /// standard integer value zero; direct source use and authored attempts
    /// to define or undefine the host-owned name remain rejected.
    static func permitsUndefinedZeroInCondition(_ identifier: String) -> Bool {
        unresolvedRequirement(for: identifier) == .textureFormat
    }

    static func hasVerifiedHostResolution(
        _ resolution: SceneShaderComboResolution
    ) -> Bool {
        guard unresolvedRequirement(for: resolution.binding.name) == .textureFormat,
              resolution.provenance == .textureFormat
                || resolution.provenance == .requirementInactive else {
            return false
        }
        if resolution.provenance == .requirementInactive {
            return resolution.binding.definition == .undefined
                && resolution.validatedTextureSlots.isEmpty
        }
        guard case .defined(.integer(let value)) = resolution.binding.definition,
              let rawValue = UInt32(exactly: value),
              SceneShaderTextureFormat(rawValue: rawValue) != nil,
              resolution.validatedTextureSlots.count == 1,
              let slot = resolution.validatedTextureSlots.first else {
            return false
        }
        return resolution.binding.name == "TEX\(slot)FORMAT"
    }
}
