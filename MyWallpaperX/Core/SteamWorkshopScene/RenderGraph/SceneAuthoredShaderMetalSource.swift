import Foundation

nonisolated enum SceneAuthoredShaderMetalSource {
    static let float3x3InverseHelper = """
        inline float3x3 mwxInverseFloat3x3(float3x3 value) {
            float3 cofactor0 = cross(value[1], value[2]);
            float3 cofactor1 = cross(value[2], value[0]);
            float3 cofactor2 = cross(value[0], value[1]);
            float determinant = dot(value[0], cofactor0);
            return transpose(float3x3(cofactor0, cofactor1, cofactor2)) / determinant;
        }
        """

    static func mergedDefines(
        _ first: [String: String],
        _ second: [String: String]
    ) -> (defines: [String: String]?, diagnostics: [SceneAuthoredShaderFrontendDiagnostic]) {
        var result = first
        for (name, value) in second {
            if let existing = result[name], existing != value {
                return (nil, [.init(
                    code: .malformedDefine,
                    message: "Shader stages define '\(name)' with conflicting values.",
                    stage: nil,
                    line: nil,
                    column: nil
                )])
            }
            result[name] = value
        }
        return (result, [])
    }

    static func prelude(
        defines: [String: String],
        colorTransfer: SceneShaderColorTransfer
    ) -> String {
        let authoredDefines = defines.sorted { $0.key < $1.key }.map {
            "#define \($0.key) \($0.value)"
        }.joined(separator: "\n")
        let colorBoundary = colorBoundaryHelpers(for: colorTransfer)
        return """
        #include <metal_stdlib>
        using namespace metal;

        float3x3 mwxCast3x3(float4x4 value) {
            return float3x3(value[0].xyz, value[1].xyz, value[2].xyz);
        }

        #define mul(x, y) ((y) * (x))
        #define frac fract
        #define CAST2(x) float2(x)
        #define CAST3(x) float3(x)
        #define CAST4(x) float4(x)
        #define CAST3X3(x) mwxCast3x3(x)
        #define saturate(x) clamp((x), 0.0, 1.0)
        #define lerp mix
        \(authoredDefines)
        \(colorBoundary)
        """
    }

    static func uniformStruct(
        layout: SceneAuthoredShaderUniformLayout
    ) -> String {
        let fields = layout.fields.map {
            let suffix = $0.arrayCount.map { "[\($0)]" } ?? ""
            return "    \($0.type.metalName) \($0.name)\(suffix);"
        }.joined(separator: "\n")
        return """
        struct SceneAuthoredUniforms {
        \(fields)
        };
        """
    }

    static func stageStructs(
        varyings: [(String, SceneAuthoredShaderValueType, Int?)]
    ) -> String {
        var location = 0
        var fields: [String] = []
        for varying in varyings {
            let elementCount = varying.2 ?? 1
            for element in 0..<elementCount {
                let suffix = varying.2 == nil ? "" : "_\(element)"
                fields.append(
                    "    \(varying.1.metalName) \(varying.0)\(suffix) "
                        + "[[user(locn\(location))]];"
                )
                location += 1
            }
        }
        let fieldSource = fields.joined(separator: "\n")
        return """
        struct SceneAuthoredVertexAttributes {
            float3 a_Position;
            float2 a_TexCoord;
        };

        struct SceneAuthoredVertexOutput {
            float4 position [[position]];
        \(fieldSource)
        };

        struct SceneAuthoredFragmentInput {
            float4 position [[position]];
        \(fieldSource)
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
            const float2 position = float2(
                coordinates[vertexID].x,
                1.0 - coordinates[vertexID].y
            );
            mwxAttributes.a_Position = float3(
                (position - 0.5) * mwxUniforms.mwxRenderSize,
                0.0
            );
            SceneAuthoredVertexOutput mwxOutput;
            mwxV_main(\(arguments));
            return mwxOutput;
        }
        """
    }

    static func fragmentWrapper(
        textures: [SceneAuthoredShaderProgram.TextureBinding],
        colorTransfer: SceneShaderColorTransfer
    ) -> String {
        let resources = wrapperResourceParameters(textures: textures)
        let arguments = contextArguments(stage: .fragment, textures: textures)
        let result: String
        switch colorTransfer {
        case .straightAlphaPreserving, .straightAlpha,
             .independentAlphaSignalCompositing:
            result = "mwxPremultiply(mwxFragColor)"
        default:
            result = "mwxFragColor"
        }
        return """
        fragment float4 sceneAuthoredFragment(
            SceneAuthoredFragmentInput mwxInput [[stage_in]],
            constant SceneAuthoredUniforms &mwxUniforms [[buffer(0)]]\(resources)
        ) {
            float4 mwxFragColor = float4(0.0);
            mwxF_main(\(arguments));
            return \(result);
        }
        """
    }

    private static func colorBoundaryHelpers(
        for transfer: SceneShaderColorTransfer
    ) -> String {
        switch transfer {
        case .straightAlphaPreserving, .straightAlpha, .independentAlphaSignal,
             .independentAlphaSignalCompositing:
            break
        default:
            return ""
        }
        return """
        float4 mwxUnpremultiply(float4 color) {
            const float alpha = saturate(color.a);
            const float3 rgb = alpha > 0.0
                ? saturate(color.rgb / alpha)
                : float3(0.0);
            return float4(rgb, alpha);
        }

        float4 mwxPremultiply(float4 color) {
            const float alpha = saturate(color.a);
            return float4(color.rgb * alpha, alpha);
        }
        """
    }

    static func contextParameterList(
        stage: SceneShaderContract.StageKind,
        textures: [SceneAuthoredShaderProgram.TextureBinding]
    ) -> String {
        var parameters = stage == .vertex
            ? [
                "SceneAuthoredVertexAttributes mwxAttributes",
                "thread SceneAuthoredVertexOutput &mwxOutput",
                "constant SceneAuthoredUniforms &mwxUniforms",
            ]
            : [
                "SceneAuthoredFragmentInput mwxInput",
                "thread float4 &mwxFragColor",
                "constant SceneAuthoredUniforms &mwxUniforms",
            ]
        for texture in textures {
            parameters.append("texture2d<float> mwxTexture\(texture.slot)")
            parameters.append("sampler mwxSampler\(texture.slot)")
        }
        return parameters.joined(separator: ", ")
    }

    static func contextArguments(
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

    static func functionPrefix(_ stage: SceneShaderContract.StageKind) -> String {
        stage == .vertex ? "mwxV_" : "mwxF_"
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
