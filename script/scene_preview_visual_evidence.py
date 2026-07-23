#!/usr/bin/env python3
"""Build advisory Scene screenshot comparisons from Steam preview assets."""

from __future__ import annotations

import binascii
import hashlib
import json
import math
import shutil
import struct
import subprocess
import zlib
from pathlib import Path
from typing import Any

from web_benchmark_capture import png_rgb_pixels


SUPPORTED_PREVIEW_SUFFIXES = {".gif", ".jpeg", ".jpg", ".png"}
GRID_SIZE = 16


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def project_preview_path(sample_root: Path) -> tuple[Path | None, str | None]:
    root = sample_root.resolve()
    project_path = root / "project.json"
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        return None, f"project preview metadata unavailable: {error}"
    raw_preview = project.get("preview")
    if not isinstance(raw_preview, str) or not raw_preview.strip():
        return None, "project preview is not declared"
    normalized = raw_preview.strip().replace("\\", "/")
    relative = Path(normalized)
    if relative.is_absolute() or ".." in relative.parts:
        return None, "project preview path escapes the sample root"
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None, "project preview path escapes the sample root"
    if not candidate.is_file():
        return None, "project preview file is missing"
    if candidate.suffix.lower() not in SUPPORTED_PREVIEW_SUFFIXES:
        return None, f"project preview format is unsupported: {candidate.suffix.lower()}"
    return candidate, None


def _prepare_preview_png(source: Path, destination: Path) -> str:
    if source.suffix.lower() == ".png":
        shutil.copy2(source, destination)
        return "still"
    result = subprocess.run(
        [
            "/usr/bin/sips",
            "-s",
            "format",
            "png",
            str(source),
            "--out",
            str(destination),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not destination.is_file():
        detail = (result.stderr or result.stdout).strip()
        raise ValueError(f"preview conversion failed: {detail or 'sips produced no image'}")
    return "first-frame-via-sips" if source.suffix.lower() == ".gif" else "still-via-sips"


def _center_crop(
    source_width: int,
    source_height: int,
    target_width: int,
    target_height: int,
) -> tuple[int, int, int, int]:
    if source_width * target_height > source_height * target_width:
        width = max(1, source_height * target_width // target_height)
        return (source_width - width) // 2, 0, width, source_height
    height = max(1, source_width * target_height // target_width)
    return 0, (source_height - height) // 2, source_width, height


def _grid_rgb(
    image: tuple[int, int, list[bytes]],
    crop: tuple[int, int, int, int],
    size: int = GRID_SIZE,
) -> list[tuple[int, int, int]]:
    _, _, rows = image
    crop_x, crop_y, crop_width, crop_height = crop
    values: list[tuple[int, int, int]] = []
    for grid_y in range(size):
        start_y = crop_y + grid_y * crop_height // size
        end_y = crop_y + (grid_y + 1) * crop_height // size
        end_y = max(start_y + 1, end_y)
        for grid_x in range(size):
            start_x = crop_x + grid_x * crop_width // size
            end_x = crop_x + (grid_x + 1) * crop_width // size
            end_x = max(start_x + 1, end_x)
            red = green = blue = count = 0
            for y in range(start_y, end_y):
                row = rows[y]
                for x in range(start_x, end_x):
                    offset = x * 3
                    red += row[offset]
                    green += row[offset + 1]
                    blue += row[offset + 2]
                    count += 1
            values.append((red // count, green // count, blue // count))
    return values


def _luminance(color: tuple[int, int, int]) -> float:
    return (0.2126 * color[0]) + (0.7152 * color[1]) + (0.0722 * color[2])


def _mean_color(colors: list[tuple[int, int, int]]) -> tuple[float, float, float]:
    count = max(len(colors), 1)
    return tuple(sum(color[channel] for color in colors) / count for channel in range(3))


def _histogram(colors: list[tuple[int, int, int]]) -> dict[tuple[int, int, int], int]:
    histogram: dict[tuple[int, int, int], int] = {}
    for color in colors:
        key = tuple(component // 64 for component in color)
        histogram[key] = histogram.get(key, 0) + 1
    return histogram


def _dominant_color(histogram: dict[tuple[int, int, int], int]) -> list[int]:
    key = max(histogram, key=histogram.get, default=(0, 0, 0))
    return [min(component * 64 + 32, 255) for component in key]


def _saliency_centroid(colors: list[tuple[int, int, int]], size: int) -> tuple[float, float]:
    mean_luminance = sum(_luminance(color) for color in colors) / max(len(colors), 1)
    weighted_x = weighted_y = total_weight = 0.0
    for index, color in enumerate(colors):
        contrast = abs(_luminance(color) - mean_luminance)
        saturation = max(color) - min(color)
        weight = contrast + (0.35 * saturation)
        x = index % size
        y = index // size
        weighted_x += ((x + 0.5) / size) * weight
        weighted_y += ((y + 0.5) / size) * weight
        total_weight += weight
    if total_weight <= 0:
        return 0.5, 0.5
    return weighted_x / total_weight, weighted_y / total_weight


def directional_visual_metrics(
    preview_path: Path,
    capture_path: Path,
) -> dict[str, Any]:
    preview = png_rgb_pixels(preview_path)
    capture = png_rgb_pixels(capture_path)
    if preview is None or capture is None:
        raise ValueError("preview or capture PNG cannot be decoded")
    preview_width, preview_height, _ = preview
    capture_width, capture_height, _ = capture
    capture_crop = _center_crop(
        capture_width,
        capture_height,
        preview_width,
        preview_height,
    )
    preview_grid = _grid_rgb(
        preview,
        (0, 0, preview_width, preview_height),
    )
    capture_grid = _grid_rgb(capture, capture_crop)
    preview_luminance = [_luminance(color) for color in preview_grid]
    capture_luminance = [_luminance(color) for color in capture_grid]
    spatial_color_delta = sum(
        abs(reference[channel] - actual[channel])
        for reference, actual in zip(preview_grid, capture_grid)
        for channel in range(3)
    ) / (len(preview_grid) * 3 * 255)
    spatial_luminance_delta = sum(
        abs(reference - actual)
        for reference, actual in zip(preview_luminance, capture_luminance)
    ) / (len(preview_luminance) * 255)
    preview_mean = _mean_color(preview_grid)
    capture_mean = _mean_color(capture_grid)
    mean_color_delta = sum(
        abs(reference - actual)
        for reference, actual in zip(preview_mean, capture_mean)
    ) / (3 * 255)
    preview_histogram = _histogram(preview_grid)
    capture_histogram = _histogram(capture_grid)
    histogram_intersection = sum(
        min(count, capture_histogram.get(key, 0))
        for key, count in preview_histogram.items()
    ) / len(preview_grid)
    preview_centroid = _saliency_centroid(preview_grid, GRID_SIZE)
    capture_centroid = _saliency_centroid(capture_grid, GRID_SIZE)
    centroid_distance = math.dist(preview_centroid, capture_centroid) / math.sqrt(2)
    components = {
        "spatial_color_similarity": 1 - spatial_color_delta,
        "spatial_luminance_similarity": 1 - spatial_luminance_delta,
        "color_histogram_similarity": histogram_intersection,
        "mean_color_similarity": 1 - mean_color_delta,
        "saliency_centroid_similarity": 1 - min(centroid_distance, 1),
    }
    return {
        "preview_dimensions": {"width": preview_width, "height": preview_height},
        "capture_dimensions": {"width": capture_width, "height": capture_height},
        "capture_center_crop": {
            "x": capture_crop[0],
            "y": capture_crop[1],
            "width": capture_crop[2],
            "height": capture_crop[3],
        },
        "grid_size": GRID_SIZE,
        "preview_mean_rgb": [round(value, 2) for value in preview_mean],
        "capture_mean_rgb": [round(value, 2) for value in capture_mean],
        "preview_mean_luminance": round(sum(preview_luminance) / len(preview_luminance), 2),
        "capture_mean_luminance": round(sum(capture_luminance) / len(capture_luminance), 2),
        "preview_dominant_rgb": _dominant_color(preview_histogram),
        "capture_dominant_rgb": _dominant_color(capture_histogram),
        "preview_saliency_centroid": [round(value, 4) for value in preview_centroid],
        "capture_saliency_centroid": [round(value, 4) for value in capture_centroid],
        **{name: round(value, 4) for name, value in components.items()},
    }


def _resized_crop(
    image: tuple[int, int, list[bytes]],
    crop: tuple[int, int, int, int],
    width: int,
    height: int,
) -> list[bytes]:
    _, _, source_rows = image
    crop_x, crop_y, crop_width, crop_height = crop
    rows: list[bytes] = []
    for y in range(height):
        source_y = crop_y + min(crop_height - 1, y * crop_height // height)
        row = bytearray(width * 3)
        for x in range(width):
            source_x = crop_x + min(crop_width - 1, x * crop_width // width)
            source_offset = source_x * 3
            destination_offset = x * 3
            row[destination_offset : destination_offset + 3] = source_rows[source_y][
                source_offset : source_offset + 3
            ]
        rows.append(bytes(row))
    return rows


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return (
        struct.pack(">I", len(payload))
        + body
        + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)
    )


def _write_rgb_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    pixels = zlib.compress(b"".join(b"\x00" + row for row in rows))
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", pixels)
        + _png_chunk(b"IEND", b"")
    )


def _write_comparison_montage(
    preview_path: Path,
    capture_path: Path,
    capture_crop: tuple[int, int, int, int],
    destination: Path,
) -> None:
    preview = png_rgb_pixels(preview_path)
    capture = png_rgb_pixels(capture_path)
    if preview is None or capture is None:
        raise ValueError("preview or capture PNG cannot be decoded for montage")
    preview_width, preview_height, _ = preview
    if preview_width >= preview_height:
        panel_width = 384
        panel_height = max(1, round(384 * preview_height / preview_width))
    else:
        panel_height = 384
        panel_width = max(1, round(384 * preview_width / preview_height))
    preview_rows = _resized_crop(
        preview,
        (0, 0, preview_width, preview_height),
        panel_width,
        panel_height,
    )
    capture_rows = _resized_crop(
        capture,
        capture_crop,
        panel_width,
        panel_height,
    )
    gap = 12
    marker_height = 6
    canvas_width = panel_width * 2 + gap
    rows = [
        bytes((29, 156, 142)) * panel_width
        + bytes((24, 24, 24)) * gap
        + bytes((230, 126, 34)) * panel_width
        for _ in range(marker_height)
    ]
    rows.extend(
        preview_row + bytes((24, 24, 24)) * gap + capture_row
        for preview_row, capture_row in zip(preview_rows, capture_rows)
    )
    _write_rgb_png(destination, canvas_width, len(rows), rows)


def collect_preview_visual_evidence(
    sample_root: Path,
    capture_path: Path,
    result_dir: Path,
) -> dict[str, Any]:
    base = {
        "advisory": True,
        "gating": False,
        "reference_scope": "steam-preview-directional-only",
        "comparison_scope": "same-sample-change-only",
        "cross_sample_ranking": False,
        "absolute_threshold": None,
    }
    source, error = project_preview_path(sample_root)
    if source is None:
        return {**base, "status": "unavailable", "reason": error}
    reference_png = result_dir / "preview-reference.png"
    montage = result_dir / "preview-comparison.png"
    try:
        frame_policy = _prepare_preview_png(source, reference_png)
        metrics = directional_visual_metrics(reference_png, capture_path)
        crop = metrics["capture_center_crop"]
        _write_comparison_montage(
            reference_png,
            capture_path,
            (crop["x"], crop["y"], crop["width"], crop["height"]),
            montage,
        )
    except (OSError, ValueError) as conversion_error:
        reference_png.unlink(missing_ok=True)
        montage.unlink(missing_ok=True)
        return {
            **base,
            "status": "unavailable",
            "preview_relative_path": str(source.relative_to(sample_root.resolve())),
            "reason": str(conversion_error),
        }
    return {
        **base,
        "status": "available",
        "preview_relative_path": str(source.relative_to(sample_root.resolve())),
        "preview_sha256": _sha256(source),
        "animation_frame_policy": frame_policy,
        "reference_png": str(reference_png),
        "comparison_montage": str(montage),
        "metrics": metrics,
    }


def summarize_preview_visual_evidence(results: list[dict[str, Any]]) -> dict[str, Any]:
    evidence = [
        result.get("evidence", {}).get("preview_visual", {})
        for result in results
    ]
    available = [item for item in evidence if item.get("status") == "available"]
    return {
        "advisory": True,
        "gating": False,
        "comparison_scope": "same-sample-change-only",
        "cross_sample_ranking": False,
        "absolute_threshold": None,
        "available_count": len(available),
        "unavailable_count": len(evidence) - len(available),
    }
