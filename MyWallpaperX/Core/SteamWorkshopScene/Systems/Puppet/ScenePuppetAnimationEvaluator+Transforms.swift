import simd

nonisolated extension ScenePuppetAnimationEvaluator {
    struct PlanarControlPose {
        var goal: SIMD3<Float>
        var guide: SIMD2<Float>
    }

    struct QueryAnchor {
        let index: Int
        let local: simd_float4x4
    }

    var boneNames: [String] { rig.bones.map(\.name) }
    var boneParentIndices: [Int] { rig.bones.map(\.parentIndex) }

    func boneTransforms(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        boneOverrides: [Int: simd_float4x4] = [:],
        blends: [Double]? = nil
    ) throws -> (local: [simd_float4x4], world: [simd_float4x4]) {
        var local = Array(repeating: matrix_identity_float4x4, count: rig.bones.count)
        var world = local
        try writePoseMatrices(selection: selection, frameSamples: frameSamples,
                              boneOverrides: boneOverrides, blends: blends, locals: &local, worlds: &world)
        return (local, world)
    }

    @discardableResult
    func writePoseMatrices(
        selection: ScenePuppetAnimationSelection, frameSamples: [FrameSample?],
        boneOverrides: [Int: simd_float4x4], blends: [Double]?,
        locals: inout [simd_float4x4], worlds: inout [simd_float4x4]
    ) throws -> QueryAnchor? {
        try writeLocalMatrices(selection: selection, frameSamples: frameSamples, blends: blends, into: &locals)
        let controls = try planarControls(selection: selection, frameSamples: frameSamples, blends: blends)
        if let chain = rig.planarConstraint, let controls {
            try writeWorldMatrices(in: 0..<chain.root, locals: locals, worlds: &worlds)
            let index = rig.bones[chain.root].parentIndex
            let parent = index < 0 ? matrix_identity_float4x4 : worlds[index]
            let anchor = applyPlanarConstraint(chain, controls: controls, parent: parent, locals: &locals)
            try applyOverrides(boneOverrides, to: &locals, worlds: &worlds, startingAt: chain.root)
            return boneOverrides[chain.root] == nil ? anchor : nil
        }
        try applyOverrides(boneOverrides, to: &locals, worlds: &worlds)
        return nil
    }

    func applyOverrides(
        _ overrides: [Int: simd_float4x4], to locals: inout [simd_float4x4],
        worlds: inout [simd_float4x4], startingAt: Int = 0
    ) throws {
        var start = startingAt
        for (index, matrix) in overrides {
            guard rig.bones.indices.contains(index) else {
                throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
            }
            locals[index] = matrix
            start = min(start, index)
        }
        try writeWorldMatrices(in: start..<rig.bones.count, locals: locals, worlds: &worlds)
    }

    private func writeWorldMatrices(
        in range: Range<Int>, locals: [simd_float4x4], worlds: inout [simd_float4x4]
    ) throws {
        for index in range {
            let parent = rig.bones[index].parentIndex
            let local = locals[index]
            guard Self.isFinite(local) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(index)
            }
            let world = parent < 0 ? local : worlds[parent] * local
            guard Self.isFinite(world) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(index)
            }
            worlds[index] = world
        }
    }

    private func applyPlanarConstraint(
        _ chain: SceneMdlPuppetRig.PlanarConstraint, controls: PlanarControlPose,
        parent: simd_float4x4, locals: inout [simd_float4x4]
    ) -> QueryAnchor? {
        let queryLocal = locals[chain.root]
        let root = parent * queryLocal
        let joint = root * locals[chain.joint]
        let end = joint * locals[chain.end]
        guard root.columns.3.z == joint.columns.3.z, joint.columns.3.z == end.columns.3.z else { return nil }
        let origin = SIMD2(root.columns.3.x, root.columns.3.y)
        let jointPosition = SIMD2(joint.columns.3.x, joint.columns.3.y)
        let endPosition = SIMD2(end.columns.3.x, end.columns.3.y)
        let first = jointPosition - origin
        let second = endPosition - jointPosition
        let target = SIMD2(controls.goal.x, controls.goal.y) - origin
        let targetLength = simd_length(target)
        let firstLength = Double(simd_length(first)), secondLength = Double(simd_length(second))
        let distance = min(max(Double(targetLength), abs(firstLength - secondLength)), firstLength + secondLength)
        guard distance.isFinite, distance > 0, firstLength > 0, secondLength > 0 else { return nil }
        let axis = targetLength > 0 ? target / targetLength : first / Float(firstLength)
        let perpendicular = SIMD2(-axis.y, axis.x)
        let guideSide = simd_dot(controls.guide - origin, perpendicular)
        let side: Double = guideSide == 0
            ? (simd_dot(first, perpendicular) < 0 ? -1 : 1) : (guideSide < 0 ? -1 : 1)
        let along = (firstLength * firstLength - secondLength * secondLength + distance * distance) / (2 * distance)
        let bend = sqrt(max(0, firstLength * firstLength - along * along))
        let solvedFirst = axis * Float(along) + perpendicular * Float(bend * side)
        let solvedEnd = axis * Float(distance)
        let solvedSecond = solvedEnd - solvedFirst

        let rootDelta = atan2(solvedFirst.y, solvedFirst.x) - atan2(first.y, first.x)
        let jointDelta = atan2(solvedSecond.y, solvedSecond.x) - atan2(second.y, second.x)
        let endDelta = controls.goal.z - atan2(end.columns.0.y, end.columns.0.x)
        let actualRoot = Self.planarTransform(root, at: origin, angle: rootDelta)
        let actualJoint = Self.planarTransform(joint, at: origin + solvedFirst, angle: jointDelta)
        let actualEnd = Self.planarTransform(end, at: origin + solvedEnd, angle: endDelta)
        let rootLocal = rig.bones[chain.root].parentIndex < 0 ? actualRoot : simd_inverse(parent) * actualRoot
        let jointLocal = simd_inverse(actualRoot) * actualJoint
        let endLocal = simd_inverse(actualJoint) * actualEnd
        guard Self.isFinite(rootLocal), Self.isFinite(jointLocal), Self.isFinite(endLocal) else { return nil }
        locals[chain.root] = rootLocal
        locals[chain.joint] = jointLocal
        locals[chain.end] = endLocal
        return .init(index: chain.root, local: queryLocal)
    }

    private static func planarTransform(_ matrix: simd_float4x4, at origin: SIMD2<Float>,
                                        angle: Float) -> simd_float4x4 {
        var result = SceneMatrix.eulerXYZ(SIMD3(0, 0, angle)) * matrix
        result.columns.3 = SIMD4(origin.x, origin.y, matrix.columns.3.z, matrix.columns.3.w)
        return result
    }

    static func planarAngle(_ angle: Float) -> Float { atan2(sin(angle), cos(angle)) }

    static func matrix(fromColumnMajor values: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }

    static func matrix(
        from transform: SceneMdlPuppetAnimation.Transform
    ) -> simd_float4x4 {
        SceneMatrix.translation(transform.translation)
            * SceneMatrix.eulerXYZ(transform.rotation)
            * SceneMatrix.scale(transform.scale)
    }

    static func matrix(from pose: Pose) -> simd_float4x4 {
        SceneMatrix.translation(pose.translation)
            * simd_float4x4(pose.rotation)
            * SceneMatrix.scale(pose.scale)
    }

    static func pose(
        from transform: SceneMdlPuppetAnimation.Transform
    ) -> Pose? {
        guard Self.isFinite(transform.translation),
              Self.isFinite(transform.rotation),
              Self.isFinite(transform.scale) else {
            return nil
        }
        let rotation4 = SceneMatrix.eulerXYZ(transform.rotation)
        let rotation3 = simd_float3x3(columns: (
            SIMD3(rotation4.columns.0.x, rotation4.columns.0.y, rotation4.columns.0.z),
            SIMD3(rotation4.columns.1.x, rotation4.columns.1.y, rotation4.columns.1.z),
            SIMD3(rotation4.columns.2.x, rotation4.columns.2.y, rotation4.columns.2.z)
        ))
        let rotation = simd_quatf(rotation3)
        guard Self.isFinite(rotation.vector) else { return nil }
        return Pose(
            translation: transform.translation,
            rotation: rotation,
            scale: transform.scale
        )
    }

    static func pose(from matrix: simd_float4x4) -> Pose? {
        let c0 = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let c1 = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let c2 = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        var scale = SIMD3(simd_length(c0), simd_length(c1), simd_length(c2))
        guard Self.isFinite(scale),
              scale.x > 0.000001, scale.y > 0.000001, scale.z > 0.000001 else { return nil }
        var r0 = c0 / scale.x
        let r1 = c1 / scale.y
        let r2 = c2 / scale.z
        let rotationMatrix = simd_float3x3(columns: (r0, r1, r2))
        let determinant = simd_determinant(rotationMatrix)
        guard determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
        if determinant < 0 {
            scale.x = -scale.x
            r0 = -r0
        }
        let rotation = simd_quatf(simd_float3x3(columns: (r0, r1, r2)))
        guard Self.isFinite(rotation.vector) else { return nil }
        let translation = SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        guard Self.isFinite(translation) else { return nil }
        return Pose(translation: translation, rotation: rotation, scale: scale)
    }

    static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    static func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    static func maxDifference(_ lhs: Pose, _ rhs: Pose) -> Float {
        max(
            max(
                simd_length(lhs.translation - rhs.translation),
                simd_length(lhs.scale - rhs.scale)
            ),
            simd_length(lhs.rotation.vector - rhs.rotation.vector)
        )
    }

    static func maxDifference(
        _ lhs: simd_float4x4,
        _ rhs: simd_float4x4
    ) -> Float {
        var maximum: Float = 0
        for column in 0..<4 {
            for row in 0..<4 {
                maximum = max(maximum, abs(lhs[column][row] - rhs[column][row]))
            }
        }
        return maximum
    }
}
