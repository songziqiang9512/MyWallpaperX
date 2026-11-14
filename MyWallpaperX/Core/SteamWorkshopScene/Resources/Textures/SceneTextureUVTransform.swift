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

    // UV area shrinks with atlas resolution; only a zero determinant is degenerate.
    var isFiniteAndNondegenerate: Bool {
        let area = xAxis.x * yAxis.y - xAxis.y * yAxis.x
        return origin.x.isFinite && origin.y.isFinite
            && xAxis.x.isFinite && xAxis.y.isFinite
            && yAxis.x.isFinite && yAxis.y.isFinite
            && area.isFinite && area != 0
    }

    var uniform0: SIMD4<Float> {
        SIMD4(origin.x, origin.y, xAxis.x, xAxis.y)
    }

    var uniform1: SIMD4<Float> {
        SIMD4(yAxis.x, yAxis.y, 0, 0)
    }
}
