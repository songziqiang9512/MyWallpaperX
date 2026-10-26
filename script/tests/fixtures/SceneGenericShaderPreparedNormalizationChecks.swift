import Foundation

/// CPU preparation and real signed-helper compilation; no Metal device is used.
@main
enum SceneGenericShaderPreparedNormalizationChecks {
    typealias Cache = SceneResolvedMaterialGenericShaderArtifactCache
    typealias Input = SceneResolvedMaterialGenericShaderResolutionCache.Input
    typealias Pair = SceneGenericShaderSourceNormalizer.Pair

    static let vertex = """
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec2 v_TexCoord;
    void main() {
        gl_Position = vec4(a_Position, 1.0);
        v_TexCoord = a_TexCoord;
    }
    """
    static let fragment = """
    uniform sampler2D g_Texture0;
    varying vec2 v_TexCoord;
    void main() {
        gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
    }
    """

    static func input(vertex: String, fragment: String) -> Input {
        .init(
            vertexSource: vertex, fragmentSource: fragment,
            alphaAttenuationSourceSlot: nil, colorBlendSourceSlot: nil,
            previousBlurredCompositeBlurredSlot: nil,
            previousBlurredCompositePreviousSlot: nil,
            previousBlurredCompositeMaskSlot: nil,
            hasExternalProviderTexture: false,
            producesScalarRedOutput: false, producesRedGreenUnormOutput: false,
            hasOnlyScalarDataInputs: false, isSourceIndependentPremultipliedOutput: false,
            graphTextureSlots: [], graphInputTextureSlots: [], graphDataTextureSlots: [],
            activeTextureSlots: [0], activeOpacityMaskSlots: [], typedStaticDataAuxiliarySlots: [],
            preservedChannelsExternalProviderTextureSlots: [], premultipliedColorAuxiliarySlots: [],
            sceneBackgroundColorSlots: [], spatialWeightedColorBlendSourceSlot: nil,
            spatialWeightedColorBlendActiveSlots: [], spatialWeightedColorBlendTypedAuxiliarySlots: [],
            spatialWeightedColorBlendExternalColorSlot: nil, r8TextureSlots: [],
            hasDefaultedOpacityMaskSampler: false, hasOnlyTypedOpacityMaskAuxiliary: false,
            hasOnlyGraphInputSampler: false, outputIsRGBA8Unorm: false,
            sourceColorTransfer: nil, outputSemantics: .color, runtimeLoopBounds: .none
        )
    }

    static func pairFields(_ pair: Pair) -> [String: Any] {
        ["vertex": pair.vertex, "fragment": pair.fragment,
         "mutableVaryings": pair.localizedMutableFragmentVaryings.sorted(),
         "audioArrays": pair.activeAudioSpectrumArrays.sorted(),
         "vertexPositionInput": pair.vertexPositionInput.rawValue]
    }

    static func analysisFields(_ analysis: SceneGenericShaderAnalysis) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.data(withJSONObject: [
            "profile": analysis.profile.rawValue,
            "colorTransfer": String(decoding: encoder.encode(analysis.colorTransfer), as: UTF8.self),
            "expectedTransfer": analysis.expectedColorTransfer?.cacheKey ?? "-",
            "expectedLoopWork": analysis.expectedColorTransfer?.accumulatorLoopWork ?? -1,
            "premultipliedSlots": analysis.premultipliedColorInputSlots.sorted(),
            "boundarySlots": analysis.defaultBoundaryColorSlots.sorted(),
        ], options: [.sortedKeys])
    }

    static func key(_ input: Input, _ analysis: SceneGenericShaderAnalysis) -> String {
        SceneResolvedMaterialGenericShaderRequest.key(
            vertexSource: input.vertexSource, fragmentSource: input.fragmentSource,
            outputSemantics: input.outputSemantics,
            expectedColorTransfer: analysis.expectedColorTransfer,
            premultipliedColorInputSlots: analysis.premultipliedColorInputSlots,
            defaultBoundaryColorSlots: analysis.defaultBoundaryColorSlots,
            colorBoundary: input.colorBoundary, boundTextureSlots: input.activeTextureSlots
        )
    }

    static func compile(
        _ input: Input, analysis: SceneGenericShaderAnalysis, pair: Pair?,
        bundle: Bundle, root: URL
    ) -> Result<URL, SceneGenericShaderCompiler.Failure> {
        SceneGenericShaderCompiler.compile(
            requestKey: key(input, analysis),
            vertexSource: input.vertexSource, fragmentSource: input.fragmentSource,
            outputSemantics: input.outputSemantics,
            expectedColorTransfer: analysis.expectedColorTransfer,
            premultipliedColorInputSlots: analysis.premultipliedColorInputSlots,
            defaultBoundaryColorSlots: analysis.defaultBoundaryColorSlots,
            colorBoundary: input.colorBoundary, boundTextureSlots: input.activeTextureSlots,
            cacheRoot: root, normalizedSources: pair, bundle: bundle
        )
    }

    static func expect(_ value: Bool, _ message: String) throws {
        guard value else { throw NSError(domain: message, code: 1) }
    }

    static func acceptedArtifact(
        _ url: URL, input: Input, analysis: SceneGenericShaderAnalysis
    ) throws -> Data {
        let data = try Data(contentsOf: url)
        let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self, from: data)
        try expect(artifact.requestKey == key(input, analysis), "raw-request-key")
        let program = artifact.makeProgram(
            expectedKey: key(input, analysis), expectedOutputSemantics: input.outputSemantics,
            expectedPremultipliedColorInputSlots: analysis.premultipliedColorInputSlots,
            expectedColorBoundary: input.colorBoundary, expectedColorTransfer: analysis.colorTransfer,
            expectedFragmentOutputChannelUse:
                SceneAuthoredShaderFragmentOutputAnalyzer.analyze(source: input.fragmentSource)
        )
        try expect(program != nil, "actual-program-contract")
        return data
    }

    static func equivalence(bundle: Bundle, root: URL) throws -> [String: Any] {
        let variants = [
            (vertex, fragment),
            (vertex.replacingOccurrences(of: "v_TexCoord", with: "v_RenamedUV"),
             "// renamed author\n" + fragment.replacingOccurrences(of: "v_TexCoord", with: "v_RenamedUV")),
            (vertex, fragment.replacingOccurrences(of: "void main()", with:
                "uniform float g_AudioSpectrum16Left[16];\nuniform float g_AudioSpectrum16Right[16];\nvoid main()")
                .replacingOccurrences(of: "texSample2D(g_Texture0, v_TexCoord)", with:
                    "texSample2D(g_Texture0, v_TexCoord) * vec4(vec3(g_AudioSpectrum16Left[0] + g_AudioSpectrum16Right[0]), 1.0)")),
        ]
        var rows: [[String: Any]] = []
        for (index, sources) in variants.enumerated() {
            let input = input(vertex: sources.0, fragment: sources.1)
            let fresh = Cache.resolvedAnalysis(for: input)
            try expect(!fresh.fromCache, "fresh-analysis-miss")
            let pair = try fresh.normalizedSources.unwrap("fresh-pair")
            let independent = try SceneGenericShaderSourceNormalizer.normalize(
                vertexSource: sources.0, fragmentSource: sources.1,
                maximumStageSourceBytes: Cache.maximumRouteAnalysisSourceBytes
            ).get()
            let fields = try JSONSerialization.data(withJSONObject: pairFields(pair), options: [.sortedKeys])
            let oracle = try JSONSerialization.data(withJSONObject: pairFields(independent), options: [.sortedKeys])
            try expect(fields == oracle, "all-pair-fields")
            let providedRoot = root.appendingPathComponent("provided-\(index)")
            let ordinaryRoot = root.appendingPathComponent("ordinary-\(index)")
            for path in [providedRoot, ordinaryRoot] {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
            let provided = try compile(input, analysis: fresh.analysis, pair: pair,
                bundle: bundle, root: providedRoot).get()
            let ordinary = try compile(input, analysis: fresh.analysis, pair: nil,
                bundle: bundle, root: ordinaryRoot).get()
            let providedData = try acceptedArtifact(provided, input: input, analysis: fresh.analysis)
            let ordinaryData = try acceptedArtifact(ordinary, input: input, analysis: fresh.analysis)
            try expect(providedData == ordinaryData, "same-actual-artifact-and-program")
            let normalizedInput = self.input(vertex: pair.vertex, fragment: pair.fragment)
            try expect(key(input, fresh.analysis) != key(normalizedInput, fresh.analysis), "raw-key-not-normalized-key")
            SceneGenericShaderAnalysisCache.store(analysis: fresh.analysis, input: input)
            let warm = Cache.resolvedAnalysis(for: input)
            try expect(warm.fromCache && warm.normalizedSources == nil, "warm-analysis-does-not-retain-pair")
            try expect(analysisFields(warm.analysis) == analysisFields(fresh.analysis), "same-persisted-analysis")
            rows.append(["index": index, "pairSHA256": SceneGenericShaderProgramArtifact.sha256(fields),
                "artifactSHA256": SceneGenericShaderProgramArtifact.sha256(providedData),
                "audioArrays": pair.activeAudioSpectrumArrays.sorted(), "warmHasPair": false])
        }
        return ["rows": rows]
    }

    static func budgets(low: Bundle, high: Bundle, missing: Bundle, root: URL) throws -> [String: Any] {
        let oversized = input(vertex: vertex, fragment: "//" + String(repeating: "x", count: 2_048) + "\n" + fragment)
        let lowAnalysis = Cache.computeAnalysis(input: oversized)
        try expect(lowAnalysis.normalizedSources != nil, "route-budget-allows-oversized-for-low-compiler")
        var rawFailures: [String] = []
        for pair in [lowAnalysis.normalizedSources, nil] {
            let result = compile(oversized, analysis: lowAnalysis.analysis, pair: pair, bundle: low, root: root)
            guard case .failure(.normalization("sourceTooLarge")) = result else {
                throw NSError(domain: "actual-raw-budget-\(result)", code: 1)
            }
            rawFailures.append("sourceTooLarge")
            guard case .failure(.configuration("licenseBundleUnavailable")) =
                compile(oversized, analysis: lowAnalysis.analysis, pair: pair, bundle: missing, root: root) else {
                throw NSError(domain: "bundle-must-resolve-first", code: 1)
            }
        }
        let small = input(vertex: vertex, fragment: fragment)
        let smallAnalysis = Cache.computeAnalysis(input: small)
        let smallPair = try smallAnalysis.normalizedSources.unwrap("small-pair")
        try expect(vertex.utf8.count < 1_024 && fragment.utf8.count < 1_024
            && max(smallPair.vertex.utf8.count, smallPair.fragment.utf8.count) > 1_024,
            "raw-fits-but-generated-output-exceeds-low-cap")
        for pair in [smallAnalysis.normalizedSources, nil] {
            guard case .failure(.workspace) =
                compile(small, analysis: smallAnalysis.analysis, pair: pair, bundle: low, root: root) else {
                throw NSError(domain: "normalized-output-budget", code: 1)
            }
        }
        let large = input(vertex: vertex, fragment:
            "//" + String(repeating: "x", count: Cache.maximumRouteAnalysisSourceBytes) + "\n" + fragment)
        let routeFailed = Cache.computeAnalysis(input: large)
        try expect(routeFailed.normalizedSources == nil, "route-size-failure-is-not-a-compiler-failure")
        let largeURL = try compile(large, analysis: routeFailed.analysis, pair: routeFailed.normalizedSources,
            bundle: high, root: root).get()
        _ = try acceptedArtifact(largeURL, input: large, analysis: routeFailed.analysis)
        let bad = input(vertex: vertex, fragment:
            "uniform samplerCube g_Cube;\nvoid main() { gl_FragColor = vec4(1.0); }\n")
        let badRoute = Cache.computeAnalysis(input: bad)
        try expect(badRoute.normalizedSources == nil, "route-structural-failure-has-no-pair")
        guard case .failure(.normalization("samplerUnsupported")) =
            compile(bad, analysis: badRoute.analysis, pair: badRoute.normalizedSources, bundle: high, root: root) else {
            throw NSError(domain: "compiler-still-attempts-structural-failure", code: 1)
        }
        return ["rawFailures": rawFailures, "bundleFirst": true, "outputBudget": true,
            "largeRawBytes": large.fragmentSource.utf8.count, "largeCompiled": true,
            "routeFailureRetriedByCompiler": true]
    }

    static func main() throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[2], isDirectory: true)
        let bundles = args[3...6].map { Bundle(path: $0)! }
        let expectedHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!)
            .resolvingSymlinksInPath().standardizedFileURL
        try expect(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
            .standardizedFileURL == expectedHome, "isolated-home")
        let report = try args[1] == "equivalence"
            ? equivalence(bundle: bundles[0], root: root)
            : budgets(low: bundles[1], high: bundles[2], missing: bundles[3], root: root)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]))
    }
}

private extension Optional {
    func unwrap(_ name: String) throws -> Wrapped {
        guard let value = self else { throw NSError(domain: name, code: 1) }
        return value
    }
}
