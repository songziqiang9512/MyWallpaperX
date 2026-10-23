import CoreGraphics
import simd

extension SceneMetalRenderer {
    struct DirectDrawFrameTargetGeometry {
        let outputModelViewProjection: simd_float4x4
        let pixelSize: CGSize
        let authoredDomain: SceneDirectDrawOutputGeometry.Resolved?
    }

    /// Resolve the authored numeric producers before target allocation. The
    /// returned geometry is carried through this frame, never reconstructed by
    /// the graph executor or the terminal texture compositor.
    func prepareDirectDrawFrameTargetGeometry(
        contract: SceneResolvedMaterialFrameInputContract,
        snapshot: SceneDynamicSnapshot,
        canvasSize: SIMD2<Float>,
        squareUnitModelMatrix: simd_float4x4,
        viewProjection: simd_float4x4,
        viewportSize: CGSize
    ) -> DirectDrawFrameTargetGeometry? {
        guard case .authoredCanvasDirectDraw = contract.emittedOutputGeometrySource else { return nil }
        let domain: SceneDirectDrawOutputGeometry.Resolved?
        if let binding = contract.directDrawGeometry {
            let points = binding.pointBindings.compactMap {
                SceneResolvedMaterialProgram.resolvePreparedPoint($0, snapshot: snapshot)
            }
            guard points.count == 4,
                  let resolved = SceneDirectDrawOutputGeometry.resolve(
                    coordinates: .init(p0: points[0], p1: points[1], p2: points[2], p3: points[3]),
                    canvasSize: canvasSize, squareUnitModelMatrix: squareUnitModelMatrix,
                    viewProjection: viewProjection, frameIndex: snapshot.frameIndex,
                    generation: snapshot.generation
                  ) else { return nil }
            domain = resolved
        } else {
            domain = nil
        }
        let outputMVP = domain?.outputModelViewProjection ?? viewProjection * squareUnitModelMatrix
        guard let pixelSize = SceneCaptureGeometryResolver.projectedPixelSize(
            layerMVP: outputMVP, viewportSize: viewportSize
        ) else { return nil }
        return .init(outputModelViewProjection: outputMVP, pixelSize: pixelSize, authoredDomain: domain)
    }
}
