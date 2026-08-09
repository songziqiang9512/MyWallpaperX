import simd

nonisolated struct SceneTextureUVTransform: Equatable, Hashable, Sendable {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>

    nonisolated static let identity = SceneTextureUVTransform(
        origin: .zero,
        xAxis: SIMD2(1, 0),
        yAxis: SIMD2(0, 1)
    )

    var uniform0: SIMD4<Float> {
        SIMD4(origin.x, origin.y, xAxis.x, xAxis.y)
    }

    var uniform1: SIMD4<Float> {
        SIMD4(yAxis.x, yAxis.y, 0, 0)
    }
}
