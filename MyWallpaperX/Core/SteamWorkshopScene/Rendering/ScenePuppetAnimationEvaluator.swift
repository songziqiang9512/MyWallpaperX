import simd

struct ScenePuppetAnimationSelection {
    let layer: ScenePuppetAnimationLayer
    let animation: SceneMdlPuppetAnimation
}

enum ScenePuppetAnimationSelectionFailure: Error, CustomStringConvertible, Equatable {
    case unresolvedVisibility(Int?)
    case malformedVisibility(Int?)
    case multipleVisibleLayers(Int)
    case unsupportedLayer(Int?)
    case unknownAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .unresolvedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has property-bound visibility"
        case .malformedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has no static visibility"
        case .multipleVisibleLayers(let count):
            return "\(count) visible animation layers require unsupported mixing"
        case .unsupportedLayer(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") is outside the strict single-clip profile"
        case .unknownAnimation(let id):
            return "animation id \(id) is absent from MDLA0006"
        }
    }
}

enum ScenePuppetAnimationSelector {
    static func select(
        layers: [ScenePuppetAnimationLayer],
        animationSet: SceneMdlPuppetAnimationSet
    ) -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        var visibleLayers: [ScenePuppetAnimationLayer] = []
        for layer in layers {
            guard layer.visibilityBinding == nil else {
                return .failure(.unresolvedVisibility(layer.id))
            }
            guard let visible = layer.visible else {
                return .failure(.malformedVisibility(layer.id))
            }
            if visible { visibleLayers.append(layer) }
        }
        guard visibleLayers.isEmpty == false else { return .success(nil) }
        guard visibleLayers.count == 1 else {
            return .failure(.multipleVisibleLayers(visibleLayers.count))
        }

        let layer = visibleLayers[0]
        guard let animationID = layer.animationID,
              layer.additive == false,
              layer.blend == 1,
              layer.blendIn == false,
              layer.blendOut == false,
              layer.rate == 1 else {
            return .failure(.unsupportedLayer(layer.id))
        }
        guard let animation = animationSet.animations.first(where: { $0.id == animationID }) else {
            return .failure(.unknownAnimation(animationID))
        }
        return .success(ScenePuppetAnimationSelection(layer: layer, animation: animation))
    }
}

enum ScenePuppetAnimationEvaluationFailure: Error, CustomStringConvertible, Equatable {
    case boneCountMismatch
    case singularBindMatrix(Int)
    case invalidFrame(Int)

    nonisolated var description: String {
        switch self {
        case .boneCountMismatch:
            return "puppet mesh, rig, and animation bone counts do not match"
        case .singularBindMatrix(let index):
            return "puppet bind world matrix \(index) is singular"
        case .invalidFrame(let index):
            return "puppet animation frame \(index) is out of bounds"
        }
    }
}

struct ScenePuppetAnimationEvaluator {
    private let mesh: SceneMdlPuppetMesh
    private let rig: SceneMdlPuppetRig
    private let inverseBindWorldMatrices: [simd_float4x4]

    init(mesh: SceneMdlPuppetMesh, rig: SceneMdlPuppetRig) throws {
        guard mesh.vertices.count == rig.vertexWeights.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        self.mesh = mesh
        self.rig = rig

        var bindWorldMatrices: [simd_float4x4] = []
        bindWorldMatrices.reserveCapacity(rig.bones.count)
        var inverseMatrices: [simd_float4x4] = []
        inverseMatrices.reserveCapacity(rig.bones.count)
        for (boneIndex, bone) in rig.bones.enumerated() {
            let local = Self.matrix(fromColumnMajor: bone.bindLocalMatrixColumnMajor)
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
        inverseBindWorldMatrices = inverseMatrices
    }

    func deformedPositions(
        animation: SceneMdlPuppetAnimation,
        frameIndex: Int
    ) throws -> [SIMD2<Float>] {
        guard animation.transformsByBone.count == rig.bones.count else {
            throw ScenePuppetAnimationEvaluationFailure.boneCountMismatch
        }
        var animatedWorldMatrices: [simd_float4x4] = []
        animatedWorldMatrices.reserveCapacity(rig.bones.count)
        for (boneIndex, bone) in rig.bones.enumerated() {
            guard animation.transformsByBone[boneIndex].indices.contains(frameIndex) else {
                throw ScenePuppetAnimationEvaluationFailure.invalidFrame(frameIndex)
            }
            let transform = animation.transformsByBone[boneIndex][frameIndex]
            let local = SceneMatrix.translation(transform.translation)
                * SceneMatrix.eulerXYZ(transform.rotation)
                * SceneMatrix.scale(transform.scale)
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
        let wrapped = framePhase.truncatingRemainder(dividingBy: Double(animation.frameCount))
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
}
