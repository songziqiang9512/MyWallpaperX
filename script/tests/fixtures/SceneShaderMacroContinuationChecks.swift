import Foundation

@main
private enum SceneShaderMacroContinuationChecks {
    static func main() throws {
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: inputURL))
            as! [[String: Any]]
        var rows: [[String: Any]] = []
        for item in input {
            let name = item["name"] as! String
            let directory = root.appendingPathComponent(name, isDirectory: true)
            let rootPath = item["root"] as! String
            for (path, source) in item["files"] as! [String: String] {
                let url = directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try source.write(to: url, atomically: true, encoding: .utf8)
            }
            let graph = SceneShaderSourceGraphBuilder().build(
                roots: [.init(label: "fragment", virtualPath: rootPath)],
                resourceView: SceneResourceView(projectRootURL: directory, packageRootURL: nil))
            let environment = try SceneShaderVariantEnvironment(stage: .fragment, combos: [])
            let overrides = item["limits"] as? [String: Int] ?? [:]
            let defaults = SceneShaderPreprocessor.Limits.default
            let limits = SceneShaderPreprocessor.Limits(
                maximumIncludeDepth: overrides["maximumIncludeDepth"] ?? defaults.maximumIncludeDepth,
                maximumDependencies: overrides["maximumDependencies"] ?? defaults.maximumDependencies,
                maximumInputBytes: overrides["maximumInputBytes"] ?? defaults.maximumInputBytes,
                maximumOutputBytes: overrides["maximumOutputBytes"] ?? defaults.maximumOutputBytes,
                maximumOutputLines: overrides["maximumOutputLines"] ?? defaults.maximumOutputLines,
                maximumExpressionTokens: overrides["maximumExpressionTokens"] ?? defaults.maximumExpressionTokens,
                maximumFunctionMacroParameters: overrides["maximumFunctionMacroParameters"] ?? defaults.maximumFunctionMacroParameters,
                maximumMacroExpansionDepth: overrides["maximumMacroExpansionDepth"] ?? defaults.maximumMacroExpansionDepth,
                maximumMacroExpansionTokens: overrides["maximumMacroExpansionTokens"] ?? defaults.maximumMacroExpansionTokens,
                maximumMacroExpansionBytes: overrides["maximumMacroExpansionBytes"] ?? defaults.maximumMacroExpansionBytes)
            var row: [String: Any] = ["name": name, "root": rootPath]
            switch SceneShaderPreprocessor().preprocess(rootRelativePath: rootPath,
                graph: graph, environment: environment, limits: limits) {
            case let .success(prepared):
                row["status"] = "success"
                row["source"] = prepared.source
                // Use the production lexical view only to compare emitted code
                // independently of preserved comments and physical whitespace.
                var inComment = false
                row["code"] = prepared.source.components(separatedBy: "\n").map {
                    SceneShaderLexicalScanner.scan($0, inBlockComment: &inComment).code
                }.joined(separator: "\n")
                row["sourceMap"] = prepared.sourceMap.map {
                    ["outputLine": $0.outputLine, "sourcePath": $0.sourcePath,
                     "sourceLine": $0.sourceLine] as [String: Any]
                }
                row["annotations"] = prepared.activeAnnotations.map {
                    ["path": $0.sourcePath, "line": $0.annotation.line,
                     "raw": $0.annotation.raw] as [String: Any]
                }
                row["declarations"] = prepared.activeDeclarations.map {
                    ["path": $0.sourcePath, "line": $0.declaration.line,
                     "name": $0.declaration.name] as [String: Any]
                }
                row["dependencies"] = prepared.dependencies.map { $0.relativePath }
                row["preparedSHA256"] = prepared.preparedSHA256
            case let .failure(failure):
                row["status"] = "failure"
                row["diagnostics"] = failure.diagnostics.map {
                    ["code": $0.code.rawValue, "path": $0.relativePath ?? "",
                     "line": $0.line ?? -1] as [String: Any]
                }
            }
            rows.append(row)
        }
        let data = try JSONSerialization.data(withJSONObject: ["rows": rows],
            options: [.sortedKeys, .prettyPrinted])
        FileHandle.standardOutput.write(data)
    }
}
