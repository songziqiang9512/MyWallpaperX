#!/usr/bin/env python3
"""Compile the real native Music adapter and exercise its event/transaction functions."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMusicPlayerSource.swift"
PALETTE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaArtworkPalette.swift"
SDEF = Path("/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef")

HARNESS = r'''
import Carbon
import CoreGraphics
import Foundation
import ImageIO

typealias Failure = SceneMusicPlayerSource.Failure

@main
nonisolated struct MusicSourceHarness {
    static func main() {
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            do { try cpu() }
            catch { fatalError("CPU transaction failed: \(error)") }
            completed.signal()
        }
        precondition(completed.wait(timeout: .now() + 12) == .success)
    }

    static func printJSON(_ value: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func ownedPNG(_ color: [UInt8]) -> Data {
        precondition(color.count == 3)
        let pixels = Data((0..<16).flatMap { _ in color + [255] })
        let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    static func cpu() throws {
        var checks = 0
        func check(_ value: Bool) {
            precondition(value)
            checks += 1
        }
        func reject(_ expected: Failure, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("expected failure") }
            catch let error as Failure { check(error == expected) }
            catch { preconditionFailure("unexpected failure: \(error)") }
        }
        let codec = SceneMusicPlayerSource.Codec.self
        check(SceneMusicPlayerSource.silentAuthorization(pid: 0) == .unavailable(.invalidPID))
        if case .failure(.invalidPID) = SceneMusicPlayerSource.read(pid: 0) { check(true) }
        else { preconditionFailure("invalid PID must fail without a native query") }
        let track = try codec.property(codec.currentTrack)
        let title = try codec.property(codec.title, container: track)
        check(title.descriptorType == typeObjectSpecifier)
        check(title.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue == typeProperty)
        check(title.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue == OSType(formPropertyID))
        check(title.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == codec.title)
        check(title.forKeyword(AEKeyword(keyAEContainer))?.descriptorType == typeObjectSpecifier)
        let artwork = try codec.firstArtwork(in: track)
        check(artwork.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue == codec.artworkClass)
        check(artwork.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue == OSType(formAbsolutePosition))
        check(artwork.forKeyword(AEKeyword(keyAEKeyData))?.int32Value == 1)
        let request = codec.request(title, target: NSAppleEventDescriptor(processIdentifier: 123))
        check(request.eventClass == kAECoreSuite && request.eventID == kAEGetData)
        check(request.paramDescriptor(forKeyword: keyDirectObject)?.descriptorType == typeObjectSpecifier)
        check((SceneMusicPlayerSource.sendOptions.rawValue & UInt(kAEDoNotPromptForUserConsent)) != 0)
        check((SceneMusicPlayerSource.sendOptions.rawValue & UInt(kAENeverInteract)) != 0)
        check((SceneMusicPlayerSource.sendOptions.rawValue & UInt(kAECanSwitchLayer)) == 0)
        check(codec.isMissing(.null()))
        check(codec.isMissing(NSAppleEventDescriptor(typeCode: codec.code("msng"))))
        check(!codec.isMissing(NSAppleEventDescriptor(string: "")))
        check(try codec.text(NSAppleEventDescriptor(string: "歌曲"), phase: "title") == "歌曲")
        for value in ["bad\nvalue", String(repeating: "x", count: 4097)] {
            reject(.malformed(phase: "title")) { _ = try codec.text(NSAppleEventDescriptor(string: value), phase: "title") }
        }
        reject(.malformed(phase: "title")) { _ = try codec.text(NSAppleEventDescriptor(int32: 1), phase: "title") }
        check(try codec.trackID(NSAppleEventDescriptor(string: "0123ABCdef"), phase: "id") == "0123ABCdef")
        for value in ["", "NotHex", String(repeating: "A", count: 65)] {
            reject(.malformed(phase: "id")) { _ = try codec.trackID(NSAppleEventDescriptor(string: value), phase: "id") }
        }
        for (code, state) in [("kPSS", "stopped"), ("kPSP", "playing"), ("kPSp", "paused"),
                              ("kPSF", "fastForwarding"), ("kPSR", "rewinding")] {
            check(try codec.playback(NSAppleEventDescriptor(enumCode: codec.code(code))).rawValue == state)
        }
        reject(.malformed(phase: "playerState")) { _ = try codec.playback(NSAppleEventDescriptor(enumCode: codec.code("????"))) }
        check(try codec.nonnegativeReal(NSAppleEventDescriptor(double: 42.5), phase: "position") == 42.5)
        check(try codec.nonnegativeReal(NSAppleEventDescriptor(int32: 0), phase: "position") == 0)
        for value in [-1.0, Double.nan, Double.infinity] {
            reject(.malformed(phase: "position")) { _ = try codec.nonnegativeReal(NSAppleEventDescriptor(double: value), phase: "position") }
        }
        reject(.malformed(phase: "position")) { _ = try codec.nonnegativeReal(NSAppleEventDescriptor(string: "0"), phase: "position") }
        let data = Data([1, 2, 3])
        check(try codec.artwork(NSAppleEventDescriptor(descriptorType: typeData, data: data)!) == data)
        check(try codec.artwork(.null()) == nil)
        reject(.malformed(phase: "artwork")) { _ = try codec.artwork(.record()) }
        reject(.malformed(phase: "artwork.byteBudget")) {
            _ = try codec.artwork(NSAppleEventDescriptor(descriptorType: typeData, data: Data(count: codec.maximumArtworkBytes + 1))!)
        }
        try codec.requireSameTrack("A", "A")
        reject(.changedTrack) { try codec.requireSameTrack("A", "B") }
        let reply = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEAnswer), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reply.setParam(NSAppleEventDescriptor(int32: Int32(errAEEventNotPermitted)), forKeyword: keyErrorNumber)
        reject(.permissionBlocked(status: Int32(errAEEventNotPermitted), phase: "title")) { _ = try codec.replyValue(reply, phase: "title") }
        check(Failure.appleEventStatus(Int32(errAEEventWouldRequireUserConsent), phase: "preflight") == .permissionBlocked(status: Int32(errAEEventWouldRequireUserConsent), phase: "preflight"))
        check(Failure.appleEventStatus(Int32(errAETimeout), phase: "title") == .timeout(phase: "title"))
        check(Failure.appleEventStatus(Int32(errAENoSuchObject), phase: "currentTrack.before") == .appleEvent(status: Int32(errAENoSuchObject), phase: "currentTrack.before"))

        let good: [String: NSAppleEventDescriptor] = [
            "currentTrack.before": track, "persistentID.before": NSAppleEventDescriptor(string: "AA11"),
            "title": NSAppleEventDescriptor(string: "Owned Track"), "artist": NSAppleEventDescriptor(string: "Owned Artist"),
            "album": NSAppleEventDescriptor(string: "Owned Album"), "duration": NSAppleEventDescriptor(double: 120),
            "playerState": NSAppleEventDescriptor(enumCode: codec.code("kPSP")), "position": NSAppleEventDescriptor(double: 130),
            "artwork": .null(), "currentTrack.after": track, "persistentID.after": NSAppleEventDescriptor(string: "AA11"),
        ]
        var order: [String] = []
        let result = try SceneMusicPlayerSource.Transaction.read(pid: 123) { object, phase in
            check(object.descriptorType == typeObjectSpecifier)
            order.append(phase)
            return good[phase]!
        }
        if case .snapshot(let value) = result {
            check(value.title == "Owned Track" && value.artist == "Owned Artist" && value.album == "Owned Album")
            check(value.identity == "com.apple.Music:123:AA11" && value.artworkData == nil && value.state == .playing)
            check(value.position == 130 && value.duration == 120)
        } else { preconditionFailure("expected track") }
        check(order.first == "currentTrack.before" && order.last == "persistentID.after" && order.count == 11)
        reject(.changedTrack) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                phase == "persistentID.after" ? NSAppleEventDescriptor(string: "BB22") : good[phase]!
            }
        }
        let noArt = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
            if phase == "artwork" { throw Failure.appleEvent(status: Int32(errAENoSuchObject), phase: phase) }
            return good[phase]!
        }
        if case .snapshot(let value) = noArt { check(value.artworkData == nil) }
        else { preconditionFailure("expected track without artwork") }
        reject(.permissionBlocked(status: Int32(errAEEventNotPermitted), phase: "artwork")) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                if phase == "artwork" { throw Failure.permissionBlocked(status: Int32(errAEEventNotPermitted), phase: phase) }
                return good[phase]!
            }
        }
        let empty = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
            phase == "playerState" ? NSAppleEventDescriptor(enumCode: codec.code("kPSS")) : .null()
        }
        if case .noSession = empty { check(true) }
        else { preconditionFailure("expected explicit no session") }
        reject(.changedTrack) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                if phase == "currentTrack.after" { return track }
                return phase == "playerState" ? NSAppleEventDescriptor(enumCode: codec.code("kPSS")) : .null()
            }
        }
        reject(.appleEvent(status: Int32(errAENoSuchObject), phase: "currentTrack.before")) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                throw Failure.appleEvent(status: Int32(errAENoSuchObject), phase: phase)
            }
        }
        for (state, value) in [(SceneMusicPlayerSource.PlaybackState.stopped, 0),
                               (.playing, 1), (.paused, 2), (.fastForwarding, 1), (.rewinding, 1)] {
            check(state.inboxValue == value)
        }
        let successReply = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEAnswer), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        successReply.setParam(NSAppleEventDescriptor(string: "Owned"), forKeyword: keyDirectObject)
        check(try codec.text(codec.replyValue(successReply, phase: "title"), phase: "title") == "Owned")
        let invalidReply = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEAnswer), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        reject(.malformed(phase: "title.missingReply")) { _ = try codec.replyValue(invalidReply, phase: "title") }
        invalidReply.setParam(NSAppleEventDescriptor(string: "0"), forKeyword: keyErrorNumber)
        reject(.malformed(phase: "title.errorNumber")) { _ = try codec.replyValue(invalidReply, phase: "title") }
        var artCalls = 0
        let redPNG = ownedPNG([255, 0, 0]), bluePNG = ownedPNG([0, 0, 255])
        let redPalette = SceneMediaArtworkPalette.extract(from: redPNG)!
        let bluePalette = SceneMediaArtworkPalette.extract(from: bluePNG)!
        func checkFiveColors(_ palette: SceneMediaArtworkPalette) {
            for color in [palette.primaryColor, palette.secondaryColor, palette.tertiaryColor,
                          palette.textColor, palette.highContrastColor] {
                check((0..<3).allSatisfy { color[$0].isFinite && (0...1).contains(color[$0]) })
            }
        }
        checkFiveColors(redPalette)
        checkFiveColors(bluePalette)
        check(redPalette.primaryColor == SIMD3<Double>(1, 0, 0))
        check(redPalette.textColor == .zero && redPalette.highContrastColor == .zero)
        check(bluePalette.primaryColor == SIMD3<Double>(0, 0, 1))
        check(bluePalette.textColor == SIMD3<Double>(repeating: 1)
            && bluePalette.highContrastColor == SIMD3<Double>(repeating: 1))
        let freshPNG = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
            phase == "artwork" ? NSAppleEventDescriptor(descriptorType: typeData, data: redPNG)! : good[phase]!
        }
        if case .snapshot(let value) = freshPNG {
            check(value.artworkData == redPNG && value.artworkPalette == redPalette)
            check(value.title == "Owned Track" && value.artworkFailure == nil)
        } else { preconditionFailure("fresh image must carry five colors") }
        // Deliberately pass a differently colored cached palette. Returning it
        // proves a same-track cache hit does not extract from the bytes again.
        let cachedPNG = try SceneMusicPlayerSource.Transaction.read(pid: 123,
            cachedArtworkIdentity: "com.apple.Music:123:AA11", cachedArtworkData: redPNG,
            cachedArtworkPalette: bluePalette) { _, phase in
            if phase == "artwork" { artCalls += 1 }
            return good[phase]!
        }
        if case .snapshot(let value) = cachedPNG {
            check(value.artworkData == redPNG && value.artworkPalette == bluePalette && artCalls == 0)
        } else { preconditionFailure("expected cached image palette") }
        for identity in ["com.apple.Music:999:AA11", "com.apple.Music:123:BB22"] {
            artCalls = 0
            let newTrack = try SceneMusicPlayerSource.Transaction.read(pid: 123,
                cachedArtworkIdentity: identity, cachedArtworkData: redPNG,
                cachedArtworkPalette: redPalette) { _, phase in
                if phase == "artwork" { artCalls += 1; return NSAppleEventDescriptor(descriptorType: typeData, data: bluePNG)! }
                return good[phase]!
            }
            if case .snapshot(let value) = newTrack {
                check(value.artworkData == bluePNG && value.artworkPalette == bluePalette && artCalls == 1)
            } else { preconditionFailure("new identity must extract the new image") }
        }
        artCalls = 0
        let cacheBytes = Data([7, 8, 9])
        let cacheHit = try SceneMusicPlayerSource.Transaction.read(pid: 123,
            cachedArtworkIdentity: "com.apple.Music:123:AA11", cachedArtworkData: cacheBytes) { _, phase in
            if phase == "artwork" { artCalls += 1 }
            return good[phase]!
        }
        if case .snapshot(let value) = cacheHit {
            check(value.artworkData == cacheBytes && value.artworkFailure == nil && artCalls == 0)
            check(value.artworkPalette == nil)
        } else { preconditionFailure("expected cached track") }
        for (identity, bytes) in [("com.apple.Music:999:AA11", Optional(cacheBytes)),
                                  ("com.apple.Music:123:BB22", Optional(cacheBytes)),
                                  ("com.apple.Music:123:AA11", nil),
                                  ("com.apple.Music:123:AA11", Optional(Data()))] {
            artCalls = 0
            let result = try SceneMusicPlayerSource.Transaction.read(pid: 123,
                cachedArtworkIdentity: identity, cachedArtworkData: bytes) { _, phase in
                if phase == "artwork" { artCalls += 1 }
                return good[phase]!
            }
            if case .snapshot(let value) = result { check(value.artworkData == nil && artCalls == 1) }
            else { preconditionFailure("expected fresh art read") }
        }
        reject(.changedTrack) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123,
                cachedArtworkIdentity: "com.apple.Music:123:AA11", cachedArtworkData: cacheBytes) { _, phase in
                phase == "persistentID.after" ? NSAppleEventDescriptor(string: "BB22") : good[phase]!
            }
        }
        let oversize = NSAppleEventDescriptor(descriptorType: typeData,
            data: Data(count: codec.maximumArtworkBytes + 1))!
        for (art, issue) in [(oversize, Failure.malformed(phase: "artwork.byteBudget")),
                             (NSAppleEventDescriptor.record(), Failure.malformed(phase: "artwork"))] {
            let result = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                phase == "artwork" ? art : good[phase]!
            }
            if case .snapshot(let value) = result {
                check(value.artworkData == nil && value.artworkFailure == issue && value.title == "Owned Track")
                check(value.artworkPalette == nil)
            } else { preconditionFailure("art failure must stay local") }
        }
        let badImage = try SceneMusicPlayerSource.Transaction.read(pid: 123,
            cachedArtworkIdentity: "com.apple.Music:123:BB22", cachedArtworkData: redPNG,
            cachedArtworkPalette: redPalette) { _, phase in
            phase == "artwork" ? NSAppleEventDescriptor(descriptorType: typeData, data: cacheBytes)! : good[phase]!
        }
        if case .snapshot(let value) = badImage {
            check(value.title == "Owned Track" && value.artist == "Owned Artist")
            check(value.artworkData == cacheBytes && value.artworkPalette == nil)
        } else { preconditionFailure("bad image must not discard metadata or inherit old colors") }
        reject(.malformed(phase: "title")) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                phase == "title" ? NSAppleEventDescriptor(string: String(repeating: "x", count: 4097)) : good[phase]!
            }
        }
        reject(.timeout(phase: "duration")) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                if phase == "duration" { throw Failure.timeout(phase: phase) }
                return good[phase]!
            }
        }
        reject(.changedTrack) {
            _ = try SceneMusicPlayerSource.Transaction.read(pid: 123) { _, phase in
                phase == "currentTrack.after" ? .null() : good[phase]!
            }
        }
        let selectors = ["currentTrack": codec.currentTrack, "persistentID": codec.persistentID,
            "title": codec.title, "artist": codec.artist, "album": codec.album,
            "duration": codec.duration, "playerState": codec.playerState,
            "position": codec.position, "rawData": codec.rawData, "artworkClass": codec.artworkClass]
        printJSON(["result": "PASS", "checks": checks, "nativeQueries": 0, "workerThread": !Thread.isMainThread,
                   "perEventTimeout": SceneMusicPlayerSource.perEventTimeout,
                   "overallTimeout": SceneMusicPlayerSource.overallTimeout, "selectors": selectors])
    }
}
'''


class SceneMusicPlayerSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-music-source-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        harness = root / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "music-source"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compiled = subprocess.run([
            "swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
            "-module-cache-path", str(root / "swift-cache"), str(PALETTE), str(SOURCE), str(harness),
            "-o", str(binary),
        ], capture_output=True, text=True, env=environment, cwd=ROOT)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        executed = subprocess.run([str(binary)], capture_output=True, text=True, check=True, timeout=15)
        cls.result = json.loads(executed.stdout)

    def test_real_event_specifiers_decoders_and_consistent_transaction(self):
        self.assertEqual(self.result["result"], "PASS")
        self.assertGreaterEqual(self.result["checks"], 80)
        self.assertEqual(self.result["nativeQueries"], 0)
        self.assertTrue(self.result["workerThread"])
        self.assertEqual(self.result["perEventTimeout"], 0.2)
        self.assertEqual(self.result["overallTimeout"], 2)

    def test_selector_values_match_installed_public_music_dictionary(self):
        if not SDEF.is_file():
            self.skipTest("Music's public scripting dictionary is unavailable")
        tree = ET.parse(SDEF)
        selectors = {
            "currentTrack": ("application", "current track"),
            "persistentID": ("item", "persistent ID"),
            "title": ("item", "name"), "artist": ("track", "artist"),
            "album": ("track", "album"), "duration": ("track", "duration"),
            "playerState": ("application", "player state"),
            "position": ("application", "player position"),
            "rawData": ("artwork", "raw data"),
        }
        for key, (owner, name) in selectors.items():
            with self.subTest(selector=key):
                declaration = tree.find(f".//class[@name='{owner}']/property[@name='{name}']")
                self.assertIsNotNone(declaration)
                expected = int.from_bytes(declaration.attrib["code"].encode("ascii"), "big")
                self.assertEqual(self.result["selectors"][key], expected)
        artwork = tree.find(".//class[@name='artwork']")
        self.assertEqual(self.result["selectors"]["artworkClass"],
                         int.from_bytes(artwork.attrib["code"].encode("ascii"), "big"))


if __name__ == "__main__":
    unittest.main()
