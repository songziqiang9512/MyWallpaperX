#!/usr/bin/env python3
"""Exercise the product artifact reader, validation, and bounded repair owner.

The compiler closure returns controlled typed artifacts so faults and counts
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
    var acceptedOutputChannels: [String] = []
    var acceptedMetalBytes: [Int] = []

    func result(_ value: Result<SceneAuthoredShaderProgram, Cache.ProgramLoadFailure>) {
        lock.withLock {
            switch value {
            case let .success(program):
                accepted += 1
                acceptedOutputChannels.append(program.fragmentOutputChannelUse.rawValue)
                acceptedMetalBytes.append(program.metalSource.utf8.count)
            case let .failure(failure): failures.append(failure.code)
            }
        }
    }
}

private func validate(
    _ artifact: SceneGenericShaderProgramArtifact,
    expectedColorTransfer: SceneShaderColorTransfer = .straightAlpha(textureSlot: 0),
    expectedOutputChannelUse: SceneAuthoredShaderProgram.FragmentOutputChannelUse = .unproven
) -> SceneAuthoredShaderProgram? {
    artifact.makeProgram(
        expectedKey: String(repeating: "a", count: 64),
        expectedOutputSemantics: .color,
        expectedPremultipliedColorInputSlots: [],
        expectedColorBoundary: nil,
        expectedColorTransfer: expectedColorTransfer,
        expectedFragmentOutputChannelUse: expectedOutputChannelUse
    )
}

@main
private struct ArtifactRecoveryHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let key = String(repeating: "a", count: 64)
        let cache = ["cache-parent-file", "cache-unwritable"].contains(mode)
            ? root.appendingPathComponent("cache", isDirectory: true) : root
        let artifactURL = cache.appendingPathComponent("\(key).json")
        let validData = try Data(contentsOf: root.appendingPathComponent("valid.json"))
        let valid = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: validData)
        let rejectedData = try Data(contentsOf: root.appendingPathComponent("rejected.json"))
        let rejected = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: rejectedData)
        let state = State()
        let coordinator = SceneResolvedMaterialGenericShaderCompilationCoordinator()
        let ownerStarted = DispatchSemaphore(value: 0)
        let releaseOwner = DispatchSemaphore(value: 0)

        func attempt(
            compilation: String = "valid", slow: Bool = false,
            expectedColorTransfer: SceneShaderColorTransfer = .straightAlpha(textureSlot: 0),
            expectedOutputChannelUse: SceneAuthoredShaderProgram.FragmentOutputChannelUse = .unproven
        ) {
            let result = Cache.loadOrCompileProgram(
                artifactURL: mode == "without-cache" ? nil : artifactURL,
                key: .init(requestKey: key, outputSemantics: .color,
                    premultipliedColorInputSlots: [], colorBoundary: nil,
                    colorTransfer: expectedColorTransfer,
                    fragmentOutputChannelUse: expectedOutputChannelUse),
                coordinator: coordinator,
                validate: { artifact in
                    let count = state.lock.withLock {
                        state.validations += 1
                        return state.validations
                    }
                    let program = validate(artifact, expectedColorTransfer: expectedColorTransfer,
                        expectedOutputChannelUse: expectedOutputChannelUse)
                    // Another writer repairs a rejected entry before the flight recheck.
                    if mode == "repair-race", count == 1 {
                        if program == nil { try? validData.write(to: artifactURL, options: [.atomic]) }
                        return nil
                    }
                    // The accepted immutable Program remains usable if the
                    // optional file disappears before this flight returns.
                    if mode == "accepted-file-removed", program != nil {
                        try? FileManager.default.removeItem(at: artifactURL)
                    }
                    return program
                },
                compile: {
                    state.lock.withLock { state.compilations += 1 }
                    if slow {
                        ownerStarted.signal()
                        guard releaseOwner.wait(timeout: .now() + 10) == .success else {
                            return .failure(.workspace)
                        }
                    }
                    if compilation == "failure" { return .failure(.workspace) }
                    return compilation == "rejected"
                        ? .success((artifact: rejected, encodedData: rejectedData))
                        : .success((artifact: valid, encodedData: validData))
                }
            )
            state.result(result)
        }

        func waitForPublication() -> Bool {
            let deadline = Date().addingTimeInterval(10)
            repeat {
                if let data = try? Data(contentsOf: artifactURL), data == validData { return true }
                Thread.sleep(forTimeInterval: 0.001)
            } while Date() < deadline
            return false
        }

        var allJoined = true
        var allCompleted = true
        var isolatedContracts = true
        switch mode {
        case "contracts-positive-first", "contracts-negative-first",
             "channels-unproven-first", "channels-red-first":
            let channelCase = mode.hasPrefix("channels-")
            let positiveFirst = mode == "contracts-positive-first"
            let first: SceneShaderColorTransfer = channelCase || positiveFirst ? .straightAlpha(textureSlot: 0) : .opaque
            let second: SceneShaderColorTransfer = channelCase || !positiveFirst ? .straightAlpha(textureSlot: 0) : .opaque
            let firstChannel: SceneAuthoredShaderProgram.FragmentOutputChannelUse =
                mode == "channels-red-first" ? .redDefined : .unproven
            let secondChannel: SceneAuthoredShaderProgram.FragmentOutputChannelUse =
                mode == "channels-unproven-first" ? .redDefined : .unproven
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                attempt(slow: true, expectedColorTransfer: first, expectedOutputChannelUse: firstChannel)
                group.leave()
            }
            let started = ownerStarted.wait(timeout: .now() + 10) == .success
            if started {
                group.enter()
                DispatchQueue.global().async {
                    attempt(expectedColorTransfer: second, expectedOutputChannelUse: secondChannel)
                    group.leave()
                }
            }
            let deadline = Date().addingTimeInterval(10)
            while state.lock.withLock({ state.compilations }) < 2,
                  coordinator.snapshot.waitingCallers == 0, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            isolatedContracts = started && state.lock.withLock({ state.compilations == 2 })
                && coordinator.snapshot.waitingCallers == 0
            releaseOwner.signal()
            allCompleted = group.wait(timeout: .now() + 10) == .success
        case "concurrent", "concurrent-bad-contract":
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                attempt(compilation: mode == "concurrent" ? "valid" : "rejected", slow: true)
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
            if mode == "concurrent-bad-contract", allCompleted { attempt() }
        case "sequence":
            attempt() // cold
            guard waitForPublication() else { throw NSError(domain: "cold-publication", code: 1) }
            attempt() // valid warm entry
            try FileManager.default.removeItem(at: artifactURL)
            attempt() // completed flight cannot hide deletion
            guard waitForPublication() else { throw NSError(domain: "rebuilt-publication", code: 1) }
            try Data("corrupt after success".utf8).write(to: artifactURL, options: [.atomic])
            attempt() // completed flight cannot hide corruption
        case "bad-contract":
            attempt(compilation: "rejected")
            attempt() // later request may retry a repaired compiler
        case "compiler-failure":
            attempt(compilation: "failure")
            attempt()
        case "rejected-contract": attempt(compilation: "rejected")
        default: attempt()
        }
        let publicationObserved = CommandLine.arguments[3] == "wait" && waitForPublication()
        let output: [String: Any] = [
            "compilations": state.compilations, "accepted": state.accepted,
            "failures": state.failures, "validations": state.validations,
            "allJoined": allJoined, "allCompleted": allCompleted,
            "isolatedContracts": isolatedContracts,
            "acceptedOutputChannels": state.acceptedOutputChannels,
            "acceptedMetalBytes": state.acceptedMetalBytes,
            "publicationObserved": publicationObserved,
            "optionalFileExists": FileManager.default.fileExists(atPath: artifactURL.path),
            "compiledArtifactBytes": validData.count,
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

    def run_case(self, mode="resolve", initial=None, *, entry_kind="file", compiled=None, rejected=None):
        with tempfile.TemporaryDirectory(prefix="mwx-artifact-case-") as directory:
            root = Path(directory)
            valid = compiled or generic_color_program_artifact(KEY)
            (root / "valid.json").write_text(json.dumps(valid), encoding="utf-8")
            (root / "rejected.json").write_text(json.dumps(
                rejected or generic_color_program_artifact("b" * 64)), encoding="utf-8")
            cache = root
            if mode == "cache-parent-file":
                cache = root / "cache"
                cache.write_text("preserve cache path file", encoding="utf-8")
            elif mode == "cache-unwritable":
                cache = root / "cache"
                cache.mkdir(mode=0o500)
                if os.access(cache, os.W_OK):
                    self.skipTest("this user can write through the cache directory permissions")
            path = cache / f"{KEY}.json"
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
            can_publish = entry_kind != "directory" and mode not in {
                "cache-parent-file", "cache-unwritable", "without-cache",
                "large-artifact", "rejected-contract", "accepted-file-removed",
            }
            result = subprocess.run([str(self.binary), str(root), mode,
                "wait" if can_publish else "no-wait"],
                cwd=REPOSITORY_ROOT, capture_output=True, text=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            if can_publish:
                self.assertTrue(output["publicationObserved"], output)
            output["artifact"] = json.loads(path.read_text()) if output["publicationObserved"] else None
            output["symlinkRemains"] = path.is_symlink()
            output["victim"] = victim.read_text() if victim.exists() else None
            output["directoryChild"] = (path / "unrelated.txt").read_text() if path.is_dir() else None
            output["cachePathFile"] = cache.read_text() if cache.is_file() else None
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
        output = self.run_case("repair-race", initial=generic_color_program_artifact("b" * 64))
        self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (1, 0, 2), output)

    def test_warm_program_does_not_reopen_the_optional_file_after_validation(self):
        output = self.run_case("accepted-file-removed", initial=generic_color_program_artifact(KEY))
        self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (1, 0, 1), output)
        self.assertFalse(output["optionalFileExists"], output)

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
        self.assertEqual((output["accepted"], output["compilations"]), (1, 1), output)
        self.assertEqual(output["failures"], [], output)
        self.assertEqual(output["directoryChild"], "preserve directory child", output)

    def test_absent_or_unusable_optional_cache_does_not_revoke_the_program(self):
        for mode in ("without-cache", "cache-parent-file", "cache-unwritable"):
            with self.subTest(mode=mode):
                output = self.run_case(mode)
                self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (1, 1, 1), output)
                self.assertEqual(output["failures"], [], output)
                self.assertFalse(output["optionalFileExists"], output)
                if mode == "cache-parent-file":
                    self.assertEqual(output["cachePathFile"], "preserve cache path file", output)

    def test_legal_large_encoded_artifact_is_adopted_without_cache_publication(self):
        artifact = generic_color_program_artifact(KEY)
        # Vertical tabs are C/Metal whitespace; JSON expands each one to six bytes.
        metal = artifact["program"]["metalSource"] + "\n/*" + "\v" * 400_000 + "*/\n"
        digest = hashlib.sha256(metal.encode()).hexdigest()
        artifact["program"].update(metalSource=metal, metalSourceSHA256=digest)
        output = self.run_case("large-artifact", compiled=artifact)
        self.assertGreater(output["compiledArtifactBytes"], 2 * 1024 * 1024)
        self.assertLessEqual(output["compiledArtifactBytes"], 16 * 1024 * 1024)
        self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (1, 1, 1), output)
        self.assertEqual(output["acceptedMetalBytes"], [len(metal.encode())], output)
        self.assertFalse(output["optionalFileExists"], output)

    def test_actual_msl_and_abi_contract_failures_are_not_optional(self):
        wrong_abi = generic_color_program_artifact(KEY)
        wrong_abi["program"]["uniformBufferIndex"] = 3
        oversized_msl = generic_color_program_artifact(KEY)
        metal = oversized_msl["program"]["metalSource"] + "\n/*" + "x" * (1024 * 1024) + "*/\n"
        oversized_msl["program"].update(metalSource=metal,
            metalSourceSHA256=hashlib.sha256(metal.encode()).hexdigest())
        for artifact in (wrong_abi, oversized_msl):
            with self.subTest(abi=artifact["program"]["uniformBufferIndex"]):
                output = self.run_case("rejected-contract", rejected=artifact)
                self.assertEqual((output["accepted"], output["compilations"], output["validations"]), (0, 1, 1), output)
                self.assertEqual(output["failures"], ["artifact-contract-rejected"], output)
                self.assertFalse(output["optionalFileExists"], output)

    def test_deleted_or_damaged_successful_entry_is_rebuilt(self):
        output = self.run_case("sequence")
        self.assertEqual((output["accepted"], output["compilations"]), (4, 3), output)
        self.assertEqual(output["retainedCompilerResults"], 0, output)

    def test_rejected_compiler_contract_is_bounded_and_later_request_can_retry(self):
        output = self.run_case("bad-contract")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["artifact-contract-rejected"], output)

    def test_compiler_failure_is_local_and_later_request_can_retry(self):
        output = self.run_case("compiler-failure")
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["compiler-workspace"], output)

    def test_concurrent_invalid_entry_has_one_rebuild(self):
        output = self.run_case("concurrent", initial=b"broken")
        self.assertTrue(output["allJoined"] and output["allCompleted"], output)
        self.assertEqual((output["accepted"], output["compilations"]), (8, 1), output)
        self.assertEqual(output["validations"], 1, output)

    def test_same_artifact_different_expected_contracts_do_not_share_program(self):
        for mode in ("contracts-positive-first", "contracts-negative-first"):
            with self.subTest(mode=mode):
                output = self.run_case(mode)
                self.assertTrue(output["isolatedContracts"] and output["allCompleted"], output)
                self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
                self.assertEqual(output["failures"], ["artifact-contract-rejected"], output)
                self.assertEqual(output["retainedCompilerResults"], 0, output)

    def test_same_artifact_keeps_each_accepted_output_channel_projection(self):
        for mode in ("channels-unproven-first", "channels-red-first"):
            with self.subTest(mode=mode):
                output = self.run_case(mode)
                self.assertTrue(output["isolatedContracts"] and output["allCompleted"], output)
                self.assertEqual((output["accepted"], output["compilations"]), (2, 2), output)
                self.assertEqual(output["failures"], [], output)
                self.assertEqual(sorted(output["acceptedOutputChannels"]), ["redDefined", "unproven"], output)

    def test_rejected_contract_is_shared_with_waiters_but_never_retained(self):
        output = self.run_case("concurrent-bad-contract", initial=b"broken")
        self.assertTrue(output["allJoined"] and output["allCompleted"], output)
        self.assertEqual((output["accepted"], output["compilations"]), (1, 2), output)
        self.assertEqual(output["failures"], ["artifact-contract-rejected"] * 8, output)
        self.assertEqual(output["retainedCompilerResults"], 0, output)


if __name__ == "__main__":
    unittest.main()
