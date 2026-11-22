"""Shared Program artifact fixtures and assertions for shader tests."""

from __future__ import annotations

import hashlib
from typing import Any


def generic_color_program_artifact(
    key: str,
    slot: int = 0,
    transfer: str = "straight-alpha",
    auxiliary_channel_uses: dict[int, str] | None = None,
    output_channel_use: str = "unproven",
    premultiplied_color_input_slots: tuple[int, ...] = (),
) -> dict[str, Any]:
    auxiliary_channel_uses = auxiliary_channel_uses or {}
    slots = [slot, *sorted(auxiliary_channel_uses)]
    metal = """
#include <metal_stdlib>
using namespace metal;
struct Uniforms {
    float2 mwxRenderSize;
};
vertex float4 mwxGenericVertex(
    uint vertexID [[vertex_id]], constant Uniforms& u [[buffer(8)]]) {
    return float4(0.0);
}
fragment float4 mwxGenericFragment(
    texture2d<float> g_TextureSLOT [[texture(SLOT)]],
    constant Uniforms& u [[buffer(8)]]) {
    return g_TextureSLOT.sample(
        sampler(),
        float2(0.5)
    );
}
""".replace("SLOT", str(slot)).strip() + "\n"
    return {
        "schemaVersion": 10,
        "kind": "scene-generic-shader-program-artifact",
        "backendID": "glslang-spirv-cross-msl-v2",
        "requestKey": key,
        "outputSemantics": "color",
        "program": {
            "metalSource": metal,
            "metalSourceSHA256": hashlib.sha256(metal.encode()).hexdigest(),
            "vertexFunctionName": "mwxGenericVertex",
            "fragmentFunctionName": "mwxGenericFragment",
            "uniformBufferIndex": 8,
            "uniformLayout": {
                "fields": [
                    {
                        "name": "mwxRenderSize",
                        "authoredName": "mwxRenderSize",
                        "type": "float2",
                        "offset": 0,
                    },
                ],
                "byteSize": 16,
            },
            "textureBindings": [
                {
                    "name": f"g_Texture{texture_slot}",
                    "slot": texture_slot,
                    "channelUse": (
                        "unproven" if texture_slot == slot
                        else auxiliary_channel_uses[texture_slot]
                    ),
                }
                for texture_slot in slots
            ],
            "staticLoopWork": 0,
            "premultipliedColorInputSlots": list(
                premultiplied_color_input_slots
            ),
            "fragmentOutputChannelUse": output_channel_use,
            "colorTransfer": {"kind": transfer, "slot": slot},
        },
    }


def assert_default_color_artifact(test_case: Any, artifact: dict[str, Any]) -> None:
    test_case.assertEqual(artifact["schemaVersion"], 10)
    test_case.assertEqual(
        artifact["kind"], "scene-generic-shader-program-artifact"
    )
    test_case.assertEqual(
        artifact["program"]["premultipliedColorInputSlots"], []
    )
    test_case.assertEqual(artifact["outputSemantics"], "color")
