#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_real_test_fixtures as fixtures


class SceneRealTestFixturesTests(unittest.TestCase):
    def test_default_fixture_is_declared_by_tracked_config(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            sample_root = fixtures.sample_root()
            root = fixtures.runtime_homes_root()
        self.assertEqual(
            sample_root,
            (
                fixtures.REPOSITORY_ROOT
                / ".codex/scene-user-samples-20260722/Scene"
            ).resolve(),
        )
        self.assertEqual(
            root,
            (
                fixtures.REPOSITORY_ROOT
                / ".codex/scene-nested-child-full45-20260727/runtime-homes"
            ).resolve(),
        )

    def test_environment_override_resolves_single_sample_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-fixtures-") as directory:
            samples = Path(directory) / "samples"
            runtime_homes = Path(directory) / "runtime-homes"
            cache = (
                runtime_homes
                / "123"
                / "Library/Caches/MyWallpaperX/SteamWorkshopScene/fingerprint"
            )
            cache.mkdir(parents=True)
            with mock.patch.dict(
                os.environ,
                {
                    "MWX_SCENE_TEST_SAMPLE_ROOT": str(samples),
                    "MWX_SCENE_TEST_RUNTIME_HOMES": str(runtime_homes),
                },
            ):
                self.assertEqual(fixtures.sample_root(), samples.resolve())
                self.assertEqual(fixtures.runtime_homes_root(), runtime_homes.resolve())
                self.assertEqual(fixtures.sample_cache_root("123"), cache.resolve())

    def test_missing_or_ambiguous_cache_is_unavailable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-fixtures-") as directory:
            runtime_homes = Path(directory) / "runtime-homes"
            cache_parent = (
                runtime_homes
                / "123"
                / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
            )
            with mock.patch.dict(
                os.environ,
                {"MWX_SCENE_TEST_RUNTIME_HOMES": str(runtime_homes)},
            ):
                self.assertEqual(
                    fixtures.sample_cache_root("123").name,
                    "__unavailable__",
                )
                (cache_parent / "one").mkdir(parents=True)
                (cache_parent / "two").mkdir()
                self.assertEqual(
                    fixtures.sample_cache_root("123").name,
                    "__unavailable__",
                )


if __name__ == "__main__":
    unittest.main()
