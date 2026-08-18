import Foundation

extension SceneGenericShaderArtifactBuilder {
    nonisolated static func activeUniformFields(
        _ fields: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field],
        in msl: String
    ) throws -> [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field] {
        let structPattern = try! NSRegularExpression(
            pattern: #"(?s)struct\s+MWXUniforms\s*\{.*?\};"#
        )
        let matches = structPattern.matches(
            in: msl,
            range: NSRange(msl.startIndex..., in: msl)
        )
        guard matches.count == 1,
              let structRange = Range(matches[0].range, in: msl) else {
            throw Failure.uniformStruct
        }
        var executable = msl
        executable.removeSubrange(structRange)
        executable = executable.replacingOccurrences(
            of: #"(?s)/\*.*?\*/|//[^\n]*"#,
            with: " ",
            options: .regularExpression
        )
        return fields.filter { field in
            if field.authoredName == "mwxRenderSize" { return true }
            return executable.range(
                of: #"\.\s*"#
                    + NSRegularExpression.escapedPattern(for: field.authoredName)
                    + #"\b"#,
                options: .regularExpression
            ) != nil
        }
    }

    nonisolated static func stageLocalUniformLayout(
        vertex: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field],
        fragment: [SceneGenericShaderProgramArtifact.Program.UniformLayout.Field]
    ) throws -> (
        layout: ReflectedLayout,
        vertexNames: [String: String],
        fragmentNames: [String: String]
    ) {
        let sharedInternal = "mwxRenderSize"
        let duplicateNames = Set(vertex.map(\.authoredName))
            .intersection(fragment.map(\.authoredName))
            .subtracting([sharedInternal])
        var fields: [
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field
        ] = []
        var vertexNames: [String: String] = [:]
        var fragmentNames: [String: String] = [:]
        var internalField:
            SceneGenericShaderProgramArtifact.Program.UniformLayout.Field?

        func append(
            _ source: [
                SceneGenericShaderProgramArtifact.Program.UniformLayout.Field
            ],
            stage: SceneShaderContract.StageKind,
            prefix: String,
            names: inout [String: String]
        ) throws {
            for field in source {
                if field.authoredName == sharedInternal {
                    if let internalField, internalField.type != field.type {
                        throw Failure.uniformStageMismatch
                    }
                    internalField = .init(
                        name: sharedInternal,
                        authoredName: sharedInternal,
                        type: field.type,
                        offset: 0
                    )
                    names[field.authoredName] = sharedInternal
                    continue
                }
                let name = duplicateNames.contains(field.authoredName)
                    ? prefix + field.authoredName : field.authoredName
                fields.append(.init(
                    name: name,
                    authoredName: field.authoredName,
                    stage: stage.rawValue,
                    type: field.type,
                    offset: 0
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
        if let internalField { fields.append(internalField) }
        return (alignedLayout(fields), vertexNames, fragmentNames)
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
                offset: offset
            )
            offset += type.byteSize
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
