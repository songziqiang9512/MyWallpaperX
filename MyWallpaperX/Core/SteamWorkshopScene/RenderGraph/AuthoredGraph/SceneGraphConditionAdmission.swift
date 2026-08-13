import Foundation

nonisolated struct SceneGraphAdmissionFailure: Error, Equatable {
    enum Code: String, Equatable {
        case invalidGraph
        case graphBlocked
        case descriptorMismatch
        case invalidComboIdentifier
        case reservedHostCombo
        case conflictingComboProviders
        case invalidCondition
        case unresolvedConditionProvider
        case prunedResourceReferenced
        case invalidCompose
        case invalidFunctionRegistry
        case unknownFunctionTarget
        case missingEffectOutput
        case digestFailure
    }

    let code: Code
    let path: String
}

/// Per-key proof supplied by the shader-schema layer. An absent key is not
/// silently zero unless that layer has ruled out annotation defaults, sampler
/// readiness and any other implicit provider for this exact identifier.
nonisolated struct SceneGraphConditionSchemaEvidence: Equatable, Sendable {
    let keysProvenZeroWhenMissing: Set<String>

    static let unavailable = Self(keysProvenZeroWhenMissing: [])

    init(keysProvenZeroWhenMissing: Set<String>) {
        self.keysProvenZeroWhenMissing = keysProvenZeroWhenMissing
    }
}

nonisolated struct SceneGraphConditionComboSnapshot: Equatable, Sendable {
    struct Provider: Equatable, Sendable {
        enum Source: String, Equatable, Sendable {
            case material
            case instance
        }

        let nodeIndex: Int
        let materialOrdinal: Int
        let source: Source
        let value: Int64
    }

    struct Binding: Equatable, Sendable {
        let name: String
        let value: Int64
        let providers: [Provider]
    }

    let bindings: [Binding]
    let implicitZeroKeys: [String]

    func value(for name: String) -> Int64? {
        if let binding = bindings.first(where: { $0.name == name }) {
            return binding.value
        }
        return implicitZeroKeys.contains(name) ? 0 : nil
    }
}

nonisolated struct SceneGraphConditionProviderSet {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private let providersByName: [String: [SceneGraphConditionComboSnapshot.Provider]]

    init(graph: Graph, descriptor: SceneRenderDescriptor) throws {
        guard graph.effects.count == 1, let effect = graph.effects.first,
              graph.layerID == effect.key.layerID,
              let layer = Self.unique(descriptor.layers.filter { $0.id == graph.layerID }),
              layer.effects.indices.contains(effect.key.effectIndex) else {
            throw Self.failure(.descriptorMismatch, "effect")
        }
        let instance = layer.effects[effect.key.effectIndex]
        guard instance.id == effect.key.descriptorID else {
            throw Self.failure(.descriptorMismatch, "effect.descriptorID")
        }

        var providersByName: [String: [SceneGraphConditionComboSnapshot.Provider]] = [:]
        for node in graph.nodes where node.kind == .material {
            guard node.effect == effect.key,
                  let ordinal = node.materialOrdinal,
                  let materialID = node.materialPassID,
                  let material = Self.unique(
                      descriptor.materialPasses.filter { $0.id == materialID }
                  ), Self.normalized(material.materialPath)
                    == Self.normalized(node.materialPath ?? "") else {
                throw Self.failure(.descriptorMismatch, "node[\(node.nodeIndex)]")
            }
            var local = material.combos
            let overriddenNames: Set<String>
            if instance.passes.isEmpty {
                guard node.instancePassIndex == nil else {
                    throw Self.failure(
                        .descriptorMismatch,
                        "node[\(node.nodeIndex)].instancePassIndex"
                    )
                }
                overriddenNames = []
            } else {
                guard instance.passes.indices.contains(ordinal) else {
                    throw Self.failure(.descriptorMismatch, "node[\(node.nodeIndex)]")
                }
                let instancePass = instance.passes[ordinal]
                guard node.instancePassIndex == instancePass.passIndex else {
                    throw Self.failure(
                        .descriptorMismatch,
                        "node[\(node.nodeIndex)].instancePassIndex"
                    )
                }
                instancePass.combos.forEach { local[$0.key] = $0.value }
                overriddenNames = Set(instancePass.combos.keys)
            }
            for name in local.keys.sorted() {
                guard let authored = local[name], let value = Int64(exactly: authored) else {
                    throw Self.failure(.descriptorMismatch, "combo.\(name).value")
                }
                providersByName[name, default: []].append(.init(
                    nodeIndex: node.nodeIndex,
                    materialOrdinal: ordinal,
                    source: overriddenNames.contains(name) ? .instance : .material,
                    value: value
                ))
            }
        }
        self.providersByName = providersByName
    }

    func binding(
        for name: String
    ) throws -> SceneGraphConditionComboSnapshot.Binding? {
        guard let candidates = providersByName[name] else { return nil }
        let providers = candidates.sorted {
            ($0.nodeIndex, $0.materialOrdinal, $0.source.rawValue)
                < ($1.nodeIndex, $1.materialOrdinal, $1.source.rawValue)
        }
        let values = Set(providers.map(\.value))
        guard values.count == 1, let value = values.first else {
            throw Self.failure(.conflictingComboProviders, "combo.\(name)")
        }
        return .init(name: name, value: value, providers: providers)
    }

    static func validateIdentifier(_ name: String, path: String) throws {
        let scalars = Array(name.unicodeScalars)
        guard let first = scalars.first,
              Self.isASCIIIdentifierHead(first),
              scalars.dropFirst().allSatisfy(Self.isASCIIIdentifierBody) else {
            throw failure(.invalidComboIdentifier, path)
        }
        guard !Self.isReservedHostIdentifier(name) else {
            throw failure(.reservedHostCombo, path)
        }
    }

    private static func isASCIIIdentifierHead(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || (65 ... 90).contains(scalar.value)
            || (97 ... 122).contains(scalar.value)
    }

    private static func isASCIIIdentifierBody(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIIdentifierHead(scalar) || (48 ... 57).contains(scalar.value)
    }

    private static func isReservedHostIdentifier(_ name: String) -> Bool {
        if ["GLSL", "HLSL", "HLSL_SM30", "HLSL_SM40", "HLSL_GS40",
            "VERSION", "SHADERVERSION", "THICKFORMAT"].contains(name) {
            return true
        }
        if name.hasPrefix("PLATFORM_") { return true }
        guard name.hasPrefix("TEX"), name.hasSuffix("FORMAT") else { return false }
        let digits = name.dropFirst(3).dropLast(6)
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func unique<T>(_ values: [T]) -> T? {
        values.count == 1 ? values[0] : nil
    }

    private static func failure(
        _ code: SceneGraphAdmissionFailure.Code,
        _ path: String
    ) -> SceneGraphAdmissionFailure {
        .init(code: code, path: path)
    }
}

nonisolated struct SceneGraphConditionEvaluator {
    private struct Clause {
        enum Comparison { case equal, ge, gt, le, lt }
        let name: String
        let expected: Int64
        let comparison: Comparison
    }

    private let providers: SceneGraphConditionProviderSet
    private let evidence: SceneGraphConditionSchemaEvidence
    private var resolvedBindings: [String: SceneGraphConditionComboSnapshot.Binding] = [:]
    private(set) var implicitZeroKeys: Set<String> = []

    init(
        providers: SceneGraphConditionProviderSet,
        evidence: SceneGraphConditionSchemaEvidence
    ) {
        self.providers = providers
        self.evidence = evidence
    }

    mutating func evaluate(_ raw: SceneJSONValue?, path: String) throws -> Bool {
        guard let raw else { return true }
        guard case .array(let elements) = raw, !elements.isEmpty else {
            throw failure(.invalidCondition, path)
        }
        var clauses: [Clause] = []
        for (index, element) in elements.enumerated() {
            guard case .object(let keyed) = element, !keyed.isEmpty else {
                throw failure(.invalidCondition, "\(path)[\(index)]")
            }
            for name in keyed.keys.sorted() {
                try SceneGraphConditionProviderSet.validateIdentifier(
                    name, path: "\(path)[\(index)].\(name)"
                )
                clauses.append(try clause(
                    name: name,
                    raw: keyed[name]!,
                    path: "\(path)[\(index)].\(name)"
                ))
            }
        }

        let resolved = try clauses.map { clause -> (Clause, Int64) in
            if let existing = resolvedBindings[clause.name] {
                return (clause, existing.value)
            }
            if let binding = try providers.binding(for: clause.name) {
                resolvedBindings[clause.name] = binding
                return (clause, binding.value)
            }
            guard evidence.keysProvenZeroWhenMissing.contains(clause.name) else {
                throw failure(.unresolvedConditionProvider, "\(path).\(clause.name)")
            }
            implicitZeroKeys.insert(clause.name)
            return (clause, 0)
        }
        return resolved.allSatisfy { clause, value in
            switch clause.comparison {
            case .equal: value == clause.expected
            case .ge: value >= clause.expected
            case .gt: value > clause.expected
            case .le: value <= clause.expected
            case .lt: value < clause.expected
            }
        }
    }

    func snapshot() -> SceneGraphConditionComboSnapshot {
        .init(
            bindings: resolvedBindings.values.sorted { $0.name < $1.name },
            implicitZeroKeys: implicitZeroKeys.sorted()
        )
    }

    private func clause(
        name: String,
        raw: SceneJSONValue,
        path: String
    ) throws -> Clause {
        if case .number(let number) = raw {
            return .init(name: name, expected: try integer(number, path), comparison: .equal)
        }
        guard case .object(let object) = raw,
              Set(object.keys) == Set(["value", "op"]),
              case .number(let number)? = object["value"],
              case .string(let operation)? = object["op"] else {
            throw failure(.invalidCondition, path)
        }
        let comparison: Clause.Comparison
        switch operation {
        case "ge": comparison = .ge
        case "gt": comparison = .gt
        case "le": comparison = .le
        case "lt": comparison = .lt
        default: throw failure(.invalidCondition, "\(path).op")
        }
        return .init(
            name: name,
            expected: try integer(number, "\(path).value"),
            comparison: comparison
        )
    }

    private func integer(_ value: Double, _ path: String) throws -> Int64 {
        let exactIntegerLimit = 9_007_199_254_740_991.0
        guard value.isFinite, abs(value) <= exactIntegerLimit,
              value.rounded(.towardZero) == value else {
            throw failure(.invalidCondition, path)
        }
        return Int64(value)
    }

    private func failure(
        _ code: SceneGraphAdmissionFailure.Code,
        _ path: String
    ) -> SceneGraphAdmissionFailure {
        .init(code: code, path: path)
    }
}
