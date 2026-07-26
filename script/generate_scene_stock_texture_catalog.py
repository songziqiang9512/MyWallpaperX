#!/usr/bin/env python3
"""Build a clean-room PNG placeholder mirror of Wallpaper Engine stock TEX paths."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_version(source_root: Path) -> str:
    version_path = source_root / "version.json"
    payload = json.loads(version_path.read_text(encoding="utf-8"))
    version = payload.get("version")
    if not isinstance(version, str) or not version.strip():
        raise ValueError(f"missing Wallpaper Engine version: {version_path}")
    return version.strip()


def texture_entries(source_root: Path) -> list[dict[str, Any]]:
    assets_root = source_root / "assets"
    if not assets_root.is_dir():
        raise FileNotFoundError(f"missing Wallpaper Engine assets root: {assets_root}")

    entries: list[dict[str, Any]] = []
    for texture in sorted(assets_root.rglob("*.tex")):
        if not texture.is_file():
            continue
        official_path = texture.relative_to(source_root)
        project_path = official_path.with_suffix(".png")
        sidecar = Path(f"{texture}-json")
        entries.append({
            "official_path": official_path.as_posix(),
            "project_path": project_path.as_posix(),
            "official_size_bytes": texture.stat().st_size,
            "official_sha256": sha256(texture),
            "official_sidecar_present": sidecar.is_file(),
        })
    if not entries:
        raise ValueError(f"no stock TEX files found under {assets_root}")
    return entries


def category_counts(entries: list[dict[str, Any]]) -> dict[str, int]:
    counts: Counter[str] = Counter()
    for entry in entries:
        parts = Path(entry["official_path"]).parts
        category = "/".join(parts[:3]) if parts[1] == "materials" else "/".join(parts[:2])
        counts[category] += 1
    return dict(sorted(counts.items()))


def build_catalog(
    source_root: Path,
    placeholder: Path,
    output_root: Path,
    steam_build_id: str,
) -> dict[str, Any]:
    source_root = source_root.expanduser().resolve()
    placeholder = placeholder.expanduser().resolve()
    output_root = output_root.expanduser().resolve()
    if output_root.exists():
        raise FileExistsError(f"output already exists: {output_root}")
    placeholder_bytes = placeholder.read_bytes()
    if not placeholder_bytes.startswith(PNG_SIGNATURE):
        raise ValueError(f"placeholder is not a PNG: {placeholder}")

    entries = texture_entries(source_root)
    catalog = {
        "schema_version": 1,
        "wallpaper_engine_version": load_version(source_root),
        "steam_build_id": steam_build_id,
        "evidence_scope": "stock TEX path identity only; no official payload copied",
        "mapping": {
            "official_extension": ".tex",
            "project_extension": ".png",
            "placeholder_only": True,
            "runtime_consumed": False,
        },
        "texture_count": len(entries),
        "category_counts": category_counts(entries),
        "placeholder_sha256": hashlib.sha256(placeholder_bytes).hexdigest(),
        "textures": entries,
    }

    output_root.mkdir(parents=True)
    shutil.copyfile(placeholder, output_root / "placeholder.png")
    for entry in entries:
        destination = output_root / entry["project_path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(placeholder_bytes)
    (output_root / "texture-catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    return catalog


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--placeholder", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--steam-build-id", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog = build_catalog(
        args.source_root,
        args.placeholder,
        args.output,
        args.steam_build_id,
    )
    print(json.dumps({
        "output": str(args.output.expanduser().resolve()),
        "version": catalog["wallpaper_engine_version"],
        "steam_build_id": catalog["steam_build_id"],
        "texture_count": catalog["texture_count"],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
