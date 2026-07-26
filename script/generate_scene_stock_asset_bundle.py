#!/usr/bin/env python3
"""Build a clean-room placeholder mirror of Wallpaper Engine playback assets."""

from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TEX_HEADER = b"TEXV0005\0TEXI0001\0"
TEX_CONTAINER_VERSION = b"TEXB0002\0"
JSON_PLACEHOLDER_BYTES = b"{}\n"
SIDECAR_PLACEHOLDER_BYTES = b'{\n  "format": "rgba8888",\n  "nomip": true\n}\n'
SHADER_PLACEHOLDER_BYTES = b"// MyWallpaperX stock asset placeholder\n"
JAVASCRIPT_PLACEHOLDER_BYTES = b"// MyWallpaperX stock asset placeholder\n"
SOURCE_IMAGE_EXTENSIONS = {".gif", ".png", ".tga"}
SHADER_EXTENSIONS = {".frag", ".geom", ".h", ".vert"}


def png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        raise ValueError("placeholder is not a valid PNG with an IHDR chunk")
    width, height = struct.unpack(">II", data[16:24])
    if width <= 0 or height <= 0:
        raise ValueError("placeholder PNG has invalid dimensions")
    return width, height


def placeholder_tex_bytes(png_data: bytes) -> bytes:
    width, height = png_dimensions(png_data)
    payload_size = len(png_data)
    return b"".join([
        TEX_HEADER,
        struct.pack("<IIIIIII", 0, 0, width, height, width, height, 0),
        TEX_CONTAINER_VERSION,
        struct.pack("<I", 1),
        struct.pack("<I", 1),
        struct.pack("<II", width, height),
        struct.pack("<IIi", 0, payload_size, payload_size),
        png_data,
    ])


def asset_extension(path: Path) -> str:
    return ".tex-json" if path.name.lower().endswith(".tex-json") else path.suffix.lower()


def classify_asset(assets_root: Path, asset: Path) -> tuple[bool, str]:
    relative = asset.relative_to(assets_root)
    parts = [part.lower() for part in relative.parts]
    top_level = parts[0]
    basename = asset.name.lower()
    extension = asset_extension(asset)

    if top_level == "presets":
        return False, "editor_preset"
    if top_level == "scenes":
        return False, "editor_scene_fixture"
    if top_level == "particles":
        return False, "editor_particle_example"
    if any(part.startswith("preview") or part == "particleelementpreviews" for part in parts):
        return False, "editor_preview"
    if "editor" in parts or basename.startswith("editor"):
        return False, "editor_path"
    if basename.endswith("_preview.gif"):
        return False, "editor_preview"
    if top_level == "fonts" and extension == ".txt":
        return False, "license_text"
    if basename == "webthumbnailfallback.png":
        return False, "editor_thumbnail"
    if extension in SOURCE_IMAGE_EXTENSIONS and asset.with_suffix(".tex").is_file():
        return False, "compiled_texture_source"
    return True, "runtime_candidate"


def runtime_assets(source_root: Path) -> tuple[list[Path], Counter[str]]:
    assets_root = source_root / "assets"
    if not assets_root.is_dir():
        raise FileNotFoundError(f"missing Wallpaper Engine assets root: {assets_root}")

    included: list[Path] = []
    exclusions: Counter[str] = Counter()
    for asset in sorted(path for path in assets_root.rglob("*") if path.is_file()):
        is_included, reason = classify_asset(assets_root, asset)
        if is_included:
            included.append(asset)
        else:
            exclusions[reason] += 1
    if not included:
        raise ValueError(f"no playback assets found under {assets_root}")
    return included, exclusions


def placeholder_payload(
    asset: Path,
    assets_root: Path,
    png_data: bytes,
    font_placeholder_root: Path,
) -> bytes:
    relative = asset.relative_to(assets_root)
    extension = asset_extension(asset)
    if relative.parts[0].lower() == "fonts" and extension in {".otf", ".ttf"}:
        font_path = font_placeholder_root / relative.relative_to("fonts")
        if not font_path.is_file():
            raise FileNotFoundError(f"missing official-name font placeholder: {font_path}")
        return font_path.read_bytes()
    if extension == ".tex":
        return placeholder_tex_bytes(png_data)
    if extension == ".tex-json":
        return SIDECAR_PLACEHOLDER_BYTES
    if extension == ".json":
        return JSON_PLACEHOLDER_BYTES
    if extension == ".png":
        return png_data
    if extension in SHADER_EXTENSIONS:
        return SHADER_PLACEHOLDER_BYTES
    if extension == ".js":
        return JAVASCRIPT_PLACEHOLDER_BYTES
    raise ValueError(f"unsupported playback asset extension: {extension} ({relative})")


def build_bundle(
    source_root: Path,
    png_placeholder: Path,
    font_placeholder_root: Path,
    output_root: Path,
) -> dict[str, object]:
    source_root = source_root.expanduser().resolve()
    output_root = output_root.expanduser().resolve()
    font_placeholder_root = font_placeholder_root.expanduser().resolve()
    if output_root.exists():
        raise FileExistsError(f"output already exists: {output_root}")

    png_data = png_placeholder.expanduser().resolve().read_bytes()
    png_dimensions(png_data)
    included, exclusions = runtime_assets(source_root)
    assets_root = source_root / "assets"
    extension_counts: Counter[str] = Counter()
    for asset in included:
        relative = asset.relative_to(source_root)
        destination = output_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(
            placeholder_payload(asset, assets_root, png_data, font_placeholder_root)
        )
        extension_counts[asset_extension(asset)] += 1

    return {
        "output": str(output_root),
        "runtime_asset_count": len(included),
        "excluded_asset_count": sum(exclusions.values()),
        "runtime_extension_counts": dict(sorted(extension_counts.items())),
        "exclusion_counts": dict(sorted(exclusions.items())),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--png-placeholder", required=True, type=Path)
    parser.add_argument("--font-placeholder-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(json.dumps(build_bundle(
        args.source_root,
        args.png_placeholder,
        args.font_placeholder_root,
        args.output,
    ), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
