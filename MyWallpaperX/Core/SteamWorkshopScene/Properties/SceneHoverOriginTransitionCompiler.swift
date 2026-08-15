import Foundation

/// Compiles complete initializer + hover owner + origin consumer cohorts.
/// Any unclassified writer invalidates its shared flag; malformed members never
/// become partially executable.
nonisolated enum SceneHoverOriginTransitionProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        scriptSourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> SceneHoverOriginTransitionProgram {
        var owners: [String: [OwnerCandidate]] = [:]
        var followers: [String: [FollowerCandidate]] = [:]
        var invalidFlags: Set<String> = []

        for source in scriptBindings {
            if let syntax = SceneHoverOriginTransitionSyntax.parse(source.source) {
                guard let owner = projectOwner(
                    source, sharedFlag: syntax.sharedFlag, descriptor: descriptor
                ) else {
                    invalidFlags.insert(syntax.sharedFlag)
                    continue
                }
                owners[syntax.sharedFlag, default: []].append(owner)
                continue
            }
            guard source.owner.kind == .object, source.targetKey == "origin",
                  let syntax = SceneLaunchOriginTransitionSyntax.parse(source.source),
                  !syntax.isMaster else { continue }
            guard let follower = projectFollower(
                source, syntax: syntax, descriptor: descriptor
            ) else {
                invalidFlags.insert(syntax.sharedFlag)
                continue
            }
            followers[syntax.sharedFlag, default: []].append(follower)
        }

        let initializerFacts = initializers(
            descriptor: descriptor, evidence: scriptSourceEvidence
        )
        invalidFlags.formUnion(initializerFacts.invalidFlags)
        let allowed = allowedEvidence(
            owners: owners, followers: followers,
            bindings: scriptBindings, descriptor: descriptor
        )
        let candidateFlags = Set(owners.keys).union(followers.keys)
        for evidence in scriptSourceEvidence {
            if SceneLaunchOriginTransitionSyntax.parseSharedInitializer(
                evidence.source
            ) != nil || allowed.contains(EvidenceIdentity(evidence)) {
                continue
            }
            switch SceneLaunchOriginTransitionConflictScanner.scan(evidence.source) {
            case let .flags(flags): invalidFlags.formUnion(flags)
            case .reject where evidence.source.contains("shared"):
                invalidFlags.formUnion(candidateFlags)
            case .reject: break
            }
        }

        var cohorts: [SceneHoverOriginTransitionCohort] = []
        for flag in candidateFlags.sorted() {
            guard !invalidFlags.contains(flag),
                  initializerFacts.values[flag] == [false],
                  let ownerGroup = owners[flag], ownerGroup.count == 1,
                  let followerGroup = followers[flag], !followerGroup.isEmpty,
                  Set(followerGroup.map(\.binding.definition.target)).count
                    == followerGroup.count else { continue }
            cohorts.append(.init(
                sharedFlag: flag,
                ownerLayerID: ownerGroup[0].layerID,
                bindings: followerGroup.sorted { $0.objectIndex < $1.objectIndex }
                    .map(\.binding)
            ))
        }
        guard ownersAreDisjoint(cohorts, descriptor: descriptor) else { return .empty }
        return SceneHoverOriginTransitionProgram.validated(cohorts: cohorts) ?? .empty
    }

    private struct OwnerCandidate {
        let layerID: Int
        let identity: EvidenceIdentity
    }

    private struct FollowerCandidate {
        let objectIndex: Int
        let binding: SceneHoverOriginTransitionBinding
        let identity: EvidenceIdentity
    }

    private struct InitializerFacts {
        var values: [String: [Bool]] = [:]
        var invalidFlags: Set<String> = []
    }

    private struct EvidenceIdentity: Equatable {
        let source: String
        let owner: SceneScriptBindingOwner
        let targetPath: [SceneScriptBindingPathComponent]
        let wrapperKeys: [String]

        init(_ source: SceneScriptBindingIR) {
            self.source = source.source
            owner = source.owner
            targetPath = source.targetPath
            wrapperKeys = source.wrapperKeys ?? []
        }

        init(_ source: SceneScriptSourceEvidenceIR) {
            self.source = source.source
            owner = source.owner
            targetPath = source.targetPath
            wrapperKeys = source.wrapperKeys
        }
    }

    private static func projectOwner(
        _ source: SceneScriptBindingIR,
        sharedFlag: String,
        descriptor: SceneRenderDescriptor
    ) -> OwnerCandidate? {
        guard source.owner.kind == .object, source.targetKey == "visible",
              source.wrapperKeys == ["script", "value"],
              source.valueType == .boolean, source.properties.isEmpty,
              let authored = source.authoredValue?.boolValue,
              let index = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(index) else { return nil }
        let layer = descriptor.layers[index]
        guard layer.id == layerID, layer.layerIndex == index,
              layer.visible == authored,
              source.targetPath == objectPath(index: index, key: "visible"),
              layer.contentKind == "composition",
              layer.utilityLayer?.kind == .composition,
              layer.utilityLayer?.copyBackground == false,
              layer.utilityLayer?.passthrough == false,
              layer.parentID == nil, layer.childLayerIDs.isEmpty,
              layer.effects.isEmpty, layer.effectFiles.isEmpty,
              validHitTransform(layer), sharedFlag != "__proto__" else { return nil }
        return OwnerCandidate(layerID: layerID, identity: EvidenceIdentity(source))
    }

    private static func projectFollower(
        _ source: SceneScriptBindingIR,
        syntax: SceneLaunchOriginTransitionSyntax.Profile,
        descriptor: SceneRenderDescriptor
    ) -> FollowerCandidate? {
        guard source.wrapperKeys == ["script", "scriptproperties", "value"],
              source.valueType == .string,
              let authoredSource = source.authoredValue?.stringValue,
              let authored = vector3(authoredSource),
              let index = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(index) else { return nil }
        let layer = descriptor.layers[index]
        guard layer.id == layerID, layer.layerIndex == index,
              layer.parentID == nil, layer.origin == authoredSource,
              let descriptorOrigin = layer.originXYZ, descriptorOrigin.count == 3,
              sameBits(authored, descriptorOrigin),
              source.targetPath == objectPath(index: index, key: "origin"),
              source.properties.keys.sorted() == syntax.propertyNames.sorted(),
              let base = vectorInput(
                  source.properties, names: syntax.basePropertyNames
              ), let endpoint = vectorInput(
                  source.properties, names: syntax.endpointPropertyNames
              ), let speed = scalarInput(source.properties[syntax.speedPropertyName]),
              speed.fallback >= 0, speed.fallback <= syntax.speedDivisor else {
            return nil
        }
        return FollowerCandidate(
            objectIndex: index,
            binding: .init(
                definition: .init(
                    target: .layer(layerID: layerID, field: .origin),
                    valueType: .vector3,
                    authoredValue: .vector3(authored.x, authored.y, authored.z)
                ),
                plan: .init(
                    authoredOrigin: authored, base: base, endpoint: endpoint,
                    speed: speed, speedDivisor: syntax.speedDivisor,
                    triggerPropertyKey: syntax.triggerPropertyKey,
                    baseOffset: syntax.baseOffset,
                    falseUsesEndpoint: syntax.initialFalseUsesEndpoint
                )
            ),
            identity: EvidenceIdentity(source)
        )
    }

    private static func initializers(
        descriptor: SceneRenderDescriptor,
        evidence: [SceneScriptSourceEvidenceIR]
    ) -> InitializerFacts {
        var result = InitializerFacts()
        for source in evidence {
            guard let values = SceneLaunchOriginTransitionSyntax
                .parseSharedInitializer(source.source) else { continue }
            guard isExactInitializer(source, descriptor: descriptor) else {
                result.invalidFlags.formUnion(values.keys)
                continue
            }
            for (flag, value) in values {
                result.values[flag, default: []].append(value)
            }
        }
        return result
    }

    private static func isExactInitializer(
        _ source: SceneScriptSourceEvidenceIR,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        guard source.owner.kind == .object,
              source.wrapperKeys == ["script", "value"],
              let index = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(index) else { return false }
        let layer = descriptor.layers[index]
        return layer.id == layerID && layer.layerIndex == index
            && layer.visible == true
            && source.targetPath == objectPath(index: index, key: "visible")
    }

    private static func allowedEvidence(
        owners: [String: [OwnerCandidate]],
        followers: [String: [FollowerCandidate]],
        bindings: [SceneScriptBindingIR],
        descriptor: SceneRenderDescriptor
    ) -> [EvidenceIdentity] {
        var result = owners.values.flatMap { $0 }.map(\.identity)
        result.append(contentsOf: followers.values.flatMap { $0 }.map(\.identity))
        for source in bindings where source.owner.kind == .object
        {
            let knownTransition = SceneLaunchOriginTransitionSyntax.parse(
                source.source
            ) != nil || SceneHoverOriginTransitionSyntax.parse(source.source) != nil
            let knownAlpha = source.targetKey == "alpha"
                && SceneSharedLayerAlphaSyntax.parse(source.source) != nil
            guard knownTransition || knownAlpha,
                  let index = source.owner.objectIndex,
                  let layerID = source.owner.objectID,
                  descriptor.layers.indices.contains(index),
                  descriptor.layers[index].id == layerID else { continue }
            let identity = EvidenceIdentity(source)
            if !result.contains(identity) { result.append(identity) }
        }
        return result
    }

    private static func validHitTransform(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        guard let origin = layer.originXYZ, origin.count == 3,
              let size = layer.sizeWH, size.count == 2,
              let scale = layer.scaleXYZ, scale.count == 3,
              (layer.anglesXYZ?.count ?? 3) == 3,
              (layer.parallaxDepthXY?.count ?? 2) == 2 else {
            return false
        }
        let angles = layer.anglesXYZ ?? [0, 0, 0]
        let parallax = layer.parallaxDepthXY ?? [0, 0]
        return origin.allSatisfy(\.isFinite)
            && size.allSatisfy { $0.isFinite && $0 > 0 }
            && scale.allSatisfy { $0.isFinite && $0 > 0 }
            && angles.allSatisfy { $0.bitPattern == Float(0).bitPattern }
            && parallax.allSatisfy { $0.bitPattern == Float(0).bitPattern }
    }

    private static func ownersAreDisjoint(
        _ cohorts: [SceneHoverOriginTransitionCohort],
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let boxes = cohorts.compactMap { cohort -> SIMD4<Float>? in
            guard let layer = byID[cohort.ownerLayerID],
                  let origin = layer.originXYZ, let size = layer.sizeWH,
                  let scale = layer.scaleXYZ else { return nil }
            let half = SIMD2(size[0] * scale[0], size[1] * scale[1]) * 0.5
            return SIMD4(origin[0] - half.x, origin[1] - half.y,
                         origin[0] + half.x, origin[1] + half.y)
        }
        guard boxes.count == cohorts.count else { return false }
        for left in boxes.indices {
            for right in boxes.indices where right > left {
                let a = boxes[left], b = boxes[right]
                if a.x <= b.z && b.x <= a.z && a.y <= b.w && b.y <= a.w {
                    return false
                }
            }
        }
        return true
    }

    private static func vectorInput(
        _ properties: [String: SceneJSONValue], names: [String]
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
                  case let .string(key)? = wrapper["user"], !key.isEmpty,
                  case let .number(number)? = wrapper["value"],
                  number.isFinite else { return nil }
            return .init(fallback: number, userPropertyKey: key)
        default: return nil
        }
    }

    private static func vector3(_ source: String) -> SIMD3<Double>? {
        let parts = source.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    private static func sameBits(_ value: SIMD3<Double>, _ other: [Float]) -> Bool {
        Float(value.x).bitPattern == other[0].bitPattern
            && Float(value.y).bitPattern == other[1].bitPattern
            && Float(value.z).bitPattern == other[2].bitPattern
    }

    private static func objectPath(
        index: Int, key: String
    ) -> [SceneScriptBindingPathComponent] {
        [.key("objects"), .index(index), .key(key)]
    }
}
