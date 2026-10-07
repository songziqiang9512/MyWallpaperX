#!/usr/bin/env python3
"""Static Puppet weights: public black-box contract, plus numerical safety."""
import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_playback import SWIFT_SOURCES

HARNESS = r'''
import Foundation
import simd

func layer(_ weight: Double, additive: Bool = true, id: Int = 1) -> ScenePuppetAnimationLayer {
    .init(id: id, animationID: id, name: "weight", additive: additive, blend: weight,
          blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: true,
          visibilityBinding: nil)
}
func pose(_ x: Float, rotation: SIMD3<Float> = .zero, scale: Float = 1)
    -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(x, 0, 0), rotation: rotation, scale: SIMD3(scale, 1, 1))
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
func fixture(bindRotation: SIMD3<Float> = .zero, vertexX: Float = 2)
    throws -> (SceneMdlPuppetMesh, SceneMdlPuppetRig) {
    let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
        meshBlockOffset: 9, vertices: [.init(x: vertexX,y: 1,z: 0,u: 0,v: 0)], indices: [0,0,0])
    let rig = SceneMdlPuppetRig(bones: [
        .init(parentIndex: -1, bindLocalMatrixColumnMajor:
            columns(SceneMatrix.translation(SIMD3(4,0,0)) * SceneMatrix.eulerXYZ(bindRotation))),
        .init(parentIndex: 0, bindLocalMatrixColumnMajor: columns(SceneMatrix.translation(SIMD3(2,0,0))))
    ], vertexWeights: [.init(boneIndices: SIMD4(1,0,0,0), boneWeights: SIMD4(1,0,0,0))])
    return (mesh, rig)
}
func evaluate(_ weight: Double, additive: Bool = true, extra: Bool = false,
              animation: SceneMdlPuppetAnimation = clip(), bindRotation: SIMD3<Float> = .zero,
              vertexX: Float = 2) throws -> [String: Any] {
    let (mesh, rig) = try fixture(bindRotation: bindRotation, vertexX: vertexX)
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
@main enum Harness {
    static func main() throws {
        var result: [String: Any] = [:]
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
        result["singular"] = rejected { try evaluate(2,animation: clip(held: pose(30,scale: 0.5))) }
        // Finite, non-singular world matrices can still overflow when applied to a vertex.
        do {
            _ = try evaluate(1e30,animation: clip(held: pose(4,scale: 1e6)),vertexX: 1e6)
            result["vertexOverflow"] = false
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            result["vertexOverflow"] = failure == .invalidDeformedVertex
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
        subprocess.run(["swiftc", *map(str, SWIFT_SOURCES), str(source), "-o", str(binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(subprocess.run([str(binary)], check=True, capture_output=True, text=True).stdout)

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
        self.assertTrue(self.result["singular"])
        self.assertTrue(self.result["vertexOverflow"])


if __name__ == "__main__":
    unittest.main()
