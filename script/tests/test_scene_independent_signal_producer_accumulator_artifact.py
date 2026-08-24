#!/usr/bin/env python3
"""External-artifact independent producer and accumulator source contracts."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_independent_signal_contract import (  # noqa: E402
    IndependentSignalContractFailure,
    PRESERVING_KIND,
    PRODUCER_KIND,
    independent_signal_accumulator_static_loop_work,
    parse_expected_transfer,
    prepare_independent_signal_contract,
)


def bindings(*slots: int) -> list[dict[str, object]]:
    return [
        {"name": f"g_Texture{slot}", "slot": slot, "channelUse": "unknown"}
        for slot in slots
    ]


def producer_msl(
    *,
    source_slot: int = 0,
    source: str = "sourceSignal",
    alpha: str = "sourceAlpha",
    auxiliary_slot: int = 2,
) -> str:
    """SPIRV-Cross-like shape emitted for two equivalent downsample variants."""
    return f"""#include <metal_stdlib>
using namespace metal;

struct MWXFragmentUniforms {{
    float g_NoiseAmount;
    float g_Threshold;
}};
struct FragmentIn {{
    float4 v_NoiseTexCoord [[user(locn0)]];
    float4 v_TexCoord [[user(locn1)]];
}};
struct FragmentOut {{ float4 mwxFragColor [[color(0)]]; }};

static inline __attribute__((always_inline))
float2 sourceCoordinate(
    thread const float2& value,
    constant MWXFragmentUniforms& uniforms) {{
    return value + float2(uniforms.g_NoiseAmount * 0.0);
}}

fragment FragmentOut mwxGenericFragment(
    FragmentIn in [[stage_in]],
    constant MWXFragmentUniforms& uniforms [[buffer(8)]],
    texture2d<float> g_Texture{source_slot} [[texture({source_slot})]],
    texture2d<float> g_Texture{auxiliary_slot} [[texture({auxiliary_slot})]],
    sampler g_Texture{source_slot}Smplr [[sampler({source_slot})]],
    sampler g_Texture{auxiliary_slot}Smplr [[sampler({auxiliary_slot})]]) {{
    FragmentOut out = {{}};
    float4 {source} = g_Texture{source_slot}.sample(
        g_Texture{source_slot}Smplr,
        sourceCoordinate(in.v_TexCoord.xy, uniforms));
    float {alpha} = {source}.w;
    float4 compilerCarrierCopy = {source};
    float3 compilerRGB = compilerCarrierCopy.xyz * {alpha};
    {source}.x = compilerRGB.x;
    {source}.y = compilerRGB.y;
    {source}.z = compilerRGB.z;
    {source}.w = 1.0;
    float noise = g_Texture{auxiliary_slot}.sample(
        g_Texture{auxiliary_slot}Smplr, in.v_NoiseTexCoord.xy).x;
    noise *= g_Texture{auxiliary_slot}.sample(
        g_Texture{auxiliary_slot}Smplr, in.v_NoiseTexCoord.zw).r;
    out.mwxFragColor = {source} * step(
        length({source}.xyz), noise + uniforms.g_Threshold);
    out.mwxFragColor.w *= noise * uniforms.g_NoiseAmount;
    return out;
}}
"""


def accumulator_msl(
    *,
    slot: int = 0,
    helper: str = "collectDirection",
    helper_carrier: str = "weightedSignal",
    sample: str = "sourceValue",
    loop_index: str = "ordinal",
    main_carrier: str = "combinedSignal",
    call_count: int = 4,
    sample_count: int = 8,
) -> str:
    """Actual cast-like SPIRV-Cross helper-loop and raw terminal output shape."""
    calls = "\n".join(
        f"    float4 helperResult{index} = {helper}("
        f"coordinate, direction{index}, uniforms, "
        f"g_Texture{slot}, g_Texture{slot}Smplr);\n"
        f"    {main_carrier} += helperResult{index};"
        for index in range(call_count)
    )
    directions = "\n".join(
        f"    float2 direction{index} = in.v_TexCoord01.zw;"
        for index in range(call_count)
    )
    return f"""#include <metal_stdlib>
using namespace metal;

struct MWXFragmentUniforms {{
    float3 g_ColorRays;
    float g_Intensity;
    float g_Length;
}};
struct FragmentIn {{ float4 v_TexCoord01 [[user(locn0)]]; }};
struct FragmentOut {{ float4 mwxFragColor [[color(0)]]; }};

static inline __attribute__((always_inline))
float2 sourceCoordinate(
    thread const float2& value,
    constant MWXFragmentUniforms& uniforms) {{
    return value + float2(uniforms.g_Length * 0.0);
}}

static inline __attribute__((always_inline))
float4 {helper}(
    float2 coordinate,
    float2 direction,
    constant MWXFragmentUniforms& uniforms,
    texture2d<float> g_Texture{slot},
    sampler g_Texture{slot}Smplr) {{
    float4 {helper_carrier} = float4(0.0);
    direction *= uniforms.g_Length / {sample_count - 1}.0;
    for (int {loop_index} = 0; {loop_index} < {sample_count}; {loop_index}++) {{
        float4 {sample} = g_Texture{slot}.sample(
            g_Texture{slot}Smplr,
            sourceCoordinate(coordinate, uniforms));
        coordinate -= direction;
        {helper_carrier} += ({sample} *
            (float({loop_index}) / {sample_count - 1}.0));
    }}
    return {helper_carrier};
}}

fragment FragmentOut mwxGenericFragment(
    FragmentIn in [[stage_in]],
    constant MWXFragmentUniforms& uniforms [[buffer(8)]],
    texture2d<float> g_Texture{slot} [[texture({slot})]],
    sampler g_Texture{slot}Smplr [[sampler({slot})]]) {{
    FragmentOut out = {{}};
    float2 coordinate = in.v_TexCoord01.xy;
{directions}
    float4 {main_carrier} = float4(0.0);
{calls}
    const float sampleIntensity = 0.1;
    float4 compilerCarrierCopy = {main_carrier};
    float3 compilerRGB = compilerCarrierCopy.xyz *
        float3(uniforms.g_ColorRays);
    {main_carrier}.x = compilerRGB.x;
    {main_carrier}.y = compilerRGB.y;
    {main_carrier}.z = compilerRGB.z;
    out.mwxFragColor = float4(
        uniforms.g_Intensity * sampleIntensity * {main_carrier}.xyz,
        fast::clamp(
            uniforms.g_Intensity * sampleIntensity * {main_carrier}.w,
            0.0, 1.0));
    return out;
}}
"""


def inline_accumulator_msl(
    *,
    slot: int = 0,
    carrier: str = "raySignal",
    sample: str = "sourceTap",
    loop_index: str = "tapIndex",
    bound: str = "tapCount",
    denominator: str = "tapDrop",
    tint_copy: str = "signalCopy",
    tinted_rgb: str = "tintedSignal",
    sample_count: int = 30,
) -> str:
    """SPIRV-Cross-like direct-entry loop with lowered RGB-only tint."""
    return f"""#include <metal_stdlib>
using namespace metal;

struct MWXFragmentUniforms {{
    float3 g_ColorRays;
    float g_Intensity;
    float g_Length;
}};
struct FragmentIn {{ float2 v_TexCoord [[user(locn0)]]; }};
struct FragmentOut {{ float4 mwxFragColor [[color(0)]]; }};

static inline __attribute__((always_inline))
float2 sourceCoordinate(
    thread const float2& value,
    constant MWXFragmentUniforms& uniforms) {{
    return value + float2(uniforms.g_Length * 0.0);
}}

fragment FragmentOut mwxGenericFragment(
    FragmentIn in [[stage_in]],
    constant MWXFragmentUniforms& uniforms [[buffer(8)]],
    texture2d<float> g_Texture{slot} [[texture({slot})]],
    sampler g_Texture{slot}Smplr [[sampler({slot})]]) {{
    FragmentOut out = {{}};
    float2 coordinate = in.v_TexCoord;
    float2 direction = float2(0.25, 0.5);
    float4 {carrier} = float4(0.0);
    const int {bound} = {sample_count};
    const float {denominator} = {bound} - 1;
    direction /= {denominator};
    for (int {loop_index} = 0; {loop_index} < {bound}; ++{loop_index}) {{
        float4 {sample} = g_Texture{slot}.sample(
            g_Texture{slot}Smplr, sourceCoordinate(coordinate, uniforms));
        coordinate -= direction;
        {carrier} += {sample} * (float({loop_index}) / {denominator});
    }}
    const float sampleIntensity = 0.1;
    float4 {tint_copy} = {carrier};
    float3 {tinted_rgb} = {tint_copy}.xyz * float3(uniforms.g_ColorRays);
    {carrier}.x = {tinted_rgb}.x;
    {carrier}.y = {tinted_rgb}.y;
    {carrier}.z = {tinted_rgb}.z;
    out.mwxFragColor = float4(
        uniforms.g_Intensity * sampleIntensity * {carrier}.xyz,
        fast::clamp(
            uniforms.g_Intensity * sampleIntensity * {carrier}.w,
            0.0, 1.0));
    return out;
}}
"""


class IndependentSignalProducerAccumulatorArtifactTests(unittest.TestCase):
    def assert_rejected(
        self,
        source: str,
        expected: dict[str, object],
        reflected_bindings: list[dict[str, object]],
        *,
        code: str | None = None,
        maximum_loop_work: int = 256,
    ) -> None:
        with self.assertRaises(IndependentSignalContractFailure) as context:
            prepare_independent_signal_contract(
                source,
                expected,
                reflected_bindings,
                maximum_loop_work=maximum_loop_work,
            )
        if code is not None:
            self.assertEqual(context.exception.code, code)

    def test_expected_transfer_parser_is_exact_for_both_shared_kinds(self) -> None:
        for kind in (PRODUCER_KIND, PRESERVING_KIND):
            self.assertEqual(
                parse_expected_transfer({"kind": kind, "slot": 3}),
                {"kind": kind, "slot": 3},
            )
        self.assertIsNone(parse_expected_transfer(None))
        accumulator = {
            "kind": PRESERVING_KIND,
            "slot": 3,
            "accumulatorLoopWork": 30,
        }
        self.assertEqual(parse_expected_transfer(accumulator), accumulator)
        malformed = [
            {"kind": PRODUCER_KIND, "slot": True},
            {"kind": PRODUCER_KIND, "slot": 8},
            {"kind": "unresolved", "slot": 0},
            {"kind": PRODUCER_KIND, "slot": 0, "identity": "hidden"},
            {
                "kind": PRODUCER_KIND,
                "slot": 0,
                "accumulatorLoopWork": 30,
            },
            {
                "kind": PRESERVING_KIND,
                "slot": 0,
                "accumulatorLoopWork": True,
            },
            {
                "kind": PRESERVING_KIND,
                "slot": 0,
                "accumulatorLoopWork": 257,
            },
        ]
        for value in malformed:
            with self.subTest(value=value):
                with self.assertRaises(IndependentSignalContractFailure):
                    parse_expected_transfer(value)

    def test_actual_downsample_shapes_wrap_only_unique_whole_sample(self) -> None:
        for auxiliary_slot in (1, 2):
            with self.subTest(auxiliary_slot=auxiliary_slot):
                source = producer_msl(auxiliary_slot=auxiliary_slot)
                prepared, transfer = prepare_independent_signal_contract(
                    source,
                    {"kind": PRODUCER_KIND, "slot": 0},
                    bindings(0, auxiliary_slot),
                )
                self.assertEqual(transfer, {"kind": PRODUCER_KIND, "slot": 0})
                self.assertEqual(
                    prepared.count(
                        "mwxIndependentSignalUnpremultiply(g_Texture0.sample("
                    ),
                    1,
                )
                self.assertIn(
                    "out.mwxFragColor = sourceSignal * step(", prepared
                )
                self.assertIn("out.mwxFragColor.w *= noise", prepared)
                self.assertNotIn(
                    "mwxIndependentSignalUnpremultiply(out.mwxFragColor",
                    prepared,
                )

    def test_producer_is_identifier_and_slot_independent(self) -> None:
        source = producer_msl(
            source_slot=3,
            source="unseenCarrier",
            alpha="rememberedAlpha",
            auxiliary_slot=5,
        )
        prepared, _ = prepare_independent_signal_contract(
            source,
            {"kind": PRODUCER_KIND, "slot": 3},
            bindings(3, 5),
        )
        self.assertIn(
            "mwxIndependentSignalUnpremultiply(g_Texture3.sample(", prepared
        )
        self.assertIn("out.mwxFragColor = unseenCarrier * step(", prepared)

    def test_producer_drift_fails_closed(self) -> None:
        source = producer_msl()
        expected = {"kind": PRODUCER_KIND, "slot": 0}
        drifts = {
            "wrong-slot": source.replace(
                "float4 sourceSignal = g_Texture0.sample(",
                "float4 sourceSignal = g_Texture1.sample(",
            ),
            "second-whole-source": source.replace(
                "    float noise = g_Texture2.sample(",
                "    float4 hiddenColor = g_Texture2.sample(\n"
                "        g_Texture2Smplr, in.v_NoiseTexCoord.xy);\n"
                "    float noise = g_Texture2.sample(",
            ),
            "second-root-write": source.replace(
                "    return out;",
                "    out.mwxFragColor = float4(0.0);\n    return out;",
            ),
            "carrier-multi-write": source.replace(
                "    sourceSignal.w = 1.0;",
                "    sourceSignal.x = compilerRGB.x;\n"
                "    sourceSignal.w = 1.0;",
            ),
            "lowered-rgb-mutation": source.replace(
                "    sourceSignal.x = compilerRGB.x;",
                "    compilerRGB.x = 0.0;\n"
                "    sourceSignal.x = compilerRGB.x;",
            ),
            "branch-drift": source.replace(
                "    sourceSignal.x = compilerRGB.x;",
                "    if (uniforms.g_Threshold > 0.0) {\n"
                "        sourceSignal.x = compilerRGB.x;\n    }",
            ),
            "hidden-output": source.replace(
                "struct FragmentOut { float4 mwxFragColor [[color(0)]]; };",
                "struct FragmentOut { float4 mwxFragColor [[color(0)]]; "
                "float4 hidden [[color(1)]]; };",
            ),
            "output-alias": source.replace(
                "    return out;",
                "    thread float4& hidden = out.mwxFragColor;\n"
                "    hidden = float4(0.0);\n    return out;",
            ),
        }
        for name, drift in drifts.items():
            with self.subTest(name=name):
                self.assert_rejected(drift, expected, bindings(0, 1, 2))

    def test_actual_cast_like_accumulator_preserves_raw_rgba(self) -> None:
        source = accumulator_msl()
        prepared, transfer = prepare_independent_signal_contract(
            source,
            {
                "kind": PRESERVING_KIND,
                "slot": 0,
                "accumulatorLoopWork": 32,
            },
            bindings(0),
        )
        self.assertEqual(prepared, source)
        self.assertEqual(transfer, {"kind": PRESERVING_KIND, "slot": 0})
        self.assertEqual(
            independent_signal_accumulator_static_loop_work(
                source, expected_slot=0, maximum_loop_work=256
            ),
            32,
        )
        self.assertNotIn("Unpremultiply", prepared)
        self.assertIn(
            "sampleIntensity * combinedSignal.w", prepared
        )

    def test_accumulator_is_identifier_and_slot_independent(self) -> None:
        source = accumulator_msl(
            slot=4,
            helper="gatherUnseenDirection",
            helper_carrier="rgbaIntegral",
            sample="wholeTap",
            loop_index="tapIndex",
            main_carrier="rawResult",
            call_count=4,
        )
        prepared, _ = prepare_independent_signal_contract(
            source,
            {
                "kind": PRESERVING_KIND,
                "slot": 4,
                "accumulatorLoopWork": 32,
            },
            bindings(4),
        )
        self.assertEqual(prepared, source)

    def test_accumulator_safety_drift_fails_closed(self) -> None:
        source = accumulator_msl()
        expected = {
            "kind": PRESERVING_KIND,
            "slot": 0,
            "accumulatorLoopWork": 32,
        }
        drifts = {
            "wrong-slot": source.replace("g_Texture0.sample(", "g_Texture1.sample("),
            "second-source": source.replace(
                "        coordinate -= direction;",
                "        float4 hidden = g_Texture1.sample(\n"
                "            g_Texture1Smplr, coordinate);\n"
                "        coordinate -= direction;",
            ),
            "negative-weight": source.replace(
                "(float(ordinal) / 7.0)",
                "(-float(ordinal) / 7.0)",
            ),
            "dynamic-loop": source.replace(
                "ordinal < 8",
                "ordinal < int(uniforms.g_Intensity)",
            ),
            "recursive-helper": source.replace(
                "    return weightedSignal;",
                "    collectDirection(coordinate, direction, uniforms, "
                "g_Texture0, g_Texture0Smplr);\n"
                "    return weightedSignal;",
            ),
            "coordinate-helper-mutation": source.replace(
                "    return value + float2(uniforms.g_Length * 0.0);",
                "    float2 changed = value;\n"
                "    changed.x = 0.0;\n    return changed;",
            ),
            "different-rgb": source.replace(
                "sampleIntensity * combinedSignal.xyz",
                "sampleIntensity * uniforms.g_ColorRays",
            ),
            "different-alpha": source.replace(
                "sampleIntensity * combinedSignal.w",
                "sampleIntensity * uniforms.g_Intensity",
            ),
            "mixed-rgb-source": source.replace(
                "sampleIntensity * combinedSignal.xyz",
                "sampleIntensity * (combinedSignal.xyz + uniforms.g_ColorRays.xyz)",
            ),
            "hidden-output": source.replace(
                "struct FragmentOut { float4 mwxFragColor [[color(0)]]; };",
                "struct FragmentOut { float4 mwxFragColor [[color(0)]]; "
                "float4 hidden [[color(1)]]; };",
            ),
            "branch-drift": source.replace(
                "        weightedSignal += (sourceValue *",
                "        if (ordinal > 0) { weightedSignal += (sourceValue *",
            ).replace(
                "            (float(ordinal) / 7.0));",
                "            (float(ordinal) / 7.0)); }",
            ),
            "hidden-output-alias": source.replace(
                "    return out;",
                "    thread float4& hidden = out.mwxFragColor;\n"
                "    hidden = float4(0.0);\n    return out;",
            ),
        }
        for name, drift in drifts.items():
            with self.subTest(name=name):
                self.assert_rejected(drift, expected, bindings(0, 1))

        over_budget = accumulator_msl(sample_count=64, call_count=5)
        self.assert_rejected(
            over_budget,
            expected,
            bindings(0),
            code="independent-loop-budget",
        )

    def test_direct_entry_accumulator_preserves_one_bounded_raw_rgba_loop(self) -> None:
        source = inline_accumulator_msl()
        prepared, transfer = prepare_independent_signal_contract(
            source,
            {
                "kind": PRESERVING_KIND,
                "slot": 0,
                "accumulatorLoopWork": 30,
            },
            bindings(0),
        )
        self.assertEqual(prepared, source)
        self.assertEqual(transfer, {"kind": PRESERVING_KIND, "slot": 0})
        self.assertEqual(
            independent_signal_accumulator_static_loop_work(
                source,
                expected_slot=0,
                maximum_loop_work=256,
            ),
            30,
        )

    def test_direct_entry_accumulator_is_identifier_and_slot_independent(self) -> None:
        source = inline_accumulator_msl(
            slot=4,
            carrier="unseenIntegral",
            sample="unseenTap",
            loop_index="ordinal",
            bound="sampleLimit",
            denominator="positiveDivisor",
            tint_copy="compilerSnapshot",
            tinted_rgb="coloredIntegral",
        )
        prepared, _ = prepare_independent_signal_contract(
            source,
            {
                "kind": PRESERVING_KIND,
                "slot": 4,
                "accumulatorLoopWork": 30,
            },
            bindings(4),
        )
        self.assertEqual(prepared, source)

    def test_direct_entry_accumulator_accepts_packed_rgb_tint(self) -> None:
        source = inline_accumulator_msl().replace(
            "    float4 signalCopy = raySignal;\n"
            "    float3 tintedSignal = signalCopy.xyz * "
            "float3(uniforms.g_ColorRays);\n"
            "    raySignal.x = tintedSignal.x;\n"
            "    raySignal.y = tintedSignal.y;\n"
            "    raySignal.z = tintedSignal.z;",
            "    raySignal.xyz *= uniforms.g_ColorRays;",
        )
        self.assertEqual(
            independent_signal_accumulator_static_loop_work(
                source,
                expected_slot=0,
                maximum_loop_work=256,
            ),
            30,
        )

    def test_direct_entry_accumulator_accepts_saturate_alpha(self) -> None:
        source = inline_accumulator_msl().replace(
            "fast::clamp(\n"
            "            uniforms.g_Intensity * sampleIntensity * raySignal.w,\n"
            "            0.0, 1.0)",
            "saturate(uniforms.g_Intensity * sampleIntensity * raySignal.w)",
        )
        self.assertEqual(
            independent_signal_accumulator_static_loop_work(
                source,
                expected_slot=0,
                maximum_loop_work=256,
            ),
            30,
        )

    def test_direct_entry_accumulator_safety_drift_fails_closed(self) -> None:
        source = inline_accumulator_msl()
        expected = {
            "kind": PRESERVING_KIND,
            "slot": 0,
            "accumulatorLoopWork": 30,
        }
        drifts = {
            "wrong-slot": source.replace("g_Texture0.sample(", "g_Texture1.sample("),
            "second-source": source.replace(
                "        coordinate -= direction;",
                "        float4 hiddenTap = g_Texture1.sample(\n"
                "            g_Texture1Smplr, coordinate);\n"
                "        coordinate -= direction;",
            ),
            "projected-source": source.replace(
                "            g_Texture0Smplr, sourceCoordinate(coordinate, uniforms));",
                "            g_Texture0Smplr, sourceCoordinate(coordinate, uniforms)).xyz;",
            ),
            "negative-weight": source.replace(
                "float(tapIndex) / tapDrop",
                "-float(tapIndex) / tapDrop",
            ),
            "overweight": source.replace(
                "const float tapDrop = tapCount - 1;",
                "const float tapDrop = tapCount - 2;",
            ),
            "dynamic-loop": source.replace(
                "tapIndex < tapCount",
                "tapIndex < int(uniforms.g_Intensity)",
            ),
            "branch": source.replace(
                "        raySignal += sourceTap *",
                "        if (tapIndex > 0) { raySignal += sourceTap *",
            ).replace(
                "(float(tapIndex) / tapDrop);",
                "(float(tapIndex) / tapDrop); }",
            ),
            "mismatched-alpha": source.replace(
                "uniforms.g_Intensity * sampleIntensity * raySignal.w",
                "uniforms.g_Intensity * raySignal.w",
            ),
            "unclamped-alpha": source.replace(
                "fast::clamp(\n"
                "            uniforms.g_Intensity * sampleIntensity * raySignal.w,\n"
                "            0.0, 1.0)",
                "uniforms.g_Intensity * sampleIntensity * raySignal.w",
            ),
            "extra-carrier-write": source.replace(
                "    float4 signalCopy = raySignal;",
                "    raySignal.w = 0.0;\n    float4 signalCopy = raySignal;",
            ),
            "carrier-escape": source.replace(
                "fragment FragmentOut mwxGenericFragment(",
                "static inline void mutate(thread float4& value) {\n"
                "    value = float4(0.0);\n}\n\n"
                "fragment FragmentOut mwxGenericFragment(",
            ).replace(
                "    const float sampleIntensity = 0.1;",
                "    mutate(raySignal);\n"
                "    const float sampleIntensity = 0.1;",
            ),
            "second-output": source.replace(
                "    return out;",
                "    out.mwxFragColor = float4(0.0);\n    return out;",
            ),
        }
        for name, drift in drifts.items():
            with self.subTest(name=name):
                self.assert_rejected(drift, expected, bindings(0, 1))

        fallback_calls: list[str] = []

        def fallback(
            fragment: str,
            transfer: dict[str, object],
            reflected: list[dict[str, object]],
        ) -> dict[str, object]:
            fallback_calls.append(fragment)
            return transfer

        with self.assertRaises(IndependentSignalContractFailure):
            prepare_independent_signal_contract(
                drifts["second-output"],
                expected,
                bindings(0),
                preserving_fallback=fallback,
            )
        self.assertEqual(fallback_calls, [])

        self.assert_rejected(
            inline_accumulator_msl(sample_count=65),
            expected,
            bindings(0),
            code="independent-accumulator-loop",
        )
        self.assert_rejected(
            source,
            expected,
            bindings(0),
            code="independent-loop-budget",
            maximum_loop_work=29,
        )

    def test_non_accumulator_preserving_shape_uses_existing_carrier(self) -> None:
        legacy = """struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 signal = g_Texture1.sample(g_Texture1Smplr, uv);
    out.mwxFragColor = signal;
    return out;
}
"""
        calls: list[tuple[str, dict[str, object], list[dict[str, object]]]] = []

        def fallback(
            source: str,
            expected: dict[str, object],
            reflected: list[dict[str, object]],
        ) -> dict[str, object]:
            calls.append((source, expected, reflected))
            return expected

        prepared, transfer = prepare_independent_signal_contract(
            legacy,
            {"kind": PRESERVING_KIND, "slot": 1},
            bindings(1),
            preserving_fallback=fallback,
        )
        self.assertEqual(prepared, legacy)
        self.assertEqual(transfer, {"kind": PRESERVING_KIND, "slot": 1})
        self.assertEqual(len(calls), 1)

    def test_source_accumulator_work_cannot_fall_back_to_one_sample(self) -> None:
        lowered_without_loop = """struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 signal = g_Texture1.sample(g_Texture1Smplr, uv);
    out.mwxFragColor = signal;
    return out;
}
"""
        calls: list[str] = []

        def fallback(
            source: str,
            expected: dict[str, object],
            reflected: list[dict[str, object]],
        ) -> dict[str, object]:
            calls.append(source)
            return expected

        expected = {
            "kind": PRESERVING_KIND,
            "slot": 1,
            "accumulatorLoopWork": 30,
        }
        with self.assertRaises(IndependentSignalContractFailure) as context:
            prepare_independent_signal_contract(
                lowered_without_loop,
                expected,
                bindings(1),
                preserving_fallback=fallback,
            )
        self.assertEqual(
            context.exception.code,
            "independent-accumulator-work-mismatch",
        )
        self.assertEqual(calls, [])

        with self.assertRaises(IndependentSignalContractFailure) as mismatch:
            prepare_independent_signal_contract(
                inline_accumulator_msl(),
                {**expected, "slot": 0, "accumulatorLoopWork": 31},
                bindings(0),
                preserving_fallback=fallback,
            )
        self.assertEqual(
            mismatch.exception.code,
            "independent-accumulator-work-mismatch",
        )
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
