#!/usr/bin/env python3
"""Generate the per-sample Scene acceptance ledger.

The ledger is the single reviewable answer to "which authored samples already
display and play correctly, and what blocks the rest".  It joins three inputs
over the read-only authored corpus:

1. the sample root (sample directories with ``project.json``) supplies the
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
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import (
    is_sample_directory_name,
    iter_sample_directories,
)

DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_ARCHIVE = REPOSITORY_ROOT / "script/scene_sample_debug_archive.json"
DEFAULT_VERDICTS = REPOSITORY_ROOT / "script/scene_sample_acceptance_verdicts.json"
DEFAULT_OUTPUT = (
    REPOSITORY_ROOT / "docs/scene/semantics/scene-sample-acceptance-ledger.md"
)

ALLOWED_VERDICTS = ("unreviewed", "pass", "fail", "platform-unsupported")
# P0.2 relation schema for `sample -> verdict`.  The overlay predates these
# fields, so an absent value is `unknown` until a reviewer records it; the
# loader never rewrites the human file to satisfy the schema.
UNKNOWN = "unknown"
ALLOWED_OFFICIAL_STATES = ("unknown", "not-run", "blocked", "compared")
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
    "terminal-output",
    "visual-review",
    "not-run",
)
CLUSTER_LABELS = {
    "effect-chain": "effect 准入 / 颜色合同 / graph 执行",
    "particle-load": "粒子层资源加载",
    "texture-load": "基础图片纹理加载",
    "scenescript": "SceneScript 异常",
    "terminal-output": "terminal compositor / 输出链",
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
    if stage in {"terminal-compositor", "terminal-output"}:
        return "terminal-output"
    return "visual-review"


def load_verdicts(path: Path) -> dict[str, dict[str, Any]]:
    """Load the hand-maintained verdict overlay.

    Only a person who watched real playback may author these entries, so the
    loader never invents values: fields added by the P0.2 relation schema stay
    ``unknown`` until a reviewer fills them in, and the historical overlay does
    not have to be rewritten for the ledger to build.
    """
    document = _json(path)
    allowed = document.get("allowedVerdicts")
    if allowed != list(ALLOWED_VERDICTS):
        raise ValueError(f"verdict overlay must declare allowedVerdicts={list(ALLOWED_VERDICTS)}")
    verdicts = document.get("verdicts")
    if not isinstance(verdicts, Mapping):
        raise ValueError("verdict overlay has no verdicts object")
    result: dict[str, dict[str, Any]] = {}
    for sample_id, entry in verdicts.items():
        if not (isinstance(sample_id, str) and is_sample_directory_name(sample_id)):
            raise ValueError(f"verdict key is not a sample id: {sample_id!r}")
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
        reviewer = entry.get("reviewer", UNKNOWN)
        remaining = entry.get("remainingDifferences", UNKNOWN)
        official = entry.get("officialComparison", UNKNOWN)
        if not isinstance(reviewer, str) or not isinstance(remaining, str):
            raise ValueError(
                f"sample {sample_id} viewer/remaining-difference fields must be strings"
            )
        # A blank string is not a recorded value: normalizing it to `unknown`
        # keeps the "reviewed without viewer" gap honest instead of letting a
        # placeholder erase the gap the P0.2 schema exists to expose.
        if not reviewer.strip():
            reviewer = UNKNOWN
        if not remaining.strip():
            remaining = UNKNOWN
        if not isinstance(official, str) or official not in ALLOWED_OFFICIAL_STATES:
            raise ValueError(
                f"sample {sample_id} officialComparison must be one of "
                f"{list(ALLOWED_OFFICIAL_STATES)}"
            )
        runs = _string_list(entry.get("runs"), sample_id, "runs")
        evidence = _string_list(entry.get("evidence"), sample_id, "evidence")
        result[sample_id] = {
            "verdict": verdict,
            "note": note,
            "reviewedOn": reviewed_on,
            "reviewer": reviewer,
            "runs": runs,
            "evidence": evidence,
            "remainingDifferences": remaining,
            "officialComparison": official,
        }
    return result


def _string_list(value: Any, sample_id: str, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"sample {sample_id} {field} must be a list of strings")
    return list(value)


# Suffixes a verdict reference may carry after its path.  Only recognized
# spellings are stripped: an anchor is `#L12`/`#10` style and an annotation is a
# known checksum/size note.  Any other trailing text stays part of the path, so
# a filename containing spaces, `#` or `=` is never truncated into a different,
# possibly existing file.
_ANNOTATION_SUFFIX = re.compile(
    r"\s+(?:sha256|sha1|sha512|md5|blake2b|blake3|crc32|checksum|hash|size|bytes)=\S+$",
    re.IGNORECASE,
)
_ANCHOR_SUFFIX = re.compile(r"#(?:L\d+|\d+)$", re.IGNORECASE)
# Bounded: a pathological string must not spin here.
_MAX_SUFFIX_STRIPS = 8


def _reference_variants(reference: str) -> list[str]:
    """Path spellings one reference may cite.

    Every spelling is derived from the reference itself by removing a suffix,
    never a prefix: the literal spelling, the same string without trailing
    whitespace, and repeated removals of a recognized anchor or annotation
    suffix.  Truncating at the first space is deliberately not a variant -- that
    would turn ``... 01.48.33.png`` into a different path and reject evidence
    that exists, and stripping an unrecognized ``#...`` suffix would let a
    same-prefix sibling vouch for a citation naming a different file.
    """
    variants: list[str] = []

    def add(candidate: str) -> None:
        if candidate.strip() and not candidate.startswith("#") and candidate not in variants:
            variants.append(candidate)

    add(reference)
    add(reference.rstrip())
    for candidate in list(variants):
        current = candidate
        for _ in range(_MAX_SUFFIX_STRIPS):
            stripped = _ANNOTATION_SUFFIX.sub("", current).rstrip()
            stripped = _ANCHOR_SUFFIX.sub("", stripped).rstrip()
            if stripped == current or not stripped:
                break
            current = stripped
            add(current)
    return variants


def _spelled_inside(
    repository_root: Path,
    candidate: Path,
    spelled_root: Path | None = None,
) -> bool:
    """Whether a citation spells a location inside the repository.

    Lexical only: symlinks and ``..`` are not resolved, because the question is
    where the author wrote the path, not where the filesystem sends it.  Every
    spelling of the root is accepted, so a repository whose path is reached
    through a symlinked prefix (``/var`` on macOS) is still recognized as the
    repository rather than mistaken for an external artifact.
    """
    normalized = Path(os.path.normpath(candidate))
    roots = [repository_root, repository_root.resolve()]
    if spelled_root is not None:
        roots += [spelled_root, spelled_root.resolve()]
    for spelling in roots:
        prefix = str(spelling).rstrip("/")
        # The raw spelling matters as much as the normalized one: `/repo/../x`
        # is written inside the repository even though it resolves outside.
        if str(candidate) == prefix or str(candidate).startswith(prefix + "/"):
            return True
        if normalized.is_relative_to(Path(os.path.normpath(spelling))):
            return True
    return False


def _classify_reference(
    reference: str,
    repository_root: Path,
    spelled_root: Path | None = None,
) -> str:
    """Classify one verdict reference; ``""`` means it is acceptable.

    References landing outside the repository are transient by artifact
    governance and are accepted without an existence check -- the requirement
    they carry (P0.2) is that acceptance evidence recorded *inside* the
    repository is still there, and a repository-internal citation written as an
    absolute path is checked exactly like a relative one.  A directory is not
    evidence identity, and an unresolvable spelling is a failure rather than an
    exception.
    """
    variants = _reference_variants(reference)
    if not variants:
        return "verdict-evidence-reference-empty"
    saw_escape = False
    saw_directory = False
    for variant in variants:
        expanded = Path(os.path.expandvars(os.path.expanduser(variant)))
        absolute = expanded.is_absolute()
        candidate = expanded if absolute else repository_root / expanded
        try:
            target = candidate.resolve()
        except (OSError, RuntimeError, ValueError):
            continue
        if not target.is_relative_to(repository_root):
            # Only a citation spelled outside the repository is a transient
            # artifact; one spelled inside that resolves outside (a `..` path
            # or a repository symlink pointing out) is an escape, whichever way
            # it is written.
            if absolute and not _spelled_inside(repository_root, candidate, spelled_root):
                return ""
            saw_escape = True
            continue
        try:
            if not target.exists():
                continue
            if target.is_file():
                return ""
        except OSError:
            return "verdict-evidence-reference-unresolvable"
        saw_directory = True
    if saw_escape:
        return "verdict-evidence-reference-outside-repository"
    if saw_directory:
        return "verdict-evidence-not-a-file"
    return "verdict-evidence-file-missing"


def validate_verdict_references(
    verdicts: Mapping[str, Mapping[str, Any]],
    repository_root: Path,
) -> list[dict[str, Any]]:
    """Referential integrity for the run/evidence a verdict cites.

    Unknown sample ids stay `build_ledger`'s contract; this gate owns the other
    half of the P0.2 `sample -> verdict` relation: a verdict that cites run or
    screenshot paths which no longer exist inside the repository cannot support
    the acceptance decision it records. Repository-external references are
    transient by artifact governance and are never failures, but a repository
    path that exists as a directory is not evidence identity either.

    This is a validator: malformed containers produce failure records, never
    exceptions, so it stays callable from audit scripts on unnormalized input.
    """
    failures: list[dict[str, Any]] = []
    if not isinstance(verdicts, Mapping):
        return [{
            "code": "verdict-container-shape-invalid",
            "sample_id": "",
            "field": "",
            "reference": repr(verdicts),
        }]
    try:
        root = Path(repository_root)
        resolved_root = root.resolve()
    except (OSError, RuntimeError, TypeError, ValueError):
        return [{
            "code": "verdict-repository-root-invalid",
            "sample_id": "",
            "field": "",
            "reference": repr(repository_root),
        }]
    try:
        entries = list(verdicts.items())
    except Exception:  # noqa: BLE001 - this validator never raises
        return [{
            "code": "verdict-container-shape-invalid",
            "sample_id": "",
            "field": "",
            "reference": repr(verdicts),
        }]
    for sample_id, entry in entries:
        if not isinstance(entry, Mapping):
            failures.append({
                "code": "verdict-entry-shape-invalid",
                "sample_id": sample_id,
                "field": "",
                "reference": "",
            })
            continue
        for field in ("runs", "evidence"):
            try:
                references = entry.get(field)
            except (AttributeError, KeyError, RuntimeError, TypeError, ValueError):
                failures.append({
                    "code": "verdict-entry-shape-invalid",
                    "sample_id": sample_id,
                    "field": field,
                    "reference": repr(entry),
                })
                continue
            if references is None:
                continue
            if not isinstance(references, list):
                failures.append({
                    "code": "verdict-evidence-reference-invalid",
                    "sample_id": sample_id,
                    "field": field,
                    "reference": repr(references),
                })
                continue
            for reference in references:
                if not isinstance(reference, str):
                    failures.append({
                        "code": "verdict-evidence-reference-invalid",
                        "sample_id": sample_id,
                        "field": field,
                        "reference": repr(reference),
                    })
                    continue
                code = _classify_reference(reference, resolved_root, root)
                if code:
                    failures.append({
                        "code": code,
                        "sample_id": sample_id,
                        "field": field,
                        "reference": reference,
                    })
    return failures


def _app_identity_label(identity: Mapping[str, Any]) -> str:
    """Render one archive build identity for the page header."""
    cdhash = _identity_text(identity.get("cdhash"))
    if cdhash:
        return _cell(f"CDHash `{cdhash}`", 80)
    executable = _identity_text(identity.get("executableSha256"))
    if executable:
        return _cell(f"executable SHA-256 `{executable}`", 96)
    return ""


def _distinct_app_identities(archive: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Distinct build identities of an archive, in first-appearance order.

    Degenerate archives must still render: a malformed ``appIdentities``
    container yields no identity rather than an exception, because this is a
    report renderer, not a validator of its inputs.
    """
    try:
        items = list(archive.get("appIdentities") or [])
    except TypeError:
        return []
    identities: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        if not isinstance(item, Mapping):
            continue
        identity = {
            "cdhash": _identity_text(item.get("cdhash")),
            "executableSha256": _identity_text(item.get("executable_sha256")),
        }
        label = identity["cdhash"] or identity["executableSha256"]
        if not label or label in seen:
            continue
        seen.add(label)
        identities.append(identity)
    return identities


def _identity_text(value: Any) -> str:
    """A build-identity field as text; missing and blank mean the same thing."""
    if not isinstance(value, str):
        return ""
    return value.strip()


def build_ledger(
    samples_root: Path,
    archive_path: Path,
    verdicts_path: Path,
    repository_root: Path | None = None,
) -> dict[str, Any]:
    if not samples_root.is_dir():
        raise ValueError(f"samples root is not a directory: {samples_root}")
    sample_dirs = list(iter_sample_directories(samples_root))
    if not sample_dirs:
        raise ValueError(f"no samples found below {samples_root}")
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
        verdict = verdicts.get(sample_id, {
            "verdict": "unreviewed", "note": "", "reviewedOn": "",
            "reviewer": UNKNOWN, "runs": [], "evidence": [],
            "remainingDifferences": UNKNOWN,
            "officialComparison": UNKNOWN,
        })
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
            "reviewer": verdict["reviewer"],
            "runs": list(verdict["runs"]),
            "evidence": list(verdict["evidence"]),
            "remainingDifferences": verdict["remainingDifferences"],
            "officialComparison": verdict["officialComparison"],
        })

    reference_root = REPOSITORY_ROOT if repository_root is None else Path(repository_root)
    reference_failures = validate_verdict_references(verdicts, reference_root)
    if reference_failures:
        raise ValueError(
            f"verdict overlay has dangling references ({len(reference_failures)}): "
            f"{json.dumps(reference_failures[:5], ensure_ascii=False)}"
        )

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
                # The distinct build identities the archived reports actually
                # ran under: runtime status must never be read as a claim about
                # current HEAD, and two identities mean a mixed archive.
                "appIdentities": _distinct_app_identities(archive),
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
            "officialComparisonCounts": {
                key: sum(
                    1 for row in rows if row["officialComparison"] == key
                )
                for key in ALLOWED_OFFICIAL_STATES
            },
            "reviewedWithoutViewer": sum(
                1 for row in rows
                if row["verdict"] != "unreviewed" and row["reviewer"] == UNKNOWN
            ),
            "reviewedWithoutEvidence": sum(
                1 for row in rows
                if row["verdict"] != "unreviewed" and not row["evidence"]
            ),
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
        f"- 样本根：`{source['samplesRoot']}`（{source['sampleCount']} 个 sample 目录）。",
        f"- 运行归档：`{Path(source['archive']['path']).name}` SHA-256 `{source['archive']['sha256']}`"
        f"（生成于 {source['archive']['generatedAtUtc']}）。",
        "- 归档运行身份："
        + (
            "、".join(
                label
                for label in (
                    _app_identity_label(identity)
                    for identity in source["archive"]["appIdentities"]
                )
                if label
            )
            or "未记录"
        )
        + (
            "；下方运行状态与首断点只对这些实际执行身份有效，不等于当前 HEAD 的构建；"
            "单个样本若被后续重试覆盖，其状态以该样本自己的 report 身份为准。"
            if len(source["archive"]["appIdentities"]) <= 1
            else "；**归档内不止一个执行身份**，运行状态与首断点因此是混合身份事实，"
            "单样本结论必须回到该样本自己的 report 身份。"
        ),
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
    lines += [
        "",
        "| 官方对照状态 | 样本数 |",
        "|---|---:|",
    ]
    for key in ALLOWED_OFFICIAL_STATES:
        lines.append(f"| `{key}` | {summary['officialComparisonCounts'][key]} |")
    lines += [
        "",
        f"- 已裁决但缺观看者身份的条目：**{summary['reviewedWithoutViewer']}**；"
        f"已裁决但缺截图/视频身份的条目：**{summary['reviewedWithoutEvidence']}**"
        "（P0.2 `sample → verdict` 关系要求的字段；缺项保持 `unknown`，不由生成器补写）。"
        "此处只统计**裁决自己引用的** run/截图身份，与 corpus 清单"
        "（docs/scene/semantics/scene-corpus-capability-inventory.md）的「人工对照」列"
        "（样本目录自带的用户截图 `截屏*.png` 与 `用户观察说明.md`）不是同一事实，"
        "两页不可互相替代。",
    ]
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
