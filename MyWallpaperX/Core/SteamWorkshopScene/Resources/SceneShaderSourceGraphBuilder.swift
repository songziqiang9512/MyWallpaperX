import CryptoKit
import Foundation

/// Builds the pure source-graph IR from the concrete Scene virtual filesystem.
nonisolated struct SceneShaderSourceGraphBuilder {
    nonisolated struct Limits: Equatable, Sendable {
        let maximumFileBytes: Int
        let maximumTotalBytes: Int
        let maximumNodes: Int
        let maximumIncludeDepth: Int

        nonisolated init(
            maximumFileBytes: Int = 512 * 1_024,
            maximumTotalBytes: Int = 8 * 1_024 * 1_024,
            maximumNodes: Int = 256,
            maximumIncludeDepth: Int = 64
        ) {
            self.maximumFileBytes = max(0, maximumFileBytes)
            self.maximumTotalBytes = max(0, maximumTotalBytes)
            self.maximumNodes = max(0, maximumNodes)
            self.maximumIncludeDepth = max(0, maximumIncludeDepth)
        }
    }

    private nonisolated struct DependencyNode: Encodable {
        let virtualPath: String
        let provenance: SceneShaderSourceGraph.Provenance
        let rawSHA256: String
        let byteCount: Int
    }

    private nonisolated struct DependencyPayload: Encodable {
        let nodes: [DependencyNode]
        let edges: [SceneShaderSourceGraph.Edge]
    }

    private nonisolated struct State {
        typealias File = SceneShaderSourceResolver.ResolvedFile
        typealias Resolution = SceneShaderSourceResolver.Resolution
        typealias ResolutionSet = SceneShaderSourceResolver.ResolutionSet

        let limits: Limits
        let resolver: SceneShaderSourceResolver
        let resourceView: SceneResourceView
        var nodesByIdentity: [String: SceneShaderSourceGraph.Node] = [:]
        var edges: [SceneShaderSourceGraph.Edge] = []
        var completed: Set<String> = []
        var stack: [String] = []
        var totalBytes = 0

        mutating func loadRoot(_ root: SceneShaderSourceGraph.RootRequest) {
            let request = safeRootRequest(root.virtualPath)
            let resolutionSet = resolve(root.virtualPath)
            let resolution = resolutionSet.selected
            let candidatePath = request
            var outcome = outcome(for: resolution)
            var selected: File?
            if case let .resolved(file) = resolution {
                if admit(file) {
                    selected = file
                } else {
                    outcome = .graphBudgetExceeded
                }
            }
            edges.append(edge(
                parent: nil,
                line: nil,
                request: request,
                candidates: candidates(path: candidatePath, set: resolutionSet),
                outcome: outcome
            ))
            if let selected { visit(selected, depth: 0) }
        }

        mutating func visit(_ file: File, depth: Int) {
            let identity = SceneShaderSourceResolver.identity(file.virtualPath)
            guard !completed.contains(identity) else { return }
            stack.append(file.virtualPath)
            defer {
                stack.removeLast()
                completed.insert(identity)
            }

            let includes = SceneShaderContractSourceParser().parse(
                file.source,
                stageRelativePath: file.virtualPath
            ).includes
            for include in includes {
                let result = resolveInclude(
                    request: include.relativePath,
                    parent: file.virtualPath,
                    line: include.line,
                    depth: depth
                )
                edges.append(result.edge)
                if let selected = result.selected {
                    visit(selected, depth: depth + 1)
                }
            }
        }

        mutating func resolveInclude(
            request: String,
            parent: String,
            line: Int,
            depth: Int
        ) -> (edge: SceneShaderSourceGraph.Edge, selected: File?) {
            guard case let .paths(paths) = resolver.includeCandidatePaths(
                request: request,
                parentVirtualPath: parent
            ) else {
                return (edge(
                    parent: parent,
                    line: line,
                    request: "<invalid-path>",
                    candidates: [],
                    outcome: .failed(.invalidPath)
                ), nil)
            }
            guard depth < limits.maximumIncludeDepth else {
                let candidates = paths.flatMap { path in
                    resourceView.roots.map { root in
                        SceneShaderSourceGraph.Candidate(
                            virtualPath: path,
                            provenance: SceneShaderSourceResolver.provenance(root.source),
                            outcome: .graphBudgetExceeded
                        )
                    }
                }
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidates,
                    outcome: .graphBudgetExceeded
                ), nil)
            }

            let resolutionSets = paths.map(resolve)
            let candidateEvidence = zip(paths, resolutionSets).flatMap {
                candidates(path: $0.0, set: $0.1)
            }
            let resolutions = resolutionSets.map(\.selected)
            let resolved = resolutions.compactMap { resolution -> File? in
                guard case let .resolved(file) = resolution else { return nil }
                return file
            }
            let hardFailure = resolutions.compactMap {
                resolution -> SceneShaderSourceGraph.ResourceFailure? in
                guard case let .failed(failure) = resolution, failure != .missing else {
                    return nil
                }
                return failure
            }.first
            if let hardFailure {
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidateEvidence,
                    outcome: .failed(hardFailure)
                ), nil)
            }
            guard let selected = resolved.first else {
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidateEvidence,
                    outcome: .missing
                ), nil)
            }
            if resolved.contains(where: { $0.rawSHA256 != selected.rawSHA256 }) {
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidateEvidence,
                    outcome: .ambiguous(virtualPaths: resolved.map(\.virtualPath))
                ), nil)
            }
            if let cycle = cyclePath(to: selected.virtualPath) {
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidateEvidence,
                    outcome: .cycle(virtualPaths: cycle)
                ), nil)
            }
            guard admit(selected) else {
                return (edge(
                    parent: parent,
                    line: line,
                    request: request,
                    candidates: candidateEvidence,
                    outcome: .graphBudgetExceeded
                ), nil)
            }
            return (edge(
                parent: parent,
                line: line,
                request: request,
                candidates: candidateEvidence,
                outcome: .resolved(virtualPath: selected.virtualPath)
            ), selected)
        }

        mutating func admit(_ file: File) -> Bool {
            let identity = SceneShaderSourceResolver.identity(file.virtualPath)
            if nodesByIdentity[identity] != nil { return true }
            guard nodesByIdentity.count < limits.maximumNodes,
                  file.byteCount <= limits.maximumTotalBytes - totalBytes else {
                return false
            }
            nodesByIdentity[identity] = .init(
                virtualPath: file.virtualPath,
                provenance: file.provenance,
                source: file.source,
                rawSHA256: file.rawSHA256,
                byteCount: file.byteCount
            )
            totalBytes += file.byteCount
            return true
        }

        func resolve(_ path: String) -> ResolutionSet {
            resolver.resolveWithEvidence(
                virtualPath: path,
                resourceView: resourceView,
                maximumBytes: limits.maximumFileBytes
            )
        }

        func cyclePath(to path: String) -> [String]? {
            let identity = SceneShaderSourceResolver.identity(path)
            guard let index = stack.firstIndex(where: {
                SceneShaderSourceResolver.identity($0) == identity
            }) else { return nil }
            return Array(stack[index...]) + [path]
        }

        func candidates(
            path: String,
            set: ResolutionSet
        ) -> [SceneShaderSourceGraph.Candidate] {
            set.candidates.map { candidate in
                let outcome: SceneShaderSourceGraph.CandidateOutcome
                switch candidate.resolution {
                case let .resolved(file): outcome = .resolved(rawSHA256: file.rawSHA256)
                case let .failed(failure): outcome = .failed(failure)
                }
                return .init(
                    virtualPath: path,
                    provenance: candidate.provenance,
                    outcome: outcome
                )
            }
        }

        func outcome(for resolution: Resolution) -> SceneShaderSourceGraph.Outcome {
            switch resolution {
            case let .resolved(file): return .resolved(virtualPath: file.virtualPath)
            case .failed(.missing): return .missing
            case let .failed(failure): return .failed(failure)
            }
        }

        func safeRootRequest(_ request: String) -> String {
            SceneShaderSourceResolver.normalizedShaderVirtualPath(request) ?? "<invalid-path>"
        }

        func edge(
            parent: String?,
            line: Int?,
            request: String,
            candidates: [SceneShaderSourceGraph.Candidate],
            outcome: SceneShaderSourceGraph.Outcome
        ) -> SceneShaderSourceGraph.Edge {
            .init(
                parentVirtualPath: parent,
                line: line,
                request: request,
                candidates: candidates,
                outcome: outcome
            )
        }
    }

    let limits: Limits

    nonisolated init(limits: Limits = .init()) {
        self.limits = limits
    }

    nonisolated func build(
        roots: [SceneShaderSourceGraph.RootRequest],
        resourceView: SceneResourceView
    ) -> SceneShaderSourceGraph {
        let roots = roots.sorted {
            ($0.virtualPath.lowercased(), $0.label)
                < ($1.virtualPath.lowercased(), $1.label)
        }
        var state = State(
            limits: limits,
            resolver: SceneShaderSourceResolver(),
            resourceView: resourceView
        )
        for root in roots { state.loadRoot(root) }
        let nodes = state.nodesByIdentity.values.sorted {
            ($0.virtualPath.lowercased(), $0.virtualPath)
                < ($1.virtualPath.lowercased(), $1.virtualPath)
        }
        let edges = state.edges.sorted(by: edgeOrder)
        let diagnostics = edges.flatMap(diagnostics)
        return .init(
            roots: roots,
            nodes: nodes,
            edges: edges,
            diagnostics: diagnostics,
            dependencySHA256: dependencyHash(nodes: nodes, edges: edges)
        )
    }

    nonisolated private func dependencyHash(
        nodes: [SceneShaderSourceGraph.Node],
        edges: [SceneShaderSourceGraph.Edge]
    ) -> String {
        let payload = DependencyPayload(
            nodes: nodes.map {
                .init(
                    virtualPath: $0.virtualPath,
                    provenance: $0.provenance,
                    rawSHA256: $0.rawSHA256,
                    byteCount: $0.byteCount
                )
            },
            edges: edges
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(payload)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private func edgeOrder(
        _ lhs: SceneShaderSourceGraph.Edge,
        _ rhs: SceneShaderSourceGraph.Edge
    ) -> Bool {
        (lhs.parentVirtualPath ?? "", lhs.line ?? 0, lhs.request)
            < (rhs.parentVirtualPath ?? "", rhs.line ?? 0, rhs.request)
    }

    nonisolated private func diagnostics(
        _ edge: SceneShaderSourceGraph.Edge
    ) -> [SceneShaderSourceGraph.Diagnostic] {
        var result: [SceneShaderSourceGraph.Diagnostic] = []
        let code: SceneShaderSourceGraph.DiagnosticCode?
        switch edge.outcome {
        case .resolved: code = nil
        case .missing: code = .missing
        case .ambiguous: code = .ambiguous
        case .cycle: code = .cycle
        case .graphBudgetExceeded: code = .graphBudgetExceeded
        case let .failed(failure):
            code = .init(rawValue: failure.rawValue) ?? .unreadable
        }
        if let code { result.append(diagnostic(code, edge: edge, path: nil)) }

        let grouped = Dictionary(grouping: edge.candidates) {
            SceneShaderSourceResolver.identity($0.virtualPath)
        }
        let conflicts = grouped.values.compactMap { candidates -> String? in
            let hashes = Set(candidates.compactMap { candidate -> String? in
                guard case let .resolved(hash) = candidate.outcome else { return nil }
                return hash
            })
            return hashes.count > 1 ? candidates.first?.virtualPath : nil
        }.sorted()
        result += conflicts.map {
            diagnostic(.shadowedRootContentConflict, edge: edge, path: $0)
        }
        return result
    }

    nonisolated private func diagnostic(
        _ code: SceneShaderSourceGraph.DiagnosticCode,
        edge: SceneShaderSourceGraph.Edge,
        path: String?
    ) -> SceneShaderSourceGraph.Diagnostic {
        .init(
            code: code,
            parentVirtualPath: edge.parentVirtualPath,
            line: edge.line,
            request: edge.request,
            candidateVirtualPath: path
        )
    }
}
