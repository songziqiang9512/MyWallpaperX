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

    static func contract(vertex: String = vertex, fragment: String = fragment) -> SceneShaderContract {
        func stage(_ kind: SceneShaderContract.StageKind, _ source: String) -> SceneShaderContract.Stage {
            let path = "shaders/unseen/tint." + (kind == .vertex ? "vert" : "frag")
            let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: path)
            return .init(kind: kind, relativePath: path, source: source,
                rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
                includes: parsed.includes, annotations: parsed.annotations,
                declarations: parsed.declarations)
        }
        let stages = [stage(.vertex, vertex), stage(.fragment, fragment)]
        let digest = SceneShaderStableDigest.hash(Data((vertex + fragment).utf8))
        return .init(identity: "unseen/tint", sourceKind: .authoredSource, stages: stages,
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
        dynamic: Set<String> = [], shader: SceneShaderContract? = nil) -> [String: Any] {
        let bindings = SceneBaseMaterialColorModulationCompiler.compile(
            descriptor: descriptor, shaderContracts: [shader ?? contract()],
            dynamicImageModelPaths: dynamic, admittedLayerColorConsumerIDs: [57, 58])
        guard let first = bindings.first else { return ["count": 0] }
        return ["count": bindings.count, "model": first.modelPath,
            "material": first.materialPath, "key": first.colorKey,
            "color": [first.authoredColor.x, first.authoredColor.y, first.authoredColor.z],
            "hasScript": first.scriptSource != nil, "properties": first.scriptProperties.count]
    }

    static func main() throws {
        var results: [String: [String: Any]] = [:]
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
            ("powerHalf", "power-key", 0.5), ("scrollNonzero", "slide-x", 0.5),
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
        value = base; value.layers[0].effects = [1]; results["effects"] = output(value)
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
