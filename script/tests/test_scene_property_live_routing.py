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
    var scenePropertyRenderTask: Task<Void, Never>?
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    func cleanup() { defaults.removePersistentDomain(forName: suiteName); defaults.synchronize() }
    func libraryVersionLifetime(for record: SteamWorkshopDownloadRecord) throws -> PlaybackResourceLifetime? { nil }
    func clearLaunchPending(matching id: String) {}
}
struct PlaybackCommandMultiplexer {
    static let shared = Self()
    enum Command { case setProperty([String: SceneUserPropertyValue], revision: UInt64, recordID: String) }
    enum Destination { case scene }
    func dispatch(_ command: Command, to destination: Destination) -> Bool { false }
}
struct SceneDaemonClient {
    static let shared = Self()
    func hasIntent(for id: String) -> Bool { true }
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
            let accepted = service.updateSceneTexturePropertyURL(root.appendingPathComponent(name), definition: definition, record: record)
            try await waitForReload()
            rows.append(["case": name, "accepted": accepted, "reloads": spy.requests.count - before, "path": requestPath()])
        }
        for name in ["broken.png", "crc-broken.png", "directory.png", "missing.png", "unsupported.gif"] {
            _ = service.updateSceneTexturePropertyURL(png, definition: definition, record: record)
            try await waitForReload()
            let bookmark = service.defaults.data(forKey: bookmarkKey)
            let overrides = service.scenePropertyOverrides(for: record)
            let before = spy.requests.count
            let url = root.appendingPathComponent(name)
            let accepted = service.updateSceneTexturePropertyURL(url, definition: definition, record: record)
            try await waitForReload()
            let reloads = spy.requests.count - before
            service.requestSceneRender(record)
            rows.append([
                "case": name, "accepted": accepted, "reloads": reloads,
                "bookmarkUnchanged": service.defaults.data(forKey: bookmarkKey) == bookmark,
                "overridesUnchanged": service.scenePropertyOverrides(for: record) == overrides,
                "path": requestPath(), "error": service.downloadError != nil,
                "contentType": (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? "none",
            ])
        }
        let old = service.defaults.data(forKey: bookmarkKey)
        let recovery = service.updateSceneTexturePropertyURL(jpeg, definition: definition, record: record)
        try await waitForReload()
        rows.append(["case": "recovery", "accepted": recovery, "bookmarkChanged": service.defaults.data(forKey: bookmarkKey) != old, "path": requestPath()])
        let cleared = service.updateSceneTexturePropertyURL(nil, definition: definition, record: record)
        try await waitForReload()
        rows.append(["case": "clear", "accepted": cleared, "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil, "overrides": service.scenePropertyOverrides(for: record).count, "path": requestPath()])
        _ = service.updateSceneTexturePropertyURL(png, definition: definition, record: record)
        try await waitForReload()
        service.resetScenePropertyValues(for: record, defaultValues: ["cover": .string("")])
        try await waitForReload()
        rows.append(["case": "reset", "bookmarkExists": service.defaults.data(forKey: bookmarkKey) != nil, "overrides": service.scenePropertyOverrides(for: record).count, "path": requestPath()])
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
final class SteamWorkshopService {
    let defaults = UserDefaults(suiteName: "mwx-context-" + UUID().uuidString)!
    let objectWillChange = ObservableObjectPublisher()
    var scenePropertyCommandRevision: UInt64 = 0
    var scenePropertyRenderTask: Task<Void, Never>?
    func requestSceneRender(_ record: SteamWorkshopDownloadRecord) {}
    func clearSceneTexturePropertyBookmarks(for record: SteamWorkshopDownloadRecord) -> Bool { false }
    static func evaluateWebDisplayCondition(
        _ condition: String, values: [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool { true }
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
}
@main enum ContextProbe {
    static func main() throws {
        let facts = SceneRuntimeSourceFactsBuilder().build(
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

    def test_reset_uses_only_old_override_keys_and_texture_changes_force_rebuild(self) -> None:
        reset = method_body(self.service, "func resetScenePropertyValues(")
        self.assertIn("defaultValues: [String: SceneUserPropertyValue]", reset)
        self.assertLess(
            reset.index("let overrides = scenePropertyOverrides"),
            reset.index("clearSceneTexturePropertyBookmarks"),
        )
        self.assertIn("let changedPropertyKeys = Set(overrides.keys)", reset)
        self.assertIn("if !removedTextureBookmarks,", reset)
        self.assertIn("let changedDefaults = defaultValues.filter", reset)
        self.assertIn("changedPropertyKeys.contains($0.key)", reset)
        self.assertIn(".setProperty(", reset)
        self.assertLess(
            reset.index(".setProperty("),
            reset.index("scheduleActiveScenePropertyRender"),
        )

    def test_texture_bookmark_clear_reports_whether_runtime_resources_changed(self) -> None:
        clear = method_body(self.texture, "func clearSceneTexturePropertyBookmarks(")
        self.assertIn("-> Bool", clear)
        self.assertIn("var removedBookmark = false", clear)
        self.assertIn("removedBookmark = true", clear)
        self.assertIn("return removedBookmark", clear)

    def test_editor_passes_defaults_and_commits_slider_during_drag(self) -> None:
        self.assertIn("defaultValues: context.catalog.defaultValues", self.editor)
        slider = method_body(self.editor, "private func sliderBinding(")
        self.assertIn("set: { commit(.number($0), definition: definition) }", slider)
        row = method_body(self.editor, "private func sliderRow(")
        self.assertNotIn("isEditing", row)
        self.assertNotIn("updateScenePropertyValue", row)

    def test_layer_color_is_live_for_solid_and_effectless_image_layers(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .layerColor(layerID):", support)
        layer_color = support[
            support.index("case let .layerColor(layerID):") : support.index(
                "case let .camera(field):"
            )
        ]
        self.assertIn(
            "$0.id == layerID && $0.supportsDirectLayerColorConsumer",
            layer_color,
        )

        eligibility = method_body(
            self.layer,
            "nonisolated var supportsDirectLayerColorConsumer: Bool",
        )
        self.assertIn('contentKind == "solid"', eligibility)
        self.assertIn('contentKind == "image" && effects.isEmpty', eligibility)
        self.assertNotIn('contentKind == "text"', eligibility)
        self.assertNotIn('contentKind == "particle"', eligibility)

        consumers = method_body(
            self.live_consumers, "static func activeLiveConsumerTargets("
        )
        image_case = consumers[
            consumers.index('case "image":') : consumers.index('case "text":')
        ]
        self.assertIn("if layer.supportsDirectLayerColorConsumer", image_case)
        self.assertIn("visibleLayerIDs.contains(layer.id)", image_case)
        self.assertIn(
            ".layer(layerID: layer.id, field: .color)", image_case
        )

        model = self.runtime_model
        self.assertIn(
            "let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(",
            model,
        )
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


class SceneTexturePropertyContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        from script.tests import test_scene_alpha_display_builder_fixture as builder

        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-texture-context-")
        cls.work = Path(cls.temp.name)
        # Compile the real CPU identity declarations without the candidate's
        # Metal resource storage; do not copy their validation into this test.
        candidate = (SCENE_ROOT / "Resources/Textures/SceneTextureCandidate.swift").read_text()
        identities = candidate.split("/// Identity of raw scene color", 1)[0]
        purpose = (SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift").read_text()
        purpose = method_body(purpose, "nonisolated enum SceneTextureLoadPurpose:")
        purpose_reports = candidate[candidate.index("nonisolated extension SceneTextureLoadPurpose {") :]
        purpose_reports = purpose_reports.split("private nonisolated extension SceneTextureLoadPurpose", 1)[0]
        registry = (SCENE_ROOT / "Resources/Textures/SceneFrameTextureRegistry.swift").read_text()
        system_identity = method_body(registry, "nonisolated struct SceneSystemProviderTextureIdentity:")
        harness = cls.work / "Probe.swift"
        harness.write_text("\n".join([
            builder.HARNESS_SOURCE.split("@main", 1)[0], identities,
            purpose, purpose_reports, system_identity, CONTEXT_LEAF_STUBS,
        ]))
        sources = builder.SWIFT_SOURCES + [
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift",
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialProviderBindingCompiler.swift",
            SCENE_ROOT / "Compilation/Material/SceneBaseMaterialLightingProfile.swift",
            SCENE_ROOT / "Resources/Assets/SceneStockTextureSemanticRegistry.swift",
            REPOSITORY_ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebPropertyModels.swift",
            SERVICE_SOURCE,
        ]
        cls.binary = cls.work / "context"
        compiled = subprocess.run(
            ["swiftc", *map(str, sources), str(harness), "-module-cache-path", str(cls.work / "cache"),
             "-o", str(cls.binary)], capture_output=True, text=True,
        )
        if compiled.returncode:
            cls.temp.cleanup()
            raise AssertionError(compiled.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def probe(self, objects: list[dict], *, material_usertextures=None, definitions=None) -> dict:
        root = Path(tempfile.mkdtemp(dir=self.work, prefix="input-"))
        properties = {
            key: {"type": "scenetexture", "value": "", "order": index}
            for index, key in enumerate(definitions or [
                "effectCover", "instanceCover", "materialCover", "unusedCover",
                "systemCover", "path.png", "unknownCover", "overflowCover",
                "unsupportedBase", "mismatchCover", "shadowedCover",
            ])
        }
        properties["group"] = {"type": "group", "text": "Cover controls", "order": -1}
        properties["help"] = {"type": "text", "text": "Choose an image", "order": 100}
        material = {"shader": "genericimage2", "textures": ["materials/fallback.png"]}
        if material_usertextures is not None:
            material["usertextures"] = material_usertextures
        files = {
            "project.json": {"type": "scene", "file": "scene.json", "general": {"properties": properties}},
            "scene.json": {"version": 3, "objects": objects},
            "models/image.json": {"material": "materials/image.json"},
            "materials/image.json": {"passes": [material]},
            "effects/custom/effect.json": {"passes": [{"material": "materials/effect.json"}]},
            "materials/effect.json": {"passes": [{"shader": "own_effect", "textures": [None, "materials/fallback.png"]}]},
        }
        for path, data in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(data))
        result = subprocess.run([str(self.binary), str(root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["parsed"])
        self.assertFalse(payload["wrongContentExists"])
        return payload

    @staticmethod
    def image(layer_id: int, **fields) -> dict:
        return {"id": layer_id, "image": "models/image.json", "size": "64 64", **fields}

    @staticmethod
    def effect(usertextures, **fields) -> dict:
        return {"file": "effects/custom/effect.json", "passes": [{"usertextures": usertextures, **fields}]}

    def test_effect_and_base_instance_consumers_are_actionable_with_group_context(self) -> None:
        result = self.probe([
            self.image(1, effects=[self.effect([None, "effectCover"])]),
            self.image(2, instance={"textures": ["materials/fallback.png"], "usertextures": ["instanceCover"]}),
        ])
        self.assertEqual(result["actionable"], ["effectCover", "instanceCover"])
        self.assertIn("unusedCover", result["declared"])
        self.assertNotIn("unusedCover", result["actionable"])
        self.assertIn("group", result["definitions"])

    def test_material_consumer_and_instance_precedence_use_real_base_contract(self) -> None:
        material = self.probe([self.image(1)], material_usertextures=["materialCover"])
        self.assertEqual(material["actionable"], ["materialCover"])
        replacement = self.probe([
            self.image(1, instance={"textures": ["materials/fallback.png"], "usertextures": ["instanceCover"]}),
        ], material_usertextures=["shadowedCover"])
        self.assertEqual(replacement["actionable"], ["instanceCover"])
        rejected = self.probe([
            self.image(1, instance={"textures": ["materials/fallback.png", "materials/fallback.png"],
                                  "usertextures": [None, "unsupportedBase"]}),
            self.image(2, instance={"textures": ["materials/other.png"], "usertextures": ["mismatchCover"]}),
        ])
        self.assertFalse(rejected["contextExists"])
        self.assertEqual(rejected["actionable"], [])

    def test_system_path_unknown_undeclared_and_out_of_range_inputs_are_not_controls(self) -> None:
        result = self.probe([
            self.image(1, effects=[self.effect([
                None, {"type": "system", "name": "systemCover"}, "path.png",
                {"name": "unknownCover"}, "notDeclared",
            ])]),
            self.image(2, effects=[self.effect([None] * 8 + ["overflowCover"])]),
        ])
        self.assertFalse(result["contextExists"])
        self.assertEqual(result["actionable"], [])
        # One valid authored candidate in a separate supported slot/pass keeps
        # its control; system providers do not become file properties.
        mixed = self.probe([
            self.image(1, effects=[self.effect(["effectCover", {"type": "system", "name": "systemCover"}])]),
        ])
        self.assertEqual(mixed["actionable"], ["effectCover"])

    def test_unreferenced_texture_definitions_do_not_create_a_context(self) -> None:
        result = self.probe([self.image(1)])
        self.assertTrue(result["declared"])
        self.assertFalse(result["contextExists"])


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
            "func resetScenePropertyValues(", "private func saveScenePropertyOverrides(",
            "private func scheduleActiveScenePropertyRender(",
        ]) + "\n}\n"
        # Use the exact extension policy, without bringing GPU texture storage
        # into a CPU selection test. Decode uses the entire real uploader source.
        loader = (SCENE_ROOT / "Systems/Properties/SceneUserPropertyTextureLoader.swift").read_text()
        start = loader.index("struct SceneUserPropertyTextureLoader {")
        loader = loader[start:loader.index("    func load(", start)] + "}\n"
        command = (REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift").read_text()
        reference = method_body(command, "nonisolated struct ScenePlaybackTextureReference:")
        runtime = (SCENE_ROOT / "Runtime/IPC/SceneDaemonRuntime.swift").read_text()
        resolve = method_body(runtime, "private static func resolveTextureURLs(")
        resolve = resolve.replace("private static func", "static func", 1)
        harness = cls.work / "Probe.swift"
        harness.write_text("\n".join([
            SELECTION_PROBE, reference, loader, properties,
            "enum DaemonProbe {\n" + resolve + "\n}",
        ]))
        sources = [
            SCENE_ROOT / "Systems/Properties/SceneUserProperty.swift",
            SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift",
            SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader+Resample.swift",
            SCENE_ROOT / "Resources/Textures/SceneResourceBudget.swift",
            TEXTURE_SOURCE, PLAYBACK_SOURCE, harness,
        ]
        binary = cls.work / "selection"
        compiled = subprocess.run(
            ["swiftc", *map(str, sources), "-module-cache-path", str(cls.work / "cache"), "-o", str(binary)],
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
                self.assertFalse(row["accepted"])
                self.assertTrue(row["bookmarkUnchanged"])
                self.assertTrue(row["overridesUnchanged"])
                self.assertTrue(row["error"])
                self.assertEqual(row["reloads"], 0)
                self.assertEqual(row["path"], "good.png")

    def test_directory_missing_and_unsupported_extension_are_rejected_without_commit(self) -> None:
        for name in ["directory.png", "missing.png", "unsupported.gif"]:
            with self.subTest(input=name):
                row = self.rows[name]
                self.assertFalse(row["accepted"])
                self.assertTrue(row["bookmarkUnchanged"])
                self.assertTrue(row["overridesUnchanged"])
                self.assertEqual(row["reloads"], 0)
                self.assertEqual(row["path"], "good.png")

    def test_valid_png_jpeg_and_subsequent_recovery_use_actual_load_requests(self) -> None:
        for name in ["good.png", "good.jpeg"]:
            self.assertTrue(self.rows[name]["accepted"])
            self.assertEqual(self.rows[name]["reloads"], 1)
            self.assertEqual(self.rows[name]["path"], name)
        recovery = self.rows["recovery"]
        self.assertTrue(recovery["accepted"])
        self.assertTrue(recovery["bookmarkChanged"])
        self.assertEqual(recovery["path"], "good.jpeg")

    def test_nil_and_reset_restore_author_defaults_in_actual_load_requests(self) -> None:
        self.assertTrue(self.rows["clear"]["accepted"])
        for name in ["clear", "reset"]:
            row = self.rows[name]
            self.assertFalse(row["bookmarkExists"])
            self.assertEqual(row["overrides"], 0)
            self.assertEqual(row["path"], "none")


if __name__ == "__main__":
    unittest.main()
