#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
ISOLATED_SAMPLE_ROOT = REPOSITORY_ROOT / ".codex/scene-user-samples-20260722/Scene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "SceneResourceIndex.swift",
    SOURCE_ROOT / "SceneParticleDefinition.swift",
    SOURCE_ROOT / "SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "SceneParticleTextureSource.swift",
    SOURCE_ROOT / "SceneParticleAssetGraph.swift",
    SOURCE_ROOT / "ScenePkgReader.swift",
]


HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else { throw HarnessError.missingMode }
        switch CommandLine.arguments[1] {
        case "synthetic":
            try printJSON(syntheticResult())
        case "census":
            guard CommandLine.arguments.count == 3 else { throw HarnessError.missingSampleRoot }
            try printJSON(censusResult(rootPath: CommandLine.arguments[2]))
        default:
            throw HarnessError.unknownMode
        }
    }

    private static func syntheticResult() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeJSON([
            "material": "Materials/Particle/Root.json",
            "emitter": [["name": "sphereRandom"]],
            "children": [["name": "Particles/Child.json"]]
        ], relativePath: "particles/root.json", under: directory)
        try writeJSON([
            "material": "materials/particle/child.json",
            "emitter": [["name": "boxRandom"]],
            "children": [["name": "particles/root.json"]]
        ], relativePath: "particles/child.json", under: directory)
        try writeJSON([
            "material": "materials/particle/absent-material.json",
            "emitter": [["name": "sphereRandom"]]
        ], relativePath: "particles/missing-material.json", under: directory)
        try writeJSON([
            "material": "materials/particle/missing-texture.json",
            "emitter": [["name": "sphereRandom"]]
        ], relativePath: "particles/missing-texture.json", under: directory)
        try writeJSON([
            "material": "materials/particle/builtin-texture.json",
            "emitter": [["name": "sphereRandom"]]
        ], relativePath: "particles/builtin-texture.json", under: directory)
        try writeJSON([
            "material": "materials/particle/drop-texture.json",
            "emitter": [["name": "sphereRandom"]]
        ], relativePath: "particles/drop-texture.json", under: directory)
        try write(Data([0x54, 0x45, 0x58]), relativePath: "materials/particle/root.tex", under: directory)
        try write(Data([0x89, 0x50, 0x4e, 0x47]), relativePath: "materials/particle/child.png", under: directory)

        let passes = [
            SceneParticleMaterialPass(
                materialPath: "materials/particle/root.json",
                shaderPath: "shaders/genericparticle.json",
                texturePaths: ["particle/root"],
                blending: "Additive"
            ),
            SceneParticleMaterialPass(
                materialPath: "materials/particle/child.json",
                shaderPath: "shaders/genericparticle.json",
                texturePaths: ["materials/particle/child.png"],
                blending: "Translucent"
            ),
            SceneParticleMaterialPass(
                materialPath: "materials/particle/missing-texture.json",
                shaderPath: "shaders/genericparticle.json",
                texturePaths: ["custom/absent"],
                blending: nil
            ),
            SceneParticleMaterialPass(
                materialPath: "materials/particle/builtin-texture.json",
                shaderPath: "shaders/genericparticle.json",
                texturePaths: ["particle/halo"],
                blending: nil
            ),
            SceneParticleMaterialPass(
                materialPath: "materials/particle/drop-texture.json",
                shaderPath: "shaders/genericparticle.json",
                texturePaths: ["particle/drop"],
                blending: nil
            )
        ]
        let graph = SceneParticleAssetGraphLoader().load(
            rootPaths: [
                "Particles\\Root.JSON",
                "particles/missing-material.json",
                "particles/missing-texture.json",
                "particles/builtin-texture.json",
                "particles/drop-texture.json",
                "particles/missing-definition.json"
            ],
            materialPasses: passes,
            cacheDirectory: directory
        )
        let root = graph.assetsByPath["particles/root.json"]
        let child = graph.assetsByPath["particles/child.json"]
        let drop = graph.assetsByPath["particles/drop-texture.json"]
        try write(Data([0x54, 0x45, 0x58]), relativePath: "materials/particle/drop.tex", under: directory)
        let localDropGraph = SceneParticleAssetGraphLoader().load(
            rootPaths: ["particles/drop-texture.json"],
            materialPasses: passes,
            cacheDirectory: directory
        )
        let localDrop = localDropGraph.assetsByPath["particles/drop-texture.json"]
        let diagnostics = Dictionary(grouping: graph.diagnostics, by: { $0.kind.rawValue })
            .mapValues(\.count)
        return [
            "assetCount": graph.assetsByPath.count,
            "rootPaths": graph.rootPaths,
            "rootChildren": root?.childPaths ?? [],
            "rootBlend": root?.blendMode.rawValue ?? "",
            "childBlend": child?.blendMode.rawValue ?? "",
            "rootTexture": fileURL(root?.textureSource)?.lastPathComponent ?? "",
            "childTexture": fileURL(child?.textureSource)?.lastPathComponent ?? "",
            "rootTextureExists": fileURL(root?.textureSource).map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false,
            "childTextureExists": fileURL(child?.textureSource).map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false,
            "dropTextureSource": sourceKind(drop?.textureSource),
            "localDropTextureSource": sourceKind(localDrop?.textureSource),
            "diagnostics": diagnostics
        ]
    }

    private static func censusResult(rootPath: String) throws -> [String: Any] {
        let sourceRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
        let sampleURLs = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-census-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionRoot) }

        var samplesWithParticles = 0
        var reachableAssetCount = 0
        var blendCounts: [String: Int] = [:]
        var diagnosticCounts: [String: Int] = [:]
        var missingResourceDiagnostics: [String] = []
        var summaries: [[String: Any]] = []

        for sampleURL in sampleURLs {
            let project = try jsonObject(data: Data(
                contentsOf: sampleURL.appendingPathComponent("project.json")
            ))
            let entryPath = normalizedPath(project["file"] as? String ?? "scene.json")
            let packageURL = try scenePackageURL(sampleURL: sampleURL, entryPath: entryPath)
            let index = try ScenePkgReader().readIndex(packageURL: packageURL)
            let entries = Dictionary(
                index.entries.map { (normalizedPath($0.path), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let outputURL = extractionRoot.appendingPathComponent(
                sampleURL.lastPathComponent,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let jsonEntries = entries.filter { path, _ in
                path == entryPath || URL(fileURLWithPath: path).pathExtension == "json"
            }.map(\.value)
            try extract(jsonEntries, index: index, packageURL: packageURL, outputURL: outputURL)

            let sceneURL = outputURL.appendingPathComponent(entryPath)
            let scene = try jsonObject(data: Data(contentsOf: sceneURL))
            let rootPaths = (scene["objects"] as? [[String: Any]] ?? [])
                .compactMap { $0["particle"] as? String }
            if !rootPaths.isEmpty { samplesWithParticles += 1 }

            let materialPasses = try loadMaterialPasses(rootURL: outputURL)
            let relevantMaterialPaths = reachableMaterialPaths(
                rootPaths: rootPaths,
                rootURL: outputURL
            )
            let relevantPasses = materialPasses.filter {
                relevantMaterialPaths.contains(normalizedPath($0.materialPath))
            }
            let textureEntries = relevantPasses.flatMap(\.texturePaths).compactMap { texturePath in
                textureCandidates(texturePath).lazy.compactMap { entries[$0] }.first
            }
            try extract(textureEntries, index: index, packageURL: packageURL, outputURL: outputURL)

            let graph = SceneParticleAssetGraphLoader().load(
                rootPaths: rootPaths,
                materialPasses: materialPasses,
                cacheDirectory: outputURL
            )
            reachableAssetCount += graph.assetsByPath.count
            for asset in graph.assetsByPath.values {
                blendCounts[asset.blendMode.rawValue, default: 0] += 1
            }
            for diagnostic in graph.diagnostics {
                diagnosticCounts[diagnostic.kind.rawValue, default: 0] += 1
                if [
                    SceneParticleAssetDiagnostic.Kind.missingDefinition,
                    .missingMaterial,
                    .missingTextureReference,
                    .missingTextureFile
                ].contains(diagnostic.kind) {
                    missingResourceDiagnostics.append(
                        "\(sampleURL.lastPathComponent):\(diagnostic.assetPath):\(diagnostic.detail ?? "")"
                    )
                }
            }
            summaries.append([
                "sample": sampleURL.lastPathComponent,
                "roots": rootPaths.count,
                "assets": graph.assetsByPath.count,
                "diagnostics": graph.diagnostics.count
            ])
        }

        return [
            "sampleCount": sampleURLs.count,
            "samplesWithParticles": samplesWithParticles,
            "reachableAssetCount": reachableAssetCount,
            "blendCounts": blendCounts,
            "diagnosticCounts": diagnosticCounts,
            "missingResourceDiagnostics": missingResourceDiagnostics.sorted(),
            "samples": summaries
        ]
    }

    private static func reachableMaterialPaths(rootPaths: [String], rootURL: URL) -> Set<String> {
        let resources = SceneResourceIndexBuilder().build(rootURL: rootURL)
        let files = Dictionary(
            resources.resources.map { (normalizedPath($0.relativePath), $0.url) },
            uniquingKeysWith: { first, _ in first }
        )
        var materials = Set<String>()
        var visited = Set<String>()
        var pending = rootPaths.map(normalizedPath)
        while let path = pending.popLast() {
            guard visited.insert(path).inserted,
                  let url = files[path],
                  let data = try? Data(contentsOf: url),
                  let definition = try? SceneParticleDefinitionParser().parse(data: data) else { continue }
            if let material = definition.materialPath { materials.insert(normalizedPath(material)) }
            pending.append(contentsOf: definition.children.compactMap(\.path).map(normalizedPath))
        }
        return materials
    }

    private static func loadMaterialPasses(rootURL: URL) throws -> [SceneParticleMaterialPass] {
        let resources = SceneResourceIndexBuilder().build(rootURL: rootURL)
        return try resources.resources.filter {
            normalizedPath($0.relativePath).hasPrefix("materials/")
                && normalizedPath($0.relativePath).hasSuffix(".json")
        }.flatMap { resource -> [SceneParticleMaterialPass] in
            let root = try jsonObject(data: Data(contentsOf: resource.url))
            return (root["passes"] as? [[String: Any]] ?? []).map { pass in
                SceneParticleMaterialPass(
                    materialPath: resource.relativePath,
                    shaderPath: pass["shader"] as? String,
                    texturePaths: (pass["textures"] as? [Any] ?? []).compactMap { $0 as? String },
                    blending: pass["blending"] as? String
                )
            }
        }
    }

    private static func textureCandidates(_ rawName: String) -> [String] {
        let name = normalizedPath(rawName)
        let bases = name.hasPrefix("materials/") ? [name] : ["materials/\(name)", name]
        var candidates = bases.flatMap { [$0, "\($0).tex"] }
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            candidates += bases.flatMap { base in
                ["\(base).png", "\(base).jpg", "\(base).jpeg"]
            }
        }
        return candidates
    }

    private static func extract(
        _ entries: [ScenePkgIndex.Entry],
        index: ScenePkgIndex,
        packageURL: URL,
        outputURL: URL
    ) throws {
        let handle = try FileHandle(forReadingFrom: packageURL)
        defer { try? handle.close() }
        for entry in entries {
            let path = normalizedPath(entry.path)
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw HarnessError.unsafeEntry(entry.path)
            }
            try handle.seek(toOffset: UInt64(index.dataStartOffset) + UInt64(entry.offset))
            guard let data = try handle.read(upToCount: Int(entry.size)),
                  data.count == Int(entry.size) else {
                throw HarnessError.truncatedEntry(entry.path)
            }
            try write(data, relativePath: path, under: outputURL)
        }
    }

    private static func writeJSON(
        _ value: [String: Any],
        relativePath: String,
        under rootURL: URL
    ) throws {
        try write(
            JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            relativePath: relativePath,
            under: rootURL
        )
    }

    private static func write(_ data: Data, relativePath: String, under rootURL: URL) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func scenePackageURL(sampleURL: URL, entryPath: String) throws -> URL {
        let entryName = (entryPath as NSString).lastPathComponent
        let baseName = (entryName as NSString).deletingPathExtension
        let derivedName = baseName.isEmpty ? "scene.pkg" : "\(baseName).pkg"
        for name in derivedName == "scene.pkg" ? [derivedName] : [derivedName, "scene.pkg"] {
            let candidate = sampleURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw HarnessError.missingPackage(sampleURL.lastPathComponent)
    }

    private static func jsonObject(data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessError.invalidJSON
        }
        return root
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        var value = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }

    private static func fileURL(_ source: SceneParticleTextureSource?) -> URL? {
        guard case let .file(url)? = source else { return nil }
        return url
    }

    private static func sourceKind(_ source: SceneParticleTextureSource?) -> String {
        switch source {
        case .file: "file"
        case .builtIn(.drop): "builtInDrop"
        case nil: "missing"
        }
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum HarnessError: Error {
        case missingMode
        case missingSampleRoot
        case unknownMode
        case invalidJSON
        case missingPackage(String)
        case unsafeEntry(String)
        case truncatedEntry(String)
    }
}
'''


class SceneParticleAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-assets-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-assets"
        subprocess.run(
            [swiftc, *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def run_harness(self, *arguments: str) -> dict[str, object]:
        result = subprocess.run(
            [str(self.binary), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def test_synthetic_asset_graph(self) -> None:
        result = self.run_harness("synthetic")
        self.assertEqual(result["assetCount"], 6)
        self.assertEqual(
            result["rootPaths"],
            [
                "particles/root.json",
                "particles/missing-material.json",
                "particles/missing-texture.json",
                "particles/builtin-texture.json",
                "particles/drop-texture.json",
                "particles/missing-definition.json",
            ],
        )
        self.assertEqual(result["rootChildren"], ["particles/child.json"])
        self.assertEqual(result["rootBlend"], "additive")
        self.assertEqual(result["childBlend"], "translucent")
        self.assertEqual(result["rootTexture"], "root.tex")
        self.assertEqual(result["childTexture"], "child.png")
        self.assertTrue(result["rootTextureExists"])
        self.assertTrue(result["childTextureExists"])
        self.assertEqual(result["dropTextureSource"], "builtInDrop")
        self.assertEqual(result["localDropTextureSource"], "file")
        self.assertEqual(
            result["diagnostics"],
            {
                "builtInTextureUnavailable": 1,
                "cyclicChildReference": 1,
                "missingDefinition": 1,
                "missingMaterial": 1,
                "missingTextureFile": 1,
                "missingTextureReference": 1,
            },
        )

    def test_isolated_21_sample_asset_graph(self) -> None:
        if not ISOLATED_SAMPLE_ROOT.is_dir():
            self.skipTest("isolated 21-sample Scene corpus is unavailable")
        result = self.run_harness("census", str(ISOLATED_SAMPLE_ROOT))
        self.assertEqual(result["sampleCount"], 21)
        self.assertEqual(result["samplesWithParticles"], 18)
        self.assertEqual(result["reachableAssetCount"], 55)
        self.assertEqual(result["blendCounts"], {"additive": 42, "translucent": 13})
        self.assertEqual(result["diagnosticCounts"].get("builtInTextureUnavailable", 0), 45)
        for kind in (
            "missingDefinition",
            "missingMaterial",
            "missingTextureReference",
            "missingTextureFile",
        ):
            self.assertEqual(
                result["diagnosticCounts"].get(kind, 0),
                0,
                result["missingResourceDiagnostics"],
            )


if __name__ == "__main__":
    unittest.main()
