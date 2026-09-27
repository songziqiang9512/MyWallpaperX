#!/usr/bin/env python3
"""Require reviewed, versioned release notes before any release build."""

import argparse
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
SECTIONS = ("新增", "修改", "优化", "修复", "已知问题")


def version_tuple(version: str) -> tuple[int, ...]:
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("版本号必须是 x.y.z，例如 2.0.10。")
    return tuple(map(int, version.split(".")))


def validate_notes(text: str, version: str) -> None:
    version_tuple(version)
    if re.search(r"\b(?:TODO|TBD)\b|待填写|待补充|<version>", text, re.IGNORECASE):
        raise ValueError("发布日志仍含模板占位内容。")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL).strip()
    if text.splitlines()[:1] != [f"# MyWallpaperX {version}"]:
        raise ValueError(f"发布日志标题必须是 # MyWallpaperX {version}")
    parts = re.split(r"^## (.+?)\s*$", text, flags=re.MULTILINE)
    if not "\n".join(parts[0].splitlines()[1:]).strip():
        raise ValueError("发布日志必须先概述本次面向用户的变化。")
    headings = parts[1::2]
    if len(headings) != len(set(headings)):
        raise ValueError("发布日志不能包含重复章节。")
    sections = dict(zip(headings, parts[2::2]))
    changes = []
    for heading in SECTIONS:
        bullets = re.findall(r"^[-*] (\S.*)$", sections.get(heading, ""), re.MULTILINE)
        if not bullets:
            raise ValueError(f"发布日志缺少「{heading}」条目；没有变化时写 - 无。")
        if heading != "已知问题":
            changes.extend(bullet for bullet in bullets if bullet.strip().rstrip("。.") != "无")
    if not changes:
        raise ValueError("发布日志至少需要一项实际变化。")


def validate_release(root: Path, version: str, *, check_project=False, check_tags=False) -> Path:
    requested = version_tuple(version)
    notes = root / "docs/releases" / f"{version}.md"
    validate_notes(notes.read_text(encoding="utf-8"), version)
    if check_project:
        project = (root / "MyWallpaperX.xcodeproj/project.pbxproj").read_text()
        versions = re.findall(r"MARKETING_VERSION = ([^;]+);", project)
        if not versions or any(value.strip().strip('"') != version for value in versions):
            raise ValueError("日志版本与 Xcode 项目版本不一致。")
    if check_tags:
        tags = subprocess.check_output(
            ["git", "tag", "--list", "build-*"], cwd=root, text=True
        ).splitlines()
        for tag in tags:
            previous = tag.removeprefix("build-")
            if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", previous):
                if requested <= tuple(map(int, previous.split("."))):
                    raise ValueError(f"版本必须高于已存在的 {tag}，不能覆盖或降级发布。")
    return notes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--check-project", action="store_true")
    parser.add_argument("--check-tags", action="store_true", help="requires a checkout with all remote tags")
    args = parser.parse_args()
    try:
        notes = validate_release(ROOT, args.version, check_project=args.check_project, check_tags=args.check_tags)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))
    print(f"Release notes validated: {notes.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
