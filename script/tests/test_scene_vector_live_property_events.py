"""Real Vector owner metadata admits hot properties and emits typed Sound commands.

Uses the shared QuickJS/Vector compiler fixture and production LiveUpdateState;
does not start audio, an App, or reproduce the Host's consumer-map calculation.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .scene_vector_vm_test_support import SCENE, compile_vector_harness


PROPERTY_SOURCES = tuple(
    SCENE / "Systems/Properties" / name
    for name in (
        "ScenePropertyBindingProgram.swift",
        "ScenePropertyBindingProgramValidator.swift",
        "ScenePropertyBindingCompiler+TargetMapping.swift",
        "ScenePropertyLiveUpdateState.swift",
    )
)

HARNESS = r'''
@main enum Harness {
    static let target = SceneDynamicTarget.layer(layerID: 10, field: .origin)
    static func binding(_ source: String) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: 0, objectID: 10,
            effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("origin")], properties: [:],
            authoredValue: .string("0 0 0"), valueType: .string,
            wrapperKeys: ["script", "value"])
    }
    static func definition(_ key: String) -> SceneUserPropertyDefinition {
        .init(key: key, title: key, kind: .combo, runtimeType: "combo", order: 0,
            index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil,
            displayCondition: nil, defaultValue: .string("a"), options:
                ["a", "b", "disable"].map {
                    .init(label: $0, value: .string($0), displayCondition: nil)
                })
    }
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 10, layerIndex: 0, name: "controller", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
            .init(id: 20, layerIndex: 1, name: "sound", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [],
                contentKind: "sound")
        ])
        let domain = try SceneScriptQuickJSDomain()
        let vector = SceneScriptVectorProgram.compile(domain: domain,
            descriptor: descriptor, scriptBindings: [binding("""
                export function init(value) { return value; }
                export function applyUserProperties(changed) {
                    if (changed.hasOwnProperty('music')) {
                        if (engine.userProperties.music === 'disable') throw Error('owner failed');
                        thisScene.getLayer('sound').play();
                    }
                }
                """)], userPropertyDefinitions: [definition("music"), definition("other")],
            generation: 1)
        try domain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor,
            soundPlaybackSnapshots: [20: false])
        let input = [target: SceneDynamicValue.vector3(0, 0, 0)]
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(),
            simulationFrameTime: 0.016, sceneTime: 1))
        let properties = ScenePropertyBindingProgram(definitions: [], instructions: [])
        var state = ScenePropertyLiveUpdateState(program: properties,
            effectiveValues: ["music": .string("a"), "other": .string("a")],
            activeConsumerTargets: vector.activeLivePropertyInputTargets,
            scriptUserPropertyConsumerTargetsByKey: vector.liveUserPropertyConsumerTargetsByKey)
        func evaluate() -> SceneScriptVectorFrameResult {
            vector.evaluate(inputs: input, effectivePropertyValues: state.effectiveValues,
                frame: frame, propertyRevision: state.revision)
        }
        func isSoundPlay(_ result: SceneScriptVectorFrameResult) -> Bool {
            result.failures.isEmpty && result.mediaPlaybackCommands == [
                .init(layerID: 20, action: .play, destination: .soundLayer)]
                && result.ownerEffects.count == 1
                && result.ownerEffects[0].ownerTarget == target
                && result.ownerEffects[0].mediaPlaybackCommands == result.mediaPlaybackCommands
        }
        var facts: [String: Bool] = [:]
        facts["prepared_owner"] = vector.bindings.count == 1
            && vector.liveUserPropertyConsumerTargetsByKey["music"] == [target]
            && vector.liveUserPropertyConsumerTargetsByKey["other"] == [target]
            && vector.liveUserPropertyConsumerTargetsByKey["unknown"] == nil
            && vector.activeLivePropertyInputTargets.contains(target)
        let initial = evaluate()
        facts["initial_callback"] = isSoundPlay(initial)
        vector.finalizeLayerMutations(committing: true)
        facts["live_apply"] = state.apply(.string("b"), forPropertyKey: "music")
            && state.revision == 1 && state.effectiveValues["music"] == .string("b")
        let changed = evaluate()
        facts["live_callback_sound_destination"] = isSoundPlay(changed)
        vector.finalizeLayerMutations(committing: true)
        facts["same_value_no_revision"] = state.apply(.string("b"), forPropertyKey: "music")
            && state.revision == 1
        let unchanged = evaluate()
        facts["same_value_no_replay"] = unchanged.failures.isEmpty
            && unchanged.mediaPlaybackCommands.isEmpty && unchanged.ownerEffects.isEmpty
        vector.finalizeLayerMutations(committing: true)
        let before = state.effectiveValues
        facts["wrong_kind_atomic"] = !state.apply(.number(2), forPropertyKey: "music")
            && state.revision == 1 && state.effectiveValues == before
        facts["failure_value_admitted_before_vm"] = state.apply(.string("disable"), forPropertyKey: "music")
            && state.revision == 2
        let failed = evaluate()
        facts["failed_owner_revoked"] = failed.failures[target] != nil
            && failed.mediaPlaybackCommands.isEmpty && failed.ownerEffects.isEmpty
            && vector.disabledTargets.contains(target)
            && !vector.activeLivePropertyInputTargets.contains(target)
        vector.finalizeLayerMutations(committing: false)
        let unavailable = vector.livePropertyInputTargets.subtracting(vector.activeLivePropertyInputTargets)
        facts["unavailable_live_update_rejected"] = unavailable.contains(target)
            && !state.apply(.string("a"), forPropertyKey: "music",
                unavailableConsumerTargets: unavailable) && state.revision == 2

        let pure = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding(
                "export function init(value) { return value; }")],
            userPropertyDefinitions: [definition("music")], generation: 2)
        var noCallbackState = ScenePropertyLiveUpdateState(program: properties,
            effectiveValues: ["music": .string("a")],
            activeConsumerTargets: pure.activeLivePropertyInputTargets,
            scriptUserPropertyConsumerTargetsByKey: pure.liveUserPropertyConsumerTargetsByKey)
        facts["init_only_not_live_consumer"] = pure.bindings.count == 1
            && pure.liveUserPropertyConsumerTargetsByKey["music"]?.isEmpty == true
            && !noCallbackState.apply(.string("b"), forPropertyKey: "music")
            && noCallbackState.revision == 0
        print(String(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("clang"), "Swift and Clang required")
class SceneVectorLivePropertyEventTests(unittest.TestCase):
    def test_real_vector_owner_is_a_live_property_event_consumer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-vector-live-property-") as temporary:
            binary = compile_vector_harness(
                Path(temporary), HARNESS, "vector-live-property-events",
                extra_swift_sources=PROPERTY_SOURCES,
            )
            result = subprocess.run(
                ["/usr/bin/env", str(binary)], capture_output=True, text=True,
                timeout=30, check=False,
            )
            if destination := os.environ.get("MWX_VECTOR_LIVE_TEST_EVIDENCE"):
                root = Path(destination)
                root.mkdir(parents=True, exist_ok=True)
                (root / "stdout.txt").write_text(result.stdout)
                (root / "stderr.txt").write_text(result.stderr)
                (root / "returncode.json").write_text(json.dumps(result.returncode) + "\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            facts = json.loads(result.stdout)
            self.assertEqual(len(facts), 11)
            self.assertTrue(all(facts.values()), {key: value for key, value in facts.items() if not value})


if __name__ == "__main__":
    unittest.main()
