import Foundation

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Equatable, Sendable {
    case mutationOverflow(String)
    case invalidArgument(String)
    case staleOwner
}

// Point-size VM numeric admission is outside this topology fixture. The
// actual owner/bridge gates cover it; this unavailable leaf cannot admit it.
nonisolated enum SceneScriptValueOwner {
    static func acceptsScalar(_ value: Double, for target: SceneDynamicTarget) -> Bool { false }
}

nonisolated enum SceneDynamicValueType: Sendable { case bool, string, vector3, scalar }
nonisolated enum SceneDynamicValue: Equatable, Sendable {
    case scalar(Double)
    case bool(Bool)
    case string(String)
    case vector3(Double, Double, Double)
}
nonisolated enum SceneDynamicLayerField: Hashable, Sendable {
    case visibility, solid, perspective, origin, scale, angles, color, alpha
}
nonisolated enum SceneDynamicParticleField: Hashable, Sendable { case alpha }
nonisolated enum SceneDynamicTextField: Hashable, Sendable { case content, font, color, pointSize }
nonisolated enum SceneDynamicCameraField: Hashable, Sendable {
    case origin, eye, center, up, zoom
    static let staticTransformFields: [Self] = [.eye, .center, .up, .zoom]
}
nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case text(layerID: Int, field: SceneDynamicTextField)
    case effectVisibility(layerID: Int, effectIndex: Int)
    case particle(layerID: Int, field: SceneDynamicParticleField)
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
    case materialConstant(layerID: Int, passIndex: Int, name: String, materialPath: String)
    case scriptInstanceProperty(layerID: Int, path: [String])
    case scene(Int), camera(SceneDynamicCameraField)
}
nonisolated struct SceneScriptParticlePlaybackCommand: Sendable {
    let layerID: Int
    let action: SceneParticlePlaybackAction
    let callbackEpoch: UInt64
    let ordinal: UInt32
    var count: Int = 0
}
nonisolated enum SceneTimelinePlaybackCommand: Equatable, Sendable { case play, pause, stop }
nonisolated struct SceneTimelinePlaybackMutation: Sendable {
    let target: SceneDynamicTarget
    let command: SceneTimelinePlaybackCommand
}
nonisolated struct SceneScriptCameraCommand: Sendable {
    struct Fields: OptionSet, Sendable {
        let rawValue: UInt32
        static let eye = Self(rawValue: 1), center = Self(rawValue: 2)
        static let up = Self(rawValue: 4), zoom = Self(rawValue: 8)
    }
    let fields: Fields
    let eye: SIMD3<Double>, center: SIMD3<Double>, up: SIMD3<Double>
    let zoom: Double
    let callbackEpoch: UInt64
    let ordinal: UInt32
}
nonisolated struct SceneScriptOwnerEffects: Sendable {
    let ownerTarget: SceneDynamicTarget
    let layerMutations: [SceneScriptLayerMutation]
    var layerTopologyOwnerIdentity: UInt64? = nil
    var particlePlaybackCommands: [SceneScriptParticlePlaybackCommand] = []
    var animationMutations: [SceneTimelinePlaybackMutation] = []
    var materialFunctionMutations: [Int] = []
    var mediaPlaybackCommands: [Int] = [], textureAnimationCommands: [Int] = [], puppetBoneMutations: [Int] = []
    var puppetAnimationCommands: [Int] = []
    var puppetAnimationCallbackRegistrations: Int = 0
    var cameraCommands: [SceneScriptCameraCommand] = []
}
nonisolated struct SceneDynamicTargetDefinition: Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
}

// External prepared metadata only; the runtime under test owns projection,
// admission and retirement. String/VM preparation is exercised by the VM gate.
nonisolated struct SceneScriptPreparedTextTemplate {
    let sourceTarget: SceneDynamicTarget
    let authoredSeed: String
    let outerUserInstruction: Int?
    func definition(layerID: Int) -> SceneDynamicTargetDefinition {
        .init(target: .text(layerID: layerID, field: .content), valueType: .string,
              authoredValue: .string(authoredSeed))
    }
}
nonisolated struct SceneDynamicSnapshot {
    struct Resolved { let value: SceneDynamicValue }
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    subscript(_ target: SceneDynamicTarget) -> Resolved? { values[target].map { .init(value: $0) } }
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
        var parentID: Int? = nil
        var solid: Bool? = nil
        var usesPerspective: Bool? = nil
        var utilityLayer: Bool? = nil
        var hasPerspectiveGeometryConsumer: Bool {
            utilityLayer == nil && ["image", "solid", "text", "model"].contains(contentKind)
        }
        var effects: [Effect] = []
        var alpha: Double? = nil
        struct TextStyle: Sendable { let fontPath: String?; var colorRGB: [Float]? = nil; var pointSize: Float? = nil }
        let id: Int
        let visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let contentKind: String
        let text: String?
        let textStyle: TextStyle?
        let imagePath: String?
        var sizeWH: [Float]? = nil
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

        static func preparedResourceLayer(
            _ mutation: SceneScriptLayerMutation,
            template: SceneScriptPreparedResourceLayerTemplate
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

    struct CameraDescriptor: Sendable {
        var default2DOriginInputLayerID: Int? = nil
        var orthoWidth: Float? = nil
        var orthoHeight: Float? = nil
        var eye: [Float] = [0, 0, 0]
        var center: [Float] = [0, 0, -1]
        var up: [Float] = [0, 1, 0]
        var nearZ: Float = 0.01
        var farZ: Float = 10000
    }
    var camera = CameraDescriptor()
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
    color: SIMD3<Double> = .init(repeating: 1),
    ownerTarget: SceneDynamicTarget? = nil,
    perspective: Bool? = nil,
    textTemplateIdentity: UInt64 = 0
) -> SceneScriptLayerMutation {
    .init(
        kind: kind, isDynamic: dynamic, fields: fields,
        layerID: id, orderIndex: order,
        visible: visible, alpha: alpha, origin: origin,
        scale: scale, angles: angles,
        color: color, pointSize: 32, text: text, font: font,
        assetPath: assetPath, ownerTarget: ownerTarget, perspective: perspective,
        textTemplateIdentity: textTemplateIdentity
    )
}

func succeeded(
    _ result: Result<Void, SceneScriptScalarRuntimeFailure>
) -> Bool {
    if case .success = result { return true }
    return false
}

// Pure external raw-order fixture; no sorting implementation is substituted.
nonisolated final class OrderInput: @unchecked Sendable { var value: [Int]? }

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
        let orderInput = OrderInput()
        let runtime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: [10],
            layerOrderProjection: { _ in .success(orderInput.value) }
        )
        let beforeCreate = runtime.snapshot()
        let visibilityRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: []
        )
        let visibilityDefinitions = visibilityRuntime.authoredLayerDefinitions.filter {
            if case .layer(_, .visibility) = $0.target { return true }
            return false
        }
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
        let invalidStyle = styleRuntime.apply([mutation(10, dynamic: false, alpha: .nan, fields: [.alpha])])
        let styleAfterFailure = styleRuntime.snapshot()
        let replayRuntime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [10])
        let replayTarget = SceneDynamicTarget.layer(layerID: 10, field: .alpha)
        let replayColor = SceneDynamicTarget.layer(layerID: 10, field: .color)
        _ = replayRuntime.apply([mutation(10, dynamic: false, alpha: 0.25, fields: [.alpha, .color])])
        let replayBefore = replayRuntime.snapshot()
        let replayRevision = replayRuntime.authoredDefinitionRevision
        func replayEffects(_ commands: [SceneTimelinePlaybackCommand]) -> [SceneScriptOwnerEffects] {
            [.init(ownerTarget: replayTarget,
                   layerMutations: [mutation(10, dynamic: false, alpha: 0, fields: [.alpha], ownerTarget: replayTarget)],
                   animationMutations: commands.map { .init(target: replayTarget, command: $0) })]
        }
        let replayPlans = [[SceneTimelinePlaybackCommand.play], [.play, .pause], [.play, .stop]].map {
            replayRuntime.preflightOwnerEffects(replayEffects($0)).layerPlan
        }
        let replayReadOnly = replayRuntime.snapshot().authoredLayerValues == replayBefore.authoredLayerValues
        let replayReleased = replayPlans.allSatisfy {
            $0.authoredLayerValues[replayTarget] == nil
                && $0.authoredLayerValues[replayColor] == .vector3(1, 1, 1)
        }
        let pausedSetter = replayRuntime.preflightOwnerEffects(replayEffects([.pause]))
        let rejectedReplay = replayRuntime.preflightOwnerEffectsToFixedPoint(replayEffects([.play])) { _ in [replayTarget] }
        let rejectedReplayPreservesValue = rejectedReplay.admission.layerPlan.authoredLayerValues == replayBefore.authoredLayerValues
        let invalidReplay = replayRuntime.preflightOwnerEffects([.init(
            ownerTarget: replayTarget,
            layerMutations: [mutation(10, dynamic: false, alpha: .nan, fields: [.alpha], ownerTarget: replayTarget)],
            animationMutations: [.init(target: replayTarget, command: .play)]
        )])
        replayRuntime.commit(replayPlans[0])
        let replayCommitReleasedOnlyTarget = replayRuntime.snapshot().authoredLayerValues[replayTarget] == nil
            && replayRuntime.snapshot().authoredLayerValues[replayColor] == .vector3(1, 1, 1)
            && replayRuntime.authoredDefinitionRevision == replayRevision
        let beforeInvalidParticleAlpha = runtime.snapshot().authoredLayerValues
        let invalidParticleAlpha = runtime.apply([mutation(10, dynamic: false, fields: [.particleAlpha])])
        let invalidParticleAlphaPreservesValues = runtime.snapshot().authoredLayerValues == beforeInvalidParticleAlpha
        orderInput.value = [10, -1, 20]
        let create = runtime.apply([mutation(-1, order: 1)])
        let afterCreate = runtime.snapshot()
        orderInput.value = [10, 20, -1]
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
            SceneScriptOwnerEffects(ownerTarget: projectionOwnerA, layerMutations: [], mediaPlaybackCommands: [-1]),
            SceneScriptOwnerEffects(ownerTarget: projectionOwnerB, layerMutations: [], mediaPlaybackCommands: [2]),
        ]
        var particleRejectedSets: [Set<SceneDynamicTarget>] = []
        var particleEligibleCommands: [[Int]] = []
        let projectionAdmission = projectionRuntime.preflightOwnerEffectsToFixedPoint(
            projectionEffects,
            rejectingParticleTransitions: { _, admitted, rejected in
                particleRejectedSets.append(rejected)
                let commands = admitted.filter { !rejected.contains($0.ownerTarget) }.flatMap(\.mediaPlaybackCommands)
                particleEligibleCommands.append(commands)
                return commands.contains(-1) ? [projectionOwnerB] : []
            }
        ) { admitted in
            Set(admitted.filter { $0.mediaPlaybackCommands.contains(-1) }.map(\.ownerTarget))
        }
        var projectedCommandRounds: [[Int]] = []
        let laterRejection = projectionRuntime.preflightOwnerEffectsToFixedPoint(
            projectionEffects.map { owner in
                .init(ownerTarget: owner.ownerTarget, layerMutations: [],
                      mediaPlaybackCommands: owner.mediaPlaybackCommands.map(abs))
            },
            rejectingDependents: { rejected in
                rejected.union([projectionOwnerA, budgetOwnerC])
            }
        ) { admitted in
            projectedCommandRounds.append(admitted.flatMap(\.mediaPlaybackCommands))
            return []
        }
        orderInput.value = [10, 20]
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
        let imageRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor,
            authoredMutationLayerIDs: [],
            preparedResourceLayerTemplates: [
                "models/bar.json": .init(
                    modelPath: "models/bar.json",
                    renderSizeWH: [4, 4]
                ),
            ]
        )
        let imageCreate = imageRuntime.apply([
            mutation(-2, order: 1, assetPath: "models/bar.json", color: .init(0.25, 0.5, 0.75)),
        ])
        let imageSnapshot = imageRuntime.snapshot()
        let imageUpdate = imageRuntime.apply([
            mutation(-2, order: 1, assetPath: "models/bar.json", color: .init(0.8, 0.4, 0.2)),
        ])
        let updatedImage = imageRuntime.snapshot()
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
        let perspectiveRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: [10, 20]
        )
        let perspectiveImage = SceneDynamicTarget.layer(layerID: 10, field: .perspective)
        let perspectiveText = SceneDynamicTarget.layer(layerID: 20, field: .perspective)
        let perspectivePlan = perspectiveRuntime.preflightIsolatingOwners([
            mutation(10, dynamic: false, fields: [.perspective], perspective: true),
            mutation(20, dynamic: false, fields: [.perspective], perspective: false),
        ])
        let perspectiveBeforeCommit = perspectiveRuntime.snapshot().authoredLayerValues.isEmpty
        perspectiveRuntime.commit(perspectivePlan)
        let perspectiveCommitted = perspectiveRuntime.snapshot()
        let perspectiveRevision = perspectiveRuntime.authoredDefinitionRevision
        let perspectiveFalse = perspectiveRuntime.apply([
            mutation(10, dynamic: false, fields: [.perspective], perspective: false)
        ])
        let perspectiveMissingBool = perspectiveRuntime.apply([
            mutation(10, dynamic: false, fields: [.perspective])
        ])
        let perspectiveMissingBoolPreserves = perspectiveRuntime.snapshot().authoredLayerValues[perspectiveImage] == .bool(false)
        let badPerspectiveLayers = ["particle", "sound", "camera", "composition", "image"].enumerated().map { index, kind in
            var layer = SceneRenderDescriptor.Layer(
                id: 100 + index, visible: true, originXYZ: nil, scaleXYZ: nil,
                anglesXYZ: nil, contentKind: kind
            )
            if kind == "image" { layer.utilityLayer = true }
            return layer
        }
        let perspectiveConsumerRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: .init(layers: descriptor.layers + badPerspectiveLayers,
                renderOrderLayerIDs: [10, 20] + badPerspectiveLayers.map(\.id)),
            authoredMutationLayerIDs: Set([10, 20] + badPerspectiveLayers.map(\.id))
        )
        let unsupportedPerspectiveOwners = badPerspectiveLayers.map {
            SceneDynamicTarget.layer(layerID: $0.id, field: .origin)
        }
        let perspectiveIsolation = perspectiveConsumerRuntime.preflightOwnerEffectsToFixedPoint(
            zip(badPerspectiveLayers, unsupportedPerspectiveOwners).map { layer, owner in
                .init(ownerTarget: owner, layerMutations: [
                    mutation(layer.id, dynamic: false, fields: [.perspective], ownerTarget: owner, perspective: true)
                ])
            } + [.init(ownerTarget: perspectiveImage, layerMutations: [
                mutation(10, dynamic: false, fields: [.perspective], ownerTarget: perspectiveImage, perspective: true)
            ])]
        ) { _ in [] }
        perspectiveConsumerRuntime.commit(perspectiveIsolation.admission.layerPlan)
        let templateSource = SceneDynamicTarget.text(layerID: 20, field: .content)
        let cloneTarget = SceneDynamicTarget.text(layerID: -101, field: .content)
        let nestedTarget = SceneDynamicTarget.text(layerID: -102, field: .content)
        let templateRuntime = SceneScriptDynamicLayerRuntime(
            descriptor: descriptor, authoredMutationLayerIDs: [10], textTemplates: [
                1: .init(sourceTarget: templateSource, authoredSeed: "raw", outerUserInstruction: 1),
                2: .init(sourceTarget: templateSource, authoredSeed: "script-raw", outerUserInstruction: nil)
            ])
        let templateBirth = templateRuntime.preflightIsolatingOwners([
            mutation(-101, text: "init-A", ownerTarget: ownerA, textTemplateIdentity: 1),
            mutation(-102, text: "init-B", ownerTarget: cloneTarget, textTemplateIdentity: 2)
        ])
        let templatePreflightReadOnly = templateRuntime.snapshot().dynamicLayers.isEmpty
            && templateRuntime.projectPreparedTextUserValues(from: [templateSource: .string("user")])[cloneTarget] == nil
        templateRuntime.commit(templateBirth)
        let userAlias = templateRuntime.projectPreparedTextUserValues(from: [templateSource: .string("user")])
        let userAtLimit = templateRuntime.projectPreparedTextUserValues(
            from: [templateSource: .string(String(repeating: "x", count: 4_096))])
        let userTooLong = templateRuntime.projectPreparedTextUserValues(
            from: [templateSource: .string(String(repeating: "x", count: 4_097))],
            previousValue: { $0 == cloneTarget ? .string("previous-safe") : nil })
        let userNUL = templateRuntime.projectPreparedTextUserValues(
            from: [templateSource: .string("bad\0input")],
            previousValue: { $0 == cloneTarget ? .string("previous-safe") : nil })
        let userWithoutPrevious = templateRuntime.projectPreparedTextUserValues(
            from: [templateSource: .string("bad\0input")])
        let birthDefinition = templateRuntime.authoredLayerDefinitions.first { $0.target == cloneTarget }
        let textMirror = templateRuntime.preparedTextValues(in: .init(values: [
            cloneTarget: .string("current-A"), nestedTarget: .string("current-B"), templateSource: .string("source")]))
        let unknownTemplate = templateRuntime.apply([
            mutation(-103, textTemplateIdentity: 999)
        ])
        let missingTemplate = templateRuntime.apply([mutation(-101, text: "wrong")])
        _ = templateRuntime.apply([
            mutation(-101, text: "mirror", origin: .init(3, 4, 5),
                ownerTarget: ownerA, textTemplateIdentity: 1)
        ])
        let transformDoesNotFreezeText = templateRuntime.snapshot().authoredLayerValues[cloneTarget] == nil
        _ = templateRuntime.apply([
            mutation(-102, text: "explicit", fields: [.text], ownerTarget: cloneTarget, textTemplateIdentity: 2)
        ])
        let actualSetterPublished = templateRuntime.snapshot().authoredLayerValues[nestedTarget] == .string("explicit")
        let creatorDelete = templateRuntime.preflightIsolatingOwners([
            mutation(10, dynamic: false, kind: .destroy, ownerTarget: ownerA)
        ])
        let cascadeReadOnly = templateRuntime.snapshot().dynamicLayers.count == 2
        templateRuntime.commit(creatorDelete)
        let afterCascade = templateRuntime.snapshot()
        let payload: [String: Any] = [
            "templateBirthReadOnly": templatePreflightReadOnly,
            "templateBirthSeparatesSeedAndInit": birthDefinition?.authoredValue == .string("raw")
                && templateBirth.createdPreparedTextValues[cloneTarget] == .string("init-A"),
            "templateUserAliasOnlyPreparedUser": userAlias[cloneTarget] == .string("user")
                && userAlias[nestedTarget] == nil && userAlias[templateSource] == .string("user"),
            "templateUserBoundsAreTargetLocal": userAtLimit[cloneTarget] == .string(String(repeating: "x", count: 4_096))
                && userTooLong[cloneTarget] == .string("previous-safe")
                && userNUL[cloneTarget] == .string("previous-safe")
                && userWithoutPrevious[cloneTarget] == .string("raw")
                && userTooLong[templateSource] == .string(String(repeating: "x", count: 4_097)),
            "templateMirrorUsesLiveMembership": textMirror == [-101: "current-A", -102: "current-B"],
            "templateUnknownOrMissingRejectLocally": !succeeded(unknownTemplate) && !succeeded(missingTemplate)
                && transformDoesNotFreezeText,
            "templateExplicitSetterPublished": actualSetterPublished,
            "templateCreatorCascadeRetiresDescendants": cascadeReadOnly
                && creatorDelete.retiredDynamicLayerIDs == [-101, -102] && afterCascade.dynamicLayers.isEmpty,
            "templateCascadeReleasesValuesDefinitionsAndAliases": afterCascade.authoredLayerValues[nestedTarget] == nil
                && templateRuntime.authoredLayerDefinitions.allSatisfy { $0.target != cloneTarget && $0.target != nestedTarget }
                && templateRuntime.projectPreparedTextUserValues(from: [templateSource: .string("next")])[cloneTarget] == nil,
            "perspectivePreflightReadOnly": perspectiveBeforeCommit,
            "perspectiveImageTextAccepted": perspectiveCommitted.authoredLayerValues[perspectiveImage] == .bool(true)
                && perspectiveCommitted.authoredLayerValues[perspectiveText] == .bool(false),
            "perspectiveFalseAndMissingBool": succeeded(perspectiveFalse) && !succeeded(perspectiveMissingBool) && perspectiveMissingBoolPreserves,
            "perspectiveValueChangeKeepsSchemaAndTopology": perspectiveRuntime.authoredDefinitionRevision == perspectiveRevision && perspectiveRuntime.topologyRevision == 0,
            "perspectiveUnsupportedIsLocal": Set(perspectiveIsolation.admission.rejectedOwners.map(\.ownerTarget)) == Set(unsupportedPerspectiveOwners)
                && perspectiveConsumerRuntime.snapshot().authoredLayerValues[perspectiveImage] == .bool(true),
            "replayCandidateIsReadOnly": replayReadOnly,
            "replayReleasesOnlyTargetIncludingImmediatePauseStop": replayReleased,
            "pausedSetterWithoutPlayIsRetained": pausedSetter.layerPlan.authoredLayerValues[replayTarget] == .scalar(0),
            "externallyRejectedPlayPreservesSetter": rejectedReplayPreservesValue,
            "invalidOwnerPlayPreservesSetter": invalidReplay.layerPlan.authoredLayerValues == replayBefore.authoredLayerValues,
            "replayCommitKeepsSchemaAndPeer": replayCommitReleasedOnlyTarget,
            "nonParticleInstanceAlphaRejected": !succeeded(invalidParticleAlpha) && invalidParticleAlphaPreservesValues,
            "styleBeforeCommit": styleBeforeCommit,
            "styleAlphaPublished": styleAfterCommit.authoredLayerValues[.layer(layerID: 10, field: .alpha)] == .scalar(0.25),
            "styleColorPublished": styleAfterCommit.authoredLayerValues[.layer(layerID: 10, field: .color)] == .vector3(1, 1, 1),
            "styleFailurePreservesCurrent": !succeeded(invalidStyle) && styleAfterFailure.authoredLayerValues == styleAfterCommit.authoredLayerValues,
            "createSucceeded": succeeded(create),
            "priorSnapshotStable": beforeCreate.dynamicLayers.isEmpty,
            "createdIDs": afterCreate.dynamicLayers.map(\.id),
            "createdOrder": afterCreate.renderOrderLayerIDs,
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
                .text(layerID: 20, field: .content), .text(layerID: 20, field: .font),
                .camera(.eye), .camera(.center), .camera(.up), .camera(.zoom)]),
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
            "dynamicImageColor": imageSnapshot.dynamicLayers.first?
                .colorRGB?.map(Double.init) ?? [],
            "dynamicImageUpdateSucceeded": succeeded(imageUpdate),
            "dynamicImageUpdatedColor": updatedImage.dynamicLayers.first?
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
