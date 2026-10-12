import Foundation

nonisolated struct SceneScriptDynamicImageReference: Equatable, Hashable, Sendable {
    let authoredPath: String
    let modelPath: String
}

/// Lossless resource planning for the bounded dynamic image-layer slice.
/// JavaScript still executes in QuickJS; this only identifies direct literal
/// model requests early enough to prepare their immutable GPU resources off
/// the render path.
nonisolated enum SceneScriptDynamicImageReferenceAnalysis {
    static func references(
        in source: String,
        descriptor: SceneRenderDescriptor
    ) -> [SceneScriptDynamicImageReference]? {
        references(in: source, availableModelPaths: descriptor.modelMaterialLinks.map(\.modelPath))
    }

    static func references(
        in source: String,
        availableModelPaths: [String]
    ) -> [SceneScriptDynamicImageReference]? {
        guard source.utf8.count <= 65_536 else { return nil }
        guard let tokens = SceneLaunchOriginTransitionLexer.referenceTokens(source) else { return nil }
        var literals: [String] = []
        var hasInvocation = false
        var workshopID: String?
        for index in tokens.indices {
            if index + 4 < tokens.count, tokens[index] == .identifier("export"),
               ["let", "const", "var"].contains(tokens[index + 1].identifierValue ?? ""),
               tokens[index + 2] == .identifier("__workshopId"), tokens[index + 3] == .symbol("="),
               let value = tokens[index + 4].stringValue,
               value.count <= 32, !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }) {
                workshopID = workshopID ?? value
            }
            guard index + 4 < tokens.count, tokens[index] == .identifier("thisScene"),
                  tokens[index + 1] == .symbol("."), tokens[index + 2] == .identifier("createLayer"),
                  tokens[index + 3] == .symbol("(") else { continue }
            hasInvocation = true
            literals += literalPaths(tokens, argument: index + 4)
        }
        guard hasInvocation else { return nil }
        var references: [SceneScriptDynamicImageReference] = []
        var seen: Set<String> = []
        for authored in literals {
            guard let normalized = normalizedPath(authored),
                  let resolved = resolvedModelPath(
                    normalized, workshopID: workshopID, available: availableModelPaths
                  ) else { continue }
            let identity = normalized.lowercased()
            guard seen.insert(identity).inserted else { continue }
            references.append(.init(
                authoredPath: normalized,
                modelPath: resolved
            ))
        }
        return references
    }

    private static func resolvedModelPath(
        _ authored: String,
        workshopID: String?,
        available: [String]
    ) -> String? {
        if let exact = available.first(where: {
            $0.caseInsensitiveCompare(authored) == .orderedSame
        }) {
            return exact
        }
        guard let workshopID,
              authored.lowercased().hasPrefix("models/") else { return nil }
        let suffix = authored.dropFirst("models/".count)
        let namespaced = "models/workshop/\(workshopID)/\(suffix)"
        return available.first {
            $0.caseInsensitiveCompare(namespaced) == .orderedSame
        }
    }

    private static func normalizedPath(_ raw: String) -> String? {
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, path.utf8.count <= 1_024,
              !path.hasPrefix("/"),
              path.range(
                of: #"^[A-Za-z]:/"#,
                options: .regularExpression
              ) == nil else { return nil }
        let components = path.split(
            separator: "/", omittingEmptySubsequences: false
        )
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".."
        }) else { return nil }
        return path
    }

    /// The supported object lane is flat: only a direct image String field,
    /// with arbitrary VM expressions in other fields. No expression evaluation.
    private static func literalPaths(
        _ tokens: [SceneLaunchOriginTransitionToken], argument: Int
    ) -> [String] {
        if let value = tokens[argument].stringValue,
           argument + 1 < tokens.count, tokens[argument + 1] == .symbol(")") { return [value] }
        guard tokens[argument] == .symbol("{") else { return [] }
        var fields: [String] = []
        var parentheses = 0
        var brackets = 0
        for index in (argument + 1)..<tokens.count {
            let token = tokens[index]
            if token == .symbol("{") { return [] }
            if token == .symbol("}") {
                return index + 1 < tokens.count && tokens[index + 1] == .symbol(")") ? fields : []
            }
            if parentheses == 0 && brackets == 0,
               index == argument + 1 || tokens[index - 1] == .symbol(","),
               (token.identifierValue ?? token.stringValue) == "image",
               index + 3 < tokens.count, tokens[index + 1] == .symbol(":"),
               let path = tokens[index + 2].stringValue,
               [SceneLaunchOriginTransitionToken.symbol(","), .symbol("}")].contains(tokens[index + 3]) {
                fields.append(path)
            }
            if token == .symbol("(") { parentheses += 1 }
            if token == .symbol(")") { parentheses -= 1 }
            if token == .symbol("[") { brackets += 1 }
            if token == .symbol("]") { brackets -= 1 }
        }
        return []
    }
}
