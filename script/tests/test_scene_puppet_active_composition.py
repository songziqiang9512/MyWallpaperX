#!/usr/bin/env python3
"""Hidden prepared peers preserve one active absolute clip's full vertex pose."""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_puppet_direct_skinning import SWIFT_SOURCES


HARNESS = r'''
import Foundation
import simd

@main enum ActiveCompositionHarness {
    struct Input: Decodable {
        let name: String
        let kind: String
        let ordinal: Int
        let weight: Double
        let fraction: Float
        let blendOverride: Double?
        let renamed: Bool
    }

    static func flatten(_ value: simd_float4x4) -> [Float] {
        [value.columns.0, value.columns.1, value.columns.2, value.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    static func pose(_ translation: SIMD3<Float> = .zero,
                     _ rotation: SIMD3<Float> = .zero,
                     _ scale: SIMD3<Float> = SIMD3(repeating: 1))
        -> SceneMdlPuppetAnimation.Transform {
        .init(translation: translation, rotation: rotation, scale: scale)
    }

    static func layer(_ id: Int, _ animation: Int, _ additive: Bool,
                      _ weight: Double) -> ScenePuppetAnimationLayer {
        .init(id: id, animationID: animation, name: "prepared-peer", additive: additive,
              blend: weight, blendIn: false, blendOut: false, blendTime: 0,
              rate: 1, visible: false, visibilityBinding: "own-key")
    }

    static func render(_ evaluator: ScenePuppetAnimationEvaluator,
                       _ vertices: [SceneMdlStaticModel.Vertex],
                       _ selection: ScenePuppetAnimationSelection,
                       _ samples: [ScenePuppetAnimationEvaluator.FrameSample?],
                       _ blends: [Double]?) throws -> [String: Any] {
        var output = vertices
        var local = [matrix_identity_float4x4], skin = local, world = local
        try output.withUnsafeMutableBufferPointer {
            try evaluator.writeDeformedVertices(bindVertices: vertices, selection: selection,
                frameSamples: samples, into: $0, localMatricesScratch: &local,
                skinMatricesScratch: &skin, worldMatricesScratch: &world, blends: blends)
        }
        var xy = Array(repeating: SIMD2<Float>.zero, count: vertices.count)
        try xy.withUnsafeMutableBufferPointer {
            try evaluator.writeDeformedPositions(selection: selection, frameSamples: samples,
                into: $0, localMatricesScratch: &local, skinMatricesScratch: &skin,
                worldMatricesScratch: &world, blends: blends)
        }
        return ["local": local.map(flatten), "vertices": output.enumerated().map { index, v in
            ["position": [v.position.x, v.position.y, v.position.z],
             "normal": [v.normal.x, v.normal.y, v.normal.z],
             "tangent": [v.tangent.x, v.tangent.y, v.tangent.z, v.tangent.w],
             "uv": [v.uv.x, v.uv.y], "imageXY": [xy[index].x, xy[index].y]]
        }]
    }

    static func run(_ input: Input) throws -> [String: Any] {
        let bindT = SIMD3<Float>(3, 24, -0.25)
        let bind = flatten(SceneMatrix.translation(bindT))
        let vertices = [
            SceneMdlStaticModel.Vertex(position: SIMD3(1, 2, 3), normal: SIMD3(2, 1, 3),
                tangent: SIMD4(1, -2, 1, -1), uv: SIMD2(0.25, 0.75)),
            .init(position: SIMD3(-2, 5, 7), normal: SIMD3(-1, 2, 1),
                  tangent: SIMD4(2, 1, -1, 1), uv: SIMD2(0.8, 0.2))
        ]
        let rig = SceneMdlPuppetRig(bones: [.init(name: input.renamed ? "renamed" : "joint",
            parentIndex: -1, bindLocalMatrixColumnMajor: bind)],
            vertexWeights: vertices.map { _ in .init(boneIndices: .zero, boneWeights: SIMD4(1, 0, 0, 0)) })
        let baseID = input.renamed ? 817 : 10
        let activeID = baseID + input.ordinal
        var clips: [ScenePuppetAnimationSelection.Clip] = []
        for index in 0..<3 {
            let active = index == input.ordinal
            let kind = input.kind
            let crossesBoundary = active && kind.hasPrefix("cross")
            let first = kind == "reference" ? pose(bindT)
                : (crossesBoundary ? pose(.zero, SIMD3(0, 0, .pi * 17 / 18)) : pose())
            let last: SceneMdlPuppetAnimation.Transform
            if active && kind == "euler" {
                last = pose(SIMD3(4, 8, -4), SIMD3(.pi / 2, .pi / 2, 0), SIMD3(2, 3, 4))
            } else if crossesBoundary {
                let z: Float = kind == "cross-equivalent" ? .pi * 19 / 18 : -.pi * 17 / 18
                last = pose(.zero, SIMD3(0, 0, z))
            } else if kind == "multi-absolute" || kind == "mixed" {
                last = pose(index == 0 ? SIMD3(6, 11, 1) : SIMD3(4, 2, 3))
            } else { last = kind == "reference" ? first : pose() }
            let frames = (kind == "multi-absolute" || kind == "mixed") ? [last, last] : [first, last]
            let animation = SceneMdlPuppetAnimation(id: baseID + index,
                name: input.renamed ? "renamed-motion" : "motion", mode: "loop",
                framesPerSecond: 1, frameCount: 1, transformsByBone: [frames],
                transformTrackStates: kind == "reference" && active ? [.referenceCandidate] : [.sampled],
                alphaByBone: kind == "multi-alpha" && index < 2 ? [[0.5, 0.5]] : nil)
            let additive = (kind == "one-additive" && active) || (kind == "mixed" && index == 1)
            clips.append(.init(layer: layer(100 + index, animation.id, additive,
                (kind == "multi-absolute" || kind == "mixed") ? 1 : (active ? input.weight : 0.8)), animation: animation))
        }
        let set = SceneMdlPuppetAnimationSet(boneCount: 1, animations: clips.map(\.animation))
        let selector = ScenePuppetAnimationSelector.select(layers: clips.map(\.layer), animationSet: set)
        let selection: ScenePuppetAnimationSelection
        switch selector {
        case .success(let selected?): selection = selected
        case .success(nil): return ["name": input.name, "error": "empty selection"]
        case .failure(let failure):
            return ["name": input.name, "selectorRejected": failure.description]
        }
        let evaluator = try ScenePuppetAnimationEvaluator(bindPositions: vertices.map(\.position),
            rig: rig, additiveAnimations: clips.map(\.animation))
        let reverse = input.kind == "cross-reverse"
        let sample = ScenePuppetAnimationEvaluator.FrameSample(frameA: reverse ? 1 : 0,
            frameB: reverse ? 0 : 1, fraction: input.fraction)
        var samples: [ScenePuppetAnimationEvaluator.FrameSample?] = [nil, nil, nil]
        if input.kind != "none" { samples[input.ordinal] = sample }
        if input.kind == "multi-absolute" || input.kind == "mixed" {
            samples[0] = sample; samples[1] = sample
        }
        let blends = input.blendOverride.map { weight in clips.indices.map { $0 == input.ordinal ? weight : 0.9 } }
        var result: [String: Any] = ["name": input.name, "composition": selection.composition.rawValue,
            "activeID": activeID, "activeOrdinal": input.ordinal]
        do {
            result["prepared"] = try render(evaluator, vertices, selection, samples, blends)
            let active = clips[input.ordinal]
            let single = ScenePuppetAnimationSelection(clips: [active], composition: .singleAbsolute)
            result["single"] = try render(evaluator, vertices, single, [samples[input.ordinal]],
                input.blendOverride.map { [$0] })
            if input.kind == "euler" || input.kind.hasPrefix("cross") {
                result["preparedConvenienceXY"] = try evaluator.deformedPositions(
                    animation: active.animation, frameSample: sample).map { [$0.x, $0.y] }
                let convenience = try ScenePuppetAnimationEvaluator(
                    bindPositions: vertices.map(\.position), rig: rig)
                result["unpreparedConvenienceXY"] = try convenience.deformedPositions(
                    animation: active.animation, frameSample: sample).map { [$0.x, $0.y] }
            }
            // Preserve the former malformed-single convenience behavior: no partial pose.
            if input.kind == "none" || (input.kind == "identity" && input.ordinal == 2 && input.weight == 1) {
                result["invalidSingleCount"] = try render(evaluator, vertices,
                    .init(clips: clips, composition: .singleAbsolute), samples, blends)
            }
        } catch { result["error"] = String(describing: error) }
        return result
    }

    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let inputs = try JSONDecoder().decode([Input].self, from: data)
        let result = try inputs.map(run)
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


def case(name, kind="identity", ordinal=0, weight=1, fraction=0.5, override=None, renamed=False):
    return dict(name=name, kind=kind, ordinal=ordinal, weight=weight,
                fraction=fraction, blendOverride=override, renamed=renamed)


CASES = [case(f"identity-{ordinal}-{weight}", ordinal=ordinal, weight=weight)
         for ordinal in range(3) for weight in (0, 0.5, 1, 1.5)]
CASES += [case("override-last", ordinal=2, weight=1.5, override=0.25),
          case("renamed", ordinal=1, renamed=True),
          case("euler-quarter", "euler", ordinal=2, fraction=0.25),
          case("euler-half", "euler", ordinal=1),
          *[case(kind, kind, ordinal=0) for kind in
            ("none", "one-additive", "multi-absolute", "mixed", "reference", "multi-alpha")]]
CROSS_CASES = [case(f"cross-{fraction}", "cross", ordinal=index % 3, fraction=fraction,
                    renamed=fraction == 0.75)
               for index, fraction in enumerate((0, 0.25, 0.5, 0.75, 1))]
CROSS_CASES += [case(f"{kind}-{fraction}", kind, ordinal=2, fraction=fraction,
                     renamed=kind == "cross-equivalent")
                for kind in ("cross-equivalent", "cross-reverse") for fraction in (0.25, 0.5, 0.75)]
CASES += CROSS_CASES

POSITIONS = [(1, 2, 3), (-2, 5, 7)]
NORMALS = [(2, 1, 3), (-1, 2, 1)]
TANGENTS = [(1, -2, 1, -1), (2, 1, -1, 1)]
BIND = (3, 24, -0.25)


def axis_angle(vector, axis, angle):
    """Independent Rodrigues rotation; no quaternion or evaluator implementation."""
    length = math.sqrt(sum(value * value for value in axis))
    x, y, z = [value / length for value in axis]
    vx, vy, vz = vector
    c, s = math.cos(angle), math.sin(angle)
    dot = x * vx + y * vy + z * vz
    cross = (y * vz - z * vy, z * vx - x * vz, x * vy - y * vx)
    return [c * value + s * perpendicular + (1 - c) * dot * direction
            for value, perpendicular, direction in zip(vector, cross, (x, y, z), strict=True)]


class ScenePuppetActiveCompositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        retained = os.environ.get("MWX_PUPPET_ACTIVE_OUTPUT")
        cls.temporary = None if retained else tempfile.TemporaryDirectory(prefix="mwx-active-pose-")
        cls.directory = Path(retained or cls.temporary.name)
        cls.directory.mkdir(parents=True, exist_ok=True)
        harness = cls.directory / "Harness.swift"
        harness.write_text(HARNESS)
        inputs = cls.directory / "cases.json"
        inputs.write_text(json.dumps(CASES, indent=2))
        paths = list(dict.fromkeys([Path(__file__), *SWIFT_SOURCES, harness, inputs]))
        identities = lambda: {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        before = identities()
        (cls.directory / "inputs-before.json").write_text(json.dumps(before, indent=2))
        binary = cls.directory / "active-pose"
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, dict.fromkeys(SWIFT_SOURCES)),
                   str(harness), "-module-cache-path", str(cls.directory / "module-cache"), "-o", str(binary)]
        (cls.directory / "compile-command.json").write_text(json.dumps(command, indent=2))
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=90)
        (cls.directory / "compile.stdout").write_text(compiled.stdout)
        (cls.directory / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary), str(inputs)], capture_output=True, text=True, timeout=30)
        (cls.directory / "raw.stdout").write_text(completed.stdout)
        (cls.directory / "raw.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.rows = {row["name"]: row for row in json.loads(completed.stdout)}
        after = identities()
        (cls.directory / "inputs-after.json").write_text(json.dumps(after, indent=2))
        cls.source_drift = {path: [sha, after[path]] for path, sha in before.items() if after[path] != sha}

    @classmethod
    def tearDownClass(cls):
        if cls.temporary:
            cls.temporary.cleanup()

    def vector(self, actual, expected, tolerance=3e-5):
        self.assertEqual(len(actual), len(expected))
        for value, target in zip(actual, expected, strict=True):
            self.assertTrue(math.isfinite(value))
            self.assertAlmostEqual(value, target, delta=tolerance)

    def parity(self, row):
        self.assertNotIn("error", row, row)
        self.assertEqual(row["composition"], "layered")
        for actual, expected in zip(row["prepared"]["local"], row["single"]["local"], strict=True):
            self.vector(actual, expected, 1e-6)
        for actual, expected in zip(row["prepared"]["vertices"], row["single"]["vertices"], strict=True):
            for channel in ("position", "normal", "tangent", "uv", "imageXY"):
                self.vector(actual[channel], expected[channel], 1e-6)

    def test_identity_sampled_is_not_absent_and_hidden_peers_are_neutral(self):
        for ordinal in range(3):
            for weight in (0, 0.5, 1, 1.5):
                with self.subTest(ordinal=ordinal, weight=weight):
                    row = self.rows[f"identity-{ordinal}-{weight}"]
                    self.parity(row)
                    for i, vertex in enumerate(row["prepared"]["vertices"]):
                        expected = [p - weight * b for p, b in zip(POSITIONS[i], BIND, strict=True)]
                        self.vector(vertex["position"], expected)
                        self.vector(vertex["normal"], NORMALS[i])
                        self.vector(vertex["tangent"], TANGENTS[i])

    def test_blend_override_uses_active_ordinal_and_renamed_inputs(self):
        self.parity(self.rows["override-last"])
        for i, vertex in enumerate(self.rows["override-last"]["prepared"]["vertices"]):
            self.vector(vertex["position"], [p - 0.25 * b for p, b in zip(POSITIONS[i], BIND)])
        self.parity(self.rows["renamed"])
        self.assertEqual(self.rows["renamed"]["prepared"], self.rows["identity-1-1"]["prepared"])

    def test_fraction_uses_orientation_arc_and_preserves_affine_vertex_frames(self):
        for name, fraction in (("euler-quarter", 0.25), ("euler-half", 0.5)):
            row = self.rows[name]
            self.parity(row)
            scale = [1 + fraction, 1 + 2 * fraction, 1 + 3 * fraction]
            translation = [4 * fraction, 8 * fraction, -4 * fraction]
            # eulerXYZ applies X then Y: Ry(90)Rx(90) is a120-degree
            # rotation about(1,1,-1). Interpolate this orientation arc.
            angle = math.pi * 2 / 3 * fraction
            for i, vertex in enumerate(row["prepared"]["vertices"]):
                point = axis_angle([(p-b)*s for p, b, s in zip(POSITIONS[i], BIND, scale)],
                                   (1, 1, -1), angle)
                self.vector(vertex["position"], [p+t for p, t in zip(point, translation)])
                self.vector(vertex["normal"], axis_angle([n/s for n, s in zip(NORMALS[i], scale)],
                                                       (1, 1, -1), angle))
                self.vector(vertex["tangent"][:3], axis_angle([t*s for t, s in zip(TANGENTS[i][:3], scale)],
                                                            (1, 1, -1), angle))
                self.assertEqual(vertex["tangent"][3], TANGENTS[i][3])
                self.vector(vertex["imageXY"], vertex["position"][:2])

    def test_periodic_angles_short_arc_reverse_endpoints_and_renamed_peers(self):
        for item in CROSS_CASES:
            with self.subTest(name=item["name"]):
                row = self.rows[item["name"]]
                self.parity(row)
                fraction = 1 - item["fraction"] if item["kind"] == "cross-reverse" else item["fraction"]
                angle = math.radians(170 + 20 * fraction)
                for i, vertex in enumerate(row["prepared"]["vertices"]):
                    self.vector(vertex["position"], axis_angle(
                        [p-b for p, b in zip(POSITIONS[i], BIND)], (0, 0, 1), angle))
                    self.vector(vertex["normal"], axis_angle(NORMALS[i], (0, 0, 1), angle))
                    self.vector(vertex["tangent"][:3], axis_angle(TANGENTS[i][:3], (0, 0, 1), angle))
                    self.assertEqual(vertex["tangent"][3], TANGENTS[i][3])
                    self.vector(vertex["imageXY"], vertex["position"][:2])

    def test_prepared_and_unprepared_convenience_share_orientation_sampling(self):
        for item in CASES:
            if item["kind"] != "euler" and not item["kind"].startswith("cross"):
                continue
            with self.subTest(name=item["name"]):
                row = self.rows[item["name"]]
                self.assertNotIn("error", row, row)
                expected = [vertex["imageXY"] for vertex in row["prepared"]["vertices"]]
                for key in ("preparedConvenienceXY", "unpreparedConvenienceXY"):
                    for actual, target in zip(row[key], expected, strict=True):
                        self.vector(actual, target)

    def test_zero_active_and_additive_identity_keep_reference_pose(self):
        for name in ("none", "one-additive"):
            row = self.rows[name]
            self.assertNotIn("error", row, row)
            for i, vertex in enumerate(row["prepared"]["vertices"]):
                self.vector(vertex["position"], POSITIONS[i])
                self.vector(vertex["normal"], NORMALS[i])
                self.vector(vertex["tangent"], TANGENTS[i])
        self.assertEqual(self.rows["none"]["invalidSingleCount"], self.rows["none"]["prepared"])
        self.assertEqual(self.rows["identity-2-1"]["invalidSingleCount"], self.rows["none"]["prepared"])

    def test_multiple_active_keeps_first_opaque_and_existing_additive_delta(self):
        for name, local in (("multi-absolute", (6, 11, 1)), ("mixed", (7, -11, 4.25))):
            row = self.rows[name]
            self.assertNotIn("error", row, row)
            for i, vertex in enumerate(row["prepared"]["vertices"]):
                self.vector(vertex["position"], [p+l-b for p, l, b in zip(POSITIONS[i], local, BIND)])

    def test_reference_and_multiple_alpha_preparation_still_reject(self):
        for name in ("reference", "multi-alpha"):
            self.assertIn("outside the bounded playback profile", self.rows[name]["selectorRejected"])
            self.assertNotIn("prepared", self.rows[name])

    def test_frozen_real_sources_do_not_change_during_gate(self):
        self.assertEqual(self.source_drift, {})


if __name__ == "__main__":
    unittest.main()
