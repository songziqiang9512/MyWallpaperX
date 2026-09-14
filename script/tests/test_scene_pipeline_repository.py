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

final class SceneSpotLightPipeline {
    static let attempts = Counter()
    let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        Self.attempts.increment()
        deviceRegistryID = device.registryID
    }
}

final class SceneLayerColorBlendPipelineState {
    static let attempts = Counter()
    let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        Self.attempts.increment()
        deviceRegistryID = device.registryID
    }
}

@main
enum Harness {
    // The dedicated blur/color-key slots were retired with the dedicated
    // effect runtimes; the surviving spot-light slot must keep the same
    // lazy, shared, thread-safe resolution contract.
    static func concurrentSpotLight(
        _ repository: SceneImageEffectPipelineRepository,
        count: Int
    ) -> [SceneSpotLightPipeline] {
        let queue = DispatchQueue(
            label: "scene.pipeline.repository.spot-light",
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let lock = NSLock()
        var values: [SceneSpotLightPipeline] = []
        for _ in 0..<count {
            group.enter()
            queue.async {
                if let value = repository.spotLight() {
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

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "PipelineRepositoryHarness", code: 1)
        }
        let first = SceneImageEffectPipelineRepository(device: device)
        let second = SceneImageEffectPipelineRepository(device: device)
        let attemptsAfterConstruction = SceneSpotLightPipeline.attempts.read()
        let colorBlendAttemptsAfterConstruction =
            SceneLayerColorBlendPipelineState.attempts.read()

        let firstValues = concurrentSpotLight(first, count: 128)
        let firstIDs = Set(firstValues.map(ObjectIdentifier.init))
        _ = second.spotLight()
        let firstColorBlend = first.layerColorBlendState()
        let firstColorBlendAgain = first.layerColorBlendState()
        let secondColorBlend = second.layerColorBlendState()

        let result: [String: Any] = [
            "attemptsAfterConstruction": attemptsAfterConstruction,
            "colorBlendAttemptsAfterConstruction":
                colorBlendAttemptsAfterConstruction,
            "firstSpotLightValueCount": firstValues.count,
            "firstSpotLightIdentityCount": firstIDs.count,
            "spotLightAttemptsAcrossTwoRepositories":
                SceneSpotLightPipeline.attempts.read(),
            "deviceMatches": firstValues.allSatisfy {
                $0.deviceRegistryID == device.registryID
            },
            "firstColorBlendReused": firstColorBlend != nil
                && firstColorBlendAgain === firstColorBlend,
            "colorBlendAttemptsAcrossTwoRepositories":
                SceneLayerColorBlendPipelineState.attempts.read(),
            "colorBlendDeviceMatches": firstColorBlend?.deviceRegistryID
                    == device.registryID
                && secondColorBlend?.deviceRegistryID == device.registryID,
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
        self.assertEqual(result["colorBlendAttemptsAfterConstruction"], 0)
        self.assertEqual(result["firstSpotLightValueCount"], 128)
        self.assertEqual(result["firstSpotLightIdentityCount"], 1)
        self.assertEqual(result["spotLightAttemptsAcrossTwoRepositories"], 2)
        self.assertTrue(result["deviceMatches"])
        self.assertTrue(result["firstColorBlendReused"])
        self.assertEqual(result["colorBlendAttemptsAcrossTwoRepositories"], 2)
        self.assertTrue(result["colorBlendDeviceMatches"])


if __name__ == "__main__":
    unittest.main()
