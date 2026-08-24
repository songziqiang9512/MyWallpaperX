#!/usr/bin/env python3
"""Bounded external straight-alpha-preserving artifact lowering."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_artifact import request_cache_key  # noqa: E402
from scene_shader_compiler_color_transfer_contract import (  # noqa: E402
    IndependentSignalContractFailure,
    parse_expected_transfer,
    prepare_independent_signal_contract,
)
from script.tests import test_scene_shader_compiler_harness as compiler_support  # noqa: E402


EXPECTED = {"kind": "straight-alpha-preserving", "slot": 0}
BINDINGS = [{"name": "g_Texture0", "slot": 0}]
FRAGMENT_MSL = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; };
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment(
    constant MWXUniforms& uniforms [[buffer(8)]],
    texture2d<float> g_Texture0 [[texture(0)]]) {
    Output out = {};
    float2 uv = uniforms.mwxRenderSize * 0.0;
    float4 first = g_Texture0.sample(sampler(), uv);
    float4 second = g_Texture0.sample(sampler(), uv + float2(0.25));
    float4 filtered = mix(first, second, 0.5);
    out.mwxFragColor = filtered;
    return out;
}
"""
VERTEX_MSL = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; };
vertex float4 mwxGenericVertex(
    constant MWXUniforms& uniforms [[buffer(8)]]) {
    return float4(uniforms.mwxRenderSize, 0.0, 1.0);
}
"""


class SceneShaderCompilerStraightAlphaPreservingContractTests(unittest.TestCase):
    def test_contract_wraps_every_sample_and_one_terminal_output(self) -> None:
        self.assertEqual(parse_expected_transfer(EXPECTED), EXPECTED)

        prepared, transfer = prepare_independent_signal_contract(
            FRAGMENT_MSL, EXPECTED, BINDINGS
        )

        self.assertEqual(transfer, EXPECTED)
        self.assertEqual(
            prepared.count("mwxGenericUnpremultiply(g_Texture0.sample"), 2
        )
        self.assertEqual(
            prepared.count(
                "out.mwxFragColor = "
                "mwxGenericPremultiply(out.mwxFragColor);"
            ),
            1,
        )
        self.assertEqual(
            prepared.count("inline float4 mwxGenericUnpremultiply"), 1
        )
        self.assertEqual(prepared.count("inline float4 mwxGenericPremultiply"), 1)
        self.assertIn(
            "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);\n"
            "    return out;",
            prepared,
        )

    def test_program_artifact_accepts_only_the_exact_expected_transfer(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8,
            }],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        arguments = compiler_support.artifact_arguments(
            reflection, VERTEX_MSL, FRAGMENT_MSL, "s"
        )
        arguments["expected_color_transfer"] = EXPECTED

        artifact = compiler_support.build_program_artifact(**arguments)

        self.assertEqual(artifact["program"]["colorTransfer"], EXPECTED)
        metal = artifact["program"]["metalSource"]
        self.assertEqual(
            metal.count("mwxGenericUnpremultiply(g_Texture0.sample"), 2
        )
        self.assertEqual(
            metal.count("mwxGenericPremultiply(out.mwxFragColor)"), 1
        )

        request = {
            "schemaVersion": 4,
            "outputSemantics": "color",
            "stages": [
                {"stage": "vertex", "source": "void main() {}"},
                {"stage": "fragment", "source": "void main() {}"},
            ],
            "expectedColorTransfer": EXPECTED,
        }
        independent = {
            **request,
            "expectedColorTransfer": {
                "kind": "independent-alpha-signal-preserving",
                "slot": 0,
            },
        }
        self.assertNotEqual(request_cache_key(request), request_cache_key(independent))

    def test_malformed_expected_transfer_is_rejected(self) -> None:
        malformed = [
            {"kind": "straight-alpha-preserving", "slot": True},
            {"kind": "straight-alpha-preserving", "slot": 8},
            {"kind": "straight-alpha-preserving", "slot": 0, "slots": [0]},
        ]
        for value in malformed:
            with self.subTest(value=value):
                with self.assertRaisesRegex(
                    IndependentSignalContractFailure,
                    "expected-color-transfer",
                ):
                    parse_expected_transfer(value)

    def test_binding_sample_helper_return_and_output_drift_fail_closed(self) -> None:
        drift = {
            "helper-collision": (
                FRAGMENT_MSL.replace(
                    "struct Output",
                    "float4 mwxGenericPremultiply(float4 value) { "
                    "return value; }\nstruct Output",
                ),
                BINDINGS,
                "straight-alpha-preserving-helper",
            ),
            "wrong-slot": (
                FRAGMENT_MSL.replace(
                    "float4 second = g_Texture0.sample",
                    "float4 second = g_Texture1.sample",
                ),
                BINDINGS,
                "straight-alpha-preserving-slot",
            ),
            "extra-binding": (
                FRAGMENT_MSL,
                [*BINDINGS, {"name": "g_Texture1", "slot": 1}],
                "straight-alpha-preserving-binding",
            ),
            "extra-sampler": (
                FRAGMENT_MSL.replace(
                    "float4 filtered =",
                    "float4 hidden = otherTexture.sample(sampler(), uv);\n"
                    "    float4 filtered =",
                ),
                BINDINGS,
                "straight-alpha-preserving-sample",
            ),
            "early-return": (
                FRAGMENT_MSL.replace(
                    "return out;",
                    "return out;\n    float4 unreachable = first;",
                ),
                BINDINGS,
                "straight-alpha-preserving-return",
            ),
            "component-output": (
                FRAGMENT_MSL.replace(
                    "out.mwxFragColor = filtered;",
                    "out.mwxFragColor.xyz = filtered.xyz;",
                ),
                BINDINGS,
                "straight-alpha-preserving-output",
            ),
            "compound-output": (
                FRAGMENT_MSL.replace(
                    "out.mwxFragColor = filtered;",
                    "out.mwxFragColor += filtered;",
                ),
                BINDINGS,
                "straight-alpha-preserving-output",
            ),
            "output-read": (
                FRAGMENT_MSL.replace(
                    "return out;",
                    "float alpha = out.mwxFragColor.w;\n    return out;",
                ),
                BINDINGS,
                "straight-alpha-preserving-output",
            ),
        }
        for name, (source, bindings, code) in drift.items():
            with self.subTest(name=name):
                with self.assertRaisesRegex(
                    IndependentSignalContractFailure, code
                ):
                    prepare_independent_signal_contract(
                        source, EXPECTED, bindings
                    )


if __name__ == "__main__":
    unittest.main()
