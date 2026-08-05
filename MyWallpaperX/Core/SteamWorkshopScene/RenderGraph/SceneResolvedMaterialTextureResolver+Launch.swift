import Foundation

nonisolated extension SceneResolvedMaterialTextureResolver {
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
                    if sampler.materialKey?.caseInsensitiveCompare("framebuffer") == .orderedSame,
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

    private static func launchFailure(
        _ code: Failure.Code,
        phase: Failure.Phase = .texture,
        slot: Int? = nil
    ) -> Failure {
        .init(phase: phase, code: code, slot: slot, details: [])
    }
}
