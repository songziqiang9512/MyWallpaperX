import Foundation

/// Projects the stock no-op `visible` update hook back to its authored value.
///
/// This is deliberately not a general SceneScript evaluator. Admission requires
/// one exact object/field identity and a complete token stream containing only
/// `export function update(argument) { return argument; }`. Any additional hook,
/// statement, expression, wrapper field or owner mismatch retains script
/// ownership and therefore remains fail-closed in `SceneLayerVisibility`.
nonisolated enum SceneIdentityDisplayScriptProjection {
    nonisolated static func apply(
        to descriptor: SceneRenderDescriptor,
        sourceEvidence: [SceneScriptSourceEvidenceIR]
    ) -> SceneRenderDescriptor {
        let admittedLayerIDs = Set(sourceEvidence.compactMap { evidence in
            admittedLayerID(evidence, descriptor: descriptor)
        })
        guard !admittedLayerIDs.isEmpty else { return descriptor }

        var projected = descriptor
        for index in projected.layers.indices
            where admittedLayerIDs.contains(projected.layers[index].id)
        {
            guard let ownership = projected.layers[index].displayScriptOwnership,
                  ownership.visible else { continue }
            projected.layers[index].displayScriptOwnership =
                SceneLayerDisplayScriptOwnership(
                    visible: false,
                    alpha: ownership.alpha
                )
        }
        return projected
    }

    private nonisolated static func admittedLayerID(
        _ evidence: SceneScriptSourceEvidenceIR,
        descriptor: SceneRenderDescriptor
    ) -> Int? {
        guard evidence.owner.kind == .object,
              evidence.wrapperKeys == ["script", "user", "value"]
                || evidence.wrapperKeys == ["script", "value"],
              let objectIndex = evidence.owner.objectIndex,
              let objectID = evidence.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == objectID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].visible != nil,
              descriptor.layers[objectIndex].displayScriptOwnership?.visible == true,
              evidence.targetPath == objectPath(index: objectIndex, key: "visible"),
              isIdentityUpdate(evidence.source) else {
            return nil
        }
        return objectID
    }

    private nonisolated static func isIdentityUpdate(_ source: String) -> Bool {
        guard source.utf8.count <= 4_096,
              var tokens = SceneLaunchOriginTransitionLexer.lex(source) else {
            return false
        }
        let strictHeader: [SceneLaunchOriginTransitionToken] = [
            .string("use strict"), .symbol(";"),
        ]
        if tokens.starts(with: strictHeader) {
            tokens.removeFirst(strictHeader.count)
        }
        guard tokens.count == 11 || tokens.count == 12,
              tokens[0] == .identifier("export"),
              tokens[1] == .identifier("function"),
              tokens[2] == .identifier("update"),
              tokens[3] == .symbol("("),
              let argument = tokens[4].identifierValue,
              tokens[5] == .symbol(")"),
              tokens[6] == .symbol("{"),
              tokens[7] == .identifier("return"),
              tokens[8] == .identifier(argument),
              tokens[9] == .symbol(";"),
              tokens[10] == .symbol("}"),
              tokens.count == 11 || tokens[11] == .symbol(";") else {
            return false
        }
        return !tokens[8].lineBreakBefore
    }

    private nonisolated static func objectPath(
        index: Int,
        key: String
    ) -> [SceneScriptBindingPathComponent] {
        [.key("objects"), .index(index), .key(key)]
    }
}
