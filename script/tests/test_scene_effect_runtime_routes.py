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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Effects/SceneFoliageSwayRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneGradientColorRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneInlineEffectRuntime.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeSupport.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimeModel.swift",
    SOURCE_ROOT / "Effects/SceneEffectRuntimePlan.swift",
    SOURCE_ROOT / "Effects/SceneEffectStageRuntimeDisposition.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision+Inline.swift",
    SOURCE_ROOT / "Runtime/SceneEffectExecutionFrameTrace.swift",
    SOURCE_ROOT / "Runtime/SceneEffectExecutionTelemetry.swift",
    SOURCE_ROOT / "Effects/SceneLegacyEffectPlanningDecision+Execution.swift",
    SOURCE_ROOT / "Runtime/SceneEffectRuntimeDispositionCatalog.swift",
]

HARNESS = r'''
import Foundation
import simd

struct SceneDocument {
    struct ShaderValue {
        let components: [Double]?
    }
}

enum SceneGaussianBlurKernel {
    case large
}

struct SceneStandardBlurPlan {}
struct ScenePerspectiveOpacityPlan {
    let edges: SIMD4<Float>
    let weights: SIMD4<Float>
    let opacity: Float
}

struct Marker {}
struct SceneAuthoredEffectExecutionPlan {
    let materialNodeCount: Int = 0
    let gaussianBlur: SceneGaussianBlurPlan? = nil
    let standardBlur: SceneStandardBlurPlan? = nil
    let localContrast: Marker? = nil
    let opacity: Marker? = nil
    let waterWaves: Marker? = nil
    let cursorRipple: Marker? = nil
    let workshopAudioBars: Marker? = nil
    let authoredShader: Marker? = nil
    let blend: Marker? = nil
    let depthParallax: Marker? = nil
    let clippingMask: Marker? = nil
}

struct SceneEffectFlags: OptionSet {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }
    static let foliagesway = SceneEffectFlags(rawValue: 1 << 0)
    static let waterwaves = SceneEffectFlags(rawValue: 1 << 1)
    static let chromaticaberration = SceneEffectFlags(rawValue: 1 << 3)
    static let irisMask = SceneEffectFlags(rawValue: 1 << 4)
    static let opacityMask = SceneEffectFlags(rawValue: 1 << 5)
    static let hasWaterMask = SceneEffectFlags(rawValue: 1 << 6)
    static let hasFoliageMask = SceneEffectFlags(rawValue: 1 << 9)
}

struct SceneRenderDescriptor {
    let layers: [Layer]

    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [String?]
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
        let effects: [EffectDescriptor]
        let colorBlendMode: Int?
    }
}

struct SceneAuthoredEffectStageAdmission {
    enum Activity: String {
        case authorDisabled = "author-disabled"
        case layerHidden = "layer-hidden"
        case active
    }
    enum StrictAdmission {
        case inactive
        case admittedDedicated
        case admittedGeneric
        case notAdmitted
    }
    enum Coverage {
        case inactive
        case complete
        case terminalInlineSuffix
        case prefixOmitted
    }
    let key: SceneAuthoredEffectRenderPlan.EffectKey
    let definitionPath: String
    let activity: Activity
    let strictAdmission: StrictAdmission
    let coverage: Coverage
    let backendName: String?
    let profileName: String?
    let reasonCode: String?
}

struct SceneAuthoredEffectExecutionCatalog {
    let stageAdmissions: [SceneAuthoredEffectStageAdmission]
    let chainsByLayerID: [Int: Marker]
    let legacyGaussianBlurBlockedLayerIDs: Set<Int>
    let descriptorEffectStageCount: Int
    let descriptorEffectStageKeys: Set<SceneAuthoredEffectRenderPlan.EffectKey>
}

nonisolated final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@main
enum Harness {
    static func main() throws {
        let bloomBlur = decision(layer(
            1,
            effect("blur", "effects/blur/effect.json", passes: 3),
            effect("precise", "effects/blurprecise/effect.json", passes: 2),
            effect("motion", "effects/motionblur/effect.json", passes: 2),
            effect("bloom", "effects/bloom/effect.json")
        ))
        let routeOnly = decision(layer(
            2,
            effect("two", "effects/custom/two/effect.json", passes: 2),
            effect("one", "effects/custom/one/effect.json")
        ))
        let compositeRefused = decision(layer(
            3,
            effect("flow", "effects/waterflow/effect.json"),
            effect("ripple", "effects/waterripple/effect.json"),
            effect("perspective", "effects/perspective/effect.json"),
            effect("opacity", "effects/opacity/effect.json")
        ))
        let coalesced = decision(
            layer(
                4,
                effect("chromatic-a", "effects/chromaticaberration/effect.json"),
                effect("chromatic-b", "effects/chromatic_aberration/effect.json"),
                effect("iris-a", "effects/iris/effect.json"),
                effect("iris-b", "effects/iris/effect.json")
            ),
            resources: .init(
                hasIrisMask: true,
                hasOpacityMask: false,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: false
            )
        )
        let irisOpacityPriority = decision(
            layer(
                8,
                effect("iris-priority", "effects/iris/effect.json"),
                effect("opacity-shadowed", "effects/opacity/effect.json")
            ),
            resources: .init(
                hasIrisMask: true,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: false
            )
        )
        let ripplePerspective = decision(
            layer(
                9,
                effect(
                    "ripple-normal",
                    "effects/waterripple/effect.json",
                    slots: [nil, nil, "normal-map"]
                ),
                effect("perspective", "effects/perspective/effect.json"),
                effect("opacity", "effects/opacity/effect.json")
            ),
            resources: .init(
                hasIrisMask: false,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: true
            )
        )
        let irisPriorityComposite = decision(
            layer(
                10,
                effect("flow", "effects/waterflow/effect.json"),
                effect("ripple", "effects/waterripple/effect.json"),
                effect("perspective", "effects/perspective/effect.json"),
                effect("opacity", "effects/opacity/effect.json"),
                effect("iris", "effects/iris/effect.json")
            ),
            resources: .init(
                hasIrisMask: true,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: false
            )
        )
        let opacityCompositeExecutable = decision(
            layer(
                11,
                effect("flow", "effects/waterflow/effect.json"),
                effect("ripple", "effects/waterripple/effect.json"),
                effect("perspective", "effects/perspective/effect.json"),
                effect("opacity", "effects/opacity/effect.json")
            ),
            resources: .init(
                hasIrisMask: false,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: false
            )
        )
        let opacityBeforePerspective = decision(
            layer(
                12,
                effect("flow", "effects/waterflow/effect.json"),
                effect("ripple", "effects/waterripple/effect.json"),
                effect("opacity", "effects/opacity/effect.json"),
                effect("perspective", "effects/perspective/effect.json")
            ),
            resources: .init(
                hasIrisMask: false,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: false
            )
        )
        let waterParameterWriters = decision(
            layer(
                14,
                effect(
                    "ripple-trigger",
                    "effects/waterripple/effect.json",
                    values: ["scale": [1]]
                ),
                effect(
                    "waves-last-parameters",
                    "effects/waterwaves/effect.json",
                    values: ["scale": [9]]
                )
            )
        )
        let ambiguousNormalResource = decision(
            layer(
                15,
                effect(
                    "normal-parameters-first",
                    "effects/waterripple/effect.json",
                    slots: [nil, nil, "normal-a"]
                ),
                effect(
                    "normal-resource-candidate",
                    "effects/waterripple/effect.json",
                    slots: [nil, nil, "normal-b"]
                )
            ),
            resources: .init(
                hasIrisMask: false,
                hasOpacityMask: false,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: true
            )
        )
        let blockedBlur = decision(
            layer(16, effect("blocked-blur", "effects/blur/effect.json", passes: 2)),
            blocksLegacyGaussianBlur: true
        )
        let duplicateDescriptorIDs = decision(
            layer(
                17,
                effect("duplicate", "effects/chromaticaberration/effect.json"),
                effect("duplicate", "effects/chromatic_aberration/effect.json")
            )
        )
        let exact = layer(
            5,
            effect("coarse", "effects/blur/effect.json", passes: 3),
            effect("precise", "effects/blurprecise/effect.json", passes: 2),
            effect("foliage", "effects/foliagesway/effect.json")
        )
        let foliage = SceneFoliageSwayRuntimePlanner.selection(
            for: exact,
            hasMask: false
        )
        let gaussian = SceneGaussianBlurRuntimePlanner.selection(for: exact)
        let gradientLayer = layer(
            6,
            gradient("gradient"),
            effect("clip", "effects/clipping_mask/effect.json")
        )
        let gradient = SceneGradientColorRuntimePlanner.selection(for: gradientLayer)
        let gradientDecision = decision(gradientLayer)
        let strict = strictCatalog()
        let executionLogs = executionContractLogs()

        let payload: [String: Any] = [
            "bloomBlur": bloomBlur,
            "routeOnly": routeOnly,
            "compositeRefused": compositeRefused,
            "coalesced": coalesced,
            "irisOpacityPriority": irisOpacityPriority,
            "ripplePerspective": ripplePerspective,
            "irisPriorityComposite": irisPriorityComposite,
            "opacityCompositeExecutable": opacityCompositeExecutable,
            "opacityBeforePerspective": opacityBeforePerspective,
            "waterParameterWriters": waterParameterWriters,
            "ambiguousNormalResource": ambiguousNormalResource,
            "blockedBlur": blockedBlur,
            "duplicateDescriptorIDs": duplicateDescriptorIDs,
            "strict": strict,
            "selection": [
                "foliage": foliage?.effectIndex as Any,
                "gaussian": gaussian?.effectIndex as Any,
                "gaussianPrecise": gaussian?.plan.isPrecise as Any,
                "gradient": gradient?.effectIndices as Any,
            ],
            "gradientDecision": gradientDecision,
            "executionLogs": executionLogs,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }

    static func executionContractLogs() -> [String] {
        let collector = LogCollector()
        let telemetry = SceneEffectExecutionTelemetry { collector.append($0) }

        let exactInline = planningDecision(layer(
            21,
            effect("unsupported-before-owner", "effects/custom/effect.json"),
            effect("exact-inline-owner", "effects/foliagesway/effect.json")
        ))
        let exactTrace = telemetry.makeFrame(frameIndex: 101)
        exactInline.recordInlineExecution(
            trace: exactTrace,
            origin: .image,
            backend: "legacy-inline-exact",
            outcome: .failed(reasonCode: "pipeline-missing")
        )
        exactInline.recordInlineExecution(
            trace: exactTrace,
            origin: .image,
            backend: "legacy-inline-exact",
            outcome: .encodedOutput
        )
        exactInline.recordInlineExecution(
            trace: exactTrace,
            origin: .image,
            backend: "legacy-inline-exact",
            outcome: .encodedOutput
        )

        let coalescedInline = planningDecision(layer(
            22,
            effect("ripple-contributor", "effects/waterripple/effect.json"),
            effect("waves-contributor", "effects/waterwaves/effect.json")
        ))
        coalescedInline.recordInlineExecution(
            trace: telemetry.makeFrame(frameIndex: 102),
            origin: .solid,
            backend: "legacy-inline-coalesced",
            outcome: .encodedOutput
        )

        let selectedOffscreen = planningDecision(
            layer(
                23,
                effect(
                    "normal-owner",
                    "effects/waterripple/effect.json",
                    slots: [nil, nil, "normal-map"]
                ),
                effect("perspective-contributor", "effects/perspective/effect.json"),
                effect("opacity-contributor", "effects/opacity/effect.json")
            ),
            resources: .init(
                hasIrisMask: false,
                hasOpacityMask: true,
                hasWaterMask: false,
                hasFoliageMask: false,
                hasWaterRippleNormal: true
            )
        )
        selectedOffscreen.recordOffscreenExecution(
            family: "water-ripple-normal",
            trace: telemetry.makeFrame(frameIndex: 103),
            origin: .text,
            backend: "legacy-offscreen-water",
            outcome: .encodedOutput
        )
        selectedOffscreen.recordOffscreenExecution(
            family: "perspective-opacity",
            trace: telemetry.makeFrame(frameIndex: 104),
            origin: .text,
            backend: "legacy-offscreen-perspective",
            outcome: .encodedOutput
        )

        let structural = planningDecision(layer(
            24,
            gradient("gradient-owner"),
            effect("structural-clip", "effects/clipping_mask/effect.json")
        ))
        structural.recordOffscreenExecution(
            family: "gradient-color",
            trace: telemetry.makeFrame(frameIndex: 105),
            origin: .utilityComposition,
            backend: "legacy-offscreen-structural-filter",
            outcome: .encodedOutput
        )

        let shadowed = planningDecision(layer(
            25,
            effect("shadowed-blur", "effects/blur/effect.json", passes: 2),
            effect("selected-bloom", "effects/bloom/effect.json")
        ))
        shadowed.recordOffscreenExecution(
            family: "gaussian-blur",
            trace: telemetry.makeFrame(frameIndex: 106),
            origin: .utilityProject,
            backend: "ignored-shadowed",
            outcome: .encodedOutput
        )

        let unsupported = planningDecision(layer(
            26,
            effect("unsupported-only", "effects/custom/effect.json")
        ))
        unsupported.recordInlineExecution(
            trace: telemetry.makeFrame(frameIndex: 107),
            origin: .utilityFullscreen,
            backend: "ignored-unsupported",
            outcome: .encodedOutput
        )

        return collector.snapshot()
    }

    static func planningDecision(
        _ layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability = .none,
        blocksLegacyGaussianBlur: Bool = false
    ) -> SceneLegacyEffectPlanningDecision {
        SceneEffectRuntimePlanner.legacyPlanningDecision(
            for: layer,
            resources: resources,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        )
    }

    static func decision(
        _ layer: SceneRenderDescriptor.Layer,
        resources: SceneLegacyEffectResourceAvailability = .none,
        blocksLegacyGaussianBlur: Bool = false
    ) -> [String: Any] {
        let result = SceneEffectRuntimePlanner.legacyPlanningDecision(
            for: layer,
            resources: resources,
            blocksLegacyGaussianBlur: blocksLegacyGaussianBlur
        )
        return [
            "group": result.routeGroup.kind.rawValue,
            "effects": result.routeGroup.effectKeys.count,
            "owners": result.routeGroup.ownerKeys.map(\.descriptorID),
            "aggregate": result.routeGroup.aggregateContributorKeys.map(\.descriptorID),
            "skipsComposite": result.runtimePlan.skipsUnsupportedComposite,
            "offscreenPasses": result.runtimePlan.offscreenPassCount,
            "waterScale": result.runtimePlan.inputs.params2.x,
            "records": result.dispositions.map { disposition in
                [
                    "index": disposition.key.effectIndex,
                    "id": disposition.key.descriptorID,
                    "kind": disposition.kind.rawValue,
                    "attribution": disposition.attribution.rawValue,
                    "family": disposition.family ?? "-",
                    "role": disposition.routeRole.rawValue,
                    "reason": disposition.reasonCode ?? "-",
                ] as [String: Any]
            },
        ]
    }

    static func layer(
        _ id: Int,
        _ effects: SceneRenderDescriptor.EffectDescriptor...
    ) -> SceneRenderDescriptor.Layer {
        .init(id: id, effects: effects, colorBlendMode: 0)
    }

    static func strictCatalog() -> [String: Any] {
        let strictLayer = layer(
            7,
            effect("generic", "effects/scroll/effect.json"),
            effect("iris", "effects/iris/effect.json"),
            effect("disabled", "effects/blur/effect.json", visible: false)
        )
        let prefixLayer = layer(
            13,
            effect("xray", "effects/xray/effect.json"),
            effect("prefix-omitted-a", "effects/tint/effect.json"),
            effect("prefix-omitted-b", "effects/twirl/effect.json")
        )
        let inactiveLayer = layer(
            18,
            effect("inactive-only", "effects/blur/effect.json", visible: false)
        )
        let migratedLayer = layer(
            19,
            effect("migrated", "effects/custom/material/effect.json")
        )
        let strictKeys = strictLayer.effects.enumerated().map { index, effect in
            SceneAuthoredEffectRenderPlan.EffectKey(
                layerID: strictLayer.id,
                effectIndex: index,
                descriptorID: effect.id
            )
        }
        let prefixKeys = prefixLayer.effects.enumerated().map { index, effect in
            SceneAuthoredEffectRenderPlan.EffectKey(
                layerID: prefixLayer.id,
                effectIndex: index,
                descriptorID: effect.id
            )
        }
        let inactiveKeys = inactiveLayer.effects.enumerated().map { index, effect in
            SceneAuthoredEffectRenderPlan.EffectKey(
                layerID: inactiveLayer.id,
                effectIndex: index,
                descriptorID: effect.id
            )
        }
        let migratedKey = SceneAuthoredEffectRenderPlan.EffectKey(
            layerID: migratedLayer.id,
            effectIndex: 0,
            descriptorID: migratedLayer.effects[0].id
        )
        let admissions = [
            SceneAuthoredEffectStageAdmission(
                key: strictKeys[0],
                definitionPath: strictLayer.effects[0].file,
                activity: .active,
                strictAdmission: .admittedGeneric,
                coverage: .complete,
                backendName: "authored-shader",
                profileName: "scroll",
                reasonCode: nil
            ),
            SceneAuthoredEffectStageAdmission(
                key: strictKeys[1],
                definitionPath: strictLayer.effects[1].file,
                activity: .active,
                strictAdmission: .notAdmitted,
                coverage: .terminalInlineSuffix,
                backendName: nil,
                profileName: nil,
                reasonCode: "terminal-inline-suffix"
            ),
            SceneAuthoredEffectStageAdmission(
                key: strictKeys[2],
                definitionPath: strictLayer.effects[2].file,
                activity: .authorDisabled,
                strictAdmission: .inactive,
                coverage: .inactive,
                backendName: nil,
                profileName: nil,
                reasonCode: nil
            ),
            SceneAuthoredEffectStageAdmission(
                key: prefixKeys[0],
                definitionPath: prefixLayer.effects[0].file,
                activity: .active,
                strictAdmission: .admittedDedicated,
                coverage: .complete,
                backendName: "xray",
                profileName: nil,
                reasonCode: nil
            ),
            SceneAuthoredEffectStageAdmission(
                key: prefixKeys[1],
                definitionPath: prefixLayer.effects[1].file,
                activity: .active,
                strictAdmission: .notAdmitted,
                coverage: .prefixOmitted,
                backendName: nil,
                profileName: nil,
                reasonCode: "prefix-omitted"
            ),
            SceneAuthoredEffectStageAdmission(
                key: prefixKeys[2],
                definitionPath: prefixLayer.effects[2].file,
                activity: .active,
                strictAdmission: .notAdmitted,
                coverage: .prefixOmitted,
                backendName: nil,
                profileName: nil,
                reasonCode: "prefix-omitted"
            ),
            SceneAuthoredEffectStageAdmission(
                key: inactiveKeys[0],
                definitionPath: inactiveLayer.effects[0].file,
                activity: .authorDisabled,
                strictAdmission: .inactive,
                coverage: .inactive,
                backendName: nil,
                profileName: nil,
                reasonCode: nil
            ),
            SceneAuthoredEffectStageAdmission(
                key: migratedKey,
                definitionPath: migratedLayer.effects[0].file,
                activity: .active,
                strictAdmission: .notAdmitted,
                coverage: .prefixOmitted,
                backendName: nil,
                profileName: nil,
                reasonCode: "unsupported-stage"
            ),
        ]
        let allKeys = strictKeys + prefixKeys + inactiveKeys + [migratedKey]
        let authored = SceneAuthoredEffectExecutionCatalog(
            stageAdmissions: admissions,
            chainsByLayerID: [7: Marker(), 13: Marker()],
            legacyGaussianBlurBlockedLayerIDs: [],
            descriptorEffectStageCount: allKeys.count,
            descriptorEffectStageKeys: Set(allKeys)
        )
        let catalog = SceneEffectRuntimeDispositionCatalog(
            descriptor: SceneRenderDescriptor(
                layers: [strictLayer, prefixLayer, inactiveLayer, migratedLayer]
            ),
            authoredCatalog: authored,
            resourcesByLayerID: [:],
            resolvedMaterialSubjects: [
                .init(key: migratedKey, family: "resolved-material"),
            ]
        )
        let unmigrated = SceneEffectRuntimeDispositionCatalog(
            descriptor: SceneRenderDescriptor(layers: [migratedLayer]),
            authoredCatalog: .init(
                stageAdmissions: [admissions.last!],
                chainsByLayerID: [:],
                legacyGaussianBlurBlockedLayerIDs: [],
                descriptorEffectStageCount: 1,
                descriptorEffectStageKeys: [migratedKey]
            ),
            resourcesByLayerID: [:]
        )
        return [
            "descriptorConserved": catalog.descriptorIdentityConserved,
            "groupConserved": catalog.groupIdentityConserved,
            "strictConserved": catalog.strictIdentityConserved,
            "resolvedConserved": catalog.resolvedMaterialOwnershipConserved,
            "unmigratedKind": unmigrated.dispositions.first?.kind.rawValue ?? "-",
            "groups": catalog.routeGroups.map {
                [
                    "layer": $0.layerID,
                    "kind": $0.kind.rawValue,
                    "effects": $0.effectKeys.count,
                    "owners": $0.ownerKeys.map(\.descriptorID),
                ] as [String: Any]
            },
            "records": catalog.dispositions.map {
                [
                    "id": $0.key.descriptorID,
                    "kind": $0.kind.rawValue,
                    "group": $0.routeGroupID.map { $0 as Any } ?? NSNull(),
                    "role": $0.routeRole.rawValue,
                    "family": $0.family.map { $0 as Any } ?? NSNull(),
                    "reason": $0.reasonCode.map { $0 as Any } ?? NSNull(),
                ] as [String: Any]
            },
            "resolvedMaterialSubjects": catalog
                .resolvedMaterialExecutionEvidenceSubjects.map {
                    [
                        "id": $0.key.descriptorID,
                        "index": $0.key.effectIndex,
                        "family": $0.family,
                    ] as [String: Any]
                },
        ]
    }

    static func effect(
        _ id: String,
        _ file: String,
        passes: Int = 1,
        slots: [String?] = [],
        combos: [String: Int] = [:],
        values: [String: [Double]] = [:],
        visible: Bool = true
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: file,
            visible: visible,
            passes: (0..<passes).map { index in
                .init(
                    passIndex: index,
                    texturePaths: slots.compactMap { $0 },
                    textureSlots: slots,
                    userTextureInputs: [],
                    combos: combos,
                    constantShaderValues: values.mapValues {
                        .init(components: $0)
                    }
                )
            }
        )
    }

    static func gradient(_ id: String) -> SceneRenderDescriptor.EffectDescriptor {
        effect(
            id,
            "effects/gradient_color/effect.json",
            combos: ["AXIS": 0, "BLENDMODE": 0],
            values: [
                "Amount": [50],
                "Color 1": [1, 0, 0],
                "Color 2": [0, 0, 1],
                "Hue Speed": [0],
                "Opacity": [1],
                "Oscillate": [0],
            ]
        )
    }
}
'''


class SceneEffectRuntimeRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-effect-routes-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = directory / "scene-effect-routes"
        compilation = subprocess.run(
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
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)
        cls.execution_logs = cls.result["executionLogs"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @staticmethod
    def by_id(decision: dict[str, object]) -> dict[str, dict[str, object]]:
        return {record["id"]: record for record in decision["records"]}

    def test_real_renderer_precedence_marks_blur_shadowed_by_bloom(self) -> None:
        decision = self.result["bloomBlur"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "legacy-offscreen")
        self.assertEqual(decision["owners"], ["bloom"])
        self.assertEqual(records["bloom"]["kind"], "legacy-exact-offscreen")
        self.assertEqual(records["blur"]["kind"], "legacy-shadowed")
        self.assertEqual(records["blur"]["family"], "gaussian-blur")
        self.assertEqual(records["precise"]["family"], "gaussian-blur-precise")
        self.assertEqual(records["motion"]["family"], "motion-blur")

    def test_route_only_is_one_layer_group_not_stage_execution(self) -> None:
        decision = self.result["routeOnly"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "offscreen-passthrough")
        self.assertEqual(decision["offscreenPasses"], 2)
        self.assertEqual(decision["owners"], [])
        self.assertEqual(records["two"]["kind"], "route-only-member")
        self.assertEqual(records["two"]["role"], "member")
        self.assertEqual(records["one"]["kind"], "unsupported")

    def test_composite_refusal_precedes_all_legacy_effects(self) -> None:
        decision = self.result["compositeRefused"]
        records = self.by_id(decision)
        self.assertTrue(decision["skipsComposite"])
        self.assertEqual(decision["group"], "composite-refused")
        self.assertEqual(decision["effects"], 4)
        self.assertEqual(decision["owners"], [])
        self.assertEqual(
            {record["kind"] for record in records.values()},
            {"composite-refused"},
        )
        self.assertEqual(
            {record["attribution"] for record in records.values()},
            {"layer-aggregate"},
        )

    def test_coalesced_flags_and_hybrid_masks_keep_both_effect_keys(self) -> None:
        decision = self.result["coalesced"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "direct")
        self.assertEqual(decision["effects"], 4)
        self.assertEqual(len(records), 4)
        self.assertEqual(len({record["index"] for record in records.values()}), 4)
        for identifier in ("chromatic-a", "chromatic-b", "iris-a", "iris-b"):
            self.assertEqual(records[identifier]["kind"], "legacy-coalesced-inline")
            self.assertEqual(records[identifier]["role"], "aggregate-contributor")
            self.assertEqual(records[identifier]["attribution"], "layer-aggregate")
        self.assertEqual(
            records["iris-a"]["reason"],
            "layer-resource-first-parameters-last",
        )

    def test_iris_mask_precedence_matches_real_compositor_inputs(self) -> None:
        decision = self.result["irisOpacityPriority"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "offscreen-passthrough")
        self.assertEqual(records["iris-priority"]["kind"], "legacy-exact-inline")
        self.assertEqual(records["iris-priority"]["role"], "owner")
        self.assertEqual(records["opacity-shadowed"]["kind"], "route-only-member")
        self.assertEqual(records["opacity-shadowed"]["role"], "member")

    def test_sequential_ripple_and_perspective_preserve_contributors(self) -> None:
        decision = self.result["ripplePerspective"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "legacy-offscreen")
        self.assertEqual(decision["owners"], ["ripple-normal"])
        self.assertEqual(
            set(decision["aggregate"]),
            {"perspective", "opacity"},
        )
        self.assertEqual(
            records["ripple-normal"]["kind"],
            "legacy-exact-offscreen",
        )
        self.assertEqual(records["ripple-normal"]["role"], "owner")
        for identifier in ("perspective", "opacity"):
            self.assertEqual(
                records[identifier]["kind"],
                "legacy-coalesced-offscreen",
            )
            self.assertEqual(
                records[identifier]["role"],
                "aggregate-contributor",
            )

    def test_iris_precedence_preserves_real_composite_refusal(self) -> None:
        decision = self.result["irisPriorityComposite"]
        records = self.by_id(decision)
        self.assertTrue(decision["skipsComposite"])
        self.assertEqual(decision["group"], "composite-refused")
        self.assertEqual(len(records), 5)
        self.assertEqual(
            {record["kind"] for record in records.values()},
            {"composite-refused"},
        )

    def test_opacity_mask_and_effect_order_control_composite_refusal(self) -> None:
        executable = self.result["opacityCompositeExecutable"]
        refused = self.result["opacityBeforePerspective"]
        self.assertFalse(executable["skipsComposite"])
        self.assertEqual(executable["group"], "legacy-offscreen")
        self.assertEqual(
            executable["owners"],
            ["ripple"],
        )
        self.assertEqual(
            set(executable["aggregate"]),
            {"perspective", "opacity"},
        )
        self.assertTrue(refused["skipsComposite"])
        self.assertEqual(refused["group"], "composite-refused")
        self.assertEqual(
            {record["kind"] for record in refused["records"]},
            {"composite-refused"},
        )

    def test_all_legacy_water_parameter_writers_are_aggregate_contributors(
        self,
    ) -> None:
        decision = self.result["waterParameterWriters"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "direct")
        self.assertEqual(decision["waterScale"], 9)
        for identifier in ("ripple-trigger", "waves-last-parameters"):
            self.assertEqual(
                records[identifier]["kind"],
                "legacy-coalesced-inline",
            )
            self.assertEqual(
                records[identifier]["attribution"],
                "layer-aggregate",
            )
            self.assertEqual(
                records[identifier]["role"],
                "aggregate-contributor",
            )
            self.assertEqual(
                records[identifier]["reason"],
                "layer-flag-first-resource-last-parameters",
            )

    def test_multiple_normal_candidates_are_never_exact_key_execution(self) -> None:
        decision = self.result["ambiguousNormalResource"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "legacy-offscreen")
        self.assertEqual(decision["owners"], [])
        self.assertEqual(
            set(decision["aggregate"]),
            {"normal-parameters-first", "normal-resource-candidate"},
        )
        for record in records.values():
            self.assertEqual(record["kind"], "legacy-coalesced-offscreen")
            self.assertEqual(record["attribution"], "layer-aggregate")
            self.assertEqual(record["role"], "aggregate-contributor")
            self.assertEqual(
                record["reason"],
                "first-parameters-first-resolvable-normal",
            )

    def test_blocked_legacy_blur_is_route_only_not_visual_owner(self) -> None:
        decision = self.result["blockedBlur"]
        record = decision["records"][0]
        self.assertEqual(decision["group"], "offscreen-passthrough")
        self.assertEqual(decision["owners"], [])
        self.assertEqual(record["kind"], "route-only-member")
        self.assertEqual(record["role"], "member")

    def test_duplicate_descriptor_ids_keep_distinct_effect_indices(self) -> None:
        records = self.result["duplicateDescriptorIDs"]["records"]
        self.assertEqual(len(records), 2)
        self.assertEqual([record["id"] for record in records], ["duplicate"] * 2)
        self.assertEqual([record["index"] for record in records], [0, 1])
        self.assertEqual(
            {record["kind"] for record in records},
            {"legacy-coalesced-inline"},
        )

    def test_keyed_selections_preserve_original_descriptor_indices(self) -> None:
        selection = self.result["selection"]
        self.assertEqual(selection["foliage"], 2)
        self.assertEqual(selection["gaussian"], 1)
        self.assertTrue(selection["gaussianPrecise"])
        self.assertEqual(selection["gradient"], [0, 1])

    def test_gradient_clipping_shape_is_structural_not_visual_execution(self) -> None:
        decision = self.result["gradientDecision"]
        records = self.by_id(decision)
        self.assertEqual(decision["group"], "legacy-offscreen")
        self.assertEqual(records["gradient"]["kind"], "legacy-exact-offscreen")
        self.assertEqual(records["gradient"]["role"], "owner")
        self.assertEqual(
            records["clip"]["kind"],
            "legacy-structural-member",
        )
        self.assertEqual(records["clip"]["role"], "member")
        self.assertEqual(records["clip"]["reason"], "shape-only-legacy-member")

    def test_legacy_exact_inline_execution_preserves_full_effect_key(self) -> None:
        lines = self.execution_lines("legacy-inline-exact")
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertEqual(self.log_field(line, "origin"), "image")
            self.assertEqual(self.log_field(line, "subject"), "effect")
            self.assertEqual(self.log_field(line, "layer"), "21")
            self.assertEqual(self.log_field(line, "effect"), "1")
            self.assertEqual(
                self.log_field(line, "descriptor"),
                "exact-inline-owner",
            )
            self.assertEqual(self.log_field(line, "family"), "foliage-sway")

    def test_coalesced_inline_contributors_emit_one_layer_family_aggregate(
        self,
    ) -> None:
        lines = self.execution_lines("legacy-inline-coalesced")
        self.assertEqual(len(lines), 1)
        line = lines[0]
        self.assertEqual(self.log_field(line, "origin"), "solid")
        self.assertEqual(self.log_field(line, "subject"), "aggregate")
        self.assertEqual(self.log_field(line, "layer"), "22")
        self.assertEqual(self.log_field(line, "effect"), "-")
        self.assertEqual(self.log_field(line, "descriptor"), "-")
        self.assertEqual(
            self.log_field(line, "family"),
            "water-waves-ripple",
        )

    def test_offscreen_family_filter_records_only_selected_exact_or_aggregate(
        self,
    ) -> None:
        exact = self.execution_lines("legacy-offscreen-water")
        self.assertEqual(len(exact), 1)
        self.assertEqual(self.log_field(exact[0], "subject"), "effect")
        self.assertEqual(self.log_field(exact[0], "layer"), "23")
        self.assertEqual(self.log_field(exact[0], "effect"), "0")
        self.assertEqual(self.log_field(exact[0], "descriptor"), "normal-owner")
        self.assertEqual(
            self.log_field(exact[0], "family"),
            "water-ripple-normal",
        )

        aggregate = self.execution_lines("legacy-offscreen-perspective")
        self.assertEqual(len(aggregate), 1)
        self.assertEqual(self.log_field(aggregate[0], "subject"), "aggregate")
        self.assertEqual(self.log_field(aggregate[0], "layer"), "23")
        self.assertEqual(self.log_field(aggregate[0], "effect"), "-")
        self.assertEqual(self.log_field(aggregate[0], "descriptor"), "-")
        self.assertEqual(
            self.log_field(aggregate[0], "family"),
            "perspective-opacity",
        )

    def test_non_invocation_dispositions_never_emit_execution_subjects(self) -> None:
        self.assertEqual(self.execution_lines("ignored-shadowed"), [])
        self.assertEqual(self.execution_lines("ignored-unsupported"), [])

        structural = self.execution_lines(
            "legacy-offscreen-structural-filter"
        )
        self.assertEqual(len(structural), 1)
        self.assertEqual(
            self.log_field(structural[0], "descriptor"),
            "gradient-owner",
        )
        all_logs = "\n".join(self.execution_logs)
        for descriptor in (
            "unsupported-before-owner",
            "unsupported-only",
            "shadowed-blur",
            "structural-clip",
        ):
            self.assertNotIn(f"descriptor={descriptor}", all_logs)

    def test_execution_subject_keeps_success_and_failure_sticky_facts(self) -> None:
        lines = self.execution_lines("legacy-inline-exact")
        self.assertEqual(len(lines), 2)
        self.assertEqual(
            {self.log_field(line, "outcome") for line in lines},
            {"encoded-output", "failed"},
        )
        failed = next(
            line for line in lines if self.log_field(line, "outcome") == "failed"
        )
        self.assertEqual(self.log_field(failed, "reason"), "pipeline-missing")

    def test_strict_chain_owns_route_and_omitted_stage_never_falls_back(self) -> None:
        decision = self.result["strict"]
        records = self.by_id(decision)
        groups = {group["layer"]: group for group in decision["groups"]}
        self.assertTrue(decision["descriptorConserved"])
        self.assertTrue(decision["groupConserved"])
        self.assertTrue(decision["strictConserved"])
        self.assertTrue(decision["resolvedConserved"])
        self.assertEqual(decision["unmigratedKind"], "unsupported")
        self.assertEqual(set(groups), {7, 13, 18, 19})
        self.assertEqual(groups[7]["kind"], "authored")
        self.assertEqual(groups[7]["effects"], 2)
        self.assertEqual(groups[7]["owners"], ["generic", "iris"])
        self.assertEqual(groups[13]["kind"], "authored")
        self.assertEqual(groups[13]["effects"], 3)
        self.assertEqual(groups[13]["owners"], ["xray"])
        self.assertEqual(groups[18]["kind"], "inactive")
        self.assertEqual(groups[18]["effects"], 0)
        self.assertEqual(groups[18]["owners"], [])
        self.assertEqual(groups[19]["kind"], "authored")
        self.assertEqual(groups[19]["owners"], ["migrated"])
        self.assertEqual(records["generic"]["kind"], "strict-generic")
        self.assertEqual(records["iris"]["kind"], "strict-inline-suffix")
        self.assertEqual(records["xray"]["kind"], "strict-dedicated")
        for identifier in ("prefix-omitted-a", "prefix-omitted-b"):
            self.assertEqual(
                records[identifier]["kind"],
                "omitted-by-strict-chain",
            )
            self.assertEqual(records[identifier]["role"], "member")
        self.assertEqual(records["disabled"]["kind"], "inactive")
        self.assertIsNone(records["disabled"]["group"])
        self.assertEqual(records["inactive-only"]["kind"], "inactive")
        self.assertIsNone(records["inactive-only"]["group"])
        self.assertEqual(records["migrated"]["kind"], "strict-generic")
        self.assertEqual(records["migrated"]["family"], "resolved-material")
        self.assertEqual(
            records["migrated"]["reason"],
            "resolved-material-capability-owner",
        )
        self.assertEqual(
            decision["resolvedMaterialSubjects"],
            [
                {"id": "generic", "index": 0, "family": "scroll"},
                {"id": "iris", "index": 1, "family": "iris-inline"},
                {"id": "xray", "index": 0, "family": "xray"},
                {
                    "id": "migrated",
                    "index": 0,
                    "family": "resolved-material",
                },
            ],
        )

    def execution_lines(self, backend: str) -> list[str]:
        return [
            line
            for line in self.execution_logs
            if self.log_field(line, "backend") == backend
        ]

    @staticmethod
    def log_field(line: str, name: str) -> str:
        fields = {
            key: value
            for field in line.split()
            if "=" in field
            for key, value in [field.split("=", 1)]
        }
        if name not in fields:
            raise AssertionError(f"missing {name}= in {line!r}")
        return fields[name]


if __name__ == "__main__":
    unittest.main()
