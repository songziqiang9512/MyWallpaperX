import Foundation
import simd

/// Compiles source-less direct-draw placement once from immutable Program
/// facts. The renderer only consumes this typed result; it never branches on
/// an effect, shader path, sample, layer, or hash while drawing a frame.
nonisolated enum SceneResolvedMaterialDirectDrawGeometryCompiler {
    typealias Catalog = SceneResolvedMaterialExecutionCapabilityCatalog
    typealias Contract = ScenePreparedDirectDrawOutputGeometry
    typealias Template = SceneResolvedMaterialTemplate

    private static let pointKeys = ["point0", "point1", "point2", "point3"]

    static func compile(
        materials: [Catalog.MaterialKey: Catalog.MaterialCapability]
    ) -> Contract {
        let candidates = materials.values.compactMap(
            perspectiveDirectDrawGeometry
        )
        guard candidates.count == 1, let geometry = candidates.first else {
            return .centeredHalfCanvas
        }
        return geometry
    }

    private static func perspectiveDirectDrawGeometry(
        _ material: Catalog.MaterialCapability
    ) -> Contract? {
        let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
        guard snapshot.allEntriesReady,
              !snapshot.variants.isEmpty,
              snapshot.variants.allSatisfy({ variant in
                  variant.resolvedIntegerCombos["DIRECTDRAW"] == 1
                      && variant.resolvedIntegerCombos["RAYMODE"].map {
                          (0 ... 2).contains($0)
                      } == true
                      && provesPerspectiveQuad(
                          variant,
                          pointKeys: pointKeys
                      )
              }),
              let points = staticPoints(in: material.template) else {
            return nil
        }
        return .topAlignedHalfCanvas(normalizedPerspectivePoints: points)
    }

    private static func staticPoints(
        in template: Template
    ) -> [SIMD2<Float>]? {
        var result: [SIMD2<Float>] = []
        for key in pointKeys {
            let declarations = template.uniformDeclarations.filter {
                $0.name.caseInsensitiveCompare(key) == .orderedSame
            }
            guard declarations.count == 1,
                  let declaration = declarations.first,
                  case let .staticExact(value) = declaration.value,
                  value.componentBitPatterns.count == 2 else {
                return nil
            }
            let components = value.componentBitPatterns.map {
                Float(Double(bitPattern: $0))
            }
            guard components.allSatisfy(\.isFinite) else {
                return nil
            }
            result.append(SIMD2(components[0], components[1]))
        }
        return result
    }

    private static func provesPerspectiveQuad(
        _ variant: SceneResolvedMaterialCompiledVariant,
        pointKeys: [String]
    ) -> Bool {
        let uniformNames = pointKeys.compactMap { key -> String? in
            let matches = variant.activeUniforms.values.filter { uniform in
                uniform.materialKeys.contains {
                    $0.caseInsensitiveCompare(key) == .orderedSame
                }
            }
            guard matches.count == 1 else { return nil }
            return matches[0].name
        }
        guard uniformNames.count == pointKeys.count else { return false }
        let lexical = SceneAuthoredShaderLexer.lex(
            source: variant.preparedShader.vertex.source,
            stage: .vertex
        )
        guard lexical.diagnostics.isEmpty else { return false }
        let expected = ["inverse", "(", "squareToQuad", "("]
            + Array(uniformNames.enumerated()).flatMap { index, name in
                index + 1 == uniformNames.count ? [name] : [name, ","]
            }
            + [")", ")"]
        let tokens = lexical.tokens.map(\.text)
        guard tokens.count >= expected.count else { return false }
        return (0 ... tokens.count - expected.count).contains { start in
            Array(tokens[start ..< start + expected.count]) == expected
        }
    }
}
