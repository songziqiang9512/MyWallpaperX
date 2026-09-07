import simd

struct ScenePuppetAnimationSelection {
    enum Composition: String {
        case singleAbsolute = "single-absolute"
        // More than one authored layer is evaluated in scene order; layered
        // clips may be absolute, additive, or both.
        case layered = "layered"
    }

    struct Clip {
        let layer: ScenePuppetAnimationLayer
        let animation: SceneMdlPuppetAnimation
    }

    let clips: [Clip]
    let composition: Composition
}

enum ScenePuppetAnimationSelectionFailure: Error, CustomStringConvertible, Equatable {
    case unresolvedVisibility(Int?)
    case malformedVisibility(Int?)
    case unsupportedLayer(Int?)
    case unknownAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .unresolvedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has property-bound visibility without a stable layer id"
        case .malformedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has no static visibility"
        case .unsupportedLayer(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") is outside the bounded playback profile"
        case .unknownAnimation(let id):
            return "animation id \(id) is absent from the version-matched MDLA block"
        }
    }
}

enum ScenePuppetAnimationSelector {
    static func select(
        layers: [ScenePuppetAnimationLayer],
        animationSet: SceneMdlPuppetAnimationSet
    ) -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        var clips: [ScenePuppetAnimationSelection.Clip] = []
        for layer in layers {
            guard let visible = layer.visible else {
                return .failure(.malformedVisibility(layer.id))
            }
            guard visible || layer.visibilityBinding != nil else { continue }
            guard let animationID = layer.animationID,
                  layer.additive != nil,
                  let blend = layer.blend,
                  blend.isFinite,
                  blend > 0,
                  blend <= 1,
                  // Omitted blend edges are the authored false defaults; an
                  // explicit true still stays outside this bounded profile.
                  layer.blendIn != true,
                  layer.blendOut != true,
                  let rate = layer.rate,
                  rate.isFinite,
                  rate > 0 else {
                return .failure(.unsupportedLayer(layer.id))
            }
            guard layer.visibilityBinding == nil || layer.id != nil else {
                return .failure(.unresolvedVisibility(layer.id))
            }
            guard let animation = animationSet.animations.first(where: { $0.id == animationID }) else {
                return .failure(.unknownAnimation(animationID))
            }
            clips.append(.init(layer: layer, animation: animation))
        }
        guard clips.isEmpty == false else { return .success(nil) }
        if clips.count == 1, clips[0].layer.additive == false {
            return .success(.init(clips: clips, composition: .singleAbsolute))
        }
        // Wallpaper Engine stacks visible puppet layers bottom-to-top.  An
        // additive layer contributes its frame-relative delta while an
        // opaque layer blends its absolute pose over the running pose.  Keep
        // the complete authored order instead of rejecting mixed or
        // overlapping layers; the evaluator still validates every track and
        // fails closed on malformed data.
        return .success(.init(clips: clips, composition: .layered))
    }
}

enum ScenePuppetAnimationEvaluationFailure: Error, CustomStringConvertible, Equatable {
    case boneCountMismatch
    case singularBindMatrix(Int)
    case invalidBindTransform(Int)
    case invalidFrame(Int)
    case duplicateAdditiveAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .boneCountMismatch:
            return "puppet mesh, rig, and animation bone counts do not match"
        case .singularBindMatrix(let index):
            return "puppet bind world matrix \(index) is singular"
        case .invalidBindTransform(let index):
            return "puppet bind local transform \(index) is not decomposable"
        case .invalidFrame(let index):
            return "puppet animation frame \(index) is out of bounds"
        case .duplicateAdditiveAnimation(let animationID):
            return "additive animation \(animationID) is selected more than once"
        }
    }
}

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

    private let mesh: SceneMdlPuppetMesh
    private let rig: SceneMdlPuppetRig
    private let bindLocalMatrices: [simd_float4x4]
    private let bindPoses: [Pose]
    private let inverseBindWorldMatrices: [simd_float4x4]
    private let preparedAnimationsByID: [Int: PreparedAnimation]

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

        var preparedAnimations: [Int: PreparedAnimation] = [:]
        for animation in additiveAnimations {
            guard preparedAnimations[animation.id] == nil else {
                throw ScenePuppetAnimationEvaluationFailure.duplicateAdditiveAnimation(animation.id)
            }
            preparedAnimations[animation.id] = try Self.prepare(animation: animation, boneCount: rig.bones.count)
        }
        preparedAnimationsByID = preparedAnimations
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
        guard selection.clips.count == frameSamples.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        switch selection.composition {
        case .singleAbsolute:
            guard selection.clips.count == 1,
                  let frameSample = frameSamples[0] else {
                return try deformedPositions(localMatrices: bindLocalMatrices)
            }
            return try deformedPositions(
                animation: selection.clips[0].animation,
                frameSample: frameSample
            )
        case .layered:
            var localMatrices: [simd_float4x4] = []
            localMatrices.reserveCapacity(rig.bones.count)
            for boneIndex in rig.bones.indices {
                var pose = bindPoses[boneIndex]
                // A replacement layer owns the base pose for each bone.  If
                // the authored stack contains only additive clips, the first
                // active additive track is promoted to that base; otherwise
                // its frame-0 offset would be discarded and the whole puppet
                // would be displaced toward bind space.
                let baseClipIndex = Self.baseClipIndex(
                    boneIndex: boneIndex,
                    clips: selection.clips,
                    frameSamples: frameSamples,
                    preparedAnimationsByID: preparedAnimationsByID
                )
                if let baseClipIndex,
                   let baseSample = frameSamples[baseClipIndex],
                   let prepared = preparedAnimationsByID[selection.clips[baseClipIndex].animation.id],
                   prepared.authoredBones.contains(boneIndex) {
                    pose = try Self.sample(
                        prepared.posesByBone[boneIndex],
                        frameSample: baseSample
                    )
                }

                for (clipIndex, clip) in selection.clips.enumerated() {
                    guard let frameSample = frameSamples[clipIndex],
                          let prepared = preparedAnimationsByID[clip.animation.id],
                          prepared.posesByBone.indices.contains(boneIndex) else {
                        continue
                    }
                    guard prepared.authoredBones.contains(boneIndex) else { continue }
                    // The base replacement (including a promoted additive
                    // layer) is already represented by `pose`.
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
                localMatrices.append(Self.matrix(from: pose))
            }
            return try deformedPositions(localMatrices: localMatrices)
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
        guard localMatrices.count == rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        var animatedWorldMatrices: [simd_float4x4] = []
        animatedWorldMatrices.reserveCapacity(rig.bones.count)
        for (boneIndex, bone) in rig.bones.enumerated() {
            let local = localMatrices[boneIndex]
            let world = bone.parentIndex >= 0
                ? animatedWorldMatrices[bone.parentIndex] * local
                : local
            animatedWorldMatrices.append(world)
        }
        let skinMatrices = zip(animatedWorldMatrices, inverseBindWorldMatrices).map(*)

        return mesh.vertices.indices.map { vertexIndex in
            let vertex = mesh.vertices[vertexIndex]
            let weights = rig.vertexWeights[vertexIndex]
            let bindPoint = SIMD4<Float>(vertex.x, vertex.y, 0, 1)
            let totalWeight = max(
                weights.boneWeights.x + weights.boneWeights.y
                    + weights.boneWeights.z + weights.boneWeights.w,
                Float.leastNonzeroMagnitude
            )
            var point = SIMD4<Float>.zero
            for influence in 0..<4 {
                let weight = weights.boneWeights[influence] / totalWeight
                guard weight > 0 else { continue }
                point += (skinMatrices[Int(weights.boneIndices[influence])] * bindPoint) * weight
            }
            return SIMD2(point.x, point.y)
        }
    }

    static func frameSample(
        sceneTime: Double,
        rate: Double,
        animation: SceneMdlPuppetAnimation
    ) -> FrameSample {
        guard sceneTime.isFinite, rate.isFinite, rate > 0,
              animation.framesPerSecond.isFinite,
              animation.framesPerSecond > 0,
              animation.frameCount > 0 else {
            return FrameSample(frameA: 0, frameB: 0)
        }
        let count = animation.frameCount
        let phase = max(0, sceneTime) * rate * Double(animation.framesPerSecond)
        guard phase.isFinite else {
            return FrameSample(frameA: 0, frameB: 0)
        }

        func linearSample(_ q: Double) -> FrameSample {
            let bounded = min(Double(count), max(0, q))
            if bounded >= Double(count) {
                return FrameSample(frameA: count - 1, frameB: count, fraction: 1)
            }
            let a = min(count - 1, max(0, Int(bounded.rounded(.down))))
            let fraction = Float(min(1, max(0, bounded - Double(a))))
            return FrameSample(frameA: a, frameB: a + 1, fraction: fraction)
        }

        func positiveRemainder(_ value: Double, _ period: Double) -> Double {
            let remainder = value.truncatingRemainder(dividingBy: period)
            return remainder >= 0 ? remainder : remainder + period
        }

        switch animation.mode {
        case "single":
            return linearSample(phase)
        case "mirror":
            let period = Double(count) * 2
            let q = positiveRemainder(phase, period)
            let aRaw = min(count * 2 - 1, max(0, Int(q.rounded(.down))))
            let fraction = Float(min(1, max(0, q - Double(aRaw))))
            func mirrorIndex(_ index: Int) -> Int {
                index <= count ? index : count * 2 - index
            }
            return FrameSample(
                frameA: mirrorIndex(aRaw),
                frameB: mirrorIndex(aRaw + 1),
                fraction: fraction
            )
        default:
            let q = positiveRemainder(phase, Double(count))
            return linearSample(q)
        }
    }

    static func frameIndex(
        sceneTime: Double,
        rate: Double,
        animation: SceneMdlPuppetAnimation
    ) -> Int {
        frameSample(sceneTime: sceneTime, rate: rate, animation: animation).frameA
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
