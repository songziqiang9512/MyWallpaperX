#!/usr/bin/env python3

"""Localized authored graph input admission through the real Program finalizer."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_resolved_material_program_finalizer as fixture


SWIFT_SOURCES = fixture.SWIFT_SOURCES
# Reuse the established contract, texture snapshot, template, and finalization
# fixture. The additional harness only observes Program output and failures.
HARNESS = fixture.HARNESS.split("@main", 1)[0] + r'''
@main
private enum Harness {
    static func float(_ data: Data, at offset: Int) -> Float {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
    }

    static func observe(
        _ device: MTLDevice,
        name: String,
        metadata: String,
        slot: Int = 0,
        input: Graph.TextureIdentity? = graphTexture(),
        explicit: Graph.TextureIdentity? = nil
    ) -> [String: Any] {
        let samplerName = "g_Texture\(slot)"
        let shader = contract(
            revision: "localized-graph-input-\(name)",
            uniformMetadata: nil,
            semanticProbes: false,
            vertexSourceOverride: """
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                v_TexCoord = a_TexCoord;
            }
            """,
            fragmentSourceOverride: """
            varying vec2 v_TexCoord;
            uniform sampler2D \(samplerName); // \(metadata)
            void main() {
                gl_FragColor = texSample2D(\(samplerName), v_TexCoord);
            }
            """
        )
        var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [:]
        if let input {
            entries[.graph(input)] = readyStatus(
                device,
                identity: .graph(input),
                purpose: .premultipliedColor,
                content: .color(.resolved(.premultipliedAlpha))
            )
        }
        let result = finalize(
            shader: shader,
            device: device,
            slot: slot,
            includePrimaryCandidate: explicit != nil,
            primaryReference: .graph(explicit ?? graphTexture()),
            additionalEntries: entries,
            implicitFramebufferIdentity: input
        )
        switch result {
        case let .failure(failure):
            return [
                "status": "rejected",
                "phase": failure.phase.rawValue,
                "code": failure.code.rawValue,
            ]
        case let .success(program):
            guard let selected = program.textureSlots[slot],
                  case let .graph(identity) = selected.reference else {
                return ["status": "unexpected-program"]
            }
            let expected = explicit ?? input
            return [
                "status": "ready",
                "slot": selected.index,
                "selectedExpectedIdentity": identity == expected,
                "selectedCurrentInput": identity == input,
                "registryExpectedIdentity": expected.map {
                    selected.registryIdentity == .graph($0)
                } ?? false,
                "sourceFactCurrentInput": selected.graphInputSourceFact?.inputIdentity == input,
                "sourceFactProvenance": selected.graphInputSourceFact?.provenance.rawValue ?? "none",
                "selection": String(describing: selected.diagnosticSelectionProvenance),
                "authoredExplicitSelection": selected.diagnosticSelectionProvenance == .authored(.explicitBinding),
                "premultipliedPurpose": selected.expectedPurpose == .premultipliedColor,
            ]
        }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let localized = #"{"material":"上一个","hidden":true}"#
        let prior = effectOutputTexture("fixture-prior")
        let missing = Graph.TextureIdentity(
            kind: .layerSource, layerID: 43, effect: nil, name: nil
        )
        var cases: [String: [String: Any]] = [:]
        cases["layerSource"] = observe(device, name: "layer-source", metadata: localized)
        cases["priorEffect"] = observe(
            device, name: "prior-effect", metadata: localized, input: prior
        )
        cases["explicitWins"] = observe(
            device, name: "explicit-wins", metadata: localized,
            input: prior, explicit: graphTexture()
        )
        cases["missingExplicit"] = observe(
            device, name: "missing-explicit", metadata: localized,
            input: prior, explicit: missing
        )
        cases["historical"] = observe(
            device, name: "historical",
            metadata: #"{"material":"ui_editor_properties_framebuffer","hidden":true}"#
        )
        cases["previous"] = observe(
            device, name: "previous", metadata: #"{"material":"previous"}"#
        )
        let excluded: [(String, String, Int, Graph.TextureIdentity?)] = [
            ("missingHidden", #"{"material":"上一个"}"#, 0, graphTexture()),
            ("visible", #"{"material":"上一个","hidden":false}"#, 0, graphTexture()),
            ("slotOne", localized, 1, graphTexture()),
            ("nonRegular", #"{"material":"上一个","hidden":true,"mode":"opacitymask"}"#, 0, graphTexture()),
            ("labelOnly", #"{"material":"source","label":"上一个","hidden":true}"#, 0, graphTexture()),
            ("unknownLocalized", #"{"material":"当前输入","hidden":true}"#, 0, graphTexture()),
            ("noCurrentIdentity", localized, 0, nil),
        ]
        for (name, metadata, slot, input) in excluded {
            cases[name] = observe(
                device, name: name, metadata: metadata, slot: slot, input: input
            )
        }
        let output: [String: Any] = ["metalAvailable": true, "cases": cases]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneLocalizedGraphInputAliasTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        directory = tempfile.TemporaryDirectory(prefix="mwx-localized-graph-input-")
        cls.addClassCleanup(directory.cleanup)
        root = Path(directory.name)
        support, harness, binary = (root / name for name in (
            "Support.swift", "Harness.swift", "localized-graph-input-test"
        ))
        support.write_text(fixture.SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(root / "shader-cache")
        # Match the existing unsigned finalizer fixture's explicit bounded route.
        environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
        (root / "shader-cache").mkdir()
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support), *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path", str(root / "module-cache"),
                "-o", str(binary),
            ],
            cwd=fixture.REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], cwd=fixture.REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True,
        )
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    def assert_graph_input(self, name: str, selection: str) -> None:
        result = self.result["cases"][name]
        self.assertEqual(result["status"], "ready", result)
        self.assertEqual(result["slot"], 0, result)
        for field in (
            "selectedExpectedIdentity", "selectedCurrentInput", "registryExpectedIdentity",
            "sourceFactCurrentInput", "premultipliedPurpose",
        ):
            self.assertIs(result[field], True, result)
        self.assertEqual(result["sourceFactProvenance"], "explicitMaterialAlias", result)
        self.assertEqual(result["selection"], selection, result)

    def test_localized_alias_uses_current_layer_source(self) -> None:
        self.assert_graph_input("layerSource", "implicitFramebuffer")

    def test_localized_alias_uses_current_prior_effect_output(self) -> None:
        self.assert_graph_input("priorEffect", "implicitFramebuffer")

    def test_existing_aliases_keep_their_selection_provenance(self) -> None:
        self.assert_graph_input("historical", "implicitFramebuffer")
        self.assert_graph_input("previous", "materialGraphInputAlias")

    def test_explicit_graph_resource_wins_over_current_input(self) -> None:
        result = self.result["cases"]["explicitWins"]
        self.assertEqual(result["status"], "ready", result)
        self.assertIs(result["selectedExpectedIdentity"], True, result)
        self.assertIs(result["registryExpectedIdentity"], True, result)
        self.assertIs(result["selectedCurrentInput"], False, result)
        self.assertIs(result["authoredExplicitSelection"], True, result)
        self.assertIs(result["premultipliedPurpose"], True, result)

    def test_missing_explicit_resource_does_not_fall_back_to_current_input(self) -> None:
        result = self.result["cases"]["missingExplicit"]
        self.assertEqual(result["status"], "rejected", result)
        self.assertEqual(result["code"], "resourceSnapshotUnresolved", result)

    def test_localized_metadata_outside_proven_contract_is_rejected(self) -> None:
        for name in (
            "missingHidden", "visible", "slotOne", "nonRegular", "labelOnly",
            "unknownLocalized", "noCurrentIdentity",
        ):
            with self.subTest(name=name):
                result = self.result["cases"][name]
                self.assertEqual(result["status"], "rejected", result)


if __name__ == "__main__":
    unittest.main()
