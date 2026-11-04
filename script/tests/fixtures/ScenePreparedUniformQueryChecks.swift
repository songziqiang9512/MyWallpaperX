import Foundation
import simd

// Uses the existing Finalizer fixtures for authored contracts and frame DTOs.
// No Metal device, texture, pipeline, command queue or dispatch is created.
@main
private enum ScenePreparedUniformQueryChecks {
    struct FixtureError: Error { let message: String }

    struct Prepared {
        let cache: SceneResolvedMaterialVariantCache
        let bindings: [SceneResolvedMaterialPreparedUniformBinding]
        let keys: [String]
    }

    static func target(_ key: String) -> SceneDynamicTarget {
        .effectConstant(layerID: 73, effectIndex: 2, passIndex: 5, name: key)
    }

    static func dynamicDeclaration(_ key: String,
        contributor: Template.DynamicUniformSource = .timeline,
        fallback: [Double]? = [0.25, 0.75],
        direct: Bool = false
    ) -> Template.UniformDeclaration {
        let keys = direct ? ["user", "value"] : ["value"]
        let fallback = fallback.map { Template.StaticUniformValue(valueKind: "binding",
            componentBitPatterns: $0.map(\.bitPattern), authoredBindingKeys: keys) }
        return .init(name: key, value: .dynamic(.init(target: target(key),
            valueContributors: [contributor], scriptAttachments: [],
            authoredFallback: fallback, authoredBindingKeys: keys)))
    }

    static func prepare(_ name: String, keys: [String] = ["anchor"],
        type: String = "vec2", defaultValue: String = "1 1", range: String? = nil,
        declarations: [Template.UniformDeclaration] = [], renamed: Bool = false,
        combos: [String: Int] = [:]
    ) throws -> Prepared {
        let fields = keys.indices.map { renamed ? "u_Moved\($0)" : "u_Point\($0)" }
        let uniforms = zip(keys, fields).map { key, field in
            let range = range.map { ",\"range\":\($0)" } ?? ""
            return "uniform \(type) \(field); // {\"material\":\"\(key)\",\"default\":\"\(defaultValue)\"\(range)}"
        }.joined(separator: "\n")
        let expression = renamed && fields.count == 4
            ? "(\(fields[0]) + \(fields[1])) + (\(fields[2]) + \(fields[3]))"
            : fields.joined(separator: " + ")
        let color = type == "vec2" ? "vec4(\(expression), 0.0, 1.0)"
            : "vec4(\(expression), 1.0)"
        let shader = contract(revision: "own-query/\(name)", semanticProbes: false,
            vertexSourceOverride: """
                attribute vec3 a_Position;
                attribute vec2 a_TexCoord;
                varying vec2 v_TexCoord;
                uniform mat4 g_ModelViewProjectionMatrix;
                void main() {
                    v_TexCoord = a_TexCoord;
                    gl_Position = g_ModelViewProjectionMatrix * vec4(a_Position, 1.0);
                }
                """,
            fragmentSourceOverride: """
                varying vec2 v_TexCoord;
                \(uniforms)
                void main() { gl_FragColor = \(color); }
                """)
        let material = template(shader, includePrimaryCandidate: false, comboValues: combos,
            uniformDeclarations: declarations)
        let cache = try SceneResolvedMaterialVariantCache.launchValidated(
            template: material, textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: material), maximumVariantCount: 1).get()
        try cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil).get()
        let variants = cache.launchEnvelopeCapabilitySnapshot().variants
        guard variants.count == 1, let variant = variants.first else {
            throw FixtureError(message: "one prepared variant required")
        }
        let bindings = keys.compactMap { key in
            variant.preparedAssembly.preparedUniformBindings.first {
                variant.activeUniforms[$0.field.name]?.materialKeys.contains(key) == true
            }
        }
        guard bindings.count == keys.count else { throw FixtureError(message: "prepared point missing") }
        return .init(cache: cache, bindings: bindings, keys: keys)
    }

    static func resolution(_ key: String = "anchor", value: SceneDynamicValue = .vector2(0.25, 0.75),
        authored: SceneDynamicValue = .vector2(0.25, 0.75), source: SceneDynamicSource? = .timeline,
        frame: UInt64 = 17, generation: UInt64 = 6, missing: Bool = false
    ) -> SceneDynamicSnapshotResolution {
        let values = source == nil || source == .authored || missing ? [:] : [target(key): value]
        return SceneDynamicSnapshotResolver().resolve(frameIndex: frame, generation: generation,
            definitions: missing ? [] : [.init(target: target(key), valueType: authored.valueType,
                authoredValue: authored)],
            userValues: source == .userProperty ? values : [:],
            timelineValues: source == .timeline ? values : [:],
            sceneScriptValues: source == .sceneScript ? values : [:])
    }

    static func input(_ snapshot: SceneDynamicSnapshot,
        textureFrame: UInt64? = nil
    ) throws -> SceneResolvedMaterialFinalizationInput {
        let texture = SceneFrameTextureRegistrySnapshot(frameEpoch: 1,
            frameIndex: textureFrame ?? snapshot.frameIndex, entries: [:])
        let frame = try SceneResolvedMaterialFrameSnapshot.validated(textureSnapshot: texture,
            dynamicSnapshot: snapshot, frameInputs: frameInputs(frameIndex: snapshot.frameIndex)).get()
        return frame.finalizationInput(layerID: 73,
            renderSize: CGSize(width: 320, height: 180),
            modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4)
    }

    static func finalize(_ prepared: Prepared, _ snapshot: SceneDynamicSnapshot)
        throws -> Result<Program, SceneResolvedMaterialFailure> {
        SceneResolvedMaterialProgramFinalizer.finalize(try input(snapshot),
            variantCache: prepared.cache)
    }

    static func expectedBytes(_ x: Double, _ y: Double) -> Data {
        var pair = SIMD2<Float>(Float(x), Float(y))
        return withUnsafeBytes(of: &pair) { Data($0) }
    }

    static func matches(_ prepared: Prepared, _ snapshot: SceneDynamicSnapshot,
        expected: SIMD2<Double>, resolvedSource: SceneDynamicSource? = nil
    ) throws -> Bool {
        guard let binding = prepared.bindings.first,
              let point = Program.resolvePreparedPoint(binding, snapshot: snapshot),
              case let .success(program) = try finalize(prepared, snapshot),
              let actual = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).first(where: { $0.0 == binding })
        else { return false }
        let queried = try Program.resolvedAuthoredUniform(binding, snapshot: snapshot)
        let bytes = expectedBytes(expected.x, expected.y)
        if let resolvedSource {
            guard actual.1.resolvedSource == resolvedSource else { return false }
        }
        return point == SIMD2(Float(expected.x), Float(expected.y))
            && queried.encodedValue == bytes && actual.1.encodedValue == bytes
            && program.uniformBytes.subdata(in: binding.field.offset ..< binding.field.offset + 8) == bytes
            && queried.resolvedSource == actual.1.resolvedSource
    }

    static func failureMatches(_ prepared: Prepared, _ snapshot: SceneDynamicSnapshot) throws -> Bool {
        guard let binding = prepared.bindings.first,
              Program.resolvePreparedPoint(binding, snapshot: snapshot) == nil,
              case let .failure(actual) = try finalize(prepared, snapshot) else { return false }
        do {
            _ = try Program.resolvedAuthoredUniform(binding, snapshot: snapshot)
            return false
        } catch let queried as SceneResolvedMaterialFailure {
            return queried == actual && queried.phase == .uniform
                && queried.code == .dynamicUniformBindingInvalid
        }
    }

    static func fourPoints() throws -> [String: Bool] {
        let shapes: [[SIMD2<Double>]] = [
            [.init(0,0), .init(1,0), .init(1,1), .init(0,1)],
            [.init(-0.25,-0.35), .init(1.25,-0.35), .init(1.25,1.15), .init(-0.25,1.15)],
            [.init(0.1,-0.3), .init(1.2,0.2), .init(0.9,1.3), .init(-0.2,0.8)],
        ]
        var facts: [String: Bool] = [:]
        for renamed in [false, true] {
            for (index, points) in shapes.enumerated() {
                let keys = (0..<4).map { renamed ? "otherCorner\($0)" : "quad\($0)" }
                let declarations = zip(keys, points).map {
                    staticDeclaration($0.0, components: [$0.1.x, $0.1.y])
                }
                let prepared = try prepare("shape-\(index)-\(renamed)", keys: keys,
                    declarations: declarations, renamed: renamed)
                let snapshot = SceneDynamicSnapshot.empty(frameIndex: 29, generation: 11)
                guard let role = prepared.cache.directDrawPointBindings(materialKeys: keys) else {
                    throw FixtureError(message: "four point prepared role unavailable")
                }
                let program = try finalize(prepared, snapshot).get()
                var exact = role.count == 4 && role == prepared.bindings
                let queries = try role.enumerated().map { offset, binding -> SIMD2<Float> in
                    let queried = try Program.resolvedAuthoredUniform(binding, snapshot: snapshot)
                    let expected = expectedBytes(points[offset].x, points[offset].y)
                    let actual = zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).first { $0.0 == binding }
                    exact = exact && queried.encodedValue == expected && actual?.1.encodedValue == expected
                        && program.uniformBytes.subdata(in: binding.field.offset ..< binding.field.offset + 8) == expected
                        && actual.map { queried.resolvedSource == $0.1.resolvedSource } == true
                    guard let point = Program.resolvePreparedPoint(binding, snapshot: snapshot) else {
                        throw FixtureError(message: "prepared point projection unavailable")
                    }
                    return point
                }
                let geometry = SceneDirectDrawOutputGeometry.resolve(
                    coordinates: .init(p0: queries[0], p1: queries[1], p2: queries[2], p3: queries[3]),
                    canvasSize: SIMD2(320,180), squareUnitModelMatrix: matrix_identity_float4x4,
                    viewProjection: matrix_identity_float4x4, frameIndex: snapshot.frameIndex,
                    generation: snapshot.generation)
                facts["shape\(index)-\(renamed)-real-role-query-program-exact"] = exact
                facts["shape\(index)-\(renamed)-geometry-frame-and-logical-size"] =
                    geometry?.frameIndex == 29 && geometry?.generation == 11
                    && geometry?.vertexInputSize == CGSize(width: 180, height: 180)
                    && geometry?.coordinates.p0 == queries[0] && geometry?.coordinates.p3 == queries[3]
            }
        }
        return facts
    }

    static func dynamicCases() throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        for (label, contributor, source) in [
            ("timeline", Template.DynamicUniformSource.timeline, SceneDynamicSource.timeline),
            ("script", .sceneScript, .sceneScript),
            ("user", .userProperty("ownedSlider"), .userProperty),
        ] {
            let prepared = try prepare(label, declarations: [dynamicDeclaration("anchor", contributor: contributor)])
            facts[label + "-current-source-and-bytes"] = try matches(prepared,
                resolution(source: source).snapshot, expected: SIMD2(0.25,0.75), resolvedSource: source)
            facts[label + "-authored-fallback-source-and-bytes"] = try matches(prepared,
                resolution(source: .authored).snapshot, expected: SIMD2(0.25,0.75), resolvedSource: .authored)
            let first = try finalize(prepared, resolution(source: source).snapshot).get()
            let fallback = try finalize(prepared, resolution(source: .authored).snapshot).get()
            facts[label + "-fallback-source-changes-exact-with-same-bytes"] =
                first.uniformBytes == fallback.uniformBytes && first.semanticIdentity == fallback.semanticIdentity
                && first.exactIdentity != fallback.exactIdentity
            let nextSnapshot = resolution(value: .vector2(0.5,0.125), source: source, frame: 18).snapshot
            let next = try finalize(prepared, nextSnapshot).get()
            let nextMatches = try matches(prepared, nextSnapshot,
                expected: SIMD2(0.5,0.125), resolvedSource: source)
            facts[label + "-new-frame-changes-current-not-semantic-identity"] =
                first.uniformBytes != next.uniformBytes && first.semanticIdentity == next.semanticIdentity
                && first.exactIdentity != next.exactIdentity
                && nextMatches
        }
        let splat = try prepare("splat", range: "[0.01,2]", declarations: [
            dynamicDeclaration("anchor", contributor: .userProperty("isotropic"), fallback: [0], direct: true)])
        facts["direct-scalar-splats-to-two-equal-lanes"] = try matches(splat,
            resolution(value: .scalar(0.6), authored: .scalar(0), source: .userProperty).snapshot,
            expected: SIMD2(repeating: 0.6), resolvedSource: .userProperty)
        facts["range-falls-back-to-authored-zero-sentinel"] = try matches(splat,
            resolution(value: .scalar(-0.5), authored: .scalar(0), source: .userProperty).snapshot,
            expected: .zero, resolvedSource: .userProperty)
        let invalidFallback = try prepare("invalid-fallback-valid-live", declarations: [
            dynamicDeclaration("anchor", contributor: .userProperty("live"), fallback: [1,2,3], direct: true)])
        facts["legal-live-does-not-prevalidate-unused-fallback"] = try matches(invalidFallback,
            resolution(source: .userProperty).snapshot, expected: SIMD2(0.25,0.75), resolvedSource: .userProperty)
        return facts
    }

    static func failureCases() throws -> [String: Bool] {
        let prepared = try prepare("dynamic-negative", declarations: [dynamicDeclaration("anchor")])
        let badABI = resolution(value: .vector3(1,2,3), authored: .vector3(1,2,3)).snapshot
        let huge = resolution(value: .vector2(Double.greatestFiniteMagnitude,0)).snapshot
        let invalidFallback = try prepare("used-invalid-fallback", declarations: [
            dynamicDeclaration("anchor", fallback: [1,2,3])])
        let nan = resolution(value: .vector2(.nan,0))
        let infinity = resolution(value: .vector2(.infinity,0))
        let nanFallback = try matches(prepared, nan.snapshot,
            expected: SIMD2(0.25,0.75), resolvedSource: .authored)
        let infinityFallback = try matches(prepared, infinity.snapshot,
            expected: SIMD2(0.25,0.75), resolvedSource: .authored)
        return [
            "missing-target-same-complete-typed-failure": try failureMatches(prepared,
                resolution(missing: true).snapshot),
            "wrong-source-same-complete-typed-failure": try failureMatches(prepared,
                resolution(source: .userProperty).snapshot),
            "wrong-value-ABI-same-complete-typed-failure": try failureMatches(prepared, badABI),
            "finite-double-float-overflow-same-complete-typed-failure": try failureMatches(prepared, huge),
            "invalid-fallback-rejects-only-when-consumed": try failureMatches(invalidFallback,
                resolution(source: .authored).snapshot),
            "nan-resolver-rejects-before-query-and-keeps-authored": !nan.diagnostics.isEmpty
                && nanFallback,
            "infinity-resolver-rejects-before-query-and-keeps-authored": !infinity.diagnostics.isEmpty
                && infinityFallback,
        ]
    }

    static func neighbors() throws -> [String: Bool] {
        let vector3 = try prepare("valid-vector3", type: "vec3", defaultValue: "0.2 0.4 0.6")
        let snapshot = SceneDynamicSnapshot.empty(frameIndex: 44, generation: 3)
        let binding = vector3.bindings[0]
        let queried = try Program.resolvedAuthoredUniform(binding, snapshot: snapshot)
        let program = try finalize(vector3, snapshot).get()
        var expected = SIMD4<Float>(0.2,0.4,0.6,0)
        let expectedVector3 = withUnsafeBytes(of: &expected) { Data($0) }
        var mismatch: SceneResolvedMaterialFailure?
        do { _ = try input(snapshot, textureFrame: 43) }
        catch let failure as SceneResolvedMaterialFailure { mismatch = failure }
        var facts = [
            "non-float2-keeps-valid-shader-uniform-but-is-not-geometry":
                Program.resolvePreparedPoint(binding, snapshot: snapshot) == nil
                && queried.encodedValue.count == 16
                && queried.encodedValue == expectedVector3
                && zip(program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms).contains {
                    $0.0 == binding && $0.1.encodedValue == queried.encodedValue },
            "frame-mismatch-remains-original-pre-finalization-failure": mismatch?.phase == .invariant
                && mismatch?.code == .frameSnapshotMismatch,
            "no-texture-resource-or-finalizer-slot-created": program.textureSlots.allSatisfy { $0 == nil },
        ]
        for (name, combos) in [("absent", [:]), ("zero", ["DIRECTDRAW": 0]),
                               ("one", ["DIRECTDRAW": 1]), ("unrelated", ["OWN_VARIANT": 7])] {
            let independent = try prepare("source-free-\(name)", combos: combos)
            let linked = try finalize(independent, snapshot).get()
            facts["source-free-\(name)-uses-prepared-program-without-license"] =
                independent.cache.supportsTransparentDirectDraw
                && linked.frontendProgram.textureBindings.isEmpty
                && linked.textureSlots.allSatisfy { $0 == nil }
        }
        let independentTemplate = vector3.cache.launchEnvelopeCapabilitySnapshot().template
        let unprepared = try SceneResolvedMaterialVariantCache.launchValidated(
            template: independentTemplate,
            textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: independentTemplate),
            maximumVariantCount: 1).get()
        facts["source-free-unprepared-cache-is-not-executable"] = !unprepared.supportsTransparentDirectDraw
        for slot in [0, 3] {
            for (renamed, materialKey) in [(false, "albedo"), (true, "albedo"), (true, "otherPigment")] {
                let sampler = "g_Texture\(slot)"
                let authoredSampler = renamed ? "u_MovedSource" : sampler
                let path = SceneVFSAssetPath(renamed ? "textures/other/source.tex" : "textures/owned/source.tex")!
                let reference = Template.TextureReference.asset(path)
                let identity = SceneAssetTextureIdentity(path: path, purpose: .straightAlbedo)
                let shader = contract(revision: "source-free-asset-\(slot)-\(renamed)", semanticProbes: false,
                    vertexSourceOverride: """
                        attribute vec3 a_Position;
                        attribute vec2 a_TexCoord;
                        varying vec2 \(renamed ? "otherUV" : "v_TexCoord");
                        void main() {
                            \(renamed ? "otherUV" : "v_TexCoord") = a_TexCoord;
                            gl_Position = vec4(a_Position, 1.0);
                        }
                        """,
                    fragmentSourceOverride: """
                        \(renamed ? "#define \(authoredSampler) \(sampler)" : "")
                        uniform sampler2D \(sampler); // {"material":"\(materialKey)"}
                        varying vec2 \(renamed ? "otherUV" : "v_TexCoord");
                        void main() {
                            gl_FragColor = texSample2D(\(authoredSampler), \(renamed ? "otherUV" : "v_TexCoord"));
                        }
                        """)
                let material = template(shader, slot: slot, primaryReference: reference,
                    graphBindingsOverride: [])
                let cache = try SceneResolvedMaterialVariantCache.launchValidated(template: material,
                    textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: material),
                    maximumVariantCount: 1).get()
                try cache.precompileLaunchEnvelope(implicitFramebufferIdentity: nil,
                    assetStates: [identity: .ready(.color(.resolved(.straightAlpha)))]).get()
                let variants = cache.launchEnvelopeCapabilitySnapshot().variants
                guard variants.count == 1, let variant = variants.first else {
                    throw FixtureError(message: "one source-free asset variant required")
                }
                let frame = try input(snapshot)
                let selection = try SceneResolvedMaterialTextureSelection.resolve(frame,
                    textureSlots: material.textureSlots, samplers: variant.activeSamplers,
                    reachableTexturePurposes: [:], channelUses: variant.preparedAssembly.samplerChannelUses,
                    allowPresenceIndependentDefaults: true, restrictToSamplerSlots: true,
                    textureSelectionFacts: variant.textureSelectionFacts,
                    graphInputSourceSlotFacts: variant.graphInputSourceSlotFacts)
                if materialKey == "otherPigment" {
                    let prefix = "untyped-whole-vector-slot\(slot)"
                    if case let .reference(actual, purpose, provenance, graphFact) = selection[slot] {
                        facts[prefix + "-retains-asset-without-inventing-color-role"] = actual == reference
                            && purpose == nil && provenance == .authored(.explicitBinding) && graphFact == nil
                            && variant.activeSamplers[slot]?.materialKey == materialKey
                            && variant.activeSamplers[slot]?.channelUse == .wholeVector
                            && variant.activeSamplers[slot]?.sourceProvenPurpose == nil
                    } else { facts[prefix + "-retains-asset-without-inventing-color-role"] = false }
                    if case let .failure(failure) = SceneResolvedMaterialProgramFinalizer.finalize(frame, variantCache: cache) {
                        facts[prefix + "-purpose-unproven-is-not-transparent-default"] =
                            failure.phase == .texture && failure.code == .texturePurposeUnproven
                            && failure.slot == slot && failure.effectLocalVisualFallback == nil
                    } else { facts[prefix + "-purpose-unproven-is-not-transparent-default"] = false }
                    continue
                }
                let prefix = "source-free-asset-slot\(slot)-\(renamed)"
                facts[prefix + "-prepared-active-binding"] = cache.supportsTransparentDirectDraw
                    && variant.frontendProgram.textureBindings.map(\.slot) == [slot]
                    && variant.frontendProgram.textureBindings.map(\.name) == [sampler]
                    && variant.activeSamplers[slot]?.materialKey == materialKey
                    && variant.graphInputSourceSlotFacts.isEmpty
                if case let .reference(actual, purpose, provenance, graphFact) = selection[slot] {
                    facts[prefix + "-actual-selection-keeps-authored-asset"] = actual == reference
                        && purpose == .straightAlbedo && provenance == .authored(.explicitBinding)
                        && graphFact == nil
                } else { facts[prefix + "-actual-selection-keeps-authored-asset"] = false }
                // Launch content is not a concrete frame publication. This
                // device-free gate must still fail at the actual resource read.
                if case let .failure(failure) = SceneResolvedMaterialProgramFinalizer.finalize(frame, variantCache: cache) {
                    facts[prefix + "-missing-frame-resource-is-not-transparent-default"] =
                        failure.phase == .texture && failure.code == .resourceSnapshotUnresolved && failure.slot == slot
                } else { facts[prefix + "-missing-frame-resource-is-not-transparent-default"] = false }
                if !renamed {
                    let graphMaterial = template(shader, slot: slot, graphBindingsOverride: [])
                    let graphCache = try SceneResolvedMaterialVariantCache.launchValidated(template: graphMaterial,
                        textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: graphMaterial),
                        maximumVariantCount: 1).get()
                    try graphCache.precompileLaunchEnvelope(implicitFramebufferIdentity: graphTexture()).get()
                    facts["explicit-graph-candidate-slot\(slot)-still-needs-source"] =
                        !graphCache.supportsTransparentDirectDraw
                        && graphCache.launchEnvelopeCapabilitySnapshot().variants.first?
                            .frontendProgram.textureBindings.map(\.slot) == [slot]
                }
            }
        }
        let implicitShader = contract(revision: "source-free-implicit-negative", semanticProbes: false)
        let implicitMaterial = template(implicitShader, includePrimaryCandidate: false)
        let implicitCache = try SceneResolvedMaterialVariantCache.launchValidated(template: implicitMaterial,
            textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: implicitMaterial),
            maximumVariantCount: 1).get()
        try implicitCache.precompileLaunchEnvelope(implicitFramebufferIdentity: graphTexture()).get()
        facts["implicit-slot0-still-needs-source"] = !implicitCache.supportsTransparentDirectDraw
            && implicitCache.launchEnvelopeCapabilitySnapshot().variants.first?
                .graphInputSourceSlotFacts[0]?.inputIdentity == graphTexture()
        for slot in [0, 3] {
            for combo in [0, 1] {
                let shader = contract(revision: "graph-input-\(slot)-\(combo)", semanticProbes: false,
                    vertexSourceOverride: """
                        attribute vec3 a_Position;
                        attribute vec2 a_TexCoord;
                        varying vec2 v_TexCoord;
                        void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
                        """,
                    fragmentSourceOverride: """
                        uniform sampler2D g_Texture\(slot); // {"material":"framebuffer"}
                        varying vec2 v_TexCoord;
                        void main() { gl_FragColor = texSample2D(g_Texture\(slot), v_TexCoord); }
                        """)
                let input = template(shader, slot: slot, graphBindingsOverride: slot == 0 ? nil : [],
                    comboValues: ["DIRECTDRAW": combo])
                let dependent = try SceneResolvedMaterialVariantCache.launchValidated(template: input,
                    textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: input),
                    maximumVariantCount: 1).get()
                try dependent.precompileLaunchEnvelope(implicitFramebufferIdentity: graphTexture()).get()
                let variants = dependent.launchEnvelopeCapabilitySnapshot().variants
                facts["graph-input-slot\(slot)-combo\(combo)-remains-source-dependent"] =
                    !dependent.supportsTransparentDirectDraw && variants.count == 1
                    && variants[0].frontendProgram.textureBindings.map(\.slot) == [slot]
                    && variants[0].graphInputSourceSlotFacts[slot]?.inputIdentity == graphTexture()
            }
        }
        return facts
    }

    static func main() throws {
        let result = ["fourPoints": try fourPoints(), "dynamic": try dynamicCases(),
            "failures": try failureCases(), "neighbors": try neighbors()]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
