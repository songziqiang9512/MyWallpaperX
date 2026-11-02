#!/usr/bin/env python3

from __future__ import annotations

import json
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from .test_scene_prepared_script_resource_catalog import swift_declaration


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextGenerationState.swift"
STORE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextTextureStore.swift"
)
VIEW_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let authored = SceneDynamicTextSignature(
            content: "A", fontPath: nil,
            pointSize: 8, colorRGB: [1, 1, 1], maxWidth: 100
        )
        let second = SceneDynamicTextSignature(
            content: "B", fontPath: "fonts/second.ttf",
            pointSize: 9, colorRGB: [1, 0, 0], maxWidth: 200
        )
        let latest = SceneDynamicTextSignature(
            content: "C", fontPath: "fonts/latest.ttf",
            pointSize: 10, colorRGB: [0, 1, 0], maxWidth: 300
        )
        var state = SceneDynamicTextGenerationState()
        state.registerInitial(layerID: 1, signature: authored, isReady: true)
        let initialReadyGeneration = state.readyGeneration(layerID: 1)
        let duplicate = state.request(layerID: 1, signature: authored)
        let generationB = state.request(layerID: 1, signature: second)!
        let generationC = state.request(layerID: 1, signature: latest)!
        let staleAccepted = state.complete(layerID: 1, generation: generationB, succeeded: true)
        let failureAccepted = state.complete(layerID: 1, generation: generationC, succeeded: false)
        let readyAfterFailure = state.readySignature(layerID: 1)!
        let generationAfterFailure = state.readyGeneration(layerID: 1)
        let latestAccepted = state.complete(layerID: 1, generation: generationC, succeeded: true)
        let readyAfterSuccess = state.readySignature(layerID: 1)!
        let generationAfterSuccess = state.readyGeneration(layerID: 1)

        var scheduledState = SceneDynamicTextGenerationState()
        scheduledState.registerInitial(layerID: 2, signature: authored, isReady: true)
        let scheduledSecond = scheduledState.schedule(layerID: 2, signature: second)!
        let queuedLatest = scheduledState.schedule(layerID: 2, signature: latest)
        let runningWhileLatestQueued = scheduledState.isRendering(scheduledSecond)
        let staleCompletion = scheduledState.finish(scheduledSecond, succeeded: true)
        let latestCompletion = scheduledState.finish(staleCompletion.next!, succeeded: true)
        let oldStillRendering = scheduledState.isRendering(scheduledSecond)
        var retiredState = SceneDynamicTextGenerationState()
        let retired = retiredState.registerDynamic(layerID: 7, signature: authored)!
        retiredState.unregister(layerID: 7)
        let replacement = retiredState.registerDynamic(layerID: 7, signature: second)!
        let retiredMembership = retiredState.isRendering(retired)
        let replacementMembership = retiredState.isRendering(replacement)
        let retiredAccepted = retiredState.finish(retired, succeeded: true).accepted
        let replacementAccepted = retiredState.finish(replacement, succeeded: true).accepted
        let replacementReady = retiredState.readySignature(layerID: 7)?.content
        let beforeReset = retiredState.registerDynamic(layerID: 8, signature: authored)!
        retiredState.reset()
        let afterReset = retiredState.registerDynamic(layerID: 8, signature: latest)!
        let resetStaleAccepted = retiredState.finish(beforeReset, succeeded: true).accepted
        let resetNewAccepted = retiredState.finish(afterReset, succeeded: true).accepted
        state.reset()
        let payload: [String: Any] = [
            "retiredTokenReused": retired.generation == replacement.generation,
            "retiredMembership": retiredMembership,
            "replacementMembership": replacementMembership,
            "retiredAccepted": retiredAccepted,
            "replacementAccepted": replacementAccepted,
            "replacementReady": replacementReady as Any,
            "resetTokenReused": beforeReset.generation == afterReset.generation,
            "resetStaleAccepted": resetStaleAccepted,
            "resetNewAccepted": resetNewAccepted,
            "oldMembershipAfterCompletion": oldStillRendering,
            "duplicate": duplicate as Any,
            "initialReadyGeneration": initialReadyGeneration as Any,
            "ordered": generationC > generationB,
            "staleAccepted": staleAccepted,
            "failureAccepted": failureAccepted,
            "readyAfterFailure": readyAfterFailure.content,
            "generationAfterFailure": generationAfterFailure as Any,
            "latestAccepted": latestAccepted,
            "readyAfterSuccess": readyAfterSuccess.content,
            "generationAfterSuccess": generationAfterSuccess as Any,
            "queuedLatestStartedImmediately": queuedLatest != nil,
            "runningWhileLatestQueued": runningWhileLatestQueued,
            "scheduledStaleAccepted": staleCompletion.accepted,
            "scheduledNextContent": staleCompletion.next?.signature.content as Any,
            "scheduledLatestAccepted": latestCompletion.accepted,
            "scheduledHasThirdTask": latestCompletion.next != nil,
            "scheduledReadyWidth": scheduledState.readySignature(layerID: 2)?.maxWidth as Any,
            "readyAfterReset": state.readySignature(layerID: 1) as Any,
            "generationAfterReset": state.readyGeneration(layerID: 1) as Any,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

# Execute the real Store, scheduler, and View commit/discard methods. The View
# carrier supplies only its two slots; publication admission and GPU composition
# remain outside this controlled raster-worker probe.
STORE_HARNESS = r'''
import Foundation
import Metal

enum SceneTextDescriptor {
    static func renderedPointSize(_ value: Double) -> Float? {
        guard value.isFinite else { return nil }
        return Float(max(1, min(value, 1_024)))
    }
}
enum SceneDynamicTextField: Hashable { case content, font, pointSize, color, maxWidth }
enum SceneDynamicValue { case string(String), scalar(Double), vector3(Double,Double,Double) }
enum SceneDynamicTarget: Hashable { case text(layerID: Int,field: SceneDynamicTextField) }
struct SceneDynamicSnapshot {
    struct Entry { let value: SceneDynamicValue }
    let values: [SceneDynamicTarget: Entry]
    subscript(_ key: SceneDynamicTarget) -> Entry? { values[key] }
}
struct SceneRenderDescriptor {
    struct TextStyle {
        let fontPath: String? = nil
        let pointSize: Float = 8
        let colorRGB: [Float] = [1,1,1]
        let maxWidth: Float = 100
        let limitWidth = true
    }
    struct Layer {
        let id: Int
        let contentKind = "text"
        let text: String? = "A"
        let textStyle: TextStyle? = .init()
    }
    let layers: [Layer]
}
enum SceneFrameTextureIdentity { case layerSource(Int) }
enum SceneTextureResourceIdentity { enum Provider { case dynamicText(layerID: Int) }; case provider(Provider) }
enum SceneTextureResourceGeneration { case provider(contentGeneration: UInt64) }
enum SceneTextureLoadPurpose { case premultipliedColor }
enum SceneTextureContent {
    enum Color { case resolved(Representation) }
    enum Representation { case premultipliedAlpha }
    case color(Color)
}
struct SceneTextureUVTransform { static let identity = Self() }
struct SceneTextureSampling { static let linearClamp = Self() }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let identity: SceneTextureResourceIdentity
    let generation: SceneTextureResourceGeneration
    let purpose: SceneTextureLoadPurpose
    let content: SceneTextureContent
    let physicalSize: CGSize
    let mappedSize: CGSize
    let uvTransform: SceneTextureUVTransform
    let sampling: SceneTextureSampling
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
}
struct SceneLayerSourcePublication {
    let layerID: Int
    let publication: SceneTextureProviderPublication
    let renderSizeWH: [Float]
    let textCenterOffsetY: Float
    var texture: MTLTexture { publication.candidate.texture }
    init?(layerID: Int,publication: SceneTextureProviderPublication,
          renderSizeWH: [Float],textCenterOffsetY: Float) {
        self.layerID = layerID; self.publication = publication
        self.renderSizeWH = renderSizeWH; self.textCenterOffsetY = textCenterOffsetY
    }
}
final class ControlledRasterProducer: @unchecked Sendable {
    let startedB = DispatchSemaphore(value: 0), startedC = DispatchSemaphore(value: 0)
    let startedD = DispatchSemaphore(value: 0), allowB = DispatchSemaphore(value: 0)
    let allowC = DispatchSemaphore(value: 0), allowD = DispatchSemaphore(value: 0)
    let published = DispatchSemaphore(value: 0)
    let rasterB: SceneTextTextureLoader.RasterizedTexture
    let rasterD: SceneTextTextureLoader.RasterizedTexture
    private let lock = NSLock()
    private var calls: [String] = []
    private var fontInputs: [String] = []
    init(_ b: SceneTextTextureLoader.RasterizedTexture,_ d: SceneTextTextureLoader.RasterizedTexture) {
        rasterB = b; rasterD = d
    }
    func render(_ content: String, preparedFont: String?) throws -> SceneTextTextureLoader.RasterizedTexture? {
        lock.lock(); calls.append(content); fontInputs.append(preparedFont ?? "none")
        let callCount = calls.count
        lock.unlock()
        if CommandLine.arguments.contains("--retired-font") {
            if callCount == 1 { startedB.signal(); wait(allowB); return rasterB }
            startedD.signal(); wait(allowD); return rasterD
        }
        switch content {
        case "B": startedB.signal(); wait(allowB); return rasterB
        case "C":
            startedC.signal(); wait(allowC)
            if CommandLine.arguments.contains("--hard-source") { throw SceneResourceView.ReadError.sourceChanged }
            if CommandLine.arguments.contains("--cancel-source") { throw CancellationError() }
            return nil
        case "D": startedD.signal(); wait(allowD); return rasterD
        default: preconditionFailure("unexpected raster request: \(content)")
        }
    }
    func renderedContents() -> [String] { lock.lock(); defer { lock.unlock() }; return calls }
    func renderedFonts() -> [String] { lock.lock(); defer { lock.unlock() }; return fontInputs }
    func wait(_ semaphore: DispatchSemaphore) {
        precondition(semaphore.wait(timeout: .now()+5) == .success,"producer deadline")
    }
}
enum SceneTextTextureLoader {
    struct RasterizedTexture { let texture: MTLTexture; let renderSizeWH: [Float]; let centerOffsetY: Float; var sourceFont: String? = nil }
    static var producer: ControlledRasterProducer!
    static func makeDynamicTexture(for layer: SceneRenderDescriptor.Layer,content: String,
        fontPath: String?,pointSize: Float,colorRGB: [Float],maxWidth: Float,
        resourceView: SceneResourceView?,preparedFont: String? = nil,device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil) throws -> RasterizedTexture? {
        try checkCancellation?()
        let raster = try producer.render(content, preparedFont: preparedFont)
        try checkCancellation?()
        return raster
    }
}
final class SceneMetalView {
    var preparedTextSnapshot: SceneDynamicTextTextureStore.Snapshot?
    private(set) var submittedTextSnapshot: SceneDynamicTextTextureStore.Snapshot?
__VIEW_SUBMISSION_METHODS__
}
@main enum StoreProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}"); return
        }
        func raster(_ name: String,_ width: Int,_ height: Int,_ size: [Float],_ offset: Float)
            -> SceneTextTextureLoader.RasterizedTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: width,height: height,mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .shaderRead
            let texture = device.makeTexture(descriptor: descriptor)!
            texture.label = name
            return .init(texture: texture,renderSizeWH: size,centerOffsetY: offset,sourceFont: name)
        }
        let a = raster("g1",2,3,[120,30],3), b = raster("g2",4,5,[240,50],-11)
        let d = raster("g4",6,7,[360,70],19)
        let producer = ControlledRasterProducer(b,d)
        SceneTextTextureLoader.producer = producer
        if CommandLine.arguments.contains("--retired-font") {
            let store = SceneDynamicTextTextureStore(descriptor: .init(layers: []),
                resourceView: nil, device: device, initialRasters: [:],
                onPublication: { _ in producer.published.signal() })
            let snapshot = SceneDynamicSnapshot(values: [:])
            store.update(from: snapshot, dynamicLayers: [.init(id: 8)])
            producer.wait(producer.startedB)
            store.update(from: snapshot, dynamicLayers: [])
            store.update(from: snapshot, dynamicLayers: [.init(id: 8)])
            producer.allowB.signal(); producer.wait(producer.startedD)
            let oldPublicationRejected = store.snapshot().layerSources.isEmpty
            producer.allowD.signal(); producer.wait(producer.published)
            let result: [String: Any] = ["oldPublicationRejected": oldPublicationRejected,
                "newLayerDidNotBorrowRetiredFont": producer.renderedFonts() == ["none", "none"],
                "replacementPublished": store.snapshot().layerSources[8]?.texture.label == "g4"]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
            return
        }
        let store = SceneDynamicTextTextureStore(descriptor: .init(layers: [.init(id: 7)]),
            resourceView: nil,device: device,
            initialRasters: [7:a],dynamicTextFieldsByLayerID: [7:[.content]],
            onPublication: { _ in producer.published.signal() })
        func update(_ content: String) {
            store.update(from: .init(values: [.text(layerID: 7,field: .content): .init(value: .string(content))]),
                dynamicTextFieldsByLayerID: [7:[.content]])
        }
        func atom(_ snapshot: SceneDynamicTextTextureStore.Snapshot?) -> [String: Any] {
            guard let source = snapshot?.layerSources[7] else { return [:] }
            let candidate = source.publication.candidate
            let generation: UInt64
            switch candidate.generation { case .provider(let value): generation = value }
            let requestLayer: Int
            switch source.publication.requestIdentity { case .layerSource(let value): requestLayer = value }
            let providerLayer: Int
            switch candidate.identity { case .provider(.dynamicText(let value)): providerLayer = value }
            return ["texture": source.texture.label!,
                "textureSize": [source.texture.width,source.texture.height],
                "physicalSize": [candidate.physicalSize.width,candidate.physicalSize.height],
                "mappedSize": [candidate.mappedSize.width,candidate.mappedSize.height],
                "renderSize": source.renderSizeWH,"offset": source.textCenterOffsetY,
                "generation": generation,"publicationGeneration": source.publication.contentGeneration,
                "sourceLayer": source.layerID,"requestLayer": requestLayer,"providerLayer": providerLayer]
        }
        let surfaceA = SceneMetalView(), surfaceB = SceneMetalView()
        let initial = store.snapshot()
        var result: [String: Any] = ["initialReady": atom(initial),
            "initialSubmittedA": atom(surfaceA.submittedTextSnapshot),
            "initialSubmittedB": atom(surfaceB.submittedTextSnapshot)]
        surfaceA.preparedTextSnapshot = initial; surfaceB.preparedTextSnapshot = initial
        surfaceA.commitPreparedDynamicTextFrame(); surfaceB.commitPreparedDynamicTextFrame()
        result["initialCommittedA"] = atom(surfaceA.submittedTextSnapshot)
        result["initialCommittedB"] = atom(surfaceB.submittedTextSnapshot)

        // Capture one attempt before raster publication. Both surfaces receive
        // that value even if the second one prepares after the worker completes.
        let frozenAttempt = store.snapshot()
        surfaceA.preparedTextSnapshot = frozenAttempt
        update("B"); producer.wait(producer.startedB)
        producer.allowB.signal(); producer.wait(producer.published)
        surfaceB.preparedTextSnapshot = frozenAttempt
        result["readyWhileAttemptFrozen"] = atom(store.snapshot())
        result["frozenAttempt"] = atom(frozenAttempt)
        result["preparedAWhileBReady"] = atom(surfaceA.preparedTextSnapshot)
        result["preparedBWhileBReady"] = atom(surfaceB.preparedTextSnapshot)
        result["submittedAWhileBReady"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBWhileBReady"] = atom(surfaceB.submittedTextSnapshot)
        surfaceA.commitPreparedDynamicTextFrame(); surfaceB.discardPreparedDynamicTextFrame()
        result["submittedAAfterFrozenCommit"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterFrozenDiscard"] = atom(surfaceB.submittedTextSnapshot)

        let nextAttempt = store.snapshot()
        surfaceA.preparedTextSnapshot = nextAttempt; surfaceB.preparedTextSnapshot = nextAttempt
        surfaceA.commitPreparedDynamicTextFrame(); surfaceB.discardPreparedDynamicTextFrame()
        result["submittedAAfterNextCommit"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterNextDiscard"] = atom(surfaceB.submittedTextSnapshot)
        result["preparedSlotsCleared"] = surfaceA.preparedTextSnapshot == nil
            && surfaceB.preparedTextSnapshot == nil
        surfaceA.commitPreparedDynamicTextFrame()
        result["commitWithoutPrepared"] = atom(surfaceA.submittedTextSnapshot)
        surfaceB.preparedTextSnapshot = nextAttempt; surfaceB.commitPreparedDynamicTextFrame()
        result["submittedAAfterPeerRetry"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterRetry"] = atom(surfaceB.submittedTextSnapshot)
        update("C"); producer.wait(producer.startedC)
        update("D"); producer.allowC.signal()
        // D can enter only after the real serial Store finished failed C.
        // Keep D blocked while checking the complete previous raster atom.
        producer.wait(producer.startedD)
        result["readyAfterFailure"] = atom(store.snapshot())
        result["submittedAAfterFailure"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterFailure"] = atom(surfaceB.submittedTextSnapshot)
        producer.allowD.signal(); producer.wait(producer.published)
        let recovered = store.snapshot()
        result["readyAfterRecovery"] = atom(recovered)
        result["submittedAAfterRecovery"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterRecovery"] = atom(surfaceB.submittedTextSnapshot)
        surfaceA.preparedTextSnapshot = recovered; surfaceB.preparedTextSnapshot = recovered
        surfaceA.commitPreparedDynamicTextFrame(); surfaceB.discardPreparedDynamicTextFrame()
        result["submittedAAfterRecoveryCommit"] = atom(surfaceA.submittedTextSnapshot)
        result["submittedBAfterRecoveryDiscard"] = atom(surfaceB.submittedTextSnapshot)
        result["originalCapturedSnapshot"] = atom(frozenAttempt)
        result["renderCalls"] = producer.renderedContents()
        result["fontInputs"] = producer.renderedFonts()
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,options: [.sortedKeys]),as: UTF8.self))
    }
}
'''


def store_harness() -> str:
    source = VIEW_SOURCE.read_text(encoding="utf-8")
    methods = "\n".join(swift_declaration(source, signature) for signature in (
        "    func commitPreparedDynamicTextFrame()",
        "    func discardPreparedDynamicTextFrame()",
    ))
    return STORE_HARNESS.replace("__VIEW_SUBMISSION_METHODS__", methods)


# Reuse only the DTOs above; this probe never allocates a texture or submits GPU work.
STORE_DRAIN_HARNESS = STORE_HARNESS.split("final class ControlledRasterProducer", 1)[0] + r"""
enum SceneResourceView { final class Root {} }
final class ControlledFontWork: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var events: [String] = []
    func note(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    func capturedEvents() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
    func render(_ content: String) throws {
        note("render:" + content); started.signal()
        precondition(release.wait(timeout: .now()+5) == .success)
        defer { note("raster-leaf-returned") }
        if CommandLine.arguments.contains("--hard-source") { throw ReadFailure.sourceChanged }
        if CommandLine.arguments.contains("--cancel-source") { throw CancellationError() }
    }
    enum ReadFailure: Error { case sourceChanged }
}
enum SceneTextTextureLoader {
    struct RasterizedTexture { let texture: MTLTexture; let renderSizeWH: [Float]; let centerOffsetY: Float; var sourceFont: String? = nil }
    static let work = ControlledFontWork()
    static func makeDynamicTexture(for layer: SceneRenderDescriptor.Layer, content: String,
        fontPath: String?, pointSize: Float, colorRGB: [Float], maxWidth: Float,
        resourceView: SceneResourceView?, preparedFont: String? = nil, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil) throws -> RasterizedTexture? {
        try checkCancellation?()
        try work.render(content)
        try checkCancellation?()
        return nil
    }
}
@main enum FontDrainProbe {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let work = SceneTextTextureLoader.work
        let store = SceneDynamicTextTextureStore(descriptor: .init(layers: [.init(id: 7)]),
            resourceView: nil, device: device, initialRasters: [:],
            dynamicTextFieldsByLayerID: [7:[.content]],
            onPublication: { _ in work.note("publication") })
        func update(_ content: String) {
            store.update(from: .init(values: [.text(layerID:7,field:.content):.init(value:.string(content))]),
                dynamicTextFieldsByLayerID: [7:[.content]])
        }
        update("B")
        precondition(work.started.wait(timeout:.now()+5) == .success)
        update("C")
        let drained = DispatchSemaphore(value:0)
        for _ in 0..<2 { store.closeAndDrain {work.note("drain");drained.signal()} }
        update("D")
        store.update(from:.init(values:[:]),dynamicLayers:[.init(id:8)])
        var output = ["drainPendingWhileActualWorkerHeld":drained.wait(timeout:.now()) == .timedOut]
        work.release.signal()
        precondition(drained.wait(timeout:.now()+5) == .success)
        precondition(drained.wait(timeout:.now()+5) == .success)
        let events = work.capturedEvents()
        output["closedStoreDoesNotScheduleLatestOrNewLayer"] = events.filter {$0.hasPrefix("render:")} == ["render:B"]
        output["closedWorkerDoesNotPublish"] = !events.contains("publication")
        output["bothTailsFollowWorkerReturn"] = events == ["render:B","raster-leaf-returned","drain","drain"]
        store.closeAndDrain {drained.signal()}
        output["repeatedCompletedDrainStillCompletes"] = drained.wait(timeout:.now()+5) == .success
        let empty = SceneDynamicTextTextureStore(descriptor:.init(layers:[]),resourceView:nil,
            device:device,initialRasters:[:])
        empty.closeAndDrain {drained.signal()}
        output["emptyStoreDrains"] = drained.wait(timeout:.now()+5) == .success
        print(String(data:try! JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
"""

class SceneDynamicTextGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-text-generation-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "text-generation"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_same_value_is_deduplicated_and_generations_are_monotonic(self) -> None:
        self.assertIsNone(self.result["duplicate"])
        self.assertTrue(self.result["ordered"])

    def test_shared_ready_and_two_surface_submissions_remain_independent(self) -> None:
        parent = os.environ.get("MWX_DYNAMIC_TEXT_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix="mwx-text-store-", dir=parent))
        try:
            harness = directory / "StoreHarness.swift"
            harness.write_text(store_harness(), encoding="utf-8")
            binary = directory / "text-store"
            resource_sources = [REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene" / path for path in
                                ("Resources/Assets/SceneResourceIndex.swift", "Resources/Assets/SceneResourceView.swift",
                                 "../SteamWorkshopStorage/ScenePlaybackSource.swift", "Format/ScenePkgReader.swift",
                                 "Resources/Assets/SceneResourceIdentity.swift", "Resources/Assets/SceneResourceView+Backing.swift")]
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (SOURCE, STORE_SOURCE, VIEW_SOURCE, *resource_sources, Path(__file__), harness)}
            (directory / "source-identity.json").write_text(json.dumps(identity, indent=2))
            compiled = subprocess.run(
                ["swiftc", str(SOURCE), str(STORE_SOURCE),
                 *map(str, resource_sources),
                 str(harness), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            (directory / "compile.log").write_text(compiled.stdout + compiled.stderr)
            self.assertEqual(compiled.returncode, 0, f"{directory}\n{compiled.stderr}")
            completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            (directory / "run.log").write_text(completed.stdout + completed.stderr)
            self.assertEqual(completed.returncode, 0, f"{directory}\n{completed.stderr}")
            self.assertEqual(identity, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
                                        for path in identity})
            result = json.loads(completed.stdout)
            (directory / "result.json").write_text(json.dumps(result, indent=2))
            if result.get("metalUnavailable"):
                self.skipTest("Metal is unavailable")
            g1 = result["initialReady"]
            g2 = result["readyWhileAttemptFrozen"]
            g4 = result["readyAfterRecovery"]
            for key in ("initialSubmittedA", "initialSubmittedB"):
                self.assertEqual(result[key], {}, key)
            for key in ("initialCommittedA", "initialCommittedB", "frozenAttempt",
                        "preparedAWhileBReady", "preparedBWhileBReady",
                        "submittedAWhileBReady", "submittedBWhileBReady",
                        "submittedAAfterFrozenCommit", "submittedBAfterFrozenDiscard",
                        "submittedBAfterNextDiscard", "originalCapturedSnapshot"):
                self.assertEqual(result[key], g1, key)
            for key in ("submittedAAfterNextCommit", "commitWithoutPrepared",
                        "submittedAAfterPeerRetry", "submittedBAfterRetry",
                        "readyAfterFailure", "submittedAAfterFailure", "submittedBAfterFailure",
                        "submittedAAfterRecovery", "submittedBAfterRecovery",
                        "submittedBAfterRecoveryDiscard"):
                self.assertEqual(result[key], g2, key)
            self.assertTrue(result["preparedSlotsCleared"])
            self.assertEqual(result["submittedAAfterRecoveryCommit"], g4)
            self.assertEqual(g1["texture"], "g1")
            self.assertEqual(g1["textureSize"], [2, 3])
            self.assertEqual(g1["renderSize"], [120, 30])
            self.assertEqual(g1["offset"], 3)
            self.assertEqual(g1["generation"], 0)
            self.assertEqual(g2["texture"], "g2")
            self.assertEqual(g2["textureSize"], [4, 5])
            self.assertEqual(g2["renderSize"], [240, 50])
            self.assertEqual(g2["offset"], -11)
            self.assertGreater(g2["generation"], g1["generation"])
            self.assertGreater(g4["generation"], g2["generation"])
            for atom in (g1, g2, g4):
                self.assertEqual(atom["generation"], atom["publicationGeneration"])
                self.assertEqual(atom["physicalSize"], atom["textureSize"])
                self.assertEqual(atom["mappedSize"], atom["textureSize"])
                for field in ("sourceLayer", "requestLayer", "providerLayer"):
                    self.assertEqual(atom[field], 7, field)
            self.assertEqual(g4["texture"], "g4")
            self.assertEqual(g4["textureSize"], [6, 7])
            self.assertEqual(g4["renderSize"], [360, 70])
            self.assertEqual(g4["offset"], 19)
            self.assertEqual(result["renderCalls"], ["B", "C", "D"])
            self.assertEqual(result["fontInputs"], ["g1", "g2", "g2"])
            # The same real Store transaction must preserve the complete old
            # atom for a hard read error and an original cancellation, too.
            for flag in ("--hard-source", "--cancel-source"):
                rejected = subprocess.run([str(binary), flag], capture_output=True, text=True, timeout=30)
                (directory / (flag[2:] + ".log")).write_text(rejected.stdout + rejected.stderr)
                self.assertEqual(rejected.returncode, 0, rejected.stderr)
                self.assertEqual(json.loads(rejected.stdout), result)
            retired = subprocess.run([str(binary), "--retired-font"],
                                     capture_output=True, text=True, timeout=30)
            self.assertEqual(retired.returncode, 0, retired.stderr)
            for field, passed in json.loads(retired.stdout).items():
                self.assertTrue(passed, field)
        finally:
            if not parent:
                shutil.rmtree(directory)

    def test_close_and_drain_joins_actual_worker_and_rejects_late_admission(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-text-cpu-drain-") as raw:
            directory = Path(raw)
            harness = directory / "Drain.swift"
            harness.write_text(STORE_DRAIN_HARNESS)
            binary = directory / "drain"
            sources = (SOURCE, STORE_SOURCE, harness)
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
            compiled = subprocess.run(["swiftc", *map(str, sources), "-o", str(binary)],
                                      capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            for flag in (None, "--hard-source", "--cancel-source"):
                with self.subTest(failure=flag):
                    result = subprocess.run([str(binary), *([flag] if flag else [])],
                                            capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    output = json.loads(result.stdout)
                    if output.get("metalUnavailable"):
                        self.skipTest("Metal device unavailable; no GPU commands submitted by this probe")
                    for name, passed in output.items():
                        self.assertTrue(passed, name)
            self.assertEqual(identity, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
                                        for path in identity})

    def test_retirement_and_reset_never_reuse_an_inflight_request_token(self) -> None:
        for field in ("retiredTokenReused", "retiredMembership", "retiredAccepted",
                      "resetTokenReused", "resetStaleAccepted", "oldMembershipAfterCompletion"):
            self.assertFalse(self.result[field], field)
        for field in ("replacementMembership", "replacementAccepted", "resetNewAccepted", "runningWhileLatestQueued"):
            self.assertTrue(self.result[field], field)
        self.assertEqual(self.result["replacementReady"], "B")

    def test_stale_or_failed_results_never_replace_the_last_ready_value(self) -> None:
        self.assertFalse(self.result["staleAccepted"])
        self.assertFalse(self.result["failureAccepted"])
        self.assertEqual(self.result["readyAfterFailure"], "A")
        self.assertEqual(
            self.result["generationAfterFailure"],
            self.result["initialReadyGeneration"],
        )
        self.assertTrue(self.result["latestAccepted"])
        self.assertEqual(self.result["readyAfterSuccess"], "C")
        self.assertGreater(
            self.result["generationAfterSuccess"],
            self.result["generationAfterFailure"],
        )
        self.assertIsNone(self.result["readyAfterReset"])
        self.assertIsNone(self.result["generationAfterReset"])

    def test_typed_font_default_is_distinct_from_a_missing_override(self) -> None:
        source = STORE_SOURCE.read_text(encoding="utf-8")
        methods = "\n".join(swift_declaration(source, signature).replace("private ", "") for signature in (
            "    private static func signature(", "    private static func stringValue(",
            "    private static func scalarValue(", "    private static func colorValue(",
        ))
        preamble = STORE_HARNESS.split("enum SceneFrameTextureIdentity", 1)[0]
        preamble = preamble.replace("let fontPath: String? = nil", "var fontPath: String? = nil")
        preamble = preamble.replace("let textStyle: TextStyle? = .init()", "var textStyle: TextStyle? = .init()")
        harness = preamble + "\nenum FontProbe {\n" + methods + r"""
        }
        @main enum Main {
            static func main() {
                var layer = SceneRenderDescriptor.Layer(id: 71)
                layer.textStyle!.fontPath = "fonts/birth.ttf"
                func signature(_ value: String?, interested: Bool = true) -> SceneDynamicTextSignature {
                    let values: [SceneDynamicTarget: SceneDynamicSnapshot.Entry] = value.map {
                        [.text(layerID: layer.id, field: .font): .init(value: .string($0))]
                    } ?? [:]
                    return FontProbe.signature(for: layer, snapshot: .init(values: values),
                        dynamicFields: interested ? [.font] : [])
                }
                let result = ["missingUsesBirth": signature(nil).fontPath == "fonts/birth.ttf",
                    "explicitDefaultIgnoresBirth": signature("").fontPath == nil,
                    "typedPathWins": signature("fonts/next.ttf").fontPath == "fonts/next.ttf",
                    "uninterestedKeepsBirth": signature("fonts/next.ttf", interested: false).fontPath == "fonts/birth.ttf"]
                print(String(decoding: try! JSONSerialization.data(withJSONObject: result), as: UTF8.self))
            }
        }
        """
        with tempfile.TemporaryDirectory(prefix="mwx-text-font-signature-") as directory:
            root = Path(directory)
            swift = root / "FontProbe.swift"
            swift.write_text(harness, encoding="utf-8")
            binary = root / "probe"
            compiled = subprocess.run(["swiftc", "-parse-as-library", str(SOURCE), str(swift),
                "-module-cache-path", str(root / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(executed.returncode, 0, executed.stderr)
            self.assertEqual(json.loads(executed.stdout), {"missingUsesBirth": True,
                "explicitDefaultIgnoresBirth": True, "typedPathWins": True,
                "uninterestedKeepsBirth": True})

    def test_continuous_updates_keep_only_one_render_in_flight_and_then_latest(self) -> None:
        self.assertFalse(self.result["queuedLatestStartedImmediately"])
        # 单在途调度保证按 generation 完成；中间结果可安全发布，随后只追最新，
        # 避免连续 Timeline 因永远落后一帧而饿死。
        self.assertTrue(self.result["scheduledStaleAccepted"])
        self.assertEqual(self.result["scheduledNextContent"], "C")
        self.assertTrue(self.result["scheduledLatestAccepted"])
        self.assertFalse(self.result["scheduledHasThirdTask"])
        self.assertEqual(self.result["scheduledReadyWidth"], 300)

if __name__ == "__main__":
    unittest.main()
