#if DEBUG
import AppKit
import Foundation
import WebKit

/// Opt-in real-player evidence through the production Web host or Scene IPC.
/// The observer is status-only: the actual wallpaper must request song data.
@MainActor
enum DebugSystemMediaRunner {
    static var isRequested: Bool { value("--mwx-debug-system-media-root") != nil }
    private static let observerID = UUID()
    private static var webHost: DedicatedWebWallpaperHostPlaceholderAdapter?
    private static var timer: Timer?
    private static var output: URL?
    private static var history: [[String: Any]] = []
    private static var webHistory: [[String: Any]] = []
    private static var lastCaptureKey: String?
    private static var captureCount = 0
    private static var closing = false

    static func scheduleIfRequested() {
        guard let rootPath = value("--mwx-debug-system-media-root"),
              let outputPath = value("--mwx-debug-system-media-output"),
              let protectedRoot = DebugSceneProductEntryPolicy.protectedWorkshopRootURL() else { return }
        let root = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().standardizedFileURL
        guard root != protectedRoot, !root.path.hasPrefix(protectedRoot.path + "/") else {
            NSLog("MWX MEDIA VALIDATION: isolated input required")
            NSApp.terminate(nil)
            return
        }
        output = URL(fileURLWithPath: outputPath, isDirectory: true)
        guard let output else { return }
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { NSLog("MWX MEDIA VALIDATION: output error %@", error.localizedDescription); NSApp.terminate(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        setEnabled(true)
        SystemMediaService.shared.subscribe(observerID, needsMedia: false) { snapshot in
            guard !closing else { return }
            history.append([
                "uptime": ProcessInfo.processInfo.systemUptime,
                "enabled": snapshot.enabled, "epoch": snapshot.epoch, "revision": snapshot.revision,
                "sessionGeneration": snapshot.sessionGeneration,
                "source": snapshot.sourceID ?? "", "title": snapshot.media.properties?.title ?? "",
                "artist": snapshot.media.properties?.artist ?? "", "state": snapshot.media.playbackState ?? 0,
                "artworkBytes": snapshot.media.current?.count ?? 0,
                "webPNGBytes": snapshot.webThumbnail?.utf8.count ?? 0,
                "position": snapshot.media.timeline?.position ?? 0
            ])
            write(history, name: "producer-history.json")
        }
        PlaybackPolicyController.shared.updateSettings({
            var settings = WallpaperSettings()
            settings.pauseWhenOtherAppFocused = false
            settings.pauseWhenOtherAppFullscreen = false
            settings.pauseWhenIdle = false
            settings.pauseWhenUnplugged = false
            return settings
        }())
        if value("--mwx-debug-system-media-mode") == "scene" {
            SceneDaemonClient.shared.requestLaunch(.init(rootURL: root, propertyOverrides: [:],
                userPropertyTextures: [:], recordID: "system-media-validation"))
            // A diagnostic load does not imply the product's play intent.
            PlaybackCommandMultiplexer.shared.dispatch(.resume, to: .scene)
            SceneDaemonClient.shared.handle(.setPlaybackPaused(false))
        } else {
            let host = DedicatedWebWallpaperHostPlaceholderAdapter()
            webHost = host
            host.launch(.init(entryURL: root.appendingPathComponent("index.html"), rootURL: root,
                propertiesJSON: "{}", source: .steamWorkshop, recordID: "system-media-validation",
                language: "zh-Hans", runtimeProfile: value("--mwx-debug-system-media-origin") == "loopback"
                    ? .diagnostic : .strictLocal, multiDisplayEnabled: false),
                runtimeState: .init(paused: false, volume: 0, playbackRate: 1, spectrumLevels: nil))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { collect() }
        }
        let duration = min(180, max(10, Double(value("--mwx-debug-system-media-duration") ?? "60") ?? 60))
        if ProcessInfo.processInfo.arguments.contains("--mwx-debug-system-media-switch-cycle") {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.65) { if !closing { setEnabled(false) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8) { if !closing { setEnabled(true) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish() }
    }

    private static func setEnabled(_ enabled: Bool) {
        // Volatile argument-domain override never changes the user's settings.
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[SceneMediaSourcePreference.key] = enabled
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        SceneMediaSourcePreference.notifyChange()
    }

    private static func collect() {
        guard !closing else { return }
        if let host = webHost {
            for surface in host.surfaces.values {
                surface.webView.evaluateJavaScript(#"""
                (() => { const m=window.__myWallpaperMediaState||{}; const i=document.querySelector('img');
                  return JSON.stringify({status:m.status,properties:m.properties,playback:m.playback,timeline:m.timeline,
                    thumbnailLength:((m.thumbnail||{}).thumbnail||'').length,
                    png:((m.thumbnail||{}).thumbnail||'').startsWith('data:image/png;base64,'),
                    imageLoaded:!!(i&&i.complete&&i.naturalWidth>0),text:document.body.innerText.slice(0,2048)}); })();
                """#) { result, _ in
                    guard !closing, let text = result as? String, let data = text.data(using: .utf8),
                          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                    write(value, name: "web-latest.json")
                    webHistory.append(value)
                    write(webHistory, name: "web-history.json")
                    let identity: [String: Any] = ["properties": value["properties"] ?? [:],
                        "playback": value["playback"] ?? [:], "status": value["status"] ?? [:],
                        "imageLoaded": value["imageLoaded"] ?? false]
                    guard let keyData = try? JSONSerialization.data(withJSONObject: identity, options: .sortedKeys) else { return }
                    let key = String(decoding: keyData, as: UTF8.self)
                    guard key != lastCaptureKey, captureCount < 8 else { return }
                    lastCaptureKey = key
                    captureCount += 1
                    let name = "web-\(captureCount).png"
                    let configuration = WKSnapshotConfiguration()
                    configuration.snapshotWidth = 960
                    surface.webView.takeSnapshot(with: configuration) { image, _ in
                        guard let image, let tiff = image.tiffRepresentation,
                              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
                              let output else { return }
                        try? png.write(to: output.appendingPathComponent(name))
                    }
                }
            }
        } else if let latest = history.last {
            let key = "\(latest["title"] ?? "")/\(latest["state"] ?? 0)/\(latest["enabled"] ?? false)/\(latest["artworkBytes"] ?? 0)"
            guard key != lastCaptureKey, captureCount < 8 else { return }
            lastCaptureKey = key
            captureCount += 1
            let name = "scene-\(captureCount).jpg"
            // IPC delivery and authored cover/text transitions complete after
            // the producer callback; capture the settled consumer, not ingress.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard !closing, lastCaptureKey == key else { return }
                SceneDaemonClient.shared.captureSurfaceFrame { imageURL in
                    guard let imageURL, let output else { return }
                    try? FileManager.default.moveItem(at: imageURL, to: output.appendingPathComponent(name))
                }
            }
        }
    }

    private static func finish() {
        closing = true
        timer?.invalidate()
        timer = nil
        webHost?.handle(.stop)
        webHost = nil
        SceneDaemonClient.shared.shutdown()
        SystemMediaService.shared.unsubscribe(observerID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    private static func write(_ value: Any, name: String) {
        guard let output, let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: output.appendingPathComponent(name), options: .atomic)
    }

    private static func value(_ flag: String) -> String? { DebugScenePlaybackRunner.argumentValue(after: flag) }
}
#endif
