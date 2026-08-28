#!/usr/bin/env python3
"""Executable owner partition for Pulse direct user-property uniforms."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets"
)
FINALIZER_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_program_finalizer.py"
    )
)
PULSE_FIXTURE = runpy.run_path(
    str(REPOSITORY_ROOT / "script/tests/test_scene_pulse_planner.py")
)
DEDICATED_COMPILERS_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectCompilation/SceneEffectStageDedicatedCompilers.swift"
)


def unique_sources(paths: list[Path]) -> list[Path]:
    return list(dict.fromkeys(paths))


def product_pulse_compiler_source() -> str:
    """Compile the exact production protocols and Pulse compiler extension."""
    source = DEDICATED_COMPILERS_SOURCE.read_text(encoding="utf-8")
    standard_blur = source.index("extension SceneAuthoredStandardBlurPlanner")
    pulse = source.index("extension SceneAuthoredPulsePlanner")
    return source[:standard_blur] + source[pulse:]


SWIFT_SOURCES = unique_sources([
    *FINALIZER_FIXTURE["SWIFT_SOURCES"],
    *PULSE_FIXTURE["SWIFT_SOURCES"],
    SCENE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialScriptBindingClassifier.swift",
    SCENE_ROOT / "RenderGraph/MaterialProgram/SceneResolvedMaterialTemplateCompiler.swift",
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift",
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStageAuthoredFallbackOwnerPartition.swift",
    SCENE_ROOT / "RenderGraph/EffectCompilation/SceneEffectStagePulseDirectPropertyOwnerAdmission.swift",
])


SUPPORT = r'''
import Foundation

struct SceneDocument {}
struct SceneTimelineAnimation: Codable {}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}
'''


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Constant = ScenePulseExecutionPlan.Constant

private let layerID = 20
private let effectKey = Graph.EffectKey(
    layerID: layerID,
    effectIndex: 0,
    descriptorID: "20#effect#21"
)
private let definitionPath = "effects/pulse/effect.json"
private let materialPath = "materials/effects/pulse.json"
private let shaderIdentity = "effects/pulse"

private func value(
    _ components: [Double],
    propertyKey: String
) -> SceneDocument.ShaderValue {
    .init(
        rawValue: components.map { String($0) }.joined(separator: " "),
        valueKind: "binding",
        userBinding: propertyKey,
        userValueKind: .string,
        components: components,
        bindingKeys: ["user", "value"]
    )
}

private func definition() -> SceneEffectDefinition {
    .init(
        relativePath: definitionPath,
        version: 1,
        replacementKey: "pulse",
        name: "ui_editor_effect_pulse_title",
        description: "ui_editor_effect_pulse_description",
        group: "animate",
        performance: nil,
        previewPath: "preview/project.json",
        editable: nil,
        passes: [.init(
            passIndex: 0,
            materialPath: materialPath,
            target: nil,
            bindings: [],
            compose: nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: [:]
        )],
        framebuffers: [],
        dependencies: [
            materialPath,
            "shaders/effects/pulse.frag",
            "shaders/effects/pulse.vert",
        ],
        functions: nil,
        gizmos: nil,
        extraFields: [:],
        unknownFieldPaths: []
    )
}

private func descriptor(
    bindings: [Constant: String],
    fallbackOverrides: [Constant: [Double]] = [:],
    combos: [String: Int] = [:],
    maskPath: String? = nil
) -> SceneRenderDescriptor {
    let constants = Dictionary(uniqueKeysWithValues: bindings.map {
        constant, propertyKey in
        let components = fallbackOverrides[constant]
            ?? constant.defaultComponents(for: .stock2842)
        return (constant.rawValue, value(components, propertyKey: propertyKey))
    })
    let textureSlots: [String?] = maskPath.map { [nil, nil, $0] } ?? []
    let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
        passIndex: 0,
        texturePaths: maskPath.map { [$0] } ?? [],
        textureSlots: textureSlots,
        userTextureInputs: [],
        combos: combos,
        constantShaderValues: constants
    )
    return .init(
        layers: [.init(
            id: layerID,
            contentKind: "image",
            effects: [.init(
                id: effectKey.descriptorID,
                file: definitionPath,
                visible: true,
                passes: [pass]
            )]
        )],
        materialPasses: [.init(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256:
                "76a64c2e4e0b72c056b7dc3e35f333ca5fbc3b04b345b3bdccbedd3f2334deee",
            passIndex: 0,
            shaderPath: shaderIdentity,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: [:],
            constantShaderValues: [:],
            userShaderValues: [:],
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )],
        effectDefinitions: [definition()]
    )
}

private func texture(
    _ kind: Graph.TextureKind,
    effect: Graph.EffectKey? = nil
) -> Graph.TextureIdentity {
    .init(kind: kind, layerID: layerID, effect: effect, name: nil)
}

private func graph() -> Graph {
    let input = texture(.layerSource)
    let output = texture(.effectOutput, effect: effectKey)
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effectKey,
            definitionPath: definitionPath,
            input: input,
            output: output,
            nodeIndices: [0]
        )],
        renderTargets: [],
        nodes: [.init(
            nodeIndex: 0,
            effect: effectKey,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: .material,
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: [],
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )],
        finalOutput: output,
        blockers: []
    )
}

private func producer(
    _ constant: Constant,
    propertyKey: String,
    valueType: SceneDynamicValueType? = nil
) -> SceneDynamicUserPropertyProducer {
    .init(
        propertyKey: propertyKey,
        target: .effectConstant(
            layerID: layerID,
            effectIndex: 0,
            passIndex: 0,
            name: constant.rawValue
        ),
        valueType: valueType ?? constant.valueType
    )
}

private func compileInput(
    contracts: [SceneShaderContract],
    bindings: [Constant: String],
    fallbackOverrides: [Constant: [Double]] = [:],
    producers: Set<SceneDynamicUserPropertyProducer>? = nil,
    combos: [String: Int] = [:],
    maskPath: String? = nil
) -> SceneEffectStageCompileInput {
    let actualProducers = producers ?? Set(bindings.map {
        producer($0.key, propertyKey: $0.value)
    })
    return .init(
        stageGraph: graph(),
        effectKey: effectKey,
        definitionPath: definitionPath,
        inputRole: .layerSource,
        descriptor: descriptor(
            bindings: bindings,
            fallbackOverrides: fallbackOverrides,
            combos: combos,
            maskPath: maskPath
        ),
        shaderContracts: contracts,
        userPropertyProducers: actualProducers
    )
}

private func outcome(_ input: SceneEffectStageCompileInput) -> String {
    switch SceneAuthoredPulsePlanner.compile(input) {
    case .notApplicable: return "not-applicable"
    case .accepted: return "incumbent"
    case .rejected(let failure):
        return "revoked:\(failure.details.first ?? "")"
    }
}

private func compileOutcome(
    _ contracts: [SceneShaderContract],
    bindings: [Constant: String] = [:],
    fallbackOverrides: [Constant: [Double]] = [:],
    producers: Set<SceneDynamicUserPropertyProducer>? = nil,
    combos: [String: Int] = [:],
    maskPath: String? = nil
) -> String {
    outcome(compileInput(
        contracts: contracts, bindings: bindings,
        fallbackOverrides: fallbackOverrides, producers: producers,
        combos: combos, maskPath: maskPath
    ))
}

private func plan(
    contracts: [SceneShaderContract],
    bindings: [Constant: String]
) -> ScenePulseExecutionPlan {
    let input = compileInput(contracts: contracts, bindings: bindings)
    return SceneAuthoredPulsePlanner.plan(
        graph: input.stageGraph,
        descriptor: input.descriptor,
        shaderContracts: input.shaderContracts,
        inputRole: input.inputRole
    )!
}

private func prepared(_ contract: SceneShaderContract) -> SceneShaderPreparedProgram {
    let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map { ($0, false) })
    switch SceneAuthoredShaderPreparation.prepareShaderStages(
        contract: contract,
        combos: [
            "AUDIOPROCESSING": 0,
            "BLENDMODE": 9,
            "PULSEALPHA": 0,
            "PULSECOLOR": 1,
        ],
        inactiveComboProviders: [],
        textureReadiness: readiness
    ) {
    case .accepted(let value): return value
    case .notApplicable, .rejected:
        preconditionFailure("stock Pulse preparation failed")
    }
}

private func copy(
    _ source: SceneShaderPreparedSource,
    declarations: [SceneShaderActiveDeclaration]? = nil,
    annotations: [SceneShaderActiveAnnotation]? = nil
) -> SceneShaderPreparedSource {
    .init(
        frontendSchemaVersion: source.frontendSchemaVersion,
        sourceDialect: source.sourceDialect,
        backend: source.backend,
        stage: source.stage,
        rootRelativePath: source.rootRelativePath,
        source: source.source,
        sourceMap: source.sourceMap,
        activeAnnotations: annotations ?? source.activeAnnotations,
        activeDeclarations: declarations ?? source.activeDeclarations,
        dependencies: source.dependencies,
        dependencySHA256: source.dependencySHA256,
        moduleDependencies: source.moduleDependencies,
        moduleDependencySHA256: source.moduleDependencySHA256,
        variantSHA256: source.variantSHA256,
        preparedSHA256: source.preparedSHA256
    )
}

private func copy(
    _ program: SceneShaderPreparedProgram,
    vertex: SceneShaderPreparedSource? = nil,
    fragment: SceneShaderPreparedSource? = nil
) -> SceneShaderPreparedProgram {
    .init(
        vertex: vertex ?? program.vertex,
        fragment: fragment ?? program.fragment,
        colorContract: program.colorContract,
        cacheKey: program.cacheKey
    )
}

private func declaration(
    _ active: SceneShaderActiveDeclaration,
    type: String? = nil,
    arraySuffix: String? = nil,
    arraySize: Int? = nil,
    line: Int? = nil
) -> SceneShaderActiveDeclaration {
    let original = active.declaration
    return .init(
        sourcePath: active.sourcePath,
        declaration: .init(
            kind: original.kind,
            type: type ?? original.type,
            name: original.name,
            arraySuffix: arraySuffix,
            arraySize: arraySize,
            raw: original.raw,
            line: line ?? original.line
        )
    )
}

private func materialAnnotation(
    materialKey: String,
    range: ClosedRange<Double>,
    line: Int,
    sourcePath: String
) -> SceneShaderActiveAnnotation {
    let value = SceneJSONValue.object([
        "material": .string(materialKey),
        "default": .number(range.lowerBound),
        "range": .array([.number(range.lowerBound), .number(range.upperBound)]),
    ])
    return .init(
        sourcePath: sourcePath,
        annotation: .init(
            marker: nil,
            value: value,
            raw: "// synthetic owner-admission fixture",
            line: line
        )
    )
}

private func replacingRange(
    _ source: SceneShaderPreparedSource,
    name: String,
    range: ClosedRange<Double>
) -> SceneShaderPreparedSource {
    let declaration = source.activeDeclarations.first {
        $0.declaration.name == name
    }!
    let annotations = source.activeAnnotations.map { active in
        guard active.sourcePath == declaration.sourcePath,
              active.annotation.line == declaration.declaration.line,
              case var .object(object) = active.annotation.value else {
            return active
        }
        object["range"] = .array([
            .number(range.lowerBound), .number(range.upperBound),
        ])
        let value = SceneJSONValue.object(object)
        return .init(
            sourcePath: active.sourcePath,
            annotation: .init(
                marker: active.annotation.marker,
                value: value,
                raw: active.annotation.raw,
                line: active.annotation.line
            )
        )
    }
    return copy(source, annotations: annotations)
}

private func ownerDisposition(
    _ plan: ScenePulseExecutionPlan,
    _ preparedVariants: [SceneShaderPreparedProgram]
) -> String {
    SceneAuthoredPulsePlanner.directUserPropertyOwnerDisposition(
        plan: plan,
        preparedVariants: preparedVariants
    ).rawValue
}

@main
enum Harness {
    static func main() throws {
        let root = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        precondition(contracts.count == 1)
        let legacyContracts = CommandLine.arguments.dropFirst(2).map {
            SceneShaderContractLoader().load(
                shaderReferences: [shaderIdentity],
                rootURL: URL(fileURLWithPath: $0, isDirectory: true)
            )
        }
        precondition(legacyContracts.count == 3)
        precondition(legacyContracts.allSatisfy { $0.count == 1 })
        let stock = prepared(contracts[0])
        let legacyPrepared = legacyContracts.map { prepared($0[0]) }
        let speedPlan = plan(
            contracts: contracts,
            bindings: [.speed: "pulseSpeed"]
        )
        let noisePlan = plan(
            contracts: contracts,
            bindings: [.noiseAmount: "pulseNoise"]
        )
        let phasePlan = plan(
            contracts: contracts,
            bindings: [.phase: "pulsePhase"]
        )
        let boundsPlan = plan(
            contracts: contracts,
            bindings: [.bounds: "pulseBounds"]
        )
        let legacyPhasePlans = legacyContracts.map {
            plan(contracts: $0, bindings: [.phase: "pulsePhase"])
        }

        let missingVertexSpeed = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.filter {
                $0.declaration.name != "g_PulseSpeed"
            }
        )

        let noiseTemplate = stock.fragment.activeDeclarations.first {
            $0.declaration.name == "g_NoiseAmount"
        }!
        let extraNoiseLine = 9_991
        let extraNoise = SceneShaderActiveDeclaration(
            sourcePath: stock.vertex.rootRelativePath,
            declaration: .init(
                kind: .uniform,
                type: "float",
                name: "g_ExtraNoiseAmount",
                arraySuffix: nil,
                arraySize: nil,
                raw: noiseTemplate.declaration.raw,
                line: extraNoiseLine
            )
        )
        let extraStageVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations + [extraNoise],
            annotations: stock.vertex.activeAnnotations + [materialAnnotation(
                materialKey: "noiseamount",
                range: 0 ... 2,
                line: extraNoiseLine,
                sourcePath: stock.vertex.rootRelativePath
            )]
        )

        let speedTemplate = stock.fragment.activeDeclarations.first {
            $0.declaration.name == "g_PulseSpeed"
        }!
        let duplicateLine = 9_992
        let duplicateSpeed = declaration(speedTemplate, line: duplicateLine)
        let duplicateFragment = copy(
            stock.fragment,
            declarations: stock.fragment.activeDeclarations + [duplicateSpeed],
            annotations: stock.fragment.activeAnnotations + [materialAnnotation(
                materialKey: "speed",
                range: 0 ... 10,
                line: duplicateLine,
                sourcePath: speedTemplate.sourcePath
            )]
        )

        let arrayVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.map {
                $0.declaration.name == "g_PulseSpeed"
                    ? declaration($0, arraySuffix: "[2]", arraySize: 2)
                    : $0
            }
        )
        let wrongTypeVertex = copy(
            stock.vertex,
            declarations: stock.vertex.activeDeclarations.map {
                $0.declaration.name == "g_PulseSpeed"
                    ? declaration($0, type: "vec2")
                    : $0
            }
        )
        let wrongRangeVertex = replacingRange(
            stock.vertex,
            name: "g_PulseSpeed",
            range: 0 ... 9
        )
        let wrongPhaseVertex = replacingRange(
            stock.vertex, name: "g_PulsePhase",
            range: 0 ... Double(1).nextDown.nextDown
        )
        let wrongPhaseFragment = replacingRange(
            stock.fragment, name: "g_PulsePhase", range: 0 ... 1
        )
        let legacyPhaseTemplate = legacyPrepared[0].fragment.activeDeclarations.first {
            $0.declaration.name == "g_PulsePhase"
        }!
        let legacyExtraVertexLine = 9_993
        let legacyExtraVertexPhase = SceneShaderActiveDeclaration(
            sourcePath: legacyPrepared[0].vertex.rootRelativePath,
            declaration: .init(
                kind: .uniform,
                type: "float",
                name: "g_PulsePhase",
                arraySuffix: nil,
                arraySize: nil,
                raw: legacyPhaseTemplate.declaration.raw,
                line: legacyExtraVertexLine
            )
        )
        let legacyExtraVertex = copy(
            legacyPrepared[0].vertex,
            declarations: legacyPrepared[0].vertex.activeDeclarations
                + [legacyExtraVertexPhase],
            annotations: legacyPrepared[0].vertex.activeAnnotations
                + [materialAnnotation(
                    materialKey: "phase",
                    range: 0 ... 6.282,
                    line: legacyExtraVertexLine,
                    sourcePath: legacyPrepared[0].vertex.rootRelativePath
                )]
        )
        let legacyMissingFragment = copy(
            legacyPrepared[0].fragment,
            declarations: legacyPrepared[0].fragment.activeDeclarations.filter {
                $0.declaration.name != "g_PulsePhase"
            }
        )
        let legacyWrongRange = replacingRange(
            legacyPrepared[0].fragment,
            name: "g_PulsePhase",
            range: 0 ... 1
        )
        let rgbAlpha = ["PULSECOLOR": 1, "PULSEALPHA": 1]
        let alphaOnly = ["PULSECOLOR": 0, "PULSEALPHA": 1]
        let audioRGBAlpha = ["AUDIOPROCESSING": 3, "PULSECOLOR": 1, "PULSEALPHA": 1]
        let audioAlphaOnly = ["AUDIOPROCESSING": 3, "PULSECOLOR": 0, "PULSEALPHA": 1]

        let result: [String: Any] = [
            "phaseRanges": SceneResolvedMaterialShaderSchema.exactActiveUniforms(
                materialKey: "phase", type: .float,
                stages: [.vertex, .fragment], prepared: stock
            )?.map {
                [$0.authoredRange?.lowerBound ?? -1, $0.authoredRange?.upperBound ?? -1]
            } ?? [],
            "legacyPhaseRanges": SceneResolvedMaterialShaderSchema.exactActiveUniforms(
                materialKey: "phase", type: .float,
                stages: [.fragment], prepared: legacyPrepared[0]
            )?.map {
                [$0.authoredRange?.lowerBound ?? -1, $0.authoredRange?.upperBound ?? -1]
            } ?? [],
            "productSpeed": compileOutcome(
                contracts, bindings: [.speed: "pulseSpeed"]
            ),
            "productAmount": compileOutcome(
                contracts, bindings: [.amount: "pulseAmount"]
            ),
            "productCombined": compileOutcome(
                contracts, bindings: [
                    .speed: "pulseValue",
                    .phase: "pulseValue",
                    .amount: "pulseValue",
                    .noiseAmount: "pulseValue",
                ]
            ),
            "productStaticRGBAlpha": compileOutcome(contracts, combos: rgbAlpha),
            "productMaskedBoundRGBAlpha": compileOutcome(
                contracts,
                bindings: [.speed: "pulseSpeed"],
                combos: rgbAlpha,
                maskPath: "materials/pulse-mask.png"
            ),
            "productBoundAlphaOnly": compileOutcome(
                contracts,
                bindings: [.noiseAmount: "pulseNoise"],
                combos: alphaOnly
            ),
            "productBoundAlphaExtraProducer": compileOutcome(
                contracts,
                bindings: [.speed: "pulseSpeed"],
                producers: [
                    producer(.speed, propertyKey: "pulseSpeed"),
                    producer(.speed, propertyKey: "competingSpeed"),
                ],
                combos: alphaOnly
            ),
            "productMaskedStaticRGBAlpha": compileOutcome(
                contracts, combos: rgbAlpha,
                maskPath: "materials/pulse-mask.png"
            ),
            "productMaskedAudioRGBAlpha": compileOutcome(
                contracts, combos: audioRGBAlpha,
                maskPath: "materials/pulse-mask.png"
            ),
            "productMaskedAlphaOnly": compileOutcome(
                contracts, combos: alphaOnly,
                maskPath: "materials/pulse-mask.png"
            ),
            "productMaskedAudioAlphaOnly": compileOutcome(
                contracts, combos: audioAlphaOnly,
                maskPath: "materials/pulse-mask.png"
            ),
            "legacyStaticRGBAlpha": legacyContracts.map {
                compileOutcome($0, combos: rgbAlpha)
            },
            "legacyStaticAlphaOnly": legacyContracts.map {
                compileOutcome($0, combos: alphaOnly)
            },
            "legacyMaskedStaticAlphaOnly": legacyContracts.map {
                compileOutcome(
                    $0, combos: alphaOnly,
                    maskPath: "materials/pulse-mask.png"
                )
            },
            "rgbAlphaProfile": SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputRGBBlendScalarAlpha.rawValue,
            "rgbAlphaRoute": SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputRGBBlendScalarAlpha
                .defaultRouteState.rawValue,
            "rgbAlphaRollback": SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputRGBBlendScalarAlpha
                .validatedRollbackOwner.rawValue,
            "rgbAlphaBadArtifact": SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputRGBBlendScalarAlpha
                .artifactFallbackOutcome(routeState: .genericOnly),
            "productPhase": compileOutcome(
                contracts,
                bindings: [.phase: "pulsePhase"]
            ),
            "productPhaseUnsafeFallback": compileOutcome(
                contracts, bindings: [.phase: "pulsePhase"],
                fallbackOverrides: [.phase: [2]]
            ),
            "legacyProductPhase": legacyContracts.map {
                compileOutcome($0, bindings: [.phase: "pulsePhase"])
            },
            "legacyProductPhaseUnsafeFallback": compileOutcome(
                legacyContracts[0],
                bindings: [.phase: "pulsePhase"],
                fallbackOverrides: [.phase: [7]]
            ),
            "legacyProductPhaseMissingProducer": compileOutcome(
                legacyContracts[0],
                bindings: [.phase: "pulsePhase"],
                producers: []
            ),
            "productBounds": compileOutcome(
                contracts,
                bindings: [.bounds: "pulseBounds"]
            ),
            "productMissingProducer": compileOutcome(
                contracts,
                bindings: [.speed: "pulseSpeed"],
                producers: []
            ),
            "productWrongProducerType": compileOutcome(
                contracts,
                bindings: [.speed: "pulseSpeed"],
                producers: [producer(
                    .speed,
                    propertyKey: "pulseSpeed",
                    valueType: .vector2
                )]
            ),
            "stockSpeedDisposition": ownerDisposition(speedPlan, [stock, stock]),
            "missingStage": ownerDisposition(
                speedPlan, [stock, copy(stock, vertex: missingVertexSpeed)]
            ),
            "extraStage": ownerDisposition(
                noisePlan, [stock, copy(stock, vertex: extraStageVertex)]
            ),
            "sameStageDuplicate": ownerDisposition(
                speedPlan, [stock, copy(stock, fragment: duplicateFragment)]
            ),
            "arrayDrift": ownerDisposition(
                speedPlan, [stock, copy(stock, vertex: arrayVertex)]
            ),
            "typeDrift": ownerDisposition(
                speedPlan, [stock, copy(stock, vertex: wrongTypeVertex)]
            ),
            "rangeDrift": ownerDisposition(
                speedPlan, [stock, copy(stock, vertex: wrongRangeVertex)]
            ),
            "phaseVertexRangeDrift": ownerDisposition(
                phasePlan, [stock, copy(stock, vertex: wrongPhaseVertex)]
            ),
            "phaseFragmentRangeDrift": ownerDisposition(
                phasePlan, [stock, copy(stock, fragment: wrongPhaseFragment)]
            ),
            "legacyPhaseDispositions": zip(
                legacyPhasePlans, legacyPrepared
            ).map { plan, prepared in
                ownerDisposition(plan, [prepared, prepared])
            },
            "legacyPhaseExtraStage": ownerDisposition(
                legacyPhasePlans[0], [legacyPrepared[0],
                    copy(legacyPrepared[0], vertex: legacyExtraVertex)]
            ),
            "legacyPhaseMissingStage": ownerDisposition(
                legacyPhasePlans[0],
                [legacyPrepared[0], copy(
                    legacyPrepared[0], fragment: legacyMissingFragment
                )]
            ),
            "legacyPhaseRangeDrift": ownerDisposition(
                legacyPhasePlans[0],
                [legacyPrepared[0], copy(
                    legacyPrepared[0], fragment: legacyWrongRange
                )]
            ),
            "boundsDisposition": ownerDisposition(boundsPlan, [stock, stock]),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePulseDirectUserPropertyOwnerAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-pulse-owner-admission-"
        )
        root = Path(cls.temporary_directory.name)
        support = root / "Support.swift"
        product_compiler = root / "ProductPulseCompiler.swift"
        harness = root / "Harness.swift"
        support.write_text(SUPPORT, encoding="utf-8")
        product_compiler.write_text(
            product_pulse_compiler_source(),
            encoding="utf-8",
        )
        harness.write_text(HARNESS, encoding="utf-8")

        cls.stock = root / "stock"
        (cls.stock / "shaders/effects").mkdir(parents=True)
        shutil.copy2(
            STOCK_ROOT / "effects/pulse/shaders/effects/pulse.vert",
            cls.stock / "shaders/effects/pulse.vert",
        )
        shutil.copy2(
            STOCK_ROOT / "effects/pulse/shaders/effects/pulse.frag",
            cls.stock / "shaders/effects/pulse.frag",
        )
        shutil.copy2(
            STOCK_ROOT / "shaders/common_blending.h",
            cls.stock / "shaders/common_blending.h",
        )
        cls.legacy_roots = []
        legacy_fragments = (
            PULSE_FIXTURE["LEGACY_FRAG_SATURATE_BASE64"],
            PULSE_FIXTURE["LEGACY_FRAG_CAST3_BASE64"],
            PULSE_FIXTURE["LEGACY_FRAG_LITERAL_BASE64"],
        )
        for index, fragment in enumerate(legacy_fragments):
            legacy_root = root / f"legacy-{index}"
            legacy_shader_dir = legacy_root / "shaders/effects"
            legacy_shader_dir.mkdir(parents=True)
            (legacy_shader_dir / "pulse.vert").write_bytes(
                base64.b64decode(PULSE_FIXTURE["LEGACY_VERT_BASE64"])
            )
            (legacy_shader_dir / "pulse.frag").write_bytes(
                base64.b64decode(fragment)
            )
            (legacy_root / "shaders").mkdir(exist_ok=True)
            shutil.copy2(
                STOCK_ROOT / "shaders/common_blending.h",
                legacy_root / "shaders/common_blending.h",
            )
            cls.legacy_roots.append(legacy_root)

        binary = root / "pulse-owner-admission"
        environment = os.environ.copy()
        environment["HOME"] = str(root / "home")
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                str(support),
                *(str(path) for path in SWIFT_SOURCES),
                str(product_compiler),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(cls.stock), *(str(path) for path in cls.legacy_roots)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_stock_direct_binding_cohort_revokes_the_incumbent(self) -> None:
        expected = "revoked:typed-user-property-rgb-owner-revoked-to-material-program"
        for key in ("productSpeed", "productPhase", "productAmount", "productCombined"):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], expected)
        self.assertEqual(
            self.result["stockSpeedDisposition"],
            "revoke-dedicated-owner",
        )
        self.assertEqual(self.result["phaseRanges"][0], [0, 1])
        self.assertEqual(self.result["phaseRanges"][1][0], 0)
        self.assertAlmostEqual(self.result["phaseRanges"][1][1], 6.282)

    def test_non_cohort_bindings_retain_the_incumbent(self) -> None:
        for key in (
            "productBounds",
            "productPhaseUnsafeFallback",
            "productMissingProducer",
            "productWrongProducerType",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "incumbent")
        self.assertEqual(self.result["boundsDisposition"], "retain-incumbent")

    def test_static_rgb_alpha_owner_moves_to_the_shared_program(self) -> None:
        expected = {
            "productStaticRGBAlpha": "static-rgb-alpha",
            "productMaskedStaticRGBAlpha": "static-rgb-alpha",
            "productMaskedAudioRGBAlpha": "audio-rgb-alpha",
            "productMaskedAlphaOnly": "static-alpha-only",
            "productMaskedAudioAlphaOnly": "audio-alpha-only",
        }
        for key, reason in expected.items():
            with self.subTest(key=key):
                self.assertEqual(
                    self.result[key],
                    f"revoked:{reason}-owner-revoked-to-material-program",
                )
        self.assertEqual(
            self.result["rgbAlphaProfile"],
            "source-proven-graph-input-rgb-blend-scalar-alpha",
        )
        self.assertEqual(self.result["rgbAlphaRoute"], "generic-only")
        self.assertEqual(self.result["rgbAlphaRollback"], "none")

    def test_direct_bound_alpha_writing_cohort_revokes_the_incumbent(self) -> None:
        expected = {
            "productMaskedBoundRGBAlpha": "typed-user-property-rgb-alpha",
            "productBoundAlphaOnly": "typed-user-property-alpha-only",
        }
        for key, reason in expected.items():
            with self.subTest(key=key):
                self.assertEqual(
                    self.result[key],
                    f"revoked:{reason}-owner-revoked-to-material-program",
                )

    def test_unsafe_bound_alpha_writing_shapes_retain_the_incumbent(self) -> None:
        self.assertEqual(self.result["productBoundAlphaExtraProducer"], "incumbent")

    def test_rgb_alpha_bad_artifact_or_profile_rejects_locally(self) -> None:
        self.assertEqual(self.result["rgbAlphaBadArtifact"], "rejected")
        self.assertEqual(
            self.result["legacyStaticRGBAlpha"],
            ["incumbent"] + [
                "revoked:static-rgb-alpha-owner-revoked-to-material-program"
            ] * 2,
        )

    def test_historical_alpha_only_partition_follows_source_proof(self) -> None:
        revoked = "revoked:static-alpha-only-owner-revoked-to-material-program"
        expected = ["incumbent", revoked, revoked]
        self.assertEqual(self.result["legacyStaticAlphaOnly"], expected)
        self.assertEqual(self.result["legacyMaskedStaticAlphaOnly"], expected)

    def test_historical_fragment_only_phase_revokes_the_incumbent(self) -> None:
        expected = "revoked:typed-user-property-rgb-owner-revoked-to-material-program"
        self.assertEqual(self.result["legacyProductPhase"], [expected] * 3)
        self.assertEqual(
            self.result["legacyPhaseDispositions"],
            ["revoke-dedicated-owner"] * 3,
        )
        self.assertEqual(self.result["legacyPhaseRanges"][0][0], 0)
        self.assertAlmostEqual(self.result["legacyPhaseRanges"][0][1], 6.282)

    def test_historical_phase_unsafe_shapes_retain_the_incumbent(self) -> None:
        self.assertEqual(
            self.result["legacyProductPhaseUnsafeFallback"],
            "revoked:",
        )
        self.assertEqual(
            self.result["legacyProductPhaseMissingProducer"],
            "incumbent",
        )
        for key in (
            "legacyPhaseExtraStage",
            "legacyPhaseMissingStage",
            "legacyPhaseRangeDrift",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "retain-incumbent")

    def test_shader_schema_drift_retains_the_incumbent(self) -> None:
        for key in (
            "missingStage",
            "extraStage",
            "sameStageDuplicate",
            "arrayDrift",
            "typeDrift",
            "rangeDrift",
            "phaseVertexRangeDrift",
            "phaseFragmentRangeDrift",
        ):
            with self.subTest(key=key):
                self.assertEqual(self.result[key], "retain-incumbent")


if __name__ == "__main__":
    unittest.main()
