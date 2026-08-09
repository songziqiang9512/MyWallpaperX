import Foundation

/// Projects only immutable material producers into stage-qualified loop-bound
/// facts. Annotation `range` and `int` fields are intentionally not inputs.
nonisolated enum SceneResolvedMaterialRuntimeLoopBoundResolver {
    typealias Template = SceneResolvedMaterialTemplate

    static func resolve(
        template: Template,
        prepared: SceneShaderPreparedProgram
    ) -> SceneAuthoredShaderRuntimeLoopBounds {
        .init(
            vertex: bounds(template: template, source: prepared.vertex),
            fragment: bounds(template: template, source: prepared.fragment)
        )
    }

    private static func bounds(
        template: Template,
        source: SceneShaderPreparedSource
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        var conflicts: Set<String> = []
        for active in source.activeDeclarations {
            let declaration = active.declaration
            guard declaration.kind == .uniform,
                  declaration.arraySize == nil,
                  declaration.type.split(whereSeparator: \.isWhitespace).last?
                    .caseInsensitiveCompare("float") == .orderedSame,
                  let maximum = maximum(
                      template: template,
                      source: source,
                      sourcePath: active.sourcePath,
                      declaration: declaration
                  ), !conflicts.contains(declaration.name) else { continue }
            if let existing = result[declaration.name], existing != maximum {
                result.removeValue(forKey: declaration.name)
                conflicts.insert(declaration.name)
            } else {
                result[declaration.name] = maximum
            }
        }
        return result
    }

    private static func maximum(
        template: Template,
        source: SceneShaderPreparedSource,
        sourcePath: String,
        declaration: SceneShaderContract.Declaration
    ) -> Int? {
        let annotations = source.activeAnnotations.filter {
            $0.sourcePath == sourcePath && $0.annotation.line == declaration.line
                && !isCompileTime($0.annotation)
        }
        let materialValues = annotations.compactMap { active -> String? in
            guard case let .object(object) = active.annotation.variantValue,
                  let value = object["material"] else { return nil }
            return value.stringValue
        }
        let aliases = materialValues.compactMap(normalized)
        guard aliases.count == materialValues.count,
              Set(aliases).count <= 1 else { return nil }

        var keys: Set<String> = [declaration.name]
        if let alias = aliases.first { keys.insert(alias) }
        let producers = template.uniformDeclarations.filter { keys.contains($0.name) }
        guard producers.count == 1,
              case let .staticExact(value) = producers[0].value,
              value.componentBitPatterns.count == 1 else { return nil }
        let encoded = Float(Double(bitPattern: value.componentBitPatterns[0]))
        guard encoded.isFinite else { return nil }
        return Int32(exactly: Double(encoded).rounded(.towardZero)).map(Int.init)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else { return nil }
        return value
    }

    private static func isCompileTime(
        _ annotation: SceneShaderContract.Annotation
    ) -> Bool {
        if annotation.marker?.uppercased().contains("COMBO") == true { return true }
        guard case let .object(object) = annotation.variantValue else { return false }
        return object["combo"] != nil
    }
}
