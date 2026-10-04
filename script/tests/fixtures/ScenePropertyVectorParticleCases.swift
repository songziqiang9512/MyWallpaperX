import Foundation

extension Harness {
    static func particleCases(_ fixture: PropertyVectorFixture, audioSnapshot: SceneAudioSpectrumSnapshot) -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let frame = fixture.frame
        var particleColorDescriptor = descriptor
        particleColorDescriptor.layers[3].particleInstanceOverride = .init(
            id: nil, alpha: nil, size: nil, lifetime: nil, rate: nil, speed: nil,
            count: nil, brightness: nil, color: nil,
            normalizedColor: .init(value: .vector([1, 1, 1]), userPropertyKey: nil,
                hasScript: true, hasAnimation: false), controlPoints: [:], controlPointAngles: [:])
        func particleColorBindings(user: Any? = nil, key: String = "colorn", value: String = "1 1 1") -> [SceneScriptBindingIR] {
            var wrapper: [String: Any] = ["value": value,
                "script": "export function update(v){if(v.x<0)return {};return new Vec3(v.x*0.5,v.y*0.25,v.z*0.75);} export function cursorClick(e){return new Vec3(1,0,0);}"]
            if let user { wrapper["user"] = user }
            return SceneScriptBindingIRParser.parse(document: ["objects": [
                ["id": 10], ["id": 42], ["id": 77], ["id": 139, "instanceoverride": [key: wrapper]]
            ]]).bindings
        }
        let colorBindings = particleColorBindings(user: NSNull())
        let particleColorTarget = SceneDynamicTarget.particle(layerID: 139, field: .normalizedColor)
        let particleColors = SceneScriptVectorProgram.compile(
            domain: domain, descriptor: particleColorDescriptor, scriptBindings: colorBindings,
            userPropertyDefinitions: [], generation: 194)
        func evaluateParticleColor(_ input: SceneDynamicValue) -> SceneScriptVectorFrameResult {
            particleColors.evaluate(inputs: [particleColorTarget: input], effectivePropertyValues: [:], frame: frame)
        }
        let particleColorResult = evaluateParticleColor(.vector3(1, 1, 1))
        let particleColorBad = evaluateParticleColor(.vector3(-1, 1, 1))
        let particleColorRecovered = evaluateParticleColor(.vector3(1, 1, 1))
        let colorProjection = SceneScriptVectorProgram.project(descriptor: particleColorDescriptor,
            scriptBindings: colorBindings)
        let clearedParticleColor = SceneScriptParticleProjection.apply(
            admittedTargets: colorProjection.targets, to: particleColorDescriptor)
            .layers[3].particleInstanceOverride?.normalizedColor?.hasScript == false
        let rejectedParticleColors = [particleColorBindings(user: "conflict"),
            particleColorBindings(key: "color"), particleColorBindings(value: "0 1 1"),
            colorBindings + colorBindings].map {
                SceneScriptVectorProgram.project(descriptor: particleColorDescriptor,
                    scriptBindings: $0).targets.isEmpty
            }

        let particleScalarFields: [(String, SceneDynamicParticleField)] = [
            ("alpha", .alpha), ("size", .size), ("lifetime", .lifetime),
            ("rate", .rate), ("speed", .speed), ("count", .count),
            ("brightness", .brightness),
        ]
        let scalarBound = SceneParticleBoundValue(
            value: .scalar(2), userPropertyKey: nil,
            hasScript: true, hasAnimation: false
        )
        var scalarParticleDescriptor = descriptor
        scalarParticleDescriptor.layers[3].particleInstanceOverride = .init(
            id: nil, alpha: scalarBound, size: scalarBound, lifetime: scalarBound,
            rate: scalarBound, speed: scalarBound, count: scalarBound,
            brightness: scalarBound, color: nil, normalizedColor: nil,
            controlPoints: [:], controlPointAngles: [:]
        )
        var scalarWrappers: [String: Any] = [:]
        for (name, _) in particleScalarFields {
            scalarWrappers[name] = [
                "value": 2,
                "script": "export function update(value) { if (value < 0) return Infinity; return value * \(name == "count" ? 250 : 2); }",
            ]
        }
        let parsedParticleScalars = SceneScriptBindingIRParser.parse(document: [
            "objects": [["id": 10], ["id": 42], ["id": 77],
                ["id": 139, "instanceoverride": scalarWrappers]],
        ])
        let particleScalars = SceneScriptScalarProgram.compile(
            domain: domain, descriptor: scalarParticleDescriptor,
            scriptBindings: parsedParticleScalars.bindings, generation: 193
        )
        let particleScalarInputs = Dictionary(uniqueKeysWithValues:
            particleScalarFields.map {
                (SceneDynamicTarget.particle(layerID: 139, field: $0.1), SceneDynamicValue.scalar(2))
            })
        let particleScalarResult = particleScalars.evaluate(
            inputs: particleScalarInputs, frame: frame
        )
        let particleScalarValues = Dictionary(uniqueKeysWithValues:
            particleScalarFields.map {
                ($0.0, scalar(particleScalarResult.values[.particle(layerID: 139, field: $0.1)]))
            })
        var particleBadInputs = particleScalarInputs
        particleBadInputs[.particle(layerID: 139, field: .size)] = .scalar(-2)
        let particleBadResult = particleScalars.evaluate(inputs: particleBadInputs, frame: frame)
        let particleRecoveredResult = particleScalars.evaluate(
            inputs: particleScalarInputs, frame: frame
        )
        let particleTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: scalarParticleDescriptor, scriptBindings: parsedParticleScalars.bindings
        )
        scalarParticleDescriptor.layers[3].visible = false
        let particleProjected = SceneScriptParticleProjection.apply(
            admittedTargets: particleTargets, to: scalarParticleDescriptor
        ).layers[3]
        let particleProjectedValues = particleProjected.particleInstanceOverride!
        let allParticleMarkersCleared = [
            particleProjectedValues.alpha, particleProjectedValues.size,
            particleProjectedValues.lifetime, particleProjectedValues.rate,
            particleProjectedValues.speed, particleProjectedValues.count,
            particleProjectedValues.brightness,
        ].allSatisfy { $0?.hasScript == false }
        let partialParticle = SceneScriptParticleProjection.apply(
            admittedTargets: [.particle(layerID: 139, field: .count)],
            to: scalarParticleDescriptor
        ).layers[3].particleInstanceOverride!
        let duplicatedParticleTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: scalarParticleDescriptor,
            scriptBindings: parsedParticleScalars.bindings + [parsedParticleScalars.bindings[0]]
        )
        var conflictingScalarWrappers = scalarWrappers
        conflictingScalarWrappers["count"] = ["script": "export function update(v){return v;}",
            "user": "density", "value": 2]
        conflictingScalarWrappers["size"] = ["script": "export function update(v){return v;}",
            "animation": [:], "value": 2]
        let parsedParticleConflicts = SceneScriptBindingIRParser.parse(document: [
            "objects": [["id": 10], ["id": 42], ["id": 77],
                ["id": 139, "instanceoverride": conflictingScalarWrappers]],
        ])
        let conflictingParticleTargets = SceneScriptScalarProgram.projectedTargets(
            descriptor: scalarParticleDescriptor, scriptBindings: parsedParticleConflicts.bindings
        )
        let particleAudioTarget = SceneDynamicTarget.particle(
            layerID: 139, field: .rate
        )
        let particleAudioProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [particleRateBinding(
                source: particleAudioSource, value: 2
            )],
            generation: 19
        )
        let particleAudioResult = particleAudioProgram.evaluate(
            inputs: [particleAudioTarget: .scalar(2)],
            frame: frame,
            audioSpectrum: audioSnapshot
        )
        let propertyFreeParticleProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [particleRateBinding(
                source: particleAudioSource, value: 2,
                wrapperKeys: ["script", "value"], properties: [:]
            )],
            generation: 190
        )
        let parsedNullParticle = SceneScriptBindingIRParser.parse(document: [
            "objects": [
                ["id": 10], ["id": 42], ["id": 77],
                [
                    "id": 139,
                    "instanceoverride": [
                        "rate": [
                            "script": particleAudioSource,
                            "user": NSNull(),
                            "value": 2,
                        ],
                    ],
                ],
            ],
        ])
        let nullUserParticleProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: parsedNullParticle.bindings,
            generation: 191
        )
        let conflictingParticle = SceneScriptBindingIRParser.parse(document: [
            "objects": [
                ["id": 10], ["id": 42], ["id": 77],
                [
                    "id": 139,
                    "instanceoverride": [
                        "rate": [
                            "script": particleAudioSource,
                            "user": "other-provider",
                            "value": 2,
                        ],
                    ],
                ],
            ],
        ])
        let unknownParticleWrapperProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [particleRateBinding(
                source: particleAudioSource, value: 2,
                wrapperKeys: ["extra", "script", "value"], properties: [:]
            )],
            generation: 192
        )
        let admittedParticleDescriptor = SceneScriptParticleProjection.apply(
            admittedTargets: [.particle(layerID: 139, field: .rate)], to: descriptor
        )
        let staticParticleDescriptor = SceneScriptParticleProjection.apply(
            admittedTargets: [], to: descriptor
        )
        let admittedParticle = admittedParticleDescriptor.layers[3]
        let staticParticle = staticParticleDescriptor.layers[3]
        defer { fixture.retained += [particleColors, particleScalars, particleAudioProgram, propertyFreeParticleProgram, nullUserParticleProgram, unknownParticleWrapperProgram] }
        return [
            "particleScalarBadValues": { particleBadResult.values.count },
            "particleScalarBadFailures": { particleBadResult.failures.count },
            "particleScalarBadSizeAbsent": { particleBadResult.values[.particle(layerID: 139, field: .size)] == nil },
            "particleScalarRecovered": { particleRecoveredResult.values.count },
            "particleColor": { vector(particleColorResult.values[particleColorTarget]) },
            "particleColorRecovered": { vector(particleColorRecovered.values[particleColorTarget]) },
            "particleColorBadRejected": { particleColorBad.values[particleColorTarget] == nil
                && particleColorBad.failures[particleColorTarget] != nil },
            "particleColorCursorOwners": { particleColors.cursorOwnerRegistrations.count },
            "particleColorMarkerCleared": { clearedParticleColor },
            "particleColorNegativeAdmission": { rejectedParticleColors },
            "particleScalarMarkersCleared": { allParticleMarkersCleared },
            "particleScalarHiddenPreserved": { particleProjected.visible == false },
            "particleScalarPartialExact": { partialParticle.count?.hasScript == false
                && partialParticle.size?.hasScript == true },
            "particleScalarDuplicateCount": { duplicatedParticleTargets.count },
            "particleScalarConflictCount": { conflictingParticleTargets.count },
            "particleScalarParsed": { parsedParticleScalars.bindings.count },
            "particleScalarBindings": { particleScalars.bindings.count },
            "particleScalarValues": { particleScalarValues },
            "particleScalarFailures": { particleScalarResult.failures.count },
            "particleAudioBindings": { particleAudioProgram.bindings.count },
            "particleAudioDemand": { particleAudioProgram.hasAudioConsumers },
            "particleAudioValue": { scalar(
                particleAudioResult.values[particleAudioTarget]
            ) },
            "particleAudioFailures": { particleAudioResult.failures.count },
            "particlePropertyFreeBindings": { propertyFreeParticleProgram.bindings.count },
            "particleNullUserBindings": { nullUserParticleProgram.bindings.count },
            "particleNullUserParseFailures": { parsedNullParticle.diagnostics.count },
            "particleConflictingUserRejected": { conflictingParticle.bindings.isEmpty
                && conflictingParticle.diagnostics.map(\.code) == [.conflictingSources] },
            "particleUnknownWrapperRejected": { unknownParticleWrapperProgram.bindings.isEmpty },
            "particleAdmittedVisible": { admittedParticle.visible == true },
            "particleAdmittedRateScriptRemoved": {
                admittedParticle.particleInstanceOverride?.rate?.hasScript == false },
            "particleAdmittedSiblingPreserved": {
                admittedParticle.particleInstanceOverride?.size?.hasScript == true },
            "particleStaticFallbackVisible": { staticParticle.visible == true },
            "particleStaticRatePreserved": {
                staticParticle.particleInstanceOverride?.rate?.hasScript == true },
            "particleStaticSiblingPreserved": {
                staticParticle.particleInstanceOverride?.size?.hasScript == true },
        ]
    }
}
