#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .test_scene_prepared_script_resource_catalog import swift_declaration


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
)
SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    SCENE_SCRIPT.parent / "Particles/SceneParticlePlaybackModels.swift",
    SCENE_SCRIPT / "SceneScriptDynamicLayerRuntime+ParticlePlayback.swift",
    SCENE_SCRIPT / "SceneScriptLayerMutation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerTopologyModels.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime+Values.swift",
]

HARNESS = (Path(__file__).parent / "fixtures/SceneScriptDynamicLayerRuntimeHarness.swift").read_text(encoding="utf-8")
CAMERA_PROFILE = SCENE_SCRIPT.parent / "Properties/SceneDefault2DCameraInputProfile.swift"
TEXT_DESCRIPTOR = SCENE_SCRIPT.parent / "Text/SceneTextDescriptor.swift"
DECLARATION_SUPPORT = Path(__file__).parent / "test_scene_prepared_script_resource_catalog.py"

# Add behavior to the existing harness while leaving its shared fixture intact.
HARNESS = HARNESS.replace('let payload: [String: Any] = [', 'var payload: [String: Any] = [').replace(
    '        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])',
    '        payload["ownerCallbacks"] = callbackCoalescing()\n'
    '        payload["ownerCapacity"] = ownerCapacity()\n'
    '        payload["dynamicPreparedValues"] = dynamicPreparedValues()\n'
    '        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])')
HARNESS += r'''
extension Harness {
    static func callbackCoalescing() -> [String: Bool] {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 10, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], anglesXYZ: [0,0,0]),
            .init(id: 20, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], anglesXYZ: [0,0,0],
                contentKind: "text", text: "authored", textStyle: .init(fontPath: nil))],
            renderOrderLayerIDs: [10,20])
        let a = SceneDynamicTarget.layer(layerID: 10, field: .origin)
        let b = SceneDynamicTarget.layer(layerID: 20, field: .origin)
        let bad = SceneDynamicTarget.layer(layerID: 10, field: .angles)
        let peer = SceneDynamicTarget.layer(layerID: 20, field: .angles)
        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
        let effects = [
            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.2, fields: [.alpha, .scale], scale: .init(2,3,4), ownerTarget: a)]),
            SceneScriptOwnerEffects(ownerTarget: b, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.1, fields: [.alpha], ownerTarget: b),
                mutation(20, dynamic: false, text: "retained", fields: [.text], ownerTarget: b)]),
            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha, .visibility], visible: false, ownerTarget: a)]),
            SceneScriptOwnerEffects(ownerTarget: b, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha], ownerTarget: b)]),
            SceneScriptOwnerEffects(ownerTarget: bad, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.6, fields: [.alpha], ownerTarget: bad),
                mutation(20, dynamic: false, fields: [.visibility], visible: false, ownerTarget: bad)]),
            SceneScriptOwnerEffects(ownerTarget: bad, layerMutations: [
                mutation(10, dynamic: false, alpha: 0.8, fields: [.alpha], ownerTarget: bad)]),
            SceneScriptOwnerEffects(ownerTarget: peer, layerMutations: [
                mutation(20, dynamic: false, fields: [.scale], scale: .init(5,6,7), ownerTarget: peer)])]
        let admission = runtime.preflightOwnerEffects(effects)
        let readOnly = runtime.snapshot().authoredLayerValues.isEmpty
        runtime.commit(admission.layerPlan)
        let snapshot = runtime.snapshot()
        let rawRejected = [0.2, 0.6].allSatisfy { alpha in
            let raw = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
            let result = raw.apply([
                mutation(10, dynamic: false, alpha: 0.2, fields: [.alpha], ownerTarget: a),
                mutation(10, dynamic: false, alpha: alpha, fields: [.alpha], ownerTarget: a)])
            return !succeeded(result) && raw.snapshot().authoredLayerValues.isEmpty
        }
        let order = OrderInput()
        order.value = [10,-2,20,-1]
        let dynamic = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [],
            layerOrderProjection: { _ in .success(order.value) })
        let births = [mutation(-1, text: "seed", fields: [.created], origin: .init(1,2,3),
                              scale: .init(2,2,2), ownerTarget: a),
                      mutation(-2, text: "peer birth", fields: [.created], ownerTarget: a),
                      mutation(-3, text: "transient", fields: [.created], ownerTarget: a)]
        let birth = dynamic.preflightOwnerEffects([
            .init(ownerTarget: a, layerMutations: births),
            .init(ownerTarget: a, layerMutations: [
                mutation(-1, order: 2, text: "complete final", origin: .init(9,8,7), visible: false, ownerTarget: a),
                mutation(-3, kind: .destroy, ownerTarget: a),
                mutation(-3, text: "cannot resurrect", ownerTarget: a)])])
        let birthReadOnly = dynamic.snapshot().dynamicLayers.isEmpty
        dynamic.commit(birth.layerPlan)
        let born = dynamic.snapshot()
        let staleBirth = dynamic.preflightOwnerEffects([.init(ownerTarget: a, layerMutations: [births[0]])])
        order.value = [10,20]
        let retire = dynamic.preflightOwnerEffects([
            .init(ownerTarget: a, layerMutations: [mutation(-1, kind: .destroy, ownerTarget: a)]),
            .init(ownerTarget: a, layerMutations: [mutation(-2, kind: .destroy, ownerTarget: a)])])
        dynamic.commit(retire.layerPlan)
        let retired = dynamic.snapshot()
        let single = mutation(10, dynamic: false, fields: [.visibility], ownerTarget: a)
        // Owner batches commit at their first-authored position.
        let interleaved = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: [])
        let interleavedPlan = interleaved.preflightIsolatingOwners([
            mutation(10, dynamic: false, fields: [.origin], origin: .init(1, 0, 0), ownerTarget: a),
            mutation(10, dynamic: false, fields: [.origin], origin: .init(2, 0, 0), ownerTarget: b),
            mutation(10, dynamic: false, fields: [.origin], origin: .init(3, 0, 0), ownerTarget: a)])
        interleaved.commit(interleavedPlan)
        let interleavedOrigin = interleaved.snapshot().authoredLayerValues[
            .layer(layerID: 10, field: .origin)]
        return [
            "preflightReadOnly": readOnly && birthReadOnly,
            "lastCallbackWinsAndPreservesFields": snapshot.authoredLayerValues[.layer(layerID: 10, field: .alpha)] == .scalar(0.8)
                && snapshot.authoredLayerValues[.layer(layerID: 10, field: .scale)] == .vector3(2,3,4)
                && snapshot.authoredLayerValues[.layer(layerID: 10, field: .visibility)] == .bool(false),
            "allOwnersAdmitted": admission.admittedEffects.map(\.ownerTarget) == [a,b,a,b,bad,bad,peer]
                && snapshot.authoredLayerValues[.text(layerID: 20, field: .content)] == .string("retained"),
            "divergentOwnerCommitsLastValue": admission.rejectedOwners.isEmpty
                && snapshot.authoredLayerValues[.layer(layerID: 10, field: .alpha)] == .scalar(0.8)
                && snapshot.authoredLayerValues[.layer(layerID: 20, field: .visibility)] == .bool(false),
            "healthyPeerSurvives": snapshot.authoredLayerValues[.layer(layerID: 20, field: .scale)] == .vector3(5,6,7),
            "rawDuplicatesStillReject": rawRejected,
            "interleavedOwnerPlanAdmitted": interleavedPlan.outcome.failures.isEmpty,
            "ownerBatchesCommitAtFirstPosition": interleavedOrigin == .vector3(2, 0, 0),
            "emptyAndSingleInputUnchanged": SceneScriptLayerMutation.coalescing([]).isEmpty
                && SceneScriptLayerMutation.coalescing([single]) == [single],
            "dynamicUsesCompleteLatestRecord": birth.rejectedOwners.isEmpty
                && born.authoredLayerValues[.text(layerID: -1, field: .content)] == .string("complete final")
                && born.authoredLayerValues[.layer(layerID: -1, field: .origin)] == .vector3(9,8,7)
                && born.authoredLayerValues[.layer(layerID: -1, field: .scale)] == .vector3(1,1,1)
                && born.authoredLayerValues[.layer(layerID: -1, field: .visibility)] == .bool(false),
            "createdMarkerAndOrderSurvive": birth.layerPlan.dynamicLayerCreatorTargetsByID[-1] == a
                && Set(birth.layerPlan.createdDynamicLayerMutations.map(\.layerID)) == [-1,-2,-3]
                && born.renderOrderLayerIDs == [10,-2,20,-1],
            "destroyIsTerminalWithinOwner": born.dynamicLayers.map(\.id).sorted() == [-2,-1]
                && birth.layerPlan.dynamicLayerCreatorTargetsByID[-3] == nil,
            "newbornCannotReplaceCommittedLayer": staleBirth.rejectedOwners.map(\.ownerTarget) == [a],
            "retirementPreservesStableSnapshots": retire.rejectedOwners.isEmpty && retired.dynamicLayers.isEmpty
                && retired.renderOrderLayerIDs == [10,20] && born.dynamicLayers.count == 2
                && retired.topologyRevision > born.topologyRevision]
    }

    static func ownerCapacity() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (aID, peerID, field) in [(10, 20, SceneDynamicLayerField.origin), (73, 91, .angles)] {
            let descriptor = SceneRenderDescriptor(layers: [aID, peerID].map {
                .init(id: $0, visible: true, originXYZ: [0,0,0], scaleXYZ: [1,1,1], anglesXYZ: [0,0,0])
            }, renderOrderLayerIDs: [aID, peerID])
            let a = SceneDynamicTarget.layer(layerID: aID, field: field)
            let peer = SceneDynamicTarget.layer(layerID: peerID, field: field)
            let aValue = SceneDynamicTarget.layer(layerID: aID, field: .alpha)
            let peerValue = SceneDynamicTarget.layer(layerID: peerID, field: .alpha)
            for reversed in [false, true] {
                for count in [4096, 4097] {
                    for netZero in [false, true] {
                        var callbacks = (0..<count).map { _ in
                            mutation(netZero ? -aID : aID, dynamic: netZero, alpha: 0.3,
                                fields: [.alpha], ownerTarget: a)
                        }
                        if netZero {
                            callbacks[0] = mutation(-aID, fields: [.created], ownerTarget: a)
                            callbacks[count - 1] = mutation(-aID, kind: .destroy, ownerTarget: a)
                        }
                        let peerCallbacks = (0..<4).map { _ in
                            mutation(peerID, dynamic: false, alpha: 0.7, fields: [.alpha], ownerTarget: peer)
                        }
                        let split = count / 2
                        var effects = [
                            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: Array(callbacks[..<split])),
                            SceneScriptOwnerEffects(ownerTarget: peer, layerMutations: peerCallbacks),
                            SceneScriptOwnerEffects(ownerTarget: a, layerMutations: Array(callbacks[split...]))]
                        if reversed { effects = [effects[1], effects[0], effects[2]] }
                        let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
                        let admission = runtime.preflightOwnerEffects(effects)
                        let before = runtime.snapshot()
                        runtime.commit(admission.layerPlan)
                        let after = runtime.snapshot()
                        let raw = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [])
                        let publicOverflow = (0..<4097).map { _ in
                            mutation(aID, dynamic: false, alpha: 0.9, fields: [.alpha], ownerTarget: a)
                        }
                        let publicResult = raw.apply(publicOverflow)
                        let publicOverflowRejected: Bool
                        if case .failure(.mutationOverflow) = publicResult { publicOverflowRejected = true }
                        else { publicOverflowRejected = false }
                        rows.append([
                            "variant": "\(aID)-\(peerID)-\(field)", "reversed": reversed,
                            "rawCount": count, "peerRawCount": peerCallbacks.count, "netZero": netZero,
                            "coalescedCount": SceneScriptLayerMutation.coalescing(callbacks).count,
                            "preflightReadOnly": before.authoredLayerValues.isEmpty && before.dynamicLayers.isEmpty
                                && before.renderOrderLayerIDs == [aID, peerID],
                            "admittedA": admission.admittedEffects.contains { $0.ownerTarget == a },
                            "admittedPeer": admission.admittedEffects.contains { $0.ownerTarget == peer },
                            "rejectedA": admission.rejectedOwners.contains { $0.ownerTarget == a },
                            "rejectedPeer": admission.rejectedOwners.contains { $0.ownerTarget == peer },
                            "aOverflow": admission.rejectedOwners.contains {
                                guard $0.ownerTarget == a else { return false }
                                if case .mutationOverflow = $0.failure { return true }; return false
                            },
                            "committedCount": admission.layerPlan.outcome.committedMutationCount,
                            "aPublished": after.authoredLayerValues[aValue] == .scalar(0.3),
                            "peerPublished": after.authoredLayerValues[peerValue] == .scalar(0.7),
                            "dynamicCount": after.dynamicLayers.count,
                            "birthMarkers": admission.layerPlan.createdDynamicLayerMutations.count,
                            "publicRaw4097Rejected": publicOverflowRejected && raw.snapshot().authoredLayerValues.isEmpty])
                    }
                }
            }
        }
        return rows
    }

    static func dynamicPreparedValues() -> [[String: Bool]] {
        var rows: [[String: Bool]] = []
        for (textID, imageID, resource, font) in [
            (-501, -502, "models/tile.json", "fonts/next.ttf"),
            (-731, -917, "models/renamed/equivalent.json", "fonts/renamed/other.ttf")
        ] {
            let descriptor = SceneRenderDescriptor(layers: [
                .init(id: 10, visible: true, originXYZ: nil, scaleXYZ: nil, anglesXYZ: nil),
                .init(id: 20, visible: true, originXYZ: nil, scaleXYZ: nil, anglesXYZ: nil)
            ], renderOrderLayerIDs: [10, 20])
            let a = SceneDynamicTarget.layer(layerID: 10, field: .origin)
            let peer = SceneDynamicTarget.layer(layerID: 20, field: .origin)
            let runtime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [20],
                preparedResourceLayerTemplates: [resource: .init(modelPath: resource, renderSizeWH: [4,4])])
            let textCalls = LayerFactoryCalls.text, resourceCalls = LayerFactoryCalls.resource
            let birth = runtime.apply([
                mutation(textID, alpha: 0.75, text: "seed", font: " \tfonts/seed.ttf\n ", fields: [.created],
                    origin: .init(1,2,3), scale: .init(2,3,4), color: .init(0.25,0.5,0.75), ownerTarget: a),
                mutation(imageID, fields: [.created], assetPath: resource, color: .init(0.25,0.5,0.75), ownerTarget: a)
            ])
            let born = runtime.snapshot()
            let schema = runtime.authoredDefinitionRevision
            let definitions = Dictionary(uniqueKeysWithValues: runtime.authoredLayerDefinitions.map { ($0.target, $0) })
            let required: Set<SceneDynamicTarget> = Set([textID, imageID].flatMap { id in
                [SceneDynamicLayerField.origin, .scale, .angles, .visibility, .solid, .alpha, .color].map {
                    SceneDynamicTarget.layer(layerID: id, field: $0)
                }
            } + [SceneDynamicTextField.content, .font, .color, .pointSize].map {
                SceneDynamicTarget.text(layerID: textID, field: $0)
            })
            let preparedOnce = LayerFactoryCalls.text == textCalls + 1
                && LayerFactoryCalls.resource == resourceCalls + 1
            let rawPointSize = runtime.apply([
                mutation(textID, alpha: 0.75, text: "seed", font: "fonts/seed.ttf", fields: [.pointSize],
                    origin: .init(1,2,3), scale: .init(2,3,4), color: .init(0.25,0.5,0.75),
                    ownerTarget: a, pointSize: .greatestFiniteMagnitude)
            ])
            let rawSizeSnapshot = runtime.snapshot()
            let update = runtime.apply([
                mutation(textID, alpha: -3, text: "", font: " \t\(font)\n ",
                    origin: .init(9,8,7), scale: .init(5,4,3), angles: .init(6,5,4), visible: false,
                    color: .init(0.8,0.4,0.2), ownerTarget: a, solid: false, pointSize: .greatestFiniteMagnitude),
                mutation(imageID, alpha: 2.5, origin: .init(3,4,5), visible: false,
                    assetPath: resource, color: .init(0.8,0.4,0.2), ownerTarget: a)
            ])
            let current = runtime.snapshot()
            let bornText = born.dynamicLayers.first { $0.id == textID }
            let currentText = current.dynamicLayers.first { $0.id == textID }
            let bornImage = born.dynamicLayers.first { $0.id == imageID }
            let currentImage = current.dynamicLayers.first { $0.id == imageID }
            var facts: [String: Bool] = [
                "birthAndFullRecordAccepted": succeeded(birth) && succeeded(update),
                "birthPreparesFactoriesOnce": preparedOnce,
                "valueUpsertDoesNotPrepare": LayerFactoryCalls.text == textCalls + 1
                    && LayerFactoryCalls.resource == resourceCalls + 1,
                "allRuntimeDefinitionsExistBeforeFirstWrite": required.isSubset(of: Set(definitions.keys)),
                "definitionsKeepBirthSeeds": definitions[.text(layerID: textID, field: .content)]?.authoredValue == .string("seed")
                    && definitions[.text(layerID: textID, field: .font)]?.authoredValue == .string("fonts/seed.ttf")
                    && definitions[.text(layerID: textID, field: .pointSize)]?.authoredValue == .scalar(32)
                    && definitions[.layer(layerID: textID, field: .alpha)]?.authoredValue == .scalar(0.75),
                "completeRecordTransforms": current.authoredLayerValues[.layer(layerID: textID, field: .origin)] == .vector3(9,8,7)
                    && current.authoredLayerValues[.layer(layerID: textID, field: .scale)] == .vector3(5,4,3)
                    && current.authoredLayerValues[.layer(layerID: textID, field: .angles)] == .vector3(6,5,4),
                "completeRecordVisibilitySolidAndRawAlpha": current.authoredLayerValues[.layer(layerID: textID, field: .visibility)] == .bool(false)
                    && current.authoredLayerValues[.layer(layerID: textID, field: .solid)] == .bool(false)
                    && current.authoredLayerValues[.layer(layerID: textID, field: .alpha)] == .scalar(-3)
                    && current.authoredLayerValues[.layer(layerID: imageID, field: .alpha)] == .scalar(2.5),
                "bothTextColorConsumersAndImageTint": current.authoredLayerValues[.layer(layerID: textID, field: .color)] == .vector3(0.8,0.4,0.2)
                    && current.authoredLayerValues[.text(layerID: textID, field: .color)] == .vector3(0.8,0.4,0.2)
                    && current.authoredLayerValues[.layer(layerID: imageID, field: .color)] == .vector3(0.8,0.4,0.2),
                "emptyTextNonemptyFontAndRawPointSize": current.authoredLayerValues[.text(layerID: textID, field: .content)] == .string("")
                    && current.authoredLayerValues[.text(layerID: textID, field: .font)] == .string(font)
                    && current.authoredLayerValues[.text(layerID: textID, field: .pointSize)] == .scalar(.greatestFiniteMagnitude),
                "explicitPointSizeThenUnflaggedRecordKeepsRaw": succeeded(rawPointSize)
                    && rawSizeSnapshot.authoredLayerValues[.text(layerID: textID, field: .pointSize)] == .scalar(.greatestFiniteMagnitude),
                "nilPerspectiveKeepsCameraDefault": current.authoredLayerValues[.layer(layerID: textID, field: .perspective)] == nil
                    && currentText?.usesPerspective == nil,
                "capturedSnapshotKeepsItsOwnValues": born.authoredLayerValues[.text(layerID: textID, field: .content)] == .string("seed")
                    && born.authoredLayerValues[.layer(layerID: textID, field: .origin)] == .vector3(1,2,3)
                    && born.authoredLayerValues[.layer(layerID: imageID, field: .color)] == .vector3(0.25,0.5,0.75),
                "birthLayersRemainPreparedFacts": bornText?.text == "seed" && currentText?.text == "seed"
                    && currentText?.originXYZ == [1,2,3] && currentText?.textStyle?.fontPath == "fonts/seed.ttf"
                    && currentText?.textStyle?.pointSize == 32
                    && bornImage?.colorRGB == currentImage?.colorRGB && currentImage?.imagePath == resource,
                "valueUpdatesKeepSchemaAndTopology": runtime.authoredDefinitionRevision == schema
                    && current.topologyRevision == born.topologyRevision
                    && current.renderOrderLayerIDs == born.renderOrderLayerIDs
            ]
            for field in [SceneDynamicLayerField.origin, .scale, .angles] {
                let overflow = SIMD3<Double>(Double.greatestFiniteMagnitude, 0, 0)
                let before = runtime.snapshot()
                let admission = runtime.preflightOwnerEffects([
                    .init(ownerTarget: a, layerMutations: [
                        mutation(textID, text: "must-not-publish", ownerTarget: a),
                        mutation(imageID, origin: field == .origin ? overflow : .zero,
                            scale: field == .scale ? overflow : .init(repeating: 1),
                            angles: field == .angles ? overflow : .zero, assetPath: resource, ownerTarget: a)]),
                    .init(ownerTarget: peer, layerMutations: [
                        mutation(20, dynamic: false, fields: [.scale], scale: .init(7,8,9), ownerTarget: peer)])
                ])
                let readOnly = runtime.snapshot().authoredLayerValues == before.authoredLayerValues
                runtime.commit(admission.layerPlan)
                var expected = before.authoredLayerValues
                expected[.layer(layerID: 20, field: .scale)] = .vector3(7,8,9)
                facts["\(field)OverflowRejectsWholeOwnerAndKeepsPeer"] = readOnly
                    && admission.rejectedOwners.map(\.ownerTarget) == [a]
                    && admission.admittedEffects.map(\.ownerTarget) == [peer]
                    && runtime.snapshot().authoredLayerValues == expected
                    && current.authoredLayerValues[.text(layerID: textID, field: .content)] == .string("")
                    && runtime.topologyRevision == born.topologyRevision
                    && runtime.authoredDefinitionRevision == schema
            }
            let equivalentFont = runtime.apply([mutation(textID, font: font)])
            let equivalentSnapshot = runtime.snapshot()
            let blankFont = runtime.apply([mutation(textID, font: " \t\n ")])
            let blankSnapshot = runtime.snapshot()
            facts["outerWhitespaceAndCanonicalFontsAreEquivalent"] = succeeded(equivalentFont)
                && equivalentSnapshot.authoredLayerValues[.text(layerID: textID, field: .font)] == .string(font)
                && current.authoredLayerValues[.text(layerID: textID, field: .font)] == .string(font)
            facts["nonemptyWhitespaceFontPublishesEmptyMarkerWithoutChangingBirth"] = succeeded(blankFont)
                && blankSnapshot.authoredLayerValues[.text(layerID: textID, field: .font)] == .string("")
                && born.authoredLayerValues[.text(layerID: textID, field: .font)] == .string("fonts/seed.ttf")
                && blankSnapshot.dynamicLayers.first { $0.id == textID }?.textStyle?.fontPath == "fonts/seed.ttf"
                && runtime.authoredDefinitionRevision == schema
                && blankSnapshot.topologyRevision == born.topologyRevision
            facts["rejectedUpdatesDoNotPrepareFactories"] = LayerFactoryCalls.text == textCalls + 1
                && LayerFactoryCalls.resource == resourceCalls + 1
            rows.append(facts)
        }
        return rows
    }
}
'''


def camera_numeric_leaf() -> str:
    """Compile the unchanged real numeric owner, without the unrelated parser DTOs.

    This tiny gate tests runtime transactions. The camera-input gate links the
    complete Profile and real parser; this projection cannot replace that gate.
    """
    source = CAMERA_PROFILE.read_text(encoding="utf-8")
    constants = re.findall(r"(?m)^    static let maximumOriginMagnitude = [^\n]+", source)
    signatures = list(re.finditer(
        r"    static func acceptsOrigin\(_ values: \[Double\], nearZ: Double, farZ: Double\) -> Bool \{",
        source))
    if len(constants) != 1 or len(signatures) != 1:
        raise AssertionError("camera numeric owner missing or ambiguous")
    start = signatures[0].start()
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise AssertionError("camera numeric owner is incomplete")
    return ("nonisolated enum SceneDefault2DCameraInputProfile {\n"
            + constants[0] + "\n" + source[start:end] + "\n}\n")


def font_path_leaf() -> str:
    return ("nonisolated enum SceneTextDescriptor {\n"
            + swift_declaration(TEXT_DESCRIPTOR.read_text(encoding="utf-8"),
                                "    nonisolated static func normalizedPath(")
            + "\n}\n")


class SceneScriptDynamicLayerRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-dynamic-layer-"
        )
        directory = Path(cls.temporary_directory.name)
        inputs = [*SOURCES, CAMERA_PROFILE, TEXT_DESCRIPTOR, DECLARATION_SUPPORT,
                  Path(__file__), Path(__file__).parent / "fixtures/SceneScriptDynamicLayerRuntimeHarness.swift",
                  *SCENE_SCRIPT.rglob("*.h")]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        frozen = directory / "source"
        for source in inputs:
            target = frozen / source.relative_to(REPOSITORY_ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS + "\n" + camera_numeric_leaf() + "\n" + font_path_leaf(), encoding="utf-8")
        binary = directory / "dynamic-layer-runtime"
        compilation = subprocess.run(
            ["swiftc", "-import-objc-header", str(frozen / (SCENE_SCRIPT / "SceneQuickJS.h").relative_to(REPOSITORY_ROOT)),
             *(str(frozen / p.relative_to(REPOSITORY_ROOT)) for p in SOURCES),
             str(harness), "-o", str(binary)],
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
        drift = [str(p) for p in inputs if hashlib.sha256(p.read_bytes()).hexdigest() != before[str(p)]]
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        if proof:
            output = Path(proof)
            output.mkdir(parents=True, exist_ok=True)
            (output / "runtime-input-freeze.json").write_text(json.dumps(before, indent=2) + "\n")
            (output / "runtime-result.json").write_text(json.dumps(cls.result, indent=2) + "\n")
            (output / "runtime-execution.json").write_text(json.dumps({
                "compiledFromFrozenCopy": True, "inputDrift": drift,
                "profileNumericLeafOnly": True,
                "fontPathProductionLeafOnly": True,
            }, indent=2) + "\n")
        if drift:
            raise AssertionError(f"focused input drift: {drift}")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_ordered_owner_callbacks_coalesce_before_conflict_admission(self) -> None:
        for behavior, passed in self.result["ownerCallbacks"].items():
            self.assertTrue(passed, behavior)

    def test_owner_raw_capacity_is_local_before_callback_coalescing(self) -> None:
        for row in self.result["ownerCapacity"]:
            with self.subTest(variant=row["variant"], reversed=row["reversed"],
                              raw_count=row["rawCount"], net_zero=row["netZero"]):
                within_capacity = row["rawCount"] == 4096
                expected = {
                    "peerRawCount": 4, "coalescedCount": 1, "preflightReadOnly": True,
                    "admittedA": within_capacity, "admittedPeer": True,
                    "rejectedA": not within_capacity, "rejectedPeer": False,
                    "aOverflow": not within_capacity, "committedCount": 2 if within_capacity else 1,
                    "aPublished": within_capacity and not row["netZero"], "peerPublished": True,
                    "dynamicCount": 0, "birthMarkers": int(within_capacity and row["netZero"]),
                    "publicRaw4097Rejected": True,
                }
                for fact, value in expected.items():
                    with self.subTest(fact=fact):
                        self.assertEqual(row[fact], value)
        for behavior, passed in self.result["ownerCallbacks"].items():
            with self.subTest(existing_callback_behavior=behavior):
                self.assertTrue(passed)

    def test_perspective_is_typed_atomic_and_rejects_missing_consumers_locally(self) -> None:
        for key in ("perspectivePreflightReadOnly", "perspectiveImageTextAccepted",
                    "perspectiveFalseAndMissingBool", "perspectiveValueChangeKeepsSchemaAndTopology",
                    "perspectiveUnsupportedIsLocal"):
            self.assertTrue(self.result[key], key)

    def test_prepared_text_birth_projection_and_cascade_use_committed_membership(self) -> None:
        for key in ("templateBirthReadOnly", "templateBirthSeparatesSeedAndInit",
                    "templateUserAliasOnlyPreparedUser", "templateUserBoundsAreTargetLocal", "templateMirrorUsesLiveMembership",
                    "templateUnknownOrMissingRejectLocally", "templateExplicitSetterPublished",
                    "templateCreatorCascadeRetiresDescendants", "templateCascadeReleasesValuesDefinitionsAndAliases"):
            self.assertTrue(self.result[key], key)

    def test_unpublished_parent_still_retires_its_live_creator_descendants(self) -> None:
        self.assertTrue(self.result["transientCreatorClosureReadOnly"])
        self.assertTrue(self.result["transientCreatorClosureRetiresDescendants"])

    def test_create_and_value_update_publish_only_through_snapshots(self) -> None:
        self.assertTrue(self.result["createSucceeded"])
        self.assertTrue(self.result["priorSnapshotStable"])
        self.assertEqual(self.result["createdIDs"], [-1])
        self.assertTrue(self.result["moveSucceeded"])

    def test_static_transform_mutation_and_failed_batch_are_atomic(self) -> None:
        self.assertTrue(self.result["staticAccepted"])
        self.assertTrue(self.result["staticAnglesPublished"])
        self.assertTrue(self.result["staticVisibilityPublished"])
        self.assertTrue(self.result["peerUpdateAccepted"])
        self.assertTrue(self.result["peerScalePublished"])
        self.assertTrue(self.result["peerTextPublished"])
        self.assertTrue(self.result["peerFontPublished"])
        self.assertEqual(self.result["authoredDefinitionCount"], 12)
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

    def test_identical_duplicate_owner_writes_coalesce_and_later_owner_wins(self) -> None:
        self.assertTrue(self.result["identicalDuplicateOwnersAdmitted"])
        self.assertTrue(self.result["identicalDuplicateValuePublished"])
        self.assertTrue(self.result["laterOwnerWins"])
        self.assertTrue(self.result["laterOwnerValuePublished"])

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

    def test_dynamic_image_preserves_its_own_color_in_stable_snapshots(self) -> None:
        self.assertTrue(self.result["dynamicImageSucceeded"])
        self.assertTrue(self.result["dynamicImageColor"])
        self.assertTrue(self.result["dynamicImageUpdateSucceeded"])
        self.assertTrue(self.result["dynamicImageUpdatedColor"])

    def test_dynamic_birth_facts_and_typed_current_values_have_separate_lifetimes(self) -> None:
        self.assertEqual(len(self.result["dynamicPreparedValues"]), 2)
        for variant, facts in enumerate(self.result["dynamicPreparedValues"]):
            for fact, passed in facts.items():
                with self.subTest(variant=variant, fact=fact):
                    self.assertTrue(passed)

    def test_admitted_play_releases_setter_without_losing_rejected_or_paused_values(self) -> None:
        for key in (
            "replayCandidateIsReadOnly",
            "replayReleasesOnlyTargetIncludingImmediatePauseStop",
            "pausedSetterWithoutPlayIsRetained",
            "externallyRejectedPlayPreservesSetter",
            "invalidOwnerPlayPreservesSetter",
            "replayCommitKeepsSchemaAndPeer",
        ):
            with self.subTest(key=key):
                self.assertTrue(self.result[key])

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
        self.assertTrue(self.result["dynamicBirthLayerUnchanged"])
        self.assertTrue(self.result["authoredValueKeepsTopologyRevision"])


if __name__ == "__main__":
    unittest.main()
