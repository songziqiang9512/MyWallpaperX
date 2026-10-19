import Foundation

/// Prepared material values shared with rendering. Author-string parsing stays
/// in Compilation/Material; backend mappings remain with their draw owners.
nonisolated struct SceneMaterialRenderState: Codable, Equatable, Hashable, Sendable {
    /// A prepared procedural model source, independent of its terminal state.
    enum ProceduralSolidSource: String, Codable, Sendable {
        case neutral
    }

    enum Blending: String, Codable, Sendable {
        case normal
        case translucent
        case additive
        case alphaToCoverage = "alphatocoverage"
    }

    enum Depth: String, Codable, Sendable {
        case disabled
        case enabled
    }

    enum Cull: String, Codable, Sendable {
        case noCull = "nocull"
        case normal
    }

    enum AlphaWriting: String, Codable, Sendable {
        case unspecified
        case `default`
        case enabled
    }

    struct RawValues: Codable, Equatable, Hashable, Sendable {
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

    var requiresDepthAttachment: Bool {
        depthTest == .enabled || depthWrite == .enabled
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

}
