#!/usr/bin/env python3
"""Build the deterministic, read-only authored capability census for all Scene samples.

This inventory answers what the corpus declares, not what the current renderer
executes. It never retains shader, SceneScript, layer text, image, or binary payloads.
Runtime support and visual equivalence remain separate evidence.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath
from typing import Any, Iterable
from urllib.parse import quote

from scene_capability_census_effects import (
    census_effect,
    census_image_layer,
    effective_visibility,
    object_kind,
    summarize_texture_families,
)
from scene_capability_census_io import (
    PkgArchive,
    ResolvedResource,
    SceneResourceView,
    atomic_write,
    canonical_sha256,
    decode_json,
    directory_manifest,
    ensure_outputs_outside_roots,
    iter_sample_directories,
    normalize_path,
    package_category,
    parse_tex_summary,
    path_identity,
    sha256_bytes,
    sha256_file,
    tree_manifest,
)
from scene_capability_census_particles import census_particle_layer, particle_summary
from scene_capability_census_resources import census_package_resources, shader_profile
from scene_capability_census_profiles import (
    ParameterProfiles,
    SchemaInventory,
    family_key,
    merge_counts,
    occurrence_id,
    recursive_dynamic_features,
    revision_key,
    safe_value_shape,
    scenescript_audio_registrations,
)


from scene_capability_census_samples import (
    AUDIO_SPECTRUM_UNIFORM_PATTERN,
    AUDIO_RESPONSE_COMBO_KEY,
    AUDIO_RESPONSE_CONSTANT_KEYS,
    json_document_kind,
    project_package_name,
    project_title_metadata,
    _object_parameters,
    authored_layer_visibilities,
    _dynamic_occurrences,
    _project_audio_support_occurrences,
    _shader_audio_contract,
    _audio_owner_occurrences,
    _project_properties,
    _sample_census,
    summarize_audio_declarations,
)
from scene_capability_census_contracts import (
    DOMAINS,
    REPAIR_STATUS_CONTRACT,
    REPAIR_COMMIT_PLACEHOLDER,
    DEFAULT_REGRESSION_GATE_KINDS,
    FAMILY_MAP_SCHEMA_VERSION,
    _EMPTY_FAMILY_MAP,
    load_family_map,
    _family_map_structural_failures,
    _apply_family_map,
    family_map_anchor_failures,
    load_repair_ledger,
    validate_repair_ledger,
    validate_repair_references,
    _symbol_present,
)
from scene_capability_census_reporting import (
    render_markdown,
    render_sample_markdown,
    canonical_json_bytes,
    snapshot_payload,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SAMPLES_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊/Scene"
DEFAULT_STOCK_ROOT = (
    REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
DEFAULT_MATRIX = REPOSITORY_ROOT / "script/scene_wallpaper_full_sample_matrix.json"
DEFAULT_LEDGER = REPOSITORY_ROOT / "script/scene_capability_repair_ledger.json"
DEFAULT_FAMILY_MAP = REPOSITORY_ROOT / "script/scene_capability_family_map.json"
DEFAULT_SNAPSHOT = REPOSITORY_ROOT / ".artifacts/scene-evidence/census/scene_capability_census_snapshot.json"


GENERATOR_PATHS = (
    "script/scene_capability_census.py",
    "script/scene_capability_census_contracts.py",
    "script/scene_capability_census_effects.py",
    "script/scene_capability_census_io.py",
    "script/scene_capability_census_particles.py",
    "script/scene_capability_census_profiles.py",
    "script/scene_capability_census_reporting.py",
    "script/scene_capability_census_resources.py",
    "script/scene_capability_census_samples.py",
)


def generator_manifest() -> dict[str, Any]:
    files = {
        relative: sha256_file(REPOSITORY_ROOT / relative)
        for relative in GENERATOR_PATHS
    }
    return {
        "files": files,
        "sha256": canonical_sha256(files),
    }


def matrix_identity(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"state": "missing", "relative_path": relative_repo_path(path)}
    payload = json.loads(path.read_text(encoding="utf-8"))
    samples = payload.get("samples") if isinstance(payload, dict) else None
    ids = [str(item.get("id")) for item in samples or [] if isinstance(item, dict)]
    return {
        "state": "loaded",
        "relative_path": relative_repo_path(path),
        "sha256": sha256_file(path),
        "sample_count": len(ids),
        "sample_ids": sorted(ids),
    }


def relative_repo_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPOSITORY_ROOT.resolve()).as_posix()
    except ValueError:
        return path.name


def corpus_manifest(samples: list[Path]) -> str:
    return sha256_bytes(("\n".join(sample.name for sample in samples) + "\n").encode("utf-8"))


def _family_rollup(
    occurrences: list[dict[str, Any]],
    ledger: dict[str, Any],
) -> list[dict[str, Any]]:
    repair_by_family = {
        str(item["family_key"]): item
        for item in ledger.get("families", [])
        if isinstance(item, dict) and isinstance(item.get("family_key"), str)
    }
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for occurrence in occurrences:
        grouped[occurrence["family_key"]].append(occurrence)
    result = []
    for key, values in sorted(grouped.items()):
        sample_ids = sorted({str(item["location"].get("sample_id")) for item in values})
        visible_values = [
            item for item in values
            if item.get("effective_visibility") in {"visible", "dynamic"}
        ]
        row = {
            "family_key": key,
            "domain": values[0]["domain"],
            "kind": values[0]["kind"],
            "occurrence_count": len(values),
            "sample_count": len(sample_ids),
            "sample_ids": sample_ids,
            "visible_occurrence_count": len(visible_values),
            "visible_sample_count": len({
                str(item["location"].get("sample_id")) for item in visible_values
            }),
            "revision_count": len({
                item.get("revision_key") for item in values if item.get("revision_key")
            }),
            "repair": repair_by_family.get(key, {"repair_state": "untriaged"}),
            "feature_summary": _family_feature_summary(values),
        }
        result.append(row)
    return result


def _family_feature_summary(values: list[dict[str, Any]]) -> dict[str, Any]:
    allowed = (
        "state", "slot_state", "provenance", "target_kind", "compose", "format", "uvs",
        "component_name", "parameter_keys", "combo_keys", "constant_keys", "render_state",
        "shader_features", "trigger", "value_state", "resolutions", "channels",
        "shader_stages", "has_audio_combo", "audio_constant_keys",
        "audio_parameter_keys", "resolution_states", "call_count", "activation_state",
        "scope_states", "admission_states", "statically_admitted_call_count",
        "cursor_event_exports", "cursor_event_unresolved_exports",
        "cursor_audio_consumer_state",
        "source_exact_resolutions", "source_exact_channels", "source_exact_stages",
        "source_abi_state_counts", "runtime_admission_state",
        "source_declares_audio_processing_combo",
    )
    summary: dict[str, Any] = {}
    for field in allowed:
        variants = {
            json.dumps(value[field], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            for value in values
            if field in value
        }
        if variants:
            summary[field] = [json.loads(value) for value in sorted(variants)[:32]]
    return summary


def build_census(
    samples_root: Path,
    stock_root: Path,
    matrix_path: Path,
    ledger_path: Path,
    family_map_path: Path = DEFAULT_FAMILY_MAP,
) -> dict[str, Any]:
    samples_root = samples_root.expanduser().resolve()
    stock_root = stock_root.expanduser().resolve()
    if not samples_root.is_dir():
        raise FileNotFoundError(samples_root)
    if not stock_root.is_dir():
        raise FileNotFoundError(stock_root)
    samples = list(iter_sample_directories(samples_root))
    matrix = matrix_identity(matrix_path)
    matrix_ids = set(matrix.get("sample_ids", []))
    profiles = ParameterProfiles()
    schema = SchemaInventory()
    sample_rows: list[dict[str, Any]] = []
    occurrences: list[dict[str, Any]] = []
    textures: list[dict[str, Any]] = []
    unclassified: list[dict[str, Any]] = []
    for sample in samples:
        row, sample_occurrences, sample_textures, sample_unknown = _sample_census(
            sample,
            stock_root,
            matrix_ids,
            profiles,
            schema,
        )
        sample_rows.append(row)
        occurrences.extend(sample_occurrences)
        textures.extend(sample_textures)
        unclassified.extend(sample_unknown)

    all_occurrences = sorted(
        [*occurrences, *textures],
        key=lambda value: value["occurrence_id"],
    )
    occurrence_ids = [item["occurrence_id"] for item in all_occurrences]
    duplicate_occurrences = sorted(
        identity for identity, count in Counter(occurrence_ids).items() if count > 1
    )
    occurrence_id_set = set(occurrence_ids)
    parameter_payloads = profiles.payloads()
    parameter_refs = [
        reference
        for profile in parameter_payloads
        for reference in profile["occurrence_refs"]
    ]
    orphan_parameter_refs = sorted(set(parameter_refs) - occurrence_id_set)
    missing_revision_ids = sorted(
        item["occurrence_id"] for item in all_occurrences if not item.get("revision_key")
    )
    texture_visibility_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if item["domain"] == "texture"
        and item["kind"] != "package-resource"
        and item.get("effective_visibility") not in {"visible", "dynamic", "hidden", "unknown"}
    )
    graph_binding_state_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if item["domain"] == "texture"
        and item["kind"] == "graph-binding"
        and item.get("slot_state") not in {"runtime-provided", "hole"}
    )
    family_namespace_failures = sorted(
        item["occurrence_id"]
        for item in all_occurrences
        if not item["family_key"].startswith(f"{item['domain']}/")
    )
    ledger = load_repair_ledger(ledger_path)
    family_keys = {item["family_key"] for item in all_occurrences}
    ledger_failures = validate_repair_ledger(ledger, family_keys)
    ledger_failures.extend(validate_repair_references(
        ledger,
        {sample.name for sample in samples},
        REPOSITORY_ROOT,
    ))
    family_rows = _family_rollup(all_occurrences, ledger)
    family_map, family_map_failures = load_family_map(family_map_path)
    capability_stats = _apply_family_map(family_rows, family_map, family_map_failures)
    schema_conservation = schema.conservation()
    parsed_count = sum(row["parse_state"] == "parsed" for row in sample_rows)
    failed_count = len(sample_rows) - parsed_count
    discovered_ids = [sample.name for sample in samples]
    added = sorted(set(discovered_ids) - matrix_ids)
    removed = sorted(matrix_ids - set(discovered_ids))
    texture_occurrences = [
        item for item in all_occurrences if item["domain"] == "texture"
    ]
    physical_textures = [
        item for item in texture_occurrences if item["kind"] == "package-resource"
    ]
    texture_uses = [
        item for item in texture_occurrences if item["kind"] != "package-resource"
    ]
    package_resource_occurrences = [
        item
        for item in all_occurrences
        if "package_entry_index" in item["location"]
    ]
    object_kind_counts: Counter[str] = Counter()
    visible_object_kind_counts: Counter[str] = Counter()
    package_category_counts: Counter[str] = Counter()
    dynamic_feature_counts: Counter[str] = Counter()
    for row in sample_rows:
        object_kind_counts.update(row.get("object_kind_counts", {}))
        visible_object_kind_counts.update(row.get("visible_object_kind_counts", {}))
        package_category_counts.update(row.get("package_categories", {}))
        dynamic_feature_counts.update(row.get("dynamic_feature_counts", {}))
    physical_tex_formats = Counter(
        str(item["tex"]["format_code"])
        for item in physical_textures
        if isinstance(item.get("tex"), dict) and item["tex"].get("state") == "parsed"
    )
    physical_tex_features = Counter()
    for item in physical_textures:
        tex = item.get("tex") or {}
        if tex.get("state") != "parsed":
            physical_tex_features["malformed"] += 1
            continue
        physical_tex_features["animated" if tex.get("is_animated") else "static"] += 1
        if tex.get("is_volume"):
            physical_tex_features["volume"] += 1
        if tex.get("is_video_mp4"):
            physical_tex_features["video-mp4"] += 1
    total_package_entries = sum(int(row.get("package_entry_count", 0)) for row in sample_rows)
    total_unique_package_paths = sum(
        int(row.get("package_unique_path_count", 0)) for row in sample_rows
    )
    failures = []
    if duplicate_occurrences:
        failures.append({"code": "duplicate-occurrence-identity", "occurrence_ids": duplicate_occurrences})
    if not schema_conservation["balanced"]:
        failures.append({"code": "schema-leaf-conservation-failed"})
    if total_package_entries != len(package_resource_occurrences):
        failures.append({"code": "package-resource-conservation-failed"})
    if orphan_parameter_refs:
        failures.append({
            "code": "parameter-occurrence-reference-orphaned",
            "occurrence_ids": orphan_parameter_refs,
        })
    if missing_revision_ids:
        failures.append({
            "code": "occurrence-revision-missing",
            "occurrence_ids": missing_revision_ids,
        })
    if texture_visibility_failures:
        failures.append({
            "code": "texture-use-visibility-missing",
            "occurrence_ids": texture_visibility_failures,
        })
    if graph_binding_state_failures:
        failures.append({
            "code": "graph-binding-misclassified-as-asset",
            "occurrence_ids": graph_binding_state_failures,
        })
    if family_namespace_failures:
        failures.append({
            "code": "family-domain-namespace-mismatch",
            "occurrence_ids": family_namespace_failures,
        })
    failures.extend(ledger_failures)
    failures.extend(family_map_failures)
    vocabulary = family_map.get("vocabulary") if isinstance(family_map.get("vocabulary"), dict) else {}
    stock_sha, stock_files, stock_bytes = directory_manifest(stock_root)
    result = {
        "schema_version": 1,
        "kind": "scene-capability-census",
        "snapshot": {
            "generator": {
                "path": relative_repo_path(Path(__file__)),
                "source_manifest": generator_manifest(),
                "canonical_json_contract": "sorted-keys-indented-utf8-v1",
            },
            "inputs": {
                "sample_root_label": "Workshop/Scene",
                "sample_id_manifest_sha256": corpus_manifest(samples),
                "stock_root_manifest_sha256": stock_sha,
                "stock_file_count": stock_files,
                "stock_byte_count": stock_bytes,
                "full_matrix": matrix,
                "repair_ledger": {
                    "relative_path": relative_repo_path(ledger_path),
                    "sha256": sha256_file(ledger_path) if ledger_path.is_file() else None,
                },
                "family_map": {
                    "relative_path": relative_repo_path(family_map_path),
                    "sha256": sha256_file(family_map_path) if family_map_path.is_file() else None,
                },
            },
            "boundaries": [
                "authored static observation never implies runtime support",
                "runtime evidence is not joined by this static census",
                "sample and layer identities are evidence locators, not product dispatch",
                "project title metadata is retained; layer text and shader, script, JSON fragment, texture, and binary payloads are not retained",
                "official visual equivalence requires a separate same-phase golden",
            ],
        },
        "summary": {
            "discovered_sample_count": len(samples),
            "parsed_sample_count": parsed_count,
            "failed_sample_count": failed_count,
            "matrix_sample_count": len(matrix_ids),
            "matrix_coverage_state": "current" if not added and not removed else "pending-expansion",
            "added_since_matrix": added,
            "removed_since_matrix": removed,
            "occurrence_count": len(all_occurrences),
            "package_entry_count": total_package_entries,
            "package_unique_path_count": total_unique_package_paths,
            "package_byte_count": sum(int(row.get("package_byte_count", 0)) for row in sample_rows),
            "package_category_counts": dict(sorted(package_category_counts.items())),
            "project_type_counts": dict(sorted(Counter(
                str(row.get("project_type")) for row in sample_rows if row.get("project_type")
            ).items())),
            "scene_entry_counts": dict(sorted(Counter(
                str(row.get("entry_path")) for row in sample_rows if row.get("entry_path")
            ).items())),
            "object_kind_counts": dict(sorted(object_kind_counts.items())),
            "visible_object_kind_counts": dict(sorted(visible_object_kind_counts.items())),
            "effect_instance_count": sum(int(row.get("effect_instance_count", 0)) for row in sample_rows),
            "particle_layer_count": sum(int(row.get("particle_layer_count", 0)) for row in sample_rows),
            "dynamic_feature_counts": dict(sorted(dynamic_feature_counts.items())),
            "occurrences_by_domain": dict(sorted(Counter(
                item["domain"] for item in all_occurrences
            ).items())),
            "family_count": len(family_keys),
            "families_by_domain": dict(sorted(Counter(
                item["domain"] for item in family_rows
            ).items())),
            "capability_mapping": {
                "vocabulary_count": len(vocabulary),
                "rule_count": len(family_map.get("rules") or []),
                "override_count": len(family_map.get("family_overrides") or {}),
                "mapped_family_count": capability_stats["mapped_family_count"],
                "unknown_family_count": capability_stats["unknown_family_count"],
                "unknown_reason_counts": capability_stats["unknown_reason_counts"],
                "capability_coverage": capability_stats["per_capability"],
            },
            "parameter_profile_count": len(parameter_payloads),
            "schema_field_profile_count": len(schema.payloads()),
            "unclassified_count": len(unclassified),
            "generic_or_unknown_family_count": sum(
                any(token in item["kind"].casefold() for token in ("unknown", "unresolved", "malformed"))
                for item in family_rows
            ),
            "package_anomaly_count": sum(len(row["diagnostics"]) for row in sample_rows),
            "texture": {
                "physical_resource_count": len(physical_textures),
                "physical_format_counts": dict(sorted(physical_tex_formats.items())),
                "physical_feature_counts": dict(sorted(physical_tex_features.items())),
                "use_occurrence_count": len(texture_uses),
                "use_state_counts": dict(sorted(Counter(
                    str(item.get("slot_state", "unknown")) for item in texture_uses
                ).items())),
                "all": summarize_texture_families(texture_occurrences),
            },
            "particle": particle_summary([
                item for item in all_occurrences if item["domain"] == "particle"
            ]),
            "audio_declarations": summarize_audio_declarations(all_occurrences),
        },
        "samples": sorted(sample_rows, key=lambda value: value["sample_id"]),
        "families": family_rows,
        "capability_vocabulary": dict(sorted(vocabulary.items())),
        "occurrences": all_occurrences,
        "parameter_profiles": parameter_payloads,
        "schema_fields": schema.payloads(),
        "unclassified": sorted(unclassified, key=canonical_sha256),
        "repair_ledger": ledger,
        "validation": {
            "failures": failures,
            "conservation": {
                "samples": {
                    "discovered": len(samples),
                    "parsed_plus_failed": parsed_count + failed_count,
                    "balanced": len(samples) == parsed_count + failed_count,
                },
                "sample_occurrence_refs": sum(len(row["occurrence_refs"]) for row in sample_rows),
                "global_occurrence_count": len(all_occurrences),
                "occurrences_balanced": (
                    sum(len(row["occurrence_refs"]) for row in sample_rows) == len(all_occurrences)
                ),
                "schema_fields": schema_conservation,
                "package_resources": {
                    "package_entries": total_package_entries,
                    "resource_occurrences": len(package_resource_occurrences),
                    "balanced": total_package_entries == len(package_resource_occurrences),
                },
                "parameter_occurrence_refs": {
                    "classified": len(parameter_refs),
                    "orphan_count": len(orphan_parameter_refs),
                    "balanced": not orphan_parameter_refs,
                },
                "revisions": {
                    "occurrence_count": len(all_occurrences),
                    "missing_count": len(missing_revision_ids),
                    "balanced": not missing_revision_ids,
                },
                "texture_use_visibility": {
                    "use_count": len(texture_uses),
                    "missing_count": len(texture_visibility_failures),
                    "balanced": not texture_visibility_failures,
                },
                "capability_mapping": {
                    "families_total": len(family_rows),
                    "mapped": capability_stats["mapped_family_count"],
                    "unknown": capability_stats["unknown_family_count"],
                    "balanced": (
                        capability_stats["mapped_family_count"]
                        + capability_stats["unknown_family_count"]
                        == len(family_rows)
                    ),
                },
            },
            "determinism": {
                "sort_contract": "all IDs, paths, families, occurrences, profiles and diagnostics canonical",
                "payload_sha256": None,
            },
        },
    }
    digest_input = json.loads(json.dumps(result, ensure_ascii=False))
    digest_input["validation"]["determinism"]["payload_sha256"] = None
    result["validation"]["determinism"]["payload_sha256"] = canonical_sha256(digest_input)
    return result


def _report_output_paths(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    snapshot = Path(args.snapshot).expanduser()
    overview = Path(args.markdown).expanduser()
    configured_samples = getattr(args, "sample_markdown", None)
    samples = (
        Path(configured_samples).expanduser() if configured_samples is not None
        else overview.with_name("scene-corpus-sample-inventory.md")
    )
    outputs = (snapshot, overview, samples)
    ensure_outputs_outside_roots(outputs, [args.samples_root, args.stock_root])
    return outputs


def _report_payloads(
    census: dict[str, Any], outputs: tuple[Path, Path, Path]
) -> dict[Path, bytes]:
    snapshot, overview, samples = outputs
    snapshot_bytes = canonical_json_bytes(snapshot_payload(census))
    sample_link = quote(os.path.relpath(samples.resolve(), overview.parent.resolve()), safe="/.-_")
    overview_link = quote(os.path.relpath(overview.resolve(), samples.parent.resolve()), safe="/.-_")
    # Every projection completes before generate performs its first atomic write.
    return {
        snapshot: snapshot_bytes,
        overview: (render_markdown(census, sample_markdown_link=sample_link) + "\n").encode("utf-8"),
        samples: (render_sample_markdown(
            census, overview_link=overview_link,
            snapshot_sha256=sha256_bytes(snapshot_bytes),
        ) + "\n").encode("utf-8"),
    }


def generate(args: argparse.Namespace) -> int:
    outputs = _report_output_paths(args)
    census = build_census(
        args.samples_root, args.stock_root, args.matrix, args.ledger,
        getattr(args, "family_map", DEFAULT_FAMILY_MAP),
    )
    if census["validation"]["failures"]:
        print(json.dumps(census["validation"], ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    payloads = _report_payloads(census, outputs)
    for path, payload in payloads.items():
        atomic_write(path, payload)
    print(json.dumps({
        "sample_count": census["summary"]["discovered_sample_count"],
        "occurrence_count": census["summary"]["occurrence_count"],
        "family_count": census["summary"]["family_count"],
        "added_since_matrix": census["summary"]["added_since_matrix"],
        "snapshot": str(outputs[0]),
        "markdown": str(outputs[1]),
        "sample_markdown": str(outputs[2]),
        "payload_sha256": census["validation"]["determinism"]["payload_sha256"],
    }, ensure_ascii=False, indent=2))
    return 0


def verify(args: argparse.Namespace) -> int:
    if not args.snapshot.is_file():
        print(f"snapshot cache missing: {args.snapshot}; pass --snapshot or run generate explicitly before verify", file=sys.stderr)
        return 1
    outputs = _report_output_paths(args)
    expected = build_census(
        args.samples_root, args.stock_root, args.matrix, args.ledger,
        getattr(args, "family_map", DEFAULT_FAMILY_MAP),
    )
    failures = list(expected["validation"]["failures"])
    payloads = _report_payloads(expected, outputs)
    codes = ("snapshot-drift", "markdown-drift", "sample-markdown-drift")
    for code, (path, payload) in zip(codes, payloads.items()):
        if not path.is_file() or path.read_bytes() != payload:
            failures.append({"code": code, "path": str(path)})
    family_map, _ = load_family_map(getattr(args, "family_map", DEFAULT_FAMILY_MAP))
    failures.extend(family_map_anchor_failures(family_map, REPOSITORY_ROOT))
    print(json.dumps({
        "passed": not failures,
        "sample_count": expected["summary"]["discovered_sample_count"],
        "payload_sha256": expected["validation"]["determinism"]["payload_sha256"],
        "failures": failures,
    }, ensure_ascii=False, indent=2))
    return 1 if failures else 0


def query(args: argparse.Namespace) -> int:
    if not any((args.family, args.sample, args.domain)):
        print("query requires --family, --sample, or --domain", file=sys.stderr)
        return 2
    live = getattr(args, "live", False)
    if live:
        census = build_census(
            args.samples_root, args.stock_root, args.matrix, args.ledger,
            getattr(args, "family_map", DEFAULT_FAMILY_MAP),
        )
        if census["validation"]["failures"]:
            print(json.dumps(census["validation"], ensure_ascii=False, indent=2), file=sys.stderr)
            return 1
        candidates = census["occurrences"]
        source = "live-corpus"
    else:
        snapshot = getattr(
            args,
            "snapshot",
            DEFAULT_SNAPSHOT,
        )
        try:
            stored = json.loads(snapshot.read_text(encoding="utf-8"))
            candidates = stored["validation"]["occurrence_index"]["items"]
        except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
            print(
                f"unable to query local census snapshot {snapshot}: {error}. "
                "Pass --snapshot <existing-cache> or explicitly run "
                "python3.12 script/scene_capability_census.py generate "
                "with your --samples-root and --snapshot; use query --live "
                "only when a private corpus scan is intended.",
                file=sys.stderr,
            )
            return 1
        source = "cached-snapshot"
    matches = [
        value
        for value in candidates
        if (args.family is None or value["family_key"] == args.family)
        and (args.sample is None or str(value.get("sample_id") or value["location"].get("sample_id")) == args.sample)
        and (args.domain is None or value["domain"] == args.domain)
    ]
    print(json.dumps({
        "count": len(matches),
        "filters": {
            "family": args.family,
            "sample": args.sample,
            "domain": args.domain,
        },
        "source": source,
        "occurrences": matches,
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, handler in (("generate", generate), ("verify", verify), ("query", query)):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--samples-root", type=Path, default=DEFAULT_SAMPLES_ROOT)
        subparser.add_argument("--stock-root", type=Path, default=DEFAULT_STOCK_ROOT)
        subparser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
        subparser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
        subparser.add_argument("--family-map", type=Path, default=DEFAULT_FAMILY_MAP)
        if command != "query":
            subparser.add_argument(
                "--snapshot",
                type=Path,
                default=DEFAULT_SNAPSHOT,
            )
            subparser.add_argument(
                "--markdown",
                type=Path,
                default=(
                    REPOSITORY_ROOT
                    / "docs/scene/capabilities/scene-corpus-capability-inventory.md"
                ),
            )
            subparser.add_argument(
                "--sample-markdown",
                type=Path,
                help="sample detail output; defaults beside --markdown as scene-corpus-sample-inventory.md",
            )
        else:
            subparser.add_argument(
                "--snapshot",
                type=Path,
                default=DEFAULT_SNAPSHOT,
            )
            subparser.add_argument(
                "--live",
                action="store_true",
                help="rebuild the private authored corpus instead of querying the local cached compact index",
            )
            subparser.add_argument("--family")
            subparser.add_argument("--sample")
            subparser.add_argument("--domain", choices=DOMAINS)
        subparser.set_defaults(handler=handler)
    return parser.parse_args(list(argv) if argv is not None else None)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
