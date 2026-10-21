#!/usr/bin/env python3
"""Strict per-call color-source facts, including adjacent rejected inputs."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources  # noqa: E402


HARNESS = r'''
import Foundation

private typealias Analyzer = SceneAuthoredShaderColorTransferAnalyzer

private func source(_ body: String, helpers: String = "") -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture3;
    \(helpers)
    void main() { \(body) }
    """
}

@main struct Checks {
    static func main() throws {
        var result: [String: Bool] = [:]
        for slot in [0, 3] {
            for name in ["value", "renamedSignal"] {
                let text = source("float \(name) = 0.25; gl_FragColor = vec4(\(name));")
                let parsed = Analyzer.SourceAnalysis(fragmentSource: text)
                result["splat-\(slot)-\(name)"] = parsed != nil
                    && Analyzer.isScalarSplatOutput(sourceAnalysis: parsed)
                let sample = source(
                    "vec4 \(name) = texSample2D(g_Texture\(slot), v_TexCoord); " +
                    "gl_FragColor = \(name);"
                )
                let sampled = Analyzer.SourceAnalysis(fragmentSource: sample)
                if case .passthrough(let provenSlot) = Analyzer.analyze(sourceAnalysis: sampled) {
                    result["slot-\(slot)-\(name)"] = provenSlot == slot
                } else {
                    result["slot-\(slot)-\(name)"] = false
                }
                result["sample-is-not-splat-\(slot)-\(name)"] =
                    !Analyzer.isScalarSplatOutput(sourceAnalysis: sampled)
            }
        }

        let noOutput = Analyzer.SourceAnalysis(fragmentSource: source("float unused = 1.0;"))
        result["zero-output-is-parseable"] = noOutput != nil && noOutput?.outputUses.isEmpty == true
        result["zero-output-is-not-splat"] = !Analyzer.isScalarSplatOutput(sourceAnalysis: noOutput)
        let multiple = Analyzer.SourceAnalysis(fragmentSource: source(
            "gl_FragColor = vec4(0.25); gl_FragColor = vec4(0.5);"
        ))
        result["multiple-output-is-parseable"] = multiple?.outputUses.count == 2
        result["multiple-output-is-not-splat"] = !Analyzer.isScalarSplatOutput(sourceAnalysis: multiple)
        let helperOutput = Analyzer.SourceAnalysis(fragmentSource: source(
            "gl_FragColor = vec4(0.25);",
            helpers: "void UnusedHelper() { gl_FragColor = vec4(0.5); }"
        ))
        result["helper-output-counted"] = helperOutput?.outputUses.count == 2
        result["helper-output-is-not-splat"] = !Analyzer.isScalarSplatOutput(sourceAnalysis: helperOutput)
        let helperOnly = Analyzer.SourceAnalysis(fragmentSource: source(
            "float unused = 0.25;",
            helpers: "void UnusedHelper() { gl_FragColor = vec4(0.5); }"
        ))
        result["helper-only-output-counted"] = helperOnly?.outputUses.count == 1
        result["helper-only-output-is-not-splat"] = !Analyzer.isScalarSplatOutput(sourceAnalysis: helperOnly)
        let conditional = Analyzer.SourceAnalysis(fragmentSource: source(
            "if (v_TexCoord.x > 0.5) { gl_FragColor = vec4(0.25); }"
        ))
        result["conditional-output-is-not-splat"] = !Analyzer.isScalarSplatOutput(sourceAnalysis: conditional)

        let rejected = [
            "no-main": "float helper() { return 1.0; }",
            "invalid-character": source("gl_FragColor = vec4(@);"),
            "unbounded-loop": source("while (true) { } gl_FragColor = vec4(1.0);"),
            "unbounded-unused-helper": source(
                "gl_FragColor = vec4(1.0);",
                helpers: "void UnusedHelper() { while (true) { } }"
            ),
            "runtime-bound": source(
                "for (int i = 0; i < u_Max; ++i) { } gl_FragColor = vec4(1.0);",
                helpers: "uniform float u_Max;"
            ),
        ]
        for (name, text) in rejected {
            let parsed = Analyzer.SourceAnalysis(fragmentSource: text)
            let blend = Analyzer.blendSourceSlots(sourceAnalysis: parsed)
            let transferUnresolved: Bool
            if case .unresolved = Analyzer.analyze(sourceAnalysis: parsed) {
                transferUnresolved = true
            } else { transferUnresolved = false }
            result["strict-\(name)"] = parsed == nil && transferUnresolved
                && Analyzer.conditionalStraightUnionSourceSlot(sourceAnalysis: parsed) == nil
                && Analyzer.singleSamplerAlphaMutationSourceSlot(sourceAnalysis: parsed) == nil
                && Analyzer.sameSlotChannelReconstructionSourceSlot(sourceAnalysis: parsed) == nil
                && Analyzer.straightRGBScalarAlphaFact(sourceAnalysis: parsed) == nil
                && blend.auxiliaryRGB == nil && blend.overlayAlpha == nil
                && blend.overlayAlphaPreserving == nil
                && !Analyzer.isScalarSplatOutput(sourceAnalysis: parsed)
        }

        // A failed input must not poison the next call, and retained facts must
        // continue describing their own source after unrelated parses.
        let original = Analyzer.SourceAnalysis(fragmentSource: source("gl_FragColor = vec4(0.5);"))
        _ = Analyzer.SourceAnalysis(fragmentSource: rejected["invalid-character"]!)
        _ = Analyzer.SourceAnalysis(fragmentSource: source("gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);"))
        result["facts-remain-source-local"] = Analyzer.isScalarSplatOutput(sourceAnalysis: original)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


class SceneColorAnalysisReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-color-analysis-reuse-")
        temporary = Path(cls.temporary.name)
        harness = temporary / "Checks.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        binary = temporary / "checks"
        compilation = subprocess.run(
            ["xcrun", "--sdk", "macosx", "swiftc",
             *map(str, scene_swift_sources("authored_shader_frontend_core")),
             str(harness), "-o", str(binary)],
            capture_output=True, text=True, env=environment,
        )
        if compilation.returncode:
            cls.temporary.cleanup()
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], capture_output=True, text=True, check=True, env=environment,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_renamed_values_and_slots_keep_their_own_facts(self) -> None:
        for key, value in self.result.items():
            if key.startswith(("splat-", "slot-", "sample-is-not-splat-")):
                self.assertTrue(value, key)

    def test_all_fragment_outputs_are_retained_without_early_single_output_filter(self) -> None:
        for key in (
            "zero-output-is-parseable", "zero-output-is-not-splat",
            "multiple-output-is-parseable", "multiple-output-is-not-splat",
            "helper-output-counted", "helper-output-is-not-splat",
            "helper-only-output-counted", "helper-only-output-is-not-splat",
            "conditional-output-is-not-splat",
        ):
            self.assertTrue(self.result[key], key)

    def test_invalid_or_unproven_loop_inputs_fail_closed(self) -> None:
        for key, value in self.result.items():
            if key.startswith("strict-"):
                self.assertTrue(value, key)

    def test_facts_do_not_leak_between_calls(self) -> None:
        self.assertTrue(self.result["facts-remain-source-local"])


if __name__ == "__main__":
    unittest.main()
