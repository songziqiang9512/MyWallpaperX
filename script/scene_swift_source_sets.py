#!/usr/bin/env python3

"""Load explicit, reusable Swift compilation boundaries for Scene tools."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST_PATH = Path(__file__).with_name("scene_swift_source_sets.json")


class SceneSwiftSourceSetError(ValueError):
    """The source-set manifest cannot produce a safe, deterministic set."""


def _manifest(
    manifest_path: Path,
) -> dict[str, Any]:
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SceneSwiftSourceSetError(f"cannot load {manifest_path}: {error}") from error
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise SceneSwiftSourceSetError("source-set manifest must use schema version 1")
    if not isinstance(payload.get("sets"), dict):
        raise SceneSwiftSourceSetError("source-set manifest must define an object of sets")
    return payload


def scene_swift_source_relpaths(
    set_name: str,
    repository_root: Path = REPOSITORY_ROOT,
    manifest_path: Path = DEFAULT_MANIFEST_PATH,
) -> tuple[str, ...]:
    """Expand one named set into validated repository-relative POSIX paths."""

    payload = _manifest(manifest_path)
    source_root_value = payload.get("source_root")
    if not isinstance(source_root_value, str):
        raise SceneSwiftSourceSetError("source_root must be a repository-relative path")
    source_root = PurePosixPath(source_root_value)
    if source_root.is_absolute() or ".." in source_root.parts:
        raise SceneSwiftSourceSetError("source_root must stay inside the repository")

    sets = payload["sets"]
    expanded: list[str] = []
    active: list[str] = []

    def append_set(name: str) -> None:
        if name in active:
            cycle = " -> ".join([*active, name])
            raise SceneSwiftSourceSetError(f"source-set include cycle: {cycle}")
        definition = sets.get(name)
        if not isinstance(definition, dict):
            raise SceneSwiftSourceSetError(f"unknown source set: {name}")
        includes = definition.get("includes")
        sources = definition.get("sources")
        if not isinstance(includes, list) or not all(
            isinstance(value, str) for value in includes
        ):
            raise SceneSwiftSourceSetError(f"{name}: includes must be strings")
        if not isinstance(sources, list) or not all(
            isinstance(value, str) for value in sources
        ):
            raise SceneSwiftSourceSetError(f"{name}: sources must be strings")

        active.append(name)
        for include in includes:
            append_set(include)
        active.pop()
        for value in sources:
            relative = PurePosixPath(value)
            if relative.is_absolute() or ".." in relative.parts:
                raise SceneSwiftSourceSetError(f"{name}: unsafe source path: {value}")
            if relative.suffix != ".swift":
                raise SceneSwiftSourceSetError(f"{name}: source is not Swift: {value}")
            expanded.append((source_root / relative).as_posix())

    append_set(set_name)
    duplicates = sorted({value for value in expanded if expanded.count(value) > 1})
    if duplicates:
        raise SceneSwiftSourceSetError(
            f"{set_name}: duplicate expanded sources: {', '.join(duplicates)}"
        )

    resolved_repository = repository_root.resolve()
    for value in expanded:
        source = repository_root / value
        try:
            source.resolve().relative_to(resolved_repository)
        except ValueError as error:
            raise SceneSwiftSourceSetError(f"source escapes repository: {value}") from error
        if not source.is_file():
            raise SceneSwiftSourceSetError(f"source is missing: {value}")
    return tuple(expanded)


def scene_swift_sources(
    set_name: str,
    repository_root: Path = REPOSITORY_ROOT,
    manifest_path: Path = DEFAULT_MANIFEST_PATH,
) -> tuple[Path, ...]:
    """Expand one named set into absolute paths suitable for swiftc."""

    return tuple(
        repository_root / relative
        for relative in scene_swift_source_relpaths(
            set_name,
            repository_root=repository_root,
            manifest_path=manifest_path,
        )
    )
