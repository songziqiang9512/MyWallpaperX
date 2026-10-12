"""Parse the single static effect runtime ownership catalog."""

from __future__ import annotations

import hashlib
import json
import re
from scene_wallpaper_effect_preparation import _stage_count_map, effect_stage_admission_metrics
from typing import Any
from urllib.parse import unquote


EFFECT_RUNTIME_DISPOSITION_SCHEMA_RE = re.compile(
    r"^effectStageRuntimeDispositionSchema: (?P<version>\d+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_ROUTE_SCOPE_RE = re.compile(
    r"^effectStageRuntimeRouteScope: (?P<scope>\S+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_COUNT_RE = re.compile(
    r"^effectStageRuntimeDispositionCount: (?P<count>\d+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_KIND_COUNTS_RE = re.compile(
    r"^effectStageRuntimeDispositionKindCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_ATTRIBUTION_COUNTS_RE = re.compile(
    r"^effectStageRuntimeDispositionAttributionCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_ROLE_COUNTS_RE = re.compile(
    r"^effectStageRuntimeDispositionRoleCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_ROUTE_GROUP_COUNT_RE = re.compile(
    r"^effectStaticRouteGroupCount: (?P<count>\d+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_ROUTE_GROUP_KIND_COUNTS_RE = re.compile(
    r"^effectStaticRouteGroupKindCounts: (?P<counts>[^\r\n]+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_CONSERVATION_RE = re.compile(
    r"^effectStageRuntime(?P<name>DescriptorIdentity|GroupIdentity|"
    r"AdmissionIdentity|ResolvedMaterialOwnership)Conserved: "
    r"(?P<value>true|false)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_ROUTE_GROUP_RE = re.compile(
    r"^effectStaticRouteGroup: layer=(?P<layer>\d+) scope=(?P<scope>\S+) "
    r"kind=(?P<kind>\S+) "
    r"effects=(?P<effects>\d+) owners=(?P<owners>\d+) "
    r"reason=(?P<reason>\S+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_DISPOSITION_RE = re.compile(
    r"^effectStageRuntimeDisposition: layer=(?P<layer>\d+) "
    r"effect=(?P<effect>\d+) descriptor=(?P<descriptor>\S+) "
    r"kind=(?P<kind>\S+) attribution=(?P<attribution>\S+) "
    r"family=(?P<family>\S+) group=(?P<group>-|\d+) "
    r"role=(?P<role>\S+) reason=(?P<reason>\S+) path=(?P<path>\S+)$",
    re.MULTILINE,
)

EFFECT_RUNTIME_EVIDENCE_PREFIX_RE = re.compile(
    r"^effect(?:StageRuntime|StaticRouteGroup)",
    re.MULTILINE,
)

def effect_runtime_disposition_metrics(
    preview_text: str,
    stage_admission: dict[str, Any] | None = None,
) -> dict[str, Any]:
    kind_keys = (
        "inactive",
        "dedicated",
        "fallback",
        "passthrough",
        "program",
        "unsupported",
        "unattributed",
    )
    attribution_keys = ("exact-key", "none")
    role_keys = ("owner", "member", "none")
    group_kind_keys = ("inactive", "direct", "resolved")
    if EFFECT_RUNTIME_EVIDENCE_PREFIX_RE.search(preview_text) is None:
        return {
            "has_evidence": False,
            "schema_version": None,
            "record_count": None,
            "group_count": None,
            "kind_counts": None,
            "attribution_counts": None,
            "role_counts": None,
            "group_kind_counts": None,
            "conservation": {},
            "groups": [],
            "records": [],
            "canonical_sha256": None,
            "validation_failures": [],
        }

    schema_matches = list(
        EFFECT_RUNTIME_DISPOSITION_SCHEMA_RE.finditer(preview_text)
    )
    route_scope_matches = list(
        EFFECT_RUNTIME_ROUTE_SCOPE_RE.finditer(preview_text)
    )
    record_count_matches = list(
        EFFECT_RUNTIME_DISPOSITION_COUNT_RE.finditer(preview_text)
    )
    kind_count_matches = list(
        EFFECT_RUNTIME_DISPOSITION_KIND_COUNTS_RE.finditer(preview_text)
    )
    attribution_count_matches = list(
        EFFECT_RUNTIME_DISPOSITION_ATTRIBUTION_COUNTS_RE.finditer(preview_text)
    )
    role_count_matches = list(
        EFFECT_RUNTIME_DISPOSITION_ROLE_COUNTS_RE.finditer(preview_text)
    )
    group_count_matches = list(
        EFFECT_RUNTIME_ROUTE_GROUP_COUNT_RE.finditer(preview_text)
    )
    group_kind_count_matches = list(
        EFFECT_RUNTIME_ROUTE_GROUP_KIND_COUNTS_RE.finditer(preview_text)
    )
    schema_version = (
        int(schema_matches[0].group("version"))
        if len(schema_matches) == 1 else None
    )
    route_scope = (
        route_scope_matches[0].group("scope")
        if len(route_scope_matches) == 1 else None
    )
    record_count = (
        int(record_count_matches[0].group("count"))
        if len(record_count_matches) == 1 else None
    )
    group_count = (
        int(group_count_matches[0].group("count"))
        if len(group_count_matches) == 1 else None
    )
    kind_counts = (
        _stage_count_map(kind_count_matches[0].group("counts"), kind_keys)
        if len(kind_count_matches) == 1 else None
    )
    attribution_counts = (
        _stage_count_map(
            attribution_count_matches[0].group("counts"),
            attribution_keys,
        )
        if len(attribution_count_matches) == 1 else None
    )
    role_counts = (
        _stage_count_map(role_count_matches[0].group("counts"), role_keys)
        if len(role_count_matches) == 1 else None
    )
    group_kind_counts = (
        _stage_count_map(
            group_kind_count_matches[0].group("counts"),
            group_kind_keys,
        )
        if len(group_kind_count_matches) == 1 else None
    )
    conservation_matches = list(
        EFFECT_RUNTIME_DISPOSITION_CONSERVATION_RE.finditer(preview_text)
    )
    conservation = {
        match.group("name"): match.group("value") == "true"
        for match in conservation_matches
    }
    groups = [
        {
            "layer_id": int(match.group("layer")),
            "scope": match.group("scope"),
            "kind": match.group("kind"),
            "effect_count": int(match.group("effects")),
            "owner_count": int(match.group("owners")),
            "reason": (
                None if match.group("reason") == "-"
                else match.group("reason")
            ),
        }
        for match in EFFECT_RUNTIME_ROUTE_GROUP_RE.finditer(preview_text)
    ]
    records = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "descriptor_id": unquote(match.group("descriptor")),
            "definition_path": unquote(match.group("path")),
            "kind": match.group("kind"),
            "attribution": match.group("attribution"),
            "family": (
                None if match.group("family") == "-" else match.group("family")
            ),
            "group_id": (
                None if match.group("group") == "-"
                else int(match.group("group"))
            ),
            "role": match.group("role"),
            "reason": (
                None if match.group("reason") == "-"
                else match.group("reason")
            ),
        }
        for match in EFFECT_RUNTIME_DISPOSITION_RE.finditer(preview_text)
    ]
    groups.sort(key=lambda item: item["layer_id"])
    records.sort(key=lambda item: (
        item["layer_id"],
        item["effect_index"],
        item["descriptor_id"],
    ))

    failures: list[str] = []
    summary_matches = (
        schema_matches,
        route_scope_matches,
        record_count_matches,
        kind_count_matches,
        attribution_count_matches,
        role_count_matches,
        group_count_matches,
        group_kind_count_matches,
    )
    if any(len(matches) != 1 for matches in summary_matches) or any(
        value is None for value in (
            schema_version,
            route_scope,
            record_count,
            group_count,
            kind_counts,
            attribution_counts,
            role_counts,
            group_kind_counts,
        )
    ):
        failures.append("effect runtime disposition summary missing or malformed")
    if schema_version != 1:
        failures.append("effect runtime disposition schema unsupported")
    if route_scope != "unified-effect-graph":
        failures.append("effect runtime disposition route scope invalid")
    if record_count != len(records):
        failures.append("effect runtime disposition record count mismatch")
    if group_count != len(groups):
        failures.append("effect runtime disposition group count mismatch")

    record_identities = [
        (record["layer_id"], record["effect_index"], record["descriptor_id"])
        for record in records
    ]
    if len(record_identities) != len(set(record_identities)):
        failures.append("effect runtime disposition identity duplicated")
    group_layers = [group["layer_id"] for group in groups]
    if len(group_layers) != len(set(group_layers)):
        failures.append("effect runtime disposition route group layer duplicated")

    computed_kind_counts = {
        key: sum(record["kind"] == key for record in records)
        for key in kind_keys
    }
    computed_attribution_counts = {
        key: sum(record["attribution"] == key for record in records)
        for key in attribution_keys
    }
    computed_role_counts = {
        key: sum(record["role"] == key for record in records)
        for key in role_keys
    }
    computed_group_kind_counts = {
        key: sum(group["kind"] == key for group in groups)
        for key in group_kind_keys
    }
    if kind_counts != computed_kind_counts:
        failures.append("effect runtime disposition kind counts mismatch")
    if attribution_counts != computed_attribution_counts:
        failures.append("effect runtime disposition attribution counts mismatch")
    if role_counts != computed_role_counts:
        failures.append("effect runtime disposition role counts mismatch")
    if group_kind_counts != computed_group_kind_counts:
        failures.append("effect runtime disposition group kind counts mismatch")
    for label, counts, total in (
        ("kind", kind_counts, len(records)),
        ("attribution", attribution_counts, len(records)),
        ("role", role_counts, len(records)),
        ("group kind", group_kind_counts, len(groups)),
    ):
        if counts is not None and sum(counts.values()) != total:
            failures.append(f"effect runtime disposition {label} total mismatch")

    expected_conservation = {
        "DescriptorIdentity",
        "GroupIdentity",
        "AdmissionIdentity",
        "ResolvedMaterialOwnership",
    }
    if (
        len(conservation_matches) != len(expected_conservation)
        or set(conservation) != expected_conservation
        or not all(conservation.values())
    ):
        failures.append("effect runtime disposition Swift conservation failed")

    groups_by_layer = {
        group["layer_id"]: group
        for group in groups
    } if len(group_layers) == len(set(group_layers)) else {}
    for record in records:
        group_id = record["group_id"]
        if group_id is not None and (
            group_id != record["layer_id"] or group_id not in groups_by_layer
        ):
            failures.append("effect runtime disposition group reference invalid")
            break
    for group in groups:
        if group["scope"] != "unified-effect-graph":
            failures.append("effect runtime disposition group scope invalid")
        referenced = [
            record for record in records
            if record["group_id"] == group["layer_id"]
        ]
        owners = sum(record["role"] == "owner" for record in referenced)
        if group["effect_count"] != len(referenced):
            failures.append("effect runtime disposition group membership count mismatch")
        if group["owner_count"] != owners:
            failures.append("effect runtime disposition group owner count mismatch")
        kinds = {record["kind"] for record in referenced}
        if group["kind"] == "inactive":
            if referenced or group["effect_count"] != 0 or group["owner_count"] != 0:
                failures.append("effect runtime disposition inactive group invalid")
        elif not referenced:
            failures.append("effect runtime disposition active group is empty")
        all_passthrough = bool(referenced) and all(
            record["kind"] == "passthrough" for record in referenced
        )
        if group["kind"] == "resolved" and (
            (group["owner_count"] < 1 and not all_passthrough)
            or not kinds.issubset({
                "dedicated",
                "fallback",
                "passthrough",
                "program",
                "unattributed",
            })
        ):
            failures.append("effect runtime disposition resolved group invalid")
        if group["kind"] == "direct" and (
            group["owner_count"] != 0
            or not kinds.issubset({"unsupported", "unattributed"})
            or group["reason"] not in {
                "r5-no-runtime-owner",
            }
        ):
            failures.append("effect runtime disposition direct group invalid")

    state_contracts: dict[str, tuple[str, set[str], str, str]] = {
        "inactive": ("none", {"none"}, "none", "forbidden"),
        "dedicated": ("exact-key", {"owner"}, "resolved", "required"),
        "fallback": ("exact-key", {"owner"}, "resolved", "required"),
        "passthrough": ("exact-key", {"member"}, "resolved", "required"),
        "program": ("exact-key", {"owner"}, "resolved", "required"),
        "unsupported": ("none", {"member"}, "direct", "forbidden"),
        "unattributed": (
            "none", {"member"}, "resolved-or-direct", "forbidden",
        ),
    }
    for record in records:
        contract = state_contracts.get(record["kind"])
        if contract is None:
            failures.append("effect runtime disposition kind invalid")
            continue
        expected_attribution, allowed_roles, group_contract, family_contract = contract
        group = groups_by_layer.get(record["group_id"])
        group_kind = group["kind"] if group is not None else None
        if (
            record["attribution"] != expected_attribution
            or record["role"] not in allowed_roles
            or (family_contract == "required" and record["family"] is None)
            or (family_contract == "forbidden" and record["family"] is not None)
        ):
            failures.append("effect runtime disposition state combination invalid")
            continue
        if group_contract == "none":
            valid_group = record["group_id"] is None and group is None
        elif group_contract == "resolved-or-direct":
            valid_group = group_kind in {"resolved", "direct"}
        else:
            valid_group = group_kind == group_contract
        if not valid_group:
            failures.append("effect runtime disposition state group invalid")
        if record["kind"] in {"unsupported", "unattributed"} and (
            record["reason"] is None
        ):
            failures.append("effect runtime disposition diagnostic reason missing")
        if record["kind"] == "unattributed":
            failures.append("effect runtime disposition contains unattributed stage")

    if stage_admission is None:
        stage_admission = effect_stage_admission_metrics(preview_text)
    admission_records = stage_admission.get("records", [])
    admission_identities = [
        (record["layer_id"], record["effect_index"], record["descriptor_id"])
        for record in admission_records
    ]
    if not stage_admission.get("has_evidence"):
        failures.append("effect runtime disposition stage admission evidence missing")
    elif stage_admission.get("validation_failures"):
        failures.append("effect runtime disposition stage admission evidence invalid")
    if stage_admission.get("has_evidence"):
        if set(record_identities) != set(admission_identities):
            failures.append("effect runtime disposition EffectKey set mismatch")
        if set(group_layers) != {
            record["layer_id"] for record in admission_records
        }:
            failures.append("effect runtime disposition admission layer set mismatch")
        runtime_by_identity = {
            identity: record
            for identity, record in zip(record_identities, records)
        }
        admission_by_identity = {
            identity: record
            for identity, record in zip(admission_identities, admission_records)
        }
        for identity in set(runtime_by_identity).intersection(admission_by_identity):
            record = runtime_by_identity[identity]
            admission = admission_by_identity[identity]
            group = groups_by_layer.get(record["layer_id"])
            group_kind = group["kind"] if group is not None else None
            resolved_material_owner = (
                record["kind"] == "program"
                and record["family"] == "resolved-material"
                and record["reason"] == "resolved-material-capability-owner"
                and group_kind == "resolved"
            )
            if record["definition_path"] != admission["definition_path"]:
                failures.append("effect runtime disposition definition path mismatch")
            if admission["activity"] not in {"active", "property-inactive"}:
                expected_kind = "inactive"
                expected_reason = admission["activity"]
            elif resolved_material_owner:
                expected_kind = "program"
                expected_reason = "resolved-material-capability-owner"
            elif admission["admission"] == "admitted-dedicated":
                expected_kind = "dedicated"
                expected_reason = admission["reason"]
            elif admission["admission"] == "admitted-fallback":
                expected_kind = "fallback"
                expected_reason = "effect-local-visual-failure"
            elif admission["admission"] == "admitted-passthrough":
                expected_kind = "passthrough"
                expected_reason = (
                    "initially-inactive-property-stage-passthrough"
                )
            elif admission["admission"] == "admitted-generic":
                expected_kind = "program"
                expected_reason = admission["reason"]
            else:
                expected_kind = "unsupported"
                expected_reason = (
                    "r5-no-runtime-owner"
                    if group is not None
                    and group["reason"] == "r5-no-runtime-owner"
                    else None
                )
            if record["kind"] != expected_kind:
                failures.append("effect runtime disposition conflicts with admission")
            if expected_reason is not None and record["reason"] != expected_reason:
                failures.append("effect runtime disposition admission reason mismatch")
            if expected_kind == "dedicated" and (
                record["family"] != admission["backend"]
            ):
                failures.append("effect runtime disposition dedicated family mismatch")
            if expected_kind == "fallback" and (
                record["family"] != admission["backend"]
                or record["family"] != "visual-failure-passthrough"
            ):
                failures.append("effect runtime disposition fallback family mismatch")
            if expected_kind == "passthrough" and (
                record["family"] != admission["backend"]
                or record["family"] != "initially-inactive-passthrough"
            ):
                failures.append(
                    "effect runtime disposition passthrough family mismatch"
                )
            if expected_kind == "program" and not resolved_material_owner and (
                record["family"] != (
                    admission["profile"] or admission["backend"]
                )
            ):
                failures.append("effect runtime disposition generic family mismatch")
        for group in groups:
            admissions = [
                record for record in admission_records
                if record["layer_id"] == group["layer_id"]
            ]
            active_count = sum(
                record["activity"] in {"active", "property-inactive"}
                for record in admissions
            )
            if group["effect_count"] != active_count:
                failures.append("effect runtime disposition active admission count mismatch")
            if (active_count == 0) != (group["kind"] == "inactive"):
                failures.append("effect runtime disposition inactive admission group mismatch")

    canonical_payload = {"groups": groups, "records": records}
    canonical_sha256 = hashlib.sha256(json.dumps(
        canonical_payload,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "has_evidence": True,
        "schema_version": schema_version,
        "route_scope": route_scope,
        "record_count": record_count,
        "group_count": group_count,
        "kind_counts": kind_counts,
        "attribution_counts": attribution_counts,
        "role_counts": role_counts,
        "group_kind_counts": group_kind_counts,
        "conservation": conservation,
        "groups": groups,
        "records": records,
        "canonical_sha256": canonical_sha256,
        "validation_failures": failures,
    }
