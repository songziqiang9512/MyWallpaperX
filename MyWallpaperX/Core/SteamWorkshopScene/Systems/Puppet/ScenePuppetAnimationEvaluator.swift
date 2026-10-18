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
        let alphaByBone: [[Float]]?
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

    let rig: SceneMdlPuppetRig
    private let referenceLocalMatrices: [simd_float4x4]
    private let referencePoses: [Pose]
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
        inverseBindWorldMatrices = inverseMatrices
        if let reference = rig.referenceLocalMatricesColumnMajor {
            guard reference.count == rig.bones.count else {
                throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
            }
            var referenceMatrices: [simd_float4x4] = []
            var preparedReferencePoses: [Pose] = []
            referenceMatrices.reserveCapacity(reference.count)
            preparedReferencePoses.reserveCapacity(reference.count)
            for (boneIndex, values) in reference.enumerated() {
                guard values.count == 16, values.allSatisfy(\.isFinite) else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidReferenceTransform(boneIndex)
                }
                let local = Self.matrix(fromColumnMajor: values)
                guard let pose = Self.pose(from: local) else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidReferenceTransform(boneIndex)
                }
                // A reference must survive the existing TRS projection. In particular,
                // do not approximate shear even when no active clip would expose it.
                let reconstructed = Self.matrix(from: pose)
                for column in 0..<4 {
                    for row in 0..<4 {
                        let value = local[column][row]
                        let rebuilt = reconstructed[column][row]
                        let tolerance: Float = 0.0001 * max(1, abs(value), abs(rebuilt))
                        guard abs(value - rebuilt) <= tolerance else {
                            throw ScenePuppetAnimationEvaluationFailure.invalidReferenceTransform(boneIndex)
                        }
                    }
                }
                referenceMatrices.append(local)
                preparedReferencePoses.append(pose)
            }
            referenceLocalMatrices = referenceMatrices
            referencePoses = preparedReferencePoses
        } else {
            referenceLocalMatrices = localMatrices
            referencePoses = poses
        }

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
                // Preserve source depth until skinning: X/Y bone rotation
                // can project it into the final image-space position.
                bindPoint: SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1),
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
        blends: [Double]? = nil,
        into output: inout [Float],
        boneScratch: inout [Float]
    ) throws {
        guard output.count == preparedVertices.count,
              boneScratch.count == boneCount,
              frameSamples.count == selection.clips.count,
              blends == nil || blends?.count == selection.clips.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        for bone in boneScratch.indices { boneScratch[bone] = 1 }
        var contributor: (index: Int, tracks: [[Float]])?
        for (index, clip) in selection.clips.enumerated() {
            guard let prepared = preparedAnimationsByID[clip.animation.id] else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            if prepared.hasAlphaContribution, let tracks = prepared.alphaByBone {
                // Count all prepared resources, including a currently hidden
                // clip. A changing visibility cannot admit a conflicting pair.
                guard contributor == nil else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
                }
                contributor = (index, tracks)
            }
        }
        if let (clipIndex, tracks) = contributor, let frame = frameSamples[clipIndex] {
            guard tracks.count == boneCount,
                  frame.fraction.isFinite, (0...1).contains(frame.fraction) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frame.frameA)
            }
            let weight = blends?[clipIndex] ?? selection.clips[clipIndex].layer.blend ?? 1
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
        boneOverrides: [Int: simd_float4x4] = [:],
        blends: [Double]? = nil
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
            blends: blends,
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
        }
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { column in
                column.x.isFinite && column.y.isFinite
                    && column.z.isFinite && column.w.isFinite
            }
    }

    private func localMatrices(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?]
    ) throws -> [simd_float4x4] {
        var output = referenceLocalMatrices
        try writeLocalMatrices(selection: selection, frameSamples: frameSamples, into: &output)
        return output
    }

    func writeLocalMatrices(
        selection: ScenePuppetAnimationSelection,
        frameSamples: [FrameSample?],
        blends: [Double]? = nil,
        into output: inout [simd_float4x4]
    ) throws {
        guard selection.clips.count == frameSamples.count,
              blends == nil || blends?.count == selection.clips.count,
              output.count >= rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        switch selection.composition {
        case .singleAbsolute:
            guard selection.clips.count == 1,
                  let frameSample = frameSamples[0] else {
                for boneIndex in rig.bones.indices {
                    output[boneIndex] = referenceLocalMatrices[boneIndex]
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
                    sampled, relativeTo: referencePoses[boneIndex], to: referencePoses[boneIndex],
                    weight: blends?[0] ?? selection.clips[0].layer.blend ?? 1
                ))
            }

        case .layered:
            for boneIndex in rig.bones.indices {
                var pose = referencePoses[boneIndex]
                // Preserve the first opaque owner; every additive shares the rig reference.
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
                        relativeTo: referencePoses[boneIndex], to: pose,
                        weight: blends?[baseClipIndex] ?? selection.clips[baseClipIndex].layer.blend ?? 1
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
                            relativeTo: referencePoses[boneIndex], to: pose,
                            weight: blends?[clipIndex] ?? clip.layer.blend ?? 1
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
        if let tracks = animation.alphaByBone {
            guard tracks.count == boneCount,
                  tracks.allSatisfy({ track in
                      track.count == animation.frameCount + 1
                          && track.allSatisfy { $0.isFinite && (0...1.0001).contains($0) }
                  }) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
            }
            alphaVaries = tracks.contains { track in
                track.dropFirst().contains { $0 != track[0] }
            }
        }
        return PreparedAnimation(
            posesByBone: posesByBone,
            drivenBones: drivenBones,
            authoredBones: authoredBones,
            alphaVaries: alphaVaries,
            hasAlphaContribution: animation.hasAlphaContribution,
            alphaByBone: animation.alphaByBone
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

    @inline(__always)
    private func deformedPoint(
        vertex: PreparedVertex,
        skinMatrices: [simd_float4x4]
    ) throws -> SIMD2<Float> {
        var point = SIMD2<Float>.zero
        let bindX = vertex.bindPoint.x
        let bindY = vertex.bindPoint.y
        let bindZ = vertex.bindPoint.z
        let weight0 = vertex.normalizedWeights.x
        if weight0 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.x)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY
                    + matrix[2].x * bindZ + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY
                    + matrix[2].y * bindZ + matrix[3].y
            ) * weight0
        }
        let weight1 = vertex.normalizedWeights.y
        if weight1 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.y)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY
                    + matrix[2].x * bindZ + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY
                    + matrix[2].y * bindZ + matrix[3].y
            ) * weight1
        }
        let weight2 = vertex.normalizedWeights.z
        if weight2 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.z)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY
                    + matrix[2].x * bindZ + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY
                    + matrix[2].y * bindZ + matrix[3].y
            ) * weight2
        }
        let weight3 = vertex.normalizedWeights.w
        if weight3 > 0 {
            let matrix = skinMatrices[Int(vertex.boneIndices.w)]
            point += SIMD2(
                matrix[0].x * bindX + matrix[1].x * bindY
                    + matrix[2].x * bindZ + matrix[3].x,
                matrix[0].y * bindX + matrix[1].y * bindY
                    + matrix[2].y * bindZ + matrix[3].y
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
