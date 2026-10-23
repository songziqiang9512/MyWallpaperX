#!/usr/bin/env python3
"""CPU-only nominal-output preparation regression, without Metal devices.

One real authored PMA shader goes through launch variant preparation. Metadata
counterexamples exercise the unchanged private output owner through a test
extension appended to an exact isolated copy of its production source file.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_resolved_material_program_finalizer as fixture

OWNER = fixture.VARIANT_COMPILATION_SOURCE
OWNER_TEST_EXTENSION = r'''
extension SceneResolvedMaterialVariantCache {
    static func testingNominalOutput(_ frontend: SceneAuthoredShaderProgram,
        storage: SceneResolvedMaterialProgram.OutputStorage = .color,
        signal: SceneTextureContent? = nil) -> SceneTextureContent? {
        preparedOutputContent(storage: storage, frontend: frontend,
                              signalPassthroughContent: signal)
    }
}
'''

HARNESS = r'''
import Foundation

@main enum NominalOutputHarness {
    static func main() throws {
        let shader = contract(revision: "owned-independent-pma-nominal-output",
            semanticProbes: false, vertexSourceOverride: """
            uniform mat4 g_ModelViewProjectionMatrix;
            attribute vec3 a_Position;
            void main() { gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0); }
            """, fragmentSourceOverride: """
            vec3 ApplyBlending(int mode, vec3 base, vec3 tint, float weight) {
                return base + tint * weight;
            }
            void main() {
                vec4 outputColor = vec4(0.0);
                outputColor.rgb = ApplyBlending(0, outputColor.rgb, vec3(0.4, 0.2, 0.1), 0.5);
                outputColor.a = max(outputColor.a, 0.5);
                gl_FragColor = outputColor;
            }
            """)
        let material = template(shader, includePrimaryCandidate: false)
        guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
            template: material, maximumVariantCount: 4),
              case .success = cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil),
              let variant = cache.launchEnvelopeCapabilitySnapshot().variants.first else {
            throw NSError(domain: "nominal-output-prepare", code: 1)
        }
        let pma = SceneTextureContent.color(.resolved(.premultipliedAlpha))
        var checks: [String: Bool] = [
            "realVariantIsIndependentPMA": variant.frontendProgram.colorTransfer == .premultipliedAlpha
                && variant.frontendProgram.colorBoundary == nil,
            "realVariantPublishesNominalPMA": variant.preparedOutputContent == pma,
        ]
        // These metadata-only controls are not executable Programs. They test
        // owner precedence; real admission/finalization validation is retained.
        func metadata(_ transfer: SceneShaderColorTransfer,
                      _ boundary: SceneShaderColorBoundary? = nil) -> SceneAuthoredShaderProgram {
            .init(metalSource: "", vertexFunctionName: "", fragmentFunctionName: "",
                uniformLayout: .init(fields: [], byteSize: 0), textureBindings: [],
                staticLoopWork: 0, colorTransfer: transfer, colorBoundary: boundary)
        }
        func nominal(_ transfer: SceneShaderColorTransfer,
                     _ boundary: SceneShaderColorBoundary? = nil,
                     storage: Program.OutputStorage = .color,
                     signal: SceneTextureContent? = nil) -> SceneTextureContent? {
            SceneResolvedMaterialVariantCache.testingNominalOutput(metadata(transfer, boundary),
                storage: storage, signal: signal)
        }
        checks["unknownStaysNil"] = nominal(.unresolved) == nil
        checks["opaqueUnchanged"] = nominal(.opaque) == .color(.resolved(.opaque))
        checks["PMADataStorageStaysData"] = nominal(.premultipliedAlpha,
            storage: .preservedRGBAUnorm) == .data
        checks["PMAScalarStorageStaysScalar"] = nominal(.premultipliedAlpha,
            storage: .scalarRedUnorm) == .scalarRedUnorm
        let signalBoundary = SceneShaderColorBoundary(colorInputSlots: [],
            outputRepresentation: .premultipliedAlpha, signalPassthroughSlot: 0)
        checks["signalPriorityOverPMA"] = nominal(.premultipliedAlpha, signalBoundary,
            signal: .redGreenFloat16) == .redGreenFloat16
        checks["missingSignalStaysNil"] = nominal(.premultipliedAlpha, signalBoundary) == nil
        checks["boundaryPriorityOverPMA"] = nominal(.premultipliedAlpha,
            .init(colorInputSlots: [], outputRepresentation: .straightAlpha))
                == .color(.resolved(.straightAlpha))
        checks["passthroughSignalUnchanged"] = nominal(.passthrough(textureSlot: 0),
            signal: .color(.resolved(.independentAlphaSignal)))
                == .color(.resolved(.independentAlphaSignal))
        checks["unknownIsNotSignalFallback"] = nominal(.unresolved, signal: pma) == nil
        print(String(data: try JSONSerialization.data(withJSONObject: checks), encoding: .utf8)!)
    }
}
'''


class PreparedMaterialOutputContentTests(unittest.TestCase):
    def test_real_pma_variant_and_existing_output_precedence(self):
        with tempfile.TemporaryDirectory(prefix="mwx-nominal-output-cpu-") as directory:
            p = Path(directory)
            owner_text = OWNER.read_text()
            owner_copy = p / OWNER.name
            owner_copy.write_text(owner_text + OWNER_TEST_EXTENSION)
            (p / "Main.swift").write_text(HARNESS)
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(p / "clang-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(p / "swift-cache")
            env["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(p / "shader-cache")
            env["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
            sources = [s for s in fixture.SWIFT_SOURCES if s != OWNER]
            command = ["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                       str(owner_copy), *map(str, fixture.SHARED_FIXTURE_SOURCES),
                       str(p / "Main.swift"), "-module-cache-path", str(p / "modules"),
                       "-o", str(p / "run")]
            compiled = subprocess.run(command, capture_output=True, text=True, env=env, timeout=180)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            self.assertEqual(OWNER.read_text(), owner_text, "owner changed during isolated test")
            run = subprocess.run([str(p / "run")], capture_output=True, text=True,
                                 env=env, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 11)
            for name, passed in checks.items():
                with self.subTest(contract=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
