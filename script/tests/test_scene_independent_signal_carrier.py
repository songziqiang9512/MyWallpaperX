#!/usr/bin/env python3

"""Independent RGBA signal carrier source and bounded Metal contract."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/fluidsimulation"
)
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from generate_scene_shader_cache_identity import build_identity, write_identity  # noqa: E402


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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderSourceGraph.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderLegacyAnnotationJSON.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContract.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    *scene_swift_sources("shader_preprocessing_and_variant_implementation"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneShaderSourceResolver.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneShaderSourceGraphBuilder.swift",
]
SWIFT_SOURCES = unique_sources(
    tuple(PREPROCESSOR_SOURCES),
    scene_swift_sources("authored_shader_frontend_core"),
    (
        REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
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
        compatibilityTarget: .windowsDX11ShaderModel4,
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
        compatibilityTarget: .windowsDX11ShaderModel4,
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

// Self-authored generic carrier/data fixtures, independent of the real shader.
private func rgbaDataFixture(
    update: String = "min(gl_FragColor + vec4(field.rgb, 1.0) * field.a, vec4(1.0))",
    metadata: String = #" // {"mode":"rgbmask"}"#,
    helpers: String = "", before: String = "", after: String = ""
) -> String {
    """
    uniform sampler2D g_Texture1;
    uniform sampler2D g_Texture4;\(metadata)
    varying vec2 v_TexCoord;
    \(helpers)
    void main() {
        vec4 state = texSample2D(g_Texture1, v_TexCoord);
        vec4 field = texSample2D(g_Texture4, v_TexCoord);
        \(before)
        gl_FragColor = state;
        gl_FragColor = \(update);
        \(after)
    }
    """
}

private func rgbaDataFacts(_ source: String) -> [String: Any] {
    let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
        lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: .fragment), stage: .fragment)
    let slot = syntax.unit.flatMap { SceneAuthoredShaderIndependentSignalCarrierAnalyzer.analyze($0) }
    return ["syntaxDiagnostics": syntax.diagnostics.count,
            "carrierSlot": slot.map { $0 as Any } ?? NSNull(), "transfer": transfer(source)]
}

private func rgbaDataCPUOutput() -> [String: Any] {
    let base = rgbaDataFixture()
    let helper = "vec4 AddField(vec4 current, vec4 value) { return min(current + vec4(value.rgb, 1.0) * value.a, vec4(1.0)); }"
    let sources: [String: String] = [
        "inline": base,
        "renamed": base.replacingOccurrences(of: "state", with: "historyValue").replacingOccurrences(of: "field", with: "paintValue"),
        "renamedSlots": base.replacingOccurrences(of: "g_Texture1", with: "g_Texture3").replacingOccurrences(of: "g_Texture4", with: "g_Texture6"),
        "sumSwap": rgbaDataFixture(update: "min(vec4(field.rgb, 1.0) * field.a + gl_FragColor, vec4(1.0))"),
        "minSwap": rgbaDataFixture(update: "min(vec4(1.0), gl_FragColor + vec4(field.rgb, 1.0) * field.a)"),
        "parentheses": rgbaDataFixture(update: "min((gl_FragColor + vec4((field.rgb), 1.0) * (field.a)), vec4(1.0))"),
        "helper": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper),
        "cast4Helper": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper.replacingOccurrences(of: "vec4(1.0)", with: "CAST4(1.0)")),
        "cast4Renamed": base.replacingOccurrences(of: "vec4(1.0)", with: "CAST4(1.0)").replacingOccurrences(of: "state", with: "previousValue").replacingOccurrences(of: "field", with: "sourceValue"),
        "cast4Shadow": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: "vec4 CAST4(float value) { return vec4(value); } " + helper.replacingOccurrences(of: "vec4(1.0)", with: "CAST4(1.0)")),
        "cast4UnknownArgument": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, 1.0) * field.a, CAST4(Unknown()))"),
        "sampleAlias": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, alias.a), vec4(1.0))", before: "vec4 alias = field;"),
        "missingMetadata": rgbaDataFixture(metadata: ""),
        "wrongMetadata": rgbaDataFixture(metadata: #" // {"mode":"opacitymask"}"#),
        "movedMetadata": base.replacingOccurrences(of: #"g_Texture4; // {"mode":"rgbmask"}"#, with: #"g_Texture4;"# + "\n" + #"// {"mode":"rgbmask"}"#),
        "wrongDeclarationMetadata": base.replacingOccurrences(of: #"g_Texture4; // {"mode":"rgbmask"}"#, with: #"g_Texture4;"#).replacingOccurrences(of: "g_Texture1;", with: #"g_Texture1; // {"mode":"rgbmask"}"#),
        "duplicateSampler": base.replacingOccurrences(of: "varying vec2", with: "uniform sampler2D g_Texture4;\nvarying vec2"),
        "unrelatedColor": rgbaDataFixture(helpers: "uniform sampler2D g_Texture2;", before: "vec4 extra = texSample2D(g_Texture2, v_TexCoord);"),
        "missingAlpha": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, 1.0), vec4(1.0))"),
        "missingRGB": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.a), vec4(1.0))"),
        "wrongAlphaChannel": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, 1.0) * field.r, vec4(1.0))"),
        "wrongAuxiliaryAlpha": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, 1.0) * other.a, vec4(1.0))", helpers: #"uniform sampler2D g_Texture6; // {"mode":"rgbmask"}"#, before: "vec4 other = texSample2D(g_Texture6, v_TexCoord);"),
        "sameSamplerDifferentValue": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, other.a), vec4(1.0))", before: "vec4 other = texSample2D(g_Texture4, v_TexCoord + vec2(0.1));"),
        "unboundedAdd": rgbaDataFixture(update: "gl_FragColor + vec4(field.rgb, 1.0) * field.a"),
        "wrongLimit": rgbaDataFixture(update: "min(gl_FragColor + vec4(field.rgb, 1.0) * field.a, vec4(0.5))"),
        "duplicateCarrier": rgbaDataFixture(update: "min(gl_FragColor + gl_FragColor * field.a, vec4(1.0))"),
        "unknownUpdate": rgbaDataFixture(update: "Unknown(gl_FragColor, field)"),
        "helperEscape": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper.replacingOccurrences(of: "return min", with: "Unknown(value); return min")),
        "zeroArgumentEscape": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper.replacingOccurrences(of: "return min", with: "float weight = saturate(Unknown()); return min").replacingOccurrences(of: "* value.a", with: "* value.a * weight")),
        "nestedUnknownArgument": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: "vec4 NextField(vec4 current, vec4 value, float factor) { return min(current + vec4(value.rgb, 1.0) * value.a * factor, vec4(1.0)); } vec4 AddField(vec4 current, vec4 value) { return NextField(current, value, saturate(Unknown())); }"),
        "outParameter": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper.replacingOccurrences(of: "vec4 current", with: "out vec4 current")),
        "inoutParameter": rgbaDataFixture(update: "AddField(gl_FragColor, field)", helpers: helper.replacingOccurrences(of: "vec4 current", with: "inout vec4 current")),
        "conditionalFirstWrite": base.replacingOccurrences(of: "gl_FragColor = state;", with: "if (v_TexCoord.x > 0.5) { gl_FragColor = state; }"),
        "initializerRead": base.replacingOccurrences(of: "gl_FragColor = state;", with: "gl_FragColor = gl_FragColor + state;"),
        "partialCarrierWrite": rgbaDataFixture(after: "gl_FragColor.a *= 0.5;"),
    ]
    return ["cases": sources.mapValues(rgbaDataFacts), "oldCarrier": transfer(fixture())]
}

private struct ActualCarrierInput: Decodable {
    let contract: SceneShaderContract
    let combos: [String: Int]
}

private func actualCarrierFacts(_ path: String) throws -> [String: Any] {
    let input = try JSONDecoder().decode(ActualCarrierInput.self,
        from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard let graph = input.contract.sourceGraph,
          let stage = input.contract.stages.first(where: { $0.kind == .fragment }) else {
        throw NSError(domain: "missing-actual-contract", code: 1)
    }
    let environment = try SceneShaderVariantResolver.resolve(
        stage: .fragment, stages: input.contract.stages, compatibilityTarget: .windowsDX11ShaderModel4,
        explicitCombos: input.combos, textureReadiness: [0: true, 1: true, 2: true, 3: false, 4: true]).get()
    let prepared = try SceneShaderPreprocessor().preprocess(
        rootRelativePath: stage.relativePath, graph: graph, environment: environment).get()
    return ["facts": rgbaDataFacts(prepared.source),
            "preparedSourceSHA256": SceneShaderStableDigest.hash(Data(prepared.source.utf8)),
            "preparedSHA256": prepared.preparedSHA256,
            "environment": try JSONSerialization.jsonObject(with: JSONEncoder().encode(environment))]
}

private func rgbaCacheOutput() throws -> [String: Any] {
    var programs: [String: Any] = [:]
    for (name, source) in [("old", fixture()), ("rgba", rgbaDataFixture())] {
        let first = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: source)
        let second = SceneAuthoredShaderFrontend.compile(vertexSource: vertex, fragmentSource: source)
        guard let a = first.program, let b = second.program else {
            throw NSError(domain: "cache-no-program", code: 1)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(a)
        guard bytes == (try encoder.encode(b)) else { throw NSError(domain: "memory-cache-drift", code: 1) }
        programs[name] = try JSONSerialization.jsonObject(with: bytes)
    }
    return programs
}

@main
private enum Harness {
    static func main() throws {
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        guard !home.isEmpty, Bundle.main.bundleIdentifier == "com.songziqiang.MyWallpaperX",
              cache.standardizedFileURL.path.hasPrefix(home + "/") else {
            throw NSError(domain: "private-cache-unavailable", code: 1)
        }
        if CommandLine.arguments.dropFirst().first == "--rgba-data-cpu" {
            var output = rgbaDataCPUOutput()
            if CommandLine.arguments.count > 2 { output["actual"] = try actualCarrierFacts(CommandLine.arguments[2]) }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
            return
        }
        if CommandLine.arguments.dropFirst().first == "--rgba-data-cache" {
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rgbaCacheOutput(), options: [.sortedKeys]))
            return
        }
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
        cls.binary = temporary / "Probe.app/Contents/MacOS/independent-signal-carrier"
        cls.binary.parent.mkdir(parents=True)
        (cls.binary.parent.parent / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.songziqiang.MyWallpaperX", "CFBundleExecutable": cls.binary.name,
            "CFBundlePackageType": "APPL"}))
        identity_resource = cls.binary.parent.parent / "Resources/SceneShaderCacheIdentity.json"
        cls.cache_identity = build_identity(REPOSITORY_ROOT, {"testHarness": "independent-signal-carrier"})
        write_identity(identity_resource, cls.cache_identity)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        cls.home = temporary / "private-home"; cls.home.mkdir()
        environment.update(HOME=str(cls.home), CFFIXED_USER_HOME=str(cls.home))
        cls.environment = environment
        cls.proof = Path(os.environ["MWX_INDEPENDENT_SIGNAL_PROOF"]) if os.environ.get("MWX_INDEPENDENT_SIGNAL_PROOF") else None
        cls.inputs = [*SWIFT_SOURCES, harness, identity_resource, Path(__file__), REPOSITORY_ROOT / "script/scene_swift_source_sets.py"]
        cls.before = cls.input_identities()
        cls.record("inputs-before.json", cls.before)
        started = time.monotonic()
        command = [
                swiftc,
                "-parse-as-library",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o", str(cls.binary),
            ]
        cls.record("compile-command.json", command)
        compilation = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        cls.record("compile-result.json", {"exit": compilation.returncode, "seconds": time.monotonic() - started})
        cls.record("compile.stdout", compilation.stdout.encode()); cls.record("compile.stderr", compilation.stderr.encode())
        if compilation.returncode != 0:
            cls.temporary_directory.cleanup()
            raise RuntimeError(compilation.stderr)
        cls._legacy_output = None

    @property
    def output(self) -> dict:
        # A focused source-proof method must not initialize a Metal device.
        # Existing rendering methods still share their original real GPU run.
        if self.__class__._legacy_output is None:
            completed = subprocess.run(
                [str(self.binary), str(STOCK_ROOT), str(self.loose)],
                cwd=REPOSITORY_ROOT,
                env=self.environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.__class__._legacy_output = json.loads(completed.stdout)
        return self.__class__._legacy_output

    @classmethod
    def tearDownClass(cls) -> None:
        after = cls.input_identities(); cls.record("inputs-after.json", after)
        drift = [a["path"] for a, b in zip(cls.before, after) if a != b]
        cls.record("source-drift.json", drift)
        cls.temporary_directory.cleanup()
        cls.record("retirement.json", {"temporaryRemoved": not cls.binary.exists(),
                                      "legacyGPUProbeExecuted": cls._legacy_output is not None})
        if drift: raise AssertionError(f"input drift: {drift}")

    @classmethod
    def input_identities(cls) -> list[dict]:
        return [{"path": str(p), "bytes": p.stat().st_size,
                 "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in cls.inputs]

    @classmethod
    def record(cls, name: str, value) -> None:
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
            (cls.proof / name).write_bytes(value if isinstance(value, bytes) else (json.dumps(value, indent=2) + "\n").encode())

    def test_typed_rgba_auxiliary_carrier_proof_cpu(self) -> None:
        cpu_home = self.home.parent / "cpu-home"; cpu_home.mkdir()
        cpu_environment = {**self.environment, "HOME": str(cpu_home), "CFFIXED_USER_HOME": str(cpu_home)}
        command = [str(self.binary), "--rgba-data-cpu"]
        if os.environ.get("MWX_INDEPENDENT_SIGNAL_ACTUAL_INPUT"): command.append(os.environ["MWX_INDEPENDENT_SIGNAL_ACTUAL_INPUT"])
        self.record("run-command.json", command)
        completed = subprocess.run(command,
                                   cwd=REPOSITORY_ROOT, env=cpu_environment,
                                   capture_output=True, text=True, timeout=30)
        self.record("run-result.json", {"exit": completed.returncode})
        self.record("observations.json", completed.stdout.encode()); self.record("run.stderr", completed.stderr.encode())
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        output = json.loads(completed.stdout)
        positive = {"inline", "renamed", "renamedSlots", "sumSwap", "minSwap", "parentheses", "helper", "cast4Helper", "cast4Renamed", "sampleAlias"}
        self.assertEqual(output["oldCarrier"], "signal-preserving:1")
        self.assertEqual(len(output["cases"]), 35)
        for name, facts in output["cases"].items():
            with self.subTest(case=name):
                if name == "duplicateSampler": self.assertGreater(facts["syntaxDiagnostics"], 0, facts)
                else: self.assertEqual(facts["syntaxDiagnostics"], 0, facts)
                expected = 3 if name == "renamedSlots" else 1
                if name in positive:
                    self.assertEqual(facts["carrierSlot"], expected, facts)
                    self.assertEqual(facts["transfer"], f"signal-preserving:{expected}", facts)
                else:
                    self.assertIsNone(facts["carrierSlot"], facts)
                    self.assertNotIn("signal-", facts["transfer"], facts)
        if "actual" in output:
            self.assertEqual(output["actual"]["facts"]["carrierSlot"], 1, output["actual"])
            self.assertEqual(output["actual"]["facts"]["transfer"], "signal-preserving:1", output["actual"])
        cache_home = self.home.parent / "cache-home"; cache_home.mkdir()
        cache_environment = {**self.environment, "HOME": str(cache_home), "CFFIXED_USER_HOME": str(cache_home)}
        self.assertEqual(list(cache_home.rglob("*.json")), [])
        snapshots = []
        for phase in ("cold", "warm"):
            run = subprocess.run([str(self.binary), "--rgba-data-cache"], cwd=REPOSITORY_ROOT,
                                 env=cache_environment, capture_output=True, text=True, timeout=30)
            self.record(f"cache-{phase}.json", run.stdout.encode()); self.record(f"cache-{phase}.stderr", run.stderr.encode())
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            snapshots.append(json.loads(run.stdout))
            files = sorted(cache_home.rglob("*.json"))
            self.assertEqual(len(files), 2)
            entries = [json.loads(path.read_text()) for path in files]
            self.assertEqual({entry["key"]["compilerIdentity"] for entry in entries},
                             {self.cache_identity["semantics"]})
            self.assertEqual(len({entry["key"]["fragmentSourceSHA256"] for entry in entries}), 2)
            current = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in files}
            self.record(f"cache-{phase}-files.json", [{"path": path, "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(), "mtimeNS": modified}
                for path, (raw, modified) in current.items()])
            if phase == "cold": published = current
            else: self.assertEqual(current, published)
        self.assertEqual(snapshots[0], snapshots[1])
        for program in snapshots[0].values():
            self.assertEqual(program["colorTransfer"], {"independentAlphaSignalPreserving": {"textureSlot": 1}})

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
