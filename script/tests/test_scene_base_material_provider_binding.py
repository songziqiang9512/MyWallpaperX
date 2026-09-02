#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCE = SCENE_ROOT / "Runtime/SceneBaseMaterialProviderBindingProgram.swift"
COMPILER_SOURCE = (
    SCENE_ROOT / "Runtime/SceneBaseMaterialProviderBindingCompiler.swift"
)
VISIBILITY_SOURCE = (
    SCENE_ROOT / "Runtime/SceneInitialMediaEffectVisibilityProjection.swift"
)
LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"

HARNESS = r'''
import Foundation

struct SceneEffectTextureInput: Equatable {
    enum Kind { case path, system, property, unknown }
    let kind: Kind
    let value: String
}

enum SceneTextureLoadPurpose: Hashable { case premultipliedColor }
enum SceneTextureProviderIdentity: Hashable {
    case mediaThumbnailCurrent
    case mediaThumbnailPrevious
}
enum SceneTextureResourceIdentity: Hashable {
    case file
    case provider(SceneTextureProviderIdentity)
}
struct SceneTextureCandidate {
    let identity: SceneTextureResourceIdentity
    let purpose: SceneTextureLoadPurpose
}
struct SceneSystemProviderTextureIdentity: Hashable {
    let name: String
    let purpose: SceneTextureLoadPurpose
}
struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose
    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey
        self.purpose = purpose
    }
    var reportToken: String { propertyKey }
}
enum SceneFrameTextureIdentity: Hashable {
    case system(SceneSystemProviderTextureIdentity)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
}
struct SceneVFSAssetPath {
    let value: String
    init?(_ rawValue: String) {
        let normalized = rawValue.replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        value = normalized
    }
}
enum SceneStockTextureSemanticRegistry {
    static func isNeutralColorCarrier(_ path: SceneVFSAssetPath) -> Bool {
        path.value == "util/white"
    }
}

struct SceneDocument {
    struct ShaderValue {
        let userBinding: String?
        let components: [Double]?
    }
    struct SceneLayerMaterialInstance {
        let id: Int?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let hasUserTextureOverride: Bool
        let combos: [String: Int]
        let unknownKeys: [String]
        let isMalformed: Bool
    }
}

struct SceneRenderDescriptor {
    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }
    struct MaterialPassDescriptor {
        let materialPath: String
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
    }
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let file: String
        var visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let imagePath: String?
        var effects: [EffectDescriptor]
        var isImageRenderable: Bool { contentKind == "image" || contentKind == "solid" }
    }
    var layers: [Layer]
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
    let texturePropertyKeys: [String]
}

enum SceneJSONValue: Equatable { case bool(Bool) }
enum SceneScriptBindingValueType { case boolean, number }
struct SceneScriptBindingOwner {
    enum Kind { case effect, object }
    let kind: Kind
    let objectID: Int?
    let effectIndex: Int?
}
struct SceneScriptBindingIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let properties: [String: SceneJSONValue]
    let valueType: SceneScriptBindingValueType
    let targetKey: String
}
struct SceneScriptSourceEvidenceIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetKey: String
    let wrapperKeys: [String]
}

func effect(
    path: String = "effects/blend/effect.json",
    visible: Bool? = true,
    identity: String = "$mediaThumbnail",
    multiply: Double = 1,
    alpha: Double = 1
) -> SceneRenderDescriptor.EffectDescriptor {
    .init(
        file: path,
        visible: visible,
        passes: [.init(
            textureSlots: [nil, "authored/fallback"],
            userTextureInputs: [nil, .init(kind: .system, value: identity)],
            combos: ["BLENDMODE": 0, "TRANSFORMREPEAT": 2],
            constantShaderValues: [
                "multiply": .init(userBinding: nil, components: [multiply]),
                "alpha": .init(userBinding: nil, components: [alpha]),
            ]
        )]
    )
}

let visibilitySource = """
// comments do not change the exact stock event contract
'use strict';
// Workshop exports may carry inert package provenance before the handler.
export let __workshopId = '9876543210';
export function mediaThumbnailChanged(event) {
    thisObject.visible = event.hasThumbnail;
}
"""
let directBinding = SceneScriptBindingIR(
    source: visibilitySource,
    owner: .init(kind: .effect, objectID: 20, effectIndex: 0),
    properties: ["unrelatedUserCondition": .bool(true)],
    valueType: .boolean,
    targetKey: "visible"
)
let timedBinding = SceneScriptBindingIR(
    source: """
    export let __workshopId = '2468135790';
    var lastHideEvent;
    export function mediaThumbnailChanged(event) {
        if (lastHideEvent) {
            lastHideEvent();
            lastHideEvent = undefined;
        }
        thisObject.visible = event.hasThumbnail;
        if (event.hasThumbnail) {
            lastHideEvent = engine.setTimeout(() => {
                thisObject.visible = false;
            }, 1000);
        }
    }
    """,
    owner: .init(kind: .effect, objectID: 30, effectIndex: 0),
    properties: [:],
    valueType: .boolean,
    targetKey: "visible"
)
let unsupportedBinding = SceneScriptBindingIR(
    source: visibilitySource + "\nexport let metadata = 'different topology';",
    owner: .init(kind: .effect, objectID: 40, effectIndex: 0),
    properties: [:],
    valueType: .boolean,
    targetKey: "visible"
)
let combinedEvidence = SceneScriptSourceEvidenceIR(
    source: visibilitySource,
    owner: .init(kind: .effect, objectID: 40, effectIndex: 0),
    targetKey: "visible",
    wrapperKeys: ["script", "user", "value"]
)
let unsupportedCombinedEvidence = SceneScriptSourceEvidenceIR(
    source: visibilitySource,
    owner: .init(kind: .effect, objectID: 50, effectIndex: 0),
    targetKey: "visible",
    wrapperKeys: ["script", "user", "value", "unknown"]
)
let current = SceneEffectTextureInput(kind: .system, value: "$mediaThumbnail")
let previous = SceneEffectTextureInput(kind: .system, value: "$mediaPreviousThumbnail")
let futureCurrent = SceneEffectTextureInput(kind: .unknown, value: "$mediaThumbnail")
let customCover = SceneEffectTextureInput(kind: .property, value: "customCover")
let malformedCustomCover = SceneEffectTextureInput(
    kind: .unknown, value: "customCover"
)
let undeclaredCover = SceneEffectTextureInput(
    kind: .property, value: "undeclaredCover"
)
let currentInstance = SceneDocument.SceneLayerMaterialInstance(
    id: 7,
    textureSlots: ["util/white"],
    userTextureInputs: [current],
    hasUserTextureOverride: true,
    combos: ["version": 2],
    unknownKeys: [],
    isMalformed: false
)
let previousInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["util/white"], userTextureInputs: [previous],
    hasUserTextureOverride: true, combos: [:], unknownKeys: [], isMalformed: false
)
let badSlotInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["base", "mask"],
    userTextureInputs: [nil, current], hasUserTextureOverride: true,
    combos: [:], unknownKeys: [],
    isMalformed: false
)
let badPreviousSlotInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["base", "mask"],
    userTextureInputs: [nil, previous], hasUserTextureOverride: true,
    combos: [:], unknownKeys: [], isMalformed: false
)
let emptyOverrideInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["fallback"], userTextureInputs: [],
    hasUserTextureOverride: true, combos: [:], unknownKeys: [],
    isMalformed: false
)
let nonNeutralSolidInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["util/black"], userTextureInputs: [current],
    hasUserTextureOverride: true, combos: [:], unknownKeys: [],
    isMalformed: false
)
let customCoverInstance = SceneDocument.SceneLayerMaterialInstance(
    id: nil, textureSlots: ["fallback"], userTextureInputs: [customCover],
    hasUserTextureOverride: true, combos: [:], unknownKeys: [],
    isMalformed: false
)
let descriptor = SceneRenderDescriptor(layers: [
    .init(
        id: 10, contentKind: "image", imagePath: "models/cover.json",
        effects: [effect()]
    ),
    .init(
        id: 20, contentKind: "solid", imagePath: "models/solid.json",
        effects: [effect(path: "effects/workshop/fixture/blend/effect.json", visible: true)]
    ),
    .init(
        id: 30, contentKind: "solid", imagePath: "models/previous.json",
        effects: [effect(visible: true)]
    ),
    .init(
        id: 40, contentKind: "image", imagePath: "models/bad-slot.json",
        effects: [effect(identity: "$unclaimedMediaTexture")]
    ),
    .init(
        id: 50, contentKind: "image", imagePath: "models/multi.json",
        effects: [effect(multiply: 0.5)]
    ),
    .init(
        id: 60, contentKind: "image", imagePath: "models/plain.json",
        effects: [effect(path: "effects/color/effect.json")]
    ),
    .init(
        id: 70, contentKind: "text", imagePath: nil,
        effects: [effect()]
    ),
    .init(
        id: 80, contentKind: "image", imagePath: "models/mismatch.json",
        effects: [effect()]
    ),
    .init(
        id: 90, contentKind: "image", imagePath: "models/future.json",
        effects: [effect()]
    ),
    .init(
        id: 100, contentKind: "solid", imagePath: "models/non-neutral.json",
        effects: [effect()]
    ),
    .init(
        id: 110, contentKind: "solid", imagePath: "models/stock-absent.json",
        effects: [effect()]
    ),
    .init(
        id: 120, contentKind: "solid", imagePath: "models/solid-multi.json",
        effects: [effect()]
    ),
    .init(
        id: 130, contentKind: "solid", imagePath: "models/solid-nil.json",
        effects: [effect()]
    ),
    .init(
        id: 140, contentKind: "solid", imagePath: "models/solid-mismatch.json",
        effects: [effect()]
    ),
    .init(
        id: 150, contentKind: "image", imagePath: "models/previous-bad-slot.json",
        effects: [effect()]
    ),
    .init(
        id: 160, contentKind: "image", imagePath: "models/previous-multi.json",
        effects: [effect()]
    ),
    .init(
        id: 170, contentKind: "image", imagePath: "models/property.json",
        effects: [effect()]
    ),
    .init(
        id: 180, contentKind: "image", imagePath: "models/property-instance.json",
        effects: [effect()]
    ),
    .init(
        id: 190, contentKind: "image", imagePath: "models/property-bad-slot.json",
        effects: [effect()]
    ),
    .init(
        id: 200, contentKind: "image", imagePath: "models/property-undeclared.json",
        effects: [effect()]
    ),
    .init(
        id: 210, contentKind: "image", imagePath: "models/property-malformed.json",
        effects: [effect()]
    ),
    .init(
        id: 220, contentKind: "image", imagePath: "models/provider-mixed.json",
        effects: [effect()]
    ),
], modelMaterialLinks: [
    .init(modelPath: "models/cover.json", materialPath: "materials/cover.json"),
    .init(modelPath: "models/solid.json", materialPath: "materials/solid.json"),
    .init(modelPath: "models/bad-slot.json", materialPath: "materials/bad-slot.json"),
    .init(modelPath: "models/multi.json", materialPath: "materials/multi.json"),
    .init(modelPath: "models/plain.json", materialPath: "materials/plain.json"),
    .init(modelPath: "models/future.json", materialPath: "materials/future.json"),
    .init(modelPath: "models/solid-multi.json", materialPath: "materials/solid-multi.json"),
    .init(modelPath: "models/solid-nil.json", materialPath: "materials/solid-nil.json"),
    .init(
        modelPath: "models/solid-mismatch.json",
        materialPath: "materials/solid-mismatch.json"
    ),
    .init(
        modelPath: "models/previous-bad-slot.json",
        materialPath: "materials/previous-bad-slot.json"
    ),
    .init(
        modelPath: "models/previous-multi.json",
        materialPath: "materials/previous-multi.json"
    ),
    .init(modelPath: "models/property.json", materialPath: "materials/property.json"),
    .init(
        modelPath: "models/property-instance.json",
        materialPath: "materials/property-instance.json"
    ),
    .init(
        modelPath: "models/property-bad-slot.json",
        materialPath: "materials/property-bad-slot.json"
    ),
    .init(
        modelPath: "models/property-undeclared.json",
        materialPath: "materials/property-undeclared.json"
    ),
    .init(
        modelPath: "models/property-malformed.json",
        materialPath: "materials/property-malformed.json"
    ),
    .init(
        modelPath: "models/provider-mixed.json",
        materialPath: "materials/provider-mixed.json"
    ),
], materialPasses: [
    .init(
        materialPath: "materials/cover.json", textureSlots: ["fallback"],
        userTextureInputs: [current]
    ),
    .init(
        materialPath: "materials/solid.json", textureSlots: ["util/white"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/bad-slot.json", textureSlots: ["base", "mask"],
        userTextureInputs: [nil, nil]
    ),
    .init(
        materialPath: "materials/multi.json", textureSlots: ["fallback"],
        userTextureInputs: [current]
    ),
    .init(
        materialPath: "materials/multi.json", textureSlots: ["other"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/plain.json", textureSlots: ["fallback"],
        userTextureInputs: [current]
    ),
    .init(
        materialPath: "materials/future.json", textureSlots: ["fallback"],
        userTextureInputs: [futureCurrent]
    ),
    .init(
        materialPath: "materials/solid-multi.json", textureSlots: ["util/white"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/solid-multi.json", textureSlots: ["util/white"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/solid-nil.json", textureSlots: [nil],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/solid-mismatch.json", textureSlots: ["util/black"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/previous-bad-slot.json", textureSlots: ["base", "mask"],
        userTextureInputs: [nil, nil]
    ),
    .init(
        materialPath: "materials/previous-multi.json", textureSlots: ["fallback"],
        userTextureInputs: [previous]
    ),
    .init(
        materialPath: "materials/previous-multi.json", textureSlots: ["other"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/property.json", textureSlots: ["fallback"],
        userTextureInputs: [customCover]
    ),
    .init(
        materialPath: "materials/property-instance.json", textureSlots: ["fallback"],
        userTextureInputs: [nil]
    ),
    .init(
        materialPath: "materials/property-bad-slot.json",
        textureSlots: ["base", "fallback"], userTextureInputs: [nil, customCover]
    ),
    .init(
        materialPath: "materials/property-undeclared.json",
        textureSlots: ["fallback"], userTextureInputs: [undeclaredCover]
    ),
    .init(
        materialPath: "materials/property-malformed.json",
        textureSlots: ["fallback"], userTextureInputs: [malformedCustomCover]
    ),
    .init(
        materialPath: "materials/provider-mixed.json",
        textureSlots: ["fallback", "mask"],
        userTextureInputs: [current, customCover]
    ),
], texturePropertyKeys: ["customCover"])
let program = SceneBaseMaterialProviderBindingCompiler.compile(
    descriptor: descriptor,
    materialInstancesByLayerID: [
        20: currentInstance,
        30: previousInstance,
        40: badSlotInstance,
        60: emptyOverrideInstance,
        70: currentInstance,
        80: currentInstance,
        100: nonNeutralSolidInstance,
        110: currentInstance,
        120: currentInstance,
        130: currentInstance,
        140: currentInstance,
        150: badPreviousSlotInstance,
        180: customCoverInstance,
    ],
    scriptBindings: [directBinding, timedBinding, unsupportedBinding]
)
let projected = SceneInitialMediaEffectVisibilityProjection.apply(
    to: descriptor,
    scriptBindings: [directBinding, timedBinding, unsupportedBinding],
    sourceEvidence: [combinedEvidence, unsupportedCombinedEvidence]
)
let result: [String: Any] = [
    "accepted": program.currentLayerIDs.sorted(),
    "previousAccepted": program.previousLayerIDs.sorted(),
    "propertyAccepted": program.baseMaterialBindings.compactMap {
        if case .userProperty = $0.value.provider { return $0.key }
        return nil
    }.sorted(),
    "providers": Dictionary(uniqueKeysWithValues: program.baseMaterialBindings.map {
        (String($0.key), $0.value.provider.reportToken)
    }),
    "rejected": Dictionary(uniqueKeysWithValues: program.rejectedBaseMaterialReasons.map {
        (String($0.key), $0.value)
    }),
    "demands": program.systemProviderDemands.map { "\($0.name)" }.sorted(),
    "propertyDemands": program.userPropertyDemands.map(\.propertyKey).sorted(),
    "hasConsumers": program.hasConsumers,
    "report": program.reportLines(),
    "projected": Dictionary(uniqueKeysWithValues: projected.layers.map {
        (String($0.id), $0.effects[0].visible as Any)
    }),
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''


class SceneBaseMaterialProviderBindingTests(unittest.TestCase):
    def test_current_and_previous_binding_compiler_is_shared_and_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-media-binding-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "binding"
            subprocess.run(
                [
                    "swiftc", str(SOURCE), str(COMPILER_SOURCE),
                    str(VISIBILITY_SOURCE),
                    str(harness), "-o", str(binary),
                ],
                check=True,
                cwd=ROOT,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        self.assertEqual(result["accepted"], [10, 20, 110])
        self.assertEqual(result["previousAccepted"], [30])
        self.assertEqual(result["propertyAccepted"], [170, 180])
        self.assertEqual(
            result["providers"],
            {
                "10": "current",
                "20": "current",
                "30": "previous",
                "110": "current",
                "170": "user-property:customCover",
                "180": "user-property:customCover",
            },
        )
        self.assertTrue(result["hasConsumers"])
        self.assertEqual(
            result["demands"],
            ["$mediaPreviousThumbnail", "$mediaThumbnail"],
        )
        self.assertEqual(result["propertyDemands"], ["customCover"])
        self.assertEqual(
            result["rejected"],
            {
                "40": "base-material-current-slot-shape-unsupported",
                "50": "base-material-current-multi-pass-unsupported",
                "80": "base-material-current-instance-fallback-mismatch",
                "90": "base-material-current-slot-shape-unsupported",
                "100": "base-material-current-instance-fallback-mismatch",
                "120": "base-material-current-instance-fallback-mismatch",
                "130": "base-material-current-instance-fallback-mismatch",
                "140": "base-material-current-instance-fallback-mismatch",
                "150": "base-material-previous-slot-shape-unsupported",
                "160": "base-material-previous-multi-pass-unsupported",
                "190": "base-material-user-property-slot-shape-unsupported",
                "210": "base-material-user-property-slot-shape-unsupported",
                "220": "base-material-provider-identity-conflict",
            },
        )
        self.assertEqual(
            result["report"],
            [
                "mediaThumbnailCurrentBindingCount: 3",
                "mediaThumbnailCurrentBindingLayerIDs: 10,20,110",
                "mediaThumbnailCurrentBaseMaterialBindingCount: 3",
                "mediaThumbnailPreviousBindingCount: 1",
                "mediaThumbnailPreviousBindingLayerIDs: 30",
                "mediaThumbnailPreviousBaseMaterialBindingCount: 1",
                "mediaThumbnailCurrentBaseMaterialRejectedCount: 8",
                "mediaThumbnailPreviousBaseMaterialRejectedCount: 2",
                "baseMaterialUserPropertyBindingCount: 2",
                "baseMaterialUserPropertyBindingLayerIDs: 170,180",
                "baseMaterialUserPropertyRejectedCount: 2",
                "baseMaterialProviderOtherRejectedCount: 1",
                "mediaThumbnailBaseMaterialRejectedCount: 10",
                "baseMaterialProviderRejectedCount: 13",
                "baseMaterialUserPropertyBinding: layer=170 "
                "identity=customCover source=material-pass slot=0",
                "baseMaterialUserPropertyBinding: layer=180 "
                "identity=customCover source=layer-instance slot=0",
            ],
        )
        self.assertFalse(result["projected"]["20"])
        self.assertFalse(result["projected"]["30"])
        self.assertFalse(result["projected"]["40"])
        self.assertTrue(result["projected"]["50"])

    def test_launch_uses_current_binding_compiler_without_transition_owner(self) -> None:
        launch = LAUNCH_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "SceneBaseMaterialProviderBindingCompiler.compile(",
            launch,
        )
        self.assertNotIn("SceneMediaThumbnailTransitionCompiler", launch)

        product_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(SCENE_ROOT.rglob("*.swift"))
        )
        for retired_identifier in (
            "SceneMediaThumbnailTransition",
            "previousTransitionsByLayerID",
            "mediaThumbnailPreviousTransition",
        ):
            self.assertNotIn(retired_identifier, product_source)


if __name__ == "__main__":
    unittest.main()
