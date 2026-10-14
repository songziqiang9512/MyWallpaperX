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
        facts["failed_owner_keeps_fuse_and_property_recovery"] = failed.failures[target] != nil
            && failed.mediaPlaybackCommands.isEmpty && failed.ownerEffects.isEmpty
            && vector.disabledTargets.contains(target)
            && vector.activeLivePropertyInputTargets.contains(target)
        vector.finalizeLayerMutations(committing: false)
        let unavailable = vector.livePropertyInputTargets.subtracting(vector.activeLivePropertyInputTargets)
        let held = evaluate()
        facts["unchanged_revision_keeps_fuse"] = held.failures.isEmpty
            && held.mediaPlaybackCommands.isEmpty && vector.disabledTargets.contains(target)
        let originalOwner = vector.bindings[0].owner
        facts["recoverable_live_update_admitted"] = !unavailable.contains(target)
            && state.apply(.string("b"), forPropertyKey: "music",
                unavailableConsumerTargets: unavailable) && state.revision == 3
        let missingRecoveryInput = vector.evaluate(inputs: [:],
            effectivePropertyValues: state.effectiveValues, frame: frame, propertyRevision: state.revision)
        let wrongRecoveryInput = vector.evaluate(inputs: [target: .scalar(1)],
            effectivePropertyValues: state.effectiveValues, frame: frame, propertyRevision: state.revision)
        facts["unprepared_input_does_not_consume_recovery"] = missingRecoveryInput.values.isEmpty
            && wrongRecoveryInput.values.isEmpty && vector.disabledTargets.contains(target)
            && originalOwner.canRetryUserPropertyCallback(at: state.revision)
        let beforeRecovery = vector.frameStateSnapshot()
        let recovered = evaluate()
        facts["recovery_uses_original_owner"] = isSoundPlay(recovered)
            && vector.bindings[0].owner === originalOwner
            && !vector.disabledTargets.contains(target)
        facts["same_revision_before_commit_does_not_duplicate_event"] = evaluate().mediaPlaybackCommands.isEmpty
        vector.restoreFrameState(beforeRecovery, rejectedOwnerTargets: [target])
        vector.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        let recoveredAfterRejection = evaluate()
        facts["reverted_ack_recovery_survives_cohort_rejection"] = isSoundPlay(recoveredAfterRejection)
            && vector.bindings[0].owner === originalOwner
            && !vector.disabledTargets.contains(target)
        vector.finalizeLayerMutations(committing: true)
        let afterRecovery = evaluate()
        facts["recovery_event_acked_once"] = afterRecovery.failures.isEmpty
            && afterRecovery.mediaPlaybackCommands.isEmpty
        vector.finalizeLayerMutations(committing: true)

        let multikey = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding("""
                let musicState = 0, otherState = 0;
                export function init(value) { return value; }
                export function applyUserProperties(changed) {
                    if (changed.hasOwnProperty('music')) {
                        if (engine.userProperties.music === 'disable') throw Error('bad music');
                        musicState = engine.userProperties.music === 'b' ? 2 : 1;
                    }
                    if (changed.hasOwnProperty('other'))
                        otherState = engine.userProperties.other === 'b' ? 20 : 10;
                }
                export function update(value) { value.x = musicState + otherState; return value; }
                """)], userPropertyDefinitions: [definition("music"), definition("other")], generation: 42)
        func multikeyEvaluate(_ music: String, _ other: String, _ revision: UInt64) -> SceneScriptVectorFrameResult {
            multikey.evaluate(inputs: input,
                effectivePropertyValues: ["music": .string(music), "other": .string(other)],
                frame: frame, propertyRevision: revision)
        }
        let multikeyInitial = multikeyEvaluate("a", "a", 0)
        multikey.finalizeLayerMutations(committing: true)
        let multikeyFailure = multikeyEvaluate("disable", "a", 1)
        multikey.finalizeLayerMutations(committing: false)
        let multikeyAck = multikey.frameStateSnapshot()
        let multikeyRecovery = multikeyEvaluate("a", "b", 2)
        multikey.restoreFrameState(multikeyAck, rejectedOwnerTargets: [target])
        multikey.finalizeLayerMutations(committing: true, rejectedOwnerTargets: [target])
        let multikeyReverted = multikeyEvaluate("a", "a", 3)
        facts["rejected_recovery_retains_all_delivered_changed_keys"] = multikeyInitial.values[target] == .vector3(11, 0, 0)
            && multikeyFailure.failures[target] != nil
            && multikeyRecovery.values[target] == .vector3(21, 0, 0)
            && multikeyReverted.values[target] == .vector3(11, 0, 0)
        multikey.finalizeLayerMutations(committing: true)

        let updateFailure = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding("""
                export function applyUserProperties(changed) {}
                export function update(value) { throw Error('value failed'); }
                """)], userPropertyDefinitions: [definition("music")], generation: 3)
        _ = updateFailure.evaluate(inputs: input, effectivePropertyValues: ["music": .string("a")],
            frame: frame, propertyRevision: 0)
        facts["update_failure_not_reopened"] = updateFailure.disabledTargets.contains(target)
            && !updateFailure.activeLivePropertyInputTargets.contains(target)
        let updateAgain = updateFailure.evaluate(inputs: input,
            effectivePropertyValues: ["music": .string("b")], frame: frame, propertyRevision: 1)
        facts["new_revision_does_not_reopen_update_failure"] = updateAgain.values.isEmpty
            && updateFailure.disabledTargets.contains(target)

        let timerFailure = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding("""
                export function init(value) { engine.setTimeout(() => {}, 100000); return value; }
                export function applyUserProperties(changed) {
                    if (engine.userProperties.music === 'disable') throw Error('pending work');
                }
                """)], userPropertyDefinitions: [definition("music")], generation: 4)
        _ = timerFailure.evaluate(inputs: input, effectivePropertyValues: ["music": .string("a")],
            frame: frame, propertyRevision: 0)
        timerFailure.finalizeLayerMutations(committing: true)
        _ = timerFailure.evaluate(inputs: input, effectivePropertyValues: ["music": .string("disable")],
            frame: frame, propertyRevision: 1)
        facts["pending_timer_keeps_original_rejection"] = timerFailure.disabledTargets.contains(target)
            && !timerFailure.activeLivePropertyInputTargets.contains(target)

        let overflowDescriptor = SceneRenderDescriptor(layers: ([10] + (1...257).filter { $0 != 10 }).enumerated().map { index, id in
            .init(id: id, layerIndex: index, name: "entry\(id)", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        })
        let overflowDomain = try SceneScriptQuickJSDomain()
        let overflowProgram = SceneScriptVectorProgram.compile(domain: overflowDomain,
            descriptor: overflowDescriptor, scriptBindings: [binding("""
                export function init(value) { return value; }
                export function applyUserProperties(renamed) {
                    for (let index = 1; index <= 257; index++)
                        thisScene.getLayer('entry' + index).alpha = 0.5;
                }
                """)], userPropertyDefinitions: [definition("music")], generation: 41)
        try overflowDomain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: overflowDescriptor)
        let overflowResult = overflowProgram.evaluate(inputs: input,
            effectivePropertyValues: ["music": .string("a")], frame: frame, propertyRevision: 0)
        if case .mutationOverflow? = overflowResult.failures[target] {
            facts["host_layer_overflow_keeps_safety_fuse"] = overflowProgram.bindings.count == 1
                && !overflowProgram.activeLivePropertyInputTargets.contains(target)
                && overflowResult.layerMutations.isEmpty
        } else { facts["host_layer_overflow_keeps_safety_fuse"] = false }

        let initiallyBad = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding("""
                export function init(value) { return value; }
                export function applyUserProperties(changed) {
                    thisScene.getLayer('sound').play();
                    throw Error('local callback failure');
                }
                """)], userPropertyDefinitions: [definition("music"), definition("other")], generation: 5)
        let initialBad = initiallyBad.evaluate(inputs: input,
            effectivePropertyValues: ["music": .string("a"), "other": .string("a")],
            frame: frame, propertyRevision: 0)
        initiallyBad.finalizeLayerMutations(committing: false)
        var recoveringState = ScenePropertyLiveUpdateState(program: properties,
            effectiveValues: ["music": .string("a"), "other": .string("a")],
            activeConsumerTargets: initiallyBad.livePropertyInputTargets,
            scriptUserPropertyConsumerTargetsByKey: initiallyBad.liveUserPropertyConsumerTargetsByKey)
        let badUnavailable = initiallyBad.livePropertyInputTargets
            .subtracting(initiallyBad.activeLivePropertyInputTargets)
        facts["initial_callback_failure_keeps_other_edits_live"] = initialBad.failures[target] != nil
            && initialBad.mediaPlaybackCommands.isEmpty
            && recoveringState.apply(.string("b"), forPropertyKey: "other",
                unavailableConsumerTargets: badUnavailable)
        let badAgain = initiallyBad.evaluate(inputs: input,
            effectivePropertyValues: recoveringState.effectiveValues,
            frame: frame, propertyRevision: recoveringState.revision)
        facts["repeated_callback_failure_stays_local"] = badAgain.failures[target] != nil
            && badAgain.mediaPlaybackCommands.isEmpty && initiallyBad.disabledTargets.contains(target)
            && recoveringState.effectiveValues["other"] == .string("b")
        initiallyBad.finalizeLayerMutations(committing: false)
        let owner = initiallyBad.bindings[0].owner
        facts["stale_generation_cannot_clear_fuse"] = owner.canRetryUserPropertyCallback
            && !mwx_scene_quickjs_owner_retry_user_properties(owner.handle, 6)
            && owner.canRetryUserPropertyCallback

        let recoverySource = """
            export function init(value) { return value; }
            export function applyUserProperties(payload) {
                if (payload.music === 'disable') throw Error('property fault');
            }
            """
        let scalarTarget = SceneDynamicTarget.layer(layerID: 10, field: .alpha)
        let scalarBinding = SceneScriptBindingIR(source: recoverySource,
            owner: .init(kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("alpha")], properties: [:],
            authoredValue: .number(1), valueType: .number, wrapperKeys: ["script", "value"])
        let scalarDomain = try SceneScriptQuickJSDomain()
        try scalarDomain.configureLayerCatalog(descriptor)
        try scalarDomain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor)
        let scalar = SceneScriptScalarProgram.compile(domain: scalarDomain,
            descriptor: descriptor, scriptBindings: [scalarBinding],
            userPropertyDefinitions: [definition("music")], generation: 20)
        let scalarBad = scalar.evaluate(inputs: [scalarTarget: .scalar(1)], frame: frame,
            effectivePropertyValues: ["music": .string("disable")], propertyRevision: 0)
        scalar.finalizeLayerMutations(committing: false)
        let scalarGood = scalar.evaluate(inputs: [scalarTarget: .scalar(1)], frame: frame,
            effectivePropertyValues: ["music": .string("a")], propertyRevision: 1)
        facts["scalar_program_admitted"] = scalar.bindings.count == 1
        facts["scalar_property_failure_observed"] = scalarBad.failures[scalarTarget] != nil
        facts["scalar_retry_completed"] = scalarGood.failures.isEmpty && !scalar.disabledTargets.contains(scalarTarget)
        facts["scalar_program_recovery"] = scalar.bindings.count == 1
            && scalarBad.failures[scalarTarget] != nil && scalarGood.failures.isEmpty
            && scalarGood.values[scalarTarget] == .scalar(1)
        scalar.finalizeLayerMutations(committing: true)
        let textDescriptor = SceneRenderDescriptor(layers: [.init(id: 10, layerIndex: 0,
            name: "renamed text", visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1],
            alpha: 1, effects: [], contentKind: "text", textScript: .init(source: recoverySource),
            text: "seed", textStyle: .init(fontPath: nil, colorRGB: [1, 1, 1], pointSize: 32))])
        let textBinding = SceneScriptBindingIR(source: recoverySource,
            owner: .init(kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
            targetPath: [.key("objects"), .index(0), .key("text")], properties: [:],
            authoredValue: .string("seed"), valueType: .string, wrapperKeys: ["script", "value"])
        let textDomain = try SceneScriptQuickJSDomain()
        try textDomain.configureLayerCatalog(textDescriptor)
        let text = SceneScriptStringProgram.compile(domain: textDomain,
            descriptor: textDescriptor, scriptBindings: [textBinding],
            userPropertyDefinitions: [definition("music")], generation: 21)
        let textTarget = SceneDynamicTarget.text(layerID: 10, field: .content)
        let textBad = text.evaluate(inputs: [textTarget: .string("seed")],
            effectivePropertyValues: ["music": .string("disable")], propertyRevision: 0, frame: frame)
        text.finalizeLayerMutations(committing: false)
        let textGood = text.evaluate(inputs: [textTarget: .string("seed")],
            effectivePropertyValues: ["music": .string("a")], propertyRevision: 1, frame: frame)
        facts["string_program_recovery"] = text.bindings.count == 1
            && textBad.failures[textTarget] != nil && textGood.failures.isEmpty
            && textGood.values[textTarget] == .string("seed")
        text.finalizeLayerMutations(committing: true)
        let malformedDomain = try SceneScriptQuickJSDomain()
        try malformedDomain.configureLayerCatalog(descriptor)
        try malformedDomain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor)
        let malformedProgram = SceneScriptVectorProgram.compile(domain: malformedDomain,
            descriptor: descriptor, scriptBindings: [binding(
                "export function init(value) { return value; } export function applyUserProperties(payload) {}")],
            userPropertyDefinitions: [definition("music")], generation: 40)
        let malformedWarm = malformedProgram.evaluate(inputs: input,
            effectivePropertyValues: ["music": .string("a")], frame: frame, propertyRevision: 0)
        malformedProgram.finalizeLayerMutations(committing: true)
        let malformedOwner = malformedProgram.bindings[0].owner
        let malformedResult = malformedOwner.dispatchUserProperties(changedPropertiesJSON: "{bad",
            scriptPropertiesJSON: "{}", frame: frame, userPropertiesJSON: "{}", propertyRevision: 1)
        facts["invalid_payload_fixture_warmed"] = malformedWarm.failures.isEmpty
        if case .failure = malformedResult {
            facts["invalid_json_payload_rejected"] = true
        } else { facts["invalid_json_payload_rejected"] = false }
        facts["invalid_event_payload_is_not_authored_failure"] = !malformedOwner.canRetryUserPropertyCallback
            && !malformedOwner.retryUserPropertyCallback(propertyRevision: 1)
        _ = owner.teardown(frame: frame, scriptPropertiesJSON: "{}", userPropertiesJSON: "{}")
        facts["teardown_revokes_recovery"] = !owner.canRetryUserPropertyCallback
            && !owner.retryUserPropertyCallback(propertyRevision: 2)

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
        // Property revisions cannot wake an owner without that callback. Real
        // media events and value hooks still observe current engine properties.
        for (index, source) in [
            "export function mediaPlaybackChanged(e) { thisLayer.origin = new Vec3(engine.userProperties.music === 'b' ? 2 : 1, 0, 0); }",
            "function renamed(payload) { thisLayer.origin = new Vec3(engine.userProperties.music === 'b' ? 2 : 1, 0, 0); } export { renamed as mediaPlaybackChanged };"
        ].enumerated() {
            let quietDomain = try SceneScriptQuickJSDomain()
            let quiet = SceneScriptVectorProgram.compile(domain: quietDomain,
                descriptor: descriptor, scriptBindings: [binding(source)],
                userPropertyDefinitions: [definition("music")], generation: UInt64(50 + index))
            try quietDomain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor)
            let idle = quiet.evaluate(inputs: input, effectivePropertyValues: ["music": .string("a")],
                frame: frame, propertyRevision: 0)
            quiet.finalizeLayerMutations(committing: true)
            let revised = quiet.evaluate(inputs: input, effectivePropertyValues: ["music": .string("b")],
                frame: frame, propertyRevision: 1)
            quiet.finalizeLayerMutations(committing: true)
            let event = quiet.evaluate(inputs: input, effectivePropertyValues: ["music": .string("b")],
                frame: frame, propertyRevision: 1, mediaPlaybackEvent: .init(state: 1, generation: 1))
            quiet.finalizeLayerMutations(committing: true)
            let held = quiet.evaluate(inputs: input, effectivePropertyValues: ["music": .string("b")],
                frame: frame, propertyRevision: 1, mediaPlaybackEvent: .init(state: 1, generation: 1))
            facts["no_property_callback_sleeps_\(index)"] = quiet.bindings.count == 1
                && !quiet.bindings[0].owner.handlesUserProperties
                && idle.values.isEmpty && idle.failures.isEmpty
                && revised.values.isEmpty && revised.failures.isEmpty
            facts["media_event_still_reads_current_properties_\(index)"] = event.failures.isEmpty
                && event.layerMutations.contains(where: { $0.layerID == 10
                    && $0.fields.contains(.origin) && $0.origin == SIMD3<Double>(2, 0, 0) })
                && held.failures.isEmpty && held.values.isEmpty && held.layerMutations.isEmpty
        }
        let initOnce = pure.evaluate(inputs: input, effectivePropertyValues: ["music": .string("a")],
            frame: frame, propertyRevision: 0)
        pure.finalizeLayerMutations(committing: true)
        let afterInit = pure.evaluate(inputs: input, effectivePropertyValues: ["music": .string("b")],
            frame: frame, propertyRevision: 1)
        facts["init_only_new_revision_stays_quiet"] = initOnce.values[target] == .vector3(0, 0, 0)
            && initOnce.failures.isEmpty && afterInit.values.isEmpty && afterInit.failures.isEmpty
        let valueOnly = SceneScriptVectorProgram.compile(domain: try SceneScriptQuickJSDomain(),
            descriptor: descriptor, scriptBindings: [binding(
                "export function update(v) { return new Vec3(engine.userProperties.music === 'b' ? 2 : 1, 0, 0); }")],
            userPropertyDefinitions: [definition("music")], generation: 52)
        let beforeEdit = valueOnly.evaluate(inputs: input, effectivePropertyValues: ["music": .string("a")],
            frame: frame, propertyRevision: 0)
        valueOnly.finalizeLayerMutations(committing: true)
        let afterEdit = valueOnly.evaluate(inputs: input, effectivePropertyValues: ["music": .string("b")],
            frame: frame, propertyRevision: 1)
        facts["value_hook_without_property_callback_still_updates"] = beforeEdit.values[target] == .vector3(1, 0, 0)
            && afterEdit.values[target] == .vector3(2, 0, 0) && afterEdit.failures.isEmpty
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
            self.assertIn("recovery_uses_original_owner", facts)
            self.assertTrue(all(facts.values()), {key: value for key, value in facts.items() if not value})


if __name__ == "__main__":
    unittest.main()
