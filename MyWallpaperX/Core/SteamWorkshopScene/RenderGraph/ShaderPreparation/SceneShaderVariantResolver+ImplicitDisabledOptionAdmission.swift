import Foundation

nonisolated enum SceneShaderImplicitDisabledOptionAdmission {
    static func admittedCombos(
        in schemaSources: [SceneShaderVariantSchemaSource]
    ) -> Set<String> {
        var sourceByPath: [String: String] = [:]
        for schemaSource in schemaSources {
            guard let source = schemaSource.source else { return [] }
            let path = schemaSource.relativePath.lowercased()
            if let existing = sourceByPath[path], existing != source {
                return []
            }
            sourceByPath[path] = source
        }

        var declarationsByCombo: [String: [Declaration]] = [:]
        for path in sourceByPath.keys.sorted() {
            guard let source = sourceByPath[path] else { continue }
            let parsed = SceneShaderContractSourceParser().parse(
                source,
                stageRelativePath: path
            )
            guard parsed.diagnostics.isEmpty else { return [] }
            for annotation in parsed.annotations {
                guard case let .object(object) = annotation.variantValue,
                      let combo = object["combo"]?.stringValue else { continue }
                declarationsByCombo[combo, default: []].append(.init(
                    path: path,
                    annotation: annotation,
                    object: object
                ))
            }
        }

        return Set(declarationsByCombo.compactMap { combo, declarations in
            guard declarations.count == 1,
                  let declaration = declarations.first,
                  declaration.annotation.marker == "[COMBO]",
                  declaration.object["type"]?.stringValue == "options",
                  declaration.object.keys.allSatisfy({
                      ["combo", "type", "material"].contains($0)
                  }),
                  declaration.object["material"] == nil
                    || declaration.object["material"]?.stringValue != nil,
                  structurallyDisablesWhenUndefined(
                      combo,
                      declaration: declaration,
                      sourceByPath: sourceByPath
                  ) else { return nil }
            return combo
        })
    }

    private static func structurallyDisablesWhenUndefined(
        _ combo: String,
        declaration: Declaration,
        sourceByPath: [String: String]
    ) -> Bool {
        var directUseCount = 0
        for path in sourceByPath.keys.sorted() {
            guard let source = sourceByPath[path] else { return false }
            var conditionalStack: [ConditionalFrame] = []
            var inBlockComment = false
            let lines = source.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0.isNewline }
            )
            for (offset, substring) in lines.enumerated() {
                let lineNumber = offset + 1
                let lexical = SceneShaderLexicalScanner.scan(
                    String(substring),
                    inBlockComment: &inBlockComment
                )
                let code = lexical.code
                let usesCombo = identifiers(in: code).contains(combo)

                if path == declaration.path,
                   lineNumber == declaration.annotation.line {
                    guard conditionalStack.isEmpty,
                          code.trimmingCharacters(in: .whitespaces).isEmpty else {
                        return false
                    }
                }

                guard let directive = SceneShaderDirective.parse(code) else {
                    if usesCombo { return false }
                    if code.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                        return false
                    }
                    continue
                }

                if usesCombo {
                    guard case let .ifExpression(expression) = directive,
                          expression.trimmingCharacters(in: .whitespaces) == combo else {
                        return false
                    }
                    directUseCount += 1
                }

                switch directive {
                case .ifExpression, .ifdef:
                    conditionalStack.append(.init(sawElse: false))
                case .elifExpression:
                    guard !conditionalStack.isEmpty,
                          conditionalStack[conditionalStack.count - 1].sawElse == false else {
                        return false
                    }
                case .elseDirective:
                    guard !conditionalStack.isEmpty,
                          conditionalStack[conditionalStack.count - 1].sawElse == false else {
                        return false
                    }
                    conditionalStack[conditionalStack.count - 1].sawElse = true
                case .endif:
                    guard !conditionalStack.isEmpty else { return false }
                    conditionalStack.removeLast()
                case .malformedRequire, .unsupported, .unknown,
                     .unsupportedFunctionMacro, .malformed:
                    return false
                case .define, .defineFunction, .undef, .include, .require:
                    break
                }
            }
            guard !inBlockComment, conditionalStack.isEmpty else { return false }
        }
        return directUseCount > 0
    }

    private static func identifiers(in source: String) -> Set<String> {
        var result: Set<String> = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            guard character == "_" || character.isLetter else {
                index = source.index(after: index)
                continue
            }
            let start = index
            index = source.index(after: index)
            while index < source.endIndex {
                let next = source[index]
                guard next == "_" || next.isLetter || next.isNumber else { break }
                index = source.index(after: index)
            }
            result.insert(String(source[start ..< index]))
        }
        return result
    }

    private struct Declaration {
        let path: String
        let annotation: SceneShaderContract.Annotation
        let object: [String: SceneShaderAnnotationValue]
    }

    private struct ConditionalFrame {
        var sawElse: Bool
    }
}
