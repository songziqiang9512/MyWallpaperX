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
            if isSharedInternalUniform(field.authoredName) { return true }
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
        return (alignedLayout(fields), vertexNames, fragmentNames)
    }

    nonisolated private static func isSharedInternalUniform(_ name: String) -> Bool {
        name == "mwxRenderSize"
            || SceneMaterialTextureTransformABI.component(forFieldName: name) != nil
    }

    nonisolated static func validTextureTransformLayout(
        _ layout: ReflectedLayout,
        activeSlots: Set<Int>
    ) -> Bool {
        let fields = layout.fields.compactMap {
            field -> SceneAuthoredShaderUniformLayout.Field? in
            guard let type = SceneAuthoredShaderValueType(rawValue: field.type) else {
                return nil
            }
            return .init(
                name: field.name,
                authoredName: field.authoredName,
                stage: field.stage.flatMap(SceneShaderContract.StageKind.init(rawValue:)),
                type: type,
                arrayCount: field.arrayCount,
                offset: field.offset
            )
        }
        return fields.count == layout.fields.count
            && SceneMaterialTextureTransformABI.validates(
                layout: .init(fields: fields, byteSize: layout.byteSize),
                activeSlots: activeSlots
            )
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

    nonisolated static func addingTextureTransformFields(
        to layout: ReflectedLayout,
        activeSlots: Set<Int>
    ) -> ReflectedLayout? {
        var fields = layout.fields
        let byName = Dictionary(grouping: fields, by: \.name)
        for slot in activeSlots.sorted() {
            for component in [
                SceneMaterialTextureTransformABI.Component.originAndXAxis,
                .yAxis,
            ] {
                let name = SceneMaterialTextureTransformABI.fieldName(
                    slot: slot,
                    component: component
                )
                if let existing = byName[name] {
                    guard existing.count == 1,
                          existing[0].authoredName == name,
                          existing[0].stage == nil,
                          existing[0].type == "float4",
                          existing[0].arrayCount == nil else { return nil }
                    continue
                }
                fields.append(.init(
                    name: name,
                    authoredName: name,
                    type: "float4",
                    offset: 0
                ))
            }
        }
        return alignedLayout(fields)
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
