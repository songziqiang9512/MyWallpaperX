#!/usr/bin/env python3

"""Bounded cursor-enter/leave shared flag to origin-transition cohorts."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionProgram.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionConflictScanner.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxBody.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+Syntax.swift",
    SCENE / "Properties/SceneSharedLayerAlphaSyntax.swift",
    SCENE / "Properties/SceneHoverOriginTransitionProgram.swift",
    SCENE / "Properties/SceneHoverOriginTransitionSyntax.swift",
    SCENE / "Properties/SceneHoverOriginTransitionCompiler.swift",
    SCENE / "Properties/SceneHoverOriginTransitionRuntime.swift",
]

HARNESS = r'''
import Foundation

enum SceneJSONValue: Equatable {
    case bool(Bool), number(Double), string(String), object([String: SceneJSONValue])
    var boolValue: Bool? { if case let .bool(value) = self { value } else { nil } }
    var stringValue: String? { if case let .string(value) = self { value } else { nil } }
}
enum SceneScriptBindingValueType { case boolean, string }
enum SceneScriptBindingPathComponent: Equatable { case key(String), index(Int) }
struct SceneScriptBindingOwner: Equatable {
    enum Kind: Equatable { case object }
    let kind: Kind
    let objectIndex: Int?, objectID: Int?
}
struct SceneScriptBindingIR {
    let source: String, owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?, valueType: SceneScriptBindingValueType
    let wrapperKeys: [String]?
    var targetKey: String { if case let .key(key) = targetPath.last { key } else { "" } }
}
struct SceneScriptSourceEvidenceIR {
    let source: String, owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent], wrapperKeys: [String]
}
struct SceneUtilityLayer {
    enum Kind { case composition }
    let kind: Kind
    let copyBackground: Bool
    let passthrough: Bool
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int, layerIndex: Int
        let visible: Bool?, contentKind: String
        let utilityLayer: SceneUtilityLayer?
        let parentID: Int?, childLayerIDs: [Int]
        let effects: [Int], effectFiles: [String]
        let origin: String?, originXYZ: [Float]?
        let sizeWH: [Float]?, scaleXYZ: [Float]?
        let anglesXYZ: [Float]?, parallaxDepthXY: [Float]?
    }
    let layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let valid = compile(fixture())
        var runtime = SceneHoverOriginTransitionRuntime(program: valid)
        let properties: [String: SceneUserPropertyValue] = [
            "xian": .bool(false), "liveY": .number(200),
        ]
        let idle = runtime.values(
            hoveredOwnerLayerIDs: [], effectivePropertyValues: properties
        )
        let enter1 = runtime.values(
            hoveredOwnerLayerIDs: [30], effectivePropertyValues: properties
        )
        let enter2 = runtime.values(
            hoveredOwnerLayerIDs: [30], effectivePropertyValues: properties
        )
        let leave = runtime.values(
            hoveredOwnerLayerIDs: [], effectivePropertyValues: properties
        )
        let beforeBad = runtime.values(
            hoveredOwnerLayerIDs: [30], effectivePropertyValues: properties
        )
        let bad = runtime.values(
            hoveredOwnerLayerIDs: [],
            effectivePropertyValues: ["xian": .bool(false), "liveY": .string("bad")]
        )
        let target40 = target(40), target41 = target(41)
        let malformedOwner = compile(fixture(ownerSource: hoverSource()
            .replacingOccurrences(of: "shared.panel=true", with: "shared.panel=false")))
        let wrongOwnerKind = compile(fixture(ownerContentKind: "image"))
        let visibleOwnerEffects = compile(fixture(ownerHasEffect: true))
        let missingInitializer = compile(Array(fixture().dropFirst()))
        let duplicateOwner = compile(fixture() + [owner(index: 4, id: 31)])
        let unknownWriter = compile(
            fixture(),
            extraEvidence: [evidence(
                index: 4, id: 50, key: "visible",
                source: "'use strict'; shared.panel=true;"
            )]
        )
        let wrongFollowerWrapper = compile(fixture(followerKeys: ["script", "value"]))
        let wrongFollowerIdentity = compile(fixture(followerID: 99))
        let result: [String: Any] = [
            "cohorts": valid.cohorts.count,
            "owners": valid.ownerLayerIDs,
            "layers": valid.layerIDs,
            "idle40": vector(idle, target40),
            "enter140": vector(enter1, target40),
            "enter141": vector(enter1, target41),
            "enter240": vector(enter2, target40),
            "leave40": vector(leave, target40),
            "bad40": vector(bad, target40),
            "bad41": vector(bad, target41),
            "beforeBad40": vector(beforeBad, target40),
            "malformedOwnerRejected": validEmpty(malformedOwner),
            "wrongOwnerKindRejected": validEmpty(wrongOwnerKind),
            "visibleOwnerEffectsRejected": validEmpty(visibleOwnerEffects),
            "missingInitializerRejected": validEmpty(missingInitializer),
            "duplicateOwnerRejected": validEmpty(duplicateOwner),
            "unknownWriterRejected": validEmpty(unknownWriter),
            "wrongFollowerWrapperRejected": validEmpty(wrongFollowerWrapper),
            "wrongFollowerIdentityRejected": validEmpty(wrongFollowerIdentity),
            "syntaxAccepted": SceneHoverOriginTransitionSyntax.parse(hoverSource()) != nil,
            "prototypeRejected": SceneHoverOriginTransitionSyntax.parse(
                hoverSource().replacingOccurrences(of: "shared.panel", with: "shared.__proto__")
            ) == nil,
            "extraHandlerRejected": SceneHoverOriginTransitionSyntax.parse(
                hoverSource() + "export function update(){return 1;}"
            ) == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(
        _ bindings: [SceneScriptBindingIR],
        extraEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> SceneHoverOriginTransitionProgram {
        let evidence = bindings.map {
            SceneScriptSourceEvidenceIR(
                source: $0.source, owner: $0.owner,
                targetPath: $0.targetPath, wrapperKeys: $0.wrapperKeys ?? []
            )
        } + extraEvidence
        return SceneHoverOriginTransitionProgramCompiler.compile(
            descriptor: descriptor(), scriptBindings: bindings,
            scriptSourceEvidence: evidence
        )
    }

    static func fixture(
        ownerSource: String = hoverSource(),
        ownerContentKind: String = "composition",
        ownerHasEffect: Bool = false,
        followerKeys: [String]? = ["script", "scriptproperties", "value"],
        followerID: Int = 41
    ) -> [SceneScriptBindingIR] {
        fixtureOwnerContentKind = ownerContentKind
        fixtureOwnerHasEffect = ownerHasEffect
        return [
            binding(index: 0, id: 20, key: "visible", source: initializerSource(),
                    properties: [:], value: .bool(true), type: .boolean,
                    keys: ["script", "value"]),
            binding(index: 1, id: 30, key: "visible", source: ownerSource,
                    properties: [:], value: .bool(false), type: .boolean,
                    keys: ["script", "value"]),
            follower(index: 2, id: 40, authored: [100, 500, 0],
                     base: [100, 200, 0], end: [100, 500, 0], keys: followerKeys,
                     liveY: true),
            follower(index: 3, id: followerID, authored: [300, 700, 0],
                     base: [300, 400, 0], end: [300, 700, 0], keys: followerKeys),
        ]
    }

    nonisolated(unsafe) static var fixtureOwnerContentKind = "composition"
    nonisolated(unsafe) static var fixtureOwnerHasEffect = false

    static func descriptor() -> SceneRenderDescriptor {
        SceneRenderDescriptor(layers: [
            layer(id: 20, index: 0, visible: true, kind: "project", origin: nil),
            layer(id: 30, index: 1, visible: false,
                  kind: fixtureOwnerContentKind, origin: "500 500 0",
                  utility: .init(kind: .composition, copyBackground: false,
                                 passthrough: false),
                  effects: fixtureOwnerHasEffect ? [1] : []),
            layer(id: 40, index: 2, visible: true, kind: "image", origin: "100 500 0"),
            layer(id: 41, index: 3, visible: true, kind: "image", origin: "300 700 0"),
            layer(id: 50, index: 4, visible: true, kind: "image", origin: "900 900 0"),
        ])
    }

    static func layer(
        id: Int, index: Int, visible: Bool, kind: String, origin: String?,
        utility: SceneUtilityLayer? = nil, effects: [Int] = []
    ) -> SceneRenderDescriptor.Layer {
        let xyz = origin?.split(separator: " ").compactMap { Float($0) }
        return .init(
            id: id, layerIndex: index, visible: visible, contentKind: kind,
            utilityLayer: utility, parentID: nil, childLayerIDs: [],
            effects: effects, effectFiles: effects.isEmpty ? [] : ["effect.json"],
            origin: origin, originXYZ: xyz, sizeWH: [200, 100],
            scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0], parallaxDepthXY: [0, 0]
        )
    }

    static func follower(
        index: Int, id: Int, authored: [Double], base: [Double], end: [Double],
        keys: [String]?, liveY: Bool = false
    ) -> SceneScriptBindingIR {
        var properties: [String: SceneJSONValue] = [
            "aX": .number(base[0]), "aY": .number(base[1]), "aZ": .number(base[2]),
            "positionX": .number(end[0]), "positionY": .number(end[1]),
            "positionZ": .number(end[2]), "speed": .number(10),
        ]
        if liveY {
            properties["aY"] = .object(["user": .string("liveY"), "value": .number(base[1])])
        }
        return binding(
            index: index, id: id, key: "origin", source: followerSource(),
            properties: properties,
            value: .string(authored.map { String(format: "%g", $0) }.joined(separator: " ")),
            type: .string, keys: keys
        )
    }

    static func owner(index: Int, id: Int) -> SceneScriptBindingIR {
        binding(index: index, id: id, key: "visible", source: hoverSource(),
                properties: [:], value: .bool(false), type: .boolean,
                keys: ["script", "value"])
    }

    static func binding(
        index: Int, id: Int, key: String, source: String,
        properties: [String: SceneJSONValue], value: SceneJSONValue,
        type: SceneScriptBindingValueType, keys: [String]?
    ) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: id),
              targetPath: [.key("objects"), .index(index), .key(key)],
              properties: properties, authoredValue: value,
              valueType: type, wrapperKeys: keys)
    }

    static func evidence(
        index: Int, id: Int, key: String, source: String
    ) -> SceneScriptSourceEvidenceIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: id),
              targetPath: [.key("objects"), .index(index), .key(key)],
              wrapperKeys: ["script", "value"])
    }

    static func hoverSource() -> String {
        "'use strict'; export function cursorEnter(event){shared.panel=true;} export function cursorLeave(event){shared.panel=false;}"
    }
    static func initializerSource() -> String { "'use strict'; shared={panel:false};" }
    static func followerSource() -> String {
        """
        'use strict'; import * as WEMath from 'WEMath';
        export var scriptProperties=createScriptProperties()
          .addSlider({name:'aX',label:'x',value:1,min:0,max:10,integer:false})
          .addSlider({name:'aY',label:'y',value:1,min:0,max:10,integer:false})
          .addSlider({name:'aZ',label:'z',value:0,min:-1,max:1,integer:false})
          .addSlider({name:'positionX',label:'x2',value:1,min:0,max:10,integer:false})
          .addSlider({name:'positionY',label:'y2',value:2,min:0,max:10,integer:false})
          .addSlider({name:'positionZ',label:'z2',value:0,min:-1,max:1,integer:false})
          .addSlider({name:'speed',label:'rate',value:10,min:1,max:100,integer:false}).finish();
        var newScaleX=scriptProperties.aX,newScaleY=scriptProperties.aY,newScaleZ=scriptProperties.aZ,initScale=new Vec3(scriptProperties.aX,scriptProperties.aY,scriptProperties.aZ),hover=false,speed;
        export function update(value){if(shared.panel){value=new Vec3(WEMath.mix(value.x,newScaleX.x,speed),WEMath.mix(value.y,newScaleY.y,speed),WEMath.mix(value.z,newScaleZ.z,speed),)}else{value=new Vec3(WEMath.mix(value.x,scriptProperties.aX,speed),WEMath.mix(value.y,scriptProperties.aY,speed),WEMath.mix(value.z,scriptProperties.aZ,speed),)}return value;}
        export function applyUserProperties(changed){if(changed.hasOwnProperty('xian')){newScaleX=new Vec3(initScale.add(scriptProperties.positionX-newScaleX));newScaleY=new Vec3(initScale.add(scriptProperties.positionY-newScaleY));newScaleZ=new Vec3(initScale.add(scriptProperties.positionZ-newScaleZ));speed=scriptProperties.speed/100;}}
        """
    }
    static func target(_ id: Int) -> SceneDynamicTarget { .layer(layerID: id, field: .origin) }
    static func vector(
        _ values: [SceneDynamicTarget: SceneDynamicValue], _ target: SceneDynamicTarget
    ) -> [Double] {
        guard case let .vector3(x, y, z)? = values[target] else { return [] }
        return [x, y, z]
    }
    static func validEmpty(_ program: SceneHoverOriginTransitionProgram) -> Bool {
        program.cohorts.isEmpty && program.bindings.isEmpty
    }
}
'''


class SceneHoverOriginTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.tempdir = tempfile.TemporaryDirectory()
        harness = Path(cls.tempdir.name) / "Harness.swift"
        executable = Path(cls.tempdir.name) / "hover-origin-harness"
        harness.write_text(HARNESS, encoding="utf-8")
        command = [swiftc, "-parse-as-library", *(str(path) for path in SOURCES),
                   str(harness), "-o", str(executable)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        raw = subprocess.run(
            [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True
        ).stdout
        cls.result = json.loads(raw)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    def test_complete_hover_cohort_advances_and_returns(self) -> None:
        self.assertEqual(self.result["cohorts"], 1)
        self.assertEqual(self.result["owners"], [30])
        self.assertEqual(self.result["layers"], [40, 41])
        self.assertEqual(self.result["idle40"], [100, 470, 0])
        self.assertEqual(self.result["enter140"], [100, 473, 0])
        self.assertEqual(self.result["enter141"], [300, 673, 0])
        self.assertEqual(self.result["enter240"], [100, 475.7, 0])
        self.assertEqual(self.result["leave40"], [100, 448.13, 0])

    def test_bad_live_value_freezes_the_complete_cohort(self) -> None:
        self.assertEqual(self.result["bad40"], self.result["beforeBad40"])
        self.assertEqual(self.result["bad41"], [300, 653.317, 0])

    def test_malformed_or_ambiguous_families_fail_closed(self) -> None:
        for key, value in self.result.items():
            if key.endswith("Rejected"):
                self.assertTrue(value, key)

    def test_event_parser_accepts_only_complete_enter_leave_pair(self) -> None:
        self.assertTrue(self.result["syntaxAccepted"])
        self.assertTrue(self.result["prototypeRejected"])
        self.assertTrue(self.result["extraHandlerRejected"])

    def test_product_sources_have_no_sample_or_layer_literal_dispatch(self) -> None:
        combined = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES[8:])
        self.assertNotIn("2974757317", combined)
        self.assertNotIn("layerID ==", combined)


if __name__ == "__main__":
    unittest.main()
