#!/usr/bin/env python3

"""R3 static material Template projection and fail-closed graph boundaries."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PROGRAM_SOURCE = SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialProgram.swift"
TEXTURE_CANDIDATE_SOURCE = SCENE_ROOT / "Resources/SceneTextureCandidate.swift"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneShaderMalformedMetadataAdmission.swift",
    SCENE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialEffectIngress.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
]


SUPPORT = r'''
import Foundation

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

enum SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Bool?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]

        init(
            rawValue: String,
            valueKind: String = "number",
            userBinding: String? = nil,
            components: [Double]? = nil,
            timeline: Bool? = nil,
            timelineDiagnostics: [String] = [],
            scriptSource: String? = nil,
            bindingKeys: [String] = []
        ) {
            self.rawValue = rawValue
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
            self.timeline = timeline
            self.timelineDiagnostics = timelineDiagnostics
            self.scriptSource = scriptSource
            self.bindingKeys = bindingKeys
        }
    }
}

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material, instance, userTexture, explicitBinding
    }

    enum TextureSource {
        case asset(String)
        case userTexture(SceneEffectTextureInput)
        case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    }

    struct TextureCandidate {
        let source: TextureSource
        let provenance: TextureProvenance
    }

    struct TextureSlot {
        let index: Int
        let candidates: [TextureCandidate]
    }

    struct RenderState {
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let nodeIndex: Int
    let shaderPath: String
    let textureSlots: [TextureSlot?]
    let combos: [String: Int]
    let constants: [String: SceneDocument.ShaderValue]
    let userShaderValues: [String: String]
    let renderState: RenderState
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Template = SceneResolvedMaterialTemplate

private func effectKey(_ effectIndex: Int = 2) -> Graph.EffectKey {
    .init(layerID: 42, effectIndex: effectIndex, descriptorID: "effect-\(effectIndex)")
}

private func layerSource() -> Graph.TextureIdentity {
    .init(kind: .layerSource, layerID: 42, effect: nil, name: nil)
}

private func effectOutput(_ key: Graph.EffectKey = effectKey()) -> Graph.TextureIdentity {
    .init(kind: .effectOutput, layerID: 42, effect: key, name: nil)
}

private func framebuffer(
    _ name: String,
    key: Graph.EffectKey = effectKey()
) -> Graph.TextureIdentity {
    .init(kind: .framebuffer, layerID: 42, effect: key, name: name)
}

private func node(
    index: Int = 7,
    key: Graph.EffectKey = effectKey(),
    target: Graph.TextureIdentity? = nil,
    binding: Graph.TextureIdentity? = nil,
    bindingSlot: Int? = 1,
    instancePassIndex: Int? = 3
) -> Graph.Node {
    .init(
        nodeIndex: index,
        effect: key,
        definitionPassIndex: 0,
        materialOrdinal: 0,
        instancePassIndex: instancePassIndex,
        kind: .material,
        materialPath: "materials/pass.json",
        materialPassID: "materials/pass.json#0",
        target: target ?? effectOutput(key),
        bindings: binding.map {
            [.init(slot: bindingSlot, authoredName: nil, texture: $0, conditions: nil)]
        } ?? [],
        commandSource: nil,
        commandTarget: nil,
        compose: nil,
        conditions: nil
    )
}

private func graph(
    nodes: [Graph.Node]? = nil,
    nodeIndices: [Int] = [7],
    blockers: [Graph.Blocker] = [],
    input: Graph.TextureIdentity? = nil,
    output: Graph.TextureIdentity? = nil,
    renderTargets: [Graph.RenderTarget] = []
) -> Graph {
    let key = effectKey()
    let resolvedInput = input ?? layerSource()
    let resolvedOutput = output ?? effectOutput(key)
    return Graph(
        layerID: 42,
        effects: [.init(
            key: key,
            definitionPath: "effects/test.json",
            input: resolvedInput,
            output: resolvedOutput,
            nodeIndices: nodeIndices
        )],
        renderTargets: renderTargets,
        nodes: nodes ?? [node(key: key, target: resolvedOutput, binding: resolvedInput)],
        finalOutput: resolvedOutput,
        blockers: blockers
    )
}

private func contract(
    _ identity: String,
    hasGraph: Bool = true,
    diagnostics: [SceneShaderContract.Diagnostic] = [],
    recoverableMalformedCombo: Bool = false,
    fragmentSourceOverride: String? = nil
) -> SceneShaderContract {
    let vertexSource = recoverableMalformedCombo
        ? "// [COMBO] {\"material\":\"Category\",\"combo\":\"CATEGORY\",\"type\":\"options\",\"default\":0,\"options\":{\"Color\":0}}\n"
            + "void main() { gl_Position = vec4(0.0); }"
        : "void main() { gl_Position = vec4(0.0); }"
    let fragmentSource = fragmentSourceOverride ?? (recoverableMalformedCombo
        ? "// [COMBO] {\"material\":\"Category\",\"combo\":\"CATEGORY\",\"type\":\"options\",\"default\":0,\"options\":{Color\":0}}\r\n"
            + "void main() { gl_FragColor = vec4(1.0); }"
        : "void main() { gl_FragColor = vec4(1.0); }")
    let vertexParsed = SceneShaderContractSourceParser().parse(
        vertexSource,
        stageRelativePath: "root.vert"
    )
    let fragmentParsed = SceneShaderContractSourceParser().parse(
        fragmentSource,
        stageRelativePath: "root.frag"
    )
    let stages = [
        SceneShaderContract.Stage(
            kind: .vertex,
            relativePath: "root.vert",
            source: vertexSource,
            rawSHA256: "vertex-content",
            includes: [],
            annotations: vertexParsed.annotations,
            declarations: vertexParsed.declarations
        ),
        SceneShaderContract.Stage(
            kind: .fragment,
            relativePath: "root.frag",
            source: fragmentSource,
            rawSHA256: "fragment-content",
            includes: [],
            annotations: fragmentParsed.annotations,
            declarations: fragmentParsed.declarations
        ),
    ]
    let sourceGraph = SceneShaderSourceGraph(
        roots: [
            .init(label: "vertex", virtualPath: "root.vert"),
            .init(label: "fragment", virtualPath: "root.frag"),
        ],
        nodes: [
            .init(
                virtualPath: "root.vert",
                provenance: .package,
                source: vertexSource,
                rawSHA256: "vertex-content",
                byteCount: vertexSource.utf8.count
            ),
            .init(
                virtualPath: "root.frag",
                provenance: .package,
                source: fragmentSource,
                rawSHA256: "fragment-content",
                byteCount: fragmentSource.utf8.count
            ),
        ],
        edges: [],
        diagnostics: [],
        dependencySHA256: "dependency-content"
    )
    return .init(
        identity: identity,
        sourceKind: .authoredSource,
        stages: stages,
        diagnostics: diagnostics,
        canonicalSHA256: "diagnostic:\(identity)",
        sourceGraph: hasGraph ? sourceGraph : nil
    )
}

private func material(
    shaderPath: String = "effects/test",
    slots: [SceneResolvedMaterialNode.TextureSlot?] = .emptySlots,
    constants: [String: SceneDocument.ShaderValue] = [:],
    userShaderValues: [String: String] = [:],
    blending: String = "normal"
) -> SceneResolvedMaterialNode {
    .init(
        nodeIndex: 7,
        shaderPath: shaderPath,
        textureSlots: slots,
        combos: ["Z_COMBO": 2, "A_COMBO": 1],
        constants: constants,
        userShaderValues: userShaderValues,
        renderState: .init(
            blending: blending,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )
    )
}

private extension Array where Element == SceneResolvedMaterialNode.TextureSlot? {
    static var emptySlots: Self { Array(repeating: nil, count: 8) }
}

private func compile(
    _ material: SceneResolvedMaterialNode,
    graph value: Graph = graph(),
    contract shaderContract: SceneShaderContract? = nil,
    provenSceneScriptValueTargets: Set<SceneDynamicTarget> = []
) -> Result<Template, SceneResolvedMaterialFailure> {
    SceneResolvedMaterialTemplateCompiler.compile(
        material: material,
        graph: value,
        shaderContract: shaderContract ?? contract(material.shaderPath),
        provenSceneScriptValueTargets: provenSceneScriptValueTargets
    )
}

private func template(
    _ result: Result<Template, SceneResolvedMaterialFailure>
) -> Template? {
    guard case let .success(value) = result else { return nil }
    return value
}

private func failure(
    _ result: Result<Template, SceneResolvedMaterialFailure>
) -> SceneResolvedMaterialFailure? {
    guard case let .failure(value) = result else { return nil }
    return value
}

private func referenceToken(_ value: Template.TextureReference) -> String {
    switch value {
    case let .asset(request): return "asset:\(request.value)"
    case let .userProperty(request): return "property:\(request.key)"
    case let .provider(identity):
        switch identity {
        case let .system(name): return "system:\(name)"
        case let .namedLayerTarget(reference):
            return "named:\(reference.providerLayerID):\(reference.variant.rawValue)"
        }
    case let .graph(identity): return "graph:\(identity.kind.rawValue):\(identity.layerID)"
    }
}

private func assetFailure(_ path: String) -> SceneResolvedMaterialFailure? {
    var slots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
    slots[0] = .init(index: 0, candidates: [
        .init(source: .asset(path), provenance: .material),
    ])
    return failure(compile(material(slots: slots)))
}

@main
enum Harness {
    static func main() throws {
        var slots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        slots[1] = .init(index: 1, candidates: [
            .init(source: .asset("./Textures\\Base.PNG"), provenance: .material),
            .init(
                source: .userTexture(.init(kind: .property, value: " skin ")),
                provenance: .userTexture
            ),
            .init(source: .graph(layerSource()), provenance: .explicitBinding),
        ])
        slots[3] = .init(index: 3, candidates: [.init(
            source: .userTexture(.init(kind: .path, value: "Masks\\Shape.PNG")),
            provenance: .userTexture
        )])
        slots[4] = .init(index: 4, candidates: [.init(
            source: .userTexture(.init(kind: .system, value: " $mediaThumbnail ")),
            provenance: .userTexture
        )])
        slots[6] = .init(index: 6, candidates: [.init(
            source: .userTexture(.init(kind: .property, value: " tintTexture ")),
            provenance: .userTexture
        )])
        let projected = template(compile(material(slots: slots)))
        var namedSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        namedSlots[1] = .init(index: 1, candidates: [
            .init(
                source: .asset("_rt_imageLayerComposite_42_a"),
                provenance: .instance
            ),
        ])
        let namedTemplate = template(compile(material(slots: namedSlots)))
        let candidateTokens = projected?.textureSlots[1]?.candidates.map {
            referenceToken($0.reference)
        } ?? []
        let expectedRole = Template.GraphRole(
            effectInput: .layerSource,
            effectOutput: .effectOutput,
            nodeTarget: .effectOutput,
            bindings: [.init(slot: 1, texture: .layerSource)]
        )

        var unknownSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        unknownSlots[0] = .init(index: 0, candidates: [.init(
            source: .userTexture(.init(kind: .unknown, value: "mystery")),
            provenance: .userTexture
        )])
        var emptyCandidateSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        emptyCandidateSlots[5] = .init(index: 5, candidates: [])
        var wrongIndexSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        wrongIndexSlots[2] = .init(index: 3, candidates: [
            .init(source: .asset("textures/a.png"), provenance: .material),
        ])

        let constants: [String: SceneDocument.ShaderValue] = [
            "g_Static": .init(
                rawValue: "0 -0 0.5",
                valueKind: "vector",
                components: [0.0, -0.0, 0.5]
            ),
            "g_Strength": .init(rawValue: "0.75", components: [0.75]),
        ]
        let dynamicTemplate = template(compile(material(
            constants: constants,
            userShaderValues: ["g_Strength": " strength "]
        )))
        let materialOnlyGraph = graph(nodes: [node(
            binding: layerSource(),
            instancePassIndex: nil
        )])
        let materialOnlyStatic = template(compile(
            material(constants: [
                "g_Static": .init(rawValue: "0.5", components: [0.5]),
            ]),
            graph: materialOnlyGraph
        ))
        let materialOnlyDynamicFailure = failure(compile(
            material(
                constants: [
                    "g_Dynamic": .init(
                        rawValue: "0.5",
                        userBinding: "strength",
                        components: [0.5]
                    ),
                ]
            ),
            graph: materialOnlyGraph
        ))
        let staticDeclaration = dynamicTemplate?.uniformDeclarations.first {
            $0.name == "g_Static"
        }
        let dynamicDeclaration = dynamicTemplate?.uniformDeclarations.first {
            $0.name == "g_Strength"
        }
        let exactStaticBits: Bool
        if case let .staticExact(value)? = staticDeclaration?.value {
            exactStaticBits = value.componentBitPatterns == [
                Double(0.0).bitPattern,
                Double(-0.0).bitPattern,
                Double(0.5).bitPattern,
            ]
        } else { exactStaticBits = false }
        let mergedDynamic: Bool
        if case let .dynamic(value)? = dynamicDeclaration?.value,
           value.valueContributors == [.userProperty("strength")],
           value.scriptAttachments.isEmpty,
           case .effectConstant(42, 2, 3, "g_Strength") = value.target {
            mergedDynamic = value.authoredFallback?.componentBitPatterns
                == [Double(0.75).bitPattern]
        } else { mergedDynamic = false }
        let duplicateDynamic = template(compile(material(
            constants: ["g_Strength": .init(
                rawValue: "0.5", userBinding: "legacy", components: [0.5]
            )],
            userShaderValues: ["g_Strength": "strength"]
        )))
        let timelineControl = template(compile(material(constants: [
            "g_Time": .init(
                rawValue: "0.5",
                components: [0.5],
                timeline: true,
                scriptSource: """
                    export function mediaThumbnailChanged(event) {
                        if (event.hasThumbnail) {
                            var animation = thisObject.getAnimation();
                            animation.stop();
                            animation.play();
                        }
                    }
                    """
            ),
        ])))
        let unknownTimelineScript = template(compile(material(constants: [
            "g_Time": .init(
                rawValue: "0.5",
                components: [0.5],
                timeline: true,
                scriptSource: "return 1"
            ),
        ])))
        let boundedScriptTarget = SceneDynamicTarget.effectConstant(
            layerID: 42,
            effectIndex: 2,
            passIndex: 3,
            name: "g_Fade"
        )
        let boundedScriptValue = SceneDocument.ShaderValue(
            rawValue: "1",
            valueKind: "binding",
            components: [1],
            scriptSource: "project-owned bounded source",
            bindingKeys: ["script", "value"]
        )
        let boundedScriptUnproven = template(compile(material(constants: [
            "g_Fade": boundedScriptValue,
        ])))
        let boundedScriptProven = template(compile(
            material(constants: ["g_Fade": boundedScriptValue]),
            provenSceneScriptValueTargets: [boundedScriptTarget]
        ))
        let boundedPropertyScriptValue = SceneDocument.ShaderValue(
            rawValue: "1 1 1",
            valueKind: "binding",
            components: [1, 1, 1],
            scriptSource: "project-owned bounded media color source",
            bindingKeys: ["script", "scriptproperties", "value"]
        )
        let boundedPropertyScriptUnproven = template(compile(material(constants: [
            "g_Fade": boundedPropertyScriptValue,
        ])))
        let boundedPropertyScriptProven = template(compile(
            material(constants: ["g_Fade": boundedPropertyScriptValue]),
            provenSceneScriptValueTargets: [boundedScriptTarget]
        ))
        let boundedScriptWrongTarget = template(compile(
            material(constants: ["g_Fade": boundedScriptValue]),
            provenSceneScriptValueTargets: [.effectConstant(
                layerID: 42,
                effectIndex: 2,
                passIndex: 3,
                name: "g_Other"
            )]
        ))
        let playOnlyTimelineScript = template(compile(material(constants: [
            "g_Time": .init(
                rawValue: "0.5",
                components: [0.5],
                timeline: true,
                scriptSource: """
                    export function mediaThumbnailChanged(event) {
                        if (event.hasThumbnail) {
                            let animation = thisObject.getAnimation();
                            animation.play();
                        }
                    }
                    """
            ),
        ])))
        let directPlayTimelineScript = template(compile(material(constants: [
            "g_Time": .init(
                rawValue: "0.5",
                components: [0.5],
                timeline: true,
                scriptSource: """
                    export function mediaThumbnailChanged(event) {
                        if (event.hasThumbnail) {
                            thisObject.getAnimation().play();
                        }
                    }
                    """
            ),
        ])))
        let extendedRestartScript = template(compile(material(constants: [
            "g_Time": .init(
                rawValue: "0.5",
                components: [0.5],
                timeline: true,
                scriptSource: """
                    export function mediaThumbnailChanged(event) {
                        if (event.hasThumbnail) {
                            let animation = thisObject.getAnimation();
                            animation.stop();
                            animation.play();
                        }
                    }
                    thisObject.visible = true;
                    """
            ),
        ])))

        let baseNode = node(binding: layerSource())
        let previousOutput = effectOutput(effectKey(1))
        var chainedSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        chainedSlots[1] = .init(index: 1, candidates: [.init(
            source: .graph(previousOutput), provenance: .explicitBinding
        )])
        let chainedTemplate = template(compile(
            material(slots: chainedSlots), graph: graph(input: previousOutput)
        ))
        let selfInputFailure = failure(compile(
            material(), graph: graph(input: effectOutput(effectKey()))
        ))
        let foreignLayerInput = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: 99,
            effect: .init(layerID: 99, effectIndex: 1, descriptorID: "foreign"),
            name: nil
        )
        let foreignInputFailure = failure(compile(
            material(), graph: graph(input: foreignLayerInput)
        ))
        let blockedGraph = graph(blockers: [.init(
            effect: effectKey(),
            definitionPassIndex: nil,
            reason: .invalidBinding,
            detail: "fixture"
        )])
        let duplicateNodeGraph = graph(nodes: [baseNode, baseNode])
        let orphanNodeGraph = graph(
            nodes: [baseNode, node(index: 8, binding: layerSource())],
            nodeIndices: [7]
        )
        let duplicatePartitionGraph = graph(nodeIndices: [7, 7])
        let ownerMismatchGraph = graph(nodes: [
            node(key: effectKey(9), target: effectOutput(), binding: layerSource()),
        ])
        let ghost = framebuffer("ghost")
        let invalidBindingGraph = graph(nodes: [node(binding: ghost)])
        var ghostSlots = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        ghostSlots[1] = .init(index: 1, candidates: [
            .init(source: .graph(ghost), provenance: .explicitBinding),
        ])
        var wrongBindingSlot = [SceneResolvedMaterialNode.TextureSlot?].emptySlots
        wrongBindingSlot[2] = .init(index: 2, candidates: [
            .init(source: .graph(layerSource()), provenance: .explicitBinding),
        ])

        let escapedAssets = [
            "../secret.png", "/tmp/secret.png", "C:\\secret.png",
            "textures//secret.png", "textures/./secret.png", "textures/\u{7f}.png",
        ]
        let escapedShaders = [
            "../effects/a", "/effects/a", "C:\\effects\\a", "effects//a",
        ]
        let shaderNormalization = template(compile(
            material(shaderPath: " ./Effects\\A.vert "),
            contract: contract("effects/a.json")
        ))
        let shaderEscapeFailures = escapedShaders.allSatisfy {
            failure(compile(
                material(shaderPath: $0),
                contract: contract("effects/a")
            ))?.code == .shaderIdentityMismatch
        }
        let skippedMalformedMetadata = template(compile(
            material(),
            contract: contract("effects/test", diagnostics: [.init(
                code: .malformedAnnotation,
                message: "fixture malformed metadata",
                relativePath: "root.frag",
                line: 1
            )], recoverableMalformedCombo: true)
        ))
        let unsafeMalformedSampler = failure(compile(
            material(),
            contract: contract(
                "effects/test",
                diagnostics: [.init(
                    code: .malformedAnnotation,
                    message: "fixture malformed sampler metadata",
                    relativePath: "root.frag",
                    line: 1
                )],
                recoverableMalformedCombo: true,
                fragmentSourceOverride:
                    "uniform sampler2D g_Texture0; // {\"default\": }"
            )
        ))
        let fatalShaderDiagnostic = failure(compile(
            material(),
            contract: contract("effects/test", diagnostics: [.init(
                code: .unterminatedBlockComment,
                message: "fixture fatal source diagnostic",
                relativePath: "root.frag",
                line: nil
            )])
        ))
        let annotationDefaultTemplate = template(compile(
            material(),
            contract: contract(
                "effects/test",
                fragmentSourceOverride: """
                // [COMBO] {"combo":"SHADER_DEFAULT","default":31}
                void main() { gl_FragColor = vec4(1.0); }
                """
            )
        ))

        let bounded = SceneResolvedMaterialFailure(
            phase: .uniform,
            code: .uniformDeclarationInvalid,
            details: (0..<10).map { "\($0):" + String(repeating: "x", count: 200) }
        )
        let stableCodes: [SceneResolvedMaterialFailure.Code] = [
            .resourceSnapshotUnresolved,
            .textureBindingInvalid, .texturePurposeUnproven, .textureMetadataIncomplete,
            .shaderPreparationFailed, .samplerBindingOrderInvalid,
            .samplerBindingDuplicateSlot, .samplerBindingIdentityMismatch,
            .samplerInternalTargetUnsupported, .activePassUnsupported,
            .samplerVariantSchemaDivergence,
            .authoredSamplerSchemaInvalid, .shaderFrontendFailed,
            .uniformBindingInvalid, .uniformContributorPolicyUnproven,
            .uniformScriptAttachmentUnproven, .colorContractUnproven,
            .frameSnapshotMismatch, .identityInvariant,
        ]
        let stablePhases: [SceneResolvedMaterialFailure.Phase] = [
            .preparation, .frontend, .color,
        ]

        let result: [String: Bool] = [
            "eightSlotsPreserved": projected?.textureSlots.count == 8,
            "holesPreserved": [0, 2, 5, 7].allSatisfy {
                projected?.textureSlots[$0] == nil
            },
            "precedenceLowToHigh": candidateTokens == [
                "asset:textures/base.png", "property:skin", "graph:layerSource:42",
            ],
            "typedRequests": projected?.textureSlots[3]?.candidates.first.map {
                referenceToken($0.reference)
            } == "asset:masks/shape.png"
                && projected?.textureSlots[4]?.candidates.first.map {
                    referenceToken($0.reference)
                } == "system:$mediaThumbnail"
                && projected?.textureSlots[6]?.candidates.first.map {
                    referenceToken($0.reference)
                } == "property:tintTexture",
            "namedLayerTargetIsProvider": namedTemplate?.textureSlots[1]?
                .candidates.first.map { referenceToken($0.reference) }
                    == "named:42:a",
            "typedGraphRole": projected?.graphRole == expectedRole,
            "priorEffectOutputIsTypedIngress": chainedTemplate?.graphRole.effectInput
                == .effectOutput
                && chainedTemplate?.graphRole.bindings
                    == [.init(slot: 1, texture: .effectOutput)],
            "combosDeterministic": projected?.combos.map(\.name) == ["A_COMBO", "Z_COMBO"],
            "annotationDefaultStaysOutOfTemplate": annotationDefaultTemplate?.combos
                .map(\.name) == ["A_COMBO", "Z_COMBO"],
            "stateParsedOnly": template(compile(material(blending: "additive")))?
                .renderState.blending == .additive,
            "unknownFailsClosed": failure(compile(material(slots: unknownSlots)))?.code
                == .userTextureUnknown,
            "slotShapeFailsClosed": failure(compile(material(slots: emptyCandidateSlots)))?.code
                == .textureSlotsInvalid
                && failure(compile(material(slots: wrongIndexSlots)))?.code
                    == .textureSlotsInvalid
                && failure(compile(material(slots: Array(repeating: nil, count: 7))))?.code
                    == .textureSlotsInvalid,
            "staticExactBits": exactStaticBits,
            "materialOnlyStaticDoesNotRequireInstancePass":
                materialOnlyStatic?.uniformDeclarations.first?.name == "g_Static",
            "materialOnlyDynamicStillRequiresPassIdentity":
                materialOnlyDynamicFailure?.phase == .graph
                    && materialOnlyDynamicFailure?.boundedDetails
                        == ["pass-missing-for-dynamic-uniform"],
            "constantFallbackMergedWithDynamic": mergedDynamic,
            "multipleValueContributorsPreserved": duplicateDynamic?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors == [
                        .userProperty("legacy"), .userProperty("strength"),
                    ]
                        && value.scriptAttachments.isEmpty
                } == true,
            "timelineControlSeparated": timelineControl?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors == [.timeline]
                        && value.scriptAttachments
                            == [.mediaThumbnailAnimationRestart]
                } == true,
            "unknownScriptTypedUnproven": unknownTimelineScript?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors == [.timeline]
                        && value.scriptAttachments == [.unproven]
                } == true,
            "boundedScriptNeedsExactProof": boundedScriptUnproven?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors.isEmpty
                        && value.scriptAttachments == [.unproven]
                } == true
                && boundedScriptWrongTarget?.uniformDeclarations.first.map {
                    declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors.isEmpty
                        && value.scriptAttachments == [.unproven]
                } == true,
            "boundedScriptExactProofBecomesSoleValue": boundedScriptProven?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.target == boundedScriptTarget
                        && value.valueContributors == [.sceneScript]
                        && value.scriptAttachments.isEmpty
                } == true,
            "boundedPropertyScriptNeedsExactProof": boundedPropertyScriptUnproven?
                .uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.valueContributors.isEmpty
                        && value.scriptAttachments == [.unproven]
                } == true,
            "boundedPropertyScriptExactProofBecomesSoleValue":
                boundedPropertyScriptProven?.uniformDeclarations.first.map {
                    declaration in
                    guard case let .dynamic(value) = declaration.value else { return false }
                    return value.target == boundedScriptTarget
                        && value.valueContributors == [.sceneScript]
                        && value.scriptAttachments.isEmpty
                } == true,
            "observedPlayShapesRemainUnproven": [
                playOnlyTimelineScript, directPlayTimelineScript,
                extendedRestartScript,
            ].allSatisfy { template in
                template?.uniformDeclarations.first.map { declaration in
                    guard case let .dynamic(value) = declaration.value else {
                        return false
                    }
                    return value.valueContributors == [.timeline]
                        && value.scriptAttachments == [.unproven]
                } == true
            },
            "blockedGraphRejected": failure(compile(material(), graph: blockedGraph))?.phase
                == .graph,
            "invalidEffectIngressRejected": selfInputFailure?.code == .graphNodeInvalid
                && foreignInputFailure?.code == .graphNodeInvalid,
            "duplicateNodeRejected": failure(compile(
                material(), graph: duplicateNodeGraph
            ))?.code == .graphNodeInvalid,
            "orphanNodeRejected": failure(compile(
                material(), graph: orphanNodeGraph
            ))?.code == .graphNodeInvalid,
            "duplicatePartitionRejected": failure(compile(
                material(), graph: duplicatePartitionGraph
            ))?.code == .graphNodeInvalid,
            "ownerMismatchRejected": failure(compile(
                material(), graph: ownerMismatchGraph
            ))?.code == .graphNodeInvalid,
            "graphUniverseRejected": failure(compile(
                material(), graph: invalidBindingGraph
            ))?.code == .graphNodeInvalid
                && failure(compile(material(slots: ghostSlots)))?.code
                    == .textureReferenceInvalid
                && failure(compile(material(slots: wrongBindingSlot)))?.code
                    == .textureReferenceInvalid,
            "assetVFSBoundaries": escapedAssets.allSatisfy {
                assetFailure($0)?.code == .textureReferenceInvalid
            },
            "shaderNormalizationMatchesLoader": shaderNormalization != nil,
            "shaderEscapesRejected": shaderEscapeFailures
                && failure(compile(
                    material(shaderPath: "effects/a"),
                    contract: contract("../effects/a")
                ))?.code == .shaderIdentityMismatch,
            "sourceGraphRequired": failure(compile(
                material(), contract: contract("effects/test", hasGraph: false)
            ))?.code == .shaderSourceGraphMissing,
            "malformedMetadataSkippedButPreserved": skippedMalformedMetadata?
                .shaderContract.diagnostics.map(\.code) == [.malformedAnnotation],
            "malformedSamplerMetadataRejected": unsafeMalformedSampler?.code
                == .shaderContractInvalid,
            "otherShaderDiagnosticsRejected": fatalShaderDiagnostic?.code
                == .shaderContractInvalid,
            "failureDetailsBounded": bounded.boundedDetails.count == 8
                && bounded.boundedDetails.allSatisfy { $0.count <= 160 },
            "finalizerFailuresStable": stableCodes.map(\.rawValue) == [
                "resourceSnapshotUnresolved",
                "textureBindingInvalid", "texturePurposeUnproven", "textureMetadataIncomplete",
                "shaderPreparationFailed", "samplerBindingOrderInvalid",
                "samplerBindingDuplicateSlot", "samplerBindingIdentityMismatch",
                "samplerInternalTargetUnsupported", "activePassUnsupported",
                "samplerVariantSchemaDivergence",
                "authoredSamplerSchemaInvalid", "shaderFrontendFailed",
                "uniformBindingInvalid", "uniformContributorPolicyUnproven",
                "uniformScriptAttachmentUnproven", "colorContractUnproven",
                "frameSnapshotMismatch", "identityInvariant",
            ] && stablePhases.map(\.rawValue) == ["preparation", "frontend", "color"],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def source_prefix(path: Path, marker: str) -> str:
    source = path.read_text(encoding="utf-8")
    prefix, separator, _ = source.partition(marker)
    if not separator:
        raise RuntimeError(f"production source marker missing: {path.name}: {marker}")
    return prefix


class SceneResolvedMaterialTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-template-"
        )
        temporary = Path(cls.temporary_directory.name)
        vfs_source = temporary / "SceneVFSAssetPath.swift"
        template_source = temporary / "SceneResolvedMaterialTemplate.swift"
        support = temporary / "Support.swift"
        harness = temporary / "Harness.swift"
        vfs_source.write_text(
            source_prefix(TEXTURE_CANDIDATE_SOURCE, "/// Purpose is part"),
            encoding="utf-8",
        )
        template_source.write_text(
            source_prefix(PROGRAM_SOURCE, "/// One fully resolved material pass"),
            encoding="utf-8",
        )
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "resolved-material-template"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary / "swift-cache")
        compilation = subprocess.run(
            [
                swiftc,
                *(str(source) for source in SWIFT_SOURCES),
                str(vfs_source),
                str(template_source),
                str(support),
                str(harness),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assert_contracts(self, keys: list[str]) -> None:
        for key in keys:
            self.assertTrue(self.result[key], key)

    def test_template_preserves_typed_authored_structure(self) -> None:
        self.assert_contracts([
            "eightSlotsPreserved",
            "holesPreserved",
            "precedenceLowToHigh",
            "typedRequests",
            "namedLayerTargetIsProvider",
            "typedGraphRole",
            "priorEffectOutputIsTypedIngress",
            "combosDeterministic",
            "annotationDefaultStaysOutOfTemplate",
            "stateParsedOnly",
        ])

    def test_graph_and_texture_inputs_fail_closed(self) -> None:
        self.assert_contracts([
            "unknownFailsClosed",
            "slotShapeFailsClosed",
            "blockedGraphRejected",
            "invalidEffectIngressRejected",
            "duplicateNodeRejected",
            "orphanNodeRejected",
            "duplicatePartitionRejected",
            "ownerMismatchRejected",
            "graphUniverseRejected",
        ])

    def test_uniforms_separate_value_producers_from_script_attachments(self) -> None:
        self.assert_contracts([
            "staticExactBits",
            "constantFallbackMergedWithDynamic",
            "multipleValueContributorsPreserved",
            "timelineControlSeparated",
            "unknownScriptTypedUnproven",
            "boundedScriptNeedsExactProof",
            "boundedScriptExactProofBecomesSoleValue",
            "boundedPropertyScriptNeedsExactProof",
            "boundedPropertyScriptExactProofBecomesSoleValue",
        ])

    def test_vfs_and_shader_lexical_boundaries_match_production(self) -> None:
        self.assert_contracts([
            "assetVFSBoundaries",
            "shaderNormalizationMatchesLoader",
            "shaderEscapesRejected",
            "sourceGraphRequired",
            "malformedMetadataSkippedButPreserved",
            "malformedSamplerMetadataRejected",
            "otherShaderDiagnosticsRejected",
        ])

    def test_failures_are_bounded_and_finalizer_codes_are_stable(self) -> None:
        self.assert_contracts(["failureDetailsBounded", "finalizerFailuresStable"])


if __name__ == "__main__":
    unittest.main()
