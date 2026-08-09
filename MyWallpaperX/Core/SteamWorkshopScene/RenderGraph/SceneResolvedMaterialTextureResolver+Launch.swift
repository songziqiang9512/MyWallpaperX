import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
    private enum TextureFormatLaunchIssue: Error {
        case invalidSchema
    }

    struct LaunchReadinessProjection {
        let requiredMask: UInt8
        let optionalMask: UInt8

        func mask(optionalAvailability: UInt8) -> UInt8 {
            requiredMask | (optionalMask & optionalAvailability)
        }
    }

    /// Projects runtime texture precedence without consulting a frame.
    static func launchReadinessProjection(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?
    ) -> Result<LaunchReadinessProjection, Failure> {
        do {
            guard template.textureSlots.count == 8,
                  samplers.keys.allSatisfy((0 ..< 8).contains) else {
                throw launchFailure(.activeSamplerSchemaInvalid)
            }
            var required: UInt8 = 0
            var optional: UInt8 = 0
            for index in 0 ..< 8 {
                let bit = UInt8(1) << UInt8(index)
                let sampler = samplers[index]
                var reachesFallback = true
                var hasOptionalSource = false
                if let slot = template.textureSlots[index] {
                    guard slot.index == index else {
                        throw launchFailure(.identityInvariant, phase: .invariant)
                    }
                    for candidate in slot.candidates.reversed() {
                        if let sampler,
                           sampler.purpose(for: candidate.reference) == nil {
                            throw launchFailure(.texturePurposeUnproven, slot: index)
                        }
                        switch candidate.reference {
                        case .asset, .userProperty:
                            hasOptionalSource = true
                        case .provider, .graph:
                            required |= bit
                            reachesFallback = false
                        }
                        if !reachesFallback { break }
                    }
                }
                if reachesFallback, let sampler {
                    switch sampler.defaultTexture {
                    case let .asset(path):
                        let reference = Template.TextureReference.asset(path)
                        guard sampler.purpose(for: reference) != nil else {
                            throw launchFailure(.texturePurposeUnproven, slot: index)
                        }
                        required |= bit
                    case .internalTarget:
                        throw launchFailure(.textureBindingInvalid, slot: index)
                    case nil:
                        break
                    }
                    if sampler.usesGraphInputMaterialAlias,
                       let identity = implicitFramebufferIdentity {
                        guard identity.kind == .layerSource
                                || identity.kind == .effectOutput,
                              identity.name == nil,
                              sampler.purpose(for: .graph(identity)) != nil else {
                            throw launchFailure(.textureReferenceInvalid, slot: index)
                        }
                        required |= bit
                    }
                }
                if required & bit == 0, hasOptionalSource {
                    if sampler == nil {
                        optional |= bit
                    } else {
                        required |= bit
                    }
                }
            }
            for slot in SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
                template: template,
                samplers: samplers
            ) {
                guard let identity = implicitFramebufferIdentity,
                      (identity.kind == .layerSource
                          || identity.kind == .effectOutput),
                      identity.name == nil else {
                    throw launchFailure(.textureReferenceInvalid, slot: slot)
                }
                required |= UInt8(1) << UInt8(slot)
            }
            return .success(.init(
                requiredMask: required,
                optionalMask: optional
            ))
        } catch let error as Failure {
            return .failure(error)
        } catch {
            return .failure(launchFailure(.identityInvariant, phase: .invariant))
        }
    }

    static func launchTextureFormatSlots(
        template: Template
    ) throws -> Set<Int> {
        guard let graph = template.shaderContract.sourceGraph else {
            throw TextureFormatLaunchIssue.invalidSchema
        }
        var result = Set<Int>()
        for node in graph.nodes {
            let parsed = SceneShaderContractSourceParser().parse(
                node.source,
                stageRelativePath: node.virtualPath
            )
            let declarations = Dictionary(grouping: parsed.declarations, by: \.line)
            for annotation in parsed.annotations {
                guard case let .object(object) = annotation.variantValue,
                      let raw = object["formatcombo"] else { continue }
                guard let enabled = raw.boolValue else {
                    throw TextureFormatLaunchIssue.invalidSchema
                }
                guard enabled else { continue }
                let slots = declarations[annotation.line, default: []].compactMap {
                    declaration -> Int? in
                    guard declaration.kind == .uniform,
                          declaration.type.caseInsensitiveCompare("sampler2D")
                              == .orderedSame,
                          declaration.name.hasPrefix("g_Texture"),
                          let slot = Int(declaration.name.dropFirst(
                              "g_Texture".count
                          )),
                          (0 ..< 8).contains(slot) else { return nil }
                    return slot
                }
                guard slots.count == 1, let slot = slots.first else {
                    throw TextureFormatLaunchIssue.invalidSchema
                }
                result.insert(slot)
            }
        }
        return result
    }

    static func launchTextureFormatProfiles(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        readinessMask: UInt8,
        formatSlots: Set<Int>,
        assetFormatFacts: [String: Int]
    ) -> Result<[[SceneShaderTextureFormat?]], Failure> {
        guard template.textureSlots.count == 8,
              formatSlots.allSatisfy((0 ..< 8).contains) else {
            return .failure(launchFailure(
                .activeSamplerSchemaInvalid,
                phase: .preparation
            ))
        }
        var profiles = [Array<SceneShaderTextureFormat?>(
            repeating: nil,
            count: 8
        )]
        for slot in formatSlots.sorted() {
            let isReady = readinessMask & (UInt8(1) << UInt8(slot)) != 0
            let options: [SceneShaderTextureFormat?]
            if !isReady {
                options = [nil]
            } else {
                var possible = Set<SceneShaderTextureFormat?>()
                let sampler = samplers[slot]
                if let textureSlot = template.textureSlots[slot] {
                    for candidate in textureSlot.candidates {
                        possible.formUnion(formats(
                            for: candidate.reference,
                            sampler: sampler,
                            assetFormatFacts: assetFormatFacts
                        ))
                    }
                }
                if let sampler {
                    switch sampler.defaultTexture {
                    case let .asset(path):
                        possible.formUnion(formats(
                            for: .asset(path),
                            sampler: sampler,
                            assetFormatFacts: assetFormatFacts
                        ))
                    case .internalTarget:
                        possible.insert(nil)
                    case nil:
                        break
                    }
                    if sampler.usesGraphInputMaterialAlias {
                        possible.insert(nil)
                    }
                }
                if possible.isEmpty { possible.insert(nil) }
                options = possible.sorted(by: less)
            }
            var expanded: [[SceneShaderTextureFormat?]] = []
            for profile in profiles {
                for option in options {
                    var next = profile
                    next[slot] = option
                    expanded.append(next)
                    guard expanded.count <= 256 else {
                        return .failure(launchFailure(
                            .shaderPreparationFailed,
                            phase: .preparation
                        ))
                    }
                }
            }
            profiles = expanded
        }
        return .success(profiles)
    }

    static func exhaustiveLaunchTextureFormatProfiles(
        template: Template,
        maximumProfileCount: Int = 256
    ) throws -> [[Int: SceneShaderTextureFormat]] {
        guard (1 ... 256).contains(maximumProfileCount) else {
            throw TextureFormatLaunchIssue.invalidSchema
        }
        let slots = try launchTextureFormatSlots(template: template).sorted()
        var profiles: [[Int: SceneShaderTextureFormat]] = [[:]]
        for slot in slots {
            var expanded: [[Int: SceneShaderTextureFormat]] = []
            for profile in profiles {
                for format in SceneShaderTextureFormat.allCases {
                    var next = profile
                    next[slot] = format
                    expanded.append(next)
                    guard expanded.count <= maximumProfileCount else {
                        throw TextureFormatLaunchIssue.invalidSchema
                    }
                }
            }
            profiles = expanded
        }
        return profiles
    }

    private static func formats(
        for reference: Template.TextureReference,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?,
        assetFormatFacts: [String: Int]
    ) -> Set<SceneShaderTextureFormat?> {
        guard case let .asset(path) = reference,
              let sampler,
              let purpose = sampler.purpose(for: reference) else { return [nil] }
        let identity = SceneAssetTextureIdentity(path: path, purpose: purpose)
        guard let value = assetFormatFacts[identity.reportToken] else {
            return [nil]
        }
        if value == -1 { return [] }
        guard let rawValue = UInt32(exactly: value),
              let format = SceneShaderTextureFormat(rawValue: rawValue) else {
            return [nil]
        }
        return [format]
    }

    private static func less(
        _ lhs: SceneShaderTextureFormat?,
        _ rhs: SceneShaderTextureFormat?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): false
        case (nil, _): true
        case (_, nil): false
        case let (lhs?, rhs?): lhs.rawValue < rhs.rawValue
        }
    }

    private static func launchFailure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: [])
    }
}
