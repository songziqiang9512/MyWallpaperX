#!/usr/bin/env python3

"""Pure-value gate for the layer-scoped two-member full-frame pair."""

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
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneLayerFullFramePairPlan.swift",
]


HARNESS = r'''
import Foundation

private typealias Graph = SceneAuthoredEffectRenderPlan
private typealias Pair = SceneLayerFullFramePairPlan

private let layerID = 700

private func key(_ index: Int) -> Graph.EffectKey {
    .init(
        layerID: layerID,
        effectIndex: index,
        descriptorID: "pair-effect-\(index)"
    )
}

private func layerSource() -> Graph.TextureIdentity {
    SceneAuthoredEffectInputValidator.layerSource(layerID: layerID)
}

private func output(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
    .init(
        kind: .effectOutput,
        layerID: layerID,
        effect: effect,
        name: nil
    )
}

private func framebuffer(
    _ effect: Graph.EffectKey,
    _ name: String
) -> Graph.TextureIdentity {
    .init(
        kind: .framebuffer,
        layerID: layerID,
        effect: effect,
        name: name
    )
}

private func declaration(
    _ identity: Graph.TextureIdentity
) -> Graph.RenderTarget {
    .init(
        texture: identity,
        extent: .init(kind: .input, first: nil, second: nil),
        format: nil,
        declaredUnique: false,
        clear: nil,
        uvs: nil,
        conditions: nil
    )
}

private func binding(
    _ identity: Graph.TextureIdentity,
    condition: SceneJSONValue? = nil
) -> Graph.Binding {
    .init(
        slot: 0,
        authoredName: "previous",
        texture: identity,
        conditions: condition
    )
}

private func material(
    nodeIndex: Int,
    passIndex: Int,
    ordinal: Int,
    effect: Graph.EffectKey,
    target: Graph.TextureIdentity,
    read: Graph.TextureIdentity? = nil,
    compose: SceneJSONValue? = nil,
    condition: SceneJSONValue? = nil
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: passIndex,
        materialOrdinal: ordinal,
        instancePassIndex: ordinal,
        kind: .material,
        materialPath: "materials/pair-\(effect.effectIndex)-\(ordinal).json",
        materialPassID: "pair-\(effect.effectIndex)-\(ordinal)",
        target: target,
        bindings: read.map { [binding($0)] } ?? [],
        commandSource: nil,
        commandTarget: nil,
        compose: compose,
        conditions: condition
    )
}

private func command(
    nodeIndex: Int,
    passIndex: Int,
    effect: Graph.EffectKey,
    kind: Graph.NodeKind,
    source: Graph.TextureIdentity,
    target: Graph.TextureIdentity,
    compose: SceneJSONValue? = nil
) -> Graph.Node {
    .init(
        nodeIndex: nodeIndex,
        effect: effect,
        definitionPassIndex: passIndex,
        materialOrdinal: nil,
        instancePassIndex: nil,
        kind: kind,
        materialPath: nil,
        materialPassID: nil,
        target: nil,
        bindings: [],
        commandSource: source,
        commandTarget: target,
        compose: compose,
        conditions: nil
    )
}

private func graph(
    effect: Graph.EffectKey,
    input: Graph.TextureIdentity,
    nodes: [Graph.Node],
    targets: [Graph.RenderTarget] = [],
    blockers: [Graph.Blocker] = []
) -> Graph {
    let final = output(effect)
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/pair-\(effect.effectIndex)/effect.json",
            input: input,
            output: final,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: targets,
        nodes: nodes,
        finalOutput: final,
        blockers: blockers
    )
}

private func simpleChain(_ count: Int) -> [Graph] {
    var input = layerSource()
    var result: [Graph] = []
    for index in 0 ..< count {
        let effect = key(index)
        let final = output(effect)
        result.append(graph(
            effect: effect,
            input: input,
            nodes: [material(
                nodeIndex: index * 10,
                passIndex: 0,
                ordinal: index,
                effect: effect,
                target: final,
                read: input
            )]
        ))
        input = final
    }
    return result
}

private func requirePlan(_ graphs: [Graph]) -> Pair {
    switch Pair.make(conditionPrunedGraphs: graphs) {
    case let .success(value): return value
    case let .failure(failure):
        fatalError("pair plan failed: \(failure.rawValue)")
    }
}

private func failure(_ graphs: [Graph]) -> String {
    switch Pair.make(conditionPrunedGraphs: graphs) {
    case .success: return "accepted"
    case let .failure(value): return value.rawValue
    }
}

private func member(_ value: Pair.Member?) -> Int {
    value?.rawValue ?? -1
}

@main
private enum Harness {
    static func main() throws {
        let one = requirePlan(simpleChain(1))
        let two = requirePlan(simpleChain(2))
        let three = requirePlan(simpleChain(3))

        let refractionKey = key(10)
        let refractionInput = layerSource()
        let refractionOutput = output(refractionKey)
        let refraction = requirePlan([graph(
            effect: refractionKey,
            input: refractionInput,
            nodes: [
                material(
                    nodeIndex: 100,
                    passIndex: 0,
                    ordinal: 0,
                    effect: refractionKey,
                    target: refractionOutput,
                    read: refractionInput,
                    compose: .bool(true)
                ),
                material(
                    nodeIndex: 101,
                    passIndex: 1,
                    ordinal: 1,
                    effect: refractionKey,
                    target: refractionOutput,
                    read: refractionInput
                ),
            ]
        )])

        let multipleKey = key(11)
        let multipleInput = layerSource()
        let multipleOutput = output(multipleKey)
        let multiple = requirePlan([graph(
            effect: multipleKey,
            input: multipleInput,
            nodes: [
                material(
                    nodeIndex: 110,
                    passIndex: 0,
                    ordinal: 0,
                    effect: multipleKey,
                    target: multipleOutput,
                    read: multipleInput,
                    compose: .bool(true)
                ),
                material(
                    nodeIndex: 111,
                    passIndex: 1,
                    ordinal: 1,
                    effect: multipleKey,
                    target: multipleOutput,
                    read: multipleInput,
                    compose: .bool(true)
                ),
                material(
                    nodeIndex: 112,
                    passIndex: 2,
                    ordinal: 2,
                    effect: multipleKey,
                    target: multipleOutput,
                    read: multipleInput
                ),
            ]
        )])

        let falseKey = key(12)
        let falseInput = layerSource()
        let composeFalse = requirePlan([graph(
            effect: falseKey,
            input: falseInput,
            nodes: [material(
                nodeIndex: 120,
                passIndex: 0,
                ordinal: 0,
                effect: falseKey,
                target: output(falseKey),
                read: falseInput,
                compose: .bool(false)
            )]
        )])

        // A condition-false earlier pass has already been pruned. Authored
        // node/pass/material ordinals keep their gaps and must remain valid.
        let prunedKey = key(13)
        let prunedInput = layerSource()
        let pruned = requirePlan([graph(
            effect: prunedKey,
            input: prunedInput,
            nodes: [material(
                nodeIndex: 131,
                passIndex: 2,
                ordinal: 2,
                effect: prunedKey,
                target: output(prunedKey),
                read: prunedInput,
                compose: .bool(false)
            )]
        )])

        let commandKey = key(14)
        let commandInput = layerSource()
        let first = framebuffer(commandKey, "first")
        let second = framebuffer(commandKey, "second")
        let commands = requirePlan([graph(
            effect: commandKey,
            input: commandInput,
            nodes: [
                material(
                    nodeIndex: 140,
                    passIndex: 0,
                    ordinal: 0,
                    effect: commandKey,
                    target: first,
                    read: commandInput
                ),
                command(
                    nodeIndex: 141,
                    passIndex: 1,
                    effect: commandKey,
                    kind: .copy,
                    source: first,
                    target: second
                ),
                command(
                    nodeIndex: 142,
                    passIndex: 2,
                    effect: commandKey,
                    kind: .swap,
                    source: first,
                    target: second
                ),
                material(
                    nodeIndex: 143,
                    passIndex: 3,
                    ordinal: 1,
                    effect: commandKey,
                    target: output(commandKey),
                    read: commandInput
                ),
            ],
            targets: [declaration(first), declaration(second)]
        )])

        let malformedKey = key(20)
        let malformedInput = layerSource()
        let malformedCompose = graph(
            effect: malformedKey,
            input: malformedInput,
            nodes: [material(
                nodeIndex: 200,
                passIndex: 0,
                ordinal: 0,
                effect: malformedKey,
                target: output(malformedKey),
                read: malformedInput,
                compose: .string("true")
            )]
        )

        let commandComposeKey = key(21)
        let commandComposeInput = layerSource()
        let commandA = framebuffer(commandComposeKey, "a")
        let commandB = framebuffer(commandComposeKey, "b")
        let commandCompose = graph(
            effect: commandComposeKey,
            input: commandComposeInput,
            nodes: [
                command(
                    nodeIndex: 210,
                    passIndex: 0,
                    effect: commandComposeKey,
                    kind: .copy,
                    source: commandA,
                    target: commandB,
                    compose: .bool(false)
                ),
                material(
                    nodeIndex: 211,
                    passIndex: 1,
                    ordinal: 0,
                    effect: commandComposeKey,
                    target: output(commandComposeKey),
                    read: commandComposeInput
                ),
            ],
            targets: [declaration(commandA), declaration(commandB)]
        )

        let framebufferComposeKey = key(26)
        let framebufferComposeInput = layerSource()
        let framebufferComposeTarget = framebuffer(
            framebufferComposeKey,
            "compose-target"
        )
        let framebufferCompose = graph(
            effect: framebufferComposeKey,
            input: framebufferComposeInput,
            nodes: [
                material(
                    nodeIndex: 260,
                    passIndex: 0,
                    ordinal: 0,
                    effect: framebufferComposeKey,
                    target: framebufferComposeTarget,
                    read: framebufferComposeInput,
                    compose: .bool(true)
                ),
                material(
                    nodeIndex: 261,
                    passIndex: 1,
                    ordinal: 1,
                    effect: framebufferComposeKey,
                    target: output(framebufferComposeKey),
                    read: framebufferComposeInput
                ),
            ],
            targets: [declaration(framebufferComposeTarget)]
        )

        var brokenChain = simpleChain(2)
        let secondGraph = brokenChain[1]
        brokenChain[1] = graph(
            effect: secondGraph.effects[0].key,
            input: layerSource(),
            nodes: secondGraph.nodes
        )

        let terminalKey = key(22)
        let terminalInput = layerSource()
        let terminalCompose = graph(
            effect: terminalKey,
            input: terminalInput,
            nodes: [material(
                nodeIndex: 220,
                passIndex: 0,
                ordinal: 0,
                effect: terminalKey,
                target: output(terminalKey),
                read: terminalInput,
                compose: .bool(true)
            )]
        )

        let unmarkedIntermediateKey = key(27)
        let unmarkedIntermediateInput = layerSource()
        let unmarkedIntermediateOutput = output(unmarkedIntermediateKey)
        let unmarkedIntermediate = graph(
            effect: unmarkedIntermediateKey,
            input: unmarkedIntermediateInput,
            nodes: [
                material(
                    nodeIndex: 270,
                    passIndex: 0,
                    ordinal: 0,
                    effect: unmarkedIntermediateKey,
                    target: unmarkedIntermediateOutput,
                    read: unmarkedIntermediateInput
                ),
                material(
                    nodeIndex: 271,
                    passIndex: 1,
                    ordinal: 1,
                    effect: unmarkedIntermediateKey,
                    target: unmarkedIntermediateOutput,
                    read: unmarkedIntermediateInput
                ),
            ]
        )

        let noOutputKey = key(23)
        let noOutputInput = layerSource()
        let onlyFBO = framebuffer(noOutputKey, "only")
        let noOutput = graph(
            effect: noOutputKey,
            input: noOutputInput,
            nodes: [material(
                nodeIndex: 230,
                passIndex: 0,
                ordinal: 0,
                effect: noOutputKey,
                target: onlyFBO,
                read: noOutputInput
            )],
            targets: [declaration(onlyFBO)]
        )

        let orderKey = key(24)
        let orderInput = layerSource()
        let badOrder = graph(
            effect: orderKey,
            input: orderInput,
            nodes: [
                material(
                    nodeIndex: 241,
                    passIndex: 1,
                    ordinal: 0,
                    effect: orderKey,
                    target: output(orderKey),
                    read: orderInput
                ),
                material(
                    nodeIndex: 240,
                    passIndex: 2,
                    ordinal: 1,
                    effect: orderKey,
                    target: output(orderKey),
                    read: orderInput
                ),
            ]
        )

        let rawConditionKey = key(25)
        let rawConditionInput = layerSource()
        let rawCondition = graph(
            effect: rawConditionKey,
            input: rawConditionInput,
            nodes: [material(
                nodeIndex: 250,
                passIndex: 0,
                ordinal: 0,
                effect: rawConditionKey,
                target: output(rawConditionKey),
                read: rawConditionInput,
                condition: .bool(true)
            )]
        )

        func pairs(_ plan: Pair) -> [[Int]] {
            plan.effects.map { [$0.inputMember.rawValue, $0.outputMember.rawValue] }
        }
        func terminalInvariant(_ plan: Pair) -> Bool {
            plan.terminalMember == .zero
                && plan.effects.last?.outputMember == .zero
                && plan.baseCaptureMember.rawValue
                    == (plan.transitionCount.isMultiple(of: 2) ? 0 : 1)
        }

        let refractionNodes = refraction.effects[0].nodes
        let multipleNodes = multiple.effects[0].nodes
        let commandNodes = commands.effects[0].nodes
        let result: [String: Any] = [
            "members": Pair.reservedMembers.map(\.rawValue),
            "parity": [
                "one": [
                    "transitions": one.transitionCount,
                    "base": one.baseCaptureMember.rawValue,
                    "pairs": pairs(one),
                ],
                "two": [
                    "transitions": two.transitionCount,
                    "base": two.baseCaptureMember.rawValue,
                    "pairs": pairs(two),
                ],
                "three": [
                    "transitions": three.transitionCount,
                    "base": three.baseCaptureMember.rawValue,
                    "pairs": pairs(three),
                ],
            ],
            "refraction": [
                "transitions": refraction.transitionCount,
                "input": refraction.effects[0].inputMember.rawValue,
                "output": refraction.effects[0].outputMember.rawValue,
                "alias": refraction.effects[0].inputMember
                    == refraction.effects[0].outputMember,
                "writes": refractionNodes.map { member($0.fullFrameWriteMember) },
                "after": refractionNodes.map { $0.currentMemberAfterNode.rawValue },
                "rotates": refractionNodes.map(\.rotatesAfterNode),
            ],
            "multipleCompose": [
                "transitions": multiple.transitionCount,
                "alias": multiple.effects[0].inputMember
                    == multiple.effects[0].outputMember,
                "writes": multipleNodes.map { member($0.fullFrameWriteMember) },
                "rotates": multipleNodes.map(\.rotatesAfterNode),
            ],
            "composeFalse": [
                "transitions": composeFalse.transitionCount,
                "rotates": composeFalse.effects[0].nodes.map(\.rotatesAfterNode),
            ],
            "conditionPruned": [
                "acceptedNode": pruned.effects[0].nodes[0].nodeIndex,
                "transitions": pruned.transitionCount,
            ],
            "commands": [
                "transitions": commands.transitionCount,
                "kinds": commandNodes.map(\.kind.rawValue),
                "reads": commandNodes.map { member($0.fullFrameReadMember) },
                "writes": commandNodes.map { member($0.fullFrameWriteMember) },
                "rotates": commandNodes.map(\.rotatesAfterNode),
                "before": commandNodes.map { $0.currentMemberBeforeNode.rawValue },
                "after": commandNodes.map { $0.currentMemberAfterNode.rawValue },
            ],
            "failures": [
                "malformedCompose": failure([malformedCompose]),
                "commandCompose": failure([commandCompose]),
                "framebufferCompose": failure([framebufferCompose]),
                "noncontiguous": failure(brokenChain),
                "terminalCompose": failure([terminalCompose]),
                "unmarkedIntermediate": failure([unmarkedIntermediate]),
                "missingOutput": failure([noOutput]),
                "nodeOrder": failure([badOrder]),
                "rawCondition": failure([rawCondition]),
            ],
            "terminalInvariant": [one, two, three, refraction, multiple,
                composeFalse, pruned, commands].allSatisfy(terminalInvariant),
            "baseCaptureIdentity": one.baseCaptureIdentity == layerSource(),
            "terminalOutputIdentity": three.terminalOutputIdentity
                == output(key(2)),
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
class SceneLayerFullFramePairPlanTests(unittest.TestCase):
    def test_pair_parity_compose_and_fail_closed_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-layer-full-frame-pair-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "layer-full-frame-pair-test"
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        self.assertEqual(payload["members"], [0, 1])
        self.assertEqual(
            payload["parity"],
            {
                "one": {"transitions": 1, "base": 1, "pairs": [[1, 0]]},
                "two": {
                    "transitions": 2,
                    "base": 0,
                    "pairs": [[0, 1], [1, 0]],
                },
                "three": {
                    "transitions": 3,
                    "base": 1,
                    "pairs": [[1, 0], [0, 1], [1, 0]],
                },
            },
        )
        self.assertEqual(
            payload["refraction"],
            {
                "transitions": 2,
                "input": 0,
                "output": 0,
                "alias": True,
                "writes": [1, 0],
                "after": [1, 1],
                "rotates": [True, False],
            },
        )
        self.assertEqual(
            payload["multipleCompose"],
            {
                "transitions": 3,
                "alias": False,
                "writes": [0, 1, 0],
                "rotates": [True, True, False],
            },
        )
        self.assertEqual(
            payload["composeFalse"],
            {"transitions": 1, "rotates": [False]},
        )
        self.assertEqual(
            payload["conditionPruned"],
            {"acceptedNode": 131, "transitions": 1},
        )
        self.assertEqual(
            payload["commands"],
            {
                "transitions": 1,
                "kinds": ["material", "copy", "swap", "material"],
                "reads": [1, -1, -1, 1],
                "writes": [-1, -1, -1, 0],
                "rotates": [False, False, False, False],
                "before": [1, 1, 1, 1],
                "after": [1, 1, 1, 1],
            },
        )
        self.assertEqual(
            payload["failures"],
            {
                "malformedCompose": "invalid-compose",
                "commandCompose": "invalid-compose",
                "framebufferCompose": "invalid-compose",
                "noncontiguous": "noncontiguous-chain",
                "terminalCompose": "unwritten-boundary-output",
                "unmarkedIntermediate": "unwritten-boundary-output",
                "missingOutput": "missing-effect-output",
                "nodeOrder": "invalid-node-order",
                "rawCondition": "condition-not-pruned",
            },
        )
        self.assertTrue(payload["terminalInvariant"])
        self.assertTrue(payload["baseCaptureIdentity"])
        self.assertTrue(payload["terminalOutputIdentity"])


if __name__ == "__main__":
    unittest.main()
