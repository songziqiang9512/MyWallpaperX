#!/usr/bin/env python3

"""Bounded launch-origin cohort compilation and atomic fixed-mix runtime."""

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
    SCENE / "Properties/SceneSharedBooleanEffectScalarSyntax.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionRuntime.swift",
]
HARNESS = r'''
import Foundation
enum SceneJSONValue: Equatable {
    case bool(Bool), number(Double), string(String), object([String: SceneJSONValue])
    var boolValue: Bool? { if case let .bool(value) = self { value } else { nil } }
    var numberValue: Double? { if case let .number(value) = self { value } else { nil } }
    var stringValue: String? { if case let .string(value) = self { value } else { nil } }
}
enum SceneScriptBindingValueType: Equatable { case boolean, number, string }
enum SceneScriptBindingPathComponent: Equatable { case key(String), index(Int) }
struct SceneScriptBindingOwner: Equatable {
    enum Kind: Equatable { case object, pass }
    let kind: Kind
    let objectIndex: Int?, objectID: Int?
    let effectIndex: Int?, effectID: Int?, passIndex: Int?, passID: Int?
    init(
        kind: Kind, objectIndex: Int?, objectID: Int?,
        effectIndex: Int? = nil, effectID: Int? = nil,
        passIndex: Int? = nil, passID: Int? = nil
    ) {
        self.kind = kind
        self.objectIndex = objectIndex
        self.objectID = objectID
        self.effectIndex = effectIndex
        self.effectID = effectID
        self.passIndex = passIndex
        self.passID = passID
    }
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
    var targetKey: String { if case let .key(key) = targetPath.last { key } else { "" } }
}
struct SceneRenderDescriptor {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String? = nil
        let timeline: Int? = nil
        let timelineDiagnostics: [String] = []
        let scriptSource: String?
        let bindingKeys: [String]
        let components: [Double]?
    }
    struct EffectPass {
        let id: Int?
        let passIndex: Int
        let constantShaderValues: [String: ShaderValue]
    }
    struct Effect {
        let effectID: Int?
        let passes: [EffectPass]
    }
    struct Layer {
        let id: Int, layerIndex: Int
        let visible: Bool?, origin: String?, originXYZ: [Float]?
        let effects: [Effect]
        init(
            id: Int, layerIndex: Int, visible: Bool?, origin: String?,
            originXYZ: [Float]?, effects: [Effect] = []
        ) {
            self.id = id
            self.layerIndex = layerIndex
            self.visible = visible
            self.origin = origin
            self.originXYZ = originXYZ
            self.effects = effects
        }
    }
    let layers: [Layer]
}
@main
enum Harness {
    static func main() throws {
        let valid = compile(bindings: fixture())
        var runtime = SceneLaunchOriginTransitionRuntime(program: valid)
        let trigger: [String: SceneUserPropertyValue] = ["xian": .bool(false)]
        let first = runtime.values(effectivePropertyValues: trigger)
        let second = runtime.values(effectivePropertyValues: trigger)
        let master = target(10)
        let follower = target(11)
        var atomicRuntime = SceneLaunchOriginTransitionRuntime(program: valid)
        let missingTrigger = atomicRuntime.values(effectivePropertyValues: [:])
        let beforeBad = atomicRuntime.values(effectivePropertyValues: [
            "xian": .bool(false), "liveY": .number(200)
        ])
        let bad = atomicRuntime.values(effectivePropertyValues: [
            "xian": .bool(false), "liveY": .string("bad")
        ])
        var clickRuntime = SceneLaunchOriginTransitionRuntime(program: valid)
        let clickInitial = clickRuntime.currentValues(effectivePropertyValues: trigger)
        let clickPressed = clickRuntime.values(
            clickedOwnerLayerIDs: [10], primaryButtonIsDown: true,
            effectivePropertyValues: trigger
        )
        let clickHeld = clickRuntime.values(
            clickedOwnerLayerIDs: [10], primaryButtonIsDown: true,
            effectivePropertyValues: trigger
        )
        let clickReleasedOutside = clickRuntime.values(
            clickedOwnerLayerIDs: [], primaryButtonIsDown: false,
            effectivePropertyValues: trigger
        )
        let clickOutside = clickRuntime.values(
            clickedOwnerLayerIDs: [], primaryButtonIsDown: true,
            effectivePropertyValues: trigger
        )
        _ = clickRuntime.values(
            clickedOwnerLayerIDs: [], primaryButtonIsDown: false,
            effectivePropertyValues: trigger
        )
        let clickToggledBack = clickRuntime.values(
            clickedOwnerLayerIDs: [10], primaryButtonIsDown: true,
            effectivePropertyValues: trigger
        )
        let missingInitializer = compile(bindings: Array(fixture().dropFirst()))
        let extraWrapper = compile(bindings: fixture(wrapperKeys: ["extra", "script", "scriptproperties", "value"]))
        let nilWrapper = compile(bindings: fixture(wrapperKeys: nil))
        let nestedWrapper = compile(bindings: fixture(nestedMasterY: true))
        let malformedFollower = compile(bindings: fixture(followerSource: followerSource().replacingOccurrences(of: "WEMath.mix", with: "WEMath.max", options: [], range: followerSource().range(of: "WEMath.mix"))))
        let missingSharedMember = compile(bindings: fixture() + [familyMember(source: followerSource().replacingOccurrences(of: "shared.panel", with: "panel"), id: 12)])
        let unlexableMember = compile(bindings: fixture() + [familyMember(source: followerSource() + "@", id: 12)])
        let escapedModuleMember = compile(bindings: fixture() + [familyMember(source: followerSource().replacingOccurrences(of: "'WEMath'", with: "'WE\\Math'"), id: 12)])
        let unrelatedOrigin = compile(bindings: fixture() + [binding(index: 3, id: 12, key: "origin", source: "'use strict'; export function update(v){return v;}", properties: [:], value: .string("500 900 0"), type: .string, keys: ["script", "value"])])
        let wrongIdentity = compile(bindings: fixture(followerID: 99))
        let duplicateMaster = compile(bindings: fixture() + [fixture()[1]])
        let initializerDuplicateSources = [
            "malformed": "'use strict'; shared={panel:false,broken:maybe};",
            "unlexable": "'use strict'; shared={panel:false,@};",
            "prefix-failure": "'use\\ strict'; shared={panel:true};",
            "string-key": "'use strict'; shared={other:false,'panel':true};",
            "escaped-shared": "'use strict'; sh\\u0061red={panel:true};",
            "post-function": "'use strict'; function f(){} shared={panel:true};",
            "member-write": "'use strict'; shared.panel=true;",
            "computed-write": "'use strict'; shared['panel']=true;",
            "computed-constructor": "'use strict'; [].filter['constructor']('shared.mafeia=true')();",
            "function-expression-computed-constructor": "'use strict'; var x=function(){}['constructor']('shared.panel=true')();",
            "optional-computed-constructor": "'use strict'; var x={}; x?.['constructor']('shared.panel=true')();",
            "object-reflection": "'use strict'; Object.getOwnPropertyDescriptor(Object.getPrototypeOf(()=>{}),'constructor').value('shared.panel=true')();",
            "missing-strict-global": "var x=(function(){return this})();",
            "computed-alias": "'use strict'; var fn=[].filter[key];", "computed-call": "'use strict'; [].filter[key]();",
            "standalone-reference": "'use strict'; var alias=shared;",
            "indirect-eval": "'use strict'; eval('shared.panel=true');",
            "static-import": "'use strict'; import 'unknown';", "dynamic-import": "'use strict'; import('unknown');",
            "require": "'use strict'; require('unknown');", "Function": "'use strict'; Function('shared.panel=true')();", "Reflect": "'use strict'; Reflect.get(globalThis,'shared');",
            "timeout": "'use strict'; setTimeout(()=>{},0);", "interval": "'use strict'; setInterval(()=>{},0);", "global-handle": "'use strict'; globalThis.shared.panel=true;",
            "legacy-getter": "'use strict'; shared.__defineGetter__('panel',()=>true);",
            "legacy-setter": "'use strict'; shared.__defineSetter__('panel',value=>{});",
            "shared-value-of": "'use strict'; var alias=shared.valueOf(); alias.panel=true;",
            "shared-method-this": "'use strict'; shared.mutate=function(){this.panel=true;}; shared.mutate();",
            "template": "'use strict'; const value=`shared.panel`;",
            "oversize": "'use strict';" + String(repeating: " ", count: 16_385),
            "array-destructure": "'use strict'; [shared.panel]=[true];", "object-destructure": "'use strict'; ({x:shared.panel}={x:true});",
            "for-of": "'use strict'; for(shared.panel of values){}", "for-in": "'use strict'; for(shared.panel in values){}",
            "compound": "'use strict'; shared.panel+=1;", "logical-compound": "'use strict'; shared.panel&&=true;",
            "shift-compound": "'use strict'; shared.panel<<=1;", "prefix-update": "'use strict'; ++shared.panel;",
            "postfix-update": "'use strict'; shared.panel++;", "delete": "'use strict'; delete shared.panel;",
            "parenthesized-write": "'use strict'; (shared.panel=true);",
            "conditional-write": "'use strict'; if(true) shared.panel=true;",
            "comma-write": "'use strict'; 0,shared.panel=true;",
            "block-write": "'use strict'; if(true){shared.panel=true;}",
            "launch-handler": "'use strict'; export function applyUserProperties(x){shared.panel=true;}",
        ]
        var initializerDuplicateRejections = initializerDuplicateSources.mapValues { compile(bindings: fixture() + [initializer($0)]).bindings.isEmpty }
        initializerDuplicateRejections["wrong-wrapper-string-key"] = compile(bindings: fixture() + [initializer("'use strict'; shared={'panel':true};", keys: ["extra", "script", "value"])]).bindings.isEmpty
        initializerDuplicateRejections["wrong-owner-escaped"] = compile(bindings: fixture() + [initializer("'use strict'; sh\\u0061red={panel:true};", id: 99)]).bindings.isEmpty
        initializerDuplicateRejections["user-wrapper-same-flag"] = compile(bindings: fixture() + [initializer("'use strict'; shared.panel=true;", keys: ["script", "user", "value"])]).bindings.isEmpty
        let unrelatedSharedFlags = compile(bindings: fixture() + [initializer("'use strict'; export function cursorEnter(event){shared.mafeib=true;} export function cursorLeave(event){shared.mafeib=false;}", keys: ["script", "user", "value"])])
        let noSharedEvidence = compile(bindings: fixture() + [initializer("'use strict'; export function update(value){return value;}", keys: ["script", "user", "value"])])
        let arrayLiteralEvidence = compile(bindings: fixture() + [initializer("'use strict'; var values=[1,2,3];", keys: ["script", "user", "value"])])
        let escapedStringEvidence = compile(bindings: fixture() + [initializer("'use strict'; var text='a\\nb';", keys: ["script", "user", "value"])])
        let safeComputedReads = compile(bindings: fixture() + [initializer("'use strict'; var x=audioBuffer.average[scriptProperties.frequency] - 1; var y=months[date.getMonth()] + 1;", keys: ["script", "user", "value"])])
        let readOnlySameFlag = compile(bindings: fixture() + [initializer("'use strict'; if(!shared.panel){} if(shared.panel){}", keys: ["script", "user", "value"])])
        let evidenceFlagIsolation = [
            "alpha-same": compile(bindings: fixture(), extraEvidence: [nestedEvidence("alpha", "panel")]).bindings.isEmpty,
            "alpha-other": compile(bindings: fixture(), extraEvidence: [nestedEvidence("alpha", "aux")]).bindings.count == valid.bindings.count,
            "origin-same": compile(bindings: fixture(), extraEvidence: [nestedEvidence("origin", "panel")]).bindings.isEmpty,
            "origin-other": compile(bindings: fixture(), extraEvidence: [nestedEvidence("origin", "aux")]).bindings.count == valid.bindings.count,
        ]
        let syntaxRejections = [
            "return-newline": edit(masterSource(), "return value;", "return\nvalue;"),
            "return-comment-newline": edit(masterSource(), "return value;", "return/*\n*/value;"),
            "return-u2028": edit(masterSource(), "return value;", "return\u{2028}value;"),
            "return-u2029": edit(masterSource(), "return value;", "return\u{2029}value;"),
            "return-crlf": edit(masterSource(), "return value;", "return\r\nvalue;"),
            "else-if-no-parentheses": edit(followerSource(), "else{", "else if{"),
            "else-if-bad-parentheses": edit(followerSource(), "else{", "else if(shared.panel{"),
            "missing-delimiter": edit(masterSource(), ";newScaleY", "newScaleY"),
            "missing-init-comma": edit(masterSource(), "scriptProperties.aX,scriptProperties.aY", "scriptProperties.aX scriptProperties.aY"),
            "extra-init-comma": edit(masterSource(), "scriptProperties.aX,scriptProperties.aY", "scriptProperties.aX,,scriptProperties.aY"),
            "trailing-init-comma": edit(masterSource(), "scriptProperties.aZ),hover", "scriptProperties.aZ,),hover"),
            "leading-zero-number": edit(masterSource(), "value:10,min:1,max:100", "value:010,min:1,max:100"),
            "negative-leading-zero": edit(masterSource(), "min:-1,max:1", "min:-01,max:1"),
            "wrong-globals": edit(masterSource(), "newScaleX=", "wrongScaleX="),
            "reserved-alias": transitionSource(master: true, math: "class"),
            "unicode-alias": transitionSource(master: true, math: "MathAlias²"),
            "unicode-shared-flag": followerSource().replacingOccurrences(of: "shared.panel", with: "shared.panel²"),
            "reserved-update": transitionSource(master: true, updateArgument: "return"),
            "reserved-cursor": transitionSource(master: true, cursorArgument: "yield"),
            "reserved-apply": transitionSource(master: true, applyArgument: "let"),
            "shadow-alias": transitionSource(master: true, math: "speed"),
            "shadow-update": transitionSource(master: true, updateArgument: "hover"),
            "shadow-cursor": transitionSource(master: true, cursorArgument: "shared"),
            "shadow-apply": transitionSource(master: true, applyArgument: "scriptProperties"),
            "shadow-this-layer": transitionSource(master: true, applyArgument: "thisLayer"),
            "duplicate-bindings": transitionSource(
                master: true, math: "value", updateArgument: "value"
            ),
        ]
        let asiSource = masterSource()
            .replacingOccurrences(of: "hover=false;shared", with: "hover=false\nshared")
            .replacingOccurrences(of: "hover=true;shared", with: "hover=true\nshared")
            .replacingOccurrences(of: ";newScaleY", with: "\nnewScaleY")
            .replacingOccurrences(of: ";newScaleZ", with: "\nnewScaleZ")
            .replacingOccurrences(of: ";speed=", with: "\nspeed=")
        let unicodeASIAccepted = ["\r\n", "\u{2028}", "\u{2029}"].allSatisfy { SceneLaunchOriginTransitionSyntax.parse(edit(masterSource(), ";newScaleY", $0 + "newScaleY")) != nil }
        let validElseIf = edit(followerSource(), "else{", "else if(shared.panel==false){")
        let result: [String: Any] = [
            "cohortCount": valid.cohorts.count,
            "bindingCount": valid.bindings.count,
            "layerIDs": valid.layerIDs,
            "masterFirst": vector(first, master),
            "followerFirst": vector(first, follower),
            "masterSecond": vector(second, master),
            "followerSecond": vector(second, follower),
            "atomicBeforeBad": vector(beforeBad, master),
            "missingTrigger": vector(missingTrigger, master),
            "atomicBadMaster": vector(bad, master),
            "atomicBadFollower": vector(bad, follower),
            "scalarBindingCount": valid.scalarBindings.count,
            "clickInitialAlpha": scalar(clickInitial),
            "clickPressedAlpha": scalar(clickPressed),
            "clickHeldAlpha": scalar(clickHeld),
            "clickReleasedOutsideAlpha": scalar(clickReleasedOutside),
            "clickOutsideAlpha": scalar(clickOutside),
            "clickToggledBackAlpha": scalar(clickToggledBack),
            "missingInitializerRejected": missingInitializer.bindings.isEmpty,
            "extraWrapperRejected": extraWrapper.bindings.isEmpty,
            "nilWrapperRejected": nilWrapper.bindings.isEmpty,
            "nestedWrapperRejected": nestedWrapper.bindings.isEmpty,
            "malformedMemberRejectsCohort": malformedFollower.bindings.isEmpty,
            "missingSharedMemberRejectsCohort": missingSharedMember.bindings.isEmpty,
            "unlexableMemberRejectsCohort": unlexableMember.bindings.isEmpty,
            "escapedModuleMemberRejectsProgram": escapedModuleMember.bindings.isEmpty,
            "unrelatedOriginIgnored": unrelatedOrigin.bindings.count == valid.bindings.count,
            "wrongIdentityRejected": wrongIdentity.bindings.isEmpty,
            "duplicateMasterRejected": duplicateMaster.bindings.isEmpty,
            "initializerDuplicateRejections": initializerDuplicateRejections,
            "unrelatedSharedFlagsIgnored": unrelatedSharedFlags.bindings.count == valid.bindings.count,
            "noSharedEvidenceIgnored": noSharedEvidence.bindings.count == valid.bindings.count,
            "arrayLiteralEvidenceIgnored": arrayLiteralEvidence.bindings.count == valid.bindings.count,
            "escapedStringEvidenceIgnored": escapedStringEvidence.bindings.count == valid.bindings.count,
            "safeComputedReadsIgnored": safeComputedReads.bindings.count == valid.bindings.count,
            "readOnlySameFlagIgnored": readOnlySameFlag.bindings.count == valid.bindings.count,
            "evidenceFlagIsolation": evidenceFlagIsolation,
            "inverseOriginEvidenceExempted": compile(bindings: fixture() + [familyMember(source: edit(followerSource(), "if(shared.panel)", "if(shared.panel==false)"), id: 12, nestedY: true)]).bindings.count == valid.bindings.count,
            "syntaxRejections": syntaxRejections.mapValues { SceneLaunchOriginTransitionSyntax.parse($0) == nil },
            "asiSyntaxAccepted": SceneLaunchOriginTransitionSyntax.parse(asiSource) != nil,
            "unicodeASISyntaxAccepted": unicodeASIAccepted,
            "elseIfSyntaxAccepted": SceneLaunchOriginTransitionSyntax.parse(validElseIf) != nil,
            "renamedBindingsAccepted": SceneLaunchOriginTransitionSyntax.parse(transitionSource(master: true, math: "MathAlias", updateArgument: "point", cursorArgument: "clickEvent", applyArgument: "delta")) != nil,
            "prototypeInitializerRejected": SceneLaunchOriginTransitionSyntax
                .parseSharedInitializer("'use strict'; shared={panel:false,__proto__:false};") == nil,
            "prototypeFlagRejected": SceneLaunchOriginTransitionSyntax.parse(followerSource().replacingOccurrences(of: "shared.panel", with: "shared.__proto__")) == nil,
            "masterSyntax": SceneLaunchOriginTransitionSyntax.parse(masterSource()) != nil,
            "followerSyntax": SceneLaunchOriginTransitionSyntax.parse(followerSource()) != nil,
            "initializerSyntax": SceneLaunchOriginTransitionSyntax.parseSharedInitializer(initializerSource()) != nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    static func compile(
        bindings: [SceneScriptBindingIR],
        extraEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> SceneLaunchOriginTransitionProgram {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 20, layerIndex: 0, visible: true, origin: nil, originXYZ: nil),
            .init(id: 10, layerIndex: 1, visible: nil, origin: "100 500 0", originXYZ: [100, 500, 0]),
            .init(
                id: 11, layerIndex: 2, visible: nil,
                origin: "300 700 0", originXYZ: [300, 700, 0],
                effects: [.init(
                    effectID: 30,
                    passes: [.init(
                        id: 31,
                        passIndex: 0,
                        constantShaderValues: ["alpha": .init(
                            valueKind: "binding",
                            scriptSource: scalarSource(),
                            bindingKeys: ["script", "value"],
                            components: [1]
                        )]
                    )]
                )]
            ),
            .init(id: 12, layerIndex: 3, visible: nil, origin: "500 900 0", originXYZ: [500, 900, 0]),
        ])
        let evidence = bindings.map { SceneScriptSourceEvidenceIR(source: $0.source, owner: $0.owner, targetPath: $0.targetPath, wrapperKeys: $0.wrapperKeys ?? []) } + extraEvidence
        return SceneLaunchOriginTransitionProgramCompiler.compile(descriptor: descriptor, scriptBindings: bindings, scriptSourceEvidence: evidence)
    }
    static func fixture(
        wrapperKeys: [String]? = ["script", "scriptproperties", "value"],
        followerSource: String = followerSource(),
        followerID: Int = 11,
        nestedMasterY: Bool = false
    ) -> [SceneScriptBindingIR] {
        [
            binding(index: 0, id: 20, key: "visible", source: initializerSource(),
                    properties: [:], value: .bool(true), type: .boolean,
                    keys: ["script", "value"]),
            binding(index: 1, id: 10, key: "origin", source: masterSource(),
                    properties: properties(
                        base: [100, 200, 0], end: [100, 500, 0],
                        userY: true, nestedY: nestedMasterY
                    ),
                    value: .string("100 500 0"), type: .string, keys: wrapperKeys),
            binding(index: 2, id: followerID, key: "origin", source: followerSource,
                    properties: properties(base: [300, 400, 0], end: [300, 700, 0]),
                    value: .string("300 700 0"), type: .string, keys: wrapperKeys),
            scalarBinding(),
        ]
    }
    static func scalarBinding() -> SceneScriptBindingIR {
        .init(
            source: scalarSource(),
            owner: .init(
                kind: .pass, objectIndex: 2, objectID: 11,
                effectIndex: 0, effectID: 30, passIndex: 0, passID: 31
            ),
            targetPath: [
                .key("objects"), .index(2), .key("effects"), .index(0),
                .key("passes"), .index(0), .key("constantshadervalues"),
                .key("alpha"),
            ],
            properties: [:], authoredValue: .number(1), valueType: .number,
            wrapperKeys: ["script", "value"]
        )
    }
    static func binding(
        index: Int, id: Int, key: String, source: String,
        properties: [String: SceneJSONValue], value: SceneJSONValue,
        type: SceneScriptBindingValueType, keys: [String]?
    ) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: id),
              targetPath: [.key("objects"), .index(index), .key(key)], properties: properties,
              authoredValue: value, valueType: type, wrapperKeys: keys)
    }
    static func familyMember(source: String, id: Int, nestedY: Bool = false) -> SceneScriptBindingIR {
        binding(
            index: 3, id: id, key: "origin", source: source,
            properties: properties(base: [500, 600, 0], end: [500, 900, 0], userY: nestedY, nestedY: nestedY),
            value: .string("500 900 0"), type: .string,
            keys: ["script", "scriptproperties", "value"]
        )
    }
    static func nestedEvidence(
        _ key: String,
        _ flag: String
    ) -> SceneScriptSourceEvidenceIR {
        .init(
            source: "'use strict'; shared.\(flag)=true;",
            owner: .init(kind: .object, objectIndex: 3, objectID: 12),
            targetPath: [
                .key("objects"), .index(3), .key("instanceoverride"), .key(key),
            ],
            wrapperKeys: ["script", "value"]
        )
    }
    static func initializer(_ source: String, id: Int = 20, keys: [String]? = ["script", "value"]) -> SceneScriptBindingIR {
        binding(
            index: 0, id: id, key: "visible", source: source, properties: [:],
            value: .bool(true), type: .boolean, keys: keys
        )
    }
    static func properties(
        base: [Double], end: [Double], userY: Bool = false,
        nestedY: Bool = false
    ) -> [String: SceneJSONValue] {
        var result: [String: SceneJSONValue] = [
            "aX": .number(base[0]), "aY": .number(base[1]), "aZ": .number(base[2]),
            "positionX": .number(end[0]), "positionY": .number(end[1]),
            "positionZ": .number(end[2]), "speed": .number(10),
        ]
        if userY {
            let fallback: SceneJSONValue = nestedY
                ? .object(["user": .string("innerY"), "value": .number(base[1])])
                : .number(base[1])
            result["aY"] = .object([
                "user": .string("liveY"), "value": fallback,
            ])
        }
        return result
    }
    static func target(_ id: Int) -> SceneDynamicTarget { .layer(layerID: id, field: .origin) }
    static func vector(_ values: [SceneDynamicTarget: SceneDynamicValue], _ target: SceneDynamicTarget) -> [Double] {
        guard case let .vector3(x, y, z)? = values[target] else { return [] }
        return [x, y, z]
    }
    static func scalar(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> Double {
        let target = SceneDynamicTarget.effectConstant(
            layerID: 11, effectIndex: 0, passIndex: 0, name: "alpha"
        )
        guard case let .scalar(value)? = values[target] else { return -1 }
        return value
    }
    static func edit(_ source: String, _ old: String, _ new: String) -> String { source.replacingOccurrences(of: old, with: new) }
    static func initializerSource() -> String { "'use strict'; shared={panel:false,other:true};" }
    static func scalarSource() -> String {
        "'use strict'; export function update(value){if(shared.panel){value=0;}else{value=1;}return value;}"
    }
    static func masterSource() -> String { transitionSource(master: true) }
    static func followerSource() -> String { transitionSource(master: false) }
    static func transitionSource(
        master: Bool,
        math: String = "WEMath",
        updateArgument: String = "value",
        cursorArgument: String = "event",
        applyArgument: String = "changed"
    ) -> String {
        let cursor = master
            ? "export function cursorClick(\(cursorArgument)){if(hover){hover=false;shared.panel=false}else{hover=true;shared.panel=true}}"
            : ""
        return """
        'use strict'; import * as \(math) from 'WEMath';
        export var scriptProperties=createScriptProperties()
          .addSlider({name:'aX',label:'x',value:1,min:0,max:10,integer:false})
          .addSlider({name:'aY',label:'y',value:1,min:0,max:10,integer:false})
          .addSlider({name:'aZ',label:'z',value:0,min:-1,max:1,integer:false})
          .addSlider({name:'positionX',label:'x2',value:1,min:0,max:10,integer:false})
          .addSlider({name:'positionY',label:'y2',value:2,min:0,max:10,integer:false})
          .addSlider({name:'positionZ',label:'z2',value:0,min:-1,max:1,integer:false})
          .addSlider({name:'speed',label:'rate',value:10,min:1,max:100,integer:false}).finish();
        var newScaleX=scriptProperties.aX,newScaleY=scriptProperties.aY,newScaleZ=scriptProperties.aZ,initScale=new Vec3(scriptProperties.aX,scriptProperties.aY,scriptProperties.aZ),hover=false,speed;
        export function update(\(updateArgument)){if(\(master ? "hover" : "shared.panel")){\(updateArgument)=new Vec3(\(math).mix(\(updateArgument).x,newScaleX.x,speed),\(math).mix(\(updateArgument).y,newScaleY.y,speed),\(math).mix(\(updateArgument).z,newScaleZ.z,speed),)}else{\(updateArgument)=new Vec3(\(math).mix(\(updateArgument).x,scriptProperties.aX,speed),\(math).mix(\(updateArgument).y,scriptProperties.aY,speed),\(math).mix(\(updateArgument).z,scriptProperties.aZ,speed),)}return \(updateArgument);}
        \(cursor)
        export function applyUserProperties(\(applyArgument)){if(\(applyArgument).hasOwnProperty('xian')){newScaleX=new Vec3(initScale.add(scriptProperties.positionX-newScaleX));newScaleY=new Vec3(initScale.add(scriptProperties.positionY-newScaleY));newScaleZ=new Vec3(initScale.add(scriptProperties.positionZ-newScaleZ));speed=scriptProperties.speed/100;}}
        """
    }
}
'''
class SceneLaunchOriginTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.tempdir = tempfile.TemporaryDirectory()
        directory = Path(cls.tempdir.name)
        harness = directory / "Harness.swift"
        executable = directory / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        result = subprocess.run(
            [swiftc, *map(str, SOURCES), str(harness), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        raw_output = subprocess.run(
            [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True,
        ).stdout
        cls.result = json.loads(raw_output)
    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()
    def test_complete_cohort_advances_with_fixed_per_frame_mix(self) -> None:
        self.assertEqual(self.result["cohortCount"], 1)
        self.assertEqual(self.result["bindingCount"], 2)
        self.assertEqual(self.result["layerIDs"], [10, 11])
        self.assertEqual(self.result["masterFirst"], [100, 470, 0])
        self.assertEqual(self.result["followerFirst"], [300, 670, 0])
        self.assertEqual(self.result["masterSecond"], [100, 443, 0])
        self.assertEqual(self.result["followerSecond"], [300, 643, 0])

    def test_click_edge_toggles_surface_state_and_exact_scalar_consumer(self) -> None:
        self.assertEqual(self.result["scalarBindingCount"], 1)
        self.assertEqual(self.result["clickInitialAlpha"], 1)
        self.assertEqual(self.result["clickPressedAlpha"], 0)
        self.assertEqual(self.result["clickHeldAlpha"], 0)
        self.assertEqual(self.result["clickReleasedOutsideAlpha"], 0)
        self.assertEqual(self.result["clickOutsideAlpha"], 0)
        self.assertEqual(self.result["clickToggledBackAlpha"], 1)

    def test_bad_live_value_freezes_the_whole_cohort_atomically(self) -> None:
        self.assertEqual(self.result["atomicBeforeBad"], self.result["atomicBadMaster"])
        self.assertEqual(self.result["missingTrigger"], [])
        self.assertEqual(self.result["atomicBadFollower"], [300, 670, 0])

    def test_incomplete_or_ambiguous_profiles_fail_closed(self) -> None:
        for key in (
            "missingInitializerRejected", "extraWrapperRejected", "nilWrapperRejected",
            "malformedMemberRejectsCohort", "missingSharedMemberRejectsCohort",
            "unlexableMemberRejectsCohort", "escapedModuleMemberRejectsProgram",
            "wrongIdentityRejected", "duplicateMasterRejected",
            "nestedWrapperRejected",
        ):
            self.assertTrue(self.result[key], key)
        for case, rejected in self.result["initializerDuplicateRejections"].items():
            self.assertTrue(rejected, case)

    def test_syntax_admission_preserves_only_the_bounded_javascript_shape(self) -> None:
        for case, rejected in self.result["syntaxRejections"].items():
            self.assertTrue(rejected, case)
        self.assertTrue(self.result["prototypeInitializerRejected"])
        self.assertTrue(self.result["prototypeFlagRejected"])
        self.assertTrue(self.result["asiSyntaxAccepted"])
        self.assertTrue(self.result["unicodeASISyntaxAccepted"])
        self.assertTrue(self.result["elseIfSyntaxAccepted"])
        self.assertTrue(self.result["renamedBindingsAccepted"])
        self.assertTrue(self.result["unrelatedOriginIgnored"])
        self.assertTrue(self.result["unrelatedSharedFlagsIgnored"])
        self.assertTrue(self.result["noSharedEvidenceIgnored"])
        self.assertTrue(self.result["arrayLiteralEvidenceIgnored"])
        self.assertTrue(self.result["escapedStringEvidenceIgnored"])
        self.assertTrue(self.result["safeComputedReadsIgnored"])
        self.assertTrue(self.result["readOnlySameFlagIgnored"])
        self.assertTrue(self.result["inverseOriginEvidenceExempted"])
        for case, accepted in self.result["evidenceFlagIsolation"].items():
            self.assertTrue(accepted, case)

    def test_product_sources_do_not_dispatch_on_sample_or_layer_literals(self) -> None:
        combined = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES[2:])
        self.assertNotIn("2974757317", combined)
        self.assertNotIn("layerID ==", combined)
