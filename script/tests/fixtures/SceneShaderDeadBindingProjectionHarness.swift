import Foundation
import Metal

@main private enum DeadBindingProjectionHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        let input = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: arguments[1]))) as! [String: Any]
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
            output["boundedMetal"] = program.metalSource
            output["boundedMetalError"] = libraryError(program.metalSource)
        }
        if arguments.count > 2, let bundle = Bundle(path: arguments[2]) {
            try FileManager.default.createDirectory(
                atPath: arguments[3], withIntermediateDirectories: true)
            let semantics = SceneGenericShaderOutputSemantics(
                rawValue: input["outputSemantics"] as? String ?? "color")!
            let slots = Set(input["premultipliedColorInputSlots"] as? [Int] ?? [])
            let key = SceneResolvedMaterialGenericShaderRequest.key(
                vertexSource: pair.vertex, fragmentSource: pair.fragment,
                outputSemantics: semantics, expectedColorTransfer: nil,
                premultipliedColorInputSlots: slots, boundTextureSlots: boundSlots)
            output["requestKey"] = key
            switch SceneGenericShaderCompiler.compile(
                requestKey: key, vertexSource: pair.vertex, fragmentSource: pair.fragment,
                outputSemantics: semantics, premultipliedColorInputSlots: slots,
                boundTextureSlots: boundSlots, cacheRoot: URL(fileURLWithPath: arguments[3]), bundle: bundle) {
            case let .failure(failure): output["genericFailure"] = String(describing: failure)
            case let .success(url):
                let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
                    from: Data(contentsOf: url))
                output["genericSlots"] = artifact.program.textureBindings.map(\.slot)
                output["genericUniforms"] = artifact.program.uniformLayout.fields.map(\.name)
                output["genericMetal"] = artifact.program.metalSource
                output["genericMetalError"] = libraryError(artifact.program.metalSource)
                output["genericArtifact"] = url.path
                if let contract = frontend.program {
                    let program = artifact.makeProgram(
                        expectedKey: key, expectedOutputSemantics: semantics,
                        expectedPremultipliedColorInputSlots: slots,
                        expectedColorTransfer: contract.colorTransfer,
                        expectedFragmentOutputChannelUse: contract.fragmentOutputChannelUse)
                    output["genericPublicationAccepted"] = program != nil
                }
            }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]))
    }

    private static func libraryError(_ source: String) -> String {
        guard let device = MTLCreateSystemDefaultDevice() else { return "no Metal device" }
        do { _ = try device.makeLibrary(source: source, options: nil); return "" }
        catch { return String(describing: error) }
    }
}
