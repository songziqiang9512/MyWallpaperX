"""Exercise the real Engine initializer and factory at recording audio boundaries.

The service records construction and exposes the supplied callbacks; it never
opens an audio device. Web setup, demand observation and display scanning are
recording leaves. The production initializer, stored fields and callback factory
are inserted unchanged, so the former placeholder remains a two-constructor
counterexample when this gate is overlaid on the previous implementation.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.test_web_compat_parity import source_block


ROOT = Path(__file__).resolve().parents[2]
PLAYBACK = ROOT / "MyWallpaperX/Core/Playback"

SUPPORT = r'''
import AppKit
import Foundation

nonisolated final class OwnerProbe: @unchecked Sendable {
    static let shared = OwnerProbe()
    private let lock = NSLock()
    private var constructions: [ObjectIdentifier] = []
    private var eventCounts: [(String, Int)] = []
    private var serviceUses: [ObjectIdentifier] = []
    private var webDeliveries: [ObjectIdentifier] = []

    func constructed(_ service: SystemAudioSpectrumService) {
        lock.withLock { constructions.append(ObjectIdentifier(service)) }
    }
    func event(_ name: String) {
        lock.withLock { eventCounts.append((name, constructions.count)) }
    }
    func use(_ service: SystemAudioSpectrumService) {
        lock.withLock { serviceUses.append(ObjectIdentifier(service)) }
    }
    func webDelivery(_ delivery: PlaybackSpectrumDelivery) {
        lock.withLock { webDeliveries.append(ObjectIdentifier(delivery)) }
    }
    var snapshot: (constructors: Int, events: [(String, Int)],
                   services: [ObjectIdentifier], webDeliveries: [ObjectIdentifier]) {
        lock.withLock { (constructions.count, eventCounts, serviceUses, webDeliveries) }
    }
}

nonisolated final class PlaybackSpectrumDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var overlays: [[Float]] = []
    private var web: [[Float]] = []
    private var scene: [SceneAudioSpectrumRoutedFrame] = []
    func publishOverlay(_ levels: [Float]) { lock.withLock { overlays.append(levels) } }
    func publishWeb(_ levels: [Float]) { lock.withLock { web.append(levels) } }
    func publishScene(_ frame: SceneAudioSpectrumRoutedFrame) { lock.withLock { scene.append(frame) } }
    var snapshot: (overlays: [[Float]], web: [[Float]], scene: [SceneAudioSpectrumRoutedFrame]) {
        lock.withLock { (overlays, web, scene) }
    }
}

nonisolated final class SystemAudioSpectrumService: @unchecked Sendable {
    typealias LevelsHandler = @Sendable ([Float]) -> Void
    typealias SceneLevelsHandler = @Sendable (
        [Float], [Float], [Float], [Float], [Float], [Float], SceneAudioSpectrumCaptureToken
    ) -> Void
    let barCount: Int
    private let onLevels: LevelsHandler?
    private let onWebLevels: LevelsHandler?
    private let onSceneLevels: SceneLevelsHandler?
    init(barCount: Int, onLevels: LevelsHandler? = nil,
         onWebLevels: LevelsHandler? = nil, onSceneLevels: SceneLevelsHandler? = nil) {
        self.barCount = barCount
        self.onLevels = onLevels
        self.onWebLevels = onWebLevels
        self.onSceneLevels = onSceneLevels
        OwnerProbe.shared.constructed(self)
    }
    func emitOverlay(_ values: [Float]) { onLevels?(values) }
    func emitWeb(_ values: [Float]) { onWebLevels?(values) }
    func emitScene(left: [Float], right: [Float], left32: [Float], right32: [Float],
                   left64: [Float], right64: [Float], token: SceneAudioSpectrumCaptureToken) {
        onSceneLevels?(left, right, left32, right32, left64, right64, token)
    }
}

protocol WebWallpaperHostAdapter: AnyObject {
    var eventHandler: ((Int) -> Void)? { get set }
}
final class WebDaemonHostAdapter: WebWallpaperHostAdapter {
    var eventHandler: ((Int) -> Void)?
    init(spectrumDelivery: PlaybackSpectrumDelivery) {
        OwnerProbe.shared.webDelivery(spectrumDelivery)
        OwnerProbe.shared.event("web-host")
    }
}

// Keep the production registration expression without installing an observer.
final class NotificationCenter {
    static let `default` = NotificationCenter()
    func addObserver(_ observer: Any, selector: Selector,
                     name: NSNotification.Name?, object: Any?) {
        OwnerProbe.shared.event("screen-observer")
    }
}

// ENGINE_DECLARATION
    // ENGINE_FIELDS
    // ENGINE_INITIALIZER

    func handleWebHostEvent(_ event: Int) { OwnerProbe.shared.event("web-event") }
    func configureWebSwitchCallbacks() {
        OwnerProbe.shared.event("web-callbacks")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
    func observeSceneAudioSpectrumDemand() {
        OwnerProbe.shared.event("scene-demand")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
    @objc func handleScreenParametersChanged() {}
    func scanDisplays() {
        OwnerProbe.shared.event("display-scan")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
}

extension WallpaperEngine {
    // ENGINE_FACTORY
}

@main enum Harness {
    @MainActor static func main() throws {
        let engine = WallpaperEngine()
        let initialized = OwnerProbe.shared.snapshot
        var checks: [String: Bool] = [:]
        checks["exactlyOneServiceConstructedBeforeInitializerReturns"] = initialized.constructors == 1
        checks["serviceExistsBeforeEveryExternalSetupLeaf"] = initialized.events.map { $0.0 }
            == ["web-host", "web-callbacks", "scene-demand", "screen-observer", "display-scan"]
            && initialized.events.allSatisfy { $0.1 == 1 }
        let service = engine.systemAudioSpectrumService
        let delivery = engine.spectrumDelivery
        checks["setupAndLaterReadsUseTheSameService"] = initialized.services.count == 3
            && initialized.services.allSatisfy { $0 == ObjectIdentifier(service) }
            && engine.systemAudioSpectrumService === service
        checks["webHostReceivesTheEngineDelivery"] = initialized.webDeliveries == [ObjectIdentifier(delivery)]
        checks["initialLevelsAndServiceUseTheConfiguredDefaultBandCount"] = service.barCount == WallpaperEngine.defaultSpectrumBarCount
            && engine.currentSpectrumLevels == Array(repeating: 0, count: service.barCount)

        let overlay: [Float] = [0.125, 0.875]
        let web = (0..<128).map { Float($0) / 128 }
        let left = (0..<16).map { Float($0 + 1) }
        let right = (0..<16).map { Float($0 + 21) }
        let left32 = (0..<32).map { Float($0 + 41) }
        let right32 = (0..<32).map { Float($0 + 81) }
        let left64 = (0..<64).map { Float($0 + 121) }
        let right64 = (0..<64).map { Float($0 + 201) }
        let token = SceneAudioSpectrumCaptureToken(scopeEpoch: 73, includesCurrentProcessOutput: true)
        service.emitOverlay(overlay)
        let afterOverlay = delivery.snapshot
        checks["overlayCallbackTargetsOnlyTheEngineOverlayDelivery"] = afterOverlay.overlays == [overlay]
            && afterOverlay.web.isEmpty && afterOverlay.scene.isEmpty
        service.emitWeb(web)
        let afterWeb = delivery.snapshot
        checks["webCallbackTargetsOnlyTheEngineWebDelivery"] = afterWeb.overlays == [overlay]
            && afterWeb.web == [web] && afterWeb.scene.isEmpty
        service.emitScene(left: left, right: right, left32: left32, right32: right32,
                          left64: left64, right64: right64, token: token)
        let afterScene = delivery.snapshot
        checks["sceneCallbackPreservesEveryBandArrayAndCaptureToken"] = afterScene.scene.count == 1
            && afterScene.scene.first?.left == left && afterScene.scene.first?.right == right
            && afterScene.scene.first?.left32 == left32 && afterScene.scene.first?.right32 == right32
            && afterScene.scene.first?.left64 == left64 && afterScene.scene.first?.right64 == right64
            && afterScene.scene.first?.captureToken == token
            && afterScene.overlays == [overlay] && afterScene.web == [web]
        let nextToken = SceneAudioSpectrumCaptureToken(scopeEpoch: 74, includesCurrentProcessOutput: false)
        service.emitScene(left: right, right: left, left32: right32, right32: left32,
                          left64: right64, right64: left64, token: nextToken)
        let final = delivery.snapshot
        checks["laterSceneCallbackUsesItsOwnArraysAndToken"] = final.scene.count == 2
            && final.scene.last?.left == right && final.scene.last?.right == left
            && final.scene.last?.left32 == right32 && final.scene.last?.right32 == left32
            && final.scene.last?.left64 == right64 && final.scene.last?.right64 == left64
            && final.scene.last?.captureToken == nextToken
        checks["callbackDeliveryDoesNotReplaceTheService"] = OwnerProbe.shared.snapshot.constructors == 1
            && engine.systemAudioSpectrumService === service
        let result: [String: Any] = ["checks": checks, "constructorCount": initialized.constructors,
            "constructionCountsAtSetup": initialized.events.map { ["leaf": $0.0, "count": $0.1] as [String: Any] }]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SystemAudioSpectrumOwnerTests(unittest.TestCase):
    def test_initializer_owns_one_eager_service_with_all_callbacks(self):
        engine = (PLAYBACK / "WallpaperEngine.swift").read_text()
        audio = (PLAYBACK / "WallpaperEngine+SystemAudioSpectrum.swift").read_text()
        delivery = (PLAYBACK / "PlaybackSpectrumDelivery.swift").read_text()
        scene = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift").read_text()
        fields = []
        for name in ["dedicatedWebHostAdapter", "currentSpectrumLevels", "systemAudioSpectrumService",
                     "spectrumDelivery", "defaultSpectrumBarCount"]:
            matches = re.findall(r"^    (?:(?:lazy|static) )*(?:let|var) " + re.escape(name)
                                 + r"(?:\s*[:=]).*$", engine, re.MULTILINE)
            self.assertEqual(len(matches), 1, f"one production field declaration required: {name}")
            fields.append(matches[0])
        header = re.search(r"^public final class WallpaperEngine: NSObject \{$", engine, re.MULTILINE)
        self.assertIsNotNone(header)
        source = SUPPORT.replace("// ENGINE_DECLARATION", header.group(0))
        source = source.replace("// ENGINE_FIELDS", "\n".join(fields))
        source = source.replace("// ENGINE_INITIALIZER", source_block(engine, "override init()"))
        source = source.replace("// ENGINE_FACTORY", source_block(audio, "makeSystemAudioSpectrumService("))
        source = source_block(scene, "struct SceneAudioSpectrumCaptureToken:") + "\n" + source
        source = source_block(delivery, "struct SceneAudioSpectrumRoutedFrame:") + "\n" + source
        with tempfile.TemporaryDirectory(prefix="mwx-audio-owner-", dir="/private/tmp") as folder:
            work = Path(folder)
            swift = work / "Harness.swift"
            swift.write_text(source)
            binary = work / "audio-owner"
            build = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                                    "-parse-as-library", str(swift), "-module-cache-path", str(work / "modules"),
                                    "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout)
            if proof := os.environ.get("MWX_SYSTEM_AUDIO_OWNER_PROOF_DIR"):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
                (output / "runtime.log").write_text(run.stderr)
            self.assertTrue(result["checks"])
            for name, passed in result["checks"].items():
                with self.subTest(name=name, constructorCount=result["constructorCount"]):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
