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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyDefinitionParser.swift",
    SOURCE_ROOT / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyResolver.swift",
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
        case "census":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingSampleRoot }
            try printJSON(censusResult(rootPath: CommandLine.arguments[2]))
        default:
            throw HarnessError.unknownMode
        }
    }

    private static func syntheticResult() throws -> [String: Any] {
        let projectJSON = #"""
        {"general":{"properties":{
          "heading":{"type":"group","text":"Controls","order":1},
          "enabled":{"type":"bool","text":"Enabled","order":2,"value":true},
          "size":{"type":"slider","text":"Size","order":3,"value":1,"min":0,"max":100,"step":1,"fraction":false},
          "tint":{"type":"color","text":"Tint","order":4,"value":"1 1 1"},
          "mode":{"type":"combo","text":"Mode","order":5,"value":"1","options":[{"label":"One","value":"1"},{"label":"Two","value":"2"}]},
          "caption":{"type":"textinput","text":"Caption","order":6,"value":"Default"},
          "particleAmount":{"type":"slider","text":"Particle Amount","order":7,"value":1},
          "particleTint":{"type":"color","text":"Particle Tint","order":8,"value":"1 1 1"},
          "note":{"type":"text","text":"Read only","order":9,"value":"Note"},
          "officialTexture":{"type":"texture","text":"Official Texture","order":10,"value":""},
          "sceneTexture":{"type":"scenetexture","text":"Scene Texture","order":11,"value":"default.tex"},
          "future":{"type":"futuretype","text":"Future","order":12,"value":"x"}
        }}}
        """#
        let sceneJSON = #"""
        {
          "general":{
            "cameraparallax":{"user":"enabled","value":false},
            "camerashake":{"user":"enabled","value":false}
          },
          "objects":[{
            "id":10,
            "visible":{"user":"enabled","value":false},
            "animationlayers":[{
              "id":77,
              "visible":{"user":"enabled","value":false}
            }],
            "text":{"user":"caption","value":"fallback"},
            "pointsize":{"user":"size","value":12},
            "color":{"user":"tint","value":"0 0 0"},
            "effects":[{
              "file":"effects/tint/effect.json",
              "visible":{"user":{"name":"mode","condition":"2"},"value":false},
              "passes":[{"constantshadervalues":{"strength":{"user":"size","value":1}}}]
            },{
              "file":"effects/blend/effect.json",
              "visible":{"user":"enabled","value":false},
              "passes":[]
            },{
              "file":"effects/transform/effect.json",
              "visible":{"user":{"name":"mode","condition":"2"},"value":false},
              "passes":[]
            }],
            "alpha":{"user":"size","value":0.5},
            "instanceoverride":{
              "count":{"user":"particleAmount","value":0.5},
              "colorn":{"user":"particleTint","value":"0 0 0"}
            },
            "scriptproperties":{"label":{"user":"caption","value":"fallback"}},
            "opacity":{"user":"missing","value":0.25},
            "brightness":{"user":{"name":"mode","condition":"2"},"value":0.2},
            "malformed":{"user":{"condition":"2"},"value":7},
            "ignored":{"user":null,"value":9}
          }]
        }
        """#
        let projectRoot = try jsonObject(projectJSON)
        let sceneRoot = try jsonObject(sceneJSON)
        let catalog = SceneUserPropertyDefinitionParser().parse(projectRoot: projectRoot)
        let resolution = SceneUserPropertyDocumentResolver().resolve(
            root: sceneRoot,
            catalog: catalog,
            overrides: [
                "mode": .string("2"),
                "caption": .string("Hello"),
                "size": .number(42),
                "tint": .string("0.2 0.4 0.6"),
                "particleAmount": .number(2.5),
                "particleTint": .string("0.3 0.5 0.7"),
                "unknown": .string("ignored")
            ]
        )
        let object = ((resolution.root["objects"] as? [[String: Any]]) ?? [])[0]
        let effects = (object["effects"] as? [[String: Any]]) ?? []
        let effect = effects[0]
        let pass = ((effect["passes"] as? [[String: Any]]) ?? [])[0]
        let shaderValues = pass["constantshadervalues"] as? [String: Any] ?? [:]
        let diagnostics = Dictionary(grouping: resolution.diagnostics, by: \.kind.rawValue)
            .mapValues(\.count)
        let kinds = Dictionary(grouping: catalog.definitions, by: \.kind.rawValue)
            .mapValues(\.count)
        let definitionsByKey = Dictionary(uniqueKeysWithValues: catalog.definitions.map { ($0.key, $0) })
        let particleOverride = object["instanceoverride"] as? [String: Any] ?? [:]
        let animationLayer = ((object["animationlayers"] as? [[String: Any]]) ?? [])[0]
        let effectVisibilityOwners: [[String: Any]] = resolution.bindingReport.bindings
            .compactMap { binding in
                guard case let .effectVisibility(layerID, effectIndex, effectPath) =
                        binding.target else { return nil }
                return [
                    "layerID": layerID,
                    "effectIndex": effectIndex,
                    "effectPath": effectPath.map { $0 as Any } ?? NSNull(),
                ]
            }
        return [
            "definitionCount": catalog.definitions.count,
            "definitionKinds": kinds,
            "firstDefinition": catalog.definitions.first?.key ?? "",
            "unsupportedDefinitionCount": catalog.unsupportedDefinitions.count,
            "sliderDefaultIsNumber": catalog.defaultValues["size"] == .number(1),
            "boolDefaultIsBool": catalog.defaultValues["enabled"] == .bool(true),
            "officialTextureRuntimeType": definitionsByKey["officialTexture"]?.runtimeType ?? "",
            "sceneTextureRuntimeType": definitionsByKey["sceneTexture"]?.runtimeType ?? "",
            "unknownOverrideIgnored": catalog.effectiveValues(overrides: ["unknown": .string("x")])["unknown"] == nil,
            "bindingCount": resolution.bindingReport.bindings.count,
            "conditionalBindingCount": resolution.bindingReport.conditionalBindingCount,
            "unsupportedBindingCount": resolution.bindingReport.unsupportedBindings.count,
            "particleBindingCount": resolution.bindingReport.bindings.filter {
                if case .particle = $0.target { return true }
                return false
            }.count,
            "puppetAnimationBindingCount": resolution.bindingReport.bindings.filter {
                if case .puppetAnimationVisibility = $0.target { return true }
                return false
            }.count,
            "resolvedBindingCount": resolution.resolvedBindingCount,
            "diagnostics": diagnostics,
            "cameraParallax": wrapperValue(resolution.root["general"], key: "cameraparallax"),
            "cameraShake": wrapperValue(resolution.root["general"], key: "camerashake"),
            "layerVisible": wrapperValue(object, key: "visible"),
            "puppetAnimationVisible": wrapperValue(animationLayer, key: "visible"),
            "text": wrapperValue(object, key: "text"),
            "pointSize": wrapperValue(object, key: "pointsize"),
            "color": wrapperValue(object, key: "color"),
            "effectVisible": wrapperValue(effect, key: "visible"),
            "effectVisibilityValues": effects.map {
                wrapperValue($0, key: "visible")
            },
            "effectVisibilityOwners": effectVisibilityOwners,
            "shaderStrength": wrapperValue(shaderValues, key: "strength"),
            "layerAlpha": wrapperValue(object, key: "alpha"),
            "particleCount": wrapperValue(particleOverride, key: "count"),
            "particleColor": wrapperValue(particleOverride, key: "colorn"),
            "unsupportedNestedDirect": wrapperValue(object["scriptproperties"], key: "label"),
            "missingFallback": wrapperValue(object, key: "opacity"),
            "unsupportedConditionalFallback": wrapperValue(object, key: "brightness")
        ]
    }

    private static func censusResult(rootPath: String) throws -> [String: Any] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let sampleURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var definitionCount = 0
        var bindingCount = 0
        var conditionalBindingCount = 0
        var unsupportedDefinitionCount = 0
        var kindCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]
        var conditionalTargetCounts: [String: Int] = [:]
        var diagnosticCounts: [String: Int] = [:]
        var sampleSummaries: [[String: Any]] = []

        for sampleURL in sampleURLs {
            let projectRoot = try jsonObject(data: Data(contentsOf: sampleURL.appendingPathComponent("project.json")))
            let entryPath = normalizedPath(projectRoot["file"] as? String ?? "scene.json")
            let packageURL = try scenePackageURL(sampleURL: sampleURL, entryPath: entryPath)
            let index = try ScenePkgReader().readIndex(packageURL: packageURL)
            guard let entry = index.entries.first(where: { normalizedPath($0.path) == entryPath }) else {
                throw HarnessError.missingEntry(sampleURL.lastPathComponent, entryPath)
            }
            let sceneData = try ScenePkgReader().readEntryData(entry, in: packageURL)
            let sceneRoot = try jsonObject(data: sceneData)
            let catalog = SceneUserPropertyDefinitionParser().parse(projectRoot: projectRoot)
            let report = SceneUserPropertyBindingParser().parse(root: sceneRoot)
            definitionCount += catalog.definitions.count
            unsupportedDefinitionCount += catalog.unsupportedDefinitions.count
            bindingCount += report.bindings.count
            conditionalBindingCount += report.conditionalBindingCount
            for definition in catalog.definitions {
                kindCounts[definition.kind.rawValue, default: 0] += 1
            }
            for binding in report.bindings {
                let name = targetName(binding.target)
                targetCounts[name, default: 0] += 1
                if binding.reference.isConditional {
                    conditionalTargetCounts[name, default: 0] += 1
                }
            }
            for diagnostic in report.diagnostics {
                diagnosticCounts[diagnostic.kind.rawValue, default: 0] += 1
            }
            sampleSummaries.append([
                "id": sampleURL.lastPathComponent,
                "definitions": catalog.definitions.count,
                "bindings": report.bindings.count,
                "conditional": report.conditionalBindingCount
            ])
        }
        return [
            "sampleCount": sampleURLs.count,
            "definitionCount": definitionCount,
            "unsupportedDefinitionCount": unsupportedDefinitionCount,
            "definitionKinds": kindCounts,
            "bindingCount": bindingCount,
            "directBindingCount": bindingCount - conditionalBindingCount,
            "conditionalBindingCount": conditionalBindingCount,
            "targetCounts": targetCounts,
            "conditionalTargetCounts": conditionalTargetCounts,
            "diagnosticCounts": diagnosticCounts,
            "samples": sampleSummaries
        ]
    }

    private static func targetName(_ target: SceneUserPropertyBindingTarget) -> String {
        switch target {
        case .layerVisibility: "layerVisibility"
        case .puppetAnimationVisibility: "puppetAnimationVisibility"
        case .layerAlpha: "layerAlpha"
        case .layerColor: "layerColor"
        case .effectVisibility: "effectVisibility"
        case .camera: "camera"
        case .text: "text"
        case .particle: "particle"
        case .soundVolume: "soundVolume"
        case .shaderValue: "shaderValue"
        case .scriptProperty: "scriptProperty"
        case .unsupported: "unsupported"
        }
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

    private static func wrapperValue(_ rawContainer: Any?, key: String) -> Any {
        let container = rawContainer as? [String: Any] ?? [:]
        let wrapper = container[key] as? [String: Any] ?? [:]
        return wrapper["value"] ?? NSNull()
    }

    private static func jsonObject(_ source: String) throws -> [String: Any] {
        try jsonObject(data: Data(source.utf8))
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
    }
}
'''


class SceneUserPropertyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-user-properties-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-user-properties"
        compilation = subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

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

    def test_definition_and_recursive_binding_resolution(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(result["definitionCount"], 12)
        self.assertEqual(result["unsupportedDefinitionCount"], 1)
        self.assertEqual(result["firstDefinition"], "heading")
        self.assertEqual(
            result["definitionKinds"],
            {
                "bool": 1,
                "color": 2,
                "combo": 1,
                "group": 1,
                "scenetexture": 2,
                "slider": 2,
                "text": 1,
                "textinput": 1,
                "unsupported": 1,
            },
        )
        self.assertTrue(result["sliderDefaultIsNumber"])
        self.assertTrue(result["boolDefaultIsBool"])
        self.assertEqual(result["officialTextureRuntimeType"], "texture")
        self.assertEqual(result["sceneTextureRuntimeType"], "scenetexture")
        self.assertTrue(result["unknownOverrideIgnored"])
        self.assertEqual(result["bindingCount"], 17)
        self.assertEqual(result["conditionalBindingCount"], 3)
        self.assertEqual(result["unsupportedBindingCount"], 3)
        self.assertEqual(result["resolvedBindingCount"], 15)
        self.assertEqual(result["particleBindingCount"], 2)
        self.assertEqual(result["puppetAnimationBindingCount"], 1)
        self.assertEqual(result["cameraParallax"], True)
        self.assertEqual(result["cameraShake"], True)
        self.assertEqual(result["layerVisible"], True)
        self.assertEqual(result["puppetAnimationVisible"], True)
        self.assertEqual(result["text"], "Hello")
        self.assertEqual(result["pointSize"], 42)
        self.assertEqual(result["color"], "0.2 0.4 0.6")
        self.assertEqual(result["effectVisible"], True)
        self.assertEqual(result["effectVisibilityValues"], [True, True, True])
        self.assertEqual(
            result["effectVisibilityOwners"],
            [
                {
                    "layerID": 10,
                    "effectIndex": 0,
                    "effectPath": "effects/tint/effect.json",
                },
                {
                    "layerID": 10,
                    "effectIndex": 1,
                    "effectPath": "effects/blend/effect.json",
                },
                {
                    "layerID": 10,
                    "effectIndex": 2,
                    "effectPath": "effects/transform/effect.json",
                },
            ],
        )
        self.assertEqual(result["shaderStrength"], 42)
        self.assertEqual(result["layerAlpha"], 42)
        self.assertEqual(result["particleCount"], 2.5)
        self.assertEqual(result["particleColor"], "0.3 0.5 0.7")
        self.assertEqual(result["unsupportedNestedDirect"], "Hello")
        self.assertEqual(result["missingFallback"], 0.25)
        self.assertEqual(result["unsupportedConditionalFallback"], 0.2)
        self.assertEqual(
            result["diagnostics"],
            {
                "malformedUserReference": 1,
                "missingEffectiveValue": 1,
                "unsupportedConditionalTarget": 1,
                "unsupportedTarget": 3,
            },
        )

if __name__ == "__main__":
    unittest.main()
