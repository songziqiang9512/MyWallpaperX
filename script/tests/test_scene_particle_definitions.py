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
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
]


HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "synthetic":
            try printJSON(syntheticResult())
        case "integer-safety":
            try printJSON(integerSafetyResult())
        case "census":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingSampleRoot }
            try printJSON(censusResult(rootPath: CommandLine.arguments[2]))
        default:
            throw HarnessError.unknownMode
        }
    }

    private static func syntheticResult() throws -> [String: Any] {
        let source = #"""
        {
          "material":"Materials\\Particle\\Halo.json",
          "maxcount":1200,
          "starttime":12.5,
          "flags":255,
          "animationmode":"Sequence",
          "sequencemultiplier":3,
          "emitter":[
            {"id":1,"name":"sphereRandom","origin":"1 2 3","directions":"1 0 1","sign":"-1 0 1","distancemin":"2 3 4","distancemax":"20 30 40","rate":15,"instantaneous":4,"speedmin":5,"speedmax":9,"duration":2,"controlpoint":3,"audioprocessingmode":1,"audioprocessingexponent":0.5,"audioprocessingfrequencystart":2,"audioprocessingfrequencyend":12,"audioprocessingbounds":"0.1 0.9","flags":2},
            {"id":2,"name":"boxRandom","origin":"4 5 6","distancemax":"100 200 0","rate":30,"flags":4,"delay":0,"minperiodicduration":0.5,"maxperiodicduration":1,"minperiodicdelay":1.5,"maxperiodicdelay":2,"maxtoemitperperiod":32},
            {"id":3,"name":"layerImage"}
          ],
          "initializer":[
            {"id":10,"name":"lifetimeRandom","min":1,"max":2,"exponent":3},
            {"id":11,"name":"sizeRandom","min":4,"max":5},
            {"id":12,"name":"velocityRandom","min":"-1 2 0","max":"3 4 0"},
            {"id":13,"name":"colorRandom","min":"10 20 30","max":"40 50 60"},
            {"id":14,"name":"alphaRandom","min":0.2,"max":0.8},
            {"id":15,"name":"rotationRandom","min":"0 0 0","max":"0 0 6.28"},
            {"id":16,"name":"angularVelocityRandom","min":"0 0 -1","max":"0 0 1"},
            {"id":17,"name":"turbulentVelocityRandom","forward":"0 1 0","right":"1 0 0","up":"0 0 1","offset":0.5,"phasemin":0.25,"phasemax":6.28,"scale":0.2,"speedmin":10,"speedmax":20,"timescale":0.1,"audioprocessingmode":1,"audioprocessingexponent":0.5,"audioprocessingfrequencystart":3,"audioprocessingfrequencyend":13,"audioprocessingbounds":"0.2 0.8"},
            {"id":18,"name":"futureInitializer"}
          ],
          "operator":[
            {"id":20,"name":"movement","flags":1,"gravity":"0 -9.8 0","drag":0.2},
            {"id":21,"name":"alphaFade","fadeintime":0.1,"fadeouttime":0.9},
            {"id":22,"name":"alphaChange","starttime":0.2,"endtime":0.8,"startvalue":1,"endvalue":0},
            {"id":23,"name":"sizeChange","starttime":0,"endtime":1,"startvalue":1,"endvalue":2},
            {"id":24,"name":"colorChange","starttime":0,"endtime":1,"startvalue":"255 0 0","endvalue":"0 0 255"},
            {"id":25,"name":"angularMovement","force":"0 0 1","drag":0.3},
            {"id":26,"name":"oscillatePosition","frequencymin":1,"frequencymax":3,"scalemin":"1 2 0","scalemax":"4 5 0","phasemin":0,"phasemax":6.28,"mask":"1 0 0"},
            {"id":27,"name":"oscillateAlpha","frequencymin":2,"frequencymax":4,"scalemin":0.1,"scalemax":0.9,"blendinstart":0.1,"blendinend":0.2,"blendoutstart":0.8,"blendoutend":0.9},
            {"id":28,"name":"oscillateSize","frequencymin":1,"frequencymax":2,"scalemin":0.5,"scalemax":1.5},
            {"id":29,"name":"controlPointAttract","controlpoint":2,"origin":"4 5 0","scale":512,"threshold":256},
            {"id":30,"name":"turbulence","mask":"1 1 0","phasemin":0.1,"phasemax":0.5,"scale":0.02,"speedmin":50,"speedmax":100,"timescale":0.25},
            {"id":31,"name":"vortex","audioprocessingmode":1,"audioprocessingbounds":"0.3 0.7"},
            {"id":32,"name":"futureOperator"}
          ],
          "renderer":[
            {"id":30,"name":"sprite","orientation":"fixed","axis":"0 0 1","flags":1},
            {"id":31,"name":"spriteTrail","length":0.02,"minlength":1,"maxlength":10},
            {"id":32,"name":"rope","segments":4,"subdivision":3,"fadesize":false,"uvscale":2,"uvsmoothing":false,"uvscrolling":true},
            {"id":33,"name":"ropeTrail","length":3,"segments":6,"fadealpha":true},
            {"id":34,"name":"futureRenderer"}
          ],
          "controlpoint":[{"id":1,"flags":7,"offset":"10 20 0","parentcontrolpoint":2}],
          "children":[{"id":40,"name":"Particles\\Child.json","type":"eventSpawn","maxcount":80,"controlpointstartindex":2,"probability":0.75,"origin":"1 2 3","scale":"2 2 1","angles":"0 0 1","flags":1}],
          "override":{
            "id":99,
            "alpha":{"script":null,"value":0.8},
            "size":{"user":"particle_size","value":2.5},
            "lifetime":{"script":"return 2;","value":2},
            "rate":{"animation":{},"value":4},
            "speed":{"script":{},"value":1.5},
            "count":{"animation":"malformed","value":0.5},
            "brightness":3,
            "color":"255 128 0",
            "colorn":{"user":{"name":"particle_color"},"value":"1 0.5 0"},
            "controlpoint2":"100 200 0",
            "controlpointangle2":"0 0 1"
          }
        }
        """#
        let root = try jsonObject(data: Data(source.utf8))
        let parser = SceneParticleDefinitionParser()
        let definition = parser.parse(root: root)
        guard let override = parser.parseInstanceOverride(root["override"]) else {
            throw HarnessError.invalidJSON
        }
        let encodedOverride = try JSONEncoder().encode(override)
        let decodedOverride = try JSONDecoder().decode(
            SceneParticleInstanceOverride.self,
            from: encodedOverride
        )
        let diagnostics = Dictionary(grouping: definition.diagnostics, by: { $0.kind.rawValue })
            .mapValues(\.count)
        return [
            "material": definition.materialPath ?? "",
            "maxCount": definition.maximumCount ?? -1,
            "startTime": definition.startTime ?? -1,
            "worldSpace": definition.flags.isWorldSpace,
            "noFrameBlend": definition.flags.disablesFrameBlending,
            "perspective": definition.flags.usesPerspective,
            "disablesColorOverrides": definition.flags.disablesColorOverrides,
            "disablesSpeedOverrides": definition.flags.disablesSpeedOverrides,
            "disablesCountOverrides": definition.flags.disablesCountOverrides,
            "disablesLifetimeOverrides": definition.flags.disablesLifetimeOverrides,
            "disablesSizeOverrides": definition.flags.disablesSizeOverrides,
            "animationMode": definition.animationMode ?? "",
            "sequenceMultiplier": definition.sequenceMultiplier ?? -1,
            "emitters": definition.emitters.map { emitterName($0.kind) },
            "sphereDirection": definition.emitters[0].directions?.vectorValue ?? [],
            "sphereControlPoint": definition.emitters[0].controlPoint ?? -1,
            "sphereOnePerFrame": definition.emitters[0].limitsToOnePerFrame,
            "sphereAudioMode": definition.emitters[0].audioResponse.mode ?? -1,
            "sphereAudioExponent": definition.emitters[0].audioResponse.exponent ?? -1,
            "sphereAudioFrequencyStart": definition.emitters[0].audioResponse.frequencyStart ?? -1,
            "sphereAudioFrequencyEnd": definition.emitters[0].audioResponse.frequencyEnd ?? -1,
            "sphereAudioBounds": definition.emitters[0].audioResponse.bounds?.vectorValue ?? [],
            "boxUsesPeriodicEmission": definition.emitters[1].usesRandomPeriodicEmission,
            "boxInitialDelay": definition.emitters[1].periodicEmission.initialDelay ?? -1,
            "boxPeriodicDuration": [
                definition.emitters[1].periodicEmission.minimumDuration ?? -1,
                definition.emitters[1].periodicEmission.maximumDuration ?? -1
            ],
            "boxPeriodicDelay": [
                definition.emitters[1].periodicEmission.minimumDelay ?? -1,
                definition.emitters[1].periodicEmission.maximumDelay ?? -1
            ],
            "boxMaximumEmissionCount":
                definition.emitters[1].periodicEmission.maximumEmissionCount ?? -1,
            "boxPeriodicMalformed": definition.emitters[1].periodicEmission.hasMalformedFields,
            "initializerKinds": definition.initializers.map { initializerName($0.kind) },
            "turbulentPhaseMinimum": definition.initializers[7].turbulentVelocity?.phaseMinimum ?? -1,
            "turbulentTimeScale": definition.initializers[7].turbulentVelocity?.timeScale ?? -1,
            "turbulentAudioMode": definition.initializers[7].turbulentVelocity?.audioResponse.mode ?? -1,
            "turbulentAudioBounds": definition.initializers[7].turbulentVelocity?.audioResponse.bounds?.vectorValue ?? [],
            "operatorKinds": definition.operators.map { operatorName($0.kind) },
            "movementGravity": definition.operators[0].gravity?.vectorValue ?? [],
            "movementDrag": definition.operators[0].drag ?? -1,
            "fadeOut": definition.operators[1].fadeOutTime ?? -1,
            "colorEnd": definition.operators[4].endValue?.vectorValue ?? [],
            "oscillationMask": definition.operators[6].mask?.vectorValue ?? [],
            "attractControlPoint": definition.operators[9].controlPoint ?? -1,
            "attractThreshold": definition.operators[9].threshold ?? -1,
            "turbulenceSpeedMaximum": definition.operators[10].speedMaximum ?? -1,
            "turbulenceTimeScale": definition.operators[10].timeScale ?? -1,
            "vortexAudioBounds": definition.operators[11].audioResponse.bounds?.vectorValue ?? [],
            "rendererKinds": definition.renderers.map { rendererName($0.kind) },
            "spriteWorldSpace": definition.renderers[0].isWorldSpace,
            "ropeSegments": definition.renderers[2].segments ?? -1,
            "ropeSubdivision": definition.renderers[2].subdivision ?? -1,
            "ropeFadesSize": definition.renderers[2].fadesSize ?? true,
            "ropeUVScale": definition.renderers[2].uvScale ?? -1,
            "ropeSmoothsUV": definition.renderers[2].smoothsUV ?? true,
            "ropeScrollsUV": definition.renderers[2].scrollsUV ?? false,
            "ropeTrailLength": definition.renderers[3].length ?? -1,
            "ropeTrailSegments": definition.renderers[3].segments ?? -1,
            "ropeTrailFadesAlpha": definition.renderers[3].fadesAlpha ?? false,
            "controlPointFollowsPointer": definition.controlPoints[0].followsPointer,
            "controlPointWorldSpace": definition.controlPoints[0].isWorldSpace,
            "controlPointCopiesRawParent": definition.controlPoints[0].copiesRawParentValue,
            "controlPointParent": definition.controlPoints[0].parentControlPoint ?? -1,
            "childPath": definition.children[0].path ?? "",
            "childType": definition.children[0].type ?? "",
            "diagnostics": diagnostics,
            "overrideID": override.id ?? -1,
            "overrideAlpha": override.alpha?.value?.scalarValue ?? -1,
            "overrideAlphaScript": override.alpha?.hasScript ?? true,
            "overrideSizeUser": override.size?.userPropertyKey ?? "",
            "overrideLifetimeScript": override.lifetime?.hasScript ?? false,
            "overrideRateAnimation": override.rate?.hasAnimation ?? false,
            "overrideSpeedScript": override.speed?.hasScript ?? false,
            "overrideCountAnimation": override.count?.hasAnimation ?? false,
            "overrideNormalizedColorUser": override.normalizedColor?.userPropertyKey ?? "",
            "overrideControlPoint": override.controlPoints[2]?.value?.vectorValue ?? [],
            "overrideControlPointAngle": override.controlPointAngles[2]?.value?.vectorValue ?? [],
            "overrideRoundTrip": decodedOverride == override
        ]
    }

    private static func integerSafetyResult() -> [String: Any] {
        let values: [String: Any] = [
            "validNumber": 42.0,
            "validString": "42",
            "fraction": 1.5,
            "huge": 1e300,
            "boolean": true,
            "nan": "nan",
            "infinity": "inf",
        ]
        let parser = SceneParticleDefinitionParser()
        return values.mapValues { value in
            let definition = parser.parse(root: [
                "material": "materials/particle/halo.json",
                "maxcount": value,
                "emitter": [["name": "sphereRandom"]],
            ])
            return definition.maximumCount ?? NSNull()
        }
    }

    private static func censusResult(rootPath: String) throws -> [String: Any] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let sampleURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let parser = SceneParticleDefinitionParser()
        var samplesWithParticles = 0
        var layerReferenceCount = 0
        var rootReferencePaths = Set<String>()
        var definitionCount = 0
        var childReferenceCount = 0
        var missingDefinitionCount = 0
        var emitterCounts: [String: Int] = [:]
        var initializerCounts: [String: Int] = [:]
        var operatorCounts: [String: Int] = [:]
        var rendererCounts: [String: Int] = [:]
        var implicitRendererCount = 0
        var diagnosticCounts: [String: Int] = [:]
        var overrideCount = 0
        var overrideFieldCounts: [String: Int] = [:]
        var dynamicOverrideCounts: [String: Int] = [:]
        var sampleSummaries: [[String: Any]] = []

        for sampleURL in sampleURLs {
            let projectRoot = try jsonObject(data: Data(contentsOf: sampleURL.appendingPathComponent("project.json")))
            let entryPath = normalizedPath(projectRoot["file"] as? String ?? "scene.json")
            let packageURL = try scenePackageURL(sampleURL: sampleURL, entryPath: entryPath)
            let index = try ScenePkgReader().readIndex(packageURL: packageURL)
            let entries = Dictionary(uniqueKeysWithValues: index.entries.map { (normalizedPath($0.path), $0) })
            guard let sceneEntry = entries[entryPath] else {
                throw HarnessError.missingEntry(sampleURL.lastPathComponent, entryPath)
            }
            let sceneRoot = try jsonObject(data: try readEntry(sceneEntry, index: index, packageURL: packageURL))
            let objects = sceneRoot["objects"] as? [[String: Any]] ?? []
            let particleObjects = objects.filter { $0["particle"] is String }
            if !particleObjects.isEmpty { samplesWithParticles += 1 }
            layerReferenceCount += particleObjects.count
            var sampleRootPaths = Set<String>()
            var visited = Set<String>()

            var visit: ((String) throws -> Void)!
            visit = { rawPath in
                let path = normalizedPath(rawPath)
                guard visited.insert(path).inserted else { return }
                guard let entry = entries[path] else {
                    missingDefinitionCount += 1
                    return
                }
                let definition = try parser.parse(data: readEntry(entry, index: index, packageURL: packageURL))
                definitionCount += 1
                for emitter in definition.emitters {
                    emitterCounts[emitterName(emitter.kind), default: 0] += 1
                }
                for initializer in definition.initializers {
                    initializerCounts[initializerName(initializer.kind), default: 0] += 1
                }
                for particleOperator in definition.operators {
                    operatorCounts[operatorName(particleOperator.kind), default: 0] += 1
                }
                for renderer in definition.renderers {
                    rendererCounts[rendererName(renderer.kind), default: 0] += 1
                }
                if definition.rendererWasImplicit { implicitRendererCount += 1 }
                for diagnostic in definition.diagnostics {
                    diagnosticCounts[diagnostic.kind.rawValue, default: 0] += 1
                }
                childReferenceCount += definition.children.count
                for child in definition.children {
                    if let path = child.path { try visit(path) }
                }
            }

            for object in particleObjects {
                guard let path = object["particle"] as? String else { continue }
                let normalized = normalizedPath(path)
                sampleRootPaths.insert(normalized)
                rootReferencePaths.insert(normalized)
                try visit(normalized)
                if let override = parser.parseInstanceOverride(object["instanceoverride"]) {
                    overrideCount += 1
                    countOverride(override, fields: &overrideFieldCounts, dynamic: &dynamicOverrideCounts)
                }
            }
            sampleSummaries.append([
                "id": sampleURL.lastPathComponent,
                "layerReferences": particleObjects.count,
                "rootDefinitions": sampleRootPaths.count,
                "reachableDefinitions": visited.count
            ])
        }

        return [
            "sampleCount": sampleURLs.count,
            "samplesWithParticles": samplesWithParticles,
            "particleLayerReferenceCount": layerReferenceCount,
            "uniqueRootReferencePathCount": rootReferencePaths.count,
            "reachableDefinitionCount": definitionCount,
            "childReferenceCount": childReferenceCount,
            "missingDefinitionCount": missingDefinitionCount,
            "emitterCounts": emitterCounts,
            "initializerCounts": initializerCounts,
            "operatorCounts": operatorCounts,
            "rendererCounts": rendererCounts,
            "implicitRendererCount": implicitRendererCount,
            "diagnosticCounts": diagnosticCounts,
            "instanceOverrideCount": overrideCount,
            "instanceOverrideFieldCounts": overrideFieldCounts,
            "dynamicOverrideCounts": dynamicOverrideCounts,
            "samples": sampleSummaries
        ]
    }

    private static func countOverride(
        _ override: SceneParticleInstanceOverride,
        fields: inout [String: Int],
        dynamic: inout [String: Int]
    ) {
        let values: [(String, SceneParticleBoundValue?)] = [
            ("alpha", override.alpha), ("size", override.size), ("lifetime", override.lifetime),
            ("rate", override.rate), ("speed", override.speed), ("count", override.count),
            ("brightness", override.brightness), ("color", override.color),
            ("colorn", override.normalizedColor)
        ]
        for (name, value) in values where value != nil {
            fields[name, default: 0] += 1
            if value?.userPropertyKey != nil { dynamic["user", default: 0] += 1 }
            if value?.hasScript == true { dynamic["script", default: 0] += 1 }
            if value?.hasAnimation == true { dynamic["animation", default: 0] += 1 }
        }
        for value in override.controlPoints.values {
            fields["controlpoint", default: 0] += 1
            if value.userPropertyKey != nil { dynamic["user", default: 0] += 1 }
        }
        for value in override.controlPointAngles.values {
            fields["controlpointangle", default: 0] += 1
            if value.userPropertyKey != nil { dynamic["user", default: 0] += 1 }
        }
    }

    private static func readEntry(
        _ entry: ScenePkgIndex.Entry,
        index: ScenePkgIndex,
        packageURL: URL
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: packageURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(index.dataStartOffset) + UInt64(entry.offset))
        guard let data = try handle.read(upToCount: Int(entry.size)), data.count == Int(entry.size) else {
            throw HarnessError.truncatedEntry(entry.path)
        }
        return data
    }

    private static func scenePackageURL(sampleURL: URL, entryPath: String) throws -> URL {
        let entryName = (entryPath as NSString).lastPathComponent
        let baseName = (entryName as NSString).deletingPathExtension
        let derivedName = baseName.isEmpty ? "scene.pkg" : "\(baseName).pkg"
        for name in derivedName == "scene.pkg" ? [derivedName] : [derivedName, "scene.pkg"] {
            let candidate = sampleURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw HarnessError.missingPackage(sampleURL.lastPathComponent)
    }

    private static func emitterName(_ kind: SceneParticleEmitterKind) -> String {
        switch kind {
        case .sphereRandom: "sphererandom"
        case .boxRandom: "boxrandom"
        case .layerImage: "layerimage"
        case let .unsupported(name): name
        }
    }

    private static func initializerName(_ kind: SceneParticleInitializerKind) -> String {
        switch kind {
        case .lifetime: "lifetimerandom"
        case .size: "sizerandom"
        case .velocity: "velocityrandom"
        case .color: "colorrandom"
        case .alpha: "alpharandom"
        case .rotation: "rotationrandom"
        case .angularVelocity: "angularvelocityrandom"
        case .turbulentVelocity: "turbulentvelocityrandom"
        case let .unsupported(name): name
        }
    }

    private static func operatorName(_ kind: SceneParticleOperatorKind) -> String {
        switch kind {
        case .movement: "movement"
        case .alphaFade: "alphafade"
        case .alphaChange: "alphachange"
        case .sizeChange: "sizechange"
        case .colorChange: "colorchange"
        case .angularMovement: "angularmovement"
        case .oscillatePosition: "oscillateposition"
        case .oscillateAlpha: "oscillatealpha"
        case .oscillateSize: "oscillatesize"
        case .controlPointAttract: "controlpointattract"
        case .turbulence: "turbulence"
        case .boids: "boids"
        case .vortex: "vortex"
        case let .unsupported(name): name
        }
    }

    private static func rendererName(_ kind: SceneParticleRendererKind) -> String {
        switch kind {
        case .sprite: "sprite"
        case .spriteTrail: "spritetrail"
        case .rope: "rope"
        case .ropeTrail: "ropetrail"
        case let .unsupported(name): name
        }
    }

    private static func jsonObject(data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessError.invalidJSON
        }
        return root
    }

    private static func normalizedPath(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case missingMode
        case missingSampleRoot
        case unknownMode
        case invalidJSON
        case missingPackage(String)
        case missingEntry(String, String)
        case truncatedEntry(String)
    }
}
'''


class SceneParticleDefinitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-particles-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-definitions"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [str(self.binary), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def test_synthetic_particle_definition_and_instance_override(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(result["material"], "materials/particle/halo.json")
        self.assertEqual(result["maxCount"], 1200)
        self.assertEqual(result["startTime"], 12.5)
        self.assertTrue(result["worldSpace"])
        self.assertTrue(result["noFrameBlend"])
        self.assertTrue(result["perspective"])
        self.assertTrue(result["disablesColorOverrides"])
        self.assertTrue(result["disablesSpeedOverrides"])
        self.assertTrue(result["disablesCountOverrides"])
        self.assertTrue(result["disablesLifetimeOverrides"])
        self.assertTrue(result["disablesSizeOverrides"])
        self.assertEqual(result["animationMode"], "sequence")
        self.assertEqual(result["sequenceMultiplier"], 3)
        self.assertEqual(result["emitters"], ["sphererandom", "boxrandom", "layerimage"])
        self.assertEqual(result["sphereDirection"], [1, 0, 1])
        self.assertEqual(result["sphereControlPoint"], 3)
        self.assertTrue(result["sphereOnePerFrame"])
        self.assertEqual(result["sphereAudioMode"], 1)
        self.assertEqual(result["sphereAudioExponent"], 0.5)
        # 粒子 schema 用 frequencystart/end 两个标量，没有 effect 侧的 audiofrequency 向量
        self.assertEqual(result["sphereAudioFrequencyStart"], 2)
        self.assertEqual(result["sphereAudioFrequencyEnd"], 12)
        self.assertEqual(result["sphereAudioBounds"], [0.1, 0.9])
        self.assertTrue(result["boxUsesPeriodicEmission"])
        self.assertEqual(result["boxInitialDelay"], 0)
        self.assertEqual(result["boxPeriodicDuration"], [0.5, 1])
        self.assertEqual(result["boxPeriodicDelay"], [1.5, 2])
        self.assertEqual(result["boxMaximumEmissionCount"], 32)
        self.assertFalse(result["boxPeriodicMalformed"])
        self.assertEqual(result["turbulentPhaseMinimum"], 0.25)
        self.assertEqual(len(result["initializerKinds"]), 9)
        self.assertEqual(result["turbulentTimeScale"], 0.1)
        self.assertEqual(result["turbulentAudioMode"], 1)
        self.assertEqual(result["turbulentAudioBounds"], [0.2, 0.8])
        self.assertEqual(len(result["operatorKinds"]), 13)
        self.assertEqual(result["movementGravity"], [0, -9.8, 0])
        self.assertEqual(result["movementDrag"], 0.2)
        self.assertEqual(result["fadeOut"], 0.9)
        self.assertEqual(result["colorEnd"], [0, 0, 255])
        self.assertEqual(result["oscillationMask"], [1, 0, 0])
        self.assertEqual(result["attractControlPoint"], 2)
        self.assertEqual(result["attractThreshold"], 256)
        self.assertEqual(result["turbulenceSpeedMaximum"], 100)
        self.assertEqual(result["turbulenceTimeScale"], 0.25)
        self.assertEqual(result["vortexAudioBounds"], [0.3, 0.7])
        self.assertEqual(
            result["rendererKinds"],
            ["sprite", "spritetrail", "rope", "ropetrail", "futurerenderer"],
        )
        self.assertTrue(result["spriteWorldSpace"])
        self.assertEqual(result["ropeSegments"], 4)
        self.assertEqual(result["ropeSubdivision"], 3)
        self.assertFalse(result["ropeFadesSize"])
        self.assertEqual(result["ropeUVScale"], 2)
        self.assertFalse(result["ropeSmoothsUV"])
        self.assertTrue(result["ropeScrollsUV"])
        self.assertEqual(result["ropeTrailLength"], 3)
        self.assertEqual(result["ropeTrailSegments"], 6)
        self.assertTrue(result["ropeTrailFadesAlpha"])
        self.assertTrue(result["controlPointFollowsPointer"])
        self.assertTrue(result["controlPointWorldSpace"])
        self.assertTrue(result["controlPointCopiesRawParent"])
        self.assertEqual(result["controlPointParent"], 2)
        self.assertEqual(result["childPath"], "particles/child.json")
        self.assertEqual(result["childType"], "eventspawn")
        self.assertEqual(
            result["diagnostics"],
            {
                "unsupportedInitializer": 1,
                "unsupportedOperator": 1,
                "unsupportedRenderer": 1,
            },
        )
        self.assertEqual(result["overrideID"], 99)
        self.assertEqual(result["overrideAlpha"], 0.8)
        self.assertFalse(result["overrideAlphaScript"])
        self.assertEqual(result["overrideSizeUser"], "particle_size")
        self.assertTrue(result["overrideLifetimeScript"])
        self.assertTrue(result["overrideRateAnimation"])
        self.assertTrue(result["overrideSpeedScript"])
        self.assertTrue(result["overrideCountAnimation"])
        self.assertEqual(result["overrideNormalizedColorUser"], "particle_color")
        self.assertEqual(result["overrideControlPoint"], [100, 200, 0])
        self.assertEqual(result["overrideControlPointAngle"], [0, 0, 1])
        self.assertTrue(result["overrideRoundTrip"])

    def test_integer_fields_fail_closed_without_trapping(self) -> None:
        result = self.run_harness("integer-safety")
        self.assertEqual(result["validNumber"], 42)
        self.assertEqual(result["validString"], 42)
        for key in ("fraction", "huge", "boolean", "nan", "infinity"):
            self.assertIsNone(result[key], key)

if __name__ == "__main__":
    unittest.main()
