import simd

@main
enum LightSnapshotHarness {
    static func main() {
        let spot = SceneSpotLightDefinition(
            kind: "lspot", colorRGB: [1, 1, 1], intensity: 3,
            radius: 6000, innerConeDegrees: 60, outerConeDegrees: 90,
            density: nil, exponent: nil, volumetricsExponent: nil,
            castsVolumetrics: nil, castsShadow: true, isSolid: true
        )
        let point = ScenePointLightDefinition(
            kind: "lpoint", colorRGB: [0.8, 0.6, 0.4], intensity: 2,
            radius: 40, castsVolumetrics: false, castsShadow: false,
            isSolid: true
        )
        let descriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0.1, 0.2, 0.3],
                skylightColorRGB: [0.2, 0.1, 0],
                lightClasses: .init(directional: false, point: true, spot: true),
                distanceFog: .init(color: [0.1, 0.2, 0.3], start: 10, end: 100,
                                   startDensity: 0.2, endDensity: 0.8)
            ),
            layers: [
                .init(
                    id: 6, visible: true, pointLight: point,
                    spotLight: nil, directionalLight: nil
                ),
                .init(
                    id: 7, visible: true, pointLight: nil,
                    spotLight: spot, directionalLight: nil
                ),
            ]
        )
        let frame = simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(10, 20, 30, 1)
        ))
        let dynamicSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [
                .init(
                    target: .layer(layerID: 6, field: .intensity),
                    valueType: .scalar,
                    authoredValue: .scalar(2)
                ),
                .init(
                    target: .layer(layerID: 7, field: .intensity),
                    valueType: .scalar,
                    authoredValue: .scalar(3)
                ),
            ],
            userValues: [.layer(layerID: 6, field: .intensity): .scalar(4)],
            sceneScriptValues: [
                .layer(layerID: 7, field: .intensity): .scalar(5),
            ]
        ).snapshot
        let snapshot = SceneLightSnapshot.make(
            descriptor: descriptor,
            worldFramesByLayerID: [6: frame, 7: frame],
            dynamicLayerColors: [
                6: SIMD3(1, 0.5, 0.25),
                7: SIMD3(0.25, 0.5, 1),
            ],
            dynamicSnapshot: dynamicSnapshot
        )
        let explicitBlack = SceneRenderDescriptor(
            lighting: .init(ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0]),
            layers: []
        )
        precondition(SceneLightSnapshot.make(
            descriptor: explicitBlack, worldFramesByLayerID: [:]
        ).ambient == .zero)
        let omittedAmbient = SceneRenderDescriptor(lighting: nil, layers: [])
        precondition(SceneLightSnapshot.make(
            descriptor: omittedAmbient, worldFramesByLayerID: [:]
        ).ambient == .zero)
        // An unadmitted spot class (lightconfig.spot absent) must stay inert.
        let ungatedSpotDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: false, point: false, spot: false)
            ),
            layers: [
                .init(
                    id: 12, visible: true, pointLight: nil,
                    spotLight: spot, directionalLight: nil
                ),
            ]
        )
        precondition(SceneLightSnapshot.make(
            descriptor: ungatedSpotDescriptor,
            worldFramesByLayerID: [12: frame]
        ).spot.isEmpty)
        // Official fixed-normal probes (2026-10-09) identify toward-light
        // opposite the shared world-frame +X emission axis, including zero.
        let directionalDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: false, spot: false)
            ),
            layers: [
                .init(
                    id: 13, visible: true, pointLight: nil, spotLight: nil,
                    directionalLight: .init(colorRGB: [1, 1, 1], intensity: 4)
                ),
                .init(
                    id: 14, visible: true, anglesXYZ: [0, 1, 0],
                    pointLight: nil, spotLight: nil,
                    directionalLight: .init(colorRGB: [1, 1, 1], intensity: 4)
                ),
            ]
        )
        let directionalSnapshot = SceneLightSnapshot.make(
            descriptor: directionalDescriptor,
            worldFramesByLayerID: SceneLayerWorldFrameResolver.compute(
                descriptor: directionalDescriptor,
                byID: Dictionary(uniqueKeysWithValues: directionalDescriptor.layers.map { ($0.id, $0) })
            )
        )
        precondition(directionalSnapshot.directional.count == 2)
        precondition(directionalSnapshot.directional[0].directionTowardLight
            == SIMD3(-1, 0, 0))
        let yawed = directionalSnapshot.directional[1].directionTowardLight
        precondition(abs(yawed.x + 0.5403023) < 1e-4
            && abs(yawed.y) < 1e-4
            && abs(yawed.z - 0.84147096) < 1e-4)
        // An owner for another field also reserves the authored angles lane.
        // Every producer publishes canonical radians into this typed lane.
        let angleTarget = SceneDynamicTarget.layer(layerID: 14, field: .angles)
        let angleDefinitions = [SceneDynamicTargetDefinition(
            target: angleTarget, valueType: .vector3, authoredValue: .vector3(0, 1, 0)
        )]
        // Same canonical value as the real VM angle boundary regression:
        // script Vec3(0, 0.15, 90) publishes radians before light consumption.
        let scriptAngles = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1, generation: 1, definitions: angleDefinitions,
            sceneScriptValues: [angleTarget: .vector3(0, 0.15 * .pi / 180, .pi / 2)]
        ).snapshot
        let directionalLayers = Dictionary(uniqueKeysWithValues:
            directionalDescriptor.layers.map { ($0.id, $0) })
        let directionalFrames = SceneLayerWorldFrameResolver.compute(
            descriptor: directionalDescriptor, byID: directionalLayers)
        func dynamicDirectional(_ angles: SceneDynamicSnapshot) -> SIMD3<Float> {
            let frames = SceneLayerDynamicWorldFrameResolver.resolve(
                descriptor: directionalDescriptor, byID: directionalLayers,
                snapshot: angles, staticFrames: directionalFrames)
            return SceneLightSnapshot.make(
                descriptor: directionalDescriptor, worldFramesByLayerID: frames,
                dynamicSnapshot: angles).directional[1].directionTowardLight
        }
        let scriptDirection = dynamicDirectional(scriptAngles)
        let scriptYaw = Float(0.15 * Double.pi / 180)
        precondition(simd_length(scriptDirection - SIMD3(0, -cos(scriptYaw), sin(scriptYaw))) < 1e-4,
            "light-angle-canonical-script-value: \(scriptDirection)")
        for source in [SceneDynamicSource.authored, .userProperty, .timeline, .sceneScript] {
            let value = SceneDynamicValue.vector3(0, 1, 0)
            let angles = SceneDynamicSnapshotResolver().resolve(
                frameIndex: 1, generation: 1, definitions: angleDefinitions,
                userValues: source == .userProperty ? [angleTarget: value] : [:],
                timelineValues: source == .timeline ? [angleTarget: value] : [:],
                sceneScriptValues: source == .sceneScript ? [angleTarget: value] : [:]
            ).snapshot
            let published = dynamicDirectional(angles)
            precondition(simd_length(published - yawed) < 1e-4,
                "light-angle-source-\(source.rawValue)")
        }
        func parentedDirectional(parentYaw: Float, childAngles: [Float], ortho: Float? = nil,
                                 snapshot: SceneDynamicSnapshot? = nil) -> SceneLightSnapshot {
            let layers: [SceneRenderDescriptor.Layer] = [
                .init(id: 90, visible: true, anglesXYZ: [0, parentYaw, 0],
                      spotLight: nil, directionalLight: nil, originXYZ: [30, 40, 50]),
                .init(id: 91, visible: true, anglesXYZ: childAngles,
                      spotLight: spot, directionalLight: .init(colorRGB: [1, 1, 1], intensity: 1),
                      parentID: 90, scaleXYZ: [2, 3, 4]),
            ]
            let scene = SceneRenderDescriptor(lighting: directionalDescriptor.lighting,
                layers: layers, sceneOrthoHeight: ortho)
            let index = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
            let base = SceneLayerWorldFrameResolver.compute(descriptor: scene, byID: index)
            let world = snapshot.map {
                SceneLayerDynamicWorldFrameResolver.resolve(descriptor: scene, byID: index,
                    snapshot: $0, staticFrames: base)
            } ?? base
            return SceneLightSnapshot.make(descriptor: scene, worldFramesByLayerID: world,
                                          dynamicSnapshot: snapshot)
        }
        let rootHalf = Float(0.7071067811865476)
        let identityParent = parentedDirectional(parentYaw: 0, childAngles: [0, .pi / 4, 0])
        let rotatedParent = parentedDirectional(parentYaw: .pi / 2, childAngles: [0, .pi / 4, 0])
        precondition(simd_length(identityParent.directional[0].directionTowardLight
            - SIMD3(-rootHalf, 0, rootHalf)) < 1e-6)
        precondition(simd_length(rotatedParent.directional[0].directionTowardLight
            - SIMD3(rootHalf, 0, rootHalf)) < 1e-6)
        let parentTarget = SceneDynamicTarget.layer(layerID: 90, field: .angles)
        let dynamicParent = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2, generation: 1,
            definitions: [.init(target: parentTarget, valueType: .vector3, authoredValue: .vector3(0, 0, 0))],
            sceneScriptValues: [parentTarget: .vector3(0, .pi / 2, 0)]).snapshot
        precondition(simd_length(parentedDirectional(parentYaw: 0, childAngles: [0, .pi / 4, 0],
            snapshot: dynamicParent).directional[0].directionTowardLight
            - rotatedParent.directional[0].directionTowardLight) < 1e-6)
        precondition(simd_length(identityParent.directional[0].directionTowardLight
            - SIMD3(-rootHalf, 0, rootHalf)) < 1e-6, "prior snapshot remains immutable")
        let perspectiveRoll = parentedDirectional(parentYaw: 0, childAngles: [0, 0, .pi / 2])
        let orthoRoll = parentedDirectional(parentYaw: 0, childAngles: [0, 0, .pi / 2], ortho: 100)
        precondition(simd_length(perspectiveRoll.directional[0].directionTowardLight - SIMD3(0, -1, 0)) < 1e-6)
        precondition(simd_length(orthoRoll.directional[0].directionTowardLight - SIMD3(0, 1, 0)) < 1e-6)
        // Both light classes read one already-reflected parent/world frame.
        let paired = SceneRenderDescriptor(lighting: .init(ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0]),
            layers: [.init(id: 91, visible: true, spotLight: spot,
                directionalLight: .init(colorRGB: [1, 1, 1], intensity: 1)),
                .init(id: 92, visible: true, spotLight: spot, directionalLight: nil)])
        let pairedFrame = SceneMatrix.eulerXYZ(SIMD3(0.4, 1.2, 0.6)) * SceneMatrix.scale(SIMD3(2, 3, 4))
        let pairedLights = SceneLightSnapshot.make(descriptor: paired,
            worldFramesByLayerID: [91: pairedFrame, 92: pairedFrame])
        precondition(simd_length(pairedLights.directional[0].directionTowardLight
            + pairedLights.spot[0].directionFromLight) < 1e-6)
        // An unsafe/degenerate emission axis rejects only its light. The
        // independent spot still has the unchanged valid world transform.
        for invalidAxis in [SIMD4<Float>.zero, SIMD4<Float>(.infinity, 0, 0, 0)] {
            var invalidFrame = pairedFrame
            invalidFrame.columns.0 = invalidAxis
            let rejected = SceneLightSnapshot.make(descriptor: paired,
                worldFramesByLayerID: [91: invalidFrame, 92: pairedFrame])
            precondition(rejected.directional.isEmpty && rejected.spot.count == 1
                && rejected.overflowCount == 0)
        }
        precondition(snapshot.ambient == SIMD3(0.1, 0.2, 0.3))
        precondition(snapshot.skylight == SIMD3(0.2, 0.1, 0))
        precondition(snapshot.distanceFogColor == SIMD4(0.1, 0.2, 0.3, 1))
        precondition(snapshot.distanceFogRange == SIMD4(10, 100, 0.2, 0.8))
        precondition(snapshot.directional.isEmpty)
        precondition(snapshot.point.count == 1)
        precondition(snapshot.point[0].position == SIMD3(10, 20, 30))
        precondition(snapshot.point[0].color == SIMD3(1, 0.5, 0.25))
        precondition(snapshot.point[0].intensity == 4)
        precondition(snapshot.point[0].radius == 40)
        precondition(snapshot.spot.count == 1)
        precondition(snapshot.overflowCount == 0)
        let light = snapshot.spot[0]
        precondition(light.position == SIMD3(10, 20, 30))
        precondition(light.directionFromLight == SIMD3(1, 0, 0))
        // Official own-scene probes: a spot at +Z reaches the sphere after
        // +pi/2 yaw, not at zero or -pi/2. Parent yaw has the same effect.
        // Exercise the existing matrix utility, rather than a second angle
        // converter inside the lighting snapshot.
        func aimedSpot(_ frame: simd_float4x4) -> SIMD3<Float> {
            SceneLightSnapshot.make(
                descriptor: descriptor, worldFramesByLayerID: [7: frame]
            ).spot[0].directionFromLight
        }
        let positiveYaw = SceneMatrix.eulerXYZ(SIMD3(0, .pi / 2, 0))
        precondition(simd_length(aimedSpot(positiveYaw) - SIMD3(0, 0, -1)) < 1e-6)
        precondition(simd_length(aimedSpot(SceneMatrix.eulerXYZ(
            SIMD3(0, -.pi / 2, 0)
        )) - SIMD3(0, 0, 1)) < 1e-6)
        precondition(simd_length(aimedSpot(positiveYaw * frame)
            - SIMD3(0, 0, -1)) < 1e-6)
        // Off-axis target separates Euler +X from a spherical yaw/elevation
        // replacement; roll at yaw pi/2 alone cannot distinguish the two.
        let offAxis = SceneMatrix.eulerXYZ(SIMD3(0, 1.2, 0.6))
        precondition(simd_length(aimedSpot(offAxis)
            - SIMD3(0.29906676, 0.20460258, -0.93203909)) < 1e-6)
        precondition(simd_length(aimedSpot(SceneMatrix.eulerXYZ(
            SIMD3(0.4, 1.2, 0.6)
        )) - aimedSpot(offAxis)) < 1e-6)
        // A same-frame transform update reaches the same consumer, while
        // the previous immutable snapshot keeps its original direction.
        precondition(simd_length(aimedSpot(positiveYaw) - light.directionFromLight) > 1)
        precondition(light.directionFromLight == SIMD3(1, 0, 0))
        precondition(light.color == SIMD3(0.25, 0.5, 1))
        precondition(light.intensity == 5 && light.radius == 6000)
        precondition(abs(light.innerConeCosine - 0.5) < 1e-6)
        precondition(abs(light.outerConeCosine) < 1e-6)
        let liveTargets = SceneLightSnapshot.liveConsumerTargets(
            descriptor: descriptor
        )
        precondition(liveTargets == [
            .layer(layerID: 6, field: .color),
            .layer(layerID: 6, field: .intensity),
            .layer(layerID: 7, field: .color),
            .layer(layerID: 7, field: .intensity),
        ])
        let hiddenParentDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: true, spot: true)
            ),
            layers: [
                .init(
                    id: 8, visible: false, pointLight: nil,
                    spotLight: nil, directionalLight: nil
                ),
                .init(
                    id: 9, visible: false, pointLight: nil,
                    spotLight: nil,
                    directionalLight: .init(
                        colorRGB: [1, 1, 1], intensity: 11
                    ),
                    parentID: 8
                ),
            ]
        )
        precondition(SceneLightSnapshot.liveConsumerTargets(
            descriptor: hiddenParentDescriptor
        ) == [
            .layer(layerID: 9, field: .color),
            .layer(layerID: 9, field: .intensity),
        ])
        let activatedSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: [
                .init(
                    target: .layer(layerID: 8, field: .visibility),
                    valueType: .bool, authoredValue: .bool(false)
                ),
                .init(
                    target: .layer(layerID: 9, field: .visibility),
                    valueType: .bool, authoredValue: .bool(false)
                ),
                .init(
                    target: .layer(layerID: 9, field: .intensity),
                    valueType: .scalar, authoredValue: .scalar(11)
                ),
            ],
            userValues: [
                .layer(layerID: 8, field: .visibility): .bool(true),
                .layer(layerID: 9, field: .visibility): .bool(true),
                .layer(layerID: 9, field: .intensity): .scalar(19),
            ]
        ).snapshot
        let hiddenLayersByID = Dictionary(uniqueKeysWithValues:
            hiddenParentDescriptor.layers.map { ($0.id, $0) }
        )
        // Launch candidates retain their producers while current visibility
        // gates illumination. A published show can reveal a hidden child
        // only when its parent is also visible.
        precondition(SceneLightSnapshot.make(
            descriptor: hiddenParentDescriptor,
            worldFramesByLayerID: [9: frame]
        ).directional.isEmpty)
        let activated = SceneLightSnapshot.make(
            descriptor: hiddenParentDescriptor,
            worldFramesByLayerID: [9: frame],
            dynamicSnapshot: activatedSnapshot
        )
        precondition(activated.directional.map(\.intensity) == [19])
        let parentHidden = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 3, generation: 3,
            definitions: [
                .init(target: .layer(layerID: 8, field: .visibility),
                      valueType: .bool, authoredValue: .bool(false)),
                .init(target: .layer(layerID: 9, field: .visibility),
                      valueType: .bool, authoredValue: .bool(false)),
            ],
            sceneScriptValues: [
                .layer(layerID: 8, field: .visibility): .bool(false),
                .layer(layerID: 9, field: .visibility): .bool(true),
            ]
        ).snapshot
        precondition(SceneLightSnapshot.make(
            descriptor: hiddenParentDescriptor,
            worldFramesByLayerID: [9: frame],
            dynamicSnapshot: parentHidden
        ).directional.isEmpty)
        precondition(activated.directional.map(\.intensity) == [19])

        func makePoint(_ intensity: Float, radius: Float = 40)
            -> ScenePointLightDefinition {
            .init(
                kind: "lpoint", colorRGB: [1, 1, 1], intensity: intensity,
                radius: radius, castsVolumetrics: nil, castsShadow: true,
                isSolid: nil
            )
        }
        func direction(_ intensity: Float)
            -> SceneDirectionalLightDefinition {
            .init(colorRGB: [1, 1, 1], intensity: intensity,
                  shadowCastIntent: .enabled)
        }
        func cone(_ intensity: Float) -> SceneSpotLightDefinition {
            .init(
                kind: "lspot", colorRGB: [1, 1, 1], intensity: intensity,
                radius: 40, innerConeDegrees: 60, outerConeDegrees: 90,
                density: nil, exponent: nil, volumetricsExponent: nil,
                castsVolumetrics: nil, castsShadow: true, isSolid: nil
            )
        }
        let orderedDescriptor = SceneRenderDescriptor(
            lighting: .init(
                ambientColorRGB: [0, 0, 0], skylightColorRGB: [0, 0, 0],
                lightClasses: .init(directional: true, point: true, spot: true)
            ),
            layers: [
                .init(id: 1, visible: true, pointLight: nil,
                      spotLight: nil, directionalLight: direction(11)),
                .init(id: 2, visible: false, pointLight: makePoint(12),
                      spotLight: nil, directionalLight: nil),
                .init(id: 3, visible: true, pointLight: nil,
                      spotLight: cone(13), directionalLight: nil,
                      parentID: 30),
                .init(id: 4, visible: true, pointLight: nil,
                      spotLight: nil, directionalLight: direction(14)),
                .init(id: 5, visible: true, pointLight: makePoint(15),
                      spotLight: nil, directionalLight: nil),
                .init(id: 6, visible: true, pointLight: nil,
                      spotLight: cone(16), directionalLight: nil,
                      displayScriptOwnership: .init(
                          visible: true, alpha: false
                      )),
                .init(id: 7, visible: true, pointLight: makePoint(17),
                      spotLight: nil, directionalLight: nil),
                .init(id: 30, visible: false, pointLight: nil,
                      spotLight: nil, directionalLight: nil),
            ],
            renderOrderLayerIDs: [7, 6, 5, 4, 30, 3, 2, 1]
        )
        let orderedByID = Dictionary(
            uniqueKeysWithValues: orderedDescriptor.layers.map { ($0.id, $0) }
        )
        let orderedIDs = SceneLightSnapshot.orderedLightLayerIDs(
            descriptor: orderedDescriptor, layersByID: orderedByID
        )
        precondition(orderedIDs == [7, 6, 5, 4, 3, 2, 1])
        let hiddenScriptLight = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 4, generation: 4,
            definitions: [.init(
                target: .layer(layerID: 6, field: .visibility),
                valueType: .bool, authoredValue: .bool(true)
            )],
            sceneScriptValues: [.layer(layerID: 6, field: .visibility): .bool(false)]
        ).snapshot
        // Authored-hidden, script-hidden and inherited-hidden lamps remain
        // launch candidates but consume no slot, overflow or shadow map.
        let bounded = SceneLightSnapshot.make(
            descriptor: orderedDescriptor,
            worldFramesByLayerID: Dictionary(
                uniqueKeysWithValues: (1...7).map { ($0, frame) }
            ),
            dynamicSnapshot: hiddenScriptLight,
            candidateLayerIDs: orderedIDs,
            layersByID: orderedByID
        )
        precondition(bounded.directional.map(\.intensity) == [14, 11])
        precondition(bounded.point.map(\.intensity) == [17, 15])
        precondition(bounded.spot.isEmpty)
        precondition(bounded.overflowCount == 0)
        precondition(bounded.shadowLights.compactMap(\.layerID) == [4, 7, 5])
        precondition(SceneLightSnapshot.liveConsumerTargets(
            descriptor: orderedDescriptor
        ).count == 14)

        let visibilityDescriptor = SceneRenderDescriptor(
            lighting: orderedDescriptor.lighting,
            layers: [
                .init(id: 60, visible: true, pointLight: nil, spotLight: nil,
                      directionalLight: nil),
                .init(id: 61, visible: false, pointLight: makePoint(2),
                      spotLight: nil, directionalLight: nil, parentID: 60),
                .init(id: 62, visible: true, pointLight: nil, spotLight: cone(3),
                      directionalLight: nil, parentID: 60),
                .init(id: 63, visible: true, pointLight: nil, spotLight: nil,
                      directionalLight: direction(4), parentID: 60),
                .init(id: 64, visible: false, pointLight: .init(
                    kind: "point", colorRGB: [1, 1, 1], intensity: 5,
                    radius: 40, castsVolumetrics: nil, castsShadow: true, isSolid: nil
                ), spotLight: nil, directionalLight: nil, parentID: 60),
            ]
        )
        let visibilityLayers = Dictionary(uniqueKeysWithValues:
            visibilityDescriptor.layers.map { ($0.id, $0) })
        let visibilityFrames = Dictionary(uniqueKeysWithValues:
            (61...64).map { ($0, frame) })
        func visibilitySnapshot(parent: Bool, children: Bool) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(
                frameIndex: 5, generation: 5,
                definitions: visibilityDescriptor.layers.map {
                    .init(target: .layer(layerID: $0.id, field: .visibility),
                          valueType: .bool, authoredValue: .bool($0.visible ?? true))
                },
                sceneScriptValues: Dictionary(uniqueKeysWithValues:
                    visibilityDescriptor.layers.map {
                        (.layer(layerID: $0.id, field: .visibility),
                         .bool($0.id == 60 ? parent : children))
                    })
            ).snapshot
        }
        func lights(_ dynamic: SceneDynamicSnapshot?, precomputed: Set<Int>? = nil)
            -> SceneLightSnapshot {
            SceneLightSnapshot.make(
                descriptor: visibilityDescriptor,
                worldFramesByLayerID: visibilityFrames,
                dynamicSnapshot: dynamic,
                layersByID: visibilityLayers,
                visibleLayerIDs: precomputed
            )
        }
        func noLights(_ value: SceneLightSnapshot) -> Bool {
            value.directional.isEmpty && value.point.isEmpty && value.spot.isEmpty
                && value.shadowLights.isEmpty && value.overflowCount == 0
        }
        let authoredVisibility = lights(nil)
        precondition(authoredVisibility.point.isEmpty)
        precondition(authoredVisibility.spot.compactMap(\.layerID) == [62])
        precondition(authoredVisibility.directional.compactMap(\.layerID) == [63])
        let allShown = visibilitySnapshot(parent: true, children: true)
        let shownLights = lights(allShown)
        precondition(shownLights.point.compactMap(\.layerID) == [61, 64])
        precondition(shownLights.spot.compactMap(\.layerID) == [62])
        precondition(shownLights.directional.compactMap(\.layerID) == [63])
        precondition(shownLights.shadowLights.compactMap(\.layerID) == [63, 62, 61])
        let precomputed = SceneLayerVisibility.visibleLayerIDs(
            in: visibilityDescriptor, layersByID: visibilityLayers, snapshot: allShown)
        precondition(lights(allShown, precomputed: precomputed).shadowLights.compactMap(\.layerID)
            == shownLights.shadowLights.compactMap(\.layerID))
        precondition(noLights(lights(allShown, precomputed: [])))
        precondition(noLights(lights(visibilitySnapshot(parent: true, children: false))))
        precondition(noLights(lights(visibilitySnapshot(parent: false, children: true))))
        precondition(lights(allShown).point.compactMap(\.layerID) == [61, 64])
        precondition(shownLights.point.compactMap(\.layerID) == [61, 64])

        let invalidRadiusDescriptor = SceneRenderDescriptor(
            lighting: nil,
            layers: [
                .init(id: 8, visible: true, pointLight: makePoint(1, radius: 0),
                      spotLight: nil, directionalLight: nil),
                .init(id: 9, visible: true, pointLight: makePoint(1, radius: -1),
                      spotLight: nil, directionalLight: nil),
            ]
        )
        let invalidRadius = SceneLightSnapshot.make(
            descriptor: invalidRadiusDescriptor,
            worldFramesByLayerID: [8: frame, 9: frame]
        )
        precondition(invalidRadius.point.isEmpty)
        precondition(invalidRadius.ambient == .zero)
    }
}
