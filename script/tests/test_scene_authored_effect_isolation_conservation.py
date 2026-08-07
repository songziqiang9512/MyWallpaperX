#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
CURSOR_PLAN_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredCursorRipplePlanner.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneShineExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain+Route.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectStageRebase.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectCursorRippleIsolation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectShineIsolation.swift",
]


def extract_cursor_plan_declaration() -> str:
    source = CURSOR_PLAN_SOURCE.read_text(encoding="utf-8")
    declaration = "nonisolated struct SceneCursorRippleExecutionPlan"
    start = source.index(declaration)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1] + "\n"
    raise AssertionError("SceneCursorRippleExecutionPlan declaration is incomplete")


HARNESS = r'''
import Foundation
import simd

struct SceneRenderDescriptor {}
struct SceneShaderContract {}
struct SceneDynamicTarget: Hashable {}

struct HarnessMarkerPlan {
    enum Profile { case scroll, other }

    let profile: Profile = .other
    let liveConsumerTargets = Set<SceneDynamicTarget>()
    let executedUserPropertyKeys = Set<String>()

    func offscreenSize(for requestedSize: CGSize) -> CGSize { requestedSize }
}

struct SceneIrisInlineSuffixPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneGraphRenderTargetPlan {
    struct PixelExtent {
        let width: Int
        let height: Int
    }

    static func pixelExtent(
        _ extent: SceneAuthoredEffectRenderPlan.TargetExtent,
        inputWidth: Int,
        inputHeight: Int
    ) -> PixelExtent? {
        switch extent.kind {
        case .input:
            return .init(width: inputWidth, height: inputHeight)
        case .fit:
            guard let fit = extent.first, fit > 0 else { return nil }
            let value = Int(fit)
            return .init(width: value, height: value)
        default:
            return .init(width: inputWidth, height: inputHeight)
        }
    }
}

nonisolated struct SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case shine(SceneShineExecutionPlan)
        case xRay(HarnessMarkerPlan)
    }

    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let usesLegacyComposeNormalization: Bool

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        usesLegacyComposeNormalization: Bool = false
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
        self.usesLegacyComposeNormalization = usesLegacyComposeNormalization
    }

    var cursorRipple: SceneCursorRippleExecutionPlan? {
        guard case .cursorRipple(let plan) = backend else { return nil }
        return plan
    }

    var shine: SceneShineExecutionPlan? {
        guard case .shine(let plan) = backend else { return nil }
        return plan
    }

    var xRay: HarnessMarkerPlan? {
        guard case .xRay(let plan) = backend else { return nil }
        return plan
    }

    var localContrast: HarnessMarkerPlan? { nil }
    var opacity: HarnessMarkerPlan? { nil }
    var colorGrading: HarnessMarkerPlan? { nil }
    var workshopShiftHue: HarnessMarkerPlan? { nil }
    var workshopAudioBars: HarnessMarkerPlan? { nil }
    var workshopGradient: HarnessMarkerPlan? { nil }
    var workshopAudioHueShift: HarnessMarkerPlan? { nil }
    var workshopShadow: HarnessMarkerPlan? { nil }
    var spin: HarnessMarkerPlan? { nil }
    var proceduralNoise: HarnessMarkerPlan? { nil }
    var filmGrain: HarnessMarkerPlan? { nil }
    var lightShafts: HarnessMarkerPlan? { nil }
    var shake: HarnessMarkerPlan? { nil }
    var waterFlow: HarnessMarkerPlan? { nil }
    var waterWaves: HarnessMarkerPlan? { nil }
    var waterCaustics: HarnessMarkerPlan? { nil }
    var foliageSway: HarnessMarkerPlan? { nil }
    var waterRipple: HarnessMarkerPlan? { nil }
    var depthParallax: HarnessMarkerPlan? { nil }
    var clippingMask: HarnessMarkerPlan? { nil }
    var blend: HarnessMarkerPlan? { nil }
    var tint: HarnessMarkerPlan? { nil }
    var transform: HarnessMarkerPlan? { nil }
    var fisheyeZeroDistortion: HarnessMarkerPlan? { nil }
    var pulse: HarnessMarkerPlan? { nil }
    var godrays: HarnessMarkerPlan? { nil }
    var authoredShader: HarnessMarkerPlan? { nil }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}

nonisolated struct SceneEffectStageProgram {
    let authoredOrdinal: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let definitionPath: String
    let inputRole: SceneAuthoredEffectInputRole
    let stageGraph: SceneAuthoredEffectRenderPlan
    let executionPlan: SceneAuthoredEffectExecutionPlan

    static func graphsMatch(
        _ lhs: SceneAuthoredEffectRenderPlan,
        _ rhs: SceneAuthoredEffectRenderPlan
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }
}

extension SceneAuthoredEffectChainPlanner {
    struct HarnessStageGraphAdmission {
        let graph: Graph?
    }

    struct HarnessChainAdmission {
        let chain: SceneAuthoredEffectExecutionChain?
    }

    static func admit(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> HarnessChainAdmission {
        .init(chain: nil)
    }

    static func stageGraphAdmission(
        effect: Graph.Effect,
        in graph: Graph
    ) -> HarnessStageGraphAdmission {
        let nodes = graph.nodes.filter { $0.effect == effect.key }
        guard nodes.map(\.nodeIndex) == effect.nodeIndices else {
            return .init(graph: nil)
        }
        return .init(graph: Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: nodes,
            finalOutput: effect.output,
            blockers: []
        ))
    }
}

enum SceneAuthoredCursorRipplePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneCursorRippleExecutionPlan? {
        guard graph.effects.count == 1,
              graph.nodes.count == 3,
              graph.renderTargets.count == 2,
              SceneAuthoredEffectInputValidator.accepts(
                  graph.effects[0].input,
                  layerID: graph.layerID,
                  role: inputRole
              ) else {
            return nil
        }
        return Fixture.cursorPlan(graph: graph)
    }
}

enum SceneAuthoredShinePlanner {
    static let definitionPath = "effects/shine/effect.json"

    static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneShineExecutionPlan? {
        guard graph.effects.count == 1,
              normalized(graph.effects[0].definitionPath) == definitionPath,
              graph.nodes.count == 5,
              graph.renderTargets.count == 2,
              SceneAuthoredEffectInputValidator.accepts(
                  graph.effects[0].input,
                  layerID: graph.layerID,
                  role: inputRole
              ) else {
            return nil
        }
        return Fixture.shinePlan(graph: graph)
    }
}

enum Fixture {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 41
    static let firstKey = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "fixture-base"
    )
    static let cursorKey = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 1,
        descriptorID: "fixture-cursor"
    )
    static let shineKey = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 2,
        descriptorID: "fixture-shine"
    )

    static let enabledState = SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: "enabled"
    )!
    static let defaultState = SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: "default"
    )!
    static let unspecifiedState = SceneMaterialRenderState.compile(
        blending: "normal",
        depthTest: "disabled",
        depthWrite: "disabled",
        cullMode: "nocull",
        alphaWriting: nil
    )!

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func output(_ key: Graph.EffectKey) -> Graph.TextureIdentity {
        identity(.effectOutput, effect: key)
    }

    static func target(
        _ key: Graph.EffectKey,
        _ name: String
    ) -> Graph.RenderTarget {
        .init(
            texture: identity(.framebuffer, effect: key, name: name),
            extent: .init(kind: .fit, first: 384, second: nil),
            format: "rgba8888",
            declaredUnique: false,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
    }

    static func material(
        index: Int,
        key: Graph.EffectKey,
        target: Graph.TextureIdentity,
        bindings: [Graph.TextureIdentity]
    ) -> Graph.Node {
        .init(
            nodeIndex: key.effectIndex * 10 + index,
            effect: key,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "fixture/material-\(index).json",
            materialPassID: "fixture/material-\(index).json#0",
            target: target,
            bindings: bindings.enumerated().map {
                .init(
                    slot: $0.offset,
                    authoredName: "slot-\($0.offset)",
                    texture: $0.element,
                    conditions: nil
                )
            },
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func outerGraph(
        key: Graph.EffectKey,
        path: String,
        nodeCount: Int
    ) -> Graph {
        let layerSource = identity(.layerSource)
        let firstOutput = output(firstKey)
        let effectOutput = output(key)
        let first = Graph.Effect(
            key: firstKey,
            definitionPath: "effects/fixture/base/effect.json",
            input: layerSource,
            output: firstOutput,
            nodeIndices: [0]
        )
        let stage = Graph.Effect(
            key: key,
            definitionPath: path,
            input: firstOutput,
            output: effectOutput,
            nodeIndices: (0..<nodeCount).map { key.effectIndex * 10 + $0 }
        )
        let stageTargets = [target(key, "fixture-a"), target(key, "fixture-b")]
        let targetIdentities = stageTargets.map(\.texture)
        var stageNodes: [Graph.Node] = []
        for index in 0..<nodeCount {
            let targetIdentity = index == nodeCount - 1
                ? effectOutput
                : targetIdentities[index % targetIdentities.count]
            let bindings = index == 0
                ? [firstOutput]
                : [targetIdentities[(index - 1) % targetIdentities.count]]
            stageNodes.append(material(
                index: index,
                key: key,
                target: targetIdentity,
                bindings: bindings
            ))
        }
        let baseNode = material(
            index: 0,
            key: firstKey,
            target: firstOutput,
            bindings: [layerSource]
        )
        return Graph(
            layerID: layerID,
            effects: [first, stage],
            renderTargets: stageTargets,
            nodes: [baseNode] + stageNodes,
            finalOutput: effectOutput,
            blockers: []
        )
    }

    static func cursorPlan(graph: Graph) -> SceneCursorRippleExecutionPlan {
        SceneCursorRippleExecutionPlan(
            layerID: graph.layerID,
            effectKey: graph.effects[0].key,
            renderGraph: graph,
            simulationResolution: 384,
            rippleScale: 0.375,
            decay: 0.875,
            speed: 0.625,
            strength: 0.75,
            maskTexturePath: "fixture/cursor-mask.png",
            renderStates: .init(
                applyForce: enabledState,
                simulateForce: defaultState,
                combine: unspecifiedState
            )
        )
    }

    static func shinePlan(graph: Graph) -> SceneShineExecutionPlan {
        let targets = graph.renderTargets.map(\.texture)
        return SceneShineExecutionPlan(
            layerID: graph.layerID,
            effectKey: graph.effects[0].key,
            renderGraph: graph,
            firstHalfTarget: targets[0],
            secondHalfTarget: targets[1],
            threshold: 0.125,
            noiseAmount: 0.25,
            noiseScale: 0.5,
            noiseSpeed: 0.75,
            maskTexturePath: "fixture/shine-mask.png",
            noiseTexturePath: "fixture/shine-noise.png",
            edgeCount: 3,
            sampleCount: 7,
            direction: 0.375,
            rotationSpeed: 0.625,
            rayLength: 0.875,
            rayIntensity: 1.25,
            rayColor: SIMD3<Float>(0.2, 0.4, 0.6),
            kernelRadius: 5,
            blurScaleX: SIMD2<Float>(0.75, 0.125),
            blurScaleY: SIMD2<Float>(0.25, 0.875),
            blendMode: 2
        )
    }

    static func cursorPlan(
        copying source: SceneCursorRippleExecutionPlan,
        effectKey: Graph.EffectKey? = nil,
        renderGraph: Graph? = nil
    ) -> SceneCursorRippleExecutionPlan {
        .init(
            layerID: source.layerID,
            effectKey: effectKey ?? source.effectKey,
            renderGraph: renderGraph ?? source.renderGraph,
            simulationResolution: source.simulationResolution,
            rippleScale: source.rippleScale,
            decay: source.decay,
            speed: source.speed,
            strength: source.strength,
            maskTexturePath: source.maskTexturePath,
            renderStates: source.renderStates
        )
    }

    static func shinePlan(
        copying source: SceneShineExecutionPlan,
        effectKey: Graph.EffectKey? = nil,
        renderGraph: Graph? = nil,
        firstTarget: Graph.TextureIdentity? = nil,
        secondTarget: Graph.TextureIdentity? = nil
    ) -> SceneShineExecutionPlan {
        .init(
            layerID: source.layerID,
            effectKey: effectKey ?? source.effectKey,
            renderGraph: renderGraph ?? source.renderGraph,
            firstHalfTarget: firstTarget ?? source.firstHalfTarget,
            secondHalfTarget: secondTarget ?? source.secondHalfTarget,
            threshold: source.threshold,
            noiseAmount: source.noiseAmount,
            noiseScale: source.noiseScale,
            noiseSpeed: source.noiseSpeed,
            maskTexturePath: source.maskTexturePath,
            noiseTexturePath: source.noiseTexturePath,
            edgeCount: source.edgeCount,
            sampleCount: source.sampleCount,
            direction: source.direction,
            rotationSpeed: source.rotationSpeed,
            rayLength: source.rayLength,
            rayIntensity: source.rayIntensity,
            rayColor: source.rayColor,
            kernelRadius: source.kernelRadius,
            blurScaleX: source.blurScaleX,
            blurScaleY: source.blurScaleY,
            blendMode: source.blendMode
        )
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Chain = SceneAuthoredEffectExecutionChain

    static func matches(_ lhs: Graph, _ rhs: Graph) -> Bool {
        SceneEffectStageProgram.graphsMatch(lhs, rhs)
    }

    static func routeIsLegacy(
        _ chain: Chain,
        kind expected: Chain.LegacyRecoveryKind
    ) -> Bool {
        guard case .legacyRecovery(let kind) = chain.executionRoute else {
            return false
        }
        return kind == expected
    }

    static func executionPlan(
        copying source: SceneAuthoredEffectExecutionPlan,
        renderGraph: Graph? = nil,
        backend: SceneAuthoredEffectExecutionPlan.Backend? = nil,
        materialNodeCount: Int? = nil,
        logicalTargetCount: Int? = nil,
        inputRole: SceneAuthoredEffectInputRole? = nil,
        legacyCompose: Bool? = nil
    ) -> SceneAuthoredEffectExecutionPlan {
        .init(
            layerID: source.layerID,
            renderGraph: renderGraph ?? source.renderGraph,
            backend: backend ?? source.backend,
            materialNodeCount: materialNodeCount ?? source.materialNodeCount,
            logicalRenderTargetCount:
                logicalTargetCount ?? source.logicalRenderTargetCount,
            inputRole: inputRole ?? source.inputRole,
            usesLegacyComposeNormalization:
                legacyCompose ?? source.usesLegacyComposeNormalization
        )
    }

    static func manualRecovery(
        authoredGraph: Graph,
        executionGraph: Graph,
        stage: SceneAuthoredEffectExecutionPlan,
        kind: Chain.LegacyRecoveryKind,
        omitted: [String]
    ) -> Chain? {
        Chain.legacyRecovery(
            layerID: authoredGraph.layerID,
            authoredRenderGraph: authoredGraph,
            renderGraph: executionGraph,
            legacyRecoveryStages: [stage],
            kind: kind,
            omittedEffectPaths: omitted
        )
    }

    static func cursorFieldsConserved(
        _ plan: SceneCursorRippleExecutionPlan,
        graph: Graph
    ) -> Bool {
        plan.layerID == Fixture.layerID
            && plan.effectKey == Fixture.cursorKey
            && matches(plan.renderGraph, graph)
            && plan.simulationResolution == 384
            && plan.rippleScale == 0.375
            && plan.decay == 0.875
            && plan.speed == 0.625
            && plan.strength == 0.75
            && plan.maskTexturePath == "fixture/cursor-mask.png"
            && plan.renderStates.applyForce == Fixture.enabledState
            && plan.renderStates.simulateForce == Fixture.defaultState
            && plan.renderStates.combine == Fixture.unspecifiedState
    }

    static func shineFieldsConserved(
        _ plan: SceneShineExecutionPlan,
        graph: Graph
    ) -> Bool {
        plan.layerID == Fixture.layerID
            && plan.effectKey == Fixture.shineKey
            && matches(plan.renderGraph, graph)
            && plan.firstHalfTarget == graph.renderTargets[0].texture
            && plan.secondHalfTarget == graph.renderTargets[1].texture
            && plan.threshold == 0.125
            && plan.noiseAmount == 0.25
            && plan.noiseScale == 0.5
            && plan.noiseSpeed == 0.75
            && plan.maskTexturePath == "fixture/shine-mask.png"
            && plan.noiseTexturePath == "fixture/shine-noise.png"
            && plan.edgeCount == 3
            && plan.sampleCount == 7
            && plan.direction == 0.375
            && plan.rotationSpeed == 0.625
            && plan.rayLength == 0.875
            && plan.rayIntensity == 1.25
            && plan.rayColor == SIMD3<Float>(0.2, 0.4, 0.6)
            && plan.kernelRadius == 5
            && plan.blurScaleX == SIMD2<Float>(0.75, 0.125)
            && plan.blurScaleY == SIMD2<Float>(0.25, 0.875)
            && plan.blendMode == 2
    }

    static func main() throws {
        let cursorAuthored = Fixture.outerGraph(
            key: Fixture.cursorKey,
            path: "effects/cursorripple/effect.json",
            nodeCount: 3
        )
        guard let cursor = SceneAuthoredEffectChainPlanner.isolatedCursorRippleChain(
            graph: cursorAuthored,
            descriptor: .init(),
            shaderContracts: []
        ), let cursorStage = cursor.legacyRecoveryStages.first,
              let cursorPlan = cursorStage.cursorRipple else {
            fatalError("production Cursor isolation rejected the fixture")
        }
        let cursorGraph = cursor.renderGraph
        let cursorOmitted = [cursorAuthored.effects[0].definitionPath]

        let shineAuthored = Fixture.outerGraph(
            key: Fixture.shineKey,
            path: "effects/shine/effect.json",
            nodeCount: 5
        )
        guard let shine = SceneAuthoredEffectChainPlanner.isolatedShineChain(
            graph: shineAuthored,
            descriptor: .init(),
            shaderContracts: []
        ), let shineStage = shine.legacyRecoveryStages.first,
              let shinePlan = shineStage.shine else {
            fatalError("production Shine isolation rejected the fixture")
        }
        let shineGraph = shine.renderGraph
        let shineOmitted = [shineAuthored.effects[0].definitionPath]

        let wrongCursorKey = Fixture.cursorPlan(
            copying: cursorPlan,
            effectKey: Fixture.firstKey
        )
        let wrongCursorGraph = Fixture.cursorPlan(
            copying: cursorPlan,
            renderGraph: cursorAuthored
        )
        let wrongShineKey = Fixture.shinePlan(
            copying: shinePlan,
            effectKey: Fixture.firstKey
        )
        let wrongShineGraph = Fixture.shinePlan(
            copying: shinePlan,
            renderGraph: shineAuthored
        )
        let duplicateShineTarget = Fixture.shinePlan(
            copying: shinePlan,
            secondTarget: shinePlan.firstHalfTarget
        )

        let results: [String: Bool] = [
            "cursorPositive": routeIsLegacy(cursor, kind: .isolatedCursorRipple)
                && cursor.stagePrograms.isEmpty
                && cursor.legacyRecoveryStages.count == 1
                && cursorFieldsConserved(cursorPlan, graph: cursorGraph)
                && cursorGraph.effects[0].input
                    == SceneAuthoredEffectInputValidator.layerSource(
                        layerID: Fixture.layerID
                    ),
            "shinePositive": routeIsLegacy(shine, kind: .isolatedShine)
                && shine.stagePrograms.isEmpty
                && shine.legacyRecoveryStages.count == 1
                && shineFieldsConserved(shinePlan, graph: shineGraph)
                && shineGraph.effects[0].input
                    == SceneAuthoredEffectInputValidator.layerSource(
                        layerID: Fixture.layerID
                    ),
            "cursorWrongEmbeddedKeyRejected": manualRecovery(
                authoredGraph: cursorAuthored,
                executionGraph: cursorGraph,
                stage: executionPlan(
                    copying: cursorStage,
                    backend: .cursorRipple(wrongCursorKey)
                ),
                kind: .isolatedCursorRipple,
                omitted: cursorOmitted
            ) == nil,
            "cursorWrongEmbeddedGraphRejected": manualRecovery(
                authoredGraph: cursorAuthored,
                executionGraph: cursorGraph,
                stage: executionPlan(
                    copying: cursorStage,
                    backend: .cursorRipple(wrongCursorGraph)
                ),
                kind: .isolatedCursorRipple,
                omitted: cursorOmitted
            ) == nil,
            "cursorWrongStageGraphRejected": manualRecovery(
                authoredGraph: cursorAuthored,
                executionGraph: cursorGraph,
                stage: executionPlan(
                    copying: cursorStage,
                    renderGraph: cursorAuthored
                ),
                kind: .isolatedCursorRipple,
                omitted: cursorOmitted
            ) == nil,
            "cursorWrongPlanShapeRejected": manualRecovery(
                authoredGraph: cursorAuthored,
                executionGraph: cursorGraph,
                stage: executionPlan(
                    copying: cursorStage,
                    materialNodeCount: cursorStage.materialNodeCount + 1
                ),
                kind: .isolatedCursorRipple,
                omitted: cursorOmitted
            ) == nil,
            "cursorMissingOmissionRejected": manualRecovery(
                authoredGraph: cursorAuthored,
                executionGraph: cursorGraph,
                stage: cursorStage,
                kind: .isolatedCursorRipple,
                omitted: []
            ) == nil,
            "shineWrongEmbeddedKeyRejected": manualRecovery(
                authoredGraph: shineAuthored,
                executionGraph: shineGraph,
                stage: executionPlan(
                    copying: shineStage,
                    backend: .shine(wrongShineKey)
                ),
                kind: .isolatedShine,
                omitted: shineOmitted
            ) == nil,
            "shineWrongEmbeddedGraphRejected": manualRecovery(
                authoredGraph: shineAuthored,
                executionGraph: shineGraph,
                stage: executionPlan(
                    copying: shineStage,
                    backend: .shine(wrongShineGraph)
                ),
                kind: .isolatedShine,
                omitted: shineOmitted
            ) == nil,
            "shineWrongTargetRejected": manualRecovery(
                authoredGraph: shineAuthored,
                executionGraph: shineGraph,
                stage: executionPlan(
                    copying: shineStage,
                    backend: .shine(duplicateShineTarget)
                ),
                kind: .isolatedShine,
                omitted: shineOmitted
            ) == nil,
            "shineLegacyComposeRejected": manualRecovery(
                authoredGraph: shineAuthored,
                executionGraph: shineGraph,
                stage: executionPlan(
                    copying: shineStage,
                    legacyCompose: true
                ),
                kind: .isolatedShine,
                omitted: shineOmitted
            ) == nil,
            "shineWrongLogicalTargetCountRejected": manualRecovery(
                authoredGraph: shineAuthored,
                executionGraph: shineGraph,
                stage: executionPlan(
                    copying: shineStage,
                    logicalTargetCount: shineStage.logicalRenderTargetCount + 1
                ),
                kind: .isolatedShine,
                omitted: shineOmitted
            ) == nil,
            "manualKindCannotUseCursorProgram": Chain.legacyRecovery(
                layerID: cursorAuthored.layerID,
                authoredRenderGraph: cursorAuthored,
                renderGraph: cursorGraph,
                stagePrograms: [],
                kind: .isolatedCursorRipple
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: results,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectIsolationConservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-effect-isolation-conservation-"
        )
        root = Path(cls.temporary_directory.name)
        cursor_plan = root / "SceneCursorRippleExecutionPlan.swift"
        cursor_plan.write_text(
            "import Foundation\n" + extract_cursor_plan_declaration(),
            encoding="utf-8",
        )
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-effect-isolation-conservation"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(cursor_plan),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_production_isolation_rebase_preserves_every_plan_field(self) -> None:
        self.assertTrue(self.result["cursorPositive"])
        self.assertTrue(self.result["shinePositive"])

    def test_cursor_shared_validator_rejects_corrupted_identity(self) -> None:
        for name in (
            "cursorWrongEmbeddedKeyRejected",
            "cursorWrongEmbeddedGraphRejected",
            "cursorWrongStageGraphRejected",
            "cursorWrongPlanShapeRejected",
            "cursorMissingOmissionRejected",
            "manualKindCannotUseCursorProgram",
        ):
            self.assertTrue(self.result[name], name)

    def test_shine_shared_validator_rejects_corrupted_identity(self) -> None:
        for name in (
            "shineWrongEmbeddedKeyRejected",
            "shineWrongEmbeddedGraphRejected",
            "shineWrongTargetRejected",
            "shineLegacyComposeRejected",
            "shineWrongLogicalTargetCountRejected",
        ):
            self.assertTrue(self.result[name], name)


if __name__ == "__main__":
    unittest.main()
