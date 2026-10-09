import Foundation

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
    uniform float gain; // {"material":"gain-key","default":1}
    uniform float opacity; // {"material":"opacity-key","default":1}
    uniform float exponent; // {"material":"power-key","default":1}
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
            of: "uniform float exponent; // {\"material\":\"power-key\",\"default\":1}\n", with: ""
        ).replacingOccurrences(of: "opacity", with: "gain")
            .replacingOccurrences(of: "exponent", with: "gain")
        results["sharedFragmentScalarUniform"] = output(base, shader: contract(fragment: sharedScalars))
        value = base; value.layers[0].visible = false; results["hidden"] = output(value)
        value = base; value.layers[0].usesPerspective = true; results["perspective"] = output(value)
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
        value.layers[1].usesPerspective = true
        results["unsupportedSibling"] = output(value)
        value.layers[1].usesPerspective = false
        value.layers[1].id = 59
        results["unadmittedSibling"] = output(value)
        value = base; value.layers[0].effects = [1]; results["effects"] = output(value)
        value.materialPasses[0].constantShaderValues["power-key"] = .init(rawValue: "0.99", components: [0.99])
        results["fullProgramEffects"] = output(value, consumers: [])
        value.layers.append(.init(id: 58))
        results["fullProgramMixedEffectConsumers"] = output(value, consumers: [])
        value.layers[1].parentID = 57
        results["fullProgramEffectSiblingWithDependency"] = output(value, consumers: [])
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
