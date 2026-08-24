#!/usr/bin/env python3
"""Product-side generic normalizer matrix-constructor gate."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_generic_shader_program_artifact import (
    REPOSITORY_ROOT,
    SWIFT_SOURCES,
)


HARNESS = r'''
import Foundation

@main
private struct MatrixCastHarness {
    static func main() {
        let vertex = """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        uniform mat4 g_ProjectionInverse;
        varying vec2 v_TexCoord;
        void main() {
            mat3 rotation = CAST3X3(g_ProjectionInverse);
            vec2 direction = mul(vec3(1.0, 0.0, 0.0), rotation).xy;
            gl_Position = vec4(a_Position.xy + direction * 0.0, 0.0, 1.0);
            v_TexCoord = a_TexCoord;
        }
        """
        let fragment = """
        uniform sampler2D g_Texture0;
        varying vec2 v_TexCoord;
        void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
        """
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: fragment,
            maximumStageSourceBytes: 64 * 1_024
        ) {
        case let .success(pair):
            let passed = pair.vertex.contains("#define CAST3X3(x) mat3(x)")
                && pair.vertex.contains(
                    "mat3 rotation = CAST3X3(g_ProjectionInverse)"
                )
            let positive = SceneGenericShaderBoundedLoopWork.evaluate(sources: ["""
            float bounded(float depth) {
                float layers = 24.0;
                float current = 1.0;
                for (float index = 0.0; current > depth && index < layers; index++) {
                    current -= 1.0 / layers;
                }
                return current;
            }
            void main() { bounded(0.5); }
            """])
            let unseen = SceneGenericShaderBoundedLoopWork.evaluate(sources: ["""
            float bounded(float remaining) {
                const float marchLimit = 12.0f;
                for (float probe = 0e0; probe < marchLimit && remaining > 0.0; ++probe) {
                    remaining -= 0.25;
                }
                return remaining;
            }
            void main() { bounded(1.0); }
            """])
            let rejected = [
                "uniform float count; void main() { float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}",
                "void main() { float count = 24.0; float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 || i < count; i++) { remaining -= 0.1; }}",
                "void main() { float count = 24.0; float remaining = 1.0;\n"
                    + "for (float i = 0.0; i < remaining && i < count; i++) { remaining -= 0.1; }}",
                "void main() { float count = 24.0; float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { i = 0.0; }}",
                "void main() { float count = 24.0; count = 32.0; float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}",
                "float decoy() { float count = 24.0; return count; }\n"
                    + "uniform float count; void main() { float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}",
                "void main() { for (int outer = 0; outer < 16; outer++) {\n"
                    + "for (int inner = 0; inner < 16; inner++) { consume(outer, inner); } }}",
                "void main() { float count = 24.0; float remaining = 1.0;\n"
                    + "for (int outer = 0; outer < 2; outer++) {\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; } }}",
                "void reset(inout float value) { value = 0.0; }\n"
                    + "void main() { float count = 24.0; float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { reset(i); }}",
                "void widen(inout float value) { value = 1000000.0; }\n"
                    + "void main() { float count = 24.0; widen(count); float remaining = 1.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}",
                "void inner() { for (int i = 0; i < 64; i++) { consume(i); } }\n"
                    + "void main() { for (int outer = 0; outer < 4; outer++) { inner(); } }",
                "float bounded(float remaining) { float count = 24.0;\n"
                    + "for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; } return remaining; }\n"
                    + "void main() { bounded(1.0); bounded(0.5); }",
            ].allSatisfy { source in
                if case .failure(.unbounded) =
                    SceneGenericShaderBoundedLoopWork.evaluate(sources: [source]) {
                    return true
                }
                return false
            }
            let positivePassed = if case .success(24) = positive { true } else { false }
            let unseenPassed = if case .success(12) = unseen { true } else { false }
            let helperMutationRejected = SceneAuthoredShaderColorTransferAnalyzer
                .analyze(fragmentSource: """
                uniform sampler2D g_Texture0;
                varying vec2 v_TexCoord;
                void mutate(inout vec4 value) { value.a = 0.0; }
                void main() {
                    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
                    mutate(albedo);
                    gl_FragColor = albedo;
                }
                """) != .passthrough(textureSlot: 0)
            print(
                passed && positivePassed && unseenPassed && rejected
                    && helperMutationRejected
                    ? "PASS" : "FAIL"
            )
        case .failure:
            print("FAIL")
        }
    }
}
'''


class SceneGenericShaderMatrixCastTests(unittest.TestCase):
    def test_product_normalizer_emits_matrix_constructor(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-matrix-cast-") as directory:
            root = Path(directory)
            harness = root / "MatrixCastHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "matrix-cast-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework", "Security",
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)], cwd=REPOSITORY_ROOT, check=True,
                capture_output=True, text=True,
            )
            self.assertEqual(completed.stdout.strip(), "PASS")


if __name__ == "__main__":
    unittest.main()
