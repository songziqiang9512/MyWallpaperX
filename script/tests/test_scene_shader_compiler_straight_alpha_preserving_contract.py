#!/usr/bin/env python3
"""Bounded external straight-alpha-preserving artifact lowering."""

from __future__ import annotations

from pathlib import Path
import copy
import json
import sys
import tempfile
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
MULTI_BINDINGS = [*BINDINGS, {"name": "g_Texture2", "slot": 2}]
MULTI_FRAGMENT_MSL = FRAGMENT_MSL.replace(
    "texture2d<float> g_Texture0 [[texture(0)]]) {",
    "texture2d<float> g_Texture0 [[texture(0)]],\n"
    "    texture2d<float> g_Texture2 [[texture(2)]]) {",
).replace(
    "float4 filtered = mix(first, second, 0.5);",
    "float4 background = g_Texture2.sample(sampler(), uv);\n"
    "    float4 filtered = mix(background, mix(first, second, 0.5), first.w);",
)
VERTEX_MSL = """#include <metal_stdlib>
using namespace metal;
struct MWXUniforms { float2 mwxRenderSize; };
vertex float4 mwxGenericVertex(
    constant MWXUniforms& uniforms [[buffer(8)]]) {
    return float4(uniforms.mwxRenderSize, 0.0, 1.0);
}
"""


class SceneShaderCompilerStraightAlphaPreservingContractTests(unittest.TestCase):
    def test_signal_boundary_request_to_artifact_preserves_roles(self) -> None:
        uniform = "struct MWXUniforms { float2 mwxRenderSize; };"
        prefix = "#include <metal_stdlib>\nusing namespace metal;\n" + uniform + "\n"
        vertex = prefix + "vertex float4 mwxGenericVertex() { return float4(0.0); }\n"
        cases = [
            ({"kind": "independent-alpha-signal", "slot": 0}, [0], "independent-alpha-signal", """
    float4 carrier = g_Texture0.sample(sampler(), float2(0.5));
    carrier.xyz *= carrier.w;
    carrier.w = 1.0;
    out.mwxFragColor = carrier;
    out.mwxFragColor.w *= 2.5;
"""),
            ({"kind": "independent-alpha-signal-preserving", "slot": 0}, [], "independent-alpha-signal", """
    float4 carrier = g_Texture0.sample(sampler(), uniforms.mwxRenderSize);
    out.mwxFragColor = carrier;
    out.mwxFragColor = boundedInjection(out.mwxFragColor, 0.5);
"""),
            ({"kind": "independent-alpha-signal-compositing", "slots": [0, 1]}, [1], "premultiplied-alpha", """
    float4 pulse = g_Texture0.sample(sampler(), float2(0.5));
    float4 canvas = g_Texture1.sample(sampler(), float2(0.5));
    canvas.xyz = canvas.xyz + pulse.xyz * pulse.w;
    canvas.w = clamp(canvas.w + pulse.w, 0.0, 1.0);
    out.mwxFragColor = canvas;
"""),
            ({"kind": "independent-alpha-signal-underlay-compositing", "slots": [0, 1, 2]}, [1, 2], "premultiplied-alpha", """
    float4 pulse = g_Texture0.sample(sampler(), float2(0.5));
    float4 canvas = g_Texture1.sample(sampler(), float2(0.5));
    float4 underlay = g_Texture2.sample(sampler(), float2(0.5));
    canvas = mix(underlay, canvas, canvas.w);
    canvas.xyz = canvas.xyz + pulse.xyz * pulse.w;
    canvas.w = clamp(canvas.w + pulse.w, 0.0, 1.0);
    out.mwxFragColor = canvas;
"""),
        ]
        helper = compiler_support.SceneShaderCompilerHarnessTests(
            "test_project_fixture_compiles_without_product_authority")
        for expected, color_slots, representation, body in cases:
            with self.subTest(kind=expected["kind"]), tempfile.TemporaryDirectory(
                prefix="mwx-signal-boundary-request-") as directory:
                root = Path(directory)
                tools = list(helper.tools(root))
                bindings = [0] if "slot" in expected else expected["slots"]
                preserving = expected["kind"] == "independent-alpha-signal-preserving"
                helper_source = ("float4 boundedInjection(float4 current, float amount) {\n"
                    "    return fast::min(current + float4(amount), float4(1.0));\n}\n") if preserving else ""
                parameters = "constant MWXUniforms& uniforms [[buffer(8)]]" if preserving else ""
                fragment = prefix + "struct Output { float4 mwxFragColor [[color(0)]]; };\n" \
                    + helper_source + f"fragment Output mwxGenericFragment({parameters}) {{\n    Output out = {{}};\n" \
                    + body + "    return out;\n}\n"
                reflection = {"types": {"_1": {"members": [
                    {"name": "mwxRenderSize", "type": "vec2", "offset": 0}]}},
                    "ubos": [{"type": "_1", "block_size": 8, "set": 0, "binding": 8}],
                    "textures": [{"name": f"g_Texture{slot}", "binding": slot} for slot in bindings]}
                payload = json.dumps({"vertex": vertex, "fragment": fragment, "reflection": reflection})
                payload_path = root / "tool-payload.json"
                payload_path.write_text(payload, encoding="utf-8")
                tools[1] = helper.write_tool(root, "spirv-cross", f"""
                    import json, pathlib, sys
                    if "--version" in sys.argv:
                        print("Git commit: fake-cross-v1")
                        raise SystemExit(0)
                    payload = json.loads(pathlib.Path({str(payload_path)!r}).read_text())
                    output = pathlib.Path(sys.argv[sys.argv.index("--output") + 1])
                    value = json.dumps(payload["reflection"]) if "--reflect" in sys.argv else payload[pathlib.Path(sys.argv[1]).stem]
                    output.write_text(value)
                """)
                manifest = helper.manifest(root, tools[0], tools[1], timeout_ms=10_000)
                request = json.loads(compiler_support.FIXTURE.read_text(encoding="utf-8"))
                request.update(expectedColorTransfer=expected, colorBoundary={
                    "colorInputSlots": color_slots, "outputRepresentation": representation})
                request_path, report, artifact_path = (root / name for name in ("request.json", "report.json", "program.json"))
                request_path.write_text(json.dumps(request), encoding="utf-8")
                result = helper.run_harness(request_path, report, manifest, tuple(tools), artifact_output=artifact_path)
                self.assertEqual(result.returncode, 0, result.stderr)
                artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
                source = artifact["program"]["metalSource"]
                self.assertEqual(artifact["requestKey"], request_cache_key(request))
                self.assertEqual(artifact["program"]["colorBoundary"], request["colorBoundary"])
                self.assertEqual(artifact["program"]["colorTransfer"], expected)
                for slot in color_slots:
                    self.assertIn(f"mwxStraightColorInput(g_Texture{slot}.sample", source)
                if expected["kind"] != "independent-alpha-signal":
                    self.assertNotIn("mwxStraightColorInput(g_Texture0.sample", source)
                if representation == "independent-alpha-signal":
                    self.assertNotIn("out.mwxFragColor = mwxStraightColorOutput", source)
                    self.assertNotIn("out.mwxFragColor = mwxPremultiply", source)
                else:
                    self.assertEqual(source.count("out.mwxFragColor = mwxPremultiply(out.mwxFragColor);"), 1)
                if expected["kind"] == "independent-alpha-signal":
                    self.assertIn("out.mwxFragColor.w *= 2.5;", source)
                invalid_values = [
                    ("colorInputSlots", [] if expected["kind"] == "independent-alpha-signal" else [0],
                        "ordinary-color-signal-role"),
                    ("outputRepresentation", "straight-alpha", "ordinary-color-signal-output"),
                ]
                for field, value, failure in invalid_values:
                    invalid = copy.deepcopy(request)
                    invalid["colorBoundary"][field] = value
                    request_path.write_text(json.dumps(invalid), encoding="utf-8")
                    artifact_path.unlink(missing_ok=True)
                    result = helper.run_harness(request_path, report, manifest, tuple(tools), artifact_output=artifact_path)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(json.loads(result.stderr)["failure"]["code"], failure)
                    self.assertFalse(artifact_path.exists())

    def test_ordinary_boundary_accepts_existing_pma_provider_facts(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{"type": "_1", "block_size": 8, "set": 0, "binding": 8}],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        fragment = FRAGMENT_MSL.replace(
            "    float4 first = g_Texture0.sample(sampler(), uv);\n"
            "    float4 second = g_Texture0.sample(sampler(), uv + float2(0.25));\n"
            "    float4 filtered = mix(first, second, 0.5);\n"
            "    out.mwxFragColor = filtered;",
            "    out.mwxFragColor = g_Texture0.sample(sampler(), uv);",
        )
        arguments = compiler_support.artifact_arguments(reflection, VERTEX_MSL, fragment, "provider")
        boundary = {"colorInputSlots": [0], "outputRepresentation": "straight-alpha"}
        arguments.update(color_boundary=boundary, premultiplied_color_input_slots=[0])
        program = compiler_support.build_program_artifact(**arguments)["program"]
        self.assertEqual(program["colorBoundary"], boundary)
        self.assertEqual(program["premultipliedColorInputSlots"], [0])
        self.assertEqual(program["colorTransfer"], {"kind": "passthrough", "slot": 0})
        self.assertEqual(program["metalSource"].count("mwxStraightColorInput(g_Texture0.sample"), 1)
        dynamic = {**boundary, "signalPassthroughSlot": 0}
        dynamic_program = compiler_support.build_program_artifact(**{**arguments, "color_boundary": dynamic})["program"]
        self.assertEqual(dynamic_program["colorBoundary"], dynamic)
        self.assertIn("out.mwxFragColor = mwxPassthroughColorOutput(out.mwxFragColor, uniforms.mwxPremultipliedColorInputMask, 0u);",
                      dynamic_program["metalSource"])
        self.assertIn("1u << (8u + slot)", dynamic_program["metalSource"])
        request = json.loads(compiler_support.FIXTURE.read_text(encoding="utf-8"))
        self.assertNotEqual(request_cache_key({**request, "colorBoundary": boundary}),
                            request_cache_key({**request, "colorBoundary": dynamic}))
        for slot in [True, -1, 1, 8]:
            with self.subTest(signalSlot=slot), self.assertRaisesRegex(
                compiler_support.ArtifactFailure, "ordinary-color-boundary"):
                compiler_support.build_program_artifact(**{**arguments, "color_boundary": {**dynamic,
                    "signalPassthroughSlot": slot}})
        opaque = fragment.replace("out.mwxFragColor = g_Texture0.sample(sampler(), uv);",
            "float4 sampled = g_Texture0.sample(sampler(), uv);\n"
            "    out.mwxFragColor = float4(sampled.xyz, 1.0);")
        drift = {**arguments, "color_boundary": dynamic,
                 "msl_sources": {**arguments["msl_sources"], "fragment": opaque}}
        with self.assertRaisesRegex(compiler_support.ArtifactFailure, "ordinary-color-signal-passthrough"):
            compiler_support.build_program_artifact(**drift)
        invalid_signal = {**arguments, "color_boundary": {**boundary,
            "outputRepresentation": "independent-alpha-signal"}}
        with self.assertRaisesRegex(compiler_support.ArtifactFailure, "ordinary-color-signal-output"):
            compiler_support.build_program_artifact(**invalid_signal)
        legacy = {**arguments, "color_boundary": None}
        with self.assertRaisesRegex(compiler_support.ArtifactFailure, "premultiplied-color-input-transfer"):
            compiler_support.build_program_artifact(**legacy)
        arguments["premultiplied_color_input_slots"] = [7]
        with self.assertRaisesRegex(compiler_support.ArtifactFailure, "premultiplied-color-input-binding"):
            compiler_support.build_program_artifact(**arguments)

    def test_ordinary_boundary_uses_original_math_and_typed_mask_layout(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{"type": "_1", "block_size": 8, "set": 0, "binding": 8}],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        arguments = compiler_support.artifact_arguments(
            reflection, VERTEX_MSL, FRAGMENT_MSL, "ordinary"
        )
        boundary = {"colorInputSlots": [0], "outputRepresentation": "straight-alpha"}
        arguments.update(expected_color_transfer=EXPECTED, color_boundary=boundary)
        artifact = compiler_support.build_program_artifact(**arguments)
        program = artifact["program"]
        metal = program["metalSource"]
        self.assertEqual(artifact["schemaVersion"], 10)
        self.assertEqual(program["colorBoundary"], boundary)
        self.assertEqual(metal.count("mwxStraightColorInput(g_Texture0.sample"), 2)
        self.assertIn("uniforms.mwxPremultipliedColorInputMask, 0u", metal)
        self.assertIn("float4 filtered = mix(first, second, 0.5);", metal)
        self.assertIn("out.mwxFragColor = filtered;", metal)
        self.assertNotIn("mwxGenericPremultiply", metal)
        self.assertIn("float4(color.xyz, clamp(color.w, 0.0, 1.0))", metal)
        self.assertEqual([field["type"] for field in program["uniformLayout"]["fields"]
                          if field["name"] == "mwxPremultipliedColorInputMask"], ["uint"])
        arguments["color_boundary"] = {**boundary, "outputRepresentation": "premultiplied-alpha"}
        pma = compiler_support.build_program_artifact(**arguments)["program"]["metalSource"]
        self.assertEqual(pma.count("out.mwxFragColor = mwxPremultiply(out.mwxFragColor);"), 1)
        arguments["color_boundary"] = {**boundary, "colorInputSlots": [7]}
        with self.assertRaisesRegex(compiler_support.ArtifactFailure, "ordinary-color-input-binding"):
            compiler_support.build_program_artifact(**arguments)

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
            "schemaVersion": 6,
            "outputSemantics": "color",
            "premultipliedColorInputSlots": [],
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

    def test_program_artifact_lowers_exact_typed_provider_color_slot(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8,
            }],
            "textures": [
                {"name": "g_Texture0", "binding": 0},
                {"name": "g_Texture2", "binding": 2},
            ],
        }
        arguments = compiler_support.artifact_arguments(
            reflection, VERTEX_MSL, MULTI_FRAGMENT_MSL, "s"
        )
        arguments["expected_color_transfer"] = EXPECTED
        arguments["premultiplied_color_input_slots"] = [2]

        artifact = compiler_support.build_program_artifact(**arguments)

        metal = artifact["program"]["metalSource"]
        self.assertEqual(
            metal.count("mwxGenericUnpremultiply(g_Texture0.sample"), 2
        )
        self.assertEqual(
            metal.count("mwxGenericUnpremultiply(g_Texture2.sample"), 1
        )
        self.assertEqual(
            metal.count("mwxGenericPremultiply(out.mwxFragColor)"), 1
        )
        self.assertEqual(
            artifact["program"]["premultipliedColorInputSlots"], [2]
        )

        arguments["premultiplied_color_input_slots"] = [0]
        with self.assertRaisesRegex(
            compiler_support.ArtifactFailure,
            "premultiplied-color-input-double",
        ):
            compiler_support.build_program_artifact(**arguments)

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

        prepared, _ = prepare_independent_signal_contract(
            MULTI_FRAGMENT_MSL, EXPECTED, MULTI_BINDINGS
        )
        self.assertEqual(
            prepared.count("mwxGenericUnpremultiply(g_Texture0.sample"), 2
        )
        self.assertEqual(prepared.count("g_Texture2.sample"), 1)
        self.assertNotIn(
            "mwxGenericUnpremultiply(g_Texture2.sample", prepared
        )


if __name__ == "__main__":
    unittest.main()
