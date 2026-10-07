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

    struct Pose {
        var translation: SIMD3<Float>
        var rotation: simd_quatf
        var scale: SIMD3<Float>
    }

    private struct PreparedAnimation {
        let posesByBone: [[Pose]]
        let drivenBones: Set<Int>
        let authoredBones: Set<Int>
        let alphaVaries: Bool
        let hasAlphaContribution: Bool
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
    let rig: SceneMdlPuppetRig
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
        return prepared.drivenBones.isEmpty && !prepared.alphaVaries
    }

    func hasAlphaContribution(animationID: Int) -> Bool {
        preparedAnimationsByID[animationID]?.hasAlphaContribution == true
    }

    /// MDLA alpha is already expressed per bone; applying parent opacity again
    /// would darken descendants. Reuse prepared skin weights for vertex coverage.
    func writeVertexCoverages(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        into output: inout [Float],
        boneScratch: inout [Float]
    ) throws {
        guard output.count == preparedVertices.count,
              boneScratch.count == boneCount,
              frameSamples.count == selection.clips.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        for bone in boneScratch.indices { boneScratch[bone] = 1 }
        if let clipIndex = selection.clips.indices.first(where: {
            hasAlphaContribution(animationID: selection.clips[$0].animation.id) && frameSamples[$0] != nil
        }), let frame = frameSamples[clipIndex],
           let tracks = selection.clips[clipIndex].animation.alphaByBone {
            // The selector admits a single clip when consequential alpha is present.
            guard selection.clips.count == 1, tracks.count == boneCount,
                  frame.fraction.isFinite, (0...1).contains(frame.fraction) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frame.frameA)
            }
            let weight = selection.clips[clipIndex].layer.blend ?? 1
            guard weight.isFinite, weight >= 0 else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBlend
            }
            for bone in tracks.indices {
                let track = tracks[bone]
                guard track.indices.contains(frame.frameA), track.indices.contains(frame.frameB) else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frame.frameA)
                }
                let sample = track[frame.frameA]
                    + (track[frame.frameB] - track[frame.frameA]) * frame.fraction
                guard sample.isFinite else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frame.frameA)
                }
                boneScratch[bone] = Float(min(1, max(0, 1 + (Double(sample) - 1) * weight)))
            }
        }
        for (index, vertex) in preparedVertices.enumerated() {
            var coverage: Float = 0
            for influence in 0..<4 where vertex.normalizedWeights[influence] > 0 {
                coverage += vertex.normalizedWeights[influence]
                    * boneScratch[Int(vertex.boneIndices[influence])]
            }
            output[index] = min(1, max(0, coverage))
        }
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
        into output: UnsafeMutableBufferPointer<SIMD2<Float>>,
        localMatricesScratch: inout [simd_float4x4],
        skinMatricesScratch: inout [simd_float4x4]
    ) throws {
        var worldMatricesScratch = Array(
            repeating: matrix_identity_float4x4,
            count: rig.bones.count
        )
        try writeDeformedPositions(
            selection: selection,
            frameSamples: frameSamples,
            into: output,
            localMatricesScratch: &localMatricesScratch,
            skinMatricesScratch: &skinMatricesScratch,
            worldMatricesScratch: &worldMatricesScratch
        )
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
        worldMatricesScratch: inout [simd_float4x4],
        boneOverrides: [Int: simd_float4x4] = [:]
    ) throws {
        guard output.count >= preparedVertices.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        guard localMatricesScratch.count >= rig.bones.count,
              skinMatricesScratch.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        guard worldMatricesScratch.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        try writeLocalMatrices(
            selection: selection,
            frameSamples: frameSamples,
            into: &localMatricesScratch
        )
        try applyOverrides(
            boneOverrides,
            to: &localMatricesScratch,
            worlds: &worldMatricesScratch
        )
        try ScenePuppetSkinMatrixProjection.write(
            worldMatrices: worldMatricesScratch,
            bones: rig.bones,
            inverseBindWorldMatrices: inverseBindWorldMatrices,
            into: &skinMatricesScratch
        )
        for vertexIndex in preparedVertices.indices {
            let point = try deformedPoint(
                vertex: preparedVertices[vertexIndex],
                skinMatrices: skinMatricesScratch
            )
            output[vertexIndex] = point
        }
    }

    func applyOverrides(
        _ overrides: [Int: simd_float4x4],
        to locals: inout [simd_float4x4],
        worlds: inout [simd_float4x4]
    ) throws {
        for (index, matrix) in overrides {
            guard rig.bones.indices.contains(index) else {
                throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
            }
            guard Self.isFinite(matrix) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(index)
            }
            locals[index] = matrix
        }
        // The VM boundary already resolves all writes to parent-relative
        // matrices. Authored parent-first order is the only hierarchy pass.
        for (index, bone) in rig.bones.enumerated() {
            let local = locals[index]
            guard Self.isFinite(local) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(index)
            }
            worlds[index] = bone.parentIndex >= 0
                ? worlds[bone.parentIndex] * local : local
            guard Self.isFinite(worlds[index]) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidBindTransform(index)
            }
            let determinant = simd_determinant(worlds[index])
            guard determinant.isFinite, abs(determinant) > 0.000001 else {
                throw ScenePuppetAnimationEvaluationFailure.singularBindMatrix(index)
            }
        }
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite
                    && column.z.isFinite && column.w.isFinite
            }
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

    func writeLocalMatrices(
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
                guard let sampled = Self.pose(from: try Self.sample(
                    animation.transformsByBone[boneIndex], frameSample: frameSample
                )) else { throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameSample.frameA) }
                output[boneIndex] = Self.matrix(from: try Self.applying(
                    sampled, relativeTo: bindPoses[boneIndex], to: bindPoses[boneIndex],
                    weight: selection.clips[0].layer.blend ?? 1
                ))
            }

        case .layered:
            for boneIndex in rig.bones.indices {
                var pose = bindPoses[boneIndex]
                // Preserve the first opaque owner; every additive uses the same bind reference.
                let baseClipIndex = Self.opaqueClipIndex(
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
                    pose = try Self.applying(
                        Self.sample(prepared.posesByBone[boneIndex], frameSample: baseSample),
                        relativeTo: bindPoses[boneIndex], to: pose,
                        weight: selection.clips[baseClipIndex].layer.blend ?? 1
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
                        pose = try Self.applying(
                            Self.sample(prepared.posesByBone[boneIndex], frameSample: frameSample),
                            relativeTo: bindPoses[boneIndex], to: pose,
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
        var alphaVaries = false
        var hasAlphaContribution = false
        if let tracks = animation.alphaByBone {
            guard tracks.count == boneCount,
                  tracks.allSatisfy({ track in
                      track.count == animation.frameCount + 1
                          && track.allSatisfy { $0.isFinite && (0...1.0001).contains($0) }
                  }) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            hasAlphaContribution = tracks.contains { $0.contains { $0 != 1 } }
            alphaVaries = tracks.contains { track in
                track.dropFirst().contains { $0 != track[0] }
            }
        }
        return PreparedAnimation(
            posesByBone: posesByBone,
            drivenBones: drivenBones,
            authoredBones: authoredBones,
            alphaVaries: alphaVaries,
            hasAlphaContribution: hasAlphaContribution
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

    private static func opaqueClipIndex(
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
        return nil
    }

    /// Static weight mixing is distinct from time interpolation. A shortest-
    /// hemisphere normalized linear quaternion mix supports authored extrapolation.
    /// Use a local delta on the right so bind * delta at weight 1 equals sample,
    /// including when bind and sample rotations do not commute.
    private static func applying(
        _ sampled: Pose, relativeTo reference: Pose, to current: Pose, weight: Double
    ) throws -> Pose {
        let w = Float(weight)
        guard weight.isFinite, weight >= 0, w.isFinite else {
            throw ScenePuppetAnimationEvaluationFailure.invalidBlend
        }
        if w == 0 { return current }
        var delta = (reference.rotation.inverse * sampled.rotation).vector
        if delta.w < 0 { delta = -delta }
        let identity = identityPose.rotation.vector
        let weighted = identity + (delta - identity) * w
        let normSquared = simd_length_squared(weighted)
        guard normSquared.isFinite, normSquared > 0 else {
            throw ScenePuppetAnimationEvaluationFailure.invalidBlend
        }
        let result = Pose(
            translation: current.translation + (sampled.translation - reference.translation) * w,
            rotation: simd_normalize(current.rotation * simd_quatf(vector: weighted / sqrt(normSquared))),
            scale: current.scale + (sampled.scale - reference.scale) * w
        )
        guard isFinite(result.translation), isFinite(result.rotation.vector), isFinite(result.scale) else {
            throw ScenePuppetAnimationEvaluationFailure.invalidBlend
        }
        return result
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
        return try preparedVertices.indices.map { vertexIndex in
            try deformedPoint(
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
            let point = try deformedPoint(vertex: vertex, skinMatrices: skinMatrices)
            maximum.x = max(maximum.x, abs(point.x))
            maximum.y = max(maximum.y, abs(point.y))
        }
        return maximum
    }

    @inline(__always)
    private func deformedPoint(
        vertex: PreparedVertex,
        skinMatrices: [simd_float4x4]
    ) throws -> SIMD2<Float> {
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
        guard point.x.isFinite, point.y.isFinite else {
            throw ScenePuppetAnimationEvaluationFailure.invalidDeformedVertex
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
        try ScenePuppetSkinMatrixProjection.write(
            localMatrices: localMatrices,
            bones: rig.bones,
            inverseBindWorldMatrices: inverseBindWorldMatrices,
            into: &result
        )
        return result
    }

}
