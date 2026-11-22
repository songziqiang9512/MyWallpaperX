"""Parse effect-stage admission and compile-outcome conservation."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any
from urllib.parse import unquote


EFFECT_STAGE_DESCRIPTOR_COUNT_RE = re.compile(
    r"^effectStageDescriptorCount: (?P<count>\d+)$",
    re.MULTILINE,
)

EFFECT_STAGE_PARSED_COUNT_RE = re.compile(
    r"^effectStageParsedCount: (?P<count>\d+)$",
    re.MULTILINE,
)

EFFECT_STAGE_ACTIVITY_COUNTS_RE = re.compile(
    r"^effectStageActivityCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_STAGE_ADMISSION_COUNTS_RE = re.compile(
    r"^effectStageAdmissionCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_STAGE_COVERAGE_COUNTS_RE = re.compile(
    r"^effectStageCoverageCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_STAGE_CONSERVATION_RE = re.compile(
    r"^effectStage(?P<name>DescriptorIdentity|Activity|InactiveAdmission|"
    r"ActiveAdmission|ExecutionIdentity)Conserved: (?P<value>true|false)$",
    re.MULTILINE,
)

EFFECT_STAGE_ADMISSION_RE = re.compile(
    r"^effectStageAdmission: layer=(?P<layer>\d+) "
    r"effect=(?P<effect>\d+) descriptor=(?P<descriptor>\S+) "
    r"activity=(?P<activity>\S+) admission=(?P<admission>\S+) "
    r"coverage=(?P<coverage>\S+) backend=(?P<backend>\S+) "
    r"profile=(?P<profile>\S+) reason=(?P<reason>\S+) path=(?P<path>\S+)$",
    re.MULTILINE,
)

EFFECT_STAGE_COMPILE_FAILURE_COUNT_RE = re.compile(
    r"^effectStageCompileFailureCount: (?P<count>\d+)$",
    re.MULTILINE,
)

EFFECT_STAGE_COMPILE_FAILURE_CODES_RE = re.compile(
    r"^effectStageCompileFailureCodes: ?(?P<counts>[^\r\n]*)$",
    re.MULTILINE,
)

EFFECT_STAGE_COMPILER_PROBE_OUTCOMES_RE = re.compile(
    r"^effectStageCompilerProbeOutcomeCounts: ?(?P<counts>[^\r\n]*)$",
    re.MULTILINE,
)

EFFECT_STAGE_COMPILER_FAILURE_CODES_RE = re.compile(
    r"^effectStageCompilerFailureCodes: ?(?P<counts>[^\r\n]*)$",
    re.MULTILINE,
)

def _stage_count_map(
    raw: str,
    expected_keys: tuple[str, ...],
) -> dict[str, int] | None:
    result: dict[str, int] = {}
    for item in raw.split(","):
        key, separator, value = item.partition("=")
        if not separator or key in result or not value.isdigit():
            return None
        result[key] = int(value)
    return result if set(result) == set(expected_keys) else None

def effect_stage_admission_metrics(preview_text: str) -> dict[str, Any]:
    activity_keys = (
        "author-disabled",
        "property-inactive",
        "layer-hidden",
        "active",
    )
    admission_keys = (
        "inactive",
        "admitted-dedicated",
        "admitted-fallback",
        "admitted-generic",
        "admitted-passthrough",
        "not-admitted",
    )
    coverage_keys = (
        "inactive", "complete", "rejected-missing-graph",
        "rejected-ambiguous-graph", "rejected-graph-mismatch",
        "rejected-capability",
    )
    descriptor_match = EFFECT_STAGE_DESCRIPTOR_COUNT_RE.search(preview_text)
    parsed_match = EFFECT_STAGE_PARSED_COUNT_RE.search(preview_text)
    activity_match = EFFECT_STAGE_ACTIVITY_COUNTS_RE.search(preview_text)
    admission_match = EFFECT_STAGE_ADMISSION_COUNTS_RE.search(preview_text)
    coverage_match = EFFECT_STAGE_COVERAGE_COUNTS_RE.search(preview_text)
    conservation = {
        match.group("name"): match.group("value") == "true"
        for match in EFFECT_STAGE_CONSERVATION_RE.finditer(preview_text)
    }
    records = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "descriptor_id": unquote(match.group("descriptor")),
            "definition_path": unquote(match.group("path")),
            "activity": match.group("activity"),
            "admission": match.group("admission"),
            "coverage": match.group("coverage"),
            "backend": None if match.group("backend") == "-" else match.group("backend"),
            "profile": None if match.group("profile") == "-" else match.group("profile"),
            "reason": None if match.group("reason") == "-" else match.group("reason"),
        }
        for match in EFFECT_STAGE_ADMISSION_RE.finditer(preview_text)
    ]
    has_evidence = any((
        descriptor_match,
        parsed_match,
        activity_match,
        admission_match,
        coverage_match,
        conservation,
        records,
    ))
    if not has_evidence:
        return {
            "has_evidence": False,
            "schema_version": None,
            "route_scope": None,
            "descriptor_count": None,
            "parsed_count": None,
            "activity_counts": None,
            "admission_counts": None,
            "coverage_counts": None,
            "conservation": {},
            "records": [],
            "canonical_sha256": None,
            "validation_failures": [],
        }

    descriptor_count = int(descriptor_match.group("count")) if descriptor_match else None
    parsed_count = int(parsed_match.group("count")) if parsed_match else None
    activity_counts = (
        _stage_count_map(activity_match.group("counts"), activity_keys)
        if activity_match else None
    )
    admission_counts = (
        _stage_count_map(admission_match.group("counts"), admission_keys)
        if admission_match else None
    )
    coverage_counts = (
        _stage_count_map(coverage_match.group("counts"), coverage_keys)
        if coverage_match else None
    )
    records.sort(key=lambda item: (
        item["layer_id"],
        item["effect_index"],
        item["descriptor_id"],
    ))
    computed_activity = {
        key: sum(record["activity"] == key for record in records)
        for key in activity_keys
    }
    computed_admission = {
        key: sum(record["admission"] == key for record in records)
        for key in admission_keys
    }
    computed_coverage = {
        key: sum(record["coverage"] == key for record in records)
        for key in coverage_keys
    }
    failures: list[str] = []
    if None in (descriptor_count, parsed_count, activity_counts, admission_counts, coverage_counts):
        failures.append("effect stage admission summary missing or malformed")
    if descriptor_count != len(records) or parsed_count != len(records):
        failures.append("effect stage admission record count mismatch")
    identities = [
        (record["layer_id"], record["effect_index"], record["descriptor_id"])
        for record in records
    ]
    if len(identities) != len(set(identities)):
        failures.append("effect stage admission identity duplicated")
    if activity_counts != computed_activity:
        failures.append("effect stage admission activity counts mismatch")
    if admission_counts != computed_admission:
        failures.append("effect stage admission counts mismatch")
    if coverage_counts != computed_coverage:
        failures.append("effect stage coverage counts mismatch")
    if activity_counts is not None and sum(activity_counts.values()) != len(records):
        failures.append("effect stage activity total mismatch")
    if admission_counts is not None and sum(admission_counts.values()) != len(records):
        failures.append("effect stage admission total mismatch")
    if coverage_counts is not None and sum(coverage_counts.values()) != len(records):
        failures.append("effect stage coverage total mismatch")
    expected_conservation = {
        "DescriptorIdentity",
        "Activity",
        "InactiveAdmission",
        "ActiveAdmission",
        "ExecutionIdentity",
    }
    if set(conservation) != expected_conservation or not all(conservation.values()):
        failures.append("effect stage admission Swift conservation failed")
    accepted_coverages = {"complete"}
    omitted_or_rejected_coverages = {"rejected-capability"}
    structural_rejection_coverages = {
        "rejected-missing-graph",
        "rejected-ambiguous-graph",
        "rejected-graph-mismatch",
    }
    for record in records:
        route_participating = record["activity"] in {
            "active",
            "property-inactive",
        }
        admission_inactive = record["admission"] == "inactive"
        admitted = record["admission"] in {
            "admitted-dedicated",
            "admitted-fallback",
            "admitted-generic",
            "admitted-passthrough",
        }
        if route_participating == admission_inactive:
            failures.append("effect stage activity and admission conflict")
            break
        if admitted and record["backend"] is None:
            failures.append("effect stage admitted backend missing")
            break
        if admitted and record["reason"] is not None:
            failures.append("effect stage admitted record has rejection reason")
            break
        if record["admission"] == "admitted-generic" and (
            record["backend"] != "resolved-material"
            or record["profile"] != "program"
        ):
            failures.append("effect stage generic owner invalid")
            break
        if record["admission"] == "admitted-fallback" and (
            record["backend"] != "visual-failure-passthrough"
            or record["profile"] != "effect-local-passthrough"
        ):
            failures.append("effect stage fallback owner invalid")
            break
        if record["admission"] == "admitted-passthrough" and (
            record["activity"] != "property-inactive"
            or record["backend"] != "initially-inactive-passthrough"
            or record["profile"] != "inactive-passthrough"
        ):
            failures.append("effect stage passthrough owner invalid")
            break
        if route_participating and not admitted and record["reason"] is None:
            failures.append("effect stage non-admitted reason missing")
            break
        if not route_participating and (
            not admission_inactive
            or record["coverage"] != "inactive"
            or record["backend"] is not None
            or record["profile"] is not None
            or record["reason"] is not None
        ):
            failures.append("effect stage inactive state combination invalid")
            break
        if admitted and (
            record["coverage"] not in accepted_coverages
            or (record["admission"] == "admitted-dedicated"
                and record["profile"] is not None)
            or (record["admission"] == "admitted-fallback"
                and record["profile"] != "effect-local-passthrough")
            or (record["admission"] == "admitted-generic"
                and record["profile"] is None)
            or (record["admission"] == "admitted-passthrough"
                and record["profile"] != "inactive-passthrough")
        ):
            failures.append("effect stage admitted state combination invalid")
            break
        if route_participating and not admitted and (
            record["admission"] != "not-admitted"
            or record["coverage"] not in (
                omitted_or_rejected_coverages | structural_rejection_coverages
            )
            or record["backend"] is not None
            or record["profile"] is not None
        ):
            failures.append("effect stage non-admitted state combination invalid")
            break
        if record["coverage"] in structural_rejection_coverages:
            failures.append(
                "effect stage admission structural rejection: "
                + record["coverage"]
            )
            break
    canonical_sha256 = hashlib.sha256(json.dumps(
        records,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "has_evidence": True,
        "schema_version": 1,
        "descriptor_count": descriptor_count,
        "parsed_count": parsed_count,
        "activity_counts": activity_counts,
        "admission_counts": admission_counts,
        "coverage_counts": coverage_counts,
        "conservation": conservation,
        "records": records,
        "canonical_sha256": canonical_sha256,
        "validation_failures": failures,
    }

def _stage_compile_count_map(
    raw: str,
    *,
    key_pattern: re.Pattern[str],
    maximum_entries: int,
    allowed_keys: set[str] | None = None,
) -> dict[str, int] | None:
    raw = raw.strip()
    if len(raw) > 32 * 1024:
        return None
    if not raw:
        return {}
    items = raw.split(",")
    if len(items) > maximum_entries:
        return None
    result: dict[str, int] = {}
    for item in items:
        key, separator, value = item.partition("=")
        if (
            not separator
            or key in result
            or len(key) > 128
            or key_pattern.fullmatch(key) is None
            or not value.isdigit()
            or (allowed_keys is not None and key not in allowed_keys)
        ):
            return None
        result[key] = int(value)
    return result

def authored_effect_stage_compile_metrics(preview_text: str) -> dict[str, Any]:
    line_specs = (
        (
            "effectStageCompileFailureCount:",
            EFFECT_STAGE_COMPILE_FAILURE_COUNT_RE,
        ),
        (
            "effectStageCompileFailureCodes:",
            EFFECT_STAGE_COMPILE_FAILURE_CODES_RE,
        ),
        (
            "effectStageCompilerProbeOutcomeCounts:",
            EFFECT_STAGE_COMPILER_PROBE_OUTCOMES_RE,
        ),
        (
            "effectStageCompilerFailureCodes:",
            EFFECT_STAGE_COMPILER_FAILURE_CODES_RE,
        ),
    )
    if not any(prefix in preview_text for prefix, _ in line_specs):
        return {
            "has_evidence": False,
            "schema_version": None,
            "stage_failure_count": None,
            "stage_failure_code_counts": {},
            "compiler_probe_outcome_counts": {},
            "compiler_failure_code_counts": {},
            "canonical_sha256": None,
            "validation_failures": [],
        }

    matches = {
        prefix: list(pattern.finditer(preview_text))
        for prefix, pattern in line_specs
    }
    failures: list[str] = []
    if any(len(values) != 1 for values in matches.values()):
        failures.append(
            "effect stage compile summary missing, duplicated, or malformed"
        )

    count_matches = matches["effectStageCompileFailureCount:"]
    stage_failure_count = (
        int(count_matches[0].group("count"))
        if len(count_matches) == 1
        else None
    )

    token_pattern = re.compile(r"[a-z0-9-]+")
    compiler_failure_pattern = re.compile(
        r"[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+"
    )

    def parsed_map(
        prefix: str,
        *,
        key_pattern: re.Pattern[str],
        maximum_entries: int,
        allowed_keys: set[str] | None = None,
    ) -> dict[str, int] | None:
        values = matches[prefix]
        if len(values) != 1:
            return None
        return _stage_compile_count_map(
            values[0].group("counts"),
            key_pattern=key_pattern,
            maximum_entries=maximum_entries,
            allowed_keys=allowed_keys,
        )

    stage_failure_codes = parsed_map(
        "effectStageCompileFailureCodes:",
        key_pattern=token_pattern,
        maximum_entries=2,
        allowed_keys={"no-backend-accepted", "stage-program-invariant"},
    )
    probe_outcomes = parsed_map(
        "effectStageCompilerProbeOutcomeCounts:",
        key_pattern=token_pattern,
        maximum_entries=2,
        allowed_keys={"not-applicable", "rejected"},
    )
    compiler_failure_codes = parsed_map(
        "effectStageCompilerFailureCodes:",
        key_pattern=compiler_failure_pattern,
        maximum_entries=256,
    )
    for name, value in (
        ("failure code", stage_failure_codes),
        ("probe outcome", probe_outcomes),
        ("compiler failure code", compiler_failure_codes),
    ):
        if value is None:
            failures.append(f"effect stage compile {name} counts malformed")

    normalized_stage_codes = stage_failure_codes or {}
    normalized_probe_outcomes = {
        key: (probe_outcomes or {}).get(key, 0)
        for key in ("not-applicable", "rejected")
    }
    normalized_compiler_codes = compiler_failure_codes or {}
    if stage_failure_count is not None and stage_failure_codes is not None:
        if sum(stage_failure_codes.values()) != stage_failure_count:
            failures.append("effect stage compile failure count mismatch")
    if probe_outcomes is not None and compiler_failure_codes is not None:
        if (
            sum(compiler_failure_codes.values())
            != normalized_probe_outcomes["rejected"]
        ):
            failures.append("effect stage compiler rejection count mismatch")
    if stage_failure_count is not None and probe_outcomes is not None:
        if sum(probe_outcomes.values()) > stage_failure_count * 34:
            failures.append("effect stage compiler probe count exceeds bound")

    canonical_payload = {
        "stage_failure_count": stage_failure_count,
        "stage_failure_code_counts": normalized_stage_codes,
        "compiler_probe_outcome_counts": normalized_probe_outcomes,
        "compiler_failure_code_counts": normalized_compiler_codes,
    }
    canonical_sha256 = hashlib.sha256(json.dumps(
        canonical_payload,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "has_evidence": True,
        "schema_version": 1,
        **canonical_payload,
        "canonical_sha256": canonical_sha256,
        "validation_failures": failures,
    }

def effect_stage_admission_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
    require_evidence: bool = False,
) -> list[str]:
    if not metrics["has_evidence"]:
        return ["effect stage admission evidence missing"] if require_evidence else []
    return list(metrics["validation_failures"])
