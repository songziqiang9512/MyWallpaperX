import simd

struct ScenePuppetAnimationSelection {
    enum Composition: String {
        case singleAbsolute = "single-absolute"
        case disjointAdditive = "disjoint-additive"
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
    case unsupportedMixingProfile
    case unknownAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .unresolvedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has property-bound visibility without a stable layer id"
        case .malformedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has no static visibility"
        case .unsupportedLayer(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") is outside the bounded playback profile"
        case .unsupportedMixingProfile:
            return "animation layers mix opaque and additive clips outside the bounded profile"
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
                  layer.blend == 1,
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
        guard clips.allSatisfy({ $0.layer.additive == true }) else {
            return .failure(.unsupportedMixingProfile)
        }
        return .success(.init(clips: clips, composition: .disjointAdditive))
    }
}

enum ScenePuppetAnimationEvaluationFailure: Error, CustomStringConvertible, Equatable {
    case boneCountMismatch
    case singularBindMatrix(Int)
    case invalidFrame(Int)
    case additiveReferenceMismatch(animationID: Int, boneIndex: Int)
    case overlappingAdditiveBone(Int)
    case duplicateAdditiveAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .boneCountMismatch:
            return "puppet mesh, rig, and animation bone counts do not match"
        case .singularBindMatrix(let index):
            return "puppet bind world matrix \(index) is singular"
        case .invalidFrame(let index):
            return "puppet animation frame \(index) is out of bounds"
        case let .additiveReferenceMismatch(animationID, boneIndex):
            return "additive animation \(animationID) bone \(boneIndex) does not start at bind pose"
        case .overlappingAdditiveBone(let boneIndex):
            return "additive animation layers both drive bone \(boneIndex)"
        case .duplicateAdditiveAnimation(let animationID):
            return "additive animation \(animationID) is selected more than once"
        }
    }
}

struct ScenePuppetAnimationEvaluator {
    private let mesh: SceneMdlPuppetMesh
    private let rig: SceneMdlPuppetRig
    private let bindLocalMatrices: [simd_float4x4]
    private let inverseBindWorldMatrices: [simd_float4x4]
    private let additiveBonesByAnimationID: [Int: [Int]]

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
            bindWorldMatrices.append(world)
            inverseMatrices.append(simd_inverse(world))
        }
        bindLocalMatrices = localMatrices
        inverseBindWorldMatrices = inverseMatrices

        var claimedBones: Set<Int> = []
        var additiveBones: [Int: [Int]] = [:]
        for animation in additiveAnimations {
            guard additiveBones[animation.id] == nil else {
                throw ScenePuppetAnimationEvaluationFailure.duplicateAdditiveAnimation(animation.id)
            }
            guard animation.transformsByBone.count == rig.bones.count else {
                throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
            }
            var drivenBones: [Int] = []
            for boneIndex in rig.bones.indices {
                guard let reference = animation.transformsByBone[boneIndex].first else {
                    throw ScenePuppetAnimationEvaluationFailure.invalidFrame(0)
                }
                let referenceMatrix = Self.matrix(from: reference)
                guard Self.maxDifference(referenceMatrix, localMatrices[boneIndex]) <= 0.001 else {
                    throw ScenePuppetAnimationEvaluationFailure.additiveReferenceMismatch(
                        animationID: animation.id,
                        boneIndex: boneIndex
                    )
                }
                let isDriven = animation.transformsByBone[boneIndex].contains {
                    Self.maxDifference(Self.matrix(from: $0), referenceMatrix) > 0.0001
                }
                guard isDriven else { continue }
                guard claimedBones.insert(boneIndex).inserted else {
                    throw ScenePuppetAnimationEvaluationFailure.overlappingAdditiveBone(boneIndex)
                }
                drivenBones.append(boneIndex)
            }
            additiveBones[animation.id] = drivenBones
        }
        additiveBonesByAnimationID = additiveBones
    }

    func deformedPositions(
        animation: SceneMdlPuppetAnimation,
        frameIndex: Int
    ) throws -> [SIMD2<Float>] {
        try deformedPositions(localMatrices: localMatrices(
            animation: animation,
            frameIndex: frameIndex
        ))
    }

    func deformedPositions(
        selection: ScenePuppetAnimationSelection,
        frameIndices: [Int?]
    ) throws -> [SIMD2<Float>] {
        guard selection.clips.count == frameIndices.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        switch selection.composition {
        case .singleAbsolute:
            guard selection.clips.count == 1,
                  let frameIndex = frameIndices[0] else {
                return try deformedPositions(localMatrices: bindLocalMatrices)
            }
            return try deformedPositions(
                animation: selection.clips[0].animation,
                frameIndex: frameIndex
            )
        case .disjointAdditive:
            var localMatrices = bindLocalMatrices
            for (clipIndex, clip) in selection.clips.enumerated() {
                guard let frameIndex = frameIndices[clipIndex],
                      let drivenBones = additiveBonesByAnimationID[clip.animation.id] else {
                    continue
                }
                for boneIndex in drivenBones {
                    guard clip.animation.transformsByBone[boneIndex].indices.contains(frameIndex) else {
                        throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameIndex)
                    }
                    localMatrices[boneIndex] = Self.matrix(
                        from: clip.animation.transformsByBone[boneIndex][frameIndex]
                    )
                }
            }
            return try deformedPositions(localMatrices: localMatrices)
        }
    }

    private func localMatrices(
        animation: SceneMdlPuppetAnimation,
        frameIndex: Int
    ) throws -> [simd_float4x4] {
        guard animation.transformsByBone.count == rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        return try animation.transformsByBone.map { track in
            guard track.indices.contains(frameIndex) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameIndex)
            }
            return Self.matrix(from: track[frameIndex])
        }
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

    static func frameIndex(
        sceneTime: Double,
        rate: Double,
        animation: SceneMdlPuppetAnimation
    ) -> Int {
        guard sceneTime.isFinite, rate.isFinite, sceneTime > 0, rate > 0 else { return 0 }
        let framePhase = sceneTime * rate * Double(animation.framesPerSecond)
        guard framePhase.isFinite else { return 0 }
        let wrapped = framePhase.truncatingRemainder(dividingBy: Double(animation.frameCount))
        guard wrapped.isFinite else { return 0 }
        return Int(wrapped.rounded(.down))
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
