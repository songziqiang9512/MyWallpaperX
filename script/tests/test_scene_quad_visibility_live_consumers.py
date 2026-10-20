"""Independent quad visibility uses prepared claims and atomic property cohorts.

Host, structural admission, token identity and LiveState code are production
implementations. Descriptor and prepared-material dictionaries are input
carriers; this gate does not compile shaders, allocate surfaces or prove GPU output.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .test_scene_property_live_routing import method_body
from .test_scene_property_live_update_state import SWIFT_SOURCES

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HOST = SCENE / "Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"
ADMISSION = SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift"
CATALOG = SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"

CARRIERS = r'''
import Foundation
struct SceneLayerDisplayScriptOwnership {
    var visible = false; var alpha = false
    var isEmpty: Bool { !visible && !alpha }
    var fields: [String] { [] }
}
struct SceneRenderDescriptor {
    struct Camera {
        struct Bloom { struct HDR {}; var hdr: HDR? = nil }
        var authoredOrthographicProjectionActive: Bool? = nil
        var orthoWidth: Float? = 512; var orthoHeight: Float? = 512
        var default2DInputLayerID: Int? = nil
        var bloom = Bloom(); var clearEnabled = true
    }
    struct TextStyle { var limitWidth = false }
    struct AnimationLayer { var id: Int?; var visibilityBinding: String? }
    struct Layer {
        var id: Int
        var contentKind: String
        var visible: Bool? = true
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var dependencyLayerIDs: [Int] = []
        var authoredDependencies: [Int] = []
        var utilityLayer: SceneUtilityLayer? = nil
        var effects: [Int] = []
        var staticModelPath: String? = nil
        var particlePath: String? = nil
        var puppetMeshPath: String? = nil
        var usesPerspective: Bool? = nil
        var text: String? = nil
        var textStyle: TextStyle? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
        var puppetAnimationLayers: [AnimationLayer] = []
        __COLOR_CONTRACTS__
    }
    var layers: [Layer]
    var camera = Camera()
    var preparedUtilityPlans: [Int: SceneUtilityLayerRuntimePlanner.Plan] = [:]
    var renderOrderLayerIDs: [Int] { layers.map(\.id) }
}
// Inputs are explicit prepared outcomes. Actual claim/resolve methods below
// retain the product's immutable owner/capability/layer identity checks.
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    enum SourceRoute { case capturedLayerTexture, capturedMainTargetTexture, transparentDirectDraw }
    enum DependencyOwnership { case none, graphInternal, externalPrimary, externalAggregate }
    struct LayerCapability {
        fileprivate let capabilityID = UUID()
        var sourceRoute: SourceRoute = .transparentDirectDraw
        var dependencyOwnership: DependencyOwnership = .none
        var materials: [Int: Int] = [0: 1]
    }
    __TOKEN_TYPES__
    private let ownerID = UUID()
    private let capabilitiesByLayerID: [Int: LayerCapability]
    let admittedResolvedMaterialReferences: [Int] = []
    let liveConsumerTargets: Set<SceneDynamicTarget> = []
    init(_ values: [Int: LayerCapability] = [:]) { capabilitiesByLayerID = values }
    __CLAIM__
    __RESOLVE__
    __EXECUTION_IDS__
}
enum SceneUtilityLayerRuntimePlanner {
    struct Plan {
        enum Kind { case fullscreen }
        var kind: Kind = .fullscreen
        var shouldCapture = true
        var requiresNamedTarget = false
    }
    static func plans(in descriptor: SceneRenderDescriptor, resolvedMaterialLayerIDs: Set<Int>,
                      admittedResolvedMaterialReferences: [Int]) -> [Int: Plan] {
        descriptor.preparedUtilityPlans
    }
}
enum SceneLightSnapshot {
    static func liveConsumerTargets(descriptor: SceneRenderDescriptor) -> Set<SceneDynamicTarget> { [] }
}
enum SceneDependencyGraphAnalysis {
    struct Reference { let providerLayerID: Int }
    static func references(in layers: [SceneRenderDescriptor.Layer]) -> [Reference] { [] }
}
struct SceneSoundPlaybackProgram { var liveConsumerTargets: Set<SceneDynamicTarget> = [] }
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
    let renderDescriptor: SceneRenderDescriptor
    let propertyBindingProgram: ScenePropertyBindingProgram
    let effectivePropertyValues: [String: SceneUserPropertyValue]
}
enum SceneDesktopWallpaperHost {
    __IMAGE_MODULATION__
    __ACTIVE_CONSUMERS__
    __MAKE_STATE__
}
'''

HARNESS = r'''
@main enum Probe {
    typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
    static func target(_ id: Int) -> SceneDynamicTarget { .layer(layerID: id, field: .visibility) }
    static func program(_ key: String, _ ids: [Int], _ seed: Bool) -> ScenePropertyBindingProgram {
        .init(definitions: ids.map { .init(target: target($0), valueType: .bool, authoredValue: .bool(seed)) },
            instructions: ids.map { .init(propertyKey: key, path: .init(components: [.key(key)]),
                target: target($0), valueType: .bool) })
    }
    static func state(_ descriptor: SceneRenderDescriptor, _ catalog: Catalog,
                      key: String, ids: [Int], seed: Bool = true,
                      models: Set<Int> = [], particles: Set<Int> = []) -> ScenePropertyLiveUpdateState {
        SceneDesktopWallpaperHost.makeLivePropertyState(runtimeInput: .init(renderDescriptor: descriptor,
            propertyBindingProgram: program(key, ids, seed), effectivePropertyValues: [key: .bool(seed)]),
            resolvedMaterialExecutionCapabilities: catalog, soundPlaybackProgram: .init(),
            preparedStaticModelLayerIDs: models, preparedImageMaterialTargets: [],
            preparedParticleVisibilityLayerIDs: particles,
            propertyVectorScriptProgram: .init(), sceneScriptScalarProgram: .init(),
            sceneScriptStringProgram: .init())
    }
    static func bool(_ state: ScenePropertyLiveUpdateState, _ id: Int) -> Bool? {
        guard case let .bool(value)? = state.userValues[target(id)] else { return nil }; return value
    }
    static func same(_ a: ScenePropertyLiveUpdateState, _ b: ScenePropertyLiveUpdateState) -> Bool {
        a.userValues == b.userValues && a.effectiveValues == b.effectiveValues && a.revision == b.revision
    }
    static func cohort(key: String, quad: Int, particle: Int, seed: Bool) -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: quad, contentKind: "quad", visible: seed, effects: [1]),
            .init(id: particle, contentKind: "particle", visible: seed, particlePath: "own-particle.json")])
        var current = state(descriptor, Catalog([quad: .init()]), key: key,
            ids: [quad, particle], seed: seed, particles: [particle])
        var facts: [String: Bool] = [:]
        facts["preparedBoth"] = current.activeConsumerTargets.isSuperset(of: [target(quad), target(particle)])
        facts["firstAtomic"] = current.apply(.bool(!seed), forPropertyKey: key)
            && bool(current, quad) == !seed && bool(current, particle) == !seed && current.revision == 1
        facts["secondAtomic"] = current.apply(.bool(seed), forPropertyKey: key)
            && bool(current, quad) == seed && bool(current, particle) == seed && current.revision == 2
        let held = current
        facts["particleUnavailable"] = !current.apply(.bool(!seed), forPropertyKey: key,
            unavailableConsumerTargets: [target(particle)]) && same(current, held)
        facts["quadUnavailable"] = !current.apply(.bool(!seed), forPropertyKey: key,
            unavailableConsumerTargets: [target(quad)]) && same(current, held)
        return facts
    }
    static func rejectedPreparedFacts() -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 100, contentKind: "quad", effects: [1]),
            .init(id: 54, contentKind: "particle", particlePath: "own.json")])
        var facts: [String: Bool] = [:]
        let cases: [(String, Catalog)] = [
            ("missingProgram", Catalog()),
            ("foreignLayerProgram", Catalog([101: .init()])),
            ("capturedLayer", Catalog([100: .init(sourceRoute: .capturedLayerTexture)])),
            ("capturedMain", Catalog([100: .init(sourceRoute: .capturedMainTargetTexture)])),
            ("emptyMaterials", Catalog([100: .init(materials: [:])])),
        ]
        for (name, catalog) in cases {
            var current = state(descriptor, catalog, key: "sunrays", ids: [100, 54], particles: [54])
            let held = current
            facts[name] = !current.activeConsumerTargets.contains(target(100))
                && !current.apply(.bool(false), forPropertyKey: "sunrays") && same(current, held)
                && bool(current, 54) == true
        }
        let own = Catalog([100: .init()]), foreign = Catalog([100: .init()])
        let claim = own.claim(layerID: 100)!
        facts["ownToken"] = own.resolve(claim.token) != nil
        facts["foreignOwnerToken"] = foreign.resolve(claim.token) == nil
        facts["missingToken"] = own.claim(layerID: 999) == nil
        facts["foreignCapabilityToken"] = own.resolve(.init(ownerID: claim.token.ownerID,
            capabilityID: UUID(), layerID: 100)) == nil
        facts["foreignLayerToken"] = own.resolve(.init(ownerID: claim.token.ownerID,
            capabilityID: claim.token.capabilityID, layerID: 101)) == nil
        return facts
    }
    static func existingBoundaries() -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let model = SceneRenderDescriptor(layers: [.init(id: 71, contentKind: "model", staticModelPath: "own.mdl")])
        var ready = state(model, Catalog(), key: "show", ids: [71], models: [71])
        facts["preparedModel"] = ready.apply(.bool(false), forPropertyKey: "show")
        var missing = state(model, Catalog(), key: "show", ids: [71])
        facts["missingModel"] = !missing.apply(.bool(false), forPropertyKey: "show")
        for captures in [false, true] {
            var fullscreen = SceneRenderDescriptor(layers: [.init(id: 80, contentKind: "fullscreen",
                utilityLayer: .init(kind: .fullscreen, copyBackground: false, passthrough: false), effects: [1])])
            fullscreen.preparedUtilityPlans = [80: .init(shouldCapture: captures)]
            var current = state(fullscreen, Catalog([80: .init(sourceRoute: .capturedMainTargetTexture)]),
                key: "show", ids: [80])
            facts[captures ? "fullscreenCapture" : "fullscreenNoCapture"] =
                current.apply(.bool(false), forPropertyKey: "show") == captures
            if captures {
                var cold = state(fullscreen, Catalog(), key: "show", ids: [80])
                facts["fullscreenNoProgram"] = !cold.apply(.bool(false), forPropertyKey: "show")
            }
        }
        return facts
    }
    static func main() throws {
        let report: [String: Any] = [
            "originalOn": cohort(key: "sunrays", quad: 100, particle: 54, seed: true),
            "renamedOff": cohort(key: "renamedBeam", quad: 407, particle: 819, seed: false),
            "preparedRejections": rejectedPreparedFacts(), "existingBoundaries": existingBoundaries()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }
}
'''


class QuadVisibilityLiveConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        output = ROOT / ".artifacts/tmp/light-cohort-376872-20261020/tests"
        output.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="quad-live-", dir=output)
        cls.addClassCleanup(cls.temporary.cleanup)
        work = Path(cls.temporary.name)
        catalog = CATALOG.read_text()
        token_start = catalog.index("    struct Token: Hashable {")
        token_end = catalog.index("    struct SceneBackgroundRequirement:", token_start)
        layer = (SCENE / "Runtime/Frame/SceneRenderDescriptor+Layer.swift").read_text()
        colors = "\n".join(method_body(layer, "nonisolated var " + name + ": Bool") for name in [
            "supportsDirectLayerColorConsumer", "supportsUserPropertyLayerColorConsumer",
            "supportsUserPropertyImageSourceModulationConsumer"])
        host = HOST.read_text()
        carriers = CARRIERS.replace("__TOKEN_TYPES__", catalog[token_start:token_end])
        for marker, actual in {
            "__COLOR_CONTRACTS__": colors,
            "__CLAIM__": method_body(catalog, "func claim(layerID: Int)"),
            "__RESOLVE__": method_body(catalog, "func resolve(_ token: Token)"),
            "__EXECUTION_IDS__": method_body(catalog, "var executionLayerIDs: Set<Int>"),
            "__IMAGE_MODULATION__": method_body(host, "static func imageLayerModulationConsumerTargets("),
            "__ACTIVE_CONSUMERS__": method_body(host, "static func activeLiveConsumerTargets("),
            "__MAKE_STATE__": method_body(host, "static func makeLivePropertyState("),
        }.items():
            carriers = carriers.replace(marker, actual)
        source = ADMISSION.read_text()
        start = source.index("nonisolated enum SceneDynamicLayerVisibilityRouteAdmission {")
        end = source.index("/// Raw-graph conservation", start)
        admission = work / "Admission.swift"
        admission.write_text("import Foundation\n" + source[start:end])
        harness = work / "Probe.swift"
        harness.write_text(carriers + HARNESS)
        binary = work / "probe"
        built = subprocess.run(["swiftc", *map(str, SWIFT_SOURCES),
            str(SCENE / "Rendering/Composition/SceneUtilityLayer.swift"),
            str(SCENE / "Rendering/Composition/SceneUtilityLayerSourceRoute.swift"),
            str(admission), str(harness), "-module-cache-path", str(work / "cache"),
            "-o", str(binary)], capture_output=True, text=True, timeout=120)
        if built.returncode:
            raise AssertionError(built.stdout + built.stderr)
        cls.result = json.loads(subprocess.check_output([binary], text=True, timeout=30))

    def test_original_and_renamed_cohorts_commit_both_bools_atomically(self) -> None:
        for name in ["originalOn", "renamedOff"]:
            for fact, passed in self.result[name].items():
                self.assertTrue(passed, (name, fact))

    def test_prepared_route_material_and_actual_token_identity_are_required(self) -> None:
        for name, passed in self.result["preparedRejections"].items():
            self.assertTrue(passed, name)

    def test_existing_model_and_fullscreen_readiness_guards_remain(self) -> None:
        for name, passed in self.result["existingBoundaries"].items():
            self.assertTrue(passed, name)


if __name__ == "__main__":
    unittest.main()
