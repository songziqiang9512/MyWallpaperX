// Complete framebuffer cases; state remains owned by the single fixture.
import Foundation
import Metal
import simd

func samplerPurposeToken(
    _ metadata: String?,
    vertexMetadata: String? = nil,
    assetReference: Bool = false,
    namedTargetReference: Bool = false,
    assetPath: String = "textures/fixture.tex"
) -> String {
    let shader = contract(
        revision: "sampler-schema",
        samplerMetadata: metadata,
        vertexSamplerMetadata: vertexMetadata
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true]
            ) else { return "preparation-failed" }
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema
            .activeSamplers(prepared)[0] else { return "missing" }
        let reference: Template.TextureReference
        if namedTargetReference {
            reference = .provider(.namedLayerTarget(.init(
                providerLayerID: 42,
                variant: .primary
            )))
        } else if assetReference {
            reference = .asset(SceneVFSAssetPath(assetPath)!)
        } else {
            reference = .graph(graphTexture())
        }
        return sampler.purpose(for: reference)?.reportToken ?? "unproven"
    } catch {
        return "schema-invalid"
    }
}

func samplerReadinessSchemaToken(_ metadata: String) -> String {
    let shader = contract(
        revision: "sampler-readiness-schema",
        samplerMetadata: metadata
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true]
            ) else { return "preparation-failed" }
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema
            .activeSamplers(prepared)[0] else { return "missing" }
        let defaultToken: String = switch sampler.defaultTexture {
        case .asset: "asset"
        case .internalTarget: "internal"
        case nil: "none"
        }
        return "\(sampler.readinessCombo ?? "none")|\(defaultToken)"
    } catch {
        return "schema-invalid"
    }
}

func selfGatedReadinessSeedTokens() -> [String: String] {
    let annotation =
        #"{"material":"mask","mode":"opacitymask","combo":"MASK","default":"util/white"}"#

    func token(
        _ label: String,
        conditionalSource: String,
        readiness: Bool
    ) -> String {
        let shader = contract(
            revision: "self-gated-readiness-\(label)",
            vertexSourceOverride: "void main() { gl_Position = vec4(0.0); }",
            fragmentSourceOverride: """
            \(conditionalSource)
            void main() {
                vec4 color = vec4(1.0);
            #if MASK == 1
                color *= texSample2D(g_Texture1, vec2(0.5));
            #endif
                gl_FragColor = color;
            }
            """
        )
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: [:],
            textureReadiness: [1: readiness]
        ) {
        case let .accepted(prepared):
            guard let samplers = try? SceneResolvedMaterialShaderSchema
                .activeSamplers(prepared) else { return "schema-invalid" }
            return "accepted:" + samplers.keys.sorted().map(String.init)
                .joined(separator: ",")
        case let .rejected(failure):
            return "\(failure.phase.rawValue)/\(failure.code.rawValue):"
                + failure.details.joined(separator: ",")
        case .notApplicable:
            return "not-applicable"
        }
    }

    let exact = """
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    """
    let nonUnitGuard = """
    #if MASK > 0
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    """
    let branched = """
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #else
    float inactiveBranchProbe = 0.0;
    #endif
    """
    let nested = """
    #if MASK == 1
    #if MASK == 1
    uniform sampler2D g_Texture1; // \(annotation)
    #endif
    #endif
    """
    return [
        "ready": token("ready", conditionalSource: exact, readiness: true),
        "unready": token("unready", conditionalSource: exact, readiness: false),
        "nonUnitGuard": token(
            "non-unit-guard",
            conditionalSource: nonUnitGuard,
            readiness: true
        ),
        "elseBranch": token(
            "else-branch",
            conditionalSource: branched,
            readiness: true
        ),
        "nestedGuard": token(
            "nested-guard",
            conditionalSource: nested,
            readiness: true
        ),
    ]
}

func implicitFramebufferProjectionToken(
    defaultAssetPath: String
) -> String {
    let shader = contract(
        revision: "implicit-stock-default-\(defaultAssetPath.replacingOccurrences(of: "/", with: "-"))",
        secondSamplerMetadata: "{\"default\":\"\(defaultAssetPath)\"}"
    )
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true, 1: true]
            ) else { return "preparation-failed" }
    do {
        let samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template(shader, includePrimaryCandidate: false),
            samplers: samplers
        ).sorted().map(String.init).joined(separator: ",")
    } catch {
        return "schema-invalid"
    }
}

func implicitFramebufferCandidateProjectionToken(
    assetPath: String
) -> String {
    let shader = contract(revision: "implicit-stock-candidate")
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true, 1: true]
            ) else { return "preparation-failed" }
    do {
        let samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template(
                shader,
                includePrimaryCandidate: false,
                secondReference: .asset(SceneVFSAssetPath(assetPath)!)
            ),
            samplers: samplers
        ).sorted().map(String.init).joined(separator: ",")
    } catch {
        return "schema-invalid"
    }
}

func implicitFramebufferGraphCandidateProjectionToken() -> String {
    let shader = contract(revision: "implicit-graph-candidate")
    guard case let .accepted(prepared) =
            SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: shader,
                combos: [:],
                textureReadiness: [0: true, 1: true]
            ) else { return "preparation-failed" }
    do {
        let samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        return SceneResolvedMaterialShaderSchema.implicitFramebufferSlots(
            template: template(
                shader,
                includePrimaryCandidate: false,
                secondReference: .graph(graphTexture())
            ),
            samplers: samplers
        ).sorted().map(String.init).joined(separator: ",")
    } catch {
        return "schema-invalid"
    }
}

func reachableConditionalPurposeToken() -> String {
    let shader = contract(
        revision: "conditional-sampler-schema",
        samplerMetadata: #"{"material":"framebuffer"}"#,
        secondSamplerMetadata:
            #"{"material":"albedo","default":"textures/conditional.tex"}"#,
        conditionalSecondSampler: true
    )
    var conditionalTemplate = template(
        shader,
        secondReference: .asset(
            SceneVFSAssetPath("textures/conditional.tex")!
        )
    )
    conditionalTemplate = Template.validated(
        textureSlots: conditionalTemplate.textureSlots,
        combos: [.init(name: "EXTRA", value: 1)],
        uniformDeclarations: conditionalTemplate.uniformDeclarations,
        renderState: conditionalTemplate.renderState,
        graphRole: conditionalTemplate.graphRole,
        shaderContract: conditionalTemplate.shaderContract,
        diagnosticProvenance: conditionalTemplate.diagnosticProvenance
    )!
    do {
        guard let sampler = try SceneResolvedMaterialShaderSchema.reachableSamplers(
            conditionalTemplate,
            implicitFramebufferIdentity: graphTexture()
        )[1]?.first else { return "missing" }
        let reference = Template.TextureReference.asset(
            SceneVFSAssetPath("textures/conditional.tex")!
        )
        return sampler.purpose(for: reference)?.reportToken ?? "unproven"
    } catch {
        return "schema-invalid"
    }
}


final class SceneResolvedMaterialFinalizerFramebufferCases {
    unowned let fixture: SceneResolvedMaterialFinalizerFixture

    init(_ fixture: SceneResolvedMaterialFinalizerFixture) {
        self.fixture = fixture
    }

    lazy var implicitFramebufferProgram = finalize(
        shader: contract(
            revision: "implicit-framebuffer",
            samplerMetadata: #"{"material":"framebuffer"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var caseInsensitiveFramebufferProgram = finalize(
        shader: contract(
            revision: "implicit-framebuffer-case",
            samplerMetadata: #"{"material":"Framebuffer"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var historicalFramebufferProgram = finalize(
        shader: contract(
            revision: "historical-framebuffer-material-alias",
            samplerMetadata:
                #"{"material":"ui_editor_properties_framebuffer","hidden":true}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var previousAliasProgram = finalize(
        shader: contract(
            revision: "material-previous",
            samplerMetadata: #"{"material":"previous"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var explicitFramebufferProgram = finalize(
        shader: contract(
            revision: "explicit-before-implicit",
            samplerMetadata: #"{"material":"framebuffer"}"#
        ),
        device: self.fixture.device,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var scalarRedConsumerProgram = finalize(
        shader: contract(
            revision: "scalar-red-consumer",
            directRedInput: true
        ),
        device: self.fixture.device,
        primaryReference: .graph(framebufferTexture()),
        primaryGraphTextureRole: .framebuffer,
        additionalEntries: [
            .graph(framebufferTexture()): .ready(.init(
                publication: publication(
                    self.fixture.device,
                    requestIdentity: .graph(framebufferTexture()),
                    purpose: .preservedChannels,
                    content: .scalarRedUnorm,
                    sampling: .linearRepeat,
                    pixelFormat: .r8Unorm,
                    candidateIdentity: .provider(.graph(
                        allocationGeneration: 1,
                        physicalToken: "fixture-scalar-target"
                    ))
                ),
                resourceGeneration: 1
            )),
        ],
        outputStorage: .scalarRedUnorm,
        graphTextureFormatFacts: [framebufferTexture(): .r8]
    )

    lazy var scalarRedForgedTEXFormat = finalize(
        shader: contract(
            revision: "scalar-red-forged-tex-format",
            directRedInput: true
        ),
        device: self.fixture.device,
        primaryReference: .graph(framebufferTexture()),
        primaryGraphTextureRole: .framebuffer,
        additionalEntries: [
            .graph(framebufferTexture()): .ready(.init(
                publication: publication(
                    self.fixture.device,
                    requestIdentity: .graph(framebufferTexture()),
                    purpose: .preservedChannels,
                    content: .scalarRedUnorm,
                    sampling: .linearRepeat,
                    pixelFormat: .r8Unorm,
                    authoredFormat: .r8,
                    candidateIdentity: .provider(.graph(
                        allocationGeneration: 1,
                        physicalToken: "fixture-scalar-target-forged-tex-format"
                    ))
                ),
                resourceGeneration: 1
            )),
        ],
        outputStorage: .scalarRedUnorm,
        graphTextureFormatFacts: [framebufferTexture(): .r8]
    )

    lazy var scalarRedWrongFormat = finalize(
        shader: contract(
            revision: "scalar-red-wrong-format",
            directRedInput: true
        ),
        device: self.fixture.device,
        primaryReference: .graph(framebufferTexture()),
        primaryGraphTextureRole: .framebuffer,
        additionalEntries: [
            .graph(framebufferTexture()): .ready(.init(
                publication: publication(
                    self.fixture.device,
                    requestIdentity: .graph(framebufferTexture()),
                    purpose: .preservedChannels,
                    content: .scalarRedUnorm,
                    sampling: .linearRepeat,
                    pixelFormat: .r8Unorm,
                    authoredFormat: .rgba8888,
                    candidateIdentity: .provider(.graph(
                        allocationGeneration: 1,
                        physicalToken: "fixture-scalar-target-wrong-format"
                    ))
                ),
                resourceGeneration: 1
            )),
        ],
        outputStorage: .scalarRedUnorm,
        graphTextureFormatFacts: [framebufferTexture(): .r8]
    )

    lazy var scalarRedConsumerIdentity: Bool = {
        guard case let .success(program) = self.scalarRedConsumerProgram,
              let slot = program.textureSlots[0],
              slot.expectedPurpose == .preservedChannels,
              slot.resource.publication.candidate.content == .scalarRedUnorm,
              slot.resource.publication.candidate.authoredFormat == nil,
              slot.resource.publication.candidate.sampling == .linearRepeat,
              program.frontendProgram.textureBindings.first?.channelUse == .redOnly,
              case .scalarRedUnorm = program.outputContract else {
            return false
        }
        return true
    }()

    lazy var rgbaDataConsumerProgram = finalize(
        shader: contract(revision: "rgba-data-consumer"),
        device: self.fixture.device,
        primaryReference: .graph(framebufferTexture()),
        primaryGraphTextureRole: .framebuffer,
        additionalEntries: [
            .graph(framebufferTexture()): .ready(.init(
                publication: publication(
                    self.fixture.device,
                    requestIdentity: .graph(framebufferTexture()),
                    purpose: .preservedChannels,
                    content: .data,
                    sampling: .linearRepeat,
                    pixelFormat: .rgba8Unorm,
                    candidateIdentity: .provider(.graph(
                        allocationGeneration: 1,
                        physicalToken: "fixture-rgba-data-target"
                    ))
                ),
                resourceGeneration: 1
            )),
        ],
        outputStorage: .preservedRGBAUnorm
    )

    lazy var rgbaDataConsumerIdentity: Bool = {
        guard case let .success(program) = self.rgbaDataConsumerProgram,
              let slot = program.textureSlots[0],
              slot.expectedPurpose == .preservedChannels,
              slot.resource.publication.candidate.content == .data,
              slot.resource.publication.candidate.authoredFormat == nil,
              slot.resource.publication.candidate.sampling == .linearRepeat,
              case .preservedRGBAUnorm = program.outputContract else {
            return false
        }
        return true
    }()

    lazy var graphRoleIdentityFailure = finalize(
        shader: contract(
            revision: "graph-role-identity-invariant",
            samplerMetadata: #"{"material":"framebuffer"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        graphBindingsOverride: [.init(slot: 0, texture: .effectOutput)],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var programAssemblyIdentityFailure = finalize(
        shader: contract(revision: "program-assembly-identity-invariant"),
        device: self.fixture.device,
        primaryGraphTextureRole: .effectOutput
    )

    lazy var implicitFramebufferTyped: Bool = {
        guard case let .success(program) = self.implicitFramebufferProgram,
              let slot = program.textureSlots[0],
              case let .graph(identity) = slot.reference else { return false }
        return identity == graphTexture()
            && slot.diagnosticSelectionProvenance
                == .implicitFramebuffer
            && slot.graphInputSourceFact?.provenance
                == .explicitMaterialAlias
    }()

    lazy var previousAliasTyped: Bool = {
        guard case let .success(program) = self.previousAliasProgram,
              let slot = program.textureSlots[0],
              case let .graph(identity) = slot.reference else { return false }
        return identity == graphTexture()
            && slot.diagnosticSelectionProvenance == .materialGraphInputAlias
    }()

    lazy var historicalFramebufferTyped: Bool = {
        guard case let .success(program) = self.historicalFramebufferProgram,
              let slot = program.textureSlots[0],
              case let .graph(identity) = slot.reference else { return false }
        return identity == graphTexture()
            && slot.diagnosticSelectionProvenance
                == .implicitFramebuffer
            && slot.graphInputSourceFact?.provenance
                == .explicitMaterialAlias
            && slot.expectedPurpose == .premultipliedColor
    }()

    lazy var stockNoisePath = SceneVFSAssetPath("util/noise")!

    lazy var stockNoiseIdentity = SceneAssetTextureIdentity(
        path: self.stockNoisePath,
        purpose: .noise
    )

    lazy var stockDefaultProgram = finalize(
        shader: contract(
            revision: "stock-default-program",
            secondSamplerMetadata: #"{"default":"util/noise"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        additionalEntries: [
            .asset(self.stockNoiseIdentity): readyStatus(
                self.fixture.device,
                identity: .asset(self.stockNoiseIdentity),
                purpose: .noise,
                content: .data
            ),
        ],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var stockDefaultProgramPreservesSnapshotAtoms: Bool = {
        guard case let .success(program) = self.stockDefaultProgram,
              let source = program.textureSlots[0],
              let noise = program.textureSlots[1],
              case let .graph(sourceReference) = source.reference,
              case let .asset(noiseReference) = noise.reference,
              case let .provider(sourceGeneration) =
                  source.resource.publication.candidate.generation,
              case let .provider(noiseGeneration) =
                  noise.resource.publication.candidate.generation,
              case .color(.resolved(.premultipliedAlpha)) =
                  source.resource.publication.candidate.content,
              case .data = noise.resource.publication.candidate.content else {
            return false
        }
        let sourceCandidate = source.resource.publication.candidate
        let noiseCandidate = noise.resource.publication.candidate
        return program.frontendProgram.textureBindings.map(\.slot) == [0, 1]
            && sourceReference == graphTexture()
            && noiseReference == self.stockNoisePath
            && source.registryIdentity == .graph(graphTexture())
            && noise.registryIdentity == .asset(self.stockNoiseIdentity)
            && source.diagnosticSelectionProvenance
                == .implicitFramebuffer
            && noise.diagnosticSelectionProvenance == .shaderDefault
            && source.expectedPurpose == .premultipliedColor
            && noise.expectedPurpose == .noise
            && source.resource.resourceGeneration == 1
            && noise.resource.resourceGeneration == 7
            && source.resource.publication.contentGeneration == 1
            && noise.resource.publication.contentGeneration == 7
            && sourceGeneration == 1
            && noiseGeneration == 7
            && sourceCandidate.physicalSize == CGSize(width: 2, height: 2)
            && sourceCandidate.mappedSize == CGSize(width: 2, height: 2)
            && noiseCandidate.physicalSize == CGSize(width: 2, height: 2)
            && noiseCandidate.mappedSize == CGSize(width: 2, height: 2)
            && sourceCandidate.sampling == .directImageFallback
            && noiseCandidate.sampling == .directImageFallback
            && sourceCandidate.sampling.rawFlags == nil
            && noiseCandidate.sampling.rawFlags == nil
            && sourceCandidate.texture !== noiseCandidate.texture
    }()

    lazy var explicitFramebufferPreserved: Bool = {
        guard case let .success(program) = self.explicitFramebufferProgram,
              let slot = program.textureSlots[0] else { return false }
        return slot.diagnosticSelectionProvenance
            == .authored(.explicitBinding)
    }()

    lazy var implicitDefaultPath = SceneVFSAssetPath(
        "textures/implicit-default.tex"
    )!

    lazy var shaderDefaultBeforeImplicit = finalize(
        shader: contract(
            revision: "shader-default-before-implicit",
            samplerMetadata:
                #"{"material":"framebuffer","mode":"opacitymask","default":"textures/implicit-default.tex"}"#
        ),
        device: self.fixture.device,
        includePrimaryCandidate: false,
        additionalEntries: [
            .asset(.init(
                path: self.implicitDefaultPath,
                purpose: .mask
            )): readyStatus(
                self.fixture.device,
                identity: .asset(.init(
                    path: self.implicitDefaultPath,
                    purpose: .mask
                )),
                purpose: .mask,
                content: .data
            ),
        ],
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var shaderDefaultPreserved: Bool = {
        guard case let .success(program) = self.shaderDefaultBeforeImplicit,
              let slot = program.textureSlots[0],
              slot.reference == .asset(self.implicitDefaultPath),
              slot.registryIdentity == .asset(.init(path: self.implicitDefaultPath, purpose: .mask)),
              slot.expectedPurpose == .mask,
              slot.diagnosticSelectionProvenance == .shaderDefault,
              case .data = slot.resource.publication.candidate.content,
              case let .color(output) = program.semanticIdentity.outputContract else { return false }
        return program.frontendProgram.textureBindings.map(\.slot) == [0]
            && program.frontendProgram.colorBoundary?.colorInputSlots == []
            && output.fragmentOutput == .straightAlpha
    }()

}
