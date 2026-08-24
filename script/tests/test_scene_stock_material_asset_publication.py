#!/usr/bin/env python3

"""Exact stock material asset publication and author-precedence gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_sampler_default_purpose import (
    REPOSITORY_ROOT,
    SUPPORT,
    SWIFT_SOURCES,
)


STOCK_PHASE = REPOSITORY_ROOT / (
    "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/"
    "materials/particle/normal_ring_smooth.tex"
)

HARNESS = r'''
import Foundation
import Metal

private func publication(
    _ catalog: SceneMaterialAssetTextureCatalog,
    _ identity: SceneAssetTextureIdentity
) -> SceneTextureProviderPublication? {
    guard case let .ready(value)? = catalog.makeFrameProvider()
            .states(sceneTime: 0)[identity] else { return nil }
    return value
}

private func exactFilePath(
    _ publication: SceneTextureProviderPublication?,
    _ expected: URL
) -> Bool {
    guard let publication,
          case let .file(path) = publication.candidate.identity else {
        return false
    }
    return path == expected.standardizedFileURL.path
}

@main
private enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              CommandLine.arguments.count == 4 else {
            print(#"{"metalAvailable":false}"#)
            return
        }
        let empty = URL(
            fileURLWithPath: CommandLine.arguments[1], isDirectory: true
        )
        let author = URL(
            fileURLWithPath: CommandLine.arguments[2], isDirectory: true
        )
        let stock = URL(
            fileURLWithPath: CommandLine.arguments[3], isDirectory: true
        )
        let phasePath = SceneVFSAssetPath("particle/normal_ring_smooth")!
        let phase = SceneAssetTextureIdentity(path: phasePath, purpose: .phase)
        let missing = SceneAssetTextureIdentity(
            path: SceneVFSAssetPath("particle/not_a_stock_asset")!,
            purpose: .phase
        )
        let stockView = SceneResourceView(
            projectRootURL: empty,
            packageRootURL: nil,
            stockAssetsRootURL: stock
        )
        let stockCatalog = SceneMaterialAssetTextureCatalog(
            demands: [phase, missing],
            resourceView: stockView,
            descriptor: SceneRenderDescriptor(),
            device: device
        )
        let stockPublication = publication(stockCatalog, phase)
        let stockURL = stock.appendingPathComponent(
            "materials/particle/normal_ring_smooth.tex"
        )
        let authorView = SceneResourceView(
            projectRootURL: author,
            packageRootURL: nil,
            stockAssetsRootURL: stock
        )
        let authorCatalog = SceneMaterialAssetTextureCatalog(
            demands: [phase],
            resourceView: authorView,
            descriptor: SceneRenderDescriptor(),
            device: device
        )
        let authorPublication = publication(authorCatalog, phase)
        let authorURL = author.appendingPathComponent(
            "materials/particle/normal_ring_smooth.tex"
        )
        let missingAbsent: Bool
        if case .absent? = stockCatalog.makeFrameProvider()
                .states(sceneTime: 0)[missing] {
            missingAbsent = true
        } else {
            missingAbsent = false
        }
        let contract = stockPublication.map {
            $0.requestIdentity == .asset(phase)
                && $0.candidate.purpose == .phase
                && $0.candidate.content == .data
                && $0.candidate.physicalSize.width > 0
                && $0.candidate.physicalSize.height > 0
                && $0.candidate.mappedSize.width > 0
                && $0.candidate.mappedSize.height > 0
                && $0.candidate.materialProgramUVTransform() != nil
                && !$0.candidate.sampling.usesClampBorderFallback
                && $0.isComplete
        } ?? false
        let result: [String: Any] = [
            "metalAvailable": true,
            "stockExactRequestReady": contract
                && exactFilePath(stockPublication, stockURL),
            "authorPrecedesStock": exactFilePath(authorPublication, authorURL)
                && authorPublication?.lifecycleIdentity
                    != stockPublication?.lifecycleIdentity,
            "launchContract": stockCatalog.launchStates[phase] == .ready(.data)
                && stockCatalog.launchFormatFacts[phase.reportToken] == 0,
            "missingAbsent": missingAbsent,
            "traversalRejected": SceneVFSAssetPath(
                "../particle/normal_ring_smooth"
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneStockMaterialAssetPublicationTests(unittest.TestCase):
    def test_stock_exact_identity_and_author_precedence(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-stock-material-publication-"
        ) as directory:
            root = Path(directory)
            empty = root / "empty"
            author = root / "author"
            stock = root / "stock"
            empty.mkdir()
            author_phase = author / "materials/particle/normal_ring_smooth.tex"
            stock_phase = stock / "materials/particle/normal_ring_smooth.tex"
            author_phase.parent.mkdir(parents=True)
            stock_phase.parent.mkdir(parents=True)
            shutil.copyfile(STOCK_PHASE, author_phase)
            shutil.copyfile(STOCK_PHASE, stock_phase)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "stock-material-publication"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    str(support), *(str(path) for path in SWIFT_SOURCES),
                    str(harness), "-framework", "Metal", "-framework",
                    "CoreGraphics", "-framework", "ImageIO",
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            if compilation.returncode != 0:
                raise RuntimeError(compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(empty), str(author), str(stock)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            if completed.returncode != 0:
                raise RuntimeError(completed.stderr or completed.stdout)
            result = json.loads(completed.stdout)
            if not result["metalAvailable"]:
                self.skipTest("Metal is unavailable")
        self.assertEqual(
            [
                key for key, value in result.items()
                if key != "metalAvailable" and not value
            ],
            [],
            result,
        )


if __name__ == "__main__":
    unittest.main()
