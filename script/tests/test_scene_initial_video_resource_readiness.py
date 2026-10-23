#!/usr/bin/env python3
"""Ordinary-video resource/selection controls; native texture identities only.

Compiles exact production Snapshot/Store, ordinary assembly, resolver and Source
observation method. AVPlayer/payload completion are controlled inputs; no decoder,
GPU command, App, surface cohort or promotion is exercised here.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_frame_texture_registry as registry

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneInitialVideoResourceReadinessHarness.swift"


def declaration(text: str, signature: str) -> str:
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def write_readiness_source(directory: Path) -> Path:
    """Project the production enum for standalone Source consumer gates."""
    text = (SCENE / "Resources/Textures/SceneBaseImageTextureLoad.swift").read_text()
    signature = "enum SceneOrdinaryVideoFrameReadiness:"
    if text.count(signature) != 1:
        raise RuntimeError("ordinary video readiness declaration changed")
    output = directory / "SceneOrdinaryVideoFrameReadiness.swift"
    output.write_text(declaration(text, signature) + "\n")
    return output


class InitialVideoResourceReadinessTests(unittest.TestCase):
    def test_candidate_resources_and_actual_selection(self):
        with tempfile.TemporaryDirectory(prefix="mwx-initial-video-resources-") as directory:
            p = Path(directory)
            base = (SCENE / "Resources/Textures/SceneBaseImageTextureLoad.swift").read_text()
            (p / "Snapshot.swift").write_text(base.split("enum SceneBaseImageTextureLoad {", 1)[0])
            assembly = (SCENE / "Rendering/Composition/SceneFrameLayerTextureAssembly.swift").read_text()
            (p / "Assembly.swift").write_text(assembly.split("enum SceneFrameUserPropertyTextureAssembly", 1)[0])
            program = (SCENE / "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift").read_text()
            binding = declaration(program, "    struct BaseMaterialBinding:")
            (p / "Binding.swift").write_text("import Foundation\nstruct SceneBaseMaterialProviderBindingProgram {\n"
                + binding + '\nstatic let currentIdentity="$mediaThumbnail"\n'
                + 'static let previousIdentity="$mediaPreviousThumbnail"\n'
                + "let baseMaterialBindings:[Int:BaseMaterialBinding]\nstatic let empty=Self(baseMaterialBindings:[:])\n}\n")
            source = (SCENE / "Resources/Providers/SceneVideoTextureSource.swift").read_text()
            observation = declaration(source, "    func initialFrameReadiness(")
            (p / "Observation.swift").write_text("extension SceneVideoTextureSource {\n" + observation + "\n}\n")
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(p / "clang-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(p / "swift-cache")
            extras = [SCENE / "Compilation/Material/SceneEffectTextureInput.swift",
                      SCENE / "Resources/Textures/SceneBaseImageTextureCandidateSupport.swift",
                      SCENE / "Resources/Textures/SceneBaseMaterialTextureResolver.swift"]
            command = ["xcrun", "swiftc", "-parse-as-library", *map(str, registry.SWIFT_SOURCES),
                       *map(str, extras), *map(str, (p / n for n in (
                           "Snapshot.swift", "Assembly.swift", "Binding.swift", "Observation.swift"))),
                       str(FIXTURE), "-module-cache-path", str(p / "modules"), "-o", str(p / "run")]
            compiled = subprocess.run(command, capture_output=True, text=True, env=env, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(p / "run")], capture_output=True, text=True, env=env, timeout=20)
            self.assertEqual(run.returncode, 0, run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 17)
            for name, passed in checks.items():
                with self.subTest(contract=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
