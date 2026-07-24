import simd

nonisolated struct SceneSurfacePointerState: Equatable, Sendable {
    var current: SIMD2<Float> = .zero
    var previous: SIMD2<Float> = .zero
    var isInside = false
    var isPrimaryButtonDown = false
}
