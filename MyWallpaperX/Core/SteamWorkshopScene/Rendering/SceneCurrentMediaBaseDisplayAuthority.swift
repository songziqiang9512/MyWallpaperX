import Metal
import simd

/// Admits one exact current-media publication as a neutral full-viewport base
/// image. It owns no authored effect or dependency semantics.
enum SceneCurrentMediaBaseDisplayAuthority {
    static func admits(
        _ request: SceneImageLayerDrawRequest,
        publication: SceneTextureProviderPublication?
    ) -> Bool {
        guard let publication,
              request.layer.contentKind == "image",
              request.layer.visible != false,
              request.layer.displayScriptOwnership?.isEmpty ?? true,
              request.layer.effects.contains(where: { $0.visible != false }),
              request.resolvedMaterialFrameTargetPlan == nil,
              !request.requiresSourceCopy,
              request.finalCompositeAlpha == nil,
              (request.layer.colorBlendMode ?? 0) == 0,
              neutral(request.uniforms.alpha),
              neutral(request.uniforms.tint.x),
              neutral(request.uniforms.tint.y),
              neutral(request.uniforms.tint.z),
              neutralColor(request.layer.colorRGB),
              neutral(Float(request.layer.brightness ?? 1)),
              request.textureFrame == .identity,
              publication.requestIdentity == .layerSource(request.layer.id),
              publication.texture === request.texture,
              publication.contentGeneration > 0,
              publication.isComplete,
              case .provider(.mediaThumbnailCurrent) = publication.candidate.identity,
              case let .provider(generation) = publication.candidate.generation,
              generation == publication.contentGeneration,
              publication.candidate.purpose == .premultipliedColor,
              publication.candidate.content
                == .color(.resolved(.premultipliedAlpha)),
              publication.candidate.axisAlignedMappedUVScale(
                expectedPurpose: .premultipliedColor
              ) == SIMD2<Float>(repeating: 1),
              publication.candidate.sampling == .linearClamp,
              publication.candidate.sampling.rawFlags == nil,
              publication.candidate.authoredFormat == nil,
              publication.candidate.pixelFormat == .rgba8Unorm
                || publication.candidate.pixelFormat == .bgra8Unorm,
              publication.candidate.texture.textureType == .type2D,
              publication.candidate.texture.sampleCount == 1,
              publication.candidate.texture.mipmapLevelCount == 1,
              publication.candidate.texture.usage.contains(.shaderRead),
              quadCoversViewport(request.mvp) else {
            return false
        }
        return true
    }

    private static func quadCoversViewport(_ mvp: simd_float4x4) -> Bool {
        let originClip = mvp * SIMD4<Float>(0, 0, 0, 1)
        guard finite(originClip), abs(originClip.w) > 0.000_001 else {
            return false
        }
        let planeNDCZ = originClip.z / originClip.w
        guard planeNDCZ.isFinite else { return false }
        let inverse = mvp.inverse
        guard inverse.columns.0.allFinite,
              inverse.columns.1.allFinite,
              inverse.columns.2.allFinite,
              inverse.columns.3.allFinite else {
            return false
        }
        let corners: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2(1, -1),
            SIMD2(-1, 1), SIMD2(1, 1),
        ]
        return corners.allSatisfy { corner in
            let localH = inverse * SIMD4<Float>(corner.x, corner.y, planeNDCZ, 1)
            guard finite(localH), abs(localH.w) > 0.000_001 else {
                return false
            }
            let local = localH / localH.w
            let tolerance: Float = 0.000_5
            return abs(local.z) <= tolerance
                && local.x >= -0.5 - tolerance
                && local.x <= 0.5 + tolerance
                && local.y >= -0.5 - tolerance
                && local.y <= 0.5 + tolerance
        }
    }

    private static func neutral(_ value: Float) -> Bool {
        value.isFinite && abs(value - 1) <= 0.000_001
    }

    private static func neutralColor(_ values: [Float]?) -> Bool {
        guard let values else { return true }
        return values.count == 3 && values.allSatisfy {
            $0.isFinite && abs($0 - 1) <= 0.000_001
        }
    }

    private static func finite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite
            && value.z.isFinite && value.w.isFinite
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
