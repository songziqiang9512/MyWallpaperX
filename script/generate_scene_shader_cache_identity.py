#!/usr/bin/env python3
"""Build-time Scene shader producer identity; never scans sources at runtime."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

SCENE = Path("MyWallpaperX/Core/SteamWorkshopScene")
SEMANTIC_DIRECTORIES = (
    SCENE / "Compilation",
    SCENE / "Format",
    SCENE / "Rendering/Bindings",
    SCENE / "Resources/Assets",
    SCENE / "Resources/Textures",
)
SEMANTIC_FILES = (
    Path("script/generate_scene_shader_cache_identity.py"),
)
TOOLCHAIN_FILES = (
    Path("script/scene_shader_compiler_dependencies.json"),
    Path("MyWallpaperX/Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/product-manifest.json"),
    Path("MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"),
    Path("MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"),
)
RESOURCE_NAME = "SceneShaderCacheIdentity.json"


def _digest(root: Path, files: list[Path], configuration: dict[str, str]) -> str:
    digest = hashlib.sha256()
    def append(value: bytes) -> None:
        digest.update(len(value).to_bytes(8, "big"))
        digest.update(value)
    append(b"mwx-scene-shader-producer-v1")
    append(json.dumps(configuration, sort_keys=True, separators=(",", ":")).encode())
    for relative in sorted(set(files), key=lambda path: path.as_posix()):
        source = root / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"identity input is not a regular file: {relative}")
        append(relative.as_posix().encode())
        # Bound memory even for native helper binaries. Hashes are framed by path.
        content = hashlib.sha256()
        with source.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                content.update(block)
        append(content.digest())
    return digest.hexdigest()


def build_identity(root: Path, configuration: dict[str, str] | None = None) -> dict:
    files = list(SEMANTIC_FILES)
    for relative in SEMANTIC_DIRECTORIES:
        directory = root / relative
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError(f"identity source directory is missing: {relative}")
        files.extend(path.relative_to(root) for path in directory.rglob("*.swift"))
    return {
        "schemaVersion": 1,
        "semantics": _digest(root, files, configuration or {}),
        "toolchain": _digest(root, list(TOOLCHAIN_FILES), {}),
    }


def write_identity(output: Path, identity: dict) -> bool:
    data = (json.dumps(identity, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if output.is_file() and not output.is_symlink() and output.read_bytes() == data:
        # App resources must remain readable after installation by another user.
        if output.stat().st_mode & 0o777 != 0o644:
            output.chmod(0o644)
        return False
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".scene-cache-identity-", dir=output.parent)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.replace(name, output)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    configuration = {key: os.environ.get(key, "") for key in (
        "SDK_NAME", "SWIFT_VERSION", "SWIFT_OPTIMIZATION_LEVEL",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_SWIFT_FLAGS", "XCODE_VERSION_ACTUAL",
        "XCODE_PRODUCT_BUILD_VERSION", "SDK_PRODUCT_BUILD_VERSION",
    )}
    write_identity(args.output, build_identity(args.root.resolve(), configuration))


if __name__ == "__main__":
    main()
