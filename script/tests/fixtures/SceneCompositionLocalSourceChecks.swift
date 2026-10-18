import CoreGraphics
import Foundation
import simd

enum SceneCompositionLocalSourceChecks {
    static func run() -> [String: Any] {
        // T(.125, .0625) * Rz(90 degrees) * S(.75, .125).
        // Exact binary coefficients keep the oracle independent of trig rounding.
        let root = simd_float4x4(
            SIMD4(0, 0.75, 0, 0), SIMD4(-0.125, 0, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0.125, 0.0625, 0.375, 1)
        )
        let source = SceneCompositionSourceGeometry(
            authoredRenderSizeWH: [80, 40], worldMVP: root
        )!
        func resolve(_ kind: SceneUtilityLayer.Kind = .composition,
                     members: [Int]? = [7], local: CGSize? = CGSize(width: 80, height: 40),
                     viewport: CGSize = CGSize(width: 640, height: 360)) -> SceneCaptureGeometry {
            SceneCaptureGeometryResolver.resolve(
                kind: kind, layerMVP: root, viewportSize: viewport,
                compositionSourceMemberLayerIDs: members,
                authoredRenderSizeWH: [80, 40], localCompositionSourceExtent: local
            )!
        }
        let local = resolve()
        let worldSamples: [SIMD4<Float>] = [
            SIMD4(0.125, 0.0625, 0, 1), SIMD4(0.125, 0.4375, 9, 1),
            SIMD4(0.0625, 0.0625, -9, 1), SIMD4(0.09375, -0.125, 3, 1),
            SIMD4(0.046875, 0.0625, 0, 1), SIMD4(0.125, 0.625, 0, 1),
        ]
        var rasterMatrices: [[Float]] = []
        var childCorners: [[[Float]]] = []
        var outputPoints: [[[Float]]] = []
        for z in [Float(-100), 0, 100] {
            // Half-size child at parent-local (-.25, .25), with unrelated depth.
            let child = simd_float4x4(
                SIMD4(0, 0.375, 0, 0), SIMD4(-0.0625, 0, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(0.09375, -0.125, z, 1)
            )
            let raster = source.rasterModelViewProjection(child)
            rasterMatrices.append(Harness.matrix(raster))
            childCorners.append([
                SIMD4<Float>(-0.5, -0.5, 0, 1), SIMD4(0.5, -0.5, 0, 1),
                SIMD4(0.5, 0.5, 0, 1), SIMD4(-0.5, 0.5, 0, 1),
            ].map { point(raster * $0) })
            outputPoints.append([
                SIMD4<Float>(0, 0, 0, 1), SIMD4(0.5, 0.5, 0, 1),
                SIMD4(-0.5, -0.5, 0, 1),
            ].map {
                let r = raster * $0
                let output = local.outputMVP * SIMD4(r.x * 0.5, r.y * 0.5, 0, r.w)
                return [output.x / output.w, output.y / output.w]
            })
        }

        // x=2u+.25, y=4v-.5, w=.5u-.25v+1. The middle input
        // is independently normalized from (u,v)=(.25,-.125), w=37/32.
        let projective = simd_float4x4(
            SIMD4(2, 0, 0, 0.5), SIMD4(0, 4, 0, -0.25),
            SIMD4(0, 0, 1, 0), SIMD4(0.25, -0.5, 0, 1)
        )
        let perspectiveSource = SceneCompositionSourceGeometry(
            authoredRenderSizeWH: [120, 60], worldMVP: projective
        )!
        let projectiveSamples: [SIMD4<Float>] = [
            SIMD4(0.25, -0.5, 30, 1),
            SIMD4(24.0 / 37, -32.0 / 37, -30, 1),
            SIMD4(-1.2, 2.4, 0, 1),
        ]
        let mirrored = SceneCompositionSourceGeometry(
            authoredRenderSizeWH: [80, 40],
            worldMVP: SceneMatrix.scale(SIMD3<Float>(-0.5, 2, 1))
        )!
        let invalidSizes: [String: [Float]] = [
            "empty": [], "oneAxis": [80], "extraAxis": [80, 40, 1],
            "zero": [0, 40], "negative": [80, -1], "nan": [.nan, 40],
            "infinity": [80, .infinity], "finiteIntOverflow": [1e20, 40],
            "greatestFinite": [80, .greatestFiniteMagnitude],
            "roundedIntOverflow": [Float(Int.max), 40],
        ]
        var nonfiniteXY = matrix_identity_float4x4
        nonfiniteXY.columns.0.x = .nan
        var nonfiniteW = matrix_identity_float4x4
        nonfiniteW.columns.3.w = .infinity
        let invalidMatrices = [
            "collapsedX": SceneMatrix.scale(SIMD3<Float>(0, 1, 1)),
            "dependentXY": simd_float4x4(SIMD4(1, 2, 0, 0), SIMD4(2, 4, 0, 0),
                                         SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)),
            "zeroHomogeneousRow": simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                                               SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 0)),
            "nonfiniteXY": nonfiniteXY, "nonfiniteW": nonfiniteW,
            "rasterScaleOverflow": SceneMatrix.scale(SIMD3<Float>(4e-39, 1, 1)),
        ]
        return [
            "rootMVP": Harness.matrix(root),
            "local": Harness.geometry(local),
            "otherViewport": Harness.geometry(resolve(viewport: CGSize(width: 1000, height: 400))),
            "affineWorldToSourcePoints": worldSamples.map { point(source.worldClipToSourceClip * $0) },
            "childRasterMatrices": rasterMatrices, "childRasterCorners": childCorners,
            "worldOutputOncePoints": outputPoints,
            "projectiveXYWPoints": projectiveSamples.map {
                point(perspectiveSource.worldClipToSourceClip * $0)
            },
            "negativeScalePoint": point(mirrored.worldClipToSourceClip * SIMD4(-0.125, -0.5, 4, 1)),
            "absentExtentRejected": SceneCompositionSourceGeometry(
                authoredRenderSizeWH: nil, worldMVP: root) == nil,
            "invalidExtentsRejected": invalidSizes.mapValues {
                SceneCompositionSourceGeometry(authoredRenderSizeWH: $0, worldMVP: root) == nil
            },
            "invalidMatricesRejected": invalidMatrices.mapValues {
                SceneCompositionSourceGeometry(authoredRenderSizeWH: [80, 40], worldMVP: $0) == nil
            },
            "singularDepthStillValidXYW": SceneCompositionSourceGeometry(
                authoredRenderSizeWH: [80, 40],
                worldMVP: SceneMatrix.scale(SIMD3<Float>(1, 1, 0))) != nil,
            "finiteSubnormalRasterScale": SceneCompositionSourceGeometry(
                authoredRenderSizeWH: [80, 40],
                worldMVP: SceneMatrix.scale(SIMD3<Float>(8e-39, 1, 1)))
                    .map { $0.worldClipToSourceClip.columns.0.x } ?? 0,
            "fractionalExtent": SceneCompositionSourceGeometry(
                authoredRenderSizeWH: [80.25, 40.5], worldMVP: root).map {
                    [$0.pixelSize.width, $0.pixelSize.height]
                } ?? [],
            "legacyMembers": Harness.geometry(resolve(local: nil)),
            "empty": Harness.geometry(resolve(members: [])),
            "nilMembers": Harness.geometry(resolve(members: nil)),
            "fullscreen": Harness.geometry(resolve(.fullscreen)),
            "project": Harness.geometry(resolve(.project)),
        ]
    }

    private static func point(_ value: SIMD4<Float>) -> [Float] {
        [value.x, value.y, value.z, value.w]
    }
}
