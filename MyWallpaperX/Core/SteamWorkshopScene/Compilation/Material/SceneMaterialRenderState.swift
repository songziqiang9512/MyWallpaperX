import Foundation

/// Loss-preserving typed material render state shared by authored effects and
/// particle material admission.
///
/// This type only normalizes values observed in the current stock/Workshop
/// corpus. It deliberately does not translate them to Metal blend/depth/write
/// state: Ghidra proves the state injection boundary, but not the exact backend
/// mapping or the meaning of `alphawriting = default`.
nonisolated struct SceneMaterialRenderState: Equatable, Hashable, Sendable {
    enum Blending: String, Sendable {
        case normal
        case translucent
        case additive
    }

    enum Depth: String, Sendable {
        case disabled
        case enabled
    }

    enum Cull: String, Sendable {
        case noCull = "nocull"
        case normal
    }

    enum AlphaWriting: String, Sendable {
        case unspecified
        case `default`
        case enabled
    }

    struct RawValues: Equatable, Hashable, Sendable {
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let rawValues: RawValues
    let blending: Blending
    let depthTest: Depth
    let depthWrite: Depth
    let cullMode: Cull
    let alphaWriting: AlphaWriting

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
        guard let typedBlending = typed(
                  blending,
                  as: Blending.self,
                  missing: missingBlending
              ),
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

    func matchesFullscreenOverwrite(
        alphaWriting expectedAlphaWriting: AlphaWriting
    ) -> Bool {
        blending == .normal
            && depthTest == .disabled
            && depthWrite == .disabled
            && cullMode == .noCull
            && alphaWriting == expectedAlphaWriting
    }

    /// Resolved full-screen material passes write every attachment channel.
    /// Both an omitted alpha-writing field and the authored `enabled` value
    /// are executable overwrite states; `default` remains unproven.
    var supportsResolvedMaterialFullscreenOverwrite: Bool {
        blending == .normal
            && depthTest == .disabled
            && depthWrite == .disabled
            && cullMode == .noCull
            && (alphaWriting == .unspecified || alphaWriting == .enabled)
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
