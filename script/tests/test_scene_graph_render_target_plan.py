#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
]


HARNESS = r'''
import Foundation

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
    let supportsUnifiedFullFrameComposeStage: Bool

    init(
        layerID: Int,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        cursorRipple: SceneCursorRippleExecutionPlan? = nil,
        supportsUnifiedFullFrameComposeStage: Bool = false
    ) {
        self.layerID = layerID
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
        self.cursorRipple = cursorRipple
        self.supportsUnifiedFullFrameComposeStage =
            supportsUnifiedFullFrameComposeStage
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func texture(
        _ kind: Graph.TextureKind,
        key: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 10, effect: key, name: name)
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        extent: Graph.TargetExtent,
        format: String = "rgba_backbuffer",
        unique: Bool = false,
        clear: SceneJSONValue? = nil
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: extent,
            format: format,
            declaredUnique: unique,
            clear: clear,
            uvs: nil,
            conditions: nil
        )
    }

    static func binding(_ identity: Graph.TextureIdentity, slot: Int) -> Graph.Binding {
        .init(slot: slot, authoredName: identity.name ?? "previous", texture: identity, conditions: nil)
    }

    static func node(
        _ index: Int,
        key: Graph.EffectKey,
        target: Graph.TextureIdentity,
        reads: [Graph.TextureIdentity],
        compose: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: key,
            definitionPassIndex: index,
            materialOrdinal: index,
            instancePassIndex: index,
            kind: .material,
            materialPath: "materials/\(index).json",
            materialPassID: "materials/\(index).json#0",
            target: target,
            bindings: reads.enumerated().map { binding($0.element, slot: $0.offset) },
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }

    static func commandNode(
        _ index: Int,
        kind: Graph.NodeKind,
        key: Graph.EffectKey,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: index,
            effect: key,
            definitionPassIndex: index,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func graph(
        targets: [Graph.RenderTarget],
        nodes: [Graph.Node],
        key: Graph.EffectKey,
        input: Graph.TextureIdentity,
        output: Graph.TextureIdentity
    ) -> Graph {
        .init(
            layerID: 10,
            effects: [.init(
                key: key,
                definitionPath: "effects/test/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func failure(
        _ graph: Graph,
        materialNodeCount: Int? = nil,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        supportsUnifiedFullFrameComposeStage: Bool = false,
        materialFunctionTargets: Set<Graph.TextureIdentity> = []
    ) -> String {
        let result = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: graph.layerID,
                materialNodeCount: materialNodeCount ?? graph.nodes.count,
                logicalRenderTargetCount: graph.renderTargets.count,
                inputRole: inputRole,
                supportsUnifiedFullFrameComposeStage:
                    supportsUnifiedFullFrameComposeStage
            ),
            graph: graph,
            inputWidth: 1920,
            inputHeight: 1080,
            materialFunctionTargets: materialFunctionTargets
        )
        switch result {
        case .success:
            return "success"
        case .failure(let reason):
            return reason.rawValue
        }
    }

    static func requirePlan(
        _ graph: Graph,
        materialNodeCount: Int,
        materialFunctionTargets: Set<Graph.TextureIdentity> = []
    ) -> SceneGraphRenderTargetPlan {
        let result = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: graph.layerID,
                materialNodeCount: materialNodeCount,
                logicalRenderTargetCount: graph.renderTargets.count
            ),
            graph: graph,
            inputWidth: 1920,
            inputHeight: 1080,
            materialFunctionTargets: materialFunctionTargets
        )
        guard case .success(let plan) = result else {
            fatalError("expected render target plan")
        }
        return plan
    }

    static func targetSummary(_ plan: SceneGraphRenderTargetPlan) -> [[String: Any]] {
        plan.logicalTargets.map { target in
            [
                "name": target.identity.name ?? "",
                "size": [target.extent.width, target.extent.height],
                "format": target.format.rawValue,
                "firstWrite": target.lifetime.firstWriteNodeIndex,
                "lastWrite": target.lifetime.lastWriteNodeIndex,
                "firstRead": target.lifetime.firstReadNodeIndex ?? -1,
                "lastRead": target.lifetime.lastReadNodeIndex ?? -1,
                "persistent": target.lifetime.requiresHistorySeed,
                "historySeed": target.lifetime.requiresHistorySeed,
            ]
        }
    }

    static func clearSummary(_ plan: SceneGraphRenderTargetPlan) -> [[Double]] {
        plan.logicalTargets.map { target in
            target.initialClear.map {
                [$0.red, $0.green, $0.blue, $0.alpha]
            } ?? []
        }
    }

    static func extentSummary(
        _ extent: Graph.TargetExtent,
        inputWidth: Int = 1920,
        inputHeight: Int = 1080
    ) -> [Int] {
        guard let resolved = SceneGraphRenderTargetPlan.pixelExtent(
            extent,
            inputWidth: inputWidth,
            inputHeight: inputHeight
        ) else {
            return [-1, -1]
        }
        return [resolved.width, resolved.height]
    }

    static func encodedExtentKeys(_ extent: Graph.TargetExtent) throws -> [String] {
        let data = try JSONEncoder().encode(extent)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return object.keys.sorted()
    }

    static func main() throws {
        let key = Graph.EffectKey(layerID: 10, effectIndex: 0, descriptorID: "10#effect#1")
        let input = texture(.layerSource)
        let output = texture(.effectOutput, key: key)
        let q1 = texture(.framebuffer, key: key, name: "q1")
        let q2 = texture(.framebuffer, key: key, name: "q2")
        let scaleFour = Graph.TargetExtent(kind: .scale, first: 4, second: nil)
        let inputExtent = Graph.TargetExtent(kind: .input, first: nil, second: nil)
        let composedExtent = Graph.TargetExtent(
            width: 1000,
            height: nil,
            fit: 600,
            scale: 2
        )
        let oneAxisNoUpscale = Graph.TargetExtent(
            width: nil,
            height: 720,
            fit: 2000,
            scale: nil
        )
        let absoluteExtent = Graph.TargetExtent(
            width: 640,
            height: 480,
            fit: nil,
            scale: nil
        )
        let upscaleDivisor = Graph.TargetExtent(
            width: nil,
            height: nil,
            fit: nil,
            scale: 0.5
        )
        let minimumExtent = Graph.TargetExtent(
            width: nil,
            height: nil,
            fit: nil,
            scale: 10_000
        )
        let encodedComposedExtent = try JSONEncoder().encode(composedExtent)
        let decodedComposedExtent = try JSONDecoder().decode(
            Graph.TargetExtent.self,
            from: encodedComposedExtent
        )
        let decodedLegacyScaleExtent = try JSONDecoder().decode(
            Graph.TargetExtent.self,
            from: Data(#"{"kind":"scale","first":4}"#.utf8)
        )

        let standard = graph(
            targets: [target(q1, extent: scaleFour), target(q2, extent: scaleFour)],
            nodes: [
                node(0, key: key, target: q1, reads: [input]),
                node(1, key: key, target: q2, reads: [q1]),
                node(2, key: key, target: q1, reads: [q2]),
                node(3, key: key, target: output, reads: [q1, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let standardResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 4, logicalRenderTargetCount: 2),
            graph: standard,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let standardPlan) = standardResult else {
            fatalError("standard fixture rejected")
        }
        let rgba8888 = graph(
            targets: [
                target(q1, extent: scaleFour, format: "rgba8888"),
                target(q2, extent: scaleFour, format: "rgba8888"),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let rgba8888Result = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 4, logicalRenderTargetCount: 2),
            graph: rgba8888,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let rgba8888Plan) = rgba8888Result else {
            fatalError("rgba8888 fixture rejected")
        }

        let full = texture(.framebuffer, key: key, name: "full")
        let precise = graph(
            targets: [target(full, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: full, reads: []),
                node(1, key: key, target: output, reads: [full, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let preciseResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(layerID: 10, materialNodeCount: 2, logicalRenderTargetCount: 1),
            graph: precise,
            inputWidth: 1279,
            inputHeight: 719
        )
        guard case .success(let precisePlan) = preciseResult else {
            fatalError("precise fixture rejected")
        }
        let functionOnly = graph(
            targets: [target(full, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: output, reads: [full, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let functionOnlyWithoutInvocation = failure(
            functionOnly,
            materialNodeCount: 1
        )
        let functionOnlyPlan = requirePlan(
            functionOnly,
            materialNodeCount: 1,
            materialFunctionTargets: [full]
        )
        let authoredZeroClearArray = graph(
            targets: [
                target(
                    q1,
                    extent: scaleFour,
                    clear: .array([.number(0), .number(0), .number(0), .number(0)])
                ),
                target(q2, extent: scaleFour),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let authoredZeroClearString = graph(
            targets: [
                target(q1, extent: scaleFour, clear: .string("0 0 0 0")),
                target(q2, extent: scaleFour),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let nonZeroClear = graph(
            targets: [
                target(
                    q1,
                    extent: scaleFour,
                    clear: .array([.number(0.1), .number(0), .number(0), .number(0)])
                ),
                target(q2, extent: scaleFour),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let malformedClear = graph(
            targets: [
                target(
                    q1,
                    extent: scaleFour,
                    clear: .array([.number(0), .number(0), .number(0)])
                ),
                target(q2, extent: scaleFour),
            ],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let commands = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: q1, reads: [input]),
                node(1, key: key, target: q2, reads: [input]),
                commandNode(2, kind: .copy, key: key, source: q1, target: q2),
                commandNode(3, kind: .swap, key: key, source: q1, target: q2),
                node(4, key: key, target: output, reads: [q1]),
            ],
            key: key,
            input: input,
            output: output
        )
        let commandsResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 3,
                logicalRenderTargetCount: 2
            ),
            graph: commands,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let commandsPlan) = commandsResult else {
            fatalError("command fixture rejected")
        }
        let motionBlur = graph(
            targets: [
                target(q1, extent: inputExtent, unique: true),
                target(q2, extent: inputExtent),
            ],
            nodes: [
                node(0, key: key, target: q2, reads: [input, q1]),
                commandNode(1, kind: .copy, key: key, source: q2, target: q1),
                node(2, key: key, target: output, reads: [q2]),
            ],
            key: key,
            input: input,
            output: output
        )
        let motionBlurPlan = requirePlan(motionBlur, materialNodeCount: 2)
        let transparentClear = SceneJSONValue.array([
            .number(0), .number(0), .number(0), .number(0),
        ])
        let clearMismatchCopy = graph(
            targets: [
                target(q1, extent: inputExtent, clear: transparentClear),
                target(q2, extent: inputExtent),
            ],
            nodes: [
                node(0, key: key, target: q1, reads: [input]),
                commandNode(1, kind: .copy, key: key, source: q1, target: q2),
                node(2, key: key, target: output, reads: [q2]),
            ],
            key: key,
            input: input,
            output: output
        )
        let clearMismatchCopyPlan = requirePlan(
            clearMismatchCopy,
            materialNodeCount: 2
        )
        let swapNodes = [
            node(0, key: key, target: q1, reads: [input]),
            node(1, key: key, target: q2, reads: [input]),
            commandNode(2, kind: .swap, key: key, source: q1, target: q2),
            node(3, key: key, target: output, reads: [q1]),
        ]
        let uniqueMismatchSwap = graph(
            targets: [
                target(q1, extent: inputExtent, unique: true),
                target(q2, extent: inputExtent),
            ],
            nodes: swapNodes,
            key: key,
            input: input,
            output: output
        )
        let clearMismatchSwap = graph(
            targets: [
                target(q1, extent: inputExtent, clear: transparentClear),
                target(q2, extent: inputExtent),
            ],
            nodes: swapNodes,
            key: key,
            input: input,
            output: output
        )
        let incompatibleCommands = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: scaleFour)],
            nodes: commands.nodes,
            key: key,
            input: input,
            output: output
        )
        let commandBeforeWrite = graph(
            targets: [target(q1, extent: inputExtent), target(q2, extent: inputExtent)],
            nodes: [
                commandNode(0, kind: .copy, key: key, source: q1, target: q2),
                node(1, key: key, target: q1, reads: [input]),
                node(2, key: key, target: output, reads: [q1]),
            ],
            key: key,
            input: input,
            output: output
        )

        let history = graph(
            targets: [target(q1, extent: scaleFour), target(q2, extent: scaleFour)],
            nodes: [
                node(0, key: key, target: q1, reads: [q2]),
                node(1, key: key, target: q2, reads: [q1]),
                node(2, key: key, target: output, reads: [q2, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let persistentHistory = graph(
            targets: [
                target(q1, extent: scaleFour, unique: true),
                target(q2, extent: scaleFour, unique: true),
            ],
            nodes: history.nodes,
            key: key,
            input: input,
            output: output
        )
        let persistentHistoryResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 3,
                logicalRenderTargetCount: 2
            ),
            graph: persistentHistory,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let persistentHistoryPlan) = persistentHistoryResult else {
            fatalError("persistent history fixture rejected")
        }
        let clearSeedMaterial = graph(
            targets: [
                target(q1, extent: scaleFour),
                target(q2, extent: scaleFour, clear: transparentClear),
            ],
            nodes: history.nodes,
            key: key,
            input: input,
            output: output
        )
        let clearSeedMaterialPlan = requirePlan(
            clearSeedMaterial,
            materialNodeCount: 3
        )
        let clearSeedCopy = graph(
            targets: [
                target(q1, extent: inputExtent, clear: transparentClear),
                target(q2, extent: inputExtent),
            ],
            nodes: [
                commandNode(0, kind: .copy, key: key, source: q1, target: q2),
                node(1, key: key, target: q1, reads: [input]),
                node(2, key: key, target: output, reads: [q2]),
            ],
            key: key,
            input: input,
            output: output
        )
        let clearSeedCopyPlan = requirePlan(clearSeedCopy, materialNodeCount: 2)
        let clearSeedSwap = graph(
            targets: [
                target(q1, extent: inputExtent, clear: transparentClear),
                target(q2, extent: inputExtent, clear: transparentClear),
            ],
            nodes: [
                commandNode(0, kind: .swap, key: key, source: q1, target: q2),
                node(1, key: key, target: output, reads: [q1]),
            ],
            key: key,
            input: input,
            output: output
        )
        let clearSeedSwapPlan = requirePlan(clearSeedSwap, materialNodeCount: 1)
        let composeFalse = graph(
            targets: [],
            nodes: [node(
                0, key: key, target: output, reads: [input], compose: .bool(false)
            )],
            key: key,
            input: input,
            output: output
        )
        let composeTrue = graph(
            targets: [],
            nodes: [node(
                0, key: key, target: output, reads: [input], compose: .bool(true)
            )],
            key: key,
            input: input,
            output: output
        )
        let composeString = graph(
            targets: [],
            nodes: [node(
                0, key: key, target: output, reads: [input],
                compose: .string("false")
            )],
            key: key,
            input: input,
            output: output
        )
        let composeFalsePlan = requirePlan(composeFalse, materialNodeCount: 1)
        let composeTransition = graph(
            targets: [],
            nodes: [
                node(
                    0, key: key, target: output, reads: [input],
                    compose: .bool(true)
                ),
                node(1, key: key, target: output, reads: [input]),
            ],
            key: key,
            input: input,
            output: output
        )
        guard case .success(let genericComposePlan) =
            SceneGraphRenderTargetPlan.make(
                graph: composeTransition,
                inputRole: .layerSource,
                inputWidth: 1920,
                inputHeight: 1080
            ) else {
            fatalError("typed compose target plan rejected")
        }
        let rippleBuffer1 = texture(.framebuffer, key: key, name: "_rt_EightBuffer1")
        let rippleBuffer2 = texture(.framebuffer, key: key, name: "_rt_EightBuffer2")
        let fit512 = Graph.TargetExtent(kind: .fit, first: 512, second: nil)
        let cursorHistory = graph(
            targets: [
                target(rippleBuffer1, extent: fit512, format: "rgba8888"),
                target(rippleBuffer2, extent: fit512, format: "rgba8888"),
            ],
            nodes: [
                node(0, key: key, target: rippleBuffer1, reads: [rippleBuffer2]),
                node(1, key: key, target: rippleBuffer2, reads: [rippleBuffer1]),
                node(2, key: key, target: output, reads: [rippleBuffer2, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let cursorHistoryResult = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 3,
                logicalRenderTargetCount: 2,
                cursorRipple: .init(effectKey: key)
            ),
            graph: cursorHistory,
            inputWidth: 1920,
            inputHeight: 1080
        )
        guard case .success(let cursorHistoryPlan) = cursorHistoryResult else {
            fatalError("cursor history fixture rejected")
        }
        let duplicate = graph(
            targets: [target(q1, extent: scaleFour), target(q1, extent: scaleFour)],
            nodes: standard.nodes,
            key: key,
            input: input,
            output: output
        )
        let incompleteIdentity = texture(.framebuffer, name: "orphan")
        let incomplete = graph(
            targets: [target(incompleteIdentity, extent: inputExtent)],
            nodes: [
                node(0, key: key, target: incompleteIdentity, reads: []),
                node(1, key: key, target: output, reads: [incompleteIdentity, input]),
            ],
            key: key,
            input: input,
            output: output
        )
        let unique = graph(
            targets: [target(full, extent: inputExtent, unique: true)],
            nodes: precise.nodes,
            key: key,
            input: input,
            output: output
        )
        let r8 = graph(
            targets: [target(full, extent: inputExtent, format: "r8")],
            nodes: precise.nodes,
            key: key,
            input: input,
            output: output
        )
        guard case .success(let r8Plan) = SceneGraphRenderTargetPlan.make(
            executionPlan: .init(
                layerID: 10,
                materialNodeCount: 2,
                logicalRenderTargetCount: 1
            ),
            graph: r8,
            inputWidth: 256,
            inputHeight: 256
        ) else { fatalError("r8 fixture rejected") }
        let unsupportedFormats = ["rg88", "r16f", "rg1616f", "unknown"]
        let priorKey = Graph.EffectKey(
            layerID: 10,
            effectIndex: 0,
            descriptorID: "10#effect#0"
        )
        let priorOutput = texture(.effectOutput, key: priorKey)
        let roleMismatch = graph(
            targets: standard.renderTargets,
            nodes: standard.nodes,
            key: key,
            input: priorOutput,
            output: output
        )

        let result: [String: Any] = [
            "standardInput": standardPlan.input.kind.rawValue,
            "standardOutput": standardPlan.output.kind.rawValue,
            "standardInputExtent": [
                standardPlan.inputExtent.width, standardPlan.inputExtent.height,
            ],
            "standardTargets": targetSummary(standardPlan),
            "rgba8888Targets": targetSummary(rgba8888Plan),
            "r8Targets": targetSummary(r8Plan),
            "preciseInputExtent": [
                precisePlan.inputExtent.width, precisePlan.inputExtent.height,
            ],
            "preciseTargets": targetSummary(precisePlan),
            "functionOnlyWithoutInvocation": functionOnlyWithoutInvocation,
            "functionOnlyTargets": targetSummary(functionOnlyPlan),
            "authoredZeroClearArray": clearSummary(
                requirePlan(authoredZeroClearArray, materialNodeCount: 4)
            ),
            "authoredZeroClearString": clearSummary(
                requirePlan(authoredZeroClearString, materialNodeCount: 4)
            ),
            "authoredNonZeroClearResult": failure(nonZeroClear),
            "malformedClearFailure": failure(malformedClear),
            "commandTargets": targetSummary(commandsPlan),
            "persistentHistoryTargets": targetSummary(persistentHistoryPlan),
            "clearSeedMaterialTargets": targetSummary(clearSeedMaterialPlan),
            "clearSeedCopyTargets": targetSummary(clearSeedCopyPlan),
            "clearSeedSwapTargets": targetSummary(clearSeedSwapPlan),
            "clearSeedSwapCommands": clearSeedSwapPlan.commands.map(\.kind.rawValue),
            "composeFalseAccepted": composeFalsePlan.logicalTargets.isEmpty,
            "composeTrueFailure": failure(composeTrue, materialNodeCount: 1),
            "composeStringFailure": failure(composeString, materialNodeCount: 1),
            "typedFullFrameComposeAccepted": failure(
                composeTransition,
                materialNodeCount: 2,
                supportsUnifiedFullFrameComposeStage: true
            ) == "success",
            "genericComposeAccepted": genericComposePlan.output == output,
            "cursorHistoryTargets": targetSummary(cursorHistoryPlan),
            "commands": commandsPlan.commands.map {
                [
                    "node": $0.nodeIndex,
                    "kind": $0.kind.rawValue,
                    "source": $0.source.name ?? "",
                    "target": $0.target.name ?? "",
                ]
            },
            "motionBlurCommands": motionBlurPlan.commands.map {
                [
                    "node": $0.nodeIndex,
                    "kind": $0.kind.rawValue,
                    "source": $0.source.name ?? "",
                    "target": $0.target.name ?? "",
                ]
            },
            "motionBlurTargets": targetSummary(motionBlurPlan),
            "motionBlurUnique": motionBlurPlan.logicalTargets.map(\.isUnique),
            "clearMismatchCopyCommands": clearMismatchCopyPlan.commands.map {
                [
                    "node": $0.nodeIndex,
                    "kind": $0.kind.rawValue,
                    "source": $0.source.name ?? "",
                    "target": $0.target.name ?? "",
                ]
            },
            "clearMismatchCopyClears": clearSummary(clearMismatchCopyPlan),
            "uniqueMismatchSwapFailure": failure(
                uniqueMismatchSwap, materialNodeCount: 3
            ),
            "clearMismatchSwapFailure": failure(
                clearMismatchSwap, materialNodeCount: 3
            ),
            "incompatibleCommandFailure": failure(
                incompatibleCommands, materialNodeCount: 3
            ),
            "commandBeforeWriteFailure": failure(
                commandBeforeWrite, materialNodeCount: 2
            ),
            "historyFailure": failure(history),
            "duplicateFailure": failure(duplicate),
            "incompleteFailure": failure(incomplete),
            "uniqueFailure": failure(unique),
            "unsupportedFormatFailures": unsupportedFormats.map { format in
                failure(graph(
                    targets: [target(full, extent: inputExtent, format: format)],
                    nodes: precise.nodes,
                    key: key,
                    input: input,
                    output: output
                ), materialNodeCount: 2)
            },
            "countMismatchFailure": failure(standard, materialNodeCount: 3),
            "roleMismatchFailure": failure(roleMismatch),
            "composedExtent": extentSummary(composedExtent),
            "oneAxisNoUpscale": extentSummary(oneAxisNoUpscale),
            "absoluteExtent": extentSummary(absoluteExtent),
            "upscaleDivisor": extentSummary(upscaleDivisor),
            "minimumExtent": extentSummary(
                minimumExtent,
                inputWidth: 3,
                inputHeight: 2
            ),
            "composedExtentEncodedKeys": try encodedExtentKeys(composedExtent),
            "legacyScaleEncodedKeys": try encodedExtentKeys(scaleFour),
            "composedExtentRoundTrip": extentSummary(decodedComposedExtent),
            "legacyScaleExtent": extentSummary(decodedLegacyScaleExtent),
            "invalidExtentsRejected": [
                Graph.TargetExtent(width: 0, height: nil, fit: nil, scale: nil),
                Graph.TargetExtent(width: nil, height: nil, fit: nil, scale: 0),
                Graph.TargetExtent(width: .nan, height: nil, fit: nil, scale: nil),
                Graph.TargetExtent(width: nil, height: .infinity, fit: nil, scale: nil),
            ].allSatisfy {
                extentSummary($0) == [-1, -1]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphRenderTargetPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-rt-plan-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-rt-plan"
        subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_standard_blur_targets_preserve_extent_and_lifetime(self) -> None:
        self.assertEqual(self.result["standardInput"], "layerSource")
        self.assertEqual(self.result["standardOutput"], "effectOutput")
        self.assertEqual(self.result["standardInputExtent"], [1920, 1080])
        self.assertEqual(
            self.result["standardTargets"],
            [
                {
                    "name": "q1",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 2,
                    "firstRead": 1,
                    "lastRead": 3,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 2,
                    "lastRead": 2,
                    "persistent": False,
                    "historySeed": False,
                },
            ],
        )

    def test_precise_blur_target_uses_exact_input_extent(self) -> None:
        self.assertEqual(self.result["preciseInputExtent"], [1279, 719])
        self.assertEqual(
            self.result["preciseTargets"],
            [
                {
                    "name": "full",
                    "size": [1279, 719],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                }
            ],
        )

    def test_rgba8888_targets_preserve_authored_format(self) -> None:
        self.assertEqual(
            [target["format"] for target in self.result["rgba8888Targets"]],
            ["rgba8888", "rgba8888"],
        )

    def test_r8_target_preserves_authored_format_and_extent(self) -> None:
        self.assertEqual(
            self.result["r8Targets"],
            [
                {
                    "name": "full",
                    "size": [256, 256],
                    "format": "r8",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                }
            ],
        )

    def test_read_before_first_write_requires_history(self) -> None:
        self.assertEqual(self.result["historyFailure"], "historyRequired")
        self.assertEqual(self.result["commandBeforeWriteFailure"], "historyRequired")

    def test_material_function_target_is_a_typed_graph_write(self) -> None:
        self.assertEqual(self.result["functionOnlyWithoutInvocation"], "historyRequired")
        self.assertEqual(
            self.result["functionOnlyTargets"],
            [
                {
                    "name": "full",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 0,
                    "lastRead": 0,
                    "persistent": False,
                    "historySeed": False,
                }
            ],
        )

    def test_unique_read_before_write_is_a_seeded_persistent_target(self) -> None:
        self.assertEqual(
            self.result["persistentHistoryTargets"],
            [
                {
                    "name": "q1",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [480, 270],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 0,
                    "lastRead": 2,
                    "persistent": True,
                    "historySeed": True,
                },
            ],
        )

    def test_authored_clear_is_a_defined_seed_for_every_first_read_shape(self) -> None:
        material = self.result["clearSeedMaterialTargets"]
        copy = self.result["clearSeedCopyTargets"]
        swap = self.result["clearSeedSwapTargets"]
        self.assertEqual(
            [(target["name"], target["historySeed"]) for target in material],
            [("q1", False), ("q2", True)],
        )
        self.assertEqual(
            [(target["name"], target["historySeed"]) for target in copy],
            [("q1", True), ("q2", False)],
        )
        self.assertEqual(
            [(target["name"], target["historySeed"]) for target in swap],
            [("q1", True), ("q2", True)],
        )
        self.assertEqual(self.result["clearSeedSwapCommands"], ["swap"])

    def test_compose_false_is_absent_but_other_raw_shapes_fail_closed(self) -> None:
        self.assertTrue(self.result["composeFalseAccepted"])
        self.assertEqual(self.result["composeTrueFailure"], "executionMismatch")
        self.assertEqual(self.result["composeStringFailure"], "executionMismatch")
        self.assertTrue(self.result["typedFullFrameComposeAccepted"])
        self.assertTrue(self.result["genericComposeAccepted"])

    def test_cursor_ripple_admits_only_its_named_history_and_fit_extent(self) -> None:
        self.assertEqual(
            self.result["cursorHistoryTargets"],
            [
                {
                    "name": "_rt_EightBuffer1",
                    "size": [512, 288],
                    "format": "rgba8888",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 1,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "_rt_EightBuffer2",
                    "size": [512, 288],
                    "format": "rgba8888",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 0,
                    "lastRead": 2,
                    "persistent": True,
                    "historySeed": True,
                },
            ],
        )

    def test_copy_and_swap_extend_target_lifetimes_in_authored_order(self) -> None:
        self.assertEqual(
            self.result["commands"],
            [
                {"node": 2, "kind": "copy", "source": "q1", "target": "q2"},
                {"node": 3, "kind": "swap", "source": "q1", "target": "q2"},
            ],
        )
        self.assertEqual(
            self.result["commandTargets"],
            [
                {
                    "name": "q1",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 3,
                    "firstRead": 2,
                    "lastRead": 4,
                    "persistent": False,
                    "historySeed": False,
                },
                {
                    "name": "q2",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 3,
                    "firstRead": 3,
                    "lastRead": 3,
                    "persistent": False,
                    "historySeed": False,
                },
            ],
        )
        self.assertEqual(
            self.result["incompatibleCommandFailure"],
            "unsupportedTargetDescriptor",
        )

    def test_copy_uses_storage_compatibility_but_swap_requires_full_descriptor(self) -> None:
        self.assertEqual(
            self.result["motionBlurCommands"],
            [{"node": 1, "kind": "copy", "source": "q2", "target": "q1"}],
        )
        self.assertEqual(
            self.result["motionBlurTargets"],
            [
                {
                    "name": "q1",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 1,
                    "lastWrite": 1,
                    "firstRead": 0,
                    "lastRead": 0,
                    "persistent": True,
                    "historySeed": True,
                },
                {
                    "name": "q2",
                    "size": [1920, 1080],
                    "format": "rgbaBackbuffer",
                    "firstWrite": 0,
                    "lastWrite": 0,
                    "firstRead": 1,
                    "lastRead": 2,
                    "persistent": False,
                    "historySeed": False,
                },
            ],
        )
        self.assertEqual(self.result["motionBlurUnique"], [True, False])
        self.assertEqual(
            self.result["clearMismatchCopyCommands"],
            [{"node": 1, "kind": "copy", "source": "q1", "target": "q2"}],
        )
        self.assertEqual(
            self.result["clearMismatchCopyClears"],
            [[0.0, 0.0, 0.0, 0.0], []],
        )
        self.assertEqual(
            self.result["uniqueMismatchSwapFailure"],
            "unsupportedTargetDescriptor",
        )
        self.assertEqual(
            self.result["clearMismatchSwapFailure"],
            "unsupportedTargetDescriptor",
        )

    def test_extent_operations_are_composed_in_authored_order(self) -> None:
        self.assertEqual(self.result["composedExtent"], [277, 300])
        self.assertEqual(self.result["oneAxisNoUpscale"], [1920, 720])
        self.assertEqual(self.result["absoluteExtent"], [640, 480])
        self.assertEqual(self.result["upscaleDivisor"], [3840, 2160])
        self.assertEqual(self.result["minimumExtent"], [1, 1])
        self.assertEqual(
            self.result["composedExtentEncodedKeys"],
            ["fit", "kind", "scale", "width"],
        )
        self.assertEqual(self.result["legacyScaleEncodedKeys"], ["first", "kind"])
        self.assertEqual(self.result["composedExtentRoundTrip"], [277, 300])
        self.assertEqual(self.result["legacyScaleExtent"], [480, 270])

    def test_invalid_extent_values_fail_closed(self) -> None:
        self.assertTrue(self.result["invalidExtentsRejected"])

    def test_duplicate_and_incomplete_identities_fail_closed(self) -> None:
        self.assertEqual(self.result["duplicateFailure"], "duplicateTarget")
        self.assertEqual(self.result["incompleteFailure"], "incompleteIdentity")

    def test_unsupported_descriptor_and_execution_mismatch_fail_closed(self) -> None:
        self.assertEqual(self.result["uniqueFailure"], "success")
        self.assertEqual(
            self.result["unsupportedFormatFailures"],
            ["unsupportedTargetDescriptor"] * 4,
        )
        self.assertEqual(self.result["countMismatchFailure"], "executionMismatch")
        self.assertEqual(self.result["roleMismatchFailure"], "executionMismatch")

    def test_bounded_authored_clear_is_preserved_and_malformed_clear_rejected(self) -> None:
        self.assertEqual(
            self.result["authoredZeroClearArray"],
            [[0.0, 0.0, 0.0, 0.0], []],
        )
        self.assertEqual(
            self.result["authoredZeroClearString"],
            [[0.0, 0.0, 0.0, 0.0], []],
        )
        self.assertEqual(
            self.result["authoredNonZeroClearResult"],
            "success",
        )
        self.assertEqual(
            self.result["malformedClearFailure"],
            "unsupportedTargetDescriptor",
        )


if __name__ == "__main__":
    unittest.main()
