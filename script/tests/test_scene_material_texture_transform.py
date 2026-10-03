#!/usr/bin/env python3

"""Authored texture coordinates through the real bounded Program/Metal path."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_resolved_material_pass_encoder import (
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SUPPORT as PASS_ENCODER_SUPPORT,
    SWIFT_SOURCES as PASS_ENCODER_SOURCES,
)


SUPPORT = PASS_ENCODER_SUPPORT.replace(
    """nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

""",
    "",
)

EXTRA_SOURCES = [
    SCENE_ROOT / "Systems/Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Rendering/Bindings/SceneAuthoredShaderFrameInputs.swift",
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift",
    SCENE_ROOT / "Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift",
]
SWIFT_SOURCES = list(dict.fromkeys([*PASS_ENCODER_SOURCES, *EXTRA_SOURCES]))


COORDINATE_HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

private typealias Program = SceneResolvedMaterialProgram
private typealias Graph = SceneAuthoredEffectRenderPlan

private struct CoordinateFixture {
    let name: String
    let vertex: String
    let fragment: String
    let slot: Int
}

private let point = "vec2(0.0891089141368866, 0.6699029207229614)"
private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position, 1.0);
}
"""

private func fixture(
    _ name: String, output: String, slot: Int = 1, vertexSource: String = vertex,
    helper: String = ""
) -> CoordinateFixture {
    .init(name: name, vertex: vertexSource, fragment: """
    varying vec2 v_TexCoord;
    uniform sampler2D g_Texture\(slot);
    \(helper)
    void main() { \(output) }
    """, slot: slot)
}

private let coordinateFixtures = [
    fixture("literal", output: "gl_FragColor = texSample2D(g_Texture1, \(point));"),
    fixture("explicit", output: """
        vec2 mapped = vec2(0.125) + 0.25 * \(point);
        gl_FragColor = texSample2D(g_Texture1, mapped);
        """),
    fixture("mixed", output: """
        vec4 raw = texSample2D(g_Texture1, \(point));
        vec2 mapped = vec2(0.125) + 0.25 * \(point);
        vec4 authored = texSample2D(g_Texture1, mapped);
        gl_FragColor = vec4(raw.r, authored.g, authored.b, 1.0);
        """),
    fixture("varying", output: "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);",
        vertexSource: vertex.replacingOccurrences(of: "v_TexCoord = a_TexCoord;",
            with: "v_TexCoord = \(point);")),
    fixture("vertex-explicit", output: "gl_FragColor = texSample2D(g_Texture1, v_TexCoord);",
        vertexSource: vertex.replacingOccurrences(of: "v_TexCoord = a_TexCoord;",
            with: "v_TexCoord = vec2(0.125) + 0.25 * \(point);")),
    fixture("helper-explicit", output: "gl_FragColor = texSample2D(g_Texture1, ownMap(\(point)));", helper: """
        vec2 ownMap(vec2 arbitraryName) {
            return vec2(0.125) + 0.25 * arbitraryName;
        }
        """),
    fixture("lod-zero", output: "vec4 c = texSample2DLod(g_Texture1, \(point), 0.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("lod-one", output: "vec4 c = texSample2DLod(g_Texture1, \(point), 1.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("texture-lod-one", output: "vec4 c = texture2DLod(g_Texture1, \(point), 1.0); gl_FragColor = vec4(c.rgb, 1.0);"),
    fixture("slot-zero", output: "gl_FragColor = texSample2D(g_Texture0, \(point));", slot: 0),
    fixture("slot-seven", output: "gl_FragColor = texSample2D(g_Texture7, \(point));", slot: 7),
]

// The reviewed profiles keep physical/header and mip size equal at 384x192.
// Mapped extent differs independently; this does not decide animation phase.
private let fragmentCompanionFixtures = [
    fixture("companion-rotation-xyz", output: """
        vec4 sampled = texSample2D(g_Texture1, \(point));
        gl_FragColor = vec4(g_Texture1Rotation.xyz * sampled.a, 1.0);
        """, helper: "uniform vec4 g_Texture1Rotation;"),
    fixture("companion-rotation-w", output: """
        vec4 sampled = texSample2D(g_Texture1, \(point));
        gl_FragColor = vec4(g_Texture1Rotation.w * sampled.a, 0.0, 0.0, 1.0);
        """, helper: "uniform vec4 g_Texture1Rotation;"),
    fixture("companion-translation", output: """
        vec4 sampled = texSample2D(g_Texture1, \(point));
        gl_FragColor = vec4(g_Texture1Translation * sampled.a, 0.0, 1.0);
        """, helper: "uniform vec2 g_Texture1Translation;"),
    fixture("companion-explicit-sample", output: """
        vec2 authored = g_Texture1Translation + vec2(
            g_Texture1Rotation.x * \(point).x + g_Texture1Rotation.z * \(point).y,
            g_Texture1Rotation.y * \(point).x + g_Texture1Rotation.w * \(point).y);
        vec4 sampled = texSample2D(g_Texture1, authored);
        gl_FragColor = vec4(sampled.rgb, 1.0);
        """, helper: "uniform vec4 g_Texture1Rotation;\nuniform vec2 g_Texture1Translation;"),
]

private func companionAtSlot(_ fixture: CoordinateFixture, slot: Int) -> CoordinateFixture {
    .init(name: "\(fixture.name)-slot-\(slot)",
        vertex: fixture.vertex.replacingOccurrences(of: "g_Texture1", with: "g_Texture\(slot)"),
        fragment: fixture.fragment.replacingOccurrences(of: "g_Texture1", with: "g_Texture\(slot)"),
        slot: slot)
}

private func vertexCompanion(
    _ name: String, declaration: String, value: String, output: String
) -> CoordinateFixture {
    fixture("vertex-\(name)", output: """
        vec4 sampled = texSample2D(g_Texture1, v_TexCoord);
        \(output)
        """, vertexSource: vertex
            .replacingOccurrences(of: "varying vec2 v_TexCoord;", with: """
                varying vec2 v_TexCoord;
                varying vec4 v_Companion;
                \(declaration)
                """)
            .replacingOccurrences(of: "v_TexCoord = a_TexCoord;", with: """
                v_TexCoord = \(point);
                v_Companion = \(value);
                """), helper: "varying vec4 v_Companion;")
}

private let companionFixtures = fragmentCompanionFixtures
    + [0, 7].flatMap { slot in fragmentCompanionFixtures.map { companionAtSlot($0, slot: slot) } }
    + [
        vertexCompanion("companion-rotation-xyz", declaration: "uniform vec4 g_Texture1Rotation;",
            value: "g_Texture1Rotation",
            output: "gl_FragColor = vec4(v_Companion.xyz * sampled.a, 1.0);"),
        vertexCompanion("companion-rotation-w", declaration: "uniform vec4 g_Texture1Rotation;",
            value: "g_Texture1Rotation",
            output: "gl_FragColor = vec4(v_Companion.w * sampled.a, 0.0, 0.0, 1.0);"),
        vertexCompanion("companion-translation", declaration: "uniform vec2 g_Texture1Translation;",
            value: "vec4(g_Texture1Translation, 0.0, 1.0)",
            output: "gl_FragColor = vec4(v_Companion.xy * sampled.a, 0.0, 1.0);"),
        fixture("vertex-companion-explicit-sample",
            output: "vec4 sampled = texSample2D(g_Texture1, v_TexCoord); gl_FragColor = vec4(sampled.rgb, 1.0);",
            vertexSource: vertex
                .replacingOccurrences(of: "varying vec2 v_TexCoord;", with: """
                    varying vec2 v_TexCoord;
                    uniform vec4 g_Texture1Rotation;
                    uniform vec2 g_Texture1Translation;
                    """)
                .replacingOccurrences(of: "v_TexCoord = a_TexCoord;", with: """
                    v_TexCoord = g_Texture1Translation + vec2(
                        g_Texture1Rotation.x * \(point).x + g_Texture1Rotation.z * \(point).y,
                        g_Texture1Rotation.y * \(point).x + g_Texture1Rotation.w * \(point).y);
                    """)),
    ] + [fixture("companion-mapped-resolution", output: """
        vec4 sampled = texSample2D(g_Texture1, \(point));
        gl_FragColor = vec4(g_Texture1Resolution.zw / vec2(512.0) * sampled.a, 0.0, 1.0);
        """, helper: "uniform vec4 g_Texture1Resolution;")]

private func prepared(_ fixture: CoordinateFixture) -> SceneShaderPreparedProgram {
    func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderPreparedSource {
        let digest = SceneGenericShaderProgramArtifact.sha256(Data(source.utf8))
        return .init(
            frontendSchemaVersion: SceneShaderVariantEnvironment.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike, backend: .mwxMetal, stage: kind,
            rootRelativePath: "self-authored/\(fixture.name)/\(kind.rawValue).shader",
            source: source, sourceMap: [], activeAnnotations: [], activeDeclarations: [],
            dependencies: [], dependencySHA256: digest, variantSHA256: digest,
            preparedSHA256: digest
        )
    }
    return .init(vertex: stage(.vertex, fixture.vertex),
        fragment: stage(.fragment, fixture.fragment),
        colorContract: .unresolvedAuthoredPass, cacheKey: "own-\(fixture.name)")
}

private func texture(_ device: MTLDevice, redOffset: UInt8 = 0) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 384, height: 192, mipmapped: true)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    let value = device.makeTexture(descriptor: descriptor)!
    for level in 0..<value.mipmapLevelCount {
        let width = max(1, 384 >> level), height = max(1, 192 >> level)
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                if level == 0 {
                    let c = x / 24, r = y / 24
                    bytes += [UInt8(16 + 14*c) + redOffset, UInt8(16 + 14*r),
                        UInt8(32 + 7*((c + 3*r) % 24)), 255]
                } else {
                    // Every authored level is initialized; level 1 differs from level 0.
                    bytes += [77 + redOffset, 123, 201, 255]
                }
            }
        }
        bytes.withUnsafeBytes {
            value.replace(region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level, withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
    }
    return value
}

private func target(_ device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}

private func selectedSlot(
    index: Int, texture: MTLTexture, transform: SceneTextureUVTransform,
    generation: UInt64, mappedSize: CGSize = CGSize(width: 384, height: 192),
    isSpriteSheet: Bool = false
) -> Program.TextureSlot {
    let effect = Graph.EffectKey(layerID: 42, effectIndex: 1, descriptorID: "own-atlas")
    let identity = Graph.TextureIdentity(kind: .framebuffer, layerID: 42,
        effect: effect, name: "own-atlas")
    let candidate = SceneTextureCandidate(
        texture: texture, identity: .provider(.video(layerID: 42, lifecycleEpoch: 1)),
        generation: .provider(contentGeneration: generation), purpose: .premultipliedColor,
        content: .color(.resolved(.premultipliedAlpha)),
        physicalSize: CGSize(width: 384, height: 192),
        mappedSize: mappedSize, uvTransform: transform, isSpriteSheet: isSpriteSheet,
        sampling: .init(texFlags: 3))
    return .init(index: index, reference: .graph(identity), registryIdentity: .graph(identity),
        diagnosticSelectionProvenance: .authored(.explicitBinding),
        expectedPurpose: .premultipliedColor,
        resource: .init(publication: .init(requestIdentity: .graph(identity),
            candidate: candidate, contentGeneration: generation),
            resourceGeneration: generation))
}

private func inputs(index: Int, generation: UInt64) -> SceneAuthoredShaderUniformInputs {
    .init(frameIndex: generation, renderSize: CGSize(width: 2, height: 2),
        screenSize: CGSize(width: 2, height: 2),
        modelViewProjection: matrix_identity_float4x4,
        layerModelMatrix: matrix_identity_float4x4,
        effectOutputModelViewProjection: matrix_identity_float4x4,
        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
        sceneTime: Float(generation), dayTime: 0, frameTime: 1 / 60,
        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero,
        texturePhysicalSizes: [index: CGSize(width: 384, height: 192)])
}

private func assembly(
    fixture: CoordinateFixture, frontend: SceneAuthoredShaderProgram,
    selected: Program.TextureSlot, generation: UInt64,
    outputStorage: Program.OutputStorage = .color,
    failure: ((String, String) -> Void)? = nil
) -> Program.AssemblyInput? {
    var slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    slots[fixture.slot] = selected
    var resolved: [Program.ResolvedUniform] = []
    for field in frontend.uniformLayout.fields {
        guard let host = SceneResolvedMaterialUniformEncoder.hostUniform(field, slots: slots) else {
            failure?("host-schema-missing", field.authoredName)
            return nil
        }
        guard let value = SceneResolvedMaterialUniformEncoder.encodeHost(host,
                type: field.type, inputs: inputs(index: fixture.slot, generation: generation),
                slots: slots) else {
            failure?("host-encode-rejected", field.authoredName)
            return nil
        }
        resolved.append(.init(field: field, source: .host(host), encodedValue: value))
    }
    return .init(preparedShader: prepared(fixture), textureSlots: slots,
        resolvedUniforms: resolved,
        renderState: SceneMaterialRenderState.compile(blending: "normal",
            depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
            alphaWriting: nil)!,
        graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
            nodeTarget: .framebuffer, bindings: [.init(slot: fixture.slot, texture: .framebuffer)]),
        outputStorage: outputStorage)
}

private func render(
    _ program: Program, encoder: SceneResolvedMaterialPassEncoder,
    queue: MTLCommandQueue, device: MTLDevice
) throws -> [String: Any] {
    let output = target(device)
    let attachment: SceneResolvedMaterialAttachmentKind =
        program.outputContract == .preservedRGBAUnorm ? .preservedRGBAUnorm : .color
    guard let pass = try? encoder.prepareResult(program: program, target: output,
            attachmentStorage: attachment).get(),
          let command = queue.makeCommandBuffer(),
          encoder.encode(pass, commandBuffer: command) else {
        throw NSError(domain: "pass-encode", code: 1)
    }
    command.commit()
    command.waitUntilCompleted()
    let completed = command.status == .completed && command.error == nil
    var pixels = [UInt8](repeating: 0, count: 16)
    if completed {
        pixels.withUnsafeMutableBytes {
            output.getBytes($0.baseAddress!, bytesPerRow: 8,
                from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        }
    }
    return ["completed": completed, "pixels": pixels,
        "pipelineAttempts": encoder.pipelineCompilationAttemptCount]
}

private func runCoordinates(
    generic: Bool, frontend: (CoordinateFixture) throws -> SceneAuthoredShaderProgram
) throws -> [String: Any] {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
          let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
        return ["metalAvailable": false]
    }
    let original = texture(device), replacement = texture(device, redOffset: 7)
    let transforms = [SceneTextureUVTransform.identity,
        SceneTextureUVTransform(origin: SIMD2(0.125, 0.125),
            xAxis: SIMD2(0.25, 0), yAxis: SIMD2(0, 0.25)),
        SceneTextureUVTransform.identity]
    var results: [String: Any] = [:]
    for fixture in coordinateFixtures {
        let compiled = try frontend(fixture)
        var frames: [[String: Any]] = []
        var previous: Program?
        for (index, transform) in transforms.enumerated() {
            let generation = UInt64(index + 1)
            let selected = selectedSlot(index: fixture.slot,
                texture: index == 2 ? replacement : original,
                transform: transform, generation: generation)
            guard let input = assembly(fixture: fixture, frontend: compiled,
                    selected: selected, generation: generation) else {
                throw NSError(domain: "assembly-input-\(fixture.name)", code: index)
            }
            let program = generic ? Program.assembleCompiled(input, frontend: compiled,
                routeDecision: .init(profile: "ordinary-shader", state: "prefer-generic",
                    fallbackOwner: "bounded-frontend"),
                conditionalGeneratedRGBInputContract: nil) : Program.assemble(input)
            guard let program else {
                throw NSError(domain: "program-\(fixture.name)", code: index,
                    userInfo: [NSLocalizedDescriptionKey: "transfer=\(compiled.colorTransfer)"])
            }
            var frame = try render(program, encoder: encoder, queue: queue, device: device)
            frame["generation"] = generation
            frame["exactIdentityChanged"] = previous.map {
                $0.exactIdentity != program.exactIdentity
            } ?? true
            frame["resourceGeneration"] = selected.resource.resourceGeneration
            frames.append(frame)
            previous = program
        }
        results[fixture.name] = ["slot": fixture.slot,
            "backend": String(describing: compiled.backend),
            "physicalSize": [384, 192],
            "vertexSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.vertex.utf8)),
            "fragmentSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.fragment.utf8)),
            "metalSHA256": SceneGenericShaderProgramArtifact.sha256(Data(compiled.metalSource.utf8)),
            "frames": frames]
    }
    return ["metalAvailable": true, "device": device.name, "fixtures": results]
}

// Numeric companion probes use the existing preserved-channel target contract;
// actual color effect/compositor behavior is exercised by the isolated App gate.
private func runCompanions(
    generic: Bool, frontend: (CoordinateFixture) throws -> SceneAuthoredShaderProgram
) throws -> [String: Any] {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
          let encoder = SceneResolvedMaterialPassEncoder(device: device) else {
        return ["metalAvailable": false]
    }
    let source = texture(device)
    let fullSize = CGSize(width: 384, height: 192)
    let axis = SceneTextureUVTransform(origin: SIMD2(0.125, 0.125),
        xAxis: SIMD2(0.25, 0), yAxis: SIMD2(0, 0.25))
    let profiles: [(name: String, transform: SceneTextureUVTransform,
                    mappedSize: CGSize, isSpriteSheet: Bool)] = [
        ("axis", axis, fullSize, true),
        ("move-x", SceneTextureUVTransform(origin: SIMD2(0.1875, 0.125),
            xAxis: SIMD2(0.25, 0), yAxis: SIMD2(0, 0.25)), fullSize, true),
        ("neutral", .identity, fullSize, true),
        ("axis-mapped-width", axis, CGSize(width: 192, height: 192), true),
        ("axis-mapped-height", axis, CGSize(width: 384, height: 96), true),
        ("non-sprite-full", .identity, fullSize, false),
        ("non-sprite-padding", .init(origin: .zero,
            xAxis: SIMD2(0.5, 0), yAxis: SIMD2(0, 0.5)),
            CGSize(width: 192, height: 96), false),
    ]
    var results: [String: Any] = [:]
    var validation: [String: Any] = [:]
    for fixture in companionFixtures {
        let compiled = try frontend(fixture)
        var observations: [[String: Any]] = []
        var previous: Program?
        for (index, profile) in profiles.enumerated() {
            let generation = UInt64(index + 1)
            let selected = selectedSlot(index: fixture.slot, texture: source,
                transform: profile.transform, generation: generation,
                mappedSize: profile.mappedSize, isSpriteSheet: profile.isSpriteSheet)
            let candidate = selected.resource.publication.candidate
            var observation: [String: Any] = ["profile": profile.name, "status": "pending",
                "mappedSize": [Int(candidate.mappedSize.width), Int(candidate.mappedSize.height)],
                "isSpriteSheet": candidate.isSpriteSheet,
                "generation": generation, "resourceGeneration": selected.resource.resourceGeneration]
            if let input = assembly(fixture: fixture, frontend: compiled,
                    selected: selected, generation: generation, outputStorage: .preservedRGBAUnorm,
                    failure: { status, field in
                        observation["status"] = status
                        observation["field"] = field
                    }) {
                let program = generic ? Program.assembleCompiled(input, frontend: compiled,
                    routeDecision: .init(profile: "ordinary-shader", state: "prefer-generic",
                        fallbackOwner: "bounded-frontend"),
                    conditionalGeneratedRGBInputContract: nil) : Program.assemble(input)
                if let program {
                    observation.merge(try render(program, encoder: encoder,
                        queue: queue, device: device)) { _, rendered in rendered }
                    observation["status"] = "assembled"
                    observation["exactIdentityChanged"] = previous.map {
                        $0.exactIdentity != program.exactIdentity
                    } ?? true
                    observation["semanticIdentityStable"] = previous.map {
                        $0.semanticIdentity == program.semanticIdentity
                    } ?? true
                    previous = program
                } else {
                    observation["status"] = "program-rejected"
                }
            }
            observations.append(observation)
        }
        if ["companion-rotation-xyz", "companion-translation"].contains(fixture.name) {
            validation[fixture.name] = companionRejections(fixture: fixture, frontend: compiled,
                selected: selectedSlot(index: fixture.slot, texture: source,
                    transform: axis, generation: 1, isSpriteSheet: true), generic: generic)
        }
        results[fixture.name] = ["slot": fixture.slot,
            "backend": String(describing: compiled.backend),
            "physicalSize": [384, 192],
            "vertexSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.vertex.utf8)),
            "fragmentSHA256": SceneGenericShaderProgramArtifact.sha256(Data(fixture.fragment.utf8)),
            "metalSHA256": SceneGenericShaderProgramArtifact.sha256(Data(compiled.metalSource.utf8)),
            "observations": observations]
    }
    results.merge(try companionStaticFallbackRejections(frontend: frontend,
        selected: selectedSlot(index: 1, texture: source,
            transform: axis, generation: 1, isSpriteSheet: true))) { _, probe in probe }
    var result: [String: Any] = ["metalAvailable": true,
        "fixtures": results, "validation": validation]
    if !generic {
        var arrays: [String: Any] = [:]
        for (suffix, type) in [("Rotation", "vec4"), ("Translation", "vec2")] {
            let name = "g_Texture1\(suffix)"
            let compiled = SceneAuthoredShaderFrontend.compile(vertexSource: vertex,
                fragmentSource: """
                    uniform sampler2D g_Texture1;
                    uniform \(type) \(name)[1];
                    void main() {
                        vec4 sampled = texSample2D(g_Texture1, \(point));
                        gl_FragColor = vec4(\(name)[0].x * sampled.a, 0.0, 0.0, 1.0);
                    }
                    """)
            arrays[suffix] = ["frontendRejected": compiled.program == nil,
                "unsupportedType": compiled.diagnostics.contains {
                    $0.code == .unsupportedType && $0.message.contains(name)
                }]
        }
        // These sources stop at the bounded frontend, before Program assembly.
        result["boundedArraySourceRejections"] = arrays
    }
    return result
}

// Compile each invalid declaration rather than mutating a field after reflection.
// Ordinary-name controls prove that legal static bytes and the remaining inputs
// are accepted, so reserved companion ownership is the rejecting boundary.
private func companionStaticFallbackRejections(
    frontend: (CoordinateFixture) throws -> SceneAuthoredShaderProgram,
    selected: Program.TextureSlot
) throws -> [String: Any] {
    let cases: [(name: String, suffix: String, declaration: String,
                 type: SceneAuthoredShaderValueType, samplerActive: Bool)] = [
        ("rotation-wrong-type", "Rotation", "vec3", .float3, true),
        ("translation-wrong-type", "Translation", "vec4", .float4, true),
        ("rotation-inactive-sampler", "Rotation", "vec4", .float4, false),
        ("translation-inactive-sampler", "Translation", "vec2", .float2, false),
    ]
    var results: [String: Any] = [:]
    for testCase in cases {
        for reserved in [true, false] {
            let name = "\(reserved ? "reserved" : "ordinary")-static-\(testCase.name)"
            let uniformName = reserved ? "g_Texture1\(testCase.suffix)" : "own\(testCase.suffix)"
            let sampler = testCase.samplerActive ? "uniform sampler2D g_Texture1;" : ""
            let sample = testCase.samplerActive
                ? "vec4 sampled = texSample2D(g_Texture1, \(point));" : ""
            let alpha = testCase.samplerActive ? " * sampled.a" : ""
            let fixture = CoordinateFixture(name: name, vertex: vertex, fragment: """
                \(sampler)
                uniform \(testCase.declaration) \(uniformName);
                void main() {
                    \(sample)
                    gl_FragColor = vec4(\(uniformName).x\(alpha), 0.0, 0.0, 1.0);
                }
                """, slot: 1)
            let compiled = try frontend(fixture)
            var slots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
            if testCase.samplerActive { slots[1] = selected }
            // Only the source-authored field attempts static fallback. Existing
            // compiler host fields (such as render size) retain their real owner.
            let uniforms = try compiled.uniformLayout.fields.map { field -> Program.ResolvedUniform in
                if field.authoredName == uniformName {
                    return .init(field: field, source: .staticValue,
                        encodedValue: Data(count: field.storageByteSize))
                }
                guard let host = SceneResolvedMaterialUniformEncoder.hostUniform(field, slots: slots),
                      let value = SceneResolvedMaterialUniformEncoder.encodeHost(host,
                        type: field.type, inputs: inputs(index: 1, generation: 1), slots: slots) else {
                    throw NSError(domain: "unexpected-static-probe-field", code: 1)
                }
                return .init(field: field, source: .host(host), encodedValue: value)
            }
            let input = Program.AssemblyInput(preparedShader: prepared(fixture),
                textureSlots: slots, resolvedUniforms: uniforms,
                renderState: SceneMaterialRenderState.compile(blending: "normal",
                    depthTest: "disabled", depthWrite: "disabled", cullMode: "nocull",
                    alphaWriting: nil)!,
                graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
                    nodeTarget: .framebuffer, bindings: testCase.samplerActive
                        ? [.init(slot: 1, texture: .framebuffer)] : []),
                outputStorage: .preservedRGBAUnorm)
            let field = compiled.uniformLayout.fields.first { $0.authoredName == uniformName }
            results[name] = [
                "backend": String(describing: compiled.backend),
                "metalSHA256": SceneGenericShaderProgramArtifact.sha256(Data(compiled.metalSource.utf8)),
                "fieldShapeMatches": field?.type == testCase.type
                    && field?.arrayCount == nil
                    && compiled.uniformLayout.fields.filter { $0.authoredName == uniformName }.count == 1,
                "activeSamplerMatches": compiled.textureBindings.map(\.slot)
                    == (testCase.samplerActive ? [1] : []),
                "assembleAccepted": Program.assemble(input) != nil,
                "assembleCompiledAccepted": Program.assembleCompiled(input, frontend: compiled,
                    routeDecision: .init(profile: "ordinary-shader", state: "prefer-generic",
                        fallbackOwner: "bounded-frontend"),
                    conditionalGeneratedRGBInputContract: nil) != nil,
            ]
        }
    }
    return results
}

private func companionRejections(
    fixture: CoordinateFixture, frontend: SceneAuthoredShaderProgram,
    selected: Program.TextureSlot, generic: Bool
) -> [String: Any] {
    typealias Field = SceneAuthoredShaderUniformLayout.Field
    guard let field = frontend.uniformLayout.fields.first(where: {
        $0.authoredName.hasSuffix("Rotation") || $0.authoredName.hasSuffix("Translation")
    }) else { return ["status": "active-companion-missing"] }
    let wrongType: SceneAuthoredShaderValueType = field.type == .float4 ? .float3 : .float4
    func changedField(type: SceneAuthoredShaderValueType, arrayCount: Int? = nil,
                      authoredName: String? = nil) -> Field {
        .init(name: field.name, authoredName: authoredName ?? field.authoredName,
            stage: field.stage, type: type, arrayCount: arrayCount, offset: field.offset)
    }
    let typedWrong = changedField(type: wrongType)
    let arrayWrong = changedField(type: field.type, arrayCount: 2)
    let slotEight = changedField(type: field.type,
        authoredName: field.authoredName.replacingOccurrences(of: "g_Texture1", with: "g_Texture8"))
    var checks = [
        "schemaMissingActiveSampler": SceneResolvedMaterialHostUniformSchema.resolve(
            field, activeTextureSlots: []) == nil,
        "schemaWrongType": SceneResolvedMaterialHostUniformSchema.resolve(
            typedWrong, activeTextureSlots: [fixture.slot]) == nil,
        "schemaArray": SceneResolvedMaterialHostUniformSchema.resolve(
            arrayWrong, activeTextureSlots: [fixture.slot]) == nil,
        "schemaSlotEight": SceneResolvedMaterialHostUniformSchema.resolve(
            slotEight, activeTextureSlots: [8]) == nil,
    ]
    guard let host = SceneResolvedMaterialHostUniformSchema.resolve(
            field, activeTextureSlots: [fixture.slot]),
          let baseline = assembly(fixture: fixture, frontend: frontend,
            selected: selected, generation: 1, outputStorage: .preservedRGBAUnorm) else {
        return ["status": "producer-unavailable", "rejected": checks]
    }
    func assembled(_ input: Program.AssemblyInput) -> Program? {
        generic ? Program.assembleCompiled(input, frontend: frontend,
            routeDecision: .init(profile: "ordinary-shader", state: "prefer-generic",
                fallbackOwner: "bounded-frontend"),
            conditionalGeneratedRGBInputContract: nil) : Program.assemble(input)
    }
    func changedInput(slots: [Program.TextureSlot?]? = nil,
                      uniforms: [Program.ResolvedUniform]? = nil) -> Program.AssemblyInput {
        .init(preparedShader: baseline.preparedShader, textureSlots: slots ?? baseline.textureSlots,
            resolvedUniforms: uniforms ?? baseline.resolvedUniforms, renderState: baseline.renderState,
            graphRole: baseline.graphRole, outputStorage: baseline.outputStorage,
            runtimeLoopBounds: baseline.runtimeLoopBounds)
    }
    func replacingUniform(_ replace: (Program.ResolvedUniform) -> Program.ResolvedUniform)
        -> [Program.ResolvedUniform] {
        baseline.resolvedUniforms.map { $0.field == field ? replace($0) : $0 }
    }
    let emptySlots = Array<Program.TextureSlot?>(repeating: nil, count: 8)
    checks["encoderWrongType"] = SceneResolvedMaterialUniformEncoder.encodeHost(host,
        type: wrongType, inputs: inputs(index: fixture.slot, generation: 1),
        slots: baseline.textureSlots) == nil
    checks["encoderMissingBinding"] = SceneResolvedMaterialUniformEncoder.encodeHost(host,
        type: field.type, inputs: inputs(index: fixture.slot, generation: 1), slots: emptySlots) == nil
    checks["programMissingBinding"] = assembled(changedInput(slots: emptySlots)) == nil
    checks["programWrongType"] = assembled(changedInput(uniforms: replacingUniform {
        .init(field: typedWrong, source: $0.source, encodedValue: $0.encodedValue)
    })) == nil
    checks["programArray"] = assembled(changedInput(uniforms: replacingUniform {
        .init(field: arrayWrong, source: $0.source, encodedValue: $0.encodedValue)
    })) == nil
    checks["programWrongSource"] = assembled(changedInput(uniforms: replacingUniform {
        .init(field: $0.field, source: .staticValue, encodedValue: $0.encodedValue)
    })) == nil
    checks["programTruncatedBytes"] = assembled(changedInput(uniforms: replacingUniform {
        .init(field: $0.field, source: $0.source, encodedValue: Data($0.encodedValue.dropLast()))
    })) == nil
    return ["status": "ready", "baselineProgramAccepted": assembled(baseline) != nil,
        "rejected": checks]
}
'''

HARNESS = COORDINATE_HARNESS + r'''
@main private enum Main {
    static func main() throws {
        let compileFixture: (CoordinateFixture) throws -> SceneAuthoredShaderProgram = { fixture in
            let compiled = SceneAuthoredShaderFrontend.compile(
                vertexSource: fixture.vertex, fragmentSource: fixture.fragment)
            guard let frontend = compiled.program else {
                throw NSError(domain: "bounded-\(fixture.name)", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(describing: compiled.diagnostics)])
            }
            return frontend
        }
        var result = try runCoordinates(generic: false, frontend: compileFixture)
        result["companions"] = try runCompanions(generic: false, frontend: compileFixture)
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def source_hashes(paths: list[Path]) -> dict[str, str]:
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def fixture_environment(root: Path) -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        CLANG_MODULE_CACHE_PATH=str(root / "clang-cache"),
        SWIFT_MODULECACHE_PATH=str(root / "swift-cache"),
        MWX_SCENE_GENERIC_SHADER_CACHE=str(root / "program-cache"),
    )
    return environment


def preserve_evidence(
    root: Path, name: str, before: dict[str, str], after: dict[str, str],
    command: list[str], compile_result: subprocess.CompletedProcess[str],
    completed: subprocess.CompletedProcess[str],
) -> None:
    destination = os.environ.get("MWX_SCENE_COORDINATE_EVIDENCE")
    if not destination:
        return
    output = Path(destination) / name
    output.mkdir(parents=True, exist_ok=False)
    for path in root.iterdir():
        if path.is_file():
            shutil.copy2(path, output / path.name)
        elif path.name in ("artifacts", "Compiler.bundle"):
            shutil.copytree(path, output / path.name)
    (output / "identity.json").write_text(json.dumps({
        "command": command, "inputHashesBefore": before, "inputHashesAfter": after,
        "sameInputs": before == after, "compileExit": compile_result.returncode,
        "runExit": completed.returncode,
        "outputHashes": source_hashes([path for path in output.rglob("*") if path.is_file()]),
    }, indent=2), encoding="utf-8")
    (output / "compile.stderr").write_text(compile_result.stderr, encoding="utf-8")
    (output / "result.json").write_text(completed.stdout, encoding="utf-8")
    (output / "run.stderr").write_text(completed.stderr, encoding="utf-8")


def assert_coordinate_pixels(test: unittest.TestCase, result: dict, backend: str) -> None:
    # Independent fixed oracle for the self-authored nearest-sampled atlas.
    expected = {
        "literal": [30, 86, 144, 255], "explicit": [44, 44, 88, 255],
        "mixed": [30, 44, 88, 255], "varying": [30, 86, 144, 255],
        "vertex-explicit": [44, 44, 88, 255], "helper-explicit": [44, 44, 88, 255],
        "lod-zero": [30, 86, 144, 255], "lod-one": [77, 123, 201, 255],
        "texture-lod-one": [77, 123, 201, 255],
        "slot-zero": [30, 86, 144, 255], "slot-seven": [30, 86, 144, 255],
    }
    test.assertEqual(set(result["fixtures"]), set(expected), result)
    for name, pixel in expected.items():
        with test.subTest(fixture=name):
            fixture = result["fixtures"][name]
            test.assertEqual(fixture["backend"], backend)
            test.assertEqual(fixture["physicalSize"], [384, 192])
            test.assertEqual(fixture["slot"], {"slot-zero": 0, "slot-seven": 7}.get(name, 1))
            test.assertEqual(len(fixture["frames"]), 3)
            for index, frame in enumerate(fixture["frames"]):
                test.assertTrue(frame["completed"], frame)
                test.assertTrue(frame["exactIdentityChanged"], frame)
                test.assertEqual(frame["generation"], index + 1)
                test.assertEqual(frame["resourceGeneration"], index + 1)
                rgba = pixel.copy()
                if index == 2:
                    rgba[0] += 7
                test.assertEqual(frame["pixels"], rgba * 4, (name, index, frame))
            test.assertEqual(len({f["pipelineAttempts"] for f in fixture["frames"]}), 1, fixture)


STATIC_COMPANION_CASES = (
    "rotation-wrong-type", "translation-wrong-type",
    "rotation-inactive-sampler", "translation-inactive-sampler",
)
STATIC_COMPANION_FIXTURES = {
    f"{prefix}-static-{case}"
    for prefix in ("reserved", "ordinary") for case in STATIC_COMPANION_CASES
}


def assert_companion_pixels(test: unittest.TestCase, result: dict, backend: str) -> None:
    # Every value in each reviewed interval rounds to this RGBA8 output.
    # This does not recover the exact official floating-point value.
    base = {
        "companion-rotation-xyz": {
            "axis": [64, 0, 0, 255], "move-x": [64, 0, 0, 255], "neutral": [255, 0, 0, 255]},
        "companion-rotation-w": {
            "axis": [64, 0, 0, 255], "move-x": [64, 0, 0, 255], "neutral": [255, 0, 0, 255]},
        "companion-translation": {
            "axis": [32, 32, 0, 255], "move-x": [48, 32, 0, 255], "neutral": [0, 0, 0, 255]},
        "companion-explicit-sample": {
            "axis": [44, 44, 88, 255], "move-x": [58, 44, 95, 255], "neutral": [30, 86, 144, 255]},
    }
    metadata = {
        "axis": ([384, 192], True), "move-x": ([384, 192], True),
        "neutral": ([384, 192], True), "axis-mapped-width": ([192, 192], True),
        "axis-mapped-height": ([384, 96], True), "non-sprite-full": ([384, 192], False),
        "non-sprite-padding": ([192, 96], False),
    }
    for name, profiles in base.items():
        profiles["axis-mapped-width"] = profiles["axis"]
        profiles["axis-mapped-height"] = profiles["axis"]
        # Zero companions explicitly sample the first texel in the authored sample fixture.
        zero_pixel = [16, 16, 32, 255] if name == "companion-explicit-sample" else [0, 0, 0, 255]
        profiles["non-sprite-full"] = zero_pixel
        profiles["non-sprite-padding"] = zero_pixel
    expected = base | {f"{name}-slot-{slot}": profiles
                       for slot in (0, 7) for name, profiles in base.items()}
    expected |= {f"vertex-{name}": profiles for name, profiles in base.items()}
    expected["companion-mapped-resolution"] = {
        profile: [round(mapped[0] / 512 * 255), round(mapped[1] / 512 * 255), 0, 255]
        for profile, (mapped, _) in metadata.items()
    }
    fixtures = result["companions"]["fixtures"]
    test.assertEqual(set(fixtures), set(expected) | STATIC_COMPANION_FIXTURES, result)
    for name, profiles in expected.items():
        fixture = fixtures[name]
        test.assertEqual(fixture["backend"], backend)
        slot = 0 if name.endswith("-slot-0") else 7 if name.endswith("-slot-7") else 1
        test.assertEqual(fixture["slot"], slot)
        test.assertEqual(fixture["physicalSize"], [384, 192])
        test.assertEqual([value["profile"] for value in fixture["observations"]],
                         list(metadata))
        for index, observation in enumerate(fixture["observations"]):
            with test.subTest(fixture=name, profile=observation["profile"]):
                mapped, is_sprite = metadata[observation["profile"]]
                test.assertEqual(observation["status"], "assembled", observation)
                test.assertTrue(observation["completed"], observation)
                test.assertTrue(observation["exactIdentityChanged"], observation)
                test.assertTrue(observation["semanticIdentityStable"], observation)
                test.assertEqual(observation["mappedSize"], mapped)
                test.assertEqual(observation["isSpriteSheet"], is_sprite)
                test.assertEqual(observation["generation"], index + 1)
                test.assertEqual(observation["resourceGeneration"], index + 1)
                test.assertEqual(observation["pixels"], profiles[observation["profile"]] * 4,
                                 observation)
        if all(value["status"] == "assembled" for value in fixture["observations"]):
            test.assertEqual(len({value["pipelineAttempts"] for value in fixture["observations"]}),
                             1, fixture)


def assert_companion_rejections(test: unittest.TestCase, result: dict) -> None:
    validation = result["companions"]["validation"]
    test.assertEqual(set(validation), {"companion-rotation-xyz", "companion-translation"})
    expected = {
        "schemaMissingActiveSampler", "schemaWrongType", "schemaArray", "schemaSlotEight",
        "encoderWrongType", "encoderMissingBinding", "programMissingBinding", "programWrongType",
        "programArray", "programWrongSource", "programTruncatedBytes",
    }
    for name, probe in validation.items():
        with test.subTest(companion=name):
            test.assertEqual(probe["status"], "ready", probe)
            test.assertTrue(probe["baselineProgramAccepted"], probe)
            test.assertEqual(set(probe["rejected"]), expected)
            test.assertEqual([check for check, passed in probe["rejected"].items() if not passed],
                             [], probe)
    fixtures = result["companions"]["fixtures"]
    backend = fixtures["companion-rotation-xyz"]["backend"]
    if backend == "boundedSwift":
        arrays = result["companions"]["boundedArraySourceRejections"]
        test.assertEqual(set(arrays), {"Rotation", "Translation"})
        for suffix, probe in arrays.items():
            with test.subTest(bounded_frontend_array_source=suffix):
                test.assertTrue(probe["frontendRejected"], probe)
                test.assertTrue(probe["unsupportedType"], probe)
    for name in sorted(STATIC_COMPANION_FIXTURES):
        with test.subTest(actual_frontend_static_binding=name):
            probe = fixtures[name]
            test.assertEqual(probe["backend"], backend, probe)
            test.assertTrue(probe["fieldShapeMatches"], probe)
            test.assertTrue(probe["activeSamplerMatches"], probe)
            expected_acceptance = name.startswith("ordinary-")
            test.assertEqual(probe["assembleAccepted"], expected_acceptance, probe)
            test.assertEqual(probe["assembleCompiledAccepted"], expected_acceptance, probe)


class SceneMaterialTextureTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-authored-coordinate-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        support, harness, binary = root / "Support.swift", root / "Harness.swift", root / "probe"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        before = source_hashes([*SWIFT_SOURCES, support, harness])
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            str(support), *map(str, SWIFT_SOURCES), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ]
        environment = fixture_environment(root)
        compilation = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, timeout=180)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], cwd=root, env=environment,
            capture_output=True, text=True, timeout=90)
        after = source_hashes([*SWIFT_SOURCES, support, harness])
        preserve_evidence(root, "bounded", before, after, command, compilation, completed)
        if before != after:
            raise RuntimeError("Compilation inputs changed during the coordinate gate")
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable; no coordinate behavior evidence")

    def test_authored_coordinates_survive_metadata_and_next_generation_on_gpu(self) -> None:
        assert_coordinate_pixels(self, self.result, "boundedSwift")

    def test_reviewed_companion_profiles_reach_the_real_gpu(self) -> None:
        assert_companion_pixels(self, self.result, "boundedSwift")

    def test_companion_shape_binding_and_program_boundaries_fail_closed(self) -> None:
        assert_companion_rejections(self, self.result)


if __name__ == "__main__":
    unittest.main()
