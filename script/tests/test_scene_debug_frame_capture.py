#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneDebugFrameCapture.swift"
)

HARNESS_SOURCE = r'''
import AppKit
@preconcurrency import Metal

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            throw HarnessError.missingOutputDirectory
        }
        let outputDirectory = URL(
            fileURLWithPath: CommandLine.arguments.last!,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw HarnessError.metalUnavailable
        }

        let capture = SceneDebugFrameCapture()
        capture.request(reason: "ready", outputDirectory: outputDirectory)
        capture.request(reason: "after", outputDirectory: outputDirectory)
        try encodeFrame(capture: capture, device: device, queue: queue, value: 64)
        try encodeFrame(capture: capture, device: device, queue: queue, value: 192)

        for name in ["scene-ready-window.png", "scene-after-window.png"] {
            let path = outputDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw HarnessError.missingCapture(name)
            }
        }
    }

    private static func encodeFrame(
        capture: SceneDebugFrameCapture,
        device: MTLDevice,
        queue: MTLCommandQueue,
        value: UInt8
    ) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: 4 * 4
        )
        capture.encodeIfRequested(texture: texture, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status != .completed {
            throw HarnessError.commandFailed
        }
    }
}

enum HarnessError: Error {
    case missingOutputDirectory
    case metalUnavailable
    case commandFailed
    case missingCapture(String)
}
'''


class SceneDebugFrameCaptureTests(unittest.TestCase):
    def test_multiple_pending_requests_are_captured_in_order(self) -> None:
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
