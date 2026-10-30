import Foundation
import simd

enum ScenePuppetReferenceEquivalenceChecks {
    static func transform(_ scale: Float = 1, translation: SIMD3<Float> = SIMD3(294.640625, 1646.4677734375, 0),
                          rotation: SIMD3<Float> = .zero) -> SceneMdlPuppetAnimation.Transform {
        .init(translation: translation, rotation: rotation, scale: SIMD3(repeating: scale))
    }

    static func fixture(_ track: [SceneMdlPuppetAnimation.Transform], id: Int = 301,
                        name: String = "Reference", postBounds: Bool = false)
        -> (SceneMdlPuppetMesh, SceneMdlPuppetRig, SceneMdlPuppetAnimation) {
        let root = ScenePuppetAnimationEvaluator.matrix(from: transform())
        let child = SceneMatrix.translation(SIMD3<Float>(10, 0, 0))
        func words(_ matrix: simd_float4x4) -> [Float] {
            [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap {
                [$0.x, $0.y, $0.z, $0.w]
            }
        }
        let vertices: [SceneMdlPuppetMesh.Vertex] = [
            .init(x: 295.640625, y: 1646.4677734375, z: 0, u: 0, v: 0),
            .init(x: 294.640625, y: 1647.4677734375, z: 0, u: 1, v: 0),
            .init(x: 294.640625, y: 1646.4677734375, z: 0, u: 0, v: 1),
        ]
        let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
            meshBlockOffset: 0, vertices: vertices, indices: [0,1,2])
        let rig = SceneMdlPuppetRig(bones: [
            .init(name: name + " root", parentIndex: -1, bindLocalMatrixColumnMajor: words(root)),
            .init(name: name + " tip", parentIndex: 0, bindLocalMatrixColumnMajor: words(child)),
        ], vertexWeights: vertices.map { _ in .init(boneIndices: SIMD4(0,1,0,0),
            boneWeights: SIMD4(0.5,0.5,0,0)) })
        let moving = (0..<track.count).map { frame in
            transform(1, translation: SIMD3(frame == 1 ? 12 : 10, 0, 0))
        }
        let clip = SceneMdlPuppetAnimation(id: id, name: name, mode: "loop", framesPerSecond: 3,
            frameCount: track.count - 1, transformsByBone: [track, moving],
            transformTrackStates: [.referenceCandidate, .sampled], hasPostBoundsScalarTrack: postBounds)
        return (mesh, rig, clip)
    }

    static func accepted(_ input: (SceneMdlPuppetMesh, SceneMdlPuppetRig, SceneMdlPuppetAnimation)) -> Bool {
        do {
            let (mesh, rig, clip) = input
            let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig, additiveAnimations: [clip])
            let first = try evaluator.deformedPositions(animation: clip, frameIndex: 0)
            let later = try evaluator.deformedPositions(animation: clip, frameIndex: 1)
            return evaluator.hasPreparedAnimation(animationID: clip.id)
                && abs(first[0].x - mesh.vertices[0].x) < 0.0001
                && abs(later[0].x - first[0].x - 1) < 0.0001
        } catch { return false }
    }

    static func rejects(_ input: (SceneMdlPuppetMesh, SceneMdlPuppetRig, SceneMdlPuppetAnimation)) -> Bool {
        do {
            _ = try ScenePuppetAnimationEvaluator(mesh: input.0, rig: input.1,
                additiveAnimations: [input.2])
            return false
        } catch { return true }
    }

    static func realAsset(_ directory: URL) throws -> [String: Any] {
        let url = directory.appendingPathComponent("reference-real.mdl")
        guard FileManager.default.fileExists(atPath: url.path) else { return ["available": false] }
        let data = try Data(contentsOf: url)
        let mesh = try SceneMdlPuppetMeshReader.read(data: data)
        let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
        let set = try SceneMdlPuppetAnimationReader.read(data: data)!
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf:
            directory.appendingPathComponent("reference-real-scene.json"))) as! [String: Any]
        let source = (root["objects"] as! [[String: Any]]).first { ($0["id"] as? Int) == 28 }!
        let layers = ScenePuppetAnimationLayer.parse(source["animationlayers"])
        let selection = try ScenePuppetAnimationSelector.select(layers: layers, animationSet: set).get()!
        let original = selection.clips[0].animation
        var results: [[String: Any]] = []
        for renamed in [false, true] {
            let clip = SceneMdlPuppetAnimation(id: renamed ? 6401 : original.id,
                name: renamed ? "Alternate κ motion" : original.name,
                mode: original.mode, framesPerSecond: original.framesPerSecond,
                frameCount: original.frameCount, transformsByBone: original.transformsByBone,
                transformTrackStates: original.transformTrackStates, alphaByBone: original.alphaByBone,
                events: original.events, bounds: original.bounds,
                hasAuxiliaryScalarTrack: original.hasAuxiliaryScalarTrack,
                hasPostBoundsScalarTrack: original.hasPostBoundsScalarTrack)
            do {
                let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig, additiveAnimations: [clip])
                let first = try evaluator.deformedPositions(animation: clip, frameIndex: 0)
                let later = try evaluator.deformedPositions(animation: clip, frameIndex: clip.frameCount / 2)
                results.append(["renamed": renamed, "prepared": evaluator.hasPreparedAnimation(animationID: clip.id),
                    "animated": zip(first, later).contains { simd_length($0 - $1) > 0.01 },
                    "vertexCount": later.count, "failure": ""])
            } catch {
                results.append(["renamed": renamed, "prepared": false, "animated": false,
                    "vertexCount": 0, "failure": String(describing: error)])
            }
        }
        return ["available": true, "vertices": mesh.vertices.count, "variants": results]
    }

    static func run() throws -> [String: Any] {
        // Exact scale words from the authored 382 root track; its translation/rotation stay fixed.
        let low = Float(bitPattern: 0x3f7fffff), high = Float(bitPattern: 0x3f800001)
        var checks: [String: Bool] = [:]
        for (id, name) in [(301, "Reference"), (809, "Renamed λ")] {
            checks["\(id)-authored-float-roundtrip"] = accepted(fixture(
                [transform(low), transform(1), transform(high)], id: id, name: name))
            checks["\(id)-equivalent-rotation"] = accepted(fixture([
                transform(), transform(1, rotation: SIMD3(0,0,2 * Float.pi)), transform()
            ], id: id, name: name))
        }
        checks["constant-bind-reference-retained"] = accepted(fixture(Array(repeating: transform(), count: 3)))
        for (name, value) in [
            ("moving-translation", transform(1, translation: SIMD3(294.642, 1646.4677734375, 0))),
            ("moving-scale", transform(1.01)),
            ("reflected-unit-scale", transform(-1)),
            ("moving-rotation", transform(1, rotation: SIMD3(0,0,0.01))),
            ("nonfinite-transform", transform(.nan)),
        ] {
            checks[name + "-rejected"] = rejects(fixture([transform(), value, transform()]))
        }
        checks["constant-away-from-bind-rejected"] = rejects(fixture(Array(repeating:
            transform(1, translation: SIMD3(300, 1646.4677734375, 0)), count: 3)))
        checks["unknown-scalar-rejected"] = rejects(fixture(Array(repeating: transform(), count: 3), postBounds: true))
        let (mesh, rig, clip) = fixture(Array(repeating: transform(), count: 3))
        var badBones = rig.bones
        var matrix = badBones[0].bindLocalMatrixColumnMajor; matrix[0] = .nan
        badBones[0] = .init(parentIndex: -1, bindLocalMatrixColumnMajor: matrix)
        checks["bad-bind-matrix-rejected"] = rejects((mesh,
            .init(bones: badBones, vertexWeights: rig.vertexWeights), clip))
        checks["separate-reference-pose-remains-unqualified"] = rejects((mesh,
            .init(bones: rig.bones, vertexWeights: rig.vertexWeights,
                referenceLocalMatricesColumnMajor: rig.bones.map(\.bindLocalMatrixColumnMajor)), clip))
        let peer = SceneMdlPuppetAnimation(id: 302, name: "Opaque peer", mode: clip.mode,
            framesPerSecond: clip.framesPerSecond, frameCount: clip.frameCount,
            transformsByBone: clip.transformsByBone, transformTrackStates: clip.transformTrackStates)
        let selected = ScenePuppetAnimationSelector.select(
            layers: [layer(id: 1, animationID: clip.id), layer(id: 2, animationID: peer.id)],
            animationSet: .init(boneCount: 2, animations: [clip,peer]))
        if case .failure(.unsupportedLayer) = selected { checks["multiple-opaque-rejected"] = true }
        else { checks["multiple-opaque-rejected"] = false }
        return ["selfContained": checks, "realSource": try realAsset(
            URL(fileURLWithPath: CommandLine.arguments[1]))]
    }
}
