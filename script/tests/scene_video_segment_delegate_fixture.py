"""Compile the production NSData segment delegate for standalone Swift fixtures."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess


SCENE_ROOT = Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene"


def segment_delegate_sources(scene_root: Path = SCENE_ROOT) -> tuple[Path, Path]:
    providers = scene_root / "Resources/Providers"
    return providers / "SceneVideoSegmentDelegate.h", providers / "SceneVideoSegmentDelegate.m"


def compile_segment_delegate(
    directory: Path,
    *,
    scene_root: Path = SCENE_ROOT,
    environment: dict[str, str] | None = None,
    target: str | None = None,
    evidence_directory: Path | None = None,
    allow_legacy: bool = False,
) -> list[str]:
    """Return Swift bridge/link arguments; historical sources keep their own ABI."""
    header, implementation = segment_delegate_sources(scene_root)
    if allow_legacy and not header.exists() and not implementation.exists():
        return []
    if not header.is_file() or not implementation.is_file():
        raise RuntimeError(f"incomplete production segment delegate: {header}, {implementation}")
    output = directory / "SceneVideoSegmentDelegate.o"
    cache = directory / "segment-clang-cache"
    command = ["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fmodules",
        "-fmodules-cache-path=" + str(cache), "-c", str(implementation), "-o", str(output)]
    if target is not None:
        command.extend(["-target", target])
    compiler_environment = dict(os.environ if environment is None else environment)
    compiler_environment["CLANG_MODULE_CACHE_PATH"] = str(cache)
    result = subprocess.run(command, env=compiler_environment,
        capture_output=True, text=True, timeout=30)
    evidence = directory if evidence_directory is None else evidence_directory
    (evidence / "segment-delegate-compile.json").write_text(json.dumps({
        "argv": command, "exit": result.returncode,
        "stdout": result.stdout, "stderr": result.stderr,
    }, indent=2) + "\n")
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return ["-import-objc-header", str(header), str(output)]
