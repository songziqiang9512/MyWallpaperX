#!/usr/bin/env python3
"""Shared owner gate for conditional opaque alpha-weighted RGB transforms."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_generic_shader_program_artifact as generic
from script.tests import test_scene_resolved_material_program_derivation as derivation


ROOT = Path(__file__).resolve().parents[2]
PROFILE = "source-proven-graph-input-conditional-opaque-alpha-weighted-rgb"


def ordered_unique(paths: list[Path]) -> list[Path]:
    seen: set[Path] = set()
    result: list[Path] = []
    for path in paths:
        if path not in seen:
            seen.add(path)
            result.append(path)
    return result


SWIFT_SOURCES = ordered_unique([
    *generic.SWIFT_SOURCES,
    *derivation.SWIFT_SOURCES,
])

HARNESS = derivation.SUPPORT + r'''
import Foundation
import Metal

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 probes[4];
void main() {
    gl_Position = vec4(a_Position, 1.0);
    probes[0] = a_TexCoord - vec2(0.1);
    probes[1] = a_TexCoord + vec2(0.1, -0.1);
    probes[2] = a_TexCoord + vec2(-0.1, 0.1);
    probes[3] = a_TexCoord + vec2(0.1);
}
"""

private let authored = """
uniform sampler2D g_Texture0;
uniform float gain;
uniform float enabled;
uniform float radius;
uniform float threshold;
uniform float exponent;
varying vec2 probes[4];
vec3 shape(vec3 color) { return color; }
void main() {
    float total = 0.0;
    vec3 gathered = CAST3(0.0), spare;
    vec4 texel;
    if (gain > 0.001 && enabled > 0.001) {
        for (int probe = 0; probe < 4; ++probe) {
            texel = texSample2D(g_Texture0, probes[probe]);
            gathered += texel.rgb * texel.a;
            total += texel.a;
        }
        gathered = pow(
            shape(saturate(gathered / total - threshold)) * 1.0,
            CAST3(exponent)
        );
    }
    gl_FragColor = vec4(gathered * gain * radius * 0.25, 1.0);
}
"""

private let unseen = """
uniform sampler2D g_Texture3;
uniform float energy;
uniform float active;
uniform float spread;
uniform float cutoff;
uniform float curve;
varying float2 taps[3];
float3 passThrough(float3 value) { return value; }
void main() {
    float alphaSum = 0.0;
    float3 light = float3(0.0);
    float4 value;
    if (energy > 0.01 && active > 0.02) {
        { value = texture2D(g_Texture3, taps[0]); light += value.xyz * value.w; alphaSum += value.w; }
        { value = texture2D(g_Texture3, taps[1]); light += value.xyz * value.w; alphaSum += value.w; }
        { value = texture2D(g_Texture3, taps[2]); light += value.xyz * value.w; alphaSum += value.w; }
        light = pow(passThrough(saturate(light / alphaSum - cutoff)), float3(curve));
    }
    gl_FragColor = float4(light * energy * spread * 0.5, 1.0);
}
"""

private struct Output: Codable {
    let factSlot: Int?
    let factCount: Int?
    let unseenSlot: Int?
    let unseenCount: Int?
    let negativeAccepted: [Bool]
    let boundedTransfer: String
    let boundedUnpremultiplyCount: Int
    let boundedPremultipliesOutput: Bool
    let artifactTransfer: String?
    let artifactFailure: String?
    let artifactSlot: Int?
    let artifactUnpremultiplyCount: Int
    let artifactPremultipliesOutput: Bool
    let profile: String?
    let routeState: String?
    let rollbackOwner: String?
    let permitsSharedFallback: Bool
    let ignoresLegacyRoute: Bool
    let opaqueInputAccepted: Bool
    let premultipliedInputAccepted: Bool
    let straightInputAccepted: Bool
    let dataInputAccepted: Bool
    let unresolvedInputAccepted: Bool
    let missingInputAccepted: Bool
}

private func transferName(_ value: SceneShaderColorTransfer) -> String {
    switch value {
    case let .opaqueFromStraightColor(slot):
        return "opaque-from-straight-color:\(slot)"
    default:
        return "other"
    }
}

private func occurrences(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

private func reflection() -> Data {
    Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32}]}},"ubos":[{"type":"_1","block_size":48,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0}]}"#.utf8)
}

private func builtArtifact(
    vertexSource: String,
    fragmentSource: String
) -> (SceneGenericShaderProgramArtifact?, String?) {
    let vertexMSL = """
    #include <metal_stdlib>
    using namespace metal;
    struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };
    vertex float4 mwxGenericVertex(uint id [[vertex_id]], constant MWXUniforms& u [[buffer(8)]]) {
        return float4(0.0);
    }
    """
    let fragmentMSL = """
    #include <metal_stdlib>
    using namespace metal;
    struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };
    struct Output { float4 mwxFragColor [[color(0)]]; };
    fragment Output mwxGenericFragment(
        texture2d<float> g_Texture0 [[texture(0)]],
        constant MWXUniforms& u [[buffer(8)]]) {
        Output out;
        constexpr sampler s;
        float4 texel;
        float3 gathered = float3(0.0);
        texel = g_Texture0.sample(s, float2(0.1)); gathered += texel.xyz * texel.w;
        texel = g_Texture0.sample(s, float2(0.2)); gathered += texel.xyz * texel.w;
        texel = g_Texture0.sample(s, float2(0.3)); gathered += texel.xyz * texel.w;
        texel = g_Texture0.sample(s, float2(0.4)); gathered += texel.xyz * texel.w;
        out.mwxFragColor = float4(gathered, 1.0);
        return out;
    }
    """
    switch SceneGenericShaderArtifactBuilder.build(
        requestKey: String(repeating: "a", count: 64),
        backendID: "fixture",
        stages: [
            .init(name: "vertex", source: vertexSource,
                  authoredSource: vertexSource, msl: vertexMSL,
                  reflection: reflection()),
            .init(name: "fragment", source: fragmentSource,
                  authoredSource: fragmentSource, msl: fragmentMSL,
                  reflection: reflection()),
        ],
        maximumArtifactBytes: 1_024_000
    ) {
    case let .success(value): return (value, nil)
    case let .failure(failure): return (nil, String(describing: failure))
    }
}

private func accepts(_ content: SceneTextureContent?) -> Bool {
    var facts = Array<SceneResolvedMaterialProgramDerivation.ColorTextureFact?>(
        repeating: nil,
        count: 8
    )
    if let content {
        facts[0] = .init(
            isGraphReference: true,
            isFramebufferInput: true,
            content: content
        )
    }
    return SceneResolvedMaterialProgramDerivation.resolveColor(
        transfer: .opaqueFromStraightColor(textureSlot: 0),
        textureFacts: facts
    )?.fragmentOutput == .opaque
}

@main
private enum Harness {
    static func main() throws {
        let canonical = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: vertex,
            fragment: authored
        )
        let fact = SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer
            .analyze(fragmentSource: canonical.fragment)
        let unseenFact =
            SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer
                .analyze(fragmentSource: unseen)
        let negatives = [
            canonical.fragment.replacingOccurrences(
                of: "total += texel.a", with: "total += texel.r"
            ),
            canonical.fragment.replacingOccurrences(
                of: "gathered / total - threshold",
                with: "gathered / max(0.001, total) - threshold"
            ),
            canonical.fragment.replacingOccurrences(
                of: "return color;", with: "return color * color;"
            ),
            canonical.fragment.replacingOccurrences(
                of: "0.25, 1.0", with: "0.25, 0.5"
            ),
            canonical.fragment.replacingOccurrences(
                of: "shape(saturate", with: "shape(texture2D(g_Texture1, probes[0]).rgb + saturate"
            ),
        ]
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: canonical.fragment
        )
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: canonical.vertex,
            fragmentSource: canonical.fragment,
            provenColorTransfer: transfer
        ).program
        let artifactResult = builtArtifact(
            vertexSource: canonical.vertex,
            fragmentSource: canonical.fragment
        )
        let artifact = artifactResult.0
        let resolution = SceneResolvedMaterialGenericShaderArtifactCache.resolve(
            vertexSource: canonical.vertex,
            fragmentSource: canonical.fragment,
            graphInputTextureSlots: [0],
            activeTextureSlots: [0],
            hasOnlyGraphInputSampler: true,
            sourceColorTransfer: transfer
        )
        let decision: SceneGenericShaderRouteDecision?
        switch resolution {
        case let .accepted(_, _, value), let .ownerDeferred(_, _, value),
             let .unavailable(_, _, _, value):
            decision = value
        }
        let profile = decision.flatMap {
            SceneGenericShaderCapabilityProfile(rawValue: $0.profile)
        }
        let result = Output(
            factSlot: fact?.sourceSlot,
            factCount: fact?.sampleCount,
            unseenSlot: unseenFact?.sourceSlot,
            unseenCount: unseenFact?.sampleCount,
            negativeAccepted: negatives.map {
                SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer
                    .analyze(fragmentSource: $0) != nil
            },
            boundedTransfer: bounded.map { transferName($0.colorTransfer) }
                ?? "missing",
            boundedUnpremultiplyCount: bounded.map {
                occurrences("mwxUnpremultiply(mwxTexture0.sample", in: $0.metalSource)
            } ?? 0,
            boundedPremultipliesOutput:
                bounded?.metalSource.contains("mwxPremultiply(mwxFragColor)")
                    == true,
            artifactTransfer: artifact?.program.colorTransfer.kind,
            artifactFailure: artifactResult.1,
            artifactSlot: artifact?.program.colorTransfer.slot,
            artifactUnpremultiplyCount: artifact.map {
                occurrences(
                    "mwxGenericUnpremultiply(g_Texture0.sample",
                    in: $0.program.metalSource
                )
            } ?? 0,
            artifactPremultipliesOutput:
                artifact?.program.metalSource.contains(
                    "mwxGenericPremultiply(out.mwxFragColor)"
                ) == true,
            profile: decision?.profile,
            routeState: decision?.state,
            rollbackOwner: decision?.fallbackOwner,
            permitsSharedFallback: profile?.permitsBoundedFrontendAfterArtifactFailure(
                routeState: .genericOnly
            ) == true,
            ignoresLegacyRoute: profile?.ignoresLegacyProcessRoute == true,
            opaqueInputAccepted: accepts(.color(.resolved(.opaque))),
            premultipliedInputAccepted:
                accepts(.color(.resolved(.premultipliedAlpha))),
            straightInputAccepted: accepts(.color(.resolved(.straightAlpha))),
            dataInputAccepted: accepts(.data),
            unresolvedInputAccepted: accepts(.color(.unresolved)),
            missingInputAccepted: accepts(nil)
        )
        let data = try JSONEncoder().encode(result)
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneConditionalOpaqueAlphaWeightedRGBOwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-conditional-opaque-alpha-weighted-rgb-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "owner-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-framework", "Metal", "-framework", "Security",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(cls.binary),
            ],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_shared_owner_lowering_route_and_typed_input_contract(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-light-map-route-") as directory:
            root = Path(directory)
            base_environment = os.environ.copy()
            base_environment.update({
                "MWX_SCENE_GENERIC_SHADER_ROUTE": "disable-generic",
                "MWX_SCENE_GENERIC_SHADER_REQUESTS": str(root / "requests"),
                "MWX_SCENE_GENERIC_SHADER_CACHE": str(root / "cache"),
            })
            (root / "requests").mkdir()
            (root / "cache").mkdir()
            default = subprocess.run(
                [str(self.binary)],
                cwd=ROOT,
                env=base_environment,
                capture_output=True,
                text=True,
            )
            rollback_environment = dict(base_environment)
            rollback_environment["MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES"] = (
                f"{PROFILE}=disable-generic"
            )
            completed = subprocess.run(
                [str(self.binary)], cwd=ROOT, env=rollback_environment,
                capture_output=True, text=True,
            )
        self.assertEqual(default.returncode, 0, default.stderr)
        default_value = json.loads(default.stdout)
        self.assertEqual(default_value["profile"], PROFILE)
        self.assertEqual(default_value["routeState"], "generic-only")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        value = json.loads(completed.stdout)
        self.assertEqual((value["factSlot"], value["factCount"]), (0, 4))
        self.assertEqual((value["unseenSlot"], value["unseenCount"]), (3, 3))
        self.assertEqual(value["negativeAccepted"], [False] * 5)
        self.assertEqual(value["boundedTransfer"], "opaque-from-straight-color:0")
        self.assertEqual(value["boundedUnpremultiplyCount"], 4)
        self.assertFalse(value["boundedPremultipliesOutput"])
        self.assertIsNone(value.get("artifactFailure"), value)
        self.assertEqual(value["artifactTransfer"], "opaque-from-straight-color")
        self.assertEqual(value["artifactSlot"], 0)
        self.assertEqual(value["artifactUnpremultiplyCount"], 4)
        self.assertFalse(value["artifactPremultipliesOutput"])
        self.assertEqual(value["profile"], PROFILE)
        self.assertEqual(value["routeState"], "disable-generic")
        self.assertEqual(value["rollbackOwner"], "bounded-frontend")
        self.assertTrue(value["permitsSharedFallback"])
        self.assertTrue(value["ignoresLegacyRoute"])
        self.assertTrue(value["opaqueInputAccepted"])
        self.assertTrue(value["premultipliedInputAccepted"])
        for key in (
            "straightInputAccepted", "dataInputAccepted",
            "unresolvedInputAccepted", "missingInputAccepted",
        ):
            self.assertFalse(value[key], value)


if __name__ == "__main__":
    unittest.main()
