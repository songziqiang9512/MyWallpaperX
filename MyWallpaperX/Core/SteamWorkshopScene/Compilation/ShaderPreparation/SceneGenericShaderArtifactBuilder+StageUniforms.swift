import Foundation

nonisolated extension SceneGenericShaderArtifactBuilder {
    struct UniformMemberAccess {
        let name: String
        let range: NSRange
    }

    static func uniformMemberAccesses(in msl: String) -> [UniformMemberAccess] {
        // SPIRV-Cross passes the block to its entry point and to helpers
        // that read its fields. Ordinary structs may have the same fields.
        let receivers = Set(SceneShaderSourceTextFacts.matches(
            #"\bconstant\s+MWXUniforms\s*&\s*([A-Za-z_]\w*)\b"#, in: msl
        ).compactMap { SceneShaderSourceTextFacts.capture($0, 1, in: msl) })
        guard !receivers.isEmpty else { return [] }
        let names = receivers.sorted().joined(separator: "|")
        let accesses = SceneShaderSourceTextFacts.matches(
            #"\b(?:"# + names + #")\s*\.\s*([A-Za-z_]\w*)\b"#, in: msl
        )
        return accesses.compactMap { access in
            guard let field = SceneShaderSourceTextFacts.capture(access, 1, in: msl) else { return nil }
            return .init(name: field, range: access.range(at: 1))
        }
    }

    static func activeUniformFields(
        _ fields: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field],
        accesses: [UniformMemberAccess]
    ) -> [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field] {
        let names = Set(accesses.map(\.name))
        return fields.filter { isSharedInternalUniform($0.authoredName) || names.contains($0.authoredName) }
    }

    nonisolated static func stageLocalUniformLayout(
        vertex: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field],
        fragment: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field],
        colorBoundary: SceneShaderColorBoundary? = nil
    ) throws -> (
        layout: ReflectedLayout,
        vertexNames: [String: String],
        fragmentNames: [String: String]
    ) {
        let sharedInternals = Set((vertex + fragment).map(\.authoredName).filter {
            isSharedInternalUniform($0)
        })
        let duplicateNames = Set(vertex.map(\.authoredName))
            .intersection(fragment.map(\.authoredName))
            .subtracting(sharedInternals)
        var fields: [
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field
        ] = []
        var vertexNames: [String: String] = [:]
        var fragmentNames: [String: String] = [:]
        var internalFields: [String:
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field] = [:]

        func append(
            _ source: [
                SceneGenericShaderProgramArtifact.Program.UniformLayout.Field
            ],
            stage: SceneShaderContract.StageKind,
            prefix: String,
            names: inout [String: String]
        ) throws {
            for field in source {
                if sharedInternals.contains(field.authoredName) {
                    if let existing = internalFields[field.authoredName],
                       existing.type != field.type {
                        throw Failure.uniformStageMismatch
                    }
                    internalFields[field.authoredName] = .init(
                        name: field.authoredName,
                        authoredName: field.authoredName,
                        type: field.type,
                        offset: 0,
                        arrayCount: field.arrayCount
                    )
                    names[field.authoredName] = field.authoredName
                    continue
                }
                let name = duplicateNames.contains(field.authoredName)
                    ? prefix + field.authoredName : field.authoredName
                fields.append(.init(
                    name: name,
                    authoredName: field.authoredName,
                    stage: stage.rawValue,
                    type: field.type,
                    offset: 0,
                    arrayCount: field.arrayCount
                ))
                names[field.authoredName] = name
            }
        }

        try append(
            vertex,
            stage: .vertex,
            prefix: "mwxV_",
            names: &vertexNames
        )
        try append(
            fragment,
            stage: .fragment,
            prefix: "mwxF_",
            names: &fragmentNames
        )
        fields += internalFields.values.sorted { $0.authoredName < $1.authoredName }
        if colorBoundary?.requiresInputMask == true {
            fields.append(.init(
                name: SceneShaderColorBoundary.uniformName,
                authoredName: SceneShaderColorBoundary.uniformName,
                type: "uint", offset: 0, arrayCount: nil
            ))
        }
        return (alignedLayout(fields), vertexNames, fragmentNames)
    }

    nonisolated private static func isSharedInternalUniform(_ name: String) -> Bool {
        name == "mwxRenderSize" || name == "mwxVertexCoordinates01"
            || name == "mwxVertexCoordinates23"
    }

    nonisolated static func resolutionTextureDependencySlots(
        layout: ReflectedLayout,
        authoredSources: [String],
        neutralMissingResolutionSlots: Set<Int> = []
    ) -> Set<Int> {
        let source = authoredSources.joined(separator: "\n")
        return Set(layout.fields.compactMap { field -> Int? in
            let name = field.authoredName
            guard field.type == "float4", field.arrayCount == nil,
                  name.hasPrefix("g_Texture"), name.hasSuffix("Resolution")
            else { return nil }
            let start = name.index(name.startIndex, offsetBy: "g_Texture".count)
            let end = name.index(name.endIndex, offsetBy: -"Resolution".count)
            guard start < end, let slot = Int(name[start ..< end]),
                  (0 ..< 8).contains(slot),
                  !neutralMissingResolutionSlots.contains(slot) else { return nil }
            let sampler = "g_Texture\(slot)"
            let pattern = #"\buniform\s+(?:(?:lowp|mediump|highp)\s+)?sampler2D\s+"#
                + NSRegularExpression.escapedPattern(for: sampler) + #"\b"#
            return source.range(of: pattern, options: .regularExpression) == nil
                ? nil : slot
        })
    }

    nonisolated private static func alignedLayout(
        _ fields: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field]
    ) -> ReflectedLayout {
        var offset = 0
        let aligned = fields.compactMap { field ->
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field? in
            guard let type = SceneAuthoredShaderValueType(rawValue: field.type) else {
                return nil
            }
            offset = alignUniform(offset, to: type.alignment)
            let value = SceneGenericShaderProgramArtifact.Program.UniformLayout.Field(
                name: field.name,
                authoredName: field.authoredName,
                stage: field.stage,
                type: field.type,
                offset: offset,
                arrayCount: field.arrayCount
            )
            offset += type.byteSize * (field.arrayCount ?? 1)
            return value
        }
        return .init(
            fields: aligned,
            byteSize: alignUniform(offset, to: 16)
        )
    }

    nonisolated private static func alignUniform(
        _ value: Int,
        to alignment: Int
    ) -> Int {
        (value + alignment - 1) / alignment * alignment
    }
}
