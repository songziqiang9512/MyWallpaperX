#!/usr/bin/env python3
"""Design-first gate: block implementation starts on registered capabilities.

A capability registered in script/design_gated_areas.json with status
``blocked-pending-design`` may not gain implementation files or trigger
symbols until a design document lands and the registry entry flips to
``approved``.  The gate is pure static analysis: it matches changed paths
against fnmatch patterns and greps changed file contents for trigger
symbols; it never builds or executes product code.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Sequence

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path(__file__).with_name("design_gated_areas.json")
# The registry lists trigger symbols as data and the checker mentions them in
# help text; scanning our own files would make every registry edit self-fail.
CONTENT_SCAN_EXEMPT = {
    "script/design_gated_areas.json",
    "script/check_design_gate.py",
}
MAX_CONTENT_SCAN_BYTES = 4 * 1024 * 1024


def changed_paths(base: str | None, explicit_paths: Sequence[str]) -> list[str]:
    if explicit_paths:
        cleaned = [p if Path(p).is_absolute() else p.strip("/") for p in explicit_paths]
        return sorted({p for p in cleaned if p})
    completed = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACDMRTUXB", base or "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths = {line for line in completed.stdout.splitlines() if line}
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths.update(line for line in untracked.stdout.splitlines() if line)
    return sorted(paths)


def load_registry() -> dict[str, Any]:
    payload = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("design gate registry schema must be 1")
    areas = payload.get("areas")
    if not isinstance(areas, list):
        raise ValueError("design gate registry is malformed")
    seen: set[str] = set()
    required = {"id", "title", "owner", "status", "designDoc", "design_notes",
                "matchPatterns", "contentPatterns"}
    for area in areas:
        if not isinstance(area, dict) or set(area) != required:
            raise ValueError(f"design gate area is incomplete: {area.get('id')}")
        if area["id"] in seen:
            raise ValueError(f"duplicate design gate area id: {area['id']}")
        seen.add(area["id"])
        if area["status"] not in {"blocked-pending-design", "approved"}:
            raise ValueError(f"invalid design gate status: {area['id']}")
        if area["status"] == "approved" and not area["designDoc"]:
            raise ValueError(f"approved area must reference a design doc: {area['id']}")
        if area["status"] == "approved" and area["designDoc"]:
            if not (ROOT / area["designDoc"]).is_file():
                raise ValueError(f"design doc missing for approved area: {area['id']}")
    return payload


def file_hits_content(path: Path, patterns: Sequence[str]) -> list[str]:
    if not path.is_file() or not patterns:
        return []
    try:
        blob = path.read_bytes()[:MAX_CONTENT_SCAN_BYTES].decode("utf-8", errors="replace")
    except OSError:
        return []
    return [p for p in patterns if p in blob]


def evaluate(
    paths: Sequence[str],
    registry: dict[str, Any],
) -> tuple[list[str], list[str]]:
    violations: list[str] = []
    advisory: list[str] = []
    for area in registry["areas"]:
        if area["status"] != "blocked-pending-design":
            continue
        if not area["matchPatterns"] and not area["contentPatterns"]:
            advisory.append(
                f"{area['id']}: {area['title']}（owner={area['owner']}）——清单登记、"
                "无机器模式，实施前按 AGENTS.md 设计前置判定程序执行设计"
            )
            continue
        matched_paths = [
            p for p in paths
            if any(fnmatch.fnmatch(p, pat) for pat in area["matchPatterns"])
        ]
        matched_symbols: list[tuple[str, str]] = []
        for p in paths:
            normalized = p if Path(p).is_absolute() else p.strip("/")
            if normalized in CONTENT_SCAN_EXEMPT:
                continue
            candidate = Path(p) if Path(p).is_absolute() else ROOT / p
            for symbol in file_hits_content(candidate, area["contentPatterns"]):
                matched_symbols.append((p, symbol))
        if matched_paths or matched_symbols:
            details = []
            if matched_paths:
                details.append("新增/变更文件命中: " + ", ".join(matched_paths[:5]))
            if matched_symbols:
                details.append(
                    "触发符号命中: "
                    + ", ".join(f"{p}:{sym}" for p, sym in matched_symbols[:5])
                )
            violations.append(
                f"{area['id']}: {area['title']}\n"
                f"  owner={area['owner']}  状态={area['status']}\n"
                f"  {'; '.join(details)}\n"
                "  该能力属设计前置类：先落设计文档（写入 designDoc 并将状态改为 "
                "approved，同批提交 owner 与裁决依据），或确属误报时收窄 "
                "matchPatterns/contentPatterns 并写理由。判定程序见 AGENTS.md 与 "
                "script/design_gated_areas.json 的 policy。"
            )
    return violations, advisory


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--paths", nargs="*", help="workspace-relative changed paths")
    source.add_argument("--base-ref", help="git ref to diff against (default HEAD)")
    parser.add_argument("--list", action="store_true", help="list registry areas and exit")
    args = parser.parse_args()

    registry = load_registry()
    if args.list:
        for area in registry["areas"]:
            mark = "✔" if area["status"] == "approved" else "✖"
            doc = area["designDoc"] or "(未定)"
            print(f"{mark} {area['id']} [{area['status']}] owner={area['owner']} design={doc}")
        return 0

    paths = changed_paths(args.base_ref, args.paths or [])
    if not paths:
        print("design-gate: no changed paths; nothing to check")
        return 0
    violations, advisory = evaluate(paths, registry)
    for line in advisory:
        print(f"design-gate advisory: {line}")
    if violations:
        print("design-gate: FAIL —— 设计前置能力出现实施迹象，先完成设计再动代码：")
        for v in violations:
            print(f"  - {v}")
        return 1
    print(f"design-gate: pass（{len(paths)} 个变更路径无设计前置命中）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
