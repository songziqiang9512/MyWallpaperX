#!/usr/bin/env python3
"""Structured authored-effect census over Scene samples.

Read-only: opens sample packages and the stock asset bundle, never writes to
either. Produces per-effect reference counts joined with the stock definition
shape (pass count, materials, shaders, combos, texture slots) so effect backend
selection is driven by authored graph structure instead of route-only totals.
"""

from __future__ import annotations

import argparse
import json
import struct
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterator


DEFAULT_SAMPLES = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_STOCK = Path(__file__).resolve().parent.parent / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"


class PkgArchive:
    """Minimal PKGV reader matching ScenePkgReader.swift."""

    def __init__(self, path: Path) -> None:
        self.entries: dict[str, tuple[int, int]] = {}
        self._blob = path.read_bytes()
        cursor = 0

        def u32() -> int:
            nonlocal cursor
            value = struct.unpack_from("<I", self._blob, cursor)[0]
            cursor += 4
            return value

        magic_len = u32()
        magic = self._blob[cursor:cursor + magic_len].decode("utf-8", "replace")
        cursor += magic_len
        if not magic.startswith("PKGV"):
            raise ValueError(f"bad magic {magic!r}")
        for _ in range(u32()):
            path_len = u32()
            name = self._blob[cursor:cursor + path_len].decode("utf-8", "replace")
            cursor += path_len
            offset = u32()
            size = u32()
            self.entries[name.replace("\\", "/")] = (offset, size)
        self._data_start = cursor

    def read(self, name: str) -> bytes | None:
        hit = self.entries.get(name)
        if hit is None:
            return None
        offset, size = hit
        start = self._data_start + offset
        return self._blob[start:start + size]


def load_json(raw: bytes | None) -> Any:
    if not raw:
        return None
    for encoding in ("utf-8-sig", "utf-16", "latin-1"):
        try:
            return json.loads(raw.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    return None


def normalize(path: str) -> str:
    return path.strip().replace("\\", "/").lstrip("./").lower()


def effect_id(path: str) -> str:
    """effects/scroll/effect.json -> scroll;
    effects/workshop/<id>/<name>/effect.json -> workshop:<id>/<name>."""
    parts = normalize(path).split("/")
    if len(parts) >= 2 and parts[0] == "effects":
        if parts[1] == "workshop" and len(parts) >= 4:
            return "workshop:" + "/".join(parts[2:-1])
        return parts[1]
    return "/".join(parts[:-1]) or normalize(path)


def is_visible(value: Any) -> bool:
    """Match the runtime rule: only an explicit false hides; bindings stay visible."""
    return value is not False


def walk_objects(scene: dict[str, Any]) -> Iterator[dict[str, Any]]:
    for obj in scene.get("objects") or []:
        if isinstance(obj, dict):
            yield obj


def open_scene(sample: Path) -> tuple[dict[str, Any] | None, PkgArchive | None]:
    project = load_json((sample / "project.json").read_bytes()) if (sample / "project.json").is_file() else None
    entry = "scene.json"
    if isinstance(project, dict) and isinstance(project.get("file"), str):
        entry = Path(project["file"].strip().replace("\\", "/")).name or entry
    loose = sample / entry
    if loose.is_file():
        return load_json(loose.read_bytes()), None
    pkg_name = str(Path(entry).with_suffix(".pkg"))
    for name in dict.fromkeys([pkg_name, "scene.pkg"]):
        candidate = sample / name
        if candidate.is_file():
            archive = PkgArchive(candidate)
            return load_json(archive.read(entry) or archive.read("scene.json")), archive
    return None, None


def resolve_definition(
    path: str,
    stock_root: Path,
    archive: PkgArchive | None,
    base_dir: str = "",
) -> tuple[Any, str]:
    """Resolve a definition path, trying effect-relative then root-relative."""
    rel = normalize(path)
    candidates = [f"{base_dir}/{rel}", rel] if base_dir else [rel]
    if archive is not None:
        lowered = {key.lower(): key for key in archive.entries}
        for candidate in candidates:
            key = lowered.get(candidate)
            if key is not None:
                return load_json(archive.read(key)), "workshop"
    for candidate in candidates:
        file_path = stock_root / candidate
        if file_path.is_file():
            return load_json(file_path.read_bytes()), "stock"
    return None, "missing"


def definition_shape(
    definition: Any,
    definition_path: str,
    stock_root: Path,
    archive: PkgArchive | None,
) -> dict[str, Any]:
    """Join an effect definition with its materials to expose the graph shape."""
    if not isinstance(definition, dict):
        return {}
    base_dir = "/".join(normalize(definition_path).split("/")[:-1])
    passes = [p for p in definition.get("passes") or [] if isinstance(p, dict)]
    materials: list[str] = []
    shaders: list[str] = []
    targets: list[str] = []
    texture_slots = 0
    combos: set[str] = set()
    for entry in passes:
        material_path = entry.get("material")
        if isinstance(material_path, str):
            materials.append(normalize(material_path))
            material, _ = resolve_definition(material_path, stock_root, archive, base_dir)
            if isinstance(material, dict):
                for mpass in material.get("passes") or []:
                    if not isinstance(mpass, dict):
                        continue
                    shader = mpass.get("shader")
                    if isinstance(shader, str):
                        shaders.append(normalize(shader))
                    textures = mpass.get("textures")
                    if isinstance(textures, list):
                        texture_slots = max(texture_slots, len(textures))
                    combos.update((mpass.get("combos") or {}).keys())
        if isinstance(entry.get("target"), str):
            targets.append(entry["target"])
        combos.update((entry.get("combos") or {}).keys())
    return {
        "definition_passes": len(passes),
        "materials": sorted(set(materials)),
        "shaders": sorted(set(shaders)),
        "render_targets": sorted(set(targets)),
        "texture_slots": texture_slots,
        "combos": sorted(combos),
        "dependencies": [normalize(d) for d in definition.get("dependencies") or [] if isinstance(d, str)],
    }


def census(samples_root: Path, stock_root: Path) -> dict[str, Any]:
    records: dict[str, dict[str, Any]] = defaultdict(
        lambda: {
            "total_refs": 0,
            "visible_refs": 0,
            "samples": set(),
            "visible_samples": set(),
            "authored_pass_counts": set(),
            "authored_constants": set(),
            "authored_combos": set(),
            "authored_textures": set(),
            "paths": set(),
            "origin": set(),
            "shape": {},
        }
    )
    per_sample: dict[str, dict[str, int]] = {}

    for sample in sorted(p for p in samples_root.iterdir() if p.is_dir()):
        scene, archive = open_scene(sample)
        if not isinstance(scene, dict):
            continue
        counts: dict[str, int] = defaultdict(int)
        for obj in walk_objects(scene):
            layer_visible = is_visible(obj.get("visible"))
            for effect in obj.get("effects") or []:
                if not isinstance(effect, dict):
                    continue
                raw_path = effect.get("file")
                if not isinstance(raw_path, str):
                    continue
                key = effect_id(raw_path)
                record = records[key]
                record["paths"].add(normalize(raw_path))
                record["total_refs"] += 1
                record["samples"].add(sample.name)
                visible = layer_visible and is_visible(effect.get("visible"))
                if visible:
                    record["visible_refs"] += 1
                    record["visible_samples"].add(sample.name)
                    counts[key] += 1

                passes = [p for p in effect.get("passes") or [] if isinstance(p, dict)]
                record["authored_pass_counts"].add(len(passes))
                for entry in passes:
                    record["authored_constants"].update(
                        str(k).lower() for k in (entry.get("constantshadervalues") or {})
                    )
                    record["authored_combos"].update(str(k) for k in (entry.get("combos") or {}))
                    textures = entry.get("textures")
                    if isinstance(textures, list):
                        for index, texture in enumerate(textures):
                            if isinstance(texture, str) and texture.strip():
                                record["authored_textures"].add(index)

                if not record["shape"]:
                    definition, origin = resolve_definition(raw_path, stock_root, archive)
                    record["origin"].add(origin)
                    record["shape"] = definition_shape(definition, raw_path, stock_root, archive)
        per_sample[sample.name] = dict(counts)

    return {
        "effects": {
            key: {
                "total_refs": value["total_refs"],
                "visible_refs": value["visible_refs"],
                "sample_count": len(value["samples"]),
                "visible_sample_count": len(value["visible_samples"]),
                "visible_samples": sorted(value["visible_samples"]),
                "authored_pass_counts": sorted(value["authored_pass_counts"]),
                "authored_constants": sorted(value["authored_constants"]),
                "authored_combos": sorted(value["authored_combos"]),
                "authored_texture_slots": sorted(value["authored_textures"]),
                "paths": sorted(value["paths"]),
                "origin": sorted(value["origin"]),
                **value["shape"],
            }
            for key, value in records.items()
        },
        "per_sample": per_sample,
    }


def summarize(result: dict[str, Any], top: int) -> str:
    rows = sorted(
        result["effects"].items(),
        key=lambda item: (-item[1]["visible_refs"], item[0]),
    )
    lines = [
        f"{'effect':<22}{'vis':>5}{'all':>5}{'smp':>5}{'defP':>6}{'auP':>16}{'tex':>5}  {'targets':<10}{'combos'}"
    ]
    for key, value in rows[:top]:
        lines.append(
            f"{key:<22}{value['visible_refs']:>5}{value['total_refs']:>5}"
            f"{value['visible_sample_count']:>5}{value.get('definition_passes', 0):>6}"
            f"{str(value['authored_pass_counts']):>16}{value.get('texture_slots', 0):>5}  "
            f"{str(len(value.get('render_targets', []))):<10}{','.join(value.get('combos', []))}"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES)
    parser.add_argument("--stock-root", type=Path, default=DEFAULT_STOCK)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--top", type=int, default=60)
    args = parser.parse_args()

    result = census(args.samples_root, args.stock_root)
    if args.json:
        args.json.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(summarize(result, args.top))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
