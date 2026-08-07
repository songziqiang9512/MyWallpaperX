#!/usr/bin/env python3
"""Resolve tracked Scene fixture identity separately from machine-local paths."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Mapping


ENVIRONMENT_KEYS = {
    "sample_root": "MWX_SCENE_TEST_SAMPLE_ROOT",
    "runtime_homes": "MWX_SCENE_TEST_RUNTIME_HOMES",
    "report": "MWX_SCENE_TEST_REPORT",
}


def _object(path: Path, label: str) -> dict[str, object]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load {label} {path}: {error}") from error
    if not isinstance(payload, dict):
        raise ValueError(f"{label} must be a JSON object: {path}")
    return payload


def _resolved_path(raw: object, repository_root: Path, key: str) -> str:
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError(f"Scene fixture {key} must be a non-empty path")
    path = Path(raw).expanduser()
    resolved = path.resolve() if path.is_absolute() else (repository_root / path).resolve()
    return str(resolved)


def load_fixture_config(
    config_path: Path,
    repository_root: Path,
    *,
    environ: Mapping[str, str] | None = None,
) -> dict[str, object]:
    """Return a schema-1-compatible object containing resolved local paths."""
    config_path = config_path.expanduser().resolve()
    repository_root = repository_root.expanduser().resolve()
    environment = os.environ if environ is None else environ
    tracked = _object(config_path, "tracked Scene fixture config")
    schema_version = tracked.get("schema_version")
    values: dict[str, object]
    if schema_version == 1:
        values = {
            key: value for key, value in tracked.items() if key in ENVIRONMENT_KEYS
        }
    elif schema_version == 2:
        configured_environment = tracked.get("environment")
        if configured_environment not in (None, ENVIRONMENT_KEYS):
            raise ValueError(
                "Scene fixture environment mapping does not match the supported keys"
            )
        local_value = tracked.get("local_config")
        if not isinstance(local_value, str) or not local_value.strip():
            raise ValueError("Scene fixture schema 2 requires local_config")
        local_path = (repository_root / local_value).resolve()
        codex_root = (repository_root / ".codex").resolve()
        try:
            local_path.relative_to(codex_root)
        except ValueError as error:
            raise ValueError("Scene fixture local_config must stay inside .codex") from error
        values = {}
        if local_path.is_file():
            local = _object(local_path, "local Scene fixture config")
            if local.get("schema_version") not in (None, 1):
                raise ValueError("local Scene fixture config schema must be 1")
            values.update(
                {
                    key: value
                    for key, value in local.items()
                    if key in ENVIRONMENT_KEYS
                }
            )
    else:
        raise ValueError(f"unsupported Scene real fixture config: {config_path}")

    for key, environment_name in ENVIRONMENT_KEYS.items():
        override = environment.get(environment_name)
        if override:
            values[key] = override
    return {
        "schema_version": 1,
        **{
            key: _resolved_path(value, repository_root, key)
            for key, value in values.items()
        },
    }
