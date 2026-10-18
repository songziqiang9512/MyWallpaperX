import Foundation

/// Launch/preparation-only normalization of authored material fields.
nonisolated extension SceneMaterialRenderState {
    static func compile(
        blending: String?,
        depthTest: String?,
        depthWrite: String?,
        cullMode: String?,
        alphaWriting: String?,
        missingBlending: Blending? = nil
    ) -> SceneMaterialRenderState? {
        let rawValues = RawValues(
            blending: blending,
            depthTest: depthTest,
            depthWrite: depthWrite,
            cullMode: cullMode,
            alphaWriting: alphaWriting
        )
        guard let typedBlending = compileBlending(blending, missing: missingBlending),
              let typedDepthTest = typed(depthTest, as: Depth.self),
              let typedDepthWrite = typed(depthWrite, as: Depth.self),
              let typedCullMode = typed(cullMode, as: Cull.self),
              let typedAlphaWriting = Self.alphaWriting(alphaWriting) else {
            return nil
        }
        return SceneMaterialRenderState(
            rawValues: rawValues,
            blending: typedBlending,
            depthTest: typedDepthTest,
            depthWrite: typedDepthWrite,
            cullMode: typedCullMode,
            alphaWriting: typedAlphaWriting
        )
    }

    /// Prepared model casting needs only this authored state. Do not make it
    /// depend on unrelated depth/cull fields or classify unknown alpha modes.
    static func compileBlending(_ rawValue: String?, missing: Blending? = nil) -> Blending? {
        typed(rawValue, as: Blending.self, missing: missing)
    }

    private static func typed<Value: RawRepresentable>(
        _ rawValue: String?,
        as type: Value.Type,
        missing: Value? = nil
    ) -> Value? where Value.RawValue == String {
        guard let normalized = normalized(rawValue) else { return missing }
        return Value(rawValue: normalized)
    }

    private static func alphaWriting(_ rawValue: String?) -> AlphaWriting? {
        guard let normalized = normalized(rawValue) else { return .unspecified }
        return AlphaWriting(rawValue: normalized)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        return normalized.isEmpty ? nil : normalized
    }
}
