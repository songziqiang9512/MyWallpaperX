import Foundation

extension SceneParticleDefinitionParser {
    nonisolated func parseOperator(
        _ root: [String: Any],
        diagnostics: inout [SceneParticleDiagnostic]
    ) -> SceneParticleOperator {
        let name = Self.componentName(root)
        let kind: SceneParticleOperatorKind
        switch name {
        case "movement": kind = .movement
        case "alphafade": kind = .alphaFade
        case "alphachange": kind = .alphaChange
        case "sizechange": kind = .sizeChange
        case "colorchange": kind = .colorChange
        case "angularmovement": kind = .angularMovement
        case "oscillateposition": kind = .oscillatePosition
        case "oscillatealpha": kind = .oscillateAlpha
        case "oscillatesize": kind = .oscillateSize
        case "controlpointattract": kind = .controlPointAttract
        case "turbulence": kind = .turbulence
        case "boids": kind = .boids(Self.boids(root))
        case "vortex": kind = .vortex(Self.vortex(root))
        default:
            kind = .unsupported(name)
            diagnostics.append(.init(
                kind: .unsupportedOperator, path: "operator", componentName: name
            ))
        }
        return SceneParticleOperator(
            id: Self.integer(root["id"]), kind: kind,
            rawFlags: Self.integer(root["flags"]) ?? 0,
            gravity: Self.numericValue(root["gravity"]), drag: Self.number(root["drag"]),
            force: Self.numericValue(root["force"]),
            fadeInTime: Self.number(root["fadeintime"]),
            fadeOutTime: Self.number(root["fadeouttime"]),
            startTime: Self.number(root["starttime"]), endTime: Self.number(root["endtime"]),
            startValue: Self.numericValue(root["startvalue"]),
            endValue: Self.numericValue(root["endvalue"]),
            frequencyMinimum: Self.number(root["frequencymin"]),
            frequencyMaximum: Self.number(root["frequencymax"]),
            scaleMinimum: Self.numericValue(root["scalemin"]),
            scaleMaximum: Self.numericValue(root["scalemax"]),
            phaseMinimum: Self.number(root["phasemin"]),
            phaseMaximum: Self.number(root["phasemax"]),
            mask: Self.numericValue(root["mask"]),
            blendInStart: Self.number(root["blendinstart"]),
            blendInEnd: Self.number(root["blendinend"]),
            blendOutStart: Self.number(root["blendoutstart"]),
            blendOutEnd: Self.number(root["blendoutend"]),
            controlPoint: Self.integer(root["controlpoint"]),
            origin: Self.numericValue(root["origin"]), scale: Self.numericValue(root["scale"]),
            timeScale: Self.number(root["timescale"]),
            threshold: Self.number(root["threshold"]),
            speedMinimum: Self.number(root["speedmin"]),
            speedMaximum: Self.number(root["speedmax"]),
            audioResponse: Self.audioResponse(root)
        )
    }

    private nonisolated static func boids(_ root: [String: Any]) -> SceneParticleBoids {
        let scalarFields = [
            "neighborthreshold", "separationfactor", "cohesionfactor", "alignmentfactor"
        ]
        let supportedFields = Set([
            "id", "name", "flags", "neighborthreshold", "separationfactor",
            "cohesionfactor", "alignmentfactor"
        ])
        return .init(
            neighborThreshold: number(root["neighborthreshold"]),
            separationFactor: number(root["separationfactor"]),
            cohesionFactor: number(root["cohesionfactor"]),
            alignmentFactor: number(root["alignmentfactor"]),
            hasMalformedFields: scalarFields.contains {
                root[$0] != nil && !(root[$0] is NSNull) && number(root[$0]) == nil
            } || (root["flags"] != nil && integer(root["flags"]) == nil),
            unsupportedFieldNames: root.keys.filter { !supportedFields.contains($0) }.sorted()
        )
    }

    private nonisolated static func vortex(_ root: [String: Any]) -> SceneParticleVortex {
        let scalarFields = ["distanceinner", "distanceouter", "speedinner", "speedouter"]
        let supportedFields = Set([
            "id", "name", "axis", "distanceinner", "distanceouter", "flags",
            "speedinner", "speedouter", "blendinstart", "blendinend",
            "blendoutstart", "blendoutend", "audioprocessingmode",
            "audioprocessingbounds", "audioprocessingexponent",
            "audioprocessingfrequencystart", "audioprocessingfrequencyend"
        ])
        return .init(
            axis: numericValue(root["axis"]),
            distanceInner: number(root["distanceinner"]),
            distanceOuter: number(root["distanceouter"]),
            speedInner: number(root["speedinner"]),
            speedOuter: number(root["speedouter"]),
            hasMalformedFields: (root["axis"] != nil && !(root["axis"] is NSNull)
                && numericValue(root["axis"]) == nil)
                || scalarFields.contains {
                    root[$0] != nil && !(root[$0] is NSNull) && number(root[$0]) == nil
                }
                || (root["flags"] != nil && integer(root["flags"]) == nil),
            unsupportedFieldNames: root.keys.filter { !supportedFields.contains($0) }.sorted()
        )
    }
}
