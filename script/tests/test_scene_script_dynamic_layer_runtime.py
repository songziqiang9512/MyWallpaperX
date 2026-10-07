#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
)
SOURCES = [
    SCENE_SCRIPT.parent / "Particles/SceneParticlePlaybackModels.swift",
    SCENE_SCRIPT / "SceneScriptDynamicLayerRuntime+ParticlePlayback.swift",
    SCENE_SCRIPT / "SceneScriptLayerMutation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerTopologyModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift",
]

HARNESS = r'''
import Foundation

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Equatable, Sendable {
    case mutationOverflow(String)
    case invalidArgument(String)
    case staleOwner
}

nonisolated enum SceneDynamicValueType: Sendable { case bool, string, vector3, scalar }
nonisolated enum SceneDynamicValue: Equatable, Sendable {
    case scalar(Double)
    case bool(Bool)
    case string(String)
    case vector3(Double, Double, Double)
}
nonisolated enum SceneDynamicSource: Sendable { case sceneScript }
nonisolated struct SceneDynamicResolvedValue: Sendable {
    let value: SceneDynamicValue
    let source: SceneDynamicSource
}
nonisolated struct SceneDynamicSnapshot: Sendable {
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        values[target]
    }
}
nonisolated enum SceneDynamicLayerField: Hashable, Sendable {
    case visibility, solid, origin, scale, angles, color, alpha
}
nonisolated enum SceneDynamicParticleField: Hashable, Sendable { case alpha }
nonisolated enum SceneDynamicTextField: Hashable, Sendable { case content, font, color }
nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case text(layerID: Int, field: SceneDynamicTextField)
    case effectVisibility(layerID: Int, effectIndex: Int)
    case particle(layerID: Int, field: SceneDynamicParticleField)
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
    case materialConstant(layerID: Int, passIndex: Int, name: String, materialPath: String)
    case scriptInstanceProperty(layerID: Int, path: [String])
    case scene(Int), camera(Int)
}
nonisolated struct SceneScriptParticlePlaybackCommand: Sendable {
    let layerID: Int
    let action: SceneParticlePlaybackAction
    let callbackEpoch: UInt64
    let ordinal: UInt32
    var count: Int = 0
}
nonisolated struct SceneScriptOwnerEffects: Sendable {
    let ownerTarget: SceneDynamicTarget
    let layerMutations: [SceneScriptLayerMutation]
    var particlePlaybackCommands: [SceneScriptParticlePlaybackCommand] = []
    var animationMutations: [Int] = [], materialFunctionMutations: [Int] = []
    var videoCommands: [Int] = [], textureAnimationCommands: [Int] = [], puppetBoneMutations: [Int] = []
    var puppetAnimationCommands: [Int] = []
    var puppetAnimationCallbackRegistrations: Int = 0
}
nonisolated struct SceneDynamicTargetDefinition: Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
}

nonisolated struct SceneParticleInstanceOverride: Sendable {
    struct BoundValue: Sendable {
        struct NumericValue: Sendable { let scalarValue: Double? }
        let value: NumericValue?
    }
    let alpha: BoundValue?
}

nonisolated struct SceneRenderDescriptor: Sendable {
    struct Effect: Sendable { var visible: Bool? }
    struct Layer: Sendable {
        var solid: Bool? = nil
        var effects: [Effect] = []
        var alpha: Double? = nil
        struct TextStyle: Sendable { let fontPath: String?; var colorRGB: [Float]? = nil }
        let id: Int
        let visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let contentKind: String
        let text: String?
        let textStyle: TextStyle?
        let imagePath: String?
        var colorRGB: [Float]?
        var childLayerIDs: [Int] = []
        var particleInstanceOverride: SceneParticleInstanceOverride? = nil

        static func dynamicText(_ mutation: SceneScriptLayerMutation) -> Self? {
            guard mutation.isDynamic, mutation.kind == .upsert else { return nil }
            return .init(
                id: mutation.layerID,
                visible: mutation.visible,
                originXYZ: [
                    Float(mutation.origin.x), Float(mutation.origin.y),
                    Float(mutation.origin.z),
                ],
                scaleXYZ: [
                    Float(mutation.scale.x), Float(mutation.scale.y),
                    Float(mutation.scale.z),
                ],
                anglesXYZ: [
                    Float(mutation.angles.x), Float(mutation.angles.y),
                    Float(mutation.angles.z),
                ],
                contentKind: "text", text: mutation.text,
                textStyle: .init(fontPath: mutation.font)
            )
        }

        static func dynamicImage(
            _ mutation: SceneScriptLayerMutation,
            template: SceneScriptDynamicImageLayerTemplate
        ) -> Self? {
            guard mutation.isDynamic, mutation.kind == .upsert,
                  mutation.assetPath == template.modelPath else { return nil }
            return .init(
                id: mutation.layerID,
                visible: mutation.visible,
                originXYZ: [
                    Float(mutation.origin.x), Float(mutation.origin.y),
                    Float(mutation.origin.z),
                ],
                scaleXYZ: [
                    Float(mutation.scale.x), Float(mutation.scale.y),
                    Float(mutation.scale.z),
                ],
                anglesXYZ: [
                    Float(mutation.angles.x), Float(mutation.angles.y),
                    Float(mutation.angles.z),
                ],
                contentKind: "image",
                text: nil,
                textStyle: nil,
                imagePath: template.modelPath,
                colorRGB: [
                    Float(mutation.color.x),
                    Float(mutation.color.y),
                    Float(mutation.color.z),
                ]
            )
        }

        init(
            id: Int,
            visible: Bool?,
            originXYZ: [Float]?,
            scaleXYZ: [Float]?,
            anglesXYZ: [Float]?,
            contentKind: String = "image",
            text: String? = nil,
            textStyle: TextStyle? = nil,
            imagePath: String? = nil,
            colorRGB: [Float]? = nil
        ) {
            self.id = id
            self.visible = visible
            self.originXYZ = originXYZ
            self.scaleXYZ = scaleXYZ
            self.anglesXYZ = anglesXYZ
            self.contentKind = contentKind
            self.text = text
            self.textStyle = textStyle
            self.imagePath = imagePath
            self.colorRGB = colorRGB
        }
    }

    let layers: [Layer]
    let renderOrderLayerIDs: [Int]
}

func mutation(
    _ id: Int,
    dynamic: Bool = true,
    kind: SceneScriptLayerMutation.Kind = .upsert,
    order: Int = 0,
    alpha: Double = 1,
    text: String = "text",
    font: String = "",
    fields: SceneScriptLayerMutation.Fields = [],
    origin: SIMD3<Double> = .zero,
    scale: SIMD3<Double> = .init(repeating: 1),
    angles: SIMD3<Double> = .zero,
    visible: Bool = true,
    assetPath: String? = nil,
    ownerTarget: SceneDynamicTarget? = nil
) -> SceneScriptLayerMutation {
    .init(
        kind: kind, isDynamic: dynamic, fields: fields,
        layerID: id, orderIndex: order,
        visible: visible, alpha: alpha, origin: origin,
        scale: scale, angles: angles,
        color: .init(repeating: 1), pointSize: 32, text: text, font: font,
        assetPath: assetPath, ownerTarget: ownerTarget
    )
}

func succeeded(
    _ result: Result<Void, SceneScriptScalarRuntimeFailure>
) -> Bool {
    if case .success = result { return true }
    return false
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(
            layers: [
                .init(id: 10, visible: true, originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0]),
                .init(
                    id: 20, visible: true, originXYZ: [0, 0, 0],
                    scaleXYZ: [1, 1, 1], anglesXYZ: [0, 0, 0],
                    contentKind: "text", text: "authored",
                    textStyle: .init(fontPath: nil)
                ),
            ],
            renderOrderLayerIDs: [10, 20]
        )
        let runtime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let beforeCreate = runtime.snapshot()
        let visibilityRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: []
        )
        let visibilityDefinitions = visibilityRuntime.authoredLayerDefinitions
        let visibilityBefore = visibilityRuntime.snapshot()
        let visibilityPlan = visibilityRuntime.preflightIsolatingOwners([
            mutation(20, dynamic: false, fields: [.visibility], visible: false)
        ])
        let visibilityPreflightIsReadOnly = visibilityRuntime.snapshot().authoredLayerValues.isEmpty
        visibilityRuntime.commit(visibilityPlan)
        let visibilityAfter = visibilityRuntime.snapshot()
        let styleRuntime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [10])
        let stylePlan = styleRuntime.preflightIsolatingOwners([mutation(10, dynamic: false, alpha: 0.25, fields: [.alpha, .color])])
        let styleBeforeCommit = styleRuntime.snapshot().authoredLayerValues.isEmpty
        styleRuntime.commit(stylePlan)
        let styleAfterCommit = styleRuntime.snapshot()
        let invalidStyle = styleRuntime.apply([mutation(10, dynamic: false, alpha: -1, fields: [.alpha])])
        let styleAfterFailure = styleRuntime.snapshot()
        let beforeInvalidParticleAlpha = runtime.snapshot().authoredLayerValues
        let invalidParticleAlpha = runtime.apply([mutation(10, dynamic: false, fields: [.particleAlpha])])
        let invalidParticleAlphaPreservesValues = runtime.snapshot().authoredLayerValues == beforeInvalidParticleAlpha
        let create = runtime.apply([mutation(-1, order: 1)])
        let afterCreate = runtime.snapshot()
        let move = runtime.apply([mutation(-1, order: 2, text: "updated")])
        let afterMove = runtime.snapshot()
        let staticUpdate = runtime.apply([
            mutation(
                10, dynamic: false,
                fields: [.angles, .visibility],
                angles: .init(7, 8, 9), visible: false
            )
        ])
        let afterStatic = runtime.snapshot()
        let peerUpdate = runtime.apply([
            mutation(
                20, dynamic: false, text: "~", font: "fonts/selected.ttf",
                fields: [.scale, .text, .font]
            )
        ])
        let afterPeer = runtime.snapshot()
        let rejected = runtime.apply([
            mutation(20, dynamic: false, text: "must-not-publish", fields: [.text]),
            mutation(10, dynamic: false, text: "invalid-image-text", fields: [.text]),
        ])
        let afterRejected = runtime.snapshot()
        let isolatedRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: []
        )
        let ownerA = SceneDynamicTarget.layer(layerID: 10, field: .origin)
        let ownerB = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let ownerC = SceneDynamicTarget.layer(layerID: 10, field: .angles)
        let ownerEffects = [
            SceneScriptOwnerEffects(ownerTarget: ownerA, layerMutations: [
                mutation(
                    20, dynamic: false, fields: [.scale],
                    scale: .init(2, 3, 4), ownerTarget: ownerA
                ),
            ]),
            SceneScriptOwnerEffects(ownerTarget: ownerB, layerMutations: [
                mutation(
                    10, dynamic: false, text: "invalid-image-text",
                    fields: [.text], ownerTarget: ownerB
                ),
            ]),
            SceneScriptOwnerEffects(ownerTarget: ownerC, layerMutations: [
                mutation(
                    10, dynamic: false, fields: [.angles],
                    angles: .init(5, 6, 7), ownerTarget: ownerC
                ),
            ]),
        ]
        let admission = isolatedRuntime.preflightOwnerEffects(ownerEffects)
        let preflightSnapshot = isolatedRuntime.snapshot()
        let isolated = admission.layerPlan.outcome
        isolatedRuntime.commit(admission.layerPlan)
        let afterIsolated = isolatedRuntime.snapshot()
        let duplicateOwnerA = SceneDynamicTarget.layer(
            layerID: 10, field: .visibility
        )
        let duplicateOwnerB = SceneDynamicTarget.layer(
            layerID: 20, field: .visibility
        )
        let duplicateRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: []
        )
        let duplicateAdmission = duplicateRuntime.preflightOwnerEffects([
            SceneScriptOwnerEffects(
                ownerTarget: duplicateOwnerA,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.visibility],
                    visible: false, ownerTarget: duplicateOwnerA
                )]
            ),
            SceneScriptOwnerEffects(
                ownerTarget: duplicateOwnerB,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.visibility],
                    visible: false, ownerTarget: duplicateOwnerB
                )]
            ),
        ])
        duplicateRuntime.commit(duplicateAdmission.layerPlan)
        let afterDuplicate = duplicateRuntime.snapshot()
        let conflictingRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: []
        )
        let conflictingAdmission = conflictingRuntime.preflightOwnerEffects([
            SceneScriptOwnerEffects(
                ownerTarget: duplicateOwnerA,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.visibility],
                    visible: false, ownerTarget: duplicateOwnerA
                )]
            ),
            SceneScriptOwnerEffects(
                ownerTarget: duplicateOwnerB,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.visibility],
                    visible: true, ownerTarget: duplicateOwnerB
                )]
            ),
        ])
        let budgetRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let seededFirstHalf = succeeded(budgetRuntime.apply((1...128).map {
            mutation(-$0, order: $0)
        }))
        let seededSecondHalf = succeeded(budgetRuntime.apply((129...256).map {
            mutation(-$0, order: $0)
        }))
        let budgetOwnerA = SceneDynamicTarget.layer(
            layerID: 10, field: .origin
        )
        let budgetOwnerB = SceneDynamicTarget.layer(
            layerID: 20, field: .origin
        )
        let budgetOwnerC = SceneDynamicTarget.layer(
            layerID: 10, field: .angles
        )
        let budgetEffects = [
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerA,
                layerMutations: (1...128).map {
                    mutation(-$0, kind: .destroy, ownerTarget: budgetOwnerA)
                }
            ),
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerB,
                layerMutations: (257...384).map {
                    mutation(-$0, order: $0 - 256, ownerTarget: budgetOwnerB)
                }
            ),
            SceneScriptOwnerEffects(
                ownerTarget: budgetOwnerC,
                layerMutations: [mutation(
                    10, dynamic: false, fields: [.angles],
                    angles: .init(9, 8, 7), ownerTarget: budgetOwnerC
                )]
            ),
        ]
        let fixedPoint = budgetRuntime.preflightOwnerEffectsToFixedPoint(
            budgetEffects
        ) { admitted in
            admitted.contains { $0.ownerTarget == budgetOwnerA }
                ? [budgetOwnerA] : []
        }
        budgetRuntime.commit(fixedPoint.admission.layerPlan)
        let afterFixedPoint = budgetRuntime.snapshot()
        let projectionRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: []
        )
        let projectionOwnerA = budgetOwnerA, projectionOwnerB = budgetOwnerB
        let projectionEffects = [
            SceneScriptOwnerEffects(ownerTarget: projectionOwnerA, layerMutations: [], animationMutations: [-1]),
            SceneScriptOwnerEffects(ownerTarget: projectionOwnerB, layerMutations: [], animationMutations: [2]),
        ]
        var particleRejectedSets: [Set<SceneDynamicTarget>] = []
        var particleEligibleCommands: [[Int]] = []
        let projectionAdmission = projectionRuntime.preflightOwnerEffectsToFixedPoint(
            projectionEffects,
            rejectingParticleTransitions: { _, admitted, rejected in
                particleRejectedSets.append(rejected)
                let commands = admitted.filter { !rejected.contains($0.ownerTarget) }.flatMap(\.animationMutations)
                particleEligibleCommands.append(commands)
                return commands.contains(-1) ? [projectionOwnerB] : []
            }
        ) { admitted in
            Set(admitted.filter { $0.animationMutations.contains(-1) }.map(\.ownerTarget))
        }
        var projectedCommandRounds: [[Int]] = []
        let laterRejection = projectionRuntime.preflightOwnerEffectsToFixedPoint(
            projectionEffects.map { owner in
                .init(ownerTarget: owner.ownerTarget, layerMutations: [],
                      animationMutations: owner.animationMutations.map(abs))
            },
            rejectingDependents: { rejected in
                rejected.union([projectionOwnerA, budgetOwnerC])
            }
        ) { admitted in
            projectedCommandRounds.append(admitted.flatMap(\.animationMutations))
            return []
        }
        let destroy = runtime.apply([mutation(-1, kind: .destroy, order: 2)])
        let afterDestroy = runtime.snapshot()
        let authoredDestroyRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let authoredDestroyPlan = authoredDestroyRuntime.preflightIsolatingOwners([
            mutation(10, dynamic: false, kind: .destroy)
        ])
        let authoredDestroyPreflightWasReadOnly = authoredDestroyRuntime
            .snapshot().destroyedAuthoredLayerIDs.isEmpty
        authoredDestroyRuntime.commit(authoredDestroyPlan)
        let afterAuthoredDestroy = authoredDestroyRuntime.snapshot()
        let authoredResurrection = authoredDestroyRuntime.apply([
            mutation(
                10, dynamic: false, fields: [.visibility], visible: true
            )
        ])
        let colorTarget = SceneDynamicTarget.layer(layerID: 20, field: .color)
        let imageRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [],
            dynamicImageTemplates: [
                "models/bar.json": .init(
                    modelPath: "models/bar.json",
                    renderSizeWH: [4, 4],
                    materialColorTarget: colorTarget
                ),
            ]
        )
        let imageCreate = imageRuntime.apply([
            mutation(-2, order: 1, assetPath: "models/bar.json"),
        ])
        let imageSnapshot = imageRuntime.snapshot()
        let resolvedImage = imageSnapshot.resolvingDynamicMaterialColors(
            from: .init(values: [
                colorTarget: .init(
                    value: .vector3(0.25, 0.5, 0.75),
                    source: .sceneScript
                ),
            ])
        )
        let unresolvedImage = imageSnapshot.resolvingDynamicMaterialColors(
            from: .init(values: [:])
        )
        let revisionRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: []
        )
        let initialTopologyRevision = revisionRuntime.topologyRevision
        let dynamicTopologyPlan = revisionRuntime.preflightIsolatingOwners([
            mutation(-7, order: 1)
        ])
        revisionRuntime.commit(dynamicTopologyPlan)
        let afterDynamicTopologyRevision = revisionRuntime.topologyRevision
        // Warm the topology and value cache before the value-only update.
        // Without this snapshot the old stale-cache implementation also passes.
        let dynamicBeforeValueLayer = revisionRuntime.snapshot()
            .dynamicLayers.first { $0.id == -7 }
        let dynamicValuePlan = revisionRuntime.preflightIsolatingOwners([
            mutation(-7, order: 1, origin: .init(3, 4, 5), scale: .init(2, 2, 2))
        ])
        revisionRuntime.commit(dynamicValuePlan)
        let afterDynamicValueRevision = revisionRuntime.topologyRevision
        let dynamicValueLayer = revisionRuntime.snapshot().dynamicLayers.first {
            $0.id == -7
        }
        let initialDefinitionRevision = revisionRuntime.authoredDefinitionRevision
        let firstDefinitionPlan = revisionRuntime.preflightIsolatingOwners([
            mutation(
                10, dynamic: false, fields: [.origin],
                origin: .init(2, 3, 4)
            ),
        ])
        revisionRuntime.commit(firstDefinitionPlan)
        let afterDefinitionRevision = revisionRuntime.authoredDefinitionRevision
        let valueOnlyPlan = revisionRuntime.preflightIsolatingOwners([
            mutation(
                10, dynamic: false, fields: [.origin],
                origin: .init(5, 6, 7)
            ),
        ])
        revisionRuntime.commit(valueOnlyPlan)
        // Mixed-frame unified order semantics: the mutations carry the C
        // catalog's FINAL absolute positions (the ABI has no step-wise
        // journal ops). Both interleavings of a dynamic create and an
        // authored sort must reproduce their own C final orders:
        // sequence A ([sort 10->1, create X@2] in C) -> [20, 10, X];
        // sequence B ([create X@0, sort 10->2] in C) -> [X, 20, 10].
        let mixedARuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let mixedAResult = mixedARuntime.apply([
            mutation(-1, order: 2, text: "X"),
            mutation(10, dynamic: false, order: 1, fields: []),
        ])
        let mixedAOrder = mixedARuntime.snapshot().renderOrderLayerIDs
        let mixedBRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [10]
        )
        let mixedBResult = mixedBRuntime.apply([
            mutation(10, dynamic: false, order: 2, fields: []),
            mutation(-1, order: 0, text: "X"),
        ])
        let mixedBOrder = mixedBRuntime.snapshot().renderOrderLayerIDs
        let payload: [String: Any] = [
            "nonParticleInstanceAlphaRejected": !succeeded(invalidParticleAlpha) && invalidParticleAlphaPreservesValues,
            "styleBeforeCommit": styleBeforeCommit,
            "styleAlphaPublished": styleAfterCommit.authoredLayerValues[.layer(layerID: 10, field: .alpha)] == .scalar(0.25),
            "styleColorPublished": styleAfterCommit.authoredLayerValues[.layer(layerID: 10, field: .color)] == .vector3(1, 1, 1),
            "styleFailurePreservesCurrent": !succeeded(invalidStyle) && styleAfterFailure.authoredLayerValues == styleAfterCommit.authoredLayerValues,
            "createSucceeded": succeeded(create),
            "priorSnapshotStable": beforeCreate.dynamicLayers.isEmpty,
            "createdIDs": afterCreate.dynamicLayers.map(\.id),
            "createdOrder": afterCreate.renderOrderLayerIDs,
            "mixedAResultSucceeded": succeeded(mixedAResult),
            "mixedAOrder": mixedAOrder,
            "mixedBResultSucceeded": succeeded(mixedBResult),
            "mixedBOrder": mixedBOrder,
            "moveSucceeded": succeeded(move),
            "movedOrder": afterMove.renderOrderLayerIDs,
            "staticAccepted": succeeded(staticUpdate),
            "staticAnglesPublished": afterStatic.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(7, 8, 9),
            "staticVisibilityPublished": afterStatic.authoredLayerValues[
                .layer(layerID: 10, field: .visibility)
            ] == .bool(false),
            "peerUpdateAccepted": succeeded(peerUpdate),
            "peerScalePublished": afterPeer.authoredLayerValues[
                .layer(layerID: 20, field: .scale)
            ] == .vector3(1, 1, 1),
            "peerTextPublished": afterPeer.authoredLayerValues[
                .text(layerID: 20, field: .content)
            ] == .string("~"),
            "peerFontPublished": afterPeer.authoredLayerValues[
                .text(layerID: 20, field: .font)
            ] == .string("fonts/selected.ttf"),
            "authoredDefinitionCount": runtime.authoredLayerDefinitions.count,
            "authoredDefinitionTargets": Set(runtime.authoredLayerDefinitions.map(\.target)) == Set([
                .layer(layerID: 10, field: .origin), .layer(layerID: 10, field: .scale),
                .layer(layerID: 10, field: .angles), .layer(layerID: 10, field: .visibility),
                .layer(layerID: 20, field: .visibility), .layer(layerID: 20, field: .scale),
                .text(layerID: 20, field: .content), .text(layerID: 20, field: .font)]),
            "visibilityLanesPreparedBeforeFirstWrite": Set(visibilityDefinitions.map(\.target)) == Set([
                .layer(layerID: 10, field: .visibility), .layer(layerID: 20, field: .visibility)])
                && visibilityDefinitions.allSatisfy { $0.authoredValue == .bool(true) },
            "visibilityCandidatePublishedBeforeCommit": visibilityPlan.authoredLayerValues[
                .layer(layerID: 20, field: .visibility)] == .bool(false),
            "visibilityPreflightIsReadOnly": visibilityPreflightIsReadOnly,
            "visibilityCommitRetainsLaneWithoutSchemaChange": visibilityAfter.authoredLayerValues[
                .layer(layerID: 20, field: .visibility)] == .bool(false)
                && visibilityBefore.authoredLayerValues.isEmpty
                && visibilityRuntime.authoredDefinitionRevision == 0
                && visibilityRuntime.topologyRevision == 0,
            "rejected": !succeeded(rejected),
            "failedBatchTextRolledBack": afterRejected.authoredLayerValues[
                .text(layerID: 20, field: .content)
            ] == .string("~"),
            "rollbackLayers": afterRejected.dynamicLayers.map(\.id),
            "rollbackOrder": afterRejected.renderOrderLayerIDs,
            "isolatedCommittedMutationCount": isolated.committedMutationCount,
            "isolatedFailureCount": admission.rejectedOwners.count,
            "isolatedFailureOwnerIsB": admission.rejectedOwners.first?
                .ownerTarget == ownerB,
            "isolatedAdmittedOwnerCount": admission.admittedEffects.count,
            "isolatedPreflightWasReadOnly": preflightSnapshot.authoredLayerValues.isEmpty,
            "isolatedPeerScalePublished": afterIsolated.authoredLayerValues[
                .layer(layerID: 20, field: .scale)
            ] == .vector3(2, 3, 4),
            "isolatedDisjointAnglesPublished": afterIsolated.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(5, 6, 7),
            "isolatedBadTextAbsent": afterIsolated.authoredLayerValues[
                .text(layerID: 10, field: .content)
            ] == nil,
            "identicalDuplicateOwnersAdmitted":
                duplicateAdmission.admittedEffects.count == 2
                    && duplicateAdmission.rejectedOwners.isEmpty,
            "identicalDuplicateValuePublished": afterDuplicate.authoredLayerValues[
                .layer(layerID: 10, field: .visibility)
            ] == .bool(false),
            "conflictingLaterOwnerRejected":
                conflictingAdmission.admittedEffects.map(\.ownerTarget)
                    == [duplicateOwnerA]
                    && conflictingAdmission.rejectedOwners.map(\.ownerTarget)
                    == [duplicateOwnerB],
            "fixedPointSeeded": seededFirstHalf && seededSecondHalf,
            "particleSeesCurrentExternalReject": particleRejectedSets.first?.contains(projectionOwnerA) == true,
            "particleFiltersWholeRejectedBundle": particleEligibleCommands == [[2], [2]],
            "particleKeepsValidPeer": projectionAdmission.admission.admittedEffects.map(\.ownerTarget) == [projectionOwnerB],
            "laterRejectionReplacesProjection": projectedCommandRounds == [[1, 2], [2]],
            "laterRejectionKeepsValidPeer": laterRejection.admission.admittedEffects.map(\.ownerTarget) == [projectionOwnerB],
            "typedOnlyReaderRejected": laterRejection.externallyRejectedOwners.contains(budgetOwnerC),
            "fixedPointExternalRejectsA":
                fixedPoint.externallyRejectedOwners == [budgetOwnerA],
            "fixedPointLayerRejectsB":
                fixedPoint.admission.rejectedOwners.contains {
                    $0.ownerTarget == budgetOwnerB
                },
            "fixedPointAdmitsOnlyC":
                fixedPoint.admission.admittedEffects.map(\.ownerTarget)
                    == [budgetOwnerC],
            "fixedPointPreservesFullTopology":
                afterFixedPoint.dynamicLayers.map(\.id).sorted()
                    == Array(-256 ... -1),
            "fixedPointCommitsDisjointC": afterFixedPoint.authoredLayerValues[
                .layer(layerID: 10, field: .angles)
            ] == .vector3(9, 8, 7),
            "destroySucceeded": succeeded(destroy),
            "destroyedIDs": afterDestroy.dynamicLayers.map(\.id),
            "destroyedOrder": afterDestroy.renderOrderLayerIDs,
            "authoredDestroyPreflightWasReadOnly":
                authoredDestroyPreflightWasReadOnly,
            "authoredDestroySucceeded":
                authoredDestroyPlan.outcome.failures.isEmpty,
            "authoredDestroyedIDs":
                afterAuthoredDestroy.destroyedAuthoredLayerIDs.sorted(),
            "authoredDestroyedOrder": afterAuthoredDestroy.renderOrderLayerIDs,
            "authoredDestroyBumpsTopology":
                afterAuthoredDestroy.topologyRevision > 0,
            "authoredResurrectionRejected": !succeeded(authoredResurrection),
            "dynamicImageSucceeded": succeeded(imageCreate),
            "dynamicImageColorTarget":
                imageSnapshot.dynamicMaterialColorTargetsByLayerID[-2]
                    == colorTarget,
            "dynamicImageColor": resolvedImage.dynamicLayers.first?
                .colorRGB?.map(Double.init) ?? [],
            "dynamicImageWithoutTypedColor": unresolvedImage.dynamicLayers.first?
                .colorRGB?.map(Double.init) ?? [],
            "definitionRevisionBumped": afterDefinitionRevision > initialDefinitionRevision,
            "valueOnlyRevisionStable": revisionRuntime.authoredDefinitionRevision == afterDefinitionRevision,
            "topologyRevisionStartsAtZero": initialTopologyRevision == 0,
            "dynamicTopologyRevisionBumped": afterDynamicTopologyRevision > initialTopologyRevision,
            "dynamicValueKeepsTopologyRevision": afterDynamicValueRevision == afterDynamicTopologyRevision,
            "dynamicBeforeValueOrigin": dynamicBeforeValueLayer?.originXYZ == [0, 0, 0],
            "dynamicBeforeValueScale": dynamicBeforeValueLayer?.scaleXYZ == [1, 1, 1],
            "dynamicValueOriginPublished": dynamicValueLayer?.originXYZ == [3, 4, 5],
            "dynamicValueScalePublished": dynamicValueLayer?.scaleXYZ == [2, 2, 2],
            "authoredValueKeepsTopologyRevision": revisionRuntime.topologyRevision == afterDynamicTopologyRevision,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptDynamicLayerRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-dynamic-layer-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "dynamic-layer-runtime"
        compilation = subprocess.run(
            ["swiftc", "-import-objc-header", str(SCENE_SCRIPT / "SceneQuickJS.h"),
             *map(str, SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(
            subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            ).stdout
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_create_and_sort_publish_only_through_snapshots(self) -> None:
        self.assertTrue(self.result["createSucceeded"])
        self.assertTrue(self.result["priorSnapshotStable"])
        self.assertEqual(self.result["createdIDs"], [-1])
        self.assertEqual(self.result["createdOrder"], [10, -1, 20])
        self.assertTrue(self.result["moveSucceeded"])
        self.assertEqual(self.result["movedOrder"], [10, 20, -1])

    def test_mixed_frames_reproduce_their_c_final_orders(self) -> None:
        self.assertTrue(self.result["mixedAResultSucceeded"])
        self.assertEqual(self.result["mixedAOrder"], [20, 10, -1])
        self.assertTrue(self.result["mixedBResultSucceeded"])
        self.assertEqual(self.result["mixedBOrder"], [-1, 20, 10])

    def test_static_transform_mutation_and_failed_batch_are_atomic(self) -> None:
        self.assertTrue(self.result["staticAccepted"])
        self.assertTrue(self.result["staticAnglesPublished"])
        self.assertTrue(self.result["staticVisibilityPublished"])
        self.assertTrue(self.result["peerUpdateAccepted"])
        self.assertTrue(self.result["peerScalePublished"])
        self.assertTrue(self.result["peerTextPublished"])
        self.assertTrue(self.result["peerFontPublished"])
        self.assertEqual(self.result["authoredDefinitionCount"], 8)
        self.assertTrue(self.result["authoredDefinitionTargets"])
        self.assertTrue(self.result["rejected"])
        self.assertTrue(self.result["failedBatchTextRolledBack"])
        self.assertEqual(self.result["rollbackLayers"], [-1])
        self.assertEqual(self.result["rollbackOrder"], [10, 20, -1])

    def test_visibility_lane_exists_before_the_first_authored_handle_write(self) -> None:
        self.assertTrue(self.result["visibilityLanesPreparedBeforeFirstWrite"])
        self.assertTrue(self.result["visibilityCandidatePublishedBeforeCommit"])
        self.assertTrue(self.result["visibilityPreflightIsReadOnly"])
        self.assertTrue(self.result["visibilityCommitRetainsLaneWithoutSchemaChange"])

    def test_instance_alpha_cannot_be_admitted_for_an_ordinary_layer(self) -> None:
        self.assertTrue(self.result["nonParticleInstanceAlphaRejected"])

    def test_destroy_removes_only_the_dynamic_layer(self) -> None:
        self.assertTrue(self.result["destroySucceeded"])
        self.assertEqual(self.result["destroyedIDs"], [])
        self.assertEqual(self.result["destroyedOrder"], [10, 20])

    def test_authored_self_destroy_is_atomic_persistent_topology(self) -> None:
        self.assertTrue(self.result["authoredDestroyPreflightWasReadOnly"])
        self.assertTrue(self.result["authoredDestroySucceeded"])
        self.assertEqual(self.result["authoredDestroyedIDs"], [10])
        self.assertEqual(self.result["authoredDestroyedOrder"], [20])
        self.assertTrue(self.result["authoredDestroyBumpsTopology"])
        self.assertTrue(self.result["authoredResurrectionRejected"])

    def test_bad_owner_does_not_reject_disjoint_owner_mutations(self) -> None:
        self.assertEqual(self.result["isolatedCommittedMutationCount"], 2)
        self.assertEqual(self.result["isolatedFailureCount"], 1)
        self.assertTrue(self.result["isolatedFailureOwnerIsB"])
        self.assertEqual(self.result["isolatedAdmittedOwnerCount"], 2)
        self.assertTrue(self.result["isolatedPreflightWasReadOnly"])
        self.assertTrue(self.result["isolatedPeerScalePublished"])
        self.assertTrue(self.result["isolatedDisjointAnglesPublished"])
        self.assertTrue(self.result["isolatedBadTextAbsent"])

    def test_identical_duplicate_owner_writes_coalesce_but_disagreement_rejects(self) -> None:
        self.assertTrue(self.result["identicalDuplicateOwnersAdmitted"])
        self.assertTrue(self.result["identicalDuplicateValuePublished"])
        self.assertTrue(self.result["conflictingLaterOwnerRejected"])

    def test_external_rejection_reaches_layer_admission_fixed_point(self) -> None:
        self.assertTrue(self.result["fixedPointSeeded"])
        self.assertTrue(self.result["fixedPointExternalRejectsA"])
        self.assertTrue(self.result["fixedPointLayerRejectsB"])
        self.assertTrue(self.result["fixedPointAdmitsOnlyC"])
        self.assertTrue(self.result["fixedPointPreservesFullTopology"])
        self.assertTrue(self.result["fixedPointCommitsDisjointC"])

    def test_particle_preflight_sees_this_round_rejected_owner_and_preserves_peer(self) -> None:
        self.assertTrue(self.result["particleSeesCurrentExternalReject"])
        self.assertTrue(self.result["particleFiltersWholeRejectedBundle"])
        self.assertTrue(self.result["particleKeepsValidPeer"])

    def test_dependency_rejection_replaces_previous_projection_candidate(self) -> None:
        self.assertTrue(self.result["laterRejectionReplacesProjection"])
        self.assertTrue(self.result["laterRejectionKeepsValidPeer"])
        self.assertTrue(self.result["typedOnlyReaderRejected"])

    def test_dynamic_image_inherits_typed_material_color(self) -> None:
        self.assertTrue(self.result["dynamicImageSucceeded"])
        self.assertTrue(self.result["dynamicImageColorTarget"])
        self.assertEqual(self.result["dynamicImageColor"], [0.25, 0.5, 0.75])
        self.assertEqual(self.result["dynamicImageWithoutTypedColor"], [1.0, 1.0, 1.0])

    def test_material_color_projection_has_quiescent_and_lazy_copy_gates(self) -> None:
        source = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
        projection = source.split(
            "func resolvingDynamicMaterialColors(", 1
        )[1].split(
            "nonisolated struct SceneScriptDynamicImageLayerTemplate", 1
        )[0]
        self.assertRegex(
            projection,
            r"guard !dynamicLayers\.isEmpty,\s*!dynamicMaterialColorTargetsByLayerID\.isEmpty else \{\s*return self",
        )
        self.assertIn(
            "var resolvedLayers: [SceneRenderDescriptor.Layer]?", projection
        )
        self.assertIn("if resolvedLayers == nil", projection)
        self.assertIn("guard let resolvedLayers else { return self }", projection)

    def test_definition_revision_tracks_schema_changes_only(self) -> None:
        self.assertTrue(self.result["definitionRevisionBumped"])
        self.assertTrue(self.result["valueOnlyRevisionStable"])

    def test_topology_revision_tracks_dynamic_projection_only(self) -> None:
        self.assertTrue(self.result["styleBeforeCommit"])
        self.assertTrue(self.result["styleAlphaPublished"])
        self.assertTrue(self.result["styleColorPublished"])
        self.assertTrue(self.result["styleFailurePreservesCurrent"])
        self.assertTrue(self.result["topologyRevisionStartsAtZero"])
        self.assertTrue(self.result["dynamicTopologyRevisionBumped"])
        self.assertTrue(self.result["dynamicValueKeepsTopologyRevision"])
        self.assertTrue(self.result["dynamicBeforeValueOrigin"])
        self.assertTrue(self.result["dynamicBeforeValueScale"])
        self.assertTrue(self.result["dynamicValueOriginPublished"])
        self.assertTrue(self.result["dynamicValueScalePublished"])
        self.assertTrue(self.result["authoredValueKeepsTopologyRevision"])


if __name__ == "__main__":
    unittest.main()
