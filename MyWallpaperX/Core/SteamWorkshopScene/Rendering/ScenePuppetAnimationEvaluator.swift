import simd

struct ScenePuppetAnimationEvaluator {
    /// A source-FPS interval sample.  MDLA stores frameCount + 1 poses, so a
    /// frame is an interval between two authored poses rather than a single
    /// integer lookup.  Keeping both endpoints also lets mirror playback
    /// preserve the authored terminal pose and direction.
    struct FrameSample: Equatable {
        let frameA: Int
        let frameB: Int
        let fraction: Float

        init(frameA: Int, frameB: Int, fraction: Float = 0) {
            self.frameA = frameA
            self.frameB = frameB
            self.fraction = fraction
        }
    }

    private struct Pose {
        var translation: SIMD3<Float>
        var rotation: simd_quatf
        var scale: SIMD3<Float>
    }

    private struct PreparedAnimation {
        let posesByBone: [[Pose]]
        let referencePosesByBone: [Pose]
        let drivenBones: Set<Int>
        let authoredBones: Set<Int>
    }

    /// Vertex data that is invariant for the lifetime of a playback state.
    /// The source reader has already validated the four influences and their
    /// sum, so normalize once at load instead of repeating four additions and
    /// divisions for every animated frame.
    private struct PreparedVertex {
        let bindPoint: SIMD4<Float>
        let boneIndices: SIMD4<UInt32>
        let normalizedWeights: SIMD4<Float>
    }

    private let mesh: SceneMdlPuppetMesh
    private let rig: SceneMdlPuppetRig
    private let bindLocalMatrices: [simd_float4x4]
    private let bindPoses: [Pose]
    private let inverseBindWorldMatrices: [simd_float4x4]
    private let preparedAnimationsByID: [Int: PreparedAnimation]
    private let preparedVertices: [PreparedVertex]

    /// Launch-stable skeleton size used by the playback owner's reusable
    /// matrix storage.  The rig itself remains private so callers cannot
    /// bypass the evaluator's hierarchy and validation contracts.
    var boneCount: Int { rig.bones.count }

    init(
        mesh: SceneMdlPuppetMesh,
        rig: SceneMdlPuppetRig,
        additiveAnimations: [SceneMdlPuppetAnimation] = []
    ) throws {
        guard mesh.vertices.count == rig.vertexWeights.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        self.mesh = mesh
        self.rig = rig

        var localMatrices: [simd_float4x4] = []
        localMatrices.reserveCapacity(rig.bones.count)
        var poses: [Pose] = []
        poses.reserveCapacity(rig.bones.count)
        var bindWorldMatrices: [simd_float4x4] = []
        bindWorldMatrices.reserveCapacity(rig.bones.count)
        var inverseMatrices: [simd_float4x4] = []
        inverseMatrices.reserveCapacity(rig.bones.count)
        for (boneIndex, bone) in rig.bones.enumerated() {
            let local = Self.matrix(fromColumnMajor: bone.bindLocalMatrixColumnMajor)
            localMatrices.append(local)
            let world = bone.parentIndex >= 0
                ? bindWorldMatrices[bone.parentIndex] * local
                : local
            let determinant = simd_determinant(world)
            guard determinant.isFinite, abs(determinant) > 0.000001 else {
                throw ScenePuppetAnimationEvaluationFailure.singularBindMatrix(boneIndex)
            }
            guard let pose = Self.pose(from: local) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(boneIndex)
            }
            bindWorldMatrices.append(world)
            inverseMatrices.append(simd_inverse(world))
            poses.append(pose)
        }
        bindLocalMatrices = localMatrices
        bindPoses = poses
        inverseBindWorldMatrices = inverseMatrices

        var vertexData: [PreparedVertex] = []
        vertexData.reserveCapacity(mesh.vertices.count)
        for (vertexIndex, vertex) in mesh.vertices.enumerated() {
            let source = rig.vertexWeights[vertexIndex]
            let totalWeight = max(
                source.boneWeights.x + source.boneWeights.y
                    + source.boneWeights.z + source.boneWeights.w,
                Float.leastNonzeroMagnitude
            )
            vertexData.append(.init(
                // The animated skinning path intentionally keeps the
                // historical 2D bind point (z=0,w=1); z from the MDL record
                // is not part of the existing image-space contract.
                bindPoint: SIMD4<Float>(vertex.x, vertex.y, 0, 1),
                boneIndices: source.boneIndices,
                normalizedWeights: SIMD4<Float>(
                    source.boneWeights.x / totalWeight,
                    source.boneWeights.y / totalWeight,
                    source.boneWeights.z / totalWeight,
                    source.boneWeights.w / totalWeight
                )
            ))
        }
        preparedVertices = vertexData

        var preparedAnimations: [Int: PreparedAnimation] = [:]
        for animation in additiveAnimations {
            guard preparedAnimations[animation.id] == nil else {
                throw ScenePuppetAnimationEvaluationFailure.duplicateAdditiveAnimation(animation.id)
            }
            preparedAnimations[animation.id] = try Self.prepare(animation: animation, boneCount: rig.bones.count)
        }
        preparedAnimationsByID = preparedAnimations
    }

    /// Reports whether an authored clip produces the same pose at every
    /// frame.  Playback uses this load-time fact to keep the submission
    /// signature stable for static clips, avoiding repeated skinning and
    /// command encoding when scene time advances without any visual change.
    /// Unknown clips stay conservative and are treated as time-varying.
    func isTimeInvariant(animationID: Int) -> Bool {
        guard let prepared = preparedAnimationsByID[animationID] else {
            return false
        }
        return prepared.drivenBones.isEmpty
    }

    func deformedPositions(
        animation: SceneMdlPuppetAnimation,
        frameIndex: Int
    ) throws -> [SIMD2<Float>] {
        try deformedPositions(
            animation: animation,
            frameSample: FrameSample(frameA: frameIndex, frameB: frameIndex)
        )
    }

    func deformedPositions(
        animation: SceneMdlPuppetAnimation,
        frameSample: FrameSample
    ) throws -> [SIMD2<Float>] {
        if let prepared = preparedAnimationsByID[animation.id] {
            return try deformedPositions(
                localMatrices: try prepared.posesByBone.indices.map { boneIndex in
                    Self.matrix(from: try Self.sample(
                        prepared.posesByBone[boneIndex],
                        frameSample: frameSample
                    ))
                }
            )
        }
        return try deformedPositions(localMatrices: localMatrices(
            animation: animation,
            frameSample: frameSample
        ))
    }

    func deformedPositions(
        selection: ScenePuppetAnimationSelection,
        frameIndices: [Int?]
    ) throws -> [SIMD2<Float>] {
        try deformedPositions(
            selection: selection,
            frameSamples: frameIndices.map { index in
                index.map { FrameSample(frameA: $0, frameB: $0) }
            }
        )
    }

    func deformedPositions(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?]
    ) throws -> [SIMD2<Float>] {
        var positions = Array(
            repeating: SIMD2<Float>.zero,
            count: preparedVertices.count
        )
        try positions.withUnsafeMutableBufferPointer { buffer in
            try writeDeformedPositions(
                selection: selection,
                frameSamples: frameSamples,
                into: buffer
            )
        }
        return positions
    }

    /// Fills caller-owned positions using the same per-vertex accumulation order.
    func writeDeformedPositions(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        into output: UnsafeMutableBufferPointer<SIMD2<Float>>
    ) throws {
        var localMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: rig.bones.count
        )
        var skinMatrices = localMatrices
        try writeDeformedPositions(
            selection: selection,
            frameSamples: frameSamples,
            into: output,
            localMatricesScratch: &localMatrices,
            skinMatricesScratch: &skinMatrices
        )
    }

    /// Playback reuses both matrix arrays after its frame signature changes.
    func writeDeformedPositions(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        into output: UnsafeMutableBufferPointer<SIMD2<Float>>,
        localMatricesScratch: inout [simd_float4x4],
        skinMatricesScratch: inout [simd_float4x4],
        boneOverrides: [Int: simd_float4x4] = [:],
        worldBoneOverrides: [Int: simd_float4x4] = [:]
    ) throws {
        guard output.count >= preparedVertices.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        guard localMatricesScratch.count >= rig.bones.count,
              skinMatricesScratch.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        try writeLocalMatrices(
            selection: selection,
            frameSamples: frameSamples,
            into: &localMatricesScratch
        )
        for (index, matrix) in boneOverrides where rig.bones.indices.contains(index) {
            localMatricesScratch[index] = matrix
        }
        if !worldBoneOverrides.isEmpty {
            var worlds = Array(repeating: matrix_identity_float4x4, count: rig.bones.count)
            for bone in rig.bones {
                worlds[boneIndex(bone, in: rig)] = bone.parentIndex >= 0
                    ? worlds[bone.parentIndex] * localMatricesScratch[boneIndex(bone, in: rig)]
                    : localMatricesScratch[boneIndex(bone, in: rig)]
            }
            for (index, matrix) in worldBoneOverrides where rig.bones.indices.contains(index) {
                let parent = rig.bones[index].parentIndex
                localMatricesScratch[index] = parent >= 0
                    ? simd_inverse(worlds[parent]) * matrix : matrix
                worlds[index] = matrix
            }
        }
        try writeSkinMatrices(
            localMatrices: localMatricesScratch,
            into: &skinMatricesScratch
        )
        for vertexIndex in preparedVertices.indices {
            let point = deformedPoint(
                vertex: preparedVertices[vertexIndex],
                skinMatrices: skinMatricesScratch
            )
            output[vertexIndex] = point
        }
    }

    private func boneIndex(_ bone: SceneMdlPuppetRig.Bone, in rig: SceneMdlPuppetRig) -> Int {
        rig.bones.firstIndex { $0.name == bone.name && $0.parentIndex == bone.parentIndex } ?? 0
    }

    /// Computes only the origin-centred extent needed by load-time target
    /// sizing. Coverage callers do not need one temporary `SIMD2` per mesh
    /// vertex for every sampled animation pose; keeping this reduction beside
    /// the normal evaluator preserves the exact same skinning inputs while
    /// avoiding that allocation and copy traffic.
    func maxAbsDeformedPosition(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?]
    ) throws -> SIMD2<Float> {
        try maxAbsDeformedPosition(
            localMatrices: localMatrices(
                selection: selection,
                frameSamples: frameSamples
            )
        )
    }

    /// Returns a conservative extent for a batch of sampled poses.  The
    /// previous load path reduced every sampled pose over every vertex, which
    /// made a 35k vertex mesh spend seconds in repeated CPU skinning.  This
    /// pass scans each sampled skeleton once, keeps per-bone row norms and
    /// translations, then bounds all vertices with a weighted radius.  The
    /// bound is intentionally over-approximated, so animation remains fully
    /// inside the target even between samples.
    func conservativeMaxAbsDeformedPosition(
        selection: ScenePuppetAnimationSelection,
        frameSamplesBatch: [[FrameSample?]]
    ) throws -> SIMD2<Float> {
        guard frameSamplesBatch.isEmpty == false else {
            return try maxAbsDeformedPosition(
                selection: selection,
                frameSamples: selection.clips.map { _ in nil }
            )
        }
        var rowNormX = Array(repeating: Float.zero, count: rig.bones.count)
        var rowNormY = Array(repeating: Float.zero, count: rig.bones.count)
        var translationX = Array(repeating: Float.zero, count: rig.bones.count)
        var translationY = Array(repeating: Float.zero, count: rig.bones.count)
        for frameSamples in frameSamplesBatch {
            let matrices = try localMatrices(
                selection: selection,
                frameSamples: frameSamples
            )
            let skin = try skinMatrices(localMatrices: matrices)
            for boneIndex in skin.indices {
                let matrix = skin[boneIndex]
                let normX = hypot(matrix[0].x, matrix[1].x)
                let normY = hypot(matrix[0].y, matrix[1].y)
                let tx = abs(matrix[3].x)
                let ty = abs(matrix[3].y)
                guard normX.isFinite, normY.isFinite,
                      tx.isFinite, ty.isFinite else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
                }
                rowNormX[boneIndex] = max(rowNormX[boneIndex], normX)
                rowNormY[boneIndex] = max(rowNormY[boneIndex], normY)
                translationX[boneIndex] = max(translationX[boneIndex], tx)
                translationY[boneIndex] = max(translationY[boneIndex], ty)
            }
        }

        var maximum = SIMD2<Float>(repeating: 0)
        for vertex in preparedVertices {
            let radius = hypot(vertex.bindPoint.x, vertex.bindPoint.y)
            guard radius.isFinite else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            var bound = SIMD2<Float>.zero
            let weights = vertex.normalizedWeights
            let indices = vertex.boneIndices
            for influence in 0..<4 {
                let weight = weights[influence]
                guard weight > 0 else { continue }
                let boneIndex = Int(indices[influence])
                guard rig.bones.indices.contains(boneIndex) else {
                    throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
                }
                bound.x += weight * (rowNormX[boneIndex] * radius + translationX[boneIndex])
                bound.y += weight * (rowNormY[boneIndex] * radius + translationY[boneIndex])
            }
            maximum.x = max(maximum.x, bound.x)
            maximum.y = max(maximum.y, bound.y)
        }
        return maximum
    }

    private func localMatrices(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?]
    ) throws -> [simd_float4x4] {
        var output = bindLocalMatrices
        try writeLocalMatrices(selection: selection, frameSamples: frameSamples, into: &output)
        return output
    }

    private func writeLocalMatrices(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        into output: inout [simd_float4x4]
    ) throws {
        guard selection.clips.count == frameSamples.count,
              output.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        switch selection.composition {
        case .singleAbsolute:
            guard selection.clips.count == 1,
                  let frameSample = frameSamples[0] else {
                for boneIndex in rig.bones.indices {
                    output[boneIndex] = bindLocalMatrices[boneIndex]
                }
                return
            }
            let animation = selection.clips[0].animation
            guard animation.transformsByBone.count == rig.bones.count else {
                throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
            }
            for boneIndex in rig.bones.indices {
                output[boneIndex] = Self.matrix(from: try Self.sample(
                    animation.transformsByBone[boneIndex],
                    frameSample: frameSample
                ))
            }

        case .layered:
            for boneIndex in rig.bones.indices {
                var pose = bindPoses[boneIndex]
                // The first replacement, or first active additive track, owns the base pose.
                let baseClipIndex = Self.baseClipIndex(
                    boneIndex: boneIndex,
                    clips: selection.clips,
                    frameSamples: frameSamples,
                    preparedAnimationsByID: preparedAnimationsByID
                )
                if let baseClipIndex,
                   let baseSample = frameSamples[baseClipIndex],
                   let prepared = preparedAnimationsByID[
                       selection.clips[baseClipIndex].animation.id
                   ],
                   prepared.authoredBones.contains(boneIndex) {
                    pose = try Self.sample(
                        prepared.posesByBone[boneIndex],
                        frameSample: baseSample
                    )
                }
                for (clipIndex, clip) in selection.clips.enumerated() {
                    guard let frameSample = frameSamples[clipIndex],
                          let prepared = preparedAnimationsByID[clip.animation.id],
                          prepared.posesByBone.indices.contains(boneIndex),
                          prepared.authoredBones.contains(boneIndex)
                    else { continue }
                    if clipIndex == baseClipIndex { continue }
                    if clip.layer.additive == true {
                        pose = try Self.additive(
                            pose,
                            poses: prepared.posesByBone[boneIndex],
                            reference: prepared.referencePosesByBone[boneIndex],
                            frameSample: frameSample,
                            weight: clip.layer.blend ?? 1
                        )
                    }
                }
                output[boneIndex] = Self.matrix(from: pose)
            }
        }
    }

    private static func prepare(
        animation: SceneMdlPuppetAnimation,
        boneCount: Int
    ) throws -> PreparedAnimation {
        guard animation.transformsByBone.count == boneCount else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        var posesByBone: [[Pose]] = []
        posesByBone.reserveCapacity(boneCount)
        var references: [Pose] = []
        references.reserveCapacity(boneCount)
        var drivenBones: Set<Int> = []
        var authoredBones: Set<Int> = []
        for (boneIndex, track) in animation.transformsByBone.enumerated() {
            guard animation.frameCount >= 0,
                  track.isEmpty == false,
                  track.count == animation.frameCount + 1 else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            let poses = track.map(Self.pose(from:))
            guard poses.allSatisfy({ $0 != nil }) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            let unwrapped = poses.compactMap { $0 }
            let reference = unwrapped[0]
            references.append(reference)
            if unwrapped.contains(where: Self.isAuthoredPose) {
                authoredBones.insert(boneIndex)
            }
            if unwrapped.dropFirst().contains(where: {
                Self.maxDifference($0, reference) > 0.0001
            }) {
                drivenBones.insert(boneIndex)
            }
            posesByBone.append(unwrapped)
        }
        return PreparedAnimation(
            posesByBone: posesByBone,
            referencePosesByBone: references,
            drivenBones: drivenBones,
            authoredBones: authoredBones
        )
    }

    private func localMatrices(
        animation: SceneMdlPuppetAnimation,
        frameSample: FrameSample
    ) throws -> [simd_float4x4] {
        guard animation.transformsByBone.count == rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        return try animation.transformsByBone.map { track in
            Self.matrix(from: try Self.sample(track, frameSample: frameSample))
        }
    }

    private static func sample(
        _ poses: [Pose],
        frameSample: FrameSample
    ) throws -> Pose {
        guard poses.indices.contains(frameSample.frameA),
              poses.indices.contains(frameSample.frameB),
              frameSample.fraction.isFinite,
              frameSample.fraction >= 0,
              frameSample.fraction <= 1 else {
            throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameSample.frameA)
        }
        let a = poses[frameSample.frameA]
        let b = poses[frameSample.frameB]
        let t = frameSample.fraction
        let rotation = simd_normalize(simd_slerp(a.rotation, b.rotation, t))
        guard Self.isFinite(rotation.vector) else {
            throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameSample.frameA)
        }
        return Pose(
            translation: a.translation + (b.translation - a.translation) * t,
            rotation: rotation,
            scale: a.scale + (b.scale - a.scale) * t
        )
    }

    private static func sample(
        _ transforms: [SceneMdlPuppetAnimation.Transform],
        frameSample: FrameSample
    ) throws -> SceneMdlPuppetAnimation.Transform {
        guard transforms.indices.contains(frameSample.frameA),
              transforms.indices.contains(frameSample.frameB),
              frameSample.fraction.isFinite,
              frameSample.fraction >= 0,
              frameSample.fraction <= 1 else {
            throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameSample.frameA)
        }
        let a = transforms[frameSample.frameA]
        let b = transforms[frameSample.frameB]
        let t = frameSample.fraction
        return .init(
            translation: a.translation + (b.translation - a.translation) * t,
            rotation: a.rotation + (b.rotation - a.rotation) * t,
            scale: a.scale + (b.scale - a.scale) * t
        )
    }

    private static func baseClipIndex(
        boneIndex: Int,
        clips: [ScenePuppetAnimationSelection.Clip],
        frameSamples: [FrameSample?],
        preparedAnimationsByID: [Int: PreparedAnimation]
    ) -> Int? {
        // A replacement (opaque) layer wins for a bone.  The authored layer
        // order is retained; later replacement layers do not silently replace
        // the first owner.  This is also the rule used when an autosorted
        // stack contains multiple replacement clips.
        for index in clips.indices {
            guard frameSamples[index] != nil,
                  clips[index].layer.additive == false,
                  let prepared = preparedAnimationsByID[clips[index].animation.id],
                  prepared.authoredBones.contains(boneIndex) else { continue }
            return index
        }
        // With no replacement owner, the first visible additive layer is the
        // base anchor.  Its own frame-0 offset is part of the authored pose;
        // other additive layers are applied as deltas from their references.
        for index in clips.indices {
            guard frameSamples[index] != nil,
                  clips[index].layer.additive == true,
                  (clips[index].layer.blend ?? 0) > 0,
                  let prepared = preparedAnimationsByID[clips[index].animation.id],
                  prepared.authoredBones.contains(boneIndex) else { continue }
            return index
        }
        return nil
    }

    private static func additive(
        _ current: Pose,
        poses: [Pose],
        reference: Pose,
        frameSample: FrameSample,
        weight: Double
    ) throws -> Pose {
        guard poses.indices.contains(frameSample.frameA),
              poses.indices.contains(frameSample.frameB),
              frameSample.fraction.isFinite,
              frameSample.fraction >= 0,
              frameSample.fraction <= 1 else {
            throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameSample.frameA)
        }
        let a = poses[frameSample.frameA]
        let b = poses[frameSample.frameB]
        let w = Float(min(1, max(0, weight.isFinite ? weight : 0)))
        let t = frameSample.fraction
        let deltaA = a.rotation * reference.rotation.inverse
        let deltaB = b.rotation * reference.rotation.inverse
        let deltaRotation = simd_normalize(simd_slerp(deltaA, deltaB, t))
        return Pose(
            translation: current.translation + (
                a.translation + (b.translation - a.translation) * t - reference.translation
            ) * w,
            rotation: simd_normalize(
                current.rotation * simd_slerp(identityPose.rotation, deltaRotation, w)
            ),
            scale: current.scale + (
                a.scale + (b.scale - a.scale) * t - reference.scale
            ) * w
        )
    }

    private static let identityPose = Pose(
        translation: .zero,
        rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)),
        scale: SIMD3(repeating: 1)
    )

    private static func isAuthoredPose(_ pose: Pose) -> Bool {
        maxDifference(pose, identityPose) > 0.0001
    }

    private func deformedPositions(
        localMatrices: [simd_float4x4]
    ) throws -> [SIMD2<Float>] {
        let skinMatrices = try skinMatrices(localMatrices: localMatrices)
        return preparedVertices.indices.map { vertexIndex in
            deformedPoint(
                vertex: preparedVertices[vertexIndex],
                skinMatrices: skinMatrices
            )
        }
    }

    private func maxAbsDeformedPosition(
        localMatrices: [simd_float4x4]
    ) throws -> SIMD2<Float> {
        let skinMatrices = try skinMatrices(localMatrices: localMatrices)
        var maximum = SIMD2<Float>(repeating: 0)
        for vertex in preparedVertices {
            let point = deformedPoint(vertex: vertex, skinMatrices: skinMatrices)
            maximum.x = max(maximum.x, abs(point.x))
            maximum.y = max(maximum.y, abs(point.y))
        }
        return maximum
    }

    @inline(__always)
    private func deformedPoint(
        vertex: PreparedVertex,
        skinMatrices: [simd_float4x4]
    ) -> SIMD2<Float> {
        var point = SIMD2<Float>.zero
        let bindX = vertex.bindPoint.x
        let bindY = vertex.bindPoint.y
        let weight0 = vertex.normalizedWeights.x
        if weight0 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.x)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY + matrix[3].y
            ) * weight0
        }
        let weight1 = vertex.normalizedWeights.y
        if weight1 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.y)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY + matrix[3].y
            ) * weight1
        }
        let weight2 = vertex.normalizedWeights.z
        if weight2 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.z)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY + matrix[3].y
            ) * weight2
        }
        let weight3 = vertex.normalizedWeights.w
        if weight3 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.w)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY + matrix[3].y
            ) * weight3
        }
        return point
    }

    private func skinMatrices(
        localMatrices: [simd_float4x4]
    ) throws -> [simd_float4x4] {
        var result = Array(
            repeating: matrix_identity_float4x4,
            count: rig.bones.count
        )
        try writeSkinMatrices(localMatrices: localMatrices, into: &result)
        return result
    }

    /// Build parent-first world transforms before converting the same storage
    /// to skin matrices, so children never consume an inverse-bind transform.
    private func writeSkinMatrices(
        localMatrices: [simd_float4x4],
        into output: inout [simd_float4x4]
    ) throws {
        guard localMatrices.count >= rig.bones.count,
              output.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        for (boneIndex, bone) in rig.bones.enumerated() {
            let local = localMatrices[boneIndex]
            output[boneIndex] = bone.parentIndex >= 0
                ? output[bone.parentIndex] * local
                : local
        }
        for boneIndex in rig.bones.indices {
            output[boneIndex] *= inverseBindWorldMatrices[boneIndex]
        }
    }

    private static func matrix(fromColumnMajor values: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }

    private static func matrix(
        from transform: SceneMdlPuppetAnimation.Transform
    ) -> simd_float4x4 {
        SceneMatrix.translation(transform.translation)
            * SceneMatrix.eulerXYZ(transform.rotation)
            * SceneMatrix.scale(transform.scale)
    }

    private static func matrix(from pose: Pose) -> simd_float4x4 {
        SceneMatrix.translation(pose.translation)
            * simd_float4x4(pose.rotation)
            * SceneMatrix.scale(pose.scale)
    }

    private static func pose(
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

    private static func pose(from matrix: simd_float4x4) -> Pose? {
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

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private static func maxDifference(_ lhs: Pose, _ rhs: Pose) -> Float {
        max(
            max(
                simd_length(lhs.translation - rhs.translation),
                simd_length(lhs.scale - rhs.scale)
            ),
            simd_length(lhs.rotation.vector - rhs.rotation.vector)
        )
    }

    private static func maxDifference(
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
