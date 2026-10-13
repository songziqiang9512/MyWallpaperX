// Complete uniforms cases; state remains owned by the single fixture.
import Foundation
import Metal
import simd


final class SceneResolvedMaterialFinalizerDynamicUniformCases {
    unowned let fixture: SceneResolvedMaterialFinalizerFixture

    init(_ fixture: SceneResolvedMaterialFinalizerFixture) {
        self.fixture = fixture
    }

    lazy var tintField = self.fixture.preparation.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "u_Tint"
    }!

    lazy var tintRange = self.tintField.offset ..< self.tintField.offset + self.tintField.type.byteSize

    lazy var tintDefaultCorrect = self.fixture.preparation.programA.uniformBytes.subdata(in: self.tintRange)
        == SceneResolvedMaterialUniformEncoder.encodeComponents(
            [1, 0.5, 0.25],
            as: self.tintField.type
        )!

    lazy var timeField = self.fixture.preparation.programA.frontendProgram.uniformLayout.fields.first {
        $0.name == "g_Time"
    }!

    lazy var timeRange = self.timeField.offset ..< self.timeField.offset + self.timeField.type.byteSize

    lazy var hostDefaultIgnored = self.fixture.preparation.programA.uniformBytes.subdata(in: self.timeRange)
        == SceneResolvedMaterialUniformEncoder.encodeComponents(
            [2],
            as: self.timeField.type
        )!

    lazy var explicitTint = finalize(
        shader: contract(revision: "explicit-tint"),
        device: self.fixture.device,
        uniformDeclarations: [staticDeclaration("Tint", components: [0.2, 0.4, 0.6])]
    )

    lazy var explicitOverrideCorrect: Bool = {
        let explicitOverrideCorrect: Bool
        if case let .success(program) = self.explicitTint,
           let field = program.frontendProgram.uniformLayout.fields.first(where: {
               $0.name == "u_Tint"
           }) {
            let range = field.offset ..< field.offset + field.type.byteSize
            explicitOverrideCorrect = program.uniformBytes.subdata(in: range)
                == SceneResolvedMaterialUniformEncoder.encodeComponents(
                    [0.2, 0.4, 0.6],
                    as: field.type
                )!
        } else {
            explicitOverrideCorrect = false
        }
        return explicitOverrideCorrect
    }()

    lazy var maskMetadata = #"{"mode":"opacitymask"}"#

    lazy var assetPath = SceneVFSAssetPath("textures/fixture-mask.tex")!

    lazy var assetProgram = finalize(
        shader: contract(
            revision: "asset-reference",
            secondSamplerMetadata: self.maskMetadata
        ),
        device: self.fixture.device,
        secondReference: .asset(self.assetPath),
        additionalEntries: [
            .asset(.init(path: self.assetPath, purpose: .mask)):
                readyStatus(
                    self.fixture.device,
                    identity: .asset(.init(path: self.assetPath, purpose: .mask)),
                    purpose: .mask,
                    content: .data
                ),
        ]
    )

    lazy var maskedPath = SceneVFSAssetPath("textures/masked-alpha.tex")!

    lazy var maskedIdentity = SceneFrameTextureIdentity.asset(.init(
        path: self.maskedPath,
        purpose: .mask
    ))

    lazy var maskedShader = contract(
        revision: "masked-alpha",
        secondSamplerMetadata: self.maskMetadata,
        maskedAlpha: true
    )

    lazy var maskedProgram = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [dynamicAlphaDeclaration([
            .userProperty("opacity")
        ])],
        dynamicSource: .userProperty,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var maskedDynamicAlphaEncoded: Bool = {
        guard case let .success(program) = self.maskedProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_UserAlpha" }
              ),
              let maskSlot = program.textureSlots[1],
              maskSlot.reference == .asset(self.maskedPath),
              maskSlot.expectedPurpose == .mask,
              case .data = maskSlot.resource.publication.candidate.content,
              program.frontendProgram.colorBoundary?.colorInputSlots == [0]
        else { return false }
        guard case let .color(contract) =
                program.semanticIdentity.outputContract else { return false }
        return sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset) == 0.25
            && contract.fragmentOutput == .straightAlpha
            && inputAssociationMask(program) == 1
    }()

    lazy var directScalarWithinRange = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [directUserAlphaDeclaration()],
        dynamicSource: .userProperty,
        dynamicAlphaValue: .scalar(0.4),
        authoredAlphaValue: .scalar(0.75),
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var directScalarOutOfRange = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [directUserAlphaDeclaration(fallback: 2)],
        dynamicSource: .userProperty,
        dynamicAlphaValue: .scalar(2),
        authoredAlphaValue: .scalar(0.75),
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var directScalarInvalidFallback = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [directUserAlphaDeclaration(fallback: 1.5)],
        dynamicSource: .userProperty,
        dynamicAlphaValue: .scalar(2),
        authoredAlphaValue: .scalar(1.5),
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var directScalarTypeMismatch = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [directUserAlphaDeclaration()],
        dynamicSource: .userProperty,
        dynamicAlphaValue: .vector3(2, 2, 2),
        authoredAlphaValue: .vector3(1, 1, 1),
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var directUserPropertyScalarRangeFallback: Bool = {
        guard case let .success(live) = self.directScalarWithinRange,
              case let .success(fallback) = self.directScalarOutOfRange,
              let liveField = live.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "g_UserAlpha" }
              ),
              let fallbackField = fallback.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "g_UserAlpha" }
              ) else { return false }
        return sceneResolvedMaterialFixtureFloat(live.uniformBytes, at: liveField.offset) == 0.4
            && sceneResolvedMaterialFixtureFloat(fallback.uniformBytes, at: fallbackField.offset) == 0.75
            && failureToken(self.directScalarInvalidFallback)
                == "uniform/dynamicUniformBindingInvalid"
            && failureToken(self.directScalarTypeMismatch)
                == "uniform/dynamicUniformBindingInvalid"
    }()

    lazy var sceneScriptAlphaProgram = finalize(
        shader: self.maskedShader,
        device: self.fixture.device,
        includePrimaryCandidate: false,
        secondReference: .asset(self.maskedPath),
        additionalEntries: [
            self.maskedIdentity: readyStatus(
                self.fixture.device,
                identity: self.maskedIdentity,
                purpose: .mask,
                content: .data
            ),
        ],
        uniformDeclarations: [dynamicAlphaDeclaration([.sceneScript])],
        dynamicSource: .sceneScript,
        implicitFramebufferIdentity: graphTexture()
    )

    lazy var sceneScriptDynamicAlphaEncoded: Bool = {
        guard case let .success(program) = self.sceneScriptAlphaProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                where: { $0.name == "g_UserAlpha" }
              )
        else { return false }
        return sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset) == 0.25
    }()

    lazy var timelineVectorA = finalize(
        shader: contract(revision: "timeline-vector-shared"),
        device: self.fixture.device,
        uniformDeclarations: [dynamicDeclaration([.timeline])],
        textureFrameIndex: 5,
        dynamicFrameIndex: 5,
        frameInputIndex: 5,
        dynamicSource: .timeline,
        dynamicTintValue: .vector3(0.1, 0.2, 0.3)
    )

    lazy var timelineVectorB = finalize(
        shader: contract(revision: "timeline-vector-shared"),
        device: self.fixture.device,
        uniformDeclarations: [dynamicDeclaration([.timeline])],
        textureFrameIndex: 6,
        dynamicFrameIndex: 6,
        frameInputIndex: 6,
        dynamicSource: .timeline,
        dynamicTintValue: .vector3(0.7, 0.6, 0.5)
    )

    lazy var timelineVectorTypeMismatch = finalize(
        shader: contract(revision: "timeline-vector-type-mismatch"),
        device: self.fixture.device,
        uniformDeclarations: [dynamicDeclaration([.timeline])],
        dynamicSource: .timeline,
        dynamicTintValue: .vector2(0.1, 0.2),
        authoredTintValue: .vector2(1, 0.5)
    )

    lazy var timelineVectorUpdatesProgramWithoutTopologyChange: Bool = {
        guard case let .success(first) = self.timelineVectorA,
              case let .success(second) = self.timelineVectorB,
              let field = first.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Tint" }
              ) else { return false }
        let range = field.offset ..< field.offset + field.type.byteSize
        return first.semanticIdentity == second.semanticIdentity
            && first.preparedShader.cacheKey == second.preparedShader.cacheKey
            && first.uniformBytes.subdata(in: range)
                != second.uniformBytes.subdata(in: range)
    }()

    lazy var scalarSplatShader = contract(
        revision: "user-property-scalar-float2-splat",
        semanticProbes: false,
        scalarSplatScale: true
    )

    lazy var scalarSplatProgram = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration()],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(0.6)
    )

    lazy var scalarSplatAuthoredProgram = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration()],
        dynamicSource: nil,
        authoredScaleValue: .scalar(0.6)
    )

    lazy var rangedScalarSplatShader = contract(
        revision: "user-property-scalar-float2-authored-range-sentinel",
        semanticProbes: false,
        scalarSplatScale: true,
        scalarSplatRange: "[0.01,2]"
    )

    lazy var authoredRangeSentinelProgram = finalize(
        shader: self.rangedScalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0, 0])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(0),
        authoredScaleValue: .scalar(0)
    )

    lazy var outOfRangeLiveFallsBackToAuthoredSentinel = finalize(
        shader: self.rangedScalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0, 0])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(-0.5),
        authoredScaleValue: .scalar(0)
    )

    lazy var mismatchedOutOfRangeAuthoredSentinel = finalize(
        shader: self.rangedScalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0, 0])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(-0.5),
        authoredScaleValue: .scalar(-0.25)
    )

    lazy var producerDomainScalarShader = contract(
        revision: "user-property-scalar-producer-domain",
        semanticProbes: false,
        scalarSplatScale: true,
        scalarSplatType: "float",
        scalarSplatDefault: "1",
        scalarSplatRange: "[0.01,2]"
    )

    lazy var producerDomainZeroProgram = finalize(
        shader: self.producerDomainScalarShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0.05])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(0),
        authoredScaleValue: .scalar(0.05),
        userPropertyScaleRange: 0 ... 0.3
    )

    lazy var producerDomainFractionProgram = finalize(
        shader: self.producerDomainScalarShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0.05])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(0.005),
        authoredScaleValue: .scalar(0.05),
        userPropertyScaleRange: 0 ... 0.3
    )

    lazy var producerDomainOverflowProgram = finalize(
        shader: self.producerDomainScalarShader,
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [0.05])],
        dynamicSource: .userProperty,
        dynamicScaleValue: .scalar(0.31),
        authoredScaleValue: .scalar(0.05),
        userPropertyScaleRange: 0 ... 0.3
    )

    lazy var staticScalarSplatProgram = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var userPropertyScalarFloat2SplatEncoded: Bool = {
        guard case let .success(program) = self.scalarSplatProgram,
              case let .success(authored) = self.scalarSplatAuthoredProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ) else { return false }
        return field.type == .float2
            && sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset) == 0.6
            && sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset + 4) == 0.6
            && sceneResolvedMaterialFixtureFloat(authored.uniformBytes, at: field.offset) == 0.6
            && sceneResolvedMaterialFixtureFloat(authored.uniformBytes, at: field.offset + 4) == 0.6
    }()

    lazy var authoredOutOfRangeScalarFloat2SentinelPreserved: Bool = {
        guard case let .success(authored) = self.authoredRangeSentinelProgram,
              case let .success(fallback) =
                self.outOfRangeLiveFallsBackToAuthoredSentinel,
              let authoredField = authored.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ), let fallbackField = fallback.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ) else { return false }
        return sceneResolvedMaterialFixtureFloat(authored.uniformBytes, at: authoredField.offset) == 0
            && sceneResolvedMaterialFixtureFloat(authored.uniformBytes, at: authoredField.offset + 4) == 0
            && sceneResolvedMaterialFixtureFloat(fallback.uniformBytes, at: fallbackField.offset) == 0
            && sceneResolvedMaterialFixtureFloat(fallback.uniformBytes, at: fallbackField.offset + 4) == 0
            && failureToken(self.mismatchedOutOfRangeAuthoredSentinel)
                == "uniform/dynamicUniformBindingInvalid"
    }()

    lazy var directUserPropertyScalarProducerDomainPreserved: Bool = {
        guard case let .success(zero) = self.producerDomainZeroProgram,
              case let .success(fraction) = self.producerDomainFractionProgram,
              case let .success(overflow) = self.producerDomainOverflowProgram,
              let zeroField = zero.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ), let fractionField = fraction.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ), let overflowField = overflow.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ) else { return false }
        return sceneResolvedMaterialFixtureFloat(zero.uniformBytes, at: zeroField.offset) == 0
            && sceneResolvedMaterialFixtureFloat(fraction.uniformBytes, at: fractionField.offset)
                == Float(0.005)
            && sceneResolvedMaterialFixtureFloat(overflow.uniformBytes, at: overflowField.offset)
                == Float(0.05)
    }()

    lazy var staticScalarFloat2SplatEncoded: Bool = {
        guard case let .success(program) = self.staticScalarSplatProgram,
              let field = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ) else { return false }
        return field.type == .float2
            && field.arrayCount == nil
            && sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset) == 0.4
            && sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset + 4) == 0.4
    }()

    lazy var unequalDefaultStaticScalarSplat = finalize(
        shader: contract(
            revision: "static-scalar-float2-unequal-default",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatDefault: "1 0.5"
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var missingDefaultStaticScalarSplat = finalize(
        shader: contract(
            revision: "static-scalar-float2-missing-default",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatDefault: nil
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var nonFiniteDefaultStaticScalarSplat = finalize(
        shader: contract(
            revision: "static-scalar-float2-nonfinite-default",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatDefault: "nan nan"
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var wrongABIStaticScalarSplat = finalize(
        shader: contract(
            revision: "static-scalar-float3-rejected",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatType: "vec3",
            scalarSplatDefault: "1 1 1"
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var arrayStaticScalarSplat = finalize(
        shader: contract(
            revision: "static-scalar-float2-array-rejected",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatArray: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [0.4],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var nonFiniteStaticScalarSplat = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration(
                "scale",
                components: [.nan],
                scalarProjectionProven: true
            ),
        ]
    )

    lazy var unprovenStaticScalarSplat = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration("scale", components: [0.4]),
        ]
    )

    lazy var scalarShaderDefaultOnly = finalize(
        shader: contract(
            revision: "scalar-shader-default-not-projected",
            semanticProbes: false,
            scalarSplatScale: true,
            scalarSplatDefault: "1"
        ),
        device: self.fixture.device
    )

    lazy var exactStaticFloat2Program = finalize(
        shader: self.scalarSplatShader,
        device: self.fixture.device,
        uniformDeclarations: [
            staticDeclaration("scale", components: [0.4, 0.7]),
        ]
    )

    lazy var exactStaticFloat2Preserved: Bool = {
        guard case let .success(program) = self.exactStaticFloat2Program,
              let field = program.frontendProgram.uniformLayout.fields.first(
                  where: { $0.name == "u_Scale" }
              ) else { return false }
        return sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset) == 0.4
            && sceneResolvedMaterialFixtureFloat(program.uniformBytes, at: field.offset + 4) == 0.7
    }()

    lazy var unequalScalarSplatFallback = finalize(
        shader: contract(
            revision: "user-property-scalar-float2-unequal",
            semanticProbes: false,
            scalarSplatScale: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(fallback: [1, 0.5])],
        dynamicSource: .userProperty
    )

    lazy var nonUserScalarSplatContributor = finalize(
        shader: contract(
            revision: "timeline-scalar-float2-rejected",
            semanticProbes: false,
            scalarSplatScale: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(
            contributors: [.timeline]
        )],
        dynamicSource: .timeline
    )

    lazy var extraKeyScalarSplat = finalize(
        shader: contract(
            revision: "user-property-scalar-float2-extra-key",
            semanticProbes: false,
            scalarSplatScale: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(
            bindingKeys: ["extra", "user", "value"]
        )],
        dynamicSource: .userProperty
    )

    lazy var scriptKeyScalarSplat = finalize(
        shader: contract(
            revision: "user-property-scalar-float2-script-key",
            semanticProbes: false,
            scalarSplatScale: true
        ),
        device: self.fixture.device,
        uniformDeclarations: [dynamicScaleDeclaration(
            bindingKeys: ["script", "user", "value"]
        )],
        dynamicSource: .userProperty
    )

}
