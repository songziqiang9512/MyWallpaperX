#!/usr/bin/env python3
"""Build a compact, traceable archive for a real Scene sample run.

The archive joins the read-only authored corpus census with one or more
``scene_wallpaper_benchmark`` reports and the existing first-breakpoint
normalizer.  It deliberately records structural runtime evidence only:
non-black output and a benchmark ``passed`` flag are not visual-correctness
claims.  Reports may cover a subset of the corpus; samples without a report
remain explicit ``not-run`` entries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence

SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIRECTORY = SCRIPT_PATH.parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

from scene_capability_census_io import iter_sample_directories, path_identity, sha256_file
from scene_diagnostic_report import (
    load_preview_oracle_registry,
    normalize_reports,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_SNAPSHOT = REPOSITORY_ROOT / ".artifacts/scene-evidence/census/scene_capability_census_snapshot.json"

CLAIM_BOUNDARY = (
    "runtime-first-breakpoint-and-lifecycle-diagnostics-only-not-visual-correctness"
)


def _json(path: Path) -> tuple[Mapping[str, Any], str]:
    try:
        data = path.read_bytes()
        value = json.loads(data.decode("utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot load JSON {path}: {error}") from error
    if not isinstance(value, Mapping):
        raise ValueError(f"JSON document is not an object: {path}")
    return value, hashlib.sha256(data).hexdigest()


def _corpus_manifest(sample_ids: Sequence[str]) -> str:
    payload = ("\n".join(sample_ids) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _sample_status(observation: Mapping[str, Any] | None) -> str:
    if observation is None:
        return "not-run"
    status = observation.get("basicDisplayStatus")
    if status == "blocked":
        return "blocked"
    if status == "degraded":
        return "degraded-runtime"
    if status == "terminal-compositor-observed":
        return "terminal-compositor-observed-visual-review"
    if status == "runtime-evidence-incomplete":
        return "runtime-evidence-incomplete"
    return "runtime-status-unknown"


def _next_action(status: str, first_breakpoint: Mapping[str, Any] | None) -> str:
    if status == "not-run":
        return "run-isolated-authored-sample"
    if status == "blocked":
        if first_breakpoint:
            stage = first_breakpoint.get("stage", "unknown-stage")
            owner = first_breakpoint.get("owner", "unknown-owner")
            reason = first_breakpoint.get("reasonCode", "unknown-reason")
            return f"repair-shared-owner:{stage}:{owner}:{reason}"
        return "locate-first-runtime-breakpoint"
    if status == "degraded-runtime":
        return "inspect-fallback-and-authored-visual-ROI"
    if status == "terminal-compositor-observed-visual-review":
        return "perform-authored-preview-and-next-frame-visual-review"
    if status in {"input-identity-unknown", "input-identity-mismatch"}:
        return "rerun-with-observed-matching-input-identity"
    return "add-or-reproduce-runtime-evidence"


def _input_identity(row: Mapping[str, Any], sample: Mapping[str, Any]) -> dict[str, Any]:
    observed = sample.get("hashes")
    observed = observed if isinstance(observed, Mapping) else {}
    fields = ["project_sha256", "tree_sha256"]
    if row.get("package_sha256") is not None:
        fields.append("package_sha256")
    mismatches = [field for field in fields if row.get(field) is not None
                  and observed.get(field) is not None and row[field] != observed[field]]
    if row.get("package_sha256") is None and observed.get("package_sha256") is not None:
        mismatches.append("package_sha256")
    missing = [field for field in fields if row.get(field) is None or observed.get(field) is None]
    source_invalid = row.get("parse_state") == "failed" and sample.get("input_status") == "source-invalid"
    if mismatches:
        status = "mismatch"
    elif source_invalid:
        status = "source-invalid"
    else:
        status = "unknown" if missing else "matched"
    return {
        "status": status, "missingFields": missing, "mismatchedFields": mismatches,
        "expectedHashes": {field: row.get(field) for field in ("project_sha256", "tree_sha256", "package_sha256")},
        "observedHashes": dict(observed),
    }


def _occurrence_locations(occurrences: Sequence[Mapping[str, Any]]) -> dict[str, dict[str, Any]]:
    by_id = {item["occurrence_id"]: item for item in occurrences}
    resolved: dict[str, dict[str, Any]] = {}
    for identity in by_id:
        pending, visiting = [], set()
        cursor = identity
        while cursor in by_id and cursor not in resolved:
            if cursor in visiting:
                raise ValueError(f"cyclic census occurrence owner: {cursor}")
            visiting.add(cursor)
            location = by_id[cursor].get("location", {})
            pending.append((cursor, location))
            cursor = location.get("owner_occurrence")
        location = resolved.get(cursor, {})
        for cursor, own_location in reversed(pending):
            location = {**location, **own_location}
            resolved[cursor] = location
    return resolved


def _occurrence_observations(
    occurrences: Sequence[Mapping[str, Any]], locations: Mapping[str, Mapping[str, Any]],
    runtime: Mapping[str, Any],
    *, qualify: bool = True,
) -> dict[str, Any]:
    layers: dict[object, list[str]] = defaultdict(list)
    effects: dict[tuple[object, object], list[str]] = defaultdict(list)
    textures: dict[tuple[object, object, object, str], list[str]] = defaultdict(list)
    components: dict[tuple[object, str, object, object], list[str]] = defaultdict(list)
    layer_objects: dict[object, set[object]] = defaultdict(set)
    output: dict[str, dict[str, Any]] = {}
    for item in occurrences:
        identity = item["occurrence_id"]
        location = locations[identity]
        layer = location.get("layer_id")
        if layer is not None and "object_index" in location:
            layer_objects[layer].add(location["object_index"])
        inventory = "package_entry_index" in location and "layer_id" not in location and "object_index" not in location
        output[identity] = {
            "occurrenceId": identity, "domain": item.get("domain"), "kind": item.get("kind"),
            "familyKey": item.get("family_key"),
            "consumptionScope": "inventory-only" if inventory else "authored-occurrence",
            "authoredVisibility": item.get("effective_visibility"),
            "authoredInputState": item.get("slot_state", item.get("state")),
            "observedStages": ["declared"], "evidenceRefs": [], "reasons": [],
            "observationState": "inventory-only" if inventory else "unknown",
            "visibleContribution": "unknown",
            **({"instanceCoverage": "unknown"} if item.get("domain") == "particle" else {}),
        }
        if inventory:
            continue
        domain, kind = item.get("domain"), item.get("kind")
        if domain == "layer" or (domain == "particle" and kind == "layer"):
            layers[layer].append(identity)
        elif domain == "effect":
            effects[(layer, location.get("effect_index"))].append(identity)
        elif domain == "texture":
            resource = item.get("resource")
            resource = resource if isinstance(resource, Mapping) else {}
            paths = {path_identity(value) for value in (item.get("reference"), resource.get("relative_path")) if isinstance(value, str)}
            if layer is not None:
                for path in paths:
                    textures[(layer, location.get("effect_index"), location.get("slot_index"), path)].append(identity)
        elif domain == "particle" and "component_index" in location:
            path = location.get("definition_path")
            if isinstance(path, str):
                components[(layer, path_identity(path), location.get("component_category"), location["component_index"])].append(identity)

    def record(identities: Sequence[str], stages: Sequence[str], reference: dict[str, Any], reason: object = None) -> None:
        for identity in identities:
            observed = output[identity]
            observed["observedStages"] = sorted(set(observed["observedStages"]) | set(stages))
            observed["evidenceRefs"].append(reference)
            if isinstance(reason, str) and reason and reason not in observed["reasons"]:
                observed["reasons"].append(reason)

    disposition = runtime.get("effect_runtime_disposition", {})
    resolved = runtime.get("resolved_material_graph_execution", {})
    graph = resolved.get("graph_observations", {}) if isinstance(resolved, Mapping) else {}
    fallback_sources = (
        ("effectDisposition", disposition.get("records", []) if isinstance(disposition, Mapping) else []),
        ("visualFailurePassthrough", graph.get("visual_failure_passthroughs", []) if isinstance(graph, Mapping) else []),
    )
    if qualify:
        for channel, records in fallback_sources:
            for index, entry in enumerate(records if isinstance(records, list) else []):
                if not isinstance(entry, Mapping):
                    continue
                if channel == "effectDisposition" and not (
                    entry.get("attribution") == "exact-key" and entry.get("kind") in {"fallback", "passthrough"}
                ):
                    continue
                layer = entry.get("layer_id")
                identities = effects.get((layer, entry.get("effect_index")), [])
                if len(layer_objects.get(layer, set())) > 1:
                    record(identities, [], {"channel": channel, "recordIndex": index}, "authored-layer-identity-ambiguous")
                    continue
                record(identities, ["fallback"], {"channel": channel, "recordIndex": index}, entry.get("reason"))

    sources = {}
    for channel, field in (("composition", "composition_observations"), ("particleComponent", "particle_component_observations")):
        carrier = runtime.get(field)
        carrier = carrier if isinstance(carrier, Mapping) else {}
        events = carrier.get("events", [])
        events = events if isinstance(events, list) else []
        sources[channel] = {key: value for key, value in carrier.items() if key != "events"}
        sources[channel]["eventCount"] = len(events)
        sources[channel]["truncatedRows"] = 0
        for event_index, event in enumerate(events):
            if not isinstance(event, Mapping) or event.get("schemaVersion") != 1:
                continue
            truncated = event.get("truncatedRows")
            if isinstance(truncated, int):
                sources[channel]["truncatedRows"] += truncated
            if not qualify:
                continue
            if channel == "particleComponent":
                path = event.get("particlePath")
                if not isinstance(path, str):
                    continue
                key = (event.get("layerID"), path_identity(path), event.get("category"), event.get("componentIndex"))
                identities = components.get(key, [])
                if len(identities) == 1:
                    stage = event.get("stage")
                    record(identities, [stage] if isinstance(stage, str) else [], {"channel": channel, "eventIndex": event_index}, event.get("reason"))
                elif identities:
                    record(identities, [], {"channel": channel, "eventIndex": event_index}, "particle-definition-identity-ambiguous")
                continue
            rows = event.get("rows", [])
            rows = rows if isinstance(rows, list) else []
            logical_tails = {
                (row.get("layerID"), row.get("source", {}).get("textureToken")): row_index
                for row_index, row in enumerate(rows)
                if isinstance(row, Mapping) and row.get("outcome") == "terminal-consumed"
                and row.get("access") in {"output-texture-composite", "terminal-material-replay"}
                and isinstance(row.get("source"), Mapping)
                and isinstance(row["source"].get("textureToken"), str)
                and row["source"]["textureToken"]
            }
            for row_index, row in enumerate(rows):
                if not isinstance(row, Mapping):
                    continue
                layer = row.get("layerID")
                if layer is None:
                    continue
                identities = [*layers.get(layer, []), *effects.get((layer, row.get("effectIndex")), [])]
                source = row.get("source")
                source = source if isinstance(source, Mapping) else {}
                logical = source.get("logical")
                access, outcome = row.get("access"), row.get("outcome")
                details = row.get("details")
                details = details if isinstance(details, Mapping) else {}
                if row.get("kind") == "particle":
                    path, ordinal = details.get("particlePath"), details.get("rendererComponentIndex")
                    if isinstance(path, str) and isinstance(ordinal, str) and ordinal.isdecimal():
                        candidates = components.get((layer, path_identity(path), "renderer", int(ordinal)), [])
                        if len(candidates) == 1:
                            identities.extend(candidates)
                        elif candidates:
                            record(candidates, [], {"channel": channel, "eventIndex": event_index, "rowIndex": row_index}, "particle-renderer-identity-ambiguous")
                if access == "texture-bind" and isinstance(logical, str) and logical.startswith("asset:"):
                    candidates = textures.get((layer, row.get("effectIndex"), row.get("slot"), path_identity(logical[6:])), [])
                    if candidates and details.get("selectionMetadataRole") == "prepared-logical-origin":
                        record(candidates, ["logical-origin-attributed"], {"channel": channel, "eventIndex": event_index, "rowIndex": row_index}, "physical-binding-replaced")
                    elif len(candidates) == 1:
                        identities.extend(candidates)
                    elif candidates:
                        record(candidates, [], {"channel": channel, "eventIndex": event_index, "rowIndex": row_index}, "authored-pass-identity-ambiguous")
                reference = {"channel": channel, "eventIndex": event_index, "rowIndex": row_index}
                if len(layer_objects.get(layer, set())) > 1:
                    record(identities, [], reference, "authored-layer-identity-ambiguous")
                    continue
                if not event.get("surfaceIdentity") or not event.get("commandBufferToken"):
                    record(identities, [], reference, "surface-or-submission-identity-unavailable")
                    continue
                stages = [outcome] if isinstance(outcome, str) else []
                if row.get("kind") == "tail-consume" and outcome == "terminal-consumed":
                    stages = ["named-publication-only" if access == "named-publication-only" else "logical-tail-consumed"]
                if access == "texture-bind" and outcome in {"draw-encoded", "encoded"}:
                    stages.append("bound")
                elif access == "color-attachment-read" and outcome in {"draw-encoded", "encoded"}:
                    stages.append("attachment-read-encoded")
                if event.get("gpuStatus") == "completed" and outcome in {"draw-encoded", "encoded", "terminal-consumed"}:
                    stages.append("gpu-completed")
                elif event.get("gpuStatus") == "failed":
                    stages.append("gpu-failed")
                target = row.get("target")
                target = target if isinstance(target, Mapping) else {}
                tail_index = logical_tails.get((layer, target.get("textureToken")))
                if tail_index is not None and outcome in {"draw-encoded", "encoded"} and event.get("gpuStatus") == "completed":
                    stages.append("logical-tail-consumed")
                    reference["logicalTailRowIndex"] = tail_index
                record(identities, stages, reference, row.get("reason"))
    for observed in output.values():
        if observed["consumptionScope"] == "inventory-only":
            continue
        stages = set(observed["observedStages"])
        if stages & {"failed", "gpu-failed", "rejected", "unsupported"}:
            state = "failed"
        elif "fallback" in stages:
            state = "fallback"
        elif stages & {"evaluated", "accepted-birth", "gpu-completed"}:
            state = "executed"
        elif stages & {"draw-encoded", "encoded", "logical-tail-consumed"}:
            state = "encoded"
        elif stages & {"prepared", "prepared-executable"}:
            state = "prepared"
        elif "not-selected" in stages:
            state = "not-selected"
        elif "not-triggered" in stages:
            state = "not-triggered"
        else:
            state = "unknown"
        observed["observationState"] = state
    return {
        "claimBoundary": "exact-declaration-or-bounded-consumer-observation-not-visible-contribution",
        "sources": sources, "indexedOccurrenceCount": len(output), "occurrences": list(output.values()),
        "scopeCounts": dict(sorted(Counter(item["consumptionScope"] for item in output.values()).items())),
        "runtimeCandidateStateCounts": dict(sorted(Counter(
            item["observationState"] for item in output.values() if item["consumptionScope"] == "authored-occurrence"
        ).items())),
        "stateCounts": dict(sorted(Counter(item["observationState"] for item in output.values()).items())),
        "reasonGroups": [
            {"domain": domain, "kind": kind, "reason": reason, "occurrenceCount": count}
            for (domain, kind, reason), count in sorted(Counter(
                (str(item["domain"]), str(item["kind"]), reason)
                for item in output.values() for reason in item["reasons"]
            ).items())
        ],
    }


def _attempt(
    row: Mapping[str, Any], raw: Mapping[str, Any], observation: Mapping[str, Any],
    report_meta: Mapping[str, Any], sample_index: int, app_identity: object,
    occurrences: Sequence[Mapping[str, Any]], locations: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    identity = _input_identity(row, raw)
    status = _sample_status(observation)
    first = observation.get("firstBreakpoint")
    first = first if isinstance(first, Mapping) else None
    raw_runtime = raw.get("runtime")
    raw_runtime = raw_runtime if isinstance(raw_runtime, Mapping) else {}
    app_verified_after = app_identity.get("verified_after") if isinstance(app_identity, Mapping) else None
    runtime = {
        "status": status, "firstBreakpoint": first,
        "secondaryEvents": observation.get("secondaryEvents", []),
        "evidenceSummary": observation.get("evidenceSummary", {}),
        "benchmarkResultIgnored": observation.get("benchmarkResultIgnored", {}),
        "occurrenceObservations": {
            **_occurrence_observations(occurrences, locations, raw_runtime,
                                      qualify=identity["status"] == "matched" and app_verified_after is not False),
            "inputQualification": identity["status"],
        },
    }
    if identity["status"] in {"unknown", "mismatch"}:
        runtime.update(observedStatus=status, status="input-identity-" + identity["status"])
    raw_evidence = raw.get("evidence")
    paths = {
        str(key): value for key, value in raw_evidence.items() if isinstance(value, str)
    } if isinstance(raw_evidence, Mapping) else {}
    reference = {"path": report_meta["path"], "sha256": report_meta["sha256"], "sampleIndex": sample_index}
    return {
        "id": f"{report_meta['sha256']}:{sample_index}",
        "inputIdentity": identity, "appIdentity": app_identity,
        "inputStatus": raw.get("input_status"), "inputReasonCode": raw.get("input_reason_code"),
        "runtime": runtime, "evidence": {"report": reference, "sampleEvidencePaths": paths,
            "snapshotCapture": raw_evidence.get("snapshot_capture") if isinstance(raw_evidence, Mapping) else None},
        "nextAction": "rerun-with-verified-app-identity" if app_verified_after is False else _next_action(runtime["status"], first),
    }


def build_archive(
    samples_root: Path,
    snapshot_path: Path,
    report_paths: Sequence[Path],
    *,
    base_archive_path: Path | None = None,
) -> dict[str, Any]:
    if not snapshot_path.is_file():
        raise ValueError(
            f"census cache is missing: {snapshot_path}; pass --snapshot <existing-cache> "
            "or explicitly run python3.12 script/scene_capability_census.py generate "
            "with the matching --samples-root and --snapshot first"
        )
    if not samples_root.is_dir():
        raise ValueError(f"samples root is not a directory: {samples_root}")
    if not report_paths:
        raise ValueError("at least one benchmark report is required")

    sample_ids = [item.name for item in iter_sample_directories(samples_root)]
    if not sample_ids:
        raise ValueError(f"no samples found below {samples_root}")

    snapshot, snapshot_sha = _json(snapshot_path)
    static_rows = snapshot.get("samples")
    if not isinstance(static_rows, list):
        raise ValueError(f"census snapshot has no samples array: {snapshot_path}")
    static_by_id: dict[str, Mapping[str, Any]] = {}
    for row in static_rows:
        if not isinstance(row, Mapping) or not isinstance(row.get("sample_id"), str):
            raise ValueError(f"census snapshot has malformed sample row: {snapshot_path}")
        if row["sample_id"] in static_by_id:
            raise ValueError(f"duplicate census sample: {row['sample_id']}")
        static_by_id[row["sample_id"]] = row
    base: Mapping[str, Any] = {}
    retained: dict[str, dict[str, Any]] = {}
    base_source: dict[str, Any] = {}
    if base_archive_path is not None:
        base, base_sha = _json(base_archive_path)
        if (base.get("kind") != "scene-sample-debug-archive"
                or base.get("claimBoundary") != CLAIM_BOUNDARY
                or not isinstance(base.get("samples"), list)):
            raise ValueError(f"invalid base archive: {base_archive_path}")
        for row in base["samples"]:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                raise ValueError(f"malformed base archive sample: {base_archive_path}")
            if row["id"] in retained:
                raise ValueError(f"duplicate base archive sample: {row['id']}")
            retained[row["id"]] = row
        if set(retained) & set(static_by_id):
            raise ValueError("base archive and new census sample IDs overlap")
        if snapshot.get("snapshot", {}).get("inputs", {}).get("scope") != "subset":
            raise ValueError("base archive append requires an explicit subset census")
        base_source = {"baseArchive": {
            "path": str(base_archive_path), "sha256": base_sha,
            "sampleCount": len(retained),
        }}
    observed_ids = set(retained) | set(static_by_id)
    if observed_ids != set(sample_ids):
        missing = sorted(set(sample_ids) - observed_ids)
        extra = sorted(observed_ids - set(sample_ids))
        raise ValueError(
            f"census/sample-root mismatch: missing={missing[:5]} extra={extra[:5]}"
        )

    reports: list[Mapping[str, Any]] = []
    raw_by_id: dict[str, list[tuple[int, int, Mapping[str, Any]]]] = {}
    report_meta: list[dict[str, Any]] = []
    for report_index, report_path in enumerate(report_paths):
        report, report_sha = _json(report_path)
        raw_samples = report.get("samples")
        if not isinstance(raw_samples, list):
            raise ValueError(f"benchmark report has no samples array: {report_path}")
        report_meta.append({
            "path": str(report_path),
            "sha256": report_sha,
            "matrix": report.get("matrix"),
            "matrixSha256": report.get("matrix_sha256"),
            "sampleCount": len(raw_samples),
        })
        reports.append(report)
        seen_ids: set[str] = set()
        for index, sample in enumerate(raw_samples):
            if not isinstance(sample, Mapping) or not isinstance(sample.get("id"), str):
                raise ValueError(f"malformed sample in benchmark report: {report_path}")
            sample_id = sample["id"]
            if sample_id not in static_by_id:
                raise ValueError(f"report sample is outside the census: {sample_id}")
            if sample_id in seen_ids:
                raise ValueError(f"duplicate sample id within report {report_path}: {sample_id}")
            seen_ids.add(sample_id)
            raw_by_id.setdefault(sample_id, []).append((report_index, index, sample))

    preview_oracle_registry_path = (
        Path(__file__).resolve().parent
        / "scene_sample_preview_oracle_registry.json"
    )
    preview_oracle_uncontrolled = load_preview_oracle_registry(
        preview_oracle_registry_path
    )
    normalized = normalize_reports(reports, preview_oracle_uncontrolled)
    observations = {
        (item["reportIndex"], str(item["sampleId"])): item
        for item in normalized.get("samples", [])
        if isinstance(item, Mapping) and isinstance(item.get("sampleId"), str)
    }
    occurrence_rows = snapshot.get("occurrences")
    if not isinstance(occurrence_rows, list):
        occurrence_rows = snapshot.get("validation", {}).get("occurrence_index", {}).get("items", [])
    occurrences_by_sample: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for item in occurrence_rows:
        sample_id = item.get("sample_id", item.get("location", {}).get("sample_id"))
        occurrences_by_sample[str(sample_id)].append(item)

    archive_samples: list[dict[str, Any]] = []
    for sample_id in sample_ids:
        if sample_id in retained:
            archive_samples.append(retained[sample_id])
            continue
        row = static_by_id[sample_id]
        occurrences = occurrences_by_sample[sample_id]
        locations = _occurrence_locations(occurrences)
        attempts: dict[str, dict[str, Any]] = {}
        selected = None
        for report_index, sample_index, raw in raw_by_id.get(sample_id, []):
            attempt = _attempt(
                row, raw, observations[(report_index, sample_id)], report_meta[report_index],
                sample_index, reports[report_index].get("app_identity"),
                occurrences, locations,
            )
            attempts[attempt["id"]] = attempt
            selected = attempt
        archive_samples.append({
            "id": sample_id,
            "title": row.get("title", sample_id),
            "authored": {
                "projectSha256": row.get("project_sha256"),
                "packageSha256": row.get("package_sha256"),
                "treeSha256": row.get("tree_sha256"),
                "parseState": row.get("parse_state"),
                "diagnostics": row.get("diagnostics", []),
                "inventoryScope": row.get("inventory_scope"),
                "objectCount": row.get("object_count"),
                "occurrenceCount": row.get("occurrence_count"),
                "visibleOccurrenceCount": row.get("visible_occurrence_count"),
                "effectInstanceCount": row.get("effect_instance_count"),
                "particleLayerCount": row.get("particle_layer_count"),
                "dynamicFeatureCounts": row.get("dynamic_feature_counts", {}),
            },
            "attempts": list(attempts.values()),
            "selectedAttempt": selected["id"] if selected else None,
            "selectionBasis": "last-explicit-report" if selected else None,
            "runtime": selected["runtime"] if selected else {
                "status": "not-run", "firstBreakpoint": None,
                "occurrenceObservations": _occurrence_observations(occurrences, locations, {}),
            },
            "evidence": selected["evidence"] if selected else {"report": None},
            "nextAction": selected["nextAction"] if selected else _next_action("not-run", None),
        })

    status_counts: Counter[str] = Counter()
    breakpoint_counts: Counter[str] = Counter()
    scope_counts: Counter[str] = Counter()
    runtime_candidate_states: Counter[str] = Counter()
    scope_sample_count = 0
    for row in archive_samples:
        status_counts[row["runtime"]["status"]] += 1
        observation = row["runtime"].get("occurrenceObservations", {})
        if "scopeCounts" in observation and observation.get("indexedOccurrenceCount") == row["authored"].get("occurrenceCount"):
            scope_sample_count += 1
            scope_counts.update(observation["scopeCounts"])
            runtime_candidate_states.update(observation["runtimeCandidateStateCounts"])
        first = row["runtime"].get("firstBreakpoint")
        if first:
            key = f"{first.get('stage', 'unknown-stage')}:{first.get('reasonCode', 'unknown-reason')}"
            breakpoint_counts[key] += 1
    app_identities = list(base.get("appIdentities", []))
    app_identities.extend(
        report.get("app_identity")
        for report in reports
        if isinstance(report.get("app_identity"), Mapping)
    )
    return {
        "schemaVersion": 1,
        "kind": "scene-sample-debug-archive",
        "claimBoundary": CLAIM_BOUNDARY,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": {
            **base_source,
            "samplesRoot": str(samples_root),
            "sampleCount": len(sample_ids),
            "sampleIdManifestSha256": _corpus_manifest(sample_ids),
            "censusSnapshot": {
                "path": str(snapshot_path),
                "sha256": snapshot_sha,
                "sampleCount": len(static_rows),
                **({"scope": "subset"} if base_archive_path is not None else {}),
            },
            "previewOracleRegistry": {
                "path": str(preview_oracle_registry_path),
                "sha256": sha256_file(preview_oracle_registry_path),
                "registeredSampleCount": len(preview_oracle_uncontrolled),
            },
        },
        "reports": [*base.get("reports", []), *report_meta],
        "appIdentities": app_identities,
        "summary": {
            "sampleCount": len(archive_samples),
            "reportedSampleCount": sum(row["evidence"].get("report") is not None for row in archive_samples),
            "attemptCount": sum(len(row.get("attempts", [])) if "attempts" in row else int(row["evidence"].get("report") is not None) for row in archive_samples),
            "sourceInvalidAttemptCount": sum(attempt.get("inputStatus") == "source-invalid" for row in archive_samples for attempt in row.get("attempts", [])),
            "occurrenceScopes": {
                "classifiedSampleCount": scope_sample_count,
                "unclassifiedSampleCount": len(archive_samples) - scope_sample_count,
                "inventoryOnlyCount": scope_counts["inventory-only"],
                "runtimeCandidateCount": scope_counts["authored-occurrence"],
                "runtimeCandidateStateCounts": dict(sorted(runtime_candidate_states.items())),
            },
            "statusCounts": dict(sorted(status_counts.items())),
            "firstBreakpointCounts": dict(sorted(breakpoint_counts.items())),
            "normalizedDiagnosticClaim": normalized.get("claimBoundary"),
        },
        "samples": archive_samples,
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES_ROOT)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--base-archive", type=Path)
    parser.add_argument("--report", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        archive = build_archive(
            args.samples_root.expanduser().resolve(),
            args.snapshot.expanduser().resolve(),
            [path.expanduser().resolve() for path in args.report],
            base_archive_path=args.base_archive.expanduser().resolve() if args.base_archive else None,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(archive, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (OSError, ValueError) as error:
        print(f"scene_sample_debug_archive: {error}", file=sys.stderr)
        return 2
    print(json.dumps({
        "sampleCount": archive["summary"]["sampleCount"],
        "reportedSampleCount": archive["summary"]["reportedSampleCount"],
        "statusCounts": archive["summary"]["statusCounts"],
        "output": str(args.output),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
