import Foundation

nonisolated struct SceneUserPropertyDocumentResolver {
    nonisolated func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        resolve(root: root, effectiveValues: catalog.effectiveValues(overrides: overrides))
    }

    nonisolated func resolve(
        root: [String: Any],
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        let parser = SceneUserPropertyBindingParser()
        let report = parser.parse(root: root)
        var resolvedCount = 0
        var diagnostics = report.diagnostics
        let resolved = resolveValue(
            root,
            path: [],
            root: root,
            effectiveValues: effectiveValues,
            parser: parser,
            resolvedCount: &resolvedCount,
            diagnostics: &diagnostics
        ) as? [String: Any] ?? root
        return SceneUserPropertyResolution(
            root: resolved,
            bindingReport: report,
            diagnostics: diagnostics,
            resolvedBindingCount: resolvedCount
        )
    }

    private nonisolated func resolveValue(
        _ value: Any,
        path: [SceneUserPropertyPathComponent],
        root: [String: Any],
        effectiveValues: [String: SceneUserPropertyValue],
        parser: SceneUserPropertyBindingParser,
        resolvedCount: inout Int,
        diagnostics: inout [SceneUserPropertyBindingDiagnostic]
    ) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary {
                result[key] = resolveValue(
                    child,
                    path: path + [.key(key)],
                    root: root,
                    effectiveValues: effectiveValues,
                    parser: parser,
                    resolvedCount: &resolvedCount,
                    diagnostics: &diagnostics
                )
            }
            guard case let .success(reference?) = parser.reference(in: dictionary) else {
                return result
            }
            let propertyPath = SceneUserPropertyPath(components: path)
            let target = parser.target(for: path, root: root)
            guard let effectiveValue = effectiveValues[reference.key] else {
                diagnostics.append(.init(
                    kind: .missingEffectiveValue,
                    path: propertyPath,
                    propertyKey: reference.key,
                    message: "属性没有定义或有效覆盖值，保留 wrapper 默认值。"
                ))
                return result
            }
            if let condition = reference.condition {
                guard target.acceptsConditionalBoolean else { return result }
                result["value"] = effectiveValue.matches(condition)
            } else {
                result["value"] = effectiveValue.foundationValue
            }
            resolvedCount += 1
            return result
        }
        if let array = value as? [Any] {
            return array.enumerated().map { index, child in
                resolveValue(
                    child,
                    path: path + [.index(index)],
                    root: root,
                    effectiveValues: effectiveValues,
                    parser: parser,
                    resolvedCount: &resolvedCount,
                    diagnostics: &diagnostics
                )
            }
        }
        return value
    }
}
