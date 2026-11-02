import Foundation
import Metal

@main private enum DeadBindingProjectionHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        let input = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: arguments[1]))) as! [String: Any]
        if let builderStages = input["builderStages"] as? [[String: Any]] {
            let stages = try builderStages.map { stage in
                SceneGenericShaderArtifactBuilder.Stage(
                    name: stage["stage"] as! String, source: stage["source"] as! String,
                    authoredSource: stage["authoredSource"] as! String,
                    msl: stage["msl"] as! String,
                    reflection: try JSONSerialization.data(withJSONObject: stage["reflection"]!)
                )
            }
            var output: [String: Any] = [:]
            switch SceneGenericShaderArtifactBuilder.build(
                requestKey: String(repeating: "d", count: 64),
                backendID: "glslang-spirv-cross-msl-v2", stages: stages,
                maximumArtifactBytes: 1_000_000
            ) {
            case let .success(artifact):
                output["builderBindings"] = artifact.program.textureBindings.map {
                    ["name": $0.name, "slot": $0.slot] as [String: Any]
                }
            case let .failure(failure): output["builderFailure"] = String(describing: failure)
            }
            FileHandle.standardOutput.write(try JSONSerialization.data(
                withJSONObject: output, options: [.sortedKeys]))
            return
        }
        let stages = input["stages"] as! [[String: Any]]
        let vertex = stages.first { $0["stage"] as? String == "vertex" }!["source"] as! String
        let fragment = stages.first { $0["stage"] as? String == "fragment" }!["source"] as! String
        if input["neutralProofOnly"] as? Bool == true {
            let slots = Set(input["activeSlots"] as? [Int] ?? [0])
            let fact = SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                vertexSource: vertex, fragmentSource: fragment, activeSamplerSlots: slots)
            let vertexUnit = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
                lexerOutput: SceneAuthoredShaderLexer.lex(source: vertex, stage: .vertex), stage: .vertex)
            let fragmentUnit = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
                lexerOutput: SceneAuthoredShaderLexer.lex(source: fragment, stage: .fragment), stage: .fragment)
            let unitFact = vertexUnit.unit.flatMap { vertex in
                fragmentUnit.unit.flatMap { fragment in
                    SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                        vertex: vertex, fragment: fragment, activeSamplerSlots: slots)
                }
            }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: [
                "sourceSlot": fact?.resolutionSlot ?? -1, "unitSlot": unitFact?.resolutionSlot ?? -1,
            ], options: [.sortedKeys]))
            return
        }
        let boundSlots = Set(input["boundTextureSlots"] as? [Int] ?? [])
        let pair = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: vertex, fragment: fragment, boundTextureSlots: boundSlots)
        if input["projectionOnly"] as? Bool == true {
            let names = SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
                vertexSource: pair.vertex, fragmentSource: pair.fragment, boundTextureSlots: boundSlots)
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: [
                "vertex": pair.vertex, "fragment": pair.fragment,
                "samplerNames": names?.sorted() ?? [],
            ], options: [.sortedKeys]))
            return
        }
        let frontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: pair.vertex, fragmentSource: pair.fragment, boundTextureSlots: boundSlots)
        var output: [String: Any] = [
            "vertex": pair.vertex, "fragment": pair.fragment,
            "boundedDiagnostics": frontend.diagnostics.map { $0.code.rawValue },
        ]
        if let program = frontend.program {
            output["boundedSlots"] = program.textureBindings.map(\.slot)
            output["boundedUniforms"] = program.uniformLayout.fields.map(\.name)
            output["boundedLayout"] = try layoutJSON(program.uniformLayout)
            output["boundedMetal"] = program.metalSource
            output["boundedMetalError"] = libraryError(program.metalSource)
        }
        if arguments.count > 2, let bundle = Bundle(path: arguments[2]) {
            let semantics = SceneGenericShaderOutputSemantics(
                rawValue: input["outputSemantics"] as? String ?? "color")!
            let slots = Set(input["premultipliedColorInputSlots"] as? [Int] ?? [])
            let key = SceneResolvedMaterialGenericShaderRequest.key(
                vertexSource: pair.vertex, fragmentSource: pair.fragment,
                outputSemantics: semantics, expectedColorTransfer: nil,
                premultipliedColorInputSlots: slots, boundTextureSlots: boundSlots)
            output["requestKey"] = key
            let compileArtifact = {
                SceneGenericShaderCompiler.compile(
                    requestKey: key, vertexSource: pair.vertex, fragmentSource: pair.fragment,
                    outputSemantics: semantics, premultipliedColorInputSlots: slots,
                    boundTextureSlots: boundSlots, bundle: bundle)
            }
            switch compileArtifact() {
            case let .failure(failure): output["genericFailure"] = String(describing: failure)
            case let .success(compiled):
                let artifact = compiled.artifact
                output["genericSlots"] = artifact.program.textureBindings.map(\.slot)
                output["genericUniforms"] = artifact.program.uniformLayout.fields.map(\.name)
                output["genericLayout"] = try layoutJSON(artifact.program.uniformLayout)
                output["genericLoopGuardCap"] = artifact.program.loopGuardCap.map { $0 as Any } ?? NSNull()
                output["genericMetal"] = artifact.program.metalSource
                output["genericMetalError"] = libraryError(artifact.program.metalSource)
                if input["verifyRepeatedCompilation"] as? Bool == true {
                    let repeated = try compileArtifact().get()
                    output["genericRepeatedLayout"] = try layoutJSON(repeated.artifact.program.uniformLayout)
                    output["genericRepeatedArtifactEqual"] = repeated.encodedData == compiled.encodedData
                }
                if let contract = frontend.program {
                    let program = artifact.makeProgram(
                        expectedKey: key, expectedOutputSemantics: semantics,
                        expectedPremultipliedColorInputSlots: slots,
                        expectedColorTransfer: contract.colorTransfer,
                        expectedFragmentOutputChannelUse: contract.fragmentOutputChannelUse)
                    output["genericProgramAccepted"] = program != nil
                }
            }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]))
    }

    private static func layoutJSON(_ layout: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout))
    }

    private static func libraryError(_ source: String) -> String {
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        do { _ = try device.makeLibrary(source: source, options: nil); return "" }
        catch { return String(describing: error) }
    }
}
