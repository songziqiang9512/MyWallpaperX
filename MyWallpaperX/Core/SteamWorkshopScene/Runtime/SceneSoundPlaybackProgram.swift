import Foundation

/// Launch-scoped typed plan for authored Sound layers. The program admits only
/// the shared, observable subset whose playback and failure boundary are known;
/// unsupported authored forms remain in `SceneDocument` and reject only their
/// own Sound layer.
struct SceneSoundPlaybackProgram {
    struct Binding {
        let layerID: Int
        let resourceURL: URL
        let displayPath: String
        let authoredVolume: Double
        let volumePropertyKey: String?

        var volumeTarget: SceneDynamicTarget {
            .layer(layerID: layerID, field: .volume)
        }
    }

    struct Diagnostic: Equatable {
        enum Reason: String {
            case malformedSourceList
            case multipleSourcesUnsupported
            case playbackModeUnsupported
            case startsSilentUnsupported
            case timedPlaybackUnsupported
            case spatialPlaybackUnsupported
            case volumeInvalid
            case audioFormatUnsupported
            case resourceUnavailable
        }

        let layerID: Int
        let reason: Reason
        let detail: String
    }

    let bindings: [Binding]
    let diagnostics: [Diagnostic]

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.volumePropertyKey == nil ? nil : binding.volumeTarget
        })
    }

    var reportLines: [String] {
        var lines = [
            "scene sound playback: schema=avqueueplayer-loop-v1"
                + " admitted=\(bindings.count) rejected=\(diagnostics.count)"
                + " route=generic-only failure=layer-local"
                + " dynamicVolumeTargets=\(liveConsumerTargets.count)",
        ]
        lines += bindings.map {
            "scene sound binding: layer=\($0.layerID)"
                + " source=\($0.displayPath) volume=\($0.authoredVolume)"
                + " property=\($0.volumePropertyKey ?? "-")"
        }
        lines += diagnostics.map {
            "scene sound diagnostic: layer=\($0.layerID)"
                + " reason=\($0.reason.rawValue) detail=\($0.detail)"
        }
        return lines
    }

    static func compile(
        document: SceneDocument,
        resourceView: SceneResourceView
    ) -> SceneSoundPlaybackProgram {
        var bindings: [Binding] = []
        var diagnostics: [Diagnostic] = []
        for object in document.objects.sorted(by: { $0.id < $1.id }) {
            guard let sound = object.sound else { continue }
            let rejection = admissionFailure(sound)
            if let rejection {
                diagnostics.append(.init(
                    layerID: object.id,
                    reason: rejection.reason,
                    detail: rejection.detail
                ))
                continue
            }
            guard let path = sound.paths.first,
                  let resource = resourceView.resource(forReference: path) else {
                diagnostics.append(.init(
                    layerID: object.id,
                    reason: .resourceUnavailable,
                    detail: sound.paths.first ?? "missing"
                ))
                continue
            }
            bindings.append(.init(
                layerID: object.id,
                resourceURL: resource.url,
                displayPath: resourceView.displayPath(for: resource.url),
                authoredVolume: sound.volume ?? 1,
                volumePropertyKey: sound.volumePropertyKey
            ))
        }
        return SceneSoundPlaybackProgram(
            bindings: bindings,
            diagnostics: diagnostics
        )
    }

    private static func admissionFailure(
        _ sound: SceneDocument.SceneSoundLayerDefinition
    ) -> (reason: Diagnostic.Reason, detail: String)? {
        guard sound.authoredPathCount == sound.paths.count,
              !sound.paths.isEmpty else {
            return (.malformedSourceList, "count=\(sound.authoredPathCount)")
        }
        guard sound.paths.count == 1 else {
            return (.multipleSourcesUnsupported, "count=\(sound.paths.count)")
        }
        guard sound.playbackMode?.localizedLowercase == "loop" else {
            return (.playbackModeUnsupported, sound.playbackMode ?? "missing")
        }
        guard sound.startsSilent == false else {
            return (.startsSilentUnsupported, String(describing: sound.startsSilent))
        }
        guard sound.minimumTime == nil,
              sound.maximumTime == nil else {
            return (.timedPlaybackUnsupported, "min-max-fields-present")
        }
        guard sound.spatialization == nil,
              sound.attenuation == nil,
              sound.minimumDistance == nil else {
            return (.spatialPlaybackUnsupported, "spatial-fields-present")
        }
        guard let volume = sound.volume,
              volume.isFinite,
              (0 ... 1).contains(volume) else {
            return (.volumeInvalid, String(describing: sound.volume))
        }
        let path = sound.paths[0]
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return (.malformedSourceList, path)
        }
        let supportedExtensions: Set<String> = ["flac", "mp3", "wav"]
        let fileExtension = URL(fileURLWithPath: path).pathExtension.localizedLowercase
        guard supportedExtensions.contains(fileExtension) else {
            return (.audioFormatUnsupported, fileExtension.isEmpty ? "missing" : fileExtension)
        }
        return nil
    }
}
