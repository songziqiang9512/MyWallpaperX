#!/usr/bin/env python3
"""Exported request identity, bound texture context, and legacy replay."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_request_contract import (  # noqa: E402
    RequestContractFailure,
    request_cache_key,
    validated_request_stages,
)


def request() -> dict:
    return {
        "schemaVersion": 7,
        "requestID": "own-bound-context",
        "sourceDialect": "wallpaper-engine-glsl-like-v0",
        "outputSemantics": "color",
        "expectedColorTransfer": {
            "kind": "independent-alpha-signal-preserving", "slot": 1,
        },
        "premultipliedColorInputSlots": [2],
        "defaultBoundaryColorSlots": [0, 3],
        "colorBoundary": {
            "colorInputSlots": [0, 3],
            "outputRepresentation": "premultiplied-alpha",
            "signalPassthroughSlot": 0,
        },
        "boundTextureSlots": [0, 3, 7],
        "defines": {},
        "stages": [
            {"stage": "vertex", "entryPoint": "main",
             "source": "void main() { /* 顶点 */ }"},
            {"stage": "fragment", "entryPoint": "main",
             "source": "void main() { /* fragment */ }"},
        ],
    }


class SceneShaderCompilerRequestContractTests(unittest.TestCase):
    def test_schema7_matches_swift_v33_utf8_field_order(self) -> None:
        # The Swift key frames each UTF-8 field with a big-endian UInt64 length;
        # bound slots follow colorBoundary and precede defines.
        payload = request()
        self.assertEqual(request_cache_key(payload),
            "dbbe49f500407f7680c5532f0bbab75e48708dc7bdc7aa7d9f07fde3996b8729")
        self.assertNotEqual(request_cache_key(payload),
            "97b87df878d0ddbfad61bfb3f8972db17b563553436f05e28976b089d3e0d421")
        self.assertNotEqual(request_cache_key(payload),
            "50685a429c279c65a21e49de075e1f69be11d78884c7e4706484143f15f0d902")
        replay = json.loads(json.dumps(payload, ensure_ascii=False))
        replay["stages"].reverse()
        self.assertEqual(request_cache_key(replay), request_cache_key(payload))
        self.assertEqual(validated_request_stages(replay, 65_536), payload["stages"])

    def test_missing_bound_context_is_empty_but_each_bound_set_has_own_key(self) -> None:
        payload = request()
        missing = {key: value for key, value in payload.items()
                   if key != "boundTextureSlots"}
        empty = {**payload, "boundTextureSlots": []}
        self.assertEqual(request_cache_key(missing), request_cache_key(empty))
        self.assertEqual(validated_request_stages(missing, 65_536), payload["stages"])
        keys = {request_cache_key({**payload, "boundTextureSlots": slots})
                for slots in ([], [0], [3], [0, 3], list(range(8)))}
        self.assertEqual(len(keys), 5)

    def test_bound_context_cannot_replace_other_typed_key_fields(self) -> None:
        payload = request()
        variants = [payload, {**payload, "premultipliedColorInputSlots": []},
                    {**payload, "defaultBoundaryColorSlots": []},
                    {**payload, "colorBoundary": None},
                    {**payload, "expectedColorTransfer": None},
                    {**payload, "defines": {"OPTIONAL_MASK": 1}},
                    {**payload, "boundTextureSlots": []}]
        self.assertEqual(len({request_cache_key(value) for value in variants}), 7)

    def test_invalid_bound_slots_reject_validation_and_identity(self) -> None:
        for slots in (None, "0,1", {}, [True], [0.0], [-1], [8],
                      [0, 0], [3, 0], list(range(9))):
            with self.subTest(slots=slots):
                payload = {**request(), "boundTextureSlots": slots}
                for validate in (request_cache_key,
                                 lambda value: validated_request_stages(value, 65_536)):
                    with self.assertRaises(RequestContractFailure) as failure:
                        validate(payload)
                    self.assertEqual(failure.exception.code, "bound-texture-slots")

    def test_schema6_replay_keeps_historical_identity_without_bound_context(self) -> None:
        # Captured from the unmodified HEAD contract and the existing fixtures.
        keys = {
            "ordinary_one_pass": "b2c721ef7ba55299bbc13753e506475520b4df152e2d77aba70b0cb4716c48f3",
            "wallpaper_engine_one_pass": "5a8c6d6b8a79ff4125b1bbb46f863ea1d6113e5538f15197a72c3f2105514a11",
        }
        for name, key in keys.items():
            with self.subTest(fixture=name):
                path = REPOSITORY_ROOT / "script/fixtures/scene_shader_compiler" / f"{name}.json"
                legacy = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(legacy["schemaVersion"], 6)
                self.assertEqual(request_cache_key(legacy), key)
                self.assertEqual(len(validated_request_stages(legacy, 65_536)), 2)
                modern = {**legacy, "schemaVersion": 7, "boundTextureSlots": []}
                self.assertNotEqual(request_cache_key(legacy), request_cache_key(modern))
                self.assertEqual(validated_request_stages(modern, 65_536),
                                 validated_request_stages(legacy, 65_536))

    def test_schema6_cannot_silently_drop_new_binding_context(self) -> None:
        for slots in ([], [0], None):
            with self.subTest(slots=slots):
                legacy = {**request(), "schemaVersion": 6, "boundTextureSlots": slots}
                for validate in (request_cache_key,
                                 lambda value: validated_request_stages(value, 65_536)):
                    with self.assertRaises(RequestContractFailure) as failure:
                        validate(legacy)
                    self.assertEqual(failure.exception.code, "bound-texture-slots-schema")

    def test_new_schema_preserves_stage_limits_and_version_rejection(self) -> None:
        payload = request()
        for schema in (5, 8, "7", 7.0, True, None):
            with self.subTest(schema=schema):
                for validate, code in (
                    (request_cache_key, "request-schema"),
                    (lambda value: validated_request_stages(value, 65_536), "schema-version"),
                ):
                    with self.assertRaises(RequestContractFailure) as failure:
                        validate({**payload, "schemaVersion": schema})
                    self.assertEqual(failure.exception.code, code)
        for source, maximum, code in (("void main() {}", 1, "source-too-large"),
                                      ("void main() {\x00}", 65_536, "source-nul")):
            invalid = copy.deepcopy(payload)
            invalid["stages"][0]["source"] = source
            with self.assertRaises(RequestContractFailure) as failure:
                validated_request_stages(invalid, maximum)
            self.assertEqual(failure.exception.code, code)


if __name__ == "__main__":
    unittest.main()
