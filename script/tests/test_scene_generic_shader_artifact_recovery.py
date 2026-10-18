#!/usr/bin/env python3
"""Exercise the product artifact reader, validation, and bounded repair owner.

The compiler closure publishes controlled bytes so faults and invocation counts
are deterministic. Signed helper compilation and GPU startup are separate gates.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene_generic_shader_test_support import generic_color_program_artifact
from script.tests.test_scene_generic_shader_program_artifact import (
    REPOSITORY_ROOT,
    SWIFT_SOURCES,
)


KEY = "a" * 64
HARNESS = r"""
import Foundation

private typealias Cache = SceneResolvedMaterialGenericShaderArtifactCache

private final class State: @unchecked Sendable {
    let lock = NSLock()
    var compilations = 0
    var accepted = 0
    var failures: [String] = []
    var validations = 0

    func result(_ value: Result<SceneAuthoredShaderProgram, Cache.ProgramLoadFailure>) {
        lock.withLock {
            switch value {
            case .success: accepted += 1
            case let .failure(failure): failures.append(failure.code)
            }
        }
    }
}

private func validate(_ data: Data) ->
    Result<SceneAuthoredShaderProgram, Cache.ProgramLoadFailure>
{
    let artifact: SceneGenericShaderProgramArtifact
    do { artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: data) }
    catch { return .failure(.invalidJSON) }
    guard let program = artifact.makeProgram(
        expectedKey: String(repeating: "a", count: 64),
        expectedOutputSemantics: .color,
        expectedPremultipliedColorInputSlots: [],
        expectedColorBoundary: nil,
        expectedColorTransfer: .straightAlpha(textureSlot: 0),
        expectedFragmentOutputChannelUse: .unproven
    ) else { return .failure(.contractRejected) }
    return .success(program)
}

@main
private struct ArtifactRecoveryHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let key = String(repeating: "a", count: 64)
        let artifactURL = root.appendingPathComponent("\(key).json")
        let validData = try Data(contentsOf: root.appendingPathComponent("valid.json"))
        let state = State()
        let coordinator = SceneResolvedMaterialGenericShaderCompilationCoordinator()
        let ownerStarted = DispatchSemaphore(value: 0)
        let releaseOwner = DispatchSemaphore(value: 0)

        func attempt(publication: String = "valid", slow: Bool = false) {
            let result = Cache.loadOrCompileProgram(
                artifactURL: artifactURL, requestKey: key, coordinator: coordinator,
                validate: { data in
                    let count = state.lock.withLock {
                        state.validations += 1
                        return state.validations
                    }
                    // A second process repairs the old file after its first
                    // rejection, before this caller enters the compiler flight.
                    if mode == "repair-race", count == 1 {
                        do { try validData.write(to: artifactURL, options: [.atomic]) }
                        catch { return .failure(.publicationMissing) }
                        return .failure(.invalidJSON)
                    }
                    return validate(data)
                },
                compile: {
                    state.lock.withLock { state.compilations += 1 }
                    if slow {
                        ownerStarted.signal()
                        guard releaseOwner.wait(timeout: .now() + 10) == .success else {
                            return .failure(.workspace)
                        }
                    }
                    if publication == "failure" { return .failure(.workspace) }
                    if publication == "missing" { return .success(artifactURL) }
                    let data = publication == "invalid" ? Data("bad publication".utf8) : validData
                    do { try data.write(to: artifactURL, options: [.atomic]) }
                    catch { return .failure(.publication) }
                    return .success(artifactURL)
                }
            )
            state.result(result)
        }

        var allJoined = true
        var allCompleted = true
        switch mode {
        case "concurrent", "concurrent-bad-publication":
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                attempt(publication: mode == "concurrent" ? "valid" : "invalid", slow: true)
                group.leave()
            }
            let started = ownerStarted.wait(timeout: .now() + 10) == .success
            if started {
                for _ in 1 ..< 8 {
                    group.enter()
                    DispatchQueue.global().async { attempt(); group.leave() }
                }
            }
            let deadline = Date().addingTimeInterval(10)
            while coordinator.snapshot.waitingCallers < 7, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            allJoined = started && coordinator.snapshot.waitingCallers == 7
            releaseOwner.signal()
            allCompleted = group.wait(timeout: .now() + 10) == .success
            if mode == "concurrent-bad-publication", allCompleted { attempt() }
        case "sequence":
            attempt() // cold
            attempt() // valid warm entry
            try FileManager.default.removeItem(at: artifactURL)
            attempt() // completed URL cannot hide deletion
            try Data("corrupt after success".utf8).write(to: artifactURL, options: [.atomic])
            attempt() // completed URL cannot hide corruption
        case "bad-publication":
            attempt(publication: "invalid")
            attempt() // later request may retry a repaired compiler
        case "compiler-failure":
            attempt(publication: "failure")
            attempt()
        case "missing-publication": attempt(publication: "missing")
        default: attempt()
        }
        let output: [String: Any] = [
            "compilations": state.compilations, "accepted": state.accepted,
            "failures": state.failures, "validations": state.validations,
            "allJoined": allJoined, "allCompleted": allCompleted,
            "retainedCompilerResults": coordinator.snapshot.completedEntries,
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
    }
}
"""


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is unavailable")
class SceneGenericShaderArtifactRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-artifact-recovery-")
        root = Path(cls.directory.name)
        harness = root / "ArtifactRecoveryHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        # Standalone harnesses carry the same build-produced identity contract.
        (root / "SceneShaderCacheIdentity.json").write_text(json.dumps({
            "schemaVersion": 1, "semantics": "1" * 64, "toolchain": "2" * 64,
        }), encoding="utf-8")
        cls.binary = root / "artifact-recovery"
        # Other lanes may edit live Swift inputs. Compile one verified frozen
        # source set so such edits cannot turn a repair result into build drift.
        fingerprints = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in SWIFT_SOURCES}
        sources = []
        for path in SWIFT_SOURCES:
            target = root / "source" / path.relative_to(REPOSITORY_ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            if hashlib.sha256(target.read_bytes()).hexdigest() != fingerprints[path]:
                cls.directory.cleanup()
                raise AssertionError(f"source changed while freezing: {path}")
            sources.append(target)
        if any(hashlib.sha256(path.read_bytes()).hexdigest() != digest for path, digest in fingerprints.items()):
            cls.directory.cleanup()
            raise AssertionError("source changed while freezing artifact recovery inputs")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        result = subprocess.run([
            shutil.which("swiftc"), "-parse-as-library",
            *(str(path) for path in sources), str(harness),
            "-framework", "Security", "-o", str(cls.binary),
        ], cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True)
        if result.returncode:
            cls.directory.cleanup()
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_case(self, mode="resolve", initial=None, *, entry_kind="file"):
        with tempfile.TemporaryDirectory(prefix="mwx-artifact-case-") as directory:
            root = Path(directory)
            valid = generic_color_program_artifact(KEY)
            (root / "valid.json").write_text(json.dumps(valid), encoding="utf-8")
            path = root / f"{KEY}.json"
            victim = root / "unrelated.txt"
            if entry_kind == "symlink":
                victim.write_text("preserve symlink target", encoding="utf-8")
                path.symlink_to(victim)
            elif entry_kind == "directory":
                path.mkdir()
                (path / "unrelated.txt").write_text("preserve directory child", encoding="utf-8")
            elif entry_kind == "oversized":
                path.write_bytes(b"x" * (2 * 1024 * 1024 + 1))
            elif isinstance(initial, dict):
                path.write_text(json.dumps(initial), encoding="utf-8")
            elif initial is not None:
                path.write_bytes(initial)
            result = subprocess.run([str(self.binary), str(root), mode],
                cwd=REPOSITORY_ROOT, capture_output=True, text=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            output["artifact"] = json.loads(path.read_text()) if path.is_file() and mode != "missing-publication" else None
            output["symlinkRemains"] = path.is_symlink()
            output["victim"] = victim.read_text() if victim.exists() else None
            output["directoryChild"] = (path / "unrelated.txt").read_text() if path.is_dir() else None
            return output

    def test_valid_warm_entry_does_not_start_compiler(self):
        output = self.run_case(initial=generic_color_program_artifact(KEY))
        self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (1, 0, 1), output)

    def test_missing_invalid_json_empty_and_contract_rejections_rebuild_once(self):
        stale = generic_color_program_artifact(KEY)
        stale["schemaVersion"] -= 1
        wrong_key = generic_color_program_artifact("b" * 64)
        tampered = copy.deepcopy(generic_color_program_artifact(KEY))
        tampered["program"]["metalSource"] += "\n// changed without digest"
        wrong_abi = generic_color_program_artifact(KEY)
        wrong_abi["program"]["uniformBufferIndex"] = 3
        for initial in (None, b"", b"{broken", stale, wrong_key, tampered, wrong_abi):
            with self.subTest(initial=initial):
                output = self.run_case(initial=initial)
                self.assertEqual((output["accepted"], output["compilations"], output["failures"]), (1, 1, []), output)
                self.assertEqual(output["artifact"], generic_color_program_artifact(KEY))

    def test_repaired_entry_is_rechecked_before_compiling(self):
        output = self.run_case("repair-race", initial=b"broken")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 0), output)

    def test_symlink_target_is_preserved_and_entry_is_atomically_replaced(self):
        output = self.run_case(entry_kind="symlink")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 1), output)
        self.assertFalse(output["symlinkRemains"], output)
        self.assertEqual(output["victim"], "preserve symlink target", output)

    def test_oversized_entry_is_not_loaded_and_is_replaced(self):
        output = self.run_case(entry_kind="oversized")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 1), output)

    def test_directory_entry_is_not_recursively_deleted_for_repair(self):
        output = self.run_case(entry_kind="directory")
        self.assertEqual((output["accepted"], output["compilations"]), (0, 1), output)
        self.assertEqual(output["failures"], ["compiler-publication"], output)
        self.assertEqual(output["directoryChild"], "preserve directory child", output)

    def test_deleted_or_damaged_successful_entry_is_rebuilt(self):
        output = self.run_case("sequence")
        self.assertEqual((output["accepted"], output["compilations"]), (4, 3), output)
        self.assertEqual(output["retainedCompilerResults"], 0, output)

    def test_bad_publication_is_bounded_and_later_request_can_retry(self):
        output = self.run_case("bad-publication")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["artifact-invalid-json"], output)

    def test_compiler_failure_is_local_and_later_request_can_retry(self):
        output = self.run_case("compiler-failure")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["compiler-workspace"], output)

    def test_missing_publication_does_not_retry_in_the_same_request(self):
        output = self.run_case("missing-publication")
        self.assertEqual((output["accepted"], output["compilations"]), (0, 1), output)
        self.assertEqual(output["failures"], ["compiler-publication-missing"], output)

    def test_concurrent_invalid_entry_has_one_rebuild(self):
        output = self.run_case("concurrent", initial=b"broken")
        self.assertTrue(output["allJoined"] and output["allCompleted"], output)
        self.assertEqual((output["accepted"], output["compilations"]), (8, 1), output)

    def test_bad_publication_is_shared_with_waiters_but_never_retained(self):
        output = self.run_case("concurrent-bad-publication", initial=b"broken")
        self.assertTrue(output["allJoined"] and output["allCompleted"], output)
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["artifact-invalid-json"] * 8, output)
        self.assertEqual(output["retainedCompilerResults"], 0, output)


if __name__ == "__main__":
    unittest.main()
