#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_PHASE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials/particle"
    / "normal_ring_smooth.tex"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneWaterFlowBuiltInPhaseTexture.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneEffectTextureLoadResult.swift",
    SCENE_ROOT / "Rendering/SceneTextureMappedUVScale.swift",
    SCENE_ROOT / "Resources/SceneLayerEffectTextureLoader+TextureLoading.swift",
    SCENE_ROOT / "Resources/SceneWaterFlowEffectTextureLoader.swift",
]


HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) {
        return nil
    }
}

struct SceneWaterFlowExecutionPlan {
    let flowTexturePath: String
    let phaseTexturePath: String
}

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urlsByPath[path]
    }
}

struct SceneRenderDescriptor {
    struct EffectPass {
        let textureSlots: [String?]
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        let passes: [EffectPass]
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

enum SceneLayerEffectTextureLoader {}

@main
enum Harness {
    static let effectID = "86#effect#1"
    static let flowPath = "workshop/water_flow"
    static let embeddedFlowPath = "workshop/water_flow_embedded"
    static let oversizedFlowPath = "workshop/water_flow_oversized"
    static let paddedFlowPath = "workshop/padded_flow"
    static let stockPhasePath = "particle/normal_ring_smooth"
    static let paddedPhasePath = "workshop/padded_phase"
    static let flowPixels: [UInt8] = [
        231, 17, 149, 0, 200, 100, 50, 64,
        17, 203, 41, 255, 89, 7, 211, 128,
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw HarnessError.invalidArguments
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let stockPhase = URL(fileURLWithPath: CommandLine.arguments[1])
        let temporary = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        let flowURL = temporary.appendingPathComponent("flow.png")
        let embeddedFlowURL = temporary.appendingPathComponent("flow.tex")
        let oversizedFlowURL = temporary.appendingPathComponent("oversized-flow.png")
        let corruptURL = temporary.appendingPathComponent("corrupt.png")
        let paddedPhaseURL = temporary.appendingPathComponent("padded-phase.tex")
        let paddedFlowURL = temporary.appendingPathComponent("padded-flow.tex")
        try writeImage(flowURL, width: 2, height: 2, pixels: flowPixels)
        try writeEmbeddedTex(
            embeddedFlowURL,
            imageData: Data(contentsOf: flowURL),
            width: 2,
            height: 2
        )
        try writeImage(
            oversizedFlowURL,
            width: 4097,
            height: 1,
            pixels: (0 ..< 4097).flatMap { _ in [231, 17, 149, 0] }
        )
        try Data("not an image".utf8).write(to: corruptURL)
        try writeRawR8Tex(
            paddedPhaseURL,
            textureWidth: 4,
            imageWidth: 2
        )
        try writeRawR8Tex(
            paddedFlowURL,
            textureWidth: 4,
            imageWidth: 2
        )

        let loader = SceneTextureLoader()
        let valid = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL, stockPhasePath: stockPhase],
            loader: loader,
            device: device
        )
        let embedded = load(
            flowPath: embeddedFlowPath,
            phasePath: stockPhasePath,
            urlsByPath: [
                embeddedFlowPath: embeddedFlowURL,
                stockPhasePath: stockPhase,
            ],
            loader: loader,
            device: device
        )
        let oversized = load(
            flowPath: oversizedFlowPath,
            phasePath: stockPhasePath,
            urlsByPath: [
                oversizedFlowPath: oversizedFlowURL,
                stockPhasePath: stockPhase,
            ],
            loader: loader,
            device: device
        )
        let missing = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL],
            loader: loader,
            device: device
        )
        let corrupt = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL, stockPhasePath: corruptURL],
            loader: loader,
            device: device
        )
        let unknown = load(
            phasePath: "particle/unknown",
            urlsByPath: [flowPath: flowURL],
            loader: loader,
            device: device
        )
        let paddedPhase = load(
            phasePath: paddedPhasePath,
            urlsByPath: [flowPath: flowURL, paddedPhasePath: paddedPhaseURL],
            loader: loader,
            device: device
        )
        let paddedFlow = load(
            flowPath: paddedFlowPath,
            phasePath: stockPhasePath,
            urlsByPath: [
                paddedFlowPath: paddedFlowURL,
                stockPhasePath: stockPhase,
            ],
            loader: loader,
            device: device
        )

        let validTextures = valid.textures[effectID]
        let embeddedTextures = embedded.textures[effectID]
        let oversizedTextures = oversized.textures[effectID]
        let missingTextures = missing.textures[effectID]
        let corruptTextures = corrupt.textures[effectID]
        let paddedPhaseTextures = paddedPhase.textures[effectID]
        let paddedFlowTextures = paddedFlow.textures[effectID]
        let paddedFlowScale = paddedFlowTextures?.flowCandidate?
            .axisAlignedMappedUVScale(expectedPurpose: .flow)
        let validFlowScale = validTextures?.flowCandidate?.axisAlignedMappedUVScale(
            expectedPurpose: .flow
        )
        let result: [String: Any] = [
            "validFlowPixels": try pixels(validTextures?.flowCandidate?.texture),
            "validPhaseLoaded": validTextures?.phaseCandidate != nil,
            "validPhasePreservedMips":
                (validTextures?.phaseCandidate?.texture.mipmapLevelCount ?? 0) > 1,
            "validMatches": validTextures?.matches(plan(phasePath: stockPhasePath)) ?? false,
            "validPhaseAddress":
                validTextures?.phaseCandidate?.sampling.addressMode.rawValue ?? "",
            "validFlowAddress":
                validTextures?.flowCandidate?.sampling.addressMode.rawValue ?? "",
            "validFlowPurpose": validTextures?.flowCandidate?.purpose == .flow,
            "validPhasePurpose": validTextures?.phaseCandidate?.purpose == .phase,
            "validFlowScale": [validFlowScale?.x ?? -1, validFlowScale?.y ?? -1],
            "validFlowIdentity": identityKind(validTextures?.flowCandidate),
            "validPhaseIdentity": identityKind(validTextures?.phaseCandidate),
            "embeddedFlowPixels": try pixels(embeddedTextures?.flowCandidate?.texture),
            "embeddedMatches": embeddedTextures?.matches(plan(
                flowPath: embeddedFlowPath,
                phasePath: stockPhasePath
            )) ?? false,
            "oversizedStayedFailed": oversizedTextures?.flowCandidate == nil,
            "oversizedDoesNotMatch": !(oversizedTextures?.matches(plan(
                flowPath: oversizedFlowPath,
                phasePath: stockPhasePath
            )) ?? false),
            "oversizedReported": oversized.message.contains("decode failed"),
            "missingUsesBuiltIn": missingTextures?.phaseCandidate?.texture.label
                == "Scene Water Flow built-in normal_ring_smooth",
            "missingMatches": missingTextures?.matches(plan(phasePath: stockPhasePath)) ?? false,
            "missingPhaseAddress":
                missingTextures?.phaseCandidate?.sampling.addressMode.rawValue ?? "",
            "missingPhaseIdentity": identityKind(missingTextures?.phaseCandidate),
            "missingPhaseGeneration": generationKind(missingTextures?.phaseCandidate),
            "corruptStayedFailed": corruptTextures?.phaseCandidate == nil,
            "corruptDoesNotMatch": !(corruptTextures?.matches(
                plan(phasePath: stockPhasePath)
            ) ?? false),
            "corruptReported": corrupt.message.contains("decode failed"),
            "unknownStayedFailed": unknown.textures[effectID]?.phaseCandidate == nil,
            "paddedPhaseLoaded": paddedPhaseTextures?.phaseCandidate != nil,
            "paddedPhaseRejected": !(paddedPhaseTextures?.matches(
                plan(phasePath: paddedPhasePath)
            ) ?? false),
            "paddedFlowMatches": paddedFlowTextures?.matches(plan(
                flowPath: paddedFlowPath,
                phasePath: stockPhasePath
            )) ?? false,
            "paddedFlowScale": [
                paddedFlowScale?.x ?? -1,
                paddedFlowScale?.y ?? -1,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func load(
        flowPath: String = flowPath,
        phasePath: String,
        urlsByPath: [String: URL],
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterFlowEffectTextures], message: String) {
        SceneWaterFlowEffectTextureLoader.load(
            for: .init(effects: [.init(
                id: effectID,
                file: "effects/waterflow/effect.json",
                passes: [.init(textureSlots: [nil, flowPath, phasePath])]
            )]),
            effectIDs: [effectID],
            resolver: .init(urlsByPath: urlsByPath),
            loader: loader,
            device: device
        )
    }

    static func plan(
        flowPath: String = flowPath,
        phasePath: String
    ) -> SceneWaterFlowExecutionPlan {
        .init(flowTexturePath: flowPath, phaseTexturePath: phasePath)
    }

    static func pixels(_ texture: MTLTexture?) throws -> [UInt8] {
        guard let texture else { throw HarnessError.textureReadFailed }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return bytes
    }

    static func identityKind(_ candidate: SceneTextureCandidate?) -> String {
        guard let candidate else { return "none" }
        switch candidate.identity {
        case .file: return "file"
        case .builtIn: return "builtIn"
        case .provider: return "provider"
        }
    }

    static func generationKind(_ candidate: SceneTextureCandidate?) -> String {
        guard let candidate else { return "none" }
        switch candidate.generation {
        case .file: return "file"
        case .immutable: return "immutable"
        case .provider: return "provider"
        }
    }

    static func writeImage(
        _ url: URL,
        width: Int,
        height: Int,
        pixels: [UInt8]
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
    }

    static func writeEmbeddedTex(
        _ url: URL,
        imageData: Data,
        width: UInt32,
        height: UInt32
    ) throws {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(0, to: &data)
        append(0, to: &data)
        append(width, to: &data)
        append(height, to: &data)
        append(width, to: &data)
        append(height, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(width, to: &data)
        append(height, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        append(UInt32(imageData.count), to: &data)
        data.append(imageData)
        try data.write(to: url)
    }

    static func writeRawR8Tex(
        _ url: URL,
        textureWidth: UInt32,
        imageWidth: UInt32
    ) throws {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(9, to: &data)
        append(0, to: &data)
        append(textureWidth, to: &data)
        append(4, to: &data)
        append(imageWidth, to: &data)
        append(4, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(textureWidth, to: &data)
        append(4, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        let payload = Data(repeating: 128, count: Int(textureWidth) * 4)
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        try data.write(to: url)
    }

    static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    enum HarnessError: Error {
        case invalidArguments
        case imageCreationFailed
        case textureReadFailed
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneWaterFlowEffectTextureLoaderTests(unittest.TestCase):
    def test_missing_phase_falls_back_but_resolved_corrupt_phase_fails_closed(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-waterflow-loader-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "waterflow-loader-test"
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
                    "-framework",
                    "ImageIO",
                    "-framework",
                    "CoreGraphics",
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
                [str(binary), str(STOCK_PHASE), str(root / "runtime")],
                check=True,
                capture_output=True,
                text=True,
            )
        if completed.stdout.strip() == "SKIP":
            self.skipTest("Metal is unavailable")
        result = json.loads(completed.stdout)
        self.assertEqual(
            result,
            {
                "corruptDoesNotMatch": True,
                "corruptReported": True,
                "corruptStayedFailed": True,
                "embeddedFlowPixels": [
                    231, 17, 149, 0, 200, 100, 50, 64,
                    17, 203, 41, 255, 89, 7, 211, 128,
                ],
                "embeddedMatches": True,
                "missingMatches": True,
                "missingPhaseAddress": "clampToEdge",
                "missingPhaseGeneration": "immutable",
                "missingPhaseIdentity": "builtIn",
                "missingUsesBuiltIn": True,
                "oversizedDoesNotMatch": True,
                "oversizedReported": True,
                "oversizedStayedFailed": True,
                "paddedPhaseLoaded": True,
                "paddedPhaseRejected": True,
                "paddedFlowMatches": True,
                "paddedFlowScale": [0.5, 1],
                "unknownStayedFailed": True,
                "validFlowAddress": "clampToEdge",
                "validFlowIdentity": "file",
                "validFlowPixels": [
                    231, 17, 149, 0, 200, 100, 50, 64,
                    17, 203, 41, 255, 89, 7, 211, 128,
                ],
                "validFlowPurpose": True,
                "validFlowScale": [1, 1],
                "validMatches": True,
                "validPhaseAddress": "clampToEdge",
                "validPhaseIdentity": "file",
                "validPhaseLoaded": True,
                "validPhasePreservedMips": True,
                "validPhasePurpose": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
