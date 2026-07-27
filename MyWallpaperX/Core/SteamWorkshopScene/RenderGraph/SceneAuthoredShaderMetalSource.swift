import Foundation

nonisolated enum SceneAuthoredShaderMetalSource {
    static func prelude(defines: [String: String]) -> String {
        let authoredDefines = defines.sorted { $0.key < $1.key }.map {
            "#define \($0.key) \($0.value)"
        }.joined(separator: "\n")
        return """
        #include <metal_stdlib>
        using namespace metal;

        #define mul(x, y) ((y) * (x))
        #define frac fract
        #define CAST2(x) float2(x)
        #define CAST3(x) float3(x)
        #define CAST4(x) float4(x)
        #define CAST3X3(x) float3x3(x)
        #define saturate(x) clamp((x), 0.0, 1.0)
        #define lerp mix
        \(authoredDefines)
        """
    }

    static func uniformStruct(
        layout: SceneAuthoredShaderUniformLayout
    ) -> String {
        let fields = layout.fields.map {
            "    \($0.type.metalName) \($0.name);"
        }.joined(separator: "\n")
        return """
        struct SceneAuthoredUniforms {
        \(fields)
        };
        """
    }

    static func stageStructs(
        varyings: [(String, SceneAuthoredShaderValueType)]
    ) -> String {
        let fields = varyings.enumerated().map { index, varying in
            "    \(varying.1.metalName) \(varying.0) [[user(locn\(index))]];"
        }.joined(separator: "\n")
        return """
        struct SceneAuthoredVertexAttributes {
            float3 a_Position;
            float2 a_TexCoord;
        };

        struct SceneAuthoredVertexOutput {
            float4 position [[position]];
        \(fields)
        };

        struct SceneAuthoredFragmentInput {
            float4 position [[position]];
        \(fields)
        };
        """
    }

    static func vertexWrapper(
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        let resources = wrapperResourceParameters(textures: textures)
        let arguments = contextArguments(stage: .vertex, textures: textures)
        return """
        vertex SceneAuthoredVertexOutput sceneAuthoredVertex(
            uint vertexID [[vertex_id]],
            constant SceneAuthoredUniforms &mwxUniforms [[buffer(0)]]\(resources)
        ) {
            const float2 coordinates[4] = {
                float2(0.0, 1.0), float2(1.0, 1.0),
                float2(0.0, 0.0), float2(1.0, 0.0)
            };
            SceneAuthoredVertexAttributes mwxAttributes;
            mwxAttributes.a_TexCoord = coordinates[vertexID];
            mwxAttributes.a_Position = float3(
                (coordinates[vertexID] - 0.5) * mwxUniforms.mwxRenderSize,
                0.0
            );
            SceneAuthoredVertexOutput mwxOutput;
            mwxV_main(\(arguments));
            return mwxOutput;
        }
        """
    }

    static func fragmentWrapper(
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        let resources = wrapperResourceParameters(textures: textures)
        let arguments = contextArguments(stage: .fragment, textures: textures)
        return """
        fragment float4 sceneAuthoredFragment(
            SceneAuthoredFragmentInput mwxInput [[stage_in]],
            constant SceneAuthoredUniforms &mwxUniforms [[buffer(0)]]\(resources)
        ) {
            float4 mwxFragColor = float4(0.0);
            mwxF_main(\(arguments));
            return mwxFragColor;
        }
        """
    }

    private static func contextArguments(
        stage: SceneShaderContract.StageKind,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        var arguments = stage == .vertex
            ? ["mwxAttributes", "mwxOutput", "mwxUniforms"]
            : ["mwxInput", "mwxFragColor", "mwxUniforms"]
        for texture in textures {
            arguments.append("mwxTexture\(texture.slot)")
            arguments.append("mwxSampler\(texture.slot)")
        }
        return arguments.joined(separator: ", ")
    }

    private static func wrapperResourceParameters(
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        textures.map {
            ",\n    texture2d<float> mwxTexture\($0.slot) [[texture(\($0.slot))]],"
                + "\n    sampler mwxSampler\($0.slot) [[sampler(\($0.slot))]]"
        }.joined()
    }
}
