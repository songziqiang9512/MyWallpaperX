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
TARGET_MAPPING_SOURCE = (
    SOURCE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift"
)
SERVICE_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopSceneService+SceneProperties.swift"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/ScenePuppetAnimationPropertyTarget.swift",
    SOURCE_ROOT / "Properties/ScenePropertyBindingProgram.swift",
    TARGET_MAPPING_SOURCE,
    SOURCE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
    SOURCE_ROOT / "Properties/ScenePropertyLiveUpdateState.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let alphaOne = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
    static let alphaTwo = SceneDynamicTarget.layer(layerID: 2, field: .alpha)
    static let alphaThree = SceneDynamicTarget.layer(layerID: 3, field: .alpha)
    static let color = SceneDynamicTarget.layer(layerID: 4, field: .color)
    static let xrayVisibility = SceneDynamicTarget.effectVisibility(
        layerID: 5,
        effectIndex: 0
    )
    static let genericVisibility = SceneDynamicTarget.effectVisibility(
        layerID: 6,
        effectIndex: 0
    )
    static let layoutOne = SceneDynamicTarget.layer(
        layerID: 7,
        field: .visibility
    )
    static let layoutTwo = SceneDynamicTarget.layer(
        layerID: 8,
        field: .visibility
    )
    static let layoutThree = SceneDynamicTarget.layer(
        layerID: 9,
        field: .visibility
    )

    static func main() throws {
        let liveProgram = program(
            bindings: [
                ("opacity", alphaOne, .scalar, .scalar(0.1)),
                ("opacity", alphaTwo, .scalar, .scalar(0.2)),
                ("accentOpacity", alphaThree, .scalar, .scalar(0.3)),
                ("tint", color, .vector3, .vector3(1, 1, 1)),
            ]
        )
        let initialValues: [String: SceneUserPropertyValue] = [
            "opacity": .number(0.5),
            "accentOpacity": .number(0.6),
            "tint": .string("0.1 0.2 0.3"),
        ]
        let alphaTargets: Set<SceneDynamicTarget> = [alphaOne, alphaTwo, alphaThree]
        var state = ScenePropertyLiveUpdateState(
            program: liveProgram,
            effectiveValues: initialValues,
            activeConsumerTargets: alphaTargets.union([color])
        )

        let initialEvaluatedAllTargets = scalar(state, alphaOne) == 0.5
            && scalar(state, alphaTwo) == 0.5
            && scalar(state, alphaThree) == 0.6
            && vector(state, color) == [0.1, 0.2, 0.3]
        let singleAccepted = state.apply(.number(0.75), forPropertyKey: "opacity")
        let singleUpdatedAllTargets = scalar(state, alphaOne) == 0.75
            && scalar(state, alphaTwo) == 0.75
            && vector(state, color) == [0.1, 0.2, 0.3]

        let beforeMissing = state
        let missingRejected = !state.apply(.number(0.4), forPropertyKey: "missing")
        let missingWasAtomic = unchanged(state, from: beforeMissing)

        let beforeTypeFailure = state
        let badTypeRejected = !state.apply(.string("0.2"), forPropertyKey: "opacity")
        let badTypeWasAtomic = unchanged(state, from: beforeTypeFailure)

        let beforeNonFinite = state
        let nonFiniteRejected = !state.apply(.number(.nan), forPropertyKey: "opacity")
        let nonFiniteWasAtomic = unchanged(state, from: beforeNonFinite)

        let colorAccepted = state.apply(.string("0.8 0.7 0.6"), forPropertyKey: "tint")
        let colorUpdated = vector(state, color) == [0.8, 0.7, 0.6]

        let beforeInvalidColor = state
        let invalidColorRejected = !state.apply(.string("0.2 0.4"), forPropertyKey: "tint")
        let invalidColorWasAtomic = unchanged(state, from: beforeInvalidColor)

        let beforeNonFiniteColor = state
        let nonFiniteColorRejected = !state.apply(
            .string("0.2 NaN 0.4"),
            forPropertyKey: "tint"
        )
        let nonFiniteColorWasAtomic = unchanged(state, from: beforeNonFiniteColor)

        let bulkAccepted = state.apply(
            replacements: [
                "opacity": .number(0.25),
                "accentOpacity": .number(0.35),
                "ignoredDefault": .number(99),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let bulkUpdatedAtomically = scalar(state, alphaOne) == 0.25
            && scalar(state, alphaTwo) == 0.25
            && scalar(state, alphaThree) == 0.35
            && state.effectiveValues["ignoredDefault"] == nil

        let beforeBulkFailure = state
        let badBulkRejected = !state.apply(
            replacements: [
                "opacity": .number(0.9),
                "accentOpacity": .string("bad"),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let badBulkWasAtomic = unchanged(state, from: beforeBulkFailure)

        let resetAccepted = state.apply(
            replacements: [
                "opacity": .number(0.5),
                "accentOpacity": .number(0.6),
                "tint": .string("1 1 1"),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let resetAppliedOnlyChangedKeys = scalar(state, alphaOne) == 0.5
            && scalar(state, alphaThree) == 0.6
            && vector(state, color) == [0.8, 0.7, 0.6]

        let beforeMissingResetDefault = state
        let missingResetDefaultRejected = !state.apply(
            replacements: ["opacity": .number(0.2)],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let missingResetDefaultWasAtomic = unchanged(state, from: beforeMissingResetDefault)

        let beforeNoOp = state
        let noOpAccepted = state.apply(
            replacements: ["opacity": .number(0.99)],
            changedPropertyKeys: []
        )
        let noOpIgnoredReplacements = unchanged(state, from: beforeNoOp)

        let rebuildProgram = program(
            bindings: [("opacity", alphaOne, .scalar, .scalar(0.1))],
            rebuildRequiredKeys: ["opacity"]
        )
        var rebuildState = ScenePropertyLiveUpdateState(
            program: rebuildProgram,
            effectiveValues: ["opacity": .number(0.5)],
            activeConsumerTargets: [alphaOne]
        )
        let beforeRebuild = rebuildState
        let rebuildRejected = !rebuildState.apply(.number(0.8), forPropertyKey: "opacity")
        let rebuildWasAtomic = unchanged(rebuildState, from: beforeRebuild)

        let mixedProgram = program(bindings: [
            ("mixed", alphaOne, .scalar, .scalar(0.1)),
            ("mixed", color, .vector3, .vector3(1, 1, 1)),
        ], rebuildRequiredKeys: ["mixed"])
        var mixedState = ScenePropertyLiveUpdateState(
            program: mixedProgram,
            effectiveValues: ["mixed": .number(0.5)],
            activeConsumerTargets: [alphaOne, color]
        )
        let beforeMixed = mixedState
        let mixedRejected = !mixedState.apply(.number(0.7), forPropertyKey: "mixed")
        let mixedWasAtomic = unchanged(mixedState, from: beforeMixed)

        let partialConsumerProgram = program(bindings: [
            ("sharedOpacity", alphaOne, .scalar, .scalar(1)),
            ("sharedOpacity", alphaTwo, .scalar, .scalar(1)),
        ])
        var partialConsumerState = ScenePropertyLiveUpdateState(
            program: partialConsumerProgram,
            effectiveValues: ["sharedOpacity": .number(1)],
            activeConsumerTargets: [alphaOne]
        )
        let beforePartialConsumer = partialConsumerState
        let partialConsumerRejected = !partialConsumerState.apply(
            .number(0.2),
            forPropertyKey: "sharedOpacity"
        )
        let partialConsumerWasAtomic = unchanged(
            partialConsumerState,
            from: beforePartialConsumer
        )

        let genericVisibilityProgram = program(bindings: [
            ("genericVisibility", genericVisibility, .bool, .bool(true)),
        ])
        var genericVisibilityState = ScenePropertyLiveUpdateState(
            program: genericVisibilityProgram,
            effectiveValues: ["genericVisibility": .bool(true)],
            activeConsumerTargets: []
        )
        let beforeGenericVisibility = genericVisibilityState
        let genericVisibilityRejected = !genericVisibilityState.apply(
            .bool(false),
            forPropertyKey: "genericVisibility"
        )
        let genericVisibilityWasAtomic = unchanged(
            genericVisibilityState,
            from: beforeGenericVisibility
        )

        let xrayVisibilityProgram = program(bindings: [
            ("xrayVisibility", xrayVisibility, .bool, .bool(true)),
        ])
        var xrayVisibilityState = ScenePropertyLiveUpdateState(
            program: xrayVisibilityProgram,
            effectiveValues: ["xrayVisibility": .bool(true)],
            activeConsumerTargets: [xrayVisibility]
        )
        let xrayVisibilityAccepted = xrayVisibilityState.apply(
            .bool(false),
            forPropertyKey: "xrayVisibility"
        )
        let xrayVisibilityUpdated = bool(xrayVisibilityState, xrayVisibility) == false

        let mixedVisibilityProgram = program(bindings: [
            ("sharedVisibility", xrayVisibility, .bool, .bool(true)),
            ("sharedVisibility", genericVisibility, .bool, .bool(true)),
        ])
        var mixedVisibilityState = ScenePropertyLiveUpdateState(
            program: mixedVisibilityProgram,
            effectiveValues: ["sharedVisibility": .bool(true)],
            activeConsumerTargets: [xrayVisibility]
        )
        let beforeMixedVisibility = mixedVisibilityState
        let mixedVisibilityRejected = !mixedVisibilityState.apply(
            .bool(false),
            forPropertyKey: "sharedVisibility"
        )
        let mixedVisibilityWasAtomic = unchanged(
            mixedVisibilityState,
            from: beforeMixedVisibility
        )

        let conditionalLayoutProgram = ScenePropertyBindingProgram(
            definitions: [
                .init(target: layoutOne, valueType: .bool, authoredValue: .bool(true)),
                .init(target: layoutTwo, valueType: .bool, authoredValue: .bool(false)),
                .init(target: layoutThree, valueType: .bool, authoredValue: .bool(true)),
            ],
            instructions: [
                .init(
                    propertyKey: "layout",
                    path: .init(components: [.key("layout"), .index(0)]),
                    target: layoutOne,
                    valueType: .bool,
                    condition: .string("one")
                ),
                .init(
                    propertyKey: "layout",
                    path: .init(components: [.key("layout"), .index(1)]),
                    target: layoutTwo,
                    valueType: .bool,
                    condition: .string("two")
                ),
                .init(
                    propertyKey: "layout",
                    path: .init(components: [.key("layout"), .index(2)]),
                    target: layoutThree,
                    valueType: .bool,
                    condition: .string("one")
                ),
            ],
            conditionalValueDomainsByPropertyKey: [
                "layout": ["base", "one", "two"],
            ]
        )
        var conditionalLayoutState = ScenePropertyLiveUpdateState(
            program: conditionalLayoutProgram,
            effectiveValues: ["layout": .string("one")],
            activeConsumerTargets: [layoutOne, layoutTwo, layoutThree]
        )
        let conditionalLayoutInitial = bool(conditionalLayoutState, layoutOne) == true
            && bool(conditionalLayoutState, layoutTwo) == false
            && bool(conditionalLayoutState, layoutThree) == true
        let conditionalLayoutAccepted = conditionalLayoutState.apply(
            .string("two"),
            forPropertyKey: "layout"
        )
        let conditionalLayoutSwapped = bool(conditionalLayoutState, layoutOne) == false
            && bool(conditionalLayoutState, layoutTwo) == true
            && bool(conditionalLayoutState, layoutThree) == false
        let conditionalLayoutBaseAccepted = conditionalLayoutState.apply(
            .string("base"),
            forPropertyKey: "layout"
        )
        let conditionalLayoutBaseCleared =
            bool(conditionalLayoutState, layoutOne) == false
                && bool(conditionalLayoutState, layoutTwo) == false
                && bool(conditionalLayoutState, layoutThree) == false
        let beforeUnmatchedLayout = conditionalLayoutState
        let conditionalLayoutUnmatchedRejected = !conditionalLayoutState.apply(
            .string("missing"),
            forPropertyKey: "layout"
        )
        let conditionalLayoutUnmatchedWasAtomic = unchanged(
            conditionalLayoutState,
            from: beforeUnmatchedLayout
        )
        var partialLayoutState = ScenePropertyLiveUpdateState(
            program: conditionalLayoutProgram,
            effectiveValues: ["layout": .string("one")],
            activeConsumerTargets: [layoutOne]
        )
        let beforePartialLayout = partialLayoutState
        let conditionalLayoutPartialRejected = !partialLayoutState.apply(
            .string("two"),
            forPropertyKey: "layout"
        )
        let conditionalLayoutPartialWasAtomic = unchanged(
            partialLayoutState,
            from: beforePartialLayout
        )

        let scriptRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "effects": [[
                    "passes": [[
                        "constantshadervalues": [
                            "scripted": [
                                "script": "export function update(value) { return value; }",
                                "scriptproperties": [
                                    "nestedSpeed": [
                                        "user": "scriptSpeed",
                                        "value": 50.0,
                                    ],
                                ],
                                "value": -0.2,
                            ],
                            "direct": [
                                "user": "scriptSpeed",
                                "value": 0.2,
                            ],
                        ],
                    ]],
                ]],
            ]],
        ]
        let scriptCatalog = SceneUserPropertyCatalog(definitions: [
            SceneUserPropertyDefinition(
                key: "scriptSpeed", title: "Speed", kind: .slider,
                runtimeType: "slider", order: 0, index: nil,
                minimumValue: 0, maximumValue: 1, stepValue: 0.01,
                allowsFractionalValues: true, fractionalPrecision: 2,
                displayCondition: nil, defaultValue: .number(0.2), options: []
            ),
        ])
        let scriptReport = SceneUserPropertyBindingParser().parse(root: scriptRoot)
        let scriptCompilation = ScenePropertyBindingCompiler().compile(
            report: scriptReport,
            catalog: scriptCatalog
        )
        let scriptTargets = Set(scriptCompilation.program.instructions.compactMap {
            instruction -> SceneDynamicTarget? in
            guard case .scriptInstanceProperty = instruction.target else { return nil }
            return instruction.target
        })
        let directScriptTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "direct"
        )
        let scriptProviderClassified = scriptTargets.count == 1
            && scriptReport.diagnostics.isEmpty
            && !scriptCompilation.program.rebuildRequiredPropertyKeys
                .contains("scriptSpeed")
        var scriptLiveState = ScenePropertyLiveUpdateState(
            program: scriptCompilation.program,
            effectiveValues: ["scriptSpeed": .number(0.2)],
            activeConsumerTargets: scriptTargets.union([directScriptTarget])
        )
        let scriptProviderAccepted = scriptLiveState.apply(
            .number(0.35),
            forPropertyKey: "scriptSpeed"
        )
        let scriptProviderPublishedBoth = scalar(scriptLiveState, directScriptTarget) == 0.35
            && scriptTargets.allSatisfy { scalar(scriptLiveState, $0) == 0.35 }
        var missingScriptConsumerState = ScenePropertyLiveUpdateState(
            program: scriptCompilation.program,
            effectiveValues: ["scriptSpeed": .number(0.2)],
            activeConsumerTargets: [directScriptTarget]
        )
        let beforeMissingScriptConsumer = missingScriptConsumerState
        let missingScriptConsumerRejected = !missingScriptConsumerState.apply(
            .number(0.35),
            forPropertyKey: "scriptSpeed"
        )
        let missingScriptConsumerWasAtomic = unchanged(
            missingScriptConsumerState,
            from: beforeMissingScriptConsumer
        )
        var disabledScriptConsumerState = ScenePropertyLiveUpdateState(
            program: scriptCompilation.program,
            effectiveValues: ["scriptSpeed": .number(0.2)],
            activeConsumerTargets: scriptTargets.union([directScriptTarget])
        )
        let beforeDisabledScriptConsumer = disabledScriptConsumerState
        let disabledScriptConsumerRejected = !disabledScriptConsumerState.apply(
            .number(0.35),
            forPropertyKey: "scriptSpeed",
            unavailableConsumerTargets: scriptTargets
        )
        let disabledScriptConsumerWasAtomic = unchanged(
            disabledScriptConsumerState,
            from: beforeDisabledScriptConsumer
        )
        let falsePositiveRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "metadata": [
                    "scriptproperties": [
                        "nestedSpeed": [
                            "user": "scriptSpeed",
                            "value": 50.0,
                        ],
                    ],
                ],
            ]],
        ]
        let falsePositiveReport = SceneUserPropertyBindingParser().parse(
            root: falsePositiveRoot
        )
        let falsePositiveCompilation = ScenePropertyBindingCompiler().compile(
            report: falsePositiveReport,
            catalog: scriptCatalog
        )
        let ordinaryUnknownStillRebuilds = falsePositiveCompilation.program
            .rebuildRequiredPropertyKeys.contains("scriptSpeed")
        let unsupportedScriptPathRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "metadata": [
                    "custom": [
                        "script": "export function update(value) { return value; }",
                        "scriptproperties": [
                            "nestedSpeed": [
                                "user": "scriptSpeed",
                                "value": 50.0,
                            ],
                        ],
                        "value": 0.2,
                    ],
                ],
            ]],
        ]
        let unsupportedScriptPathCompilation = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(
                root: unsupportedScriptPathRoot
            ),
            catalog: scriptCatalog
        )
        let unsupportedScriptPathRebuilds = unsupportedScriptPathCompilation.program
            .rebuildRequiredPropertyKeys.contains("scriptSpeed")
        let malformedProviderRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "effects": [[
                    "passes": [[
                        "constantshadervalues": [
                            "scripted": [
                                "script": "export function update(value) { return value; }",
                                "scriptproperties": [
                                    "nestedSpeed": [
                                        "extra": true,
                                        "user": "scriptSpeed",
                                        "value": 50.0,
                                    ],
                                ],
                                "value": -0.2,
                            ],
                        ],
                    ]],
                ]],
            ]],
        ]
        let malformedProviderCompilation = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: malformedProviderRoot),
            catalog: scriptCatalog
        )
        let malformedProviderRebuilds = malformedProviderCompilation.program
            .rebuildRequiredPropertyKeys.contains("scriptSpeed")
        let nullOuterUserRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "effects": [[
                    "passes": [[
                        "constantshadervalues": [
                            "scripted": [
                                "script": "export function update(value) { return value; }",
                                "scriptproperties": [
                                    "nestedSpeed": [
                                        "user": "scriptSpeed",
                                        "value": 50.0,
                                    ],
                                ],
                                "user": NSNull(),
                                "value": -0.2,
                            ],
                        ],
                    ]],
                ]],
            ]],
        ]
        let nullOuterUserCompilation = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(root: nullOuterUserRoot),
            catalog: scriptCatalog
        )
        let nullOuterUserProviderClassified = nullOuterUserCompilation.program.instructions
            .contains { instruction in
                guard instruction.propertyKey == "scriptSpeed" else { return false }
                if case .scriptInstanceProperty = instruction.target { return true }
                return false
            }
            && !nullOuterUserCompilation.program.rebuildRequiredPropertyKeys
                .contains("scriptSpeed")
        let unsupportedColorProviderRoot: [String: Any] = [
            "objects": [[
                "id": 10,
                "color": [
                    "script": "export function update(value) { return value; }",
                    "scriptproperties": [
                        "nestedSpeed": [
                            "user": "scriptSpeed",
                            "value": 50.0,
                        ],
                    ],
                    "value": "1 1 1",
                ],
            ]],
        ]
        let unsupportedColorProviderCompilation = ScenePropertyBindingCompiler().compile(
            report: SceneUserPropertyBindingParser().parse(
                root: unsupportedColorProviderRoot
            ),
            catalog: scriptCatalog
        )
        let unsupportedColorProviderRebuilds = unsupportedColorProviderCompilation.program
            .rebuildRequiredPropertyKeys.contains("scriptSpeed")

        let scriptEventProgram = program(bindings: [])
        var scriptEventState = ScenePropertyLiveUpdateState(
            program: scriptEventProgram,
            effectiveValues: ["fontChoice": .string("13")],
            activeConsumerTargets: [alphaThree],
            scriptUserPropertyConsumerTargetsByKey: [
                "fontChoice": [alphaThree],
            ]
        )
        let scriptEventAccepted = scriptEventState.apply(
            .string("21"),
            forPropertyKey: "fontChoice"
        )
        let scriptEventPublished =
            scriptEventState.effectiveValues["fontChoice"] == .string("21")
                && scriptEventState.userValues.isEmpty
        let beforeScriptEventTypeFailure = scriptEventState
        let scriptEventTypeRejected = !scriptEventState.apply(
            .number(21),
            forPropertyKey: "fontChoice"
        )
        let scriptEventTypeFailureWasAtomic = unchanged(
            scriptEventState,
            from: beforeScriptEventTypeFailure
        )
        let beforeUnavailableScriptEvent = scriptEventState
        let unavailableScriptEventRejected = !scriptEventState.apply(
            .string("1"),
            forPropertyKey: "fontChoice",
            unavailableConsumerTargets: [alphaThree]
        )
        let unavailableScriptEventWasAtomic = unchanged(
            scriptEventState,
            from: beforeUnavailableScriptEvent
        )

        let payload: [String: Bool] = [
            "initialEvaluatedAllTargets": initialEvaluatedAllTargets,
            "singleAccepted": singleAccepted,
            "singleUpdatedAllTargets": singleUpdatedAllTargets,
            "missingRejected": missingRejected,
            "missingWasAtomic": missingWasAtomic,
            "badTypeRejected": badTypeRejected,
            "badTypeWasAtomic": badTypeWasAtomic,
            "nonFiniteRejected": nonFiniteRejected,
            "nonFiniteWasAtomic": nonFiniteWasAtomic,
            "colorAccepted": colorAccepted,
            "colorUpdated": colorUpdated,
            "invalidColorRejected": invalidColorRejected,
            "invalidColorWasAtomic": invalidColorWasAtomic,
            "nonFiniteColorRejected": nonFiniteColorRejected,
            "nonFiniteColorWasAtomic": nonFiniteColorWasAtomic,
            "bulkAccepted": bulkAccepted,
            "bulkUpdatedAtomically": bulkUpdatedAtomically,
            "badBulkRejected": badBulkRejected,
            "badBulkWasAtomic": badBulkWasAtomic,
            "resetAccepted": resetAccepted,
            "resetAppliedOnlyChangedKeys": resetAppliedOnlyChangedKeys,
            "missingResetDefaultRejected": missingResetDefaultRejected,
            "missingResetDefaultWasAtomic": missingResetDefaultWasAtomic,
            "noOpAccepted": noOpAccepted,
            "noOpIgnoredReplacements": noOpIgnoredReplacements,
            "rebuildRejected": rebuildRejected,
            "rebuildWasAtomic": rebuildWasAtomic,
            "mixedRejected": mixedRejected,
            "mixedWasAtomic": mixedWasAtomic,
            "partialConsumerRejected": partialConsumerRejected,
            "partialConsumerWasAtomic": partialConsumerWasAtomic,
            "genericVisibilityRejected": genericVisibilityRejected,
            "genericVisibilityWasAtomic": genericVisibilityWasAtomic,
            "xrayVisibilityAccepted": xrayVisibilityAccepted,
            "xrayVisibilityUpdated": xrayVisibilityUpdated,
            "mixedVisibilityRejected": mixedVisibilityRejected,
            "mixedVisibilityWasAtomic": mixedVisibilityWasAtomic,
            "conditionalLayoutInitial": conditionalLayoutInitial,
            "conditionalLayoutAccepted": conditionalLayoutAccepted,
            "conditionalLayoutSwapped": conditionalLayoutSwapped,
            "conditionalLayoutBaseAccepted": conditionalLayoutBaseAccepted,
            "conditionalLayoutBaseCleared": conditionalLayoutBaseCleared,
            "conditionalLayoutUnmatchedRejected":
                conditionalLayoutUnmatchedRejected,
            "conditionalLayoutUnmatchedWasAtomic":
                conditionalLayoutUnmatchedWasAtomic,
            "conditionalLayoutPartialRejected":
                conditionalLayoutPartialRejected,
            "conditionalLayoutPartialWasAtomic":
                conditionalLayoutPartialWasAtomic,
            "scriptProviderClassified": scriptProviderClassified,
            "scriptProviderAccepted": scriptProviderAccepted,
            "scriptProviderPublishedBoth": scriptProviderPublishedBoth,
            "missingScriptConsumerRejected": missingScriptConsumerRejected,
            "missingScriptConsumerWasAtomic": missingScriptConsumerWasAtomic,
            "disabledScriptConsumerRejected": disabledScriptConsumerRejected,
            "disabledScriptConsumerWasAtomic": disabledScriptConsumerWasAtomic,
            "ordinaryUnknownStillRebuilds": ordinaryUnknownStillRebuilds,
            "unsupportedScriptPathRebuilds": unsupportedScriptPathRebuilds,
            "malformedProviderRebuilds": malformedProviderRebuilds,
            "nullOuterUserProviderClassified": nullOuterUserProviderClassified,
            "colorProviderClassified": !unsupportedColorProviderRebuilds,
            "scriptEventAccepted": scriptEventAccepted,
            "scriptEventPublished": scriptEventPublished,
            "scriptEventTypeRejected": scriptEventTypeRejected,
            "scriptEventTypeFailureWasAtomic": scriptEventTypeFailureWasAtomic,
            "unavailableScriptEventRejected": unavailableScriptEventRejected,
            "unavailableScriptEventWasAtomic": unavailableScriptEventWasAtomic,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func program(
        bindings: [(String, SceneDynamicTarget, SceneDynamicValueType, SceneDynamicValue)],
        rebuildRequiredKeys: [String] = []
    ) -> ScenePropertyBindingProgram {
        ScenePropertyBindingProgram(
            definitions: bindings.map {
                .init(target: $0.1, valueType: $0.2, authoredValue: $0.3)
            },
            instructions: bindings.map {
                .init(
                    propertyKey: $0.0,
                    path: .init(components: [.key($0.0)]),
                    target: $0.1,
                    valueType: $0.2
                )
            },
            rebuildRequiredPropertyKeys: rebuildRequiredKeys
        )
    }

    static func scalar(
        _ state: ScenePropertyLiveUpdateState,
        _ target: SceneDynamicTarget
    ) -> Double? {
        guard case let .scalar(value) = state.userValues[target] else { return nil }
        return value
    }

    static func vector(
        _ state: ScenePropertyLiveUpdateState,
        _ target: SceneDynamicTarget
    ) -> [Double]? {
        guard case let .vector3(x, y, z) = state.userValues[target] else { return nil }
        return [x, y, z]
    }

    static func bool(
        _ state: ScenePropertyLiveUpdateState,
        _ target: SceneDynamicTarget
    ) -> Bool? {
        guard case let .bool(value) = state.userValues[target] else { return nil }
        return value
    }

    static func unchanged(
        _ state: ScenePropertyLiveUpdateState,
        from before: ScenePropertyLiveUpdateState
    ) -> Bool {
        state.effectiveValues == before.effectiveValues
            && state.userValues == before.userValues
    }
}
'''


class ScenePropertyLiveUpdateStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-live-state-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-property-live-update-state"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_initialization_and_single_key_fan_out(self) -> None:
        self.assertTrue(self.result["initialEvaluatedAllTargets"])
        self.assertTrue(self.result["singleAccepted"])
        self.assertTrue(self.result["singleUpdatedAllTargets"])

    def test_missing_instruction_and_invalid_values_fail_atomically(self) -> None:
        self.assertTrue(self.result["missingRejected"])
        self.assertTrue(self.result["missingWasAtomic"])
        self.assertTrue(self.result["badTypeRejected"])
        self.assertTrue(self.result["badTypeWasAtomic"])
        self.assertTrue(self.result["nonFiniteRejected"])
        self.assertTrue(self.result["nonFiniteWasAtomic"])

    def test_active_color_target_accepts_only_finite_vector3_strings(self) -> None:
        self.assertTrue(self.result["colorAccepted"])
        self.assertTrue(self.result["colorUpdated"])
        self.assertTrue(self.result["invalidColorRejected"])
        self.assertTrue(self.result["invalidColorWasAtomic"])
        self.assertTrue(self.result["nonFiniteColorRejected"])
        self.assertTrue(self.result["nonFiniteColorWasAtomic"])

    def test_bulk_updates_and_reset_only_change_requested_keys(self) -> None:
        self.assertTrue(self.result["bulkAccepted"])
        self.assertTrue(self.result["bulkUpdatedAtomically"])
        self.assertTrue(self.result["resetAccepted"])
        self.assertTrue(self.result["resetAppliedOnlyChangedKeys"])
        self.assertTrue(self.result["noOpAccepted"])
        self.assertTrue(self.result["noOpIgnoredReplacements"])

    def test_bulk_failure_and_missing_reset_default_are_atomic(self) -> None:
        self.assertTrue(self.result["badBulkRejected"])
        self.assertTrue(self.result["badBulkWasAtomic"])
        self.assertTrue(self.result["missingResetDefaultRejected"])
        self.assertTrue(self.result["missingResetDefaultWasAtomic"])

    def test_rebuild_required_keys_are_rejected_with_all_consumers_active(self) -> None:
        self.assertTrue(self.result["rebuildRejected"])
        self.assertTrue(self.result["rebuildWasAtomic"])
        self.assertTrue(self.result["mixedRejected"])
        self.assertTrue(self.result["mixedWasAtomic"])

    def test_shared_key_requires_every_consumer_to_be_active(self) -> None:
        self.assertTrue(self.result["partialConsumerRejected"])
        self.assertTrue(self.result["partialConsumerWasAtomic"])

    def test_generic_effect_visibility_without_consumer_fails_atomically(self) -> None:
        self.assertTrue(self.result["genericVisibilityRejected"])
        self.assertTrue(self.result["genericVisibilityWasAtomic"])

    def test_exact_xray_visibility_is_live_with_an_active_consumer(self) -> None:
        self.assertTrue(self.result["xrayVisibilityAccepted"])
        self.assertTrue(self.result["xrayVisibilityUpdated"])

    def test_mixed_visibility_key_rejects_if_any_consumer_is_inactive(self) -> None:
        self.assertTrue(self.result["mixedVisibilityRejected"])
        self.assertTrue(self.result["mixedVisibilityWasAtomic"])

    def test_conditional_layout_cohort_and_base_selection_are_atomic(self) -> None:
        self.assertTrue(self.result["conditionalLayoutInitial"])
        self.assertTrue(self.result["conditionalLayoutAccepted"])
        self.assertTrue(self.result["conditionalLayoutSwapped"])
        self.assertTrue(self.result["conditionalLayoutBaseAccepted"])
        self.assertTrue(self.result["conditionalLayoutBaseCleared"])
        self.assertTrue(self.result["conditionalLayoutUnmatchedRejected"])
        self.assertTrue(self.result["conditionalLayoutUnmatchedWasAtomic"])
        self.assertTrue(self.result["conditionalLayoutPartialRejected"])
        self.assertTrue(self.result["conditionalLayoutPartialWasAtomic"])

    def test_script_property_provider_is_typed_and_requires_its_vm_consumer(self) -> None:
        self.assertTrue(self.result["scriptProviderClassified"])
        self.assertTrue(self.result["scriptProviderAccepted"])
        self.assertTrue(self.result["scriptProviderPublishedBoth"])
        self.assertTrue(self.result["missingScriptConsumerRejected"])
        self.assertTrue(self.result["missingScriptConsumerWasAtomic"])
        self.assertTrue(self.result["disabledScriptConsumerRejected"])
        self.assertTrue(self.result["disabledScriptConsumerWasAtomic"])

    def test_scriptproperties_name_without_a_script_wrapper_still_rebuilds(self) -> None:
        self.assertTrue(self.result["ordinaryUnknownStillRebuilds"])
        self.assertTrue(self.result["unsupportedScriptPathRebuilds"])
        self.assertTrue(self.result["malformedProviderRebuilds"])
        self.assertTrue(self.result["nullOuterUserProviderClassified"])
        self.assertTrue(self.result["colorProviderClassified"])

    def test_effect_visibility_mapping_is_generic_and_live_rejection_requests_relaunch(
        self,
    ) -> None:
        mapping = TARGET_MAPPING_SOURCE.read_text(encoding="utf-8")
        visibility_mapping = mapping[
            mapping.index("case let .effectVisibility") :
            mapping.index("default:", mapping.index("case let .effectVisibility"))
        ]
        self.assertIn("where layerID >= 0 && effectIndex >= 0", visibility_mapping)
        self.assertNotIn("effects/xray/effect.json", visibility_mapping)

        service = SERVICE_SOURCE.read_text(encoding="utf-8")
        update = service[
            service.index("func updateScenePropertyValue(") :
            service.index("func resetScenePropertyValues(")
        ]
        self.assertIn(
            "if !SceneDesktopWallpaperHost.shared.applyUserPropertyValue(",
            update,
        )
        self.assertLess(
            update.index("applyUserPropertyValue("),
            update.index("scheduleActiveScenePropertyRender"),
        )


if __name__ == "__main__":
    unittest.main()
