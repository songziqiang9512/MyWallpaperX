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
        let loops: Bool
        let authoredVolume: Double
        let volumePropertyKey: String?

        var volumeTarget: SceneDynamicTarget {
            .layer(layerID: layerID, field: .volume)
        }
    }

    struct Diagnostic: Equatable {
        enum Reason: String {
            case malformedSourceList
            case playbackModeUnsupported
            case startsSilentUnsupported
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

    /// Diagnostics for layers that admitted no binding at all.
    var layerRejectionCount: Int {
        let admittedLayerIDs = Set(bindings.map(\.layerID))
        return diagnostics.filter { !admittedLayerIDs.contains($0.layerID) }.count
    }

    /// Diagnostics for sources skipped by layers that admitted another
    /// source - real facts, but they must not read as rejected layers in
    /// corpus tooling that counts reason lines.
    var skippedSourceCount: Int {
        diagnostics.count - layerRejectionCount
    }

    var reportLines: [String] {
        var lines = [
            "scene sound playback: schema=avqueueplayer-loop-v2"
                + " admitted=\(bindings.count) rejected=\(layerRejectionCount)"
                + " skipped=\(skippedSourceCount)"
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
            let loops = normalizedPlaybackMode(sound.playbackMode) == "loop"
            var skippedSources: [(reason: Diagnostic.Reason, detail: String)] = []
            var binding: Binding?
            // Sources are attempted in author order; the first usable source
            // carries the binding and skipped sources keep their real
            // per-source reason/detail through the existing diagnostic
            // reasons (no new reason code, also when nothing is admitted).
            for path in sound.paths {
                if let failure = sourceFailure(path) {
                    skippedSources.append(failure)
                    continue
                }
                guard let resource = resourceView.resource(forReference: path) else {
                    skippedSources.append((.resourceUnavailable, path))
                    continue
                }
                binding = Binding(
                    layerID: object.id,
                    resourceURL: resource.url,
                    displayPath: resourceView.displayPath(for: resource.url),
                    loops: loops,
                    authoredVolume: sound.volume ?? 1,
                    volumePropertyKey: sound.volumePropertyKey
                )
                break
            }
            diagnostics.append(contentsOf: skippedSources.map { skip in
                .init(layerID: object.id, reason: skip.reason, detail: skip.detail)
            })
            if let binding {
                bindings.append(binding)
            }
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
        guard normalizedPlaybackMode(sound.playbackMode) != nil else {
            return (.playbackModeUnsupported, sound.playbackMode ?? "missing")
        }
        guard sound.startsSilent == false else {
            return (.startsSilentUnsupported, String(describing: sound.startsSilent))
        }
        // `mintime` / `maxtime` are retained in the loss-preserving document,
        // but they do not narrow the admitted `loop` contract. Workshop loop
        // layers commonly carry the editor defaults even though playback is
        // continuous; rejecting their presence would reject the whole corpus.
        let hasSpatialTuning = sound.attenuation != nil
            || sound.minimumDistance != nil
        // An explicit false switch makes authored attenuation/distance fields
        // dormant metadata. Keep them loss-preserving, but do not require a
        // spatial player for the ordinary nonspatial loop. Enabled or
        // ambiguous spatial tuning remains layer-local unsupported.
        guard sound.spatialization != true,
              sound.spatialization == false || !hasSpatialTuning else {
            return (.spatialPlaybackUnsupported, "spatial-fields-present")
        }
        guard let volume = sound.volume,
              volume.isFinite,
              (0 ... 1).contains(volume) else {
            return (.volumeInvalid, String(describing: sound.volume))
        }
        return nil
    }

    /// `loop` keeps its continuous playback contract verbatim; `single` plays
    /// once to the end and stops. Every other authored spelling stays
    /// layer-locally rejected.
    private static func normalizedPlaybackMode(_ raw: String?) -> String? {
        switch raw?.localizedLowercase {
        case "loop":
            "loop"
        case "single":
            "single"
        default:
            nil
        }
    }

    /// Per-source guards: path legality and the supported-extension list both
    /// still apply to every authored source, not only the first.
    private static func sourceFailure(
        _ path: String
    ) -> (reason: Diagnostic.Reason, detail: String)? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return (.malformedSourceList, path)
        }
        let supportedExtensions: Set<String> = ["flac", "mp3", "wav"]
        let fileExtension = sourceExtension(of: path)
        guard supportedExtensions.contains(fileExtension) else {
            return (.audioFormatUnsupported, fileExtension)
        }
        return nil
    }

    private static func sourceExtension(of path: String) -> String {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.localizedLowercase
        return fileExtension.isEmpty ? "missing" : fileExtension
    }
}
