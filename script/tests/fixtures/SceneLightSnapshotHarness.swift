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
        // Official directional semantics (own-fixture black-box, 2026-10-06):
        // angle values are radians; an exactly identity rotation keeps the
        // official default aim (0, 0, -1) and yaw sweeps XZ toward +Z.
        let directionalFrame = simd_float4x4(columns: (
            SIMD4<Float>(0.5403023, 0, -0.84147096, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0.84147096, 0, 0.5403023, 0),
            SIMD4<Float>(10, 20, 30, 1)
        ))
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
            worldFramesByLayerID: [13: frame, 14: directionalFrame]
        )
        precondition(directionalSnapshot.directional.count == 2)
        precondition(directionalSnapshot.directional[0].directionTowardLight
            == SIMD3(0, 0, -1))
        let yawed = directionalSnapshot.directional[1].directionTowardLight
        precondition(abs(yawed.x - 0.5403023) < 1e-4
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
        let scriptDirection = SceneLightSnapshot.make(
            descriptor: directionalDescriptor,
            worldFramesByLayerID: [13: frame, 14: directionalFrame],
            dynamicSnapshot: scriptAngles
        ).directional[1].directionTowardLight
        precondition(simd_length(scriptDirection - SIMD3(0, 1, 0)) < 1e-4,
            "light-angle-canonical-script-value: \(scriptDirection)")
        for source in [SceneDynamicSource.authored, .userProperty, .timeline, .sceneScript] {
            let value = SceneDynamicValue.vector3(0, 1, 0)
            let angles = SceneDynamicSnapshotResolver().resolve(
                frameIndex: 1, generation: 1, definitions: angleDefinitions,
                userValues: source == .userProperty ? [angleTarget: value] : [:],
                timelineValues: source == .timeline ? [angleTarget: value] : [:],
                sceneScriptValues: source == .sceneScript ? [angleTarget: value] : [:]
            ).snapshot
            let published = SceneLightSnapshot.make(
                descriptor: directionalDescriptor,
                worldFramesByLayerID: [13: frame, 14: directionalFrame],
                dynamicSnapshot: angles
            ).directional[1].directionTowardLight
            precondition(simd_length(published - yawed) < 1e-4,
                "light-angle-source-\(source.rawValue)")
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
        // Lights are admitted regardless of the layer visibility flag
        // (3589454154 authors `lpoint` with `visible:false` and the official
        // client still lights the scene from it); the dynamic intensity
        // snapshot remains the activation channel.
        let activated = SceneLightSnapshot.make(
            descriptor: hiddenParentDescriptor,
            worldFramesByLayerID: [9: frame],
            dynamicSnapshot: activatedSnapshot
        )
        precondition(activated.directional.map(\.intensity) == [19])

        func makePoint(_ intensity: Float, radius: Float = 40)
            -> ScenePointLightDefinition {
            .init(
                kind: "lpoint", colorRGB: [1, 1, 1], intensity: intensity,
                radius: radius, castsVolumetrics: nil, castsShadow: nil,
                isSolid: nil
            )
        }
        func direction(_ intensity: Float)
            -> SceneDirectionalLightDefinition {
            .init(colorRGB: [1, 1, 1], intensity: intensity)
        }
        func cone(_ intensity: Float) -> SceneSpotLightDefinition {
            .init(
                kind: "lspot", colorRGB: [1, 1, 1], intensity: intensity,
                radius: 40, innerConeDegrees: 60, outerConeDegrees: 90,
                density: nil, exponent: nil, volumetricsExponent: nil,
                castsVolumetrics: nil, castsShadow: nil, isSolid: nil
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
                .init(id: 2, visible: true, pointLight: makePoint(12),
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
        // Script-hidden lights stay admitted: illumination is independent of
        // the visibility flag (3589454154 `lpoint` visible:false still lights
        // the scene officially), so the four-slot budget spans all seven
        // ordered lights and three overflow.
        let bounded = SceneLightSnapshot.make(
            descriptor: orderedDescriptor,
            worldFramesByLayerID: Dictionary(
                uniqueKeysWithValues: (1...7).map { ($0, frame) }
            ),
            candidateLayerIDs: orderedIDs,
            layersByID: orderedByID
        )
        precondition(bounded.directional.map(\.intensity) == [14])
        precondition(bounded.point.map(\.intensity) == [17, 15])
        precondition(bounded.spot.map(\.intensity) == [16])
        precondition(bounded.overflowCount == 3)

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
