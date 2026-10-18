#!/usr/bin/env python3
"""Static Puppet weights: public black-box contract, plus numerical safety."""
import json
import math
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SWIFT_SOURCES
from script.tests.test_scene_puppet_rig import build_rig_mdl, matrix

HARNESS = r'''
import Foundation
import simd

func layer(_ weight: Double, additive: Bool = true, id: Int = 1) -> ScenePuppetAnimationLayer {
    .init(id: id, animationID: id, name: "weight", additive: additive, blend: weight,
          blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: true,
          visibilityBinding: nil)
}
func pose(_ x: Float, rotation: SIMD3<Float> = .zero, scale: Float = 1,
          scaleXYZ: SIMD3<Float>? = nil)
    -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(x, 0, 0), rotation: rotation, scale: scaleXYZ ?? SIMD3(scale, 1, 1))
}
func clip(_ id: Int = 1, reference: SceneMdlPuppetAnimation.Transform = pose(20),
          held: SceneMdlPuppetAnimation.Transform = pose(30, rotation: SIMD3(0,0,.pi/6), scale: 1.2))
    -> SceneMdlPuppetAnimation {
    .init(id: id, name: "weight", mode: "single", framesPerSecond: 1, frameCount: 1,
          transformsByBone: [[reference, held], [pose(2), pose(2)]])
}
func columns(_ m: simd_float4x4) -> [Float] {
    (0..<4).flatMap { i in (0..<4).map { j in m[i][j] } }
}
func fixture(bindRotation: SIMD3<Float> = .zero, vertexX: Float = 2, vertexZ: Float = 0,
             bindScale: Float = 1)
    throws -> (SceneMdlPuppetMesh, SceneMdlPuppetRig) {
    let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
        meshBlockOffset: 9, vertices: [.init(x: vertexX,y: 1,z: vertexZ,u: 0,v: 0)], indices: [0,0,0])
    let rig = SceneMdlPuppetRig(bones: [
        .init(parentIndex: -1, bindLocalMatrixColumnMajor:
            columns(SceneMatrix.translation(SIMD3(4,0,0)) * SceneMatrix.eulerXYZ(bindRotation)
                * SceneMatrix.scale(SIMD3(bindScale,1,1)))),
        .init(parentIndex: 0, bindLocalMatrixColumnMajor: columns(SceneMatrix.translation(SIMD3(2,0,0))))
    ], vertexWeights: [.init(boneIndices: SIMD4(1,0,0,0), boneWeights: SIMD4(1,0,0,0))])
    return (mesh, rig)
}
func evaluate(_ weight: Double, additive: Bool = true, extra: Bool = false,
              animation: SceneMdlPuppetAnimation = clip(), bindRotation: SIMD3<Float> = .zero,
              vertexX: Float = 2, vertexZ: Float = 0) throws -> [String: Any] {
    let (mesh, rig) = try fixture(bindRotation: bindRotation, vertexX: vertexX, vertexZ: vertexZ)
    let base = clip(2, reference: pose(9), held: pose(9))
    let clips: [ScenePuppetAnimationSelection.Clip] = (extra
        ? [.init(layer: layer(1,id: 2),animation: base)] : [])
        + [.init(layer: layer(weight,additive: additive),animation: animation)]
    let selection = ScenePuppetAnimationSelection(clips: clips,
        composition: additive || extra ? .layered : .singleAbsolute)
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh,rig: rig,
        additiveAnimations: clips.map(\.animation))
    let samples = clips.map { _ in ScenePuppetAnimationEvaluator.FrameSample(frameA: 1,frameB: 1) }
    let transforms = try evaluator.boneTransforms(selection: selection,frameSamples: samples)
    let points = try evaluator.deformedPositions(selection: selection,frameSamples: samples)
    // Exercise the actual persistent-buffer writer too; a throw prevents publication.
    var output = [SIMD2<Float>](repeating: .zero,count: 1)
    var locals = [simd_float4x4](repeating: matrix_identity_float4x4,count: 2)
    var skins = locals, worlds = locals
    try output.withUnsafeMutableBufferPointer {
        try evaluator.writeDeformedPositions(selection: selection,frameSamples: samples,into: $0,
            localMatricesScratch: &locals,skinMatricesScratch: &skins,
            worldMatricesScratch: &worlds)
    }
    return ["local": columns(transforms.local[0]),"childWorld": columns(transforms.world[1]),
            "point": [points[0].x,points[0].y],"written": [output[0].x,output[0].y]]
}
func rejected(_ operation: () throws -> [String: Any]) -> Bool {
    do { _ = try operation(); return false } catch { return true }
}
func depthProjection(_ vertex: SIMD3<Float>, rotations: [SIMD3<Float>],
                     bindRotation: SIMD3<Float> = .zero,
                     indices: SIMD4<UInt32> = SIMD4(repeating: 0),
                     weights: SIMD4<Float> = SIMD4(1,0,0,0),
                     tag: String = "depth", animationID: Int = 701) throws -> [String: Any] {
    let bindPosition = SIMD3<Float>(4,0,2)
    let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
        meshBlockOffset: 9, vertices: [.init(x: vertex.x, y: vertex.y, z: vertex.z, u: 0, v: 0)],
        indices: [0,0,0])
    let bind = columns(SceneMatrix.translation(bindPosition) * SceneMatrix.eulerXYZ(bindRotation))
    let rig = SceneMdlPuppetRig(bones: rotations.indices.map {
        .init(name: "\(tag)-bone-\($0)", parentIndex: -1, bindLocalMatrixColumnMajor: bind)
    }, vertexWeights: [.init(boneIndices: indices, boneWeights: weights)])
    let animation = SceneMdlPuppetAnimation(id: animationID, name: tag, mode: "single",
        framesPerSecond: 1, frameCount: 1, transformsByBone: rotations.map {
            [.init(translation: bindPosition, rotation: bindRotation, scale: SIMD3(repeating: 1)),
             .init(translation: SIMD3(10,0,0), rotation: $0, scale: SIMD3(repeating: 1))]
        })
    let selection = ScenePuppetAnimationSelection(clips: [
        .init(layer: layer(1, additive: false, id: animationID), animation: animation)
    ], composition: .singleAbsolute)
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig, additiveAnimations: [animation])
    let samples: [ScenePuppetAnimationEvaluator.FrameSample?] = [.init(frameA: 1, frameB: 1)]
    let points = try evaluator.deformedPositions(selection: selection, frameSamples: samples)
    var written = [SIMD2<Float>](repeating: .zero, count: 1)
    var locals = [simd_float4x4](repeating: matrix_identity_float4x4, count: rotations.count)
    var skins = locals, worlds = locals
    try written.withUnsafeMutableBufferPointer {
        try evaluator.writeDeformedPositions(selection: selection, frameSamples: samples, into: $0,
            localMatricesScratch: &locals, skinMatricesScratch: &skins, worldMatricesScratch: &worlds)
    }
    return ["point": [points[0].x, points[0].y], "written": [written[0].x, written[0].y]]
}
func referenceEvaluation(mesh: SceneMdlPuppetMesh, rig: SceneMdlPuppetRig,
                         weights: [Double], additive: [Bool], frames: [Int?]) throws -> [String: Any] {
    let clips = weights.indices.map { index in
        let animation = SceneMdlPuppetAnimation(id: index + 1, name: "reference", mode: "single",
            framesPerSecond: 1, frameCount: 1, transformsByBone: [
                [pose(index == 0 ? 23 : 25), pose(index == 0 ? 30 : 40)],
                [pose(index == 0 ? 8 : 9), pose(index == 0 ? 10 : 12)]])
        return ScenePuppetAnimationSelection.Clip(
            layer: layer(weights[index], additive: additive[index], id: index + 1), animation: animation)
    }
    let selection = ScenePuppetAnimationSelection(clips: clips,
        composition: clips.count == 1 && additive[0] == false ? .singleAbsolute : .layered)
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig,
        additiveAnimations: clips.map(\.animation))
    let samples = frames.map { $0.map { ScenePuppetAnimationEvaluator.FrameSample(frameA: $0, frameB: $0) } }
    let transforms = try evaluator.boneTransforms(selection: selection, frameSamples: samples)
    let points = try evaluator.deformedPositions(selection: selection, frameSamples: samples)
    var written = [SIMD2<Float>](repeating: .zero, count: mesh.vertices.count)
    var locals = [simd_float4x4](repeating: matrix_identity_float4x4, count: rig.bones.count)
    var skins = locals, worlds = locals
    try written.withUnsafeMutableBufferPointer {
        try evaluator.writeDeformedPositions(selection: selection, frameSamples: samples, into: $0,
            localMatricesScratch: &locals, skinMatricesScratch: &skins, worldMatricesScratch: &worlds)
    }
    return ["root": transforms.local[0].columns.3.x,
            "child": transforms.local[1].columns.3.x,
            "childWorld": transforms.world[1].columns.3.x,
            "points": points.map { [$0.x, $0.y] }, "written": written.map { [$0.x, $0.y] }]
}
func denseClip(_ id: Int = 1701, root: [SceneMdlPuppetAnimation.Transform]? = nil,
               states: [SceneMdlPuppetAnimation.TransformTrackState] = [.referenceCandidate, .sampled],
               alpha: Bool = false, tag: String = "neutral") -> SceneMdlPuppetAnimation {
    .init(id: id, name: tag, mode: "single", framesPerSecond: 1, frameCount: 1,
        transformsByBone: [root ?? [pose(4), pose(4)], [pose(2), pose(2)]],
        transformTrackStates: states, alphaByBone: alpha ? [[1,1], [1,0.25]] : nil)
}
func denseEvaluation(_ clips: [ScenePuppetAnimationSelection.Clip],
                     rig override: SceneMdlPuppetRig? = nil, hidden: Bool = false) throws -> [String: Any] {
    let (mesh, original) = try fixture(vertexZ: 5)
    let rig = override ?? original
    let selection = try ScenePuppetAnimationSelector.select(layers: clips.map(\.layer),
        animationSet: .init(boneCount: 2, animations: clips.map(\.animation))).get()!
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: rig,
        additiveAnimations: clips.map(\.animation))
    let samples: [ScenePuppetAnimationEvaluator.FrameSample?] = clips.map {
        _ in hidden ? nil : .init(frameA: 1, frameB: 1)
    }
    let transforms = try evaluator.boneTransforms(selection: selection, frameSamples: samples)
    let points = try evaluator.deformedPositions(selection: selection, frameSamples: samples)
    var written = [SIMD2<Float>](repeating: .zero, count: 1)
    var local = [simd_float4x4](repeating: matrix_identity_float4x4, count: 2)
    var skin = local, world = local
    try written.withUnsafeMutableBufferPointer {
        try evaluator.writeDeformedPositions(selection: selection, frameSamples: samples, into: $0,
            localMatricesScratch: &local, skinMatricesScratch: &skin, worldMatricesScratch: &world)
    }
    var coverage: [Float] = [0], boneCoverage: [Float] = [0,0]
    try evaluator.writeVertexCoverages(selection: selection, frameSamples: samples,
        into: &coverage, boneScratch: &boneCoverage)
    return ["root": transforms.local[0].columns.3.x,
        "child": transforms.local[1].columns.3.x, "point": [points[0].x, points[0].y],
        "written": [written[0].x, written[0].y], "coverage": coverage[0],
        "invariant": evaluator.isTimeInvariant(animationID: clips[0].animation.id)]
}
func denseReferenceCases() throws -> [String: Any] {
    var output: [String: Any] = [:]
    for weight in [0.0, 0.5, 1, 2] {
        for additive in [false, true] {
            let a = denseClip()
            output["neutral-\(additive)-\(weight)"] = try denseEvaluation([
                .init(layer: layer(weight, additive: additive, id: a.id), animation: a)])
        }
    }
    let renamed = denseClip(2987, root: [pose(2 + 2), pose(2 + 2)], tag: "renamed-ρ")
    output["renamed"] = try denseEvaluation([
        .init(layer: layer(1, additive: false, id: renamed.id), animation: renamed)])
    let sampled = denseClip(1702, root: [pose(9), pose(9)], states: [.sampled, .sampled])
    output["sampled-constant"] = try denseEvaluation([
        .init(layer: layer(1, additive: false, id: sampled.id), animation: sampled)])
    let candidateOnChild = denseClip(1703, root: [pose(9), pose(9)],
        states: [.sampled, .referenceCandidate])
    output["second-bone"] = try denseEvaluation([
        .init(layer: layer(1, additive: false, id: candidateOnChild.id), animation: candidateOnChild)])
    for referenceOpaque in [false, true] {
        let neutral = denseClip()
        let pair: [ScenePuppetAnimationSelection.Clip] = [
            .init(layer: layer(1, additive: !referenceOpaque, id: neutral.id), animation: neutral),
            .init(layer: layer(1, additive: referenceOpaque, id: sampled.id), animation: sampled)]
        output["mixed-\(referenceOpaque)"] = try denseEvaluation(pair)
        output["reordered-\(referenceOpaque)"] = try denseEvaluation(Array(pair.reversed()))
    }
    let alpha = denseClip(alpha: true)
    let alphaClips = [ScenePuppetAnimationSelection.Clip(
        layer: layer(1, additive: false, id: alpha.id), animation: alpha)]
    output["alpha"] = try denseEvaluation(alphaClips)
    output["hidden"] = try denseEvaluation(alphaClips, hidden: true)
    let (mesh, bind) = try fixture()
    let assembled = SceneMdlPuppetRig(bones: bind.bones, vertexWeights: bind.vertexWeights,
        referenceLocalMatricesColumnMajor: bind.bones.map(\.bindLocalMatrixColumnMajor))
    for (label, candidate) in [
        ("nonbind", denseClip(root: [pose(9), pose(9)])),
        ("above-tolerance", denseClip(root: [pose(4.0002), pose(4.0002)])),
        ("varying", denseClip(root: [pose(4), pose(4.00001)])),
        ("state-count", denseClip(states: [.referenceCandidate]))
    ] {
        do {
            _ = try ScenePuppetAnimationEvaluator(mesh: mesh, rig: bind, additiveAnimations: [candidate])
            output[label] = "accepted"
        } catch { output[label] = String(describing: error) }
    }
    output["assembled-rejected"] = rejected {
        try denseEvaluation([.init(layer: layer(1, id: alpha.id), animation: alpha)], rig: assembled)
    }
    output["multiple-opaque-rejected"] = rejected {
        try denseEvaluation([.init(layer: layer(1, additive: false, id: alpha.id), animation: alpha),
            .init(layer: layer(1, additive: false, id: sampled.id), animation: sampled)])
    }
    let close = denseClip(root: [pose(4.00005), pose(4.00005)])
    output["within-tolerance"] = try denseEvaluation([
        .init(layer: layer(1, additive: false, id: close.id), animation: close)])
    return output
}

@main enum Harness {
    static func main() throws {
        var result: [String: Any] = [:]
        result["denseReference"] = try denseReferenceCases()
        for w in [0.0,0.5,1,1.3,2] {
            for (label,additive,extra) in [("base",true,false),("extra",true,true),("opaque",false,false)] {
                result["\(label)-\(w)"] = try evaluate(w,additive: additive,extra: extra)
            }
        }
        let crossAxis = clip(held: pose(30,rotation: SIMD3(0,.pi/6,0),scale: 1.2))
        result["crossAxis"] = try evaluate(1,animation: crossAxis,bindRotation: SIMD3(.pi/4,0,0))
        result["crossAxisExpected"] = columns(ScenePuppetAnimationEvaluator.matrix(from: crossAxis.transformsByBone[0][1]))
        // 270 degrees must use the same hemisphere as -90, rather than turn 135 at half weight.
        result["hemisphere"] = try evaluate(0.5,animation: clip(held: pose(30,rotation: SIMD3(0,0,3 * .pi/2))))
        let set = SceneMdlPuppetAnimationSet(boneCount: 2,animations: [clip()])
        result["selected"] = [0.0,0.5,1,1.3,2].map { w in
            if case .success(.some) = ScenePuppetAnimationSelector.select(layers: [layer(w)],animationSet: set) { return true }
            return false
        }
        result["invalidSelection"] = [-1.0,Double.nan,Double.infinity,Double.greatestFiniteMagnitude].map { w in
            if case .failure = ScenePuppetAnimationSelector.select(layers: [layer(w)],animationSet: set) { return true }
            return false
        }
        result["invalidEvaluation"] = [-1.0,Double.nan,Double.infinity,Double.greatestFiniteMagnitude,
            Double(Float.greatestFiniteMagnitude)].map { w in rejected { try evaluate(w) } }
        result["collapsedWeight2"] = try evaluate(2, animation: clip(held: pose(30, scale: 0.5)))
        for (name, scale) in [("zeroX", SIMD3<Float>(0,1,1)), ("zeroY", SIMD3(1,0,1)),
            ("zeroZ", SIMD3(1,1,0)), ("zeroAll", SIMD3(0,0,0)),
            ("near", SIMD3(repeating: Float(1.0 / 1024))), ("negativeX", SIMD3(-1,1,1)),
            ("negativeYZ", SIMD3(1,-2,-3))] {
            for additive in [false, true] {
                result["forward-\(name)-\(additive)"] = try evaluate(1, additive: additive,
                    animation: clip(held: pose(30, scaleXYZ: scale)))
            }
        }
        let (singularMesh, singularRig) = try fixture(bindScale: 0)
        do {
            _ = try ScenePuppetAnimationEvaluator(mesh: singularMesh, rig: singularRig)
            result["singularBindRejected"] = false
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            result["singularBindRejected"] = failure == .singularBindMatrix(0)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let referenceMesh = try SceneMdlPuppetMeshReader.read(data: data)
        let referenceRig = try SceneMdlPuppetRigReader.read(data: data, mesh: referenceMesh)
        for weight in [0.0, 0.5, 1, 1.3, 2] {
            for additive in [false, true] {
                result["reference-\(additive)-\(weight)"] = try referenceEvaluation(
                    mesh: referenceMesh, rig: referenceRig, weights: [weight], additive: [additive], frames: [1])
            }
        }
        for (key, weights, additive, frames) in [
            ("reference-pair", [1.0, 1.0], [true, true], [1, 1]),
            ("reference-mixed", [1.0, 1.0], [false, true], [1, 1]),
            ("reference-frame0", [1.0, 1.0], [true, true], [0, 0]),
            ("reference-hidden", [1.0, 1.0], [true, true], [nil, nil]),
            ("reference-resumed", [1.0, 1.0], [true, true], [nil, 1]),
            ("reference-single-hidden", [1.0], [false], [nil]),
            ("reference-no-clips", [], [], [])
        ] as [(String, [Double], [Bool], [Int?])] {
            result[key] = try referenceEvaluation(mesh: referenceMesh, rig: referenceRig,
                weights: weights, additive: additive, frames: frames)
        }
        for path in CommandLine.arguments.dropFirst(2) {
            let file = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: file)
            let mesh = try SceneMdlPuppetMeshReader.read(data: data)
            let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
            for (key, weights, additive, frames) in [
                ("empty", [], [], []), ("zero", [0.0], [true], [1])
            ] as [(String, [Double], [Bool], [Int?])] {
                do {
                    _ = try referenceEvaluation(mesh: mesh, rig: rig,
                        weights: weights, additive: additive, frames: frames)
                    result["\(file.deletingPathExtension().lastPathComponent)-\(key)"] = "accepted"
                } catch let failure as ScenePuppetAnimationEvaluationFailure {
                    result["\(file.deletingPathExtension().lastPathComponent)-\(key)"] = failure.description
                }
            }
        }
        // Finite, non-singular world matrices can still overflow when applied to a vertex.
        do {
            _ = try evaluate(1e30,animation: clip(held: pose(4,scale: 1e6)),vertexX: 1e6)
            result["vertexOverflow"] = false
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            result["vertexOverflow"] = failure == .invalidDeformedVertex
        }
        let rx = SIMD3<Float>(.pi/2,0,0), ry = SIMD3<Float>(0,.pi/2,0)
        let rz = SIMD3<Float>(0,0,.pi/2)
        for (name, sourceZ, rotation, bindRotation) in [
            ("x-positive", Float(5), rx, SIMD3<Float>.zero), ("x-negative", -1, rx, .zero),
            ("y-positive", 5, ry, .zero), ("y-negative", -1, ry, .zero),
            ("zero-x", 0, rx, .zero), ("zero-y", 0, ry, .zero),
            ("translation-positive", 5, .zero, .zero), ("translation-negative", -1, .zero, .zero),
            ("z-rotation-positive", 5, rz, .zero), ("z-rotation-negative", -1, rz, .zero),
            ("rotated-bind-x", 5, rx, ry), ("rotated-bind-y", 5, ry, ry)
        ] {
            result["depth-\(name)"] = try depthProjection(SIMD3(6,1,sourceZ),
                rotations: [rotation], bindRotation: bindRotation)
        }
        let axes = [rx, -rx, ry, -ry]
        for slot in 0..<4 {
            var weights = SIMD4<Float>.zero
            weights[slot] = 1
            result["depth-slot-\(slot)"] = try depthProjection(SIMD3(6,1,5), rotations: axes,
                indices: SIMD4(0,1,2,3), weights: weights)
        }
        let mixed = SIMD4<Float>(0.1,0.2,0.3,0.4)
        result["depth-mixed"] = try depthProjection(SIMD3(6,1,5), rotations: axes,
            indices: SIMD4(0,1,2,3), weights: mixed)
        result["depth-mixed-negative"] = try depthProjection(SIMD3(6,1,-1), rotations: axes,
            indices: SIMD4(0,1,2,3), weights: mixed)
        result["depth-normalized"] = try depthProjection(SIMD3(6,1,5), rotations: axes,
            indices: SIMD4(0,1,2,3), weights: mixed * Float(1.00005))
        result["depth-slot-permutation"] = try depthProjection(SIMD3(6,1,5), rotations: axes,
            indices: SIMD4(3,1,0,2), weights: SIMD4(0.4,0.2,0.1,0.3), tag: "slots-renamed", animationID: 917)
        result["depth-bone-permutation"] = try depthProjection(SIMD3(6,1,5),
            rotations: [axes[3],axes[0],axes[2],axes[1]], indices: SIMD4(1,3,2,0),
            weights: mixed, tag: "renamed-κ", animationID: 827)
        do {
            // Direct-IR numeric defense: finite matrices and Z overflow only at projection.
            // The wire reader's smaller authored limits are covered separately.
            _ = try evaluate(1, animation: clip(held: pose(4, rotation: ry,
                scaleXYZ: SIMD3(1,1,1e10))), vertexZ: 1e30)
            result["depthVertexOverflow"] = false
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            result["depthVertexOverflow"] = failure == .invalidDeformedVertex
        }
        print(String(data: try JSONSerialization.data(withJSONObject: result,options: [.sortedKeys]),encoding: .utf8)!)
    }
}
'''


class PuppetWeightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc unavailable")
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-puppet-weights-")
        root = Path(cls.directory.name)
        source, binary = root / "weights.swift", root / "weights"
        source.write_text(HARNESS)
        fixture = root / "reference.mdl"
        fixture.write_bytes(build_rig_mdl(magic=b"MDLV0017", skeleton_marker=b"MDLS0002\0",
            animation_marker=b"MDLA0004\0", bind_matrices=[matrix(4), matrix(2)],
            skeleton_tail=b"\0\0\1" + struct.pack("<32f", *matrix(20), *matrix(7)) + b"uninterpreted suffix"))
        extra_fixtures = []
        for label in ("shear", "singular", "rotated"):
            reference = matrix(20)
            if label == "shear":
                reference[4] = 0.25
            elif label == "singular":
                reference[0] = 0
            else:
                angle = math.pi / 6
                reference[0], reference[1] = 2 * math.cos(angle), 2 * math.sin(angle)
                reference[4], reference[5] = -0.75 * math.sin(angle), 0.75 * math.cos(angle)
            path = root / f"reference-{label}.mdl"
            path.write_bytes(build_rig_mdl(magic=b"MDLV0017", skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0004\0", bind_matrices=[matrix(4), matrix(2)],
                skeleton_tail=b"\0\0\1" + struct.pack("<32f", *reference, *matrix(7))))
            extra_fixtures.append(str(path))
        subprocess.run(["swiftc", "-module-cache-path", str(root / "module-cache"),
                        *map(str, SWIFT_SOURCES), str(source), "-o", str(binary)],
                       check=True, capture_output=True, text=True)
        cls.result = json.loads(subprocess.run([str(binary), str(fixture), *extra_fixtures],
                                              check=True, capture_output=True, text=True).stdout)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_selector_accepts_zero_and_extrapolation_rejects_unrepresentable_weights(self):
        self.assertEqual(self.result["selected"], [True] * 5)
        self.assertEqual(self.result["invalidSelection"], [True] * 4)

    def test_each_track_uses_bind_relative_translation_and_scale(self):
        for role in ("base", "extra", "opaque"):
            for weight in (0.0,0.5,1.0,1.3,2.0):
                with self.subTest(role=role,weight=weight):
                    data = self.result[f"{role}-{weight}"]
                    m = data["local"]
                    self.assertAlmostEqual(m[12], (9 if role == "extra" else 4) + 26 * weight, places=4)
                    self.assertAlmostEqual(math.hypot(m[0],m[1]),1 + 0.2 * weight,places=5)
                    self.assertEqual(data["point"],data["written"])
                    self.assertAlmostEqual(data["childWorld"][12],m[12] + 2*m[0],places=4)

    def test_rotation_uses_shortest_normalized_linear_weight_not_slerp_extrapolation(self):
        for weight in (0.0,0.5,1.0,1.3,2.0):
            expected = 2 * math.atan2(weight * math.sin(math.pi/12),1 + weight * (math.cos(math.pi/12)-1))
            for role in ("base", "extra", "opaque"):
                m = self.result[f"{role}-{weight}"]["local"]
                self.assertAlmostEqual(math.atan2(m[1],m[0]),expected,places=5)
        m = self.result["hemisphere"]["local"]
        self.assertAlmostEqual(math.atan2(m[1],m[0]),-math.pi/4,places=5)

    def test_unit_weight_returns_absolute_sample_with_noncommuting_bind_rotation(self):
        for actual,expected in zip(self.result["crossAxis"]["local"],self.result["crossAxisExpected"]):
            self.assertAlmostEqual(actual,expected,places=5)

    def test_invalid_numeric_pose_and_final_vertex_are_not_publishable(self):
        self.assertEqual(self.result["invalidEvaluation"],[True] * 5)
        self.assertTrue(self.result["singularBindRejected"])
        self.assertTrue(self.result["vertexOverflow"])
        self.assertTrue(self.result["depthVertexOverflow"])

    def test_source_z_reaches_xy_after_bind_relative_cross_axis_rotation(self):
        # Hand-derived from bind T(4,0,2), vertex (6,1,z), target T(10,0,0)R.
        # Rotated-bind cases additionally undo bind Ry90 before the target rotation.
        expected = {"x-positive": (12,-3), "x-negative": (12,3),
                    "y-positive": (13,1), "y-negative": (7,1),
                    "zero-x": (12,2), "zero-y": (8,1),
                    "translation-positive": (12,1), "translation-negative": (12,1),
                    "z-rotation-positive": (9,2), "z-rotation-negative": (9,2),
                    "rotated-bind-x": (7,-2), "rotated-bind-y": (12,1)}
        for name, wanted in expected.items():
            with self.subTest(case=name):
                actual = self.result[f"depth-{name}"]
                self.assertEqual(actual["point"], actual["written"])
                for value, target in zip(actual["point"], wanted):
                    self.assertAlmostEqual(value, target, delta=1e-5)

    def test_four_influence_slots_preserve_depth_and_normalized_mixture(self):
        # Each independently exercised slot has a different analytic signed-Z response.
        expected = {"slot-0": (12,-3), "slot-1": (12,3), "slot-2": (13,1), "slot-3": (7,1),
                    "mixed": (10.3,1), "mixed-negative": (10.9,0.4),
                    "normalized": (10.3,1), "slot-permutation": (10.3,1),
                    "bone-permutation": (10.3,1)}
        for name, wanted in expected.items():
            with self.subTest(case=name):
                actual = self.result[f"depth-{name}"]
                self.assertEqual(actual["point"], actual["written"])
                for value, target in zip(actual["point"], wanted):
                    self.assertAlmostEqual(value, target, delta=1e-5)

    def test_finite_collapsed_near_zero_and_negative_forward_transforms_are_valid(self):
        for name, scale in (("zeroX", (0, 1, 1)), ("zeroY", (1, 0, 1)),
                            ("zeroZ", (1, 1, 0)), ("zeroAll", (0, 0, 0)),
                            ("near", (1 / 1024, 1 / 1024, 1 / 1024)),
                            ("negativeX", (-1, 1, 1)), ("negativeYZ", (1, -2, -3))):
            for additive in (False, True):
                with self.subTest(shape=name, additive=additive):
                    data = self.result[f"forward-{name}-{str(additive).lower()}"]
                    expected = [scale[0], 0, 0, 0, 0, scale[1], 0, 0, 0, 0, scale[2], 0, 30, 0, 0, 1]
                    for actual, wanted in zip(data["local"], expected):
                        self.assertAlmostEqual(actual, wanted, delta=1e-6)
                    self.assertTrue(all(map(math.isfinite, data["childWorld"] + data["point"])))
                    self.assertAlmostEqual(data["childWorld"][12], 30 + 2 * scale[0], places=5)
                    self.assertAlmostEqual(data["point"][0], 30 - 2 * scale[0], places=5)
                    self.assertAlmostEqual(data["point"][1], scale[1], places=5)
                    self.assertEqual(data["point"], data["written"])
        collapsed = self.result["collapsedWeight2"]
        self.assertEqual(collapsed["local"][0], 0)
        self.assertEqual(collapsed["point"], [56, 1])
        self.assertEqual(collapsed["point"], collapsed["written"])

    def assert_reference_pose(self, key, root, child):
        data = self.result[key]
        self.assertAlmostEqual(data["root"], root, places=4)
        self.assertAlmostEqual(data["child"], child, places=4)
        self.assertAlmostEqual(data["childWorld"], root + child, places=4)
        self.assertEqual(data["points"], data["written"])
        # Skinning must retain the original bind world (4 + 2), not the reference world (20 + 7).
        self.assertAlmostEqual(data["points"][0][0], -10 + root - 4, places=4)
        self.assertAlmostEqual(data["points"][2][0], root + child - 6, places=4)

    def test_explicit_reference_weights_are_separate_from_bind_and_frame0(self):
        for additive in (False, True):
            for weight in (0.0, 0.5, 1.0, 1.3, 2.0):
                with self.subTest(additive=additive, weight=weight):
                    self.assert_reference_pose(f"reference-{str(additive).lower()}-{weight}",
                                               20 + 10 * weight, 7 + 3 * weight)

    def test_multiple_clips_share_one_reference_assembly(self):
        self.assert_reference_pose("reference-pair", 50, 15)
        self.assert_reference_pose("reference-mixed", 50, 15)
        self.assert_reference_pose("reference-frame0", 28, 10)

    def test_hidden_missing_and_empty_clips_keep_reference_pose(self):
        for key in ("reference-hidden", "reference-single-hidden", "reference-no-clips"):
            self.assert_reference_pose(key, 20, 7)
        self.assert_reference_pose("reference-resumed", 40, 12)

    def test_reference_trs_validation_precedes_empty_and_zero_weight_frames(self):
        for mode in ("empty", "zero"):
            for shape in ("shear", "singular"):
                self.assertIn("reference local transform 0 is not decomposable",
                              self.result[f"reference-{shape}-{mode}"])
            self.assertEqual(self.result[f"reference-rotated-{mode}"], "accepted")

    def test_dense_reference_tracks_are_neutral_without_stealing_pose_ownership(self):
        result = self.result["denseReference"]
        for key in [f"neutral-{str(a).lower()}-{w}" for a in (False, True)
                    for w in ("0.0", "0.5", "1.0", "2.0")] + ["renamed", "within-tolerance", "hidden"]:
            with self.subTest(key=key):
                self.assertEqual(result[key]["point"], [2, 1])
                self.assertEqual(result[key]["written"], [2, 1])
                if key != "hidden":
                    self.assertTrue(result[key]["invariant"])
        for key in ("sampled-constant", "second-bone", "mixed-false", "mixed-true",
                    "reordered-false", "reordered-true"):
            with self.subTest(key=key):
                self.assertAlmostEqual(result[key]["root"], 9)
                self.assertEqual(result[key]["point"], [7, 1])
                self.assertEqual(result[key]["written"], [7, 1])
        self.assertTrue(result["sampled-constant"]["invariant"])
        self.assertEqual(result["alpha"]["coverage"], .25)
        self.assertFalse(result["alpha"]["invariant"])
        self.assertEqual(result["hidden"]["coverage"], 1)

    def test_dense_reference_profile_rejects_nonbind_varying_assembled_and_ambiguous_inputs(self):
        result = self.result["denseReference"]
        for key in ("nonbind", "above-tolerance", "varying"):
            self.assertIn("reference track 0", result[key])
        self.assertNotEqual(result["state-count"], "accepted")
        self.assertTrue(result["assembled-rejected"])
        self.assertTrue(result["multiple-opaque-rejected"])


if __name__ == "__main__":
    unittest.main()
