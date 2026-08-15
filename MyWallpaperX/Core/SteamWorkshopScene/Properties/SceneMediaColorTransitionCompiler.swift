import Foundation

/// Recognizes one bounded, statement-for-statement media color transition.
/// Unknown wrappers, properties, hooks, calls, and statement shapes fail closed.
nonisolated enum SceneMediaColorTransitionCompiler {
    nonisolated static func compile(
        value: SceneDocument.ShaderValue,
        target: SceneDynamicTarget,
        properties: [String: SceneJSONValue]
    ) -> SceneMediaColorTransitionBinding? {
        guard value.valueKind.localizedLowercase == "binding",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.bindingKeys.sorted() == ["script", "scriptproperties", "value"],
              let source = value.scriptSource,
              source.utf8.count <= 16_384,
              case .effectConstant = target,
              let outerColor = vector3(value.rawValue),
              isNormalizedColor(outerColor),
              let components = value.components,
              components.count == 3,
              components.allSatisfy(\.isFinite),
              sameBits(outerColor, SIMD3(components[0], components[1], components[2])),
              properties.keys.sorted() == ["topColor"],
              case let .object(topColor)? = properties["topColor"],
              topColor.keys.sorted() == ["user", "value"],
              case let .string(userPropertyKey)? = topColor["user"],
              !userPropertyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case let .string(propertyValue)? = topColor["value"],
              let authoredTopColor = vector3(propertyValue),
              isNormalizedColor(authoredTopColor),
              let syntax = SceneMediaColorTransitionSyntax.parse(source),
              isNormalizedColor(syntax.defaultTopColor) else {
            return nil
        }
        return SceneMediaColorTransitionBinding(
            definition: SceneDynamicTargetDefinition(
                target: target,
                valueType: .vector3,
                authoredValue: .vector3(
                    authoredTopColor.x,
                    authoredTopColor.y,
                    authoredTopColor.z
                )
            ),
            plan: SceneMediaColorTransitionPlan(
                userPropertyKey: userPropertyKey,
                authoredTopColor: authoredTopColor,
                duration: syntax.duration,
                thumbnailColorChannel: syntax.thumbnailColorChannel
            )
        )
    }

    private nonisolated static func vector3(_ source: String) -> SIMD3<Double>? {
        let spellings = source.split { character in
            character.isWhitespace || character == ","
        }
        guard spellings.count == 3 else { return nil }
        let values = spellings.compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    private nonisolated static func sameBits(
        _ lhs: SIMD3<Double>,
        _ rhs: SIMD3<Double>
    ) -> Bool {
        lhs.x.bitPattern == rhs.x.bitPattern
            && lhs.y.bitPattern == rhs.y.bitPattern
            && lhs.z.bitPattern == rhs.z.bitPattern
    }

    private nonisolated static func isNormalizedColor(
        _ value: SIMD3<Double>
    ) -> Bool {
        (0...1).contains(value.x)
            && (0...1).contains(value.y)
            && (0...1).contains(value.z)
    }
}
