"""Script-addressable roots prepare without changing frame visibility."""
import json
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
    struct Utility { enum Kind { case composition }; let kind: Kind }
    struct Layer {
        let id: Int
        var visible: Bool? = false
        var parentID: Int? = nil
        var childLayerIDs: [Int] = []
        var contentKind: String = "image"
        var utilityLayer: Utility? = nil
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership? = nil
    }
    let layers: [Layer]
}
@main enum Harness {
    static func main() throws {
        let d = SceneRenderDescriptor(layers: [
            .init(id: 1), .init(id: 2, visible: true),
            .init(id: 3, contentKind: "composition", utilityLayer: .init(kind: .composition)),
            .init(id: 4, visible: true, contentKind: "composition", utilityLayer: .init(kind: .composition)),
            .init(id: 5, parentID: 6), .init(id: 6, childLayerIDs: [5]),
            .init(id: 7, contentKind: "text"), .init(id: 8, contentKind: "solid"),
            .init(id: 9, contentKind: "particle")
        ])
        func ids(_ candidates: Set<SceneDynamicTarget>, scripts: Bool) -> [Int] {
            SceneDynamicLayerVisibilityRouteAdmission.targets(in: d, candidates: candidates, hasScriptLayerAccess: scripts).compactMap {
                if case let .layer(id, .visibility) = $0 { return id }; return nil
            }.sorted()
        }
        let target = SceneDynamicTarget.layer(layerID: 1, field: .visibility)
        let definition = SceneDynamicTargetDefinition(target: target, valueType: .bool, authoredValue: .bool(false))
        let shown = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1, definitions: [definition], sceneScriptValues: [target: .bool(true)]).snapshot
        let hidden = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 2, definitions: [definition], sceneScriptValues: [target: .bool(false)]).snapshot
        let output: [String: Any] = [
            "scriptRoots": ids([], scripts: true),
            "noScripts": ids([], scripts: false),
            "typedOwner": ids([target], scripts: false),
            "authoredHidden": !SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: .empty(frameIndex: 0)).contains(1),
            "shown": SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: shown).contains(1),
            "hiddenAgain": !SceneLayerVisibility.visibleLayerIDs(in: d, snapshot: hidden).contains(1)
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: output), encoding: .utf8)!)
    }
}
'''

class ScriptVisibleRootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Compile the production declaration, separated from the unrelated
        # graph compiler in the same file; no copied admission algorithm.
        source = (SCENE / 'Compilation/Material/SceneResolvedMaterialExecutionCapabilityAdmission.swift').read_text()
        start = source.index('nonisolated enum SceneDynamicLayerVisibilityRouteAdmission {')
        end = source.index('/// Raw-graph conservation', start)
        with tempfile.TemporaryDirectory(prefix='mwx-visible-root-test-') as tmp:
            root = Path(tmp)
            admission = root / 'Admission.swift'
            admission.write_text('import Foundation\n' + source[start:end])
            harness = root / 'Harness.swift'
            harness.write_text(HARNESS)
            binary = root / 'run'
            subprocess.run(['swiftc', str(SCENE / 'Systems/Properties/SceneDynamicSnapshot.swift'), str(SCENE / 'Rendering/Geometry/SceneLayerVisibility.swift'), str(admission), str(harness), '-o', str(binary)], check=True, capture_output=True, text=True)
            cls.result = json.loads(subprocess.check_output([str(binary)], text=True))

    def test_arbitrary_script_layer_lookup_prepares_supported_roots(self):
        self.assertEqual(self.result['scriptRoots'], [1, 2, 4, 7, 8])

    def test_no_script_keeps_only_explicit_typed_candidates(self):
        self.assertEqual(self.result['noScripts'], [])
        self.assertEqual(self.result['typedOwner'], [1])

    def test_preparation_does_not_force_visibility_or_prevent_hiding(self):
        for key in ['authoredHidden', 'shown', 'hiddenAgain']:
            self.assertTrue(self.result[key], key)
