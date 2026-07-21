#!/usr/bin/env python3
"""Capture-infrastructure helpers for the Web wallpaper benchmark."""

from __future__ import annotations

import hashlib
import os
import plistlib
import re
import shutil
import struct
import subprocess
import time
import zlib
from pathlib import Path
from typing import Any


class AppIdentityError(RuntimeError):
    pass


def require_fresh_output_dir(path: Path) -> Path:
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise FileExistsError(f"output directory is not empty: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _app_bundle_for(binary: Path) -> Path:
    for parent in binary.parents:
        if parent.suffix == ".app":
            return parent
    raise AppIdentityError(f"app binary is not inside an .app bundle: {binary}")


def _verify_signature(bundle: Path) -> None:
    result = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", "--deep", "--verbose=2", str(bundle)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise AppIdentityError(f"strict code signature verification failed for {bundle}: {detail}")


def _codesign_values(bundle: Path) -> dict[str, str | None]:
    result = subprocess.run(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(bundle)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AppIdentityError(f"failed to read code signature metadata for {bundle}")
    output = "\n".join((result.stdout, result.stderr))

    def value(name: str) -> str | None:
        match = re.search(rf"^{re.escape(name)}=(.+)$", output, flags=re.MULTILINE)
        if not match:
            return None
        parsed = match.group(1).strip()
        return None if parsed in {"", "not set"} else parsed

    values = {
        "bundle_identifier": value("Identifier"),
        "team_identifier": value("TeamIdentifier"),
        "cdhash": value("CDHash"),
    }
    if not values["bundle_identifier"] or not values["cdhash"]:
        raise AppIdentityError(f"incomplete code signature metadata for {bundle}")
    return values


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _identity_values(bundle: Path, binary: Path) -> dict[str, Any]:
    info_path = bundle / "Contents/Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise AppIdentityError(f"failed to read {info_path}: {error}") from error
    return {
        **_codesign_values(bundle),
        "short_version": info.get("CFBundleShortVersionString"),
        "bundle_version": info.get("CFBundleVersion"),
        "executable_sha256": _sha256(binary),
    }


def _ditto_copy(source: Path, destination: Path) -> None:
    result = subprocess.run(
        ["/usr/bin/ditto", str(source), str(destination)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise AppIdentityError(f"failed to stage signed app with ditto: {detail}")


def stage_signed_app(source_binary: Path, output_dir: Path) -> tuple[Path, dict[str, Any]]:
    source_binary = source_binary.expanduser().resolve()
    if not source_binary.is_file():
        raise AppIdentityError(f"app binary not found: {source_binary}")
    source_bundle = _app_bundle_for(source_binary)
    _verify_signature(source_bundle)

    runtime_root = output_dir / f"runtime-app-{os.getpid()}-{time.time_ns()}"
    runtime_bundle = runtime_root / source_bundle.name
    runtime_root.mkdir(parents=False, exist_ok=False)
    _ditto_copy(source_bundle, runtime_bundle)
    relative_binary = source_binary.relative_to(source_bundle)
    runtime_binary = runtime_bundle / relative_binary
    _verify_signature(runtime_bundle)

    identity = {
        **_identity_values(runtime_bundle, runtime_binary),
        "source_bundle_path": str(source_bundle),
        "source_executable_path": str(source_binary),
        "runtime_bundle_path": str(runtime_bundle),
        "runtime_executable_path": str(runtime_binary),
        "source_signature_verified": True,
        "verified_before": True,
        "verified_after": None,
    }
    return runtime_binary, identity


def verify_staged_app(identity: dict[str, Any]) -> None:
    bundle = Path(identity["runtime_bundle_path"])
    binary = Path(identity["runtime_executable_path"])
    try:
        _verify_signature(bundle)
        current = _identity_values(bundle, binary)
    except (AppIdentityError, OSError):
        identity["verified_after"] = False
        raise
    expected_keys = (
        "bundle_identifier",
        "team_identifier",
        "cdhash",
        "short_version",
        "bundle_version",
        "executable_sha256",
    )
    mismatches = [key for key in expected_keys if current.get(key) != identity.get(key)]
    identity["verified_after"] = not mismatches
    if mismatches:
        raise AppIdentityError(f"staged app identity changed during benchmark: {', '.join(mismatches)}")


def logged_snapshot_paths(metadata: dict[str, Any], sample_dir: Path) -> list[Path]:
    root = sample_dir.resolve()
    accepted: list[Path] = []
    for snapshot in metadata.get("snapshots") or []:
        raw_path = snapshot.get("path")
        if not raw_path:
            continue
        candidate = Path(str(raw_path)).expanduser()
        if not candidate.is_absolute():
            candidate = sample_dir / candidate
        candidate = candidate.resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            continue
        if candidate.is_file() and candidate not in accepted:
            accepted.append(candidate)
    return sorted(accepted)


def has_window_snapshot(paths: list[str] | list[Path]) -> bool:
    return any(Path(path).stem.endswith("-window") for path in paths)


def _paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - upper_left))
    return (left, up, upper_left)[distances.index(min(distances))]


def _decode_png_rows(path: Path) -> tuple[int, int, int, int, list[bytes]] | None:
    try:
        payload = path.read_bytes()
        if payload[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        offset = 8
        width = height = bit_depth = color_type = interlace = None
        compressed = bytearray()
        while offset + 12 <= len(payload):
            length = struct.unpack(">I", payload[offset : offset + 4])[0]
            kind = payload[offset + 4 : offset + 8]
            data = payload[offset + 8 : offset + 8 + length]
            offset += 12 + length
            if kind == b"IHDR":
                width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", data)
            elif kind == b"IDAT":
                compressed.extend(data)
            elif kind == b"IEND":
                break
        channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
        if not width or not height or bit_depth != 8 or interlace != 0 or channels is None:
            return None
        decoded = zlib.decompress(compressed)
        stride = width * channels
        previous = bytearray(stride)
        cursor = 0
        rows: list[bytes] = []
        for _ in range(height):
            filter_type = decoded[cursor]
            source = decoded[cursor + 1 : cursor + 1 + stride]
            cursor += stride + 1
            row = bytearray(stride)
            for index, value in enumerate(source):
                left = row[index - channels] if index >= channels else 0
                up = previous[index]
                upper_left = previous[index - channels] if index >= channels else 0
                if filter_type == 0:
                    predictor = 0
                elif filter_type == 1:
                    predictor = left
                elif filter_type == 2:
                    predictor = up
                elif filter_type == 3:
                    predictor = (left + up) // 2
                elif filter_type == 4:
                    predictor = _paeth(left, up, upper_left)
                else:
                    return None
                row[index] = (value + predictor) & 0xFF
            rows.append(bytes(row))
            previous = row
    except (IndexError, OSError, struct.error, ValueError, zlib.error):
        return None
    color_channels = 1 if color_type in {0, 4} else 3
    return width, height, channels, color_channels, rows


def png_has_non_black_pixel(path: Path, threshold: int = 2) -> bool:
    decoded = _decode_png_rows(path)
    if decoded is None:
        return False
    width, _, channels, color_channels, rows = decoded
    stride = width * channels
    return any(
        row[pixel + channel] > threshold
        for row in rows
        for pixel in range(0, stride, channels)
        for channel in range(color_channels)
    )


def png_motion_metrics(
    first_path: Path,
    second_path: Path,
    threshold: int = 2,
) -> dict[str, float] | None:
    first = _decode_png_rows(first_path)
    second = _decode_png_rows(second_path)
    if first is None or second is None or first[:4] != second[:4]:
        return None
    width, height, channels, color_channels, first_rows = first
    second_rows = second[4]
    changed_pixels = 0
    total_delta = 0
    for first_row, second_row in zip(first_rows, second_rows):
        for pixel in range(0, width * channels, channels):
            deltas = [
                abs(first_row[pixel + channel] - second_row[pixel + channel])
                for channel in range(color_channels)
            ]
            total_delta += sum(deltas)
            if max(deltas) > threshold:
                changed_pixels += 1
    pixel_count = width * height
    component_count = pixel_count * color_channels
    return {
        "mean_delta": total_delta / max(component_count * 255, 1),
        "changed_ratio": changed_pixels / max(pixel_count, 1),
    }


def capture_non_black_screenshot(path: Path) -> Path | None:
    executable = shutil.which("screencapture")
    if not executable:
        return None
    result = subprocess.run(
        [executable, "-x", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not path.is_file() or path.stat().st_size == 0:
        return None
    return path if png_has_non_black_pixel(path) else None
