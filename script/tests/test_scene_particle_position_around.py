"""Number-valued Position Around CP through the real parser and birth owner."""
from fractions import Fraction
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_particle_simulator import SWIFT_SOURCES

HARNESS = r'''
import Foundation

@main enum Harness {
    static func definition(_ count: Any, renamed: Bool = false,
                           extra: [String: Any] = [:]) -> SceneParticleDefinition {
        var component: [String: Any] = [
            "name": "mapsequencearoundcontrolpoint", "bounds": "0 1", "count": count,
            "limitbehavior": "repeat", "speedmin": "0 0 0", "speedmax": "0 0 0"]
        component.merge(extra) { _, new in new }
        return SceneParticleDefinitionParser().parse(root: [
            "name": renamed ? "unseen angular fixture" : "own circle",
            "material": renamed ? "renamed/white.json" : "own.json", "maxcount": 5,
            "controlpoint": [["id": 0, "flags": 0, "offset": "0 0 0"]],
            "emitter": [["name": "boxrandom", "instantaneous": 5, "rate": 0,
                         "distancemin": "50 0 0", "distancemax": "50 0 0"]],
            "initializer": [["name": "lifetimerandom", "min": 120, "max": 120], component],
            "renderer": [["name": "sprite"]]])
    }

    static func simulator(_ definition: SceneParticleDefinition) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: definition, seed: 43, fixedTimeStep: 0.125)
    }

    static func main() throws {
        var rows: [[String: Any]] = []
        for (label, count, renamed) in [
            ("integer2", 2 as Any, false), ("integer3", 3 as Any, false),
            ("fractional", 2.5 as Any, false), ("renamed", "2.5e0" as Any, true),
            ("trinity-value", 3.02 as Any, false), ("independent-value", 2.2 as Any, true)] {
            let def = definition(count, renamed: renamed)
            let sim = simulator(def)
            sim.advance(by: 0.125)
            let partitioned = simulator(def)
            partitioned.advance(by: 0.25)
            sim.advance(by: 0.125)
            rows.append([
                "label": label, "admitted": def.initializers[1].positionAroundControlPointPlan != nil,
                "positions": sim.particles.map { [$0.position.x, $0.position.y, $0.position.z] },
                "diagnostics": sim.diagnostics.map(\.kind.rawValue),
                "partitioned": sim.particles == partitioned.particles])
        }
        var invalid: [[String: Any]] = []
        for raw: Any in [0, -1, 0.999, 1024.001, "nan", "inf", "bad", true, [2, 3]] {
            let def = definition(raw)
            let sim = simulator(def)
            sim.advance(by: 0.125)
            invalid.append([
                "admitted": def.initializers[1].positionAroundControlPointPlan != nil,
                "preserved": sim.particles.count == 5
                    && sim.particles.allSatisfy { $0.position == SIMD3(50, 0, 0) },
                "diagnostics": sim.diagnostics.map(\.kind.rawValue)])
        }
        let adjacent = [
            ["limitbehavior": "mirror"], ["flags": 1], ["controlpoint": 8],
            ["future": 1], ["bounds": "0.8 0.2"]] as [[String: Any]]
        let adjacentRejected = adjacent.allSatisfy {
            definition(2.5, extra: $0).initializers[1].positionAroundControlPointPlan == nil
        }
        let ids: [UInt64] = [0, 1, 4, 4_294_967_295, 4_294_967_296,
            9_007_199_254_740_991, 9_007_199_254_740_992, 9_007_199_254_740_993,
            UInt64.max - 1, UInt64.max]
        var wide: [[String: Any]] = []
        for count in [1.0, 2.5, 3.02, 2.2, 1024.0, 1.0.nextUp, 1024.0.nextDown] {
            let def = definition(count)
            let sim = simulator(def)
            sim.advance(by: 0.125)
            guard let plan = def.initializers[1].positionAroundControlPointPlan else { continue }
            for id in ids {
                var particle = SceneParticleState(
                    id: id, position: SIMD3(50, 0, 0), velocity: .zero,
                    color: .init(repeating: 1), alpha: 1, size: 8,
                    rotation: .zero, angularVelocity: .zero, age: 0, lifetime: 120,
                    initialColor: .init(repeating: 1), initialAlpha: 1, initialSize: 8)
                let applied = sim.applyPositionAroundControlPoint(plan, to: &particle)
                wide.append(["count": count, "id": String(id), "applied": applied,
                             "position": [particle.position.x, particle.position.y, particle.position.z]])
            }
        }
        let result: [String: Any] = ["rows": rows, "invalid": invalid,
                                    "adjacentRejected": adjacentRejected, "wide": wide]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
'''


class SceneParticlePositionAroundTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("swiftc")
        if compiler is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-position-around-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        source = directory / "Harness.swift"
        source.write_text(HARNESS)
        binary = directory / "harness"
        build = subprocess.run([compiler, "-module-cache-path", str(directory / "modules"),
                                *map(str, SWIFT_SOURCES), str(source), "-o", str(binary)],
                               capture_output=True, text=True, timeout=150)
        if build.returncode:
            raise RuntimeError(build.stderr)
        run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15, check=True)
        cls.result = json.loads(run.stdout)

    def test_fractional_counts_reach_births_without_rounding(self):
        for row in self.result["rows"]:
            with self.subTest(label=row["label"]):
                self.assertTrue(row["admitted"])
                self.assertTrue(row["partitioned"])
                self.assertEqual(len(row["positions"]), 5)
                self.assertIn("positionAroundControlPointBounded", row["diagnostics"])
                self.assertNotIn("positionAroundControlPointUnsupported", row["diagnostics"])
        rows = {row["label"]: row for row in self.result["rows"]}
        for label, distinct in [("integer2", 2), ("integer3", 3), ("fractional", 5)]:
            points = rows[label]["positions"]
            self.assertEqual(len({tuple(round(v, 6) for v in point) for point in points}), distinct)
        self.assertEqual(rows["fractional"]["positions"], rows["renamed"]["positions"])
        # Rotation-independent oracle from the preregistered official N3 board.
        points = rows["fractional"]["positions"][:3]
        chords = sorted(math.dist(a, b) / 50 for i, a in enumerate(points) for b in points[i + 1:])
        for actual, expected in zip(chords, [1.1755705046, 1.9021130326, 1.9021130326]):
            self.assertAlmostEqual(actual, expected, places=8)

    def test_large_identity_positions_match_exact_rational_remainder(self):
        self.assertEqual(len(self.result["wide"]), 70)
        for row in self.result["wide"]:
            with self.subTest(count=row["count"], identity=row["id"]):
                self.assertTrue(row["applied"])
                count = Fraction.from_float(row["count"])
                cycles = Fraction(int(row["id"])) / count
                phase = float(cycles - cycles.numerator // cycles.denominator)
                expected = [50 * math.cos(phase * math.tau), 50 * math.sin(phase * math.tau), 0]
                for actual, value in zip(row["position"], expected):
                    self.assertAlmostEqual(actual, value, delta=1e-10)

    def test_invalid_counts_preserve_emitter_and_adjacent_profiles_stay_rejected(self):
        self.assertEqual(len(self.result["invalid"]), 9)
        for row in self.result["invalid"]:
            self.assertFalse(row["admitted"])
            self.assertTrue(row["preserved"])
            self.assertIn("positionAroundControlPointUnsupported", row["diagnostics"])
        self.assertTrue(self.result["adjacentRejected"])


if __name__ == "__main__":
    unittest.main()
