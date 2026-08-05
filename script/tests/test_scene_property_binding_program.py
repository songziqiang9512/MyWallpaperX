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
PROGRAM_SOURCE = SOURCE_ROOT / "Properties/ScenePropertyBindingProgram.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/ScenePuppetAnimationPropertyTarget.swift",
    PROGRAM_SOURCE,
    SOURCE_ROOT / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift",
    SOURCE_ROOT / "Properties/ScenePropertyBindingProgramValidator.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let alpha = binding("opacity", .number(0.25), 20, .layerAlpha(layerID: 20))
        let color = binding("tint", .string("0.1 0.2 0.3"), 10, .layerColor(layerID: 10))
        let catalog = SceneUserPropertyCatalog(definitions: [
            property("opacity", .slider, .number(0.5)),
            property("tint", .color, .string("1 1 1")),
        ])
        let compiler = ScenePropertyBindingCompiler()
        let report = SceneUserPropertyBindingReport(bindings: [alpha, color], diagnostics: [])
        let compilation = compiler.compile(report: report, catalog: catalog)
        let reversed = compiler.compile(
            report: .init(bindings: [color, alpha], diagnostics: []),
            catalog: .init(definitions: catalog.definitions.reversed())
        )
        let decoded = try JSONDecoder().decode(
            ScenePropertyBindingCompilation.self,
            from: JSONEncoder().encode(compilation)
        )

        let authored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: compilation.program.definitions
        ).snapshot
        let userEvaluation = compilation.program.evaluate(effectiveValues: [
            "opacity": .number(0.75),
            "tint": .string("0.8\t0.7\n0.6"),
        ])
        let user = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: compilation.program.definitions,
            userValues: userEvaluation.userValues
        ).snapshot

        let alphaTarget = SceneDynamicTarget.layer(layerID: 20, field: .alpha)
        let colorTarget = SceneDynamicTarget.layer(layerID: 10, field: .color)
        let badEvaluation = compilation.program.evaluate(effectiveValues: [
            "opacity": .string("0.9"),
            "tint": .string("1 2"),
        ])
        let nonFiniteEvaluation = compilation.program.evaluate(effectiveValues: [
            "opacity": .number(.nan),
            "tint": .string("1 NaN 3"),
        ])
        let badSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3,
            generation: 3,
            definitions: compilation.program.definitions,
            userValues: badEvaluation.userValues
        ).snapshot

        let invalidAuthored = compiler.compile(
            report: .init(bindings: [
                binding("wrongAlpha", .string("0.5"), 30, .layerAlpha(layerID: 30)),
                binding("shortColor", .string("1 2"), 31, .layerColor(layerID: 31)),
                binding("nanColor", .string("1 NaN 3"), 32, .layerColor(layerID: 32)),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("wrongAlpha", .slider, .number(1)),
                property("shortColor", .color, .string("1 1 1")),
                property("nanColor", .color, .string("1 1 1")),
            ])
        )
        let invalidCatalog = compiler.compile(
            report: .init(bindings: [
                binding("alphaBool", .number(0.5), 33, .layerAlpha(layerID: 33)),
                binding("colorText", .string("1 1 1"), 34, .layerColor(layerID: 34)),
                binding("alphaString", .number(0.5), 35, .layerAlpha(layerID: 35)),
                binding("shortDefault", .string("1 1 1"), 36, .layerColor(layerID: 36)),
                binding("nanDefault", .number(0.5), 37, .layerAlpha(layerID: 37)),
                binding("missingDefault", .number(0.5), 38, .layerAlpha(layerID: 38)),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("alphaBool", .bool, .number(1)),
                property("colorText", .text, .string("1 1 1")),
                property("alphaString", .slider, .string("1")),
                property("shortDefault", .color, .string("1 2")),
                property("nanDefault", .slider, .number(.nan)),
                property("missingDefault", .slider, nil),
            ])
        )
        let conditional = compiler.compile(
            report: .init(bindings: [binding(
                "opacity",
                .number(0.2),
                40,
                .layerAlpha(layerID: 40),
                condition: .bool(true)
            )], diagnostics: []),
            catalog: catalog
        )
        let duplicate = compiler.compile(
            report: .init(bindings: [
                binding("opacity", .number(0.2), 50, .layerAlpha(layerID: 50), pathSuffix: "a"),
                binding("opacity2", .number(0.4), 50, .layerAlpha(layerID: 50), pathSuffix: "b"),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("opacity", .slider, .number(1)),
                property("opacity2", .slider, .number(1)),
            ])
        )
        let rejected = compiler.compile(
            report: .init(bindings: [
                binding("missing", .number(0.5), 60, .layerAlpha(layerID: 60)),
                binding("opacity", .number(1), 61, .layerVisibility(layerID: 61)),
            ], diagnostics: [
                .init(
                    kind: .malformedUserReference,
                    path: path(62),
                    propertyKey: nil,
                    message: "bad reference"
                )
            ]),
            catalog: catalog
        )
        let mixed = SceneUserPropertyBindingReport(
            bindings: [alpha, color, conditionalInput(), missingInput(), unsupportedInput()],
            diagnostics: []
        )
        let mixedReverse = SceneUserPropertyBindingReport(
            bindings: mixed.bindings.reversed(),
            diagnostics: []
        )
        let deterministicForward = compiler.compile(report: mixed, catalog: catalog)
        let deterministicReverse = compiler.compile(report: mixedReverse, catalog: catalog)
        let mixedKey = compiler.compile(
            report: .init(bindings: [
                binding("opacity", .number(0.25), 80, .layerAlpha(layerID: 80)),
                binding("opacity", .number(1), 81, .layerVisibility(layerID: 81)),
            ], diagnostics: []),
            catalog: catalog
        )
        let mixedKeyDecoded = try JSONDecoder().decode(
            ScenePropertyBindingProgram.self,
            from: JSONEncoder().encode(mixedKey.program)
        )
        let localContrastTarget = SceneDynamicTarget.effectConstant(
            layerID: 90,
            effectIndex: 1,
            passIndex: 3,
            name: "strength"
        )
        let localContrast = compiler.compile(
            report: .init(bindings: [binding(
                "contrastStrength",
                .number(0.32),
                90,
                localContrastBindingTarget(layerID: 90, effectIndex: 1)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("contrastStrength", .slider, .number(0.5)),
            ])
        )
        let localContrastDecoded = try JSONDecoder().decode(
            ScenePropertyBindingProgram.self,
            from: JSONEncoder().encode(localContrast.program)
        )
        let localContrastAuthored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4,
            generation: 4,
            definitions: localContrast.program.definitions
        ).snapshot
        let localContrastEvaluation = localContrast.program.evaluate(effectiveValues: [
            "contrastStrength": .number(0.75),
        ])
        let localContrastUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 5,
            generation: 5,
            definitions: localContrast.program.definitions,
            userValues: localContrastEvaluation.userValues
        ).snapshot
        let audioBarsColorTarget = SceneDynamicTarget.effectConstant(
            layerID: 64,
            effectIndex: 0,
            passIndex: 0,
            name: "Bar Color"
        )
        let audioBarsColor = compiler.compile(
            report: .init(bindings: [binding(
                "basecolor",
                .string("0.99608 0.09804 1"),
                64,
                audioBarsColorBindingTarget(layerID: 64, effectIndex: 0)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("basecolor", .color, .string("0.99608 0.09804 1")),
            ])
        )
        let audioBarsColorAuthored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 6,
            generation: 6,
            definitions: audioBarsColor.program.definitions
        ).snapshot
        let audioBarsColorEvaluation = audioBarsColor.program.evaluate(effectiveValues: [
            "basecolor": .string("0.25 0.5 0.75"),
        ])
        let audioBarsColorUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 7,
            generation: 7,
            definitions: audioBarsColor.program.definitions,
            userValues: audioBarsColorEvaluation.userValues
        ).snapshot
        let relocatedAudioBarsTargets = [
            SceneDynamicTarget.effectConstant(
                layerID: 151,
                effectIndex: 0,
                passIndex: 0,
                name: "Bar Color"
            ),
            SceneDynamicTarget.effectConstant(
                layerID: 151,
                effectIndex: 0,
                passIndex: 0,
                name: "ui_editor_properties_opacity"
            ),
        ]
        let relocatedAudioBarsPath =
            "effects/workshop/3299008209/workshop/2084198056/"
            + "Simple_Audio_Bars/effect.json"
        let relocatedAudioBars = compiler.compile(
            report: .init(bindings: [
                binding("barcolor", .string("1 1 1"), 151, .shaderValue(
                    layerID: 151,
                    effectIndex: 0,
                    passIndex: 0,
                    name: "Bar Color",
                    effectPath: relocatedAudioBarsPath
                )),
                binding("musicbar", .number(1), 151, .shaderValue(
                    layerID: 151,
                    effectIndex: 0,
                    passIndex: 0,
                    name: "ui_editor_properties_opacity",
                    effectPath: relocatedAudioBarsPath
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("barcolor", .color, .string("1 1 1")),
                property("musicbar", .slider, .number(1)),
            ])
        )
        let relocatedAudioBarsEvaluation = relocatedAudioBars.program.evaluate(
            effectiveValues: [
                "barcolor": .string("0.2 0.4 0.6"),
                "musicbar": .number(0.35),
            ]
        )
        let relocatedAudioBarsUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 8,
            generation: 8,
            definitions: relocatedAudioBars.program.definitions,
            userValues: relocatedAudioBarsEvaluation.userValues
        ).snapshot
        let unsupportedAudioBarsColorTargets = compiler.compile(
            report: .init(bindings: [
                binding("audioWrongPath", .string("1 0 1"), 110, .shaderValue(
                    layerID: 110, effectIndex: 0, passIndex: 0, name: "Bar Color",
                    effectPath: "effects/workshop/2084198056/other/effect.json"
                )),
                binding("audioWrongPass", .string("1 0 1"), 111, .shaderValue(
                    layerID: 111, effectIndex: 0, passIndex: 1, name: "Bar Color",
                    effectPath: "effects/workshop/2084198056/simple_audio_bars/effect.json"
                )),
                binding("audioWrongName", .string("1 0 1"), 112, .shaderValue(
                    layerID: 112, effectIndex: 0, passIndex: 0, name: "Color",
                    effectPath: "effects/workshop/2084198056/simple_audio_bars/effect.json"
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("audioWrongPath", .color, .string("1 0 1")),
                property("audioWrongPass", .color, .string("1 0 1")),
                property("audioWrongName", .color, .string("1 0 1")),
            ])
        )
        let opacityTargets = [365, 372, 647, 664].map {
            SceneDynamicTarget.effectConstant(
                layerID: $0,
                effectIndex: 0,
                passIndex: 0,
                name: $0 == 365 ? "Alpha" : "alpha"
            )
        }
        let opacity = compiler.compile(
            report: .init(bindings: [365, 372, 647, 664].map {
                binding(
                    "newproperty50",
                    .number(1),
                    $0,
                    opacityBindingTarget(
                        layerID: $0,
                        effectIndex: 0,
                        usesNormalizedVariant: $0 == 365
                    )
                )
            }, diagnostics: []),
            catalog: .init(definitions: [
                property("newproperty50", .slider, .number(1)),
            ])
        )
        let opacityDecoded = try JSONDecoder().decode(
            ScenePropertyBindingProgram.self,
            from: JSONEncoder().encode(opacity.program)
        )
        let opacityAuthored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 6,
            generation: 6,
            definitions: opacity.program.definitions
        ).snapshot
        let opacityEvaluation = opacity.program.evaluate(effectiveValues: [
            "newproperty50": .number(0.2),
        ])
        let opacityUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 7,
            generation: 7,
            definitions: opacity.program.definitions,
            userValues: opacityEvaluation.userValues
        ).snapshot
        let xRayVisibilityTarget = SceneDynamicTarget.effectVisibility(
            layerID: 23,
            effectIndex: 5
        )
        let xRaySizeTarget = SceneDynamicTarget.effectConstant(
            layerID: 69,
            effectIndex: 0,
            passIndex: 0,
            name: "Size"
        )
        let xRayBindings = compiler.compile(
            report: .init(bindings: [
                binding("newproperty2", .bool(true), 23, .effectVisibility(
                    layerID: 23,
                    effectIndex: 5,
                    effectPath: "Effects\\XRay\\Effect.json"
                )),
                binding("x", .number(0.2), 69, .shaderValue(
                    layerID: 69,
                    effectIndex: 0,
                    passIndex: 0,
                    name: "Size",
                    effectPath: "effects/xray/effect.json"
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("newproperty2", .bool, .bool(true)),
                property("x", .slider, .number(0.2)),
            ])
        )
        let xRayDecoded = try JSONDecoder().decode(
            ScenePropertyBindingProgram.self,
            from: JSONEncoder().encode(xRayBindings.program)
        )
        let xRayAuthored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 8,
            generation: 8,
            definitions: xRayBindings.program.definitions
        ).snapshot
        let xRayEvaluation = xRayBindings.program.evaluate(effectiveValues: [
            "newproperty2": .bool(false),
            "x": .number(0.4),
        ])
        let xRayUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 9,
            generation: 9,
            definitions: xRayBindings.program.definitions,
            userValues: xRayEvaluation.userValues
        ).snapshot
        let unsupportedOpacityTargets = compiler.compile(
            report: .init(bindings: [
                binding("opacityWrongPath", .number(1), 101, .shaderValue(
                    layerID: 101, effectIndex: 0, passIndex: 0, name: "alpha",
                    effectPath: "effects/workshop/opacity/effect.json"
                )),
                binding("opacityWrongPass", .number(1), 102, .shaderValue(
                    layerID: 102, effectIndex: 0, passIndex: 1, name: "alpha",
                    effectPath: "effects/opacity/effect.json"
                )),
                binding("opacityWrongName", .number(1), 103, .shaderValue(
                    layerID: 103, effectIndex: 0, passIndex: 0, name: "amount",
                    effectPath: "effects/opacity/effect.json"
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("opacityWrongPath", .slider, .number(1)),
                property("opacityWrongPass", .slider, .number(1)),
                property("opacityWrongName", .slider, .number(1)),
            ])
        )
        let unsupportedShaderTargets = compiler.compile(
            report: .init(bindings: [
                binding("wrongPath", .number(0.2), 91, .shaderValue(
                    layerID: 91,
                    effectIndex: 0,
                    passIndex: 3,
                    name: "strength",
                    effectPath: "effects/other/effect.json"
                )),
                binding("wrongPass", .number(0.2), 92, .shaderValue(
                    layerID: 92,
                    effectIndex: 0,
                    passIndex: 2,
                    name: "strength",
                    effectPath: "effects/localcontrast/effect.json"
                )),
                binding("wrongName", .number(0.2), 93, .shaderValue(
                    layerID: 93,
                    effectIndex: 0,
                    passIndex: 3,
                    name: "amount",
                    effectPath: "effects/localcontrast/effect.json"
                )),
                binding("missingPath", .number(0.2), 94, .shaderValue(
                    layerID: 94,
                    effectIndex: 0,
                    passIndex: 3,
                    name: "strength",
                    effectPath: nil
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("wrongPath", .slider, .number(0.5)),
                property("wrongPass", .slider, .number(0.5)),
                property("wrongName", .slider, .number(0.5)),
                property("missingPath", .slider, .number(0.5)),
            ])
        )
        let conditionalLocalContrast = compiler.compile(
            report: .init(bindings: [binding(
                "conditionalStrength",
                .number(0.2),
                95,
                localContrastBindingTarget(layerID: 95, effectIndex: 0),
                condition: .bool(true)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("conditionalStrength", .slider, .number(0.5)),
            ])
        )
        let invalidLocalContrast = compiler.compile(
            report: .init(bindings: [binding(
                "invalidStrength",
                .string("0.2"),
                96,
                localContrastBindingTarget(layerID: 96, effectIndex: 0)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("invalidStrength", .slider, .number(0.5)),
            ])
        )
        let mixedLocalContrast = compiler.compile(
            report: .init(bindings: [
                binding(
                    "mixedStrength",
                    .number(0.2),
                    97,
                    localContrastBindingTarget(layerID: 97, effectIndex: 0)
                ),
                binding("mixedStrength", .number(0.4), 98, .shaderValue(
                    layerID: 98,
                    effectIndex: 0,
                    passIndex: 3,
                    name: "strength",
                    effectPath: "effects/other/effect.json"
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("mixedStrength", .slider, .number(0.5)),
            ])
        )
        let particleTargets: [SceneDynamicTarget] = [
            .particle(layerID: 120, field: .alpha),
            .particle(layerID: 120, field: .normalizedColor),
        ]
        let particle = compiler.compile(
            report: .init(bindings: [
                binding("particleAlpha", .number(0.8), 120, .particle(
                    layerID: 120, field: .alpha
                )),
                binding("particleColor", .string("1 1 1"), 120, .particle(
                    layerID: 120, field: .normalizedColor
                )),
            ], diagnostics: []),
            catalog: .init(definitions: [
                property("particleAlpha", .slider, .number(1)),
                property("particleColor", .color, .string("1 1 1")),
            ])
        )
        let particleEvaluation = particle.program.evaluate(effectiveValues: [
            "particleAlpha": .number(0.35),
            "particleColor": .string("0.2 0.4 0.6"),
        ])
        let particleUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 10,
            generation: 10,
            definitions: particle.program.definitions,
            userValues: particleEvaluation.userValues
        ).snapshot
        let directParticleColor = compiler.compile(
            report: .init(bindings: [binding(
                "particleColor", .string("255 255 255"), 121,
                .particle(layerID: 121, field: .color)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("particleColor", .color, .string("1 1 1")),
            ])
        )
        let puppetVisibilityTarget = ScenePuppetAnimationPropertyTarget.visibility(
            layerID: 21,
            animationLayerID: 756
        )
        let puppetVisibility = compiler.compile(
            report: .init(bindings: [binding(
                "blinking",
                .bool(true),
                21,
                .puppetAnimationVisibility(layerID: 21, animationLayerID: 756)
            )], diagnostics: []),
            catalog: .init(definitions: [
                property("blinking", .bool, .bool(true)),
            ])
        )
        let puppetVisibilityAuthored = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 11,
            generation: 11,
            definitions: puppetVisibility.program.definitions
        ).snapshot
        let puppetVisibilityEvaluation = puppetVisibility.program.evaluate(
            effectiveValues: ["blinking": .bool(false)]
        )
        let puppetVisibilityUser = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 12,
            generation: 12,
            definitions: puppetVisibility.program.definitions,
            userValues: puppetVisibilityEvaluation.userValues
        ).snapshot

        let alphaDefinition = compilation.program.definitions.first { $0.target == alphaTarget }!
        let alphaInstruction = compilation.program.instructions.first { $0.target == alphaTarget }!
        let duplicateDefinitionProgram = ScenePropertyBindingProgram(
            definitions: [alphaDefinition, alphaDefinition],
            instructions: [alphaInstruction]
        )
        let duplicateInstructionProgram = ScenePropertyBindingProgram(
            definitions: [alphaDefinition],
            instructions: [alphaInstruction, alphaInstruction]
        )
        let missingDefinitionProgram = ScenePropertyBindingProgram(
            definitions: [],
            instructions: [alphaInstruction]
        )
        let mismatchedInstruction = ScenePropertyBindingInstruction(
            propertyKey: alphaInstruction.propertyKey,
            path: alphaInstruction.path,
            target: alphaInstruction.target,
            valueType: .vector3
        )
        let mismatchedProgram = ScenePropertyBindingProgram(
            definitions: [alphaDefinition],
            instructions: [mismatchedInstruction]
        )
        let invalidPrograms = [
            duplicateDefinitionProgram,
            duplicateInstructionProgram,
            missingDefinitionProgram,
            mismatchedProgram,
        ]
        let validator = ScenePropertyBindingProgramValidator()
        let structureCodes = invalidPrograms.map { codes(validator.validate($0).diagnostics) }
        let structureInstructionCounts = invalidPrograms.map { validator.validate($0).instructions.count }
        let structureDecodeRejected = invalidPrograms.map(decodeFails)
        let mismatchedEvaluation = mismatchedProgram.evaluate(effectiveValues: ["opacity": .number(1)])

        let payload: [String: Any] = [
            "roundTrip": decoded == compilation,
            "deterministic": compilation == reversed,
            "mixedDeterministic": deterministicForward == deterministicReverse,
            "definitionCount": compilation.program.definitions.count,
            "instructionKeys": compilation.program.instructions.map(\.propertyKey),
            "authoredAlpha": resolved(authored[alphaTarget]),
            "authoredColor": resolved(authored[colorTarget]),
            "userAlpha": resolved(user[alphaTarget]),
            "userColor": resolved(user[colorTarget]),
            "badAlpha": resolved(badSnapshot[alphaTarget]),
            "badColor": resolved(badSnapshot[colorTarget]),
            "badCodes": codes(badEvaluation.diagnostics),
            "nonFiniteCodes": codes(nonFiniteEvaluation.diagnostics),
            "invalidAuthoredCount": invalidAuthored.program.instructions.count,
            "invalidAuthoredCodes": codes(invalidAuthored.diagnostics),
            "invalidCatalogCount": invalidCatalog.program.instructions.count,
            "invalidCatalogCodes": codes(invalidCatalog.diagnostics),
            "conditionalCount": conditional.program.instructions.count,
            "conditionalCodes": codes(conditional.diagnostics),
            "duplicateCount": duplicate.program.instructions.count,
            "duplicateCodes": codes(duplicate.diagnostics),
            "rejectedCount": rejected.program.instructions.count,
            "rejectedCodes": codes(rejected.diagnostics),
            "mixedKeyCount": mixedKey.program.instructions.count,
            "mixedKeyRebuild": mixedKey.program.rebuildRequiredPropertyKeys,
            "mixedKeyRoundTrip": mixedKeyDecoded == mixedKey.program,
            "localContrastCount": localContrast.program.instructions.count,
            "localContrastTarget": localContrast.program.instructions.first?.target == localContrastTarget,
            "localContrastRoundTrip": localContrastDecoded == localContrast.program,
            "localContrastCodes": codes(localContrast.diagnostics),
            "localContrastRebuild": localContrast.program.rebuildRequiredPropertyKeys,
            "localContrastAuthored": resolved(localContrastAuthored[localContrastTarget]),
            "localContrastUser": resolved(localContrastUser[localContrastTarget]),
            "localContrastRuntimeCodes": codes(localContrastEvaluation.diagnostics),
            "audioBarsColorCount": audioBarsColor.program.instructions.count,
            "audioBarsColorTarget":
                audioBarsColor.program.instructions.first?.target == audioBarsColorTarget,
            "audioBarsColorCodes": codes(audioBarsColor.diagnostics),
            "audioBarsColorRebuild": audioBarsColor.program.rebuildRequiredPropertyKeys,
            "audioBarsColorAuthored": resolved(audioBarsColorAuthored[audioBarsColorTarget]),
            "audioBarsColorUser": resolved(audioBarsColorUser[audioBarsColorTarget]),
            "audioBarsColorRuntimeCodes": codes(audioBarsColorEvaluation.diagnostics),
            "relocatedAudioBarsCount": relocatedAudioBars.program.instructions.count,
            "relocatedAudioBarsTargets":
                relocatedAudioBars.program.instructions.map(\.target)
                    == relocatedAudioBarsTargets,
            "relocatedAudioBarsCodes": codes(relocatedAudioBars.diagnostics),
            "relocatedAudioBarsRebuild":
                relocatedAudioBars.program.rebuildRequiredPropertyKeys,
            "relocatedAudioBarsUser": relocatedAudioBarsTargets.map {
                resolved(relocatedAudioBarsUser[$0])
            },
            "relocatedAudioBarsRuntimeCodes":
                codes(relocatedAudioBarsEvaluation.diagnostics),
            "unsupportedAudioBarsColorCount":
                unsupportedAudioBarsColorTargets.program.instructions.count,
            "unsupportedAudioBarsColorCodes":
                codes(unsupportedAudioBarsColorTargets.diagnostics),
            "unsupportedAudioBarsColorRebuild":
                unsupportedAudioBarsColorTargets.program.rebuildRequiredPropertyKeys,
            "opacityCount": opacity.program.instructions.count,
            "opacityTargets": opacity.program.instructions.map(\.target) == opacityTargets,
            "opacityRoundTrip": opacityDecoded == opacity.program,
            "opacityCodes": codes(opacity.diagnostics),
            "opacityRebuild": opacity.program.rebuildRequiredPropertyKeys,
            "opacityAuthored": opacityTargets.map { resolved(opacityAuthored[$0]) },
            "opacityUser": opacityTargets.map { resolved(opacityUser[$0]) },
            "opacityRuntimeCodes": codes(opacityEvaluation.diagnostics),
            "xRayBindingCount": xRayBindings.program.instructions.count,
            "xRayTargets": Set(xRayBindings.program.instructions.map(\.target))
                == Set([xRayVisibilityTarget, xRaySizeTarget]),
            "xRayRoundTrip": xRayDecoded == xRayBindings.program,
            "xRayCodes": codes(xRayBindings.diagnostics),
            "xRayRebuild": xRayBindings.program.rebuildRequiredPropertyKeys,
            "xRayAuthoredVisibility": resolved(xRayAuthored[xRayVisibilityTarget]),
            "xRayAuthoredSize": resolved(xRayAuthored[xRaySizeTarget]),
            "xRayUserVisibility": resolved(xRayUser[xRayVisibilityTarget]),
            "xRayUserSize": resolved(xRayUser[xRaySizeTarget]),
            "xRayRuntimeCodes": codes(xRayEvaluation.diagnostics),
            "unsupportedOpacityCount": unsupportedOpacityTargets.program.instructions.count,
            "unsupportedOpacityCodes": codes(unsupportedOpacityTargets.diagnostics),
            "unsupportedOpacityRebuild": unsupportedOpacityTargets.program.rebuildRequiredPropertyKeys,
            "unsupportedShaderCount": unsupportedShaderTargets.program.instructions.count,
            "unsupportedShaderCodes": codes(unsupportedShaderTargets.diagnostics),
            "unsupportedShaderRebuild": unsupportedShaderTargets.program.rebuildRequiredPropertyKeys,
            "conditionalLocalContrastCount": conditionalLocalContrast.program.instructions.count,
            "conditionalLocalContrastCodes": codes(conditionalLocalContrast.diagnostics),
            "conditionalLocalContrastRebuild": conditionalLocalContrast.program.rebuildRequiredPropertyKeys,
            "invalidLocalContrastCount": invalidLocalContrast.program.instructions.count,
            "invalidLocalContrastCodes": codes(invalidLocalContrast.diagnostics),
            "invalidLocalContrastRebuild": invalidLocalContrast.program.rebuildRequiredPropertyKeys,
            "mixedLocalContrastCount": mixedLocalContrast.program.instructions.count,
            "mixedLocalContrastCodes": codes(mixedLocalContrast.diagnostics),
            "mixedLocalContrastRebuild": mixedLocalContrast.program.rebuildRequiredPropertyKeys,
            "particleCount": particle.program.instructions.count,
            "particleTargets": particle.program.instructions.map(\.target) == particleTargets,
            "particleCodes": codes(particle.diagnostics),
            "particleUser": particleTargets.map { resolved(particleUser[$0]) },
            "particleRuntimeCodes": codes(particleEvaluation.diagnostics),
            "directParticleColorCount": directParticleColor.program.instructions.count,
            "directParticleColorCodes": codes(directParticleColor.diagnostics),
            "puppetVisibilityCount": puppetVisibility.program.instructions.count,
            "puppetVisibilityCodes": codes(puppetVisibility.diagnostics),
            "puppetVisibilityAuthored":
                resolved(puppetVisibilityAuthored[puppetVisibilityTarget]),
            "puppetVisibilityUser": resolved(puppetVisibilityUser[puppetVisibilityTarget]),
            "puppetVisibilityRuntimeCodes": codes(puppetVisibilityEvaluation.diagnostics),
            "structureCodes": structureCodes,
            "structureInstructionCounts": structureInstructionCounts,
            "structureDecodeRejected": structureDecodeRejected,
            "mismatchedEvaluationCount": mismatchedEvaluation.userValues.count,
            "mismatchedEvaluationCodes": codes(mismatchedEvaluation.diagnostics),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(
        _ key: String,
        _ fallback: SceneUserPropertyValue?,
        _ layerID: Int,
        _ target: SceneUserPropertyBindingTarget,
        condition: SceneUserPropertyValue? = nil,
        pathSuffix: String = "value"
    ) -> SceneUserPropertyBinding {
        .init(
            reference: .init(key: key, condition: condition),
            fallbackValue: fallback,
            path: .init(components: [
                .key("objects"), .index(layerID), .key(pathSuffix),
            ]),
            target: target
        )
    }

    static func property(
        _ key: String,
        _ kind: SceneUserPropertyKind,
        _ value: SceneUserPropertyValue?
    ) -> SceneUserPropertyDefinition {
        .init(
            key: key,
            title: key,
            kind: kind,
            runtimeType: kind.rawValue,
            order: 0,
            index: nil,
            minimumValue: nil,
            maximumValue: nil,
            stepValue: nil,
            allowsFractionalValues: true,
            fractionalPrecision: nil,
            displayCondition: nil,
            defaultValue: value,
            options: []
        )
    }

    static func conditionalInput() -> SceneUserPropertyBinding {
        binding("opacity", .number(1), 70, .layerAlpha(layerID: 70), condition: .bool(true))
    }

    static func missingInput() -> SceneUserPropertyBinding {
        binding("absent", .number(1), 71, .layerAlpha(layerID: 71))
    }

    static func unsupportedInput() -> SceneUserPropertyBinding {
        binding("opacity", .number(1), 72, .layerVisibility(layerID: 72))
    }

    static func localContrastBindingTarget(
        layerID: Int,
        effectIndex: Int
    ) -> SceneUserPropertyBindingTarget {
        .shaderValue(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: 3,
            name: "strength",
            effectPath: "effects/localcontrast/effect.json"
        )
    }

    static func opacityBindingTarget(
        layerID: Int,
        effectIndex: Int,
        usesNormalizedVariant: Bool = false
    ) -> SceneUserPropertyBindingTarget {
        .shaderValue(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: 0,
            name: usesNormalizedVariant ? "Alpha" : "alpha",
            effectPath: usesNormalizedVariant
                ? "Effects\\Opacity\\Effect.json"
                : "effects/opacity/effect.json"
        )
    }

    static func audioBarsColorBindingTarget(
        layerID: Int,
        effectIndex: Int
    ) -> SceneUserPropertyBindingTarget {
        .shaderValue(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: 0,
            name: "Bar Color",
            effectPath: "Effects\\Workshop\\2084198056\\Simple_Audio_Bars\\Effect.json"
        )
    }

    static func path(_ layerID: Int) -> SceneUserPropertyPath {
        .init(components: [.key("objects"), .index(layerID), .key("value")])
    }

    static func codes(_ diagnostics: [ScenePropertyBindingDiagnostic]) -> [String] {
        diagnostics.map { $0.code.rawValue }
    }

    static func decodeFails(_ program: ScenePropertyBindingProgram) -> Bool {
        do {
            let data = try JSONEncoder().encode(program)
            _ = try JSONDecoder().decode(ScenePropertyBindingProgram.self, from: data)
            return false
        } catch {
            return true
        }
    }

    static func resolved(_ value: SceneDynamicResolvedValue?) -> [String] {
        guard let value else { return [] }
        return [String(describing: value.value), value.source.rawValue]
    }
}
'''


class ScenePropertyBindingProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-binding-program-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-property-binding-program"
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

    def test_program_is_codable_and_deterministic(self) -> None:
        self.assertTrue(self.result["roundTrip"])
        self.assertTrue(self.result["deterministic"])
        self.assertTrue(self.result["mixedDeterministic"])
        self.assertEqual(self.result["definitionCount"], 2)
        self.assertEqual(self.result["instructionKeys"], ["tint", "opacity"])

    def test_authored_and_user_values_are_typed(self) -> None:
        self.assertEqual(self.result["authoredAlpha"], ["scalar(0.25)", "authored"])
        self.assertEqual(
            self.result["authoredColor"],
            ["vector3(0.1, 0.2, 0.3)", "authored"],
        )
        self.assertEqual(self.result["userAlpha"], ["scalar(0.75)", "userProperty"])
        self.assertEqual(
            self.result["userColor"],
            ["vector3(0.8, 0.7, 0.6)", "userProperty"],
        )

    def test_bad_runtime_values_keep_authored_values(self) -> None:
        self.assertEqual(self.result["badAlpha"], self.result["authoredAlpha"])
        self.assertEqual(self.result["badColor"], self.result["authoredColor"])
        self.assertEqual(
            self.result["badCodes"],
            ["invalidRuntimeValue", "runtimeTypeMismatch"],
        )
        self.assertEqual(
            self.result["nonFiniteCodes"],
            ["nonFiniteRuntimeValue", "nonFiniteRuntimeValue"],
        )

    def test_invalid_authored_values_fail_closed(self) -> None:
        self.assertEqual(self.result["invalidAuthoredCount"], 0)
        self.assertEqual(
            self.result["invalidAuthoredCodes"],
            ["authoredTypeMismatch", "invalidAuthoredValue", "nonFiniteAuthoredValue"],
        )

    def test_catalog_kind_and_default_values_are_validated(self) -> None:
        self.assertEqual(self.result["invalidCatalogCount"], 0)
        self.assertEqual(
            self.result["invalidCatalogCodes"],
            [
                "propertyKindMismatch",
                "propertyKindMismatch",
                "propertyDefaultTypeMismatch",
                "invalidPropertyDefaultValue",
                "nonFinitePropertyDefaultValue",
                "missingPropertyDefault",
            ],
        )

    def test_conditional_and_duplicate_targets_fail_closed(self) -> None:
        self.assertEqual(self.result["conditionalCount"], 0)
        self.assertEqual(self.result["conditionalCodes"], ["conditionalBinding"])
        self.assertEqual(self.result["duplicateCount"], 0)
        self.assertEqual(self.result["duplicateCodes"], ["duplicateTarget"])

    def test_missing_invalid_and_unsupported_inputs_are_diagnostic(self) -> None:
        self.assertEqual(self.result["rejectedCount"], 0)
        self.assertEqual(
            self.result["rejectedCodes"],
            ["unsupportedTarget", "malformedInputBinding", "missingPropertyDefinition"],
        )
        self.assertNotIn("SceneUserPropertyResolver", PROGRAM_SOURCE.read_text(encoding="utf-8"))

    def test_mixed_property_key_retains_rebuild_requirement(self) -> None:
        self.assertEqual(self.result["mixedKeyCount"], 1)
        self.assertEqual(self.result["mixedKeyRebuild"], ["opacity"])
        self.assertTrue(self.result["mixedKeyRoundTrip"])

    def test_particle_scalar_and_normalized_color_are_live_typed_targets(self) -> None:
        self.assertEqual(self.result["particleCount"], 2)
        self.assertTrue(self.result["particleTargets"])
        self.assertEqual(self.result["particleCodes"], [])
        self.assertEqual(
            self.result["particleUser"],
            [
                ["scalar(0.35)", "userProperty"],
                ["vector3(0.2, 0.4, 0.6)", "userProperty"],
            ],
        )
        self.assertEqual(self.result["particleRuntimeCodes"], [])
        self.assertEqual(self.result["directParticleColorCount"], 0)
        self.assertEqual(self.result["directParticleColorCodes"], ["unsupportedTarget"])

    def test_puppet_animation_visibility_is_a_live_typed_target(self) -> None:
        self.assertEqual(self.result["puppetVisibilityCount"], 1)
        self.assertEqual(self.result["puppetVisibilityCodes"], [])
        self.assertEqual(
            self.result["puppetVisibilityAuthored"],
            ["bool(true)", "authored"],
        )
        self.assertEqual(
            self.result["puppetVisibilityUser"],
            ["bool(false)", "userProperty"],
        )
        self.assertEqual(self.result["puppetVisibilityRuntimeCodes"], [])

    def test_direct_local_contrast_strength_compiles_as_scalar_target(self) -> None:
        self.assertEqual(self.result["localContrastCount"], 1)
        self.assertTrue(self.result["localContrastTarget"])
        self.assertTrue(self.result["localContrastRoundTrip"])
        self.assertEqual(self.result["localContrastCodes"], [])
        self.assertEqual(self.result["localContrastRebuild"], [])
        self.assertEqual(
            self.result["localContrastAuthored"],
            ["scalar(0.32)", "authored"],
        )
        self.assertEqual(
            self.result["localContrastUser"],
            ["scalar(0.75)", "userProperty"],
        )
        self.assertEqual(self.result["localContrastRuntimeCodes"], [])

    def test_simple_audio_bars_color_compiles_as_live_vector_target(self) -> None:
        self.assertEqual(self.result["audioBarsColorCount"], 1)
        self.assertTrue(self.result["audioBarsColorTarget"])
        self.assertEqual(self.result["audioBarsColorCodes"], [])
        self.assertEqual(self.result["audioBarsColorRebuild"], [])
        self.assertEqual(
            self.result["audioBarsColorAuthored"],
            ["vector3(0.99608, 0.09804, 1.0)", "authored"],
        )
        self.assertEqual(
            self.result["audioBarsColorUser"],
            ["vector3(0.25, 0.5, 0.75)", "userProperty"],
        )
        self.assertEqual(self.result["audioBarsColorRuntimeCodes"], [])

    def test_relocated_audio_bars_color_and_opacity_are_live_typed_targets(self) -> None:
        self.assertEqual(self.result["relocatedAudioBarsCount"], 2)
        self.assertTrue(self.result["relocatedAudioBarsTargets"])
        self.assertEqual(self.result["relocatedAudioBarsCodes"], [])
        self.assertEqual(self.result["relocatedAudioBarsRebuild"], [])
        self.assertEqual(
            self.result["relocatedAudioBarsUser"],
            [
                ["vector3(0.2, 0.4, 0.6)", "userProperty"],
                ["scalar(0.35)", "userProperty"],
            ],
        )
        self.assertEqual(self.result["relocatedAudioBarsRuntimeCodes"], [])

    def test_direct_color_targets_do_not_depend_on_effect_path_pass_or_name(self) -> None:
        self.assertEqual(self.result["unsupportedAudioBarsColorCount"], 3)
        self.assertEqual(self.result["unsupportedAudioBarsColorCodes"], [])
        self.assertEqual(self.result["unsupportedAudioBarsColorRebuild"], [])

    def test_direct_opacity_alpha_compiles_four_live_scalar_targets(self) -> None:
        self.assertEqual(self.result["opacityCount"], 4)
        self.assertTrue(self.result["opacityTargets"])
        self.assertTrue(self.result["opacityRoundTrip"])
        self.assertEqual(self.result["opacityCodes"], [])
        self.assertEqual(self.result["opacityRebuild"], [])
        self.assertEqual(
            self.result["opacityAuthored"],
            [["scalar(1.0)", "authored"]] * 4,
        )
        self.assertEqual(
            self.result["opacityUser"],
            [["scalar(0.2)", "userProperty"]] * 4,
        )
        self.assertEqual(self.result["opacityRuntimeCodes"], [])

    def test_xray_visibility_bool_and_size_scalar_compile_and_evaluate(self) -> None:
        self.assertEqual(self.result["xRayBindingCount"], 2)
        self.assertTrue(self.result["xRayTargets"])
        self.assertTrue(self.result["xRayRoundTrip"])
        self.assertEqual(self.result["xRayCodes"], [])
        self.assertEqual(self.result["xRayRebuild"], [])
        self.assertEqual(
            self.result["xRayAuthoredVisibility"],
            ["bool(true)", "authored"],
        )
        self.assertEqual(
            self.result["xRayAuthoredSize"],
            ["scalar(0.2)", "authored"],
        )
        self.assertEqual(
            self.result["xRayUserVisibility"],
            ["bool(false)", "userProperty"],
        )
        self.assertEqual(
            self.result["xRayUserSize"],
            ["scalar(0.4)", "userProperty"],
        )
        self.assertEqual(self.result["xRayRuntimeCodes"], [])

    def test_direct_scalar_targets_do_not_depend_on_effect_path_pass_or_name(self) -> None:
        self.assertEqual(self.result["unsupportedOpacityCount"], 3)
        self.assertEqual(self.result["unsupportedOpacityCodes"], [])
        self.assertEqual(self.result["unsupportedOpacityRebuild"], [])

    def test_generic_scalar_targets_accept_arbitrary_effect_identity(self) -> None:
        self.assertEqual(self.result["unsupportedShaderCount"], 4)
        self.assertEqual(self.result["unsupportedShaderCodes"], [])
        self.assertEqual(self.result["unsupportedShaderRebuild"], [])

    def test_invalid_local_contrast_bindings_fail_closed_and_rebuild(self) -> None:
        self.assertEqual(self.result["conditionalLocalContrastCount"], 0)
        self.assertEqual(
            self.result["conditionalLocalContrastCodes"],
            ["conditionalBinding"],
        )
        self.assertEqual(
            self.result["conditionalLocalContrastRebuild"],
            ["conditionalStrength"],
        )
        self.assertEqual(self.result["invalidLocalContrastCount"], 0)
        self.assertEqual(
            self.result["invalidLocalContrastCodes"],
            ["authoredTypeMismatch"],
        )
        self.assertEqual(
            self.result["invalidLocalContrastRebuild"],
            ["invalidStrength"],
        )

    def test_one_property_can_drive_distinct_direct_shader_targets(self) -> None:
        self.assertEqual(self.result["mixedLocalContrastCount"], 2)
        self.assertEqual(self.result["mixedLocalContrastCodes"], [])
        self.assertEqual(self.result["mixedLocalContrastRebuild"], [])

    def test_shader_target_mapping_has_no_effect_or_workshop_selector(self) -> None:
        source = (
            SOURCE_ROOT
            / "Properties/ScenePropertyBindingCompiler+TargetMapping.swift"
        ).read_text(encoding="utf-8")
        self.assertNotIn("isSimpleAudioBars", source)
        self.assertNotIn("effects/localcontrast/effect.json", source)
        self.assertNotIn("effects/opacity/effect.json", source)
        self.assertNotIn("effects/tint/effect.json", source)
        self.assertNotIn("workshop/2084198056", source)

    def test_cached_program_structure_is_validated_fail_closed(self) -> None:
        self.assertEqual(
            self.result["structureCodes"],
            [
                ["duplicateProgramDefinition"],
                ["duplicateProgramInstruction"],
                ["missingProgramDefinition"],
                ["programTypeMismatch"],
            ],
        )
        self.assertEqual(self.result["structureInstructionCounts"], [0, 0, 0, 0])
        self.assertEqual(self.result["structureDecodeRejected"], [True, True, True, True])
        self.assertEqual(self.result["mismatchedEvaluationCount"], 0)
        self.assertEqual(self.result["mismatchedEvaluationCodes"], ["programTypeMismatch"])


if __name__ == "__main__":
    unittest.main()
