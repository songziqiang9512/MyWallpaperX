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
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlanner+Resolution.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneLayerFullFramePairPlan.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Validation.swift",
    SOURCE_ROOT / "RenderGraph/GraphTargets/SceneGraphExecutionState+Identity.swift",
]


BLUR = {
    "passes": [
        {"material": "materials/down.json", "target": "q1", "bind": [{"name": "previous", "index": 0}]},
        {"material": "materials/x.json", "target": "q2", "bind": [{"name": "q1", "index": 0}]},
        {"material": "materials/y.json", "target": "q1", "bind": [{"name": "q2", "index": 0}]},
        {
            "material": "materials/combine.json",
            "bind": [{"name": "q1", "index": 0}, {"name": "previous", "index": 2}],
        },
    ],
    "fbos": [
        {"name": "q1", "scale": 4, "format": "rgba_backbuffer"},
        {"name": "q2", "scale": 4, "format": "rgba_backbuffer"},
    ],
}

MOTION = {
    "passes": [
        {
            "material": "materials/motion_accumulate.json",
            "target": "full2",
            "bind": [{"name": "previous", "index": 0}, {"name": "full1", "index": 1}],
        },
        {"command": "copy", "source": "full2", "target": "full1"},
        {"material": "materials/motion_combine.json", "bind": [{"name": "full2", "index": 0}]},
    ],
    "fbos": [
        {"name": "full1", "scale": 1, "format": "rgba_backbuffer", "unique": True},
        {"name": "full2", "scale": 1, "format": "rgba_backbuffer"},
    ],
}

SAFE_COMMAND_FBO = {
    "passes": [
        {
            "material": "materials/safe-init-a.json",
            "target": "scratch_a",
            "bind": [{"name": "previous", "index": 0}],
        },
        {
            "material": "materials/safe-init-b.json",
            "target": "scratch_b",
            "bind": [{"name": "previous", "index": 0}],
        },
        {"command": "swap", "source": "scratch_a", "target": "scratch_b"},
        {"command": "copy", "source": "scratch_a", "target": "scratch_b"},
        {
            "material": "materials/safe-terminal.json",
            "bind": [{"name": "scratch_b", "index": 0}],
        },
    ],
    "fbos": [
        {"name": "scratch_a", "scale": 2, "format": "rgba_backbuffer"},
        {"name": "scratch_b", "scale": 2, "format": "rgba_backbuffer"},
    ],
}

UNSAFE_COPY_FBO = {
    "passes": [
        {
            "material": "materials/copy-init-a.json",
            "target": "copy_a",
            "bind": [{"name": "previous", "index": 0}],
        },
        {
            "material": "materials/copy-init-b.json",
            "target": "copy_b",
            "bind": [{"name": "previous", "index": 0}],
        },
        {"command": "copy", "source": "copy_a", "target": "copy_b"},
        {
            "material": "materials/copy-terminal.json",
            "bind": [{"name": "copy_b", "index": 0}],
        },
    ],
    "fbos": [
        {"name": "copy_a", "scale": 1, "format": "rgba_backbuffer"},
        {"name": "copy_b", "scale": 2, "format": "rgba_backbuffer"},
    ],
}

FLUID = {
    "passes": [
        *[
            {
                "material": f"materials/fluid_{index}.json",
                "target": "velocity1" if index % 2 == 0 else "velocity2",
                "bind": [{"name": "velocity2" if index % 2 == 0 else "velocity1", "index": 0}],
            }
            for index in range(17)
        ],
        {
            "material": "materials/fluid_combine.json",
            "bind": [
                {"name": "dye2", "index": 0},
                {"name": "previous", "index": 1},
                {"name": "velocity2", "index": 4, "conditions": [{"RENDERING": 3}]},
            ],
        },
        {"command": "swap", "source": "velocity1", "target": "velocity2"},
        {"command": "swap", "source": "dye1", "target": "dye2"},
    ],
    "fbos": [
        {"name": name, "fit": 256, "format": "rg1616f", "unique": True}
        for name in ("velocity1", "velocity2", "dye1", "dye2")
    ],
    "functions": {"reset": {"action": "clear"}},
}

COMPOSE = {
    "passes": [{"material": "materials/compose.json", "compose": True}],
    "fbos": [],
}

COMPOSE_FALSE = {
    "passes": [{"material": "materials/compose-false.json", "compose": False}],
    "fbos": [],
}

COMPOSE_STRING = {
    "passes": [{"material": "materials/compose-string.json", "compose": "false"}],
    "fbos": [],
}

SEMANTIC_SWAP = {
    "passes": [
        {"command": "swap", "source": "a", "target": "b"},
        {
            "material": "materials/semantic-swap.json",
            "bind": [{"name": "b", "index": 0}],
            "compose": False,
        },
    ],
    "fbos": [
        {
            "name": "a",
            "scale": 1,
            "format": "RGBA_BACKBUFFER",
            "clear": "0 0 0 0",
        },
        {
            "name": "b",
            "scale": 1,
            "format": "rgba_backbuffer",
            "unique": False,
            "clear": [0, 0, 0, 0],
        },
    ],
}


def incompatible_swap(
    source: dict[str, object], target: dict[str, object]
) -> dict[str, object]:
    return {
        "passes": [
            {"command": "swap", "source": "a", "target": "b"},
            {
                "material": "materials/incompatible-swap.json",
                "bind": [{"name": "b", "index": 0}],
            },
        ],
        "fbos": [
            {"name": "a", **source},
            {"name": "b", **target},
        ],
    }


INCOMPATIBLE_EXTENT = incompatible_swap(
    {"scale": 1, "format": "rgba_backbuffer", "unique": True},
    {"scale": 2, "format": "rgba_backbuffer", "unique": True},
)
INCOMPATIBLE_FORMAT = incompatible_swap(
    {"scale": 1, "format": "rgba_backbuffer", "unique": True},
    {"scale": 1, "format": "rgba8888", "unique": True},
)
INCOMPATIBLE_UNIQUE = incompatible_swap(
    {"scale": 1, "format": "rgba_backbuffer", "unique": True},
    {"scale": 1, "format": "rgba_backbuffer", "unique": False},
)
INCOMPATIBLE_CLEAR = incompatible_swap(
    {
        "scale": 1,
        "format": "rgba_backbuffer",
        "unique": True,
        "clear": [0, 0, 0, 0],
    },
    {"scale": 1, "format": "rgba_backbuffer", "unique": True},
)

RAW_COMPOSE = {
    "passes": [
        {"material": "materials/raw-compose-x.json", "compose": True},
        {"material": "materials/raw-compose-y.json"},
    ],
    "fbos": [],
}

COMPOSED_EXTENT = {
    "passes": [
        {
            "material": "materials/composed-x.json",
            "target": "composed",
            "bind": [{"name": "previous", "index": 0}],
        },
        {
            "material": "materials/composed-y.json",
            "bind": [{"name": "composed", "index": 0}],
        },
    ],
    "fbos": [
        {
            "name": "composed",
            "width": 1000,
            "fit": 600,
            "scale": 2,
            "format": "rgba_backbuffer",
        }
    ],
}

MALFORMED = {
    "passes": [
        {
            "material": "materials/bad.json",
            "target": "missing",
            "bind": [
                {"name": "missing", "index": -1},
                {"name": "previous", "index": -1},
            ],
        },
        {"command": "teleport", "source": "same", "target": "same"},
        {"command": "swap", "source": "left", "target": "right"},
    ],
    "fbos": [
        {
            "name": "same",
            "scale": 1,
            "format": "rgba_backbuffer",
            "unique": "yes",
            "clear": [0, 0, 0],
        },
        {"name": "left", "scale": 1, "format": "rgba_backbuffer", "unique": True},
        {"name": "right", "scale": 1, "format": "rgba_backbuffer"},
        {"name": "bad-scale", "scale": "2", "format": "rgba_backbuffer"},
        {"name": "bad-width", "width": 0, "format": "rgba_backbuffer"},
    ],
}


HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let passIndex: Int
    }

    let layers: [Layer]
    let effectDefinitions: [SceneEffectDefinition]
    let materialPasses: [MaterialPassDescriptor]
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

@main
enum Harness {
    typealias Plan = SceneAuthoredEffectRenderPlan
    typealias TargetPlan = SceneGraphRenderTargetPlan
    typealias State = SceneGraphExecutionState

    static func effect(
        _ id: String,
        _ file: String,
        passCount: Int,
        visible: Bool = true
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: file,
            visible: visible,
            passes: (0..<passCount).map { .init(passIndex: $0) }
        )
    }

    static func textureKey(_ texture: Plan.TextureIdentity?) -> String {
        guard let texture else { return "nil" }
        return [
            texture.kind.rawValue,
            String(texture.layerID),
            texture.effect.map { String($0.effectIndex) } ?? "-",
            texture.name ?? "-",
        ].joined(separator: ":")
    }

    static func targetPlan(
        _ graph: Plan,
        width: Int = 64,
        height: Int = 32
    ) -> Result<TargetPlan, TargetPlan.Failure> {
        TargetPlan.make(
            executionPlan: .init(
                layerID: graph.layerID,
                materialNodeCount: graph.nodes.filter { $0.kind == .material }.count,
                logicalRenderTargetCount: graph.renderTargets.count,
                inputRole: .layerSource
            ),
            graph: graph,
            inputWidth: width,
            inputHeight: height
        )
    }

    static func targetPlanFailure(
        _ graph: Plan,
        width: Int = 64,
        height: Int = 32
    ) -> String {
        switch targetPlan(graph, width: width, height: height) {
        case .success: return "success"
        case .failure(let failure): return failure.rawValue
        }
    }

    static func pairStep(_ graph: Plan) -> SceneLayerFullFramePairPlan.EffectStep {
        guard case let .success(pair) = SceneLayerFullFramePairPlan.make(
            conditionPrunedGraphs: [graph]
        ), pair.effects.count == 1, let step = pair.effects.first else {
            fatalError("full-frame pair plan failed")
        }
        return step
    }

    static func allocation(_ plan: TargetPlan) -> State.Allocation {
        let logical = Dictionary(uniqueKeysWithValues: plan.logicalTargets.map {
            ($0.identity, $0)
        })
        var resources: [Plan.TextureIdentity: State.Resource] = [:]
        for (index, identity) in plan.logicalTargets.map(\.identity).enumerated() {
            let target = logical[identity]
            resources[identity] = .init(
                token: .init(rawValue: "raw-graph-\(index)"),
                descriptor: .init(
                    extent: target?.extent ?? plan.inputExtent,
                    format: target?.format ?? .rgbaBackbuffer,
                    addressMode: target?.addressMode ?? .clampToEdge,
                    isUnique: target?.isUnique ?? false,
                    initialClear: target?.initialClear
                )
            )
        }
        return .init(generation: 1, resources: resources)
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let names = [
            "blur", "motion", "safe-command-fbo", "unsafe-copy-fbo",
            "raw-compose", "composed-extent",
            "fluid", "compose", "compose-false", "compose-string",
            "semantic-swap", "incompatible-extent", "incompatible-format",
            "incompatible-unique", "incompatible-clear", "malformed",
        ]
        let definitions = try names.map { name in
            try SceneEffectDefinitionLoader().load(
                from: root.appendingPathComponent("\(name).json"),
                relativePath: "effects/\(name)/effect.json"
            )
        }
        let materialPaths = Set(definitions.flatMap { definition in
            definition.passes.compactMap(\.materialPath)
        })
        let materials = materialPaths.sorted().map {
            SceneRenderDescriptor.MaterialPassDescriptor(
                id: "\($0)#0",
                materialPath: $0,
                passIndex: 0
            )
        }
        let layers: [SceneRenderDescriptor.Layer] = [
            .init(id: 10, effects: [effect("blur-a", "effects/blur/effect.json", passCount: 4)]),
            .init(id: 20, effects: [effect("motion-a", "effects/motion/effect.json", passCount: 2)]),
            .init(id: 30, effects: [effect("fluid-a", "effects/fluid/effect.json", passCount: 18)]),
            .init(id: 40, effects: [effect("compose-a", "effects/compose/effect.json", passCount: 1)]),
            .init(id: 45, effects: [
                effect("raw-compose-a", "effects/raw-compose/effect.json", passCount: 2),
            ]),
            .init(id: 50, effects: [
                effect("blur-first", "effects/blur/effect.json", passCount: 4),
                effect("blur-second", "effects/blur/effect.json", passCount: 4),
            ]),
            .init(id: 60, effects: [effect("bad-a", "effects/malformed/effect.json", passCount: 1)]),
            .init(id: 70, effects: [
                effect("composed-a", "effects/composed-extent/effect.json", passCount: 2),
            ]),
            .init(id: 75, effects: [
                effect("compose-false-a", "effects/compose-false/effect.json", passCount: 1),
            ]),
            .init(id: 80, effects: [
                effect("compose-string-a", "effects/compose-string/effect.json", passCount: 1),
            ]),
            .init(id: 85, effects: [
                effect("semantic-swap-a", "effects/semantic-swap/effect.json", passCount: 1),
            ]),
            .init(id: 90, effects: [
                effect("extent-a", "effects/incompatible-extent/effect.json", passCount: 1),
            ]),
            .init(id: 91, effects: [
                effect("format-a", "effects/incompatible-format/effect.json", passCount: 1),
            ]),
            .init(id: 92, effects: [
                effect("unique-a", "effects/incompatible-unique/effect.json", passCount: 1),
            ]),
            .init(id: 93, effects: [
                effect("clear-a", "effects/incompatible-clear/effect.json", passCount: 1),
            ]),
            .init(id: 100, effects: [
                effect("active-prefix", "effects/compose-false/effect.json", passCount: 1),
                effect(
                    "startup-pair-leaf",
                    "effects/compose-false/effect.json",
                    passCount: 1,
                    visible: false
                ),
                effect("active-suffix", "effects/compose-false/effect.json", passCount: 1),
            ]),
            .init(id: 101, effects: [
                effect("fbo-prefix", "effects/compose-false/effect.json", passCount: 1),
                effect(
                    "renamed-startup-command-graph",
                    "effects/safe-command-fbo/effect.json",
                    passCount: 3,
                    visible: false
                ),
                effect("fbo-suffix", "effects/compose-false/effect.json", passCount: 1),
            ]),
            .init(id: 102, effects: [
                effect(
                    "static-disabled",
                    "effects/compose-false/effect.json",
                    passCount: 1,
                    visible: false
                ),
            ]),
            .init(id: 103, effects: [
                effect("unsafe-prefix", "effects/compose-false/effect.json", passCount: 1),
                effect(
                    "startup-history-read",
                    "effects/motion/effect.json",
                    passCount: 2,
                    visible: false
                ),
                effect("unsafe-suffix", "effects/compose-false/effect.json", passCount: 1),
            ]),
            .init(id: 104, effects: [
                effect("copy-prefix", "effects/compose-false/effect.json", passCount: 1),
                effect(
                    "startup-copy-mismatch",
                    "effects/unsafe-copy-fbo/effect.json",
                    passCount: 3,
                    visible: false
                ),
                effect("copy-suffix", "effects/compose-false/effect.json", passCount: 1),
            ]),
        ]
        let plans = SceneAuthoredEffectRenderPlanner.plans(for: .init(
            layers: layers,
            effectDefinitions: definitions,
            materialPasses: materials
        ), startupInactiveEffectVisibilityTargets: [
            .effectVisibility(layerID: 100, effectIndex: 1),
            .effectVisibility(layerID: 101, effectIndex: 1),
            .effectVisibility(layerID: 103, effectIndex: 1),
            .effectVisibility(layerID: 104, effectIndex: 1),
        ])
        let byLayer = Dictionary(uniqueKeysWithValues: plans.map { ($0.layerID, $0) })
        let blur = byLayer[10]!
        let motion = byLayer[20]!
        let fluid = byLayer[30]!
        let compose = byLayer[40]!
        let rawCompose = byLayer[45]!
        let scoped = byLayer[50]!
        let malformed = byLayer[60]!
        let composed = byLayer[70]!
        let composeFalse = byLayer[75]!
        let composeString = byLayer[80]!
        let semanticSwap = byLayer[85]!
        let incompatibleExtent = byLayer[90]!
        let incompatibleFormat = byLayer[91]!
        let incompatibleUnique = byLayer[92]!
        let incompatibleClear = byLayer[93]!
        let startupPairLeaf = byLayer[100]!
        let startupFBO = byLayer[101]!
        let unsafeStartupFBO = byLayer[103]!
        let unsafeCopyFBO = byLayer[104]!
        let incompatibleGraphs = [
            incompatibleExtent, incompatibleFormat, incompatibleUnique, incompatibleClear,
        ]
        let motionTargets = Dictionary(uniqueKeysWithValues: motion.renderTargets.map {
            ($0.texture.name ?? "", $0)
        })
        let composedExtent = composed.renderTargets[0].extent
        guard case .success(let composeFalseTargetPlan) = targetPlan(composeFalse) else {
            fatalError("compose false target plan failed")
        }
        let composeFalseStateAccepted: Bool
        switch State.reduce(
            graph: composeFalse,
            targetPlan: composeFalseTargetPlan,
            pairStep: pairStep(composeFalse),
            allocation: allocation(composeFalseTargetPlan),
            effectGeneration: 1,
            resetGeneration: 1
        ) {
        case .success: composeFalseStateAccepted = true
        case .failure: composeFalseStateAccepted = false
        }
        guard case .success(let semanticTargetPlan) = targetPlan(semanticSwap) else {
            fatalError("semantic descriptor swap target plan failed")
        }
        let semanticState = State.reduce(
            graph: semanticSwap,
            targetPlan: semanticTargetPlan,
            pairStep: pairStep(semanticSwap),
            allocation: allocation(semanticTargetPlan),
            effectGeneration: 1,
            resetGeneration: 1
        )
        let semanticStateAccepted: Bool
        switch semanticState {
        case .success: semanticStateAccepted = true
        case .failure: semanticStateAccepted = false
        }

        let result: [String: Any] = [
            "blurKinds": blur.nodes.map { $0.kind.rawValue },
            "blurOrdinals": blur.nodes.map { $0.materialOrdinal ?? -1 },
            "blurTargets": blur.nodes.map { textureKey($0.target) },
            "blurPrevious": [
                textureKey(blur.nodes[0].bindings[0].texture),
                textureKey(blur.nodes[3].bindings[1].texture),
            ],
            "blurStructural": blur.isStructurallyResolved,
            "motionKinds": motion.nodes.map { $0.kind.rawValue },
            "motionOrdinals": motion.nodes.map { $0.materialOrdinal ?? -1 },
            "motionInstancePasses": motion.nodes.map { $0.instancePassIndex ?? -1 },
            "motionCopy": [
                textureKey(motion.nodes[1].commandSource),
                textureKey(motion.nodes[1].commandTarget),
            ],
            "motionDeclaredUnique": [
                motionTargets["full1"]!.declaredUnique,
                motionTargets["full2"]!.declaredUnique,
            ],
            "fluidNodeCount": fluid.nodes.count,
            "fluidMaterialOrdinals": fluid.nodes.compactMap(\.materialOrdinal),
            "fluidTailKinds": fluid.nodes.suffix(3).map { $0.kind.rawValue },
            "fluidBlockers": fluid.blockers.map { $0.reason.rawValue },
            "composeBlockers": compose.blockers.map { $0.reason.rawValue },
            "composeTextureKinds": Array(Set(
                compose.nodes.flatMap { node in
                    [node.target, node.commandSource, node.commandTarget]
                        .compactMap { $0?.kind.rawValue }
                        + node.bindings.map { $0.texture.kind.rawValue }
                }
            )).sorted(),
            "composeFalseBlockers": composeFalse.blockers.map { $0.reason.rawValue },
            "composeFalsePlanFailure": targetPlanFailure(composeFalse),
            "composeFalseStateAccepted": composeFalseStateAccepted,
            "composeStringBlockers": composeString.blockers.map { $0.reason.rawValue },
            "semanticSwapBlockers": semanticSwap.blockers.map { $0.reason.rawValue },
            "semanticSwapHistory": semanticTargetPlan.logicalTargets.map {
                $0.lifetime.requiresHistorySeed
            },
            "semanticSwapUnique": semanticTargetPlan.logicalTargets.map(\.isUnique),
            "semanticSwapClearCount": semanticTargetPlan.logicalTargets.filter {
                $0.initialClear != nil
            }.count,
            "semanticSwapStateAccepted": semanticStateAccepted,
            "semanticSwapAuthoredDescriptorsCompatible":
                SceneGraphRenderTargetPlan.authoredSwapDescriptorsAreCompatible(
                    in: semanticSwap
                ),
            "incompatibleAuthoredDescriptorsCompatible": incompatibleGraphs.map {
                SceneGraphRenderTargetPlan.authoredSwapDescriptorsAreCompatible(in: $0)
            },
            "incompatibleOnePixelPlanFailures": incompatibleGraphs.map {
                targetPlanFailure($0, width: 1, height: 1)
            },
            "incompatibleRawBlockers": [
                incompatibleExtent, incompatibleFormat,
                incompatibleUnique, incompatibleClear,
            ].map { $0.blockers.map(\.reason.rawValue) },
            "incompatiblePlanFailures": [
                incompatibleExtent, incompatibleFormat,
                incompatibleUnique, incompatibleClear,
            ].map { targetPlanFailure($0) },
            "rawComposeStructural": rawCompose.isStructurallyResolved,
            "rawComposeBlockers": rawCompose.blockers.map { $0.reason.rawValue },
            "rawComposeTargets": rawCompose.nodes.map { textureKey($0.target) },
            "rawComposeBindings": rawCompose.nodes.map { node in
                node.bindings.map { "\(String(describing: $0.slot))=\(textureKey($0.texture))" }
            },
            "rawComposeTargetCount": rawCompose.renderTargets.count,
            "rawComposeValuesPreserved": rawCompose.nodes.count == 2
                && rawCompose.nodes[0].compose == .bool(true)
                && rawCompose.nodes[1].compose == nil,
            "scopedQ1": scoped.renderTargets
                .filter { $0.texture.name == "q1" }
                .map { textureKey($0.texture) },
            "secondInput": textureKey(scoped.effects[1].input),
            "firstOutput": textureKey(scoped.effects[0].output),
            "malformedBlockers": malformed.blockers.map { $0.reason.rawValue },
            "malformedStructural": malformed.isStructurallyResolved,
            "composedStructural": composed.isStructurallyResolved,
            "composedExtent": [
                composedExtent.kind.rawValue,
                String(composedExtent.width ?? -1),
                String(composedExtent.height ?? -1),
                String(composedExtent.fit ?? -1),
                String(composedExtent.scale ?? -1),
            ],
            "startupPairLeafEffectIndices":
                startupPairLeaf.effects.map(\.key.effectIndex),
            "startupPairLeafInputs": startupPairLeaf.effects.map {
                textureKey($0.input)
            },
            "startupPairLeafOutputs": startupPairLeaf.effects.map {
                textureKey($0.output)
            },
            "startupFBOEffectIndices": startupFBO.effects.map(\.key.effectIndex),
            "startupFBOTargetCount": startupFBO.renderTargets.count,
            "startupFBONodeKinds": startupFBO.nodes.filter {
                $0.effect.effectIndex == 1
            }.map(\.kind.rawValue),
            "unsafeStartupFBOEffectIndices":
                unsafeStartupFBO.effects.map(\.key.effectIndex),
            "unsafeStartupFBOTargetCount": unsafeStartupFBO.renderTargets.count,
            "unsafeCopyFBOEffectIndices":
                unsafeCopyFBO.effects.map(\.key.effectIndex),
            "unsafeCopyFBOTargetCount": unsafeCopyFBO.renderTargets.count,
            "staticDisabledPlanAbsent": byLayer[102] == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneEffectRenderGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-effect-graph-")
        root = Path(cls.temporary_directory.name)
        for name, fixture in {
            "blur": BLUR,
            "motion": MOTION,
            "safe-command-fbo": SAFE_COMMAND_FBO,
            "unsafe-copy-fbo": UNSAFE_COPY_FBO,
            "fluid": FLUID,
            "compose": COMPOSE,
            "compose-false": COMPOSE_FALSE,
            "compose-string": COMPOSE_STRING,
            "semantic-swap": SEMANTIC_SWAP,
            "incompatible-extent": INCOMPATIBLE_EXTENT,
            "incompatible-format": INCOMPATIBLE_FORMAT,
            "incompatible-unique": INCOMPATIBLE_UNIQUE,
            "incompatible-clear": INCOMPATIBLE_CLEAR,
            "raw-compose": RAW_COMPOSE,
            "composed-extent": COMPOSED_EXTENT,
            "malformed": MALFORMED,
        }.items():
            (root / f"{name}.json").write_text(json.dumps(fixture), encoding="utf-8")
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-effect-graph"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(root)], capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_blur_previous_is_fixed_chain_input_and_targets_follow_authored_order(self) -> None:
        self.assertTrue(self.result["blurStructural"])
        self.assertEqual(self.result["blurKinds"], ["material"] * 4)
        self.assertEqual(self.result["blurOrdinals"], [0, 1, 2, 3])
        self.assertEqual(self.result["blurPrevious"], ["layerSource:10:-:-"] * 2)
        self.assertEqual(
            self.result["blurTargets"],
            ["framebuffer:10:0:q1", "framebuffer:10:0:q2", "framebuffer:10:0:q1", "effectOutput:10:0:-"],
        )

    def test_motion_command_does_not_consume_instance_material_ordinal(self) -> None:
        self.assertEqual(self.result["motionKinds"], ["material", "copy", "material"])
        self.assertEqual(self.result["motionOrdinals"], [0, -1, 1])
        self.assertEqual(self.result["motionInstancePasses"], [0, -1, 1])
        self.assertEqual(
            self.result["motionCopy"],
            ["framebuffer:20:0:full2", "framebuffer:20:0:full1"],
        )
        self.assertEqual(
            self.result["motionDeclaredUnique"],
            [True, False],
        )

    def test_fluid_preserves_material_then_swap_order_but_is_not_executable(self) -> None:
        self.assertEqual(self.result["fluidNodeCount"], 20)
        self.assertEqual(self.result["fluidMaterialOrdinals"], list(range(18)))
        self.assertEqual(self.result["fluidTailKinds"], ["material", "swap", "swap"])
        self.assertIn("unsupportedFunctions", self.result["fluidBlockers"])
        self.assertIn("unsupportedCondition", self.result["fluidBlockers"])

    def test_compose_true_fails_closed_without_scene_texture_guess(self) -> None:
        self.assertIn("unsupportedCompose", self.result["composeBlockers"])
        self.assertNotIn("sceneCompose", self.result["composeTextureKinds"])

    def test_compose_false_flows_from_raw_planner_through_state(self) -> None:
        self.assertEqual(self.result["composeFalseBlockers"], [])
        self.assertEqual(self.result["composeFalsePlanFailure"], "success")
        self.assertTrue(self.result["composeFalseStateAccepted"])
        self.assertIn("unsupportedCompose", self.result["composeStringBlockers"])

    def test_descriptor_semantics_are_resolved_once_by_target_plan(self) -> None:
        self.assertEqual(self.result["semanticSwapBlockers"], [])
        self.assertEqual(self.result["semanticSwapHistory"], [True, True])
        self.assertEqual(self.result["semanticSwapUnique"], [False, False])
        self.assertEqual(self.result["semanticSwapClearCount"], 2)
        self.assertTrue(self.result["semanticSwapStateAccepted"])
        self.assertTrue(self.result["semanticSwapAuthoredDescriptorsCompatible"])

    def test_true_descriptor_incompatibility_fails_at_target_plan(self) -> None:
        self.assertEqual(
            self.result["incompatibleAuthoredDescriptorsCompatible"],
            [False] * 4,
        )
        self.assertEqual(
            self.result["incompatibleOnePixelPlanFailures"],
            ["unsupportedTargetDescriptor"] * 4,
        )
        self.assertEqual(self.result["incompatibleRawBlockers"], [[], [], [], []])
        self.assertEqual(
            self.result["incompatiblePlanFailures"],
            ["unsupportedTargetDescriptor"] * 4,
        )

    def test_raw_two_pass_compose_is_preserved_without_synthetic_framebuffer(self) -> None:
        self.assertTrue(self.result["rawComposeStructural"])
        self.assertEqual(self.result["rawComposeBlockers"], [])
        self.assertEqual(self.result["rawComposeTargetCount"], 0)
        self.assertEqual(
            self.result["rawComposeTargets"],
            ["effectOutput:45:0:-", "effectOutput:45:0:-"],
        )
        self.assertEqual(self.result["rawComposeBindings"], [[], []])
        self.assertTrue(self.result["rawComposeValuesPreserved"])

    def test_framebuffer_identity_is_effect_scoped_and_chain_ordered(self) -> None:
        self.assertEqual(
            self.result["scopedQ1"],
            ["framebuffer:50:0:q1", "framebuffer:50:1:q1"],
        )
        self.assertEqual(self.result["secondInput"], self.result["firstOutput"])
        self.assertEqual(self.result["secondInput"], "effectOutput:50:0:-")

    def test_composed_extent_preserves_each_authored_operation(self) -> None:
        self.assertTrue(self.result["composedStructural"])
        self.assertEqual(
            self.result["composedExtent"],
            ["composed", "1000.0", "-1.0", "600.0", "2.0"],
        )

    def test_malformed_graph_is_diagnostic_and_ineligible(self) -> None:
        self.assertFalse(self.result["malformedStructural"])
        reasons = self.result["malformedBlockers"]
        self.assertIn("invalidBinding", reasons)
        self.assertIn("unknownTexture", reasons)
        self.assertIn("unknownCommand", reasons)
        self.assertIn("incompatibleCommand", reasons)
        self.assertIn("invalidFramebufferUnique", reasons)
        self.assertIn("invalidFramebufferClear", reasons)
        self.assertIn("unsupportedFramebufferExtent", reasons)

    def test_startup_inactive_pair_leaf_preserves_authored_sibling_chain(self) -> None:
        self.assertEqual(self.result["startupPairLeafEffectIndices"], [0, 1, 2])
        inputs = self.result["startupPairLeafInputs"]
        outputs = self.result["startupPairLeafOutputs"]
        self.assertEqual(inputs[1], outputs[0])
        self.assertEqual(inputs[2], outputs[1])

    def test_startup_inactive_safe_fbo_keeps_authored_command_chain(self) -> None:
        self.assertEqual(self.result["startupFBOEffectIndices"], [0, 1, 2])
        self.assertEqual(self.result["startupFBOTargetCount"], 2)
        self.assertEqual(
            self.result["startupFBONodeKinds"],
            ["material", "material", "swap", "copy", "material"],
        )

    def test_startup_inactive_unsafe_fbo_and_static_false_remain_outside_slice(self) -> None:
        self.assertEqual(self.result["unsafeStartupFBOEffectIndices"], [0, 2])
        self.assertEqual(self.result["unsafeStartupFBOTargetCount"], 0)
        self.assertEqual(self.result["unsafeCopyFBOEffectIndices"], [0, 2])
        self.assertEqual(self.result["unsafeCopyFBOTargetCount"], 0)
        self.assertTrue(self.result["staticDisabledPlanAbsent"])


if __name__ == "__main__":
    unittest.main()
