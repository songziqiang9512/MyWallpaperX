#!/usr/bin/env python3

"""Fail-closed color-transfer proofs from the emitted shader syntax unit."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaPreservingLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderScalarizedRGBPreservedAlphaLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaWholeOutputUnionLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderConditionalGeneratedRGBLowering.swift",
]


HARNESS = r'''
import Foundation

private func fragment(
    _ body: String,
    helpers: String = "",
    blendReturns: String = "return mix(base, (blend), opacity);"
) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform sampler2D g_Texture2;
    uniform sampler2D g_Texture3;
    uniform float g_ScalarWeight;
    uniform float g_Border;
    uniform vec3 g_Tint;
    uniform vec3 g_Shadow;
    uniform vec3 g_VectorWeight;
    varying vec3 v_Tint;
    vec3 ApplyBlending(
        const int mode,
        in vec3 base,
        in vec3 blend,
        in float opacity
    ) {
        \(blendReturns)
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

private func program(
    _ body: String,
    helpers: String = "",
    blendReturns: String = "return mix(base, (blend), opacity);"
) -> SceneAuthoredShaderProgram? {
    let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    varying vec3 v_Tint;
    void main() {
        v_TexCoord = a_TexCoord;
        v_Tint = vec3(a_TexCoord, 0.0);
        gl_Position = vec4(a_Position, 1.0);
    }
    """
    return SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex,
        fragmentSource: fragment(
            body,
            helpers: helpers,
            blendReturns: blendReturns
        )
    ).program
}

private func transfer(
    _ body: String,
    helpers: String = "",
    blendReturns: String = "return mix(base, (blend), opacity);"
) -> String {
    let result = program(
        body,
        helpers: helpers,
        blendReturns: blendReturns
    )?.colorTransfer ?? .unresolved
    switch result {
    case .opaque: return "opaque"
    case .opaqueFromStraightColor(let slot):
        return "opaque-from-straight-slot:\(slot)"
    case .unresolved: return "unresolved"
    case .passthrough(let slot): return "slot:\(slot)"
    case .interpolatedColor(let slots):
        return "interpolated-slots:" + slots.map(String.init).joined(separator: ",")
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
    case .generatedStraightAlpha: return "generated-straight-alpha"
    }
}

private func runtimeBoundedTransfer(
    _ body: String,
    helpers: String,
    bounds: [String: Int]
) -> String {
    let runtimeBounds = SceneAuthoredShaderRuntimeLoopBounds(
        vertex: [:],
        fragment: bounds
    )
    let result = SceneAuthoredShaderColorTransferAnalyzer.analyze(
        fragmentSource: fragment(body, helpers: helpers),
        provenRuntimeLoopBounds: runtimeBounds.fragment
    )
    guard case let .straightAlphaPreserving(slot) = result else {
        return "unresolved"
    }
    return "straight-preserving-slot:\(slot)"
}

private func fragmentOutputUse(_ body: String) -> String {
    program(body)?.fragmentOutputChannelUse.rawValue ?? "unproven"
}

private func fragmentOutputUse(source: String) -> String {
    let lexerOutput = SceneAuthoredShaderLexer.lex(
        source: source,
        stage: .fragment
    )
    let syntaxOutput = SceneAuthoredShaderSyntaxAnalyzer.analyze(
        lexerOutput: lexerOutput,
        stage: .fragment
    )
    guard syntaxOutput.diagnostics.isEmpty,
          let fragment = syntaxOutput.unit else { return "unproven" }
    return SceneAuthoredShaderFragmentOutputAnalyzer.analyze(fragment).rawValue
}

private func scalarAlphaFact(_ body: String) -> String {
    guard let fact = SceneAuthoredShaderColorTransferAnalyzer
        .straightRGBScalarAlphaFact(fragmentSource: fragment(body)) else {
        return "unresolved"
    }
    return "source:\(fact.sourceSlot);aux:" + fact.auxiliarySlots.sorted()
        .map(String.init).joined(separator: ",")
}

private func scalarAlphaDetailedFact(_ body: String) -> String {
    guard let fact = SceneAuthoredShaderColorTransferAnalyzer
        .straightRGBScalarAlphaFact(fragmentSource: fragment(body)) else {
        return "unresolved"
    }
    return "source:\(fact.sourceSlot);scalar:"
        + fact.scalarAuxiliarySlots.sorted().map(String.init).joined(separator: ",")
        + ";mask:" + (fact.maskSlot.map(String.init) ?? "none")
        + ";aux:" + fact.auxiliarySlots.sorted().map(String.init)
            .joined(separator: ",")
}

private func metal(
    _ body: String,
    helpers: String = "",
    blendReturns: String = "return mix(base, (blend), opacity);"
) -> String {
    program(
        body,
        helpers: helpers,
        blendReturns: blendReturns
    )?.metalSource ?? ""
}

private func generatedUnderlayFragment(_ body: String) -> String {
    """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform sampler2D g_Texture2;
    uniform sampler2D g_Texture3;
    uniform float g_ScalarWeight;
    uniform vec3 g_Shadow;
    void main() {
        \(body)
    }
    """
}

private func generatedUnderlayProgram(
    _ body: String
) -> SceneAuthoredShaderProgram? {
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
        fragmentSource: generatedUnderlayFragment(body)
    ).program
}

private func generatedUnderlayTransfer(_ body: String) -> String {
    let result = generatedUnderlayProgram(body)?.colorTransfer ?? .unresolved
    switch result {
    case .straightAlpha(let slot): return "straight-slot:\(slot)"
    default: return "other"
    }
}

private func generatedUnderlayMetal(_ body: String) -> String {
    generatedUnderlayProgram(body)?.metalSource ?? ""
}

private func conditionalGeneratedRGBFact(
    _ body: String,
    helpers: String = ""
) -> String {
    guard let fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
        fragmentSource: fragment(body, helpers: helpers)
    ) else { return "unresolved" }
    let generated = fact.generatedOpaqueColorSlots.sorted()
        .map(String.init).joined(separator: ",")
    let red = fact.scalarRedSlots.sorted()
        .map(String.init).joined(separator: ",")
    let green = fact.scalarGreenSlots.sorted()
        .map(String.init).joined(separator: ",")
    let blue = fact.scalarBlueSlots.sorted()
        .map(String.init).joined(separator: ",")
    let alpha = fact.scalarAlphaSlots.sorted()
        .map(String.init).joined(separator: ",")
    let counts = fact.sampleCallCounts.sorted(by: { $0.key < $1.key })
        .map { "\($0.key):\($0.value)" }.joined(separator: ",")
    return "carrier:\(fact.alphaCarrierSlot);generated:\(generated);" +
        "red:\(red);green:\(green);blue:\(blue);alpha:\(alpha);" +
        "counts:\(counts)"
}

private func conditionalGeneratedRGBCompilerLowering(
    _ body: String,
    mutation: String = "valid"
) -> String {
    guard let fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
        fragmentSource: fragment(body)
    ) else { return "unresolved" }
    var source = """
    using namespace metal;
    struct CompilerOutput { float4 mwxFragColor; };
    fragment CompilerOutput translatedFragment() {
        CompilerOutput out = {};
        float4 base = g_Texture2.sample(g_Texture2Smplr, coordinates);
        float3 color = base.xyz;
        float mask = g_Texture1.sample(g_Texture1Smplr, coordinates).x;
        if ((weight > 0.001) && (mask > 0.001)) {
            color = g_Texture0.sample(g_Texture0Smplr, coordinates).xyz;
            color += g_Texture0.sample(g_Texture0Smplr, coordinates * 0.5).xyz;
            color *= 0.4 * tint;
            color = ApplyBlending(0, base.xyz, color, mask);
        }
        out.mwxFragColor = float4(color, base.w);
        return out;
    }
    """
    switch mutation {
    case "role-swap":
        source = source.replacingOccurrences(
            of: "float3 color = g_Texture0.sample(g_Texture0Smplr, coordinates).xyz;",
            with: "float3 color = g_Texture1.sample(g_Texture1Smplr, coordinates).xyz;"
        ).replacingOccurrences(
            of: "float mask = g_Texture1.sample(g_Texture1Smplr, coordinates).x;",
            with: "float mask = g_Texture0.sample(g_Texture0Smplr, coordinates).x;"
        )
    case "post-output":
        source = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(color, base.w);",
            with: "out.mwxFragColor = float4(color, base.w);\n        sideEffect();"
        )
    case "carrier-conditional-write":
        source = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(color, base.w);",
            with: "if (weight > 0.0) base.w = 0.0;\n        " +
                "out.mwxFragColor = float4(color, base.w);"
        )
    case "carrier-prefix-write":
        source = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(color, base.w);",
            with: "++base.w;\n        " +
                "out.mwxFragColor = float4(color, base.w);"
        )
    case "compound-extra-output":
        source = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(color, base.w);",
            with: "out.secondary += float4(1.0);\n        " +
                "out.mwxFragColor = float4(color, base.w);"
        )
    case "prefix-extra-output":
        source = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(color, base.w);",
            with: "++out.secondary.x;\n        " +
                "out.mwxFragColor = float4(color, base.w);"
        )
    case "hidden-helper-sample":
        source = source.replacingOccurrences(
            of: "fragment CompilerOutput translatedFragment() {",
            with: "float3 compilerHidden() { return g_Texture0.sample(" +
                "g_Texture0Smplr, coordinates * 0.5).xyz; }\n" +
                "fragment CompilerOutput translatedFragment() {"
        ).replacingOccurrences(
            of: "color += g_Texture0.sample(g_Texture0Smplr, " +
                "coordinates * 0.5).xyz;",
            with: "color += compilerHidden();"
        )
    default:
        break
    }
    return SceneGenericShaderConditionalGeneratedRGBLowering.lower(
        source,
        fact: fact
    ) ?? "unresolved"
}

private func conditionalShadowBody(
    mode: Int = 30,
    offsetSample: String = "texSample2D(g_Texture0, " +
        "v_TexCoord + vec2(0.25, 0.0))",
    prelude: String = "",
    weight: String = "g_ScalarWeight",
    alphaWeight: String? = nil,
    blendExpression: String? = nil,
    alphaExpression: String? = nil,
    alphaOperation: String = "+",
    shadowCondition: String = "offset.a > 0.0",
    betweenBranches: String = "",
    fallback: String = "base"
) -> String {
    let resolvedAlphaWeight = alphaWeight ?? weight
    let resolvedBlend = blendExpression ??
        "ApplyBlending(\(mode), base.rgb, g_Shadow, \(weight))"
    let resolvedAlpha = alphaExpression ?? "offset.a * \(resolvedAlphaWeight)"
    return "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
        "vec4 offset = \(offsetSample); \(prelude)" +
        "if (base.a > g_Border) { gl_FragColor = base; } " +
        "else if (\(shadowCondition)) { " +
        "gl_FragColor.rgb = \(resolvedBlend); " +
        "gl_FragColor.a = min(1.0, base.a \(alphaOperation) " +
        "\(resolvedAlpha)); " +
        "} \(betweenBranches)else { gl_FragColor = \(fallback); }"
}

@main
enum Harness {
    static func main() throws {
        let normalMaskOffShadow = conditionalShadowBody(
            mode: 0,
            prelude: "float mask = 1.0; ",
            weight: "g_ScalarWeight * mask"
        )
        let conditionalGeneratedRGB =
            "vec4 base = texSample2D(g_Texture2, v_TexCoord); " +
            "vec3 color = base.rgb; " +
            "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
            "if (g_ScalarWeight > 0.001 && mask > 0.001) { " +
            "color = texSample2D(g_Texture0, v_TexCoord).rgb; " +
            "color += texSample2D(g_Texture0, v_TexCoord * 0.5).rgb; " +
            "color *= 0.4 * g_Tint; " +
            "color.rgb = ApplyBlending(0, base.rgb, color, mask); } " +
            "gl_FragColor = vec4(color, base.a);"
        let conditionalGeneratedRGBComponentScalars =
            "vec4 base = texSample2D(g_Texture2, v_TexCoord); " +
            "vec3 color = base.rgb; " +
            "float red = texSample2D(g_Texture1, v_TexCoord).x; " +
            "float green = texSample2D(g_Texture3, v_TexCoord).y; " +
            "float blue = texSample2D(g_Texture1, v_TexCoord).z; " +
            "float alpha = texSample2D(g_Texture3, v_TexCoord).w; " +
            "if (g_ScalarWeight > 0.001 && " +
            "red + green + blue + alpha > 0.001) { " +
            "color = texSample2D(g_Texture0, v_TexCoord).rgb; " +
            "color += texSample2D(g_Texture0, v_TexCoord * 0.5).rgb; " +
            "color *= (0.4 + blue) * g_Tint; " +
            "color.rgb = ApplyBlending(0, base.rgb, color, red); } " +
            "gl_FragColor = vec4(color, base.a);"
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
            "opaqueCarrier": transfer(
                "vec4 carrier = CAST4(1); vec3 derived = carrier.rgb; " +
                "derived *= g_ScalarWeight; carrier.rgb = derived; " +
                "gl_FragColor = carrier;"
            ),
            "opaqueCarrierAlphaWrite": transfer(
                "vec4 carrier = CAST4(1); carrier.rgb *= g_ScalarWeight; " +
                "carrier.a = 0.5; gl_FragColor = carrier;"
            ),
            "opaqueCarrierWholeWrite": transfer(
                "vec4 carrier = CAST4(1); carrier = vec4(0.5); " +
                "gl_FragColor = carrier;"
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
            "straightRGBScalarAlpha": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r * 6.0; " +
                "pulse = smoothstep(0.0, 1.0, " +
                "sin(g_ScalarWeight + phase) * 0.5 + 0.5); " +
                "float noise = texSample2D(g_Texture1, " +
                "vec2(g_ScalarWeight * 0.08, g_ScalarWeight * 0.03)).r * 0.5; " +
                "pulse += noise; pulse = pow(pulse, 1.0); " +
                "color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaFact": scalarAlphaFact(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r * 6.0; " +
                "pulse = smoothstep(0.0, 1.0, " +
                "sin(g_ScalarWeight + phase) * 0.5 + 0.5); " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r * 0.5; " +
                "pulse += noise; pulse = pow(pulse, 1.0); " +
                "color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaMasked": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "color.a *= pulse; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r; " +
                "color = mix(sampled, color, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaMaskedFact": scalarAlphaDetailedFact(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "color.a *= pulse; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r; " +
                "color = mix(sampled, color, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaMaskTransform": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "color.a *= pulse; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r * 0.5; " +
                "color = mix(sampled, color, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaMaskShadowedMix": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "color.a *= pulse; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r; " +
                "color = mix(sampled, color, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);",
                helpers: "vec4 mix(vec4 a, vec4 b, float t) { return a; }"
            ),
            "straightRGBScalarAlphaMaskReversed": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "color.a *= pulse; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r; " +
                "color = mix(color, sampled, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaMaskBeforeAlpha": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = g_ScalarWeight; " +
                "float mask = texSample2D(g_Texture2, v_TexCoord).r; " +
                "color.a *= pulse; color = mix(sampled, color, mask); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaNoAux": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaNoAuxFact": scalarAlphaFact(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaNoAuxMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaSaturate": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = saturate(color);"
            ),
            "straightRGBScalarAlphaSaturateMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = saturate(color);"
            ),
            "straightRGBScalarAlphaShadowedSaturate": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "pulse = g_ScalarWeight; color.a *= pulse; " +
                "gl_FragColor = saturate(color);",
                helpers: "vec4 saturate(vec4 value) { return value; }"
            ),
            "straightRGBScalarAlphaMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r * 6.0; " +
                "pulse = smoothstep(0.0, 1.0, " +
                "sin(g_ScalarWeight + phase) * 0.5 + 0.5); " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r * 0.5; " +
                "pulse += noise; pulse = pow(pulse, 1.0); " +
                "color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaGreen": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).g; " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r; " +
                "pulse = phase + noise; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaRepeatedAux": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float first = texSample2D(g_Texture1, v_TexCoord).r; " +
                "float second = texSample2D(g_Texture1, v_TexCoord * 0.5).r; " +
                "pulse = first + second; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaRGBWrite": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r; " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r; " +
                "pulse = phase + noise; color.rgb *= 0.5; color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaReplacement": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r; " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r; " +
                "pulse = phase + noise; color.a = pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "straightRGBScalarAlphaUnknownHelper": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float pulse = 0.0; " +
                "float phase = texSample2D(g_Texture3, v_TexCoord).r; " +
                "float noise = texSample2D(g_Texture1, v_TexCoord).r; " +
                "pulse = SafeCoverage(phase + noise); color.a *= pulse; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);",
                helpers: "float SafeCoverage(float value) { return value; }"
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
            "generatedRGBPreservedAlpha": transfer(
                "float weight = g_ScalarWeight; " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "vec3 generated = vec3(0.8); " +
                "vec3 finalColor = generated.rgb; " +
                "finalColor = ApplyBlending(0, lerp(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight * mask); " +
                "float alpha = scene.a; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "generatedRGBPreservedAlphaMetal": metal(
                "float weight = g_ScalarWeight; " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "float mask = texSample2D(g_Texture1, v_TexCoord).r; " +
                "vec3 generated = vec3(0.8); " +
                "vec3 finalColor = generated.rgb; " +
                "finalColor = ApplyBlending(0, lerp(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight * mask); " +
                "float alpha = scene.a; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "generatedRGBReplacedAlpha": transfer(
                "float weight = g_ScalarWeight; " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "vec3 finalColor = vec3(0.8); " +
                "finalColor = ApplyBlending(0, lerp(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = weight; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "generatedRGBSecondColorSource": transfer(
                "float weight = g_ScalarWeight; " +
                "vec4 scene = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 other = texSample2D(g_Texture1, v_TexCoord); " +
                "vec3 finalColor = other.rgb; " +
                "finalColor = ApplyBlending(0, lerp(finalColor.rgb, " +
                "scene.rgb, scene.a), finalColor.rgb, weight); " +
                "float alpha = scene.a; " +
                "gl_FragColor = vec4(finalColor, alpha);"
            ),
            "conditionalGeneratedRGBPreservedAlpha": transfer(
                conditionalGeneratedRGB
            ),
            "conditionalGeneratedRGBFact": conditionalGeneratedRGBFact(
                conditionalGeneratedRGB
            ),
            "conditionalGeneratedRGBComponentScalarFact":
                conditionalGeneratedRGBFact(
                    conditionalGeneratedRGBComponentScalars
                ),
            "conditionalGeneratedRGBMetal": metal(conditionalGeneratedRGB),
            "conditionalGeneratedRGBCompilerLowering":
                conditionalGeneratedRGBCompilerLowering(conditionalGeneratedRGB),
            "conditionalGeneratedRGBCompilerRoleSwap":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "role-swap"
                ),
            "conditionalGeneratedRGBCompilerPostOutput":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "post-output"
                ),
            "conditionalGeneratedRGBCompilerCarrierConditionalWrite":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "carrier-conditional-write"
                ),
            "conditionalGeneratedRGBCompilerCarrierPrefixWrite":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "carrier-prefix-write"
                ),
            "conditionalGeneratedRGBCompilerCompoundExtraOutput":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "compound-extra-output"
                ),
            "conditionalGeneratedRGBCompilerPrefixExtraOutput":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "prefix-extra-output"
                ),
            "conditionalGeneratedRGBCompilerHiddenHelperSample":
                conditionalGeneratedRGBCompilerLowering(
                    conditionalGeneratedRGB,
                    mutation: "hidden-helper-sample"
                ),
            "conditionalGeneratedRGBMultiReturnHelper": transfer(
                conditionalGeneratedRGB,
                blendReturns: "if (opacity > 0.0) { " +
                    "return mix(base, (blend), opacity); } " +
                    "return base;"
            ),
            "conditionalGeneratedRGBReplacedAlpha": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "vec4(color, base.a)",
                    with: "vec4(color, mask)"
                )
            ),
            "conditionalGeneratedRGBWholeColorSample": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "texSample2D(g_Texture0, v_TexCoord).rgb",
                    with: "texSample2D(g_Texture0, v_TexCoord)",
                    options: [],
                    range: conditionalGeneratedRGB.range(
                        of: "texSample2D(g_Texture0, v_TexCoord).rgb"
                    )
                )
            ),
            "conditionalGeneratedRGBHiddenHelperSample": transfer(
                conditionalGeneratedRGB,
                helpers: "float HiddenGeneratedControl() { " +
                    "return texSample2D(g_Texture3, v_TexCoord).r; }"
            ),
            "conditionalGeneratedRGBHelperSample": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "ApplyBlending",
                    with: "SamplingGeneratedBlend"
                ),
                helpers: "vec3 SamplingGeneratedBlend(const int mode, " +
                    "in vec3 base, in vec3 blend, in float opacity) { " +
                    "float sampled = texSample2D(g_Texture3, " +
                    "v_TexCoord).r; " +
                    "return mix(base, blend, opacity * sampled); }"
            ),
            "conditionalGeneratedRGBHelperOutputMutation": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "ApplyBlending",
                    with: "OutputMutatingGeneratedBlend"
                ),
                helpers: "vec3 OutputMutatingGeneratedBlend(" +
                    "const int mode, in vec3 base, in vec3 blend, " +
                    "in float opacity) { gl_FragColor = vec4(base, 1.0); " +
                    "return mix(base, blend, opacity); }"
            ),
            "conditionalGeneratedRGBHelperOutMutation": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "ApplyBlending",
                    with: "MutatingGeneratedBlend"
                ),
                helpers: "void MutateGeneratedOutput(out vec3 value) { " +
                    "value = vec3(0.0); } " +
                    "vec3 MutatingGeneratedBlend(const int mode, " +
                    "in vec3 base, in vec3 blend, in float opacity) { " +
                    "MutateGeneratedOutput(blend); " +
                    "return mix(base, blend, opacity); }"
            ),
            "conditionalGeneratedRGBCallAfterBlend": transfer(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "color.rgb = ApplyBlending(0, base.rgb, " +
                        "color, mask); }",
                    with: "color.rgb = ApplyBlending(0, base.rgb, " +
                        "color, mask); GeneratedTail(); }"
                ),
                helpers: "void GeneratedTail() {}"
            ),
            "conditionalGeneratedRGBCallAfterOutput": transfer(
                conditionalGeneratedRGB + " GeneratedTail();",
                helpers: "void GeneratedTail() {}"
            ),
            "conditionalGeneratedRGBDiscardAfterOutput": transfer(
                conditionalGeneratedRGB + " discard;"
            ),
            "conditionalGeneratedRGBMainBarrier": conditionalGeneratedRGBFact(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "gl_FragColor = vec4(color, base.a);",
                    with: "memoryBarrier(); " +
                        "gl_FragColor = vec4(color, base.a);"
                )
            ),
            "conditionalGeneratedRGBMainTexelFetch": conditionalGeneratedRGBFact(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "if (g_ScalarWeight > 0.001",
                    with: "vec4 hidden = texelFetch(g_Texture3, ivec2(0), 0); " +
                        "if (g_ScalarWeight > 0.001"
                )
            ),
            "conditionalGeneratedRGBGlobalWritingHelper":
                conditionalGeneratedRGBFact(
                    conditionalGeneratedRGB.replacingOccurrences(
                        of: "gl_FragColor = vec4(color, base.a);",
                        with: "MutateGeneratedGlobal(); " +
                            "gl_FragColor = vec4(color, base.a);"
                    ),
                    helpers: "float generatedGlobal; " +
                        "void MutateGeneratedGlobal() { " +
                        "generatedGlobal = 1.0; }"
                ),
            "conditionalGeneratedRGBExtraOutput": conditionalGeneratedRGBFact(
                conditionalGeneratedRGB.replacingOccurrences(
                    of: "gl_FragColor = vec4(color, base.a);",
                    with: "gl_FragDepth = mask; " +
                        "gl_FragColor = vec4(color, base.a);"
                )
            ),
            "overlayAlphaBlend": transfer(
                "vec4 base = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 overlay = texSample2D(g_Texture1, v_TexCoord); " +
                "float mask = 1.0; " +
                "float weight = mask * g_ScalarWeight * overlay.a; " +
                "base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight); " +
                "base.a = overlay.a * g_ScalarWeight; gl_FragColor = base;"
            ),
            "generatedUnderlayBlend": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shadowAlpha = texSample2D(g_Texture0, " +
                "v_TexCoord + vec2(0.01, 0.02)).a; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shadowAlpha); " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
            ),
            "generatedUnderlayBlendMetal": generatedUnderlayMetal(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shadowAlpha = texSample2D(g_Texture0, " +
                "v_TexCoord + vec2(0.01, 0.02)).a; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shadowAlpha); " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
            ),
            "generatedUnderlayBlendRenamed": generatedUnderlayTransfer(
                "vec4 authored = texture2D(g_Texture3, v_TexCoord); " +
                "float shifted = texture2D(g_Texture3, " +
                "v_TexCoord + vec2(0.03, 0.04)).w; " +
                "vec4 behind = vec4(g_Shadow, " +
                "shifted * g_ScalarWeight); " +
                "gl_FragColor = lerp(behind, authored, authored.w);"
            ),
            "generatedUnderlayDifferentSlot": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture1, v_TexCoord).a; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shifted); " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
            ),
            "generatedUnderlayWrongWeight": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture0, v_TexCoord).a; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shifted); " +
                "gl_FragColor = mix(shadow, pix, g_ScalarWeight);"
            ),
            "generatedUnderlayExtraSample": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture0, v_TexCoord).a; " +
                "float extra = texSample2D(g_Texture0, " +
                "v_TexCoord * 0.5).r; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shifted); " +
                "gl_FragColor = mix(shadow, pix, pix.a + extra);"
            ),
            "generatedUnderlayGeneratedRGBSample": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture0, v_TexCoord).a; " +
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 shadow = vec4(color.rgb, " +
                "g_ScalarWeight * shifted); " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
            ),
            "generatedUnderlayMissingSignal": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture0, v_TexCoord).a; " +
                "vec4 shadow = vec4(g_Shadow, g_ScalarWeight); " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
            ),
            "generatedUnderlayConditional": generatedUnderlayTransfer(
                "vec4 pix = texSample2D(g_Texture0, v_TexCoord); " +
                "float shifted = texSample2D(g_Texture0, v_TexCoord).a; " +
                "vec4 shadow = vec4(g_Shadow, " +
                "g_ScalarWeight * shifted); " +
                "if (g_ScalarWeight > 0.0) " +
                "gl_FragColor = mix(shadow, pix, pix.a);"
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
            "conditionalShadow": transfer(conditionalShadowBody()),
            "conditionalShadowMetal": metal(conditionalShadowBody()),
            "conditionalShadowModeThirtyHelper": transfer(
                conditionalShadowBody(),
                blendReturns: "return mix(base, " +
                    "(CAST3(max(base.x, max(base.y, base.z))) * blend), " +
                    "opacity); return mix(base, (blend), opacity);"
            ),
            "conditionalShadowModeThirtyHelperMetal": metal(
                conditionalShadowBody(),
                blendReturns: "return mix(base, " +
                    "(CAST3(max(base.x, max(base.y, base.z))) * blend), " +
                    "opacity); return mix(base, (blend), opacity);"
            ),
            "conditionalShadowNormalMaskOff": transfer(normalMaskOffShadow),
            "conditionalShadowNormalMaskOffMetal": metal(normalMaskOffShadow),
            "conditionalShadowNormalMaskMutation": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = 1.0; mask *= g_ScalarWeight; ",
                    weight: "g_ScalarWeight * mask"
                )
            ),
            "conditionalShadowNormalMaskTexture": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = " +
                        "texSample2D(g_Texture1, v_TexCoord).r; ",
                    weight: "g_ScalarWeight * mask"
                )
            ),
            "conditionalShadowNormalDifferentWeight": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = 1.0; ",
                    weight: "g_ScalarWeight * mask",
                    alphaWeight: "g_ScalarWeight * mask * 0.5"
                )
            ),
            "conditionalShadowNormalVectorWeight": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = 1.0; ",
                    weight: "g_VectorWeight.x * mask"
                )
            ),
            "conditionalShadowNormalControlFlow": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = 1.0; " +
                        "if (g_ScalarWeight > 0.5) { mask = 0.5; } ",
                    weight: "g_ScalarWeight * mask"
                )
            ),
            "conditionalShadowNormalWrongHelper": transfer(
                conditionalShadowBody(
                    mode: 0,
                    prelude: "float mask = 1.0; ",
                    weight: "g_ScalarWeight * mask"
                ),
                blendReturns: "return base + blend * opacity;"
            ),
            "conditionalShadowWrongSlot": transfer(
                conditionalShadowBody(
                    offsetSample: "texSample2D(g_Texture1, " +
                        "v_TexCoord + vec2(0.25, 0.0))"
                )
            ),
            "conditionalShadowExtraSample": transfer(
                conditionalShadowBody(
                    prelude: "vec4 extra = texSample2D(g_Texture0, " +
                        "v_TexCoord - vec2(0.25, 0.0)); ",
                    alphaExpression: "offset.a * g_ScalarWeight + extra.a"
                )
            ),
            "conditionalShadowAlphaSubtract": transfer(
                conditionalShadowBody(alphaOperation: "-")
            ),
            "conditionalShadowDifferentAlphaWeight": transfer(
                conditionalShadowBody(alphaWeight: "(g_ScalarWeight * 0.5)")
            ),
            "conditionalShadowWrongFallback": transfer(
                conditionalShadowBody(fallback: "offset")
            ),
            "conditionalShadowMutatingHelper": transfer(
                conditionalShadowBody(
                    blendExpression: "MutatingShadow(" +
                        "base.rgb, g_Shadow, g_ScalarWeight)"
                ),
                helpers: "vec3 MutatingShadow(inout vec3 base, vec3 blend, " +
                    "float opacity) { base = blend; " +
                    "return mix(base, blend, opacity); }"
            ),
            "conditionalShadowExtraBranch": transfer(
                conditionalShadowBody(
                    shadowCondition: "offset.a > 0.5",
                    betweenBranches: "else if (offset.a > 0.0) { " +
                        "gl_FragColor = offset; } "
                )
            ),
            "conditionalShadowCoordinateMutation": transfer(
                conditionalShadowBody(
                    offsetSample: "texSample2D(g_Texture0, " +
                        "vec2(base[0] *= base.a))"
                )
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
            "alphaPreservingRGBBlend": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = g_ScalarWeight; " +
                "color.rgb = ApplyBlending(30, color.rgb, g_Tint, weight); " +
                "gl_FragColor = color;"
            ),
            "alphaPreservingRGBReconstruction": transfer(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float weight = g_ScalarWeight; " +
                "color.rgb = ApplyBlending(9, color.rgb * g_Tint, " +
                "color.rgb * g_Tint, weight); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "alphaPreservingRGBScalarClamp": transfer(
                "vec4 carrier = texSample2D(g_Texture3, v_TexCoord); " +
                "vec3 generated = vec3(g_ScalarWeight); " +
                "carrier.rgb = ApplyBlending(9, carrier.rgb, " +
                "generated, 1.0); " +
                "gl_FragColor = vec4(max(0, carrier.rgb), carrier.a);"
            ),
            "alphaPreservingRGBScalarClampReplacement": transfer(
                "vec4 carrier = texSample2D(g_Texture3, v_TexCoord); " +
                "vec3 generated = vec3(g_ScalarWeight); " +
                "carrier.rgb = generated; " +
                "gl_FragColor = vec4(max(0, carrier.rgb), carrier.a);"
            ),
            "alphaPreservingRGBRuntimeLoopUnproven": transfer(
                "float generated = RuntimeSignal(); " +
                "vec4 carrier = texSample2D(g_Texture3, v_TexCoord); " +
                "carrier.rgb = mix(carrier.rgb, vec3(generated), 1.0); " +
                "gl_FragColor = vec4(max(0, carrier.rgb), carrier.a);",
                helpers: "uniform float u_Min; uniform float u_Max; " +
                    "uniform float u_Signal[64]; " +
                    "float RuntimeSignal() { float result = 0.0; " +
                    "for (int i = u_Min; i < u_Max; ++i) { " +
                    "result += u_Signal[i]; } return result; }"
            ),
            "alphaPreservingRGBRuntimeLoopProven": runtimeBoundedTransfer(
                "float generated = RuntimeSignal(); " +
                "vec4 carrier = texSample2D(g_Texture3, v_TexCoord); " +
                "carrier.rgb = mix(carrier.rgb, vec3(generated), 1.0); " +
                "gl_FragColor = vec4(max(0, carrier.rgb), carrier.a);",
                helpers: "uniform float u_Min; uniform float u_Max; " +
                    "uniform float u_Signal[64]; " +
                    "float RuntimeSignal() { float result = 0.0; " +
                    "for (int i = u_Min; i < u_Max; ++i) { " +
                    "result += u_Signal[i]; } return result; }",
                bounds: ["u_Min": 0, "u_Max": 16]
            ),
            "alphaPreservingRGBReconstructionMetal": metal(
                "vec4 sampled = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 color = sampled; float weight = g_ScalarWeight; " +
                "color.rgb = ApplyBlending(9, color.rgb * g_Tint, " +
                "color.rgb * g_Tint, weight); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
            ),
            "alphaPreservingRGBReconstructionDifferentAlpha": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "color.rgb = vec3(0.25); " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), " +
                "g_ScalarWeight);"
            ),
            "alphaPreservingRGBReconstructionOtherColor": transfer(
                "vec4 color = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 other = texSample2D(g_Texture1, v_TexCoord); " +
                "color.rgb = other.rgb; " +
                "gl_FragColor = vec4(max(vec3(0.0), color.rgb), color.a);"
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
            "scanlineUniformRGBMix": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineUniformRGBMixMetal": metal(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineUniformRGBMixDependencyDiamond": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord.xy); " +
                "float origin = g_ScalarWeight; " +
                "float left = saturate(origin); " +
                "float right = saturate(origin); " +
                "float weight = saturate(left * right); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineAlphaRewrite": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a * 0.5);"
            ),
            "scanlineSecondColorSample": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 second = texSample2D(g_Texture1, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, second.rgb, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineUnboundedWeight": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = g_ScalarWeight; " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineVectorWeight": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "vec3 weight = saturate(g_VectorWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineVaryingTint": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, v_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);"
            ),
            "scanlineCustomMix": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = CustomMix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);",
                helpers: "vec3 CustomMix(in vec3 base, in vec3 tint, " +
                    "in float weight) { return mix(base, tint, weight); }"
            ),
            "scanlineMutatingWeightHelper": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float rawWeight = g_ScalarWeight; " +
                "float weight = MutatingWeight(rawWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);",
                helpers: "float MutatingWeight(inout float value) { " +
                    "value = saturate(value); return value; }"
            ),
            "scanlineShadowedSmoothstep": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float raw = smoothstep(0.0, 1.0, g_ScalarWeight); " +
                "float weight = saturate(raw); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = vec4(mixed, source.a);",
                helpers: "float smoothstep(float low, float high, float value) { " +
                    "float sampled = texSample2D(g_Texture1, v_TexCoord).r; " +
                    "return sampled * 4.0; }"
            ),
            "scanlineShadowedFloat4": transfer(
                "vec4 source = texSample2D(g_Texture0, v_TexCoord); " +
                "float weight = saturate(g_ScalarWeight); " +
                "vec3 mixed = mix(source.rgb, g_Tint, weight); " +
                "gl_FragColor = float4(mixed, source.a);",
                helpers: "float4 float4(vec3 rgb, float alpha) { " +
                    "return vec4(rgb, 0.5); }"
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
            "signalCarrierComposite": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 gradient = texSample2D(g_Texture3, " +
                "vec2(signal.r, 0.5)); " +
                "signal.rgb = gradient.rgb * g_Tint; " +
                "signal.a *= gradient.a; " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, previous.rgb, signal.rgb, " +
                "signal.a * g_ScalarWeight); " +
                "signal.a = saturate(previous.a + signal.a); " +
                "gl_FragColor = signal;"
            ),
            "signalCarrierCompositeRenamed": transfer(
                "vec4 payload = texSample2D(g_Texture3, v_TexCoord); " +
                "float mask = texSample2D(g_Texture0, v_TexCoord).r; " +
                "payload.rgb *= g_Tint; payload.a *= mask; " +
                "vec4 base = texSample2D(g_Texture1, v_TexCoord); " +
                "payload.rgb = ApplyBlending(9, base.rgb, payload.rgb, " +
                "payload.a); " +
                "payload.a = saturate(base.a + payload.a); " +
                "gl_FragColor = payload;"
            ),
            "signalCarrierCompositeWrongBase": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, signal.rgb, previous.rgb, " +
                "signal.a); " +
                "signal.a = saturate(previous.a + signal.a); " +
                "gl_FragColor = signal;"
            ),
            "signalCarrierCompositeWrongAlpha": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, previous.rgb, signal.rgb, " +
                "signal.a); signal.a = saturate(signal.a); " +
                "gl_FragColor = signal;"
            ),
            "signalCarrierCompositeWholeEscape": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 alias = signal; " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, previous.rgb, signal.rgb, " +
                "signal.a); " +
                "signal.a = saturate(previous.a + signal.a); " +
                "gl_FragColor = signal;"
            ),
            "signalCarrierCompositePostMutation": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, previous.rgb, signal.rgb, " +
                "signal.a); " +
                "signal.a = saturate(previous.a + signal.a); " +
                "signal.rgb *= g_Tint; gl_FragColor = signal;"
            ),
            "signalCarrierCompositeShadowedSaturate": transfer(
                "vec4 signal = texSample2D(g_Texture0, v_TexCoord); " +
                "vec4 previous = texSample2D(g_Texture1, v_TexCoord); " +
                "signal.rgb = ApplyBlending(31, previous.rgb, signal.rgb, " +
                "signal.a); " +
                "signal.a = saturate(previous.a + signal.a); " +
                "gl_FragColor = signal;",
                helpers: "float saturate(float value) { return 0.0; }"
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
            "scalarOutput": fragmentOutputUse(
                "float signal = texSample2D(g_Texture1, v_TexCoord).r * g_ScalarWeight; " +
                "gl_FragColor = vec4(signal, signal * 0.5, 0.0, 0.0);"
            ),
            "scalarConditionalOutput": fragmentOutputUse(
                "if (v_TexCoord.x > 0.5) gl_FragColor = vec4(0.5);"
            ),
            "scalarMultipleOutputs": fragmentOutputUse(
                "gl_FragColor = vec4(0.25); gl_FragColor = vec4(0.5);"
            ),
            "scalarComponentOutput": fragmentOutputUse(
                "gl_FragColor.r = 0.5;"
            ),
            "scalarEarlyReturn": fragmentOutputUse(
                "if (v_TexCoord.x < 0.0) return; gl_FragColor = vec4(0.5);"
            ),
            "scalarDiscard": fragmentOutputUse(
                "if (v_TexCoord.x < 0.0) discard; gl_FragColor = vec4(0.5);"
            ),
            "scalarHelperDiscard": fragmentOutputUse(source: """
                void MaybeDiscard() { if (v_TexCoord.x < 0.0) discard; }
                void main() { MaybeDiscard(); gl_FragColor = vec4(0.5); }
                """),
            "scalarTransitiveHelperDiscard": fragmentOutputUse(source: """
                void MaybeDiscard() { if (v_TexCoord.x < 0.0) discard; }
                void ForwardDiscard() { MaybeDiscard(); }
                void main() { ForwardDiscard(); gl_FragColor = vec4(0.5); }
                """),
            "scalarHelperBeforeMain": fragmentOutputUse(source: """
                void WriteOutput() { gl_FragColor = vec4(0.5); }
                void main() { WriteOutput(); }
                """),
            "scalarHelperAfterMain": fragmentOutputUse(source: """
                void main() { WriteOutput(); }
                void WriteOutput() { gl_FragColor = vec4(0.5); }
                """),
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
        cls.binary = binary
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

    def test_opaque_carrier_allows_only_rgb_member_flow(self) -> None:
        self.assertEqual(self.result["opaqueCarrier"], "opaque")
        self.assertEqual(self.result["opaqueCarrierAlphaWrite"], "unresolved")
        self.assertEqual(self.result["opaqueCarrierWholeWrite"], "unresolved")

    def test_scalar_red_output_fact_is_independent_of_color_transfer(self) -> None:
        self.assertEqual(self.result["scalarOutput"], "redDefined")
        for key in (
            "scalarConditionalOutput",
            "scalarMultipleOutputs",
            "scalarComponentOutput",
            "scalarEarlyReturn",
            "scalarDiscard",
            "scalarHelperDiscard",
            "scalarTransitiveHelperDiscard",
            "scalarHelperBeforeMain",
            "scalarHelperAfterMain",
        ):
            self.assertEqual(self.result[key], "unproven", key)

    def test_closed_control_flow_does_not_hide_root_output(self) -> None:
        self.assertEqual(self.result["closedControlFlowOpaque"], "opaque")
        self.assertEqual(self.result["closedConditionalPassthrough"], "slot:1")

    def test_exhaustive_branch_preserves_one_sampled_alpha(self) -> None:
        for key in (
            "conditionalAlphaPreserving",
            "conditionalGeneratedRGB",
        ):
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

    def test_generated_rgb_blend_can_preserve_one_sampled_alpha(self) -> None:
        self.assertEqual(
            self.result["generatedRGBPreservedAlpha"],
            "straight-preserving-slot:0",
        )
        source = self.result["generatedRGBPreservedAlphaMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in (
            "generatedRGBReplacedAlpha",
            "generatedRGBSecondColorSource",
        ):
            self.assertNotEqual(
                self.result[key], "straight-preserving-slot:0", key
            )

    def test_conditional_generated_rgb_keeps_an_independent_base_alpha(self) -> None:
        self.assertEqual(
            self.result["conditionalGeneratedRGBPreservedAlpha"],
            "straight-preserving-slot:2",
        )
        self.assertEqual(
            self.result["conditionalGeneratedRGBFact"],
            "carrier:2;generated:0;red:1;green:;blue:;alpha:;" +
            "counts:0:2,1:1,2:1",
        )
        self.assertEqual(
            self.result["conditionalGeneratedRGBComponentScalarFact"],
            "carrier:2;generated:0;red:1;green:3;blue:1;alpha:3;" +
            "counts:0:2,1:2,2:1,3:2",
        )
        source = self.result["conditionalGeneratedRGBMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture2.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        compiler_source = self.result["conditionalGeneratedRGBCompilerLowering"]
        self.assertIn(
            "mwxGenericUnpremultiply(g_Texture2.sample", compiler_source
        )
        self.assertNotIn(
            "mwxGenericUnpremultiply(g_Texture0.sample", compiler_source
        )
        self.assertIn(
            "mwxGenericPremultiply(float4(color, base.w))", compiler_source
        )
        for key in (
            "conditionalGeneratedRGBCompilerRoleSwap",
            "conditionalGeneratedRGBCompilerPostOutput",
            "conditionalGeneratedRGBCompilerCarrierConditionalWrite",
            "conditionalGeneratedRGBCompilerCarrierPrefixWrite",
            "conditionalGeneratedRGBCompilerCompoundExtraOutput",
            "conditionalGeneratedRGBCompilerPrefixExtraOutput",
            "conditionalGeneratedRGBCompilerHiddenHelperSample",
        ):
            self.assertEqual(self.result[key], "unresolved", key)
        self.assertEqual(
            self.result["conditionalGeneratedRGBMultiReturnHelper"],
            "straight-preserving-slot:2",
        )
        for key in (
            "conditionalGeneratedRGBReplacedAlpha",
            "conditionalGeneratedRGBWholeColorSample",
            "conditionalGeneratedRGBHiddenHelperSample",
            "conditionalGeneratedRGBHelperSample",
            "conditionalGeneratedRGBHelperOutputMutation",
            "conditionalGeneratedRGBHelperOutMutation",
            "conditionalGeneratedRGBCallAfterBlend",
            "conditionalGeneratedRGBCallAfterOutput",
            "conditionalGeneratedRGBDiscardAfterOutput",
            "conditionalGeneratedRGBMainBarrier",
            "conditionalGeneratedRGBMainTexelFetch",
            "conditionalGeneratedRGBGlobalWritingHelper",
            "conditionalGeneratedRGBExtraOutput",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

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

    def test_scalar_auxiliaries_can_only_modulate_sampled_alpha(self) -> None:
        self.assertEqual(self.result["straightRGBScalarAlpha"], "straight-slot:0")
        self.assertEqual(
            self.result["straightRGBScalarAlphaFact"], "source:0;aux:1,3"
        )
        source = self.result["straightRGBScalarAlphaMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture3.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in (
            "straightRGBScalarAlphaGreen",
            "straightRGBScalarAlphaRepeatedAux",
            "straightRGBScalarAlphaRGBWrite",
            "straightRGBScalarAlphaReplacement",
            "straightRGBScalarAlphaUnknownHelper",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

    def test_uniform_or_linked_scalar_can_modulate_alpha_without_auxiliary_texture(
        self,
    ) -> None:
        self.assertEqual(
            self.result["straightRGBScalarAlphaNoAux"], "straight-slot:0"
        )
        self.assertEqual(
            self.result["straightRGBScalarAlphaNoAuxFact"], "source:0;aux:"
        )
        source = self.result["straightRGBScalarAlphaNoAuxMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        self.assertEqual(
            self.result["straightRGBScalarAlphaSaturate"],
            "straight-unorm-slot:0",
        )
        source = self.result["straightRGBScalarAlphaSaturateMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxSaturateAndPremultiply(mwxFragColor);", source)
        self.assertEqual(
            self.result["straightRGBScalarAlphaShadowedSaturate"],
            "unresolved",
        )

    def test_optional_mask_must_restore_the_original_after_alpha_mutation(
        self,
    ) -> None:
        self.assertEqual(
            self.result["straightRGBScalarAlphaMasked"], "straight-slot:0"
        )
        self.assertEqual(
            self.result["straightRGBScalarAlphaMaskedFact"],
            "source:0;scalar:;mask:2;aux:2",
        )
        for key in (
            "straightRGBScalarAlphaMaskTransform",
            "straightRGBScalarAlphaMaskShadowedMix",
            "straightRGBScalarAlphaMaskReversed",
            "straightRGBScalarAlphaMaskBeforeAlpha",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

    def test_overlay_alpha_blend_reuses_the_bounded_straight_boundary(self) -> None:
        self.assertEqual(self.result["overlayAlphaBlend"], "straight-slot:0")
        source = self.result["overlayAlphaBlendMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_generated_underlay_blend_has_one_straight_color_boundary(self) -> None:
        self.assertEqual(
            self.result["generatedUnderlayBlend"], "straight-slot:0"
        )
        self.assertEqual(
            self.result["generatedUnderlayBlendRenamed"], "straight-slot:3"
        )
        source = self.result["generatedUnderlayBlendMetal"]
        self.assertEqual(
            source.count("mwxUnpremultiply(mwxTexture0.sample"), 2
        )
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_generated_underlay_blend_rejects_unproven_dataflow(self) -> None:
        for key in (
            "generatedUnderlayDifferentSlot",
            "generatedUnderlayWrongWeight",
            "generatedUnderlayExtraSample",
            "generatedUnderlayGeneratedRGBSample",
            "generatedUnderlayMissingSignal",
            "generatedUnderlayConditional",
        ):
            self.assertEqual(self.result[key], "other", key)

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

    def test_conditional_shadow_has_one_straight_color_boundary(self) -> None:
        self.assertEqual(self.result["conditionalShadow"], "straight-slot:0")
        source = self.result["conditionalShadowMetal"]
        self.assertEqual(source.count("mwxUnpremultiply(mwxTexture0.sample"), 2)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

        self.assertEqual(
            self.result["conditionalShadowModeThirtyHelper"],
            "straight-slot:0",
        )
        mode_thirty_source = self.result["conditionalShadowModeThirtyHelperMetal"]
        self.assertEqual(
            mode_thirty_source.count("mwxUnpremultiply(mwxTexture0.sample"),
            2,
        )
        self.assertIn(
            "return mwxPremultiply(mwxFragColor);",
            mode_thirty_source,
        )

        self.assertEqual(
            self.result["conditionalShadowNormalMaskOff"],
            "straight-slot:0",
        )
        normal_source = self.result["conditionalShadowNormalMaskOffMetal"]
        self.assertEqual(normal_source.count("mwxUnpremultiply(mwxTexture0.sample"), 2)
        self.assertIn("return mwxPremultiply(mwxFragColor);", normal_source)

    def test_conditional_shadow_rejects_unproven_dataflow(self) -> None:
        for key in (
            "conditionalShadowWrongSlot",
            "conditionalShadowExtraSample",
            "conditionalShadowAlphaSubtract",
            "conditionalShadowDifferentAlphaWeight",
            "conditionalShadowWrongFallback",
            "conditionalShadowMutatingHelper",
            "conditionalShadowExtraBranch",
            "conditionalShadowCoordinateMutation",
            "conditionalShadowNormalMaskMutation",
            "conditionalShadowNormalMaskTexture",
            "conditionalShadowNormalDifferentWeight",
            "conditionalShadowNormalVectorWeight",
            "conditionalShadowNormalControlFlow",
            "conditionalShadowNormalWrongHelper",
        ):
            self.assertNotEqual(self.result[key], "straight-slot:0", key)

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
        self.assertEqual(
            self.result["nestedDifferentSlotMixGraph"],
            "interpolated-slots:0,1",
        )
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
        self.assertEqual(
            self.result["alphaPreservingRGBBlend"],
            "straight-preserving-slot:0",
        )
        source = self.result["alphaPreservingMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_rgb_reconstruction_preserves_only_the_proven_source_alpha(self) -> None:
        self.assertEqual(
            self.result["alphaPreservingRGBReconstruction"],
            "straight-preserving-slot:0",
        )
        self.assertEqual(
            self.result["alphaPreservingRGBScalarClamp"],
            "straight-preserving-slot:3",
        )
        self.assertEqual(
            self.result["alphaPreservingRGBRuntimeLoopUnproven"],
            "unresolved",
        )
        self.assertEqual(
            self.result["alphaPreservingRGBRuntimeLoopProven"],
            "straight-preserving-slot:3",
        )
        source = self.result["alphaPreservingRGBReconstructionMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        for key in (
            "alphaPreservingRGBReconstructionDifferentAlpha",
            "alphaPreservingRGBReconstructionOtherColor",
            "alphaPreservingRGBScalarClampReplacement",
        ):
            self.assertNotEqual(
                self.result[key], "straight-preserving-slot:0", key
            )

    def test_rgb_mix_read_preserves_source_alpha(self) -> None:
        self.assertEqual(
            self.result["alphaPreservingRGBMix"],
            "straight-preserving-slot:0",
        )
        source = self.result["alphaPreservingRGBMixMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)

    def test_scanline_uniform_rgb_mix_has_one_straight_color_boundary(self) -> None:
        self.assertEqual(
            self.result["scanlineUniformRGBMix"],
            "straight-preserving-slot:0",
        )
        source = self.result["scanlineUniformRGBMixMetal"]
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", source)
        self.assertNotIn("mwxUnpremultiply(mwxTexture1.sample", source)
        self.assertIn("return mwxPremultiply(mwxFragColor);", source)
        self.assertEqual(
            self.result["scanlineUniformRGBMixDependencyDiamond"],
            "straight-preserving-slot:0",
        )
        for _ in range(32):
            completed = subprocess.run(
                [str(self.binary)], check=True, capture_output=True, text=True
            )
            repeated = json.loads(completed.stdout)
            self.assertEqual(
                repeated["scanlineUniformRGBMixDependencyDiamond"],
                "straight-preserving-slot:0",
            )

    def test_scanline_uniform_rgb_mix_rejects_unproven_shapes(self) -> None:
        for key in (
            "scanlineAlphaRewrite",
            "scanlineSecondColorSample",
            "scanlineUnboundedWeight",
            "scanlineVectorWeight",
            "scanlineCustomMix",
            "scanlineMutatingWeightHelper",
            "scanlineShadowedSmoothstep",
            "scanlineShadowedFloat4",
            "scanlineVaryingTint",
        ):
            self.assertNotEqual(
                self.result[key], "straight-preserving-slot:0", key
            )

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
            self.result["signalCarrierComposite"], "signal-composite:0:1"
        )
        self.assertEqual(
            self.result["signalCarrierCompositeRenamed"],
            "signal-composite:3:1",
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

    def test_signal_carrier_composite_rejects_unsafe_tail_shapes(self) -> None:
        for key in (
            "signalCarrierCompositeWrongBase",
            "signalCarrierCompositeWrongAlpha",
            "signalCarrierCompositeWholeEscape",
            "signalCarrierCompositePostMutation",
            "signalCarrierCompositeShadowedSaturate",
        ):
            self.assertEqual(self.result[key], "unresolved", key)

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
