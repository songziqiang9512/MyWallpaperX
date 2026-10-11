#!/usr/bin/env python3
"""Effect hosts through preparation and bounded Program/Metal graph execution.

The bare Swift GPU carrier follows the graph fixture's explicit bounded route;
it does not exercise the signed generic compiler bundle. The reduction probe
reads the material stage's authored FBO publication, not terminal composition.
"""

from __future__ import annotations

import json
import shutil
import unittest

from script.tests import test_scene_resolved_material_graph_executor as graph_fixture
from script.tests import test_scene_resolved_material_program_finalizer as finalizer_fixture


def runtime_frame_support() -> str:
    """Use the real typed input/copy implementation within the existing graph fixture."""
    source = (finalizer_fixture.SCENE_ROOT / "Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift").read_text()
    frame = source.split("    struct FrameInputs {", 1)[1].split("\n    enum FramePreparationResult", 1)[0]
    support = graph_fixture.SUPPORT
    start = support.index("final class SceneResolvedMaterialRuntimeBridge {")
    end = support.index("\nstruct SceneDependencyEffectInput", start)
    replacement = "struct SceneAudioSpectrumSnapshot { static let silent = Self() }\n"
    replacement += "final class SceneResolvedMaterialRuntimeBridge {\n    struct FrameInputs {" + frame + "\n}\n"
    replacement += r'''
extension SceneResolvedMaterialRuntimeBridge.FrameInputs {
    init(dependencyEffects: [SceneDependencyEffectInput] = [],
        dependencyUnavailability: DependencyUnavailability? = nil,
        dynamicValues: SceneDynamicSnapshot = .empty(frameIndex: 0),
        pointerIsInside: Bool = true, effectDrawAlpha: Float = 1,
        effectDrawColor: SIMD3<Float> = .init(repeating: 1)) {
        self.init(dynamicValues: dynamicValues, cursorUV: .zero, previousCursorUV: .zero,
            pointerIsInside: pointerIsInside, previousPointerIsInside: pointerIsInside,
            pointerMovement: 0, primaryButtonIsDown: false,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            effectDrawAlpha: effectDrawAlpha, effectDrawColor: effectDrawColor,
            frameTime: 1 / 60, time: 0,
            audioSpectrum: .silent, dependencyEffects: dependencyEffects,
            dependencyUnavailability: dependencyUnavailability)
    }
}
'''
    return support[:start] + replacement + support[end:]


CPU_HARNESS = finalizer_fixture.HARNESS.split("@main\nprivate enum Harness", 1)[0] + r'''
private enum Harness {
    static func float(_ data: Data, at offset: Int) -> Float {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
    }
}

private func alphaShader() -> SceneShaderContract {
    contract(revision: "self-owned-draw-alpha", vertexSourceOverride: """
        attribute vec3 a_Position;
        uniform mat4 g_ModelViewProjectionMatrix;
        void main() { gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0); }
        """, fragmentSourceOverride: """
        uniform float g_Alpha; // {"material":"g_Alpha","default":0.75}
        void main() { gl_FragColor = vec4(g_Alpha, g_Alpha, g_Alpha, 1.0); }
        """)
}

private func colorShader() -> SceneShaderContract {
    contract(revision: "self-owned-draw-color", vertexSourceOverride: """
        attribute vec3 a_Position;
        uniform mat4 g_ModelViewProjectionMatrix;
        void main() { gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0); }
        """, fragmentSourceOverride: """
        uniform vec3 g_Color; // {"default":"0.1 0.2 0.3"}
        uniform vec4 g_Color4; // {"default":"0.1 0.2 0.3 0.75"}
        void main() { gl_FragColor = vec4(g_Color + g_Color4.rgb, 1.0); }
        """)
}

private func preparedDrawAlpha(effect: Bool, name: String = "g_Alpha",
    type: SceneAuthoredShaderValueType = .float, arrayCount: Int? = nil,
    declarations: [Template.UniformDeclaration] = []) throws -> SceneResolvedMaterialPreparedUniformBinding {
    let context: Template.EffectContext? = effect ? .init(
        key: .init(layerID: 42, effectIndex: 0, descriptorID: "self-owned-alpha"),
        input: graphTexture()) : nil
    let material = template(alphaShader(), includePrimaryCandidate: false,
        uniformDeclarations: declarations, effectContext: context)
    let field = SceneAuthoredShaderUniformLayout.Field(name: name, type: type,
        arrayCount: arrayCount, offset: 0)
    return try SceneResolvedMaterialProgramFinalizer.prepareUniformBindings(
        template: material, fields: [field], activeUniforms: [name: .init(
            name: name, materialKeys: [name],
            defaultValue: staticValue(type == .float3 ? [0.1, 0.2, 0.3]
                : type == .float4 ? [0.1, 0.2, 0.3, 0.75] : [0.75]), authoredRange: nil)],
        activeTextureSlots: [], neutralTextureResolution: nil)[0]
}

private func rejection(_ body: () throws -> SceneResolvedMaterialPreparedUniformBinding) -> String {
    do { _ = try body(); return "accepted" }
    catch let failure as SceneResolvedMaterialFailure { return failure.code.rawValue }
    catch { return "unexpected" }
}

private func assembly(effect: Bool, source: Program.ResolvedUniform.Source,
    alpha: Float = 0.25, color: SIMD3<Float>? = nil,
    contractOverride: SceneShaderContract? = nil, scalarName: String = "g_Alpha") -> Program? {
    let contract = contractOverride ?? (color == nil ? alphaShader() : colorShader())
    guard let shader = prepared(contract),
          let frontend = SceneAuthoredShaderFrontend.compile(vertexSource: shader.vertex.source,
            fragmentSource: shader.fragment.source).program else { return nil }
    let slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    var values: [Program.ResolvedUniform] = []
    for field in frontend.uniformLayout.fields {
        if field.authoredName == scalarName {
            guard let encoded = SceneResolvedMaterialUniformEncoder.encode(
                staticValue([Double(alpha)]), as: field.type) else { return nil }
            values.append(.init(field: field, source: source, encodedValue: encoded))
        } else if field.authoredName == "g_Color" || field.authoredName == "g_Color4" {
            guard let color else { return nil }
            var components = [Double(color.x), Double(color.y), Double(color.z)]
            if field.authoredName == "g_Color4" { components.append(Double(alpha)) }
            guard let encoded = SceneResolvedMaterialUniformEncoder.encodeComponents(
                components, as: field.type) else { return nil }
            let actualSource: Program.ResolvedUniform.Source
            if field.authoredName == "g_Color4", case .host(.effectDrawColor) = source {
                actualSource = .host(.effectDrawColor4)
            } else { actualSource = source }
            values.append(.init(field: field, source: actualSource, encodedValue: encoded))
        } else {
            guard let host = SceneResolvedMaterialHostUniformSchema.resolve(field,
                activeTextureSlots: [], hasEffectContext: effect),
                let encoded = SceneResolvedMaterialUniformEncoder.encodeHost(host,
                    type: field.type, inputs: uniformInputs(), slots: slots) else { return nil }
            values.append(.init(field: field, source: .host(host), encodedValue: encoded))
        }
    }
    return Program.assemble(.init(preparedShader: shader,
        textureSlots: slots, resolvedUniforms: values,
        renderState: state(), graphRole: template(contract, includePrimaryCandidate: false).graphRole,
        hasEffectContext: effect))
}

private func variantAliasScope(effect: Bool, name: String = "g_Alpha") -> String {
    let scalar = name == "g_Alpha" || name == "g_TextureReductionScale"
    let type = scalar ? "float" : name == "g_Color" ? "vec3" : "vec4"
    let fallback = scalar ? "0.75" : name == "g_Color" ? "\"0.1 0.2 0.3\"" : "\"0.1 0.2 0.3 0.75\""
    let gainDefault = scalar ? "1" : name == "g_Color" ? "\"1 1 1\"" : "\"1 1 1 1\""
    let output = scalar ? "vec4(\(name), gain, 0.0, 1.0)" : "vec4(\(name).rgb + gain.rgb, 1.0)"
    let shader = contract(revision: "self-owned-draw-alias-\(name)", fragmentSourceOverride: """
        uniform \(type) \(name); // {"material":"gain","default":\(fallback)}
        uniform \(type) gain; // {"default":\(gainDefault)}
        void main() { gl_FragColor = \(output); }
        """)
    let context: Template.EffectContext? = effect ? .init(
        key: .init(layerID: fixtureLayerID, effectIndex: 0, descriptorID: "self-owned-alpha"),
        input: graphTexture()) : nil
    let material = template(shader, includePrimaryCandidate: false, effectContext: context)
    guard case let .success(cache) = SceneResolvedMaterialVariantCache.launchValidated(
        template: material, maximumVariantCount: 4) else { return "launch-failed" }
    switch cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil) {
    case .success:
        let variants = cache.launchEnvelopeCapabilitySnapshot().variants
        guard let bindings = variants.first?.preparedUniformBindings,
              let alpha = bindings.first(where: { $0.field.authoredName == name }),
              let gain = bindings.first(where: { $0.field.authoredName == "gain" }),
              case let .host(host) = alpha.source,
              case .staticValue = gain.source else { return "wrong-ownership" }
        let expected = SceneResolvedMaterialHostUniformSchema.resolve(alpha.field,
            activeTextureSlots: [], hasEffectContext: effect)
        guard host == expected else { return "wrong-host" }
        return "effect-host-and-authored-gain"
    case let .failure(.material(error)): return error.code.rawValue
    case .failure(.capacity): return "capacity"
    }
}

private func drawUniformInputs(alpha: Float = 0.25,
    color: SIMD3<Float> = .init(0.1, 0.2, 0.3)) -> SceneAuthoredShaderUniformInputs {
    .init(frameIndex: 1, renderSize: CGSize(width: 2, height: 2),
        screenSize: CGSize(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        effectDrawAlpha: alpha, effectDrawColor: color, sceneTime: 0, dayTime: 0,
        frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
        texturePhysicalSizes: [:])
}

private func colorFacts() throws -> [String: Any] {
    let rgb = SIMD3<Float>(0.1, 0.2, 0.3)
    let inputs = drawUniformInputs(color: rgb)
    let slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    var fields: [[String: Any]] = []
    for (name, type, host) in [
        ("g_Color", SceneAuthoredShaderValueType.float3, Program.HostUniform.effectDrawColor),
        ("g_Color4", .float4, .effectDrawColor4)
    ] {
        let values: [Double] = name == "g_Color" ? [0.1, 0.2, 0.3] : [0.1, 0.2, 0.3, 0.75]
        let declared = staticDeclaration(name, components: values)
        let dynamic = Template.UniformDeclaration(name: name, value: .dynamic(.init(
            target: .effectConstant(layerID: fixtureLayerID, effectIndex: 0, passIndex: 0, name: name),
            valueContributors: [.timeline], scriptAttachments: [], authoredFallback: staticValue(values),
            authoredBindingKeys: ["value"])))
        let defaultSource = try preparedDrawAlpha(effect: false, name: name, type: type)
        let staticSource = try preparedDrawAlpha(effect: false, name: name, type: type, declarations: [declared])
        let dynamicSource = try preparedDrawAlpha(effect: false, name: name, type: type, declarations: [dynamic])
        var authoredDefault = false, authoredStatic = false, authoredDynamic = false
        if case .staticValue = defaultSource.source { authoredDefault = true }
        if case .staticValue = staticSource.source { authoredStatic = true }
        if case .dynamic = dynamicSource.source { authoredDynamic = true }
        let encoded = SceneResolvedMaterialUniformEncoder.encodeHost(host, type: type, inputs: inputs, slots: slots)
        let bytesMatch = encoded.map {
            Harness.float($0, at: 0) == rgb.x && Harness.float($0, at: 4) == rgb.y
                && Harness.float($0, at: 8) == rgb.z
                && (name == "g_Color" || Harness.float($0, at: 12) == 0.25)
        } ?? false
        fields.append(["name": name, "defaultPreserved": authoredDefault, "staticPreserved": authoredStatic,
            "dynamicPreserved": authoredDynamic, "bytesMatch": bytesMatch,
            "staticConflict": rejection { try preparedDrawAlpha(effect: true, name: name, type: type, declarations: [declared]) },
            "dynamicConflict": rejection { try preparedDrawAlpha(effect: true, name: name, type: type, declarations: [dynamic]) },
            "array": rejection { try preparedDrawAlpha(effect: true, name: name, type: type, arrayCount: 2) },
            "wrongType": rejection { try preparedDrawAlpha(effect: true, name: name, type: name == "g_Color" ? .float4 : .float3) },
            "nonFiniteRejected": SceneResolvedMaterialUniformEncoder.encodeHost(host, type: type,
                inputs: drawUniformInputs(color: .init(.nan, 0.2, 0.3)), slots: slots) == nil,
            "effectAliasVariant": variantAliasScope(effect: true, name: name),
            "sourceAliasVariant": variantAliasScope(effect: false, name: name)])
    }
    let first = assembly(effect: true, source: .host(.effectDrawColor), color: rgb)
    let second = assembly(effect: true, source: .host(.effectDrawColor), alpha: 0.5, color: .init(0.2, 0.4, 0.1))
    let replay = first?.terminalReplay(unitModelViewProjection: matrix_identity_float4x4)
    let copied = SceneResolvedMaterialRuntimeBridge.FrameInputs(effectDrawAlpha: 0.25, effectDrawColor: rgb)
        .withDependencyEffects([])
    return ["colorFields": fields,
        "colorIdentityStable": first != nil && second != nil && first!.semanticIdentity == second!.semanticIdentity,
        "colorExactChanged": first != nil && second != nil && first!.exactIdentity != second!.exactIdentity,
        "colorSourceHostRejected": assembly(effect: false, source: .host(.effectDrawColor), color: rgb) == nil,
        "colorEffectStaticRejected": assembly(effect: true, source: .staticValue, color: rgb) == nil,
        "colorSourceStaticAccepted": assembly(effect: false, source: .staticValue, color: rgb) != nil,
        "colorWrongHostRejected": assembly(effect: true, source: .host(.time), color: rgb) == nil,
        "colorCopyPreserved": copied.effectDrawAlpha == 0.25 && copied.effectDrawColor == rgb,
        "colorTerminalPreserved": replay != nil && replay!.resolvedUniforms.contains {
            if case .host(.effectDrawColor4) = $0.source {
                return Harness.float($0.encodedValue, at: 0) == rgb.x
                    && Harness.float($0.encodedValue, at: 12) == 0.25
            }; return false
        },
        "rgbDoesNotReadAlpha": SceneResolvedMaterialUniformEncoder.encodeHost(.effectDrawColor, type: .float3,
            inputs: drawUniformInputs(alpha: .nan), slots: slots) != nil,
        "rgbaRejectsNonfiniteAlpha": SceneResolvedMaterialUniformEncoder.encodeHost(.effectDrawColor4, type: .float4,
            inputs: drawUniformInputs(alpha: .nan), slots: slots) == nil]
}

private func reductionFacts() throws -> [String: Any] {
    let name = "g_TextureReductionScale"
    let shader = contract(revision: "self-owned-effect-reduction", vertexSourceOverride: """
        attribute vec3 a_Position;
        uniform mat4 g_ModelViewProjectionMatrix;
        uniform float g_TextureReductionScale; // {"default":0.75}
        varying float v_Reduction;
        void main() {
            v_Reduction = g_TextureReductionScale;
            gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0);
        }
        """, fragmentSourceOverride: """
        varying float v_Reduction;
        void main() { gl_FragColor = vec4(v_Reduction, 0.0, 0.0, 1.0); }
        """)
    let field = SceneAuthoredShaderUniformLayout.Field(name: name, type: .float, offset: 0)
    let host = SceneResolvedMaterialHostUniformSchema.resolve(field,
        activeTextureSlots: [], hasEffectContext: true)
    let effect = try preparedDrawAlpha(effect: true, name: name)
    let source = try preparedDrawAlpha(effect: false, name: name)
    let declared = staticDeclaration(name, components: [0.125])
    let dynamic = Template.UniformDeclaration(name: name, value: .dynamic(.init(
        target: .effectConstant(layerID: fixtureLayerID, effectIndex: 0, passIndex: 0, name: name),
        valueContributors: [.timeline], scriptAttachments: [],
        authoredFallback: staticValue([0.3]), authoredBindingKeys: ["value"])))
    let sourceDeclared = try preparedDrawAlpha(effect: false, name: name, declarations: [declared])
    let sourceDynamic = try preparedDrawAlpha(effect: false, name: name, declarations: [dynamic])
    var effectIsHost = false, sourceIsStatic = false, sourceStaticOwned = false, sourceDynamicOwned = false
    if case let .host(actual) = effect.source { effectIsHost = host != nil && actual == host }
    if case .staticValue = source.source { sourceIsStatic = true }
    if case .staticValue = sourceDeclared.source { sourceStaticOwned = true }
    if case .dynamic = sourceDynamic.source { sourceDynamicOwned = true }
    func program(_ effect: Bool, _ source: Program.ResolvedUniform.Source, _ value: Float = 1) -> Program? {
        assembly(effect: effect, source: source, alpha: value,
            contractOverride: shader, scalarName: name)
    }
    let correct = host.flatMap { program(true, .host($0)) }
    let sourceProgram = program(false, .staticValue, 0.125)
    let sourceBytes = sourceProgram?.resolvedUniforms.first { $0.field.authoredName == name }?.encodedValue
    let hostBytes = host.flatMap { SceneResolvedMaterialUniformEncoder.encodeHost($0,
        type: .float, inputs: drawUniformInputs(), slots: Array(repeating: nil, count: 8)) }
    let wrongType = host.map { SceneResolvedMaterialUniformEncoder.encodeHost($0,
        type: .float2, inputs: drawUniformInputs(), slots: Array(repeating: nil, count: 8)) == nil } ?? false
    let replay = correct?.terminalReplay(unitModelViewProjection: matrix_identity_float4x4)
    return ["effectIsHost": effectIsHost, "sourceIsStatic": sourceIsStatic,
        "sourceStaticOwned": sourceStaticOwned, "sourceDynamicOwned": sourceDynamicOwned,
        "hostBytes": hostBytes.map { Harness.float($0, at: 0) == 1 } ?? false,
        "sourceBytes": sourceBytes.map { Harness.float($0, at: 0) == 0.125 } ?? false,
        "wrongEncoderType": wrongType,
        "staticConflict": rejection { try preparedDrawAlpha(effect: true, name: name, declarations: [declared]) },
        "dynamicConflict": rejection { try preparedDrawAlpha(effect: true, name: name, declarations: [dynamic]) },
        "effectAliasVariant": variantAliasScope(effect: true, name: name),
        "sourceAliasVariant": variantAliasScope(effect: false, name: name),
        "wrongScalar": rejection { try preparedDrawAlpha(effect: true, name: name, type: .int) },
        "wrongVector": rejection { try preparedDrawAlpha(effect: true, name: name, type: .float2) },
        "wrongVectorStatic": rejection { try preparedDrawAlpha(effect: true, name: name, type: .float2,
            declarations: [staticDeclaration(name, components: [0.2, 0.3])]) },
        "array": rejection { try preparedDrawAlpha(effect: true, name: name, arrayCount: 2) },
        "hostAssembly": correct != nil,
        "effectStaticRejected": program(true, .staticValue) == nil,
        "wrongHostRejected": program(true, .host(.time)) == nil,
        "sourceHostRejected": host.map { program(false, .host($0)) == nil } ?? false,
        "sourceStaticAccepted": sourceProgram != nil,
        "terminalPreserved": replay?.resolvedUniforms.contains {
            $0.field.authoredName == name && Harness.float($0.encodedValue, at: 0) == 1 } ?? false]
}

@main private enum EffectDrawAlphaPreparationHarness {
    static func main() throws {
        let effect = try preparedDrawAlpha(effect: true)
        let source = try preparedDrawAlpha(effect: false)
        let color = try preparedDrawAlpha(effect: true, name: "g_Color", type: .float3)
        let color4 = try preparedDrawAlpha(effect: true, name: "g_Color4", type: .float4)
        let colorIsHost: Bool, color4IsHost: Bool
        if case .host = color.source { colorIsHost = true } else { colorIsHost = false }
        if case .host = color4.source { color4IsHost = true } else { color4IsHost = false }
        let effectIsHost: Bool
        if case .host(.effectDrawAlpha) = effect.source { effectIsHost = true } else { effectIsHost = false }
        let sourceIsStatic: Bool
        if case .staticValue = source.source { sourceIsStatic = true } else { sourceIsStatic = false }
        let declared = staticDeclaration("g_Alpha", components: [0.125])
        let sourceDeclared = try preparedDrawAlpha(effect: false, declarations: [declared])
        let target = SceneDynamicTarget.effectConstant(layerID: fixtureLayerID,
            effectIndex: 0, passIndex: 0, name: "g_Alpha")
        let dynamic = Template.UniformDeclaration(name: "g_Alpha", value: .dynamic(.init(
            target: target, valueContributors: [.timeline], scriptAttachments: [],
            authoredFallback: staticValue([0.3]), authoredBindingKeys: ["value"])))
        let sourceDynamic = try preparedDrawAlpha(effect: false, declarations: [dynamic])
        var sourceStaticOwned = false, sourceDynamicOwned = false
        if case .staticValue = sourceDeclared.source { sourceStaticOwned = true }
        if case .dynamic = sourceDynamic.source { sourceDynamicOwned = true }
        let first = assembly(effect: true, source: .host(.effectDrawAlpha))
        let second = assembly(effect: true, source: .host(.effectDrawAlpha), alpha: 0.5)
        let replay = first?.terminalReplay(unitModelViewProjection: matrix_identity_float4x4)
        let inputs = SceneAuthoredShaderUniformInputs(frameIndex: 1, renderSize: CGSize(width: 2, height: 2),
            screenSize: CGSize(width: 2, height: 2), modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            effectDrawAlpha: .nan, sceneTime: 0, dayTime: 0, frameTime: 1 / 60,
            pointerCurrentNDC: .zero, pointerPreviousNDC: .zero, texturePhysicalSizes: [:])
        let copied = SceneResolvedMaterialRuntimeBridge.FrameInputs(effectDrawAlpha: 0.25)
            .withDependencyEffects([])
        var output: [String: Any] = [
            "effectIsHost": effectIsHost, "sourceIsStatic": sourceIsStatic,
            "colorIsHost": colorIsHost, "color4IsHost": color4IsHost,
            "sourceStaticOwned": sourceStaticOwned, "sourceDynamicOwned": sourceDynamicOwned,
            "effectStaticConflict": rejection { try preparedDrawAlpha(effect: true, declarations: [declared]) },
            "effectDynamicConflict": rejection { try preparedDrawAlpha(effect: true, declarations: [dynamic]) },
            "wrongScalar": rejection { try preparedDrawAlpha(effect: true, type: .int) },
            "wrongVector": rejection { try preparedDrawAlpha(effect: true, type: .float2) },
            "array": rejection { try preparedDrawAlpha(effect: true, arrayCount: 2) },
            "hostAssembly": first != nil,
            "sourceHostRejected": assembly(effect: false, source: .host(.effectDrawAlpha)) == nil,
            "effectStaticRejected": assembly(effect: true, source: .staticValue) == nil,
            "sourceStaticAssembly": assembly(effect: false, source: .staticValue) != nil,
            "wrongHostRejected": assembly(effect: true, source: .host(.time)) == nil,
            "identityStable": first != nil && second != nil && first!.semanticIdentity == second!.semanticIdentity,
            "exactBytesChanged": first != nil && second != nil && first!.exactIdentity != second!.exactIdentity,
            "terminalAlphaPreserved": replay != nil && replay!.resolvedUniforms.contains {
                if case .host(.effectDrawAlpha) = $0.source {
                    return Harness.float($0.encodedValue, at: 0) == 0.25
                }
                return false
            },
            "nonFiniteRejected": SceneResolvedMaterialUniformEncoder.encodeHost(.effectDrawAlpha,
                type: .float, inputs: inputs, slots: Array(repeating: nil, count: 8)) == nil,
            "copiedAlpha": copied.effectDrawAlpha,
            "effectAliasVariant": variantAliasScope(effect: true),
            "sourceAliasVariant": variantAliasScope(effect: false),
        ]
        output.merge(try colorFacts()) { _, value in value }
        output["reduction"] = try reductionFacts()
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


METAL_HARNESS = graph_fixture.HARNESS.split("@main\nprivate enum Harness", 1)[0] + r'''
private func reductionVertex(_ shader: SceneShaderContract) -> SceneShaderContract {
    let stages = shader.stages.map { stage -> SceneShaderContract.Stage in
        guard stage.kind == .vertex else { return stage }
        let source = "uniform float g_TextureReductionScale;\nvarying float v_Reduction;\n"
            + stage.source.replacingOccurrences(of: "v_TexCoord = a_TexCoord;",
                with: "v_TexCoord = a_TexCoord; v_Reduction = g_TextureReductionScale;")
                .replacingOccurrences(of: "gl_Position = vec4(a_Position, 1.0);",
                    with: "gl_Position = vec4(a_Position * g_TextureReductionScale, 1.0);")
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: stage.relativePath)
        return .init(kind: stage.kind, relativePath: stage.relativePath, source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)), includes: parsed.includes,
            annotations: parsed.annotations, declarations: parsed.declarations)
    }
    let graph = SceneShaderSourceGraph(roots: stages.map {
        .init(label: $0.kind.rawValue, virtualPath: $0.relativePath)
    }, nodes: stages.map {
        .init(virtualPath: $0.relativePath, provenance: .package, source: $0.source,
            rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count)
    }, edges: [], diagnostics: [], dependencySHA256: SceneShaderStableDigest.hash(stages))
    return .init(identity: shader.identity, sourceKind: shader.sourceKind, stages: stages,
        diagnostics: [], canonicalSHA256: SceneShaderStableDigest.hash(stages), sourceGraph: graph)
}

private func drawModulationFrames(
    device: MTLDevice, queue: MTLCommandQueue, colorProbe: String? = nil,
    reductionScale: Double? = nil
) -> [String: Any] {
    let provider = SceneNamedTextureReference(providerLayerID: 879, variant: .primary)
    let node = material(0, ordinal: 0, target: reductionScale == nil ? output : first, read: input)
    let terminal = material(1, ordinal: 1, target: output, read: first)
    let target = Graph.RenderTarget(texture: first,
        extent: .init(width: 8, height: 8, fit: nil, scale: reductionScale),
        format: "rgba_backbuffer", declaredUnique: false, clear: nil, uvs: nil, conditions: nil)
    let value = graph(targets: reductionScale == nil ? [] : [target],
        nodes: reductionScale == nil ? [node] : [node, terminal])
    let base = template(for: node, namedProvider: provider)
    let declaration: String
    let consumerExpression: String
    switch colorProbe {
    case "colorRG":
        declaration = "uniform vec3 g_Color;"
        consumerExpression = "vec4(g_Color.r, g_Color.g, provider.a, 1.0)"
    case "colorBlue":
        declaration = "uniform vec3 g_Color;"
        consumerExpression = "vec4(g_Color.b, provider.r, provider.g, 1.0)"
    case "color4RG":
        declaration = "uniform vec4 g_Color4;"
        consumerExpression = "vec4(g_Color4.r, g_Color4.g, provider.a, 1.0)"
    case "color4BlueAlpha":
        declaration = "uniform vec4 g_Color4;"
        consumerExpression = "vec4(g_Color4.b, g_Color4.w, provider.a, 1.0)"
    case "reduction":
        declaration = "varying float v_Reduction;"
        consumerExpression = "vec4(v_Reduction / 8.0, provider.a, provider.r, 1.0)"
    default:
        declaration = "uniform float g_Alpha;"
        consumerExpression = "vec4(g_Alpha, provider.a, provider.r, 1.0)"
    }
    var shader = shaderContract(nodeIndex: 0, pass: false, fragmentOverride: """
        varying vec2 v_TexCoord;
        uniform sampler2D g_Texture1;
        \(declaration)
        void main() {
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            gl_FragColor = \(consumerExpression);
        }
        """)
    if reductionScale != nil { shader = reductionVertex(shader) }
    let materialTemplate = Template.validated(textureSlots: base.textureSlots, combos: [],
        uniformDeclarations: [], renderState: base.renderState, graphRole: base.graphRole,
        effectContext: .init(key: effect, input: input), shaderContract: shader,
        diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
            contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
            textureSources: [], uniformSources: []))!
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [
        .init(effect: effect, nodeIndex: 0): .template(materialTemplate)
    ]
    if reductionScale != nil { entries[.init(effect: effect, nodeIndex: 1)] = .template(template(for: terminal)) }
    let materials = SceneResolvedMaterialRuntimeCatalog(entries: entries, resourceDemandIssues: [])
    let dependency = SceneDependencyRenderPlan.Binding(consumerLayerID: layerID,
        providerLayerID: provider.providerLayerID,
        slot: .init(effectID: effect.descriptorID, passIndex: 0, slotIndex: 1),
        blendMode: 0, kind: .resolvedMaterial)
    let chain = admittedGraph(value)
    let facts = capabilities(chain, catalog: materials, namedProvider: provider,
        dependencyBinding: dependency)
    guard let claim = facts.claim(chain), let capability = facts.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device),
          let selected = capability.material(for: node),
          let executor = Executor(device: device, capabilities: facts) else {
        return ["failure": "setup", "reports": facts.reportLines]
    }
    let sourcePipeline = makeSourcePipeline(device)
    let providerTexture = makeSource(device, width: 2, height: 2,
        usage: [.renderTarget, .shaderRead], bgra: [77, 179, 51, 191])
    var rows: [[String: Any]] = []
    var states: [Graph.EffectKey: Executor.State] = [:]
    var resources: [Graph.EffectKey: [Graph.TextureIdentity: SceneFrameTextureResource]] = [:]
    var key: String?, frontendCount = 0, libraryCount = 0
    let alphas: [Float] = colorProbe == nil ? [0.25, 0.5, 1] : [0.25, 0.5, 0.75]
    let colors: [SIMD3<Float>] = [.init(0.1, 0.2, 0.3), .init(0.2, 0.4, 0.1), .init(0.3, 0.1, 0.2)]
    for (offset, alpha) in alphas.enumerated() {
        let color = colors[offset]
        let index = UInt64(offset + 1)
        let snapshot = frame(index)
        guard let providerResource = SceneFrameTextureResource.reservedNamedLayerTarget(
            reference: provider, frameEpoch: index, texture: providerTexture,
            content: .color(.resolved(.straightAlpha))) else { return ["failure": "provider"] }
        let inputFrame = SceneResolvedMaterialRuntimeBridge.FrameInputs(
            effectDrawAlpha: alpha, effectDrawColor: color)
            .withDependencyEffects([.init(consumerLayerID: layerID,
                providerLayerID: provider.providerLayerID, slot: dependency.slot,
                frameEpoch: index, texture: providerTexture,
                content: providerResource.publication.candidate.content,
                namedReference: provider, reservedMaterialResource: providerResource)])
        var sourceUniforms = SceneLayerFragmentUniforms.neutral()
        sourceUniforms.alpha = 0.625
        if colorProbe != nil { sourceUniforms.tint = SIMD4(0.8, 0.6, 0.4, 1) }
        let command = queue.makeCommandBuffer()!
        let result = executor.prepare(token: claim.token, leases: leases,
            historyRehydrateCopiesByEffect: [:], frame: snapshot,
            sourceTexture: makeSource(device, width: 2, height: 2, bgra: [26, 51, 102, 128]),
            sourceUniforms: sourceUniforms, sourcePipeline: sourcePipeline, frameInputs: inputFrame,
            commandBuffer: command, previousStates: states, previousGraphResources: resources,
            effectGeneration: 1, resetGeneration: 1)
        guard case let .success(prepared) = result, prepared.stages.count == 1,
              executor.encode(prepared, commandBuffer: command) else {
            return ["failure": failureCode(result), "frames": rows]
        }
        let stage = prepared.stages[0]
        // Read the authored FBO independently of the existing terminal template.
        let rendered = reductionScale == nil ? prepared.finalResource : stage.frameResources[first]
        guard let rendered, let read = appendReadback(rendered.publication.texture,
                commandBuffer: command) else {
            return ["failure": "readback", "frames": rows]
        }
        command.commit(); command.waitUntilCompleted()
        if offset == 0 {
            key = stage.programCacheKeys.first
            frontendCount = selected.variants.counters.frontendCompilationCount
            libraryCount = executor.materialEncoder.metalLibraryCompilationAttemptCount
        }
        let alphaByte = UInt8((alpha * 255).rounded())
        let expected: [UInt8]
        switch colorProbe {
        case "colorRG", "color4RG":
            expected = [191, UInt8((color.y * 255).rounded()), UInt8((color.x * 255).rounded()), 255]
        case "colorBlue":
            expected = [179, 51, UInt8((color.z * 255).rounded()), 255]
        case "color4BlueAlpha":
            expected = [191, alphaByte, UInt8((color.z * 255).rounded()), 255]
        case "reduction":
            expected = [51, 191, 32, 255]
        default:
            expected = [51, 191, alphaByte, 255]
        }
        rows.append(["alpha": alpha, "color": [color.x, color.y, color.z],
            "pixel": read.firstPixel, "providerPixel": read.lastPixel,
            "expected": expected,
            "gpuCompleted": command.status == .completed && command.error == nil,
            "consumerProviderIndependent": matches(read.firstPixel, expected)
                && matches(read.lastPixel, expected),
            "copyPreservedAlpha": inputFrame.effectDrawAlpha == alpha,
            "copyPreservedColor": inputFrame.effectDrawColor == color,
            "samePreparedProgram": key != nil && key == stage.programCacheKeys.first,
            "noRecompile": frontendCount == selected.variants.counters.frontendCompilationCount
                && libraryCount == executor.materialEncoder.metalLibraryCompilationAttemptCount,
            "noLocalFallback": stage.effectLocalFailureReasonCode == nil,
            "opaqueOutput": rendered.publication.candidate.content == .color(.resolved(.opaque))])
        states = [stage.effect: stage.transition.nextState]
        resources = [stage.effect: stage.persistentResources]
    }
    var result: [String: Any] = ["frames": rows]
    if let reductionScale, let texture = leases.first?.texture(for: first) {
        result["fboExtent"] = [texture.width, texture.height]
        result["authoredScale"] = reductionScale
    }
    return result
}

@main private enum EffectDrawAlphaMetalHarness {
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"skip\":\"Metal unavailable\"}"); return
        }
        var result: [String: Any] = ["alpha": drawModulationFrames(device: device, queue: queue)]
        for probe in ["colorRG", "colorBlue", "color4RG", "color4BlueAlpha"] {
            result[probe] = drawModulationFrames(device: device, queue: queue, colorProbe: probe)
        }
        for scale in [1.0, 2.0, 4.0] {
            result["reduction\(Int(scale))"] = drawModulationFrames(device: device, queue: queue,
                colorProbe: "reduction", reductionScale: scale)
        }
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectDrawAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compiled, completed = graph_fixture.compile_harness(
            runtime_frame_support(), CPU_HARNESS,
            additional_sources=[
                finalizer_fixture.SCENE_ROOT / "Compilation/ShaderContract/SceneShaderContractLoader.swift",
                finalizer_fixture.SCENE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
            ],
        )
        if compiled.returncode != 0 or completed is None or completed.returncode != 0:
            raise AssertionError(compiled.stderr + (completed.stderr + completed.stdout if completed else ""))
        cls.result = json.loads(completed.stdout)
        print("CPU " + completed.stdout.strip())

    def test_effect_scope_takes_host_alpha_and_source_keeps_authored_default(self) -> None:
        result = self.result
        self.assertTrue(result["sourceIsStatic"], result)
        self.assertTrue(result["effectIsHost"], result)

    def test_effect_scope_takes_host_rgb_and_rgba(self) -> None:
        self.assertTrue(self.result["colorIsHost"], self.result)
        self.assertTrue(self.result["color4IsHost"], self.result)

    def test_color_sources_types_conflicts_and_variant_alias_scope(self) -> None:
        for field in self.result["colorFields"]:
            for key in ("defaultPreserved", "staticPreserved", "dynamicPreserved", "bytesMatch", "nonFiniteRejected"):
                self.assertTrue(field[key], field)
            for key in ("staticConflict", "dynamicConflict"):
                self.assertEqual(field[key], "hostUniformDeclarationConflict", field)
            for key in ("array", "wrongType"):
                self.assertEqual(field[key], "staticUniformBindingInvalid", field)
            self.assertEqual(field["effectAliasVariant"], "effect-host-and-authored-gain", field)
            self.assertEqual(field["sourceAliasVariant"], "uniformBindingInvalid", field)

    def test_color_identity_copy_terminal_and_unassociated_channels(self) -> None:
        for key in ("colorIdentityStable", "colorExactChanged", "colorSourceHostRejected", "colorEffectStaticRejected",
                    "colorSourceStaticAccepted", "colorWrongHostRejected", "colorCopyPreserved", "colorTerminalPreserved",
                    "rgbDoesNotReadAlpha", "rgbaRejectsNonfiniteAlpha"):
            self.assertTrue(self.result[key], self.result)

    def test_source_static_dynamic_and_effect_conflicts(self) -> None:
        for key in ("sourceStaticOwned", "sourceDynamicOwned"):
            self.assertTrue(self.result[key], self.result)
        for key in ("effectStaticConflict", "effectDynamicConflict"):
            self.assertEqual(self.result[key], "hostUniformDeclarationConflict", self.result)

    def test_effect_requires_nonarray_float(self) -> None:
        for key in ("wrongScalar", "wrongVector", "array"):
            self.assertEqual(self.result[key], "staticUniformBindingInvalid", self.result)

    def test_variant_schema_filter_shares_effect_scope(self) -> None:
        self.assertEqual(self.result["effectAliasVariant"], "effect-host-and-authored-gain", self.result)
        self.assertEqual(self.result["sourceAliasVariant"], "uniformBindingInvalid", self.result)

    def test_program_identity_rechecks_scope(self) -> None:
        for key in ("hostAssembly", "sourceHostRejected", "effectStaticRejected", "sourceStaticAssembly",
                    "wrongHostRejected", "identityStable", "exactBytesChanged", "terminalAlphaPreserved"):
            self.assertTrue(self.result[key], self.result)

    def test_nonfinite_rejection_and_dependency_copy(self) -> None:
        self.assertTrue(self.result["nonFiniteRejected"], self.result)
        self.assertEqual(self.result["copiedAlpha"], 0.25, self.result)

    def test_reduction_effect_host_and_source_authored_values(self) -> None:
        result = self.result["reduction"]
        for key in ("effectIsHost", "hostBytes", "sourceIsStatic", "sourceStaticOwned",
                    "sourceDynamicOwned", "sourceBytes", "sourceStaticAccepted"):
            self.assertTrue(result[key], result)

    def test_reduction_types_conflicts_and_program_identity(self) -> None:
        result = self.result["reduction"]
        for key in ("staticConflict", "dynamicConflict"):
            self.assertEqual(result[key], "hostUniformDeclarationConflict", result)
        for key in ("wrongScalar", "wrongVector", "wrongVectorStatic", "array"):
            self.assertEqual(result[key], "staticUniformBindingInvalid", result)
        for key in ("wrongEncoderType", "hostAssembly", "effectStaticRejected", "wrongHostRejected",
                    "sourceHostRejected", "terminalPreserved"):
            self.assertTrue(result[key], result)
        self.assertEqual(result["effectAliasVariant"], "effect-host-and-authored-gain", result)
        self.assertEqual(result["sourceAliasVariant"], "uniformBindingInvalid", result)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEffectDrawAlphaMetalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compiled, completed = graph_fixture.compile_harness(runtime_frame_support(), METAL_HARNESS)
        if compiled.returncode != 0 or completed is None or completed.returncode != 0:
            raise AssertionError(compiled.stderr + (completed.stderr + completed.stdout if completed else ""))
        cls.result = json.loads(completed.stdout)
        print("Metal " + completed.stdout.strip())
        if "skip" in cls.result:
            raise unittest.SkipTest(cls.result["skip"])

    def assert_probe_frames(self, name: str) -> None:
        result = self.result[name]
        self.assertNotIn("failure", result, result)
        self.assertEqual(len(result["frames"]), 3, result)
        for row in result["frames"]:
            for key in ("gpuCompleted", "consumerProviderIndependent", "copyPreservedAlpha", "copyPreservedColor",
                        "samePreparedProgram", "noRecompile", "noLocalFallback", "opaqueOutput"):
                self.assertTrue(row[key], result)

    def test_actual_graph_consumer_alpha_is_independent_across_frames(self) -> None:
        self.assert_probe_frames("alpha")

    def test_actual_graph_rgb_and_rgba_follow_consumer_not_source_or_provider(self) -> None:
        for name in ("colorRG", "colorBlue", "color4RG", "color4BlueAlpha"):
            self.assert_probe_frames(name)

    def test_vertex_reduction_host_stays_one_at_authored_fbo_scales(self) -> None:
        for scale in (1, 2, 4):
            name = f"reduction{scale}"
            self.assert_probe_frames(name)
            result = self.result[name]
            self.assertEqual(result["fboExtent"], [8 // scale, 8 // scale], result)
            for row in result["frames"]:
                self.assertEqual(row["expected"], [51, 191, 32, 255], result)


if __name__ == "__main__":
    unittest.main()
