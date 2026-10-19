#!/usr/bin/env python3
"""Bounded DEBUG observations borrow real typed inputs without consuming playback.

Compiler admission and App wiring are outside this CPU cut. Reuse the production
Binding/Program declaration boundary from the maintained named-Timeline gate;
the authored parser, playback, resolver and observer implementations are real.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DECLARATIONS = SCENE / "Systems/Timeline/SceneTimelineTargetCompiler.swift"
FIXTURE = Path(__file__).with_name("fixtures") / "SceneTimelineFrameEvidenceHarness.swift"
SWIFT_SOURCES = [SCENE / path for path in [
    "Format/SceneTimelineAnimation.swift",
    "Systems/Properties/SceneDynamicSnapshot.swift",
    "Systems/Timeline/SceneTimelineEvaluator.swift",
    "Systems/Timeline/SceneTimelineRuntime.swift",
    "Systems/Timeline/SceneTimelinePlaybackRuntime.swift",
    "Diagnostics/SceneTimelineFrameEvidence.swift",
]]


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is unavailable")
class SceneTimelineFrameEvidenceTests(unittest.TestCase):
    def test_selected_inputs_are_bounded_and_do_not_consume_playback(self) -> None:
        inputs = [*SWIFT_SOURCES, DECLARATIONS, FIXTURE, Path(__file__)]
        before = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in inputs}
        declarations, separator, _ = DECLARATIONS.read_text().partition(
            "nonisolated enum SceneTimelineTargetCompiler")
        self.assertTrue(separator, "production Binding/Program declaration boundary missing")
        with tempfile.TemporaryDirectory(prefix="mwx-timeline-frame-evidence-") as temporary:
            directory = Path(temporary)
            prepared = directory / "PreparedProgram.swift"
            prepared.write_text(declarations)
            binary = directory / "evidence"
            compiled = subprocess.run([
                "swiftc", "-D", "DEBUG", *map(str, SWIFT_SOURCES),
                str(prepared), str(FIXTURE), "-module-cache-path", str(directory / "cache"),
                "-o", str(binary),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            observed = json.loads(completed.stdout)
        self.assertEqual(set(observed), {"71", "907"})
        for label, facts in observed.items():
            with self.subTest(case=label):
                self.assertTrue(facts)
                self.assertTrue(all(value is True for value in facts.values()), facts)
        after = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in inputs}
        self.assertEqual(before, after, "focused input source drift")


if __name__ == "__main__":
    unittest.main()
