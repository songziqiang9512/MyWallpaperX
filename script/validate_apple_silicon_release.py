#!/usr/bin/env python3
"""Validate MyWallpaperX's effective arm64 settings and built app Mach-O closure."""

from __future__ import annotations

import argparse
import re
import stat
import subprocess
from pathlib import Path


OWN_TARGETS = ("MyWallpaperX", "MyWallpaperXWallpaperDaemon")
CONFIGURATIONS = ("Debug", "Release")
MINIMUM_MACOS = "26.0"
REQUIRED_BUNDLE_EXECUTABLES = (
    Path("Contents/MacOS/MyWallpaperX"),
    Path("Contents/Helpers/MyWallpaperXWallpaperDaemon"),
    Path("Contents/Helpers/glslang"),
    Path("Contents/Helpers/spirv-cross"),
)
THIRD_PARTY_HELPERS = {
    Path("Contents/Helpers/glslang"),
    Path("Contents/Helpers/spirv-cross"),
}
SYSTEM_DEPENDENCY_PREFIXES = ("/usr/lib/", "/System/Library/")
SAFE_RPATH_PREFIXES = ("@executable_path/", "@loader_path/")


def run_checked(command: list[str], *, cwd: Path | None = None) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"{' '.join(command)} failed: {detail}")
    return completed.stdout


def parse_build_settings(output: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    for line in output.splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+) = (.*)$", line)
        if match:
            settings[match.group(1)] = match.group(2).strip()
    return settings


def validate_project(project: Path) -> None:
    if not project.is_dir():
        raise RuntimeError(f"Xcode project does not exist: {project}")
    for target in OWN_TARGETS:
        for configuration in CONFIGURATIONS:
            output = run_checked(
                [
                    "xcodebuild",
                    "-project",
                    project.name,
                    "-target",
                    target,
                    "-configuration",
                    configuration,
                    "-showBuildSettings",
                ],
                cwd=project.parent,
            )
            settings = parse_build_settings(output)
            architectures = settings.get("ARCHS", "").split()
            if architectures != ["arm64"]:
                raise RuntimeError(
                    f"{target} {configuration} ARCHS must be exactly arm64; got {architectures}"
                )
            deployment = settings.get("MACOSX_DEPLOYMENT_TARGET")
            if deployment != MINIMUM_MACOS:
                raise RuntimeError(
                    f"{target} {configuration} deployment target must be {MINIMUM_MACOS}; "
                    f"got {deployment or 'missing'}"
                )
    print("Effective settings: App and WallpaperDaemon Debug/Release = arm64, macOS 26.0")


def executable_candidates(app: Path) -> list[Path]:
    candidates = set(app / relative for relative in REQUIRED_BUNDLE_EXECUTABLES)
    for path in app.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        mode = path.stat().st_mode
        if mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) or path.suffix in {
            ".dylib",
            ".so",
        }:
            candidates.add(path)
    return sorted(candidates)


def dependency_names(otool_output: str) -> list[str]:
    lines = otool_output.splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines if line.strip()]


def rpath_names(otool_output: str) -> list[str]:
    paths: list[str] = []
    expects_path = False
    for line in otool_output.splitlines():
        value = line.strip()
        if value == "cmd LC_RPATH":
            expects_path = True
        elif expects_path and value.startswith("path "):
            paths.append(value.removeprefix("path ").split(" (offset ", 1)[0])
            expects_path = False
    return paths


def is_third_party(relative: Path) -> bool:
    return relative.parts[:2] == ("Contents", "Frameworks") or relative in THIRD_PARTY_HELPERS


def validate_bundle(app: Path) -> None:
    if not app.is_dir():
        raise RuntimeError(f"App bundle does not exist: {app}")
    for relative in REQUIRED_BUNDLE_EXECUTABLES:
        path = app / relative
        if not path.is_file():
            raise RuntimeError(f"Required bundled executable is missing: {relative}")

    mach_o_count = 0
    third_party_count = 0
    required_paths = {app / relative for relative in REQUIRED_BUNDLE_EXECUTABLES}
    for path in executable_candidates(app):
        description = run_checked(["file", "-b", str(path)])
        if "Mach-O" not in description:
            if path in required_paths:
                raise RuntimeError(
                    f"Required bundled executable is not Mach-O: {path.relative_to(app)}"
                )
            continue
        mach_o_count += 1
        relative = path.relative_to(app)
        architectures = set(run_checked(["lipo", "-archs", str(path)]).split())
        if is_third_party(relative):
            third_party_count += 1
            if "arm64" not in architectures:
                raise RuntimeError(f"Third-party Mach-O lacks arm64: {relative} ({architectures})")
        elif architectures != {"arm64"}:
            raise RuntimeError(f"Owned Mach-O must be arm64-only: {relative} ({architectures})")

        install_names = set(
            dependency_names(run_checked(["otool", "-D", str(path)]))
        )
        for dependency in dependency_names(run_checked(["otool", "-L", str(path)])):
            if dependency in install_names:
                continue
            if dependency.startswith("/") and not dependency.startswith(SYSTEM_DEPENDENCY_PREFIXES):
                raise RuntimeError(
                    f"Mach-O has non-system absolute dependency: {relative} -> {dependency}"
                )
        for rpath in rpath_names(run_checked(["otool", "-l", str(path)])):
            if rpath.startswith(SAFE_RPATH_PREFIXES):
                continue
            if rpath.startswith(SYSTEM_DEPENDENCY_PREFIXES):
                continue
            raise RuntimeError(f"Mach-O has unsafe runtime search path: {relative} -> {rpath}")

    if mach_o_count == 0:
        raise RuntimeError("No Mach-O files were found in the app bundle")
    print(
        f"Bundle closure: {mach_o_count} Mach-O files include arm64; "
        f"{mach_o_count - third_party_count} owned files are arm64-only; "
        f"{third_party_count} third-party files include arm64"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    try:
        validate_project(args.project.resolve())
        validate_bundle(args.app.resolve())
    except RuntimeError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
