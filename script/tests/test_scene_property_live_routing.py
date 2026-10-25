#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path

from script.tests.scene_video_segment_delegate_fixture import compile_segment_delegate


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SERVICE_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopSceneService+SceneProperties.swift"
)
TEXTURE_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopSceneService+SceneTextureProperties.swift"
)
EDITOR_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopScenePropertyEditorView.swift"
)
LIVE_CONSUMERS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+LiveConsumers.swift"
LAYER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor+Layer.swift"
RUNTIME_MODEL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift"
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
PLAYBACK_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+ScenePlayback.swift"


SELECTION_PROBE = r'''
import Combine
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
enum SceneTextureLoadOutcome {
    case loaded(MTLTexture), decodeFailed(String), textureAllocationFailed(width: Int, height: Int)
}
struct SteamWorkshopDownloadRecord {
    enum ContentType { case scene, video }
    let id: String; let contentType: ContentType; let folderURL: URL; let title: String
}
struct PlaybackResourceLifetime {}
extension Notification.Name {
    static let steamWorkshopSceneReadyToRender = Self("own-selection-probe-request")
}
@MainActor final class SteamWorkshopService {
    let suiteName = "com.songziqiang.MyWallpaperX.Debug.SelectionTest." + UUID().uuidString
    let defaults: UserDefaults
    let objectWillChange = ObservableObjectPublisher()
    var downloadError: String?; var statusMessage = ""
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyEditRevisions: [String: UInt64] = [:]
    var pendingSceneTextureProperties: [String: SceneTexturePropertyPending] = [:]
    var scenePropertyRenderTask: Task<Void, Never>?
    var webLaunchIntentGeneration: UInt64 = 0
    var prepareScenePlaybackIntent: ((String, Bool) ->
        (intentEpoch: UInt64, isCurrent: () -> Bool, cancel: () -> Void)?)?
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    func cleanup() { defaults.removePersistentDomain(forName: suiteName); defaults.synchronize() }
    // Controlled source admission; playback runs its real synchronous method.
    struct SceneSourceAdmission {
        let source: ScenePlaybackSource
        let resourceLifetime: PlaybackResourceLifetime?
    }
    func sceneSourceAdmission(for record: SteamWorkshopDownloadRecord) throws -> SceneSourceAdmission {
        .init(source: .init(rootURL: record.folderURL), resourceLifetime: nil)
    }
    func clearLaunchPending(matching id: String) {}
    func resetSceneShortcutProperties(for record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void) { completion(.applied) }

    func sceneShortcutConfiguration(for record: SteamWorkshopDownloadRecord) -> ScenePlaybackShortcutConfiguration { .empty }
}
@MainActor final class PlaybackCommandMultiplexer {
    static let shared = PlaybackCommandMultiplexer()
    enum Command { case setProperty([String: SceneUserPropertyValue], revision: UInt64, recordID: String) }
    enum Destination { case scene }
    var pending: [(ScenePlaybackTextureUpdate, @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void)] = []
    var scalarDispatches = 0
    var lastScalarValues: [String: SceneUserPropertyValue] = [:]
    func dispatch(_ command: Command, to destination: Destination) -> Bool {
        scalarDispatches += 1
        if case let .setProperty(values, _, _) = command { lastScalarValues = values }
        return true
    }
    func applyUserTextureUpdate(_ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void) -> Bool {
        pending.append((update, completion)); return true
    }
    func reloadUserTextureUpdate(_ update: ScenePlaybackTextureUpdate,
        completion: @escaping @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void) -> Bool { false }
    func finish(_ outcome: ScenePlaybackTextureUpdateOutcome) { pending.removeFirst().1(outcome) }
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var active = false
    func hasIntent(for id: String) -> Bool { active }
    func preparedCallbackPropertyKeys(for recordID: String, source: ScenePreparedCallbackPropertyReachability.Source?) -> Set<String> { [] }
}
@MainActor final class RequestSpy {
    var requests: [SteamWorkshopScenePlaybackRequest] = []
}
@main enum SelectionProbe {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = SteamWorkshopService()
        defer { service.cleanup() }
        let record = SteamWorkshopDownloadRecord(id: "own", contentType: .scene, folderURL: root, title: "own")
        let definition = SceneUserPropertyDefinition(
            key: "cover", title: "cover", kind: .sceneTexture, runtimeType: "scenetexture",
            order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil,
            defaultValue: .string(""), options: []
        )
        let bookmarkKey = "SteamWorkshop.scenePropertyBookmarks.own.cover"
        let spy = RequestSpy()
        let observer = NotificationCenter.default.addObserver(
            forName: .steamWorkshopSceneReadyToRender, object: nil, queue: nil
        ) { note in
            guard let request = note.userInfo?["request"] as? SteamWorkshopScenePlaybackRequest else { return }
            MainActor.assumeIsolated { spy.requests.append(request) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        func outcomeLabel(_ outcome: ScenePlaybackTextureUpdateOutcome?) -> String {
            guard let outcome else { return "pending" }
            switch outcome {
            case .applied: return "applied"
            case .superseded: return "superseded"
            case .unavailable: return "unavailable"
            case .failed: return "failed"
            }
        }
        func select(_ url: URL?, definition selectedDefinition: SceneUserPropertyDefinition? = nil) async -> ScenePlaybackTextureUpdateOutcome {
            await withCheckedContinuation { continuation in
                service.updateSceneTexturePropertyURL(url, definition: selectedDefinition ?? definition, record: record) {
                    continuation.resume(returning: $0)
                }
            }
        }
        func waitForReload() async throws { try await Task.sleep(nanoseconds: 300_000_000) }
        func requestPath() -> String {
            guard let request = spy.requests.last else { return "none" }
            return DaemonProbe.resolveTextureURLs(request.userPropertyTextures)["cover"]?.lastPathComponent ?? "none"
        }
        var rows: [[String: Any]] = []
        let png = root.appendingPathComponent("good.png")
        let sourceImage = SceneImageTextureUploader.decodeSourceImage(try Data(contentsOf: png))!
        let jpeg = root.appendingPathComponent("good.jpeg")
        let destination = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, sourceImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

        for name in ["good.png", "good.jpeg"] {
            let before = spy.requests.count
            let accepted = await select(root.appendingPathComponent(name))
            try await waitForReload()
            let reloads = spy.requests.count - before
            service.requestSceneRender(record)
                rows.append(["case": name, "outcome": outcomeLabel(accepted), "reloads": reloads, "path": requestPath()])
        }
        for name in ["broken.png", "crc-broken.png", "directory.png", "missing.png", "unsupported.gif"] {
            _ = await select(png)
            try await waitForReload()
            let bookmark = service.defaults.data(forKey: bookmarkKey)
            let overrides = service.scenePropertyOverrides(for: record)
            let before = spy.requests.count
            let url = root.appendingPathComponent(name)
            let accepted = await select(url)
            try await waitForReload()
            let reloads = spy.requests.count - before
            service.requestSceneRender(record)
                rows.append([
                "case": name, "outcome": outcomeLabel(accepted), "reloads": reloads,
                "bookmarkUnchanged": service.defaults.data(forKey: bookmarkKey) == bookmark,
                "overridesUnchanged": service.scenePropertyOverrides(for: record) == overrides,
                "path": requestPath(), "error": service.downloadError != nil,
                "contentType": (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? "none",
            ])
        }
        let old = service.defaults.data(forKey: bookmarkKey)
        let recovery = await select(jpeg)
        try await waitForReload()
        service.requestSceneRender(record)
        rows.append(["case": "recovery", "outcome": outcomeLabel(recovery), "bookmarkChanged": service.defaults.data(forKey: bookmarkKey) != old, "path": requestPath()])
        let cleared = await select(nil)
        try await waitForReload()
        service.requestSceneRender(record)
        rows.append(["case": "clear", "outcome": outcomeLabel(cleared), "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil, "overrides": service.scenePropertyOverrides(for: record).count, "path": requestPath()])
        _ = await select(png)
        try await waitForReload()
        let resetOutcome = await withCheckedContinuation { continuation in
            service.resetScenePropertyValues(for: record, defaultValues: ["cover": .string("")]) {
                continuation.resume(returning: $0)
            }
        }
        service.requestSceneRender(record)
        rows.append(["case": "reset", "outcome": outcomeLabel(resetOutcome), "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil, "overrides": service.scenePropertyOverrides(for: record).count, "path": requestPath()])
        let mux = PlaybackCommandMultiplexer.shared
        SceneDaemonClient.shared.active = true
        func waitForPending(_ count: Int = 1) async throws {
            for _ in 0..<500 {
                if mux.pending.count >= count { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw CocoaError(.coderReadCorrupt)
        }
        let pendingFailure = Task { @MainActor in await select(png) }
        try await waitForPending()
        let beforeAckEmpty = service.defaults.data(forKey: bookmarkKey) == nil && service.scenePropertyOverrides(for: record).isEmpty
        mux.finish(.failed("own-runtime-decode-failure"))
        let failed = await pendingFailure.value
        rows.append(["case": "live-failure", "beforeAckEmpty": beforeAckEmpty,
            "outcome": outcomeLabel(failed), "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil,
            "overrides": service.scenePropertyOverrides(for: record).count, "error": service.downloadError != nil,
            "reasonPreserved": failed == .failed("own-runtime-decode-failure")])
        let older = Task { @MainActor in await select(png) }
        try await waitForPending()
        let newer = Task { @MainActor in await select(jpeg) }
        try await waitForPending(2)
        let olderAccepted = await older.value
        mux.finish(.applied)
        let oldAckDidNotSave = service.defaults.data(forKey: bookmarkKey) == nil
        mux.finish(.applied)
        let newerAccepted = await newer.value
        rows.append(["case": "live-latest", "olderOutcome": outcomeLabel(olderAccepted),
            "olderAckDidNotSave": oldAckDidNotSave, "newerOutcome": outcomeLabel(newerAccepted),
            "value": service.scenePropertyOverrides(for: record)["cover"]?.stringValue ?? "none", "error": service.downloadError != nil])
        let oldSelection = Task { @MainActor in await select(png) }
        try await waitForPending()
        let clearing = Task { @MainActor in await select(nil) }
        try await waitForPending(2)
        let oldSelectionAccepted = await oldSelection.value
        mux.finish(.applied); mux.finish(.applied)
        let resetAccepted = await clearing.value
        rows.append(["case": "live-reset", "olderOutcome": outcomeLabel(oldSelectionAccepted),
            "outcome": outcomeLabel(resetAccepted), "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil,
            "overrides": service.scenePropertyOverrides(for: record).count, "error": service.downloadError != nil])
        for failure in ["missing-file", "invalid-bookmark"] {
            let lost = root.appendingPathComponent("selected-then-unavailable.png")
            try? FileManager.default.removeItem(at: lost)
            try FileManager.default.copyItem(at: png, to: lost)
            let selection = Task { @MainActor in await select(lost) }
            try await waitForPending(); mux.finish(.applied); _ = await selection.value
            if failure == "missing-file" { try FileManager.default.removeItem(at: lost) }
            else { service.defaults.set(Data([0, 1, 2]), forKey: bookmarkKey) }
            let displayedURL = service.resolvedSceneTexturePropertyURL(forKey: "cover", record: record)
            var referencesEmpty = false
            service.withResolvedSceneTexturePropertyReferences(for: record) { referencesEmpty = $0.isEmpty }
            let retainedBookmark = service.defaults.data(forKey: bookmarkKey); let retainedOverrides = service.scenePropertyOverrides(for: record)
            mux.scalarDispatches = 0
            var completed = false; var resetOutcome: ScenePlaybackTextureUpdateOutcome?
            service.resetScenePropertyValues(for: record, defaultValues: ["cover": .string("")]) {
                completed = true; resetOutcome = $0
            }
            let typedReset = mux.pending.count == 1
                && mux.pending.first?.0.resetKeys == ["cover"]
                && mux.pending.first?.0.references.isEmpty == true
            let waitsForAck = !completed && service.scenePropertyOverrides(for: record)["cover"] != nil
            var failurePreserved = false; var failureOutcome: ScenePlaybackTextureUpdateOutcome?
            if !mux.pending.isEmpty {
                mux.finish(.failed("own-reset-rejected"))
                failureOutcome = resetOutcome
                failurePreserved = completed && service.defaults.data(forKey: bookmarkKey) == retainedBookmark
                    && service.scenePropertyOverrides(for: record) == retainedOverrides
                    && mux.scalarDispatches == 0
                completed = false
                service.resetScenePropertyValues(for: record, defaultValues: ["cover": .string("")]) {
                    completed = true; resetOutcome = $0
                }
                if !mux.pending.isEmpty { mux.finish(.applied) }
            }
            rows.append(["case": failure, "unavailable": displayedURL == nil && referencesEmpty,
                "failurePreserved": failurePreserved, "failureOutcome": outcomeLabel(failureOutcome),
                "outcome": outcomeLabel(resetOutcome), "error": service.downloadError != nil,
                "intentRetained": retainedBookmark != nil, "typedReset": typedReset, "waitsForAck": waitsForAck,
                "scalarDispatches": mux.scalarDispatches, "completed": completed,
                "cleared": service.defaults.data(forKey: bookmarkKey) == nil
                    && service.scenePropertyOverrides(for: record)["cover"] == nil])
        }
        let second = SceneUserPropertyDefinition(
            key: "background", title: "background", kind: .sceneTexture, runtimeType: "scenetexture",
            order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil,
            defaultValue: .string(""), options: [])
        for selected in [definition, second] {
            let task = Task { @MainActor in await select(png, definition: selected) }
            try await waitForPending(); mux.finish(.applied); _ = await task.value
        }
        var scalarOverrides = service.scenePropertyOverrides(for: record)
        scalarOverrides["rate"] = .number(2)
        service.saveScenePropertyOverrides(scalarOverrides, for: record)
        mux.scalarDispatches = 0
        let panelReset = Task { @MainActor in
            await withCheckedContinuation { continuation in
                service.resetScenePropertyValues(for: record,
                    defaultValues: ["cover": .string(""), "background": .string(""), "rate": .number(1)]) {
                    continuation.resume(returning: $0)
                }
            }
        }
        try await waitForPending()
        let firstResetKey = mux.pending.first!.0.keys.first!
        let scalarWaited = mux.scalarDispatches == 0 && mux.pending.count == 1
        // A newer choice supersedes its queued reset while the other key prepares.
        let overrideQueued = Task { @MainActor in await select(jpeg, definition: definition) }
        try await waitForPending(2)
        mux.finish(.applied)
        let panelResetOutcome = await panelReset.value
        let resetDidNotEnqueueOldChoice = mux.pending.count == 1 && mux.pending.first!.0.references["cover"] != nil
        mux.finish(.applied)
        let overrideAccepted = await overrideQueued.value
        rows.append(["case": "panel-reset", "firstKey": firstResetKey,
            "scalarWaited": scalarWaited, "scalarDispatches": mux.scalarDispatches,
            "queuedResetSkipped": resetDidNotEnqueueOldChoice, "newerOutcome": outcomeLabel(overrideAccepted),
            "outcome": outcomeLabel(panelResetOutcome),
            "coverValue": service.scenePropertyOverrides(for: record)["cover"]?.stringValue ?? "none",
            "backgroundBookmark": service.defaults.data(forKey: "SteamWorkshop.scenePropertyBookmarks.own.background") != nil,
            "rateOverride": service.scenePropertyOverrides(for: record)["rate"] != nil])
        let restoreBackground = Task { @MainActor in await select(png, definition: second) }
        try await waitForPending(); mux.finish(.applied); _ = await restoreBackground.value
        let coverBookmark = service.defaults.data(forKey: bookmarkKey)
        let partialReset = Task { @MainActor in
            await withCheckedContinuation { continuation in
                service.resetScenePropertyValues(for: record, defaultValues: ["cover": .string(""), "background": .string("")]) {
                    continuation.resume(returning: $0)
                }
            }
        }
        try await waitForPending(); mux.finish(.applied)
        try await waitForPending(); mux.finish(.failed("own-partial-reset-failure"))
        rows.append(["case": "partial-reset", "outcome": outcomeLabel(await partialReset.value),
            "coverBookmarkUnchanged": service.defaults.data(forKey: bookmarkKey) == coverBookmark,
            "coverValue": service.scenePropertyOverrides(for: record)["cover"]?.stringValue ?? "none",
            "backgroundCleared": service.scenePropertyOverrides(for: record)["background"] == nil,
            "error": service.downloadError != nil])
        func scalarDefinition(_ key: String, kind: SceneUserPropertyKind,
            defaultValue: SceneUserPropertyValue) -> SceneUserPropertyDefinition {
            .init(key: key, title: key, kind: kind, runtimeType: kind.rawValue,
                order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
                allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil,
                defaultValue: defaultValue, options: [])
        }
        let slider = scalarDefinition("rate", kind: .slider, defaultValue: .number(1))
        let tint = scalarDefinition("tint", kind: .color, defaultValue: .string("1 1 1"))
        for editedValue in [3.0, 2.0, 1.0] {
            let selected = Task { @MainActor in await select(png) }
            try await waitForPending(); mux.finish(.applied); _ = await selected.value
            var initial = service.scenePropertyOverrides(for: record)
            initial["rate"] = .number(2); initial["other"] = .number(2)
            initial["tint"] = .string("1 0 0")
            service.saveScenePropertyOverrides(initial, for: record)
            let reset = Task { @MainActor in
                await withCheckedContinuation { continuation in
                    service.resetScenePropertyValues(for: record, defaultValues: [
                        "cover": .string(""), "rate": .number(1), "other": .number(1),
                        "tint": .string("1 1 1")
                    ]) { continuation.resume(returning: $0) }
                }
            }
            try await waitForPending()
            service.updateScenePropertyValue(.number(editedValue), definition: slider, record: record)
            // A one-component color edit still commits its complete property
            // key, through exactly the same public scalar entry as the editor.
            service.updateScenePropertyValue(.string("0.25 0 0"), definition: tint, record: record)
            mux.finish(.applied)
            let scalarResetOutcome = await reset.value
            let saved = service.scenePropertyOverrides(for: record)
            rows.append(["case": "reset-scalar-" + String(Int(editedValue)),
                "rate": saved["rate"]?.numberValue ?? -1, "outcome": outcomeLabel(scalarResetOutcome),
                "tint": saved["tint"]?.stringValue ?? "none",
                "otherOverride": saved["other"] != nil,
                "resetPayloadKeys": mux.lastScalarValues.keys.sorted(),
                "resetOther": mux.lastScalarValues["other"]?.numberValue ?? -1,
                "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self))
    }
}
'''


CONTEXT_LEAF_STUBS = r'''
import Combine

// The asserted path uses real disk parsers, descriptor, base provider compiler
// and the entire SceneProperties service source. These leaves represent only
// GPU resource storage and unrelated product command routing.
enum SceneTextureProviderIdentity: Hashable {
    case mediaThumbnailCurrent, mediaThumbnailPrevious
    case videoUserProperty(property: SceneUserPropertyTextureIdentity,
                           sourceIncarnation: UUID, lifecycleEpoch: UInt64)
}
enum SceneTextureResourceIdentity: Hashable {
    case file, provider(SceneTextureProviderIdentity)
}
struct SceneTextureCandidate {
    let identity: SceneTextureResourceIdentity
    let purpose: SceneTextureLoadPurpose
}
enum SceneFrameTextureIdentity: Hashable {
    case system(SceneSystemProviderTextureIdentity)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
}
struct SteamWorkshopDownloadRecord {
    enum ContentType { case scene, video }
    let id: String
    let contentType: ContentType
}
@MainActor final class SteamWorkshopService {
    let defaults = UserDefaults(suiteName: "mwx-context-" + UUID().uuidString)!
    let objectWillChange = ObservableObjectPublisher()
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyEditRevisions: [String: UInt64] = [:]
    var scenePropertyRenderTask: Task<Void, Never>?
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord, newSelection: Bool = true) {}
    func resetSceneShortcutProperties(for record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void) { completion(.applied) }

    func resetSceneTextureProperties(for record: SteamWorkshopDownloadRecord,
        defaultValues: [String: SceneUserPropertyValue],
        completion: @escaping @MainActor (Set<String>, ScenePlaybackTextureUpdateOutcome) -> Void) {}
}
struct PlaybackCommandMultiplexer {
    static let shared = Self()
    enum Command {
        case setProperty([String: SceneUserPropertyValue], revision: UInt64, recordID: String)
    }
    enum Destination { case scene }
    func dispatch(_ command: Command, to destination: Destination) -> Bool { false }
}
struct SceneDaemonClient {
    static let shared = Self()
    func hasIntent(for recordID: String) -> Bool { false }
    func preparedCallbackPropertyKeys(for recordID: String, source: ScenePreparedCallbackPropertyReachability.Source?) -> Set<String> { [] }
}
@main enum ContextProbe {
    @MainActor static func main() throws {
        let facts = try SceneRuntimeSourceFactsBuilder().build(
            rootURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let service = SteamWorkshopService()
        let context = service.scenePropertyContext(
            for: .init(id: "own-fixture", contentType: .scene), sourceFacts: facts
        )
        let wrongContent = service.scenePropertyContext(
            for: .init(id: "own-fixture", contentType: .video), sourceFacts: facts
        )
        let output: [String: Any] = [
            "parsed": facts.sceneDocument != nil && facts.renderDescriptor != nil,
            "declared": facts.renderDescriptor?.texturePropertyKeys.sorted() ?? [],
            "contextExists": context != nil,
            "actionable": context?.actionableDefinitions.map(\.key).sorted() ?? [],
            "definitions": context?.definitions.map(\.key).sorted() ?? [],
            "wrongContentExists": wrongContent != nil,
            "documentTextureInputs": facts.sceneDocument?.objects.flatMap { object in
                object.effects.flatMap { $0.passes.flatMap(\.userTextureInputs) }
                    + (object.materialInstance?.userTextureInputs ?? [])
            }.compactMap { $0 }.map { "\($0.kind.rawValue):\($0.value)" } ?? [],
            "materialTextureInputs": facts.assetCatalog?.materials.flatMap {
                $0.passes.flatMap(\.userTextureInputs)
            }.compactMap { $0 }.map { "\($0.kind.rawValue):\($0.value)" } ?? [],
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
    }
}
'''


def method_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise AssertionError(f"unterminated method: {signature}")


class ScenePropertyLiveRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.service = SERVICE_SOURCE.read_text(encoding="utf-8")
        cls.texture = TEXTURE_SOURCE.read_text(encoding="utf-8")
        cls.editor = EDITOR_SOURCE.read_text(encoding="utf-8")
        cls.live_consumers = LIVE_CONSUMERS_SOURCE.read_text(encoding="utf-8")
        cls.layer = LAYER_SOURCE.read_text(encoding="utf-8")
        cls.runtime_model = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")

    def test_single_update_persists_before_live_attempt_and_rebuilds_on_rejection(self) -> None:
        update = method_body(self.service, "func updateScenePropertyValue(")
        save = update.index("saveScenePropertyOverrides")
        notify = update.index("objectWillChange.send()")
        live = update.index("PlaybackCommandMultiplexer.shared.dispatch(")
        fallback = update.rindex("scheduleActiveScenePropertyRender")
        self.assertLess(save, notify)
        self.assertLess(notify, live)
        self.assertLess(live, fallback)
        self.assertIn(".setProperty(", update)
        self.assertIn("revision: scenePropertyCommandRevision", update)
        self.assertIn("to: .scene", update)

    def test_live_success_does_not_cancel_an_existing_fallback(self) -> None:
        update = method_body(self.service, "func updateScenePropertyValue(")
        schedule = method_body(self.service, "private func scheduleActiveScenePropertyRender(")
        self.assertNotIn("scenePropertyRenderTask?.cancel()", update)
        self.assertLess(
            schedule.index("guard SceneDaemonClient.shared.hasIntent"),
            schedule.index("scenePropertyRenderTask?.cancel()"),
        )
        self.assertEqual(
            schedule.count("SceneDaemonClient.shared.hasIntent(for: record.id)"),
            2,
        )
        self.assertLess(
            schedule.index("Task.sleep"),
            schedule.rindex("SceneDaemonClient.shared.hasIntent"),
        )


    def test_layer_color_is_live_for_solid_and_effectless_image_layers(self) -> None:
        # Legacy source wiring only: this does not execute Service filtering or
        # RuntimeModel's upstream Script consumer selection. Prepared Host
        # admission has executable coverage in SceneHiddenPropertyConsumerTests.
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .layerColor(layerID):", support)
        layer_color = support[
            support.index("case let .layerColor(layerID):") : support.index(
                "case let .camera(field):"
            )
        ]
        self.assertIn("$0.id == layerID && $0.supportsUserPropertyLayerColorConsumer", layer_color)

        eligibility = method_body(
            self.layer,
            "nonisolated var supportsDirectLayerColorConsumer: Bool",
        )
        self.assertIn('contentKind == "solid"', eligibility)
        self.assertIn('contentKind == "image" && effects.isEmpty', eligibility)
        self.assertNotIn('contentKind == "text"', eligibility)
        self.assertNotIn('contentKind == "particle"', eligibility)

        model = self.runtime_model
        self.assertIn("let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(", model)
        self.assertIn("let hasConsumer = layer.supportsDirectLayerColorConsumer", model)
        self.assertIn('layer.contentKind == "text"', model)
        self.assertIn("layer.supportsDirectLayerColorConsumer", model)
        self.assertIn("visibleLayerIDs.contains(layer.id)", model)
        self.assertIn(
            "admittedLayerColorConsumerIDs: sceneScriptColorConsumerLayerIDs",
            model,
        )

    def test_uniform_layer_scale_is_live_for_the_shared_world_frame(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .layerScale(layerID):", support)
        self.assertIn(
            "renderDescriptor.layers.contains { $0.id == layerID }",
            support,
        )
        consumers = method_body(
            self.live_consumers, "static func activeLiveConsumerTargets("
        )
        self.assertIn(
            "targets.insert(.layer(layerID: layer.id, field: .scale))",
            consumers,
        )
        self.assertNotIn("SceneScriptedLayerTransformProjection.apply", self.runtime_model)

    def test_particle_properties_are_actionable_only_for_particle_layers(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .particle(layerID, _):", support)
        self.assertIn('$0.id == layerID && $0.contentKind == "particle"', support)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn('case "particle":', consumers)
        for field in (
            ".alpha", ".size", ".lifetime", ".rate", ".speed", ".count",
            ".brightness", ".normalizedColor",
        ):
            self.assertIn(field, consumers)
        self.assertIn(".particle(layerID: layer.id, field: $0)", consumers)

    def test_camera_properties_use_the_existing_typed_frame_consumer(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        for field in (
            "cameraparallax",
            "cameraparallaxamount",
            "cameraparallaxdelay",
            "cameraparallaxmouseinfluence",
            "camerashake",
            "camerashakeamplitude",
            "camerashakeroughness",
            "camerashakespeed",
        ):
            self.assertIn(f'"{field}"', support)
        camera_case = support[
            support.index("case let .camera(field):") : support.index(
                "case let .effectVisibility"
            )
        ]
        self.assertIn("let orthoWidth = renderDescriptor.camera.orthoWidth", camera_case)
        self.assertIn("let orthoHeight = renderDescriptor.camera.orthoHeight", camera_case)
        self.assertIn("orthoWidth.isFinite", camera_case)
        self.assertIn("orthoHeight.isFinite", camera_case)
        self.assertIn("orthoWidth > 0", camera_case)
        self.assertIn("orthoHeight > 0", camera_case)
        self.assertIn("return false", camera_case)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn("let cameraTargets = Set(", consumers)
        self.assertIn(".parallaxEnabled", consumers)
        self.assertIn(".parallaxDelay", consumers)
        self.assertIn(".shakeEnabled", consumers)
        self.assertIn(".shakeSpeed", consumers)
        self.assertIn("return hasOrthographicCamera ? instruction.target : nil", consumers)
        self.assertIn(".union(cameraTargets)", consumers)

    def test_puppet_animation_visibility_is_live_only_for_bound_layers(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn(
            "case let .puppetAnimationVisibility(layerID, animationLayerID):",
            support,
        )
        self.assertIn("$0.id == animationLayerID && $0.visibilityBinding != nil", support)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn("where animationLayer.visibilityBinding != nil", consumers)
        self.assertIn("ScenePuppetAnimationPropertyTarget.visibility(", consumers)

    def test_effect_properties_validate_descriptor_identity_without_path_allowlists(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertNotIn("SceneAuthoredEffectExecutionCatalog", context)
        self.assertIn("case let .effectVisibility(layerID, effectIndex, effectPath)", support)
        self.assertIn("let .shaderValue(layerID, effectIndex, _, _, effectPath)", support)
        self.assertIn("Self.hasAuthoredEffect(", support)
        identity = method_body(self.service, "private static func hasAuthoredEffect(")
        self.assertIn("layer.effects.indices.contains(effectIndex)", identity)
        self.assertIn("layer.effects[effectIndex].file", identity)
        self.assertNotIn("supportedNamesByPath", self.service)
        self.assertNotIn("isStrictLocalContrastPath", self.service)

    def test_actionable_properties_come_from_typed_binding_targets(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        self.assertIn(
            "document.userPropertyResolution.bindingReport.bindings", context
        )
        self.assertIn("+ materialBindings", context)
        self.assertNotIn("authoredEffectCatalog", context)
        self.assertNotIn("blendPlan", context)
        self.assertNotIn("SceneImageBlendRenderPlan", self.service)

    def test_resolved_material_property_targets_remain_live_after_owner_transfer(self) -> None:
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn(
            "resolvedMaterialExecutionCapabilities:\n"
            "            SceneResolvedMaterialExecutionCapabilityCatalog",
            consumers,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.liveConsumerTargets",
            consumers,
        )

    def test_generic_string_property_inputs_remain_live_without_scene_relaunch(self) -> None:
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        unavailable = method_body(
            self.live_consumers, "static func unavailableLiveScriptPropertyTargets("
        )
        for source in (consumers, unavailable):
            self.assertIn("sceneScriptStringProgram.livePropertyInputTargets", source)
        self.assertIn(
            "sceneScriptStringProgram.activeLivePropertyInputTargets",
            unavailable,
        )


class SceneTextureSelectionAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-texture-admission-")
        cls.work = Path(cls.temp.name)
        service = SERVICE_SOURCE.read_text()
        properties = "extension SteamWorkshopService {\n" + method_body(
            service, "private enum ScenePropertyOverrideStore {"
        ) + "\n" + "\n".join(method_body(service, signature) for signature in [
            "func scenePropertyOverrides(", "func updateScenePropertyValue(",
            "func resetScenePropertyValues(", "func saveScenePropertyOverrides(",
            "private func scheduleActiveScenePropertyRender(",
        ]) + "\n}\n"
        # Use the exact extension policy, without bringing GPU texture storage
        # into a CPU selection test. Decode uses the entire real uploader source.
        loader = (SCENE_ROOT / "Systems/Properties/SceneUserPropertyTextureLoader.swift").read_text()
        start = loader.index("struct SceneUserPropertyTextureLoader {")
        loader = loader[start:loader.index("    func load(", start)] + "}\n"
        command = (REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift").read_text()
        reference = "\n".join(method_body(command, signature) for signature in [
            "nonisolated struct ScenePlaybackTextureReference:",
            "nonisolated struct ScenePlaybackTextureUpdate:",
            "nonisolated enum ScenePlaybackTextureUpdateOutcome:",
        ])
        runtime = (SCENE_ROOT / "Runtime/IPC/SceneDaemonRuntime.swift").read_text()
        resolve = method_body(runtime, "private static func resolveTextureURLs(")
        resolve = resolve.replace("private static func", "static func", 1)
        harness = cls.work / "Probe.swift"
        harness.write_text("\n".join([
            SELECTION_PROBE, reference, loader, properties,
            "enum DaemonProbe {\n" + resolve + "\n}",
        ]))
        sources = [
            SCENE_ROOT / "Runtime/Session/SceneDesktopWallpaperLaunchModels.swift",
            SCENE_ROOT / "Systems/Properties/SceneUserProperty.swift",
            SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift",
            SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader+Resample.swift",
            SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift",
            SCENE_ROOT / "Resources/Providers/SceneVideoPayloadPreparation.swift",
            SCENE_ROOT / "Resources/Providers/SceneVideoOwnedFile.swift",
            SCENE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
            SCENE_ROOT / "Resources/Assets/SceneResourceView.swift",
            SCENE_ROOT / "Resources/Assets/SceneResourceIdentity.swift",
            SCENE_ROOT / "Resources/Assets/SceneResourceView+Backing.swift",
            SCENE_ROOT / "Format/ScenePkgReader.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
            SCENE_ROOT / "Format/SceneWebMContainer.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift",
            TEXTURE_SOURCE, PLAYBACK_SOURCE, harness,
        ]
        binary = cls.work / "selection"
        delegate_arguments = compile_segment_delegate(cls.work)
        compiled = subprocess.run(
            ["swiftc", "-enable-upcoming-feature", "MemberImportVisibility", *delegate_arguments, *map(str, sources), "-module-cache-path", str(cls.work / "cache"), "-o", str(binary)],
            capture_output=True, text=True,
        )
        if compiled.returncode:
            cls.temp.cleanup()
            raise AssertionError(compiled.stderr)
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
        png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(b"\0\xff\x00\x00\xff")) + chunk(b"IEND", b""))
        (cls.work / "good.png").write_bytes(png)
        (cls.work / "broken.png").write_bytes(b"not a PNG")
        bad_crc = bytearray(png); bad_crc[29] ^= 1
        (cls.work / "crc-broken.png").write_bytes(bad_crc)
        (cls.work / "unsupported.gif").write_bytes(png)
        (cls.work / "directory.png").mkdir()
        run = subprocess.run([str(binary), str(cls.work)], capture_output=True, text=True)
        if run.returncode:
            cls.temp.cleanup()
            raise AssertionError(run.stderr)
        cls.rows = {row["case"]: row for row in json.loads(run.stdout)}

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_invalid_png_preserves_bookmark_bytes_overrides_and_no_reload(self) -> None:
        for name in ["broken.png", "crc-broken.png"]:
            with self.subTest(input=name):
                row = self.rows[name]
                self.assertEqual(row["contentType"], "public.png")
                self.assertEqual(row["outcome"], "failed")
                self.assertTrue(row["bookmarkUnchanged"])
                self.assertTrue(row["overridesUnchanged"])
                self.assertFalse(row["error"])
                self.assertEqual(row["reloads"], 0)
                self.assertEqual(row["path"], "good.png")

    def test_directory_missing_and_unsupported_extension_are_rejected_without_commit(self) -> None:
        for name in ["directory.png", "missing.png", "unsupported.gif"]:
            with self.subTest(input=name):
                row = self.rows[name]
                self.assertEqual(row["outcome"], "failed")
                self.assertFalse(row["error"])
                self.assertTrue(row["bookmarkUnchanged"])
                self.assertTrue(row["overridesUnchanged"])
                self.assertEqual(row["reloads"], 0)
                self.assertEqual(row["path"], "good.png")

    def test_valid_png_jpeg_and_subsequent_recovery_use_actual_load_requests(self) -> None:
        for name in ["good.png", "good.jpeg"]:
            self.assertEqual(self.rows[name]["outcome"], "applied")
            self.assertEqual(self.rows[name]["reloads"], 0)
            self.assertEqual(self.rows[name]["path"], name)
        recovery = self.rows["recovery"]
        self.assertEqual(recovery["outcome"], "applied")
        self.assertTrue(recovery["bookmarkChanged"])
        self.assertEqual(recovery["path"], "good.jpeg")

    def test_nil_and_reset_restore_author_defaults_in_actual_load_requests(self) -> None:
        for name in ["clear", "reset"]:
            row = self.rows[name]
            self.assertEqual(row["outcome"], "applied")
            self.assertFalse(row["bookmarkExists"])
            self.assertEqual(row["overrides"], 0)
            self.assertEqual(row["path"], "none")

    def test_live_failure_does_not_save_before_or_after_ack(self) -> None:
        row = self.rows["live-failure"]
        self.assertTrue(row["beforeAckEmpty"])
        self.assertEqual((row["outcome"], row["reasonPreserved"]), ("failed", True))
        self.assertFalse(row["error"])
        self.assertFalse(row["bookmarkExists"])
        self.assertEqual(row["overrides"], 0)

    def test_live_latest_choice_and_reset_ignore_late_success(self) -> None:
        latest = self.rows["live-latest"]
        self.assertEqual((latest["olderOutcome"], latest["error"]), ("superseded", False))
        self.assertTrue(latest["olderAckDidNotSave"])
        self.assertEqual(latest["newerOutcome"], "applied")
        self.assertTrue(latest["value"].endswith("good.jpeg"))
        reset = self.rows["live-reset"]
        self.assertEqual((reset["olderOutcome"], reset["error"]), ("superseded", False))
        self.assertEqual(reset["outcome"], "applied")
        self.assertFalse(reset["bookmarkExists"])
        self.assertEqual(reset["overrides"], 0)

    def test_unavailable_selected_source_keeps_typed_reset_until_acknowledged(self) -> None:
        for failure in ["missing-file", "invalid-bookmark"]:
            with self.subTest(failure=failure):
                row = self.rows[failure]
                for field in ["unavailable", "intentRetained", "typedReset", "waitsForAck", "failurePreserved", "completed", "cleared"]:
                    self.assertTrue(row[field], field)
                self.assertEqual(row["scalarDispatches"], 0)
                self.assertEqual(row["failureOutcome"], "failed")
                self.assertEqual(row["outcome"], "applied")
                self.assertFalse(row["error"])

    def test_all_reset_is_serial_and_newer_queued_choice_wins(self) -> None:
        row = self.rows["panel-reset"]
        self.assertEqual(row["firstKey"], "background")
        self.assertTrue(row["scalarWaited"])
        self.assertEqual(row["scalarDispatches"], 1)
        self.assertTrue(row["queuedResetSkipped"])
        self.assertEqual(row["newerOutcome"], "applied")
        self.assertEqual(row["outcome"], "superseded")
        self.assertTrue(row["coverValue"].endswith("good.jpeg"))
        self.assertFalse(row["backgroundBookmark"])
        self.assertFalse(row["rateOverride"])
        partial = self.rows["partial-reset"]
        self.assertEqual(partial["outcome"], "failed")
        self.assertTrue(partial["coverBookmarkUnchanged"])
        self.assertTrue(partial["coverValue"].endswith("good.jpeg"))
        self.assertTrue(partial["backgroundCleared"])
        self.assertFalse(partial["error"])

    def test_scalar_and_vector_edits_during_texture_reset_remain_latest(self) -> None:
        for value in [3, 2, 1]:
            with self.subTest(new_slider_value=value):
                row = self.rows[f"reset-scalar-{value}"]
                self.assertEqual(row["rate"], value if value != 1 else -1)
                self.assertEqual(row["tint"], "0.25 0 0")
                self.assertFalse(row["otherOverride"])
                self.assertEqual(row["resetPayloadKeys"], ["other"])
                self.assertEqual(row["resetOther"], 1)
                self.assertFalse(row["bookmarkExists"])


if __name__ == "__main__":
    unittest.main()
