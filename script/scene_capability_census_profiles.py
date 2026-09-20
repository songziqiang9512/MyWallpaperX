#!/usr/bin/env python3
"""Safe structural profiles used by the authored Scene corpus census."""

from __future__ import annotations

import math
import re
from collections import Counter
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


def scenescript_audio_registrations(source: str) -> dict[str, Any] | None:
    """Return payload-free, scope-aware AudioBuffers registrations.

    This is deliberately a conservative JavaScript lexer, not an evaluator.
    Only a direct ``engine.registerAudioBuffers`` (or the equivalent computed
    string member) at proven top-level scope with an exact supported resolution
    is statically admitted. Nested/callback calls and expressions remain
    explicit unknowns for module evaluation instead of being upgraded to
    consumers. Comments, strings and regular-expression bodies are ignored;
    executable template interpolations are still scanned.
    """

    tokens = _javascript_tokens(source)
    resolutions: list[str] = []
    scopes: list[str] = []
    admissions: list[str] = []
    index = 0
    while index < len(tokens):
        open_index = _audio_registration_open_paren(tokens, index)
        if open_index is None:
            index += 1
            continue
        closing_index = _matching_paren(tokens, open_index)
        scope = _registration_scope(tokens, index)
        resolution = (
            _registration_resolution(tokens[open_index + 1:closing_index])
            if closing_index is not None else "dynamic-or-invalid"
        )
        scopes.append(scope)
        resolutions.append(resolution)
        if scope == "proven-global" and resolution in {"16", "32", "64"}:
            admissions.append("statically-admitted")
        elif scope == "proven-global":
            admissions.append("resolution-unresolved")
        else:
            admissions.append("scope-unproven")
        index = (closing_index + 1) if closing_index is not None else open_index + 1
    if not resolutions:
        return None
    return {
        "call_count": len(resolutions),
        "resolution_states": sorted(set(resolutions)),
        "scope_states": sorted(set(scopes)),
        "admission_states": sorted(set(admissions)),
        "statically_admitted_call_count": admissions.count("statically-admitted"),
        "resolution_state_counts": dict(sorted(Counter(resolutions).items())),
        "scope_state_counts": dict(sorted(Counter(scopes).items())),
        "admission_state_counts": dict(sorted(Counter(admissions).items())),
    }


@dataclass(frozen=True)
class _JavaScriptToken:
    kind: str
    value: str
    start: int
    end: int
    brace_depth: int
    paren_depth: int


def _javascript_tokens(source: str) -> list[_JavaScriptToken]:
    """Tokenize only the structure needed by the audio declaration census."""

    tokens: list[_JavaScriptToken] = []
    brace_depth = 0
    paren_depth = 0

    def append(kind: str, value: str, start: int, end: int) -> None:
        tokens.append(_JavaScriptToken(
            kind, value, start, end, brace_depth, paren_depth
        ))

    def skip_quoted(index: int, quote: str) -> tuple[int, str | None]:
        value: list[str] = []
        simple = True
        index += 1
        while index < len(source):
            character = source[index]
            if character == "\\":
                simple = False
                index += 2
                continue
            if character == quote:
                return index + 1, "".join(value) if simple else None
            value.append(character)
            index += 1
        return index, None

    def regex_starts_here() -> bool:
        if not tokens:
            return True
        return tokens[-1].value in {
            "(", "[", "{", ",", ":", ";", "=", "=>", "!", "?",
            "return", "case", "throw", "typeof", "void", "delete", "in",
        }

    def skip_regex(index: int) -> int:
        index += 1
        in_class = False
        while index < len(source):
            character = source[index]
            if character == "\\":
                index += 2
                continue
            if character == "[":
                in_class = True
            elif character == "]":
                in_class = False
            elif character == "/" and not in_class:
                index += 1
                while index < len(source) and (
                    source[index].isalpha() or source[index] in "$_"
                ):
                    index += 1
                return index
            elif character in "\r\n":
                return index
            index += 1
        return index

    def scan_template(index: int) -> int:
        index += 1
        while index < len(source):
            character = source[index]
            following = source[index + 1] if index + 1 < len(source) else ""
            if character == "\\":
                index += 2
                continue
            if character == "`":
                return index + 1
            if character == "$" and following == "{":
                index = scan_code(index + 2, template_expression=True)
                continue
            index += 1
        return index

    def scan_code(index: int, *, template_expression: bool = False) -> int:
        nonlocal brace_depth, paren_depth
        expression_base_brace_depth = brace_depth
        while index < len(source):
            character = source[index]
            following = source[index + 1] if index + 1 < len(source) else ""
            if template_expression and character == "}" and (
                brace_depth == expression_base_brace_depth
            ):
                return index + 1
            if character.isspace():
                index += 1
                continue
            if character == "/" and following == "/":
                index += 2
                while index < len(source) and source[index] not in "\r\n":
                    index += 1
                continue
            if character == "/" and following == "*":
                index += 2
                while index + 1 < len(source) and source[index:index + 2] != "*/":
                    index += 1
                index = min(len(source), index + 2)
                continue
            if character in {"'", '"'}:
                start = index
                index, value = skip_quoted(index, character)
                append("string", value or "", start, index)
                continue
            if character == "`":
                index = scan_template(index)
                continue
            if character == "/" and regex_starts_here():
                index = skip_regex(index)
                continue
            if character.isalpha() or character in "$_":
                start = index
                index += 1
                while index < len(source) and (
                    source[index].isalnum() or source[index] in "$_"
                ):
                    index += 1
                append("identifier", source[start:index], start, index)
                continue
            if character.isdigit():
                start = index
                index += 1
                while index < len(source) and (
                    source[index].isalnum() or source[index] in ".xX_"
                ):
                    index += 1
                append("number", source[start:index], start, index)
                continue
            if character == "=" and following == ">":
                append("punctuation", "=>", index, index + 2)
                index += 2
                continue
            if character == "{":
                append("punctuation", character, index, index + 1)
                brace_depth += 1
            elif character == "}":
                brace_depth = max(0, brace_depth - 1)
                append("punctuation", character, index, index + 1)
            elif character == "(":
                append("punctuation", character, index, index + 1)
                paren_depth += 1
            elif character == ")":
                paren_depth = max(0, paren_depth - 1)
                append("punctuation", character, index, index + 1)
            else:
                append("punctuation", character, index, index + 1)
            index += 1
        return index

    scan_code(0)
    return tokens


def _audio_registration_open_paren(
    tokens: list[_JavaScriptToken], index: int
) -> int | None:
    if [token.value for token in tokens[index:index + 4]] == [
        "engine", ".", "registerAudioBuffers", "(",
    ]:
        return index + 3
    candidate = tokens[index:index + 5]
    if [token.value for token in candidate] == [
        "engine", "[", "registerAudioBuffers", "]", "(",
    ] and len(candidate) == 5 and candidate[2].kind == "string":
        return index + 4
    return None


def _matching_paren(
    tokens: list[_JavaScriptToken], open_index: int
) -> int | None:
    depth = tokens[open_index].paren_depth
    for index in range(open_index + 1, len(tokens)):
        token = tokens[index]
        if token.value == ")" and token.paren_depth == depth:
            return index
    return None


def _registration_scope(
    tokens: list[_JavaScriptToken], call_index: int
) -> str:
    call = tokens[call_index]
    if call.brace_depth != 0:
        return "non-global-or-nested"
    boundary = -1
    for index in range(call_index - 1, -1, -1):
        token = tokens[index]
        if token.brace_depth == 0 and token.value in {";", "}"}:
            boundary = index
            break
    prefix = tokens[boundary + 1:call_index]
    if any(token.value in {"=>", "function"} for token in prefix):
        return "non-global-or-nested"
    return "proven-global"


def _registration_resolution(tokens: list[_JavaScriptToken]) -> str:
    values = [token.value for token in tokens]
    if not values:
        return "16"
    if len(tokens) == 1 and tokens[0].kind == "number" and values[0] in {
        "16", "32", "64",
    }:
        return values[0]
    if len(tokens) == 3 and values[0:2] == ["engine", "."]:
        match = re.fullmatch(r"AUDIO_RESOLUTION_(16|32|64)", values[2])
        if match is not None:
            return match.group(1)
    if len(tokens) == 4 and values[0] == "engine" and values[1] == "[" and (
        tokens[2].kind == "string" and values[3] == "]"
    ):
        match = re.fullmatch(r"AUDIO_RESOLUTION_(16|32|64)", values[2])
        if match is not None:
            return match.group(1)
    return "dynamic-or-invalid"


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
