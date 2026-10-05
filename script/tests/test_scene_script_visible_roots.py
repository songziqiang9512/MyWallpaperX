"""Typed/script visibility prepares supported trees without revealing them."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'

HARNESS = r'''
import Foundation
struct SceneLayerDisplayScriptOwnership {
    let visible: Bool
    let alpha: Bool
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}
struct SceneRenderDescriptor {
    struct Utility {
        enum Kind: String { case composition, fullscreen }
        let kind: Kind
        var copyBackground = true
        var passthrough = false
    }
    struct Effect { let visible: Bool }
    struct Layer {
        let id: Int
        var visible: Bool? = false
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var contentKind: String = "image"
        var utilityLayer: Utility? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var authoredDependencies: [Int] = []
        var effects: [Effect] = []
        var staticModelPath: String? = nil
        var particlePath: String? = nil
    }
    let layers: [Layer]
    var renderOrderLayerIDs: [Int] { layers.map(\.id) }
}
// Stored prepared-plan carriers only. The production DirectBool admission
// and utility source-route implementation consume these explicit sets.
struct SceneDependencyRenderPlan {
    struct Reference { let consumerLayerID: Int }
    var references: [Reference] = []
    var namedReferenceConsumerLayerIDs: Set<Int> = []
    var requiredEffectConsumerLayerIDs: Set<Int> = []
    var bindingsByConsumerLayerID: [Int: Int] = [:]
    var requiredProviderLayerIDs: Set<Int> = []
    var requiredGraphOutputProviderLayerIDs: Set<Int> = []
    var staticLayerSourcePassthroughBlockedLayerIDs: Set<Int> = []
}
@main enum Harness {
    static func target(_ id: Int) -> SceneDynamicTarget {
        .layer(layerID: id, field: .visibility)
    }
    static func ids(_ descriptor: SceneRenderDescriptor, candidates: Set<SceneDynamicTarget>,
                    scripts: Bool = false) -> [Int] {
        SceneDynamicLayerVisibilityRouteAdmission.targets(in: descriptor, candidates: candidates,
            hasScriptLayerAccess: scripts).compactMap {
            if case let .layer(id, .visibility) = $0 { return id }; return nil
        }.sorted()
    }
    static func negative(_ name: String) -> SceneRenderDescriptor {
        let layers: [SceneRenderDescriptor.Layer]
        switch name {
        case "duplicate": layers = [.init(id: 10), .init(id: 10)]
        case "cycle": layers = [.init(id: 10, parentID: 11, childLayerIDs: [11], contentKind: "container"),
                                 .init(id: 11, parentID: 10, childLayerIDs: [10], contentKind: "text")]
        case "missing-parent": layers = [.init(id: 10, parentID: 999, contentKind: "text")]
        case "missing-child": layers = [.init(id: 10, childLayerIDs: [999], contentKind: "container")]
        case "child-index-mismatch": layers = [.init(id: 10, contentKind: "container"),
                                               .init(id: 11, parentID: 10, contentKind: "text")]
        case "model", "particle", "utility":
            layers = [.init(id: 10, childLayerIDs: [11], contentKind: "container"),
                      .init(id: 11, parentID: 10,
                            contentKind: name == "utility" ? "composition" : name,
                            utilityLayer: name == "utility"
                                ? .init(kind: .composition, passthrough: true) : nil)]
        case "foreign-ancestor": layers = [.init(id: 10, parentID: 11, contentKind: "text"),
                                            .init(id: 11, childLayerIDs: [10], contentKind: "model")]
        default: fatalError("unknown owned fixture")
        }
        return .init(layers: layers)
    }
    static func composition(_ violation: String? = nil) -> SceneRenderDescriptor {
        var ancestor = SceneRenderDescriptor.Layer(
            id: 90, visible: true, childLayerIDs: [100], contentKind: "container")
        var root = SceneRenderDescriptor.Layer(
            id: 100, parentID: 90, childLayerIDs: [110, 120], contentKind: "composition",
            utilityLayer: .init(kind: .composition, copyBackground: false))
        var inner = SceneRenderDescriptor.Layer(
            id: 110, visible: true, parentID: 100, childLayerIDs: [111, 112],
            contentKind: "composition", utilityLayer: .init(kind: .composition),
            effects: [.init(visible: false)])
        var image = SceneRenderDescriptor.Layer(id: 111, visible: true, parentID: 110)
        let text = SceneRenderDescriptor.Layer(id: 112, parentID: 110, contentKind: "text")
        let solid = SceneRenderDescriptor.Layer(id: 120, visible: true, parentID: 100,
                                               contentKind: "solid")
        let peer = SceneRenderDescriptor.Layer(id: 130, visible: true, contentKind: "solid")
        switch violation {
        case "passthrough": root.utilityLayer?.passthrough = true
        case "dependency": root.dependencyLayerIDs = [130]
        case "authored-dependency": root.authoredDependencies = [130]
        case "inner-dependency": inner.dependencyLayerIDs = [130]
        case "inner-authored-dependency": inner.authoredDependencies = [130]
        case "inner-passthrough": inner.utilityLayer?.passthrough = true
        case "inner-kind": inner.contentKind = "fullscreen"
        case "particle", "model", "container": image.contentKind = violation!
        case "fullscreen":
            image.contentKind = "fullscreen"
            image.utilityLayer = .init(kind: .fullscreen)
        case "missing-parent": ancestor.childLayerIDs = []; root.parentID = 999
        case "child-index": inner.childLayerIDs = [111]
        case nil: break
        default: fatalError("unknown owned composition fixture")
        }
        return .init(layers: [ancestor, root, inner, image, text, solid, peer])
    }
    static func particleTree(_ violation: String? = nil) -> SceneRenderDescriptor {
        var root = SceneRenderDescriptor.Layer(id: 200, childLayerIDs: [201, 204],
                                               contentKind: "container")
        var inner = SceneRenderDescriptor.Layer(id: 201, visible: true, parentID: 200,
                                                childLayerIDs: [202, 203], contentKind: "container")
        var first = SceneRenderDescriptor.Layer(id: 202, visible: true, parentID: 201,
                                                contentKind: "particle", particlePath: "owned.json")
        let second = SceneRenderDescriptor.Layer(id: 203, parentID: 201,
                                                 contentKind: "particle", particlePath: "owned.json")
        let solid = SceneRenderDescriptor.Layer(id: 204, visible: true, parentID: 200,
                                                contentKind: "solid")
        let peer = SceneRenderDescriptor.Layer(id: 205, visible: true, contentKind: "solid")
        var extras: [SceneRenderDescriptor.Layer] = []
        switch violation {
        case "missing-path": first.particlePath = nil
        case "effect": first.effects = [.init(visible: false)]
        case "particle-child":
            first.childLayerIDs = [206]; extras = [.init(id: 206, parentID: 202)]
        case "unlisted-child": extras = [.init(id: 206, parentID: 202)]
        case "composition":
            root.contentKind = "composition"
            root.utilityLayer = .init(kind: .composition, copyBackground: false)
        case "nested-composition":
            inner.contentKind = "composition"
            inner.utilityLayer = .init(kind: .composition, copyBackground: false)
        case "model-ancestor": root.contentKind = "model"
        case "missing-parent": first.parentID = 999
        case "child-index": inner.childLayerIDs = [202]
        case "cycle": root.parentID = 202; first.childLayerIDs = [200]
        case "duplicate": extras = [first]
        case nil: break
        default: fatalError("unknown owned particle fixture")
        }
        return .init(layers: [root, inner, first, second, solid, peer] + extras)
    }
    static func particleRequirements(_ descriptor: SceneRenderDescriptor,
                                     candidates: Set<SceneDynamicTarget>) -> [String: [Int]] {
#if PARTICLE_REQUIREMENTS_API
        return Dictionary(uniqueKeysWithValues:
            SceneDynamicLayerVisibilityRouteAdmission.particleRequirements(
                in: descriptor, candidates: candidates).map { (String($0.key), $0.value.sorted()) })
#else
        // The pre-fix API has no stored relation. Run the same inputs without
        // inventing a replacement algorithm for that baseline.
        return [:]
#endif
    }
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            let name = CommandLine.arguments[1]
            let isComposition = name.hasPrefix("composition-")
            let descriptor = isComposition
                ? composition(String(name.dropFirst("composition-".count))) : negative(name)
            let candidates: Set<SceneDynamicTarget> = isComposition
                ? [target(100), target(110), target(111), target(130)] : [target(10)]
            let targets = ids(descriptor, candidates: candidates)
            var output: [String: Any] = ["targets": targets]
#if PREPARATION_API
            output["preparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
                in: descriptor, candidates: [isComposition ? target(100) : target(10)]).sorted()
#endif
            print(String(data: try JSONSerialization.data(withJSONObject: output), encoding: .utf8)!)
            return
        }
        let d = SceneRenderDescriptor(layers: [
            .init(id: 1), .init(id: 2, visible: true),
            .init(id: 3, contentKind: "composition", utilityLayer: .init(kind: .composition)),
            .init(id: 4, visible: true, contentKind: "composition", utilityLayer: .init(kind: .composition)),
            .init(id: 5, parentID: 6), .init(id: 6, childLayerIDs: [5]),
            .init(id: 7, contentKind: "text"), .init(id: 8, contentKind: "solid"),
            .init(id: 9, contentKind: "particle")
        ])
        let leaf = target(1)
        let definition = SceneDynamicTargetDefinition(target: leaf, valueType: .bool, authoredValue: .bool(false))
        let shown = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1, definitions: [definition], sceneScriptValues: [leaf: .bool(true)]).snapshot
        let hidden = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 2, definitions: [definition], sceneScriptValues: [leaf: .bool(false)]).snapshot
        let nested = SceneRenderDescriptor(layers: [
            .init(id: 10, childLayerIDs: [11, 14], contentKind: "container"),
            .init(id: 11, visible: true, parentID: 10, childLayerIDs: [12, 13], contentKind: "container"),
            .init(id: 12, visible: true, parentID: 11, contentKind: "text"),
            .init(id: 13, parentID: 11, contentKind: "image"),
            .init(id: 14, visible: true, parentID: 10, contentKind: "solid"),
            .init(id: 20, visible: true, contentKind: "solid")])
        let parentDefinition = SceneDynamicTargetDefinition(target: target(10), valueType: .bool,
                                                            authoredValue: .bool(false))
        func visible(_ value: Bool) -> [Int] {
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: [parentDefinition], userValues: [target(10): .bool(value)]).snapshot
            return SceneLayerVisibility.visibleLayerIDs(in: nested, snapshot: snapshot).sorted()
        }
        var output: [String: Any] = [
            "scriptRoots": ids(d, candidates: [], scripts: true),
            "noScripts": ids(d, candidates: []),
            "typedOwner": ids(d, candidates: [leaf]),
            "authoredHidden": !SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: .empty(frameIndex: 0)).contains(1),
            "shown": SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: shown).contains(1),
            "hiddenAgain": !SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: hidden).contains(1),
            "nestedTargets": ids(nested, candidates: [target(10), target(12)]),
            "nestedInitiallyHidden": visible(false), "nestedShown": visible(true),
            "nestedHiddenAgain": visible(false), "nestedShownAgain": visible(true)
        ]
#if PREPARATION_API
        output["nestedPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: nested, candidates: [target(10)]).sorted()
        output["leafPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: nested, candidates: [target(12)]).sorted()
        let effectDescriptor = SceneRenderDescriptor(layers: [
            .init(id: 31, parentID: 32, effects: [.init(visible: false)]),
            .init(id: 32, childLayerIDs: [31], contentKind: "container"),
            .init(id: 40, visible: true, contentKind: "fullscreen", utilityLayer: .init(kind: .fullscreen),
                  effects: [.init(visible: false)]),
            .init(id: 41, visible: true, parentID: 42, contentKind: "fullscreen", utilityLayer: .init(kind: .fullscreen),
                  effects: [.init(visible: false)]),
            .init(id: 42, visible: true, childLayerIDs: [41], contentKind: "container")])
        let childEffect = SceneDynamicTarget.effectVisibility(layerID: 31, effectIndex: 0)
        let rootFullscreen = SceneDynamicTarget.effectVisibility(layerID: 40, effectIndex: 0)
        let childFullscreen = SceneDynamicTarget.effectVisibility(layerID: 41, effectIndex: 0)
        let allEffects: Set<SceneDynamicTarget> = [childEffect, rootFullscreen, childFullscreen]
        func dormant(_ plan: SceneDependencyRenderPlan) -> Set<SceneDynamicTarget> {
            SceneDirectBoolEffectVisibilityRouteAdmission.startupInactiveTargets(
                in: effectDescriptor, candidates: allEffects, visibleLayerIDs: [31, 40, 41],
                dependencyPlan: plan)
        }
        let dormantTargets = dormant(.init())
        output["childInactiveEffectAdmitted"] = dormantTargets.contains(childEffect)
        output["rootInactiveFullscreenAdmitted"] = dormantTargets.contains(rootFullscreen)
        output["childInactiveFullscreenRejected"] = !dormantTargets.contains(childFullscreen)
        output["childProviderEffectRejected"] = !dormant(.init(requiredProviderLayerIDs: [31])).contains(childEffect)
        output["childDependencyEffectRejected"] = !dormant(.init(requiredEffectConsumerLayerIDs: [31])).contains(childEffect)
#endif
        func modelTargets(_ layers: [SceneRenderDescriptor.Layer], prepared: Set<Int> = [81],
                          candidate: Int = 81) -> [Int] {
            let descriptor = SceneRenderDescriptor(layers: layers)
#if MODEL_VISIBILITY_API
            let targets = SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor, candidates: [target(candidate)], preparedStaticModelLayerIDs: prepared)
#else
            let targets = SceneDynamicLayerVisibilityRouteAdmission.targets(
                in: descriptor, candidates: [target(candidate)])
#endif
            return targets.compactMap { if case let .layer(id, .visibility) = $0 { return id }; return nil }.sorted()
        }
        let modelParent = SceneRenderDescriptor.Layer(id: 80, childLayerIDs: [81], contentKind: "container")
        let modelLeaf = SceneRenderDescriptor.Layer(id: 81, parentID: 80, contentKind: "model", staticModelPath: "owned.mdl")
        output["modelPrepared"] = modelTargets([modelParent, modelLeaf])
        output["modelUnprepared"] = modelTargets([modelParent, modelLeaf], prepared: [])
        output["modelParentNotExpanded"] = modelTargets([modelParent, modelLeaf], candidate: 80)
        var invalidModels: [String: [Int]] = [:]
        for kind in ["missing-path", "effect", "utility", "child", "missing-parent", "bad-parent-index", "model-parent", "cycle", "duplicate"] {
            var leaf = modelLeaf, parent = modelParent
            var extras: [SceneRenderDescriptor.Layer] = []
            switch kind {
            case "missing-path": leaf.staticModelPath = nil
            case "effect": leaf.effects = [.init(visible: false)]
            case "utility": leaf.utilityLayer = .init(kind: .composition)
            case "child": leaf.childLayerIDs = [82]; extras = [.init(id: 82, parentID: 81)]
            case "missing-parent": leaf.parentID = 999
            case "bad-parent-index": parent.childLayerIDs = []
            case "model-parent": parent.contentKind = "model"
            case "cycle": parent.parentID = 81; leaf.childLayerIDs = [80]
            default: extras = [leaf]
            }
            invalidModels[kind] = modelTargets([parent, leaf] + extras)
        }
        output["invalidModels"] = invalidModels
        let particles = particleTree()
        let particleCandidates: Set<SceneDynamicTarget> = [target(200), target(201),
            target(202), target(203), target(204), target(205)]
        output["particleTreeTargets"] = ids(particles, candidates: particleCandidates)
        output["scriptParticleTreeTargets"] = ids(particles, candidates: [], scripts: true)
        output["particleRequirements"] = particleRequirements(particles, candidates: particleCandidates)
        output["particleParentOnlyRequirements"] = particleRequirements(particles, candidates: [target(200)])
        output["particleLeafOnlyRequirements"] = particleRequirements(particles, candidates: [target(202)])
#if PREPARATION_API
        output["particleTreePreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: particles, candidates: [target(200)]).sorted()
        output["particleLeafPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: particles, candidates: [target(202)]).sorted()
#endif
        let particleParentDefinition = SceneDynamicTargetDefinition(
            target: target(200), valueType: .bool, authoredValue: .bool(false))
        func particleVisible(_ value: Bool) -> [Int] {
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: [particleParentDefinition], userValues: [target(200): .bool(value)]).snapshot
            return SceneLayerVisibility.visibleLayerIDs(in: particles, snapshot: snapshot).sorted()
        }
        output["particleParentHidden"] = particleVisible(false)
        output["particleParentShown"] = particleVisible(true)
        let rootParticleEffect = SceneRenderDescriptor(layers: [
            .init(id: 210, contentKind: "particle", effects: [.init(visible: false)],
                  particlePath: "owned-root.json"),
            .init(id: 211, visible: true, contentKind: "solid")])
        output["rootParticleEffectTargets"] = ids(rootParticleEffect,
            candidates: [target(210), target(211)])
        output["rootParticleEffectRequirements"] = particleRequirements(rootParticleEffect,
            candidates: [target(210), target(211)])
#if PREPARATION_API
        output["rootParticleEffectPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: rootParticleEffect, candidates: [target(210)]).sorted()
#endif
        var invalidParticles: [String: [String: Any]] = [:]
        for violation in ["missing-path", "effect", "particle-child", "unlisted-child", "composition",
                          "nested-composition", "model-ancestor", "missing-parent", "child-index", "cycle", "duplicate"] {
            let descriptor = particleTree(violation)
            let candidates: Set<SceneDynamicTarget> = [target(200), target(202), target(205)]
            var result: [String: Any] = ["targets": ids(descriptor, candidates: candidates),
                "requirements": particleRequirements(descriptor, candidates: candidates)]
#if PREPARATION_API
            result["preparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
                in: descriptor, candidates: [target(200), target(202)]).sorted()
#endif
            invalidParticles[violation] = result
        }
        output["invalidParticles"] = invalidParticles
        let groups = composition()
        let groupTargets: Set<SceneDynamicTarget> = [target(90), target(100), target(110),
                                                    target(111), target(112), target(120)]
        output["compositionTargets"] = ids(groups, candidates: groupTargets)
        output["scriptCompositionTargets"] = ids(groups, candidates: [], scripts: true)
        let groupDefinition = SceneDynamicTargetDefinition(
            target: target(100), valueType: .bool, authoredValue: .bool(false))
        func groupVisible(_ value: Bool, frame: UInt64) -> [Int] {
            let snapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: frame, generation: 1, definitions: [groupDefinition],
                userValues: [target(100): .bool(value)]).snapshot
            return SceneLayerVisibility.visibleLayerIDs(in: groups, snapshot: snapshot).sorted()
        }
        output["compositionHidden"] = groupVisible(false, frame: 0)
        output["compositionShown"] = groupVisible(true, frame: 1)
        output["compositionHiddenAgain"] = groupVisible(false, frame: 2)
        output["compositionShownAgain"] = groupVisible(true, frame: 3)
#if PREPARATION_API
        output["compositionPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: groups, candidates: [target(100)]).sorted()
        output["compositionAncestorPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: groups, candidates: [target(90)]).sorted()
        output["compositionLeafPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: groups, candidates: [target(111)]).sorted()
#endif
        let initiallyVisibleGroup = SceneRenderDescriptor(layers: [
            .init(id: 140, visible: true, childLayerIDs: [141, 142], contentKind: "composition",
                  utilityLayer: .init(kind: .composition)),
            .init(id: 141, visible: true, parentID: 140),
            .init(id: 142, parentID: 140, contentKind: "text")])
        output["compositionBackgroundTargets"] = ids(
            initiallyVisibleGroup, candidates: [target(140), target(141), target(142)])
        let hiddenBackground = SceneRenderDescriptor(layers: [
            .init(id: 150, contentKind: "composition", utilityLayer: .init(kind: .composition),
                  effects: [.init(visible: true)]),
            .init(id: 151, visible: true, contentKind: "solid")])
        let clockShape = SceneRenderDescriptor(layers: [
            .init(id: 160, childLayerIDs: [161, 162], contentKind: "composition",
                  utilityLayer: .init(kind: .composition)),
            .init(id: 161, visible: true, parentID: 160, contentKind: "text"),
            .init(id: 162, visible: true, parentID: 160, contentKind: "composition",
                  utilityLayer: .init(kind: .composition),
                  effects: [.init(visible: true), .init(visible: true)])])
        output["hiddenBackgroundTargets"] = ids(hiddenBackground, candidates: [target(150)])
        output["clockBackgroundTargets"] = ids(clockShape,
            candidates: [target(160), target(161), target(162)])
        let clockSource = try SceneUtilityLayerSourceRoute.resolve(
            layer: clockShape.layers[2], descriptor: clockShape).get()
        output["clockChildSourceUsesEnclosingBackground"] = !clockSource.usesIsolatedGroupTarget
            && !clockSource.capturesCompositionSubtree && clockSource.triggerLayerID == 162
        func dependencyComposition(_ violation: String? = nil) -> SceneRenderDescriptor {
            var owner = SceneRenderDescriptor.Layer(
                id: 420, dependencyLayerIDs: [410], contentKind: "composition",
                utilityLayer: .init(kind: .composition), effects: [.init(visible: true)])
            var extras: [SceneRenderDescriptor.Layer] = []
            switch violation {
            case "source": owner.contentKind = "fullscreen"
            case "utility": owner.utilityLayer = .init(kind: .fullscreen)
            case "parent": owner.parentID = 410
            case "child":
                owner.childLayerIDs = [421]
                extras = [.init(id: 421, parentID: 420)]
            case "unlisted-child": extras = [.init(id: 421, parentID: 420)]
            case "duplicate": extras = [owner]
            case nil: break
            default: fatalError("unknown dependency composition fixture")
            }
            return .init(layers: [
                .init(id: 410, contentKind: "solid", effects: [.init(visible: true)]),
                owner, .init(id: 430, visible: true, contentKind: "text")
            ] + extras)
        }
        let dependencyGroup = dependencyComposition()
        output["dependencyCompositionTargets"] = ids(dependencyGroup, candidates: [target(420)])
        output["dependencyCompositionNoOwner"] = ids(dependencyGroup, candidates: [])
        let dependencySource = try SceneUtilityLayerSourceRoute.resolve(
            layer: dependencyGroup.layers[1], descriptor: dependencyGroup).get()
        output["dependencyCompositionSourceCapturesSubtree"] = dependencySource.capturesCompositionSubtree
        var invalidDependencyGroups: [String: [Int]] = [:]
        for violation in ["source", "utility", "parent", "child", "unlisted-child", "duplicate"] {
            invalidDependencyGroups[violation] = ids(
                dependencyComposition(violation), candidates: [target(420)])
        }
        output["invalidDependencyCompositionTargets"] = invalidDependencyGroups
        func backgroundVisible(_ descriptor: SceneRenderDescriptor, owner: Int, value: Bool) -> [Int] {
            let definition = SceneDynamicTargetDefinition(target: target(owner),
                valueType: .bool, authoredValue: .bool(false))
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: [definition], userValues: [target(owner): .bool(value)]).snapshot
            return SceneLayerVisibility.visibleLayerIDs(in: descriptor, snapshot: snapshot).sorted()
        }
        output["hiddenBackgroundFalse"] = backgroundVisible(hiddenBackground, owner: 150, value: false)
        output["hiddenBackgroundTrue"] = backgroundVisible(hiddenBackground, owner: 150, value: true)
        output["clockBackgroundFalse"] = backgroundVisible(clockShape, owner: 160, value: false)
        output["clockBackgroundTrue"] = backgroundVisible(clockShape, owner: 160, value: true)
        output["dependencyCompositionFalse"] = backgroundVisible(dependencyGroup, owner: 420, value: false)
        output["dependencyCompositionTrue"] = backgroundVisible(dependencyGroup, owner: 420, value: true)
        output["dependencyCompositionFalseAgain"] = backgroundVisible(dependencyGroup, owner: 420, value: false)
#if PREPARATION_API
        output["hiddenBackgroundPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: hiddenBackground, candidates: [target(150)]).sorted()
        output["clockBackgroundPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: clockShape, candidates: [target(160)]).sorted()
        output["dependencyCompositionPreparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
            in: dependencyGroup, candidates: [target(420)]).sorted()
#endif
        print(String(data: try JSONSerialization.data(withJSONObject: output), encoding: .utf8)!)
    }
}
'''

class ScriptVisibleRootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Compile the production declaration, separated from the unrelated
        # graph compiler in the same file; no copied admission algorithm.
        source_path = Path(os.environ.get('MWX_SCENE_VISIBILITY_ADMISSION_SOURCE', str(
            SCENE / 'Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift')))
        source = source_path.read_text()
        start = source.index('nonisolated enum SceneDynamicLayerVisibilityRouteAdmission {')
        end = source.index('/// Raw-graph conservation', start)
        cls.directory = tempfile.TemporaryDirectory(prefix='mwx-visible-root-test-')
        try:
            root = Path(cls.directory.name)
            admission = root / 'Admission.swift'
            admission.write_text('import Foundation\n' + source[start:end])
            direct = root / 'DirectBool.swift'
            direct_source = (SCENE / 'Compilation/Material/SceneDirectBoolEffectVisibilityRouteAdmission.swift').read_text()
            # Link the actual prepared-plan overload and private implementation.
            # Its launch-plan builder is covered by the graph owner gates.
            first = direct_source.index('    static func startupInactiveTargets(')
            second = direct_source.index('    static func startupInactiveTargets(', first + 1)
            direct.write_text('import Foundation\nnonisolated enum SceneDirectBoolEffectVisibilityRouteAdmission {\n'
                              + direct_source[second:])
            harness = root / 'Harness.swift'
            harness.write_text(HARNESS)
            cls.binary = root / 'run'
            # The explicit baseline mode links the old API and runs the same
            # target inputs. Only the added preparation API is excluded.
            flags = [] if os.environ.get('MWX_SCENE_VISIBILITY_PREPARATION_API') == '0' else ['-D', 'PREPARATION_API']
            extra_sources = [str(direct)] if flags else []
            if os.environ.get('MWX_SCENE_MODEL_VISIBILITY_API') != '0':
                flags += ['-D', 'MODEL_VISIBILITY_API']
            if 'static func particleRequirements(' in source[start:end]:
                flags += ['-D', 'PARTICLE_REQUIREMENTS_API']
            built = subprocess.run(['swiftc', *flags, str(SCENE / 'Systems/Properties/SceneDynamicSnapshot.swift'),
                str(SCENE / 'Rendering/Geometry/SceneLayerVisibility.swift'),
                str(SCENE / 'Rendering/Composition/SceneUtilityLayerSourceRoute.swift'),
                str(admission), *extra_sources, str(harness), '-module-cache-path',
                str(root / 'module-cache'), '-o', str(cls.binary)], capture_output=True, text=True, timeout=120)
            if built.returncode:
                raise AssertionError(built.stdout + built.stderr)
            cls.result = json.loads(subprocess.check_output([str(cls.binary)], text=True))
        except BaseException:
            cls.directory.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_arbitrary_script_layer_lookup_prepares_supported_roots(self):
        self.assertEqual(self.result['scriptRoots'], [1, 2, 3, 4, 5, 6, 7, 8])

    def test_no_script_keeps_only_explicit_typed_candidates(self):
        self.assertEqual(self.result['noScripts'], [])
        self.assertEqual(self.result['typedOwner'], [1])

    def test_preparation_does_not_force_visibility_or_prevent_hiding(self):
        for key in ['authoredHidden', 'shown', 'hiddenAgain']:
            self.assertTrue(self.result[key], key)

    def test_ordinary_parent_and_parented_leaf_are_typed_candidates(self):
        self.assertEqual(self.result['nestedTargets'], [10, 12])

    def test_preparation_includes_the_complete_hidden_subtree(self):
        self.assertEqual(self.result['nestedPreparation'], [10, 11, 12, 13, 14])
        self.assertEqual(self.result['leafPreparation'], [12])

    def test_parent_cycles_preserve_the_childs_own_false_and_healthy_peer(self):
        self.assertEqual(self.result['nestedInitiallyHidden'], [20])
        self.assertEqual(self.result['nestedShown'], [10, 11, 12, 14, 20])
        self.assertEqual(self.result['nestedHiddenAgain'], [20])
        self.assertEqual(self.result['nestedShownAgain'], [10, 11, 12, 14, 20])

    def test_invalid_or_unsupported_hierarchies_reject_without_trapping(self):
        for name in ('duplicate', 'cycle', 'missing-parent', 'missing-child',
                     'child-index-mismatch', 'model', 'particle', 'utility', 'foreign-ancestor'):
            with self.subTest(case=name):
                run = subprocess.run([str(self.binary), name], capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stderr[-3000:])
                result = json.loads(run.stdout)
                self.assertEqual(result['targets'], [])
                self.assertEqual(result['preparation'], [])

    def test_inactive_effect_admission_keeps_fullscreen_standalone_and_dependency_guards(self):
        for key in ('childInactiveEffectAdmitted', 'rootInactiveFullscreenAdmitted',
                    'childInactiveFullscreenRejected', 'childProviderEffectRejected', 'childDependencyEffectRejected'):
            self.assertTrue(self.result[key], key)

    def test_prepared_model_leaf_uses_actual_resources_without_opening_parent_or_effect_routes(self):
        self.assertEqual(self.result['modelPrepared'], [81])
        self.assertEqual(self.result['modelUnprepared'], [])
        self.assertEqual(self.result['modelParentNotExpanded'], [])
        for name, targets in self.result['invalidModels'].items():
            with self.subTest(case=name):
                self.assertEqual(targets, [])

    def test_ordinary_parent_and_particle_leaves_are_typed_and_script_candidates(self):
        self.assertEqual(self.result['particleTreeTargets'], [200, 201, 202, 203, 204, 205])
        self.assertEqual(self.result['scriptParticleTreeTargets'], [200, 201, 202, 203, 204, 205])
        self.assertEqual(self.result['particleTreePreparation'], [200, 201, 202, 203, 204])
        self.assertEqual(self.result['particleLeafPreparation'], [202])

    def test_particle_requirements_belong_to_each_exact_visibility_target(self):
        self.assertEqual(self.result['particleRequirements'],
                         {'200': [202, 203], '201': [202, 203], '202': [202], '203': [203]})
        self.assertEqual(self.result['particleParentOnlyRequirements'], {'200': [202, 203]})
        self.assertEqual(self.result['particleLeafOnlyRequirements'], {'202': [202]})

    def test_particle_parent_show_keeps_the_childs_own_false_and_independent_peer(self):
        self.assertEqual(self.result['particleParentHidden'], [205])
        self.assertEqual(self.result['particleParentShown'], [200, 201, 202, 204, 205])

    def test_independent_particle_root_keeps_its_existing_inactive_effect_route(self):
        self.assertEqual(self.result['rootParticleEffectTargets'], [210, 211])
        self.assertEqual(self.result['rootParticleEffectPreparation'], [210])
        self.assertEqual(self.result['rootParticleEffectRequirements'], {'210': [210]})

    def test_invalid_particle_leaf_or_composition_rejects_without_blocking_peer(self):
        for name, result in self.result['invalidParticles'].items():
            with self.subTest(case=name):
                self.assertEqual(result['targets'], [205])
                self.assertEqual(result['preparation'], [])
                self.assertEqual(result['requirements'], {})

    def test_isolated_composition_parents_and_descendants_share_visibility_admission(self):
        self.assertEqual(self.result['compositionTargets'], [90, 100, 110, 111, 112, 120])
        self.assertEqual(self.result['scriptCompositionTargets'], [90, 100, 110, 111, 112, 120, 130])
        self.assertEqual(self.result['compositionBackgroundTargets'], [140, 141, 142])

    def test_composition_preparation_contains_hidden_descendants_without_revealing_them(self):
        self.assertEqual(self.result['compositionPreparation'], [100, 110, 111, 112, 120])
        self.assertEqual(self.result['compositionAncestorPreparation'], [90, 100, 110, 111, 112, 120])
        self.assertEqual(self.result['compositionLeafPreparation'], [111])
        self.assertEqual(self.result['compositionHidden'], [90, 130])

    def test_composition_visibility_cycles_keep_child_false_and_independent_peer(self):
        self.assertEqual(self.result['compositionShown'], [90, 100, 110, 111, 120, 130])
        self.assertEqual(self.result['compositionHiddenAgain'], [90, 130])
        self.assertEqual(self.result['compositionShownAgain'], [90, 100, 110, 111, 120, 130])

    def test_hidden_childless_background_capture_prepares_without_revealing(self):
        self.assertEqual(self.result['hiddenBackgroundTargets'], [150])
        self.assertEqual(self.result['hiddenBackgroundPreparation'], [150])
        self.assertEqual(self.result['hiddenBackgroundFalse'], [151])
        self.assertEqual(self.result['hiddenBackgroundTrue'], [150, 151])

    def test_nested_childless_background_capture_keeps_parent_visibility_authority(self):
        self.assertEqual(self.result['clockBackgroundTargets'], [160, 161, 162])
        self.assertEqual(self.result['clockBackgroundPreparation'], [160, 161, 162])
        self.assertTrue(self.result['clockChildSourceUsesEnclosingBackground'])
        self.assertEqual(self.result['clockBackgroundFalse'], [])
        self.assertEqual(self.result['clockBackgroundTrue'], [160, 161, 162])

    def test_hidden_dependency_composition_prepares_its_future_visibility_owner(self):
        self.assertEqual(self.result['dependencyCompositionTargets'], [420])
        self.assertEqual(self.result['dependencyCompositionPreparation'], [420])
        self.assertEqual(self.result['dependencyCompositionNoOwner'], [])
        self.assertFalse(self.result['dependencyCompositionSourceCapturesSubtree'])
        self.assertEqual(self.result['dependencyCompositionFalse'], [430])
        self.assertEqual(self.result['dependencyCompositionTrue'], [420, 430])
        self.assertEqual(self.result['dependencyCompositionFalseAgain'], [430])

    def test_dependency_composition_keeps_source_and_hierarchy_boundaries(self):
        for name, targets in self.result['invalidDependencyCompositionTargets'].items():
            with self.subTest(case=name):
                self.assertEqual(targets, [])

    def test_unsupported_composition_subtrees_reject_locally(self):
        for name in ('passthrough', 'dependency', 'authored-dependency', 'inner-dependency',
                     'inner-authored-dependency', 'inner-passthrough', 'inner-kind',
                     'particle', 'model', 'container', 'fullscreen', 'missing-parent', 'child-index'):
            with self.subTest(case=name):
                run = subprocess.run([str(self.binary), 'composition-' + name],
                                     capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stderr[-3000:])
                result = json.loads(run.stdout)
                self.assertEqual(result['targets'], [130])
                self.assertEqual(result['preparation'], [])
