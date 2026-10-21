#!/usr/bin/env python3
"""Real snapshot, world transform, shared host schema and uniform bytes; no GPU."""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_property_live_routing import method_body
from script.tests.test_scene_static_model_pipeline import LIGHTING_STUB

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


SUPPORT = r'''
nonisolated enum SceneShaderContract {
    enum StageKind: String, Codable, Sendable { case vertex, fragment }
}
nonisolated enum SceneShaderColorBoundary { static let uniformName = "mwxColorInputMask" }
nonisolated enum SceneDynamicValue {
    case scalar(Double), vector2(Double, Double), vector3(Double, Double, Double)
    case vector4(Double, Double, Double, Double), bool(Bool), string(String)
}
nonisolated enum SceneDynamicLayerField: Hashable {
    case alpha, brightness, color, intensity, radius, visibility
    __RADIUS_ACCEPTANCE__
}
nonisolated enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
}
nonisolated struct SceneDynamicSnapshot {
    struct Resolved { let value: SceneDynamicValue }
    var values: [SceneDynamicTarget: Resolved] = [:]
    subscript(_ target: SceneDynamicTarget) -> Resolved? { values[target] }
}
nonisolated struct ScenePuppetAttachmentFrameSnapshot {
    static let empty = Self()
    func frame(parentLayerID: Int, attachmentName: String) -> simd_float4x4? { nil }
}
nonisolated struct SceneResolvedMaterialTemplate {
    struct StaticUniformValue { let componentBitPatterns: [UInt64] }
}
nonisolated struct SceneResolvedMaterialProgram {
    __HOST_ENUM__
    enum Representation { case premultipliedAlpha, independentAlphaSignal, opaque }
    enum Resolution { case resolved(Representation) }
    enum Content { case color(Resolution) }
    struct Transform {
        var xAxis = SIMD2<Float>(1, 0)
        var yAxis = SIMD2<Float>(0, 1)
        var origin = SIMD2<Float>.zero
    }
    struct Candidate {
        let content: Content
        var physicalSize = CGSize(width: 1, height: 1)
        var mappedSize = CGSize(width: 1, height: 1)
        var uvTransform = Transform()
        var isSpriteSheet = false
    }
    struct Publication { let candidate: Candidate }
    struct Resource { let publication: Publication }
    struct TextureSlot { let resource: Resource }
}
'''

HARNESS = r'''
@main enum Checks {
    static func light(_ id: Int, color: [Float], radius: Float = 4,
                      intensity: Float = 0.5, kind: String = "point") -> SceneRenderDescriptor.Layer {
        var layer = SceneRenderDescriptor.Layer(id: id, visible: true,
            spotLight: nil, directionalLight: nil)
        layer.pointLight = .init(kind: kind, colorRGB: color, intensity: intensity,
            radius: radius, castsVolumetrics: false, castsShadow: true, isSolid: true)
        layer.originXYZ = [Float(id), Float(id * 10), Float(id + 100)]
        layer.scaleXYZ = [1, 1, 1]
        return layer
    }
    static func snapshot(_ layers: [SceneRenderDescriptor.Layer],
                         order: [Int]? = nil, height: Float? = 786,
                         dynamic: SceneDynamicSnapshot? = nil) -> SceneLightSnapshot {
        let descriptor = SceneRenderDescriptor(lighting: .init(
            ambientColorRGB: [0.125, 0.25, 0.375], skylightColorRGB: [0.9, 0.8, 0.7]),
            layers: layers, renderOrderLayerIDs: order, sceneOrthoHeight: height)
        let index = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        // Match renderFrame's existing native sanitizer, including its entries
        // for lights without a live color target. Ordinary host inputs must
        // validate their raw source even when this map contains safe substitutes.
        let dynamicLightColors = Dictionary(uniqueKeysWithValues: layers.map { layer in
            (layer.id, SceneDynamicLayerValues.color(layerID: layer.id,
                authoredValue: layer.pointLight?.colorRGB, snapshot: dynamic ?? .init()))
        })
        return .make(descriptor: descriptor,
            worldFramesByLayerID: SceneLayerWorldFrameResolver.compute(descriptor: descriptor, byID: index),
            dynamicLayerColors: dynamicLightColors,
            dynamicSnapshot: dynamic)
    }
    static func inputs(_ lighting: SceneAuthoredShaderLightingInputs,
                       size: CGSize = .init(width: 100, height: 50),
                       model: simd_float4x4? = nil) -> SceneAuthoredShaderUniformInputs {
        .init(frameIndex: 8, renderSize: size, screenSize: .init(width: 1210, height: 786),
            modelViewProjection: matrix_identity_float4x4,
            layerModelMatrix: matrix_identity_float4x4, effectUnitModelMatrix: model,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            sceneTime: 2, dayTime: 0.5, frameTime: 1 / 60,
            pointerCurrentNDC: .zero, pointerPreviousNDC: .zero, lighting: lighting)
    }
    static func bytes(_ host: SceneResolvedMaterialProgram.HostUniform,
                      type: SceneAuthoredShaderValueType,
                      input: SceneAuthoredShaderUniformInputs) -> Data? {
        SceneResolvedMaterialUniformEncoder.encodeHost(host, type: type, inputs: input, slots: [])
    }
    static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            stride(from: 0, to: data.count, by: 4).map { raw.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }
    static func field(_ name: String, _ type: SceneAuthoredShaderValueType,
                      _ count: Int? = nil) -> SceneAuthoredShaderUniformLayout.Field {
        .init(name: name, type: type, arrayCount: count, offset: 0)
    }
    static func main() throws {
        var facts: [String: Bool] = [:]
        var lamps = [light(18, color: [0.125, 0.25, 0.5]),
                     light(19, color: [0.25, 0.5, 0.125]),
                     light(20, color: [0.5, 0.125, 0.25]),
                     light(21, color: [0.375, 0.625, 0.875])]
        let value = snapshot(lamps)
        let host = value.authoredShaderLighting
        facts["world-y-roundtrip"] = value.point[0].position.y == 606
            && host.positions?[0] == SIMD3(18, 180, 118)
        facts["native-admission-unchanged"] = value.point.count == 4 && value.overflowCount == 0
        facts["hybrid-fourth-light"] = host.colorsPremultiplied == [
            SIMD4(1, 2, 4, 3), SIMD4(2, 4, 1, 5), SIMD4(4, 1, 2, 7)]
        facts["raw-ambient"] = host.ambient == SIMD3(0.125, 0.25, 0.375)
        let positionData = bytes(.lightsPosition, type: .float3, input: inputs(host))!
        let colorData = bytes(.lightsColorPremultiplied, type: .float4, input: inputs(host))!
        facts["vector-strides-and-padding"] = positionData.count == 64 && colorData.count == 48
            && floats(positionData) == [18,180,118,0,19,190,119,0,20,200,120,0,21,210,121,0]
            && floats(colorData) == [1,2,4,3,2,4,1,5,4,1,2,7]
        let reverse = snapshot(lamps, order: [21, 20, 19, 18]).authoredShaderLighting
        facts["authored-order"] = reverse.positions?[0] == SIMD3(21, 210, 121)
            && reverse.colorsPremultiplied?[0] == SIMD4(3, 5, 7, 1)
        var child = lamps[0]
        child.parentID = 90
        var parent = SceneRenderDescriptor.Layer(id: 90, visible: true,
            spotLight: nil, directionalLight: nil)
        parent.originXYZ = [100, 200, 30]
        parent.scaleXYZ = [2, 3, 1]
        facts["nonuniform-parent-world-position"] = snapshot([child, parent])
            .authoredShaderLighting.positions?[0] == SIMD3(136, 740, 148)
        var hidden = light(30, color: [1, 1, 1], kind: "lpoint")
        hidden.parentID = 90
        let hiddenParent = SceneRenderDescriptor.Layer(id: 90, visible: false,
            spotLight: nil, directionalLight: nil)
        facts["hidden-unsupported-does-not-poison"] = snapshot(lamps + [hidden, hiddenParent])
            .authoredShaderLighting.colorsPremultiplied == host.colorsPremultiplied
        var dynamic = SceneDynamicSnapshot()
        dynamic.values[.layer(layerID: 18, field: .radius)] = .init(value: .scalar(0))
        dynamic.values[.layer(layerID: 19, field: .intensity)] = .init(value: .scalar(2))
        let live = snapshot(lamps, dynamic: dynamic)
        facts["same-frame-radius-zero-keeps-slot"] = live.point.count == 3
            && live.authoredShaderLighting.positions?[0] == host.positions?[0]
            && live.authoredShaderLighting.colorsPremultiplied?[0] == SIMD4(0, 0, 0, 3)
            && live.authoredShaderLighting.colorsPremultiplied?[1] == SIMD4(8, 16, 4, 5)
        let empty = snapshot([]).authoredShaderLighting
        facts["empty-defaults"] = empty.positions == Array(repeating: SIMD3(0, 100, 0), count: 4)
            && empty.colorsPremultiplied == Array(repeating: SIMD4<Float>.zero, count: 3)
        lamps.append(light(22, color: [1, 1, 1]))
        let overflow = snapshot(lamps)
        facts["overflow-local-to-host"] = overflow.point.count == 5
            && overflow.authoredShaderLighting.positions == nil
            && overflow.authoredShaderLighting.colorsPremultiplied == nil
            && overflow.authoredShaderLighting.ambient == host.ambient
        let other = snapshot([light(18, color: [1, 1, 1], kind: "lpoint")])
        facts["unsupported-class-keeps-native"] = other.point.count == 1
            && other.authoredShaderLighting.positions == nil
            && other.authoredShaderLighting.ambient == host.ambient
        let perspective = snapshot([], height: nil).authoredShaderLighting
        facts["perspective-unavailable"] = perspective.positions == nil
            && perspective.ambient == nil && perspective.worldFromRenderWorld == nil
        let bad = snapshot([light(18, color: [1, 1, 1], radius: .greatestFiniteMagnitude)])
            .authoredShaderLighting
        facts["energy-overflow-field-local"] = bad.colorsPremultiplied == nil
            && bad.positions != nil && bad.ambient == host.ambient
        let zero = snapshot([light(18, color: [1, 1, 1], radius: .greatestFiniteMagnitude, intensity: 0)])
        facts["zero-energy-no-premature-overflow"] = zero.authoredShaderLighting.colorsPremultiplied
            == Array(repeating: SIMD4<Float>.zero, count: 3)
        for (label, color, normalized) in [
            ("negative", [Float(-0.25), 0.5, 1], SIMD3<Float>(0, 0.5, 1)),
            ("nan", [Float.nan, 0.5, 1], SIMD3<Float>(repeating: 1)),
            ("short", [Float(0.5), 1], SIMD3<Float>(0.5, 1, 1))
        ] {
            let rejected = snapshot([light(18, color: color)])
            facts["raw-author-color-" + label] = rejected.authoredShaderLighting.colorsPremultiplied == nil
                && rejected.authoredShaderLighting.positions != nil
                && rejected.point.first?.color == normalized
        }
        for (label, color, normalized) in [
            ("negative", SceneDynamicValue.vector3(-0.25, 0.5, 1), SIMD3<Float>(0, 0.5, 1)),
            ("nan", .vector3(.nan, 0.5, 1), SIMD3<Float>(0.125, 0.25, 0.5)),
            ("infinity", .vector3(.infinity, 0.5, 1), SIMD3<Float>(0.125, 0.25, 0.5)),
            ("float-overflow", .vector3(.greatestFiniteMagnitude, 0.5, 1), SIMD3<Float>(1, 0.5, 1)),
            ("wrong-type", .scalar(0.5), SIMD3<Float>(0.125, 0.25, 0.5))
        ] {
            var colors = SceneDynamicSnapshot()
            colors.values[.layer(layerID: 18, field: .color)] = .init(value: color)
            let rejected = snapshot([light(18, color: [0.125, 0.25, 0.5])], dynamic: colors)
            facts["raw-typed-color-" + label] = rejected.authoredShaderLighting.colorsPremultiplied == nil
                && rejected.authoredShaderLighting.positions != nil
                && rejected.point.first?.color == normalized
        }
        var liveColor = SceneDynamicSnapshot()
        liveColor.values[.layer(layerID: 18, field: .color)] = .init(value: .vector3(0.25, 0.75, 2))
        let overridden = snapshot([light(18, color: [-0.25, 0.5, 1])], dynamic: liveColor)
        facts["typed-color-overrides-author-without-clamp"] = overridden.authoredShaderLighting
            .colorsPremultiplied?[0] == SIMD4(2, 6, 16, 0)
            && overridden.point.first?.color == SIMD3(0.25, 0.75, 1)
        let rawAboveOne = snapshot([light(18, color: [2, 0.5, 1.25])])
        facts["raw-author-color-above-one-preserved"] = rawAboveOne.authoredShaderLighting
            .colorsPremultiplied?[0] == SIMD4(16, 4, 10, 0)
            && rawAboveOne.point.first?.color == SIMD3(1, 0.5, 1)
        var model = SceneMatrix.translation(SIMD3(300, 400, 7))
            * SceneMatrix.scale(SIMD3(200, -100, 1))
        let modelA = floats(bytes(.effectModelMatrix, type: .float4x4,
            input: inputs(host, model: model))!)
        let modelB = floats(bytes(.effectModelMatrix, type: .float4x4,
            input: inputs(host, size: .init(width: 50, height: 25), model: model))!)
        facts["effect-world-and-target-basis"] = modelA == [2,0,0,0,0,2,0,0,0,0,1,0,300,386,7,1]
            && modelB == [4,0,0,0,0,4,0,0,0,0,1,0,300,386,7,1]
        facts["unknown-geometry-unavailable"] = bytes(.effectModelMatrix, type: .float4x4,
            input: inputs(host)) == nil
        model.columns.0.x = .infinity
        facts["invalid-matrix-unavailable"] = bytes(.effectModelMatrix, type: .float4x4,
            input: inputs(host, model: model)) == nil
        facts["invalid-extent-unavailable"] = bytes(.effectModelMatrix, type: .float4x4,
            input: inputs(host, size: .zero, model: matrix_identity_float4x4)) == nil
        facts["missing-light-input-unavailable"] = bytes(.lightsPosition, type: .float3,
            input: inputs(.unavailable)) == nil
        let encoder = SceneResolvedMaterialUniformEncoder.self
        for (name, kind, type) in [
            ("model", SceneResolvedMaterialProgram.HostUniform.effectModelMatrix,
                SceneAuthoredShaderValueType.float4x4),
            ("positions", .lightsPosition, .float3),
            ("colors", .lightsColorPremultiplied, .float4),
            ("ambient", .lightAmbientColor, .float3)
        ] {
            facts["typed-optional-input-" + name] = encoder.resolveHost(kind, type: type,
                inputs: inputs(.unavailable), slots: []) == .inputUnavailable
            facts["typed-invalid-host-type-" + name] = encoder.resolveHost(kind, type: .float,
                inputs: inputs(.unavailable), slots: []) == .invalid
        }
        let malformed = SceneAuthoredShaderLightingInputs(positions: [.zero],
            colorsPremultiplied: [.zero], ambient: .init(.nan, 0, 0),
            worldFromRenderWorld: matrix_identity_float4x4)
        facts["typed-malformed-payload-remains-invalid"] = encoder.resolveHost(.lightsPosition,
            type: .float3, inputs: inputs(malformed), slots: []) == .invalid
            && encoder.resolveHost(.lightsColorPremultiplied, type: .float4,
                inputs: inputs(malformed), slots: []) == .invalid
            && encoder.resolveHost(.lightAmbientColor, type: .float3,
                inputs: inputs(malformed), slots: []) == .invalid
        facts["typed-present-bad-matrix-remains-invalid"] = encoder.resolveHost(.effectModelMatrix,
            type: .float4x4, inputs: inputs(host, model: model), slots: []) == .invalid
        facts["typed-old-host-failure-remains-invalid"] = encoder.resolveHost(.renderSize,
            type: .float2, inputs: inputs(.unavailable, size: .zero), slots: []) == .invalid
        let schema = SceneResolvedMaterialHostUniformSchema.self
        facts["exact-host-shapes"] = schema.resolve(field("g_LightsPosition", .float3, 4),
            activeTextureSlots: [], hasEffectContext: true) == .lightsPosition
            && schema.resolve(field("g_LightsColorPremultiplied", .float4, 3),
                activeTextureSlots: [], hasEffectContext: true) == .lightsColorPremultiplied
            && schema.resolve(field("g_EffectModelMatrix", .float4x4),
                activeTextureSlots: [], hasEffectContext: true) == .effectModelMatrix
        facts["malformed-shape-reserved"] = schema.resolve(field("g_LightsPosition", .float3, 3),
            activeTextureSlots: [], hasEffectContext: true) == nil
            && schema.requiresEffectHost("g_LightsPosition", hasEffectContext: true)
            && schema.resolve(field("g_LightAmbientColor", .float4),
                activeTextureSlots: [], hasEffectContext: true) == nil
        facts["effect-context-required"] = schema.resolve(field("g_LightsPosition", .float3, 4),
            activeTextureSlots: [], hasEffectContext: false) == nil
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

FINALIZER_HARNESS = r'''
import Foundation
import Metal
import simd
@main enum ReservedLightingNames {
    static func finalized(_ declaration: String, expression: String,
                          lighting: SceneAuthoredShaderLightingInputs = .unavailable,
                          model: simd_float4x4? = nil, effect: Bool = true,
                          size: CGSize = .init(width: 8, height: 8)) -> String {
        let shader = contract(revision: "typed-lighting-" + declaration,
            vertexSourceOverride: """
            attribute vec3 a_Position;
            void main(){gl_Position=vec4(a_Position,1.0);}
            """, fragmentSourceOverride: """
            \(declaration)
            void main(){gl_FragColor=\(expression);}
            """)
        let material = template(shader, includePrimaryCandidate: false,
            effectContext: effect ? .init(key: .init(layerID: fixtureLayerID,
                effectIndex: 0, descriptorID: "typed-lighting"), input: graphTexture()) : nil)
        do {
            let frame = try SceneResolvedMaterialFrameSnapshot.validated(
                textureSnapshot: .init(frameEpoch: 1, frameIndex: 1, entries: [:]),
                dynamicSnapshot: .empty(frameIndex: 1), frameInputs: .init(frameIndex: 1,
                    screenSize: .init(width: 1210, height: 786), sceneTime: 1, dayTime: 0,
                    frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
                    lighting: lighting)).get()
            let input = frame.finalizationInput(template: material, renderSize: size,
                modelViewProjection: matrix_identity_float4x4,
                layerModelMatrix: matrix_identity_float4x4,
                effectOutputModelViewProjection: matrix_identity_float4x4,
                effectUnitModelMatrix: model,
                effectTextureProjectionMatrixInverse: matrix_identity_float4x4)
            let cache = try SceneResolvedMaterialVariantCache.launchValidated(
                template: material, maximumVariantCount: 4).get()
            switch cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil,
                outputStorage: .preservedRGBAUnorm) {
            case .success: break
            case let .failure(.material(failure)): return failure.code.rawValue
            case .failure(.capacity): return "capacity"
            }
            switch SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: cache,
                outputStorage: .preservedRGBAUnorm) {
            case .success: return "success"
            case let .failure(failure): return failure.code.rawValue
            }
        } catch let failure as SceneResolvedMaterialFailure {
            return failure.code.rawValue
        } catch { return "unexpected" }
    }
    static func attempt(_ name: String, type: SceneAuthoredShaderValueType,
                        declarations: [Template.UniformDeclaration],
                        values: [Double]) -> String {
        let shader = contract(revision: "owned-reserved-light-host", fragmentSourceOverride:
            "void main(){gl_FragColor=vec4(0.1,0.2,0.3,1.0);}")
        let material = template(shader, includePrimaryCandidate: false,
            uniformDeclarations: declarations, effectContext: nil)
        do {
            let prepared = try SceneResolvedMaterialProgramFinalizer.prepareUniformBindings(
                template: material,
                fields: [.init(name: name, type: type, offset: 0)],
                activeUniforms: [name: .init(name: name, materialKeys: [name],
                    defaultValue: staticValue(values), authoredRange: nil)],
                activeTextureSlots: [], neutralTextureResolution: nil)
            switch prepared[0].source {
            case .host: return "host"
            case .staticValue: return "static"
            case .dynamic: return "dynamic"
            default: return "other"
            }
        } catch let failure as SceneResolvedMaterialFailure {
            return failure.code.rawValue
        } catch { return "unexpected" }
    }
    static func main() throws {
        var facts: [String: Bool] = [:]
        for (name, type, values) in [
            ("g_LightsPosition", SceneAuthoredShaderValueType.float, [0.25]),
            ("g_LightsColorPremultiplied", .float, [0.25]),
            ("g_LightAmbientColor", .float3, [0.1, 0.2, 0.3]),
            ("g_EffectModelMatrix", .float4x4,
                [1.0,0,0,0,0,1,0,0,0,0,1,0,4,5,6,1]),
        ] {
            let declared = staticDeclaration(name, components: values)
            let dynamic = Template.UniformDeclaration(name: name, value: .dynamic(.init(
                target: .effectConstant(layerID: fixtureLayerID, effectIndex: 0,
                    passIndex: 0, name: name), valueContributors: [.timeline],
                scriptAttachments: [], authoredFallback: staticValue(values),
                authoredBindingKeys: ["value"])))
            for (label, declarations) in [("schema-default", []), ("static", [declared]),
                                           ("dynamic", [dynamic])] {
                facts[name + ":" + label] = attempt(name, type: type,
                    declarations: declarations, values: values) == "staticUniformBindingInvalid"
            }
        }
        facts["old-source-alpha-static-preserved"] = attempt("g_Alpha", type: .float,
            declarations: [staticDeclaration("g_Alpha", components: [0.25])],
            values: [0.75]) == "static"
        var builder = SceneAuthoredShaderLightingInputs.Builder(orthographicHeight: 786,
            ambient: [0.125, 0.25, 0.375])
        builder.appendPoint(renderWorldPosition: .zero, color: .init(repeating: 0.5),
            intensity: 0.5, radius: 4)
        let lighting = builder.finish()
        for (name, declaration, expression) in [
            ("model", "uniform mat4 g_EffectModelMatrix;",
                "g_EffectModelMatrix*vec4(0.0,0.0,0.0,1.0)"),
            ("positions", "uniform vec3 g_LightsPosition[4];", "vec4(g_LightsPosition[0],1.0)"),
            ("colors", "uniform vec4 g_LightsColorPremultiplied[3];", "g_LightsColorPremultiplied[0]"),
            ("ambient", "uniform vec3 g_LightAmbientColor;", "vec4(g_LightAmbientColor,1.0)")
        ] {
            facts["finalizer-optional-" + name] = finalized(declaration,
                expression: expression) == "hostUniformInputUnavailable"
            facts["finalizer-present-" + name] = finalized(declaration, expression: expression,
                lighting: lighting, model: matrix_identity_float4x4) == "success"
            facts["finalizer-no-effect-" + name] = finalized(declaration,
                expression: expression, lighting: lighting, model: matrix_identity_float4x4,
                effect: false) == "staticUniformBindingInvalid"
        }
        facts["finalizer-nil-world-geometry"] = finalized("uniform mat4 g_EffectModelMatrix;",
            expression: "g_EffectModelMatrix*vec4(0.0,0.0,0.0,1.0)",
            lighting: lighting) == "hostUniformInputUnavailable"
        facts["finalizer-wrong-type-remains-rejected"] = finalized(
            "uniform vec4 g_EffectModelMatrix;", expression: "g_EffectModelMatrix",
            lighting: lighting) == "staticUniformBindingInvalid"
        facts["finalizer-wrong-count-remains-rejected"] = finalized(
            "uniform vec3 g_LightsPosition[3];", expression: "vec4(g_LightsPosition[0],1.0)",
            lighting: lighting) == "shaderFrontendFailed"
        let malformed = SceneAuthoredShaderLightingInputs(positions: [.zero],
            colorsPremultiplied: nil, ambient: nil, worldFromRenderWorld: nil)
        facts["finalizer-malformed-payload-remains-invalid"] = finalized(
            "uniform vec3 g_LightsPosition[4];", expression: "vec4(g_LightsPosition[0],1.0)",
            lighting: malformed) == "hostUniformBindingInvalid"
        var badModel = matrix_identity_float4x4
        badModel.columns.0.x = .nan
        facts["finalizer-present-bad-matrix-remains-invalid"] = finalized(
            "uniform mat4 g_EffectModelMatrix;",
            expression: "g_EffectModelMatrix*vec4(0.0,0.0,0.0,1.0)", lighting: lighting,
            model: badModel) == "hostUniformBindingInvalid"
        facts["finalizer-old-host-remains-invalid"] = finalized("",
            expression: "vec4(0.1,0.2,0.3,1.0)", size: .zero) == "hostUniformBindingInvalid"
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class OrdinaryEffectLightingTests(unittest.TestCase):
    def test_actual_snapshot_and_uniform_encoding(self) -> None:
        model = (SCENE / "Compilation/ShaderFrontend/SceneAuthoredShaderFrontendModel.swift").read_text()
        program = (SCENE / "Compilation/Material/SceneResolvedMaterialProgram.swift").read_text()
        dynamic = (SCENE / "Systems/Properties/SceneDynamicSnapshot.swift").read_text()
        support = SUPPORT.replace("__HOST_ENUM__", method_body(program, "enum HostUniform:"))
        support = support.replace("__RADIUS_ACCEPTANCE__",
            method_body(dynamic, "nonisolated static func acceptsLightRadius("))
        support += "\n" + LIGHTING_STUB.replace(
            "struct SceneLayerDisplayScriptOwnership", "nonisolated struct SceneLayerDisplayScriptOwnership"
        ) + "\n"
        support += method_body(model, "nonisolated enum SceneAuthoredShaderValueType:") + "\n"
        support += method_body(model, "nonisolated enum SceneAuthoredShaderHostArrayShape") + "\n"
        support += method_body(model, "nonisolated struct SceneAuthoredShaderUniformLayout:") + "\n"
        paths = [SCENE / path for path in [
            "Rendering/Lighting/SceneAuthoredShaderLightingInputs.swift",
            "Rendering/Lighting/SceneLightSnapshot.swift",
            "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
            "Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift",
            "Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift",
            "Format/SceneDirectionalLightDefinition.swift", "Format/ScenePointLightDefinition.swift",
            "Format/SceneSpotLightDefinition.swift", "Rendering/Geometry/SceneMatrix.swift",
            "Rendering/Geometry/SceneLayerWorldFrameResolver.swift",
            "Rendering/Geometry/SceneLayerVisibility.swift",
            "Systems/Properties/SceneDynamicLayerValues.swift",
        ]]
        with tempfile.TemporaryDirectory(prefix="mwx-ordinary-light-") as tmp:
            work = Path(tmp)
            fixture = work / "Harness.swift"
            fixture.write_text("import Foundation\nimport simd\n" + support + HARNESS)
            binary = work / "probe"
            frozen = []
            hashes = {}
            for path in paths:
                data = path.read_bytes()
                hashes[path] = hashlib.sha256(data).hexdigest()
                target = work / path.name
                target.write_bytes(data)
                frozen.append(target)
            compiled = subprocess.run(["swiftc", "-swift-version", "6",
                "-default-isolation", "MainActor", "-warnings-as-errors",
                *map(str, frozen), str(fixture), "-o", str(binary)],
                capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(hashes, {
                path: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths
            }, "production sources changed during the frozen CPU gate")
            self.assertGreaterEqual(len(result), 18)
            self.assertTrue(all(result.values()), {key: value for key, value in result.items() if not value})

    def test_reserved_names_reject_real_finalizer_authored_fallback(self) -> None:
        from script.tests import test_scene_resolved_material_program_finalizer as fixture
        with tempfile.TemporaryDirectory(prefix="mwx-light-host-finalizer-") as tmp:
            work = Path(tmp)
            harness = work / "Harness.swift"
            harness.write_text(FINALIZER_HARNESS)
            sources = [*fixture.SWIFT_SOURCES, *fixture.SHARED_FIXTURE_SOURCES]
            frozen = []
            hashes = {}
            for index, source in enumerate(dict.fromkeys(sources)):
                data = source.read_bytes()
                hashes[source] = hashlib.sha256(data).hexdigest()
                target = work / f"source-{index}-{source.name}"
                target.write_bytes(data)
                frozen.append(target)
            binary = work / "probe"
            environment = os.environ.copy()
            environment["MWX_SCENE_GENERIC_SHADER_ROUTE"] = "disable-generic"
            environment["MWX_SCENE_GENERIC_SHADER_CACHE"] = str(work / "shader-cache")
            compiled = subprocess.run(["swiftc", "-parse-as-library", *map(str, frozen),
                str(harness), "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(binary)], capture_output=True, text=True, env=environment)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            facts = json.loads(completed.stdout)
            self.assertEqual(hashes, {
                path: hashlib.sha256(path.read_bytes()).hexdigest() for path in hashes
            }, "production sources changed during the frozen Finalizer CPU gate")
            self.assertEqual(len(facts), 31)
            self.assertTrue(all(facts.values()), {key: value for key, value in facts.items() if not value})


if __name__ == "__main__":
    unittest.main()
