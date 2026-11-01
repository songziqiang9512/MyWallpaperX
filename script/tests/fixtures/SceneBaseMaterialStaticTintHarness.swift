import Foundation
import simd

private typealias Value = SceneDocument.ShaderValue
private typealias Descriptor = SceneRenderDescriptor

@main private enum Harness {
    static let vertex = """
    uniform mat4 g_ModelViewProjectionMatrix;
    uniform float g_Time;
    uniform float slideX; // {"material":"slide-x","default":0}
    uniform float slideY; // {"material":"slide-y","default":0}
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 sampleUV;
    void main() {
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        vec2 shift = vec2(slideX, slideY);
        shift = sign(shift) * pow(vec2(slideX, slideY), CAST2(2.0));
        sampleUV = a_TexCoord + g_Time * shift;
    }
    """
    static let fragment = """
    uniform sampler2D g_Texture0;
    uniform float gain; // {"material":"gain-key","default":1,"range":[0,2]}
    uniform float opacity; // {"material":"opacity-key","default":1}
    uniform float exponent; // {"material":"power-key","default":1,"range":[0,6]}
    uniform vec3 surfaceColor; // {"material":"surface-key","default":"1 1 1"}
    varying vec2 sampleUV;
    void main() {
        vec4 colorCarrier = texSample2D(g_Texture0, sampleUV.xy);
        colorCarrier.rgb *= gain * surfaceColor;
        colorCarrier.a *= opacity;
        colorCarrier.rgb = pow(colorCarrier.rgb, CAST3(exponent));
        gl_FragColor = colorCarrier;
    }
    """

    static func contract(vertex: String = vertex, fragment: String = fragment,
        identity: String = "unseen/tint") -> SceneShaderContract {
        func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderContract.Stage {
            let path = "shaders/" + identity + "." + (kind == .vertex ? "vert" : "frag")
            let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
            return .init(kind: kind, relativePath: path, source: source,
                rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
                includes: parsed.includes, annotations: parsed.annotations,
                declarations: parsed.declarations)
        }
        let stages = [stage(.vertex, vertex), stage(.fragment, fragment)]
        let digest = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
        return .init(identity: identity, sourceKind: .authoredSource, stages: stages,
            diagnostics: [], canonicalSHA256: digest, sourceGraph: .init(
                roots: stages.map { .init(label: $0.kind.rawValue, virtualPath: $0.relativePath) },
                nodes: stages.map { .init(virtualPath: $0.relativePath, provenance: .package,
                    source: $0.source, rawSHA256: $0.rawSHA256, byteCount: $0.source.utf8.count) },
                edges: [], diagnostics: [], dependencySHA256: digest))
    }

    static func descriptor(_ color: Value) -> Descriptor {
        var result = Descriptor()
        result.materialPasses[0].constantShaderValues = ["surface-key": color]
        return result
    }

    static func output(_ descriptor: Descriptor,
        dynamic: Set<String> = [], shader: SceneShaderContract? = nil,
        consumers: Set<Int> = [57, 58]) -> [String: Any] {
        let bindings = SceneBaseMaterialColorModulationCompiler.compile(
            descriptor: descriptor, shaderContracts: [shader ?? contract()],
            dynamicImageModelPaths: dynamic, admittedLayerColorConsumerIDs: consumers)
        guard let first = bindings.first else { return ["count": 0] }
        return ["count": bindings.count, "model": first.modelPath, "context": first.sourceLayerID,
            "canLower": first.canLowerToCompositor,
            "material": first.materialPath, "key": first.colorKey,
            "color": [first.authoredColor.x, first.authoredColor.y, first.authoredColor.z],
            "alpha": first.authoredAlpha, "alphaKey": first.alphaKey ?? "",
            "colorUserKey": first.colorUserPropertyKey ?? "",
            "colorTargetMatches": first.colorPropertyTarget == .materialConstant(
                layerID: first.sourceLayerID, passIndex: 0,
                name: first.colorKey, materialPath: first.materialPath),
            "alphaUserKey": first.alphaUserPropertyKey ?? "",
            "alphaIsDynamic": first.alphaPropertyTarget != nil,
            "alphaTargetMatches": first.alphaPropertyTarget == first.alphaKey.map {
                SceneDynamicTarget.materialConstant(layerID: first.sourceLayerID,
                    passIndex: 0, name: $0, materialPath: first.materialPath)
            },
            "hasScript": first.scriptSource != nil, "properties": first.scriptProperties.count]
    }

    static func dynamicScalarCases() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for renamed in [false, true] {
            let gainKey = renamed ? "luma-control" : "gain-key"
            let powerKey = renamed ? "curve-control" : "power-key"
            let gainUser = renamed ? "renamed_gain" : "brightness_gain"
            let powerUser = renamed ? "renamed_curve" : "response_power"
            let model = renamed ? "models/independent/scalar.json" : "models/unseen/tint.json"
            let material = renamed ? "materials/independent/scalar.json" : "materials/unseen/tint.json"
            let shaderName = renamed ? "independent/scalar" : "unseen/tint"
            var fragment = self.fragment
            if renamed {
                for (old, new) in [("gain-key", gainKey), ("power-key", powerKey),
                    ("gain", "lumaScale"), ("exponent", "curveExponent"),
                    ("surfaceColor", "paletteRGB"), ("colorCarrier", "sampleColor")] {
                    fragment = fragment.replacingOccurrences(of: old, with: new)
                }
                fragment = fragment.replacingOccurrences(of: "sampleUV.xy)", with: "sampleUV)")
                    .replacingOccurrences(of: "CAST3(curveExponent)", with: "vec3(curveExponent)")
            }
            let shader = contract(fragment: fragment, identity: shaderName)
            func user(_ key: String, _ seed: Double = 1) -> Value {
                var value = Value(rawValue: String(seed), components: [seed])
                value.userBinding = key; value.userValueKind = .string
                value.bindingKeys = ["user", "value"]
                return value
            }
            func descriptor(_ constants: [String: Value]) -> Descriptor {
                var value = self.descriptor(.init(rawValue: "0.2 0.4 0.6", components: [0.2,0.4,0.6]))
                value.layers[0].imagePath = model
                value.modelMaterialLinks = [.init(modelPath: model, materialPath: material)]
                value.materialPasses[0].materialPath = material
                value.materialPasses[0].shaderPath = shaderName
                value.materialPasses[0].constantShaderValues.merge(constants) { _, new in new }
                return value
            }
            for mode in ["brightness", "power", "both", "nonneutral", "mixed"] {
                var constants: [String: Value] = [:]
                var expected: [String: String] = [:]
                if mode != "power" { constants[gainKey] = user(gainUser, mode == "nonneutral" ? 1.5 : 1); expected[gainKey] = gainUser }
                if mode != "brightness" { constants[powerKey] = user(powerUser, mode == "nonneutral" ? 0.5 : 1); expected[powerKey] = powerUser }
                if mode == "mixed" {
                    var color = Value(rawValue: "0.2 0.4 0.6", components: [0.2,0.4,0.6])
                    color.userBinding = "palette"; color.userValueKind = .string
                    color.scriptSource = "export function update(value) { return value; }"
                    color.bindingKeys = ["script", "user", "value"]
                    constants["surface-key"] = color; constants["opacity-key"] = user("opacity")
                }
                let value = descriptor(constants)
                let facts = SceneBaseMaterialColorModulationCompiler.compile(descriptor: value,
                    shaderContracts: [shader], dynamicImageModelPaths: [model], admittedLayerColorConsumerIDs: [57])
                var row: [String: Any] = ["variant": renamed ? "renamed" : "original", "mode": mode,
                    "count": facts.count, "expected": expected]
                if let fact = facts.first {
                    // Read output metadata across the frozen pre-feature baseline too.
                    let keys = Mirror(reflecting: fact).children.first { $0.label == "scalarUserPropertyKeys" }?.value as? [String: String] ?? [:]
                    row["keys"] = keys; row["canLower"] = fact.canLowerToCompositor
                    row["model"] = fact.modelPath; row["material"] = fact.materialPath
                    row["hasScript"] = fact.scriptSource != nil
                    row["alphaUser"] = fact.alphaUserPropertyKey ?? ""
                    if let property = keys[powerKey], let authored = constants[powerKey],
                       case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
                        contract: shader, compatibilityTarget: .windowsDX11ShaderModel4,
                        combos: [:], textureReadiness: [0: true]),
                       let schema = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                        named: renamed ? "curveExponent" : "exponent", type: .float, stage: .fragment, prepared: prepared) {
                        let target = SceneDynamicTarget.materialConstant(layerID: fact.sourceLayerID,
                            passIndex: 0, name: powerKey, materialPath: fact.materialPath)
                        let fallback = SceneResolvedMaterialTemplate.StaticUniformValue(valueKind: "binding",
                            componentBitPatterns: authored.components!.map(\.bitPattern), authoredBindingKeys: ["user", "value"])
                        let declaration = SceneResolvedMaterialTemplate.DynamicUniform(target: target,
                            valueContributors: [.userProperty(property)], scriptAttachments: [],
                            authoredFallback: fallback, authoredBindingKeys: ["user", "value"])
                        let field = SceneAuthoredShaderUniformLayout.Field(name: schema.name, stage: .fragment, type: .float, offset: 0)
                        let binding = SceneResolvedMaterialPreparedUniformBinding(field: field, source: .dynamic(.init(
                            declaration: declaration, contributor: .userProperty(property), fallback: fallback, schema: schema)))
                        var encoded: [Double] = []
                        for scalar in [0.5, 2.0, 8.0] {
                            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                                definitions: [.init(target: target, valueType: .scalar,
                                    authoredValue: .scalar(authored.components![0]), userPropertyNumericRange: 0 ... 10)],
                                userValues: [target: .scalar(scalar)]).snapshot
                            if let resolved = try? SceneResolvedMaterialProgram.resolvedAuthoredUniform(binding, snapshot: snapshot),
                               resolved.field.stage == .fragment, resolved.encodedValue.count == 4 {
                                encoded.append(Double(resolved.encodedValue.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }))
                            }
                        }
                        row["fragmentFloatBytes"] = encoded
                        row["schemaRange"] = schema.authoredRange.map { [$0.lowerBound, $0.upperBound] } ?? []
                    }
                }
                rows.append(row)
            }
            for key in [gainKey, powerKey] {
                for invalid in ["script", "timeline", "scroll", "alias", "host", "empty-user", "wrong-user-kind", "extra-key", "vector", "malformed"] {
                    var scalar = user(key == gainKey ? gainUser : powerUser)
                    switch invalid {
                    case "script": scalar.scriptSource = "export function update(value){return value;}"; scalar.bindingKeys.append("script")
                    case "timeline": scalar.timeline = true
                    case "empty-user": scalar.userBinding = ""
                    case "wrong-user-kind": scalar.userValueKind = .null
                    case "extra-key": scalar.bindingKeys.append("extra")
                    case "vector": scalar.rawValue = "1 1"; scalar.components = [1,1]
                    case "malformed": scalar.rawValue = "1 junk"
                    default: break
                    }
                    var constants = [key: scalar]
                    var testShader = shader
                    if invalid == "scroll" { constants = ["slide-x": scalar] }
                    if invalid == "alias" { constants[key == gainKey ? (renamed ? "lumaScale" : "gain") : (renamed ? "curveExponent" : "exponent")] = scalar }
                    if invalid == "host" {
                        let symbol = key == gainKey ? (renamed ? "lumaScale" : "gain") : (renamed ? "curveExponent" : "exponent")
                        let host = fragment.replacingOccurrences(of: "uniform float \(symbol);", with: "uniform float g_Time;")
                            .replacingOccurrences(of: "*= \(symbol) *", with: "*= g_Time *")
                            .replacingOccurrences(of: "CAST3(\(symbol))", with: "CAST3(g_Time)")
                            .replacingOccurrences(of: "vec3(\(symbol))", with: "vec3(g_Time)")
                        testShader = contract(fragment: host, identity: shaderName)
                    }
                    let result = output(descriptor(constants), dynamic: [model], shader: testShader)
                    rows.append(["variant": renamed ? "renamed" : "original", "mode": "reject-\(key)-\(invalid)", "count": result["count"]!])
                }
            }
            let multi = fragment.replacingOccurrences(of: "uniform sampler2D g_Texture0;", with: "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;")
                .replacingOccurrences(of: "gl_FragColor =", with: "\(renamed ? "sampleColor" : "colorCarrier") *= texSample2D(g_Texture1, sampleUV); gl_FragColor =")
            rows.append(["variant": renamed ? "renamed" : "original", "mode": "reject-multi", "count": output(
                descriptor([powerKey: user(powerUser)]), dynamic: [model], shader: contract(fragment: multi, identity: shaderName))["count"]!])
        }
        return rows
    }

    static func scalarOwner(_ shader: SceneShaderContract, symbol: String,
        stage: SceneShaderContract.StageKind,
        declarations: [SceneResolvedMaterialTemplate.UniformDeclaration]) -> [String: Any] {
        typealias Template = SceneResolvedMaterialTemplate
        guard case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader, compatibilityTarget: .windowsDX11ShaderModel4,
            combos: [:], textureReadiness: [0: true]),
            let scalar = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                named: symbol, type: .float, stage: stage, prepared: prepared) else {
            return ["owner": "schema-rejected"]
        }
        let fields: [SceneAuthoredShaderUniformLayout.Field] = [
            .init(name: scalar.name, authoredName: symbol, stage: stage, type: .float, offset: 0),
            .init(name: "g_ModelViewProjectionMatrix", stage: .vertex, type: .float4x4, offset: 16),
        ]
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [
            .init(reference: .asset(.init("fixtures/host-default/source")!), provenance: .material),
        ])
        // Template and reflected fields are leaf DTOs; ownership comes only
        // from the real schema and Finalizer, never a fixture-created host binding.
        let template = Template.validated(textureSlots: slots, combos: [],
            uniformDeclarations: declarations,
            renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull", alphaWriting: "enabled")!,
            graphRole: .init(effectInput: .layerSource, effectOutput: .effectOutput,
                nodeTarget: .effectOutput, bindings: []),
            compatibilityTarget: .windowsDX11ShaderModel4, shaderContract: shader,
            diagnosticProvenance: .init(nodeIndex: 0, authoredShaderPath: shader.identity,
                contractIdentity: shader.identity, contractCanonicalSHA256: shader.canonicalSHA256,
                textureSources: [], uniformSources: []))!
        var row: [String: Any] = ["schemaKeys": scalar.materialKeys,
            "default": scalar.defaultValue?.componentBitPatterns.map { Double(bitPattern: $0) } ?? [],
            "declarationCount": template.uniformDeclarations.count]
        do {
            let schemas = try SceneResolvedMaterialShaderSchema.activeUniforms(fields, prepared: prepared)
            let bindings = try SceneResolvedMaterialProgramFinalizer.prepareUniformBindings(
                template: template, fields: fields, activeUniforms: schemas,
                activeTextureSlots: [0], neutralTextureResolution: nil)
            if case .host(.modelViewProjection) = bindings[1].source { row["mvpOwner"] = "host.modelViewProjection" }
            switch bindings[0].source {
            case let .host(host):
                row["owner"] = "host.\(host)"
                var encoded: [Double] = []
                for (index, time) in [Float(0.25), 0.75].enumerated() {
                    let inputs = SceneAuthoredShaderUniformInputs(frameIndex: UInt64(index + 1),
                        renderSize: .init(width: 64, height: 32), screenSize: .init(width: 64, height: 32),
                        modelViewProjection: matrix_identity_float4x4, layerModelMatrix: matrix_identity_float4x4,
                        effectOutputModelViewProjection: matrix_identity_float4x4,
                        effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
                        sceneTime: time, dayTime: 0.5, frameTime: time / 2,
                        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero)
                    if case let .encoded(bytes) = SceneResolvedMaterialUniformEncoder.resolveHost(
                        host, type: bindings[0].field.type, inputs: inputs, slots: []), bytes.count == 4 {
                        encoded.append(Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }))
                    }
                }
                row["floatBytes"] = encoded
            case let .staticValue(bytes):
                row["owner"] = "static"
                row["floatBytes"] = [Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })]
            default: row["owner"] = "other"
            }
        } catch let failure as SceneResolvedMaterialFailure {
            row["owner"] = "\(failure.phase.rawValue)/\(failure.code.rawValue)"
        } catch { row["owner"] = "unexpected-error" }
        return row
    }

    static func scalarHostDefaultCases() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let roles: [(String, String, String, SceneShaderContract.StageKind, Double)] = [
            ("brightness", "gain", "gain-key", .fragment, 1),
            ("power", "exponent", "power-key", .fragment, 1),
            ("scroll-x", "slideX", "slide-x", .vertex, 0),
            ("scroll-y", "slideY", "slide-y", .vertex, 0),
        ]
        for renamed in [false, true] {
            for (role, originalSymbol, originalAlias, stage, neutral) in roles {
                let modes = (stage == .vertex ? ["host-frame-time", "host-time"] : ["host-time", "host-frame-time"])
                    + ["host-name", "host-alias",
                    "unannotated-host", "author-default", "author-name", "author-host-alias"]
                    + (stage == .fragment ? ["host-name-nonneutral", "host-alias-nonneutral"] : [])
                for mode in modes {
                    let isHost = !mode.hasPrefix("author-")
                    let symbol = isHost ? (mode == "host-frame-time"
                        || (stage == .vertex && mode != "host-time") ? "g_Frametime" : "g_Time")
                        : (renamed ? "renamedScalar" : originalSymbol)
                    let alias = mode == "author-host-alias" ? "g_Daytime"
                        : (renamed ? "renamed-\(role)-parameter" : originalAlias)
                    var vertex = self.vertex
                    var fragment = self.fragment
                    if stage == .vertex && symbol == "g_Time" {
                        // Keep the time multiplier distinct from both scroll
                        // roles, as required by the existing neutral proof.
                        vertex = vertex.replacingOccurrences(of: "g_Time", with: "g_Daytime")
                    }
                    var source = stage == .vertex ? vertex : fragment
                    source = source.replacingOccurrences(of: originalAlias, with: "__fixture_scalar_alias__")
                        .replacingOccurrences(of: originalSymbol, with: symbol)
                        .replacingOccurrences(of: "__fixture_scalar_alias__", with: alias)
                    if mode == "unannotated-host" {
                        let line = source.components(separatedBy: "\n").first {
                            $0.contains("uniform float \(symbol);")
                        }!
                        source = source.replacingOccurrences(of: line, with: "uniform float \(symbol);")
                    }
                    if stage == .vertex { vertex = source } else { fragment = source }
                    if renamed {
                        for (old, new) in [("sampleUV", "imageCoordinates"), ("colorCarrier", "paintSample"),
                            ("surfaceColor", "paletteRGB"), ("shift", "uvMotion")] {
                            vertex = vertex.replacingOccurrences(of: old, with: new)
                            fragment = fragment.replacingOccurrences(of: old, with: new)
                        }
                        fragment = fragment.replacingOccurrences(of: "imageCoordinates.xy)", with: "imageCoordinates)")
                            .replacingOccurrences(of: "CAST3(", with: "vec3(")
                    }
                    var descriptor = self.descriptor(.init(rawValue: "0.2 0.4 0.6", components: [0.2, 0.4, 0.6]))
                    let model = renamed ? "models/independent/host-default.json" : "models/unseen/tint.json"
                    let material = renamed ? "materials/independent/host-default.json" : "materials/unseen/tint.json"
                    let identity = renamed ? "independent/host-default" : "unseen/tint"
                    descriptor.layers[0].imagePath = model
                    descriptor.modelMaterialLinks = [.init(modelPath: model, materialPath: material)]
                    descriptor.materialPasses[0].materialPath = material
                    descriptor.materialPasses[0].shaderPath = identity
                    descriptor.materialPasses[0].textureSlots = [renamed ? "independent/renamed-input" : "unseen/source"]
                    descriptor.materialPasses[0].texturePaths = descriptor.materialPasses[0].textureSlots.compactMap { $0 }
                    var declarations: [SceneResolvedMaterialTemplate.UniformDeclaration] = []
                    let declarationKey: String? = mode.hasPrefix("host-name") || mode == "author-name" ? symbol
                        : (mode.hasPrefix("host-alias") || mode == "author-host-alias" ? alias : nil)
                    if let declarationKey {
                        let scalar = mode.hasSuffix("nonneutral") ? 2 : neutral
                        descriptor.materialPasses[0].constantShaderValues[declarationKey] = .init(
                            rawValue: String(scalar), components: [scalar])
                        declarations = [.init(name: declarationKey, value: .staticExact(.init(valueKind: "number",
                            componentBitPatterns: [scalar.bitPattern], authoredBindingKeys: [])))]
                    }
                    let shader = contract(vertex: vertex, fragment: fragment, identity: identity)
                    var row = output(descriptor, shader: shader)
                    row.merge(scalarOwner(shader, symbol: symbol, stage: stage, declarations: declarations)) { _, new in new }
                    row["variant"] = renamed ? "renamed" : "original"
                    row["role"] = role; row["mode"] = mode
                    row["symbol"] = symbol; row["alias"] = alias; row["neutral"] = neutral
                    rows.append(row)
                }
            }
        }
        return rows
    }

    static func main() throws {
        var results: [String: [String: Any]] = [:]
        let shader = contract()
        if case let .accepted(prepared) = SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader, compatibilityTarget: .windowsDX11ShaderModel4,
            combos: [:], textureReadiness: [0: true]),
           let sampler = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)[0] {
            let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: prepared.vertex.source, fragment: prepared.fragment.source)
            let typed = sampler.withSourceProvenPurpose(.normal)
            let retained = SceneResolvedMaterialShaderSchema.sourceTypedColorSamplers(
                [0: typed], vertexSource: sources.vertex, fragmentSource: sources.fragment)[0]
            results["sharedTintPowerPurpose"] = ["matches": sampler.sourceProvenPurpose == .straightAlbedo
                && sampler.purpose(for: .asset(.init("unseen/source")!)) == .straightAlbedo]
            results["sharedPurposePreservesAlreadyTypedSampler"] = ["matches": retained?.sourceProvenPurpose == .normal]
        } else {
            results["sharedTintPowerPurpose"] = ["matches": false]
            results["sharedPurposePreservesAlreadyTypedSampler"] = ["matches": false]
        }
        let black = Value(rawValue: "0 0 0", components: [0, 0, 0])
        let nonwhite = Value(rawValue: "0.2 0.4 0.6", components: [0.2, 0.4, 0.6])
        let base = descriptor(nonwhite)
        results["staticBlack"] = output(descriptor(black))
        results["staticNonwhite"] = output(base)
        results["staticComma"] = output(descriptor(.init(rawValue: "0.2,\t0.4, 0.6", components: [0.2, 0.4, 0.6])))
        results["directVec2UV"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "sampleUV.xy)", with: "sampleUV)")))
        var script = nonwhite
        script.scriptSource = "export function update(value) { return value; }"
        script.scriptProperties = ["phase": .number(0.25)]
        script.bindingKeys = ["script", "scriptproperties", "value"]
        results["scriptDynamic"] = output(descriptor(script), dynamic: ["models/unseen/tint.json"])
        results["scriptWithoutDynamicResource"] = output(descriptor(script))
        var userColor = nonwhite
        userColor.userBinding = "palette"
        userColor.userValueKind = .string
        userColor.bindingKeys = ["user", "value"]
        results["strictUserColor"] = output(descriptor(userColor))
        var mixedColor = userColor
        mixedColor.scriptSource = "export function update(value) { if (scriptProperties.ifchange) return value.multiply(0.5); }"
        mixedColor.scriptProperties = ["ifchange": .object(["user": .string("animate"), "value": .bool(true)])]
        mixedColor.bindingKeys = ["script", "scriptproperties", "user", "value"]
        results["mixedUserScriptColor"] = output(descriptor(mixedColor), dynamic: ["models/unseen/tint.json"])
        results["mixedUserScriptWithoutDynamicResource"] = output(descriptor(mixedColor))
        for name in ["emptyColorUser", "nullColorUser", "unknownUserColorWrapper", "mixedMissingScriptProperties"] {
            var rejected = name == "mixedMissingScriptProperties" ? mixedColor : userColor
            switch name {
            case "emptyColorUser": rejected.userBinding = ""
            case "nullColorUser": rejected.userValueKind = .null
            case "unknownUserColorWrapper": rejected.bindingKeys.append("extra")
            default: rejected.scriptProperties = nil
            }
            results[name] = output(descriptor(rejected), dynamic: ["models/unseen/tint.json"])
        }
        var aliasedColor = descriptor(userColor)
        aliasedColor.materialPasses[0].constantShaderValues["surfaceColor"] = userColor
        results["multipleColorAliases"] = output(aliasedColor)
        results["normalizedDuplicate"] = output(base, dynamic: ["MODELS\\UNSEEN\\TINT.JSON", "models/unseen/tint.json"])

        var malformed = nonwhite
        malformed.rawValue = "0.2 junk 0.4 0.6"
        results["malformedColor"] = output(descriptor(malformed))
        malformed.rawValue = "0.1 0.4 0.6"
        results["componentMismatch"] = output(descriptor(malformed))
        malformed.rawValue = "0.2 0.4 0.6 1"
        results["extraColorToken"] = output(descriptor(malformed))
        results["nonfiniteColor"] = output(descriptor(.init(rawValue: "nan 0.4 0.6", components: [.nan, 0.4, 0.6])))
        results["outOfRangeColor"] = output(descriptor(.init(rawValue: "2 0.4 0.6", components: [2, 0.4, 0.6])))
        var wrapper = nonwhite
        wrapper.bindingKeys = ["extra", "value"]
        results["unknownWrapper"] = output(descriptor(wrapper))
        wrapper.bindingKeys = ["user", "value"]; wrapper.userValueKind = .string
        results["userColor"] = output(descriptor(wrapper))
        wrapper = script; wrapper.scriptProperties = nil
        results["partialScript"] = output(descriptor(wrapper), dynamic: ["models/unseen/tint.json"])
        wrapper = script; wrapper.bindingKeys = []
        results["scriptStaticConflict"] = output(descriptor(wrapper), dynamic: ["models/unseen/tint.json"])
        wrapper = nonwhite; wrapper.timeline = true
        results["animatedColor"] = output(descriptor(wrapper))

        for (name, key, number) in [
            ("alphaHalf", "opacity-key", 0.5), ("brightnessTwo", "gain-key", 2.0),
            ("powerHalf", "power-key", 0.5), ("powerPoint99", "power-key", 0.99),
            ("scrollNonzero", "slide-x", 0.5),
        ] {
            var value = base
            value.materialPasses[0].constantShaderValues[key] = .init(rawValue: String(number), components: [number])
            results[name] = output(value)
        }
        for (name, key, number) in [
            ("malformedAlpha", "opacity-key", 1.0), ("malformedPower", "power-key", 1.0),
            ("malformedScroll", "slide-x", 0.0),
        ] {
            var value = base
            value.materialPasses[0].constantShaderValues[key] = .init(rawValue: "\(number) junk", components: [number])
            results[name] = output(value)
        }
        var value = base
        var userAlpha = Value(rawValue: "1", components: [1])
        userAlpha.bindingKeys = ["user", "value"]; userAlpha.userValueKind = .string
        value.materialPasses[0].constantShaderValues["opacity-key"] = userAlpha
        results["userAlpha"] = output(value)
        userAlpha.userBinding = "liveOpacity"
        value.materialPasses[0].constantShaderValues["opacity-key"] = userAlpha
        results["strictUserAlpha"] = output(value)
        var mixedMaterial = descriptor(mixedColor)
        mixedMaterial.materialPasses[0].constantShaderValues["opacity-key"] = userAlpha
        results["mixedColorAndUserAlpha"] = output(mixedMaterial, dynamic: ["models/unseen/tint.json"])
        mixedMaterial.materialPasses[0].constantShaderValues["power-key"] = .init(
            rawValue: "0.99", components: [0.99])
        results["fullProgramMixedColorAndUserAlpha"] = output(mixedMaterial,
            dynamic: ["models/unseen/tint.json"])
        for (name, scalar) in [("overflowingBrightness", 1e100),
                               ("nonfinitePower", Double.nan)] {
            var rejected = base
            let key = name == "overflowingBrightness" ? "gain-key" : "power-key"
            rejected.materialPasses[0].constantShaderValues[key] = .init(
                rawValue: String(scalar), components: [scalar])
            results[name] = output(rejected)
        }
        var unknownBrightness = base
        var wrappedBrightness = Value(rawValue: "2", components: [2])
        wrappedBrightness.bindingKeys = ["extra", "value"]
        unknownBrightness.materialPasses[0].constantShaderValues["gain-key"] = wrappedBrightness
        results["unknownBrightnessWrapper"] = output(unknownBrightness)
        let arbitraryAlpha = fragment.replacingOccurrences(of: "opacity-key", with: "coverage-parameter")
            .replacingOccurrences(of: "opacity", with: "coverageRatio")
        value = base
        value.materialPasses[0].constantShaderValues["coverage-parameter"] = .init(rawValue: "0.3", components: [0.3])
        results["arbitraryStaticAlpha"] = output(value, shader: contract(fragment: arbitraryAlpha))
        value.materialPasses[0].constantShaderValues["coverage-parameter"] = userAlpha
        results["arbitraryUserAlpha"] = output(value, shader: contract(fragment: arbitraryAlpha))
        results["defaultAlphaQuarter"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "\"material\":\"opacity-key\",\"default\":1", with: "\"material\":\"opacity-key\",\"default\":0.25")))
        results["missingAlphaDeclaration"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: " // {\"material\":\"opacity-key\",\"default\":1}", with: "")))
        for (name, scalar) in [("staticAlphaZero", 0.0), ("staticAlphaOne", 1.0),
                               ("negativeAlpha", -0.1), ("oversizedAlpha", 1.1),
                               ("nonfiniteAlpha", Double.nan)] {
            value = base
            value.materialPasses[0].constantShaderValues["opacity-key"] = .init(rawValue: String(scalar), components: [scalar])
            results[name] = output(value)
        }
        value = base
        value.materialPasses[0].constantShaderValues["opacity-key"] = .init(rawValue: "0.5", components: [0.4])
        results["alphaComponentMismatch"] = output(value)
        value.materialPasses[0].constantShaderValues["opacity-key"] = .init(rawValue: "0.5 0.5", components: [0.5])
        results["extraAlphaToken"] = output(value)
        value = base
        value.materialPasses[0].constantShaderValues["opacity-key"] = userAlpha
        value.materialPasses[0].constantShaderValues["opacity"] = userAlpha
        results["multipleAlphaAliases"] = output(value)
        for name in ["unknownAlphaWrapper", "emptyAlphaUser", "nullAlphaUser", "scriptedAlpha", "animatedAlpha"] {
            var invalid = userAlpha
            switch name {
            case "unknownAlphaWrapper": invalid.bindingKeys.append("extra")
            case "emptyAlphaUser": invalid.userBinding = ""
            case "nullAlphaUser": invalid.userValueKind = .null
            case "scriptedAlpha": invalid.scriptSource = "export function update(value) { return value; }"
            default: invalid.timeline = true
            }
            value = base; value.materialPasses[0].constantShaderValues["opacity-key"] = invalid
            results[name] = output(value)
        }
        results["hostAlphaUniform"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "opacity", with: "g_Time")))
        value = base
        value.materialPasses[0].shaderPath = "genericimage"
        value.materialPasses[0].constantShaderValues["opacity-key"] = .init(rawValue: "0.25", components: [0.25])
        value.materialPasses[0].constantShaderValues["Alpha"] = .init(rawValue: "1", components: [1])
        results["authoredStockAliasUsesExactAlphaKey"] = output(value, shader: contract(identity: "genericimage"))
        value = base; value.materialPasses[0].userShaderValues = ["surface-key": "property-key"]
        results["userShaderValue"] = output(value)
        value = base; value.materialPasses[0].constantShaderValues = ["color": nonwhite]
        results["wrongColorKey"] = output(value)

        results["alphaReplacement"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "colorCarrier.a *= opacity;", with: "colorCarrier.a = 1.0;")))
        results["extraSample"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "gl_FragColor = colorCarrier;", with: "colorCarrier += texSample2D(g_Texture0, sampleUV.xy); gl_FragColor = colorCarrier;")))
        results["offsetUV"] = output(base, shader: contract(vertex: vertex.replacingOccurrences(
            of: "g_Time * shift", with: "g_Time * shift + vec2(0.1)")))
        results["fragmentOffsetUV"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "sampleUV.xy)", with: "sampleUV.xy + vec2(0.1))")))
        results["fragmentSwizzledUV"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "sampleUV.xy)", with: "sampleUV.yx)")))
        results["fragmentUnlinkedVarying"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "sampleUV", with: "otherUV")))
        results["fragmentConstantUV"] = output(base, shader: contract(fragment: fragment.replacingOccurrences(
            of: "sampleUV.xy)", with: "vec2(0.5))")))
        results["customPositionAttribute"] = output(base, shader: contract(vertex: vertex.replacingOccurrences(
            of: "a_Position", with: "positionInput")))
        results["customUVAttribute"] = output(base, shader: contract(vertex: vertex.replacingOccurrences(
            of: "a_TexCoord", with: "uvInput")))
        results["customPositionMatrix"] = output(base, shader: contract(vertex: vertex.replacingOccurrences(
            of: "g_ModelViewProjectionMatrix", with: "g_CustomMatrix")))
        value = base
        let matrix = "1 0 0 0 0 1 0 0 0 0 1 0 0.25 0 0 1"
        value.materialPasses[0].constantShaderValues["g_ModelViewProjectionMatrix"] = .init(
            rawValue: matrix, components: matrix.split(separator: " ").map { Double($0)! })
        results["explicitMVPOverride"] = output(value)
        let seededVertex = vertex.replacingOccurrences(of: "uniform mat4 g_ModelViewProjectionMatrix;",
            with: "uniform mat4 g_ModelViewProjectionMatrix; // {\"default\":\"\(matrix)\"}")
        results["defaultMVPSeed"] = output(base, shader: contract(vertex: seededVertex))
        for (name, annotation) in [
            ("invalidSamplerMode", #"{"mode":"not-a-mode"}"#),
            ("invalidDepthFormat", #"{"mode":"depth","format":"rgba8"}"#),
            ("depthSampler", #"{"mode":"depth","format":"r8"}"#),
            ("rgbMaskSampler", #"{"mode":"rgbmask"}"#),
            ("normalMapFormat", #"{"format":"normalmap"}"#),
            ("stockNoiseDefault", #"{"default":"util/noise"}"#),
        ] {
            let annotated = fragment.replacingOccurrences(of: "uniform sampler2D g_Texture0;",
                with: "uniform sampler2D g_Texture0; // \(annotation)")
            results[name] = output(base, shader: contract(fragment: annotated))
        }
        for (name, path) in [
            ("stockNormalAsset", "effects/waterripplenormal"),
            ("stockNoiseAsset", "util/noise"),
        ] {
            value = base
            value.materialPasses[0].textureSlots = [path]
            value.materialPasses[0].texturePaths = [path]
            results[name] = output(value)
        }
        let sharedScroll = vertex.replacingOccurrences(
            of: "uniform float slideY; // {\"material\":\"slide-y\",\"default\":0}\n", with: ""
        ).replacingOccurrences(of: "slideY", with: "slideX")
        results["sharedScrollUniform"] = output(base, shader: contract(vertex: sharedScroll))
        let sharedScalars = fragment.replacingOccurrences(
            of: "uniform float opacity; // {\"material\":\"opacity-key\",\"default\":1}\n", with: ""
        ).replacingOccurrences(
            of: "uniform float exponent; // {\"material\":\"power-key\",\"default\":1,\"range\":[0,6]}\n", with: ""
        ).replacingOccurrences(of: "opacity", with: "gain")
            .replacingOccurrences(of: "exponent", with: "gain")
        results["sharedFragmentScalarUniform"] = output(base, shader: contract(fragment: sharedScalars))
        value = base; value.layers[0].visible = false; results["hidden"] = output(value)
        value = base; value.layers[0].usesPerspective = true; results["perspective"] = output(value)
        let perspective = value
        results["perspectiveScriptDynamic"] = output({
            var candidate = descriptor(script)
            candidate.layers[0].usesPerspective = true
            return candidate
        }(), dynamic: ["models/unseen/tint.json"])
        for (name, key, number) in [
            ("perspectiveBrightnessTwo", "gain-key", 2.0),
            ("perspectivePowerHalf", "power-key", 0.5),
        ] {
            value = perspective
            value.materialPasses[0].constantShaderValues[key] = .init(
                rawValue: String(number), components: [number])
            results[name] = output(value)
        }
        value = perspective; value.layers[0].effects = [1]
        results["perspectiveEffects"] = output(value)
        value = perspective; value.materialPasses[0].depthTest = "enabled"
        results["perspectiveDepthTest"] = output(value)
        value = perspective; value.materialPasses[0].depthWrite = "enabled"
        results["perspectiveDepthWrite"] = output(value)
        results["perspectiveCustomMVP"] = output(perspective,
            shader: contract(vertex: vertex.replacingOccurrences(
                of: "g_ModelViewProjectionMatrix", with: "g_UnprovenMatrix")))
        results["perspectiveOffsetUV"] = output(perspective,
            shader: contract(fragment: fragment.replacingOccurrences(
                of: "sampleUV.xy)", with: "sampleUV.xy + vec2(0.1))")))

        var renamedVertex = vertex
        var renamedFragment = fragment
        for (old, fresh) in [("slideX", "driftU"), ("slideY", "driftV"),
                             ("shift", "neutralDrift"), ("sampleUV", "paintUV"),
                             ("gain", "radianceWeight"), ("opacity", "coverageRatio"),
                             ("exponent", "gammaPower"), ("surfaceColor", "inkTint"),
                             ("colorCarrier", "sampleColor")] {
            renamedVertex = renamedVertex.replacingOccurrences(of: old, with: fresh)
            renamedFragment = renamedFragment.replacingOccurrences(of: old, with: fresh)
        }
        renamedVertex = renamedVertex.replacingOccurrences(of: "1.0)", with: "1e0)")
            .replacingOccurrences(of: "CAST2(2.0)", with: "vec2(2e0)")
        renamedFragment = renamedFragment.replacingOccurrences(of: "paintUV.xy)", with: "paintUV)")
            .replacingOccurrences(of: "CAST3(gammaPower)", with: "vec3(gammaPower)")
            .replacingOccurrences(of: "surface-key", with: "pigment-key")
        value = perspective
        value.layers[0].imagePath = "models/independent/paint.json"
        value.modelMaterialLinks = [.init(modelPath: "models/independent/paint.json",
            materialPath: "materials/independent/paint.json")]
        value.materialPasses[0].materialPath = "materials/independent/paint.json"
        value.materialPasses[0].shaderPath = "independent/paint-source"
        value.materialPasses[0].textureSlots = ["independent/paint-source"]
        value.materialPasses[0].texturePaths = ["independent/paint-source"]
        value.materialPasses[0].constantShaderValues = ["pigment-key": nonwhite]
        results["perspectiveRenamedEquivalent"] = output(value,
            shader: contract(vertex: renamedVertex, fragment: renamedFragment,
                             identity: "independent/paint-source"))

        value = perspective; var mixedSibling = value.layers[0]
        mixedSibling.id = 58; mixedSibling.usesPerspective = false
        value.layers.append(mixedSibling)
        results["mixedPerspectiveConsumers"] = output(value)
        value.layers.reverse()
        results["reversedMixedPerspectiveConsumers"] = output(value)
        results["perspectiveUnadmittedSibling"] = output(value, consumers: [57])
        value = base; value.layers[0].puppetMeshPath = "models/puppet.mdl"; results["puppet"] = output(value)
        value = base; var sibling = value.layers[0]; sibling.id = 58; value.layers.append(sibling)
        results["multipleConsumers"] = output(value)
        value.layers.reverse()
        results["reversedConsumers"] = output(value)
        value.layers[0].visible = false
        results["hiddenFirstConsumer"] = output(value)
        value.layers.reverse()
        results["hiddenLastConsumer"] = output(value)
        value.layers[1].visible = true
        value.layers[1].staticModelPath = "models/unsupported-sibling.mdl"
        results["unsupportedSibling"] = output(value)
        value.layers[1].staticModelPath = nil
        value.layers[1].id = 59
        results["unadmittedSibling"] = output(value)
        value = base; value.layers[0].effects = [1]; results["effects"] = output(value)
        value.materialPasses[0].constantShaderValues["power-key"] = .init(rawValue: "0.99", components: [0.99])
        results["fullProgramEffects"] = output(value, consumers: [])
        value.layers.append(.init(id: 58))
        results["fullProgramMixedEffectConsumers"] = output(value, consumers: [])
        value.layers[1].parentID = 57
        results["fullProgramEffectSiblingWithDependency"] = output(value, consumers: [])
        results["dynamicScalarRoles"] = ["rows": dynamicScalarCases()]
        results["scalarHostDefaults"] = ["rows": scalarHostDefaultCases()]
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
