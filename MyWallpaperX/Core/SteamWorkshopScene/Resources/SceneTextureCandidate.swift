import CoreGraphics
import Metal
import simd

nonisolated enum SceneTextureResourceIdentity: Hashable, Sendable {
    case file(path: String)
    case builtIn(name: String)
}

nonisolated struct SceneTextureFileRevision: Hashable, Sendable {
    let fileSystemID: UInt64
    let fileID: UInt64
    let statusChangedAtSeconds: Int64
    let statusChangedAtNanoseconds: Int64
}

nonisolated enum SceneTextureResourceGeneration: Hashable, Sendable {
    case file(
        byteCount: UInt64,
        modifiedAtBits: UInt64,
        revision: SceneTextureFileRevision
    )
    case immutable(revision: UInt64)
}

/// Immutable texture and slot metadata published as one value. Consumers must
/// validate the expected purpose and UV shape before splitting the binding into
/// Metal arguments, so generation, sampler, and mapped extent cannot drift
/// independently from the texture.
struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureResourceIdentity
    let generation: SceneTextureResourceGeneration
    let purpose: SceneTextureLoadPurpose
    let physicalSize: CGSize
    let mappedSize: CGSize
    let uvTransform: SceneTextureUVTransform
    let sampling: SceneTextureSampling

    var pixelFormat: MTLPixelFormat { texture.pixelFormat }

    func axisAlignedMappedUVScale(
        expectedPurpose: SceneTextureLoadPurpose
    ) -> SIMD2<Float>? {
        guard purpose == expectedPurpose,
              valid(physicalSize),
              valid(mappedSize),
              mappedSize.width <= physicalSize.width,
              mappedSize.height <= physicalSize.height,
              Int(physicalSize.width.rounded()) == texture.width,
              Int(physicalSize.height.rounded()) == texture.height else {
            return nil
        }
        let expected = SIMD2<Float>(
            Float(mappedSize.width / physicalSize.width),
            Float(mappedSize.height / physicalSize.height)
        )
        guard finite(uvTransform.origin),
              finite(uvTransform.xAxis),
              finite(uvTransform.yAxis),
              near(uvTransform.origin, .zero),
              near(uvTransform.xAxis, SIMD2(expected.x, 0)),
              near(uvTransform.yAxis, SIMD2(0, expected.y)),
              expected.x > 0,
              expected.y > 0,
              expected.x <= 1,
              expected.y <= 1 else {
            return nil
        }
        return expected
    }

    var diagnosticSummary: String {
        let scale = axisAlignedMappedUVScale(expectedPurpose: purpose) ?? .zero
        return "purpose=\(purpose.diagnosticName)"
            + " physical=\(Int(physicalSize.width))x\(Int(physicalSize.height))"
            + " mapped=\(Int(mappedSize.width))x\(Int(mappedSize.height))"
            + " uvScale=\(scale.x),\(scale.y)"
            + " sampling=\(sampling.filter.rawValue)/\(sampling.addressMode.rawValue)"
            + " pixelFormat=\(pixelFormat.rawValue)"
    }

    private func valid(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
            && size.width.rounded() == size.width
            && size.height.rounded() == size.height
    }

    private func finite(_ value: SIMD2<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite
    }

    private func near(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        abs(lhs.x - rhs.x) <= 0.000_001
            && abs(lhs.y - rhs.y) <= 0.000_001
    }
}

private extension SceneTextureLoadPurpose {
    var diagnosticName: String {
        switch self {
        case .premultipliedColor: "premultipliedColor"
        case .straightAlbedo: "straightAlbedo"
        case .preservedChannels: "preservedChannels"
        case .mask: "mask"
        case .noise: "noise"
        case .flow: "flow"
        case .phase: "phase"
        case .normal: "normal"
        case .depth: "depth"
        }
    }
}
