#if DEBUG
import Foundation

extension DebugSceneDaemonClientRunner {
    private struct TextureStep {
        let delay: TimeInterval
        let definition: SceneUserPropertyDefinition
        let url: URL?
    }

    private static var textureSteps: [TextureStep] = []
    private static var textureRecord: SteamWorkshopDownloadRecord?
    private static var textureSequenceStarted = false
    static var textureSequenceFinished = false
    static var textureSequenceResults: [[String: Any]] = []

    /// Explicit evidence input only. Definitions use the same product context
    /// as the editor, prepared once before playback rather than per update.
    static func prepareUserTextureSequence(
        record: SteamWorkshopDownloadRecord
    ) -> Bool {
        let flag = "--mwx-debug-scene-live-texture-sequence-json"
        guard ProcessInfo.processInfo.arguments.contains(flag) else { return true }
        guard let payload = DebugScenePlaybackRunner.argumentValue(after: flag),
              let data = payload.data(using: .utf8), data.count <= 65_536,
              let objects = try? JSONSerialization.jsonObject(with: data)
                as? [[String: Any]], objects.count <= 64 else { return false }
        let facts = SceneRuntimeSourceFactsBuilder().build(rootURL: record.folderURL)
        guard let context = SteamWorkshopService.shared.scenePropertyContext(
            for: record, sourceFacts: facts
        ) else { return false }
        let root = record.folderURL.resolvingSymlinksInPath().standardizedFileURL
        var steps: [TextureStep] = []
        for object in objects {
            guard let delay = object["delay"] as? Double,
                  delay.isFinite, delay >= 0, delay <= 3_600,
                  let key = object["key"] as? String,
                  let definition = context.actionableDefinitions.first(where: {
                      $0.key == key && $0.kind == .sceneTexture
                  }) else { return false }
            let url: URL?
            if object["file"] is NSNull {
                url = nil
            } else if let path = object["file"] as? String, !path.isEmpty {
                let candidate = URL(fileURLWithPath: path, relativeTo: root)
                    .resolvingSymlinksInPath().standardizedFileURL
                guard candidate.path.hasPrefix(root.path + "/") else { return false }
                // Missing/corrupt files deliberately reach the real selection
                // owner so failure-preserves-old evidence is not prefiltered.
                url = candidate
            } else {
                return false
            }
            steps.append(.init(delay: delay, definition: definition, url: url))
        }
        textureSteps = steps
        textureRecord = record
        return true
    }

    static func scheduleUserTextureSequence() {
        guard !textureSequenceStarted, !textureSequenceFinished,
              let record = textureRecord, !textureSteps.isEmpty else { return }
        textureSequenceStarted = true
        for (index, step) in textureSteps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                guard !textureSequenceFinished else { return }
                let started = ProcessInfo.processInfo.systemUptime
                let pid = SceneDaemonClient.shared.debugProcessIdentifier
                NSLog("MWX SCENE CLIENT: phase=texture-selection index=%d key=%@ file=%@",
                      index, step.definition.key, step.url?.lastPathComponent ?? "reset")
                SteamWorkshopService.shared.updateSceneTexturePropertyURL(
                    step.url, definition: step.definition, record: record
                ) { accepted in
                    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                    textureSequenceResults.append([
                        "index": index, "key": step.definition.key,
                        "file": step.url?.lastPathComponent ?? "reset",
                        "accepted": accepted, "acknowledgementMs": elapsed,
                        "daemonPIDBefore": pid.map { Int($0) } ?? -1,
                        "daemonPIDAfter": SceneDaemonClient.shared.debugProcessIdentifier
                            .map { Int($0) } ?? -1,
                        "committedValue": SteamWorkshopService.shared
                            .scenePropertyOverrides(for: record)[step.definition.key]?
                            .foundationValue ?? NSNull()
                    ])
                    NSLog("MWX SCENE CLIENT: phase=texture-result index=%d accepted=%@ ackMs=%.3f",
                          index, accepted ? "true" : "false", elapsed)

                }
            }
        }
    }

}
#endif
