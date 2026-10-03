#!/usr/bin/env python3
"""CPU behavior of accepted property intent while actual Session resources wait.

The Session extension and property validation execute unchanged. Controlled
resource and surface seams supply readiness/adoption events without Metal.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SESSION = SCENE / "Runtime/Session/SceneDesktopWallpaperSession.swift"
LIVE_CONSUMERS = SCENE / "Runtime/Session/SceneDesktopWallpaperSession+LiveConsumers.swift"
PROPERTY_SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Systems/Properties/SceneUserProperty.swift",
    SCENE / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SCENE / "Systems/Properties/SceneUserPropertyBindings.swift",
    SCENE / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE / "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgram.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SCENE / "Systems/Properties/ScenePropertyBindingProgramValidator.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
]


def declaration(source: str, signature: str) -> str:
    """Extract an unchanged production declaration for a bounded CPU shell."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth == 0:
            return source[start:index + 1]
    raise ValueError(f"unterminated production declaration: {signature}")


SHELL = r'''
import Foundation

enum SceneDeferredBaseImageStatus: Equatable {
    case notDeferred, pending, loading, ready
    case failed(String)
}

final class FixtureResources {
    let deferredLayerIDs: Set<Int> = [11, 22]
    var statuses: [Int: SceneDeferredBaseImageStatus] = [11: .pending, 22: .pending]
    var requests: [(layerID: Int, generation: UInt64)] = []

    @discardableResult
    func requestDeferredBaseImage(layerID: Int, requestGeneration: UInt64)
        -> SceneDeferredBaseImageStatus {
        requests.append((layerID, requestGeneration))
        return deferredStatus(for: layerID)
    }
    func deferredStatus(for layerID: Int) -> SceneDeferredBaseImageStatus {
        statuses[layerID] ?? .notDeferred
    }
}

final class FixtureAdoption {
    var successfulCalls = 0
    var failAfterSuccessfulCalls: Int?

    func accept() -> Bool {
        if let limit = failAfterSuccessfulCalls, successfulCalls >= limit { return false }
        successfulCalls += 1
        return true
    }
}

final class FixtureView {
    let adoption: FixtureAdoption
    var staged: Set<Int> = []
    var committed: Set<Int> = []
    var attempts = 0
    var discards = 0
    var commits = 0

    init(_ adoption: FixtureAdoption) { self.adoption = adoption }
    func adoptPreparedDeferredBaseImage(layerID: Int) -> Bool {
        attempts += 1
        guard adoption.accept() else { return false }
        staged.insert(layerID)
        return true
    }
    func discardPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        discards += 1
        staged.subtract(layerIDs)
    }
    func commitPreparedDeferredBaseImages(layerIDs: Set<Int>) {
        commits += 1
        committed.formUnion(layerIDs)
        staged.subtract(layerIDs)
    }
}

final class FixtureSound {
    var accepts = true
    var applies = 0
    func canApply(userValues: [SceneDynamicTarget: SceneDynamicValue]) -> Bool { accepts }
    func apply(userValues: [SceneDynamicTarget: SceneDynamicValue]) { applies += 1 }
}

struct FixtureRuntimeInput { let propertyBindingProgram: ScenePropertyBindingProgram }
struct FixtureDeviceResources { let baseImages: FixtureResources }
struct SceneDesktopWallpaperLaunchContext {
    let recordID: String?
    var liveState: ScenePropertyLiveUpdateState
    let runtimeInput: FixtureRuntimeInput
    let preparedDeviceResources: FixtureDeviceResources
    var unavailable: Set<SceneDynamicTarget> = []
}

enum SceneDesktopWallpaperHost {
    static let usesDebugEvidenceWindow = false
    static func unavailableLiveScriptPropertyTargets(
        in context: SceneDesktopWallpaperLaunchContext
    ) -> Set<SceneDynamicTarget> { context.unavailable }
}

final class SceneDesktopWallpaperSession {
    struct Surface { let metalView: FixtureView }
    var launchContext: SceneDesktopWallpaperLaunchContext?
    var surfaces: [Int: Surface] = [:]
    var soundPlaybackRegistry: FixtureSound? = FixtureSound()
    var nextDeferredPropertyGeneration: UInt64 = 0
    var pendingDeferredLayerVisibilityUpdate: PendingDeferredLayerVisibilityUpdate?
    init(_ context: SceneDesktopWallpaperLaunchContext) { launchContext = context }
'''

HARNESS = r'''
import Foundation

@main enum Harness {
    static let a = SceneDynamicTarget.layer(layerID: 11, field: .visibility)
    static let b = SceneDynamicTarget.layer(layerID: 22, field: .visibility)
    static let level = SceneDynamicTarget.layer(layerID: 33, field: .alpha)
    static let optional = SceneDynamicTarget.scriptInstanceProperty(
        layerID: 44, path: ["optional"])

    static func make() -> (SceneDesktopWallpaperSession, FixtureResources, FixtureAdoption) {
        let program = ScenePropertyBindingProgram(
            definitions: [
                .init(target: a, valueType: .bool, authoredValue: .bool(false)),
                .init(target: b, valueType: .bool, authoredValue: .bool(false)),
                .init(target: level, valueType: .scalar, authoredValue: .scalar(0.2)),
            ],
            instructions: [
                .init(propertyKey: "A", path: .init(components: [.key("A")]),
                    target: a, valueType: .bool, condition: .string("on")),
                .init(propertyKey: "B", path: .init(components: [.key("B")]),
                    target: b, valueType: .bool, condition: .string("on")),
                .init(propertyKey: "level", path: .init(components: [.key("level")]),
                    target: level, valueType: .scalar),
            ],
            conditionalValueDomainsByPropertyKey: ["A": ["off", "on"], "B": ["off", "on"]]
        )
        let state = ScenePropertyLiveUpdateState(
            program: program,
            effectiveValues: ["A": .string("off"), "B": .string("off"),
                "level": .number(0.2), "optional": .string("seed")],
            activeConsumerTargets: [a, b, level, optional],
            scriptUserPropertyConsumerTargetsByKey: ["optional": [optional]]
        )
        let resources = FixtureResources()
        let adoption = FixtureAdoption()
        let session = SceneDesktopWallpaperSession(.init(recordID: "own-input",
            liveState: state, runtimeInput: .init(propertyBindingProgram: program),
            preparedDeviceResources: .init(baseImages: resources)))
        installSurfaces(session, adoption)
        return (session, resources, adoption)
    }

    static func installSurfaces(_ session: SceneDesktopWallpaperSession,
                                _ adoption: FixtureAdoption) {
        session.surfaces = [1: .init(metalView: FixtureView(adoption)),
                           2: .init(metalView: FixtureView(adoption))]
    }

    static func apply(_ session: SceneDesktopWallpaperSession,
                      _ values: [String: SceneUserPropertyValue],
                      keys: Set<String>? = nil) -> Bool {
        session.applyUserPropertyValues(values,
            changedPropertyKeys: keys ?? Set(values.keys), recordID: "own-input")
    }

    static func snapshot(_ session: SceneDesktopWallpaperSession,
                         _ resources: FixtureResources) -> [String: Any] {
        let state = session.launchContext!.liveState
        func boolean(_ target: SceneDynamicTarget) -> Bool {
            guard case let .bool(value)? = state.userValues[target] else { return false }
            return value
        }
        let levelValue: Double
        if case let .scalar(value)? = state.userValues[level] { levelValue = value }
        else { levelValue = -1 }
        let optionalValue: Any
        if case let .string(value)? = state.effectiveValues["optional"] { optionalValue = value }
        else { optionalValue = NSNull() }
        let pending: Any
        if let value = session.pendingDeferredLayerVisibilityUpdate {
            pending = ["generation": value.generation,
                "keys": value.changedPropertyKeys.sorted(),
                "layers": value.layerIDs.sorted()] as [String: Any]
        } else { pending = NSNull() }
        let views = session.surfaces.keys.sorted().map { id -> [String: Any] in
            let view = session.surfaces[id]!.metalView
            return ["id": id, "staged": view.staged.sorted(),
                "committed": view.committed.sorted(), "attempts": view.attempts,
                "discards": view.discards, "commits": view.commits]
        }
        return ["visible": [boolean(a), boolean(b)], "level": levelValue,
            "optional": optionalValue, "pending": pending, "views": views,
            "requests": resources.requests.map { [Int($0.layerID), Int($0.generation)] },
            "soundApplies": session.soundPlaybackRegistry?.applies ?? 0]
    }

    static func main() throws {
        var output: [String: Any] = [:]
        do {
            let (session, resources, _) = make()
            let first = apply(session, ["A": .string("on")])
            let second = apply(session, ["B": .string("on")])
            let waiting = snapshot(session, resources)
            resources.statuses[11] = .ready
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["independent"] = ["accepted": [first, second],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let bulk = apply(session, ["A": .string("on"), "B": .string("on")])
            let cancel = apply(session, ["A": .string("off")])
            let waiting = snapshot(session, resources)
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["partialCancellation"] = ["accepted": [bulk, cancel],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let hide = apply(session, ["A": .string("off")])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["sameKeyCancellation"] = ["accepted": [show, hide],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let before = snapshot(session, resources)
            let invalid = apply(session, ["B": .bool(true)])
            let after = snapshot(session, resources)
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["invalidUpdate"] = ["accepted": [show, invalid],
                "before": before, "after": after, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on"), "optional": .string("pending")])
            let remove = apply(session, [:], keys: ["optional"])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["removal"] = ["accepted": [show, remove],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, adoption) = make()
            let accepted = apply(session, ["A": .string("on"), "B": .string("on")])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            let oneReady = snapshot(session, resources)
            session.surfaces = [:]
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            let noSurface = snapshot(session, resources)
            installSurfaces(session, adoption)
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["readiness"] = ["accepted": accepted, "oneReady": oneReady,
                "noSurface": noSurface, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, adoption) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .ready
            adoption.failAfterSuccessfulCalls = 1
            session.promotePendingDeferredLayerVisibilityIfReady()
            let rolledBack = snapshot(session, resources)
            adoption.failAfterSuccessfulCalls = nil
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["adoptionRollback"] = ["accepted": accepted,
                "rolledBack": rolledBack, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .ready
            session.launchContext!.unavailable = [a]
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["validationRollback"] = ["accepted": accepted,
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .failed("own-controlled-load-failure")
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["resourceFailure"] = ["accepted": accepted,
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let level = apply(session, ["level": .number(0.7)])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["disjointValue"] = ["accepted": [show, level],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let level = apply(session, ["level": .number(0.7)])
            let waiting = snapshot(session, resources)
            resources.statuses[11] = .failed("own-controlled-load-failure")
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["disjointFailure"] = ["accepted": [show, level],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneDeferredPropertyIntentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-deferred-property-intent-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        session = SESSION.read_text(encoding="utf-8")
        owner_source = Path(os.environ.get(
            "MWX_SCENE_DEFERRED_PROPERTY_OWNER_SOURCE", str(LIVE_CONSUMERS)))
        extension = owner_source.read_text(encoding="utf-8")
        pending = declaration(session, "struct PendingDeferredLayerVisibilityUpdate {")
        shell = directory / "SessionShell.swift"
        shell.write_text(SHELL + "\n" + pending + "\n}\n", encoding="utf-8")
        # The pre-fix owner may still contain apply. This assembles that exact
        # method without copying its algorithm into the test's fixture.
        if "func applyUserPropertyValues(" not in extension:
            extension += "\nextension SceneDesktopWallpaperSession {\n"
            extension += declaration(session, "func applyUserPropertyValues(")
            extension += "\n}\n"
        owner = directory / "SessionLiveConsumers.swift"
        owner.write_text(extension, encoding="utf-8")
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "deferred-property-intent"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in PROPERTY_SOURCES),
             str(shell), str(owner), str(harness), "-module-cache-path",
             str(directory / "module-cache"), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True, timeout=30,
        )
        cls.result = json.loads(completed.stdout)

    def assert_committed(self, value: dict, visible: list[bool], layers: list[int]) -> None:
        self.assertEqual(value["visible"], visible)
        self.assertIsNone(value["pending"])
        self.assertEqual(len(value["views"]), 2)
        for view in value["views"]:
            self.assertEqual(view["committed"], layers)
            self.assertEqual(view["staged"], [])

    def test_independent_accepted_commands_both_commit(self) -> None:
        result = self.result["independent"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["pending"]["layers"], [11, 22])
        requests = result["waiting"]["requests"]
        newest = max(generation for _, generation in requests)
        self.assertEqual(sorted(layer for layer, generation in requests if generation == newest), [11, 22])
        self.assert_committed(result["final"], [True, True], [11, 22])

    def test_partial_bulk_cancellation_keeps_the_other_accepted_key(self) -> None:
        result = self.result["partialCancellation"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["pending"]["layers"], [22])
        self.assert_committed(result["final"], [False, True], [22])

    def test_same_key_latest_hide_cancels_show(self) -> None:
        result = self.result["sameKeyCancellation"]
        self.assertEqual(result["accepted"], [True, True])
        self.assert_committed(result["final"], [False, False], [])
        self.assertTrue(all(view["attempts"] == 0 for view in result["final"]["views"]))

    def test_invalid_update_does_not_erase_accepted_pending_intent(self) -> None:
        result = self.result["invalidUpdate"]
        self.assertEqual(result["accepted"], [True, False])
        self.assertEqual(result["after"], result["before"])
        self.assert_committed(result["final"], [True, False], [11])

    def test_latest_removal_survives_pending_merge(self) -> None:
        result = self.result["removal"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertIsNone(result["final"]["optional"])
        self.assert_committed(result["final"], [True, False], [11])

    def test_every_resource_and_a_surface_are_required_before_publication(self) -> None:
        result = self.result["readiness"]
        self.assertTrue(result["accepted"])
        self.assertEqual(result["oneReady"]["visible"], [False, False])
        self.assertIsNotNone(result["oneReady"]["pending"])
        self.assertTrue(all(view["attempts"] == 0 for view in result["oneReady"]["views"]))
        self.assertEqual(result["noSurface"]["visible"], [False, False])
        self.assertIsNotNone(result["noSurface"]["pending"])
        self.assertEqual(result["noSurface"]["views"], [])
        self.assert_committed(result["final"], [True, True], [11, 22])

    def test_partial_surface_adoption_rolls_back_and_retry_commits_all(self) -> None:
        result = self.result["adoptionRollback"]
        self.assertTrue(result["accepted"])
        before = result["rolledBack"]
        self.assertEqual(before["visible"], [False, False])
        self.assertIsNotNone(before["pending"])
        self.assertEqual(before["soundApplies"], 0)
        self.assertEqual(sum(view["attempts"] for view in before["views"]), 2)
        for view in before["views"]:
            self.assertEqual(view["staged"], [])
            self.assertEqual(view["committed"], [])
            self.assertEqual(view["discards"], 1)
        self.assert_committed(result["final"], [True, False], [11])
        self.assertEqual(result["final"]["soundApplies"], 1)

    def test_late_validation_failure_releases_adoptions_without_publication(self) -> None:
        result = self.result["validationRollback"]
        self.assertTrue(result["accepted"])
        self.assert_committed(result["final"], [False, False], [])
        self.assertEqual(result["final"]["soundApplies"], 0)
        self.assertTrue(all(view["discards"] == 1 for view in result["final"]["views"]))

    def test_failed_resource_preserves_previous_display(self) -> None:
        result = self.result["resourceFailure"]
        self.assertTrue(result["accepted"])
        self.assert_committed(result["final"], [False, False], [])
        self.assertTrue(all(view["attempts"] == 0 for view in result["final"]["views"]))

    def test_disjoint_value_update_survives_later_visibility_commit(self) -> None:
        result = self.result["disjointValue"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["final"]["level"], 0.7)
        self.assert_committed(result["final"], [True, False], [11])

    def test_independent_ready_value_survives_other_resource_failure(self) -> None:
        result = self.result["disjointFailure"]
        self.assertEqual(result["accepted"], [True, True])
        self.assertEqual(result["waiting"]["visible"], [False, False])
        self.assertEqual(result["waiting"]["level"], 0.7)
        self.assertEqual(result["final"]["level"], 0.7)
        self.assert_committed(result["final"], [False, False], [])


if __name__ == "__main__":
    unittest.main()
