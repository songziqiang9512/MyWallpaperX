#!/usr/bin/env python3
"""Depth Parallax slot-1 depth binding and atomic metadata admission."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneDepthParallaxEffectTextureLoader.swift",
]


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
}

struct SceneDepthParallaxExecutionPlan {
    let depthTexturePath: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
        }

        let id: String
        let file: String
        let passes: [PassDescriptor]
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

struct SceneTexturePathResolver {
    let urls: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urls[path]
    }
}

final class SceneTextureLoader {
    var candidate: SceneTextureCandidate?
    var lastLabel: String?
    var lastPurpose: SceneTextureLoadPurpose?
    var lastURL: URL?
}

struct SceneEffectTextureLoadResult {
    let candidate: SceneTextureCandidate?
    let message: String
}

enum SceneLayerEffectTextureLoader {
    static func loadTextureCandidate(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        loader.lastURL = url
        loader.lastLabel = label
        loader.lastPurpose = purpose
        return .init(
            candidate: url == nil ? nil : loader.candidate,
            message: url == nil ? "" : "; \(label) fixture"
        )
    }
}

@main
enum Harness {
    static let effectID = "85#effect#930"
    static let depthPath = "materials/depth_map"

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .r8Unorm,
        width: Int = 8,
        height: Int = 8
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        return device.makeTexture(descriptor: descriptor)!
    }

    static func candidate(
        device: MTLDevice,
        format: MTLPixelFormat = .r8Unorm,
        purpose: SceneTextureLoadPurpose = .depth,
        physical: CGSize = CGSize(width: 8, height: 8),
        mapped: CGSize = CGSize(width: 6, height: 4),
        transform: SceneTextureUVTransform = .init(
            origin: .zero,
            xAxis: SIMD2(0.75, 0),
            yAxis: SIMD2(0, 0.5)
        ),
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneTextureCandidate {
        .init(
            texture: texture(
                device: device,
                format: format,
                width: Int(physical.width),
                height: Int(physical.height)
            ),
            identity: .file(path: "/fixture/depth.tex"),
            generation: .immutable(revision: 42),
            purpose: purpose,
            physicalSize: physical,
            mappedSize: mapped,
            uvTransform: transform,
            sampling: sampling
        )
    }

    static func binding(
        device: MTLDevice,
        slot: Int = 1,
        format: MTLPixelFormat = .r8Unorm,
        purpose: SceneTextureLoadPurpose = .depth,
        physical: CGSize = CGSize(width: 8, height: 8),
        mapped: CGSize = CGSize(width: 6, height: 4),
        transform: SceneTextureUVTransform = .init(
            origin: .zero,
            xAxis: SIMD2(0.75, 0),
            yAxis: SIMD2(0, 0.5)
        ),
        sampling: SceneTextureSampling = .linearClamp
    ) -> SceneTextureSlotBinding? {
        SceneTextureSlotBinding(
            slotIndex: slot,
            candidate: candidate(
                device: device,
                format: format,
                purpose: purpose,
                physical: physical,
                mapped: mapped,
                transform: transform,
                sampling: sampling
            )
        )
    }

    static func resources(
        _ binding: SceneTextureSlotBinding?,
        path: String = depthPath
    ) -> SceneDepthParallaxEffectTextures {
        .init(depthBinding: binding, depthPath: path)
    }

    static func layer(
        file: String = "effects/depthparallax/effect.json",
        passCount: Int = 1,
        slots: [String?] = [nil, depthPath]
    ) -> SceneRenderDescriptor.Layer {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            textureSlots: slots
        )
        return .init(effects: [.init(
            id: effectID,
            file: file,
            passes: Array(repeating: pass, count: passCount)
        )])
    }

    static func generationIsPreserved(
        _ arguments: SceneDepthParallaxEffectTextures.ResolvedArguments?
    ) -> Bool {
        guard let arguments else { return false }
        guard case .immutable(let revision) = arguments.depth.generation,
              revision == 42,
              case .file(let path) = arguments.depth.identity else {
            return false
        }
        return path == "/fixture/depth.tex"
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print(#"{"available":false}"#)
            return
        }

        let fileURL = URL(fileURLWithPath: "/fixture/depth.tex")
        let loader = SceneTextureLoader()
        loader.candidate = candidate(device: device)
        let loaded = SceneDepthParallaxEffectTextureLoader.load(
            for: layer(),
            effectIDs: [effectID],
            resolver: .init(urls: [depthPath: fileURL]),
            loader: loader,
            device: device
        )
        let plan = SceneDepthParallaxExecutionPlan(
            depthTexturePath: depthPath
        )
        let arguments = loaded.textures[effectID]?.resolvedArguments(for: plan)

        let missingLoader = SceneTextureLoader()
        let missing = SceneDepthParallaxEffectTextureLoader.load(
            for: layer(),
            effectIDs: [effectID],
            resolver: .init(urls: [:]),
            loader: missingLoader,
            device: device
        )
        let ignoredFile = SceneDepthParallaxEffectTextureLoader.load(
            for: layer(file: "effects/other/effect.json"),
            effectIDs: [effectID],
            resolver: .init(urls: [depthPath: fileURL]),
            loader: SceneTextureLoader(),
            device: device
        )
        let ignoredPasses = SceneDepthParallaxEffectTextureLoader.load(
            for: layer(passCount: 2),
            effectIDs: [effectID],
            resolver: .init(urls: [depthPath: fileURL]),
            loader: SceneTextureLoader(),
            device: device
        )
        let ignoredSlots = SceneDepthParallaxEffectTextureLoader.load(
            for: layer(slots: [depthPath]),
            effectIDs: [effectID],
            resolver: .init(urls: [depthPath: fileURL]),
            loader: SceneTextureLoader(),
            device: device
        )

        let wrongPath = resources(
            binding(device: device),
            path: "materials/other"
        )
        let wrongSlot = resources(binding(device: device, slot: 0))
        let wrongPurpose = resources(binding(
            device: device,
            purpose: .mask
        ))
        let wrongFormat = resources(binding(
            device: device,
            format: .bgra8Unorm
        ))
        let rotated = resources(binding(
            device: device,
            transform: .init(
                origin: .zero,
                xAxis: SIMD2(0, 0.75),
                yAxis: SIMD2(-0.5, 0)
            )
        ))
        let translated = resources(binding(
            device: device,
            transform: .init(
                origin: SIMD2(0.1, 0),
                xAxis: SIMD2(0.75, 0),
                yAxis: SIMD2(0, 0.5)
            )
        ))
        let clampBorder = resources(binding(
            device: device,
            sampling: SceneTextureSampling(texFlags: 8)
        ))
        let invalidMapped = resources(binding(
            device: device,
            mapped: CGSize(width: 9, height: 4),
            transform: .identity
        ))

        let result: [String: Any] = [
            "available": true,
            "loaderUsedDepthPurpose": loader.lastPurpose == .depth,
            "loaderUsedSlotPath": loader.lastURL == fileURL
                && loader.lastLabel == "depthparallax depth",
            "loaderStoredBinding": arguments != nil,
            "mappedScalePreserved": arguments.map {
                abs($0.depthUVScale.x - 0.75) < 0.000_001
                    && abs($0.depthUVScale.y - 0.5) < 0.000_001
            } ?? false,
            "generationPreserved": generationIsPreserved(arguments),
            "samplingPreserved": arguments?.depth.sampling == .linearClamp,
            "messageReported": loaded.message.contains(
                "depthparallax depth fixture"
            ),
            "missingStayedFailed": missing.textures[effectID]?
                .resolvedArguments(for: plan) == nil,
            "missingReported": missing.message.contains(
                "depthparallax depth missing \(depthPath)"
            ),
            "shapeRejected": ignoredFile.textures.isEmpty
                && ignoredPasses.textures.isEmpty
                && ignoredSlots.textures.isEmpty,
            "atomicGatesRejected": [
                wrongPath, wrongSlot, wrongPurpose, wrongFormat, rotated,
                translated, clampBorder, invalidMapped,
            ].allSatisfy { $0.resolvedArguments(for: plan) == nil },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneDepthParallaxEffectTextureLoaderTests(unittest.TestCase):
    def test_slot_one_depth_metadata_is_admitted_atomically(self) -> None:
        if shutil.which("xcrun") is None:
            self.skipTest("xcrun is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-depth-parallax-loader-",
            dir="/private/tmp",
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "depth-parallax-loader"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if not result.get("available", False):
            self.skipTest("Metal device is unavailable")
        self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
