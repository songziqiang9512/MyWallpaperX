import CoreGraphics
import Metal
import simd

nonisolated struct SceneEffectTextureLoadResult {
    let candidate: SceneTextureCandidate?
    let texture: MTLTexture?
    let mappedUVScale: SIMD2<Float>
    let sampling: SceneTextureSampling
    let message: String
}

/// Shared typed view of an effect-local texture demand.  Effect renderers may
/// keep their own semantic wrapper, but the resource facts (purpose,
/// generation, readiness and mapped extent) are published by this one value.
/// A missing optional path is `absent`; a declared path that did not publish a
/// texture is `unavailable`.  This distinction is used by the layer safety
/// gate and must not be collapsed into an empty texture fallback.
nonisolated struct SceneEffectTextureBinding {
    enum State: Hashable, Sendable {
        case absent
        case pending
        case unavailable
        case ready
    }

    let candidate: SceneTextureCandidate?
    let path: String?
    let purpose: SceneTextureLoadPurpose
    let state: State

    var texture: MTLTexture? { candidate?.texture }
    var generation: SceneTextureResourceGeneration? { candidate?.generation }
    var physicalSize: CGSize? { candidate?.physicalSize }
    var mappedSize: CGSize? { candidate?.mappedSize }
    var mappedUVScale: SIMD2<Float> {
        candidate?.axisAlignedMappedUVScale(expectedPurpose: purpose)
            ?? SIMD2(repeating: 1)
    }

    init(
        path: String?,
        purpose: SceneTextureLoadPurpose,
        loadResult: SceneEffectTextureLoadResult
    ) {
        self.path = path
        self.purpose = purpose
        if path == nil {
            candidate = nil
            state = .absent
        } else if let candidate = loadResult.candidate,
                  candidate.purpose == purpose,
                  candidate.texture === loadResult.texture,
                  candidate.axisAlignedMappedUVScale(expectedPurpose: purpose)
                    == loadResult.mappedUVScale {
            self.candidate = candidate
            state = .ready
        } else {
            candidate = nil
            state = .unavailable
        }
    }

    static func absent(purpose: SceneTextureLoadPurpose) -> Self {
        Self(candidate: nil, path: nil, purpose: purpose, state: .absent)
    }

    static func pending(path: String, purpose: SceneTextureLoadPurpose) -> Self {
        Self(candidate: nil, path: path, purpose: purpose, state: .pending)
    }

    static func unavailable(path: String, purpose: SceneTextureLoadPurpose) -> Self {
        Self(candidate: nil, path: path, purpose: purpose, state: .unavailable)
    }

    var isReady: Bool { state == .ready && texture != nil }

    func matches(path expectedPath: String?) -> Bool {
        guard path.map(Self.normalized) == expectedPath.map(Self.normalized) else {
            return false
        }
        return expectedPath == nil || isReady
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private init(
        candidate: SceneTextureCandidate?,
        path: String?,
        purpose: SceneTextureLoadPurpose,
        state: State
    ) {
        self.candidate = candidate
        self.path = path
        self.purpose = purpose
        self.state = state
    }
}
