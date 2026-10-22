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
                           extra: [String: Any] = [:], omitted: [String] = [],
                           followingRandom: Bool = false, withoutPosition: Bool = false) -> SceneParticleDefinition {
        var component: [String: Any] = [
            "name": "mapsequencearoundcontrolpoint", "bounds": "0 1", "count": count,
            "limitbehavior": "repeat", "speedmin": "0 0 0", "speedmax": "0 0 0"]
        component.merge(extra) { _, new in new }
        for key in omitted { component.removeValue(forKey: key) }
        var initializers: [[String: Any]] = [["name": "lifetimerandom", "min": 120, "max": 120]]
        if !withoutPosition { initializers.append(component) }
        if followingRandom { initializers.append(["name": "sizerandom", "min": 3, "max": 9]) }
        return SceneParticleDefinitionParser().parse(root: [
            "name": renamed ? "unseen angular fixture" : "own circle",
            "material": renamed ? "renamed/white.json" : "own.json", "maxcount": 5,
            "controlpoint": [["id": 0, "flags": 0, "offset": "0 0 0"]],
            "emitter": [["name": "boxrandom", "instantaneous": 5, "rate": 0,
                         "distancemin": "50 0 0", "distancemax": "50 0 0"]],
            "initializer": initializers,
            "renderer": [["name": "sprite"]]])
    }

    static func simulator(_ definition: SceneParticleDefinition) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: definition, seed: 43, fixedTimeStep: 0.125)
    }


    static let defaultFields = ["bounds", "limitbehavior", "speedmin", "speedmax"]

    static func rawNilFields(_ definition: SceneParticleDefinition) -> [String] {
        guard case let .positionAroundControlPoint(raw) = definition.initializers[1].kind else {
            return ["unexpected-kind"]
        }
        return [("bounds", raw.bounds == nil), ("limitbehavior", raw.limitBehavior == nil),
                ("speedmin", raw.speedMinimum == nil), ("speedmax", raw.speedMaximum == nil)]
            .filter { $0.1 }.map { $0.0 }.sorted()
    }

    static func birthComparison(_ definition: SceneParticleDefinition,
                                reference: SceneParticleDefinition) -> [String: Any] {
        let sim = simulator(definition), peer = simulator(reference)
        sim.advance(by: 0.125)
        peer.advance(by: 0.125)
        let state = sim.frameSnapshot(), expected = peer.frameSnapshot()
        var following = state.random, expectedFollowing = expected.random
        let next = following.value(-7, 9), expectedNext = expectedFollowing.value(-7, 9)
        var row: [String: Any] = [
            "admitted": definition.initializers[1].positionAroundControlPointPlan != nil,
            "rawNil": rawNilFields(definition),
            "planEqual": definition.initializers[1].positionAroundControlPointPlan
                == reference.initializers[1].positionAroundControlPointPlan,
            "particleCount": sim.particles.count, "birthStatesEqual": sim.particles == peer.particles,
            "stateEqual": state.random.state == expected.random.state
                && state.nextParticleID == expected.nextParticleID
                && state.simulationTime.bitPattern == expected.simulationTime.bitPattern,
            "followingRandomEqual": next.bitPattern == expectedNext.bitPattern
                && following.state == expectedFollowing.state,
            "randomState": String(state.random.state), "followingRandomBits": String(next.bitPattern),
            "followingSizes": sim.particles.map(\.size),
            "positions": sim.particles.map { [$0.position.x, $0.position.y, $0.position.z] },
            "velocities": sim.particles.map { [$0.velocity.x, $0.velocity.y, $0.velocity.z] },
            "diagnostics": sim.diagnostics.map(\.kind.rawValue)]
        if let plan = definition.initializers[1].positionAroundControlPointPlan {
            row["bounds"] = [plan.bounds.lowerBound, plan.bounds.upperBound]
            row["speedmin"] = [plan.speedMinimum.x, plan.speedMinimum.y, plan.speedMinimum.z]
            row["speedmax"] = [plan.speedMaximum.x, plan.speedMaximum.y, plan.speedMaximum.z]
        }
        return row
    }

    static func speedDrawSequence(_ definition: SceneParticleDefinition) -> [String: Any] {
        let sim = simulator(definition)
        sim.advance(by: 0.125)
        guard let plan = definition.initializers[1].positionAroundControlPointPlan,
              var particle = sim.particles.first else { return ["applied": false] }
        let before = sim.frameSnapshot().random
        var expected = before
        // Existing RNG API supplies an independent exact three-draw oracle.
        // Both zero speed vectors must still consume one shared draw per axis.
        for _ in 0..<3 { _ = expected.unit() }
        let applied = sim.applyPositionAroundControlPoint(plan, to: &particle)
        var following = sim.frameSnapshot().random
        let after = following.state, expectedAfter = expected.state
        let next = following.value(-7, 9), expectedNext = expected.value(-7, 9)
        return ["applied": applied, "before": String(before.state), "after": String(after),
                "expectedAfterThreeDraws": String(expectedAfter),
                "exactlyThreeDraws": after == expectedAfter && after != before.state,
                "followingRandomEqual": next.bitPattern == expectedNext.bitPattern
                    && following.state == expected.state]
    }

    static func omissionResults() -> [String: Any] {
        let reference = definition(5, followingRandom: true)
        var combinations: [[String: Any]] = []
        for mask in 0..<(1 << defaultFields.count) {
            let omitted = defaultFields.enumerated().compactMap { index, key in
                mask & (1 << index) == 0 ? nil : key
            }
            let def = definition(5, omitted: omitted, followingRandom: true)
            var row = birthComparison(def, reference: reference)
            row["omitted"] = omitted.sorted()
            combinations.append(row)
        }
        let equivalent = definition("5e0", renamed: true, extra: [
            "id": 917, "bounds": ["value": "0e0 1e0"], "limitbehavior": " REPEAT ",
            "speedmin": [0, 0, 0], "speedmax": "0e0, 0e0, 0e0"], followingRandom: true)
        let renamedOmitted = definition("5e0", renamed: true, extra: ["id": 739],
                                        omitted: defaultFields, followingRandom: true)
        let absent = definition(5, followingRandom: true, withoutPosition: true)
        var rejected: [[String: Any]] = []
        func reject(_ label: String, _ extra: [String: Any], omitted: [String] = []) {
            let def = definition(5, extra: extra, omitted: omitted, followingRandom: true)
            var row = birthComparison(def, reference: absent)
            row["label"] = label
            rejected.append(row)
        }
        let wrongTypes: [String: Any] = ["bounds": true, "limitbehavior": ["repeat"],
                                         "speedmin": 7, "speedmax": "0 0"]
        for key in defaultFields {
            reject("null-" + key, [key: NSNull()])
            reject("wrong-type-" + key, [key: wrongTypes[key]!])
            reject("empty-" + key, [key: ""])
        }
        reject("missing-count", [:], omitted: ["count"])
        reject("null-count", ["count": NSNull()])
        reject("missing-min-unordered", ["speedmax": "0 -1 0"], omitted: ["speedmin"])
        reject("missing-max-unordered", ["speedmin": "0 1 0"], omitted: ["speedmax"])
        let minMissing = definition(5, extra: ["speedmax": "0 4 0"],
                                    omitted: ["speedmin"], followingRandom: true)
        let minExplicit = definition(5, extra: ["speedmax": "0 4 0"], followingRandom: true)
        let maxMissing = definition(5, extra: ["speedmin": "0 -4 0"],
                                    omitted: ["speedmax"], followingRandom: true)
        let maxExplicit = definition(5, extra: ["speedmin": "0 -4 0"], followingRandom: true)
        let half = definition(5, extra: ["bounds": "0.25 0.75", "speedmin": "0 2 0",
                                        "speedmax": "0 2 0"], followingRandom: true)
        return ["combinations": combinations,
                "variants": [birthComparison(equivalent, reference: reference),
                             birthComparison(renamedOmitted, reference: reference)],
                "rejected": rejected,
                "singleEndpoints": [birthComparison(minMissing, reference: minExplicit),
                                    birthComparison(maxMissing, reference: maxExplicit)],
                "explicitHalf": birthComparison(half, reference: half),
                "speedDrawSequences": [speedDrawSequence(reference), speedDrawSequence(renamedOmitted)]]
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
                                    "adjacentRejected": adjacentRejected, "wide": wide,
                                    "defaults": omissionResults()]
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

    def assert_birth_match(self, row):
        self.assertTrue(row["admitted"])
        self.assertTrue(row["planEqual"])
        self.assertEqual(row["particleCount"], 5)
        self.assertTrue(row["birthStatesEqual"])
        self.assertTrue(row["stateEqual"])
        self.assertTrue(row["followingRandomEqual"])
        self.assertTrue(all(3 <= size <= 9 for size in row["followingSizes"]))
        self.assertIn("positionAroundControlPointBounded", row["diagnostics"])
        self.assertNotIn("positionAroundControlPointUnsupported", row["diagnostics"])

    def test_four_field_omissions_preserve_raw_plan_births_and_shared_rng(self):
        defaults = self.result["defaults"]
        self.assertEqual(len(defaults["combinations"]), 16)
        self.assertEqual(len({tuple(row["omitted"]) for row in defaults["combinations"]}), 16)
        for row in defaults["combinations"]:
            with self.subTest(omitted=row["omitted"]):
                self.assertEqual(row["rawNil"], row["omitted"])
                self.assert_birth_match(row)
        self.assertEqual(len(defaults["variants"]), 2)
        for row in defaults["variants"]:
            self.assert_birth_match(row)
        self.assertEqual(defaults["variants"][0]["rawNil"], [])
        self.assertEqual(defaults["variants"][1]["rawNil"],
                         ["bounds", "limitbehavior", "speedmax", "speedmin"])
        for row in defaults["speedDrawSequences"]:
            self.assertTrue(row["applied"])
            self.assertTrue(row["exactlyThreeDraws"])
            self.assertTrue(row["followingRandomEqual"])
            self.assertNotEqual(row["before"], row["after"])
            self.assertEqual(row["after"], row["expectedAfterThreeDraws"])

    def test_present_invalid_defaults_and_missing_count_preserve_emitter_and_rng(self):
        rejected = self.result["defaults"]["rejected"]
        self.assertEqual(len(rejected), 16)
        for row in rejected:
            with self.subTest(label=row["label"]):
                self.assertFalse(row["admitted"])
                self.assertEqual(row["particleCount"], 5)
                self.assertTrue(row["birthStatesEqual"])
                self.assertTrue(row["stateEqual"])
                self.assertTrue(row["followingRandomEqual"])
                self.assertIn("positionAroundControlPointUnsupported", row["diagnostics"])

    def test_speed_endpoints_default_independently_and_explicit_ranges_stay_active(self):
        minimum, maximum = self.result["defaults"]["singleEndpoints"]
        for row in [minimum, maximum]:
            self.assert_birth_match(row)
            self.assertTrue(any(math.dist(velocity, [0, 0, 0]) > 0
                                for velocity in row["velocities"]))
        self.assertEqual(minimum["rawNil"], ["speedmin"])
        self.assertEqual(minimum["speedmin"], [0, 0, 0])
        self.assertEqual(minimum["speedmax"], [0, 4, 0])
        self.assertEqual(maximum["rawNil"], ["speedmax"])
        self.assertEqual(maximum["speedmin"], [0, -4, 0])
        self.assertEqual(maximum["speedmax"], [0, 0, 0])
        half = self.result["defaults"]["explicitHalf"]
        self.assert_birth_match(half)
        self.assertEqual(half["bounds"], [0.25, 0.75])
        for identity, (position, velocity) in enumerate(zip(half["positions"], half["velocities"])):
            phase = 0.25 + 0.5 * identity / 5
            expected = [50 * math.cos(phase * math.tau), 50 * math.sin(phase * math.tau), 0]
            for actual, value in zip(position, expected):
                self.assertAlmostEqual(actual, value, delta=1e-10)
            self.assertAlmostEqual(math.dist(velocity, [0, 0, 0]), 2, places=12)

    def test_invalid_counts_preserve_emitter_and_adjacent_profiles_stay_rejected(self):
        self.assertEqual(len(self.result["invalid"]), 9)
        for row in self.result["invalid"]:
            self.assertFalse(row["admitted"])
            self.assertTrue(row["preserved"])
            self.assertIn("positionAroundControlPointUnsupported", row["diagnostics"])
        self.assertTrue(self.result["adjacentRejected"])


if __name__ == "__main__":
    unittest.main()
