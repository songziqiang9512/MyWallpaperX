#!/usr/bin/env python3
"""Shader compiler request identity and bounded stage validation."""

from __future__ import annotations

import hashlib
import json
from typing import Any

from scene_shader_compiler_color_transfer_contract import (
    IndependentSignalContractFailure,
    expected_color_transfer_key,
    parse_expected_transfer,
)
from scene_shader_compiler_input_color_contract import (
    InputColorContractFailure,
    cache_key as input_color_cache_key,
    premultiplied_color_input_slots,
)


ALLOWED_STAGES = ("vertex", "fragment")


class RequestContractFailure(ValueError):
    def __init__(self, code: str, details: list[str] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details or []


def expected_independent_color_transfer(value: Any) -> dict[str, Any] | None:
    try:
        return parse_expected_transfer(value)
    except IndependentSignalContractFailure as error:
        raise RequestContractFailure(error.code) from error


def expected_color_transfer_for_output(
    output_semantics: Any, value: Any
) -> dict[str, Any] | None:
    if output_semantics not in ("color", "red-green-unorm"):
        raise RequestContractFailure("output-semantics")
    if output_semantics == "red-green-unorm" and value is not None:
        raise RequestContractFailure("expected-color-transfer")
    return None if output_semantics != "color" else (
        expected_independent_color_transfer(value)
    )


def request_cache_key(request: dict[str, Any]) -> str:
    if request.get("schemaVersion") != 5:
        raise RequestContractFailure("request-schema")
    raw_stages = request.get("stages")
    if not isinstance(raw_stages, list):
        raise RequestContractFailure("request-stages")
    sources: dict[str, str] = {}
    for stage in raw_stages:
        if not isinstance(stage, dict):
            raise RequestContractFailure("request-stage")
        name, source = stage.get("stage"), stage.get("source")
        if name not in ALLOWED_STAGES or not isinstance(source, str):
            raise RequestContractFailure("request-stage")
        sources[name] = source
    if set(sources) != set(ALLOWED_STAGES):
        raise RequestContractFailure("request-pair")

    output_semantics = request.get("outputSemantics")
    expected = expected_color_transfer_for_output(
        output_semantics, request.get("expectedColorTransfer")
    )
    try:
        input_slots = premultiplied_color_input_slots(
            request.get("premultipliedColorInputSlots")
        )
    except InputColorContractFailure as error:
        raise RequestContractFailure(str(error)) from error

    digest = hashlib.sha256()
    for value in (
        "mwx-generic-shader-request-v10",
        str(request.get("sourceDialect", "glsl-450")),
        output_semantics,
        sources["vertex"],
        sources["fragment"],
        expected_color_transfer_key(expected),
        input_color_cache_key(input_slots),
        json.dumps(request.get("defines", {}), sort_keys=True, separators=(",", ":")),
    ):
        encoded = value.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    return digest.hexdigest()


def validated_request_stages(
    payload: dict[str, Any], maximum_stage_source_bytes: int
) -> list[dict[str, str]]:
    if payload.get("schemaVersion") != 5:
        raise RequestContractFailure("schema-version")
    request_id = payload.get("requestID")
    if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
        raise RequestContractFailure("request-id")
    expected_color_transfer_for_output(
        payload.get("outputSemantics"), payload.get("expectedColorTransfer")
    )
    try:
        premultiplied_color_input_slots(
            payload.get("premultipliedColorInputSlots")
        )
    except InputColorContractFailure as error:
        raise RequestContractFailure(str(error)) from error

    raw_stages = payload.get("stages")
    if not isinstance(raw_stages, list) or len(raw_stages) != 2:
        raise RequestContractFailure("stage-count")
    stages: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in raw_stages:
        if not isinstance(raw, dict):
            raise RequestContractFailure("stage-shape")
        stage = raw.get("stage")
        entry_point = raw.get("entryPoint")
        source = raw.get("source")
        if stage not in ALLOWED_STAGES or stage in seen:
            raise RequestContractFailure("stage-identity")
        if entry_point != "main":
            raise RequestContractFailure("entry-point")
        if not isinstance(source, str) or not source:
            raise RequestContractFailure("source")
        encoded = source.encode("utf-8")
        if len(encoded) > maximum_stage_source_bytes:
            raise RequestContractFailure("source-too-large", [str(stage)])
        if "\x00" in source:
            raise RequestContractFailure("source-nul", [str(stage)])
        seen.add(stage)
        stages.append({"stage": stage, "entryPoint": entry_point, "source": source})
    if seen != set(ALLOWED_STAGES):
        raise RequestContractFailure("stage-pair")
    return sorted(stages, key=lambda value: ALLOWED_STAGES.index(value["stage"]))
