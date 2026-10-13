// Neutral and mapped texture-resolution proofs and failure cases.
import Foundation
import Metal
import simd

func neutralTextureResolutionSources(
    resolutionSlot: Int,
    coordinateSlot: Int,
    varying: String
) -> (vertex: String, fragment: String) {
    (
        """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec4 \(varying);
        uniform vec4 g_Texture\(resolutionSlot)Resolution;
        void main() {
            \(varying).xy = a_TexCoord;
            \(varying).zw = vec2(
                ((\(varying).x * g_Texture\(resolutionSlot)Resolution.z)
                    / (g_Texture\(resolutionSlot)Resolution.x)),
                ((\(varying).y * g_Texture\(resolutionSlot)Resolution.w)
                    / (g_Texture\(resolutionSlot)Resolution.y))
            );
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        """
        varying vec4 \(varying);
        uniform sampler2D g_Texture0; // {"material":"framebuffer"}
        uniform sampler2D g_Texture\(coordinateSlot); // {"mode":"opacitymask"}
        void main() {
            vec4 current = texSample2D(g_Texture0, \(varying).xy);
            float mask = texSample2D(
                g_Texture\(coordinateSlot),
                (\(varying).zw)
            ).r;
            gl_FragColor = vec4(current.rgb, current.a * mask);
        }
        """
    )
}

func separateNeutralTextureResolutionSources(
    resolutionSlot: Int,
    coordinateSlot: Int,
    sourceVarying: String,
    targetVarying: String
) -> (vertex: String, fragment: String) {
    (
        """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec4 \(sourceVarying);
        varying vec2 \(targetVarying);
        uniform vec4 g_Texture\(resolutionSlot)Resolution;
        void main() {
            \(sourceVarying).xy = a_TexCoord;
            \(targetVarying) = vec2(
                ((\(sourceVarying).x * g_Texture\(resolutionSlot)Resolution.z)
                    / (g_Texture\(resolutionSlot)Resolution.x)),
                ((\(sourceVarying).y * g_Texture\(resolutionSlot)Resolution.w)
                    / (g_Texture\(resolutionSlot)Resolution.y))
            );
            gl_Position = vec4(a_Position, 1.0);
        }
        """,
        """
        varying vec4 \(sourceVarying);
        varying vec2 \(targetVarying);
        uniform sampler2D g_Texture0; // {"material":"framebuffer"}
        uniform sampler2D g_Texture\(coordinateSlot); // {"mode":"opacitymask"}
        void main() {
            vec4 current = texSample2D(g_Texture0, \(sourceVarying).xy);
            float mask = texSample2D(
                g_Texture\(coordinateSlot),
                \(targetVarying)
            ).r;
            gl_FragColor = vec4(current.rgb, current.a * mask);
        }
        """
    )
}

func neutralTextureResolutionResult(
    _ device: MTLDevice,
    resolutionSlot: Int = 1,
    coordinateSlot: Int = 2,
    varying: String = "coordinateCarrier",
    physicalSize: CGSize = CGSize(width: 2, height: 2),
    mappedSize: CGSize = CGSize(width: 2, height: 2),
    uvTransform: SceneTextureUVTransform = .identity,
    includeResolutionCandidate: Bool = false,
    includeResolutionDefault: Bool = false,
    vertexSourceOverride: String? = nil,
    fragmentSourceOverride: String? = nil,
    coordinateStatusOverride: SceneFrameTextureLookupStatus? = nil
) -> Result<Program, SceneResolvedMaterialFailure> {
    let maskPath = SceneVFSAssetPath(
        "textures/neutral-resolution-mask-\(coordinateSlot).tex"
    )!
    let maskIdentity = SceneFrameTextureIdentity.asset(.init(
        path: maskPath,
        purpose: .mask
    ))
    let sources = neutralTextureResolutionSources(
        resolutionSlot: resolutionSlot,
        coordinateSlot: coordinateSlot,
        varying: varying
    )
    let shader = contract(
        revision: "neutral-texture-resolution-\(resolutionSlot)-\(coordinateSlot)",
        uniformMetadata: nil,
        semanticProbes: false,
        vertexSourceOverride: vertexSourceOverride ?? sources.vertex,
        fragmentSourceOverride: fragmentSourceOverride ?? sources.fragment
    )
    var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
    slots[coordinateSlot] = .init(index: coordinateSlot, candidates: [
        .init(reference: .asset(maskPath), provenance: .material),
    ])
    let coordinateStatus = coordinateStatusOverride ?? readyStatus(
            device,
            identity: maskIdentity,
            purpose: .mask,
            content: .data,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: uvTransform
        )
    var entries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [
        maskIdentity: coordinateStatus,
    ]
    if includeResolutionDefault {
        let identity = SceneFrameTextureIdentity.asset(.init(
            path: SceneVFSAssetPath("textures/default.tex")!, purpose: .mask))
        entries[identity] = readyStatus(device, identity: identity,
            purpose: .mask, content: .data,
            physicalSize: CGSize(width: 64, height: 32),
            mappedSize: CGSize(width: 64, height: 32))
    }
    if includeResolutionCandidate {
        let path = SceneVFSAssetPath(
            "textures/unexpected-resolution-slot-\(resolutionSlot).tex"
        )!
        let identity = SceneFrameTextureIdentity.asset(.init(
            path: path,
            purpose: .mask
        ))
        slots[resolutionSlot] = .init(index: resolutionSlot, candidates: [
            .init(reference: .asset(path), provenance: .material),
        ])
        entries[identity] = readyStatus(
            device,
            identity: identity,
            purpose: .mask,
            content: .data
        )
    }
    return finalize(
        shader: shader,
        device: device,
        includePrimaryCandidate: false,
        additionalEntries: entries,
        implicitFramebufferIdentity: graphTexture(),
        outputStorage: .preservedRGBAUnorm,
        textureSlotsOverride: slots
    )
}

func neutralTextureResolutionToken(_ device: MTLDevice) -> String {
    let result = neutralTextureResolutionResult(device)
    guard case let .success(program) = result else {
        if case let .failure(failure) = result {
            return failureToken(result) + "/" + failure.boundedDetails.joined(separator: ",")
        }
        return failureToken(result)
    }
    guard program.textureSlots[1] == nil else { return "slot1-bound" }
    guard program.textureSlots[2] != nil else { return "slot2-missing" }
    guard let uniform = program.resolvedUniforms.first(where: {
              $0.field.name == "g_Texture1Resolution"
          }) else { return "uniform-missing" }
    guard case let .neutralMissingTextureResolution(fact) = uniform.source
    else { return "uniform-source" }
    guard
          fact.resolutionSlot == 1,
          uniform.encodedValue.count == 16,
          (0 ..< 4).allSatisfy({
              Harness.float(uniform.encodedValue, at: $0 * 4) == 2
          }),
          program.semanticIdentity.activeUniforms.contains(where: {
              guard $0.fieldName == "g_Texture1Resolution",
                    case .neutralMissingTextureResolution(fact) = $0.source
              else { return false }
              return fact.resolutionSlot == 1
          })
    else { return "uniform-fact-or-bytes" }
    return program.exactIdentity.textureSlots[2]?.physicalExtent == [2, 2]
        && program.exactIdentity.textureSlots[2]?.mappedExtent == [2, 2]
        && program.exactIdentity.uniformBytes == program.uniformBytes
        ? "success" : "exact-identity"
}

func neutralTextureResolutionUnseenToken(_ device: MTLDevice) -> String {
    let result = neutralTextureResolutionResult(
        device,
        resolutionSlot: 3,
        coordinateSlot: 5,
        varying: "unseenCoordinates",
        physicalSize: CGSize(width: 64, height: 32),
        mappedSize: CGSize(width: 64, height: 32)
    )
    guard case let .success(program) = result,
          program.textureSlots[3] == nil,
          program.textureSlots[5] != nil,
          program.exactIdentity.textureSlots[5]?.physicalExtent == [64, 32],
          program.exactIdentity.textureSlots[5]?.mappedExtent == [64, 32],
          let uniform = program.resolvedUniforms.first(where: {
              $0.field.name == "g_Texture3Resolution"
          }),
          case let .neutralMissingTextureResolution(fact) = uniform.source,
          fact.resolutionSlot == 3,
          uniform.encodedValue.count == 16,
          (0 ..< 4).allSatisfy({ Harness.float(uniform.encodedValue, at: $0 * 4) == 2 })
    else { return failureToken(result) }
    return "success"
}

func separateNeutralTextureResolutionToken(_ device: MTLDevice) -> String {
    let sources = separateNeutralTextureResolutionSources(
        resolutionSlot: 7,
        coordinateSlot: 3,
        sourceVarying: "baseCoordinates",
        targetVarying: "opacityCoordinates"
    )
    let result = neutralTextureResolutionResult(
        device,
        resolutionSlot: 7,
        coordinateSlot: 3,
        varying: "unusedPackedCoordinates",
        physicalSize: CGSize(width: 256, height: 256),
        mappedSize: CGSize(width: 256, height: 256),
        vertexSourceOverride: sources.vertex.replacingOccurrences(
            of: "baseCoordinates.xy = a_TexCoord;",
            with: "baseCoordinates.xy = a_TexCoord; baseCoordinates.zw = baseCoordinates.xy;"
        ),
        fragmentSourceOverride: sources.fragment
    )
    guard case let .success(program) = result,
          program.textureSlots[7] == nil,
          program.exactIdentity.textureSlots[3]?.physicalExtent == [256, 256],
          let uniform = program.resolvedUniforms.first(where: {
              $0.field.name == "g_Texture7Resolution"
          }),
          case let .neutralMissingTextureResolution(fact) = uniform.source,
          fact.resolutionSlot == 7,
          (0 ..< 4).allSatisfy({
              Harness.float(uniform.encodedValue, at: $0 * 4) == 2
          })
    else { return failureToken(result) }
    return "success"
}

func neutralTextureResolutionAnalyzerCases() -> [String: Bool] {
    let sources = neutralTextureResolutionSources(
        resolutionSlot: 1,
        coordinateSlot: 2,
        varying: "coordinateCarrier"
    )
    func fact(_ vertex: String, _ fragment: String = "")
        -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment.isEmpty ? sources.fragment : fragment,
            activeSamplerSlots: [0, 2]
        )
    }
    let resolution = "g_Texture1Resolution"
    let varying = "coordinateCarrier"
    let separate = separateNeutralTextureResolutionSources(
        resolutionSlot: 7,
        coordinateSlot: 3,
        sourceVarying: "baseCoordinates",
        targetVarying: "opacityCoordinates"
    )
    func separateFact(_ vertex: String, _ fragment: String? = nil)
        -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
            vertexSource: vertex,
            fragmentSource: fragment ?? separate.fragment,
            activeSamplerSlots: [0, 3]
        )
    }
    let realVertex = """
    uniform mat4 g_ModelViewProjectionMatrix;
    uniform vec4 g_Texture1Resolution;
    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;
    varying vec4 v_TexCoord;
    void main() {
        gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
        v_TexCoord.xy = a_TexCoord;
        v_TexCoord.zw = vec2(
            v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
            v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y
        );
    }
    """
    let realFragment = """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture2; // {"combo":"OPACITYMASK","mode":"opacitymask"}
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        float opactiyMask = 1.0 - texSample2D(g_Texture2, v_TexCoord.zw).r;
        gl_FragColor = albedo * opactiyMask;
    }
    """
    let realConditionalFragment = """
    varying vec4 v_TexCoord;
    uniform sampler2D g_Texture0; // {"hidden":true}
    uniform sampler2D g_Texture1; // {"mode":"opacitymask","combo":"MASK"}
    uniform sampler2D g_Texture2; // {"mode":"opacitymask","combo":"OPACITYMASK","default":"util/white"}
    void main() {
        vec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        #if MASK
        float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;
        #else
        float mask = 0.5;
        #endif
        #if OPACITYMASK
        float opactiyMask = 1.0 - texSample2D(g_Texture2, v_TexCoord.zw).r;
        #else
        float opactiyMask = 1.0;
        #endif
        gl_FragColor = albedo * mask * opactiyMask;
    }
    """
    let realPrepared: Bool = {
        let shader = contract(
            revision: "neutral-texture-resolution-real-prepared",
            uniformMetadata: nil,
            semanticProbes: false,
            vertexSourceOverride: realVertex,
            fragmentSourceOverride: realConditionalFragment
        )
        guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                inactiveComboProviders: ["MASK"],
                textureReadiness: [0: true, 1: false, 2: true]
            ) else { return false }
        let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        guard let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
            .activeSamplerNames(
                vertexSource: sources.vertex,
                fragmentSource: sources.fragment
            ) else { return false }
        let activeSlots = Set(activeNames.compactMap { name -> Int? in
            guard name.hasPrefix("g_Texture") else { return nil }
            return Int(name.dropFirst("g_Texture".count))
        })
        let analyzed = SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
            vertexSource: sources.vertex,
            fragmentSource: sources.fragment,
            activeSamplerSlots: activeSlots
        ) != nil
        return activeSlots == [0, 2] && analyzed
    }()
    return [
        "exact": fact(sources.vertex) != nil,
        "separateExact": separateFact(separate.vertex) != nil,
        "separateSourceOverwrite": separateFact(
            separate.vertex.replacingOccurrences(
                of: "gl_Position =",
                with: "baseCoordinates.xy = opacityCoordinates; gl_Position ="
            )
        ) == nil,
        "separateTargetLiveUse": separateFact(
            separate.vertex,
            separate.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float live = opacityCoordinates.x; gl_FragColor ="
            )
        ) != nil,
        "realActiveCurrentAndMask": SceneAuthoredShaderNeutralTextureResolutionAnalyzer
            .analyze(
                vertexSource: realVertex,
                fragmentSource: realFragment,
                activeSamplerSlots: [0, 2]
            ) != nil,
        "realPreparedCombo": realPrepared,
        "activeResolutionSlot": SceneAuthoredShaderNeutralTextureResolutionAnalyzer
            .analyze(
                vertexSource: sources.vertex,
                fragmentSource: sources.fragment,
                activeSamplerSlots: [0, 1, 2]
            ) == nil,
        "glPosition": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).zw = vec2",
            with: "gl_Position.zw = vec2"
        )) == nil,
        "wrongComponent": fact(sources.vertex.replacingOccurrences(
            of: "\(resolution).z",
            with: "\(resolution).y"
        )) == nil,
        "attributeUV": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).x *", with: "a_TexCoord.x *"
        ).replacingOccurrences(of: "\(varying).y *", with: "a_TexCoord.y *")) != nil,
        "functionUse": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).x * \(resolution).z",
            with: "abs(\(varying).x) * \(resolution).z"
        )) == nil,
        "fragmentResolutionUse": fact(sources.vertex, sources.fragment.replacingOccurrences(
            of: "void main() {", with: "uniform vec4 \(resolution);\nvoid main() { float extra = \(resolution).x;"
        )) == nil,
        "array": fact(sources.vertex.replacingOccurrences(
            of: "uniform vec4 \(resolution);",
            with: "uniform vec4 \(resolution)[1];"
        )) == nil,
        "transform": fact(sources.vertex.replacingOccurrences(
            of: "/ (\(resolution).x))",
            with: "/ (\(resolution).x) + 0.25)"
        )) == nil,
        "singleSided": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).y * \(resolution).w",
            with: "\(varying).y"
        )) == nil,
        "crossComponent": fact(sources.vertex.replacingOccurrences(
            of: "\(resolution).w",
            with: "\(resolution).z"
        )) == nil,
        "swappedSource": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).x * \(resolution).z",
            with: "\(varying).y * \(resolution).z"
        )) == nil,
        "extraResolutionUse": fact(sources.vertex.replacingOccurrences(
            of: "gl_Position =",
            with: "float texelOrMip = \(resolution).x; gl_Position ="
        )) == nil,
        "multipleSource": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).xy = a_TexCoord;",
            with: "\(varying).xy = a_TexCoord; \(varying).xy = a_TexCoord;"
        )) == nil,
        "multipleConsumer": fact(
            sources.vertex,
            sources.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float duplicate = texSample2D(g_Texture2, \(varying).zw).r; gl_FragColor ="
            )
        ) != nil,
        "targetLiveUse": fact(
            sources.vertex,
            sources.fragment.replacingOccurrences(
                of: "gl_FragColor =",
                with: "float live = \(varying).z; gl_FragColor ="
            )
        ) != nil,
        "wrongUniformType": fact(sources.vertex.replacingOccurrences(
            of: "uniform vec4 \(resolution);",
            with: "uniform vec3 \(resolution);"
        )) == nil,
        "wrongUniformName": fact(sources.vertex.replacingOccurrences(
            of: resolution,
            with: "u_MissingResolution"
        )) == nil,
        "missingAssignment": fact(sources.vertex.replacingOccurrences(
            of: "\(varying).zw = vec2",
            with: "vec2 discarded = vec2"
        )) == nil,
    ]
}

func neutralTextureResolutionFinalizerFailures(
    _ device: MTLDevice
) -> [String: String] {
    let sources = neutralTextureResolutionSources(
        resolutionSlot: 1,
        coordinateSlot: 2,
        varying: "coordinateCarrier"
    )
    let nonIdentityMapped = SceneTextureUVTransform(
        origin: .zero,
        xAxis: SIMD2(0.5, 0),
        yAxis: SIMD2(0, 1)
    )
    let nonIdentityUV = SceneTextureUVTransform(
        origin: SIMD2(0.1, 0),
        xAxis: SIMD2(0.8, 0),
        yAxis: SIMD2(0, 1)
    )
    let maskPath = SceneVFSAssetPath("textures/neutral-resolution-mask-2.tex")!
    let maskIdentity = SceneFrameTextureIdentity.asset(.init(
        path: maskPath,
        purpose: .mask
    ))
    let wrongPurpose = SceneFrameTextureLookupStatus.ready(.init(
        publication: publication(
            device,
            requestIdentity: maskIdentity,
            purpose: .straightAlbedo,
            content: .color(.resolved(.straightAlpha)),
            candidateGeneration: 7,
            contentGeneration: 7
        ),
        resourceGeneration: 7
    ))
    let defaultResult = neutralTextureResolutionResult(device,
        includeResolutionDefault: true,
        fragmentSourceOverride: sources.fragment.replacingOccurrences(
            of: "void main() {",
            with: "uniform sampler2D g_Texture1; // {\"mode\":\"opacitymask\",\"default\":\"textures/default.tex\"}\nvoid main() {"))
    let defaultToken: String = {
        guard case let .success(program) = defaultResult,
              let slot = program.textureSlots[1], slot.registryIdentity ==
                .asset(.init(path: SceneVFSAssetPath("textures/default.tex")!, purpose: .mask)),
              let uniform = program.resolvedUniforms.first(where: {
                  $0.field.name == "g_Texture1Resolution"
              }), case .host(.textureResolution(slot: 1)) = uniform.source,
              (0..<4).map({ Harness.float(uniform.encodedValue, at: $0 * 4) }) == [64, 32, 64, 32]
        else { return failureToken(defaultResult) + "/default-resource-or-host" }
        return "success"
    }()
    return [
        "resolutionCandidate": failureToken(neutralTextureResolutionResult(
            device,
            includeResolutionCandidate: true
        )),
        "mappedNotIdentity": failureToken(neutralTextureResolutionResult(
            device,
            physicalSize: CGSize(width: 64, height: 32),
            mappedSize: CGSize(width: 32, height: 32),
            uvTransform: nonIdentityMapped
        )),
        "uvNotIdentity": failureToken(neutralTextureResolutionResult(
            device,
            physicalSize: CGSize(width: 64, height: 32),
            mappedSize: CGSize(width: 64, height: 32),
            uvTransform: nonIdentityUV
        )),
        "coordinatePending": failureToken(neutralTextureResolutionResult(
            device,
            coordinateStatusOverride: .pending
        )),
        "coordinateWrongPurpose": failureToken(neutralTextureResolutionResult(
            device,
            coordinateStatusOverride: wrongPurpose
        )),
        "wrongComponent": failureToken(neutralTextureResolutionResult(
            device,
            vertexSourceOverride: sources.vertex.replacingOccurrences(
                of: "g_Texture1Resolution.z",
                with: "g_Texture1Resolution.y"
            )
        )),
        "downstreamComputation": failureToken(neutralTextureResolutionResult(
            device,
            fragmentSourceOverride: sources.fragment.replacingOccurrences(
                of: "(coordinateCarrier.zw)",
                with: "(coordinateCarrier.zw * 0.5)"
            )
        )),
        "unsampledDefaultResolution": defaultToken,
    ]
}

func mappedTextureResolutionTokens(
    _ device: MTLDevice
) -> [String: Bool] {
    let maskPath = SceneVFSAssetPath(
        "textures/same-slot-mapped-mask.tex"
    )!
    let maskIdentity = SceneFrameTextureIdentity.asset(.init(
        path: maskPath,
        purpose: .mask
    ))
    let mappedTransform = SceneTextureUVTransform(
        origin: .zero,
        xAxis: SIMD2(0.5, 0),
        yAxis: SIMD2(0, 1)
    )
    let translatedTransform = SceneTextureUVTransform(
        origin: SIMD2(0.5, 0),
        xAxis: SIMD2(0.5, 0),
        yAxis: SIMD2(0, 1)
    )
    func maskStatus(
        _ transform: SceneTextureUVTransform
    ) -> SceneFrameTextureLookupStatus {
        readyStatus(
            device,
            identity: maskIdentity,
            purpose: .mask,
            content: .data,
            physicalSize: CGSize(width: 4, height: 4),
            mappedSize: CGSize(width: 2, height: 4),
            uvTransform: transform
        )
    }
    let mappedShader = contract(
        revision: "same-slot-mapped-coordinate",
        secondSamplerMetadata:
            #"{"mode":"opacitymask","combo":"MASK"}"#,
        maskedAlpha: true,
        optionalMask: true,
        deadMaskCoordinates: true,
        semanticProbes: false,
        fragmentSourceOverride: nil
    )
    let mapped = finalize(
        shader: mappedShader,
        device: device,
        secondReference: .asset(maskPath),
        additionalEntries: [maskIdentity: maskStatus(mappedTransform)],
        uniformDeclarations: [staticDeclaration("alpha", components: [1])]
    )
    let unproven = finalize(
        shader: contract(
            revision: "same-slot-unproven-coordinate",
            uniformMetadata: nil,
            semanticProbes: false
        ),
        device: device,
        additionalEntries: [
            .graph(graphTexture()): readyStatus(
                device,
                identity: .graph(graphTexture()),
                purpose: .premultipliedColor,
                content: .color(.resolved(.premultipliedAlpha)),
                physicalSize: CGSize(width: 4, height: 4),
                mappedSize: CGSize(width: 2, height: 4),
                uvTransform: mappedTransform
            ),
        ],
        snapshotKind: .missing
    )
    let translated = finalize(
        shader: mappedShader,
        device: device,
        secondReference: .asset(maskPath),
        additionalEntries: [maskIdentity: maskStatus(translatedTransform)],
        uniformDeclarations: [staticDeclaration("alpha", components: [1])]
    )

    func values(
        _ program: Program,
        _ fieldName: String
    ) -> [Float]? {
        guard let field = program.frontendProgram.uniformLayout.fields.first(
            where: { $0.name == fieldName }
        ), field.type == .float4 else { return nil }
        return (0 ..< 4).map { component in
            program.uniformBytes.withUnsafeBytes {
                $0.loadUnaligned(
                    fromByteOffset: field.offset + component * 4,
                    as: Float.self
                )
            }
        }
    }

    guard case let .success(mappedProgram) = mapped,
          case .success = unproven,
          case let .success(translatedProgram) = translated else {
        return [
            "mapped-\(failureToken(mapped))": false,
            "unproven-\(failureToken(unproven))": false,
            "translated-\(failureToken(translated))": false,
        ]
    }
    return [
        "programs": true,
        "resolutionPreservesPhysicalAndMapped":
            values(mappedProgram, "g_Texture1Resolution") == [4, 4, 2, 4],
        "translatedResolutionPreservesPhysicalAndMapped":
            values(translatedProgram, "g_Texture1Resolution") == [4, 4, 2, 4],
    ]
}
