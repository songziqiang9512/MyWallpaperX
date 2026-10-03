#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift"
)

HARNESS_SOURCE = r'''
import AppKit
import Darwin
@preconcurrency import Metal

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SceneDebugFrameCapture.Terminal] = []
    let delivered = DispatchSemaphore(value: 0)
    func append(_ event: SceneDebugFrameCapture.Terminal) {
        lock.lock(); values.append(event); lock.unlock(); delivered.signal()
    }
    var snapshot: [SceneDebugFrameCapture.Terminal] {
        lock.lock(); defer { lock.unlock() }; return values
    }
}
struct SceneResolvedMaterialFrameTargetPlan {}
final class SceneMetalRenderer {}
@main enum Harness {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func wait(_ event: DispatchSemaphore) {
        check(event.wait(timeout: .now() + 15) == .success, "event timed out")
    }
    static func drain(_ capture: SceneDebugFrameCapture) {
        let done = DispatchSemaphore(value: 0)
        capture.closeAndDrain { done.signal() }; wait(done)
    }
    static func waitForLeaseReturn(to baseline: Int) {
        let deadline = DispatchTime.now() + 5
        // Drain delivers terminal notifications; destruction of the dispatch
        // closure and its captured Metal buffer may follow that notification.
        // Check the real account, not elapsed sleep or another test attempt.
        while SceneResourceBudget.shared.snapshot.residentBytes != baseline {
            let remaining = SceneResourceBudget.shared.snapshot.residentBytes - baseline
            check(DispatchTime.now() < deadline,
                  "real buffer leases did not return: remaining bytes=\(remaining)")
            sched_yield()
        }
    }
    static func texture(_ device: MTLDevice, width: Int = 4, value: UInt8 = 64,
                        format: MTLPixelFormat = .bgra8Unorm) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        if format == .bgra8Unorm { fill(texture, value: value) }
        return texture
    }
    static func fill(_ texture: MTLTexture, value: UInt8) {
        var bytes = [UInt8](repeating: value, count: texture.width * texture.height * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        texture.replace(region: MTLRegionMake2D(0,0,texture.width,texture.height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: texture.width * 4)
    }
    static func encode(_ capture: SceneDebugFrameCapture, _ texture: MTLTexture, _ queue: MTLCommandQueue) {
        autoreleasepool {
            let command = queue.makeCommandBuffer()!
            capture.encodeIfRequested(texture: texture, commandBuffer: command)
            command.commit(); command.waitUntilCompleted()
            check(command.status == .completed && command.error == nil, "GPU failed")
        }
    }
    static func image(_ dir: URL, _ reason: String) throws -> NSBitmapImageRep {
        let url = dir.appendingPathComponent("scene-\(reason)-window.png")
        return NSBitmapImageRep(data: try Data(contentsOf: url))!
    }
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
        let baseline = SceneResourceBudget.shared.snapshot.residentBytes
        try autoreleasepool {
            // Required FIFO, original wide-row case, 16-bit gradient and alpha.
            let events = Events()
            let capture = SceneDebugFrameCapture(observeTerminal: { events.append($0) })
            capture.request(reason: "ready", outputDirectory: dir)
            capture.request(reason: "after", outputDirectory: dir)
            encode(capture, texture(device), queue); wait(events.delivered)
            encode(capture, texture(device, width: 1304, value: 192), queue); wait(events.delivered)
            let readyImage = try image(dir, "ready")
            check(readyImage.pixelsWide == 4, "ready size")
            let afterImage = try image(dir, "after")
            check(afterImage.pixelsWide == 1304, "after size")
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1024, height: 1, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.shaderRead]
            let gradient = device.makeTexture(descriptor: descriptor)!
            var words = [UInt16](repeating: 0, count: 4096)
            for x in 0..<1024 {
                let value = Float16(Float(x) / 1023).bitPattern
                words[x*4] = value; words[x*4+1] = value; words[x*4+2] = value; words[x*4+3] = Float16(1).bitPattern
            }
            words.withUnsafeBytes { gradient.replace(region: MTLRegionMake2D(0,0,1024,1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 8192) }
            capture.request(reason: "float", outputDirectory: dir)
            encode(capture, gradient, queue); drain(capture)
            let rep = try image(dir, "float")
            check(rep.bitsPerSample == 16 && rep.pixelsWide == 1024, "16 bit output")
            var distinct = Set<Int>()
            for x in 0..<1024 {
                var pixel = [Int](repeating: 0, count: 4); rep.getPixel(&pixel, atX: x, y: 0)
                distinct.insert(pixel[0]); check(pixel[3] == 65535, "float alpha")
            }
            check(distinct.count == 1024, "gradient precision")
        }
        try autoreleasepool {
            // Two global work slots across three independent surfaces. Blocking
            // export must not block this command's or the next command's handlers.
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let firstEvents = Events(), secondEvents = Events(), thirdEvents = Events()
            let first = SceneDebugFrameCapture(beforeExport: { entered.signal(); release.wait() }, observeTerminal: { firstEvents.append($0) })
            let second = SceneDebugFrameCapture(observeTerminal: { secondEvents.append($0) })
            let third = SceneDebugFrameCapture(observeTerminal: { thirdEvents.append($0) })
            let original = texture(device)
            first.request(reason: "independent", outputDirectory: dir)
            encode(first, original, queue); wait(entered)
            fill(original, value: 192)
            second.request(reason: "second", outputDirectory: dir)
            encode(second, texture(device), queue)
            let occupied = SceneResourceBudget.shared.snapshot.residentBytes
            let size = device.heapBufferSizeAndAlign(length: 4*4*4, options: .storageModeShared).size
            check(occupied == baseline + 2*size, "global two buffers must be accounted")
            third.request(reason: "third-pending", outputDirectory: dir)
            encode(third, texture(device), queue)
            check(SceneResourceBudget.shared.snapshot.residentBytes == occupied, "third capture allocated beyond global bound")
            let firstDrain = DispatchSemaphore(value: 0), secondDrain = DispatchSemaphore(value: 0)
            first.closeAndDrain { firstDrain.signal() }; second.closeAndDrain { secondDrain.signal() }
            check(firstDrain.wait(timeout: .now()) == .timedOut && secondDrain.wait(timeout: .now()) == .timedOut, "drain crossed outstanding export")
            drain(third)
            check(thirdEvents.snapshot.count == 1 && thirdEvents.snapshot[0].failure == "teardown", "pending third must terminate")
            release.signal(); wait(firstDrain); wait(secondDrain)
            let rep = try image(dir, "independent")
            var pixel = [Int](repeating: 0, count: 4); rep.getPixel(&pixel, atX: 0, y: 0)
            check(abs(pixel[0] - 64) <= 1 && pixel[3] == 255, "export read reused texture instead of snapshot")
            check(firstEvents.snapshot.count == 1 && secondEvents.snapshot.count == 1, "duplicate terminal")
            drain(first); drain(second)
            check(firstEvents.snapshot.count == 1, "repeated drain repeated terminal")
        }
        autoreleasepool {
            // GPU terminal with the earlier completion handler deliberately held:
            // capture's own completion has not even handed off to the CPU lane.
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0), events = Events()
            let capture = SceneDebugFrameCapture(observeTerminal: { events.append($0) })
            capture.request(reason: "handoff-gap", outputDirectory: dir)
            let command = queue.makeCommandBuffer()!
            command.addCompletedHandler { _ in entered.signal(); release.wait() }
            capture.encodeIfRequested(texture: texture(device), commandBuffer: command)
            command.commit(); wait(entered)
            capture.closeAndDrain { done.signal() }
            check(done.wait(timeout: .now()) == .timedOut && events.snapshot.isEmpty,
                  "drain crossed GPU-complete/capture-handler gap")
            release.signal(); wait(done); command.waitUntilCompleted()
            check(events.snapshot.count == 1 && events.snapshot[0].failure == nil, "handoff gap lost terminal")
        }
        autoreleasepool {
            let events = Events(), capture = SceneDebugFrameCapture(observeTerminal: { _ in })
            drain(capture)
            check(capture.request(reason: "late", outputDirectory: dir) == .rejected("closed"), "closed accepted request")
            let bounded = SceneDebugFrameCapture(observeTerminal: { events.append($0) })
            bounded.request(reason: "one", outputDirectory: dir)
            bounded.request(reason: "two", outputDirectory: dir)
            check(bounded.request(reason: "three", outputDirectory: dir) == .rejected("required-pending-full"), "required overflow")
            for i in 0..<100 { bounded.request(reason: "periodic-\(i)", outputDirectory: dir, kind: .periodic) }
            check(events.snapshot.count == 99 && events.snapshot.allSatisfy { $0.failure == "superseded" }, "periodic replacement terminal")
            drain(bounded)
            check(events.snapshot.count == 102 && Set(events.snapshot.map(\.id)).count == 102, "accepted terminal not once")
            check(events.snapshot.filter { $0.failure == "teardown" }.count == 3, "pending limit not 2+1")
        }
        autoreleasepool {
            let events = Events(), capture = SceneDebugFrameCapture(observeTerminal: { _ in })
            drain(capture)
            let failed = SceneDebugFrameCapture(observeTerminal: { events.append($0) })
            failed.request(reason: "unsupported", outputDirectory: dir)
            encode(failed, texture(device, format: .r8Unorm), queue)
            failed.request(reason: "write-failed", outputDirectory: dir.appendingPathComponent("missing/parent"))
            encode(failed, texture(device), queue); drain(failed)
            check(events.snapshot.map(\.failure) == ["readback-format-or-size", "write"], "failed setup/write terminals")
        }
        autoreleasepool {
            let events = Events(), capture = SceneDebugFrameCapture(observeTerminal: { events.append($0) })
            let source = texture(device)
            let budget = SceneResourceBudget.shared
            let reserved = budget.maximumBytes - budget.snapshot.residentBytes
            check(budget.reserve(reserved, kind: .gpu), "budget test admission")
            capture.request(reason: "budget-failed", outputDirectory: dir)
            encode(capture, source, queue)
            budget.release(reserved, kind: .gpu)
            drain(capture)
            check(events.snapshot.count == 1 && events.snapshot[0].failure == "metal-readback-setup", "failed budget cleanup")
        }
        autoreleasepool {
            let events = Events()
            let exportEntered = DispatchSemaphore(value: 0), allowExport = DispatchSemaphore(value: 0)
            let drainNotified = DispatchSemaphore(value: 0), allowDrainReturn = DispatchSemaphore(value: 0)
            let capture = SceneDebugFrameCapture(
                beforeExport: { exportEntered.signal(); wait(allowExport) },
                observeTerminal: { events.append($0) }
            )
            let source = texture(device)
            capture.request(reason: "cancel", outputDirectory: dir)
            let cancelled = queue.makeCommandBuffer()!
            let candidate = SceneMetalRenderer.PreparedFrame(commandBuffer: cancelled, submit: {
                capture.encodeIfRequested(texture: source, commandBuffer: cancelled); cancelled.commit()
            }, cancel: {})
            candidate.cancel()
            check(SceneResourceBudget.shared.snapshot.residentBytes == baseline && events.snapshot.isEmpty, "cancel consumed or allocated")
            let next = queue.makeCommandBuffer()!
            let nextFrame = SceneMetalRenderer.PreparedFrame(commandBuffer: next, submit: {
                capture.encodeIfRequested(texture: source, commandBuffer: next); next.commit()
            }, cancel: {})
            check(SceneMetalRenderer.submitPreparedFrame(.prepared(nextFrame)).isSubmitted, "next submit")
            next.waitUntilCompleted(); wait(exportEntered)
            // Register while export is deliberately held, so this callback
            // runs from finish() inside the real export closure. Hold its
            // return to expose the notification-before-capture-release window.
            capture.closeAndDrain {
                drainNotified.signal()
                wait(allowDrainReturn)
            }
            allowExport.signal(); wait(drainNotified)
            check(events.snapshot.count == 1 && events.snapshot[0].failure == nil, "cancel lost pending request")
            check(SceneResourceBudget.shared.snapshot.residentBytes > baseline,
                  "controlled drain window did not retain its real buffer lease")
            allowDrainReturn.signal()
        }
        waitForLeaseReturn(to: baseline)
        print("PASS: completion-independent snapshot, global bounds, request terminals, errors, real leases, cancel, precision")
    }
}
'''


class SceneDebugFrameCaptureTests(unittest.TestCase):
    def test_capture_lifecycle_is_bounded_and_completion_independent(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-frame-capture-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS_SOURCE, encoding="utf-8")
            binary = directory / "scene-frame-capture"
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-D",
                    "DEBUG",
                    str(CAPTURE_SOURCE),
                    str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift"),
                    str(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift"),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            evidence = directory / "evidence"
            completed = subprocess.run(
                [
                    str(binary),
                    "--mwx-debug-scene-evidence-dir",
                    str(evidence),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertGreater((evidence / "scene-ready-window.png").stat().st_size, 0)
            self.assertGreater((evidence / "scene-after-window.png").stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
