//
//  DebugScenePlaybackRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugScenePlaybackRunner {
    static var runsIsolatedSceneSample: Bool {
        argumentValue(after: "--mwx-debug-scene-root") != nil
    }

    static func scheduleScenePlaybackIfRequested() {
        guard let rootPath = argumentValue(after: "--mwx-debug-scene-root") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            launchScene(rootPath: rootPath)
        }
    }

    private static func launchScene(rootPath: String) {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        guard isIsolatedSampleRoot(rootURL) else {
            NSLog("MWX DEBUG SCENE: phase=precondition-failed reason=isolated-root-required root=%@", rootURL.path)
            terminate(after: 0.1)
            return
        }

        let evidenceDirectory = argumentValue(after: "--mwx-debug-scene-evidence-dir")
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        if let evidenceDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: evidenceDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                NSLog("MWX DEBUG SCENE: phase=precondition-failed reason=evidence-directory error=%@", error.localizedDescription)
                terminate(after: 0.1)
                return
            }
        }

        do {
            if evidenceDirectory != nil {
                NSApp.activate(ignoringOtherApps: true)
            }
            let model = try SceneRuntimeModelBuilder().build(rootURL: rootURL)
            guard let cacheDirectory = model.diagnostics.packageReport?.outputURL else {
                throw SceneRuntimeModelBuilder.BuildError.missingRenderDescriptor
            }
            let previewLogURL = evidenceDirectory?.appendingPathComponent("scene-preview.log")
            let launched = SceneDesktopWallpaperHost.shared.launch(
                renderDescriptor: model.renderDescriptor,
                cacheDirectory: cacheDirectory,
                logURL: previewLogURL
            )
            guard launched else {
                NSLog("MWX DEBUG SCENE: phase=launch-failed reason=no-surface root=%@", rootURL.path)
                terminate(after: 0.1)
                return
            }

            let snapshot = SceneDesktopWallpaperHost.shared.debugSnapshot()
            let imageLayerCount = model.renderDescriptor.layers.filter { $0.contentKind == "image" }.count
            NSLog(
                "MWX DEBUG SCENE: phase=ready root=%@ layers=%d imageLayers=%d effects=%d surfaces=%d windows=%@ previewLog=%@",
                rootURL.path,
                model.renderDescriptor.layers.count,
                imageLayerCount,
                model.sceneDocument.effectCount,
                snapshot.surfaceCount,
                snapshot.windowNumbers.map(String.init).joined(separator: ","),
                previewLogURL?.path ?? "-"
            )
            if let evidenceDirectory,
               let windowNumber = snapshot.windowNumbers.first {
                scheduleSnapshots(
                    windowNumber: windowNumber,
                    outputDirectory: evidenceDirectory
                )
            }
            scheduleStop(after: requestedDuration)
        } catch {
            NSLog(
                "MWX DEBUG SCENE: phase=build-failed root=%@ error=%@",
                rootURL.path,
                error.localizedDescription
            )
            terminate(after: 0.1)
        }
    }

    private static func scheduleStop(after duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            let before = SceneDesktopWallpaperHost.shared.debugSnapshot()
            SceneDesktopWallpaperHost.shared.stop()
            let after = SceneDesktopWallpaperHost.shared.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=stopped surfacesBefore=%d surfacesAfter=%d",
                before.surfaceCount,
                after.surfaceCount
            )
            terminate(after: 0.2)
        }
    }

    private static func scheduleSnapshots(
        windowNumber: Int,
        outputDirectory: URL
    ) {
        for (reason, delay) in [("ready", 1.0), ("after", 3.0)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DebugSceneWindowCapture.capture(
                    windowNumber: windowNumber,
                    reason: reason,
                    outputDirectory: outputDirectory
                )
            }
        }
    }

    private static var requestedDuration: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-duration"),
              let duration = TimeInterval(raw) else {
            return 10
        }
        return min(max(duration, 5), 60)
    }

    private static func isIsolatedSampleRoot(_ rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let realWorkshopRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/MyWallpaperX/创意工坊", isDirectory: true)
            .standardizedFileURL.path
        return rootURL.path != realWorkshopRoot
            && rootURL.path.hasPrefix(realWorkshopRoot + "/") == false
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func terminate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.terminate(nil)
        }
    }
}
#endif
