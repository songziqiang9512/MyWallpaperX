"""Real Root -> private Sound file -> AV asset lifetime; generated silent WAV only."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import wave

from .test_scene_sound_playback_program import STUB_SOURCE
from .scene_pkg_fixture import make_package

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [SCENE / name for name in (
    "../SteamWorkshopStorage/ScenePlaybackSource.swift",
    "Resources/Assets/SceneResourceIdentity.swift",
    "Resources/Assets/SceneResourceView+Backing.swift",
    "Resources/Assets/SceneResourceIndex.swift",
    "Resources/Assets/SceneResourceView.swift",
    "Resources/Providers/SceneVideoOwnedFile.swift",
    "Systems/Media/SceneSoundPlaybackProgram.swift",
    "Systems/Media/SceneSoundPlaybackRegistry.swift",
    "Format/ScenePkgReader.swift",
)]
# Only document/dynamic value carriers remain doubled. All resource selection,
# copying, file lifetime, Sound preparation and AV playback owners are real.
CARRIERS = STUB_SOURCE.split("struct SceneResource {", 1)[0]

HARNESS = r'''
import AVFoundation
import CryptoKit
import Darwin
import Foundation

@main enum SoundResources {
    enum Stop: Error { case original }
    static let fm = FileManager.default
    static func wav(_ seconds: Double) -> Data {
        let samples = Int(seconds * 8_000)
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + samples * 2)); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(8_000); u32(16_000); u16(2); u16(16)
        text("data"); u32(UInt32(samples * 2)); data.append(Data(repeating: 0, count: samples * 2))
        return data
    }
    static func write(_ data: Data, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    static func sound(_ paths: [String], mode: String = "loop") -> SceneDocument.SceneSoundLayerDefinition {
        .init(paths: paths, authoredPathCount: paths.count, playbackMode: mode,
            startsSilent: false, muteInEditor: false, volume: 0, volumePropertyKey: nil,
            minimumTime: mode == "random" ? 0.05 : nil,
            maximumTime: mode == "random" ? 0.05 : nil,
            spatialization: nil, attenuation: nil, minimumDistance: nil)
    }
    static func view(_ base: URL) -> SceneResourceView {
        .init(projectRootURL: base.appendingPathComponent("loose"),
            packageRootURL: base.appendingPathComponent("package"), stockAssetsRootURL: nil)
    }
    static func files(_ cache: URL) -> [URL] {
        let dir = cache.appendingPathComponent(".mywallpaperx-scene-video-payloads")
        return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }
    static func prepare(_ paths: [String], view: SceneResourceView, cache: URL,
                        mode: String = "loop", check: (() throws -> Void)? = nil) throws -> SceneSoundPlaybackProgram {
        try .compile(document: .init(objects: [.init(id: 1, sound: sound(paths, mode: mode))]),
            resourceView: view, privateCacheDirectory: cache, checkCancellation: check)
    }
    static func hasChunk(_ cache: URL) -> Bool {
        files(cache).contains { (((try? fm.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber)?.intValue ?? 0) >= 65_536 }
    }
    static func pump(_ seconds: Double, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !condition() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }
    static func player(_ registry: SceneSoundPlaybackRegistry, layer: Int) -> AVQueuePlayer {
        let sources = Mirror(reflecting: registry).children.first { $0.label == "sources" }!.value
        for child in Mirror(reflecting: sources).children {
            let pair = Array(Mirror(reflecting: child.value).children)
            if pair[0].value as? Int == layer {
                return Mirror(reflecting: pair[1].value).children.first { $0.value is AVQueuePlayer }!.value as! AVQueuePlayer
            }
        }
        fatalError("real player missing")
    }
    static func sourceSetup(_ base: URL, large: Bool = false) throws -> (URL, URL) {
        let source = base.appendingPathComponent("package/audio/first.wav")
        let cache = base.appendingPathComponent("cache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("loose"), withIntermediateDirectories: true)
        try write(large ? Data(repeating: 37, count: 512 * 1_024) : wav(0.3), source)
        return (source, cache)
    }
    static func selection(_ base: URL) throws -> [String: Bool] {
        let (first, cache) = try sourceSetup(base)
        let package = base.appendingPathComponent("package")
        let second = package.appendingPathComponent("audio/second.wav")
        let raw = package.appendingPathComponent("audio/raw\\leaf.wav")
        let a = try Data(contentsOf: first), b = wav(0.42)
        try write(b, second); try write(wav(0.2), raw)
        let mp3 = package.appendingPathComponent("audio/renamed-track.MP3")
        let flac = package.appendingPathComponent("alternate/renamed-track.FLAC")
        let encoded = URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("encoded")
        let mp3Bytes = fm.fileExists(atPath: encoded.appendingPathComponent("silent.mp3").path)
            ? try Data(contentsOf: encoded.appendingPathComponent("silent.mp3")) : wav(0.3)
        let flacBytes = fm.fileExists(atPath: encoded.appendingPathComponent("silent.flac").path)
            ? try Data(contentsOf: encoded.appendingPathComponent("silent.flac")) : wav(0.3)
        try write(mp3Bytes, mp3); try write(flacBytes, flac)
        try write(wav(0.6), base.appendingPathComponent("loose/audio/first.wav"))
        let program = try SceneSoundPlaybackProgram.compile(document: .init(objects: [
            .init(id: 1, sound: sound(["audio/first.wav", "audio/second.wav"])),
            .init(id: 2, sound: sound(["audio/first.wav"], mode: "single")),
            .init(id: 3, sound: sound(["audio/second.wav", "audio/first.wav", "audio/raw/leaf.wav"], mode: "random")),
            .init(id: 4, sound: sound(["audio/renamed-track.MP3"])),
            .init(id: 5, sound: sound(["alternate/renamed-track.FLAC"]))
        ]), resourceView: view(base), privateCacheDirectory: cache)
        let resources = program.bindings.flatMap(\.resources)
        let one = program.bindings[0].resources[0].file!, two = program.bindings[1].resources[0].file!
        let random = program.bindings[2].resources
        let owned = resources.compactMap(\.file)
        let permissions = owned.allSatisfy {
            ((try? fm.attributesOfItem(atPath: $0.url.path)[.posixPermissions]) as? NSNumber)?.intValue == 0o600
        }
        try write(wav(0.9), first); try fm.removeItem(at: second)
        return ["firstSelectedPackageBytes": try Data(contentsOf: one.url) == a,
            "sameSelectedHandleShared": one === two && one === random[1].file,
            "randomAuthorOrderAndRawSelectedRead": try Data(contentsOf: random[0].file!.url) == b
                && Data(contentsOf: random[2].file!.url) == wav(0.2),
            "copiedOncePerSelectedSource": files(cache).count == 5,
            "mp3FlacRawBytesAndSuffix": try Data(contentsOf: program.bindings[3].resources[0].file!.url) == mp3Bytes
                && Data(contentsOf: program.bindings[4].resources[0].file!.url) == flacBytes
                && program.bindings[3].resources[0].file!.url.pathExtension == "mp3"
                && program.bindings[4].resources[0].file!.url.pathExtension == "flac",
            "privateSuffixAndMode": permissions && owned.allSatisfy { ["wav", "mp3", "flac"].contains($0.url.pathExtension) && $0.url.path.hasPrefix(cache.path + "/") },
            "noOriginalAuthorURL": owned.allSatisfy { ![first, second, raw].contains($0.url) }]
    }
    static func unavailable(_ base: URL) throws -> [String: Bool] {
        let (first, cache) = try sourceSetup(base)
        try write(wav(0.5), base.appendingPathComponent("loose/audio/first.wav"))
        try write(wav(0.4), base.appendingPathComponent("package/audio/second.wav"))
        let captured = view(base)
        try fm.removeItem(at: first)
        let loop = try prepare(["audio/first.wav", "audio/second.wav"], view: captured, cache: cache)
        let random = try prepare(["audio/first.wav", "audio/second.wav"], view: captured, cache: cache, mode: "random")
        return ["bindingAndFirstSlotKept": loop.bindings.count == 1 && loop.bindings[0].resources.count == 1 && loop.bindings[0].resources[0].file == nil,
            "randomNilSlotAndOrderKept": random.bindings.count == 1 && random.bindings[0].resources.count == 2 && random.bindings[0].resources[0].file == nil && random.bindings[0].resources[1].file != nil,
            "unavailableDiagnosticPreserved": loop.diagnostics.contains { $0.reason == .resourceUnavailable },
            "noFallbackPrivateFile": files(cache).count == 1]
    }
    static func failures(_ base: URL, kind: String) throws -> [String: Bool] {
        let (source, cache) = try sourceSetup(base, large: true)
        let captured = view(base)
        var triggered = false, preserved = false
        do {
            _ = try prepare(["audio/first.wav"], view: captured, cache: cache, check: {
                guard !triggered, hasChunk(cache) else { return }
                triggered = true
                if kind == "cancel" { throw CancellationError() }
                if kind == "callback" { throw Stop.original }
                if kind == "replace" { try wav(0.5).write(to: source, options: .atomic) }
                if kind == "truncate" {
                    let file = try FileHandle(forWritingTo: source)
                    defer { try? file.close() }; try file.truncate(atOffset: 1)
                }
            })
        } catch is CancellationError { preserved = kind == "cancel" }
        catch Stop.original { preserved = kind == "callback" }
        catch SceneResourceView.ReadError.sourceChanged { preserved = kind == "replace" || kind == "truncate" }
        return ["actualChunkReached": triggered, "originalFailurePreserved": preserved,
            "partialCleaned": files(cache).isEmpty]
    }
    static func retarget(_ base: URL) throws -> [String: Bool] {
        let (_, cache) = try sourceSetup(base)
        let package = base.appendingPathComponent("package"), link = base.appendingPathComponent("root-link")
        let other = base.appendingPathComponent("other")
        try write(wav(0.7), other.appendingPathComponent("audio/first.wav"))
        try fm.createSymbolicLink(at: link, withDestinationURL: package)
        let captured = SceneResourceView.Root(source: .package, url: link)
        let handle = try captured.existingLiteralHandle(relativePath: "audio/first.wav")!
        try fm.removeItem(at: link); try fm.createSymbolicLink(at: link, withDestinationURL: other)
        var changed = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav") }
        catch SceneResourceView.ReadError.sourceChanged { changed = true }
        let raw = package.appendingPathComponent("audio/raw\\leaf.wav")
        try write(wav(0.2), raw)
        let rawRoot = SceneResourceView.Root(source: .package, url: package)
        let selected = rawRoot.handle(relativePath: "audio/raw/leaf.wav")!
        try fm.removeItem(at: raw)
        try fm.createSymbolicLink(at: raw, withDestinationURL: other.appendingPathComponent("audio/first.wav"))
        var escaped = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: selected, cacheDirectory: cache, fileExtension: "wav") }
        catch SceneResourceView.ReadError.symlinkEscape { escaped = true }
        return ["rootRetargetRejected": changed, "rawSelectedEscapeRejected": escaped,
            "noPublishedPrivateFile": files(cache).isEmpty]
    }
    static func writeFailure(_ base: URL) throws -> [String: Bool] {
        let (source, cache) = try sourceSetup(base, large: true)
        let handle = view(base).resolvedResource(forReference: "audio/first.wav")!
        var failure = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav") }
        catch let SceneVideoOwnedFile.Failure.io(operation, code) { failure = operation == .writeSnapshot && code == EIO }
        let plan = try prepare(["audio/first.wav"], view: view(base), cache: cache)
        return ["realWriteFailureObserved": failure, "partialCleaned": files(cache).isEmpty,
            "authorStillExists": fm.fileExists(atPath: source.path),
            "selectedWriteFailureIsUnavailableSlot": plan.bindings.count == 1 && plan.bindings[0].resources[0].file == nil]
    }
    static func native(_ base: URL) throws -> [String: Bool] {
        let (source, cache) = try sourceSetup(base)
        let package = base.appendingPathComponent("package")
        try write(wav(0.42), package.appendingPathComponent("audio/second.wav"))
        try write(Data("not an audio codec".utf8), package.appendingPathComponent("audio/bad.wav"))
        var facts: [String: Bool] = [:]
        var borrowedItem: AVPlayerItem?
        var borrowedAsset: AVAsset?
        var pinnedURL: URL!
        weak var weakFile: SceneVideoOwnedFile?
        try autoreleasepool {
        var program: SceneSoundPlaybackProgram? = try .compile(document: .init(objects: [
            .init(id: 11, sound: sound(["audio/first.wav"])),
            .init(id: 12, sound: sound(["audio/first.wav"], mode: "single")),
            .init(id: 13, sound: sound(["audio/first.wav", "audio/second.wav"], mode: "random")),
            .init(id: 14, sound: sound(["audio/bad.wav"], mode: "random"))
        ]), resourceView: view(base), privateCacheDirectory: cache)
        let allowed = Set(program!.bindings.flatMap(\.resources).compactMap { $0.file?.url })
        pinnedURL = program!.bindings[0].resources[0].file!.url
        weakFile = program!.bindings[0].resources[0].file
        try fm.removeItem(at: source)
        var registry: SceneSoundPlaybackRegistry? = .init(program: program!, epoch: 71)
        registry!.start(paused: false, userValues: [:])
        let loop = player(registry!, layer: 11), single = player(registry!, layer: 12)
        let random = player(registry!, layer: 13), bad = player(registry!, layer: 14)
        let ready = pump(8) { loop.currentItem?.status == .readyToPlay && CMTimeGetSeconds(loop.currentTime()) > 0.05 }
        let isolatedFailure = pump(8) { bad.items().isEmpty && registry!.sceneScriptSnapshots()[14] == false }
        let privateAssets = [loop, single, random].allSatisfy {
            guard let asset = $0.currentItem?.asset as? AVURLAsset else { return $0 === single && $0.items().isEmpty }
            return allowed.contains(asset.url)
        }
        let singleEnded = pump(8) { single.items().isEmpty }
        try registry!.apply([.init(layerID: 12, action: .play, destination: .soundLayer)]).get()
        let singleReplayed = pump(4) { single.currentItem?.status == .readyToPlay && CMTimeGetSeconds(single.currentTime()) > 0.03 }
        let randomEnded = pump(8) { random.items().isEmpty }
        registry!.advance(sceneTime: 10); registry!.advance(sceneTime: 10.06)
        let randomReplayed = random.items().count == 1 && (random.currentItem?.asset as? AVURLAsset).map { allowed.contains($0.url) } == true
        borrowedItem = loop.currentItem
        borrowedAsset = borrowedItem?.asset
        let actualLooperItemBorrowed = borrowedItem != nil && (borrowedAsset as? AVURLAsset)?.url == pinnedURL
        registry!.stop(); registry = nil; program = nil
        facts = ["realPrivateAssetReadyAfterAuthorDeletion": ready && privateAssets,
            "ordinaryCodecFailureLocal": isolatedFailure && ready,
            "singleOwnedFileReplayed": singleEnded && singleReplayed,
            "randomOwnedFileNaturalEndAndReplay": randomEnded && randomReplayed,
            "actualLooperItemBorrowed": actualLooperItemBorrowed]
        }
        facts["filePinnedUntilActualAVBorrowerReleased"] = weakFile != nil && fm.fileExists(atPath: pinnedURL.path)
        autoreleasepool { borrowedItem = nil; borrowedAsset = nil }
        facts["finalBorrowerUnlinksFile"] = pump(8) { weakFile == nil && !fm.fileExists(atPath: pinnedURL.path) }
        return facts
    }
    static func nativeCodecs(_ base: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let encoded = URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("encoded")
        for ext in ["mp3", "flac"] {
            let part = base.appendingPathComponent(ext)
            let (_, cache) = try sourceSetup(part)
            let name = "audio/renamed-track." + ext.uppercased()
            let author = part.appendingPathComponent("package").appendingPathComponent(name)
            let bytes = try Data(contentsOf: encoded.appendingPathComponent("silent." + ext))
            try write(bytes, author)
            let plan = try prepare([name], view: view(part), cache: cache, mode: "single")
            let owned = plan.bindings[0].resources[0].file!.url
            facts[ext + "PrivateSuffixAndExactEncodedBytes"] = try owned.pathExtension == ext && Data(contentsOf: owned) == bytes
            try fm.removeItem(at: author)
            let registry = SceneSoundPlaybackRegistry(program: plan, epoch: 91)
            registry.start(paused: false, userValues: [:])
            let actual = player(registry, layer: 1)
            guard let item = actual.currentItem else { fatalError("codec item missing") }
            var ended = false
            let observer = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item, queue: .main) { _ in ended = true }
            let ready = pump(8) { item.status == .readyToPlay }
            let naturalEnd = pump(8) { ended && actual.items().isEmpty }
            facts[ext + "RealAVReadyAndNaturalEnd"] = ready && naturalEnd
                && (item.asset as? AVURLAsset)?.url == owned
            NotificationCenter.default.removeObserver(observer)
            registry.stop()
        }
        return facts
    }
    static func packageLifetime(_ base: URL) throws -> [String: Bool] {
        let project = base.appendingPathComponent("project"), cache = base.appendingPathComponent("private-cache")
        let package = project.appendingPathComponent("scene.pkg")
        let fixture = URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("package-lifetime-fixture.pkg")
        let packageBytes = try Data(contentsOf: fixture)
        try write(packageBytes, package)
        let retired = project.appendingPathComponent(".scene-extracted/sounds/owned.wav")
        let retiredCache = cache.appendingPathComponent("retired-package-cache/sounds/owned.wav")
        try write(wav(0.1), retired); try write(wav(0.12), retiredCache)
        let first = try SceneResourceView.Root.package(openedPackage: ScenePkgReader().openPackage(packageURL: package))
        let bytes = try first.existingLiteralHandle(relativePath: "sounds/owned.wav")!.readBytes()
        func packageView(_ root: SceneResourceView.Root) -> SceneResourceView {
            .init(projectRoot: .init(source: .loose, url: project), packageRoot: root, stockRoot: nil)
        }
        var facts: [String: Bool] = [:]
        var borrowedItem: AVPlayerItem?, borrowedAsset: AVAsset?
        var privateURL: URL!
        weak var weakFile: SceneVideoOwnedFile?
        try autoreleasepool {
            var program: SceneSoundPlaybackProgram? = try prepare(["sounds/owned.wav"], view: packageView(first), cache: cache)
            let file = program!.bindings[0].resources[0].file!
            privateURL = file.url; weakFile = file
            facts["privateLeaseOutsideAuthorAndRetiredCache"] = file.url.path.hasPrefix(cache.path + "/")
                && !file.url.path.hasPrefix(project.path + "/") && !file.url.path.hasPrefix(retiredCache.deletingLastPathComponent().path + "/")
            var registry: SceneSoundPlaybackRegistry? = .init(program: program!, epoch: 97)
            registry!.start(paused: true, userValues: [:])
            let actual = player(registry!, layer: 1)
            facts["actualPrivateAVAssetReady"] = pump(8) { actual.currentItem?.status == .readyToPlay }
            borrowedItem = actual.currentItem; borrowedAsset = borrowedItem?.asset
            facts["borrowerUsesPrivateLease"] = (borrowedAsset as? AVURLAsset)?.url == privateURL
            let warm = try SceneResourceView.Root.package(openedPackage: ScenePkgReader().openPackage(packageURL: package))
            let warmProgram = try prepare(["sounds/owned.wav"], view: packageView(warm), cache: cache)
            facts["independentPackageMountReusesCompletedFile"] = warmProgram.bindings[0].resources[0].file === file
                && warm.directoryURL == nil && (try? Data(contentsOf: privateURL)) == bytes
            try write(wav(0.08), retired); try write(wav(0.09), retiredCache)
            let remounted = try SceneResourceView.Root.package(openedPackage: ScenePkgReader().openPackage(packageURL: package))
            let remountedBytes = try remounted.existingLiteralHandle(relativePath: "sounds/owned.wav")!.readBytes()
            facts["retiredCachePollutionDoesNotChangePackageBytes"] = remountedBytes == bytes
                && (try? Data(contentsOf: package)) == packageBytes
            facts["retiredCachePollutionKeepsBorrowedPrivateBytes"] = borrowedAsset != nil
                && (try? Data(contentsOf: privateURL)) == bytes
            registry!.stop(); registry = nil; program = nil
        }
        facts["actualBorrowerAloneStillPinsPrivateFile"] = weakFile != nil && (try? Data(contentsOf: privateURL)) == bytes
        autoreleasepool { borrowedItem = nil; borrowedAsset = nil }
        facts["finalBorrowerUnlinksPrivateFile"] = pump(8) { weakFile == nil && !fm.fileExists(atPath: privateURL.path) }
        for kind in ["failed", "missing"] {
            let looseProject = base.appendingPathComponent(kind + "-loose-project")
            let looseSound = looseProject.appendingPathComponent("sounds/loose.wav")
            try write(bytes, looseSound)
            try write(wav(0.1), looseProject.appendingPathComponent(".scene-extracted/sounds/loose.wav"))
            let invalidPackage = looseProject.appendingPathComponent("scene.pkg")
            if kind == "failed" { try Data("not a package".utf8).write(to: invalidPackage) }
            var unavailable = false
            do { _ = try ScenePkgReader().openPackage(packageURL: invalidPackage) }
            catch ScenePkgReader.ReadError.fileTooSmall { unavailable = kind == "failed" }
            catch let error as POSIXError { unavailable = kind == "missing" && error.code == .ENOENT }
            func authorPaths() -> [String] {
                (fm.enumerator(at: looseProject, includingPropertiesForKeys: nil)!.allObjects as! [URL]).map(\.path).sorted()
            }
            let beforePaths = authorPaths()
            let looseView = SceneResourceView(projectRoot: .init(source: .loose, url: looseProject), packageRoot: nil, stockRoot: nil)
            let plan = try prepare(["sounds/loose.wav"], view: looseView, cache: cache)
            let copied = plan.bindings.first?.resources.first?.file
            facts[kind + "PackageUnavailableKeepsActualLooseSelection"] = unavailable
                && looseView.resolvedResource(forReference: "sounds/loose.wav")?.owner.source == .loose && copied != nil
            facts[kind + "LooseSnapshotUsesPrivateCacheOutsideAuthor"] = copied.map {
                $0.url.path.hasPrefix(cache.path + "/") && !$0.url.path.hasPrefix(looseProject.path + "/")
                    && (try? Data(contentsOf: $0.url)) == bytes
            } == true
            facts[kind + "LooseAuthorNamespaceUnchanged"] = authorPaths() == beforePaths && (try? Data(contentsOf: looseSound)) == bytes
        }
        return facts
    }
    enum FixtureFailure: Error { case missing(String) }
    static func io(_ name: String) throws -> UInt64 {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "mwx_sound_io_" + name) else {
            throw FixtureFailure.missing("IO observation: " + name)
        }
        return unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)()
    }
    // Independent Roots mount the same current opened file revision.
    static func mounted(_ base: URL, packagePath: String = "scene.pkg") throws -> SceneResourceView.Root {
        let url = base.appendingPathComponent("packages").appendingPathComponent(packagePath)
        if !fm.fileExists(atPath: url.path) {
            let fixture = URL(fileURLWithPath: CommandLine.arguments[3]).appendingPathComponent("weak-package-fixture.pkg")
            try write(Data(contentsOf: fixture), url)
        }
        return try .package(openedPackage: ScenePkgReader().openPackage(packageURL: url))
    }
    static func packageView(_ root: SceneResourceView.Root, base: URL) throws -> SceneResourceView {
        let loose = base.appendingPathComponent("loose")
        try fm.createDirectory(at: loose, withIntermediateDirectories: true)
        return .init(projectRoot: .init(source: .loose, url: loose), packageRoot: root, stockRoot: nil)
    }
    static func selected(_ root: SceneResourceView.Root, _ path: String = "sounds/owned.wav") throws -> SceneResourceView.Handle {
        guard let handle = try root.existingLiteralHandle(relativePath: path) else {
            throw FixtureFailure.missing("selected package leaf: " + path)
        }
        return handle
    }
    static func owned(_ program: SceneSoundPlaybackProgram) throws -> SceneVideoOwnedFile {
        guard let file = program.bindings.first?.resources.first?.file else {
            throw FixtureFailure.missing("prepared Sound resource")
        }
        return file
    }
    static func packageReuse(_ base: URL) throws -> [String: Bool] {
        let cache = base.appendingPathComponent("cache"), budget = SceneVideoOwnedFile.DiskBudget.shared
        let before = budget.reservedBytes
        var facts: [String: Bool] = [:], borrowedAsset: AVAsset?, privateURL: URL?
        weak var weakFile: SceneVideoOwnedFile?
        try autoreleasepool {
            let rootA = try mounted(base), rootB = try mounted(base)
            _ = try io("reset")
            var a: SceneSoundPlaybackProgram? = try prepare(["sounds/owned.wav"],
                view: packageView(rootA, base: base), cache: cache)
            guard let first = a else { throw FixtureFailure.missing("first Program") }
            let file = try owned(first)
            weakFile = file; privateURL = file.url
            facts["firstCopyHasExactPayloadIOAndSingleCharge"] = try io("read_bytes") == UInt64(wav(10).count)
                && io("write_bytes") == UInt64(wav(10).count) && budget.reservedBytes - before == UInt64(wav(10).count)
            var registryA: SceneSoundPlaybackRegistry? = .init(program: first, epoch: 101)
            registryA?.start(paused: true, userValues: [:])
            guard let activeA = registryA else { throw FixtureFailure.missing("first Registry") }
            let playerA = player(activeA, layer: 1)
            guard pump(8, until: { playerA.currentItem != nil }), let asset = playerA.currentItem?.asset else {
                throw FixtureFailure.missing("actual looper asset")
            }
            borrowedAsset = asset
            _ = try io("reset")
            var b: SceneSoundPlaybackProgram? = try prepare(["sounds/owned.wav"],
                view: packageView(rootB, base: base), cache: cache)
            guard let second = b else { throw FixtureFailure.missing("second Program") }
            let peer = try owned(second)
            var registryB: SceneSoundPlaybackRegistry? = .init(program: second, epoch: 102)
            registryB?.start(paused: true, userValues: [:])
            guard let activeB = registryB else { throw FixtureFailure.missing("second Registry") }
            let playerB = player(activeB, layer: 1)
            facts["independentProgramsAndRegistriesShareCompletedFile"] = rootA !== rootB && playerA !== playerB && file === peer
                && pump(8, until: { playerB.currentItem != nil })
                && (playerB.currentItem?.asset as? AVURLAsset)?.url == file.url
                && (asset as? AVURLAsset)?.url == file.url
            facts["warmHitHasNoPayloadReadWriteOrSecondCharge"] = try io("read_bytes") == 0
                && io("write_bytes") == 0 && budget.reservedBytes - before == UInt64(wav(10).count)
                && files(cache).count == 1
            registryA?.stop(); registryB?.stop(); registryA = nil; registryB = nil; a = nil; b = nil
        }
        guard let url = privateURL else { throw FixtureFailure.missing("private URL") }
        facts["onlyActualAssetBorrowerKeepsFileAndCharge"] = weakFile != nil && borrowedAsset != nil
            && fm.fileExists(atPath: url.path) && budget.reservedBytes - before == UInt64(wav(10).count)
        try autoreleasepool {
            let root = try mounted(base)
            _ = try io("reset")
            let next = try prepare(["sounds/owned.wav"], view: packageView(root, base: base), cache: cache)
            facts["assetOnlyBorrowerStillAllowsHit"] = try owned(next) === weakFile
                && io("read_bytes") == 0 && io("write_bytes") == 0
        }
        autoreleasepool { borrowedAsset = nil }
        facts["weakLookupDoesNotDelayFinalUnlinkOrBudgetReturn"] = pump(8) {
            weakFile == nil && !fm.fileExists(atPath: url.path) && budget.reservedBytes == before
        }
        try autoreleasepool {
            let root = try mounted(base)
            _ = try io("reset")
            let next = try prepare(["sounds/owned.wav"], view: packageView(root, base: base), cache: cache)
            facts["afterFinalReleaseColdCopyResumes"] = try owned(next).url != url
                && io("read_bytes") == UInt64(wav(10).count) && io("write_bytes") == UInt64(wav(10).count)
        }
        return facts
    }
    static func packageFailures(_ base: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let cache = base.appendingPathComponent("cache"), root = try mounted(base), handle = try selected(root)
        let file = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav")
        _ = try io("reset")
        var cancelled = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav",
            checkCancellation: { throw Stop.original }) } catch Stop.original { cancelled = true }
        facts["cachedSuccessNeverBypassesOriginalCancellation"] = try cancelled && io("write_bytes") == 0
        for operation in ["rewrite", "delete", "symlink"] {
            let current = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav")
            let outside = base.appendingPathComponent("outside.wav"), outsideBytes = wav(0.1)
            if operation == "rewrite" { try Data(repeating: 19, count: wav(10).count).write(to: current.url) }
            else {
                try fm.removeItem(at: current.url)
                if operation == "symlink" { try write(outsideBytes, outside); try fm.createSymbolicLink(at: current.url, withDestinationURL: outside) }
            }
            _ = try io("reset")
            let repaired = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav")
            facts[operation + "CannotReuseUnsafeOutput"] = try repaired !== current && repaired.url != current.url
                && Data(contentsOf: repaired.url) == wav(10) && io("read_bytes") == UInt64(wav(10).count)
                && io("write_bytes") == UInt64(wav(10).count)
            if operation == "symlink" { facts["externalSymlinkTargetUntouched"] = try Data(contentsOf: outside) == outsideBytes }
        }
        let approved = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav")
        let peerRoot = try mounted(base)
        facts["sameCurrentRevisionReusesAcrossIndependentRoots"] = try SceneVideoOwnedFile.snapshot(
            from: selected(peerRoot), cacheDirectory: cache, fileExtension: "wav") === approved
        let author = base.appendingPathComponent("packages/scene.pkg")
        guard let backing = root.packageBacking else { throw FixtureFailure.missing("actual package backing") }
        let writing = try FileHandle(forWritingTo: author)
        try writing.seek(toOffset: UInt64(backing.opened.index.dataStartOffset))
        try writing.write(contentsOf: Data([17])); try writing.close()
        _ = try io("reset")
        var changed = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav") }
        catch SceneResourceView.ReadError.sourceChanged { changed = true }
        facts["cachedSuccessNeverBypassesCurrentSourceChanged"] = try changed && io("write_bytes") == 0
        withExtendedLifetime((file, approved)) {}
        return facts
    }
    static func packagePartitions(_ base: URL) throws -> [String: Bool] {
        let cache = base.appendingPathComponent("cache"), root = try mounted(base), handle = try selected(root)
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 8 * 1_024 * 1_024)
        let first = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav", diskBudget: budget)
        var facts: [String: Bool] = [:], retained = [first]
        let variants: [(String, SceneResourceView.Root, String)] = [
            ("packagePath", try mounted(base, packagePath: "renamed.pkg"), "sounds/owned.wav"),
            ("rawEntry", root, "sounds/peer.wav")]
        for (name, candidate, path) in variants {
            _ = try io("reset")
            let result = try SceneVideoOwnedFile.snapshot(from: selected(candidate, path), cacheDirectory: cache,
                fileExtension: "wav", diskBudget: budget)
            facts[name + "SeparatesSuccessfulFiles"] = try result !== first && io("write_bytes") == UInt64(wav(10).count)
            retained.append(result)
        }
        let otherBudget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 8 * 1_024 * 1_024)
        let other = base.appendingPathComponent("other-cache")
        for (name, directory, suffix, ledger) in [("outputDomain", other, "wav", budget),
            ("suffix", cache, "mp3", budget), ("budget", cache, "wav", otherBudget)] {
            let result = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: directory,
                fileExtension: suffix, diskBudget: ledger)
            facts[name + "SeparatesSuccessfulFiles"] = result !== first && result.url != first.url
            retained.append(result)
        }
        facts["separateLedgerChargesItsOwnOutput"] = otherBudget.reservedBytes == UInt64(wav(10).count)
        let author = base.appendingPathComponent("packages/scene.pkg")
        try Data(contentsOf: author).write(to: author, options: .atomic)
        let currentRoot = try mounted(base)
        let replaced = try SceneVideoOwnedFile.snapshot(from: selected(currentRoot), cacheDirectory: cache,
            fileExtension: "wav", diskBudget: budget)
        facts["replacedPackageRevisionCannotReuseOldFile"] = replaced !== first
            && replaced.url != first.url
        retained.append(replaced)
        withExtendedLifetime(retained) {}
        return facts
    }
    static func packageRetry(_ base: URL) throws -> [String: Bool] {
        let root = try mounted(base), handle = try selected(root), cache = base.appendingPathComponent("cache")
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 8 * 1_024 * 1_024)
        var facts: [String: Bool] = [:]
        _ = try io("reset"); _ = try io("fail_next_write")
        var failed = false
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav", diskBudget: budget) }
        catch SceneVideoOwnedFile.Failure.io(let operation, let code) { failed = operation == .writeSnapshot && code == EIO }
        facts["failedWriteHasNoFileOrCharge"] = failed && files(cache).isEmpty && budget.reservedBytes == 0
        var cancelled = false
        _ = try io("reset")
        do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav", diskBudget: budget,
            checkCancellation: { if try io("write_bytes") > 0 { throw CancellationError() } }) }
        catch is CancellationError { cancelled = true }
        facts["partialCancellationReachesRealWriteAndReturnsCharge"] = try cancelled && io("write_bytes") > 0
            && files(cache).isEmpty && budget.reservedBytes == 0
        _ = try io("reset")
        let recovered = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache, fileExtension: "wav", diskBudget: budget)
        facts["failureAndCancelDoNotPoisonLaterSuccess"] = try Data(contentsOf: recovered.url) == wav(10)
            && io("read_bytes") == UInt64(wav(10).count) && io("write_bytes") == UInt64(wav(10).count)
            && budget.reservedBytes == UInt64(wav(10).count)
        return facts
    }
    static func packageSnapshotBoundaries(_ base: URL) throws -> [String: Bool] {
        var facts: [String: Bool] = [:]
        let original = wav(10)
        var changedBytes = original
        changedBytes[changedBytes.count - 1] = 17
        for mode in ["completed-copy", "completed-hit", "during-read", "cancel-after-close"] {
            let directory = base.appendingPathComponent(mode), cache = directory.appendingPathComponent("cache")
            let root = try mounted(directory), handle = try selected(root)
            guard let backing = root.packageBacking,
                  let entry = backing.opened.index.entries.first(where: { $0.path == "sounds/owned.wav" }) else {
                throw FixtureFailure.missing("actual package entry")
            }
            let author = directory.appendingPathComponent("packages/scene.pkg")
            func mutateAuthor() throws {
                let writing = try FileHandle(forWritingTo: author)
                defer { try? writing.close() }
                try writing.seek(toOffset: UInt64(backing.opened.index.dataStartOffset)
                    + UInt64(entry.offset) + UInt64(entry.size) - 1)
                try writing.write(contentsOf: Data([17]))
            }
            let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 8 * 1_024 * 1_024)
            let oldIdentity = try handle.currentIdentity()
            var prior: SceneVideoOwnedFile?
            if mode == "completed-hit" {
                prior = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache,
                    fileExtension: "wav", diskBudget: budget)
            }
            _ = try io("reset")
            var mutated = false, cancelled = false, rejected = false
            var completed: SceneVideoOwnedFile?
            do {
                completed = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache,
                    fileExtension: "wav", diskBudget: budget, checkCancellation: {
                        if mode == "cancel-after-close", try io("closed_outputs") > 0 { throw Stop.original }
                        let reached: Bool
                        if mode == "during-read" { reached = try io("write_bytes") > 0 }
                        else { reached = try io("closed_outputs") > 0 }
                        if reached, !mutated { mutated = true; try mutateAuthor() }
                    })
            } catch Stop.original { cancelled = true }
            catch SceneResourceView.ReadError.sourceChanged { rejected = true }
            if mode == "during-read" {
                facts["readInProgressStillRejectsChangedPackage"] = try mutated && rejected && completed == nil
                    && io("write_bytes") > 0 && files(cache).isEmpty && budget.reservedBytes == 0
            } else if mode == "cancel-after-close" {
                facts["completedCopyStillPropagatesOriginalCancellation"] = try cancelled && completed == nil
                    && io("closed_outputs") > 0 && files(cache).isEmpty && budget.reservedBytes == 0
            } else {
                guard let completed else { throw FixtureFailure.missing("completed package snapshot") }
                facts[mode + "KeepsCapturedBytesAfterAuthorWrite"] = try mutated && !rejected
                    && Data(contentsOf: completed.url) == original && budget.reservedBytes == UInt64(original.count)
                    && io("read_bytes") == (prior == nil ? UInt64(original.count) : 0)
                    && io("write_bytes") == (prior == nil ? UInt64(original.count) : 0)
                    && (prior == nil || completed === prior)
                _ = try io("reset")
                var stale = false
                do { _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache,
                    fileExtension: "wav", diskBudget: budget) }
                catch SceneResourceView.ReadError.sourceChanged { stale = true }
                facts[mode + "NextOldHandleStillRejectsBeforePayload"] = try stale && io("read_bytes") == 0
                    && io("write_bytes") == 0
                let current = try selected(mounted(directory))
                let nextIdentity = try current.currentIdentity()
                _ = try io("reset")
                let next = try SceneVideoOwnedFile.snapshot(from: current, cacheDirectory: cache,
                    fileExtension: "wav", diskBudget: budget)
                facts[mode + "NewRequestUsesNewRevisionAndBytes"] = try nextIdentity != oldIdentity && next !== completed
                    && Data(contentsOf: next.url) == changedBytes && Data(contentsOf: completed.url) == original
                    && io("read_bytes") == UInt64(original.count) && io("write_bytes") == UInt64(original.count)
                    && budget.reservedBytes == UInt64(original.count * 2)
                withExtendedLifetime((prior, completed, next)) {}
            }
        }
        return facts
    }
    static func main() throws {
        let mode = CommandLine.arguments[1], base = URL(fileURLWithPath: CommandLine.arguments[2])
        var facts: [String: Bool]
        switch mode {
        case "selection": facts = try selection(base)
        case "unavailable": facts = try unavailable(base)
        case "cancel", "callback", "replace", "truncate": facts = try failures(base, kind: mode)
        case "retarget": facts = try retarget(base)
        case "write-failure": facts = try writeFailure(base)
        case "native": facts = try native(base)
        case "native-codecs": facts = try nativeCodecs(base)
        case "root-lifetime": facts = try packageLifetime(base)
        case "package-reuse": facts = try packageReuse(base)
        case "package-failures": facts = try packageFailures(base)
        case "package-partitions": facts = try packagePartitions(base)
        case "package-retry": facts = try packageRetry(base)
        case "package-snapshot-boundaries": facts = try packageSnapshotBoundaries(base)
        default: fatalError("unknown controlled mode")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

WRITE_FAILURE = r'''
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/param.h>
#include <stdatomic.h>
#include <stdint.h>
static unsigned attempts;
static _Atomic uint64_t read_bytes, write_bytes, fail_next_write, closed_outputs;
uint64_t mwx_sound_io_reset(void) {
    atomic_store(&read_bytes, 0); atomic_store(&write_bytes, 0);
    atomic_store(&fail_next_write, 0); atomic_store(&closed_outputs, 0); return 0;
}
uint64_t mwx_sound_io_read_bytes(void) { return atomic_load(&read_bytes); }
uint64_t mwx_sound_io_write_bytes(void) { return atomic_load(&write_bytes); }
uint64_t mwx_sound_io_fail_next_write(void) { atomic_store(&fail_next_write, 1); return 0; }
uint64_t mwx_sound_io_closed_outputs(void) { return atomic_load(&closed_outputs); }
static int observed(int fd, const char *leaf) {
    const char *root = getenv("MWX_SOUND_IO_ROOT"); char path[MAXPATHLEN];
    return root && fcntl(fd, F_GETPATH, path) == 0
        && strncmp(path, root, strlen(root)) == 0 && strstr(path, leaf);
}
static ssize_t observe_package_read(int fd, void *bytes, size_t count, off_t offset) {
    ssize_t result = pread(fd, bytes, count, offset);
    if (result > 0 && observed(fd, "/packages/")) atomic_fetch_add(&read_bytes, (uint64_t)result);
    return result;
}
static int observe_owned_close(int fd) {
    int own = observed(fd, "/.mywallpaperx-scene-video-payloads/");
    int result = close(fd);
    if (own && result == 0) atomic_fetch_add(&closed_outputs, 1);
    return result;
}
static ssize_t fail_owned_write(int fd, const void *bytes, size_t count) {
    const char *prefix = getenv("MWX_SOUND_FAIL_WRITE_ROOT");
    char path[MAXPATHLEN];
    if (prefix && fcntl(fd, F_GETPATH, path) == 0 && strncmp(path, prefix, strlen(prefix)) == 0) {
        attempts++;
        if (attempts >= 2) { errno = EIO; return -1; }
    }
    int own = observed(fd, "/.mywallpaperx-scene-video-payloads/");
    if (own && atomic_exchange(&fail_next_write, 0)) { errno = EIO; return -1; }
    ssize_t result = write(fd, bytes, count);
    if (own && result > 0) atomic_fetch_add(&write_bytes, (uint64_t)result);
    return result;
}
__attribute__((used)) static struct { const void *replacement, *original; }
interpose_write __attribute__((section("__DATA,__interpose"))) = { (const void *)fail_owned_write, (const void *)write };
__attribute__((used)) static struct { const void *replacement, *original; }
interpose_pread __attribute__((section("__DATA,__interpose"))) = { (const void *)observe_package_read, (const void *)pread };
__attribute__((used)) static struct { const void *replacement, *original; }
interpose_close __attribute__((section("__DATA,__interpose"))) = { (const void *)observe_owned_close, (const void *)close };
__attribute__((destructor)) static void trace(void) {
    const char *path = getenv("MWX_SOUND_FAIL_WRITE_TRACE");
    if (!path) return;
    FILE *file = fopen(path, "w");
    if (file) { fprintf(file, "%u\n", attempts); fclose(file); }
}
'''


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("xcrun"), "macOS Swift/clang required")
class SceneSoundResourceInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_SOUND_RESOURCE_EVIDENCE")
        if parent:
            cls.directory = Path(parent)
            cls.directory.mkdir(parents=True, exist_ok=True)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-sound-resource-")
            cls.addClassCleanup(cls.temporary.cleanup)
            cls.directory = Path(cls.temporary.name).resolve()
        cls.ffmpeg = shutil.which("ffmpeg")
        pcm = io.BytesIO()
        with wave.open(pcm, "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(8_000)
            stream.writeframes(b"\0\0" * 2400)
        (cls.directory / "package-lifetime-fixture.pkg").write_bytes(make_package([
            ("scene.json", b'{"version":3,"objects":[]}'),
            ("sounds/owned.wav", pcm.getvalue()),
        ]))
        pcm = io.BytesIO()
        with wave.open(pcm, "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(8_000)
            stream.writeframes(b"\0\0" * 80_000)
        (cls.directory / "weak-package-fixture.pkg").write_bytes(make_package([
            ("sounds/owned.wav", pcm.getvalue()), ("sounds/peer.wav", pcm.getvalue()),
        ]))
        cls.inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (*SOURCES, Path(__file__), Path(__file__).with_name("test_scene_sound_playback_program.py"),
                                Path(__file__).with_name("scene_pkg_fixture.py"))}
        carrier, harness = cls.directory / "Carriers.swift", cls.directory / "Harness.swift"
        carrier.write_text(CARRIERS)
        harness.write_text(HARNESS)
        cls.binary = cls.directory / "sound-resources"
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, SOURCES), str(carrier), str(harness),
                   "-module-cache-path", str(cls.directory / "module-cache"), "-o", str(cls.binary)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (cls.directory / "compile.log").write_text(result.stdout + result.stderr)
        (cls.directory / "identity.json").write_text(json.dumps({"inputs": cls.inputs, "command": command,
            "boundary": "real Root/private file/Program/Registry; generated silent WAV; no App or speaker PCM"}, indent=2))
        if result.returncode:
            raise RuntimeError(result.stderr)
        fault = cls.directory / "write-failure.c"
        fault.write_text(WRITE_FAILURE)
        cls.fault_library = cls.directory / "write-failure.dylib"
        compiled = subprocess.run(["xcrun", "clang", "-dynamiclib", str(fault), "-o", str(cls.fault_library)],
                                  capture_output=True, text=True, timeout=60)
        (cls.directory / "fault-compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)

    @classmethod
    def prepare_encoded(cls):
        if cls.ffmpeg:
            encoded = cls.directory / "encoded"
            encoded.mkdir()
            wav = encoded / "silent.wav"
            with wave.open(str(wav), "wb") as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(44100)
                stream.writeframes(b"\0\0" * 13230)
            commands = []
            for ext, codec in (("mp3", "libmp3lame"), ("flac", "flac")):
                command = [cls.ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                           "-i", str(wav), "-c:a", codec, str(encoded / ("silent." + ext))]
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                (encoded / (ext + ".log")).write_text(result.stdout + result.stderr)
                if result.returncode:
                    raise RuntimeError(result.stderr)
                commands.append(command)
            (encoded / "identity.json").write_text(json.dumps({"commands": commands,
                "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in encoded.iterdir() if p.suffix in (".wav", ".mp3", ".flac")},
                "scope": "self-generated silent PCM encoded locally; no user media or speaker capture"}, indent=2))

    def run_mode(self, mode):
        directory = self.directory / mode
        directory.mkdir()
        env = os.environ.copy()
        home = directory / "home"
        home.mkdir()
        env.update(HOME=str(home), CFFIXED_USER_HOME=str(home))
        if mode == "write-failure":
            env["DYLD_INSERT_LIBRARIES"] = str(self.fault_library)
            env["MWX_SOUND_FAIL_WRITE_ROOT"] = str(directory / "cache/.mywallpaperx-scene-video-payloads") + "/"
            env["MWX_SOUND_FAIL_WRITE_TRACE"] = str(directory / "write-attempts.txt")
        if mode.startswith("package-"):
            env["DYLD_INSERT_LIBRARIES"] = str(self.fault_library)
            env["MWX_SOUND_IO_ROOT"] = str(directory) + "/"
        completed = subprocess.run([str(self.binary), mode, str(directory), str(self.directory)], env=env,
                                   capture_output=True, text=True, timeout=60)
        (directory / "stdout.json").write_text(completed.stdout)
        (directory / "stderr.log").write_text(completed.stderr)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(self.inputs, {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in self.inputs})
        facts = json.loads(completed.stdout)
        self.assertTrue(facts)
        for key, value in facts.items():
            self.assertIs(value, True, f"{mode}/{key}: {facts}")
        return directory

    def test_selected_root_raw_name_suffix_and_same_launch_source_dedup(self):
        self.run_mode("selection")

    def test_selected_missing_keeps_slot_and_does_not_try_other_root_or_path(self):
        self.run_mode("unavailable")

    def test_original_cancel_and_callback_error_clean_partial(self):
        self.run_mode("cancel")
        self.run_mode("callback")

    def test_midstream_source_replacement_and_truncation_preserve_hard_error(self):
        self.run_mode("replace")
        self.run_mode("truncate")

    def test_root_retarget_and_raw_selected_escape_never_publish_file(self):
        self.run_mode("retarget")

    def test_real_partial_write_failure_cleans_and_retains_unavailable_slot(self):
        directory = self.run_mode("write-failure")
        self.assertGreaterEqual(int((directory / "write-attempts.txt").read_text()), 2)

    def test_real_av_uses_private_source_and_pins_actual_looper_asset(self):
        self.run_mode("native")

    def test_generated_mp3_flac_private_assets_keep_real_codec_playback(self):
        if not self.ffmpeg:
            self.skipTest("ffmpeg required only for self-generated MP3/FLAC native codec check")
        self.prepare_encoded()
        self.run_mode("native-codecs")

    def test_package_remount_and_retired_cache_pollution_preserve_actual_av_private_lease(self):
        directory = self.run_mode("root-lifetime")
        facts = json.loads((directory / "stdout.json").read_text())
        required = {"actualPrivateAVAssetReady", "borrowerUsesPrivateLease",
            "independentPackageMountReusesCompletedFile", "retiredCachePollutionDoesNotChangePackageBytes",
            "retiredCachePollutionKeepsBorrowedPrivateBytes", "actualBorrowerAloneStillPinsPrivateFile",
            "finalBorrowerUnlinksPrivateFile"}
        required.update(kind + suffix for kind in ("failed", "missing") for suffix in (
            "PackageUnavailableKeepsActualLooseSelection", "LooseSnapshotUsesPrivateCacheOutsideAuthor",
            "LooseAuthorNamespaceUnchanged"))
        self.assertTrue(required.issubset(facts), facts)

    def test_package_success_reuses_across_programs_and_actual_asset_borrower(self):
        self.run_mode("package-reuse")

    def test_package_hit_rechecks_source_cancellation_and_private_output_revision(self):
        self.run_mode("package-failures")

    def test_package_identity_output_domain_suffix_and_budget_partition_reuse(self):
        self.run_mode("package-partitions")

    def test_package_failed_write_and_partial_cancel_are_not_cached(self):
        self.run_mode("package-retry")

    def test_completed_package_snapshot_survives_later_write_but_active_read_does_not(self):
        directory = self.run_mode("package-snapshot-boundaries")
        facts = json.loads((directory / "stdout.json").read_text())
        required = {"readInProgressStillRejectsChangedPackage", "completedCopyStillPropagatesOriginalCancellation"}
        required.update(mode + suffix for mode in ("completed-copy", "completed-hit") for suffix in (
            "KeepsCapturedBytesAfterAuthorWrite", "NextOldHandleStillRejectsBeforePayload",
            "NewRequestUsesNewRevisionAndBytes"))
        self.assertTrue(required.issubset(facts), facts)
