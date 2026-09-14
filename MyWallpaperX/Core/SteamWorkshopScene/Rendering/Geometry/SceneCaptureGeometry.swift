import CoreGraphics
import simd

struct SceneCaptureGeometry {
    let sourceUV: SceneTextureUVTransform
    let outputMVP: simd_float4x4
    let pixelSize: CGSize
}

/// The semantic pixel extent of one layer-local effect source. This is kept
/// separate from the Metal texture allocation: padded TEX resources can have
/// a square physical texture while the authored layer and mapped image are a
/// wide or narrow logical surface.
nonisolated struct SceneLayerEffectSourceExtent: Equatable {
    let pixelSize: CGSize

    init?(pixelSize: CGSize) {
        guard pixelSize.width.isFinite, pixelSize.width > 0,
              pixelSize.height.isFinite, pixelSize.height > 0 else {
            return nil
        }
        self.pixelSize = pixelSize
    }

    static func resolve(
        publishedRenderSizeWH: [Float]?,
        authoredRenderSizeWH: [Float]?,
        candidateMappedSize: CGSize?
    ) -> SceneLayerEffectSourceExtent? {
        if let publishedRenderSizeWH {
            return extent(renderSizeWH: publishedRenderSizeWH)
        }
        if let authoredRenderSizeWH {
            return extent(renderSizeWH: authoredRenderSizeWH)
        }
        guard let candidateMappedSize else { return nil }
        return SceneLayerEffectSourceExtent(pixelSize: candidateMappedSize)
    }

    private static func extent(
        renderSizeWH: [Float]
    ) -> SceneLayerEffectSourceExtent? {
        guard renderSizeWH.count == 2 else { return nil }
        return SceneLayerEffectSourceExtent(pixelSize: CGSize(
            width: CGFloat(renderSizeWH[0]),
            height: CGFloat(renderSizeWH[1])
        ))
    }
}

enum SceneCaptureGeometryResolver {
    nonisolated static func projectedPixelSize(
        layerMVP: simd_float4x4,
        viewportSize: CGSize
    ) -> CGSize? {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              let topLeft = sourceUV(position: SIMD2(-0.5, 0.5), mvp: layerMVP),
              let topRight = sourceUV(position: SIMD2(0.5, 0.5), mvp: layerMVP),
              let bottomLeft = sourceUV(position: SIMD2(-0.5, -0.5), mvp: layerMVP),
              let bottomRight = sourceUV(position: SIMD2(0.5, -0.5), mvp: layerMVP) else {
            return nil
        }
        let points = [topLeft, topRight, bottomLeft, bottomRight]
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGSize(
            width: max(1, ceil(CGFloat(maxX - minX) * viewportSize.width)),
            height: max(1, ceil(CGFloat(maxY - minY) * viewportSize.height))
        )
    }

    nonisolated static func resolve(
        kind: SceneUtilityLayer.Kind,
        layerMVP: simd_float4x4,
        viewportSize: CGSize
    ) -> SceneCaptureGeometry? {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return nil
        }
        if kind == .fullscreen {
            return SceneCaptureGeometry(
                sourceUV: .identity,
                outputMVP: fullTargetMVP,
                pixelSize: viewportSize
            )
        }

        guard let topLeft = sourceUV(position: SIMD2(-0.5, 0.5), mvp: layerMVP),
              let topRight = sourceUV(position: SIMD2(0.5, 0.5), mvp: layerMVP),
              let bottomLeft = sourceUV(position: SIMD2(-0.5, -0.5), mvp: layerMVP) else {
            return nil
        }
        guard let pixelSize = projectedPixelSize(
            layerMVP: layerMVP,
            viewportSize: viewportSize
        ) else { return nil }

        return SceneCaptureGeometry(
            sourceUV: SceneTextureUVTransform(
                origin: topLeft,
                xAxis: topRight - topLeft,
                yAxis: bottomLeft - topLeft
            ),
            outputMVP: layerMVP,
            pixelSize: pixelSize
        )
    }

    nonisolated static func isAxisAlignedFullViewportCoverage(
        layerMVP: simd_float4x4,
        viewportSize: CGSize
    ) -> Bool {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              let topLeft = sourceUV(position: SIMD2(-0.5, 0.5), mvp: layerMVP),
              let topRight = sourceUV(position: SIMD2(0.5, 0.5), mvp: layerMVP),
              let bottomLeft = sourceUV(position: SIMD2(-0.5, -0.5), mvp: layerMVP),
              let bottomRight = sourceUV(position: SIMD2(0.5, -0.5), mvp: layerMVP)
        else { return false }

        let tolerance: Float = 0.000_1
        guard abs(topLeft.y - topRight.y) <= tolerance,
              abs(bottomLeft.y - bottomRight.y) <= tolerance,
              abs(topLeft.x - bottomLeft.x) <= tolerance,
              abs(topRight.x - bottomRight.x) <= tolerance else {
            return false
        }
        let minX = min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let maxX = max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let minY = min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        return minX <= tolerance && maxX >= 1 - tolerance
            && minY <= tolerance && maxY >= 1 - tolerance
    }

    nonisolated private static func sourceUV(
        position: SIMD2<Float>,
        mvp: simd_float4x4
    ) -> SIMD2<Float>? {
        let clip = mvp * SIMD4(position.x, position.y, 0, 1)
        guard clip.w.isFinite, abs(clip.w) > 1e-8 else { return nil }
        let ndc = SIMD2(clip.x / clip.w, clip.y / clip.w)
        guard ndc.x.isFinite, ndc.y.isFinite else { return nil }
        return SIMD2((ndc.x + 1) * 0.5, (1 - ndc.y) * 0.5)
    }

    nonisolated private static let fullTargetMVP = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
}
