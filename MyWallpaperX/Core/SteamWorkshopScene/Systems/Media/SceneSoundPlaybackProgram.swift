import AVFoundation
import Foundation

/// Launch-scoped typed plan for authored Sound layers. The program admits only
/// the shared, observable subset whose playback and failure boundary are known;
/// unsupported authored forms remain in `SceneDocument` and reject only their
/// own Sound layer.
struct SceneSoundPlaybackProgram {
    struct Resource {
        /// Nil retains a selected but ordinarily unreadable source slot. It
        /// must not trigger another authored path or lower-priority Root.
        let file: SceneVideoOwnedFile?
        let displayPath: String
    }

    enum PlaybackMode: Equatable {
        case loop
        case single
        case random(minimumTime: Double, maximumTime: Double)
    }

    struct Binding {
        let layerID: Int
        let resources: [Resource]
        let playbackMode: PlaybackMode
        let startsSilent: Bool
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
            case intervalInvalid
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
    private(set) var scriptVolumeTargets: Set<SceneDynamicTarget> = []

    private struct AdmissionFailure: Error {
        let reason: Diagnostic.Reason
        let detail: String
    }

    /// Final owner construction transfers gain publication for these targets.
    /// The property key remains input identity, never a second player writer.
    func assigningSceneScriptVolumes(_ targets: Set<SceneDynamicTarget>) -> Self {
        var result = self
        result.scriptVolumeTargets = targets.intersection(Set(bindings.map(\.volumeTarget)))
        return result
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.volumePropertyKey == nil ? nil : binding.volumeTarget
        })
    }

    /// The IR seed is authored, while this plan carries the resolved startup
    /// seed. Named inputs instead prove the same property and resolved seed;
    /// the IR raw seed stays independently validated by Scalar projection.
    func sceneScriptVolumeConsumerTargets(
        for definitions: [SceneDynamicTargetDefinition],
        namedPropertyKeys: [SceneDynamicTarget: String] = [:],
        resolvedPropertyVolumes: [String: Double] = [:]
    ) -> Set<SceneDynamicTarget> {
        Set(definitions.compactMap { definition in
            guard case .layer(_, .volume) = definition.target,
                  case let .scalar(seed) = definition.authoredValue,
                  let binding = bindings.first(where: {
                      $0.volumeTarget == definition.target
                  }),
                  seed.isFinite, (0 ... 1).contains(seed)
            else { return nil }
            if let key = binding.volumePropertyKey {
                guard namedPropertyKeys[definition.target] == key,
                      let current = resolvedPropertyVolumes[key],
                      current.bitPattern == binding.authoredVolume.bitPattern else { return nil }
            } else if binding.authoredVolume.bitPattern != seed.bitPattern {
                return nil
            }
            return definition.target
        })
    }

    /// Diagnostics for layers that admitted no binding at all.
    var layerRejectionCount: Int {
        let admittedLayerIDs = Set(bindings.map(\.layerID))
        return Set(diagnostics.lazy.filter {
            !admittedLayerIDs.contains($0.layerID)
        }.map(\.layerID)).count
    }

    /// Source diagnostics on admitted layers include unavailable selected
    /// slots. They must not read as rejected layers in corpus tooling.
    var skippedSourceCount: Int {
        let admittedLayerIDs = Set(bindings.map(\.layerID))
        return diagnostics.filter { admittedLayerIDs.contains($0.layerID) }.count
    }

    var reportLines: [String] {
        var lines = [
            "scene sound playback: schema=avqueueplayer-multi-source-v3"
                + " admitted=\(bindings.count) rejected=\(layerRejectionCount)"
                + " skipped=\(skippedSourceCount)"
                + " route=generic-only failure=layer-local"
                + " dynamicVolumeTargets=\(liveConsumerTargets.count)",
        ]
        lines += bindings.map { binding in
            let mode: String
            switch binding.playbackMode {
            case .loop: mode = "loop"
            case .single: mode = "single"
            case .random: mode = "random"
            }
            return "scene sound binding: layer=\(binding.layerID) mode=\(mode)"
                + " candidates=\(binding.resources.count)"
                + " sources=\(binding.resources.map(\.displayPath).joined(separator: ","))"
                + " volume=\(binding.authoredVolume)"
                + " property=\(binding.volumePropertyKey ?? "-")"
        }
        lines += diagnostics.map {
            "scene sound diagnostic: layer=\($0.layerID)"
                + " reason=\($0.reason.rawValue) detail=\($0.detail)"
        }
        return lines
    }

    static func compile(
        document: SceneDocument,
        resourceView: SceneResourceView,
        privateCacheDirectory: URL,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneSoundPlaybackProgram {
        var bindings: [Binding] = []
        var diagnostics: [Diagnostic] = []
        var preparedResources: [SceneResourceView.FileInput: Resource] = [:]
        for object in document.objects.sorted(by: { $0.id < $1.id }) {
            try checkCancellation?()
            guard let sound = object.sound else { continue }
            let playbackMode: PlaybackMode
            switch admission(sound) {
            case let .success(mode):
                playbackMode = mode
            case let .failure(rejection):
                diagnostics.append(.init(
                    layerID: object.id,
                    reason: rejection.reason,
                    detail: rejection.detail
                ))
                continue
            }
            var skippedSources: [(reason: Diagnostic.Reason, detail: String)] = []
            var resources: [Resource] = []
            // Preserve index selection, including an unavailable selected slot.
            // Random retains all selected references; playback owns decoding.
            for path in sound.paths {
                try checkCancellation?()
                if let failure = sourceFailure(path) {
                    skippedSources.append(failure)
                    continue
                }
                guard let handle = resourceView.resolvedResource(forReference: path) else {
                    skippedSources.append((.resourceUnavailable, path))
                    continue
                }
                let input = SceneResourceView.FileInput.resource(handle)
                let resource: Resource
                if let prepared = preparedResources[input] {
                    resource = prepared
                } else {
                    let file: SceneVideoOwnedFile?
                    do {
                        file = try SceneVideoOwnedFile.snapshot(
                            from: handle, cacheDirectory: privateCacheDirectory,
                            fileExtension: sourceExtension(of: path),
                            checkCancellation: checkCancellation
                        )
                    } catch SceneResourceView.ReadError.missing {
                        file = nil
                    } catch SceneResourceView.ReadError.unreadable {
                        file = nil
                    } catch SceneVideoOwnedFile.Failure.directoryCreation {
                        file = nil
                    } catch SceneVideoOwnedFile.Failure.aggregateDiskBudgetExceeded {
                        file = nil
                    } catch SceneVideoOwnedFile.Failure.io(let operation, _)
                        where operation == .createSnapshot || operation == .writeSnapshot
                            || operation == .closeSnapshot {
                        file = nil
                    }
                    resource = Resource(
                        file: file,
                        displayPath: handle.displayPath
                    )
                    preparedResources[input] = resource
                }
                if resource.file == nil {
                    skippedSources.append((.resourceUnavailable, resource.displayPath))
                }
                resources.append(resource)
                if case .random = playbackMode { continue }
                break
            }
            diagnostics.append(contentsOf: skippedSources.map { skip in
                .init(layerID: object.id, reason: skip.reason, detail: skip.detail)
            })
            if !resources.isEmpty {
                bindings.append(Binding(
                    layerID: object.id, resources: resources,
                    playbackMode: playbackMode,
                    startsSilent: sound.startsSilent == true,
                    authoredVolume: sound.volume ?? 1,
                    volumePropertyKey: sound.volumePropertyKey
                ))
            }
        }
        try checkCancellation?()
        return SceneSoundPlaybackProgram(
            bindings: bindings,
            diagnostics: diagnostics
        )
    }

    private static func admission(
        _ sound: SceneDocument.SceneSoundLayerDefinition
    ) -> Result<PlaybackMode, AdmissionFailure> {
        guard sound.authoredPathCount == sound.paths.count,
              !sound.paths.isEmpty else {
            return .failure(.init(
                reason: .malformedSourceList, detail: "count=\(sound.authoredPathCount)"
            ))
        }
        let playbackMode: PlaybackMode
        switch sound.playbackMode?.localizedLowercase {
        case "loop": playbackMode = .loop
        case "single": playbackMode = .single
        case "random":
            guard let minimum = sound.minimumTime, let maximum = sound.maximumTime,
                  minimum.isFinite, maximum.isFinite, minimum >= 0, minimum <= maximum else {
                return .failure(.init(
                    reason: .intervalInvalid,
                    detail: "min=\(String(describing: sound.minimumTime))"
                        + " max=\(String(describing: sound.maximumTime))"
                ))
            }
            playbackMode = .random(minimumTime: minimum, maximumTime: maximum)
        default:
            return .failure(.init(
                reason: .playbackModeUnsupported, detail: sound.playbackMode ?? "missing"
            ))
        }
        guard sound.startsSilent != nil else {
            return .failure(.init(
                reason: .startsSilentUnsupported, detail: String(describing: sound.startsSilent)
            ))
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
            return .failure(.init(
                reason: .spatialPlaybackUnsupported, detail: "spatial-fields-present"
            ))
        }
        guard let volume = sound.volume,
              volume.isFinite,
              (0 ... 1).contains(volume) else {
            return .failure(.init(
                reason: .volumeInvalid, detail: String(describing: sound.volume)
            ))
        }
        return .success(playbackMode)
    }

    /// Platform format capability is stable preparation metadata, not proof
    /// that an individual file or codec can decode. Playback keeps that owner.
    private static let nativeOggPlaybackAvailable =
        AVURLAsset.isPlayableExtendedMIMEType("audio/ogg")

    /// Each attempted source checks path legality before format capability;
    /// loop/single selection stops at the first available resource.
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
        guard supportedExtensions.contains(fileExtension)
                || (fileExtension == "ogg" && nativeOggPlaybackAvailable) else {
            return (.audioFormatUnsupported, fileExtension)
        }
        return nil
    }

    private static func sourceExtension(of path: String) -> String {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.localizedLowercase
        return fileExtension.isEmpty ? "missing" : fileExtension
    }
}
