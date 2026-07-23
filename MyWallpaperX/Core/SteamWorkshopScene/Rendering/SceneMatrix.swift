import simd

// Column-major 4x4 matrix utilities used by the Scene renderer. These match
// the conventions Metal expects: column-major storage, post-multiplication
// (M * v), depth in [0, 1] for the orthographic projection.
//
// Right-handed world space. View space: looking along -Z, +Y up. Layers live
// on a single z=0 plane unless their origin specifies otherwise.
enum SceneMatrix {
    // MARK: - Identity / translate / scale / rotate

    static func identity() -> simd_float4x4 {
        matrix_identity_float4x4
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(t.x, t.y, t.z, 1)
        ))
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(s.x, 0, 0, 0),
            SIMD4(0, s.y, 0, 0),
            SIMD4(0, 0, s.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotationX(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotationY(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotationZ(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians), s = sin(radians)
        return simd_float4x4(columns: (
            SIMD4(c, s, 0, 0),
            SIMD4(-s, c, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    // Wallpaper Engine angles order: X then Y then Z (rad). Composed as Rz * Ry * Rx
    // so the X rotation is applied first to the point.
    static func eulerXYZ(_ radians: SIMD3<Float>) -> simd_float4x4 {
        rotationZ(radians.z) * rotationY(radians.y) * rotationX(radians.x)
    }

    // MARK: - View / projection

    // Right-handed lookAt. Builds a view matrix that places `eye` at the origin
    // and orients `center - eye` along -Z, `up` along +Y.
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)         // forward (camera looks toward this)
        let s = simd_normalize(simd_cross(f, up))    // right
        let u = simd_cross(s, f)                     // recomputed up
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    // Right-handed orthographic projection mapping [left, right] x [bottom, top]
    // x [near, far] to Metal NDC ([-1,1] x [-1,1] x [0,1]).
    static func ortho(
        left: Float, right: Float,
        bottom: Float, top: Float,
        near: Float, far: Float
    ) -> simd_float4x4 {
        let rl = right - left
        let tb = top - bottom
        let fn = far - near
        return simd_float4x4(columns: (
            SIMD4(2 / rl, 0, 0, 0),
            SIMD4(0, 2 / tb, 0, 0),
            SIMD4(0, 0, -1 / fn, 0),
            SIMD4(-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1)
        ))
    }

    // Right-handed perspective projection for Metal NDC depth [0, 1]. `near`
    // and `far` are positive distances while visible view-space Z is negative.
    static func perspectiveRHMetal(
        fovYRadians: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        guard fovYRadians.isFinite, fovYRadians > 0, fovYRadians < .pi,
              aspect.isFinite, aspect > 0,
              near.isFinite, far.isFinite, near > 0, far > near else {
            return identity()
        }
        let yScale = 1 / tan(fovYRadians * 0.5)
        let xScale = yScale / aspect
        let depth = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, depth, -1),
            SIMD4(0, 0, depth * near, 0)
        ))
    }
}

extension SIMD3 where Scalar == Float {
    init(_ array: [Float], fill: Float = 0) {
        let x = array.count > 0 ? array[0] : fill
        let y = array.count > 1 ? array[1] : fill
        let z = array.count > 2 ? array[2] : fill
        self.init(x, y, z)
    }
}

extension SIMD2 where Scalar == Float {
    init(_ array: [Float], fill: Float = 0) {
        let x = array.count > 0 ? array[0] : fill
        let y = array.count > 1 ? array[1] : fill
        self.init(x, y)
    }
}
