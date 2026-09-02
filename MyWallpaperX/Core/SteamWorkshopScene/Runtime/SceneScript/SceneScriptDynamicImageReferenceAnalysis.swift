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
        guard source.utf8.count <= 65_536 else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        let invocations = createLayerInvocation.matches(
            in: source, range: range
        )
        guard !invocations.isEmpty else { return nil }
        let directLiterals = createLayerLiteral.matches(in: source, range: range)
        let configuredLiterals = createLayerConfigurationLiteral.matches(
            in: source, range: range
        )
        let literals = (directLiterals.map { ($0, 2) }
            + configuredLiterals.map { ($0, 2) })
            .sorted { $0.0.range.location < $1.0.range.location }
        guard literals.count == invocations.count else { return nil }
        let workshopID = firstCapture(
            from: workshopIdentity.firstMatch(in: source, range: range),
            in: source,
            index: 1
        )
        let available = descriptor.modelMaterialLinks.map(\.modelPath)
        var references: [SceneScriptDynamicImageReference] = []
        var seen: Set<String> = []
        for (match, captureIndex) in literals {
            guard let authored = firstCapture(
                from: match, in: source, index: captureIndex
            ), let normalized = normalizedPath(authored),
                  let resolved = resolvedModelPath(
                    normalized,
                    workshopID: workshopID,
                    available: available
                  ) else { return nil }
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

    private static func firstCapture(
        from match: NSTextCheckingResult?,
        in source: String,
        index: Int
    ) -> String? {
        guard let match, index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }

    private static let createLayerInvocation = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_$])thisScene\s*\.\s*createLayer\s*\("#
    )
    private static let createLayerLiteral = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_$])thisScene\s*\.\s*createLayer\s*\(\s*(['\"])([^'\"\\\r\n]{1,1024})\1\s*\)"#
    )
    /// A bounded object-form request remains resource-driven: the `image`
    /// field must be a direct package-local literal so launch can prepare the
    /// immutable model before the callback runs. Runtime fields such as
    /// transform, tint, and visibility continue to be evaluated by QuickJS.
    private static let createLayerConfigurationLiteral = try! NSRegularExpression(
        pattern: #"(?s)(?<![A-Za-z0-9_$])thisScene\s*\.\s*createLayer\s*\(\s*\{(?:(?!\}).)*?(?<![A-Za-z0-9_$])(?:image|['\"]image['\"])\s*:\s*(['\"])([^'\"\\\r\n]{1,1024})\1(?:(?!\}).)*?\}\s*\)"#
    )
    private static let workshopIdentity = try! NSRegularExpression(
        pattern: #"(?m)(?<![A-Za-z0-9_$])export\s+(?:let|const|var)\s+__workshopId\s*=\s*['\"]([0-9]{1,32})['\"]\s*;?"#
    )
}
