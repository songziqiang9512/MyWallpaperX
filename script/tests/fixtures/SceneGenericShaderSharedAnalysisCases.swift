import Foundation

/// The harness stages the real syntax analyzer with a call to recordParse.
/// No product source, cache entry, or compiler identity contains this counter.
nonisolated enum SceneGenericShaderSharedAnalysisCases {
    private final class ParseCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func record() { lock.lock(); value += 1; lock.unlock() }
        func reset() { lock.lock(); value = 0; lock.unlock() }
        func read() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    }
    private static let counter = ParseCounter()

    static func recordParse(strict: Bool) {
        if strict { counter.record() }
    }

    struct Facts: Equatable {
        let associated: SceneAuthoredShaderAssociatedOverBlendAnalyzer.Fact?
        let normalized: Int?
        let preserved: SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.Fact?
        let typed: SceneAuthoredShaderTypedDataRGBFilterAnalyzer.Fact?
        let reconstructed: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?
        let previous: SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.Fact?

        var present: [Bool] {
            [associated != nil, normalized != nil, preserved != nil,
             typed != nil, reconstructed != nil, previous != nil]
        }
    }

    struct Case {
        let name: String
        let source: String
        let positive: Int?
        let rejected: Int?
        let requiresNilAnalysis: Bool

        init(_ name: String, _ source: String, positive: Int? = nil,
             rejected: Int? = nil, requiresNilAnalysis: Bool = false) {
            self.name = name; self.source = source; self.positive = positive
            self.rejected = rejected; self.requiresNilAnalysis = requiresNilAnalysis
        }
    }

    /// Independent expectations use the original public String entry points.
    static func stringFacts(_ source: String) -> Facts {
        .init(
            associated: SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze(fragmentSource: source),
            normalized: SceneAuthoredShaderNormalizedSampleSumAnalyzer.sourceSlot(fragmentSource: source),
            preserved: SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(fragmentSource: source),
            typed: SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(fragmentSource: source),
            reconstructed: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(fragmentSource: source),
            previous: SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze(fragmentSource: source)
        )
    }

    static func sharedFacts(
        _ analysis: SceneAuthoredShaderColorTransferAnalyzer.SourceAnalysis?
    ) -> Facts {
        .init(
            associated: analysis.flatMap { SceneAuthoredShaderAssociatedOverBlendAnalyzer.analyze($0.fragment) },
            normalized: analysis.flatMap { SceneAuthoredShaderNormalizedSampleSumAnalyzer.analyze(
                outputUses: $0.outputUses, fragment: $0.fragment, main: $0.main) },
            preserved: analysis.flatMap { SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny($0.fragment) },
            typed: analysis.flatMap { SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze($0.fragment) },
            reconstructed: analysis.flatMap { SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze($0.fragment) },
            previous: analysis.flatMap { SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.analyze($0.fragment) }
        )
    }

    static let associated = """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform float g_ScalarWeight;
    vec4 Composite(vec4 albedo, vec4 blendColors, float blendAlpha) {
        float newAlpha = (albedo.a * (1.0 - blendAlpha) + blendColors.a * blendAlpha);
        vec4 input = albedo;
        albedo.rgb = albedo.rgb * albedo.a * (1.0 - blendAlpha) + blendColors.rgb * blendColors.a * blendAlpha;
        vec3 srcRgb = mix(blendColors.rgb, input.rgb, step(0.01, input.a) * (1.0 - blendColors.a * blendAlpha));
        vec3 dstRgb = mix(input.rgb, blendColors.rgb, step(0.01, blendColors.a * (1.0 - input.a * (1.0 - blendAlpha))));
        albedo.rgb += mix(srcRgb, dstRgb, blendAlpha) * (1.0 - newAlpha);
        albedo.a = newAlpha;
        return albedo;
    }
    float GetUVBlend(vec2 uv) { return 1.0; }
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        vec2 blendUV = v_TexCoord.zw;
        vec4 blendColors = texSample2D(g_Texture1, blendUV);
        float blend = 1.0;
        blend = GetUVBlend(blendUV) * blend;
        float blendAlpha = blend * g_ScalarWeight;
        albedo = Composite(albedo, blendColors, blendAlpha);
        gl_FragColor = albedo;
    }
    """

    static let normalized = """
    uniform sampler2D g_Texture0;
    varying vec2 v_TexCoord;
    vec4 sharedKernel(vec2 uv, vec2 delta) {
        vec2 offset = delta * 1.0;
        return texSample2D(g_Texture0, uv - offset) * 0.25
            + texSample2D(g_Texture0, uv) * 0.5
            + texSample2D(g_Texture0, uv + offset) * 0.25;
    }
    void main() { gl_FragColor = sharedKernel(v_TexCoord, vec2(0.01)); }
    """

    static let preserved = """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform sampler2D g_Texture2;
    uniform float u_Opacity;
    varying vec2 v_TexCoord;
    vec3 ApplyBlending(const int mode, in vec3 base, in vec3 filtered, in float opacity) {
        return mix(base, filtered, opacity);
    }
    #define kernel 1
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        vec2 depthTex = texSample2D(g_Texture2, v_TexCoord).rg;
        float depth = max(depthTex.x, depthTex.y);
        if (depth > 0.01) {
            vec4 original = albedo;
            for (int i = -kernel; i <= kernel; i++) {
                albedo.rgb += texSample2D(g_Texture0, v_TexCoord + vec2(float(i))).rgb;
            }
            albedo.rgb /= 4.0;
        }
        vec4 baseAlbedo = texSample2D(g_Texture1, v_TexCoord);
        albedo = vec4(ApplyBlending(0, baseAlbedo.rgb, albedo.rgb, u_Opacity * depthTex.x), albedo.a);
        gl_FragColor = albedo;
    }
    """

    static let typed = """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    uniform sampler2D g_Texture2;
    uniform sampler2D g_Texture3;
    uniform sampler2D g_Texture4;
    uniform sampler2D g_Texture5;
    uniform sampler2D g_Texture6;
    varying vec2 v_TexCoord;
    vec3 ApplyBlending(const int mode, in vec3 base, in vec3 generated, in float opacity) {
        return mix(base, generated, opacity);
    }
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        float mask = texSample2D(g_Texture1, v_TexCoord).r;
        vec4 shiftColor = texSample2D(g_Texture4, v_TexCoord) * 2.0 - 1.0;
        vec4 noiseColor = texSample2D(g_Texture3, v_TexCoord) * 2.0 - 1.0;
        vec4 noiseColor2 = texSample2D(g_Texture3, v_TexCoord * 2.0) * 2.0 - 1.0;
        vec3 pattern = vec3(texSample2D(g_Texture2, v_TexCoord).r,
            texSample2D(g_Texture2, v_TexCoord * 2.0).r,
            texSample2D(g_Texture2, v_TexCoord * 3.0).r);
        float glow = texSample2D(g_Texture5, v_TexCoord).r;
        vec4 blendColor = texSample2D(g_Texture3, v_TexCoord * 3.0);
        vec2 flow = texSample2D(g_Texture6, v_TexCoord).rg;
        vec3 generated = pattern * noiseColor.rgb + shiftColor.rgb * glow + blendColor.rgb * flow.x;
        albedo.rgb = ApplyBlending(8, albedo.rgb, generated, mask);
        gl_FragColor = albedo;
    }
    """

    static let reconstructed = """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture1;
    varying vec4 v_Coordinate;
    vec2 bend(vec2 uv, float amount) {
        vec2 shifted = uv;
        return uv + vec2(amount * shifted.y * shifted.y, 0.0);
    }
    void main() {
        float red = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.4)).r;
        float green = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.0)).g;
        float blue = texSample2D(g_Texture0, bend(v_Coordinate.xy, -0.4)).b;
        float alpha = texSample2D(g_Texture0, bend(v_Coordinate.xy, 0.2)).a;
        float mask = texSample2D(g_Texture1, v_Coordinate.xy).r;
        gl_FragColor = lerp(texSample2D(g_Texture0, v_Coordinate.xy), vec4(red, green, blue, alpha), mask);
    }
    """

    static let previous = """
    uniform sampler2D g_Texture0;
    uniform sampler2D g_Texture2;
    uniform vec3 u_Tint;
    varying vec2 v_TexCoord;
    vec4 compose(vec4 base, vec4 effect) {
        effect.rgb *= u_Tint;
        return effect;
    }
    void main() {
        vec4 blurred = texSample2D(g_Texture0, v_TexCoord);
        vec4 previous = texSample2D(g_Texture2, v_TexCoord.xy);
        float mask = 1.0;
        float divisor = mix(blurred.a, 1, step(blurred.a, 0));
        blurred = compose(previous, vec4(blurred.rgb / divisor, blurred.a));
        blurred = mix(previous, blurred, mask);
        gl_FragColor = blurred;
    }
    """

    static var cases: [Case] {
        let positive = [associated, normalized, preserved, typed, reconstructed, previous]
        var result = positive.enumerated().map { Case("positive-\($0.offset)", $0.element, positive: $0.offset) }
        for (index, source) in positive.enumerated() {
            // Rename samplers, varying, locals and helpers without changing the
            // algorithm. Raw GLSL and authored aliases stay separate inputs.
            let renamed = source.replacingOccurrences(of: "g_Texture0", with: "g_Texture7")
                .replacingOccurrences(of: "v_TexCoord", with: "v_UV")
                .replacingOccurrences(of: "albedo", with: "surface")
                .replacingOccurrences(of: "Composite", with: "CombineLayers")
                .replacingOccurrences(of: "sharedKernel", with: "filterSamples")
                .replacingOccurrences(of: "bend", with: "warpCoordinate")
                .replacingOccurrences(of: "compose", with: "mixHistory")
            result.append(Case("renamed-\(index)", renamed, positive: index))
        }
        result += [
            Case("weight-equivalent", normalized.replacingOccurrences(of: "0.25", with: "0.125")
                .replacingOccurrences(of: "0.5", with: "0.75"), positive: 1),
            Case("weight-not-normalized", normalized.replacingOccurrences(of: "0.25", with: "0.5"), rejected: 1),
            Case("helper-alpha-drift", associated.replacingOccurrences(of: "albedo.a = newAlpha;",
                with: "albedo.a = blendColors.a;"), rejected: 0),
            Case("carrier-alpha-drift", preserved.replacingOccurrences(of: "gl_FragColor = albedo;",
                with: "albedo.a = 0.5; gl_FragColor = albedo;"), rejected: 2),
            Case("typed-alpha-drift", typed.replacingOccurrences(of: "gl_FragColor = albedo;",
                with: "albedo.a = mask; gl_FragColor = albedo;"), rejected: 3),
            Case("sampled-alpha-other-slot", reconstructed.replacingOccurrences(
                of: "float alpha = texSample2D(g_Texture0", with: "float alpha = texSample2D(g_Texture1"), rejected: 4),
            Case("composite-helper-drift", previous.replacingOccurrences(of: "return effect;",
                with: "return base;"), rejected: 5),
            Case("conditional-output", normalized.replacingOccurrences(of: "gl_FragColor = sharedKernel",
                with: "if (v_TexCoord.x > 0.0) gl_FragColor = sharedKernel"), rejected: 1),
            Case("missing-main", normalized.replacingOccurrences(of: "void main()", with: "void other()"), requiresNilAnalysis: true),
            Case("broken-delimiter", normalized + "{", requiresNilAnalysis: true),
            Case("unsupported-control-flow", "void main() { while (true) {} gl_FragColor = vec4(1.0); }", requiresNilAnalysis: true),
            Case("unproven-runtime-loop", "uniform int n; void main() { vec4 c = vec4(0.0); for (int i = 0; i < n; i++) { c += vec4(0.1); } gl_FragColor = c; }", requiresNilAnalysis: true),
        ]
        return result
    }

    static func input(_ source: String) -> SceneResolvedMaterialGenericShaderResolutionCache.Input {
        .init(
            vertexSource: "attribute vec3 a_Position; void main() { gl_Position = vec4(a_Position, 1.0); }",
            fragmentSource: source,
            alphaAttenuationSourceSlot: nil, colorBlendSourceSlot: nil,
            previousBlurredCompositeBlurredSlot: nil, previousBlurredCompositePreviousSlot: nil,
            previousBlurredCompositeMaskSlot: nil, hasExternalProviderTexture: true,
            producesScalarRedOutput: false, producesRedGreenUnormOutput: false,
            hasOnlyScalarDataInputs: false, isSourceIndependentPremultipliedOutput: false,
            graphTextureSlots: [], graphInputTextureSlots: [0], graphDataTextureSlots: [],
            activeTextureSlots: Set(0 ... 7), activeOpacityMaskSlots: [2],
            typedStaticDataAuxiliarySlots: [2], preservedChannelsExternalProviderTextureSlots: [],
            premultipliedColorAuxiliarySlots: [1], sceneBackgroundColorSlots: [],
            spatialWeightedColorBlendSourceSlot: nil, spatialWeightedColorBlendActiveSlots: [],
            spatialWeightedColorBlendTypedAuxiliarySlots: [], spatialWeightedColorBlendExternalColorSlot: nil,
            r8TextureSlots: [], hasDefaultedOpacityMaskSampler: false,
            hasOnlyTypedOpacityMaskAuxiliary: false, hasOnlyGraphInputSampler: false,
            outputIsRGBA8Unorm: true, sourceColorTransfer: nil, outputSemantics: .color,
            runtimeLoopBounds: .none
        )
    }

    struct AnalysisSignature: Encodable {
        let profile: String
        let transfer: SceneShaderColorTransfer
        let expected: SceneGenericShaderExpectedColorTransfer?
        let inputSlots: [Int]
        let defaultSlots: [Int]
        init(_ value: SceneGenericShaderAnalysis) {
            profile = value.profile.rawValue; transfer = value.colorTransfer
            expected = value.expectedColorTransfer
            inputSlots = value.premultipliedColorInputSlots.sorted()
            defaultSlots = value.defaultBoundaryColorSlots.sorted()
        }
    }

    static func run() throws {
        var rows: [[String: Any]] = []
        for fixture in cases {
            counter.reset()
            let originalAnalysis = SceneAuthoredShaderColorTransferAnalyzer.SourceAnalysis(fragmentSource: fixture.source)
            let expected = stringFacts(fixture.source)
            let originalParses = counter.read()
            counter.reset()
            let sharedAnalysis = SceneAuthoredShaderColorTransferAnalyzer.SourceAnalysis(fragmentSource: fixture.source)
            let actual = sharedFacts(sharedAnalysis)
            let sharedParses = counter.read()
            precondition(actual == expected, "\(fixture.name): every source fact must remain identical")
            precondition(originalParses == 7 && sharedParses == 1, "\(fixture.name): strict parse reuse")
            if let index = fixture.positive { precondition(actual.present[index], "\(fixture.name): positive fact") }
            if let index = fixture.rejected { precondition(!actual.present[index], "\(fixture.name): changed semantics") }
            if fixture.requiresNilAnalysis {
                precondition(originalAnalysis == nil && sharedAnalysis == nil && !actual.present.contains(true),
                    "\(fixture.name): preserve strict grammar and missing-main behavior")
            }
            counter.reset()
            let computed = SceneResolvedMaterialGenericShaderArtifactCache.computeAnalysis(input: input(fixture.source)).analysis
            let productParses = counter.read()
            precondition(computed.colorTransfer == SceneAuthoredShaderColorTransferAnalyzer.analyze(sourceAnalysis: sharedAnalysis),
                "\(fixture.name): actual analysis must consume the same raw source transfer")
            let signature = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnalysisSignature(computed)))
            rows.append(["name": fixture.name, "facts": actual.present,
                "originalParses": originalParses, "sharedParses": sharedParses,
                "productParses": productParses, "analysis": signature])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]))
    }
}
