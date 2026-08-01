#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Runtime/SceneMediaThumbnailBindingProgram.swift",
    SCENE / "Runtime/SceneMediaThumbnailTransitionCompiler.swift",
]

HARNESS = r'''
import Foundation

enum SceneJSONValue: Equatable {}

struct SceneEffectTextureInput: Equatable {
    enum Kind { case system, property }
    let kind: Kind
    let value: String
}

struct SceneTimelineTangent { let isEnabled: Bool; let x: Double; let y: Double }
struct SceneTimelineKeyframe {
    let frame: Double; let value: Double
    let back: SceneTimelineTangent?; let front: SceneTimelineTangent?
    let locksAngle: Bool?; let locksLength: Bool?
}
enum SceneTimelineMode { case single, loop, mirror }
struct SceneTimelineGroupReference { let key: String }
struct SceneTimelineOptions {
    let fps: Double; let length: Double; let mode: SceneTimelineMode
    let startsPaused: Bool; let wrapsLoop: Bool
    let smoothing: Double?; let stiffness: Double?
    let parent: SceneTimelineGroupReference?; let children: [SceneTimelineGroupReference]
    var durationSeconds: Double { fps > 0 ? length / fps : 0 }
}
struct SceneTimelineAnimation {
    let lanes: [[SceneTimelineKeyframe]]; let options: SceneTimelineOptions
    let isRelative: Bool; let previewValue: Double?
}

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String; let userBinding: String?; let components: [Double]?
        let timeline: SceneTimelineAnimation?; let timelineDiagnostics: [String]
        let scriptSource: String?; let bindingKeys: [String]
    }
}

struct SceneEffectDefinition {
    struct Binding {}
    struct Pass {
        let passIndex: Int; let materialPath: String?; let target: String?
        let bindings: [Binding]; let compose: SceneJSONValue?; let command: String?
        let source: String?; let conditions: SceneJSONValue?
        let extraFields: [String: SceneJSONValue]
    }
    struct Framebuffer {}
    let relativePath: String; let version: Int?; let replacementKey: String?
    let group: String?; let passes: [Pass]; let framebuffers: [Framebuffer]
    let dependencies: [String]; let extraFields: [String: SceneJSONValue]
    let unknownFieldPaths: [String]; let rawSHA256: String?
}

struct SceneShaderContract {
    enum SourceKind { case authoredSource, hostBuiltin }
    enum StageKind { case vertex, fragment }
    struct Diagnostic {}
    struct Stage { let kind: StageKind; let rawSHA256: String }
    let identity: String; let sourceKind: SourceKind; let stages: [Stage]
    let diagnostics: [Diagnostic]; let canonicalSHA256: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int; let texturePaths: [String]; let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]; let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String; let file: String; let visible: Bool?; let passes: [PassDescriptor]
    }
    struct MaterialPassDescriptor {
        let materialPath: String; let materialRawSHA256: String; let passIndex: Int
        let shaderPath: String?; let texturePaths: [String]; let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]; let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]; let blending: String?
        let depthTest: String?; let depthWrite: String?; let cullMode: String?
    }
    struct Layer {
        let id: Int; let contentKind: String; let effects: [EffectDescriptor]
        var isImageRenderable: Bool { contentKind == "image" || contentKind == "solid" }
    }
    let layers: [Layer]
    let effectDefinitions: [SceneEffectDefinition]
    let materialPasses: [MaterialPassDescriptor]
}

enum SceneScriptBindingValueType { case boolean, number }
struct SceneScriptBindingOwner {
    enum Kind { case effect, object }
    let kind: Kind; let objectID: Int?; let effectIndex: Int?
}
struct SceneScriptBindingIR {
    let source: String; let owner: SceneScriptBindingOwner
    let properties: [String: SceneJSONValue]
    let valueType: SceneScriptBindingValueType; let targetKey: String
}

let prefix = "relocated/shared-profile"
let effectPath = "effects/\(prefix)/blendgradient/effect.json"
let materialPath = "materials/\(prefix)/effects/blendgradient.json"
let shaderIdentity = "\(prefix)/effects/blendgradient"
let tangentBack = SceneTimelineTangent(isEnabled: true, x: -1, y: 0)
let tangentFront = SceneTimelineTangent(isEnabled: true, x: 1, y: 0)

func number(_ value: Double) -> SceneDocument.ShaderValue {
    .init(valueKind: "number", userBinding: nil, components: [value], timeline: nil,
          timelineDiagnostics: [], scriptSource: nil, bindingKeys: [])
}

func multiply(script: String, mode: SceneTimelineMode = .single) -> SceneDocument.ShaderValue {
    let lane = [
        SceneTimelineKeyframe(frame: 0, value: 1, back: tangentBack, front: tangentFront,
                              locksAngle: true, locksLength: true),
        SceneTimelineKeyframe(frame: 15, value: 0, back: tangentBack, front: tangentFront,
                              locksAngle: true, locksLength: true),
    ]
    let options = SceneTimelineOptions(
        fps: 15, length: 15, mode: mode, startsPaused: true, wrapsLoop: false,
        smoothing: nil, stiffness: nil, parent: nil, children: []
    )
    return .init(
        valueKind: "binding", userBinding: nil, components: [0],
        timeline: .init(lanes: [lane], options: options, isRelative: false, previewValue: nil),
        timelineDiagnostics: [], scriptSource: script,
        bindingKeys: ["value", "script", "animation"]
    )
}

let validScript = """
export let metadata = 'fixture';
export function mediaThumbnailChanged(event) {
    if (event.hasThumbnail) {
        var animation = thisObject.getAnimation();
        animation.stop();
        animation.play();
    }
}
"""

func effect(id: String, gradient: String? = "gradient/shared-mask", script: String = validScript,
            mode: SceneTimelineMode = .single) -> SceneRenderDescriptor.EffectDescriptor {
    let slots: [String?] = [nil, "fixture/fallback", gradient]
    let paths = gradient.map { ["fixture/fallback", $0] } ?? ["fixture/fallback"]
    return .init(
        id: id, file: effectPath, visible: false,
        passes: [.init(
            passIndex: 0, texturePaths: paths, textureSlots: slots,
            userTextureInputs: [nil, .init(kind: .system, value: "$mediaPreviousThumbnail")],
            combos: ["edgeglow": 1],
            constantShaderValues: [
                "alpha": number(1), "edgebrightness": number(1),
                "edgecolor": .init(valueKind: "vector", userBinding: nil,
                    components: [0, 0, 0], timeline: nil, timelineDiagnostics: [],
                    scriptSource: nil, bindingKeys: []),
                "gradientscale": number(0.034),
                "multiply": multiply(script: script, mode: mode),
            ]
        )]
    )
}

func descriptor(materialHash: String, fragmentHash: String) -> SceneRenderDescriptor {
    let definition = SceneEffectDefinition(
        relativePath: effectPath, version: 1, replacementKey: "blendgradient",
        group: "colorize", passes: [.init(
            passIndex: 0, materialPath: materialPath, target: nil, bindings: [],
            compose: nil, command: nil, source: nil, conditions: nil, extraFields: [:]
        )], framebuffers: [], dependencies: [
            materialPath, "shaders/\(shaderIdentity).frag", "shaders/\(shaderIdentity).vert",
        ], extraFields: [:], unknownFieldPaths: [],
        rawSHA256: "07c4d0fc7479c7c98a8290fa1c070be37e42b25a402fd0960b0d5dc79fa7ce79"
    )
    let material = SceneRenderDescriptor.MaterialPassDescriptor(
        materialPath: materialPath, materialRawSHA256: materialHash, passIndex: 0,
        shaderPath: shaderIdentity, texturePaths: [], textureSlots: [],
        userTextureInputs: [], combos: [:], constantShaderValues: [:],
        userShaderValues: [:], blending: "normal", depthTest: "disabled",
        depthWrite: "disabled", cullMode: "nocull"
    )
    return .init(layers: [
        .init(id: 1, contentKind: "image", effects: [effect(id: "valid")]),
        .init(id: 2, contentKind: "image", effects: [effect(id: "missing", gradient: nil)]),
        .init(id: 3, contentKind: "image", effects: [effect(
            id: "script", script: "export function mediaThumbnailChanged(e){thisObject.getAnimation().play();}"
        )]),
        .init(id: 4, contentKind: "image", effects: [effect(id: "not-current")]),
        .init(id: 5, contentKind: "image", effects: [
            effect(id: "duplicate-a"), effect(id: "duplicate-b"),
        ]),
        .init(id: 6, contentKind: "image", effects: [effect(id: "loop", mode: .loop)]),
    ], effectDefinitions: [definition], materialPasses: [material])
}

func contracts(fragmentHash: String) -> [SceneShaderContract] {
    [.init(
        identity: shaderIdentity, sourceKind: .authoredSource,
        stages: [
            .init(kind: .vertex, rawSHA256: "9ac7bb9de5e8cc62f506ee0bfa895afc77bbe1c48fdc176c51efc4fe959382a1"),
            .init(kind: .fragment, rawSHA256: fragmentHash),
        ], diagnostics: [],
        canonicalSHA256: "76c476291a68d7caf0f3f38afe83aafa87d56110a5659e738f50dcc6c3aa575a"
    )]
}

let goodMaterial = "33af55c228574c4800b2f8f72327810dfd9779bdb3e77d2c2e7888a199e09ea9"
let goodFragment = "12c73646d1a98dedba873bab5a067fc261256526a1d7a8e867f68f9e10fe572f"
let current = SceneMediaThumbnailBindingProgram(currentLayerIDs: [1, 2, 3, 5, 6])
let accepted = SceneMediaThumbnailTransitionCompiler.compile(
    descriptor: descriptor(materialHash: goodMaterial, fragmentHash: goodFragment),
    shaderContracts: contracts(fragmentHash: goodFragment), currentProgram: current
)
let badMaterial = SceneMediaThumbnailTransitionCompiler.compile(
    descriptor: descriptor(materialHash: String(repeating: "0", count: 64), fragmentHash: goodFragment),
    shaderContracts: contracts(fragmentHash: goodFragment), currentProgram: current
)
let badShader = SceneMediaThumbnailTransitionCompiler.compile(
    descriptor: descriptor(materialHash: goodMaterial, fragmentHash: String(repeating: "0", count: 64)),
    shaderContracts: contracts(fragmentHash: String(repeating: "0", count: 64)), currentProgram: current
)
let plan = accepted.previousTransitionsByLayerID[1]!
let result: [String: Any] = [
    "accepted": accepted.previousTransitionsByLayerID.keys.sorted(),
    "gradient": plan.gradientTexturePath,
    "duration": plan.durationSeconds,
    "scale": plan.gradientScale,
    "badMaterialCount": badMaterial.previousTransitionsByLayerID.count,
    "badShaderCount": badShader.previousTransitionsByLayerID.count,
    "report": accepted.reportLines(),
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneMediaThumbnailTransitionTests(unittest.TestCase):
    def test_content_profile_is_relocatable_and_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-transition-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "transition"
            subprocess.run(
                ["swiftc", *map(str, SOURCES), str(harness), "-o", str(binary)],
                check=True,
                cwd=ROOT,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        self.assertEqual(result["accepted"], [1])
        self.assertEqual(result["gradient"], "gradient/shared-mask")
        self.assertAlmostEqual(result["duration"], 1.0)
        self.assertAlmostEqual(result["scale"], 0.034, places=5)
        self.assertEqual(result["badMaterialCount"], 0)
        self.assertEqual(result["badShaderCount"], 0)
        self.assertIn("mediaThumbnailPreviousTransitionCount: 1", result["report"])


if __name__ == "__main__":
    unittest.main()
