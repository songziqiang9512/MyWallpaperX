#!/usr/bin/env python3

"""Fail-closed color-transfer proofs from the emitted shader syntax unit."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderRuntimeLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderDeadBindingAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderTextureChannelAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBuiltInVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFunctionSemantics.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter+Translation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer+Syntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderConditionalAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderWholeVectorAffineParser.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightWholeColorFilterAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightWholeColorFilterAnalyzer+Syntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOverlayAlphaBlendAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStraightBlendOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
]


HARNESS = r'''
import Foundation

private func fragment(_ body: String, helpers: String = "") -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform float g_ScalarWeight;
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return mix(base, (blend), opacity);
    }
    vec3 AdditiveBlend(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        return base + blend * opacity;
    }
    float PreserveAlpha(float base, float changed, float opacity) {
        float preserved = base;
        return mix(base, preserved, opacity);
    }
    float ReplaceAlpha(float base, float changed, float opacity) {
        float replacement = changed;
        return mix(base, replacement, opacity);
    }
    \(helpers)
    void main() {
        \(body)
    }
    """
}

private func program(_ body: String, helpers: String = "") -> SceneAuthoredShaderProgram? {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        v_TexCoord = a_TexCoord;
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    return SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment(body, helpers: helpers)
    ).program
}

private func transfer(_ body: String, helpers: String = "") -> String {
    let result = program(body, helpers: helpers)?.colorTransfer ?? .unresolved
    switch result {
    case .opaque: return "opaque"
    case .unresolved: return "unresolved"
    case .passthrough(let slot): return "slot:\(slot)"
    case .straightAlphaPreserving(let slot):
        return "straight-preserving-slot:\(slot)"
    case .straightAlpha(let slot): return "straight-slot:\(slot)"
    case .straightAlphaUNorm(let slot): return "straight-unorm-slot:\(slot)"
    case .independentAlphaSignal(let slot): return "signal-slot:\(slot)"
    case .independentAlphaSignalPreserving(let slot):
        return "signal-preserving-slot:\(slot)"
    case .independentAlphaSignalCompositing(let signal, let color):
        return "signal-composite:\(signal):\(color)"
    case .premultipliedAlpha: return "premultiplied-alpha"
    }
}

private func metal(_ body: String, helpers: String = "") -> String {
    program(body, helpers: helpers)?.metalSource ?? ""
}

@main
enum Harness {
    static func main() throws {
        let result: [String: String] = [
            "directTexture0": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
            ),
            "directTexture1": transfer(
                "gl_FragColor = texSample2D(g_Texture1, v_TexCoord * 0.5);"
            ),
            "directTexture2D": transfer(
                "gl_FragColor = texture2D(g_Texture0, v_TexCoord);"
            ),
            "opaque": transfer(
                "vec3 total = vec3(0.2); gl_FragColor = vec4(total, 1.0);"
            ),
            "closedControlFlowOpaque": transfer(
                "vec3 total = vec3(0.2); " +
                "for (int index = 0; index < 2; index++) { " +
                "if (index > 0) { total += vec3(0.1); } " +
                "} gl_FragColor = vec4(total, 1.0);"
            ),
            "closedConditionalPassthrough": transfer(
                "float scale = 1.0; " +
                "if (v_TexCoord.x > 0.5) { scale = 0.5; } " +
                "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);"
            ),
            "conditionalAlphaPreserving": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "changed.rgb = mix(source.rgb, changed.rgb, g_ScalarWeight); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source;"
            ),
            "conditionalGeneratedRGB": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = vec4(0.25); changed.rgb = vec3(0.75); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else { gl_FragColor = source; }"
            ),
            "conditionalAlphaPreservingMetal": metal(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "changed.rgb = mix(source.rgb, changed.rgb, g_ScalarWeight); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source;"
            ),
            "conditionalDifferentSlot": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture1, v_TexCoord); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source;"
            ),
            "conditionalNonIdentityAlpha": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "changed.a = ReplaceAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source;"
            ),
            "conditionalAlphaRewrittenAfterJoin": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "changed.a *= 0.5; gl_FragColor = changed; " +
                "} else gl_FragColor = source;"
            ),
            "conditionalGuardedAlphaJoin": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "if (source.r > 0.0) changed.a = " +
                "PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source;"
            ),
            "conditionalTrailingStatement": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "if (g_ScalarWeight > 0.0) { " +
                "vec4 changed = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "changed.a = PreserveAlpha(source.a, changed.a, g_ScalarWeight); " +
                "gl_FragColor = changed; } else gl_FragColor = source; " +
                "g_ScalarWeight;"
            ),
            "straightAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 0.5; " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "straightRGBFactoredAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float coverage = 0.5; " +
                "float alpha = color.a * coverage * g_ScalarWeight; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBFactoredAlphaMetal": metal(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float coverage = 0.5; " +
                "float alpha = color.a * coverage * g_ScalarWeight; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBSafeHelper": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float coverage = SafeCoverage(g_ScalarWeight); " +
                "float alpha = color.a * coverage; " +
                "gl_FragColor = vec4(color.rgb, alpha);",
                helpers: "float SafeCoverage(float value) { " +
                    "float scaled = value * 0.5; " +
                    "return smoothstep(0.0, 1.0, scaled); }"
            ),
            "straightRGBReplacedAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float alpha = g_ScalarWeight * 0.5; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBAdditiveAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float alpha = color.a * g_ScalarWeight + 0.1; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBConditionalAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float factor = 0.5; if (g_ScalarWeight > 0.5) factor = 1.0; " +
                "float alpha = color.a * factor; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBExtraSample": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float factor = texSample2D(g_Texture1, v_TexCoord).r; " +
                "float alpha = color.a * factor; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBMutatedColor": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "color.rgb *= 0.5; float alpha = color.a * g_ScalarWeight; " +
                "gl_FragColor = vec4(color.rgb, alpha);"
            ),
            "straightRGBHiddenHelperSample": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float factor = HiddenSampleFactor(); " +
                "float alpha = color.a * factor; " +
                "gl_FragColor = vec4(color.rgb, alpha);",
                helpers: "float HiddenSampleFactor() { " +
                    "return texSample2D(g_Texture1, v_TexCoord).r; }"
            ),
            "straightRGBHiddenHelperConditional": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float factor = HiddenConditionalFactor(g_ScalarWeight); " +
                "float alpha = color.a * factor; " +
                "gl_FragColor = vec4(color.rgb, alpha);",
                helpers: "float HiddenConditionalFactor(float value) { " +
                    "if (value > 0.5) return 1.0; return value; }"
            ),
            "straightRGBHiddenHelperMutation": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float factor = g_ScalarWeight; " +
                "float adjusted = HiddenMutatingFactor(factor); " +
                "float alpha = color.a * adjusted; " +
                "gl_FragColor = vec4(color.rgb, alpha);",
                helpers: "float HiddenMutatingFactor(inout float value) { " +
                    "value *= 0.5; return value; }"
            ),
            "straightBlendReplacement": transfer(
                "float weight = 0.5; vec3 finalColor = vec3(0.8); " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "finalColor = ApplyBlending(0, mix(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = weight; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "straightBlendDifferentAlpha": transfer(
                "float weight = 0.5; vec3 finalColor = vec3(0.8); " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "finalColor = ApplyBlending(0, mix(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = weight * 0.5; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "straightBlendExtraSample": transfer(
                "float weight = texSample2D(g_Texture1, v_TexCoord).r; " +
                "vec3 finalColor = vec3(0.8); " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "finalColor = ApplyBlending(0, mix(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = weight; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "straightBlendMetal": metal(
                "float weight = 0.5; vec3 finalColor = vec3(0.8); " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "finalColor = ApplyBlending(0, mix(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = weight; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "overlayAlphaBlend": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float mask = 1.0; " +
                "float weight = mask * g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendMetal": metal(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float mask = 1.0; " +
                "float weight = mask * g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendWrongHelper": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = AdditiveBlend(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendSameSlot": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendWeightWithoutAlpha": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * 0.5; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendNonzeroMode": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(1, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendBaseAlpha": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = base.a * overlay.a; gl_FragColor = base;"
            ),
            "overlayAlphaBlendExtraSample": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float extra = texSample2D(g_Texture1, v_TexCoord * 0.5).r; " +
                "float weight = extra * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendMultipleWrites": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.rgb = overlay.rgb; " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "overlayAlphaBlendConditionalAlpha": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "if (g_ScalarWeight > 0.0) base.a = overlay.a * 0.5; " +
                "gl_FragColor = base;"
            ),
            "overlayAlphaBlendOverlayMutation": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "overlay.rgb *= 0.5; float weight = g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "closedControlFlowStraightAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 1.0; " +
                "for (int index = 0; index < 2; index++) { " +
                "if (index > 0) { mask *= 0.5; } } " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "modifiedStraightLocal": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "color.a *= 0.5; gl_FragColor = vec4(color.rgb, color.a);"
            ),
            "mutatedLocalOutput": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float delta = dot(color.rgb, vec3(1.0)); " +
                "color.a *= delta; gl_FragColor = color;"
            ),
            "sameSlotScalarMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "gl_FragColor = mix(texSample2D(g_Texture0, " +
                "v_TexCoord * 0.5), gl_FragColor, mask);"
            ),
            "sameSlotUniformMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = mix(gl_FragColor, texSample2D(g_Texture0, " +
                "v_TexCoord * 0.5), g_ScalarWeight);"
            ),
            "sameSlotAliasReplacement": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "vec4 shifted = texSample2D(g_Texture0, v_TexCoord + mask); " +
                "base = shifted; gl_FragColor = base;"
            ),
            "nestedSameSlotMixGraph": transfer(
                "float phase = texSample2D(g_Texture1, v_TexCoord).r; " +
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 flow = mix(texSample2D(g_Texture0, v_TexCoord * 0.5), " +
                "texSample2D(g_Texture0, v_TexCoord * 0.75), v_TexCoord.x); " +
                "vec4 second = mix(texSample2D(g_Texture0, v_TexCoord + 0.1), " +
                "texSample2D(g_Texture0, v_TexCoord + 0.2), v_TexCoord.y); " +
                "flow = mix(flow, second, smoothstep(0.2, 0.8, phase)); " +
                "gl_FragColor = mix(base, flow, length(v_TexCoord));"
            ),
            "nestedDifferentSlotMixGraph": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 flow = mix(texSample2D(g_Texture0, v_TexCoord * 0.5), " +
                "texSample2D(g_Texture1, v_TexCoord * 0.75), v_TexCoord.x); " +
                "gl_FragColor = mix(base, flow, g_ScalarWeight);"
            ),
            "conditionalNestedMixGraph": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 flow = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "if (g_ScalarWeight > 0.5) { " +
                "flow = mix(flow, base, g_ScalarWeight); } " +
                "gl_FragColor = mix(base, flow, g_ScalarWeight);"
            ),
            "differentSlotAliasReplacement": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 shifted = texSample2D(g_Texture1, v_TexCoord); " +
                "base = shifted; gl_FragColor = base;"
            ),
            "conditionalAliasReplacement": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 shifted = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "if (g_ScalarWeight > 0.5) { base = shifted; } " +
                "gl_FragColor = base;"
            ),
            "modifiedAliasReplacement": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 shifted = texSample2D(g_Texture0, v_TexCoord * 0.5); " +
                "shifted.rgb *= 0.5; base = shifted; gl_FragColor = base;"
            ),
            "wholeColorFilter": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord); " +
                "if (mask > 0.1) source = Sharpen(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "uniform vec2 g_TexelSize; " +
                    "uniform float g_Strength; " +
                    "vec4 Sharpen(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 upperLeft = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, -1.0)); " +
                    "vec4 upper = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(0.0, -1.0)); " +
                    "vec4 upperRight = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, -1.0)); " +
                    "vec4 left = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, 0.0)); " +
                    "vec4 right = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, 0.0)); " +
                    "vec4 lowerLeft = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, 1.0)); " +
                    "vec4 lower = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(0.0, 1.0)); " +
                    "vec4 lowerRight = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, 1.0)); " +
                    "vec4 lowpass = (upperLeft + upperRight + lowerLeft + " +
                    "lowerRight + 2.0 * (upper + left + right + lower) + " +
                    "4.0 * center) / 16.0; " +
                    "vec4 filtered = (1.0 + g_Strength * mask) * center - " +
                    "g_Strength * mask * lowpass; " +
                    "return filtered; }"
            ),
            "wholeColorFilterMetal": metal(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord); " +
                "if (mask > 0.1) source = Sharpen(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "uniform vec2 g_TexelSize; " +
                    "uniform float g_Strength; " +
                    "vec4 Sharpen(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 upperLeft = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, -1.0)); " +
                    "vec4 upper = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(0.0, -1.0)); " +
                    "vec4 upperRight = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, -1.0)); " +
                    "vec4 left = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, 0.0)); " +
                    "vec4 right = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, 0.0)); " +
                    "vec4 lowerLeft = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(-1.0, 1.0)); " +
                    "vec4 lower = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(0.0, 1.0)); " +
                    "vec4 lowerRight = texSample2D(g_Texture0, " +
                    "uv + g_TexelSize * vec2(1.0, 1.0)); " +
                    "vec4 lowpass = (upperLeft + upperRight + lowerLeft + " +
                    "lowerRight + 2.0 * (upper + left + right + lower) + " +
                    "4.0 * center) / 16.0; " +
                    "vec4 filtered = (1.0 + g_Strength * mask) * center - " +
                    "g_Strength * mask * lowpass; " +
                    "return filtered; }"
            ),
            "wholeColorFilterDifferentSlot": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "if (mask > 0.1) source = MixedFilter(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "vec4 MixedFilter(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 left = texSample2D(g_Texture1, uv - vec2(0.1)); " +
                    "vec4 filtered = center - mask * left; return filtered; }"
            ),
            "wholeColorFilterComponentWrite": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "if (mask > 0.1) source = ComponentFilter(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "vec4 ComponentFilter(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 left = texSample2D(g_Texture0, uv - vec2(0.1)); " +
                    "center.rgb -= left.rgb * mask; return center; }"
            ),
            "wholeColorFilterDynamicDivision": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "if (mask > 0.1) source = DividingFilter(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "vec4 DividingFilter(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 left = texSample2D(g_Texture0, uv - vec2(0.1)); " +
                    "vec4 filtered = (center - left) / mask; return filtered; }"
            ),
            "wholeColorFilterHiddenMutation": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "Mutate(source); " +
                "if (mask > 0.1) source = Filter(v_TexCoord, mask); " +
                "gl_FragColor = source;",
                helpers: "void Mutate(inout vec4 value) { value.a = 0.0; } " +
                    "vec4 Filter(vec2 uv, float mask) { " +
                    "vec4 center = texSample2D(g_Texture0, uv); " +
                    "vec4 left = texSample2D(g_Texture0, uv - vec2(0.1)); " +
                    "vec4 filtered = center - mask * left; return filtered; }"
            ),
            "opaqueInputRGBTransform": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.rgb = vec3(0.25); " +
                "gl_FragColor = saturate(color);"
            ),
            "alphaPreservingRGBMix": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec3 shifted = vec3(0.25); float mask = " +
                "texSample2D(g_Texture1, v_TexCoord).r; " +
                "color.rgb = mix(color, shifted, mask); " +
                "gl_FragColor = color;"
            ),
            "alphaPreservingRGBMixMetal": metal(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec3 shifted = vec3(0.25); float mask = " +
                "texSample2D(g_Texture1, v_TexCoord).r; " +
                "color.rgb = mix(color, shifted, mask); " +
                "gl_FragColor = color;"
            ),
            "alphaPreservingMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.rgb = vec3(0.25); " +
                "gl_FragColor = saturate(color);"
            ),
            "opaqueInputAlphaWrite": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color.a *= 0.5; " +
                "gl_FragColor = saturate(color);"
            ),
            "opaqueInputWholeWrite": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; color = vec4(1.0); " +
                "gl_FragColor = saturate(color);"
            ),
            "independentSignal": transfer(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= sample.a; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5; gl_FragColor.a *= 0.25;"
            ),
            "independentSignalPreserving": transfer(
                "vec4 total = vec4(0.0); " +
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "total += sample * 0.5; total.rgb *= vec3(0.5); " +
                "gl_FragColor = total;"
            ),
            "independentSignalComposite": transfer(
                "vec4 rays = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = texSample2D(g_Texture1, v_TexCoord); " +
                "color.rgb = ApplyBlending(9, color.rgb, rays.rgb, rays.a); " +
                "color.a += rays.a; gl_FragColor = color;"
            ),
            "premultipliedAdditive": transfer(
                "float weight = 0.5; vec3 tint = vec3(0.8); " +
                "vec4 color = CAST4(0.0); " +
                "color.rgb = ApplyBlending(31, color.rgb, tint, weight); " +
                "color.a = max(color.a, weight); gl_FragColor = color;"
            ),
            "premultipliedWrongBase": transfer(
                "float weight = 0.5; vec3 tint = vec3(0.8); " +
                "vec4 color = vec4(0.0); " +
                "color.rgb = ApplyBlending(0, tint, color.rgb, weight); " +
                "color.a = max(color.a, weight); gl_FragColor = color;"
            ),
            "premultipliedDifferentWeight": transfer(
                "float weight = 0.5; vec3 tint = vec3(0.8); " +
                "vec4 color = vec4(0.0); " +
                "color.rgb = ApplyBlending(31, color.rgb, tint, weight); " +
                "color.a = max(color.a, 0.25); gl_FragColor = color;"
            ),
            "premultipliedNonzeroBase": transfer(
                "float weight = 0.5; vec3 tint = vec3(0.8); " +
                "vec4 color = vec4(0.1); " +
                "color.rgb = ApplyBlending(31, color.rgb, tint, weight); " +
                "color.a = max(color.a, weight); gl_FragColor = color;"
            ),
            "premultipliedExtraWrite": transfer(
                "float weight = 0.5; vec3 tint = vec3(0.8); " +
                "vec4 color = vec4(0.0); " +
                "color.rgb = ApplyBlending(31, color.rgb, tint, weight); " +
                "color.rgb *= 0.5; color.a = max(color.a, weight); " +
                "gl_FragColor = color;"
            ),
            "invalidIndependentSignal": transfer(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= 0.5; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5;"
            ),
            "differentSlotMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = 0.5; gl_FragColor = mix(gl_FragColor, " +
                "texSample2D(g_Texture1, v_TexCoord), mask);"
            ),
            "vectorWeightMix": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 mask = vec4(0.5); gl_FragColor = mix(gl_FragColor, " +
                "texSample2D(g_Texture0, v_TexCoord), mask);"
            ),
            "straightRGBMath": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb * 0.5, color.a * 0.5);"
            ),
            "mixedSampleAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 other = texSample2D(g_Texture1, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb, color.a * other.a);"
            ),
            "sampledMaskAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "gl_FragColor = vec4(color.rgb, color.a * mask);"
            ),
            "mutatedSampledMaskAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "color.a *= mask * g_ScalarWeight; gl_FragColor = color;"
            ),
            "repeatedAuxiliarySample": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "mask *= texSample2D(g_Texture1, v_TexCoord * 0.5).r; " +
                "color.a *= mask; gl_FragColor = color;"
            ),
            "maskedRGBWrite": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "color.rgb *= mask; color.a *= mask; gl_FragColor = color;"
            ),
            "arithmetic": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * 0.5;"
            ),
            "localAlpha": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); c.a = 0.5; gl_FragColor = c;"
            ),
            "conditionalLocalAlpha": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "if (v_TexCoord.x > 0.5) { c.a *= 0.5; } gl_FragColor = c;"
            ),
            "localRGBWrite": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c.rgb *= 0.5; c.a *= 0.5; gl_FragColor = c;"
            ),
            "multipleLocalAlphaWrites": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c.a *= 0.5; c.a += 0.1; gl_FragColor = c;"
            ),
            "wholeLocalWrite": transfer(
                "vec4 c = texSample2D(g_Texture0, v_TexCoord); " +
                "c = vec4(1.0); c.a *= 0.5; gl_FragColor = c;"
            ),
            "multipleWrites": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); gl_FragColor = vec4(1.0);"
            ),
            "componentWrite": transfer(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord); gl_FragColor.a = 1.0;"
            ),
            "conditionalOpaque": transfer(
                "if (v_TexCoord.x > 0.5) gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "loopControlledOpaque": transfer(
                "for (int index = 0; index < 2; index++) " +
                "gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "earlyReturn": transfer(
                "if (v_TexCoord.x < 0.0) return; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "discardedBranch": transfer(
                "if (v_TexCoord.x < 0.0) discard; gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);"
            ),
            "straightMetal": metal(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "gl_FragColor = vec4(color.rgb, color.a * 0.5);"
            ),
            "passthroughMetal": metal(
                "gl_FragColor = texSample2D(g_Texture0, v_TexCoord);"
            ),
            "opaqueMetal": metal(
                "gl_FragColor = vec4(0.2, 0.3, 0.4, 1.0);"
            ),
            "independentSignalMetal": metal(
                "vec4 sample = texSample2D(g_Texture0, v_TexCoord); " +
                "sample.rgb *= sample.a; sample.a = 1.0; " +
                "gl_FragColor = sample * 0.5;"
            ),
            "independentCompositeMetal": metal(
                "vec4 rays = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = texSample2D(g_Texture1, v_TexCoord); " +
                "color.rgb = ApplyBlending(9, color.rgb, rays.rgb, rays.a); " +
                "color.a += rays.a; gl_FragColor = color;"
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShaderColorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-shader-color-transfer-"
        )
        temporary = Path(cls.temporary_directory.name)
        harness = temporary / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "shader-color-transfer"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True, env=environment
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_direct_sample_proves_only_the_sampled_slot(self) -> None:
        self.assertEqual(self.result["directTexture0"], "slot:0")
        self.assertEqual(self.result["directTexture1"], "slot:1")
        self.assertEqual(self.result["directTexture2D"], "slot:0")

    def test_literal_one_alpha_proves_only_opaque_output(self) -> None:
        self.assertEqual(self.result["opaque"], "opaque")

    def test_closed_control_flow_does_not_hide_root_output(self) -> None:
        self.assertEqual(self.result["closedControlFlowOpaque"], "opaque")
        self.assertEqual(self.result["closedConditionalPassthrough"], "slot:1")

    def test_exhaustive_branch_preserves_one_sampled_alpha(self) -> None:
        for key in ("conditionalAlphaPreserving", "conditionalGeneratedRGB"):
            self.assertEqual(
                self.result[key], "straight-preserving-slot:0", key
            )
        source = self.result["conditionalAlphaPreservingMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_conditional_alpha_join_remains_fail_closed(self) -> None:
        for key in (
            "conditionalDifferentSlot",
            "conditionalNonIdentityAlpha",
            "conditionalAlphaRewrittenAfterJoin",
            "conditionalGuardedAlphaJoin",
            "conditionalTrailingStatement",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

    def test_straight_alpha_boundary_is_proven_from_a_single_source(self) -> None:
        self.assertEqual(self.result["straightAlpha"], "straight-slot:0")
        self.assertEqual(
            self.result["straightBlendReplacement"], "straight-slot:0"
        )
        self.assertEqual(
            self.result["closedControlFlowStraightAlpha"], "straight-slot:0"
        )
        self.assertEqual(self.result["localAlpha"], "straight-slot:0")
        self.assertEqual(self.result["mutatedLocalOutput"], "straight-slot:0")
        self.assertEqual(
            self.result["mutatedSampledMaskAlpha"], "straight-slot:0"
        )
        source = self.result["straightBlendMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_straight_rgb_with_factored_source_alpha_has_one_color_boundary(self) -> None:
        self.assertEqual(
            self.result["straightRGBFactoredAlpha"], "straight-slot:0"
        )
        self.assertEqual(self.result["straightRGBSafeHelper"], "straight-slot:0")
        source = self.result["straightRGBFactoredAlphaMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in (
            "straightRGBReplacedAlpha",
            "straightRGBAdditiveAlpha",
            "straightRGBConditionalAlpha",
            "straightRGBExtraSample",
            "straightRGBMutatedColor",
            "straightRGBHiddenHelperSample",
            "straightRGBHiddenHelperConditional",
            "straightRGBHiddenHelperMutation",
        ):
            self.assertNotEqual(self.result[key], "straight-slot:0", key)

    def test_overlay_alpha_blend_reuses_the_bounded_straight_boundary(self) -> None:
        self.assertEqual(self.result["overlayAlphaBlend"], "straight-slot:0")
        source = self.result["overlayAlphaBlendMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_overlay_alpha_blend_stays_closed_without_the_exact_dataflow(self) -> None:
        for key in (
            "overlayAlphaBlendWrongHelper",
            "overlayAlphaBlendWeightWithoutAlpha",
            "overlayAlphaBlendNonzeroMode",
            "overlayAlphaBlendBaseAlpha",
            "overlayAlphaBlendExtraSample",
            "overlayAlphaBlendMultipleWrites",
            "overlayAlphaBlendConditionalAlpha",
            "overlayAlphaBlendOverlayMutation",
        ):
            self.assertEqual(self.result[key], "unresolved", key)
        self.assertNotEqual(
            self.result["overlayAlphaBlendSameSlot"], "straight-slot:0"
        )

    def test_same_slot_scalar_mix_preserves_one_color_source(self) -> None:
        self.assertEqual(self.result["sameSlotScalarMix"], "slot:0")
        self.assertEqual(self.result["sameSlotUniformMix"], "slot:0")

    def test_same_slot_alias_replacement_preserves_one_color_source(self) -> None:
        self.assertEqual(self.result["sameSlotAliasReplacement"], "slot:0")
        for key in (
            "differentSlotAliasReplacement",
            "conditionalAliasReplacement",
        ):
            self.assertEqual(self.result[key], "unresolved", key)
        self.assertEqual(
            self.result["modifiedAliasReplacement"],
            "signal-preserving-slot:0",
        )

    def test_nested_same_slot_mix_graph_is_bounded_and_fail_closed(self) -> None:
        self.assertEqual(self.result["nestedSameSlotMixGraph"], "slot:0")
        self.assertEqual(self.result["nestedDifferentSlotMixGraph"], "unresolved")
        self.assertEqual(self.result["conditionalNestedMixGraph"], "unresolved")

    def test_whole_rgba_affine_filter_uses_a_clamped_straight_boundary(self) -> None:
        self.assertEqual(
            self.result["wholeColorFilter"], "straight-unorm-slot:0"
        )
        source = self.result["wholeColorFilterMetal"]
        self.assertEqual(
            source.count("mwxUnpremultiply(mwxTexture0.sample"), 10
        )
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertIn(
            "return mwxSaturateAndPremultiply(mwxFragColor);", source
        )
        for key in (
            "wholeColorFilterDifferentSlot",
            "wholeColorFilterComponentWrite",
            "wholeColorFilterDynamicDivision",
            "wholeColorFilterHiddenMutation",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

    def test_rgb_only_local_flow_uses_a_straight_color_boundary(self) -> None:
        self.assertEqual(
            self.result["opaqueInputRGBTransform"], "straight-preserving-slot:0"
        )
        source = self.result["alphaPreservingMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_rgb_mix_read_preserves_source_alpha(self) -> None:
        self.assertEqual(
            self.result["alphaPreservingRGBMix"],
            "straight-preserving-slot:0",
        )
        source = self.result["alphaPreservingRGBMixMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_independent_alpha_signal_is_bounded_and_composed_explicitly(self) -> None:
        self.assertEqual(self.result["independentSignal"], "signal-slot:0")
        self.assertEqual(
            self.result["independentSignalPreserving"],
            "signal-preserving-slot:0",
        )
        self.assertEqual(
            self.result["independentSignalComposite"], "signal-composite:0:1"
        )
        self.assertEqual(
            self.result["invalidIndependentSignal"],
            "signal-preserving-slot:0",
        )

        producer = self.result["independentSignalMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", producer)
        self.assertNotIn("return mwxPremultiply(mwxFragColor);", producer)
        composite = self.result["independentCompositeMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture1.sample", composite)
        self.assertIn("return mwxPremultiply(mwxFragColor);", composite)

    def test_zero_base_additive_output_proves_only_exact_premultiplied_flow(self) -> None:
        self.assertEqual(
            self.result["premultipliedAdditive"], "premultiplied-alpha"
        )
        for key in (
            "premultipliedWrongBase",
            "premultipliedDifferentWeight",
            "premultipliedNonzeroBase",
            "premultipliedExtraWrite",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

    def test_straight_alpha_boundary_is_emitted_only_for_proven_programs(self) -> None:
        source = self.result["straightMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in ("passthroughMetal", "opaqueMetal"):
            self.assertNotIn("mwxUnpremultiply", self.result[key], key)
            self.assertNotIn("mwxPremultiply", self.result[key], key)

    def test_alpha_math_and_non_linear_writes_remain_unproven(self) -> None:
        for key in (
            "localRGBWrite",
            "multipleLocalAlphaWrites",
            "wholeLocalWrite",
        ):
            self.assertEqual(self.result[key], "signal-preserving-slot:0", key)
        for key in (
            "arithmetic",
            "modifiedStraightLocal",
            "straightRGBMath",
            "straightBlendDifferentAlpha",
            "straightBlendExtraSample",
            "mixedSampleAlpha",
            "sampledMaskAlpha",
            "conditionalLocalAlpha",
            "multipleWrites",
            "componentWrite",
            "conditionalOpaque",
            "loopControlledOpaque",
            "earlyReturn",
            "discardedBranch",
            "differentSlotMix",
            "vectorWeightMix",
            "opaqueInputAlphaWrite",
            "opaqueInputWholeWrite",
            "repeatedAuxiliarySample",
            "maskedRGBWrite",
        ):
            self.assertEqual(self.result[key], "unresolved", key)


if __name__ == "__main__":
    unittest.main()
