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

    /// Presence combos describe an authored binding, not the resource finally
    /// supplied to an active sampler. A prepared combo-off variant without an
    /// authored candidate or graph-input alias may consume its typed asset
    /// default. Launch admission separately keeps format-combo slots closed.
    static func presenceIndependentDefault(
        template: Template,
        sampler: SceneResolvedMaterialShaderSchema.Sampler,
        slot: Int
    ) -> Template.TextureReference? {
        guard sampler.slot == slot,
              sampler.readinessCombo != nil,
              !sampler.usesGraphInputMaterialAlias,
              template.textureSlots.indices.contains(slot),
              template.textureSlots[slot] == nil,
              case let .asset(path)? = sampler.defaultTexture else {
            return nil
        }
        let reference = Template.TextureReference.asset(path)
        guard sampler.purpose(for: reference) != nil else { return nil }
        return reference
    }

    /// Projects runtime texture precedence without consulting a frame.
    static func launchReadinessProjection(
        template: Template,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> Result<LaunchReadinessProjection, Failure> {
        do {
            guard template.textureSlots.count == 8,
                  samplers.keys.allSatisfy((0 ..< 8).contains) else {
                throw launchFailure(.identityInvariant, phase: .invariant)
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
                    switch try launchAuthoredReference(
                        template: template,
                        sampler: sampler,
                        slot: index,
                        assetStates: assetStates
                    ) {
                    case .selected:
                        if sampler == nil {
                            // The candidate may be a readiness signal for a
                            // conditional declaration, but it is not required
                            // consumption until that sampler becomes active.
                            hasOptionalSource = true
                        // A readiness-combo asset may disappear between the
                        // immutable launch census and a concrete frame. Cache
                        // both combo-off and combo-on Programs even when the
                        // launch snapshot is ready; frame selection still
                        // refuses pending/unavailable instead of silently
                        // substituting the combo-off result.
                        } else if sampler?.readinessCombo != nil {
                            hasOptionalSource = true
                        } else {
                            required |= bit
                            reachesFallback = false
                        }
                    case .none:
                        break
                    case .deferred:
                        hasOptionalSource = true
                    }
                }
                if reachesFallback, let sampler {
                    switch sampler.defaultTexture {
                    case let .asset(path) where sampler.readinessCombo == nil:
                        let reference = Template.TextureReference.asset(path)
                        switch try launchAssetState(
                            reference,
                            sampler: sampler,
                            assetStates: assetStates,
                            slot: index
                        ) {
                        case .ready: required |= bit
                        case .absent: break
                        case .pending, .unavailable:
                            throw launchFailure(.textureBindingInvalid, slot: index)
                        }
                    case .internalTarget where sampler.readinessCombo == nil:
                        throw launchFailure(.textureBindingInvalid, slot: index)
                    case .asset, .internalTarget, nil:
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
                    if sampler == nil || sampler?.readinessCombo != nil {
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
        graphTextureFormatFacts: [
            Graph.TextureIdentity: SceneShaderTextureFormat
        ],
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState]
    ) -> Result<[[SceneShaderTextureFormat?]], Failure> {
        guard template.textureSlots.count == 8,
              formatSlots.allSatisfy((0 ..< 8).contains) else {
            return .failure(launchFailure(
                .identityInvariant,
                phase: .invariant
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
                let authored: LaunchAuthoredReference
                do {
                    authored = try launchAuthoredReference(
                        template: template,
                        sampler: sampler,
                        slot: slot,
                        assetStates: assetStates
                    )
                } catch let failure as Failure {
                    return .failure(failure)
                } catch {
                    return .failure(launchFailure(
                        .identityInvariant,
                        phase: .invariant,
                        slot: slot
                    ))
                }
                switch authored {
                case let .selected(reference):
                    possible.formUnion(formats(
                        for: reference,
                        sampler: sampler,
                        graphTextureFormatFacts: graphTextureFormatFacts,
                        assetFormatFacts: assetFormatFacts
                    ))
                case .deferred:
                    possible.insert(nil)
                case .none:
                    if let sampler {
                        switch sampler.defaultTexture {
                        case let .asset(path) where sampler.readinessCombo == nil:
                            possible.formUnion(formats(
                                for: .asset(path),
                                sampler: sampler,
                                graphTextureFormatFacts: graphTextureFormatFacts,
                                assetFormatFacts: assetFormatFacts
                            ))
                        case .internalTarget where sampler.readinessCombo == nil:
                            possible.insert(nil)
                        case .asset, .internalTarget, nil:
                            break
                        }
                        if sampler.usesGraphInputMaterialAlias {
                            possible.insert(nil)
                        }
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
        graphTextureFormatFacts: [
            Graph.TextureIdentity: SceneShaderTextureFormat
        ],
        assetFormatFacts: [String: Int]
    ) -> Set<SceneShaderTextureFormat?> {
        switch reference {
        case let .graph(identity):
            return [graphTextureFormatFacts[identity]]
        case let .asset(path):
            guard let sampler,
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
        case .userProperty, .provider:
            return [nil]
        }
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
