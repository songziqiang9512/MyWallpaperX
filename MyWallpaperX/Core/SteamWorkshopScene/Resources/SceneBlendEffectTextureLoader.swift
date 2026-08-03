import Metal
import simd

struct SceneBlendEffectTextures {
    struct ResolvedArguments {
        let blend: SceneTextureSlotBinding
        let uvScale: SIMD2<Float>
    }

    let blendBinding: SceneTextureSlotBinding?
    let assetPath: String
    let propertyKey: String?

    func resolvedArguments(
        for plan: SceneBlendExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(assetPath) == normalized(plan.assetTexturePath),
              propertyKey == plan.userPropertyKey,
              let blendBinding,
              let uvScale = blendBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .premultipliedColor,
                  allowedPixelFormats: [.rgba8Unorm, .bgra8Unorm]
              ) else {
            return nil
        }
        return ResolvedArguments(blend: blendBinding, uvScale: uvScale)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneBlendEffectTextureLoader {
    private struct Selection {
        let assetPath: String
        let propertyKey: String?
    }

    private struct CandidateSelection {
        let candidate: SceneTextureCandidate?
        let message: String
    }

    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ]
    ) -> (textures: [String: SceneBlendEffectTextures], message: String) {
        var textures: [String: SceneBlendEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard effect.visible != false,
                  normalized(effect.file) == definitionPath,
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.passIndex == 0,
                  let selection = selection(from: pass) else {
                continue
            }

            let assetURL = resolver.resolveTextureFile(named: selection.assetPath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: assetURL,
                label: "blend effect texture",
                purpose: .premultipliedColor,
                loader: loader,
                device: device
            )
            let selected = selectCandidate(
                propertyKey: selection.propertyKey,
                states: userPropertyTextureStates,
                authoredCandidate: loaded.candidate,
                authoredMessage: assetURL == nil
                    ? "; blend effect texture missing \(selection.assetPath)"
                    : loaded.message
            )
            guard let selectedCandidate = selected.candidate,
                  let binding = SceneTextureSlotBinding(
                slotIndex: 1,
                candidate: selectedCandidate
            ) else {
                messages.append(selected.message)
                continue
            }
            textures[effect.id] = SceneBlendEffectTextures(
                blendBinding: binding,
                assetPath: selection.assetPath,
                propertyKey: selection.propertyKey
            )
            messages.append(selected.message)
        }
        return (textures, messages.joined())
    }

    private static func selectCandidate(
        propertyKey: String?,
        states: [SceneUserPropertyTextureIdentity: SceneTextureProviderState],
        authoredCandidate: SceneTextureCandidate?,
        authoredMessage: String
    ) -> CandidateSelection {
        guard let propertyKey else {
            return .init(candidate: authoredCandidate, message: authoredMessage)
        }
        guard let identity = SceneUserPropertyTextureIdentity(
            propertyKey: propertyKey,
            purpose: .premultipliedColor
        ) else {
            return .init(
                candidate: nil,
                message: "; blend property texture invalid identity"
            )
        }
        guard let state = states[identity] else {
            return .init(
                candidate: nil,
                message: "; blend property texture missing state \(propertyKey)"
            )
        }
        switch state {
        case .absent:
            return .init(candidate: authoredCandidate, message: authoredMessage)
        case .pending:
            return .init(
                candidate: nil,
                message: "; blend property texture pending \(propertyKey)"
            )
        case .unavailable:
            return .init(
                candidate: nil,
                message: "; blend property texture unavailable \(propertyKey)"
            )
        case let .ready(publication):
            guard publication.requestIdentity == .materialUserProperty(identity),
                  publication.isComplete else {
                return .init(
                    candidate: nil,
                    message: "; blend property texture invalid publication \(propertyKey)"
                )
            }
            return .init(
                candidate: publication.candidate,
                message: "; blend property texture OK \(propertyKey)"
            )
        }
    }

    private static func selection(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Selection? {
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let assetPath = pass.textureSlots[1],
              !assetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pass.texturePaths == [assetPath] else {
            return nil
        }
        if pass.userTextureInputs.isEmpty {
            return Selection(assetPath: assetPath, propertyKey: nil)
        }
        guard pass.userTextureInputs.count == 2,
              pass.userTextureInputs[0] == nil,
              let input = pass.userTextureInputs[1],
              input.kind == .property,
              !input.value.isEmpty else {
            return nil
        }
        return Selection(assetPath: assetPath, propertyKey: input.value)
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static let definitionPath = "effects/blend/effect.json"
}
