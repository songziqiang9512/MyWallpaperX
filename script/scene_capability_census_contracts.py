"""Validate declared census domains, family mappings, and repair evidence contracts."""

from __future__ import annotations
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any
from scene_capability_census_profiles import family_key


DOMAINS = (
    "resource",
    "shader",
    "layer",
    "material",
    "effect",
    "render-graph",
    "render-target",
    "texture",
    "particle",
    "audio-declaration",
    "dynamic-input",
    "project-property",
)


REPAIR_STATUS_CONTRACT = {
    "repair_state": [
        "untriaged", "diagnosed", "in-progress", "implemented", "bounded-verified",
    ],
    "runtime_proof_state": [
        "none", "partial-chain", "visible-chain-closed", "official-golden-equivalent",
    ],
    "regression_protection_state": [
        "none", "synthetic", "targeted-runtime", "milestone",
    ],
}


REPAIR_COMMIT_PLACEHOLDER = "uncommitted-working-tree"


DEFAULT_REGRESSION_GATE_KINDS = (
    "synthetic-positive", "synthetic-negative", "targeted-runtime", "milestone",
)


FAMILY_MAP_SCHEMA_VERSION = 1


_EMPTY_FAMILY_MAP: dict[str, Any] = {
    "schema_version": FAMILY_MAP_SCHEMA_VERSION,
    "vocabulary": {},
    "rules": [],
    "family_overrides": {},
}


def load_family_map(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Load the P0.2 declared-capability mapping input with structural validation.

    Structural failures surface as census validation failures so a broken map
    can never silently widen, narrow, or misdirect the family→capability
    association. Vocabulary anchor literals are deliberately checked only by
    `family_map_anchor_failures` (verify/tests), never here: ledger prose edits
    must not make the corpus snapshot drift.
    """
    if not path.is_file():
        return dict(_EMPTY_FAMILY_MAP), [{"code": "family-map-missing", "path": str(path)}]
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return dict(_EMPTY_FAMILY_MAP), [
            {"code": "family-map-unreadable", "path": str(path), "detail": str(error)}
        ]
    if not isinstance(payload, dict):
        return dict(_EMPTY_FAMILY_MAP), [{"code": "family-map-root-not-object", "path": str(path)}]
    return payload, _family_map_structural_failures(payload)


def _family_map_structural_failures(payload: dict[str, Any]) -> list[dict[str, Any]]:
    import re

    failures: list[dict[str, Any]] = []
    if payload.get("schema_version") != FAMILY_MAP_SCHEMA_VERSION:
        failures.append({
            "code": "family-map-schema-version",
            "detail": str(payload.get("schema_version")),
        })
    vocabulary = payload.get("vocabulary")
    if not isinstance(vocabulary, dict) or not vocabulary:
        failures.append({"code": "family-map-vocabulary-missing"})
        vocabulary = {}
    for capability, entry in sorted(vocabulary.items()):
        if not re.fullmatch(r"cap\.[a-z0-9]+(\.[a-z0-9-]+)+", capability):
            failures.append({"code": "family-map-invalid-capability-id", "capability": capability})
        if not isinstance(entry, dict):
            failures.append({"code": "family-map-invalid-vocabulary-entry", "capability": capability})
            continue
        authority = entry.get("authority")
        if not isinstance(authority, dict) or not authority.get("doc") or not authority.get("row"):
            failures.append({"code": "family-map-invalid-authority", "capability": capability})
        if not entry.get("scope"):
            failures.append({"code": "family-map-missing-scope", "capability": capability})
    rules = payload.get("rules")
    if not isinstance(rules, list) or not rules:
        failures.append({"code": "family-map-rules-missing"})
        rules = []
    seen_rule_ids: set[str] = set()
    domain_fallback_index: dict[str, int] = {}
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            failures.append({"code": "family-map-invalid-rule", "detail": repr(rule)[:120]})
            continue
        rule_id = rule.get("rule_id")
        if (
            not isinstance(rule_id, str)
            or not rule_id.startswith("rule.")
            or rule_id in seen_rule_ids
        ):
            failures.append({"code": "family-map-invalid-rule-id", "rule_id": str(rule_id)})
        seen_rule_ids.add(str(rule_id))
        match = rule.get("match")
        if not isinstance(match, dict) or not isinstance(match.get("domain"), str):
            failures.append({"code": "family-map-invalid-match", "rule_id": str(rule_id)})
            continue
        domain = str(match["domain"])
        kind = match.get("kind")
        capabilities = rule.get("capabilities")
        unknown_reason = rule.get("unknown_reason")
        if capabilities is not None and not isinstance(capabilities, list):
            failures.append({
                "code": "family-map-invalid-capabilities-type",
                "rule_id": str(rule_id),
            })
            capabilities = None
        if bool(capabilities) == bool(unknown_reason):
            failures.append({
                "code": "family-map-rule-outcome-required",
                "rule_id": str(rule_id),
            })
        if kind is None:
            earlier_specific = any(
                isinstance(prior, dict)
                and isinstance(prior.get("match"), dict)
                and prior["match"].get("domain") == domain
                and prior["match"].get("kind") is not None
                for prior in rules[index + 1:]
            )
            if earlier_specific:
                failures.append({
                    "code": "family-map-fallback-before-specific",
                    "rule_id": str(rule_id),
                    "domain": domain,
                })
            domain_fallback_index[domain] = index
        if isinstance(unknown_reason, str) and not unknown_reason:
            failures.append({"code": "family-map-empty-unknown-reason", "rule_id": str(rule_id)})
        if isinstance(capabilities, list):
            if not capabilities:
                failures.append({"code": "family-map-empty-capabilities", "rule_id": str(rule_id)})
            for ref in capabilities:
                if not isinstance(ref, dict) or not ref.get("profile"):
                    failures.append({
                        "code": "family-map-invalid-capability-ref",
                        "rule_id": str(rule_id),
                    })
                    continue
                if ref.get("capability") not in vocabulary:
                    failures.append({
                        "code": "family-map-undefined-capability",
                        "rule_id": str(rule_id),
                        "capability": str(ref.get("capability")),
                    })
    overrides = payload.get("family_overrides")
    if not isinstance(overrides, dict):
        failures.append({"code": "family-map-overrides-not-object"})
        overrides = {}
    for family_key, override in sorted(overrides.items(), key=lambda kv: str(kv[0])):
        if not isinstance(family_key, str) or not family_key:
            failures.append({"code": "family-map-invalid-override-key", "family_key": str(family_key)})
            continue
        if not isinstance(override, dict):
            failures.append({"code": "family-map-invalid-override", "family_key": family_key})
            continue
        override_capabilities = override.get("capabilities")
        override_unknown = override.get("unknown_reason")
        if override_capabilities is not None and not isinstance(override_capabilities, list):
            failures.append({
                "code": "family-map-invalid-capabilities-type",
                "family_key": family_key,
            })
            override_capabilities = None
        if bool(override_capabilities) == bool(override_unknown):
            failures.append({
                "code": "family-map-override-outcome-required",
                "family_key": family_key,
            })
            continue
        if isinstance(override_capabilities, list):
            if not override_capabilities:
                failures.append({
                    "code": "family-map-override-empty-capabilities",
                    "family_key": family_key,
                })
            for ref in override_capabilities:
                if not isinstance(ref, dict) or not ref.get("profile"):
                    failures.append({
                        "code": "family-map-invalid-capability-ref",
                        "family_key": family_key,
                    })
                    continue
                if ref.get("capability") not in vocabulary:
                    failures.append({
                        "code": "family-map-undefined-capability",
                        "family_key": family_key,
                        "capability": str(ref.get("capability")),
                    })
        if isinstance(override_unknown, str) and not override_unknown:
            failures.append({
                "code": "family-map-empty-unknown-reason",
                "family_key": family_key,
            })
    return failures


def _apply_family_map(
    families: list[dict[str, Any]],
    family_map: dict[str, Any],
    failures: list[dict[str, Any]],
) -> dict[str, Any]:
    """Attach declared-capability refs to each family row (first match wins)."""
    rules = family_map.get("rules") if isinstance(family_map.get("rules"), list) else []
    overrides = (
        family_map.get("family_overrides")
        if isinstance(family_map.get("family_overrides"), dict)
        else {}
    )
    mapped = 0
    unknown = 0
    unknown_reasons: Counter[str] = Counter()
    per_capability: dict[str, dict[str, int]] = {}
    for row in families:
        key = str(row["family_key"])
        override = overrides.get(key)
        outcome: Any = None
        rule_id: Any = None
        if override is not None:
            if not isinstance(override, dict):
                row["capability_state"] = "unknown"
                row["capability_unknown_reason"] = "family-map-invalid-override"
                unknown += 1
                unknown_reasons["family-map-invalid-override"] += 1
                failures.append({
                    "code": "family-map-invalid-override",
                    "family_key": key,
                })
                continue
            outcome = override
            rule_id = f"family-override:{key}"
        else:
            for rule in rules:
                if not isinstance(rule, dict):
                    continue
                match = rule.get("match")
                if not isinstance(match, dict) or match.get("domain") != row["domain"]:
                    continue
                kind = match.get("kind")
                if kind is not None and kind != row["kind"]:
                    continue
                outcome = rule
                rule_id = rule.get("rule_id")
                break
        if outcome is None:
            row["capability_state"] = "unknown"
            row["capability_unknown_reason"] = "family-map-no-rule"
            unknown += 1
            unknown_reasons["family-map-no-rule"] += 1
            failures.append({"code": "family-map-unmatched-family", "family_key": key})
            continue
        capabilities = outcome.get("capabilities")
        if capabilities is not None and not isinstance(capabilities, list):
            row["capability_state"] = "unknown"
            row["capability_unknown_reason"] = "family-map-invalid-capabilities-type"
            unknown += 1
            unknown_reasons["family-map-invalid-capabilities-type"] += 1
            failures.append({
                "code": "family-map-invalid-capabilities-type",
                "family_key": key,
            })
            continue
        if capabilities:
            refs = [
                {
                    "capability": str(ref["capability"]),
                    "profile": str(ref["profile"]),
                    "rule_id": str(rule_id),
                }
                for ref in capabilities
                if isinstance(ref, dict) and ref.get("capability") and ref.get("profile")
            ]
            row["capability_refs"] = refs
            row["capability_state"] = "mapped"
            mapped += 1
            for ref in refs:
                bucket = per_capability.setdefault(
                    ref["capability"],
                    {"family_count": 0, "occurrence_count": 0, "sample_count": 0, "sample_id_set": set()},
                )
                bucket["family_count"] += 1
                bucket["occurrence_count"] += int(row.get("occurrence_count", 0))
                bucket["sample_id_set"].update(str(value) for value in row.get("sample_ids", []))
                bucket["sample_count"] = len(bucket["sample_id_set"])
        else:
            reason = str(outcome.get("unknown_reason") or "family-map-empty-outcome")
            row["capability_state"] = "unknown"
            row["capability_unknown_reason"] = reason
            unknown += 1
            unknown_reasons[reason] += 1
    return {
        "mapped_family_count": mapped,
        "unknown_family_count": unknown,
        "unknown_reason_counts": dict(sorted(unknown_reasons.items())),
        "per_capability": {
            capability: {
                key: value for key, value in sorted(bucket.items())
                if key != "sample_id_set"
            }
            for capability, bucket in sorted(per_capability.items())
        },
    }


def family_map_anchor_failures(
    family_map: dict[str, Any],
    repository_root: Path,
) -> list[dict[str, Any]]:
    """Verify vocabulary authority rows literally exist in their owning docs.

    Report-only: run by verify/tests so ledger prose edits fail verification
    without coupling the deterministic corpus snapshot payload to doc text.
    """
    failures: list[dict[str, Any]] = []
    vocabulary = family_map.get("vocabulary")
    if not isinstance(vocabulary, dict):
        return failures
    doc_cache: dict[str, str] = {}
    root = repository_root.resolve()
    for capability, entry in sorted(vocabulary.items()):
        authority = entry.get("authority") if isinstance(entry, dict) else None
        if not isinstance(authority, dict):
            continue
        doc = str(authority.get("doc") or "")
        row = str(authority.get("row") or "")
        if not doc or not row:
            continue
        text = doc_cache.get(doc)
        if text is None:
            doc_path = (root / doc).resolve()
            try:
                doc_path.relative_to(root)
            except ValueError:
                failures.append({
                    "code": "family-map-anchor-escapes-repository",
                    "capability": capability,
                    "doc": doc,
                })
                text = ""
            else:
                text = doc_path.read_text(encoding="utf-8") if doc_path.is_file() else ""
            doc_cache[doc] = text
        if row not in text:
            failures.append({
                "code": "family-map-anchor-missing",
                "capability": capability,
                "doc": doc,
                "row": row,
            })
    return failures


def load_repair_ledger(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "schema_version": 1,
            "status_contract": REPAIR_STATUS_CONTRACT,
            "families": [],
        }
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ValueError("repair ledger schema must be 1")
    if not isinstance(payload.get("families"), list):
        raise ValueError("repair ledger families must be an array")
    if "status_contract" not in payload:
        payload["status_contract"] = REPAIR_STATUS_CONTRACT
    return payload


def validate_repair_ledger(
    ledger: dict[str, Any],
    observed_family_keys: set[str],
) -> list[dict[str, Any]]:
    failures: list[dict[str, Any]] = []
    status_contract = {field: set(values) for field, values in REPAIR_STATUS_CONTRACT.items()}
    declared_contract = ledger.get("status_contract")
    for field, allowed in status_contract.items():
        declared = declared_contract.get(field) if isinstance(declared_contract, dict) else None
        if not isinstance(declared, list) or set(declared) != allowed or len(declared) != len(allowed):
            failures.append({"code": "repair-status-contract-invalid", "field": field})
    seen: set[str] = set()
    for index, item in enumerate(ledger.get("families", [])):
        if not isinstance(item, dict):
            failures.append({"code": "repair-entry-not-object", "index": index})
            continue
        key = item.get("family_key")
        if not isinstance(key, str):
            failures.append({"code": "repair-family-key-missing", "index": index})
            continue
        if key in seen:
            failures.append({"code": "duplicate-repair-family", "family_key": key})
        seen.add(key)
        item["corpus_observation_state"] = (
            "observed" if key in observed_family_keys else "historical-not-currently-observed"
        )
        repair_state = item.get("repair_state")
        runtime_state = item.get("runtime_proof_state")
        regression_state = item.get("regression_protection_state")
        gates = item.get("regression_gates")
        events = item.get("events")
        for field, allowed in status_contract.items():
            if item.get(field) not in allowed:
                failures.append({
                    "code": "repair-state-invalid",
                    "family_key": key,
                    "field": field,
                    "value": item.get(field),
                })
        if repair_state == "bounded-verified":
            if runtime_state not in {"visible-chain-closed", "official-golden-equivalent"}:
                failures.append({"code": "verified-repair-lacks-visible-proof", "family_key": key})
            if regression_state not in {"targeted-runtime", "milestone"}:
                failures.append({
                    "code": "verified-repair-lacks-targeted-regression-protection",
                    "family_key": key,
                })
            required_gate_kinds = {
                "synthetic-positive", "synthetic-negative", "targeted-runtime",
            }
            gate_kinds = {
                gate.get("kind")
                for gate in gates or []
                if isinstance(gate, dict)
                and isinstance(gate.get("kind"), str)
                and isinstance(gate.get("reference"), str)
                and gate["reference"].strip()
            } if isinstance(gates, list) else set()
            if not required_gate_kinds.issubset(gate_kinds):
                failures.append({
                    "code": "verified-repair-lacks-regression-gates",
                    "family_key": key,
                    "missing_kinds": sorted(required_gate_kinds - gate_kinds),
                })
            if not isinstance(events, list) or not events:
                failures.append({"code": "verified-repair-lacks-event", "family_key": key})
            else:
                required_event_fields = {"date", "state", "commit", "evidence_refs", "notes"}
                for event_index, event in enumerate(events):
                    valid_event = (
                        isinstance(event, dict)
                        and not required_event_fields.difference(event)
                        and event.get("state") in status_contract["repair_state"]
                        and isinstance(event.get("evidence_refs"), list)
                        and bool(event["evidence_refs"])
                        and all(
                            isinstance(event.get(field), str) and event[field].strip()
                            for field in ("date", "commit", "notes")
                        )
                        and all(
                            isinstance(reference, str) and reference.strip()
                            for reference in event["evidence_refs"]
                        )
                    )
                    if not valid_event:
                        failures.append({
                            "code": "verified-repair-event-invalid",
                            "family_key": key,
                            "event_index": event_index,
                        })
            required = {
                "root_cause", "public_fix", "commit", "targeted_samples",
                "roi_evidence", "remaining_boundaries",
            }
            missing = sorted(field for field in required if not item.get(field))
            if missing:
                failures.append({
                    "code": "verified-repair-missing-fields",
                    "family_key": key,
                    "fields": missing,
                })
            for field in ("targeted_samples", "roi_evidence", "remaining_boundaries"):
                values = item.get(field)
                if not isinstance(values, list) or not values or not all(
                    isinstance(value, str) and value.strip() for value in values
                ):
                    failures.append({
                        "code": "verified-repair-field-invalid",
                        "family_key": key,
                        "field": field,
                    })
            for field in ("root_cause", "public_fix", "commit"):
                if not isinstance(item.get(field), str) or not item[field].strip():
                    failures.append({
                        "code": "verified-repair-field-invalid",
                        "family_key": key,
                        "field": field,
                    })
        if runtime_state == "official-golden-equivalent" and not item.get("official_golden_refs"):
            failures.append({"code": "official-equivalence-lacks-golden", "family_key": key})
        if runtime_state == "official-golden-equivalent":
            for field in ("official_phase_identity", "pixel_tolerance", "timing_tolerance"):
                if not item.get(field):
                    failures.append({
                        "code": "official-equivalence-missing-contract",
                        "family_key": key,
                        "field": field,
                    })
    return failures


def validate_repair_references(
    ledger: Any,
    known_sample_ids: set[str],
    repository_root: Path,
) -> list[dict[str, Any]]:
    """Referential integrity for the repair ledger.

    Field and enum shape is `validate_repair_ledger`'s job. This gate answers a
    different question: do the recorded references still exist? A sentinel that
    names a deleted test, an unknown sample or a moved document claims
    regression protection that no longer exists, so it must fail closed.

    Repository-external references (typically /private/tmp run artefacts) are
    transient by artifact governance and are not failures. Commit identifiers are
    only shape-checked here so the census stays reproducible without depending on
    local history; resolving them belongs to an explicit audit.

    This is a validator: malformed containers must produce failure records, never
    exceptions, so every access below goes through a shape guard.
    """
    failures: list[dict[str, Any]] = []
    repository_root = repository_root.resolve()
    if not isinstance(ledger, dict):
        return [{"code": "repair-ledger-not-object", "value": repr(ledger)[:80]}]

    def entries(value: Any) -> list[Any]:
        return value if isinstance(value, list) else []

    def fields(value: Any) -> dict[str, Any]:
        return value if isinstance(value, dict) else {}

    entry_contract = ledger.get("entry_contract")
    declared_kinds = (
        entry_contract.get("regression_gate_kinds")
        if isinstance(entry_contract, dict) else None
    )
    allowed_kinds = set(
        declared_kinds if isinstance(declared_kinds, list)
        and all(isinstance(kind, str) for kind in declared_kinds)
        else DEFAULT_REGRESSION_GATE_KINDS
    )
    cache: dict[Path, str | None] = {}

    def repository_text(path: Path) -> str | None:
        if path not in cache:
            try:
                cache[path] = (
                    path.read_text(encoding="utf-8", errors="replace")
                    if path.is_file() else None
                )
            except OSError:
                cache[path] = None
        return cache[path]

    def inside_repository(path_part: str) -> Path | None:
        """Resolve a repository-relative reference, or None when it escapes."""
        if not path_part:
            return None
        target = Path(path_part)
        try:
            target = (
                target.resolve() if target.is_absolute()
                else (repository_root / target).resolve()
            )
        except (OSError, RuntimeError, ValueError):
            return None
        return target if target.is_relative_to(repository_root) else None

    for index, item in enumerate(entries(ledger.get("families"))):
        if not isinstance(item, dict):
            continue
        key = item.get("family_key")
        family_label = key if isinstance(key, str) else f"#{index}"

        for sample in entries(item.get("targeted_samples")):
            if isinstance(sample, str) and sample not in known_sample_ids:
                failures.append({
                    "code": "repair-sample-reference-unknown",
                    "family_key": family_label,
                    "sample_id": sample,
                })

        for gate in entries(item.get("regression_gates")):
            gate = fields(gate)
            kind = gate.get("kind")
            reference = gate.get("reference")
            if not isinstance(reference, str) or not reference.strip():
                continue
            if not isinstance(kind, str) or kind not in allowed_kinds:
                failures.append({
                    "code": "repair-gate-kind-unknown",
                    "family_key": family_label,
                    "kind": kind if isinstance(kind, str) else repr(kind)[:40],
                })
                continue
            if kind == "targeted-runtime":
                continue
            path_part, _, symbol = reference.partition("#")
            target = inside_repository(path_part)
            if target is None:
                failures.append({
                    "code": "repair-gate-reference-outside-repository",
                    "family_key": family_label,
                    "reference": reference,
                })
                continue
            text = repository_text(target)
            if text is None:
                failures.append({
                    "code": "repair-gate-file-missing",
                    "family_key": family_label,
                    "reference": reference,
                })
                continue
            name = symbol.split()[0] if symbol.strip() else ""
            if name and not _symbol_present(name, text):
                failures.append({
                    "code": "repair-gate-symbol-missing",
                    "family_key": family_label,
                    "reference": reference,
                })

        evidence_groups = [("roi_evidence", entries(item.get("roi_evidence")))]
        events = entries(item.get("events"))
        for event_index, event in enumerate(events):
            evidence_groups.append((
                f"events[{event_index}].evidence_refs",
                entries(fields(event).get("evidence_refs")),
            ))
        for field, references in evidence_groups:
            for reference in references:
                if not isinstance(reference, str):
                    continue
                path_part = reference.split("#")[0].split(" ")[0]
                if path_part.startswith("/"):
                    continue
                target = inside_repository(path_part)
                if target is None:
                    failures.append({
                        "code": "repair-evidence-reference-outside-repository",
                        "family_key": family_label,
                        "field": field,
                        "reference": reference,
                    })
                elif target.is_relative_to(repository_root / ".artifacts/scene-evidence") or target.is_relative_to(repository_root / ".codex"):
                    # Local evidence caches are intentionally not shipped in Git.
                    # Executable regression gates above remain mandatory.
                    continue
                elif not target.exists():
                    failures.append({
                        "code": "repair-evidence-file-missing",
                        "family_key": family_label,
                        "field": field,
                        "reference": reference,
                    })

        commits = [item.get("commit")]
        commits.extend(fields(event).get("commit") for event in events)
        for commit in commits:
            if commit == REPAIR_COMMIT_PLACEHOLDER:
                continue
            if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{7,40}", commit):
                failures.append({
                    "code": "repair-commit-shape-invalid",
                    "family_key": family_label,
                    "commit": commit if isinstance(commit, str) else repr(commit)[:40],
                })
    return failures


def _symbol_present(name: str, text: str) -> bool:
    """The referenced symbol must appear as a whole identifier.

    Recorded gate symbols are of two kinds: Python test method names and Swift
    harness function names embedded in the test files' raw harness strings. A
    whole-word match covers both while rejecting a symbol that survives only as
    a fragment of a longer identifier.
    """
    return re.search(
        rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", text
    ) is not None
