#!/usr/bin/env python3
"""Safe structural profiles used by the authored Scene corpus census."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from typing import Any, Iterable

from scene_capability_census_io import canonical_sha256


SCRIPT_HOOK_PATTERN = re.compile(
    r"\b(?:export\s+)?(?:function\s+)?(init|update|applyUserProperties|"
    r"mediaPlaybackChanged|mediaPropertiesChanged|mediaThumbnailChanged|"
    r"cursorDown|cursorUp|cursorMove|audioProcessing)\b"
)
SCRIPT_API_PATTERN = re.compile(
    r"\b(engine|thisLayer|thisScene|shared|audioBuffer|media|cursor|pointer|"
    r"currentMousePosition|previousMousePosition)\b"
)


def value_kind(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def numeric_components(value: Any) -> list[float] | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        return [number] if math.isfinite(number) else None
    if isinstance(value, str):
        tokens = re.split(r"[\s,]+", value.strip()) if value.strip() else []
        if not tokens:
            return None
        try:
            numbers = [float(token) for token in tokens]
        except ValueError:
            return None
        return numbers if all(math.isfinite(number) for number in numbers) else None
    return None


def binding_sources(value: Any) -> list[str]:
    if not isinstance(value, dict):
        return ["authored"]
    sources: list[str] = []
    if "value" in value:
        sources.append("authored-fallback")
    if isinstance(value.get("user"), str):
        sources.append("user-property")
    if isinstance(value.get("script"), str):
        sources.append("scenescript")
    if "animation" in value or "timeline" in value:
        sources.append("timeline")
    if isinstance(value.get("condition"), (str, dict)):
        sources.append("condition")
    return sources or ["object-wrapper"]


def safe_value_shape(value: Any) -> dict[str, Any]:
    kind = value_kind(value)
    shape: dict[str, Any] = {"kind": kind}
    if isinstance(value, dict):
        shape["keys"] = sorted(str(key) for key in value)
        shape["sources"] = binding_sources(value)
        authored = value.get("value")
        components = numeric_components(authored)
        if components is not None:
            shape["component_count"] = len(components)
            shape["finite"] = True
            shape["numeric_min"] = min(components)
            shape["numeric_max"] = max(components)
        script = value.get("script")
        if isinstance(script, str):
            shape["script"] = script_profile(script)
        animation = value.get("animation")
        if isinstance(animation, dict):
            shape["animation_keys"] = sorted(str(key) for key in animation)
    elif isinstance(value, list):
        shape["length"] = len(value)
        shape["element_kinds"] = sorted({value_kind(item) for item in value})
        components = numeric_components(value)
        if components is not None:
            shape["component_count"] = len(components)
    elif isinstance(value, str):
        components = numeric_components(value)
        shape["length"] = len(value)
        if components is not None:
            shape["component_count"] = len(components)
            shape["finite"] = True
            shape["numeric_min"] = min(components)
            shape["numeric_max"] = max(components)
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        number = float(value)
        shape["component_count"] = 1
        shape["finite"] = math.isfinite(number)
        if math.isfinite(number):
            shape["numeric_min"] = number
            shape["numeric_max"] = number
    return shape


def script_profile(source: str) -> dict[str, Any]:
    hooks = sorted(set(SCRIPT_HOOK_PATTERN.findall(source)))
    apis = sorted(set(SCRIPT_API_PATTERN.findall(source)))
    features = []
    for token, name in (
        ("for", "for-loop"),
        ("while", "while-loop"),
        ("if", "conditional"),
        ("return", "return"),
        ("Math.", "math-api"),
        ("Date", "date-api"),
        ("JSON", "json-api"),
        ("Promise", "promise-api"),
    ):
        if token in source:
            features.append(name)
    return {
        "sha256": canonical_sha256(source),
        "byte_count": len(source.encode("utf-8")),
        "line_count": source.count("\n") + 1,
        "hooks": hooks,
        "api_families": apis,
        "features": sorted(features),
    }


FAMILY_REVISION_FIELDS = {
    "byte_count",
    "line_count",
    "length",
    "numeric_max",
    "numeric_min",
    "occurrence_refs",
    "sha256",
    "string_byte_max",
    "string_byte_min",
}


def semantic_family_shape(value: Any) -> Any:
    """Remove concrete revision/value evidence from a public capability shape."""
    if isinstance(value, dict):
        return {
            str(key): semantic_family_shape(child)
            for key, child in sorted(value.items(), key=lambda item: str(item[0]).casefold())
            if str(key) not in FAMILY_REVISION_FIELDS
        }
    if isinstance(value, list):
        return [semantic_family_shape(child) for child in value]
    return value


def family_key(domain: str, kind: str, shape: Any) -> str:
    digest = canonical_sha256(semantic_family_shape(shape))[:16]
    return f"{domain}/{kind}@{digest}"


def revision_key(*parts: Any) -> str:
    return canonical_sha256(list(parts))


def occurrence_id(domain: str, location: dict[str, Any]) -> str:
    return canonical_sha256({"domain": domain, "location": location})


@dataclass
class ParameterProfileAccumulator:
    owner_kind: str
    name: str
    shape_key: str
    kinds: set[str] = field(default_factory=set)
    sources: set[str] = field(default_factory=set)
    binding_keys: set[str] = field(default_factory=set)
    component_counts: set[int] = field(default_factory=set)
    numeric_min: float | None = None
    numeric_max: float | None = None
    occurrence_refs: list[str] = field(default_factory=list)

    def add(self, value: Any, occurrence_ref: str) -> None:
        shape = safe_value_shape(value)
        self.kinds.add(str(shape["kind"]))
        self.sources.update(str(source) for source in shape.get("sources", ["authored"]))
        self.binding_keys.update(str(key) for key in shape.get("keys", []))
        if isinstance(shape.get("component_count"), int):
            self.component_counts.add(shape["component_count"])
        low = shape.get("numeric_min")
        high = shape.get("numeric_max")
        if isinstance(low, (int, float)):
            self.numeric_min = float(low) if self.numeric_min is None else min(self.numeric_min, float(low))
        if isinstance(high, (int, float)):
            self.numeric_max = float(high) if self.numeric_max is None else max(self.numeric_max, float(high))
        self.occurrence_refs.append(occurrence_ref)

    def payload(self) -> dict[str, Any]:
        key = family_key(
            "parameter",
            self.owner_kind,
            {"name": self.name.casefold(), "shape": self.shape_key},
        )
        return {
            "parameter_profile_key": key,
            "owner_kind": self.owner_kind,
            "normalized_name": self.name.casefold(),
            "value_kinds": sorted(self.kinds),
            "source_kinds": sorted(self.sources),
            "binding_keys": sorted(self.binding_keys),
            "component_counts": sorted(self.component_counts),
            "numeric_min": self.numeric_min,
            "numeric_max": self.numeric_max,
            "occurrence_count": len(self.occurrence_refs),
            "occurrence_refs": sorted(self.occurrence_refs),
        }


class ParameterProfiles:
    def __init__(self) -> None:
        self._profiles: dict[tuple[str, str, str], ParameterProfileAccumulator] = {}

    def add(self, owner_kind: str, name: str, value: Any, occurrence_ref: str) -> str:
        shape = safe_value_shape(value)
        shape_key = canonical_sha256({
            "kind": shape["kind"],
            "keys": shape.get("keys", []),
            "sources": shape.get("sources", ["authored"]),
            "component_count": shape.get("component_count"),
        })[:16]
        identity = (owner_kind, name.casefold(), shape_key)
        accumulator = self._profiles.setdefault(
            identity,
            ParameterProfileAccumulator(owner_kind, name, shape_key),
        )
        accumulator.add(value, occurrence_ref)
        return family_key(
            "parameter",
            owner_kind,
            {"name": name.casefold(), "shape": shape_key},
        )

    def payloads(self) -> list[dict[str, Any]]:
        return sorted(
            (profile.payload() for profile in self._profiles.values()),
            key=lambda value: value["parameter_profile_key"],
        )


@dataclass
class SchemaFieldAccumulator:
    document_kind: str
    path_pattern: str
    field_name: str
    count: int = 0
    kinds: set[str] = field(default_factory=set)
    sources: set[str] = field(default_factory=set)
    component_counts: set[int] = field(default_factory=set)
    numeric_min: float | None = None
    numeric_max: float | None = None
    string_byte_min: int | None = None
    string_byte_max: int | None = None
    script_hashes: set[str] = field(default_factory=set)
    script_hooks: set[str] = field(default_factory=set)
    script_apis: set[str] = field(default_factory=set)
    sample_ids: set[str] = field(default_factory=set)

    def add(self, value: Any, sample_id: str) -> None:
        shape = safe_value_shape(value)
        self.count += 1
        self.kinds.add(str(shape["kind"]))
        self.sample_ids.add(sample_id)
        self.sources.update(str(source) for source in shape.get("sources", ["authored"]))
        component_count = shape.get("component_count")
        if isinstance(component_count, int):
            self.component_counts.add(component_count)
        low = shape.get("numeric_min")
        high = shape.get("numeric_max")
        if isinstance(low, (int, float)):
            self.numeric_min = float(low) if self.numeric_min is None else min(self.numeric_min, float(low))
        if isinstance(high, (int, float)):
            self.numeric_max = float(high) if self.numeric_max is None else max(self.numeric_max, float(high))
        if isinstance(value, str):
            byte_count = len(value.encode("utf-8"))
            self.string_byte_min = byte_count if self.string_byte_min is None else min(self.string_byte_min, byte_count)
            self.string_byte_max = byte_count if self.string_byte_max is None else max(self.string_byte_max, byte_count)
        script = shape.get("script")
        if isinstance(script, dict):
            self.script_hashes.add(str(script["sha256"]))
            self.script_hooks.update(str(value) for value in script.get("hooks", []))
            self.script_apis.update(str(value) for value in script.get("api_families", []))

    def payload(self) -> dict[str, Any]:
        return {
            "schema_field_key": family_key(
                "schema-field",
                self.document_kind,
                {"path": self.path_pattern, "field": self.field_name.casefold()},
            ),
            "document_kind": self.document_kind,
            "path_pattern": self.path_pattern,
            "field_name": self.field_name,
            "count": self.count,
            "sample_count": len(self.sample_ids),
            "sample_ids": sorted(self.sample_ids),
            "value_kinds": sorted(self.kinds),
            "source_kinds": sorted(self.sources),
            "component_counts": sorted(self.component_counts),
            "numeric_min": self.numeric_min,
            "numeric_max": self.numeric_max,
            "string_byte_min": self.string_byte_min,
            "string_byte_max": self.string_byte_max,
            "script_hashes": sorted(self.script_hashes),
            "script_hooks": sorted(self.script_hooks),
            "script_api_families": sorted(self.script_apis),
        }


class SchemaInventory:
    """Conserving, payload-free inventory of every authored JSON leaf."""

    def __init__(self) -> None:
        self._fields: dict[tuple[str, str, str], SchemaFieldAccumulator] = {}
        self.document_count = 0
        self.leaf_count = 0
        self.documents_by_kind: dict[str, int] = {}
        self.leaves_by_kind: dict[str, int] = {}

    def add_document(self, document_kind: str, value: Any, sample_id: str) -> None:
        self.document_count += 1
        self.documents_by_kind[document_kind] = self.documents_by_kind.get(document_kind, 0) + 1

        def walk(candidate: Any, path: tuple[str, ...], field_name: str) -> None:
            if isinstance(candidate, dict):
                if not candidate:
                    self._add_leaf(document_kind, path, field_name, candidate, sample_id)
                    return
                for key, child in sorted(candidate.items(), key=lambda item: str(item[0]).casefold()):
                    walk(child, (*path, str(key)), str(key))
                return
            if isinstance(candidate, list):
                if not candidate:
                    self._add_leaf(
                        document_kind,
                        (*path, "[]"),
                        field_name,
                        candidate,
                        sample_id,
                    )
                    return
                for child in candidate:
                    walk(child, (*path, "[]"), field_name)
                return
            self._add_leaf(document_kind, path, field_name, candidate, sample_id)

        walk(value, (), "$root")

    def _add_leaf(
        self,
        document_kind: str,
        path: tuple[str, ...],
        field_name: str,
        value: Any,
        sample_id: str,
    ) -> None:
        path_pattern = ".".join(path) or "$root"
        identity = (document_kind, path_pattern, field_name.casefold())
        accumulator = self._fields.setdefault(
            identity,
            SchemaFieldAccumulator(document_kind, path_pattern, field_name),
        )
        if field_name.casefold() == "script" and isinstance(value, str):
            value = {"script": value}
        accumulator.add(value, sample_id)
        self.leaf_count += 1
        self.leaves_by_kind[document_kind] = self.leaves_by_kind.get(document_kind, 0) + 1

    def payloads(self) -> list[dict[str, Any]]:
        return sorted(
            (field.payload() for field in self._fields.values()),
            key=lambda value: value["schema_field_key"],
        )

    def conservation(self) -> dict[str, Any]:
        classified = sum(field.count for field in self._fields.values())
        return {
            "document_count": self.document_count,
            "documents_by_kind": dict(sorted(self.documents_by_kind.items())),
            "observed_leaf_count": self.leaf_count,
            "classified_leaf_count": classified,
            "leaves_by_kind": dict(sorted(self.leaves_by_kind.items())),
            "balanced": classified == self.leaf_count,
        }


def profile_parameter_mapping(
    profiles: ParameterProfiles,
    owner_kind: str,
    mapping: Any,
    occurrence_ref: str,
) -> list[str]:
    if not isinstance(mapping, dict):
        return []
    return [
        profiles.add(owner_kind, str(name), value, occurrence_ref)
        for name, value in sorted(mapping.items(), key=lambda item: str(item[0]).casefold())
    ]


def recursive_dynamic_features(value: Any) -> dict[str, int]:
    counts = {
        "script_wrappers": 0,
        "user_bindings": 0,
        "timeline_wrappers": 0,
        "condition_wrappers": 0,
    }

    def walk(candidate: Any) -> None:
        if isinstance(candidate, dict):
            if isinstance(candidate.get("script"), str):
                counts["script_wrappers"] += 1
            if isinstance(candidate.get("user"), str):
                counts["user_bindings"] += 1
            if "animation" in candidate or "timeline" in candidate:
                counts["timeline_wrappers"] += 1
            if "condition" in candidate:
                counts["condition_wrappers"] += 1
            for child in candidate.values():
                walk(child)
        elif isinstance(candidate, list):
            for child in candidate:
                walk(child)

    walk(value)
    return counts


def merge_counts(target: dict[str, int], source: dict[str, int]) -> None:
    for key, value in source.items():
        target[key] = target.get(key, 0) + value


def sorted_unique(values: Iterable[str]) -> list[str]:
    return sorted(set(values))
