"""Direct-model live readiness uses the production Session gate and LiveState.

The private Session method is extracted without rewriting its implementation.
The carrier supplies prepared target sets and surface/generation transport only;
it does not allocate Metal resources, register playback states, or prove those
producers publish the sets. Conditional programs below exercise the existing
LiveState atomic update authority, rather than the parser/compiler admission.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_property_live_update_state import SWIFT_SOURCES


ROOT = Path(__file__).resolve().parents[2]
SESSION_SOURCE = ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/"
    "SceneDesktopWallpaperSession+LiveConsumers.swift"
)

HARNESS = r'''
import Foundation

struct PreparedStaticModels {
    var preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget>
}
struct PreparedDeviceResources { var staticModels: PreparedStaticModels }
struct PreparedScriptProgram { var generation: UInt64 }
struct PreparedDynamicLayerRuntime {
    struct Snapshot { var destroyedAuthoredLayerIDs: Set<Int> }
    var value: Snapshot
    func snapshot() -> Snapshot { value }
}
struct SceneDesktopWallpaperLaunchContext {
    var preparedDeviceResources: PreparedDeviceResources
    var propertyVectorScriptProgram: PreparedScriptProgram
    var sceneScriptDynamicLayerRuntime: PreparedDynamicLayerRuntime
}

final class SceneDesktopWallpaperSession {
    struct View {
        var preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget>
    }
    struct Surface {
        var metalView: View
        var scriptGeneration: UInt64
    }
    var surfaces: [Int: Surface] = [:]
    var preparedSurfaceIDs: Set<Int> = [4, 9]

    __PRODUCTION_GATE__

    func observe(_ context: SceneDesktopWallpaperLaunchContext) -> Set<SceneDynamicTarget> {
        unavailableDirectModelAnimationTargets(in: context)
    }
}

@main enum DirectModelLiveProbe {
    static func context(_ targets: Set<SceneDynamicTarget>, generation: UInt64 = 37,
                        destroyed: Set<Int> = [])
        -> SceneDesktopWallpaperLaunchContext {
        .init(preparedDeviceResources: .init(staticModels: .init(
            preparedDirectModelAnimationVisibilityTargets: targets)),
            propertyVectorScriptProgram: .init(generation: generation),
            sceneScriptDynamicLayerRuntime: .init(value: .init(destroyedAuthoredLayerIDs: destroyed)))
    }

    static func surface(_ targets: Set<SceneDynamicTarget>, generation: UInt64 = 37)
        -> SceneDesktopWallpaperSession.Surface {
        .init(metalView: .init(preparedDirectModelAnimationVisibilityTargets: targets),
            scriptGeneration: generation)
    }

    static func readySession(_ targets: Set<SceneDynamicTarget>) -> SceneDesktopWallpaperSession {
        let session = SceneDesktopWallpaperSession()
        session.surfaces = [4: surface(targets), 9: surface(targets)]
        return session
    }

    static func surfaceFacts(_ a: SceneDynamicTarget, _ b: SceneDynamicTarget) -> [String: Bool] {
        let targets: Set<SceneDynamicTarget> = [a, b]
        let launch = context(targets)
        let session = SceneDesktopWallpaperSession()
        var facts: [String: Bool] = [:]
        facts["no-direct-candidates"] = session.observe(context([])).isEmpty
        facts["no-surfaces"] = session.observe(launch) == targets
        session.surfaces = [4: surface(targets)]
        facts["missing-surface"] = session.observe(launch) == targets
        session.surfaces = [4: surface(targets), 9: surface(targets), 12: surface(targets)]
        facts["extra-surface"] = session.observe(launch) == targets
        session.surfaces = [4: surface(targets), 12: surface(targets)]
        facts["same-count-wrong-surface"] = session.observe(launch) == targets
        session.surfaces = [4: surface(targets), 9: surface(targets)]
        facts["complete-surfaces"] = session.observe(launch).isEmpty
        session.surfaces[9] = surface(targets, generation: 36)
        facts["stale-generation"] = session.observe(launch) == targets
        session.surfaces[9] = surface(targets)
        facts["new-launch-old-surfaces"] = session.observe(context(targets, generation: 38)) == targets
        session.surfaces = [4: surface(targets, generation: 38), 9: surface(targets, generation: 38)]
        facts["matching-new-generation"] = session.observe(context(targets, generation: 38)).isEmpty
        session.preparedSurfaceIDs = [4]
        session.surfaces = [4: surface(targets)]
        facts["one-prepared-surface"] = session.observe(launch).isEmpty
        return facts
    }

    static func targetFacts(layerID: Int, first: Int, second: Int) -> [String: Bool] {
        let a = ScenePuppetAnimationPropertyTarget.visibility(layerID: layerID, animationLayerID: first)
        let b = ScenePuppetAnimationPropertyTarget.visibility(layerID: layerID, animationLayerID: second)
        let targets: Set<SceneDynamicTarget> = [a, b]
        let launch = context(targets)
        let session = readySession(targets)
        var facts: [String: Bool] = [:]
        facts["all-targets-ready"] = session.observe(launch).isEmpty
        session.surfaces[9] = surface([a])
        facts["exact-missing-target"] = session.observe(launch) == [b]
        session.surfaces = [9: surface([a]), 4: surface(targets)]
        facts["surface-order-independent"] = session.observe(launch) == [b]
        session.surfaces = [4: surface([b]), 9: surface([a])]
        facts["missing-target-union"] = session.observe(launch) == targets
        let wrongParent = ScenePuppetAnimationPropertyTarget.visibility(
            layerID: layerID + 1, animationLayerID: second)
        session.surfaces = [4: surface(targets), 9: surface([a, wrongParent])]
        facts["parent-identity-required"] = session.observe(launch) == [b]
        let wrongAnimation = ScenePuppetAnimationPropertyTarget.visibility(
            layerID: layerID, animationLayerID: second + 1)
        session.surfaces[9] = surface([a, wrongAnimation])
        facts["animation-layer-identity-required"] = session.observe(launch) == [b]
        let wrongField = SceneDynamicTarget.scriptInstanceProperty(
            layerID: layerID, path: ["puppetAnimationLayer", String(second), "blend"])
        session.surfaces[9] = surface([a, wrongField])
        facts["visibility-path-required"] = session.observe(launch) == [b]
        session.surfaces = [4: surface(targets.union([wrongParent])), 9: surface(targets)]
        facts["unrelated-ready-target-not-reported"] = session.observe(launch).isEmpty
        let allTargets = targets.union([wrongParent])
        session.surfaces = [4: surface(allTargets), 9: surface(allTargets)]
        facts["destroyed-parent-unavailable-with-ready-surfaces"] = session.observe(
            context(allTargets, destroyed: [layerID])) == targets
        facts["animation-id-is-not-parent-retirement"] = session.observe(
            context(allTargets, destroyed: [first])).isEmpty
        facts["retirement-is-parent-local"] = session.observe(
            context(allTargets, destroyed: [layerID + 1])) == [wrongParent]
        session.surfaces[9] = surface(targets)
        facts["retired-and-missing-target-union"] = session.observe(
            context(allTargets, destroyed: [layerID])) == allTargets
        return facts
    }

    static func unchanged(_ state: ScenePropertyLiveUpdateState,
                          _ previous: ScenePropertyLiveUpdateState) -> Bool {
        state.effectiveValues == previous.effectiveValues
            && state.userValues == previous.userValues && state.revision == previous.revision
    }

    static func liveFacts(key: String, layerID: Int, first: Int, second: Int) -> [String: Bool] {
        let a = ScenePuppetAnimationPropertyTarget.visibility(layerID: layerID, animationLayerID: first)
        let b = ScenePuppetAnimationPropertyTarget.visibility(layerID: layerID, animationLayerID: second)
        let unrelated = SceneDynamicTarget.layer(layerID: layerID + 50, field: .alpha)
        let targets: Set<SceneDynamicTarget> = [a, b]
        let program = ScenePropertyBindingProgram(
            definitions: [
                .init(target: a, valueType: .bool, authoredValue: .bool(true)),
                .init(target: b, valueType: .bool, authoredValue: .bool(false)),
                .init(target: unrelated, valueType: .scalar, authoredValue: .scalar(1)),
            ], instructions: [
                .init(propertyKey: key, path: .init(components: [.key(key), .index(0)]),
                    target: a, valueType: .bool, condition: .string("first")),
                .init(propertyKey: key, path: .init(components: [.key(key), .index(1)]),
                    target: b, valueType: .bool, condition: .string("second")),
                .init(propertyKey: "opacity", path: .init(components: [.key("opacity")]),
                    target: unrelated, valueType: .scalar),
            ], conditionalValueDomainsByPropertyKey: [key: ["first", "second"]])
        let initialValues: [String: SceneUserPropertyValue] = [key: .string("first"), "opacity": .number(1)]
        var state = ScenePropertyLiveUpdateState(program: program, effectiveValues: initialValues,
            activeConsumerTargets: targets.union([unrelated]))
        let session = readySession(targets)
        let launch = context(targets)
        var facts: [String: Bool] = [:]
        facts["valid-program"] = ScenePropertyBindingProgramValidator().validate(program).diagnostics.isEmpty
        facts["initial-conditional-values"] = state.userValues[a] == .bool(true)
            && state.userValues[b] == .bool(false) && state.revision == 0
        facts["ready-switch"] = state.apply(.string("second"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch))
            && state.userValues[a] == .bool(false) && state.userValues[b] == .bool(true)
            && state.revision == 1
        facts["ready-return"] = state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch))
            && state.userValues[a] == .bool(true) && state.userValues[b] == .bool(false)
            && state.revision == 2

        session.surfaces[9] = surface([a])
        let beforeMissing = state
        facts["missing-target-whole-key-atomic"] = !state.apply(.string("second"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch)) && unchanged(state, beforeMissing)
        facts["missing-target-batch-atomic"] = !state.apply(
            replacements: [key: .string("second"), "opacity": .number(0.5)],
            changedPropertyKeys: [key, "opacity"], unavailableConsumerTargets: session.observe(launch))
            && unchanged(state, beforeMissing)
        facts["known-resend-stays-noop"] = state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch)) && unchanged(state, beforeMissing)
        facts["unrelated-key-remains-live"] = state.apply(.number(0.5), forPropertyKey: "opacity",
            unavailableConsumerTargets: session.observe(launch))
            && state.effectiveValues[key] == .string("first")
            && state.userValues[a] == .bool(true) && state.userValues[b] == .bool(false)
            && state.userValues[unrelated] == .scalar(0.5) && state.revision == 3

        session.surfaces[9] = surface(targets)
        facts["restored-surface-same-state-switches"] = state.apply(.string("second"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch))
            && state.userValues[a] == .bool(false) && state.userValues[b] == .bool(true)
            && state.revision == 4 && state.program == program
        session.surfaces[9] = surface([b])
        let beforeHiddenTarget = state
        facts["currently-false-target-still-required"] = !state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch)) && unchanged(state, beforeHiddenTarget)

        session.surfaces[9] = surface(targets, generation: 36)
        facts["stale-surface-whole-key-atomic"] = !state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch)) && unchanged(state, beforeHiddenTarget)
        session.surfaces.removeValue(forKey: 9)
        facts["missing-surface-whole-key-atomic"] = !state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(launch)) && unchanged(state, beforeHiddenTarget)

        session.surfaces[9] = surface(targets)
        var unregistered = ScenePropertyLiveUpdateState(program: program, effectiveValues: initialValues,
            activeConsumerTargets: [a, unrelated])
        let beforeUnregistered = unregistered
        facts["surface-ready-does-not-bypass-active-consumer"] = !unregistered.apply(
            .string("second"), forPropertyKey: key, unavailableConsumerTargets: session.observe(launch))
            && unchanged(unregistered, beforeUnregistered)
        let retired = context(targets, destroyed: [layerID])
        let beforeRetired = state
        facts["retired-targets-unavailable-despite-ready-surfaces"] = session.observe(retired) == targets
        facts["retired-parent-whole-key-atomic"] = !state.apply(.string("first"), forPropertyKey: key,
            unavailableConsumerTargets: session.observe(retired)) && unchanged(state, beforeRetired)
        facts["retired-parent-batch-atomic"] = !state.apply(
            replacements: [key: .string("first"), "opacity": .number(0.25)],
            changedPropertyKeys: [key, "opacity"], unavailableConsumerTargets: session.observe(retired))
            && unchanged(state, beforeRetired)
        facts["retired-parent-does-not-block-unrelated-key"] = state.apply(
            .number(0.25), forPropertyKey: "opacity", unavailableConsumerTargets: session.observe(retired))
            && state.effectiveValues[key] == .string("second")
            && state.userValues[a] == .bool(false) && state.userValues[b] == .bool(true)
            && state.userValues[unrelated] == .scalar(0.25) && state.revision == 5
        return facts
    }

    static func main() throws {
        let a = ScenePuppetAnimationPropertyTarget.visibility(layerID: 101, animationLayerID: 701)
        let b = ScenePuppetAnimationPropertyTarget.visibility(layerID: 101, animationLayerID: 709)
        let facts = [
            "surfaces": surfaceFacts(a, b),
            "targets": targetFacts(layerID: 101, first: 701, second: 709),
            "renamed-targets": targetFacts(layerID: 845, first: 12, second: 15),
            "live": liveFacts(key: "motion", layerID: 101, first: 701, second: 709),
            "renamed-live": liveFacts(key: "renamed_choice", layerID: 845, first: 12, second: 15),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self))
    }
}
'''


class SceneDirectModelAnimationLiveConsumersTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("Swift compiler required")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-direct-model-live-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        work = Path(cls.temporary_directory.name)
        harness = work / "Probe.swift"
        gate = method_body(SESSION_SOURCE.read_text(encoding="utf-8"),
                           "    private func unavailableDirectModelAnimationTargets(")
        harness.write_text(HARNESS.replace("    __PRODUCTION_GATE__", gate), encoding="utf-8")
        # The neighbouring module's retired-callback checks extend its own main.
        # Reuse its maintained production source set without that extra fixture.
        sources = [path for path in SWIFT_SOURCES
                   if path.name != "SceneRetiredCallbackLiveUpdateChecks.swift"]
        binary = work / "probe"
        build = subprocess.run(
            ["swiftc", "-swift-version", "5", "-parse-as-library", *map(str, sources),
             str(harness), "-module-cache-path", str(work / "cache"), "-o", str(binary)],
            capture_output=True, text=True, timeout=90,
        )
        if build.returncode:
            raise RuntimeError(f"Swift compilation failed ({build.returncode}):\n{build.stdout}{build.stderr}")
        run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise RuntimeError(f"CPU probe failed ({run.returncode}):\n{run.stdout}{run.stderr}")
        cls.facts = json.loads(run.stdout)

    def assert_facts(self, group: str, expected: tuple[str, ...]) -> None:
        self.assertEqual(set(self.facts[group]), set(expected))
        for name in expected:
            with self.subTest(group=group, fact=name):
                self.assertIs(self.facts[group][name], True)

    def test_all_prepared_surfaces_and_current_generation_are_required(self) -> None:
        self.assert_facts("surfaces", (
            "no-direct-candidates", "no-surfaces", "missing-surface", "extra-surface",
            "same-count-wrong-surface", "complete-surfaces", "stale-generation",
            "new-launch-old-surfaces", "matching-new-generation", "one-prepared-surface",
        ))

    def test_missing_targets_are_exact_and_unioned_across_surfaces(self) -> None:
        for group in ("targets", "renamed-targets"):
            self.assert_facts(group, (
                "all-targets-ready", "exact-missing-target", "surface-order-independent",
                "missing-target-union", "parent-identity-required",
                "animation-layer-identity-required", "visibility-path-required",
                "unrelated-ready-target-not-reported",
                "destroyed-parent-unavailable-with-ready-surfaces",
                "animation-id-is-not-parent-retirement", "retirement-is-parent-local",
                "retired-and-missing-target-union",
            ))

    def test_live_state_rejects_whole_key_and_recovers_without_rebuilding(self) -> None:
        for group in ("live", "renamed-live"):
            self.assert_facts(group, (
                "valid-program", "initial-conditional-values", "ready-switch", "ready-return",
                "missing-target-whole-key-atomic", "missing-target-batch-atomic",
                "known-resend-stays-noop", "unrelated-key-remains-live",
                "restored-surface-same-state-switches", "currently-false-target-still-required",
                "stale-surface-whole-key-atomic", "missing-surface-whole-key-atomic",
                "surface-ready-does-not-bypass-active-consumer",
                "retired-targets-unavailable-despite-ready-surfaces", "retired-parent-whole-key-atomic",
                "retired-parent-batch-atomic", "retired-parent-does-not-block-unrelated-key",
            ))


if __name__ == "__main__":
    unittest.main()
