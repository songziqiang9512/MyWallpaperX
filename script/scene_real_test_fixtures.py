#!/usr/bin/env python3
"""Resolve the bounded local cache used by real-sample Scene tests."""

from __future__ import annotations

import json
from pathlib import Path

try:
    from .scene_real_test_fixture_config import load_fixture_config
except ImportError:
    from scene_real_test_fixture_config import load_fixture_config


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path(__file__).with_name("scene_real_test_fixture.json")


def configured_path(key: str) -> Path:
    config = load_fixture_config(CONFIG_PATH, REPOSITORY_ROOT)
    configured = config.get(key)
    if not isinstance(configured, str):
        raise ValueError(
            f"Scene fixture {key} is not configured; set the documented environment "
            "override or .codex/scene_real_test_fixture.local.json"
        )
    return Path(configured)


def sample_root() -> Path:
    return configured_path("sample_root")


def runtime_homes_root() -> Path:
    return configured_path("runtime_homes")


def sample_cache_root(sample_id: str) -> Path:
    cache_parent = (
        runtime_homes_root()
        / sample_id
        / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
    )
    candidates = sorted(path for path in cache_parent.iterdir() if path.is_dir()) if cache_parent.is_dir() else []
    return candidates[0] if len(candidates) == 1 else cache_parent / "__unavailable__"


def sample_runtime_evidence_path(sample_id: str) -> Path:
    report_path = configured_path("report")
    if not report_path.is_file():
        return report_path.parent / "__unavailable__"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    sample = next(
        (item for item in report.get("samples", []) if str(item.get("id")) == sample_id),
        None,
    )
    evidence_path = (sample or {}).get("evidence", {}).get("runtime_evidence")
    return Path(evidence_path) if evidence_path else report_path.parent / "__unavailable__"
