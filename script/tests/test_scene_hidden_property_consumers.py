#!/usr/bin/env python3
"""Prepared hidden consumers accept typed updates without changing visibility."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HOST_SOURCE = SCENE / "Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"
LAYER_SOURCE = SCENE / "Runtime/Frame/SceneRenderDescriptor+Layer.swift"
CATALOG_SOURCE = SCENE / "Compilation/Material/SceneResolvedMaterialRuntimeCatalog.swift"
SOURCE_MATERIAL_SOURCE = SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge+SourceMaterials.swift"
SOURCE_MATERIAL_STORAGE_SOURCE = SCENE / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
VISIBILITY_SOURCE = SCENE / "Rendering/Geometry/SceneLayerVisibility.swift"

# Only declarations for unrelated graph, light, audio and script consumers are
# substituted. The Host function, color eligibility, visibility walk, Program
# validation/evaluation and live state are production implementations.
STUBS = r'''
import Foundation

struct SceneLayerDisplayScriptOwnership {
    var visible = false
    var alpha = false
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}

struct SceneRenderDescriptor {
    struct TextStyle { var limitWidth = false }
    struct AnimationLayer { var id: Int?; var visibilityBinding: Bool? }
    struct Camera {
        struct Bloom {
            struct HDR {}
            var hdr: HDR? = nil
        }
        var orthoWidth: Float? = 512
        var orthoHeight: Float? = 512
        var bloom = Bloom()
        var clearEnabled = true
    }
    struct Layer {
        var id: Int
        var contentKind: String
        var imagePath: String? = nil
        var visible: Bool? = false
        var parentID: Int? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var staticModelPath: String? = nil
        var puppetMeshPath: String? = nil
        var effects: [Int] = []
        var authoredDependencies: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var puppetAnimationLayers: [AnimationLayer] = []
        var namedProviderLayerIDs: [Int] = []
        __COLOR_ELIGIBILITY__
    }
    var layers: [Layer]
    var camera = Camera()
}

struct SceneResolvedMaterialRuntimeCatalog {
    struct Key { var layerID: Int }
    enum Entry { case template, failure }
    struct SourceMaterialEntry {
        var key: Key
        var entry: Entry
        var sharedModelPath: String? = nil
    }
    var sourceMaterialEntries: [Int: SourceMaterialEntry]
    __SOURCE_CANDIDATES__
}

// Prepared-program dictionaries are leaves. Alias lookup is the production
// runtime method, so the candidate projection must cover the same consumers.
final class SceneResolvedMaterialRuntimeBridge {
    struct PreparedSourceMaterial { var sharedModelPath: String? }
    struct SourceMaterialConsumer { var layerID: Int; var prototypeLayerID: Int }
    __SOURCE_MATERIAL_STORAGE__
    private(set) var sourceMaterialPrototypeByModel: [String: Int] = [:]
    __SOURCE_MATERIAL_CONSUMER__
}

struct SceneResolvedMaterialExecutionCapabilityCatalog {
    enum SourceRoute { case capturedLayerTexture, capturedMainTargetTexture, transparentDirectDraw }
    enum DependencyOwnership { case none, graphInternal, externalPrimary, externalAggregate }
    struct Capability {
        var sourceRoute: SourceRoute = .capturedLayerTexture
        var dependencyOwnership: DependencyOwnership = .none
    }
    struct Token { var layerID: Int }
    struct Claim { var token: Token }
    var executionLayerIDs: Set<Int> = []
    var admittedResolvedMaterialReferences: [Int] = []
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
    var capabilities: [Int: Capability] = [:]
    var unresolvedLayerIDs: Set<Int> = []
    // Capability outcomes are leaves; the production Host owns admission.
    func claim(layerID: Int) -> Claim? {
        capabilities[layerID].map { _ in .init(token: .init(layerID: layerID)) }
    }
    func resolve(_ token: Token) -> Capability? {
        unresolvedLayerIDs.contains(token.layerID) ? nil : capabilities[token.layerID]
    }
}
enum SceneUtilityLayerRuntimePlanner {
    enum Kind { case fullscreen }
    struct Plan {
        var kind: Kind
        var requiresNamedTarget: Bool
        var shouldCapture: Bool
    }
    static func plans(in descriptor: SceneRenderDescriptor,
        resolvedMaterialLayerIDs: Set<Int>, admittedResolvedMaterialReferences: [Int])
        -> [Int: Plan] { [:] }
}
enum SceneLightSnapshot {
    static func liveConsumerTargets(descriptor: SceneRenderDescriptor)
        -> Set<SceneDynamicTarget> { [] }
}
enum SceneDependencyGraphAnalysis {
    struct Reference { var providerLayerID: Int }
    static func references(in layers: [SceneRenderDescriptor.Layer])
        -> [Reference] { layers.flatMap { $0.namedProviderLayerIDs.map { Reference(providerLayerID: $0) } } }
}
enum SceneDynamicLayerVisibilityRouteAdmission {
    // Route shape is exercised by the visibility admission gate. Here a legal
    // candidate lets the real Host prove actual preparation is still required.
    static func targets(in descriptor: SceneRenderDescriptor,
        candidates: Set<SceneDynamicTarget>, preparedStaticModelLayerIDs: Set<Int>)
        -> Set<SceneDynamicTarget> { candidates }
}
struct SceneSoundPlaybackProgram {
    var liveConsumerTargets: Set<SceneDynamicTarget> = []
}
struct SceneScriptVectorProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
    var liveUserPropertyConsumerTargetsByKey: [String: Set<SceneDynamicTarget>] = [:]
}
struct SceneScriptScalarProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
    var liveUserPropertyConsumerTargetsByKey: [String: Set<SceneDynamicTarget>] = [:]
}
struct SceneScriptStringProgram {
    var livePropertyInputTargets: Set<SceneDynamicTarget> = []
    var liveUserPropertyConsumerTargetsByKey: [String: Set<SceneDynamicTarget>] = [:]
}
struct SceneRuntimeInput {
    var renderDescriptor: SceneRenderDescriptor
    var propertyBindingProgram: ScenePropertyBindingProgram
    var effectivePropertyValues: [String: SceneUserPropertyValue]
}
enum SceneDesktopWallpaperHost {
    __IMAGE_MODULATION_CONSUMERS__
    __ACTIVE_CONSUMERS__
    __MAKE_LIVE_STATE__
}
'''

HARNESS = r'''
@main enum Probe {
    struct Binding {
        var key: String
        var target: SceneDynamicTarget
        var type: SceneDynamicValueType
        var seed: SceneDynamicValue
    }

    static func program(_ bindings: [Binding], rebuild: [String] = []) -> ScenePropertyBindingProgram {
        .init(
            definitions: bindings.map {
                .init(target: $0.target, valueType: $0.type, authoredValue: $0.seed)
            },
            instructions: bindings.map {
                .init(propertyKey: $0.key, path: .init(components: [.key($0.key)]),
                    target: $0.target, valueType: $0.type)
            }, rebuildRequiredPropertyKeys: rebuild
        )
    }

    static func state(_ layers: [SceneRenderDescriptor.Layer], _ bindings: [Binding],
        values: [String: SceneUserPropertyValue], prepared: Set<Int> = [],
        colorCapabilities: [Int: SceneResolvedMaterialExecutionCapabilityCatalog.Capability] = [:],
        unresolved: Set<Int> = [], sourceCandidates: Set<Int> = [],
        definitions: [SceneUserPropertyDefinition] = [], rebuild: [String] = [],
        scriptConsumers: [String: Set<SceneDynamicTarget>] = [:],
        scriptTargets: Set<SceneDynamicTarget> = [], programOverride: ScenePropertyBindingProgram? = nil,
        clearEnabled: Bool = true, hdr: Bool = false)
        -> ScenePropertyLiveUpdateState {
        let p = programOverride ?? program(bindings, rebuild: rebuild)
        var descriptor = SceneRenderDescriptor(layers: layers)
        descriptor.camera.clearEnabled = clearEnabled
        descriptor.camera.bloom.hdr = hdr ? .init() : nil
        return SceneDesktopWallpaperHost.makeLivePropertyState(
            runtimeInput: .init(renderDescriptor: descriptor,
                propertyBindingProgram: p, effectivePropertyValues: values),
            resolvedMaterialExecutionCapabilities: .init(executionLayerIDs: prepared,
                capabilities: colorCapabilities, unresolvedLayerIDs: unresolved),
            soundPlaybackProgram: .init(), preparedStaticModelLayerIDs: [],
            preparedImageMaterialTargets: [], sourceMaterialCandidateConsumerLayerIDs: sourceCandidates,
            propertyVectorScriptProgram: .init(livePropertyInputTargets: scriptTargets,
                liveUserPropertyConsumerTargetsByKey: scriptConsumers),
            sceneScriptScalarProgram: .init(), sceneScriptStringProgram: .init()
            __PROPERTY_DEFINITIONS_ARGUMENT__
        )
    }

    static func unchanged(_ a: ScenePropertyLiveUpdateState,
        _ b: ScenePropertyLiveUpdateState) -> Bool {
        a.effectiveValues == b.effectiveValues && a.userValues == b.userValues
            && a.revision == b.revision
    }

    static func clearColorFacts() -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for key in ["palette", "renamedBackdrop"] {
            let seed = SceneUserPropertyValue.string("0.125 0.25 0.5")
            func property(_ value: SceneUserPropertyValue?, kind: SceneUserPropertyKind = .color)
                -> SceneUserPropertyDefinition {
                .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
                    order: 0, index: nil, minimumValue: nil, maximumValue: nil,
                    stepValue: nil, allowsFractionalValues: true, fractionalPrecision: nil,
                    displayCondition: nil, defaultValue: value, options: [])
            }
            let definition = property(seed)
            func compile(extra: [String: Any] = [:], objects: [[String: Any]] = [],
                         catalog: SceneUserPropertyCatalog? = nil)
                -> ScenePropertyBindingCompilation {
                let wrapper: [String: Any] = ["user": key, "value": seed.foundationValue]
                    .merging(extra) { _, new in new }
                return ScenePropertyBindingCompiler().compile(
                    report: SceneUserPropertyBindingParser().parse(root: [
                        "general": ["clearcolor": wrapper], "objects": objects]),
                    catalog: catalog ?? .init(definitions: [definition]))
            }
            let compiled = compile()
            facts[key + "-compiled"] = compiled.program.instructions.count == 1
                && compiled.program.rebuildRequiredPropertyKeys.isEmpty && compiled.diagnostics.isEmpty
            guard let field = SceneDynamicSceneField(rawValue: "clearColor") else {
                facts[key + "-typed-field"] = false
                continue
            }
            let target = SceneDynamicTarget.scene(field)
            let encoded = try! JSONEncoder().encode(compiled)
            facts[key + "-roundtrip"] = (try! JSONDecoder().decode(
                ScenePropertyBindingCompilation.self, from: encoded)) == compiled
            facts[key + "-null-inactive-sources"] = compile(extra: ["script": NSNull(), "animation": NSNull()])
                .program.rebuildRequiredPropertyKeys.isEmpty
            func fresh(_ program: ScenePropertyBindingProgram? = nil, clear: Bool = true,
                       hdr: Bool = false, layers: [SceneRenderDescriptor.Layer] = []) -> ScenePropertyLiveUpdateState {
                state(layers, [], values: [key: seed], definitions: [definition],
                    programOverride: program ?? compiled.program, clearEnabled: clear, hdr: hdr)
            }
            for hdr in [false, true] {
                var live = fresh(hdr: hdr)
                facts[key + "-active-\(hdr)"] = live.activeConsumerTargets.contains(target)
                facts[key + "-edit-\(hdr)"] = live.apply(.string("0.75 0.5 0.25"), forPropertyKey: key)
                    && live.userValues[target] == .vector3(0.75, 0.5, 0.25) && live.revision == 1
                let same = live
                facts[key + "-same-\(hdr)"] = live.apply(.string("0.75 0.5 0.25"), forPropertyKey: key)
                    && unchanged(live, same)
                facts[key + "-reset-\(hdr)"] = live.apply(seed, forPropertyKey: key)
                    && live.userValues[target] == .vector3(0.125, 0.25, 0.5) && live.revision == 2
                var off = fresh(clear: false, hdr: hdr); let before = off
                facts[key + "-clear-off-\(hdr)"] = !off.activeConsumerTargets.contains(target)
                    && !off.apply(.string("0.2 0.4 0.6"), forPropertyKey: key) && unchanged(off, before)
            }
            for (name, bad) in [("number", SceneUserPropertyValue.number(1)), ("bool", .bool(true)),
                ("short", .string("0.1 0.2")), ("long", .string("0.1 0.2 0.3 1")),
                ("nan", .string("0 NaN 1")), ("infinity", .string("0 inf 1")),
                ("text", .string("0 blue 1"))] {
                var live = fresh(); let before = live
                facts[key + "-invalid-" + name] = !live.apply(bad, forPropertyKey: key) && unchanged(live, before)
            }
            var absent = ScenePropertyLiveUpdateState(program: compiled.program,
                effectiveValues: [key: seed], activeConsumerTargets: [])
            let beforeAbsent = absent
            facts[key + "-no-consumer"] = !absent.apply(.string("0.2 0.4 0.6"), forPropertyKey: key)
                && unchanged(absent, beforeAbsent)
            for (name, extra) in [("script", ["script": "export function update(v) { return v; }"] as [String: Any]),
                                  ("animation", ["animation": ["frames": []]]),
                                  ("conditional", ["user": ["name": key, "condition": "1"]]),
                                  ("bad-fallback", ["value": "0.2 0.4"]),
                                  ("missing-fallback", ["value": NSNull()])] {
                let conflict = compile(extra: extra).program
                var live = fresh(conflict); let before = live
                facts[key + "-conflict-" + name] = conflict.rebuildRequiredPropertyKeys.contains(key)
                    && !live.apply(.string("0.2 0.4 0.6"), forPropertyKey: key) && unchanged(live, before)
            }
            for (name, catalog) in [("bad-default", [property(.string("0.2 0.4"))]),
                                   ("missing-default", [property(nil)]),
                                   ("wrong-kind", [property(.bool(true), kind: .bool)]),
                                   ("duplicate", [definition, definition])] {
                let rejected = compile(catalog: .init(definitions: catalog)).program
                var live = fresh(rejected); let before = live
                facts[key + "-catalog-" + name] = rejected.rebuildRequiredPropertyKeys.contains(key)
                    && !live.apply(.string("0.2 0.4 0.6"), forPropertyKey: key) && unchanged(live, before)
            }
            let clearSwitch = ScenePropertyBindingCompiler().compile(
                report: SceneUserPropertyBindingParser().parse(root: ["general": [
                    "clearenabled": ["user": key, "value": true]]]),
                catalog: .init(definitions: [property(.bool(true), kind: .bool)])).program
            var switchState = state([], [], values: [key: .bool(true)],
                definitions: [property(.bool(true), kind: .bool)], programOverride: clearSwitch)
            let beforeSwitch = switchState
            facts[key + "-clear-switch-still-rebuilds"] = clearSwitch.rebuildRequiredPropertyKeys.contains(key)
                && !switchState.apply(.bool(false), forPropertyKey: key) && unchanged(switchState, beforeSwitch)
            let colored: [String: Any] = ["id": 91, "image": "models/renamed-solid.json",
                "color": ["user": key, "value": seed.foundationValue]]
            let mixed = compile(objects: [colored]).program
            let layerTarget = SceneDynamicTarget.layer(layerID: 91, field: .color)
            var shared = fresh(mixed, layers: [.init(id: 91, contentKind: "solid")])
            facts[key + "-shared"] = shared.apply(.string("0.2 0.4 0.6"), forPropertyKey: key)
                && shared.userValues[target] == .vector3(0.2, 0.4, 0.6)
                && shared.userValues[layerTarget] == .vector3(0.2, 0.4, 0.6) && shared.revision == 1
            var inactive = fresh(mixed); let beforeInactive = inactive
            facts[key + "-shared-inactive"] = !inactive.apply(.string("0.2 0.4 0.6"), forPropertyKey: key)
                && unchanged(inactive, beforeInactive)
            let unknown: [String: Any] = ["id": 92, "unknownField": ["user": key, "value": seed.foundationValue]]
            var structural = fresh(compile(objects: [unknown]).program); let beforeStructural = structural
            facts[key + "-shared-unsupported"] = !structural.apply(.string("0.2 0.4 0.6"), forPropertyKey: key)
                && unchanged(structural, beforeStructural)
        }
        return facts
    }

    // Catalog kind/default and callback registrations are typed input leaves.
    // The production Host merges them and the real State owns all admission.
    static func unboundBooleanFacts() -> [String: Bool] {
        func definition(_ key: String, kind: SceneUserPropertyKind = .bool,
                        seed: SceneUserPropertyValue? = .bool(true)) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
                order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
                allowsFractionalValues: true, fractionalPrecision: nil, displayCondition: nil,
                defaultValue: seed, options: [])
        }
        var facts: [String: Bool] = [:]
        for key in ["gate", "renamedPanelSwitch"] {
            let defs = [definition(key)]
            func fresh(values: [String: SceneUserPropertyValue]? = nil,
                       definitions: [SceneUserPropertyDefinition]? = nil) -> ScenePropertyLiveUpdateState {
                state([], [], values: values ?? [key: .bool(true)], definitions: definitions ?? defs)
            }
            var value = fresh()
            facts[key + "-changed"] = value.apply(.bool(false), forPropertyKey: key)
                && value.effectiveValues[key] == .bool(false) && value.userValues.isEmpty && value.revision == 1
            let changed = value
            facts[key + "-same"] = value.apply(.bool(false), forPropertyKey: key) && unchanged(value, changed)
            facts[key + "-empty"] = value.apply(replacements: [key: .bool(true)], changedPropertyKeys: [])
                && unchanged(value, changed)
            facts[key + "-reset"] = value.apply(.bool(true), forPropertyKey: key)
                && value.effectiveValues[key] == .bool(true) && value.userValues.isEmpty && value.revision == 2
            let initial = fresh()
            for (name, replacements, keys) in [
                ("unknown", ["unknown": SceneUserPropertyValue.bool(false)], Set(["unknown"])),
                ("type-number", [key: .number(0)], Set([key])),
                ("type-string", [key: .string("false")], Set([key])),
                ("deletion", [:], Set([key]))] {
                var attempt = initial
                facts[key + "-" + name] = !attempt.apply(replacements: replacements, changedPropertyKeys: keys)
                    && unchanged(attempt, initial)
            }
            for (name, definitions) in [
                ("duplicate", defs + defs), ("number-default", [definition(key, seed: .number(1))]),
                ("missing-default", [definition(key, seed: nil)]),
                ("resource-kind", [definition(key, kind: .sceneTexture)]),
                ("unknown-kind", [definition(key, kind: .unsupported)])] {
                var attempt = fresh(definitions: definitions); let before = attempt
                facts[key + "-" + name] = !attempt.apply(.bool(false), forPropertyKey: key)
                    && unchanged(attempt, before)
            }
            var wrongCurrent = fresh(values: [key: .number(1)]); let beforeWrongCurrent = wrongCurrent
            facts[key + "-wrong-current"] = !wrongCurrent.apply(.bool(false), forPropertyKey: key)
                && unchanged(wrongCurrent, beforeWrongCurrent)
            var ordinaryResource = fresh(values: [key: .string("old.png")],
                definitions: [definition(key, kind: .sceneTexture, seed: .string("old.png"))])
            let beforeOrdinaryResource = ordinaryResource
            facts[key + "-ordinary-resource"] = !ordinaryResource.apply(.string("new.png"), forPropertyKey: key)
                && unchanged(ordinaryResource, beforeOrdinaryResource)
            var resource = fresh(); let beforeResource = resource
            facts[key + "-resource-path"] = !resource.apply(replacements: [key: .bool(false)],
                changedPropertyKeys: [key], preparedTexturePropertyKeys: [key]) && unchanged(resource, beforeResource)
            var structural = state([], [], values: [key: .bool(true)], definitions: defs, rebuild: [key])
            let beforeStructural = structural
            facts[key + "-structural"] = !structural.apply(.bool(false), forPropertyKey: key)
                && unchanged(structural, beforeStructural)
            var raw = ScenePropertyLiveUpdateState(program: program([]),
                effectiveValues: [key: .bool(true)], activeConsumerTargets: [])
            let beforeRaw = raw
            facts[key + "-default-conservative"] = !raw.apply(.bool(false), forPropertyKey: key)
                && unchanged(raw, beforeRaw)
            let target = SceneDynamicTarget.effectVisibility(layerID: 61, effectIndex: 0)
            let bound = Binding(key: key, target: target, type: .bool, seed: .bool(true))
            var unavailable = state([], [bound], values: [key: .bool(true)], definitions: defs)
            let beforeUnavailable = unavailable
            facts[key + "-bound-unavailable"] = !unavailable.apply(.bool(false), forPropertyKey: key)
                && unchanged(unavailable, beforeUnavailable)
            let malformed = ScenePropertyBindingProgram(definitions: [], instructions: [
                .init(propertyKey: key, path: .init(components: []), target: target, valueType: .bool)])
            var malformedState = state([], [], values: [key: .bool(true)], definitions: defs,
                programOverride: malformed); let beforeMalformed = malformedState
            facts[key + "-raw-invalid-instruction"] = !malformedState.apply(.bool(false), forPropertyKey: key)
                && unchanged(malformedState, beforeMalformed)
            // A callback consumes every defined property even without a typed binding.
            var callback = state([], [], values: [key: .bool(true)], definitions: defs,
                scriptConsumers: [key: [target]], scriptTargets: [target])
            facts[key + "-callback"] = callback.apply(.bool(false), forPropertyKey: key)
                && callback.effectiveValues[key] == .bool(false) && callback.revision == 1
            let beforeCallback = callback
            facts[key + "-callback-disabled"] = !callback.apply(.bool(true), forPropertyKey: key,
                unavailableConsumerTargets: [target]) && unchanged(callback, beforeCallback)
            var missingCallback = state([], [], values: [key: .bool(true)], definitions: defs,
                scriptConsumers: [key: [target]])
            let beforeMissingCallback = missingCallback
            facts[key + "-callback-unavailable"] = !missingCallback.apply(.bool(false), forPropertyKey: key)
                && unchanged(missingCallback, beforeMissingCallback)
            let opacity = SceneDynamicTarget.layer(layerID: 62, field: .alpha)
            let hot = Binding(key: "opacity", target: opacity, type: .scalar, seed: .scalar(1))
            var mixed = state([.init(id: 62, contentKind: "image")], [hot],
                values: [key: .bool(true), "opacity": .number(1)], definitions: defs)
            facts[key + "-mixed-hot"] = mixed.apply(replacements: [key: .bool(false), "opacity": .number(0.25)],
                changedPropertyKeys: [key, "opacity"]) && mixed.effectiveValues[key] == .bool(false)
                && mixed.userValues[opacity] == .scalar(0.25) && mixed.revision == 1
            let beforeMixed = mixed
            facts[key + "-mixed-invalid"] = !mixed.apply(replacements: [key: .bool(true), "opacity": .string("bad")],
                changedPropertyKeys: [key, "opacity"]) && unchanged(mixed, beforeMixed)
        }
        return facts
    }

    static func main() throws {
        let hiddenText = SceneRenderDescriptor.Layer(id: 1, contentKind: "text",
            text: "old", textStyle: .init(limitWidth: true))
        let visibleText = SceneRenderDescriptor.Layer(id: 2, contentKind: "text",
            visible: true, text: "old", textStyle: .init())
        let hiddenImage = SceneRenderDescriptor.Layer(id: 3, contentKind: "image")
        let effectedImage = SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
            effects: [1])
        let noStyleText = SceneRenderDescriptor.Layer(id: 5, contentKind: "text", text: "old")
        let noContentText = SceneRenderDescriptor.Layer(id: 6, contentKind: "text",
            textStyle: .init())
        let unlimitedText = SceneRenderDescriptor.Layer(id: 7, contentKind: "text",
            text: "old", textStyle: .init())
        let unknown = SceneRenderDescriptor.Layer(id: 8, contentKind: "unknown")
        let allLayers = [hiddenText, visibleText, hiddenImage, effectedImage,
            noStyleText, noContentText, unlimitedText, unknown]
        var rows: [String: [String: Bool]] = [:]
        rows["unboundBoolean"] = unboundBooleanFacts()
        rows["clearColor"] = clearColorFacts()
        let effectColor = SceneDynamicTarget.layer(layerID: 4, field: .color)
        let effectBinding = Binding(key: "renamedTint", target: effectColor,
            type: .vector3, seed: .vector3(1, 1, 1))
        typealias ColorCapability = SceneResolvedMaterialExecutionCapabilityCatalog.Capability
        for (name, capability, unresolved, completed) in [
            ("capturedImage", ColorCapability(), false, false),
            ("missingClaim", nil, false, false),
            ("unresolvedClaim", ColorCapability(), true, false),
            ("capturedMain", ColorCapability(sourceRoute: .capturedMainTargetTexture), false, false),
            ("transparentSource", ColorCapability(sourceRoute: .transparentDirectDraw), false, false),
            ("internalDependency", ColorCapability(dependencyOwnership: .graphInternal), false, false),
            ("externalProvider", ColorCapability(dependencyOwnership: .externalPrimary), false, false),
            ("aggregateProvider", ColorCapability(dependencyOwnership: .externalAggregate), false, false),
            ("sourceTemplateCandidate", ColorCapability(), false, true),
        ] as [(String, ColorCapability?, Bool, Bool)] {
            var s = state([effectedImage], [effectBinding], values: ["renamedTint": .string("1 1 1")],
                colorCapabilities: capability.map { [4: $0] } ?? [:],
                unresolved: unresolved ? [4] : [], sourceCandidates: completed ? [4] : [])
            let before = s
            let accepted = s.apply(.string("0.2 0.4 0.6"), forPropertyKey: "renamedTint")
            rows[name] = ["potential": effectedImage.supportsUserPropertyLayerColorConsumer,
                "admitted": s.activeConsumerTargets.contains(effectColor), "accepted": accepted,
                "published": s.userValues[effectColor] == .vector3(0.2, 0.4, 0.6),
                "unchanged": unchanged(s, before), "scriptUnchanged": !effectedImage.supportsDirectLayerColorConsumer]
        }
        // No runtime or PSO success is supplied: a template can warm on another
        // surface after the first one failed. Only the catalog owns this fact.
        let alias = SceneRenderDescriptor.Layer(id: 14, contentKind: "image",
            imagePath: " Models\\Shared.JSON ", effects: [1])
        let failed = SceneRenderDescriptor.Layer(id: 15, contentKind: "image",
            imagePath: "models/failed.json", effects: [1])
        let absent = SceneRenderDescriptor.Layer(id: 16, contentKind: "image",
            imagePath: "models/absent.json", effects: [1])
        let sourceCatalog = SceneResolvedMaterialRuntimeCatalog(sourceMaterialEntries: [
            4: .init(key: .init(layerID: 4), entry: .template, sharedModelPath: "models/shared.json"),
            15: .init(key: .init(layerID: 15), entry: .failure, sharedModelPath: "models/failed.json"),
        ])
        let candidates = sourceCatalog.sourceMaterialCandidateConsumerLayerIDs(
            in: .init(layers: [effectedImage, alias, failed, absent]))
        let firstSurface = SceneResolvedMaterialRuntimeBridge()
        let laterSurface = SceneResolvedMaterialRuntimeBridge()
        laterSurface.sourceMaterials = [4: .init(sharedModelPath: "models/shared.json")]
        let ambiguousSurface = SceneResolvedMaterialRuntimeBridge()
        ambiguousSurface.sourceMaterials = [4: .init(sharedModelPath: "models/shared.json"),
            18: .init(sharedModelPath: "models/shared.json")]
        rows["sourceCandidateProjection"] = ["templateWithoutRuntimeExcluded": candidates.contains(4),
            "normalizedSharedAliasExcluded": candidates.contains(14),
            "firstSurfaceHasNoPreparedSource": firstSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath) == nil,
            "laterSurfaceUsesSameAlias": laterSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath)?.prototypeLayerID == 4,
            "ambiguousRuntimeKeepsOriginalRejection": ambiguousSurface.sourceMaterialConsumer(
                layerID: alias.id, modelPath: alias.imagePath) == nil,
            "failedTemplateNotExcluded": !candidates.contains(15),
            "missingTemplateNotExcluded": !candidates.contains(16), "exactSet": candidates == [4, 14]]
        for (name, layer) in [("coldTemplate", effectedImage), ("sharedSourceAlias", alias),
                              ("failedSourceTemplate", failed), ("noSourceCandidate", absent)] {
            let target = SceneDynamicTarget.layer(layerID: layer.id, field: .color)
            var s = state([layer], [.init(key: "differentTint", target: target,
                type: .vector3, seed: .vector3(1, 1, 1))], values: ["differentTint": .string("1 1 1")],
                colorCapabilities: [layer.id: .init()], sourceCandidates: candidates)
            let before = s
            let accepted = s.apply(.string("0 1 0"), forPropertyKey: "differentTint")
            rows[name] = ["accepted": accepted, "published": s.userValues[target] == .vector3(0, 1, 0),
                "unchanged": unchanged(s, before)]
        }
        for (name, layer) in [
            ("puppetImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                puppetMeshPath: "renamed.mdl", effects: [1])),
            ("modelImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                staticModelPath: "renamed.model", effects: [1])),
            ("dependentImage", SceneRenderDescriptor.Layer(id: 4, contentKind: "image",
                effects: [1], authoredDependencies: [91])),
        ] {
            var s = state([layer], [effectBinding], values: ["renamedTint": .string("1 1 1")],
                colorCapabilities: [4: .init()])
            let before = s
            rows[name] = ["potentialRejected": !layer.supportsUserPropertyLayerColorConsumer,
                "rejected": !s.apply(.string("0 1 0"), forPropertyKey: "renamedTint"),
                "atomic": unchanged(s, before)]
        }
        var brightnessFacts: [String: Bool] = [:]
        let brightness = SceneDynamicTarget.layer(layerID: 4, field: .brightness)
        let brightnessBinding = Binding(key: "gain", target: brightness, type: .scalar, seed: .scalar(0.9))
        for effects in [[], [1]] {
            let image = SceneRenderDescriptor.Layer(id: 4, contentKind: "image", effects: effects)
            let prefix = effects.isEmpty ? "direct" : "effectful"
            let capabilities: [Int: SceneResolvedMaterialExecutionCapabilityCatalog.Capability] = effects.isEmpty ? [:] : [4: .init()]
            var ready = state([image], [brightnessBinding], values: ["gain": .number(0.9)], colorCapabilities: capabilities)
            brightnessFacts[prefix + "-ready"] = ready.apply(.number(2), forPropertyKey: "gain")
                && ready.activeConsumerTargets.contains(brightness)
                && ready.activeConsumerTargets.contains(.layer(layerID: 4, field: .color))
                && ready.userValues[brightness] == .scalar(2) && ready.revision == 1
                && image.visible == false
            var visible = image; visible.visible = true
            var visibleState = state([visible], [brightnessBinding], values: ["gain": .number(0.9)],
                colorCapabilities: capabilities)
            brightnessFacts[prefix + "-visible"] = visibleState.apply(.number(0.5), forPropertyKey: "gain")
                && visibleState.userValues[brightness] == .scalar(0.5) && visibleState.revision == 1
            for kind in ["puppet", "model", "dependency", "dependencyIDs", "namedProvider", "completed"] {
                var layer = image
                if kind == "puppet" { layer.puppetMeshPath = "changed.mdl" }
                if kind == "model" { layer.staticModelPath = "changed.model" }
                if kind == "dependency" { layer.authoredDependencies = [91] }
                if kind == "dependencyIDs" { layer.dependencyLayerIDs = [91] }
                let layers = kind == "namedProvider" ? [layer,
                    SceneRenderDescriptor.Layer(id: 91, contentKind: "image", namedProviderLayerIDs: [4])] : [layer]
                var rejected = state(layers, [brightnessBinding], values: ["gain": .number(0.9)],
                    colorCapabilities: capabilities, sourceCandidates: kind == "completed" ? [4] : [])
                let before = rejected
                brightnessFacts[prefix + "-" + kind] = !rejected.apply(.number(2), forPropertyKey: "gain")
                    && !rejected.activeConsumerTargets.contains(brightness)
                    && unchanged(rejected, before)
            }
        }
        for (name, layer, excluded) in [("coldTemplate", effectedImage, true),
            ("sharedSourceAlias", alias, true), ("failedTemplate", failed, false),
            ("absentTemplate", absent, false)] {
            let target = SceneDynamicTarget.layer(layerID: layer.id, field: .brightness)
            var s = state([layer], [.init(key: "renamedGain", target: target,
                type: .scalar, seed: .scalar(0.9))], values: ["renamedGain": .number(0.9)],
                colorCapabilities: [layer.id: .init()], sourceCandidates: candidates)
            let before = s
            let accepted = s.apply(.number(2), forPropertyKey: "renamedGain")
            brightnessFacts[name] = accepted == !excluded
                && s.activeConsumerTargets.contains(target) == !excluded
                && (excluded ? unchanged(s, before) : s.userValues[target] == .scalar(2))
        }
        let rejectedCapabilities: [(String, SceneResolvedMaterialExecutionCapabilityCatalog.Capability?, Bool)] = [
            ("missing", nil, false), ("unresolved", .init(), true),
            ("main", .init(sourceRoute: .capturedMainTargetTexture), false),
            ("transparent", .init(sourceRoute: .transparentDirectDraw), false),
            ("internal", .init(dependencyOwnership: .graphInternal), false),
            ("dependency", .init(dependencyOwnership: .externalPrimary), false),
            ("aggregate", .init(dependencyOwnership: .externalAggregate), false)]
        for (name, capability, unresolved) in rejectedCapabilities {
            let layer = SceneRenderDescriptor.Layer(id: 4, contentKind: "image", effects: [1])
            var rejected = state([layer], [brightnessBinding], values: ["gain": .number(0.9)],
                colorCapabilities: capability.map { [4: $0] } ?? [:], unresolved: unresolved ? [4] : [])
            let before = rejected
            brightnessFacts[name] = !rejected.apply(.number(2), forPropertyKey: "gain")
                && !rejected.activeConsumerTargets.contains(brightness) && unchanged(rejected, before)
        }
        rows["brightness"] = brightnessFacts
        let composition = SceneRenderDescriptor.Layer(id: 9, contentKind: "composition",
            effects: [1], authoredDependencies: [10], dependencyLayerIDs: [10])
        let visibilityTarget = SceneDynamicTarget.layer(layerID: 9, field: .visibility)
        let visibilityBinding = Binding(key: "show", target: visibilityTarget,
            type: .bool, seed: .bool(false))
        for prepared in [false, true] {
            var s = state([composition], [visibilityBinding], values: ["show": .bool(false)],
                prepared: prepared ? [9, 10] : [])
            let before = s
            let accepted = s.apply(.bool(true), forPropertyKey: "show")
            rows[prepared ? "preparedComposition" : "unpreparedComposition"] = [
                "admitted": s.activeConsumerTargets.contains(visibilityTarget),
                "accepted": accepted, "unchanged": unchanged(s, before),
            ]
        }
        let cases: [(String, SceneDynamicTarget, SceneDynamicValueType,
            SceneDynamicValue, SceneUserPropertyValue, SceneUserPropertyValue,
            SceneDynamicValue)] = [
            ("content", .text(layerID: 1, field: .content), .string, .string("old"),
                .string("old"), .string("new"), .string("new")),
            ("pointSize", .text(layerID: 1, field: .pointSize), .scalar, .scalar(16),
                .number(16), .number(32), .scalar(32)),
            ("color", .text(layerID: 1, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0.2 0.4 0.6"), .vector3(0.2, 0.4, 0.6)),
            ("maxWidth", .text(layerID: 1, field: .maxWidth), .scalar, .scalar(100),
                .number(100), .number(160), .scalar(160)),
            ("imageColor", .layer(layerID: 3, field: .color), .vector3,
                .vector3(1, 1, 1), .string("1 1 1"), .string("0 1 0"), .vector3(0, 1, 0)),
        ]
        for (name, target, type, seed, initial, replacement, expected) in cases {
            var s = state(allLayers, [.init(key: name, target: target, type: type, seed: seed)],
                values: [name: initial])
            let admitted = s.activeConsumerTargets.contains(target)
            let accepted = s.apply(replacement, forPropertyKey: name)
            let layerID = name == "imageColor" ? 3 : 1
            let snapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: 1, generation: 1, definitions: s.program.definitions,
                userValues: s.userValues
            ).snapshot
            rows[name] = ["admitted": admitted, "accepted": accepted,
                "published": s.userValues[target] == expected,
                "revision": s.revision == 1,
                "hidden": !SceneLayerVisibility.visibleLayerIDs(
                    in: .init(layers: allLayers), snapshot: snapshot)
                    .contains(layerID)]
        }

        let sharedTargets = [SceneDynamicTarget.text(layerID: 1, field: .color),
            .text(layerID: 2, field: .color)]
        var shared = state(allLayers, sharedTargets.map {
            .init(key: "shared", target: $0, type: .vector3, seed: .vector3(1, 1, 1))
        }, values: ["shared": .string("1 1 1")])
        let sharedAccepted = shared.apply(.string("1 0 0"), forPropertyKey: "shared")
        rows["shared"] = ["accepted": sharedAccepted,
            "published": sharedTargets.allSatisfy { shared.userValues[$0] == .vector3(1, 0, 0) },
            "revision": shared.revision == 1]

        let rejected: [(String, SceneDynamicTarget, SceneDynamicValueType, SceneDynamicValue,
            SceneUserPropertyValue, SceneUserPropertyValue)] = [
            ("effectedImage", .layer(layerID: 4, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0 1 0")),
            ("missingStyle", .text(layerID: 5, field: .content), .string, .string("old"),
                .string("old"), .string("new")),
            ("missingContent", .text(layerID: 6, field: .content), .string, .string("old"),
                .string("old"), .string("new")),
            ("unlimitedWidth", .text(layerID: 7, field: .maxWidth), .scalar, .scalar(100),
                .number(100), .number(160)),
            ("unknownLayer", .layer(layerID: 8, field: .color), .vector3, .vector3(1, 1, 1),
                .string("1 1 1"), .string("0 1 0")),
        ]
        for (name, target, type, seed, initial, replacement) in rejected {
            var s = state(allLayers, [.init(key: name, target: target, type: type, seed: seed)],
                values: [name: initial])
            let before = s
            let accepted = s.apply(replacement, forPropertyKey: name)
            rows[name] = ["rejected": !accepted, "atomic": unchanged(s, before)]
        }
        var empty = state(allLayers, [], values: ["unused": .number(1)])
        let emptyBefore = empty
        rows["noConsumer"] = ["rejected": !empty.apply(.number(2), forPropertyKey: "unused"),
            "atomic": unchanged(empty, emptyBefore)]
        var missing = state(allLayers, [], values: [:])
        let missingBefore = missing
        rows["unknownKey"] = ["rejected": !missing.apply(.number(2), forPropertyKey: "missing"),
            "atomic": unchanged(missing, missingBefore)]
        let sharedBefore = shared
        let badSharedAccepted = shared.apply(.string("0.2 junk"), forPropertyKey: "shared")
        rows["invalidShared"] = ["rejected": !badSharedAccepted,
            "atomic": unchanged(shared, sharedBefore)]
        print(String(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneHiddenPropertyConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-hidden-property-")
        work = Path(cls.temp.name)
        source_path = Path(os.environ.get("MWX_HIDDEN_PROPERTY_HOST_SOURCE", HOST_SOURCE))
        source = source_path.read_text()
        host = method_body(source, "static func activeLiveConsumerTargets(")
        factory = method_body(source, "static func makeLivePropertyState(")
        modulation_marker = "static func imageLayerModulationConsumerTargets("
        modulation = method_body(source, modulation_marker) if modulation_marker in source else ""
        # Only adapts an added input parameter for an old-owner counterexample;
        # no admission rule is reproduced in the fixture.
        definitions_argument = ", propertyDefinitions: definitions" if "propertyDefinitions:" in factory else ""
        color = method_body(
            LAYER_SOURCE.read_text(), "nonisolated var supportsDirectLayerColorConsumer: Bool"
        )
        color += "\n" + method_body(
            LAYER_SOURCE.read_text(), "nonisolated var supportsUserPropertyLayerColorConsumer: Bool"
        )
        color += "\n" + method_body(
            LAYER_SOURCE.read_text(), "nonisolated var supportsUserPropertyImageSourceModulationConsumer: Bool"
        )
        harness = work / "Probe.swift"
        harness.write_text(STUBS.replace("__ACTIVE_CONSUMERS__", host)
            .replace("__IMAGE_MODULATION_CONSUMERS__", modulation)
            .replace("__MAKE_LIVE_STATE__", factory)
            .replace("__COLOR_ELIGIBILITY__", color)
            .replace("__SOURCE_CANDIDATES__", method_body(CATALOG_SOURCE.read_text(),
                "func sourceMaterialCandidateConsumerLayerIDs("))
            .replace("__SOURCE_MATERIAL_STORAGE__", method_body(SOURCE_MATERIAL_STORAGE_SOURCE.read_text(),
                "var sourceMaterials:"))
            .replace("__SOURCE_MATERIAL_CONSUMER__", method_body(SOURCE_MATERIAL_SOURCE.read_text(),
                "func sourceMaterialConsumer(")) + HARNESS.replace(
                    "__PROPERTY_DEFINITIONS_ARGUMENT__", definitions_argument))
        binary = work / "probe"
        compiled = subprocess.run(
            ["swiftc", "-enable-upcoming-feature", "MemberImportVisibility",
             *map(str, SWIFT_SOURCES), str(VISIBILITY_SOURCE),
             str(SCENE / "Resources/Assets/SceneModelResourceIdentity.swift"), str(harness),
             "-module-cache-path", str(work / "cache"), "-o", str(binary)],
            capture_output=True, text=True,
        )
        if compiled.returncode:
            cls.temp.cleanup()
            raise AssertionError(compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise AssertionError(result.stderr)
        cls.rows = json.loads(result.stdout)

    def test_defined_unbound_booleans_keep_revision_reset_and_runtime_guards(self) -> None:
        facts = self.rows["unboundBoolean"]
        self.assertTrue(facts)
        for name, accepted in facts.items():
            self.assertTrue(accepted, name)

    def test_clear_color_requires_the_real_clear_consumer_and_keeps_atomicity(self) -> None:
        facts = self.rows["clearColor"]
        self.assertTrue(facts)
        for name, passed in facts.items():
            self.assertTrue(passed, name)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_brightness_requires_the_same_ordinary_source_on_every_route(self) -> None:
        facts = self.rows["brightness"]
        self.assertTrue(facts)
        for name, accepted in facts.items():
            self.assertTrue(accepted, name)

    def test_hidden_text_fields_publish_and_remain_hidden(self) -> None:
        for case in ("content", "pointSize", "color", "maxWidth"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "admitted": True, "accepted": True, "published": True,
                    "revision": True, "hidden": True,
                })

    def test_hidden_effectless_image_color_is_live(self) -> None:
        self.assertEqual(self.rows["imageColor"], {
            "admitted": True, "accepted": True, "published": True,
            "revision": True, "hidden": True,
        })

    def test_effectful_color_requires_a_prepared_independent_layer_capture(self) -> None:
        self.assertEqual(self.rows["capturedImage"], {
            "potential": True, "admitted": True, "accepted": True, "published": True,
            "unchanged": False, "scriptUnchanged": True,
        })
        for case in ("missingClaim", "unresolvedClaim", "capturedMain", "transparentSource",
                     "internalDependency", "externalProvider", "aggregateProvider", "sourceTemplateCandidate"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "potential": True, "admitted": False, "accepted": False, "published": False,
                    "unchanged": True, "scriptUnchanged": True,
                })

    def test_source_templates_exclude_every_surface_and_normalized_shared_alias(self) -> None:
        self.assertTrue(all(self.rows["sourceCandidateProjection"].values()), self.rows)
        for case in ("coldTemplate", "sharedSourceAlias"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"accepted": False, "published": False, "unchanged": True})
        for case in ("failedSourceTemplate", "noSourceCandidate"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"accepted": True, "published": True, "unchanged": False})

    def test_puppet_model_and_dependency_do_not_gain_the_ordinary_image_route(self) -> None:
        for case in ("puppetImage", "modelImage", "dependentImage"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {
                    "potentialRejected": True, "rejected": True, "atomic": True,
                })

    def test_hidden_dependency_composition_requires_actual_preparation(self) -> None:
        self.assertEqual(self.rows["preparedComposition"], {
            "admitted": True, "accepted": True, "unchanged": False,
        })
        self.assertEqual(self.rows["unpreparedComposition"], {
            "admitted": False, "accepted": False, "unchanged": True,
        })

    def test_visible_and_hidden_shared_key_updates_every_consumer(self) -> None:
        self.assertEqual(self.rows["shared"], {
            "accepted": True, "published": True, "revision": True,
        })

    def test_unsupported_and_invalid_updates_are_atomic(self) -> None:
        for case in ("effectedImage", "missingStyle", "missingContent", "unlimitedWidth",
                     "unknownLayer", "noConsumer", "unknownKey", "invalidShared"):
            with self.subTest(case=case):
                self.assertEqual(self.rows[case], {"rejected": True, "atomic": True})


if __name__ == "__main__":
    unittest.main()
