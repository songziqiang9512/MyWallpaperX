import CoreGraphics
import simd

/// Source-less quads use equal world units on both texture axes. The authored
/// canvas height sets their unit extent; layer scale and shader control points
/// remain responsible for the author's shape. Canvas aspect must not stretch it.
enum SceneDirectDrawOutputGeometry {
    struct Resolved {
        let frameIndex: UInt64
        let generation: UInt64
        let coordinates: SceneShaderQuadCoordinates
        let vertexInputSize: CGSize
        /// Original H-square basis for authored effect-model uniforms.
        let squareUnitModelMatrix: simd_float4x4
        let squareModelViewProjection: simd_float4x4
        let captureModelViewProjection: simd_float4x4
        let outputModelViewProjection: simd_float4x4
    }

    static func resolve(
        coordinates: SceneShaderQuadCoordinates,
        canvasSize: SIMD2<Float>,
        squareUnitModelMatrix: simd_float4x4,
        viewProjection: simd_float4x4,
        frameIndex: UInt64,
        generation: UInt64
    ) -> Resolved? {
        guard let extent = baseExtent(canvasSize: canvasSize) else { return nil }
        let points = [coordinates.p0, coordinates.p1, coordinates.p2, coordinates.p3]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        // A strict convex ring rejects collapse and crossed edges without
        // inventing a triangulation policy for unqualified author geometry.
        var winding: Double = 0
        for index in 0..<4 {
            let a = points[index], b = points[(index + 1) % 4], c = points[(index + 2) % 4]
            let cross = (Double(b.x) - Double(a.x)) * (Double(c.y) - Double(b.y))
                - (Double(b.y) - Double(a.y)) * (Double(c.x) - Double(b.x))
            guard cross.isFinite, cross != 0 else { return nil }
            if index == 0 { winding = cross }
            guard (cross > 0) == (winding > 0) else { return nil }
        }
        let minimum = SIMD2(points.map(\.x).min()!, points.map(\.y).min()!)
        let maximum = SIMD2(points.map(\.x).max()!, points.map(\.y).max()!)
        let domainSize = maximum - minimum
        let center = minimum + domainSize * 0.5
        let rawSize = extent * domainSize
        let rawCenter = SIMD2((center.x - 0.5) * extent.x, (0.5 - center.y) * extent.y)
        guard rawSize.x.isFinite, rawSize.y.isFinite,
              rawSize.x > 0, rawSize.y > 0,
              rawCenter.x.isFinite, rawCenter.y.isFinite else { return nil }
        let capture = SceneMatrix.scale(SIMD3(2 / rawSize.x, 2 / rawSize.y, 1))
            * SceneMatrix.translation(SIMD3(-rawCenter.x, -rawCenter.y, 0))
        let outputModel = squareUnitModelMatrix
            * SceneMatrix.translation(SIMD3(center.x - 0.5, 0.5 - center.y, 0))
            * SceneMatrix.scale(SIMD3(domainSize.x, domainSize.y, 1))
        let squareMVP = viewProjection * squareUnitModelMatrix
        let outputMVP = viewProjection * outputModel
        guard [capture, squareUnitModelMatrix, squareMVP, outputMVP].allSatisfy({ matrix in
            [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
                .allSatisfy(\.allFinite)
        }) else { return nil }
        return .init(
            frameIndex: frameIndex, generation: generation, coordinates: coordinates,
            vertexInputSize: CGSize(width: CGFloat(extent.x), height: CGFloat(extent.y)),
            squareUnitModelMatrix: squareUnitModelMatrix,
            squareModelViewProjection: squareMVP,
            captureModelViewProjection: capture,
            outputModelViewProjection: outputMVP
        )
    }

    static func baseExtent(canvasSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard canvasSize.x.isFinite, canvasSize.y.isFinite,
              canvasSize.x > 0, canvasSize.y > 0 else { return nil }
        return SIMD2(repeating: canvasSize.y)
    }

    static func modelMatrix(
        worldFrame: simd_float4x4,
        parallaxOffset: SIMD2<Float>,
        canvasSize: SIMD2<Float>
    ) -> simd_float4x4? {
        guard let extent = baseExtent(canvasSize: canvasSize),
              worldFrame.columns.0.allFinite,
              worldFrame.columns.1.allFinite,
              worldFrame.columns.2.allFinite,
              worldFrame.columns.3.allFinite,
              parallaxOffset.x.isFinite, parallaxOffset.y.isFinite else {
            return nil
        }
        return SceneMatrix.translation(SIMD3(parallaxOffset.x, parallaxOffset.y, 0))
            * worldFrame
            * SceneMatrix.scale(SIMD3(extent.x, -extent.y, 1))
    }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}
