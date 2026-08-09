#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REPOSITORY_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering"
    / "SceneImageEffectPipelineRepository.swift"
)

HARNESS = r'''
import Foundation
import Metal

final class Counter {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class SceneGaussianBlurPipeline { init?(device: MTLDevice) {} }
final class SceneStandardBlurPipeline { init?(device: MTLDevice) {} }
final class SceneLocalContrastPipeline { init?(device: MTLDevice) {} }
final class SceneOpacityPipeline { init?(device: MTLDevice) {} }
final class SceneColorKeyPipeline { init?(device: MTLDevice) {} }
final class SceneColorGradingPipeline { init?(device: MTLDevice) {} }
final class SceneWorkshopShiftHuePipeline { init?(device: MTLDevice) {} }
final class SceneWorkshopAudioBarsPipeline { init?(device: MTLDevice) {} }
final class SceneWorkshopGradientPipeline { init?(device: MTLDevice) {} }
final class SceneWorkshopShadowPipeline { init?(device: MTLDevice) {} }
final class SceneSpinPipeline { init?(device: MTLDevice) {} }
final class SceneProceduralNoisePipeline { init?(device: MTLDevice) {} }
final class SceneFilmGrainPipeline { init?(device: MTLDevice) {} }
final class SceneLightShaftsPipeline { init?(device: MTLDevice) {} }
final class SceneSpotLightPipeline { init?(device: MTLDevice) {} }
final class SceneShakePipeline { init?(device: MTLDevice) {} }
final class SceneWaterFlowPipeline { init?(device: MTLDevice) {} }
final class SceneWaterWavesPipeline { init?(device: MTLDevice) {} }
final class SceneWaterCausticsPipeline { init?(device: MTLDevice) {} }
final class SceneCursorRipplePipeline { init?(device: MTLDevice) {} }
final class SceneFoliageSwayPipeline { init?(device: MTLDevice) {} }
final class SceneWaterRipplePipeline { init?(device: MTLDevice) {} }
final class SceneDepthParallaxPipeline { init?(device: MTLDevice) {} }
final class SceneXRayPipeline { init?(device: MTLDevice) {} }
final class SceneBlendPipeline { init?(device: MTLDevice) {} }
final class SceneMediaThumbnailTransitionPipeline { init?(device: MTLDevice) {} }
final class ScenePulsePipeline { init?(device: MTLDevice) {} }
final class SceneShinePipeline { init?(device: MTLDevice) {} }
final class SceneGradientColorPipeline { init?(device: MTLDevice) {} }
final class ScenePerspectiveOpacityPipeline { init?(device: MTLDevice) {} }

final class SceneTintPipeline {
    static let attempts = Counter()
    let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        Self.attempts.increment()
        deviceRegistryID = device.registryID
    }
}

final class SceneFisheyeZeroDistortionPipeline {
    init?(device: MTLDevice) {}
}

final class SceneGodraysPipeline {
    static let attempts = Counter()

    init?(device: MTLDevice) {
        Self.attempts.increment()
        return nil
    }
}

final class SceneBloomPipeline {
    static let attempts = Counter()

    init?(device: MTLDevice) {
        Self.attempts.increment()
    }
}

@main
enum Harness {
    static func concurrentTint(
        _ repository: SceneImageEffectPipelineRepository,
        count: Int
    ) -> [SceneTintPipeline] {
        let queue = DispatchQueue(
            label: "scene.pipeline.repository.tint",
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let lock = NSLock()
        var values: [SceneTintPipeline] = []
        for _ in 0..<count {
            group.enter()
            queue.async {
                if let value = repository.tint() {
                    lock.lock()
                    values.append(value)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        return values
    }

    static func concurrentFailure(
        _ repository: SceneImageEffectPipelineRepository,
        count: Int
    ) -> Int {
        let queue = DispatchQueue(
            label: "scene.pipeline.repository.failure",
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let successes = Counter()
        for _ in 0..<count {
            group.enter()
            queue.async {
                if repository.godrays() != nil {
                    successes.increment()
                }
                group.leave()
            }
        }
        group.wait()
        return successes.read()
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "PipelineRepositoryHarness", code: 1)
        }
        let first = SceneImageEffectPipelineRepository(device: device)
        let second = SceneImageEffectPipelineRepository(device: device)
        let attemptsAfterConstruction = SceneTintPipeline.attempts.read()
            + SceneGodraysPipeline.attempts.read()
            + SceneBloomPipeline.attempts.read()

        let firstValues = concurrentTint(first, count: 128)
        let firstIDs = Set(firstValues.map(ObjectIdentifier.init))
        let failedSuccesses = concurrentFailure(first, count: 128)
        _ = second.tint()

        let result: [String: Any] = [
            "attemptsAfterConstruction": attemptsAfterConstruction,
            "firstTintValueCount": firstValues.count,
            "firstTintIdentityCount": firstIDs.count,
            "tintAttemptsAcrossTwoRepositories": SceneTintPipeline.attempts.read(),
            "failedSuccesses": failedSuccesses,
            "failedAttempts": SceneGodraysPipeline.attempts.read(),
            "unusedBloomAttempts": SceneBloomPipeline.attempts.read(),
            "deviceMatches": firstValues.allSatisfy {
                $0.deviceRegistryID == device.registryID
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class ScenePipelineRepositoryTests(unittest.TestCase):
    def test_slots_are_lazy_shared_thread_safe_and_cache_failures(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-pipeline-repository-") as tmp:
            root = Path(tmp)
            harness = root / "Harness.swift"
            binary = root / "pipeline-repository"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    str(REPOSITORY_SOURCE),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            if compilation.returncode != 0:
                raise RuntimeError(compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)

        self.assertEqual(result["attemptsAfterConstruction"], 0)
        self.assertEqual(result["firstTintValueCount"], 128)
        self.assertEqual(result["firstTintIdentityCount"], 1)
        self.assertEqual(result["tintAttemptsAcrossTwoRepositories"], 2)
        self.assertEqual(result["failedSuccesses"], 0)
        self.assertEqual(result["failedAttempts"], 1)
        self.assertEqual(result["unusedBloomAttempts"], 0)
        self.assertTrue(result["deviceMatches"])


if __name__ == "__main__":
    unittest.main()
