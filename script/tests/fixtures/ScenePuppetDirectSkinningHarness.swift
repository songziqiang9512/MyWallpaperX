import Foundation
import simd

@main enum ScenePuppetDirectSkinningHarness {
    struct Case: Decodable {
        let name: String
        let matrices: [[Float]]
        let weights: [Float]
        let bind: [[Float]]?
        let parents: [Int]?
        let fault: String?
        let animation: Bool?
        let blend: Double?
        let boneOverride: Float?
        let renamed: Bool?
    }

    static func matrix(_ values: [Float]) -> simd_float4x4 {
        .init(columns: (SIMD4(values[0], values[1], values[2], values[3]),
                        SIMD4(values[4], values[5], values[6], values[7]),
                        SIMD4(values[8], values[9], values[10], values[11]),
                        SIMD4(values[12], values[13], values[14], values[15])))
    }

    static func flatten(_ value: simd_float4x4) -> [Float] {
        [value.columns.0, value.columns.1, value.columns.2, value.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    static func floats(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }

    static func run(_ item: Case) throws -> [String: Any] {
        let count = item.matrices.count
        let identity = flatten(matrix_identity_float4x4)
        let binds = item.bind ?? Array(repeating: identity, count: count)
        let position: SIMD3<Float> = item.fault == "zOverflow" ? SIMD3(1, 2, 2) : SIMD3(1, 2, 3)
        let normal: SIMD3<Float> = item.fault == "zeroDirections" ? .zero : SIMD3(2, 1, 0)
        var tangent = item.fault == "zeroDirections" ? SIMD4<Float>.zero : SIMD4(1, -2, 1, -1)
        if item.fault == "nonfiniteTangent" { tangent.z = .infinity }
        let vertex = SceneMdlStaticModel.Vertex(position: position, normal: normal,
            tangent: tangent, uv: SIMD2(0.25, 0.75))
        let indices = SIMD4<UInt32>(0, UInt32(min(1, count - 1)),
                                   UInt32(min(2, count - 1)), UInt32(min(3, count - 1)))
        let rig = SceneMdlPuppetRig(bones: (0..<count).map {
            .init(name: item.renamed == true ? "joint_\($0)" : "bone_\($0)",
                  parentIndex: item.parents?[$0] ?? -1,
                  bindLocalMatrixColumnMajor: binds[$0])
        }, vertexWeights: [.init(boneIndices: indices,
            boneWeights: SIMD4(item.weights[0], item.weights[1], item.weights[2], item.weights[3]))])
        var animations: [SceneMdlPuppetAnimation] = []
        var selection = ScenePuppetAnimationSelection(clips: [], composition: .layered)
        var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = []
        if item.animation == true {
            let animation = SceneMdlPuppetAnimation(id: item.renamed == true ? 719 : 8,
                name: item.renamed == true ? "renamed-motion" : "motion", mode: "loop",
                framesPerSecond: 2, frameCount: 1,
                transformsByBone: (0..<count).map { bone in
                    [Float(0), Float((bone + 1) * 4)].map {
                        .init(translation: SIMD3(0, 0, $0), rotation: .zero,
                              scale: SIMD3(repeating: 1))
                    }
                })
            let layer = ScenePuppetAnimationLayer(id: 31, animationID: animation.id,
                name: "selected", additive: false, blend: 1, blendIn: false,
                blendOut: false, blendTime: 0, rate: 1, visible: true, visibilityBinding: nil)
            guard case let .success(selected?) = ScenePuppetAnimationSelector.select(
                layers: [layer], animationSet: .init(boneCount: count, animations: [animation]))
            else { return ["name": item.name, "error": "selection"] }
            selection = selected
            animations = [animation]
            samples = [.init(frameA: 0, frameB: 1, fraction: 0.5)]
        }
        var overrides: [Int: simd_float4x4] = item.animation == true ? [:]
            : Dictionary(uniqueKeysWithValues: item.matrices.enumerated().map { ($0.offset, matrix($0.element)) })
        if let z = item.boneOverride { overrides[1] = SceneMatrix.translation(SIMD3(0, 0, z)) }
        let evaluator = try ScenePuppetAnimationEvaluator(bindPositions: [position],
            rig: rig, additiveAnimations: animations)
        let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80, meshBlockOffset: 9,
            vertices: [.init(x: position.x, y: position.y, z: position.z, u: 0.25, v: 0.75)],
            indices: [0, 0, 0])
        let image = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig, additiveAnimations: animations)
        var local = Array(repeating: matrix_identity_float4x4, count: count)
        var skin = local, world = local
        var xy = [SIMD2<Float>.zero]
        let blends = item.blend.map { [$0] }
        var result: [String: Any] = ["name": item.name]
        do {
            try xy.withUnsafeMutableBufferPointer {
                try image.writeDeformedPositions(selection: selection, frameSamples: samples,
                    into: $0, localMatricesScratch: &local, skinMatricesScratch: &skin,
                    worldMatricesScratch: &world, boneOverrides: overrides, blends: blends)
            }
            result["imageXY"] = [xy[0].x, xy[0].y]
        } catch { result["imageError"] = String(describing: error) }
        var output = Array(repeating: vertex, count: item.fault == "shortOutput" ? 0 : 1)
        do {
            try output.withUnsafeMutableBufferPointer {
                try evaluator.writeDeformedVertices(
                    bindVertices: item.fault == "wrongCount" ? [] : [vertex],
                    selection: selection, frameSamples: samples, into: $0,
                    localMatricesScratch: &local, skinMatricesScratch: &skin,
                    worldMatricesScratch: &world, boneOverrides: overrides, blends: blends)
            }
            let value = output[0]
            result["position"] = floats(value.position)
            result["normal"] = floats(value.normal)
            result["tangent"] = [value.tangent.x, value.tangent.y, value.tangent.z, value.tangent.w]
            result["uv"] = [value.uv.x, value.uv.y]
        } catch { result["error"] = String(describing: error) }
        return result
    }

    static func main() throws {
        let cases = try JSONDecoder().decode([Case].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let result = try cases.map(run)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
