import Foundation
import simd

// PRODUCT_QUAD
enum SceneDynamicTarget: Hashable { case scriptInstanceProperty(layerID: Int, path: [String]) }
enum SceneDynamicValue { case bool(Bool), scalar(Double) }
enum SceneDynamicSource: Equatable { case authored, userProperty, timeline, sceneScript }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue; let source: SceneDynamicSource }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    init(frameIndex: UInt64, values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]) {
        self.frameIndex = frameIndex; self.values = values
    }
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
struct SceneScriptPuppetBoneMutation {
    enum Operation { case matrix([Double]), impulse(SIMD3<Double>) }
    let layerID: Int, boneIndex: Int
    let operation: Operation
    init(layerID: Int, boneIndex: Int, matrix: [Double]) {
        self.layerID = layerID
        self.boneIndex = boneIndex
        self.operation = .matrix(matrix)
    }
}
enum ScenePuppetLayerLoad {
    struct BoneConfiguration {
        let names: [String], parentIndices: [Int]
        let worldMatrices: [Double], localMatrices: [Double]
    }
}
func columns(_ matrix: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
}
func transform(z: Float = 0, scale: Float = 1) -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(0, 0, z), rotation: .zero, scale: SIMD3(repeating: scale))
}
struct Subject {
    let state: ScenePuppetPlaybackState
    let vertices: [SceneMdlStaticModel.Vertex]
    let selection: ScenePuppetAnimationSelection
    let evaluator: ScenePuppetAnimationEvaluator
}
func makeSubject(lateSingular: Bool = false, channel: String? = nil,
             renamed: Bool = false,
             latePosition: SIMD3<Float>? = nil,
             physics: [SceneMdlPuppetRig.TranslationPhysics?] = [nil, nil]) throws -> Subject {
    let vertices = (0..<2).map { index in
        SceneMdlStaticModel.Vertex(position: index == 1 ? latePosition ?? SIMD3(2, 2, 3) : SIMD3(1, 2, 3),
            normal: SIMD3(2, 1, 0), tangent: SIMD4(1, -2, 1, -1), uv: SIMD2(0.25, 0.75))
    }
    let identity = columns(matrix_identity_float4x4)
    let rig = SceneMdlPuppetRig(bones: physics.enumerated().map { index, configuration in
        .init(name: "bone-\(index)", parentIndex: -1, bindLocalMatrixColumnMajor: identity,
              translationPhysics: configuration)
    }, vertexWeights: (0..<2).map { index in
        .init(boneIndices: SIMD4(UInt32(index), 0, 0, 0), boneWeights: SIMD4(1, 0, 0, 0))
    })
    let animation = SceneMdlPuppetAnimation(id: 7, name: renamed ? "renamed-motion" : "motion",
        mode: "loop", framesPerSecond: 1, frameCount: 1,
        transformsByBone: physics.indices.map { index in
            [transform(), transform(z: 4, scale: lateSingular && index == 1 ? 0 : 1)]
        })
    var animations = [animation]
    var layers = [ScenePuppetAnimationLayer(id: 71, animationID: 7, name: "base", additive: false,
        blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: true,
        visibilityBinding: nil)]
    if let channel {
        animations.append(SceneMdlPuppetAnimation(id: 8, name: "hidden-channel", mode: "loop",
            framesPerSecond: 1, frameCount: 1,
            transformsByBone: [[transform(), transform()], [transform(), transform()]],
            alphaByBone: channel == "alpha" ? [[1, 0.5], [1, 1]] : nil,
            hasAuxiliaryScalarTrack: channel == "aux"))
        layers.append(ScenePuppetAnimationLayer(id: 72, animationID: 8, name: "optional", additive: true,
            blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: false,
            visibilityBinding: "toggle"))
    }
    guard case let .success(selection?) = ScenePuppetAnimationSelector.select(layers: layers,
        animationSet: .init(boneCount: 2, animations: animations)) else { fatalError("selector") }
    let evaluator = try ScenePuppetAnimationEvaluator(bindPositions: vertices.map(\.position), rig: rig,
        additiveAnimations: selection.clips.map(\.animation))
    guard case let .success(state) = ScenePuppetPlaybackState.makeDirectModel(layerID: renamed ? 989 : 42,
        vertices: vertices, evaluator: evaluator, selection: selection) else { fatalError("factory") }
    return Subject(state: state, vertices: vertices, selection: selection, evaluator: evaluator)
}
func frame(_ index: Int, hidden: Bool = true) -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
    .init(samples: [.init(frameA: index, frameB: index), hidden ? nil : .init(frameA: index, frameB: index)])
}
func singleFrame(_ index: Int) -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
    .init(samples: [.init(frameA: index, frameB: index)])
}

@discardableResult
func prepare(_ subject: Subject, _ frame: ScenePuppetAnimationPlaybackRuntime.LayerFrame)
    -> ScenePuppetPlaybackState.RenderFrame? {
    subject.state.prepareFrame(animationFrame: frame)
    return subject.state.renderFrame
}
func read(_ frame: ScenePuppetPlaybackState.RenderFrame?) -> [SceneMdlStaticModel.Vertex]? {
    guard let frame, case let .direct(vertices, _) = frame.geometry else { return nil }
    return vertices
}

func finiteOutputFallbackChecks() throws -> [String: Bool] {
    let cases: [(String, SIMD3<Float>, SIMD3<Float>)] = [
        ("latePositionOverflowFallback", SIMD3(0, 0, 3), SIMD3(1, 1, 3e38)),
        ("lateNormalOverflowFallback", .zero, SIMD3(1e-40, 1, 1)),
        ("lateTangentOverflowFallback", .zero, SIMD3(1, 3e38, 1))
    ]
    var rows: [String: Bool] = [:]
    for (name, position, scale) in cases {
        let subject = try makeSubject(latePosition: position)
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = scale.x; matrix.columns.1.y = scale.y; matrix.columns.2.z = scale.z
        var partial = subject.vertices
        var local = Array(repeating: matrix_identity_float4x4, count: subject.evaluator.boneCount)
        var skin = local, world = local
        var lateFailure = false
        do {
            try partial.withUnsafeMutableBufferPointer {
                try subject.evaluator.writeDeformedVertices(bindVertices: subject.vertices,
                    selection: subject.selection, frameSamples: singleFrame(1).samples, into: $0,
                    localMatricesScratch: &local, skinMatricesScratch: &skin,
                    worldMatricesScratch: &world, boneOverrides: [1: matrix])
            }
        } catch let failure as ScenePuppetAnimationEvaluator.DirectSkinningFailure {
            lateFailure = failure == .invalidVertex(1)
        }
        let firstWasWritten = partial[0].position == SIMD3(1, 2, 7)
            && partial[0].normal == subject.vertices[0].normal
            && partial[0].tangent == subject.vertices[0].tangent
            && partial[0].uv == subject.vertices[0].uv && partial[1] == subject.vertices[1]
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
            matrix: columns(matrix).map(Double.init))])
        let frozen = prepare(subject, singleFrame(1))
        let wholeBind = subject.state.directModelPoseStatus == .bindFallback(.invalidSkinFrame)
            && read(frozen) == subject.vertices
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
            matrix: columns(matrix_identity_float4x4).map(Double.init))])
        let resumed = read(prepare(subject, singleFrame(1)))
        rows[name] = lateFailure && firstWasWritten && wholeBind
            && subject.state.directModelPoseStatus == .animated
            && resumed?[0].position == SIMD3(1, 2, 7) && resumed?[1] == subject.vertices[1]
            && read(frozen) == subject.vertices
    }
    let subject = try makeSubject(latePosition: .zero)
    var scale = matrix_identity_float4x4
    scale.columns.0.x = 2; scale.columns.1.y = 3; scale.columns.2.z = 4
    subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
        matrix: columns(scale).map(Double.init))])
    let values = read(prepare(subject, singleFrame(1)))
    let expected = SceneMdlStaticModel.Vertex(position: .zero,
        normal: SIMD3(1, Float(1.0 / 3.0), 0), tangent: SIMD4(2, -6, 4, -1), uv: SIMD2(0.25, 0.75))
    rows["finiteAffineOutput"] = subject.state.directModelPoseStatus == .animated
        && values?[0].position == SIMD3(1, 2, 7) && values?[1] == expected
    return rows
}

func physicsSubsetChecks() throws -> Bool {
    let configurations: [SceneMdlPuppetRig.TranslationPhysics?] = [nil,
        .init(spring: true, stiffness: 70, friction: 5, inertia: 5, maxDistance: 50), nil,
        .init(spring: true, stiffness: 140, friction: 9, inertia: 3, maxDistance: 50)]
    let subject = try makeSubject(physics: configurations)
    let written: [Float] = [0.25, 0.45, 0.65, 0.85]
    subject.state.apply(scriptBoneMutations: written.enumerated().map { index, origin in
        var matrix = matrix_identity_float4x4; matrix.columns.3.z = origin
        return .init(layerID: 42, boneIndex: index, matrix: columns(matrix).map(Double.init))
    })
    var motions = configurations.map { _ in ScenePuppetTranslationMotion() }
    var expected = written
    var valid = true
    for cadence in UInt64(10)...11 {
        for index in configurations.indices {
            guard let config = configurations[index] else { continue }
            expected[index] = motions[index].advance(
                position: SIMD3(0, 0, expected[index]), target: .zero,
                deltaTime: 0.05, configuration: config).z
        }
        subject.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.05, frameIndex: cadence)
        let pose = subject.state.poseConfiguration(animationFrame: singleFrame(0))!
        for index in configurations.indices {
            valid = valid && abs(pose.bones.localMatrices[index * 16 + 14] - Double(expected[index])) < 1e-6
                && abs(pose.queryLocalMatrices[index * 16 + 14]
                    - Double(configurations[index] == nil ? written[index] : 0)) < 1e-6
        }
    }
    let before = subject.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices
    subject.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.25, frameIndex: 11)
    valid = valid && before == subject.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices
        && expected[1] != written[1] && expected[3] != written[3]
    let ordinary = try makeSubject()
    var matrix = matrix_identity_float4x4; matrix.columns.3.z = 0.75
    ordinary.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
        matrix: columns(matrix).map(Double.init))])
    ordinary.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.05, frameIndex: 10)
    return valid && ordinary.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices[30] == 0.75
}

@main enum Main {
    static func main() throws {
        var rows = try finiteOutputFallbackChecks()
        rows["multiplePhysicsBones"] = try physicsSubsetChecks()
        let subject = try makeSubject()
        rows["unpreparedHasNoFrame"] = subject.state.renderFrame == nil
        let frozen = prepare(subject, singleFrame(1))!
        let firstValues = read(frozen)!
        let repeated = prepare(subject, singleFrame(1))!
        var override = matrix_identity_float4x4; override.columns.3.z = 9
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 0, matrix: columns(override).map(Double.init))])
        let changed = prepare(subject, singleFrame(1))!
        let values = read(changed)!
        let query = subject.state.poseConfiguration(animationFrame: singleFrame(1))!
        rows["poseAndSignature"] = subject.state.isDirectModel && firstValues[0].position.z == 7
            && firstValues[0].normal == SIMD3(2, 1, 0) && firstValues[0].uv == SIMD2(0.25, 0.75)
            && repeated.revision == frozen.revision && values[0].position.z == 12
            && changed.revision > frozen.revision && query.bones.worldMatrices[14] == 9
        rows["frozenFrameValueSurvivesLaterPrepare"] = read(frozen) == firstValues
            && read(changed) != firstValues
        let renamed = try makeSubject(renamed: true)
        rows["renamed"] = read(prepare(renamed, singleFrame(1))) == firstValues
        let late = try makeSubject(lateSingular: true)
        let lateFrame = prepare(late, singleFrame(1))
        rows["lateVertexFallback"] = late.state.directModelPoseStatus == .bindFallback(.invalidSkinFrame)
            && read(lateFrame) == late.vertices
        var channels = true
        for channel in ["alpha", "aux"] {
            let value = try makeSubject(channel: channel)
            let hidden = prepare(value, frame(1))
            channels = channels && value.state.directModelPoseStatus == .animated
                && read(hidden)![0].position.z == 7
            let active = prepare(value, frame(1, hidden: false))
            channels = channels && value.state.directModelPoseStatus == .bindFallback(.unsupportedAnimationChannels)
                && read(active) == value.vertices
            let restored = prepare(value, frame(1))
            channels = channels && value.state.directModelPoseStatus == .animated
                && read(restored)![0].position.z == 7
        }
        rows["channelVisibility"] = channels
        let invalid = prepare(renamed, .init(samples: []))
        rows["invalidFrame"] = renamed.state.directModelPoseStatus == .bindFallback(.invalidFrame)
            && read(invalid) == renamed.vertices
        let peer = try makeSubject()
        rows["cpuInstanceIsolation"] = read(prepare(peer, singleFrame(0))) == peer.vertices
            && read(subject.state.renderFrame) == values
        let badCount = ScenePuppetPlaybackState.makeDirectModel(layerID: 1, vertices: [],
            evaluator: subject.evaluator, selection: subject.selection)
        let attachment = SceneMdlPuppetAttachment(boneIndex: 0, name: "unqualified",
            modelLocalFrameColumnMajor: columns(matrix_identity_float4x4),
            modelBindFrameColumnMajor: columns(matrix_identity_float4x4))
        let badAttachment = ScenePuppetPlaybackState.makeDirectModel(layerID: 1,
            vertices: subject.vertices, evaluator: subject.evaluator,
            selection: subject.selection, attachments: [attachment])
        if case .failure(.directModelVertexCountMismatch) = badCount,
           case .failure(.directAttachmentBasisUnqualified) = badAttachment {
            rows["factoryCount"] = true
        } else { rows["factoryCount"] = false }
        print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
