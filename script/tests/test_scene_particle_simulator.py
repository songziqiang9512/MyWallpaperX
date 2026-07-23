#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
ISOLATED_SAMPLE_ROOT = REPOSITORY_ROOT / ".codex/scene-user-samples-20260722/Scene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
]


HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "census" {
            try printJSON(census(rootPath: CommandLine.arguments[2]))
        } else {
            try printJSON(syntheticResults())
        }
    }

    private static func syntheticResults() throws -> [String: Any] {
        var first = simulator(deterministicJSON, seed: 41, step: 0.1)
        var partitioned = simulator(deterministicJSON, seed: 41, step: 0.1)
        var different = simulator(deterministicJSON, seed: 42, step: 0.1)
        first.advance(by: 0.5)
        partitioned.advance(by: 0.2)
        partitioned.advance(by: 0.3)
        different.advance(by: 0.5)

        var capped = simulator(maximumCountJSON, seed: 1, step: 0.1)
        capped.advance(by: 0.1)
        let prewarmed = simulator(prewarmJSON, seed: 1, step: 0.1)

        var burst = simulator(durationJSON, seed: 1, step: 0.1)
        burst.advance(by: 0.5)

        var bounds = simulator(boundsJSON, seed: 7, step: 0.1)
        bounds.advance(by: 0.1)
        let sphere = bounds.particles.prefix(50)
        let box = bounds.particles.dropFirst(50)
        let sphereRadii = sphere.map { length($0.position - SIMD3(10, 20, 30)) }
        let boxOffsets = box.map { $0.position - SIMD3(-10, -20, -30) }

        var movement = simulator(movementJSON, seed: 1, step: 0.25)
        movement.advance(by: 0.5)
        let movementPosition = movement.particles[0].position
        movement.advance(by: 1.25)

        let overrideRoot = try object(overrideJSON)
        let parsedOverride = SceneParticleDefinitionParser().parseInstanceOverride(overrideRoot)
        var overridden = simulator(overrideDefinitionJSON, override: parsedOverride, seed: 1, step: 0.25)
        overridden.advance(by: 0.25)
        let overriddenParticle = overridden.particles[0]
        overridden.advance(by: 1.0)

        var operators = simulator(operatorJSON, seed: 1, step: 0.25)
        operators.advance(by: 0.25)
        let operatorParticle = operators.particles[0]

        let diagnosticOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"size":{"script":"return 2","value":2}}"#)
        )
        let diagnosticSimulator = simulator(
            diagnosticJSON, override: diagnosticOverride, seed: 1, step: 0.1
        )
        var colors = simulator(colorJSON, seed: 1, step: 0.1)
        colors.advance(by: 0.1)
        let randomColor = colors.particles[0].color

        return [
            "deterministic": first.particles == partitioned.particles,
            "differentSeed": first.particles != different.particles,
            "maxCount": capped.particles.count,
            "prewarmCount": prewarmed.particles.count,
            "prewarmTime": prewarmed.simulationTime,
            "durationCount": burst.particles.count,
            "sphereMinimumRadius": sphereRadii.min() ?? -1,
            "sphereMaximumRadius": sphereRadii.max() ?? -1,
            "boxInBounds": boxOffsets.allSatisfy {
                (-1...1).contains($0.x) && (-2...2).contains($0.y) && (-3...3).contains($0.z)
            },
            "movementPosition": vector(movementPosition),
            "fadeAlpha": movement.particles[0].alpha,
            "overrideLifetime": overriddenParticle.lifetime,
            "overrideSize": overriddenParticle.size,
            "overrideVelocity": vector(overriddenParticle.velocity),
            "overrideAlpha": overriddenParticle.alpha,
            "overrideColor": vector(overriddenParticle.color),
            "overrideEmissionCount": overridden.particles.count,
            "overrideDiagnostics": overridden.diagnostics.map(\.kind.rawValue),
            "operatorAlpha": operatorParticle.alpha,
            "operatorSize": operatorParticle.size,
            "operatorColor": vector(operatorParticle.color),
            "operatorRotation": vector(operatorParticle.rotation),
            "operatorPosition": vector(operatorParticle.position),
            "independentColorChannels": randomColor.x != randomColor.y && randomColor.y != randomColor.z,
            "diagnostics": diagnosticSimulator.diagnostics.map(\.kind.rawValue).sorted()
        ]
    }

    private static func simulator(
        _ source: String,
        override: SceneParticleInstanceOverride? = nil,
        seed: UInt64,
        step: Double
    ) -> SceneParticleSimulator {
        let definition = SceneParticleDefinitionParser().parse(root: try! object(source))
        return SceneParticleSimulator(
            definition: definition, instanceOverride: override, seed: seed, fixedTimeStep: step
        )
    }

    private static let deterministicJSON = #"""
    {"material":"p.json","maxcount":64,
     "emitter":[{"name":"sphererandom","instantaneous":2,"rate":8,"distancemin":1,"distancemax":2,"speedmin":1,"speedmax":3}],
     "initializer":[{"name":"lifetimerandom","min":5,"max":5},{"name":"sizerandom","min":1,"max":2},{"name":"velocityrandom","min":"-1 -1 0","max":"1 1 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let maximumCountJSON = #"""
    {"material":"p.json","maxcount":3,
     "emitter":[{"name":"boxrandom","instantaneous":100,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let prewarmJSON = #"""
    {"material":"p.json","maxcount":64,"starttime":1,
     "emitter":[{"name":"boxrandom","rate":10,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let durationJSON = #"""
    {"material":"p.json","maxcount":64,
     "emitter":[{"name":"boxrandom","instantaneous":3,"rate":100,"duration":0.25,"flags":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let boundsJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[
       {"name":"sphererandom","instantaneous":50,"origin":"10 20 30","directions":"1 1 1","distancemin":2,"distancemax":4},
       {"name":"boxrandom","instantaneous":50,"origin":"-10 -20 -30","directions":"1 1 1","distancemin":"-1 -2 -3","distancemax":"1 2 3"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let movementJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"velocityrandom","min":"2 0 0","max":"2 0 0"},{"name":"alpharandom","min":1,"max":1}],
     "operator":[{"name":"movement","gravity":"0 -2 0","drag":1},{"name":"alphafade","fadeintime":0.25,"fadeouttime":0.75}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let overrideDefinitionJSON = #"""
    {"material":"p.json","maxcount":32,
     "emitter":[{"name":"boxrandom","instantaneous":1,"rate":4,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"sizerandom","min":2,"max":2},{"name":"velocityrandom","min":"1 0 0","max":"1 0 0"},{"name":"colorrandom","min":"255 255 255","max":"255 255 255"},{"name":"alpharandom","min":0.5,"max":0.5}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let overrideJSON = #"""
    {"alpha":0.5,"size":{"user":"size_prop","value":3},"lifetime":2,"rate":2,"speed":4,"count":0.5,"brightness":2,"colorn":"0.5 0.25 1"}
    """#

    private static let operatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":2,"max":2},{"name":"colorrandom","min":"255 255 255","max":"255 255 255"},{"name":"angularvelocityrandom","min":"0 0 1","max":"0 0 1"}],
     "operator":[
       {"name":"alphachange","starttime":0,"endtime":1,"startvalue":1,"endvalue":0.5},
       {"name":"sizechange","starttime":0,"endtime":1,"startvalue":1,"endvalue":2},
       {"name":"colorchange","starttime":0,"endtime":1,"startvalue":"1 1 1","endvalue":"0 0.5 1"},
       {"name":"angularmovement","force":"0 0 0","drag":0},
       {"name":"oscillatealpha","frequencymin":0,"frequencymax":0,"scalemin":0.5,"scalemax":0.5,"phasemin":0,"phasemax":0},
       {"name":"oscillatesize","frequencymin":0,"frequencymax":0,"scalemin":2,"scalemax":2,"phasemin":0,"phasemax":0},
       {"name":"oscillateposition","frequencymin":1,"frequencymax":1,"scalemin":"1 0 0","scalemax":"1 0 0","phasemin":1.5707963267948966,"phasemax":1.5707963267948966,"mask":"1 0 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let diagnosticJSON = #"""
    {"material":"p.json","maxcount":4,
     "emitter":[{"name":"boxrandom","rate":1,"audioprocessingmode":1}],
     "initializer":[{"name":"turbulentvelocityrandom"}],
     "operator":[{"name":"controlpointattract"},{"name":"turbulence"},{"name":"vortex"}],
     "renderer":[{"name":"spritetrail"}],"controlpoint":[{"id":0,"flags":1}],
     "children":[{"name":"child.json","type":"static"}]}
    """#

    private static let colorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"colorrandom","min":"0 0 0","max":"255 255 255"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static func census(rootPath: String) throws -> [String: Any] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let samples = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let parser = SceneParticleDefinitionParser()
        var definitionSimulators = 0
        var rootSimulators = 0

        for sample in samples {
            let project = try object(data: Data(contentsOf: sample.appendingPathComponent("project.json")))
            let scenePath = normalized(project["file"] as? String ?? "scene.json")
            let packageURL = try packageURL(sample: sample, scenePath: scenePath)
            let index = try ScenePkgReader().readIndex(packageURL: packageURL)
            let entries = Dictionary(uniqueKeysWithValues: index.entries.map { (normalized($0.path), $0) })
            guard let sceneEntry = entries[scenePath] else { throw HarnessError.missingEntry(scenePath) }
            let scene = try object(data: try read(sceneEntry, index: index, packageURL: packageURL))
            let objects = scene["objects"] as? [[String: Any]] ?? []

            for object in objects {
                guard let path = object["particle"] as? String,
                      let entry = entries[normalized(path)] else { continue }
                let definition = try parser.parse(data: read(entry, index: index, packageURL: packageURL))
                var runtime = SceneParticleSimulator(
                    definition: definition,
                    instanceOverride: parser.parseInstanceOverride(object["instanceoverride"]),
                    seed: UInt64(rootSimulators), fixedTimeStep: 1.0 / 60.0
                )
                runtime.advance(by: 1.0 / 60.0)
                rootSimulators += 1
            }

            var visited = Set<String>()
            func visit(_ rawPath: String) throws {
                let path = normalized(rawPath)
                guard visited.insert(path).inserted, let entry = entries[path] else { return }
                let definition = try parser.parse(data: read(entry, index: index, packageURL: packageURL))
                var runtime = SceneParticleSimulator(
                    definition: definition, seed: UInt64(definitionSimulators), fixedTimeStep: 1.0 / 60.0
                )
                runtime.advance(by: 1.0 / 60.0)
                definitionSimulators += 1
                for child in definition.children { if let path = child.path { try visit(path) } }
            }
            for object in objects { if let path = object["particle"] as? String { try visit(path) } }
        }
        return ["sampleCount": samples.count, "definitionSimulators": definitionSimulators,
                "rootSimulators": rootSimulators]
    }

    private static func read(
        _ entry: ScenePkgIndex.Entry, index: ScenePkgIndex, packageURL: URL
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: packageURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(index.dataStartOffset) + UInt64(entry.offset))
        guard let data = try handle.read(upToCount: Int(entry.size)), data.count == Int(entry.size) else {
            throw HarnessError.truncatedEntry(entry.path)
        }
        return data
    }

    private static func packageURL(sample: URL, scenePath: String) throws -> URL {
        let name = ((scenePath as NSString).lastPathComponent as NSString).deletingPathExtension
        for file in name == "scene" ? ["scene.pkg"] : ["\(name).pkg", "scene.pkg"] {
            let candidate = sample.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw HarnessError.missingPackage(sample.lastPathComponent)
    }

    private static func normalized(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }

    private static func object(_ source: String) throws -> [String: Any] {
        try object(data: Data(source.utf8))
    }

    private static func object(data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessError.invalidJSON
        }
        return value
    }

    private static func vector(_ value: SIMD3<Double>) -> [Double] {
        [value.x, value.y, value.z]
    }

    private static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case invalidJSON
        case missingPackage(String)
        case missingEntry(String)
        case truncatedEntry(String)
    }
}
'''


class SceneParticleSimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-particle-runtime-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-runtime"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.results = cls.run_harness()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def run_harness(cls, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [str(cls.binary), *arguments], check=True, capture_output=True, text=True
        )
        return json.loads(result.stdout)

    def test_fixed_step_and_seed_are_deterministic(self) -> None:
        self.assertTrue(self.results["deterministic"])
        self.assertTrue(self.results["differentSeed"])

    def test_maximum_count_and_start_time_prewarm(self) -> None:
        self.assertEqual(self.results["maxCount"], 3)
        self.assertEqual(self.results["prewarmCount"], 10)
        self.assertAlmostEqual(self.results["prewarmTime"], 1.0)

    def test_rate_instantaneous_duration_and_one_per_frame(self) -> None:
        self.assertEqual(self.results["durationCount"], 4)

    def test_sphere_and_box_emitters_stay_in_authored_bounds(self) -> None:
        self.assertGreaterEqual(self.results["sphereMinimumRadius"], 2.0)
        self.assertLessEqual(self.results["sphereMaximumRadius"], 4.0)
        self.assertTrue(self.results["boxInBounds"])

    def test_movement_gravity_drag_and_alpha_fade(self) -> None:
        self.assertEqual(self.results["movementPosition"], [0.65625, -0.34375, 0])
        self.assertAlmostEqual(self.results["fadeAlpha"], 0.5)

    def test_static_instance_overrides_apply_and_dynamic_binding_is_diagnosed(self) -> None:
        self.assertEqual(self.results["overrideLifetime"], 4)
        self.assertEqual(self.results["overrideSize"], 6)
        self.assertEqual(self.results["overrideVelocity"], [4, 0, 0])
        self.assertEqual(self.results["overrideAlpha"], 0.25)
        self.assertEqual(self.results["overrideColor"], [0.5, 0.125, 2])
        self.assertEqual(self.results["overrideEmissionCount"], 5)
        self.assertIn("dynamicOverrideIgnored", self.results["overrideDiagnostics"])

    def test_change_angular_and_oscillation_operators_execute(self) -> None:
        self.assertAlmostEqual(self.results["operatorAlpha"], 0.49375)
        self.assertAlmostEqual(self.results["operatorSize"], 4.1)
        self.assertEqual(self.results["operatorColor"], [0.975, 0.9875, 1])
        self.assertEqual(self.results["operatorRotation"], [0, 0, 0.25])
        self.assertLess(self.results["operatorPosition"][0], 0)

    def test_color_initializer_samples_channels_independently(self) -> None:
        self.assertTrue(self.results["independentColorChannels"])

    def test_unsupported_capabilities_are_reported(self) -> None:
        self.assertEqual(
            self.results["diagnostics"],
            [
                "audioResponseIgnored",
                "childSystemsIgnored",
                "controlPointForceIgnored",
                "dynamicOverrideIgnored",
                "pointerControlPointIgnored",
                "unsupportedInitializer",
                "unsupportedOperator",
                "unsupportedOperator",
            ],
        )

    def test_isolated_21_sample_definitions_can_initialize_and_advance(self) -> None:
        if not ISOLATED_SAMPLE_ROOT.is_dir():
            self.skipTest("isolated 21-sample Scene corpus is unavailable")
        result = self.run_harness("census", str(ISOLATED_SAMPLE_ROOT))
        self.assertEqual(result["sampleCount"], 21)
        self.assertEqual(result["definitionSimulators"], 55)
        self.assertEqual(result["rootSimulators"], 60)


if __name__ == "__main__":
    unittest.main()
