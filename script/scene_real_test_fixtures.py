#!/usr/bin/env python3
"""Resolve the bounded local cache used by real-sample Scene tests."""

from __future__ import annotations

import json
import os
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path(__file__).with_name("scene_real_test_fixture.json")


def configured_path(key: str, override_name: str) -> Path:
    override = os.environ.get(override_name)
    if override:
        return Path(override).expanduser().resolve()
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if config.get("schema_version") != 1:
        raise ValueError(f"unsupported Scene real fixture config: {CONFIG_PATH}")
    configured = Path(config[key])
    return (
        configured.resolve()
        if configured.is_absolute()
        else (REPOSITORY_ROOT / configured).resolve()
    )


def sample_root() -> Path:
    return configured_path("sample_root", "MWX_SCENE_TEST_SAMPLE_ROOT")


def runtime_homes_root() -> Path:
    return configured_path("runtime_homes", "MWX_SCENE_TEST_RUNTIME_HOMES")


def sample_cache_root(sample_id: str) -> Path:
    cache_parent = (
        runtime_homes_root()
        / sample_id
        / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
    )
    candidates = sorted(path for path in cache_parent.iterdir() if path.is_dir()) if cache_parent.is_dir() else []
    return candidates[0] if len(candidates) == 1 else cache_parent / "__unavailable__"


def sample_runtime_evidence_path(sample_id: str) -> Path:
    report_path = configured_path("report", "MWX_SCENE_TEST_REPORT")
    if not report_path.is_file():
        return report_path.parent / "__unavailable__"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    sample = next(
        (item for item in report.get("samples", []) if str(item.get("id")) == sample_id),
        None,
    )
    evidence_path = (sample or {}).get("evidence", {}).get("runtime_evidence")
    return Path(evidence_path) if evidence_path else report_path.parent / "__unavailable__"
