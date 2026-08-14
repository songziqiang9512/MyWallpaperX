import Foundation

/// Compiles only complete shared-initializer + master + follower launch cohorts.
/// A malformed member rejects its entire shared-flag cohort.
nonisolated enum SceneLaunchOriginTransitionProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> SceneLaunchOriginTransitionProgram {
        let exemptOriginEvidence = originEvidenceIdentities(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        )
        let initializers = initializerFacts(
            scriptSourceEvidence,
            descriptor: descriptor,
            exemptOriginEvidence: exemptOriginEvidence
        )
        guard !initializers.hasUnattributedMalformed else { return .empty }
        var candidates: [String: [Candidate]] = [:]
        var invalidFlags = initializers.invalidFlags

        for binding in scriptBindings where isObjectOrigin(binding) {
            guard let syntax = SceneLaunchOriginTransitionSyntax.parse(binding.source) else {
                if hasTransitionPropertySignature(binding.properties) {
                    return .empty
                }
                continue
            }
            guard syntax.blocksLaunchCohort else { continue }
            guard let candidate = project(
                binding,
                syntax: syntax,
                descriptor: descriptor
            ) else {
                invalidFlags.insert(syntax.sharedFlag)
                continue
            }
            candidates[syntax.sharedFlag, default: []].append(candidate)
        }

        var cohorts: [SceneLaunchOriginTransitionCohort] = []
        for flag in candidates.keys.sorted() {
            guard !invalidFlags.contains(flag),
                  initializers.values[flag] == [false],
                  let group = candidates[flag] else {
                continue
            }
            let masters = group.filter { $0.binding.role == .master }
            guard masters.count == 1,
                  group.contains(where: { $0.binding.role == .follower }),
                  Set(group.map(\.binding.definition.target)).count == group.count else {
                continue
            }
            cohorts.append(SceneLaunchOriginTransitionCohort(
                sharedFlag: flag,
                masterTarget: masters[0].binding.definition.target,
                bindings: group.sorted(by: candidateOrder).map(\.binding)
            ))
        }
        return SceneLaunchOriginTransitionProgram.validated(cohorts: cohorts) ?? .empty
    }

    private struct Candidate {
        let objectIndex: Int
        let binding: SceneLaunchOriginTransitionBinding
    }

    private struct InitializerFacts {
        var values: [String: [Bool]] = [:]
        var invalidFlags: Set<String> = []
        var hasUnattributedMalformed = false
    }

    private struct OriginEvidenceIdentity {
        let source: String
        let owner: SceneScriptBindingOwner
        let targetPath: [SceneScriptBindingPathComponent]
        let wrapperKeys: [String]

        func matches(_ evidence: SceneScriptSourceEvidenceIR) -> Bool {
            source == evidence.source && owner == evidence.owner
                && targetPath == evidence.targetPath
                && wrapperKeys == evidence.wrapperKeys
        }
    }

    private static func initializerFacts(
        _ evidence: [SceneScriptSourceEvidenceIR],
        descriptor: SceneRenderDescriptor,
        exemptOriginEvidence: [OriginEvidenceIdentity]
    ) -> InitializerFacts {
        var result = InitializerFacts()
        for item in evidence {
            if exemptOriginEvidence.contains(where: { $0.matches(item) }) { continue }
            let hasExactIdentity = isExactInitializerCandidate(
                item,
                descriptor: descriptor
            )
            let parsed = SceneLaunchOriginTransitionSyntax.parseSharedInitializer(
                item.source
            )
            guard let parsed else {
                switch SceneLaunchOriginTransitionConflictScanner.scan(item.source) {
                case let .flags(flags):
                    result.invalidFlags.formUnion(flags)
                case .reject:
                    result.hasUnattributedMalformed = true
                }
                continue
            }
            guard hasExactIdentity else {
                result.invalidFlags.formUnion(parsed.keys)
                continue
            }
            for (flag, value) in parsed {
                result.values[flag, default: []].append(value)
            }
        }
        return result
    }

    private static func originEvidenceIdentities(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> [OriginEvidenceIdentity] {
        scriptBindings.compactMap { binding in
            guard isObjectOrigin(binding),
                  let syntax = SceneLaunchOriginTransitionSyntax.parse(binding.source),
                  project(binding, syntax: syntax, descriptor: descriptor) != nil
                    || isExactInactiveOriginIdentity(
                        binding,
                        syntax: syntax,
                        descriptor: descriptor
                    ),
                  let wrapperKeys = binding.wrapperKeys else { return nil }
            return OriginEvidenceIdentity(
                source: binding.source,
                owner: binding.owner,
                targetPath: binding.targetPath,
                wrapperKeys: wrapperKeys
            )
        }
    }

    private static func isExactInactiveOriginIdentity(
        _ source: SceneScriptBindingIR,
        syntax: SceneLaunchOriginTransitionSyntax.Profile,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard !syntax.blocksLaunchCohort,
              source.wrapperKeys == ["script", "scriptproperties", "value"],
              source.valueType == .string,
              let authoredSource = source.authoredValue?.stringValue,
              let authored = vector3(authoredSource),
              let objectIndex = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].origin == authoredSource,
              let descriptorOrigin = descriptor.layers[objectIndex].originXYZ,
              descriptorOrigin.count == 3,
              sameBits(authored, descriptorOrigin),
              source.targetPath == objectPath(index: objectIndex, key: "origin"),
              source.properties.keys.sorted() == syntax.propertyNames.sorted() else {
            return false
        }
        return true
    }

    private static func isExactInitializerCandidate(
        _ evidence: SceneScriptSourceEvidenceIR,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard evidence.owner.kind == .object,
              evidence.wrapperKeys == ["script", "value"],
              let objectIndex = evidence.owner.objectIndex,
              let layerID = evidence.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].visible == true,
              evidence.targetPath == objectPath(index: objectIndex, key: "visible") else {
            return false
        }
        return true
    }

    private static func project(
        _ source: SceneScriptBindingIR,
        syntax: SceneLaunchOriginTransitionSyntax.Profile,
        descriptor: SceneRenderDescriptor
    ) -> Candidate? {
        guard source.wrapperKeys == ["script", "scriptproperties", "value"],
              source.valueType == .string,
              let authoredSource = source.authoredValue?.stringValue,
              let authored = vector3(authoredSource),
              let objectIndex = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].origin == authoredSource,
              let descriptorOrigin = descriptor.layers[objectIndex].originXYZ,
              descriptorOrigin.count == 3,
              sameBits(authored, descriptorOrigin),
              source.targetPath == objectPath(index: objectIndex, key: "origin"),
              source.properties.keys.sorted() == syntax.propertyNames.sorted(),
              let base = vectorInput(
                  source.properties,
                  names: syntax.basePropertyNames
              ),
              let endpoint = vectorInput(
                  source.properties,
                  names: syntax.endpointPropertyNames
              ),
              let speed = scalarInput(source.properties[syntax.speedPropertyName]),
              speed.fallback >= 0,
              speed.fallback <= syntax.speedDivisor else {
            return nil
        }
        let target = SceneDynamicTarget.layer(layerID: layerID, field: .origin)
        let role: SceneLaunchOriginTransitionBinding.Role = syntax.isMaster
            ? .master : .follower
        return Candidate(
            objectIndex: objectIndex,
            binding: SceneLaunchOriginTransitionBinding(
                definition: SceneDynamicTargetDefinition(
                    target: target,
                    valueType: .vector3,
                    authoredValue: .vector3(authored.x, authored.y, authored.z)
                ),
                role: role,
                plan: SceneLaunchOriginTransitionPlan(
                    authoredOrigin: authored,
                    base: base,
                    endpoint: endpoint,
                    speed: speed,
                    speedDivisor: syntax.speedDivisor,
                    triggerPropertyKey: syntax.triggerPropertyKey,
                    initialFalseTarget: syntax.initialFalseUsesEndpoint
                        ? .endpoint : .base(offset: syntax.baseOffset)
                )
            )
        )
    }

    private static func vectorInput(
        _ properties: [String: SceneJSONValue],
        names: [String]
    ) -> SceneLaunchOriginTransitionVectorInput? {
        guard names.count == 3,
              let x = scalarInput(properties[names[0]]),
              let y = scalarInput(properties[names[1]]),
              let z = scalarInput(properties[names[2]]) else { return nil }
        return .init(x: x, y: y, z: z)
    }

    private static func scalarInput(
        _ value: SceneJSONValue?
    ) -> SceneLaunchOriginTransitionScalarInput? {
        switch value {
        case let .number(number) where number.isFinite:
            return .init(fallback: number, userPropertyKey: nil)
        case let .object(wrapper):
            guard wrapper.keys.sorted() == ["user", "value"],
                  case let .string(key)? = wrapper["user"],
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  case let .number(number)? = wrapper["value"],
                  number.isFinite else { return nil }
            return .init(fallback: number, userPropertyKey: key)
        default:
            return nil
        }
    }

    private static func hasTransitionPropertySignature(
        _ properties: [String: SceneJSONValue]
    ) -> Bool {
        let expected = Set([
            "aX", "aY", "aZ", "positionX", "positionY", "positionZ", "speed",
        ])
        return expected.isSubset(of: Set(properties.keys))
    }

    private static func vector3(_ source: String) -> SIMD3<Double>? {
        let parts = source.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    private static func sameBits(
        _ authored: SIMD3<Double>,
        _ descriptor: [Float]
    ) -> Bool {
        Float(authored.x).bitPattern == descriptor[0].bitPattern
            && Float(authored.y).bitPattern == descriptor[1].bitPattern
            && Float(authored.z).bitPattern == descriptor[2].bitPattern
    }

    private static func isObjectOrigin(_ binding: SceneScriptBindingIR) -> Bool {
        binding.owner.kind == .object && binding.targetKey == "origin"
    }

    private static func objectPath(
        index: Int,
        key: String
    ) -> [SceneScriptBindingPathComponent] {
        [.key("objects"), .index(index), .key(key)]
    }

    private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.binding.role != rhs.binding.role { return lhs.binding.role == .master }
        return lhs.objectIndex < rhs.objectIndex
    }
}
