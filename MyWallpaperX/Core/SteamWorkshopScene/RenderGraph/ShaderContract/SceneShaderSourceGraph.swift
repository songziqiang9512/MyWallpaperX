import CryptoKit
import Foundation

nonisolated struct SceneShaderLexicalLine {
    enum SegmentKind { case code, quoted, blockComment, lineComment }
    struct Segment { let kind: SegmentKind; let text: String }

    let segments: [Segment]

    var code: String {
        segments.map { segment in
            switch segment.kind {
            case .code, .quoted: segment.text
            case .blockComment:
                String(repeating: " ", count: segment.text.count)
            case .lineComment: ""
            }
        }.joined()
    }

    var lineCommentRaw: String? {
        segments.first { $0.kind == .lineComment }?.text
    }
}

nonisolated enum SceneShaderLexicalScanner {
    static func scan(_ line: String, inBlockComment: inout Bool) -> SceneShaderLexicalLine {
        var segments: [SceneShaderLexicalLine.Segment] = []
        func append(_ kind: SceneShaderLexicalLine.SegmentKind, _ text: String) {
            guard !text.isEmpty else { return }
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = .init(kind: kind, text: last.text + text)
            } else {
                segments.append(.init(kind: kind, text: text))
            }
        }

        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(after: index)
            let pair = next < line.endIndex ? String(line[index ... next]) : ""
            if inBlockComment {
                append(.blockComment, String(line[index]))
                index = next
                if pair == "*/" {
                    append(.blockComment, "/")
                    index = line.index(after: next)
                    inBlockComment = false
                }
                continue
            }
            if pair == "//" {
                append(.lineComment, String(line[index...]))
                break
            }
            if pair == "/*" {
                append(.blockComment, "/*")
                index = line.index(after: next)
                inBlockComment = true
                continue
            }
            let character = line[index]
            if character == "\"" || character == "'" {
                let start = index
                let quote = character
                var escaped = false
                repeat {
                    let value = line[index]
                    index = line.index(after: index)
                    if escaped { escaped = false }
                    else if value == "\\" { escaped = true }
                    else if value == quote, index > line.index(after: start) { break }
                } while index < line.endIndex
                append(.quoted, String(line[start ..< index]))
                continue
            }
            append(.code, String(character))
            index = next
        }
        return .init(segments: segments)
    }
}

nonisolated enum SceneShaderContractPath {
    nonisolated static func normalizedRelativePath(
        base: String,
        path: String
    ) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !hasDrivePrefix(normalized) else { return nil }

        var components = base.split(separator: "/").map(String.init)
        for component in normalized.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".": continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default: components.append(String(component))
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    nonisolated private static func hasDrivePrefix(_ path: String) -> Bool {
        guard path.count >= 2 else { return false }
        let start = path.startIndex
        let next = path.index(after: start)
        return path[start].isLetter && path[next] == ":"
    }
}

nonisolated enum SceneShaderMetadataIdentity {
    static func annotation(
        _ value: SceneShaderContract.Annotation,
        path: String
    ) -> String {
        [path.lowercased(), String(value.line), value.raw]
            .joined(separator: "\u{1f}")
    }

    static func declaration(
        _ value: SceneShaderContract.Declaration,
        path: String
    ) -> String {
        [
            path.lowercased(), String(value.line), value.kind.rawValue,
            value.type, value.name, value.arraySuffix ?? "",
            value.arraySize.map(String.init) ?? "", value.raw,
        ].joined(separator: "\u{1f}")
    }
}

/// A deterministic, read-only snapshot of authored shader sources and includes.
/// Diagnostics are a complete census; the preprocessor decides which include
/// edges are active and therefore fatal for a particular variant.
nonisolated struct SceneShaderSourceGraph: Codable, Equatable, Sendable {
    private nonisolated struct DependencyNode: Encodable {
        let virtualPath: String
        let provenance: Provenance
        let rawSHA256: String
        let byteCount: Int
    }

    private nonisolated struct DependencyPayload: Encodable {
        let nodes: [DependencyNode]
        let edges: [Edge]
    }

    nonisolated enum Provenance: String, Codable, Equatable, Hashable, Sendable {
        case package
        case loose
        case stock
    }

    nonisolated enum ResourceFailure: String, Codable, Equatable, Sendable {
        case invalidPath
        case missing
        case symlinkEscape
        case unreadable
        case invalidUTF8
        case fileTooLarge
    }

    nonisolated struct RootRequest: Codable, Equatable, Sendable {
        let label: String
        let virtualPath: String
    }

    nonisolated struct Node: Codable, Equatable, Sendable {
        let virtualPath: String
        let provenance: Provenance
        let source: String
        let rawSHA256: String
        let byteCount: Int
    }

    nonisolated enum CandidateOutcome: Codable, Equatable, Sendable {
        case resolved(rawSHA256: String)
        case failed(ResourceFailure)
        case graphBudgetExceeded
    }

    nonisolated struct Candidate: Codable, Equatable, Sendable {
        let virtualPath: String
        let provenance: Provenance
        let outcome: CandidateOutcome
    }

    nonisolated enum Outcome: Codable, Equatable, Sendable {
        case resolved(virtualPath: String)
        case missing
        case ambiguous(virtualPaths: [String])
        case cycle(virtualPaths: [String])
        case failed(ResourceFailure)
        case graphBudgetExceeded
    }

    nonisolated struct Edge: Codable, Equatable, Sendable {
        let parentVirtualPath: String?
        let line: Int?
        let request: String
        let candidates: [Candidate]
        let outcome: Outcome
    }

    nonisolated enum DiagnosticCode: String, Codable, Equatable, Sendable {
        case missing
        case ambiguous
        case cycle
        case invalidPath
        case symlinkEscape
        case unreadable
        case invalidUTF8
        case fileTooLarge
        case graphBudgetExceeded
        /// Project-policy evidence only; selection still follows root order.
        case shadowedRootContentConflict
    }

    nonisolated struct Diagnostic: Codable, Equatable, Sendable {
        let code: DiagnosticCode
        let parentVirtualPath: String?
        let line: Int?
        let request: String
        let candidateVirtualPath: String?
    }

    let roots: [RootRequest]
    let nodes: [Node]
    let edges: [Edge]
    let diagnostics: [Diagnostic]
    let dependencySHA256: String

    nonisolated var recomputedDependencySHA256: String {
        Self.dependencySHA256(nodes: nodes, edges: edges)
    }

    nonisolated static func dependencySHA256(
        nodes: [Node],
        edges: [Edge]
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
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    nonisolated func node(at virtualPath: String) -> Node? {
        let identity = Self.identity(virtualPath)
        return nodes.first { Self.identity($0.virtualPath) == identity }
    }

    nonisolated func edge(parentVirtualPath: String, line: Int) -> Edge? {
        let identity = Self.identity(parentVirtualPath)
        return edges.first {
            $0.line == line && $0.parentVirtualPath.map(Self.identity) == identity
        }
    }

    nonisolated func provenances(at virtualPaths: [String]) -> Set<Provenance> {
        Set(virtualPaths.compactMap { node(at: $0)?.provenance })
    }

    nonisolated private static func identity(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
