#!/usr/bin/env python3
"""Generate the per-sample Scene acceptance ledger.

The ledger is the single reviewable answer to "which authored samples already
display and play correctly, and what blocks the rest".  It joins three inputs
over the read-only authored corpus:

1. the sample root (numeric directories with ``project.json``) supplies the
   sample identity, title and authored user-parameter shape;
2. ``scene_sample_debug_archive.json`` supplies the last isolated runtime
   status and normalized first breakpoint per sample;
3. ``scene_sample_acceptance_verdicts.json`` supplies the hand-maintained
   human visual verdict per sample.

Runtime evidence never produces a visual verdict.  A sample stays
``unreviewed`` until a person records ``pass`` or ``fail`` against a real
playback observation; ``platform-unsupported`` is reserved for authored
features that cannot exist on macOS by explicit platform policy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_ARCHIVE = REPOSITORY_ROOT / "script/scene_sample_debug_archive.json"
DEFAULT_VERDICTS = REPOSITORY_ROOT / "script/scene_sample_acceptance_verdicts.json"
DEFAULT_OUTPUT = (
    REPOSITORY_ROOT / "docs/scene/semantics/scene-sample-acceptance-ledger.md"
)

ALLOWED_VERDICTS = ("unreviewed", "pass", "fail", "platform-unsupported")
FINAL_GATE = (
    "每个样本在真实播放中正确显示与播放，且作者参数（project.json user properties）"
    "全部进入播放链路"
)

# Shared first-breakpoint clusters.  The active roadmap orders work by these
# clusters; sample identities stay here, not in the roadmap.
CLUSTER_ORDER = (
    "effect-chain",
    "particle-load",
    "texture-load",
    "scenescript",
    "visual-review",
    "not-run",
)
CLUSTER_LABELS = {
    "effect-chain": "effect 准入 / 颜色合同 / graph 执行",
    "particle-load": "粒子层资源加载",
    "texture-load": "基础图片纹理加载",
    "scenescript": "SceneScript 异常",
    "visual-review": "结构链完整，待视觉验收",
    "not-run": "尚无隔离运行证据",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load JSON {path}: {error}") from error
    if not isinstance(value, Mapping):
        raise ValueError(f"JSON document is not an object: {path}")
    return value


def iter_numeric_sample_directories(root: Path) -> list[Path]:
    return sorted(
        (
            item
            for item in root.iterdir()
            if item.is_dir() and not item.is_symlink() and item.name.isdigit()
        ),
        key=lambda item: item.name,
    )


def authored_parameters(sample_dir: Path) -> dict[str, Any]:
    """Summarize ``general.properties`` without copying authored values."""
    project = sample_dir / "project.json"
    result: dict[str, Any] = {
        "title": sample_dir.name,
        "parseState": "missing-project",
        "parameterCount": 0,
        "conditionalCount": 0,
        "schemeColorOnly": True,
        "typeCounts": {},
    }
    if not project.is_file():
        return result
    try:
        document = json.loads(project.read_text(encoding="utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        result["parseState"] = "invalid-project"
        return result
    if not isinstance(document, Mapping):
        result["parseState"] = "invalid-project"
        return result
    result["parseState"] = "parsed"
    title = document.get("title")
    if isinstance(title, str) and title.strip():
        result["title"] = title.strip()
    general = document.get("general")
    properties = general.get("properties") if isinstance(general, Mapping) else None
    if not isinstance(properties, Mapping):
        return result
    type_counts: Counter[str] = Counter()
    conditional = 0
    for key, raw in properties.items():
        if not isinstance(raw, Mapping):
            continue
        raw_type = raw.get("type")
        type_name = raw_type.strip().lower() if isinstance(raw_type, str) and raw_type.strip() else "untyped"
        type_counts[type_name] += 1
        if raw.get("condition") not in (None, ""):
            conditional += 1
    result["parameterCount"] = sum(type_counts.values())
    result["conditionalCount"] = conditional
    result["typeCounts"] = dict(sorted(type_counts.items()))
    result["schemeColorOnly"] = set(properties.keys()) <= {"schemecolor"}
    return result


def cluster_for(status: str, first_breakpoint: Mapping[str, Any] | None) -> str:
    if status == "not-run":
        return "not-run"
    if not first_breakpoint:
        return "visual-review"
    stage = str(first_breakpoint.get("stage", ""))
    owner = str(first_breakpoint.get("owner", ""))
    if stage in {"effect-admission", "effect-execution", "graph-execution"}:
        return "effect-chain"
    if stage == "resource-load":
        if owner == "ParticleRuntime":
            return "particle-load"
        return "texture-load"
    if stage == "script-execution":
        return "scenescript"
    return "visual-review"


def load_verdicts(path: Path) -> dict[str, dict[str, str]]:
    document = _json(path)
    allowed = document.get("allowedVerdicts")
    if allowed != list(ALLOWED_VERDICTS):
        raise ValueError(f"verdict overlay must declare allowedVerdicts={list(ALLOWED_VERDICTS)}")
    verdicts = document.get("verdicts")
    if not isinstance(verdicts, Mapping):
        raise ValueError("verdict overlay has no verdicts object")
    result: dict[str, dict[str, str]] = {}
    for sample_id, entry in verdicts.items():
        if not (isinstance(sample_id, str) and sample_id.isdigit()):
            raise ValueError(f"verdict key is not a numeric sample id: {sample_id!r}")
        if not isinstance(entry, Mapping):
            raise ValueError(f"verdict entry is not an object: {sample_id}")
        verdict = entry.get("verdict")
        if verdict not in ALLOWED_VERDICTS:
            raise ValueError(f"sample {sample_id} has invalid verdict {verdict!r}")
        note = entry.get("note", "")
        reviewed_on = entry.get("reviewedOn", "")
        if not isinstance(note, str) or not isinstance(reviewed_on, str):
            raise ValueError(f"sample {sample_id} verdict note/reviewedOn must be strings")
        if verdict != "unreviewed" and not reviewed_on:
            raise ValueError(f"sample {sample_id} verdict {verdict} requires reviewedOn")
        result[sample_id] = {"verdict": verdict, "note": note, "reviewedOn": reviewed_on}
    return result


def build_ledger(samples_root: Path, archive_path: Path, verdicts_path: Path) -> dict[str, Any]:
    if not samples_root.is_dir():
        raise ValueError(f"samples root is not a directory: {samples_root}")
    sample_dirs = iter_numeric_sample_directories(samples_root)
    if not sample_dirs:
        raise ValueError(f"no numeric samples found below {samples_root}")
    sample_ids = [item.name for item in sample_dirs]

    archive = _json(archive_path)
    archive_samples = archive.get("samples")
    if not isinstance(archive_samples, list):
        raise ValueError(f"archive has no samples array: {archive_path}")
    archive_by_id: dict[str, Mapping[str, Any]] = {}
    for row in archive_samples:
        if isinstance(row, Mapping) and isinstance(row.get("id"), str):
            archive_by_id[row["id"]] = row

    verdicts = load_verdicts(verdicts_path)
    unknown = sorted(set(verdicts) - set(sample_ids))
    if unknown:
        raise ValueError(f"verdict overlay names samples absent from the root: {unknown[:5]}")

    rows: list[dict[str, Any]] = []
    for sample_dir in sample_dirs:
        sample_id = sample_dir.name
        authored = authored_parameters(sample_dir)
        archived = archive_by_id.get(sample_id)
        runtime = archived.get("runtime") if isinstance(archived, Mapping) else None
        status = "not-run"
        first_breakpoint: Mapping[str, Any] | None = None
        if isinstance(runtime, Mapping):
            status = str(runtime.get("status", "runtime-status-unknown"))
            candidate = runtime.get("firstBreakpoint")
            first_breakpoint = candidate if isinstance(candidate, Mapping) else None
        verdict = verdicts.get(sample_id, {"verdict": "unreviewed", "note": "", "reviewedOn": ""})
        rows.append({
            "id": sample_id,
            "title": authored["title"],
            "authored": {
                key: authored[key]
                for key in ("parseState", "parameterCount", "conditionalCount", "schemeColorOnly", "typeCounts")
            },
            "runtimeStatus": status,
            "firstBreakpoint": (
                {
                    "stage": first_breakpoint.get("stage"),
                    "owner": first_breakpoint.get("owner"),
                    "reasonCode": first_breakpoint.get("reasonCode"),
                    "profile": first_breakpoint.get("capabilityProfileOrAuthoredShape"),
                }
                if first_breakpoint else None
            ),
            "cluster": cluster_for(status, first_breakpoint),
            "verdict": verdict["verdict"],
            "reviewedOn": verdict["reviewedOn"],
            "note": verdict["note"],
        })

    verdict_counts = Counter(row["verdict"] for row in rows)
    cluster_counts = Counter(row["cluster"] for row in rows)
    status_counts = Counter(row["runtimeStatus"] for row in rows)
    authored_rows = [row for row in rows if not row["authored"]["schemeColorOnly"]]
    return {
        "kind": "scene-sample-acceptance-ledger",
        "schemaVersion": 1,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "finalGate": FINAL_GATE,
        "source": {
            "samplesRoot": str(samples_root),
            "sampleCount": len(rows),
            "archive": {
                "path": str(archive_path),
                "sha256": sha256_file(archive_path),
                "generatedAtUtc": archive.get("generatedAtUtc"),
            },
            "verdicts": {"path": str(verdicts_path), "sha256": sha256_file(verdicts_path)},
        },
        "summary": {
            "verdictCounts": {key: verdict_counts.get(key, 0) for key in ALLOWED_VERDICTS},
            "clusterCounts": {key: cluster_counts.get(key, 0) for key in CLUSTER_ORDER},
            "runtimeStatusCounts": dict(sorted(status_counts.items())),
            "samplesWithAuthoredParameters": len(authored_rows),
            "authoredParameterTotal": sum(row["authored"]["parameterCount"] for row in rows),
            "conditionalParameterTotal": sum(row["authored"]["conditionalCount"] for row in rows),
        },
        "samples": rows,
    }


def _cell(text: str, limit: int = 40) -> str:
    text = text.replace("|", "\\|").replace("\n", " ").strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def render_markdown(ledger: Mapping[str, Any]) -> str:
    summary = ledger["summary"]
    source = ledger["source"]
    lines = [
        "# Scene 样本验收台账",
        "",
        "> 状态：现役验收事实。本页由 `script/scene_sample_acceptance_ledger.py` 生成；"
        "视觉裁决只来自 `script/scene_sample_acceptance_verdicts.json` 的人工记录，不要手工编辑本页。",
        ">",
        f"> 最终验收门：{ledger['finalGate']}。",
        ">",
        "> 运行状态和首断点只描述隔离运行的安全/结构事实，不是视觉正确性；"
        "`structural-chain-complete-visual-review` 仍需人工验收。集群只用于排序公共首断点，"
        "样本身份不得进入产品代码或现役路线正文。",
        "",
        "## 1. 来源",
        "",
        f"- 样本根：`{source['samplesRoot']}`（{source['sampleCount']} 个 numeric sample）。",
        f"- 运行归档：`{Path(source['archive']['path']).name}` SHA-256 `{source['archive']['sha256']}`"
        f"（生成于 {source['archive']['generatedAtUtc']}）。",
        f"- 裁决覆盖层：`{Path(source['verdicts']['path']).name}` SHA-256 `{source['verdicts']['sha256']}`。",
        f"- 本页生成于 {ledger['generatedAtUtc']}。",
        "",
        "## 2. 汇总",
        "",
        "| 视觉裁决 | 样本数 |",
        "|---|---:|",
    ]
    for key in ALLOWED_VERDICTS:
        lines.append(f"| `{key}` | {summary['verdictCounts'][key]} |")
    lines += ["", "| 首断点集群 | 含义 | 样本数 |", "|---|---|---:|"]
    for key in CLUSTER_ORDER:
        lines.append(f"| `{key}` | {CLUSTER_LABELS[key]} | {summary['clusterCounts'][key]} |")
    lines += ["", "| 运行状态 | 样本数 |", "|---|---:|"]
    for key, value in summary["runtimeStatusCounts"].items():
        lines.append(f"| `{key}` | {value} |")
    lines += [
        "",
        f"作者参数：{summary['samplesWithAuthoredParameters']} 个样本声明了 schemecolor 之外的用户参数，"
        f"共 {summary['authoredParameterTotal']} 项，其中 {summary['conditionalParameterTotal']} 项带 `condition`。"
        "参数进入播放链路的验收随各样本的视觉裁决一起记录，不单独计数。",
        "",
        "## 3. 逐样本",
        "",
        "首断点格式为 `stage / owner / reasonCode / profile`。作者参数列为 `总数(condition 数) 类型分布`。",
        "",
        "| 样本 | 标题 | 作者参数 | 运行状态 | 首断点 | 集群 | 视觉裁决 | 备注 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for row in ledger["samples"]:
        authored = row["authored"]
        if authored["parseState"] != "parsed":
            parameters = f"`{authored['parseState']}`"
        elif authored["schemeColorOnly"]:
            parameters = "仅 schemecolor"
        else:
            types = " ".join(f"{name} {count}" for name, count in authored["typeCounts"].items())
            parameters = f"{authored['parameterCount']}({authored['conditionalCount']}) {types}"
        breakpoint = row["firstBreakpoint"]
        breakpoint_text = (
            f"`{breakpoint['stage']} / {breakpoint['owner']} / {breakpoint['reasonCode']} / {breakpoint['profile']}`"
            if breakpoint else "-"
        )
        verdict = f"`{row['verdict']}`" + (f" {row['reviewedOn']}" if row["reviewedOn"] else "")
        lines.append(
            "| `{id}` | {title} | {parameters} | `{status}` | {breakpoint} | `{cluster}` | {verdict} | {note} |".format(
                id=row["id"],
                title=_cell(row["title"]),
                parameters=_cell(parameters, 60),
                status=row["runtimeStatus"],
                breakpoint=breakpoint_text,
                cluster=row["cluster"],
                verdict=verdict,
                note=_cell(row["note"], 80),
            )
        )
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES_ROOT)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--verdicts", type=Path, default=DEFAULT_VERDICTS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--json", type=Path, default=None, help="optional machine-readable copy")
    args = parser.parse_args(argv)
    try:
        ledger = build_ledger(args.samples_root, args.archive, args.verdicts)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    args.output.write_text(render_markdown(ledger), encoding="utf-8")
    if args.json is not None:
        args.json.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = ledger["summary"]
    print(
        f"wrote {args.output} samples={ledger['source']['sampleCount']}"
        f" verdicts={summary['verdictCounts']} clusters={summary['clusterCounts']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
