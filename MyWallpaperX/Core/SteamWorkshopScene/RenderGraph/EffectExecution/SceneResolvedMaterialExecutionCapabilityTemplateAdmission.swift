import Foundation

/// Validates that a catalog template is the exact immutable template owned by
/// an admitted graph node before capability publication.
nonisolated enum SceneResolvedMaterialExecutionCapabilityTemplateAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Key = SceneResolvedMaterialRuntimeCatalog.Key
    typealias Template = SceneResolvedMaterialTemplate

    static func resolve(
        node: Graph.Node,
        effect: Graph.Effect,
        key: Key,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssueKeys: Set<Key>,
        existingKeys: Set<Key>
    ) -> Template? {
        guard !demandIssueKeys.contains(key) else {
            diagnose(node, reason: "resource-demand")
            return nil
        }
        guard let entry = materialCatalog.entry(for: node) else {
            diagnose(node, reason: "catalog-missing")
            return nil
        }
        guard case let .template(template) = entry else {
            if case let .failure(failure) = entry {
                diagnose(node, reason: "catalog-failure", failure: failure)
            }
            return nil
        }
        guard exactTemplate(template, node: node, effect: effect) else {
            diagnose(node, reason: "identity-mismatch")
            return nil
        }
        guard template.renderState.matchesFullscreenOverwrite(
            alphaWriting: .unspecified
        ) else {
            diagnose(node, reason: "render-state")
            return nil
        }
        guard !existingKeys.contains(key) else {
            diagnose(node, reason: "duplicate-key")
            return nil
        }
        return template
    }

    private static func exactTemplate(
        _ template: Template,
        node: Graph.Node,
        effect: Graph.Effect
    ) -> Bool {
        guard template.diagnosticProvenance.nodeIndex == node.nodeIndex,
              let input = Template.GraphTextureRole(
                  rawValue: effect.input.kind.rawValue
              ), let output = Template.GraphTextureRole(
                  rawValue: effect.output.kind.rawValue
              ), let targetKind = node.target?.kind,
              let target = Template.GraphTextureRole(
                  rawValue: targetKind.rawValue
              ) else { return false }
        let roles = node.bindings.compactMap { binding -> Template.GraphBindingRole? in
            guard let slot = binding.slot,
                  let texture = Template.GraphTextureRole(
                      rawValue: binding.texture.kind.rawValue
                  ) else { return nil }
            return .init(slot: slot, texture: texture)
        }
        guard roles.count == node.bindings.count,
              template.graphRole == .init(
                  effectInput: input,
                  effectOutput: output,
                  nodeTarget: target,
                  bindings: roles
              ) else { return false }
        let admittedBindings = Dictionary(grouping: node.bindings, by: \.slot)
        for index in template.textureSlots.indices {
            let graphReferences = template.textureSlots[index]?.candidates.compactMap {
                candidate -> Graph.TextureIdentity? in
                guard case let .graph(identity) = candidate.reference else { return nil }
                return identity
            } ?? []
            let expected = (admittedBindings[index] ?? []).map(\.texture)
            guard graphReferences == expected else { return false }
        }
        return true
    }

    private static func diagnose(
        _ node: Graph.Node,
        reason: String,
        failure: SceneResolvedMaterialFailure? = nil
    ) {
        SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
            .materialTemplateFailure(
                node: node,
                reason: reason,
                failure: failure
            )
    }
}
