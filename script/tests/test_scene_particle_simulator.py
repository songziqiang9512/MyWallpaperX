#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "Particles/SceneParticleWorldSpacePlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleBoids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+ControlPointForce.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Boids.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Vortex.swift",
    SOURCE_ROOT / "Particles/SceneParticlePeriodicEmission.swift",
    SOURCE_ROOT / "Particles/SceneParticleLayerImageEmissionMap.swift",
    SOURCE_ROOT / "Particles/SceneParticleOscillationCache.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+Random.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulator+InstanceOverride.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import simd

@main
enum Harness {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "census" {
            try printJSON(census(rootPath: CommandLine.arguments[2]))
        } else {
            try printJSON(syntheticResults())
        }
    }

    private static func syntheticResults() throws -> [String: Any] {
        var first = simulator(deterministicJSON, seed: 41, step: 0.1)
        var partitioned = simulator(deterministicJSON, seed: 41, step: 0.1)
        var different = simulator(deterministicJSON, seed: 42, step: 0.1)
        first.advance(by: 0.5)
        partitioned.advance(by: 0.2)
        partitioned.advance(by: 0.3)
        different.advance(by: 0.5)
        let birthEvents = first.consumeBirthEvents()
        let partitionedBirthEvents = partitioned.consumeBirthEvents()

        var capped = simulator(maximumCountJSON, seed: 1, step: 0.1)
        capped.advance(by: 0.1)
        var budgeted = simulator(maximumCountJSON, seed: 1, step: 0.1, particleBudget: 2)
        budgeted.advance(by: 0.1)
        let prewarmed = simulator(prewarmJSON, seed: 1, step: 0.1)

        var death = simulator(deathJSON, seed: 1, step: 0.1)
        death.advance(by: 0.2)
        let deathEvents = death.consumeDeathEvents()

        var burst = simulator(durationJSON, seed: 1, step: 0.1)
        burst.advance(by: 0.5)

        var bounds = simulator(boundsJSON, seed: 7, step: 0.1)
        bounds.advance(by: 0.1)
        let sphere = bounds.particles.prefix(50)
        let box = bounds.particles.dropFirst(50)
        let sphereRadii = sphere.map { length($0.position - SIMD3(10, 20, 30)) }
        let boxOffsets = box.map { $0.position - SIMD3(-10, -20, -30) }
        var centeredBox = simulator(centeredBoxJSON, seed: 19, step: 0.1)
        centeredBox.advance(by: 0.1)
        let centeredBoxOffsets = centeredBox.particles.map {
            $0.position - SIMD3(10, 20, 30)
        }
        var explicitCenteredBox = simulator(
            explicitCenteredBoxJSON, seed: 23, step: 0.1
        )
        explicitCenteredBox.advance(by: 0.1)
        let explicitCenteredOffsets = explicitCenteredBox.particles.map(\.position)
        var positiveBox = simulator(positiveBoxJSON, seed: 29, step: 0.1)
        positiveBox.advance(by: 0.1)
        let positiveBoxPositions = positiveBox.particles.map(\.position)

        var movement = simulator(movementJSON, seed: 1, step: 0.25)
        movement.advance(by: 0.5)
        let movementPosition = movement.particles[0].position
        movement.advance(by: 1.25)
        let scaledWorld = simd_float4x4(
            SIMD4(2, 0, 0, 0),
            SIMD4(0, 4, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        )
        var worldMovement = simulator(
            worldMovementJSON,
            seed: 1,
            step: 0.5,
            worldSpaceFrame: SceneParticleWorldSpaceFrame(worldFrame: scaledWorld)
        )
        worldMovement.advance(by: 0.5)

        let overrideRoot = try object(overrideJSON)
        let parsedOverride = SceneParticleDefinitionParser().parseInstanceOverride(overrideRoot)
        var overridden = simulator(overrideDefinitionJSON, override: parsedOverride, seed: 1, step: 0.25)
        overridden.advance(by: 0.25)
        let overriddenParticle = overridden.particles[0]
        overridden.advance(by: 1.0)
        let authoredLiveOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"alpha":{"user":"alpha","value":1},"size":{"user":"size","value":1},"count":{"user":"count","value":1},"colorn":{"user":"color","value":"1 1 1"}}"#)
        )
        var liveOverride = simulator(
            liveOverrideDefinitionJSON, override: authoredLiveOverride, seed: 1, step: 0.25
        )
        let zeroCountOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"count":0}"#)
        )
        liveOverride.advance(by: 0.25, dynamicInstanceOverride: zeroCountOverride)
        let liveZeroCount = liveOverride.particles.count
        let currentOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"alpha":0.25,"size":3,"count":2,"colorn":"0.5 1 0.25"}"#)
        )
        liveOverride.advance(by: 0.25, dynamicInstanceOverride: currentOverride)
        let liveParticle = liveOverride.particles[0]
        liveOverride.advance(by: 0.25)
        let fallbackParticle = liveOverride.particles.last!
        var colorDenied = simulator(
            overrideDefinition(flags: 8), override: parsedOverride, seed: 1, step: 0.25
        )
        colorDenied.advance(by: 0.25)
        var speedDenied = simulator(
            overrideDefinition(flags: 16), override: parsedOverride, seed: 1, step: 0.25
        )
        speedDenied.advance(by: 0.25)
        var countDenied = simulator(
            overrideDefinition(flags: 32), override: parsedOverride, seed: 1, step: 0.25
        )
        countDenied.advance(by: 1.25)
        var lifetimeDenied = simulator(
            overrideDefinition(flags: 64), override: parsedOverride, seed: 1, step: 0.25
        )
        lifetimeDenied.advance(by: 0.25)
        var sizeDenied = simulator(
            overrideDefinition(flags: 128), override: parsedOverride, seed: 1, step: 0.25
        )
        sizeDenied.advance(by: 0.25)
        let controlPointOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"controlpoint1":"2 3 4"}"#)
        )
        var dynamicControlPoint = simulator(
            dynamicControlPointJSON,
            override: controlPointOverride,
            seed: 1,
            step: 1
        )
        dynamicControlPoint.advance(
            by: 1,
            dynamicControlPoints: [1: SIMD3(10, 20, 30)]
        )
        dynamicControlPoint.advance(
            by: 1,
            dynamicControlPoints: [1: SIMD3(-5, 6, 7)]
        )
        dynamicControlPoint.advance(by: 1)
        var authoredControlPoint = simulator(
            authoredControlPointIdentityJSON, seed: 1, step: 1
        )
        authoredControlPoint.advance(by: 1)
        var implicitControlPoint = simulator(
            implicitControlPointJSON, seed: 1, step: 1
        )
        implicitControlPoint.advance(by: 1)
        var duplicateControlPoint = simulator(
            malformedControlPointJSON(#"[{"id":0},{"id":1},{"id":1}]"#),
            seed: 1, step: 1
        )
        duplicateControlPoint.advance(by: 1)
        var outOfRangeControlPoint = simulator(
            malformedControlPointJSON(#"[{"id":8}]"#), seed: 1, step: 1
        )
        outOfRangeControlPoint.advance(by: 1)
        var missingControlPointID = simulator(
            malformedControlPointJSON(#"[{"offset":"1 0 0"}]"#), seed: 1, step: 1
        )
        missingControlPointID.advance(by: 1)
        var outOfRangeControlPointSource = simulator(
            implicitControlPointJSON.replacingOccurrences(
                of: #""controlpoint":3"#, with: #""controlpoint":8"#
            ), seed: 1, step: 1
        )
        outOfRangeControlPointSource.advance(by: 1)
        var fixedEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmin":3,"speedmax":3"#), seed: 1, step: 1
        )
        fixedEmitterSpeed.advance(by: 1)
        var maxOnlyEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmax":4"#, count: 16), seed: 1, step: 1
        )
        maxOnlyEmitterSpeed.advance(by: 1)
        var negativeEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmin":-1,"speedmax":1"#), seed: 1, step: 1
        )
        negativeEmitterSpeed.advance(by: 1)
        var reversedEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmin":5,"speedmax":1"#), seed: 1, step: 1
        )
        reversedEmitterSpeed.advance(by: 1)
        var minOnlyEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmin":1"#), seed: 1, step: 1
        )
        minOnlyEmitterSpeed.advance(by: 1)
        var nonfiniteEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmin":"nan","speedmax":1"#), seed: 1, step: 1
        )
        nonfiniteEmitterSpeed.advance(by: 1)
        var overBudgetEmitterSpeed = simulator(
            emitterSpeedJSON(#""speedmax":1000001"#), seed: 1, step: 1
        )
        overBudgetEmitterSpeed.advance(by: 1)
        var sphereDirectionSign = simulator(
            emitterShapeJSON(
                #""name":"sphererandom","directions":"2 0 1","sign":"-1 0 1","distancemin":10,"distancemax":10"#
            ), seed: 3, step: 1
        )
        sphereDirectionSign.advance(by: 1)
        var zeroDirections = simulator(
            emitterShapeJSON(
                #""name":"sphererandom","origin":"7 8 9","directions":"0 0 0","sign":"0 0 0","distancemin":10,"distancemax":10"#,
                count: 8
            ), seed: 3, step: 1
        )
        zeroDirections.advance(by: 1)
        var boxDirections = simulator(
            emitterShapeJSON(
                #""name":"boxrandom","directions":"2 -1 0","distancemin":"1 2 3","distancemax":"2 4 5""#
            ), seed: 3, step: 1
        )
        boxDirections.advance(by: 1)
        let invalidEmitterShapes = [
            #""name":"sphererandom","directions":"nan 1 0""#,
            #""name":"sphererandom","directions":"1000001 1 0""#,
            #""name":"sphererandom","directions":"1 1 0","sign":"2 0 0""#,
            #""name":"sphererandom","directions":"1 1""#,
            #""name":"sphererandom","directions":"bad""#,
            #""name":"boxrandom","directions":"1 1 0","sign":"1 0 0""#,
        ].map { fields -> SceneParticleSimulator in
            var simulator = simulator(emitterShapeJSON(fields), seed: 3, step: 1)
            simulator.advance(by: 1)
            return simulator
        }
        var pointerPull = simulator(
            controlPointForceJSON(scale: "2", threshold: "20"), seed: 1, step: 1
        )
        pointerPull.advance(by: 1, dynamicControlPoints: [1: SIMD3(10, 0, 0)])
        var pointerPush = simulator(
            controlPointForceJSON(scale: "-2", threshold: "20"), seed: 1, step: 1
        )
        pointerPush.advance(by: 1, dynamicControlPoints: [1: SIMD3(10, 0, 0)])
        var pointerOutside = simulator(
            controlPointForceJSON(scale: "2", threshold: "5"), seed: 1, step: 1
        )
        pointerOutside.advance(by: 1, dynamicControlPoints: [1: SIMD3(10, 0, 0)])
        var pointerAtCenter = simulator(
            controlPointForceJSON(scale: "2", threshold: "20"), seed: 1, step: 1
        )
        pointerAtCenter.advance(by: 1, dynamicControlPoints: [1: .zero])
        let pointerDefinition = SceneParticleDefinitionParser().parse(
            root: try! object(controlPointForceJSON(scale: "2", threshold: "20"))
        )
        let pointerMapped = pointerDefinition.pointerControlPointValues(
            at: SIMD3(3, 4, 0)
        )[1]
        let pointerOutsideMapped = pointerDefinition.pointerControlPointValues(at: nil)[1]
        let duplicatePointerDefinition = SceneParticleDefinitionParser().parse(
            root: try! object(controlPointForceJSON(
                scale: "2",
                threshold: "20",
                controlPointSuffix: #",{"id":1,"flags":1,"offset":"0 0 0"}"#
            ))
        )
        let invalidControlPointForces = [
            controlPointForceJSON(scale: #""nan""#, threshold: "20"),
            controlPointForceJSON(scale: "2", threshold: "-1"),
            controlPointForceJSON(scale: #""1 2 3""#, threshold: "20"),
            controlPointForceJSON(scale: "2", threshold: "20", flags: 3),
            controlPointForceJSON(scale: "2", threshold: "20", extra: #", "blendinstart":0"#),
            controlPointForceJSON(scale: "2", threshold: "20", controlPoint: 8),
            controlPointForceJSON(scale: "2", threshold: "20", pointOffset: "0 0"),
            controlPointForceJSON(scale: "2", threshold: "20", systemFlags: 1),
            controlPointForceJSON(scale: "2", threshold: "20", systemFlags: 4),
            controlPointForceJSON(scale: "2", threshold: "20", movementFlags: 1),
        ].map { source -> SceneParticleSimulator in
            var simulator = simulator(source, seed: 1, step: 1)
            simulator.advance(by: 1, dynamicControlPoints: [1: SIMD3(10, 0, 0)])
            return simulator
        }

        var operators = simulator(operatorJSON, seed: 1, step: 0.25)
        operators.advance(by: 0.25)
        let operatorParticle = operators.particles[0]
        var lifetimeOscillation = simulator(
            lifetimeOscillationJSON,
            seed: 1,
            step: 1
        )
        lifetimeOscillation.advance(by: 1)
        let quarterLifeOscillationAlpha = lifetimeOscillation.particles[0].alpha
        lifetimeOscillation.advance(by: 1)
        let halfLifeOscillationAlpha = lifetimeOscillation.particles[0].alpha
        let halfLifeOscillationSize = lifetimeOscillation.particles[0].size
        var fineLifetimeOscillation = simulator(
            lifetimeOscillationJSON,
            seed: 1,
            step: 1.0 / 60.0
        )
        fineLifetimeOscillation.advance(by: 2)
        let fineHalfLifeOscillationAlpha = fineLifetimeOscillation.particles[0].alpha
        let fineHalfLifeOscillationSize = fineLifetimeOscillation.particles[0].size
        var positionOscillation = simulator(
            positionOscillationJSON,
            seed: 1,
            step: 1
        )
        positionOscillation.advance(by: 2)
        let quarterLifeOscillationPosition = positionOscillation.particles[0].position
        positionOscillation.advance(by: 2)
        let halfLifeOscillationPosition = positionOscillation.particles[0].position
        var finePositionOscillation = simulator(
            positionOscillationJSON,
            seed: 1,
            step: 1.0 / 60.0
        )
        finePositionOscillation.advance(by: 4)
        let fineHalfLifeOscillationPosition =
            finePositionOscillation.particles[0].position
        var longPositionOscillation = simulator(
            longPositionOscillationJSON,
            seed: 1,
            step: 1
        )
        longPositionOscillation.advance(by: 4)
        let longQuarterLifeOscillationPosition =
            longPositionOscillation.particles[0].position

        let diagnosticOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"size":{"script":"return 2","value":2}}"#)
        )
        let diagnosticSimulator = simulator(
            diagnosticJSON, override: diagnosticOverride, seed: 1, step: 0.1
        )
        var colors = simulator(colorJSON, seed: 1, step: 0.1)
        colors.advance(by: 0.1)
        let randomColor = colors.particles[0].color
        let colorAmount = (randomColor.x * 255 - 10) / 230
        let expectedGreen = (40 + 160 * colorAmount) / 255
        let expectedBlue = (80 + 80 * colorAmount) / 255
        var uniformSize = simulator(uniformSizeJSON, seed: 17, step: 0.1)
        var biasedSize = simulator(biasedSizeJSON, seed: 17, step: 0.1)
        uniformSize.advance(by: 0.1)
        biasedSize.advance(by: 0.1)
        let uniformSizeAmount = (uniformSize.particles[0].size - 20) / 30
        let biasedSizeAmount = (biasedSize.particles[0].size - 20) / 30
        var maximumSize = simulator(maximumSizeJSON, seed: 17, step: 0.1)
        maximumSize.advance(by: 0.1)
        var uniformVelocity = simulator(uniformVelocityJSON, seed: 31, step: 0.1)
        var biasedVelocity = simulator(biasedVelocityJSON, seed: 31, step: 0.1)
        uniformVelocity.advance(by: 0.1)
        biasedVelocity.advance(by: 0.1)
        let uniformVelocityAmount = (uniformVelocity.particles[0].velocity
            - SIMD3(10, 20, 30)) / SIMD3(10, 20, 20)
        let biasedVelocityAmount = (biasedVelocity.particles[0].velocity
            - SIMD3(10, 20, 30)) / SIMD3(10, 20, 20)
        var uniformColor = simulator(uniformColorJSON, seed: 37, step: 0.1)
        var biasedColor = simulator(biasedColorJSON, seed: 37, step: 0.1)
        uniformColor.advance(by: 0.1)
        biasedColor.advance(by: 0.1)
        let uniformColorAmount = (
            uniformColor.particles[0].color.x * 255 - 10
        ) / 230
        let biasedColorAmount = (
            biasedColor.particles[0].color.x * 255 - 10
        ) / 230

        var turbulentFirst = simulator(turbulentJSON, seed: 71, step: 0.1)
        var turbulentRepeat = simulator(turbulentJSON, seed: 71, step: 0.1)
        var turbulentDifferent = simulator(turbulentJSON, seed: 72, step: 0.1)
        turbulentFirst.advance(by: 0.1)
        turbulentRepeat.advance(by: 0.1)
        turbulentDifferent.advance(by: 0.1)
        let turbulentVelocity = turbulentFirst.particles[0].velocity
        let turbulentDefinition = try SceneParticleDefinitionParser().parse(
            root: object(turbulentJSON)
        )
        let turbulentValue = turbulentDefinition.initializers[1].turbulentVelocity
        var earlyRandom = SceneParticleRandomGenerator(state: 91)
        var lateRandom = SceneParticleRandomGenerator(state: 91)
        let earlyVelocity = SceneParticleSimulationMath.turbulentVelocity(
            turbulentValue, SIMD3(4, 8, 0), 0, &earlyRandom
        )
        let lateVelocity = SceneParticleSimulationMath.turbulentVelocity(
            turbulentValue, SIMD3(4, 8, 0), 2, &lateRandom
        )
        var zeroScaleTurbulent = simulator(zeroScaleTurbulentJSON, seed: 71, step: 0.1)
        zeroScaleTurbulent.advance(by: 0.1)
        var offsetTurbulent = simulator(offsetTurbulentJSON, seed: 71, step: 0.1)
        offsetTurbulent.advance(by: 0.1)
        var audioTurbulent = simulator(audioTurbulentJSON, seed: 71, step: 0.1)
        audioTurbulent.advance(by: 0.1)

        var turbulenceOperator = simulator(turbulenceOperatorJSON, seed: 71, step: 0.1)
        var turbulenceOperatorPartitioned = simulator(
            turbulenceOperatorJSON, seed: 71, step: 0.1
        )
        var turbulenceOperatorDifferentSeed = simulator(
            turbulenceOperatorJSON, seed: 72, step: 0.1
        )
        var turbulenceOperatorOneStep = simulator(
            turbulenceOperatorJSON, seed: 71, step: 0.1
        )
        turbulenceOperator.advance(by: 0.3)
        turbulenceOperatorPartitioned.advance(by: 0.1)
        turbulenceOperatorPartitioned.advance(by: 0.2)
        turbulenceOperatorDifferentSeed.advance(by: 0.3)
        turbulenceOperatorOneStep.advance(by: 0.1)
        let turbulenceOperatorVelocity = turbulenceOperatorOneStep.particles[0].velocity

        var zeroTimeTurbulence = simulator(
            zeroTimeTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        zeroTimeTurbulence.advance(by: 0.3)
        var xOnlyTurbulence = simulator(
            xOnlyTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        xOnlyTurbulence.advance(by: 0.1)
        var defaultTurbulence = simulator(
            defaultTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        defaultTurbulence.advance(by: 0.1)
        var blendedTurbulence = simulator(
            blendedTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        blendedTurbulence.advance(by: 0.1)
        let turbulenceOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"speed":2}"#)
        )
        var overriddenTurbulence = simulator(
            turbulenceOperatorJSON,
            override: turbulenceOverride,
            seed: 71,
            step: 0.1
        )
        overriddenTurbulence.advance(by: 0.1)
        var audioOperatorTurbulence = simulator(
            audioTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        audioOperatorTurbulence.advance(by: 0.1)
        var turbulenceBeforeMovement = simulator(
            turbulenceBeforeMovementJSON, seed: 71, step: 0.1
        )
        var movementBeforeTurbulence = simulator(
            movementBeforeTurbulenceJSON, seed: 71, step: 0.1
        )
        turbulenceBeforeMovement.advance(by: 0.1)
        movementBeforeTurbulence.advance(by: 0.1)
        var overflowTurbulence = simulator(
            overflowTurbulenceOperatorJSON, seed: 71, step: 0.1
        )
        overflowTurbulence.advance(by: 0.1)

        var vortex = simulator(vortexJSON(), seed: 81, step: 1)
        vortex.advance(by: 1)
        var vortexPartitioned = simulator(vortexJSON(), seed: 81, step: 0.25)
        vortexPartitioned.advance(by: 0.5)
        vortexPartitioned.advance(by: 0.5)
        var reverseVortex = simulator(
            vortexJSON(speedInner: "0", speedOuter: "-100"), seed: 81, step: 1
        )
        reverseVortex.advance(by: 1)
        var yAxisVortex = simulator(
            vortexJSON(axis: "0 1 0"), seed: 81, step: 1
        )
        yAxisVortex.advance(by: 1)
        var infiniteAxisVortex = simulator(
            vortexJSON(position: "10 0 100", distanceOuter: "100", flags: 1),
            seed: 81, step: 1
        )
        infiniteAxisVortex.advance(by: 1)
        var finiteAxisVortex = simulator(
            vortexJSON(position: "10 0 100", distanceOuter: "100"), seed: 81, step: 1
        )
        finiteAxisVortex.advance(by: 1)
        let vortexOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"speed":2}"#)
        )
        var overriddenVortex = simulator(
            vortexJSON(), override: vortexOverride, seed: 81, step: 1
        )
        overriddenVortex.advance(by: 1)
        var overrideDeniedVortex = simulator(
            vortexJSON(systemFlags: 16), override: vortexOverride, seed: 81, step: 1
        )
        overrideDeniedVortex.advance(by: 1)
        let invalidVortices = [
            vortexJSON(axis: "0 0"),
            vortexJSON(axis: "0 0 0"),
            vortexJSON(distanceInner: "10", distanceOuter: "0"),
            vortexJSON(speedOuter: "null"),
            vortexJSON(flags: 2),
            vortexJSON(extra: #", "future":1"#),
            vortexJSON(extra: #", "blendinstart":0"#),
            vortexJSON(extra: #", "audioprocessingmode":1"#),
            vortexJSON(speedOuter: #""nan""#),
            vortexJSON(distanceInner: "10", distanceOuter: "10"),
        ].map { source -> SceneParticleSimulator in
            var value = simulator(source, seed: 81, step: 1)
            value.advance(by: 1)
            return value
        }
        var vortexV2 = simulator(vortexV2JSON, seed: 81, step: 1)
        vortexV2.advance(by: 1)

        var periodic = simulator(periodicJSON, seed: 101, step: 0.25)
        periodic.advance(by: 0.5)
        let periodicFirstWindowCount = periodic.particles.count
        periodic.advance(by: 0.5)
        let periodicDelayCount = periodic.particles.count
        periodic.advance(by: 0.5)
        let periodicSecondWindowCount = periodic.particles.count
        var periodicPartitioned = simulator(periodicJSON, seed: 101, step: 0.25)
        periodicPartitioned.advance(by: 0.25)
        periodicPartitioned.advance(by: 1.25)
        var periodicAuthorOff = simulator(periodicAuthorOffJSON, seed: 101, step: 0.25)
        periodicAuthorOff.advance(by: 1.5)
        var periodicMalformed = simulator(periodicMalformedJSON, seed: 101, step: 0.25)
        periodicMalformed.advance(by: 1.5)
        var periodicBurst = simulator(periodicBurstJSON, seed: 101, step: 0.25)
        periodicBurst.advance(by: 1.5)
        var periodicLimited = simulator(periodicLimitedJSON, seed: 101, step: 0.25)
        periodicLimited.advance(by: 1.5)
        let periodicOverride = SceneParticleDefinitionParser().parseInstanceOverride(
            try object(#"{"rate":2}"#)
        )
        var periodicOverridden = simulator(
            periodicJSON, override: periodicOverride, seed: 101, step: 0.25
        )
        periodicOverridden.advance(by: 1.5)

        let layerImageDefinition = SceneParticleDefinitionParser().parse(
            root: try object(layerImageJSON)
        )
        let layerImageMap = SceneParticleLayerImageEmissionMap(
            positions: [SIMD3(-15, 5, 0)]
        )
        var layerImage = SceneParticleSimulator(
            definition: layerImageDefinition, seed: 1, fixedTimeStep: 0.1,
            layerImageEmissionMap: layerImageMap
        )
        var layerImageMissingMap = SceneParticleSimulator(
            definition: layerImageDefinition, seed: 1, fixedTimeStep: 0.1
        )
        layerImage.advance(by: 0.1)
        layerImageMissingMap.advance(by: 0.1)

        return [
            "deterministic": first.particles == partitioned.particles,
            "differentSeed": first.particles != different.particles,
            "birthEventIDs": birthEvents.map(\.id),
            "birthEventsDeterministic": birthEvents == partitionedBirthEvents,
            "birthEventsDrain": first.consumeBirthEvents().isEmpty,
            "maxCount": capped.particles.count,
            "budgetCount": budgeted.particles.count,
            "prewarmCount": prewarmed.particles.count,
            "prewarmTime": prewarmed.simulationTime,
            "prewarmBirthEvents": prewarmed.birthEvents.count,
            "deathEventCount": deathEvents.count,
            "deathEventPosition": deathEvents.first.map { vector($0.position) } ?? [],
            "deathEventsDrain": death.consumeDeathEvents().isEmpty,
            "deathParticles": death.particles.count,
            "durationCount": burst.particles.count,
            "sphereMinimumRadius": sphereRadii.min() ?? -1,
            "sphereMaximumRadius": sphereRadii.max() ?? -1,
            "boxInBounds": boxOffsets.allSatisfy {
                (-1...1).contains($0.x) && (-2...2).contains($0.y) && (-3...3).contains($0.z)
            },
            "centeredBoxInBounds": centeredBoxOffsets.allSatisfy {
                (-4...4).contains($0.x) && (-3...3).contains($0.y) && abs($0.z) < 1e-12
            },
            "centeredBoxHasBothSigns":
                centeredBoxOffsets.contains(where: { $0.x < 0 })
                && centeredBoxOffsets.contains(where: { $0.x > 0 })
                && centeredBoxOffsets.contains(where: { $0.y < 0 })
                && centeredBoxOffsets.contains(where: { $0.y > 0 }),
            "explicitCenteredBoxHasBothSigns":
                explicitCenteredOffsets.contains(where: { $0.x < 0 })
                && explicitCenteredOffsets.contains(where: { $0.x > 0 })
                && explicitCenteredOffsets.contains(where: { $0.y < 0 })
                && explicitCenteredOffsets.contains(where: { $0.y > 0 }),
            "positiveBoxPreservesInterval": positiveBoxPositions.allSatisfy {
                (2...4).contains($0.x)
                    && (3...5).contains($0.y)
                    && (1...2).contains($0.z)
            },
            "movementPosition": vector(movementPosition),
            "worldMovementPosition": vector(worldMovement.particles[0].position),
            "worldMovementLocalVelocity": vector(worldMovement.particles[0].velocity),
            "fadeAlpha": movement.particles[0].alpha,
            "overrideLifetime": overriddenParticle.lifetime,
            "overrideSize": overriddenParticle.size,
            "overrideVelocity": vector(overriddenParticle.velocity),
            "overrideAlpha": overriddenParticle.alpha,
            "overrideColor": vector(overriddenParticle.color),
            "overrideEmissionCount": overridden.particles.count,
            "colorDeniedColor": vector(colorDenied.particles[0].color),
            "colorDeniedAlpha": colorDenied.particles[0].alpha,
            "speedDeniedVelocity": vector(speedDenied.particles[0].velocity),
            "countDeniedEmissionCount": countDenied.particles.count,
            "lifetimeDeniedLifetime": lifetimeDenied.particles[0].lifetime,
            "sizeDeniedSize": sizeDenied.particles[0].size,
            "dynamicControlPointPositions": dynamicControlPoint.particles.map {
                vector($0.position)
            },
            "authoredControlPointPosition":
                authoredControlPoint.particles.first.map { vector($0.position) } ?? [],
            "authoredControlPointDiagnostics":
                authoredControlPoint.diagnostics.map(\.kind.rawValue),
            "implicitControlPointPosition":
                implicitControlPoint.particles.first.map { vector($0.position) } ?? [],
            "implicitControlPointDiagnostics":
                implicitControlPoint.diagnostics.map(\.kind.rawValue),
            "invalidControlPointCounts": [
                duplicateControlPoint.particles.count,
                outOfRangeControlPoint.particles.count,
                missingControlPointID.particles.count,
                outOfRangeControlPointSource.particles.count,
            ],
            "invalidControlPointDiagnostics": [
                duplicateControlPoint, outOfRangeControlPoint,
                missingControlPointID, outOfRangeControlPointSource,
            ].map { $0.diagnostics.map(\.kind.rawValue) },
            "fixedEmitterSpeedPosition":
                fixedEmitterSpeed.particles.first.map { vector($0.position) } ?? [],
            "fixedEmitterSpeedVelocity":
                fixedEmitterSpeed.particles.first.map { vector($0.velocity) } ?? [],
            "fixedEmitterSpeedDiagnostics":
                fixedEmitterSpeed.diagnostics.map(\.kind.rawValue),
            "maxOnlyEmitterSpeeds": maxOnlyEmitterSpeed.particles.map { $0.velocity.x },
            "maxOnlyEmitterSpeedDiagnostics":
                maxOnlyEmitterSpeed.diagnostics.map(\.kind.rawValue),
            "invalidEmitterSpeedCounts": [
                negativeEmitterSpeed, reversedEmitterSpeed,
                minOnlyEmitterSpeed, nonfiniteEmitterSpeed, overBudgetEmitterSpeed,
            ].map { $0.particles.count },
            "invalidEmitterSpeedDiagnostics": [
                negativeEmitterSpeed, reversedEmitterSpeed,
                minOnlyEmitterSpeed, nonfiniteEmitterSpeed, overBudgetEmitterSpeed,
            ].map { $0.diagnostics.map(\.kind.rawValue) },
            "sphereDirectionSignBounded": sphereDirectionSign.particles.count == 64
                && sphereDirectionSign.particles.allSatisfy { particle in
                    let position = particle.position
                    return position.x <= 0 && abs(position.y) < 1e-12 && position.z >= 0
                        && abs(sqrt(position.x * position.x / 4 + position.z * position.z) - 10) < 1e-9
                }
                && sphereDirectionSign.particles.contains { $0.position.x < -1e-6 }
                && sphereDirectionSign.particles.contains { $0.position.z > 1e-6 },
            "sphereDirectionSignDiagnostics":
                sphereDirectionSign.diagnostics.map(\.kind.rawValue),
            "zeroDirectionsStayAtOrigin": zeroDirections.particles.count == 8
                && zeroDirections.particles.allSatisfy { $0.position == SIMD3(7, 8, 9) },
            "zeroDirectionsDiagnostics": zeroDirections.diagnostics.map(\.kind.rawValue),
            "boxDirectionsBounded": boxDirections.particles.count == 64
                && boxDirections.particles.allSatisfy { particle in
                    let position = particle.position
                    return (2 ... 4).contains(position.x)
                        && (-4 ... -2).contains(position.y) && position.z == 0
                },
            "boxDirectionsDiagnostics": boxDirections.diagnostics.map(\.kind.rawValue),
            "invalidEmitterShapeCounts": invalidEmitterShapes.map { $0.particles.count },
            "invalidEmitterShapeDiagnostics": invalidEmitterShapes.map {
                $0.diagnostics.map(\.kind.rawValue)
            },
            "pointerPullVelocity": vector(pointerPull.particles[0].velocity),
            "pointerPushVelocity": vector(pointerPush.particles[0].velocity),
            "pointerOutsideVelocity": vector(pointerOutside.particles[0].velocity),
            "pointerAtCenterVelocity": vector(pointerAtCenter.particles[0].velocity),
            "pointerMapped": pointerMapped.map(vector) ?? [],
            "pointerOutsideInactive": pointerOutsideMapped?.x.isNaN == true
                && pointerOutsideMapped?.y.isNaN == true
                && pointerOutsideMapped?.z.isNaN == true,
            "duplicatePointerRejected": duplicatePointerDefinition
                .pointerControlPointValues(at: SIMD3(3, 4, 0)).isEmpty,
            "pointerPullDiagnostics": pointerPull.diagnostics.map(\.kind.rawValue).sorted(),
            "invalidControlPointForceVelocities": invalidControlPointForces.map {
                vector($0.particles[0].velocity)
            },
            "invalidControlPointForceDiagnostics": invalidControlPointForces.map {
                $0.diagnostics.map(\.kind.rawValue)
            },
            "overrideDiagnostics": overridden.diagnostics.map(\.kind.rawValue),
            "liveOverrideDiagnostics": liveOverride.diagnostics.map(\.kind.rawValue),
            "liveZeroCount": liveZeroCount,
            "liveDynamicCount": liveOverride.particles.count - 1,
            "liveDynamicAlpha": liveParticle.alpha,
            "liveDynamicSize": liveParticle.size,
            "liveDynamicColor": vector(liveParticle.color),
            "liveFallbackAlpha": fallbackParticle.alpha,
            "liveFallbackSize": fallbackParticle.size,
            "liveFallbackColor": vector(fallbackParticle.color),
            "operatorAlpha": operatorParticle.alpha,
            "operatorSize": operatorParticle.size,
            "operatorColor": vector(operatorParticle.color),
            "operatorRotation": vector(operatorParticle.rotation),
            "operatorPosition": vector(operatorParticle.position),
            "quarterLifeOscillationAlpha": quarterLifeOscillationAlpha,
            "halfLifeOscillationAlpha": halfLifeOscillationAlpha,
            "fineHalfLifeOscillationAlpha": fineHalfLifeOscillationAlpha,
            "halfLifeOscillationSize": halfLifeOscillationSize,
            "fineHalfLifeOscillationSize": fineHalfLifeOscillationSize,
            "quarterLifeOscillationPosition":
                vector(quarterLifeOscillationPosition),
            "halfLifeOscillationPosition":
                vector(halfLifeOscillationPosition),
            "fineHalfLifeOscillationPosition":
                vector(fineHalfLifeOscillationPosition),
            "longQuarterLifeOscillationPosition":
                vector(longQuarterLifeOscillationPosition),
            "colorUsesSingleInterpolation": abs(randomColor.y - expectedGreen) < 1e-12
                && abs(randomColor.z - expectedBlue) < 1e-12,
            "uniformSizeAmount": uniformSizeAmount,
            "biasedSizeAmount": biasedSizeAmount,
            "maximumSize": maximumSize.particles[0].size,
            "uniformVelocityAmount": vector(uniformVelocityAmount),
            "biasedVelocityAmount": vector(biasedVelocityAmount),
            "uniformColorAmount": uniformColorAmount,
            "biasedColorAmount": biasedColorAmount,
            "turbulentDeterministic": turbulentFirst.particles == turbulentRepeat.particles,
            "turbulentDifferentSeed": turbulentFirst.particles != turbulentDifferent.particles,
            "turbulentDifferentTime": earlyVelocity != lateVelocity,
            "turbulentSpeed": length(turbulentVelocity),
            "turbulentPlanar": abs(turbulentVelocity.z) < 1e-12,
            "zeroScaleTurbulentVelocity": vector(zeroScaleTurbulent.particles[0].velocity),
            "offsetTurbulentVelocity": vector(offsetTurbulent.particles[0].velocity),
            "turbulentDiagnostics": turbulentFirst.diagnostics.map(\.kind.rawValue),
            "audioTurbulentVelocity": vector(audioTurbulent.particles[0].velocity),
            "audioTurbulentDiagnostics": audioTurbulent.diagnostics.map(\.kind.rawValue).sorted(),
            "turbulenceOperatorDeterministic":
                turbulenceOperator.particles == turbulenceOperatorPartitioned.particles,
            "turbulenceOperatorDifferentSeed":
                turbulenceOperator.particles != turbulenceOperatorDifferentSeed.particles,
            "turbulenceOperatorTimeScale":
                turbulenceOperator.particles != zeroTimeTurbulence.particles,
            "turbulenceOperatorSpeed": length(turbulenceOperatorVelocity),
            "turbulenceOperatorPlanar": abs(turbulenceOperatorVelocity.z) < 1e-12,
            "xOnlyTurbulenceVelocity": vector(xOnlyTurbulence.particles[0].velocity),
            "defaultTurbulenceSpeed": length(defaultTurbulence.particles[0].velocity),
            "blendedTurbulenceVelocity": vector(blendedTurbulence.particles[0].velocity),
            "overriddenTurbulenceSpeed": length(overriddenTurbulence.particles[0].velocity),
            "turbulenceOperatorDiagnostics": turbulenceOperator.diagnostics.map(\.kind.rawValue),
            "audioOperatorTurbulenceVelocity":
                vector(audioOperatorTurbulence.particles[0].velocity),
            "audioOperatorTurbulenceDiagnostics":
                audioOperatorTurbulence.diagnostics.map(\.kind.rawValue).sorted(),
            "turbulenceBeforeMovementPosition":
                vector(turbulenceBeforeMovement.particles[0].position),
            "movementBeforeTurbulencePosition":
                vector(movementBeforeTurbulence.particles[0].position),
            "overflowTurbulenceVelocity": vector(overflowTurbulence.particles[0].velocity),
            "vortexVelocity": vector(vortex.particles[0].velocity),
            "vortexDiagnostics": vortex.diagnostics.map(\.kind.rawValue),
            "vortexPartitioned": vortex.particles == vortexPartitioned.particles,
            "reverseVortexVelocity": vector(reverseVortex.particles[0].velocity),
            "yAxisVortexVelocity": vector(yAxisVortex.particles[0].velocity),
            "infiniteAxisVortexVelocity": vector(infiniteAxisVortex.particles[0].velocity),
            "finiteAxisVortexVelocity": vector(finiteAxisVortex.particles[0].velocity),
            "overriddenVortexVelocity": vector(overriddenVortex.particles[0].velocity),
            "overrideDeniedVortexVelocity": vector(overrideDeniedVortex.particles[0].velocity),
            "invalidVortexVelocities": invalidVortices.map { vector($0.particles[0].velocity) },
            "invalidVortexDiagnostics": invalidVortices.map {
                $0.diagnostics.map(\.kind.rawValue).sorted()
            },
            "vortexV2Velocity": vector(vortexV2.particles[0].velocity),
            "vortexV2Diagnostics": vortexV2.diagnostics.map(\.kind.rawValue),
            "periodicFirstWindowCount": periodicFirstWindowCount,
            "periodicDelayCount": periodicDelayCount,
            "periodicSecondWindowCount": periodicSecondWindowCount,
            "periodicDeterministic": periodic.particles == periodicPartitioned.particles,
            "periodicDiagnostics": periodic.diagnostics.map(\.kind.rawValue),
            "periodicAuthorOffCount": periodicAuthorOff.particles.count,
            "periodicMalformedCount": periodicMalformed.particles.count,
            "periodicMalformedDiagnostics": periodicMalformed.diagnostics.map(\.kind.rawValue),
            "periodicBurstCount": periodicBurst.particles.count,
            "periodicBurstDiagnostics": periodicBurst.diagnostics.map(\.kind.rawValue),
            "periodicLimitedCount": periodicLimited.particles.count,
            "periodicLimitedDiagnostics": periodicLimited.diagnostics.map(\.kind.rawValue),
            "periodicOverriddenCount": periodicOverridden.particles.count,
            "periodicOverriddenDiagnostics": periodicOverridden.diagnostics.map(\.kind.rawValue),
            "layerImagePosition": layerImage.particles.first.map { vector($0.position) } ?? [],
            "layerImageMissingMapCount": layerImageMissingMap.particles.count,
            "diagnostics": diagnosticSimulator.diagnostics.map(\.kind.rawValue).sorted()
        ]
    }

    private static func simulator(
        _ source: String,
        override: SceneParticleInstanceOverride? = nil,
        seed: UInt64,
        step: Double,
        particleBudget: Int? = nil,
        worldSpaceFrame: SceneParticleWorldSpaceFrame? = nil
    ) -> SceneParticleSimulator {
        let definition = SceneParticleDefinitionParser().parse(root: try! object(source))
        return SceneParticleSimulator(
            definition: definition,
            instanceOverride: override,
            seed: seed,
            fixedTimeStep: step,
            particleBudget: particleBudget,
            worldSpaceFrame: worldSpaceFrame
        )
    }

    private static let deterministicJSON = #"""
    {"material":"p.json","maxcount":64,
     "emitter":[{"name":"sphererandom","instantaneous":2,"rate":8,"distancemin":1,"distancemax":2,"speedmin":1,"speedmax":3}],
     "initializer":[{"name":"lifetimerandom","min":5,"max":5},{"name":"sizerandom","min":1,"max":2},{"name":"velocityrandom","min":"-1 -1 0","max":"1 1 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let layerImageJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"layerimage","instantaneous":1}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let maximumCountJSON = #"""
    {"material":"p.json","maxcount":3,
     "emitter":[{"name":"boxrandom","instantaneous":100,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let prewarmJSON = #"""
    {"material":"p.json","maxcount":64,"starttime":1,
     "emitter":[{"name":"boxrandom","rate":10,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let durationJSON = #"""
    {"material":"p.json","maxcount":64,
     "emitter":[{"name":"boxrandom","instantaneous":3,"rate":100,"duration":0.25,"flags":2,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let deathJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":0.2,"max":0.2},{"name":"velocityrandom","min":"2 0 0","max":"2 0 0"}],
     "operator":[{"name":"movement"}],"renderer":[{"name":"sprite"}]}
    """#

    private static let boundsJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[
       {"name":"sphererandom","instantaneous":50,"origin":"10 20 30","directions":"1 1 1","distancemin":2,"distancemax":4},
       {"name":"boxrandom","instantaneous":50,"origin":"-10 -20 -30","directions":"1 1 1","distancemin":"-1 -2 -3","distancemax":"1 2 3"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],"renderer":[{"name":"sprite"}]}
    """#

    private static let movementJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"velocityrandom","min":"2 0 0","max":"2 0 0"},{"name":"alpharandom","min":1,"max":1}],
     "operator":[{"name":"movement","gravity":"0 -2 0","drag":1},{"name":"alphafade","fadeintime":0.25,"fadeouttime":0.75}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let centeredBoxJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[{"name":"boxrandom","instantaneous":100,"origin":"10 20 30","distancemax":"4 3 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let explicitCenteredBoxJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[{"name":"boxrandom","instantaneous":100,"distancemin":"0 0 0","distancemax":"4 3 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let positiveBoxJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[{"name":"boxrandom","instantaneous":100,"directions":"1 1 1","distancemin":"2 3 1","distancemax":"4 5 2"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let worldMovementJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"velocityrandom","min":"8 4 0","max":"8 4 0"}],
     "operator":[{"name":"movement","flags":1,"gravity":"0 -8 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let overrideDefinitionJSON = #"""
    {"material":"p.json","maxcount":32,"flags":0,
     "emitter":[{"name":"boxrandom","instantaneous":1,"rate":4,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"sizerandom","min":2,"max":2},{"name":"velocityrandom","min":"1 0 0","max":"1 0 0"},{"name":"colorrandom","min":"255 255 255","max":"255 255 255"},{"name":"alpharandom","min":0.5,"max":0.5}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static func overrideDefinition(flags: Int) -> String {
        overrideDefinitionJSON.replacingOccurrences(
            of: #""flags":0"#,
            with: #""flags":\#(flags)"#
        )
    }

    private static let overrideJSON = #"""
    {"alpha":0.5,"size":{"user":"size_prop","value":3},"lifetime":2,"rate":2,"speed":4,"count":0.5,"brightness":2,"colorn":"0.5 0.25 1"}
    """#

    private static let liveOverrideDefinitionJSON = #"""
    {"material":"p.json","maxcount":16,"flags":0,
     "emitter":[{"name":"boxrandom","rate":4,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":2,"max":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let dynamicControlPointJSON = #"""
    {"material":"p.json","maxcount":4,
     "emitter":[{"name":"boxrandom","controlpoint":1,"rate":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}],
     "controlpoint":[{"id":1,"offset":"1 1 1"}]}
    """#

    private static let authoredControlPointIdentityJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","controlpoint":1,"instantaneous":1,"distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}],
     "controlpoint":[{"id":2,"offset":"200 0 0"},{"id":0},{"id":1,"offset":"10 0 0"}]}
    """#

    private static let implicitControlPointJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","controlpoint":3,"instantaneous":1,"origin":"5 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static func malformedControlPointJSON(_ points: String) -> String {
        let prefix = String(implicitControlPointJSON
            .replacingOccurrences(of: #""controlpoint":3"#, with: #""controlpoint":1"#)
            .dropLast())
        return prefix + #", "controlpoint":"# + points + "}"
    }

    private static func emitterSpeedJSON(_ fields: String, count: Int = 1) -> String {
        """
        {"material":"p.json","maxcount":\(count),
         "emitter":[{"name":"boxrandom","instantaneous":\(count),"distancemin":"2 0 0","distancemax":"2 0 0",\(fields)}],
         "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
         "operator":[{"name":"movement"}],"renderer":[{"name":"sprite"}]}
        """
    }

    private static func emitterShapeJSON(_ fields: String, count: Int = 64) -> String {
        """
        {"material":"p.json","maxcount":\(count),
         "emitter":[{\(fields),"instantaneous":\(count)}],
         "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
         "renderer":[{"name":"sprite"}]}
        """
    }

    private static func controlPointForceJSON(
        scale: String,
        threshold: String,
        flags: Int = 1,
        extra: String = "",
        controlPoint: Int = 1,
        pointOffset: String = "0 0 0",
        systemFlags: Int = 0,
        movementFlags: Int = 0,
        controlPointSuffix: String = ""
    ) -> String {
        """
        {"material":"p.json","maxcount":1,"flags":\(systemFlags),
         "emitter":[{"name":"boxrandom","instantaneous":1,"distancemax":0}],
         "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
         "operator":[{"name":"movement","flags":\(movementFlags)},{"name":"controlpointattract","controlpoint":\(controlPoint),"origin":"0 0 0","scale":\(scale),"threshold":\(threshold)\(extra)}],
         "renderer":[{"name":"sprite"}],
         "controlpoint":[{"id":1,"flags":\(flags),"offset":"\(pointOffset)"}\(controlPointSuffix)]}
        """
    }

    private static func vortexJSON(
        position: String = "10 0 0",
        axis: String = "0 0 1",
        distanceInner: String = "0",
        distanceOuter: String = "10",
        speedInner: String = "0",
        speedOuter: String = "100",
        flags: Int = 0,
        systemFlags: Int = 0,
        extra: String = ""
    ) -> String {
        """
        {"material":"p.json","maxcount":1,"flags":\(systemFlags),
         "emitter":[{"name":"boxrandom","instantaneous":1,"directions":"1 1 1","distancemin":"\(position)","distancemax":"\(position)"}],
         "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
         "operator":[{"name":"vortex","axis":"\(axis)","distanceinner":\(distanceInner),"distanceouter":\(distanceOuter),"speedinner":\(speedInner),"speedouter":\(speedOuter),"flags":\(flags)\(extra)}],
         "renderer":[{"name":"sprite"}]}
        """
    }

    private static let vortexV2JSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"10 0 0","distancemax":"10 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "operator":[{"name":"vortex_v2","distance":10,"speed":100}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let periodicJSON = #"""
    {"material":"p.json","maxcount":100,
     "emitter":[{"name":"sphererandom","flags":4,"rate":4,"distancemax":0,
       "minperiodicduration":0.5,"maxperiodicduration":0.5,
       "minperiodicdelay":0.5,"maxperiodicdelay":0.5}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let periodicAuthorOffJSON = periodicJSON.replacingOccurrences(
        of: #""flags":4"#,
        with: #""flags":0"#
    )

    private static let periodicMalformedJSON = periodicJSON.replacingOccurrences(
        of: #""maxperiodicdelay":0.5"#,
        with: #""maxperiodicdelay":"bad""#
    )

    private static let periodicBurstJSON = periodicJSON.replacingOccurrences(
        of: #""rate":4"#,
        with: #""rate":4,"instantaneous":1"#
    )

    private static let periodicLimitedJSON = periodicJSON.replacingOccurrences(
        of: #""rate":4"#,
        with: #""rate":4,"maxtoemitperperiod":2"#
    )

    private static let operatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":2,"max":2},{"name":"colorrandom","min":"255 255 255","max":"255 255 255"},{"name":"angularvelocityrandom","min":"0 0 1","max":"0 0 1"}],
     "operator":[
       {"name":"alphachange","starttime":0,"endtime":1,"startvalue":1,"endvalue":0.5},
       {"name":"sizechange","starttime":0,"endtime":1,"startvalue":1,"endvalue":2},
       {"name":"colorchange","starttime":0,"endtime":1,"startvalue":"1 1 1","endvalue":"0 0.5 1"},
       {"name":"angularmovement","force":"0 0 0","drag":0},
       {"name":"oscillatealpha","frequencymin":0,"frequencymax":0,"scalemin":0.5,"scalemax":0.5,"phasemin":0,"phasemax":0},
       {"name":"oscillatesize","frequencymin":0,"frequencymax":0,"scalemin":2,"scalemax":2,"phasemin":0,"phasemax":0},
       {"name":"oscillateposition","frequencymin":1,"frequencymax":1,"scalemin":"1 0 0","scalemax":"1 0 0","phasemin":1.5707963267948966,"phasemax":1.5707963267948966,"mask":"1 0 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let diagnosticJSON = #"""
    {"material":"p.json","maxcount":4,
     "emitter":[{"name":"boxrandom","rate":1,"audioprocessingmode":1}],
     "initializer":[{"name":"turbulentvelocityrandom","audioprocessingmode":1}],
     "operator":[{"name":"controlpointattract"},{"name":"turbulence"},{"name":"vortex"}],
     "renderer":[{"name":"spritetrail"}],"controlpoint":[{"id":0,"flags":1}],
     "children":[{"name":"child.json","type":"static"}]}
    """#

    private static let lifetimeOscillationJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":4,"max":4},{"name":"alpharandom","min":1,"max":1},{"name":"sizerandom","min":10,"max":10}],
     "operator":[{"name":"oscillatealpha","frequencymin":0.25,"frequencymax":0.25,"phasemin":0,"phasemax":0,"scalemin":0.2,"scalemax":1},{"name":"oscillatesize","frequencymin":0.25,"frequencymax":0.25,"phasemin":0,"phasemax":0,"scalemin":0.5,"scalemax":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let positionOscillationJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":8,"max":8}],
     "operator":[{"name":"oscillateposition","frequencymin":2,"frequencymax":2,"scalemin":"8 4 0","scalemax":"8 4 0","phasemin":0,"phasemax":0,"mask":"1 0.5 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let longPositionOscillationJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":16,"max":16}],
     "operator":[{"name":"oscillateposition","frequencymin":2,"frequencymax":2,"scalemin":"8 4 0","scalemax":"8 4 0","phasemin":0,"phasemax":0,"mask":"1 0.5 0"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let turbulentJSON = #"""
    {"material":"p.json","maxcount":2,
     "emitter":[{"name":"boxrandom","instantaneous":2,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"turbulentvelocityrandom","forward":"0 1 0","right":"0 0 1","up":"0 0 0","offset":0.25,"phasemin":0.5,"phasemax":1,"scale":0.2,"speedmin":25,"speedmax":25,"timescale":0.5}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let zeroScaleTurbulentJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"turbulentvelocityrandom","forward":"0 2 0","right":"1 0 0","scale":0,"speedmin":25,"speedmax":25}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let offsetTurbulentJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"turbulentvelocityrandom","forward":"0 1 0","offset":3,"scale":0,"speedmin":25,"speedmax":25}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let audioTurbulentJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2},{"name":"turbulentvelocityrandom","speedmin":25,"speedmax":25,"audioprocessingmode":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let turbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","scale":0.02,"speedmin":25,"speedmax":25,"phasemin":0.1,"phasemax":0.7,"timescale":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let zeroTimeTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","scale":0.02,"speedmin":25,"speedmax":25,"phasemin":0.1,"phasemax":0.7,"timescale":0}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let xOnlyTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"2 0 0","scale":0.02,"speedmin":25,"speedmax":25,"phasemin":0.1,"phasemax":0.7,"timescale":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let defaultTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","timescale":30}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let blendedTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","scale":0.02,"speedmin":25,"speedmax":25,"timescale":2,"blendinstart":0.5,"blendinend":0.6}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let audioTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"4 8 0","distancemax":"4 8 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","scale":0.02,"speedmin":25,"speedmax":25,"timescale":2,"audioprocessingmode":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let turbulenceBeforeMovementJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1 1 0","speedmin":25,"speedmax":25,"phasemin":0.3,"phasemax":0.3},{"name":"movement"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let movementBeforeTurbulenceJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"movement"},{"name":"turbulence","mask":"1 1 0","speedmin":25,"speedmax":25,"phasemin":0.3,"phasemax":0.3}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let overflowTurbulenceOperatorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":2,"max":2}],
     "operator":[{"name":"turbulence","mask":"1e308 1e308 0","speedmin":1e308,"speedmax":1e308}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let colorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"colorrandom","min":"10 40 80","max":"240 200 160"}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let uniformSizeJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":20,"max":50,"exponent":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let biasedSizeJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":20,"max":50,"exponent":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let maximumSizeJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"sizerandom","min":20,"max":50,"exponent":0}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let uniformVelocityJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"velocityrandom","min":"10 20 30","max":"20 40 50","exponent":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let biasedVelocityJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"velocityrandom","min":"10 20 30","max":"20 40 50","exponent":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let uniformColorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"colorrandom","min":"10 40 80","max":"240 200 160","exponent":1}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static let biasedColorJSON = #"""
    {"material":"p.json","maxcount":1,
     "emitter":[{"name":"boxrandom","instantaneous":1,"distancemin":"0 0 0","distancemax":"0 0 0"}],
     "initializer":[{"name":"lifetimerandom","min":10,"max":10},{"name":"colorrandom","min":"10 40 80","max":"240 200 160","exponent":2}],
     "renderer":[{"name":"sprite"}]}
    """#

    private static func census(rootPath: String) throws -> [String: Any] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let samples = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let parser = SceneParticleDefinitionParser()
        var definitionSimulators = 0
        var rootSimulators = 0

        for sample in samples {
            let project = try object(data: Data(contentsOf: sample.appendingPathComponent("project.json")))
            let scenePath = normalized(project["file"] as? String ?? "scene.json")
            let packageURL = try packageURL(sample: sample, scenePath: scenePath)
            let index = try ScenePkgReader().readIndex(packageURL: packageURL)
            let entries = Dictionary(uniqueKeysWithValues: index.entries.map { (normalized($0.path), $0) })
            guard let sceneEntry = entries[scenePath] else { throw HarnessError.missingEntry(scenePath) }
            let scene = try object(data: try read(sceneEntry, index: index, packageURL: packageURL))
            let objects = scene["objects"] as? [[String: Any]] ?? []

            for object in objects {
                guard let path = object["particle"] as? String,
                      let entry = entries[normalized(path)] else { continue }
                let definition = try parser.parse(data: read(entry, index: index, packageURL: packageURL))
                var runtime = SceneParticleSimulator(
                    definition: definition,
                    instanceOverride: parser.parseInstanceOverride(object["instanceoverride"]),
                    seed: UInt64(rootSimulators), fixedTimeStep: 1.0 / 60.0
                )
                runtime.advance(by: 1.0 / 60.0)
                rootSimulators += 1
            }

            var visited = Set<String>()
            func visit(_ rawPath: String) throws {
                let path = normalized(rawPath)
                guard visited.insert(path).inserted, let entry = entries[path] else { return }
                let definition = try parser.parse(data: read(entry, index: index, packageURL: packageURL))
                var runtime = SceneParticleSimulator(
                    definition: definition, seed: UInt64(definitionSimulators), fixedTimeStep: 1.0 / 60.0
                )
                runtime.advance(by: 1.0 / 60.0)
                definitionSimulators += 1
                for child in definition.children { if let path = child.path { try visit(path) } }
            }
            for object in objects { if let path = object["particle"] as? String { try visit(path) } }
        }
        return ["sampleCount": samples.count, "definitionSimulators": definitionSimulators,
                "rootSimulators": rootSimulators]
    }

    private static func read(
        _ entry: ScenePkgIndex.Entry, index: ScenePkgIndex, packageURL: URL
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: packageURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(index.dataStartOffset) + UInt64(entry.offset))
        guard let data = try handle.read(upToCount: Int(entry.size)), data.count == Int(entry.size) else {
            throw HarnessError.truncatedEntry(entry.path)
        }
        return data
    }

    private static func packageURL(sample: URL, scenePath: String) throws -> URL {
        let name = ((scenePath as NSString).lastPathComponent as NSString).deletingPathExtension
        for file in name == "scene" ? ["scene.pkg"] : ["\(name).pkg", "scene.pkg"] {
            let candidate = sample.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw HarnessError.missingPackage(sample.lastPathComponent)
    }

    private static func normalized(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }

    private static func object(_ source: String) throws -> [String: Any] {
        try object(data: Data(source.utf8))
    }

    private static func object(data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessError.invalidJSON
        }
        return value
    }

    private static func vector(_ value: SIMD3<Double>) -> [Double] {
        [value.x, value.y, value.z]
    }

    private static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case invalidJSON
        case missingPackage(String)
        case missingEntry(String)
        case truncatedEntry(String)
    }
}
'''


class SceneParticleSimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-particle-runtime-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-runtime"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.results = cls.run_harness()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def run_harness(cls, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [str(cls.binary), *arguments], check=True, capture_output=True, text=True
        )
        return json.loads(result.stdout)

    def test_fixed_step_and_seed_are_deterministic(self) -> None:
        self.assertTrue(self.results["deterministic"])
        self.assertTrue(self.results["differentSeed"])

    def test_birth_events_are_ordered_deterministic_and_drained(self) -> None:
        self.assertEqual(self.results["birthEventIDs"], [0, 1, 2, 3, 4])
        self.assertTrue(self.results["birthEventsDeterministic"])
        self.assertTrue(self.results["birthEventsDrain"])
        self.assertEqual(self.results["prewarmBirthEvents"], 0)

    def test_death_events_capture_final_state_before_removal(self) -> None:
        self.assertEqual(self.results["deathEventCount"], 1)
        self.assertEqual(self.results["deathEventPosition"], [0.4, 0, 0])
        self.assertTrue(self.results["deathEventsDrain"])
        self.assertEqual(self.results["deathParticles"], 0)

    def test_maximum_count_and_start_time_prewarm(self) -> None:
        self.assertEqual(self.results["maxCount"], 3)
        self.assertEqual(self.results["budgetCount"], 2)
        self.assertEqual(self.results["prewarmCount"], 10)
        self.assertAlmostEqual(self.results["prewarmTime"], 1.0)

    def test_rate_instantaneous_duration_and_one_per_frame(self) -> None:
        self.assertEqual(self.results["durationCount"], 4)

    def test_sphere_and_box_emitters_stay_in_authored_bounds(self) -> None:
        self.assertGreaterEqual(self.results["sphereMinimumRadius"], 2.0)
        self.assertLessEqual(self.results["sphereMaximumRadius"], 4.0)
        self.assertTrue(self.results["boxInBounds"])
        self.assertTrue(self.results["centeredBoxInBounds"])
        self.assertTrue(self.results["centeredBoxHasBothSigns"])
        self.assertTrue(self.results["explicitCenteredBoxHasBothSigns"])
        self.assertTrue(self.results["positiveBoxPreservesInterval"])

    def test_layer_image_emitter_uses_injected_alpha_bitmap_position(self) -> None:
        self.assertEqual(self.results["layerImagePosition"], [-15, 5, 0])
        self.assertEqual(self.results["layerImageMissingMapCount"], 0)

    def test_pointer_control_point_force_is_bounded_and_directional(self) -> None:
        self.assertEqual(self.results["pointerPullVelocity"], [2, 0, 0])
        self.assertEqual(self.results["pointerPushVelocity"], [-2, 0, 0])
        self.assertEqual(self.results["pointerOutsideVelocity"], [0, 0, 0])
        self.assertEqual(self.results["pointerAtCenterVelocity"], [0, 0, 0])
        self.assertEqual(self.results["pointerMapped"], [3, 4, 0])
        self.assertTrue(self.results["pointerOutsideInactive"])
        self.assertTrue(self.results["duplicatePointerRejected"])
        self.assertEqual(
            self.results["pointerPullDiagnostics"],
            ["controlPointForceBounded", "pointerControlPointBounded"],
        )
        self.assertEqual(
            self.results["invalidControlPointForceVelocities"],
            [[0, 0, 0]] * 10,
        )
        for diagnostics in self.results["invalidControlPointForceDiagnostics"]:
            self.assertIn("controlPointForceUnsupported", diagnostics)

    def test_random_periodic_emission_uses_bounded_active_and_delay_windows(self) -> None:
        self.assertEqual(self.results["periodicFirstWindowCount"], 2)
        self.assertEqual(self.results["periodicDelayCount"], 2)
        self.assertEqual(self.results["periodicSecondWindowCount"], 4)
        self.assertTrue(self.results["periodicDeterministic"])
        self.assertEqual(self.results["periodicDiagnostics"], ["periodicEmissionBounded"])
        self.assertEqual(self.results["periodicAuthorOffCount"], 6)
        for prefix in [
            "periodicMalformed", "periodicBurst", "periodicLimited", "periodicOverridden"
        ]:
            self.assertEqual(self.results[f"{prefix}Count"], 0)
            self.assertEqual(
                self.results[f"{prefix}Diagnostics"],
                ["periodicEmissionUnsupported"],
            )

    def test_movement_gravity_drag_and_alpha_fade(self) -> None:
        self.assertEqual(self.results["movementPosition"], [0.65625, -0.34375, 0])
        self.assertAlmostEqual(self.results["fadeAlpha"], 0.5)
        self.assertEqual(self.results["worldMovementPosition"], [2, 0, 0])
        self.assertEqual(self.results["worldMovementLocalVelocity"], [4, 0, 0])

    def test_static_instance_overrides_apply_and_supported_user_binding_is_admitted(self) -> None:
        self.assertEqual(self.results["overrideLifetime"], 4)
        self.assertEqual(self.results["overrideSize"], 6)
        self.assertEqual(self.results["overrideVelocity"], [4, 0, 0])
        self.assertEqual(self.results["overrideAlpha"], 0.25)
        self.assertEqual(self.results["overrideColor"], [0.5, 0.125, 2])
        self.assertEqual(self.results["overrideEmissionCount"], 5)
        self.assertNotIn("dynamicOverrideIgnored", self.results["overrideDiagnostics"])

    def test_dynamic_instance_override_applies_per_step_then_restores_authored_values(self) -> None:
        self.assertEqual(self.results["liveOverrideDiagnostics"], [])
        self.assertEqual(self.results["liveZeroCount"], 0)
        self.assertEqual(self.results["liveDynamicCount"], 2)
        self.assertEqual(self.results["liveDynamicAlpha"], 0.25)
        self.assertEqual(self.results["liveDynamicSize"], 6)
        self.assertEqual(self.results["liveDynamicColor"], [0.25, 1, 0.0625])
        self.assertEqual(self.results["liveFallbackAlpha"], 1)
        self.assertEqual(self.results["liveFallbackSize"], 2)
        self.assertEqual(self.results["liveFallbackColor"], [1, 1, 1])

    def test_general_flags_deny_only_the_matching_instance_override(self) -> None:
        self.assertEqual(self.results["colorDeniedColor"], [2, 2, 2])
        self.assertEqual(self.results["colorDeniedAlpha"], 0.25)
        self.assertEqual(self.results["speedDeniedVelocity"], [1, 0, 0])
        self.assertEqual(self.results["countDeniedEmissionCount"], 9)
        self.assertEqual(self.results["lifetimeDeniedLifetime"], 2)
        self.assertEqual(self.results["sizeDeniedSize"], 2)

    def test_dynamic_control_point_replaces_only_the_current_frame_override(self) -> None:
        self.assertEqual(
            self.results["dynamicControlPointPositions"],
            [[11, 21, 31], [-4, 7, 8], [3, 4, 5]],
        )

    def test_control_point_emitters_bind_authored_ids_and_reject_invalid_identity(self) -> None:
        self.assertEqual(self.results["authoredControlPointPosition"], [10, 0, 0])
        self.assertEqual(
            self.results["authoredControlPointDiagnostics"],
            ["controlPointEmitterBounded"],
        )
        self.assertEqual(self.results["implicitControlPointPosition"], [5, 0, 0])
        self.assertEqual(
            self.results["implicitControlPointDiagnostics"],
            ["controlPointEmitterBounded"],
        )
        self.assertEqual(self.results["invalidControlPointCounts"], [0, 0, 0, 0])
        self.assertEqual(
            self.results["invalidControlPointDiagnostics"],
            [["controlPointEmitterUnsupported"]] * 4,
        )

    def test_emitter_speed_uses_bounded_range_and_rejects_invalid_values(self) -> None:
        self.assertEqual(self.results["fixedEmitterSpeedPosition"], [5, 0, 0])
        self.assertEqual(self.results["fixedEmitterSpeedVelocity"], [3, 0, 0])
        self.assertEqual(
            self.results["fixedEmitterSpeedDiagnostics"], ["emitterSpeedBounded"]
        )
        speeds = self.results["maxOnlyEmitterSpeeds"]
        self.assertEqual(len(speeds), 16)
        self.assertTrue(all(0 <= value <= 4 for value in speeds))
        self.assertTrue(any(value > 0 for value in speeds))
        self.assertEqual(
            self.results["maxOnlyEmitterSpeedDiagnostics"], ["emitterSpeedBounded"]
        )
        self.assertEqual(self.results["invalidEmitterSpeedCounts"], [0, 0, 0, 0, 0])
        self.assertEqual(
            self.results["invalidEmitterSpeedDiagnostics"],
            [["emitterSpeedUnsupported"]] * 5,
        )

    def test_emitter_directions_and_sign_are_bounded_and_fail_closed(self) -> None:
        self.assertTrue(self.results["sphereDirectionSignBounded"])
        self.assertEqual(
            self.results["sphereDirectionSignDiagnostics"], ["emitterShapeBounded"]
        )
        self.assertTrue(self.results["zeroDirectionsStayAtOrigin"])
        self.assertEqual(
            self.results["zeroDirectionsDiagnostics"], ["emitterShapeBounded"]
        )
        self.assertTrue(self.results["boxDirectionsBounded"])
        self.assertEqual(
            self.results["boxDirectionsDiagnostics"], ["emitterShapeBounded"]
        )
        self.assertEqual(self.results["invalidEmitterShapeCounts"], [0, 0, 0, 0, 0, 0])
        self.assertEqual(
            self.results["invalidEmitterShapeDiagnostics"],
            [["emitterShapeUnsupported"]] * 6,
        )

    def test_change_angular_and_oscillation_operators_execute(self) -> None:
        self.assertAlmostEqual(self.results["operatorAlpha"], 0.49375)
        self.assertAlmostEqual(self.results["operatorSize"], 4.1)
        self.assertEqual(self.results["operatorColor"], [0.975, 0.9875, 1])
        self.assertEqual(self.results["operatorRotation"], [0, 0, 0.25])
        self.assertLess(self.results["operatorPosition"][0], 0)
        quarter_wave = (math.cos(math.pi / 8) + 1) * 0.5
        half_wave = (math.cos(math.pi / 4) + 1) * 0.5
        self.assertAlmostEqual(
            self.results["quarterLifeOscillationAlpha"],
            0.2 + 0.8 * quarter_wave,
        )
        self.assertAlmostEqual(
            self.results["halfLifeOscillationAlpha"],
            0.2 + 0.8 * half_wave,
        )
        self.assertAlmostEqual(
            self.results["fineHalfLifeOscillationAlpha"],
            self.results["halfLifeOscillationAlpha"],
        )
        self.assertAlmostEqual(
            self.results["halfLifeOscillationSize"],
            10 * (0.5 + 0.5 * half_wave),
        )
        self.assertAlmostEqual(
            self.results["fineHalfLifeOscillationSize"],
            self.results["halfLifeOscillationSize"],
        )
        self.assertEqual(
            self.results["quarterLifeOscillationPosition"],
            [-16, -4, 0],
        )
        self.assertEqual(
            self.results["longQuarterLifeOscillationPosition"],
            self.results["quarterLifeOscillationPosition"],
        )
        for component in self.results["halfLifeOscillationPosition"]:
            self.assertAlmostEqual(component, 0, places=10)
        for coarse, fine in zip(
            self.results["halfLifeOscillationPosition"],
            self.results["fineHalfLifeOscillationPosition"],
        ):
            self.assertAlmostEqual(coarse, fine, places=10)

    def test_color_initializer_interpolates_between_authored_colors(self) -> None:
        self.assertTrue(self.results["colorUsesSingleInterpolation"])

    def test_random_initializer_exponent_biases_values_towards_minimum(self) -> None:
        uniform = self.results["uniformSizeAmount"]
        biased = self.results["biasedSizeAmount"]
        self.assertGreater(uniform, 0)
        self.assertLess(uniform, 1)
        self.assertAlmostEqual(biased, uniform * uniform)
        self.assertLess(biased, uniform)
        self.assertEqual(self.results["maximumSize"], 50)
        for uniform_component, biased_component in zip(
            self.results["uniformVelocityAmount"],
            self.results["biasedVelocityAmount"],
        ):
            self.assertAlmostEqual(
                biased_component,
                uniform_component * uniform_component,
            )
        self.assertAlmostEqual(
            self.results["biasedColorAmount"],
            self.results["uniformColorAmount"]
            * self.results["uniformColorAmount"],
        )

    def test_non_audio_turbulent_velocity_is_deterministic_and_bounded(self) -> None:
        self.assertTrue(self.results["turbulentDeterministic"])
        self.assertTrue(self.results["turbulentDifferentSeed"])
        self.assertTrue(self.results["turbulentDifferentTime"])
        self.assertAlmostEqual(self.results["turbulentSpeed"], 25)
        self.assertTrue(self.results["turbulentPlanar"])
        self.assertEqual(self.results["zeroScaleTurbulentVelocity"], [0, 25, 0])
        offset_velocity = self.results["offsetTurbulentVelocity"]
        self.assertAlmostEqual(offset_velocity[0], -25 * math.sin(3), places=10)
        self.assertAlmostEqual(offset_velocity[1], 25 * math.cos(3), places=10)
        self.assertAlmostEqual(offset_velocity[2], 0, places=10)
        self.assertNotIn("unsupportedInitializer", self.results["turbulentDiagnostics"])

    def test_audio_turbulent_velocity_remains_fail_closed(self) -> None:
        self.assertEqual(self.results["audioTurbulentVelocity"], [0, 0, 0])
        self.assertEqual(
            self.results["audioTurbulentDiagnostics"],
            ["audioResponseIgnored", "unsupportedInitializer"],
        )

    def test_non_audio_turbulence_operator_executes_bounded_fixed_step_noise(self) -> None:
        self.assertTrue(self.results["turbulenceOperatorDeterministic"])
        self.assertTrue(self.results["turbulenceOperatorDifferentSeed"])
        self.assertTrue(self.results["turbulenceOperatorTimeScale"])
        self.assertAlmostEqual(self.results["turbulenceOperatorSpeed"], 2.5)
        self.assertTrue(self.results["turbulenceOperatorPlanar"])
        self.assertAlmostEqual(self.results["xOnlyTurbulenceVelocity"][1], 0)
        self.assertAlmostEqual(self.results["xOnlyTurbulenceVelocity"][2], 0)
        self.assertGreaterEqual(self.results["defaultTurbulenceSpeed"], 50)
        self.assertLessEqual(self.results["defaultTurbulenceSpeed"], 100)
        self.assertEqual(self.results["blendedTurbulenceVelocity"], [0, 0, 0])
        self.assertAlmostEqual(self.results["overriddenTurbulenceSpeed"], 5)
        self.assertNotIn(
            "unsupportedOperator", self.results["turbulenceOperatorDiagnostics"]
        )

    def test_audio_turbulence_operator_remains_fail_closed(self) -> None:
        self.assertEqual(self.results["audioOperatorTurbulenceVelocity"], [0, 0, 0])
        self.assertEqual(
            self.results["audioOperatorTurbulenceDiagnostics"],
            ["audioResponseIgnored", "unsupportedOperator"],
        )

    def test_turbulence_respects_authored_operator_order_and_rejects_overflow(self) -> None:
        self.assertNotEqual(self.results["turbulenceBeforeMovementPosition"], [0, 0, 0])
        self.assertEqual(self.results["movementBeforeTurbulencePosition"], [0, 0, 0])
        self.assertEqual(self.results["overflowTurbulenceVelocity"], [0, 0, 0])

    def test_classic_vortex_executes_bounded_axis_distance_and_speed(self) -> None:
        self.assertEqual(self.results["vortexVelocity"], [0, 100, 0])
        self.assertEqual(
            self.results["vortexDiagnostics"],
            ["emitterShapeBounded", "vortexBounded"],
        )
        self.assertTrue(self.results["vortexPartitioned"])
        self.assertEqual(self.results["reverseVortexVelocity"], [0, -100, 0])
        self.assertEqual(self.results["yAxisVortexVelocity"], [0, 0, -100])
        self.assertEqual(self.results["infiniteAxisVortexVelocity"], [0, 10, 0])
        finite = self.results["finiteAxisVortexVelocity"]
        self.assertAlmostEqual(finite[0], 0)
        self.assertAlmostEqual(finite[1], 100)
        self.assertAlmostEqual(finite[2], 0)
        self.assertEqual(self.results["overriddenVortexVelocity"], [0, 200, 0])
        self.assertEqual(self.results["overrideDeniedVortexVelocity"], [0, 100, 0])

    def test_classic_vortex_rejects_unknown_malformed_audio_and_unbounded_profiles(self) -> None:
        self.assertEqual(self.results["invalidVortexVelocities"], [[0, 0, 0]] * 10)
        for diagnostics in self.results["invalidVortexDiagnostics"]:
            self.assertIn("vortexUnsupported", diagnostics)

    def test_vortex_v2_remains_distinct_and_fail_closed(self) -> None:
        self.assertEqual(self.results["vortexV2Velocity"], [0, 0, 0])
        self.assertIn("unsupportedOperator", self.results["vortexV2Diagnostics"])

    def test_unsupported_capabilities_are_reported(self) -> None:
        self.assertEqual(
            self.results["diagnostics"],
            [
                "audioResponseIgnored",
                "audioResponseIgnored",
                "childSystemsIgnored",
                "controlPointForceUnsupported",
                "dynamicOverrideIgnored",
                "pointerControlPointUnsupported",
                "unsupportedInitializer",
                "vortexUnsupported",
            ],
        )

if __name__ == "__main__":
    unittest.main()
