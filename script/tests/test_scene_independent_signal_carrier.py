#!/usr/bin/env python3

"""Independent RGBA signal carrier source and bounded Metal contract."""

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
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/fluidsimulation"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


def unique_sources(*groups: list[Path] | tuple[Path, ...]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for group in groups:
        for source in group:
            if source not in seen:
                seen.add(source)
                result.append(source)
    return result


PREPROCESSOR_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    *scene_swift_sources("shader_preprocessing_and_variant_implementation"),
    SCENE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SCENE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
]
SWIFT_SOURCES = unique_sources(
    tuple(PREPROCESSOR_SOURCES),
    scene_swift_sources("authored_shader_frontend_core"),
    (
        SCENE_ROOT
        / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    ),
    scene_swift_sources("generic_shader_compiler_preparation_implementation"),
)


HARNESS = r'''
import Foundation
import Metal

private struct Output: Codable {
    let preparedTransfer: String
    let preparedSourceHasHelperChain: Bool
    let boundedMetalCompiled: Bool
    let boundedMetalHasColorBoundary: Bool
    let preparedCompositeTransfer: String
    let preparedCompositeHasExactTail: Bool
    let preparedCompositeMetalCompiled: Bool
    let positive: [String: String]
    let negative: [String: String]
    let artifact: [String: Bool]
}

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""

private func transfer(_ source: String) -> String {
    switch SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source) {
    case let .independentAlphaSignalPreserving(slot): return "signal-preserving:\(slot)"
    case let .independentAlphaSignalCompositing(signal, color):
        return "signal-composite:\(signal):\(color)"
    case let .straightAlphaPreserving(slot): return "straight-preserving:\(slot)"
    case .unresolved: return "unresolved"
    default: return "other"
    }
}

private func fixture(
    signalSlot: Int = 1,
    helper: String = "injectSignal",
    wrapper: String = "shapeSignal",
    updates: Int = 1,
    terminal: String = "return min(current + vec4(amount), vec4(1.0));",
    wrapperBody: String? = nil,
    helperParameters: String = "vec4 current, float amount",
    wrapperCarrierQualifier: String = "",
    mainPrefix: String = "",
    sourceExpression: String? = nil,
    carrierTransform: String = "signal *= step(0.0, drift.x);",
    initialOutputExpression: String = "signal / (1.0 + length(drift))",
    updateExpression: String? = nil,
    extraFunctions: String = ""
) -> String {
    let source = sourceExpression
        ?? "vec4 signal = texSample2D(g_Texture\(signalSlot), v_TexCoord);"
    let wrapperValue = wrapperBody ?? """
        float amount = smoothstep(size, 0.0, length(position - v_TexCoord));
        return \(helper)(current, amount);
        """
    let update = updateExpression
        ?? "gl_FragColor = \(wrapper)(gl_FragColor, m_Position, m_Size);"
    let updateLines = Array(repeating: update, count: updates).joined(separator: "\n")
    return """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture\(signalSlot);
    uniform vec2 m_Position;
    uniform float m_Size;
    varying vec2 v_TexCoord;
    \(extraFunctions)
    vec4 \(helper)(\(helperParameters)) {
        \(terminal)
    }
    vec4 \(wrapper)(\(wrapperCarrierQualifier)vec4 current, vec2 position, float size) {
        \(wrapperValue)
    }
    void main() {
        vec2 drift = texSample2D(g_Texture0, v_TexCoord).xy;
        \(mainPrefix)
        \(source)
        \(carrierTransform)
        gl_FragColor = \(initialOutputExpression);
        \(updateLines)
    }
    """
}

private func preparedSource(stockRoot: URL, looseRoot: URL) throws -> String {
    let path = "shaders/effects/fluidsimulation_advection.frag"
    let view = SceneResourceView(
        projectRootURL: looseRoot,
        packageRootURL: nil,
        stockAssetsRootURL: stockRoot
    )
    let graph = SceneShaderSourceGraphBuilder().build(
        roots: [.init(label: "fragment", virtualPath: path)],
        resourceView: view
    )
    let values: [String: Int64] = [
        "DYE": 1, "POINTEMITTER": 1, "LINEEMITTER": 0,
        "RENDERING": 0, "PERSPECTIVE": 0, "DYEEMITTER": 0,
        "COLLISIONMASK": 0,
    ]
    let environment = try SceneShaderVariantEnvironment(
        stage: .fragment,
        combos: values.map {
            .init(name: $0.key, definition: .defined(.integer($0.value)))
        }
    )
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: path,
        graph: graph,
        environment: environment
    ) {
    case let .success(prepared): return prepared.source
    case let .failure(failure):
        throw NSError(
            domain: "prepared-source", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(failure.diagnostics)"]
        )
    }
}

private func preparedCompositeSource(stockRoot: URL) throws -> String {
    let path = "shaders/effects/fluidsimulation_combine.frag"
    let globalStockRoot = stockRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = SceneResourceView(
        projectRootURL: stockRoot,
        packageRootURL: nil,
        stockAssetsRootURL: globalStockRoot
    )
    let graph = SceneShaderSourceGraphBuilder().build(
        roots: [.init(label: "fragment", virtualPath: path)],
        resourceView: view
    )
    let values: [String: Int64] = [
        "BLENDMODE": 31, "RENDERING": 0, "OPAQUE": 0,
        "WRITEALPHA": 1, "PERSPECTIVE": 0, "LIGHTING": 0,
        "LIGHTS_SHADOW_MAPPING": 0, "LIGHTS_COOKIE": 0,
    ]
    let environment = try SceneShaderVariantEnvironment(
        stage: .fragment,
        combos: values.map {
            .init(name: $0.key, definition: .defined(.integer($0.value)))
        }
    )
    switch SceneShaderPreprocessor().preprocess(
        rootRelativePath: path,
        graph: graph,
        environment: environment
    ) {
    case let .success(prepared): return prepared.source
    case let .failure(failure):
        throw NSError(
            domain: "prepared-composite-source", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(failure.diagnostics)"]
        )
    }
}

private func artifactChecks(authored: String) -> [String: Bool] {
    let reflection = Data(#"{"types":{"_1":{"members":[{"name":"mwxRenderSize","type":"vec2","offset":0},{"name":"mwxTexture0Transform0","type":"vec4","offset":16},{"name":"mwxTexture0Transform1","type":"vec4","offset":32},{"name":"mwxTexture1Transform0","type":"vec4","offset":48},{"name":"mwxTexture1Transform1","type":"vec4","offset":64}]}},"ubos":[{"type":"_1","block_size":80,"set":0,"binding":8}],"textures":[{"name":"g_Texture0","binding":0},{"name":"g_Texture1","binding":1}]}"#.utf8)
    let uniforms = "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };"
    let fragmentMSL = """
    #include <metal_stdlib>
    using namespace metal;
    \(uniforms)
    float4 injectSignal(float4 current, float amount) {
        return min(current + float4(amount), float4(1.0));
    }
    float4 shapeSignal(float4 current, float2 position, float size) {
        float amount = smoothstep(size, 0.0, length(position));
        return injectSignal(current, amount);
    }
    fragment void f() {
        float2 drift = g_Texture0.sample(g_Texture0Smplr, float2(0.5)).xy;
        float4 signal = g_Texture1.sample(g_Texture1Smplr, float2(0.5));
        out.mwxFragColor = signal / (1.0 + length(drift));
        out.mwxFragColor = shapeSignal(out.mwxFragColor, float2(0.5), 0.1);
    }
    """
    let built = SceneGenericShaderArtifactBuilder.build(
        requestKey: String(repeating: "d", count: 64),
        backendID: "glslang-spirv-cross-msl-v2",
        stages: [
            .init(
                name: "vertex", source: vertex, authoredSource: vertex,
                msl: uniforms, reflection: reflection
            ),
            .init(
                name: "fragment", source: authored,
                authoredSource: authored, msl: fragmentMSL,
                reflection: reflection
            ),
        ],
        maximumArtifactBytes: 1_024_000
    )
    guard case let .success(artifact) = built else {
        return ["builderAccepted": false]
    }
    let expectedUse = SceneAuthoredShaderFrontend.compile(
        vertexSource: vertex, fragmentSource: authored
    ).program?.fragmentOutputChannelUse ?? .unproven
    func program(_ value: SceneGenericShaderProgramArtifact,
                 expected: SceneShaderColorTransfer)
        -> SceneAuthoredShaderProgram? {
        value.makeProgram(
            expectedKey: String(repeating: "d", count: 64),
            expectedColorTransfer: expected,
            expectedFragmentOutputChannelUse: expectedUse
        )
    }
    func tamper(_ mutate: (inout [String: Any]) -> Void)
        -> SceneGenericShaderProgramArtifact? {
        guard var object = try? JSONSerialization.jsonObject(
            with: JSONEncoder().encode(artifact)
        ) as? [String: Any] else { return nil }
        mutate(&object)
        guard let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? JSONDecoder().decode(
            SceneGenericShaderProgramArtifact.self, from: data
        )
    }
    let wrongKind = tamper { root in
        var program = root["program"] as! [String: Any]
        var transfer = program["colorTransfer"] as! [String: Any]
        transfer["kind"] = "straight-alpha-preserving"
        program["colorTransfer"] = transfer
        root["program"] = program
    }
    let wrongSlot = tamper { root in
        var program = root["program"] as! [String: Any]
        var transfer = program["colorTransfer"] as! [String: Any]
        transfer["slot"] = 7
        program["colorTransfer"] = transfer
        root["program"] = program
    }
    let wrongBinding = tamper { root in
        var program = root["program"] as! [String: Any]
        var bindings = program["textureBindings"] as! [[String: Any]]
        bindings[1]["name"] = "g_Texture7"
        program["textureBindings"] = bindings
        root["program"] = program
    }
    let expected: SceneShaderColorTransfer =
        .independentAlphaSignalPreserving(textureSlot: 1)
    let accepted = program(artifact, expected: expected)
    return [
        "builderAccepted": artifact.program.colorTransfer.kind
            == "independent-alpha-signal-preserving"
            && artifact.program.colorTransfer.slot == 1,
        "noColorBoundary": !artifact.program.metalSource.contains("Unpremultiply")
            && !artifact.program.metalSource.contains("Premultiply")
            && !artifact.program.metalSource.contains("unpremultiply")
            && !artifact.program.metalSource.contains("premultiply"),
        "decoderAccepted": accepted?.backend == .genericCompilerArtifact
            && accepted?.colorTransfer == expected,
        "premultExpectedRejected": program(
            artifact,
            expected: .straightAlphaPreserving(textureSlot: 1)
        ) == nil,
        "unresolvedPromotionRejected": program(
            artifact, expected: .unresolved
        ) == nil,
        "kindTamperRejected": wrongKind.flatMap {
            program($0, expected: expected)
        } == nil,
        "slotTamperRejected": wrongSlot.flatMap {
            program($0, expected: expected)
        } == nil,
        "bindingTamperRejected": wrongBinding.flatMap {
            program($0, expected: expected)
        } == nil,
    ]
}

@main
private enum Harness {
    static func main() throws {
        let prepared = try preparedSource(
            stockRoot: URL(fileURLWithPath: CommandLine.arguments[1]),
            looseRoot: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex, fragmentSource: prepared
        ).program
        let metal = bounded?.metalSource ?? ""
        let metalCompiled: Bool
        if let device = MTLCreateSystemDefaultDevice(), !metal.isEmpty {
            metalCompiled = (try? device.makeLibrary(source: metal, options: nil)) != nil
        } else { metalCompiled = false }
        let preparedComposite = try preparedCompositeSource(
            stockRoot: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let boundedComposite = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: preparedComposite
        ).program
        let compositeMetal = boundedComposite?.metalSource ?? ""
        let compositeMetalCompiled: Bool
        if let device = MTLCreateSystemDefaultDevice(), !compositeMetal.isEmpty {
            compositeMetalCompiled =
                (try? device.makeLibrary(source: compositeMetal, options: nil)) != nil
        } else { compositeMetalCompiled = false }

        let positive = [
            "renamed": transfer(fixture(
                helper: "accumulateCarrier", wrapper: "boundedInjection"
            )),
            "alternateSlot": transfer(fixture(signalSlot: 3)),
            "twoUpdates": transfer(fixture(updates: 2)),
            "localAndParameterWrites": transfer(fixture(
                wrapperBody: "position.x += size; vec4 scratch = vec4(0.0); scratch[0]++; scratch.xy *= 0.5; float amount = smoothstep(size, 0.0, length(position - v_TexCoord)); return injectSignal(current, amount);"
            )),
            "pureRGBScalarRead": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb), m_Size) * 0.5;"
            )),
            "projectedSampleVectorCopy": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift;",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "exactScalarUniform": transfer(fixture(
                carrierTransform: "signal *= m_Size;"
            )),
        ]
        let negative = [
            "secondColor": transfer(fixture(
                mainPrefix: "vec4 hidden = texSample2D(g_Texture0, v_TexCoord);"
            )),
            "carrierMissing": transfer(fixture(
                updateExpression: "gl_FragColor = shapeSignal(vec4(0.0), m_Position, m_Size);"
            )),
            "splitRGBA": transfer(fixture(
                sourceExpression: "vec4 signal = vec4(texSample2D(g_Texture1, v_TexCoord).rgb, texSample2D(g_Texture1, v_TexCoord).a);"
            )),
            "outParameter": transfer(fixture(
                wrapperCarrierQualifier: "out "
            )),
            "inoutParameter": transfer(fixture(
                wrapperCarrierQualifier: "inout "
            )),
            "duplicateParameter": transfer(fixture(
                helperParameters: "vec4 current, float current"
            )),
            "carrierWrite": transfer(fixture(
                wrapperBody: "current = vec4(0.0); return injectSignal(current, 0.5);"
            )),
            "carrierAlias": transfer(fixture(
                wrapperBody: "vec4 alias = current; return injectSignal(alias, 0.5);"
            )),
            "carrierMemberRead": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float leaked = signal.r;"
            )),
            "carrierCallEscape": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); mutate(signal.rgb);",
                extraFunctions: "void mutate(inout vec3 value) { value = vec3(0.0); }"
            )),
            "carrierPrefixIncrement": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); ++signal.r;"
            )),
            "carrierPostfixIncrement": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); signal.r++;"
            )),
            "carrierNestedCompoundWrite": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); signal.rgb.xy += vec2(0.5);"
            )),
            "carrierComponentAssignment": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); signal.rgb = vec3(0.0);"
            )),
            "carrierInoutScalar": transfer(fixture(
                carrierTransform: "signal *= dirtyScalar(signal);",
                extraFunctions: "float dirtyScalar(inout vec4 value) { value = vec4(0.0); return 0.5; }"
            )),
            "carrierDirtyScalar": transfer(fixture(
                carrierTransform: "signal *= dirtyScalar();",
                extraFunctions: "float leakedScalar; float dirtyScalar() { leakedScalar = 1.0; return leakedScalar; }"
            )),
            "carrierMutatedLocalScalar": transfer(fixture(
                mainPrefix: "float dirtyFactor = 0.5; dirtyFactor = dirtyScalar();",
                carrierTransform: "signal *= dirtyFactor;",
                extraFunctions: "float dirtyScalar() { return 1.0; }"
            )),
            "dirtyVectorInitializer": transfer(fixture(
                mainPrefix: "vec2 dirtyVector = dirtyVectorHelper();",
                carrierTransform: "signal *= step(0.0, dirtyVector.x);",
                extraFunctions: "vec2 dirtyVectorHelper() { return vec2(0.0); }"
            )),
            "vectorReassignment": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; driftCopy = vec2(0.0);",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "vectorMemberAssignment": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; driftCopy.x = 0.0;",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "vectorInoutEscape": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; mutateVector(driftCopy);",
                carrierTransform: "signal *= step(0.0, driftCopy.x);",
                extraFunctions: "void mutateVector(inout vec2 value) { value = vec2(0.0); }"
            )),
            "vectorPrefixIncrement": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; ++driftCopy.x;",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "vectorPostfixIncrement": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; driftCopy.x++;",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "vectorParenthesizedPrefixIncrement": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; ++(driftCopy.x);",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "vectorShiftCompound": transfer(fixture(
                mainPrefix: "vec2 driftCopy = drift; driftCopy >>= 1;",
                carrierTransform: "signal *= step(0.0, driftCopy.x);"
            )),
            "rgbScalarInoutEscape": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb), m_Size) * 0.5; mutateScalar(energy);",
                carrierTransform: "signal *= energy;",
                extraFunctions: "void mutateScalar(inout float value) { value = 0.0; }"
            )),
            "rgbScalarPrefixIncrement": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb), m_Size) * 0.5; ++energy;",
                carrierTransform: "signal *= energy;"
            )),
            "rgbScalarPostfixIncrement": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb), m_Size) * 0.5; energy++;",
                carrierTransform: "signal *= energy;"
            )),
            "rgbScalarNestedPrefixDecrement": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb), m_Size) * 0.5; --((energy));",
                carrierTransform: "signal *= energy;"
            )),
            "scalarShiftCompound": transfer(fixture(
                mainPrefix: "int factor = 1; factor <<= 1;",
                carrierTransform: "signal *= factor;"
            )),
            "uniformLocalShadow": transfer(fixture(
                mainPrefix: "float m_Size = dirtyScalar();",
                carrierTransform: "signal *= m_Size;",
                extraFunctions: "float dirtyScalar() { return 1.0; }"
            )),
            "localRedeclaration": transfer(fixture(
                mainPrefix: "float factor = 0.5; float factor = 0.5;",
                carrierTransform: "signal *= factor;"
            )),
            "carrierGlobalScalar": transfer(fixture(
                carrierTransform: "signal *= leakedScalar;",
                extraFunctions: "float leakedScalar;"
            )),
            "carrierResourceScalar": transfer(fixture(
                carrierTransform: "signal *= texSample2D(g_Texture0, v_TexCoord).x;"
            )),
            "carrierRecursiveScalar": transfer(fixture(
                carrierTransform: "signal *= recursiveScalar(0.5);",
                extraFunctions: "float recursiveScalar(float value) { return recursiveScalar(value); }"
            )),
            "carrierShadowedScalarBuiltin": transfer(fixture(
                extraFunctions: "float step(float edge, float value) { return value; }"
            )),
            "initialOutputDirtyScalar": transfer(fixture(
                initialOutputExpression: "signal / dirtyScalar()",
                extraFunctions: "float leakedScalar; float dirtyScalar() { leakedScalar = 1.0; return leakedScalar; }"
            )),
            "pureRGBLengthProjection": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb).x, m_Size) * 0.5;"
            )),
            "pureRGBLengthIndex": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb)[0], m_Size) * 0.5;"
            )),
            "pureRGBExtraProjection": transfer(fixture(
                sourceExpression: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); float energy = step(length(signal.rgb.x), m_Size) * 0.5;"
            )),
            "recursion": transfer(fixture(
                wrapperBody: "return shapeSignal(current, position, size);"
            )),
            "globalWrite": transfer(fixture(
                terminal: "m_Size = amount; return min(current + vec4(amount), vec4(1.0));"
            )),
            "outputWrite": transfer(fixture(
                terminal: "gl_FragColor = current; return current;"
            )),
            "unreachableOutputRead": transfer(fixture(
                extraFunctions: "vec4 hiddenOutputRead() { return gl_FragColor; }"
            )),
            "unreachableOutputWrite": transfer(fixture(
                extraFunctions: "void hiddenOutputWrite() { gl_FragColor = vec4(0.0); }"
            )),
            "wrongBuiltinArity": transfer(fixture(
                wrapperBody: "float amount = smoothstep(size, 0.0); return injectSignal(current, amount);"
            )),
            "shadowedBoundedBuiltin": transfer(fixture(
                extraFunctions: "float smoothstep(float edge0, float edge1, float value) { return value; }"
            )),
            "shadowedClampBuiltin": transfer(fixture(
                extraFunctions: "vec4 min(vec4 first, vec4 second) { return first; }"
            )),
            "globalMemberIncrement": transfer(fixture(
                terminal: "leakedColor.x++; return min(current + vec4(amount), vec4(1.0));",
                extraFunctions: "vec4 leakedColor;"
            )),
            "globalNestedMemberWrite": transfer(fixture(
                terminal: "leakedColor.xy.x = amount; return min(current + vec4(amount), vec4(1.0));",
                extraFunctions: "vec4 leakedColor;"
            )),
            "globalIndexIncrement": transfer(fixture(
                terminal: "leakedColor[int(amount)]++; return min(current + vec4(amount), vec4(1.0));",
                extraFunctions: "vec4 leakedColor;"
            )),
            "resourceSideEffect": transfer(fixture(
                terminal: "imageStore(g_Image, ivec2(0), current); return current;",
                extraFunctions: "uniform image2D g_Image;"
            )),
            "duplicate": transfer(fixture(
                extraFunctions: "vec4 injectSignal(vec4 c, float a) { return c; }"
            )),
            "multipleReturn": transfer(fixture(
                terminal: "if (amount > 0.5) { return current; } return min(current + vec4(amount), vec4(1.0));"
            )),
            "extraOutput": transfer(fixture(
                updateExpression: "gl_FragColor = shapeSignal(gl_FragColor, m_Position, m_Size); gl_FragColor = vec4(0.0);"
            )),
            "conditionalInit": transfer(fixture(
                sourceExpression: "vec4 signal; if (m_Size > 0.0) { signal = texSample2D(g_Texture1, v_TexCoord); }"
            )),
            "componentMutation": transfer(fixture(
                mainPrefix: "vec4 signal = texSample2D(g_Texture1, v_TexCoord); signal.a *= 0.5;",
                sourceExpression: ""
            )),
            "unbounded": transfer(fixture(
                terminal: "return min(current + vec4(amount * 2.0), vec4(1.0));"
            )),
        ]
        let output = Output(
            preparedTransfer: transfer(prepared),
            preparedSourceHasHelperChain:
                prepared.contains("AddEmitterColor")
                && prepared.contains("EmitterColor")
                && prepared.contains("gl_FragColor = EmitterColor"),
            boundedMetalCompiled: metalCompiled,
            boundedMetalHasColorBoundary:
                metal.contains("mwxUnpremultiply") || metal.contains("mwxPremultiply"),
            preparedCompositeTransfer: transfer(preparedComposite),
            preparedCompositeHasExactTail:
                preparedComposite.contains(
                    "albedo.rgb = ApplyBlending(31, prev.rgb, albedo.rgb, albedo.a * u_Alpha);"
                )
                && preparedComposite.contains(
                    "albedo.a = saturate(prev.a + albedo.a);"
                ),
            preparedCompositeMetalCompiled: compositeMetalCompiled,
            positive: positive,
            negative: negative,
            artifact: artifactChecks(authored: fixture())
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneIndependentSignalCarrierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-carrier-"
        )
        temporary = Path(cls.temporary_directory.name)
        harness = temporary / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.loose = temporary / "loose"
        cls.loose.mkdir()
        cls.binary = temporary / "independent-signal-carrier"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(STOCK_ROOT), str(cls.loose)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.output = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_bundled_active_source_compiles_as_raw_independent_signal(self) -> None:
        self.assertEqual(self.output["preparedTransfer"], "signal-preserving:1")
        self.assertTrue(self.output["preparedSourceHasHelperChain"])
        self.assertTrue(self.output["boundedMetalCompiled"])
        self.assertFalse(self.output["boundedMetalHasColorBoundary"])

    def test_bundled_combine_source_uses_signal_over_color_contract(self) -> None:
        self.assertEqual(
            self.output["preparedCompositeTransfer"],
            "signal-composite:0:1",
        )
        self.assertTrue(self.output["preparedCompositeHasExactTail"])
        self.assertTrue(self.output["preparedCompositeMetalCompiled"])

    def test_identity_independent_positive_and_unseen_combinations(self) -> None:
        self.assertEqual(self.output["positive"], {
            "renamed": "signal-preserving:1",
            "alternateSlot": "signal-preserving:3",
            "twoUpdates": "signal-preserving:1",
            "localAndParameterWrites": "signal-preserving:1",
            "pureRGBScalarRead": "signal-preserving:1",
            "projectedSampleVectorCopy": "signal-preserving:1",
            "exactScalarUniform": "signal-preserving:1",
        })

    def test_unsafe_or_ambiguous_shapes_fail_closed(self) -> None:
        self.assertTrue(self.output["negative"])
        for key, value in self.output["negative"].items():
            with self.subTest(key=key):
                self.assertEqual(value, "unresolved")

    def test_generic_artifact_preserves_exact_signal_contract(self) -> None:
        self.assertTrue(self.output["artifact"])
        self.assertEqual(
            [name for name, passed in self.output["artifact"].items() if not passed],
            [],
            self.output["artifact"],
        )


if __name__ == "__main__":
    unittest.main()
