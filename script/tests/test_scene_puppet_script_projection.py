#!/usr/bin/env python3
"""Nested animation declarations retain identity and prepare hidden script clips."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    "Format/SceneJSONValue.swift", "Format/SceneScriptBindingDefinition.swift",
    "Format/SceneScriptSourceEvidence.swift",
    "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    "Format/ScenePuppetAnimationLayer.swift", "Format/SceneMdlPuppetAnimation.swift",
    "Systems/Puppet/ScenePuppetAnimationSelection.swift",
]
HARNESS = r'''
import Foundation
import simd
@main enum Harness {
    static func main() throws {
        let wrapper: [String: Any] = ["value": false,
            "script": "export function init(v){thisObject.play();thisObject.setFrame(thisObject.frameCount*scriptProperties.percentage);return v;}",
            "scriptproperties": ["percentage": 0.93]]
        let animation: [String: Any] = ["id": 73, "animation": 4, "name": "phase",
            "visible": wrapper, "additive": false, "blend": 1.0, "rate": 1.0]
        let parsed = SceneScriptBindingIRParser.parse(document: ["objects": [
            ["id": 7, "visible": true, "animationlayers": [animation],
             "nested": ["visible": wrapper]]]])
        let binding = parsed.bindings[0]
        let evidence = SceneScriptSourceEvidenceCollector.collect(document: ["objects": [
            ["id": 7, "animationlayers": [animation]]]])
        let clips = ScenePuppetAnimationLayer.parse([animation])
        let model = SceneMdlPuppetAnimation(id: 4, name: "track", mode: "loop",
            framesPerSecond: 30, frameCount: 1,
            transformsByBone: [], alphaByBone: nil)
        let set = SceneMdlPuppetAnimationSet(boneCount: 0, animations: [model])
        var selectedCount = -1
        if case let .success(selection) = ScenePuppetAnimationSelector.select(layers: clips, animationSet: set) {
            selectedCount = selection?.clips.count ?? 0
        }
        var base = animation; base["visible"] = true
        var unavailable = animation; unavailable["id"] = 74; unavailable["animation"] = 999999
        var unsupported = unavailable
        unsupported["visible"] = wrapper.merging(["unsupportedKey": 1]) { _, new in new }
        var duplicate = animation; duplicate["id"] = 74
        var hiddenFailuresStayLocal = true
        for hidden in [unavailable, unsupported, duplicate] {
            let all = ScenePuppetAnimationLayer.parse([base, hidden])
            if case let .success(selection?) = ScenePuppetAnimationSelector.select(layers: all, animationSet: set) {
                hiddenFailuresStayLocal = hiddenFailuresStayLocal && selection.clips.count == 1
                    && selection.clips[0].layer.id == 73
            } else { hiddenFailuresStayLocal = false }
        }
        var another = duplicate; another["id"] = 75
        let optionalPairs = ScenePuppetAnimationLayer.parse([duplicate, another])
        var optionalDuplicateStaysLocal = false
        if case let .success(selection?) = ScenePuppetAnimationSelector.select(layers: optionalPairs, animationSet: set) {
            optionalDuplicateStaysLocal = selection.clips.count == 1 && selection.clips[0].layer.id == 74
        }
        let reversed = ScenePuppetAnimationLayer.parse([duplicate, base])
        if case let .success(selection?) = ScenePuppetAnimationSelector.select(layers: reversed, animationSet: set) {
            optionalDuplicateStaysLocal = optionalDuplicateStaysLocal && selection.clips.count == 1
                && selection.clips[0].layer.id == 73
        } else { optionalDuplicateStaysLocal = false }
        let legacyData = try JSONSerialization.data(withJSONObject: animation.merging(["visible": false]) { _, new in new })
        // Old encoded models contain no flag; decoding must remain legal.
        let legacy = try JSONDecoder().decode(ScenePuppetAnimationLayer.self, from: legacyData)
        let output: [String: Any] = ["count": parsed.bindings.count,
            "evidenceOwnerMatches": evidence[0].owner == binding.owner,
            "owner": binding.owner.kind.rawValue, "parent": binding.owner.objectID!,
            "index": binding.owner.animationLayerIndex!, "id": binding.owner.animationLayerID!,
            "value": binding.authoredValue?.boolValue as Any,
            "percentage": binding.properties["percentage"]?.numberValue as Any,
            "pathMatches": binding.targetPath == [.key("objects"), .index(0), .key("animationlayers"), .index(0), .key("visible")],
            "hiddenClipPrepared": selectedCount == 1,
            "hiddenFailuresStayLocal": hiddenFailuresStayLocal,
            "optionalDuplicateStaysLocal": optionalDuplicateStaysLocal,
            "scriptFlag": clips[0].hasVisibilityScript == true,
            "legacyNoScript": legacy.hasVisibilityScript != true]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
    }
}
'''

class PuppetScriptProjectionTests(unittest.TestCase):
    def test_nested_owner_is_not_parent_and_hidden_clip_is_prepared(self):
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-script-projection-") as root:
            root = Path(root)
            source = root / "main.swift"
            source.write_text(HARNESS)
            binary = root / "harness"
            compilation = subprocess.run(["swiftc", "-parse-as-library", *[str(SCENE / p) for p in SOURCES],
                            str(source), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stdout + compilation.stderr)
            result = json.loads(subprocess.check_output([binary], text=True))
        self.assertEqual(result["count"], 1)
        self.assertEqual((result["owner"], result["parent"], result["index"], result["id"]),
                         ("animationLayer", 7, 0, 73))
        self.assertFalse(result["value"])
        self.assertEqual(result["percentage"], 0.93)
        for key in ("pathMatches", "hiddenClipPrepared", "scriptFlag", "legacyNoScript", "evidenceOwnerMatches", "hiddenFailuresStayLocal", "optionalDuplicateStaysLocal"):
            self.assertTrue(result[key], key)

if __name__ == "__main__":
    unittest.main()
