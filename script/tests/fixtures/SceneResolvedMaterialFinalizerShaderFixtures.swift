// Self-authored shader contracts, preparation, and diagnostics.

import Foundation

nonisolated enum SceneEffectStageCompilerBackend {
    case authoredShader
}

nonisolated struct SceneEffectStageCompilerFailure {
    enum Phase: String {
        case shaderPreprocessor = "shader-preprocessor"
        case invariant
    }

    enum Code: String {
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported", shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
    }

    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]
}

nonisolated enum SceneEffectStageBackendCompileResult<Value> {
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Value)
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material
        case instance
        case userTexture
        case explicitBinding
    }
}


import Foundation
import Metal
import simd

typealias Graph = SceneAuthoredEffectRenderPlan
typealias Program = SceneResolvedMaterialProgram
typealias Template = SceneResolvedMaterialTemplate

let fixtureLayerID = 42
let effectProjectionInverse = simd_float4x4(diagonal: SIMD4(2, 3, 4, 5))
let effectOutputModelViewProjection = simd_float4x4(
    diagonal: SIMD4(7, 11, 13, 17)
)
let layerModelMatrix = simd_float4x4(diagonal: SIMD4(6, 7, 8, 9))

func vertexSource(
    samplerMetadata: String?,
    deadMaskCoordinates: Bool = false,
    stageLocalUniforms: Bool = false,
    sharedStageLocalBinding: Bool = false
) -> String {
    let sampler = samplerMetadata.map {
        "uniform sampler2D g_Texture0; // \($0)"
    } ?? ""
    let varyingType = deadMaskCoordinates ? "vec4" : "vec2"
    let resolution = deadMaskCoordinates
        ? "uniform vec4 g_Texture1Resolution;"
        : ""
    let maskCoordinates = deadMaskCoordinates
        ? """
        v_TexCoord.zw = vec2(
            v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
            v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y
        );
        """
        : ""
    let stageLocalUniform: String
    if sharedStageLocalBinding {
        stageLocalUniform = #"uniform float g_Gain; // {"material":"alpha","default":0.75,"range":[0,1]}"#
    } else if stageLocalUniforms {
        stageLocalUniform = #"uniform float g_Gain; // {"material":"vertexGain","default":2}"#
    } else {
        stageLocalUniform = ""
    }
    let stageLocalProbe = stageLocalUniforms ? "float vertexProbe = g_Gain;" : ""
    return """
    #if 1
    uniform mat4 g_ModelViewProjectionMatrixInverse;
    uniform mat4 g_EffectModelViewProjectionMatrix;
    uniform mat4 g_EffectTextureProjectionMatrix;
    uniform mat4 g_EffectTextureProjectionMatrixInverse;
    uniform mat4 g_LayerModelMatrix;
    uniform vec2 g_ParallaxPosition;
    #endif
    #endif
    #if 1
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying \(varyingType) v_TexCoord;
    \(sampler)
    \(resolution)
    \(stageLocalUniform)
    void main() {
        \(stageLocalProbe)
        mat4 modelViewProjectionInverseProbe = g_ModelViewProjectionMatrixInverse;
        mat4 effectModelViewProjectionProbe = g_EffectModelViewProjectionMatrix;
        mat4 forwardProjectionProbe = g_EffectTextureProjectionMatrix;
        mat4 layerModelProbe = g_LayerModelMatrix;
        vec2 parallaxProbe = g_ParallaxPosition;
        v_TexCoord.xy = a_TexCoord;
        \(maskCoordinates)
        gl_Position = mul(
            vec4(a_Position, 1.0),
            g_EffectTextureProjectionMatrixInverse
        );
    }
    #endif
    """
}

func fragmentSource(
    samplerMetadata: String?,
    uniformMetadata: String?,
    secondSamplerMetadata: String?,
    conditionalSecondSampler: Bool,
    arithmetic: Bool = false,
    audioSpectrum: Bool = false,
    maskedAlpha: Bool = false,
    overlayAlphaBlend: Bool = false,
    optionalMask: Bool = false,
    directRedInput: Bool = false,
    stageLocalUniforms: Bool = false,
    sharedStageLocalBinding: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false,
    pointerState: Bool = false,
    semanticProbes: Bool = true,
    scalarSplatScale: Bool = false,
    scalarSplatType: String = "vec2",
    scalarSplatDefault: String? = "1 1",
    scalarSplatRange: String? = nil,
    scalarSplatArray: Bool = false,
    colorBlend: Bool = false,
    legacyMaskOverride: Bool = false
) -> String {
    if colorBlend {
        let maskMutation = legacyMaskOverride ? "=" : "*="
        return """
        // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":30}
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"MASK"}
        uniform float g_BlendAlpha; // {"material":"alpha","default":1}
        uniform vec3 g_TintColor; // {"material":"color","type":"color","default":"1 0 0"}
        vec3 ApplyBlending(
            const int mode,
            in vec3 base,
            in vec3 blend,
            in float opacity
        ) {
            return mix(base, blend, opacity);
        }
        void main() {
            vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
            float mask = g_BlendAlpha;
        #if MASK
            mask \(maskMutation) texSample2D(g_Texture1, v_TexCoord.zw).r;
        #endif
            albedo.rgb = ApplyBlending(BLENDMODE, albedo.rgb, g_TintColor, mask);
        #if BLENDMODE == 0
            albedo.a = 1.0;
        #endif
            gl_FragColor = albedo;
        }
        """
    }
    let annotation = samplerMetadata.map { " // \($0)" } ?? ""
    let uniformAnnotation = uniformMetadata.map { " // \($0)" } ?? ""
    let secondSampler = secondSamplerMetadata.map { metadata in
        let declaration = "uniform sampler2D g_Texture1; // \(metadata)"
        return conditionalSecondSampler
            ? "#if EXTRA == 1\n\(declaration)\n#endif"
            : declaration
    } ?? ""
    let combo = conditionalSecondSampler
        ? #"// [COMBO] {"combo":"EXTRA","default":1}"#
        : ""
    let output: String
    if overlayAlphaBlend {
        output = """
        vec4 base = texSample2D(g_Texture0, v_TexCoord);
        vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
        float weight = g_Multiply * overlay.a;
        base.rgb = ApplyBlending(0, base.rgb, overlay.rgb, weight);
        base.a = overlay.a * g_AlphaMultiply;
        gl_FragColor = base;
        """
    } else if maskedAlpha {
        let mask = optionalMask
            ? """
            #if MASK
            float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;
            #else
            float mask = 1.0;
            #endif
            """
            : "float mask = texSample2D(g_Texture1, v_TexCoord).r;"
        output = """
        vec4 color = texSample2D(g_Texture0, v_TexCoord.xy);
        \(mask)
        color.a *= mask * g_UserAlpha;
        gl_FragColor = color;
        """
    } else if directRedInput {
        output = """
        float scalar = texSample2D(g_Texture0, v_TexCoord).r;
        gl_FragColor = vec4(scalar);
        """
    } else {
        let expression = arithmetic
            ? "texSample2D(g_Texture0, v_TexCoord) * 0.5"
            : "texSample2D(g_Texture0, v_TexCoord)"
        if secondSamplerMetadata != nil {
            output = """
            vec4 color = \(expression);
            float auxiliary = texSample2D(g_Texture1, v_TexCoord).r;
            color.a *= auxiliary;
            gl_FragColor = color;
            """
        } else {
            output = "gl_FragColor = \(expression);"
        }
    }
    let alphaUniform = maskedAlpha
        ? "uniform float g_UserAlpha; // {\"material\":\"alpha\",\"default\":1.0,\"range\":[0,1]}"
        : ""
    let scalarSplatRangeMetadata = scalarSplatRange.map {
        ",\"range\":\($0)"
    } ?? ""
    let scalarSplatMetadata = scalarSplatDefault.map {
        "{\"material\":\"scale\",\"default\":\"\($0)\"\(scalarSplatRangeMetadata)}"
    } ?? "{\"material\":\"scale\"\(scalarSplatRangeMetadata)}"
    let scalarSplatArraySuffix = scalarSplatArray ? "[2]" : ""
    let scalarSplatUniform = scalarSplatScale
        ? "uniform \(scalarSplatType) u_Scale\(scalarSplatArraySuffix); // \(scalarSplatMetadata)"
        : ""
    let overlayUniforms = overlayAlphaBlend
        ? """
        uniform float g_Multiply; // {"material":"multiply","default":0.5}
        uniform float g_AlphaMultiply; // {"material":"alpha","default":0.5}
        """
        : ""
    let overlayHelper = overlayAlphaBlend
        ? """
        vec3 ApplyBlending(
            const int mode,
            in vec3 base,
            in vec3 blend,
            in float opacity
        ) {
            return mix(base, (blend), opacity);
        }
        """
        : ""
    let audioUniforms = audioSpectrum
        ? """
        uniform float g_AudioSpectrum16Left[16];
        uniform float g_AudioSpectrum32Right[32];
        uniform float g_AudioSpectrum64Left[64];
        uniform float g_AudioSpectrum64Right[64];
        """
        : ""
    let audioProbe = audioSpectrum
        ? "float audioProbe = g_AudioSpectrum16Left[3] + g_AudioSpectrum32Right[5] + g_AudioSpectrum64Left[7] + g_AudioSpectrum64Right[9];"
        : ""
    let stageLocalUniform: String
    if sharedStageLocalBinding {
        stageLocalUniform = #"uniform float g_Gain; // {"material":"alpha","default":0.75,"range":[0,2]}"#
    } else if stageLocalUniforms {
        stageLocalUniform = #"uniform float g_Gain; // {"material":"fragmentGain","default":3}"#
    } else {
        stageLocalUniform = ""
    }
    let stageLocalProbe = stageLocalUniforms ? "float fragmentProbe = g_Gain;" : ""
    let metadataProbes = semanticProbes
        ? "vec3 tintProbe = u_Tint;\nfloat timeProbe = g_Time;"
        : ""
    let scalarSplatReadSuffix = scalarSplatArray ? "[0]" : ""
    let scalarSplatProbe = scalarSplatScale
        ? "\(scalarSplatType) scaleProbe = u_Scale\(scalarSplatReadSuffix);"
        : ""
    let runtimeLoopMetadata = runtimeLoopEditorHints
        ? #"{"material":"Fractals","int":true,"default":5,"range":[1,10]}"#
        : #"{"material":"Fractals"}"#
    let runtimeLoopUniform = runtimeLoop
        ? "uniform float u_fractals; // \(runtimeLoopMetadata)" : ""
    let runtimeLoopProbe = runtimeLoop
        ? """
        float runtimeProbe = 0.0;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                runtimeProbe += float(x + y);
            }
        }
        for (int octave = 1; octave <= int(u_fractals); octave++) {
            runtimeProbe += float(octave);
        }
        """
        : ""
    let pointerStateUniform = pointerState ? "uniform vec4 g_PointerState;" : ""
    let pointerStateProbe = pointerState ? "vec4 pointerState = g_PointerState;" : ""
    return """
    varying \(optionalMask ? "vec4" : "vec2") v_TexCoord;
    \(combo)
    uniform sampler2D g_Texture0;\(annotation)
    \(secondSampler)
    \(pointerStateUniform)
    \(audioUniforms)
    uniform vec3 u_Tint;\(uniformAnnotation)
    \(alphaUniform)
    \(scalarSplatUniform)
    \(overlayUniforms)
    uniform float g_Time; // {"default":99}
    \(stageLocalUniform)
    \(runtimeLoopUniform)
    \(overlayHelper)
    void main() {
        \(stageLocalProbe)
        \(runtimeLoopProbe)
        \(pointerStateProbe)
        \(audioProbe)
        \(metadataProbes)
        \(scalarSplatProbe)
        \(output)
    }
    """
}

func contract(
    revision: String,
    samplerMetadata: String? = nil,
    vertexSamplerMetadata: String? = nil,
    uniformMetadata: String? = #"{"material":"Tint","default":"1 0.5 0.25"}"#,
    secondSamplerMetadata: String? = nil,
    conditionalSecondSampler: Bool = false,
    arithmetic: Bool = false,
    audioSpectrum: Bool = false,
    maskedAlpha: Bool = false,
    overlayAlphaBlend: Bool = false,
    optionalMask: Bool = false,
    directRedInput: Bool = false,
    deadMaskCoordinates: Bool = false,
    stageLocalUniforms: Bool = false,
    sharedStageLocalBinding: Bool = false,
    runtimeLoop: Bool = false,
    runtimeLoopEditorHints: Bool = false,
    pointerState: Bool = false,
    semanticProbes: Bool = true,
    scalarSplatScale: Bool = false,
    scalarSplatType: String = "vec2",
    scalarSplatDefault: String? = "1 1",
    scalarSplatRange: String? = nil,
    scalarSplatArray: Bool = false,
    colorBlend: Bool = false,
    legacyMaskOverride: Bool = false,
    includeSourceGraph: Bool = true,
    vertexSourceOverride: String? = nil,
    fragmentSourceOverride: String? = nil
) -> SceneShaderContract {
    func stage(
        _ kind: SceneShaderContract.StageKind,
        path: String,
        source: String
    ) -> SceneShaderContract.Stage {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        return .init(
            kind: kind,
            relativePath: path,
            source: source,
            rawSHA256: SceneShaderStableDigest.hash(Data(source.utf8)),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }
    let stages = [
        stage(
            .vertex,
            path: "\(revision)/root.vert",
            source: vertexSourceOverride ?? vertexSource(
                samplerMetadata: vertexSamplerMetadata,
                deadMaskCoordinates: deadMaskCoordinates || colorBlend,
                stageLocalUniforms: stageLocalUniforms,
                sharedStageLocalBinding: sharedStageLocalBinding
            )
        ),
        stage(
            .fragment,
            path: "\(revision)/root.frag",
            source: fragmentSourceOverride ?? fragmentSource(
                samplerMetadata: samplerMetadata,
                uniformMetadata: uniformMetadata,
                secondSamplerMetadata: secondSamplerMetadata,
                conditionalSecondSampler: conditionalSecondSampler,
                arithmetic: arithmetic,
                audioSpectrum: audioSpectrum,
                maskedAlpha: maskedAlpha,
                overlayAlphaBlend: overlayAlphaBlend,
                optionalMask: optionalMask,
                directRedInput: directRedInput,
                stageLocalUniforms: stageLocalUniforms,
                sharedStageLocalBinding: sharedStageLocalBinding,
                runtimeLoop: runtimeLoop,
                runtimeLoopEditorHints: runtimeLoopEditorHints,
                pointerState: pointerState,
                semanticProbes: semanticProbes,
                scalarSplatScale: scalarSplatScale,
                scalarSplatType: scalarSplatType,
                scalarSplatDefault: scalarSplatDefault,
                scalarSplatRange: scalarSplatRange,
                scalarSplatArray: scalarSplatArray,
                colorBlend: colorBlend,
                legacyMaskOverride: legacyMaskOverride
            )
        ),
    ]
    let nodes: [SceneShaderSourceGraph.Node] = stages.map { stage in
        .init(
            virtualPath: stage.relativePath,
            provenance: .package,
            source: stage.source,
            rawSHA256: stage.rawSHA256,
            byteCount: stage.source.utf8.count
        )
    }
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "\(revision)/root.vert"),
            .init(label: "fragment", virtualPath: "\(revision)/root.frag"),
        ],
        nodes: nodes,
        edges: [],
        diagnostics: [],
        dependencySHA256: SceneShaderSourceGraph.dependencySHA256(
            nodes: nodes, edges: []
        )
    )
    return .init(
        identity: "fixture/\(revision)",
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: [],
        canonicalSHA256: SceneShaderContractLoader.canonicalHash(
            identity: "fixture/\(revision)",
            sourceKind: .authoredSource,
            stages: stages,
            diagnostics: []
        )!,
        sourceGraph: includeSourceGraph ? sourceGraph : nil
    )
}

func crossStageUniformContract(
    revision: String,
    vertexDeclarations: String,
    fragmentDeclarations: String
) -> SceneShaderContract {
    contract(
        revision: revision,
        vertexSourceOverride: """
        attribute vec3 a_Position;
        varying vec2 v_TexCoord;
        \(vertexDeclarations)
        void main() {
            v_TexCoord = a_Position.xy;
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        fragmentSourceOverride: """
        varying vec2 v_TexCoord;
        \(fragmentDeclarations)
        void main() {
            gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);
        }
        """
    )
}

func prepared(
    _ contract: SceneShaderContract
) -> SceneShaderPreparedProgram? {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract,
        combos: [:],
        inactiveComboProviders: [],
        textureReadiness: [:]
    ) {
    case let .accepted(value): value
    case .notApplicable, .rejected: nil
    }
}


func positiveDiagnostic(_ shader: SceneShaderContract) -> String {
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader,
        combos: [:],
        textureReadiness: [0: true]
    ) {
    case let .accepted(prepared):
        let compiled = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard let frontend = compiled.program else {
            return "frontend=" + compiled.diagnostics.map { $0.code.rawValue }.joined(separator: ",")
        }
        let schema: String
        do {
            schema = "\(try SceneResolvedMaterialShaderSchema.activeSamplers(prepared))"
        } catch {
            schema = "error:\(error)"
        }
        return "slots=\(frontend.textureBindings.map(\.slot))"
            + ",fields=\(frontend.uniformLayout.fields.map { "\($0.name):\($0.type.rawValue):\($0.offset)" })"
            + ",bytes=\(frontend.uniformLayout.byteSize)"
            + ",transfer=\(frontend.colorTransfer)"
            + ",annotations=\(prepared.all.flatMap(\.activeAnnotations).count)"
            + ",schema=\(schema)"
    case let .rejected(failure):
        return "preparation=\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.details)"
    case .notApplicable:
        return "preparation=not-applicable"
    }
}

func missingSourceGraphDiagnostic() -> String {
    let shader = contract(
        revision: "missing-source-graph",
        includeSourceGraph: false
    )
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: shader,
        combos: [:]
    ) {
    case .accepted:
        return "accepted"
    case let .rejected(failure):
        return "\(failure.phase.rawValue)/\(failure.code.rawValue)/\(failure.details.count)"
    case .notApplicable:
        return "not-applicable"
    }
}
