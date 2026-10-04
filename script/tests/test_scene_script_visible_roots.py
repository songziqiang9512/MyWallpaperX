"""Typed/script visibility prepares ordinary hierarchies without revealing them."""
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
                            utilityLayer: name == "utility" ? .init(kind: .composition) : nil)]
        case "foreign-ancestor": layers = [.init(id: 10, parentID: 11, contentKind: "text"),
                                            .init(id: 11, childLayerIDs: [10], contentKind: "model")]
        default: fatalError("unknown owned fixture")
        }
        return .init(layers: layers)
    }
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            let descriptor = negative(CommandLine.arguments[1])
            let targets = ids(descriptor, candidates: [target(10)])
            var output: [String: Any] = ["targets": targets]
#if PREPARATION_API
            output["preparation"] = SceneDynamicLayerVisibilityRouteAdmission.preparationLayerIDs(
                in: descriptor, candidates: [target(10)]).sorted()
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
            built = subprocess.run(['swiftc', *flags, str(SCENE / 'Systems/Properties/SceneDynamicSnapshot.swift'),
                str(SCENE / 'Rendering/Geometry/SceneLayerVisibility.swift'),
                str(SCENE / 'Rendering/Composition/SceneUtilityLayerSourceRoute.swift'),
                str(admission), *extra_sources, str(harness), '-o', str(cls.binary)], capture_output=True, text=True)
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
        self.assertEqual(self.result['scriptRoots'], [1, 2, 4, 5, 6, 7, 8])

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
