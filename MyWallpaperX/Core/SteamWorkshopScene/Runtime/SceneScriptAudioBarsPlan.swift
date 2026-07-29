import Foundation

/// A bounded native execution plan for verified SceneScript audio-bar profiles.
///
/// The compiler owns profile recognition. Renderers consume only this data model and
/// never branch on Workshop, sample, or authored layer identifiers.
nonisolated struct SceneScriptAudioBarsPlan: Equatable, Sendable {
    nonisolated enum SpectrumChannel: String, Codable, Equatable, Sendable {
        case average
    }

    nonisolated enum Alignment: String, Codable, Equatable, Sendable {
        case centre
        case bottom
        case top
    }

    nonisolated enum FirstStepPolicy: String, Codable, Equatable, Sendable {
        /// Bar zero remains at the authored owner origin.
        case ownerAtBaseOrigin
        /// Bar zero is advanced by one x/y step before its transform is assigned.
        case advanceBeforeFirstBar

        nonisolated func stepIndex(forBarIndex index: Int) -> Int {
            switch self {
            case .ownerAtBaseOrigin:
                index
            case .advanceBeforeFirstBar:
                index + 1
            }
        }
    }

    let layerID: Int
    let sourceSHA256: String
    let host: String
    let modelPath: String
    let materialPath: String
    let texturePath: String
    let barCount: Int
    let audioResolution: Int
    let channel: SpectrumChannel
    let widthMultiplier: Float
    let heightMultiplier: Float
    let depthMultiplier: Float
    let xStep: Float
    let yStep: Float
    let angleDegrees: Float
    let alignment: Alignment
    let firstStepPolicy: FirstStepPolicy

    nonisolated var hasAudioConsumer: Bool {
        barCount > 0 && audioResolution > 0
    }

    /// SceneScript audio buffers may exceed 1.0. Preserve that authored behavior.
    nonisolated func height(forSpectrumValue value: Float) -> Float {
        value * heightMultiplier
    }

    nonisolated func stepIndex(forBarIndex index: Int) -> Int {
        firstStepPolicy.stepIndex(forBarIndex: index)
    }
}

nonisolated struct SceneScriptAudioBarsProgram: Equatable, Sendable {
    nonisolated struct Diagnostic: Equatable, Sendable {
        nonisolated enum Code: String, Codable, Equatable, Sendable {
            case unknownProfile
            case invalidBinding
            case invalidProperties
            case invalidLayerContract
            case invalidAssetContract
            case duplicateLayer
        }

        let layerID: Int
        let code: Code
        let sourceSHA256: String
        let detail: String
    }

    let plans: [SceneScriptAudioBarsPlan]
    let diagnostics: [Diagnostic]

    nonisolated static let empty = SceneScriptAudioBarsProgram(
        plans: [],
        diagnostics: []
    )

    nonisolated var hasAudioConsumer: Bool {
        plans.contains(where: \.hasAudioConsumer)
    }

    /// Stable lines suitable for preview logs and benchmark evidence.
    nonisolated var reportLines: [String] {
        var lines = [
            "sceneScriptAudioBarsPlanCount: \(plans.count)",
            "sceneScriptAudioBarsDiagnosticCount: \(diagnostics.count)",
            "sceneScriptAudioBarsHasAudioConsumer: \(hasAudioConsumer)",
        ]
        for plan in plans.sorted(by: { $0.layerID < $1.layerID }) {
            lines.append(
                "sceneScript audio bars: layer=\(plan.layerID)"
                    + " host=\(plan.host)"
                    + " sourceSHA256=\(plan.sourceSHA256)"
                    + " count=\(plan.barCount)"
                    + " resolution=\(plan.audioResolution)"
                    + " channel=\(plan.channel.rawValue)"
                    + " model=\(plan.modelPath)"
                    + " material=\(plan.materialPath)"
                    + " texture=\(plan.texturePath)"
                    + String(
                        format: " width=%.5f height=%.5f depth=%.5f"
                            + " xStep=%.5f yStep=%.5f angle=%.5f",
                        plan.widthMultiplier,
                        plan.heightMultiplier,
                        plan.depthMultiplier,
                        plan.xStep,
                        plan.yStep,
                        plan.angleDegrees
                    )
                    + " alignment=\(plan.alignment.rawValue)"
                    + " firstStep=\(plan.firstStepPolicy.rawValue)"
            )
        }
        for diagnostic in diagnostics.sorted(by: {
            ($0.layerID, $0.code.rawValue, $0.sourceSHA256, $0.detail)
                < ($1.layerID, $1.code.rawValue, $1.sourceSHA256, $1.detail)
        }) {
            lines.append(
                "sceneScript audio bars diagnostic: layer=\(diagnostic.layerID)"
                    + " code=\(diagnostic.code.rawValue)"
                    + " sourceSHA256=\(diagnostic.sourceSHA256)"
                    + " detail=\(diagnostic.detail)"
            )
        }
        return lines
    }
}
