"""Execute the real per-launch particle preparation without a Metal device.

The existing runtime fixture supplies only descriptor collaborators. Production
Runtime.prepareAssets, GraphLoader, parsers, ResourceView and launch cancellation
are linked unchanged; this gate never creates an MTLDevice or submits GPU work.
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_particle_assets as assets
from script.tests import test_scene_particle_runtime as runtime


SCENE = runtime.SOURCE_ROOT
MAIN = r'''
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-preparation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = root.appendingPathComponent("primary")
        let lower = root.appendingPathComponent("lower")
        let stock = root.appendingPathComponent("stock")
        for folder in [primary, lower, stock] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        func definition(_ material: String, children: [String] = []) -> [String: Any] {
            ["material": material, "emitter": [["name": "boxRandom"]],
             "children": children.map { ["name": $0] }]
        }
        try writeJSON(definition("materials/primary.json", children: [
            "Particles/RenamedChild.JSON", "particles/bad.json"]),
            to: primary.appendingPathComponent("Particles/Renamed.JSON"))
        try writeJSON(definition("materials/primary.json", children: ["particles/renamed.json"]),
            to: primary.appendingPathComponent("Particles/RenamedChild.JSON"))
        try writeJSON(definition("materials/dynamic.json"),
            to: primary.appendingPathComponent("particles/dynamic.json"))
        try Data("{bad".utf8).write(to: primary.appendingPathComponent("particles/bad.json"))
        try Data("{bad".utf8).write(to: primary.appendingPathComponent("particles/hidden.json"))
        try writeJSON(definition("materials/wrong-lower.json"),
            to: lower.appendingPathComponent("particles/renamed.json"))
        try writeJSON(definition("materials/lower-only.json"),
            to: lower.appendingPathComponent("particles/lower-only.json"))
        try writeJSON(definition("materials/wrong-fallback.json"),
            to: lower.appendingPathComponent("particles/bad.json"))
        try writeJSON(definition("materials/stock-only.json"),
            to: stock.appendingPathComponent("particles/stock-only.json"))
        for (folder, path) in [(primary, "materials/probe.tex"), (lower, "materials/probe"),
                               (stock, "materials/probe.png")] {
            let target = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data([1]).write(to: target)
        }
        let view = SceneResourceView(projectRootURL: lower, packageRootURL: primary,
                                     stockAssetsRootURL: stock)
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: "materials/primary.json", shaderPath: "genericparticle",
            texturePaths: ["probe"], blending: "translucent")
        let descriptor = SceneRenderDescriptor(layers: [
            layer(1, "Particles\\Renamed.JSON"),
            layer(2, "particles/dynamic.json", visible: false),
            layer(3, "particles/hidden.json", visible: false),
            layer(4, "particles/lower-only.json"), layer(5, "particles/stock-only.json")
        ], renderOrderLayerIDs: [3, 2, 1, 4, 5], materialPasses: [pass])
        var checks: [String: Bool] = [:]
        let graph = try SceneParticleRuntime.prepareAssets(descriptor: descriptor,
            resourceView: view, preparedParticleVisibilityLayerIDs: [2], stockTextureBundleURL: nil)
        checks["visibleAndPreparedDynamicRootsPreserveOrder"] = graph.rootPaths == [
            "particles/dynamic.json", "particles/renamed.json", "particles/lower-only.json",
            "particles/stock-only.json"]
        checks["primaryDefinitionAndRecursiveRenamedChild"] =
            graph.assetsByPath["particles/renamed.json"]?.definition.materialPath == "materials/primary.json"
            && graph.assetsByPath["particles/renamedchild.json"] != nil
        checks["cycleRemainsLocal"] = graph.diagnostics.contains {
            $0.kind == .cyclicChildReference && $0.assetPath == "particles/renamed.json" }
        checks["badPrimaryDoesNotFallbackAndKeepsPeer"] =
            graph.assetsByPath["particles/bad.json"] == nil
            && graph.assetsByPath["particles/renamedchild.json"] != nil
            && graph.diagnostics.contains { $0.kind == .invalidDefinition && $0.assetPath == "particles/bad.json" }
        checks["hiddenNotPreparedIsNotRead"] = graph.assetsByPath["particles/hidden.json"] == nil
            && !graph.diagnostics.contains { $0.assetPath == "particles/hidden.json" }
        checks["lowerAndStockDefinitionsDoNotBecomeFallback"] = ["lower-only", "stock-only"].allSatisfy { name in
            graph.assetsByPath["particles/\(name).json"] == nil
                && graph.diagnostics.contains { $0.kind == .missingDefinition
                    && $0.assetPath == "particles/\(name).json" }
        }
        if case let .file(input)? = graph.assetsByPath["particles/renamed.json"]?.textureSource {
            checks["texturePrimaryAllCandidatesPrecedeLowerExact"] = URL(fileURLWithPath: input.diagnosticPath).standardizedFileURL
                == primary.appendingPathComponent("materials/probe.tex").standardizedFileURL
        } else { checks["texturePrimaryAllCandidatesPrecedeLowerExact"] = false }
        ParticleDefinitionProbe.parses = 0
        ParticleDefinitionProbe.reads = [:]
        var captured: [String: SceneParticleAssetGraphLoader.PreparedDefinition] = [:]
        let discoveredMaterials = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .prepareDefinitions(rootPaths: ["Particles/Renamed.JSON", "particles/dynamic.json", "particles/hidden.json"]) {
                captured[$0] = $1
            }
        let readCounts = ParticleDefinitionProbe.reads
        let parseCount = ParticleDefinitionProbe.parses
        checks["oneDefinitionReadParseForSharedRecursiveClosure"] = parseCount == 5
            && readCounts.values.allSatisfy { $0 == 1 }
            && Set(discoveredMaterials) == ["materials/primary.json", "materials/dynamic.json"]
        try writeJSON(definition("materials/changed-after-capture.json"),
            to: primary.appendingPathComponent("Particles/Renamed.JSON"))
        let adopted = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
            preparedParticleVisibilityLayerIDs: [2], preparedDefinitions: captured, stockTextureBundleURL: nil)
        checks["adoptionUsesSamePreparedDefinitionWithoutReread"] =
            adopted.assetsByPath["particles/renamed.json"]?.definition.materialPath == "materials/primary.json"
            && ParticleDefinitionProbe.reads == readCounts && ParticleDefinitionProbe.parses == parseCount
        var hiddenFailure = captured
        hiddenFailure["particles/hidden.json"] = .readFailed(.sourceChanged)
        let hiddenIgnored = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
            preparedParticleVisibilityLayerIDs: [2], preparedDefinitions: hiddenFailure, stockTextureBundleURL: nil)
        checks["unadoptedHiddenFailureDoesNotPoisonPeers"] = hiddenIgnored.assetsByPath["particles/renamed.json"] != nil
            && !hiddenIgnored.diagnostics.contains { $0.assetPath == "particles/hidden.json" }
        for error in [SceneResourceView.ReadError.sourceChanged, .invalidHandle] {
            var failed = captured
            failed["particles/renamed.json"] = .readFailed(error)
            do {
                _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
                    preparedDefinitions: failed, stockTextureBundleURL: nil)
                checks["adoptedHardFailure-\(error)"] = false
            } catch let failure as SceneResourceView.ReadError {
                checks["adoptedHardFailure-\(error)"] = String(describing: failure) == String(describing: error)
            }
        }
        let noPreparedLeaves = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
            preparedDefinitions: [:], stockTextureBundleURL: nil)
        checks["missingHandoffRowNeverReopensDefinition"] = noPreparedLeaves.assetsByPath.isEmpty
            && ParticleDefinitionProbe.reads == readCounts && ParticleDefinitionProbe.parses == parseCount
        let hidden = primary.appendingPathComponent("particles/hidden.json")
        func hiddenFileIsOpen() -> Bool {
            (3..<512).contains { descriptor in
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                return fcntl(Int32(descriptor), F_GETPATH, &path) == 0
                    && URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
                        == hidden.resolvingSymlinksInPath()
            }
        }
        var duringRead: [String: SceneParticleAssetGraphLoader.PreparedDefinition] = [:]
        var changedHidden = false
        _ = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .prepareDefinitions(rootPaths: ["particles/renamed.json", "particles/hidden.json"], checkCancellation: {
                if !changedHidden, hiddenFileIsOpen() {
                    changedHidden = true
                    try Data("{changed".utf8).write(to: hidden, options: .atomic)
                }
            }) { duringRead[$0] = $1 }
        let hiddenChanged: Bool
        if case .readFailed(.sourceChanged)? = duringRead["particles/hidden.json"] { hiddenChanged = true }
        else { hiddenChanged = false }
        let unaffected = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
            preparedDefinitions: duringRead, stockTextureBundleURL: nil)
        checks["realReadFailureIsDeferredOnlyForUnadoptedHiddenRoot"] = changedHidden && hiddenChanged
            && unaffected.assetsByPath["particles/renamed.json"] != nil
        do {
            _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
                preparedParticleVisibilityLayerIDs: [3], preparedDefinitions: duringRead, stockTextureBundleURL: nil)
            checks["realHiddenReadFailureEscapesOnActualAdoption"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["realHiddenReadFailureEscapesOnActualAdoption"] = true
        }
        let hiddenCancellation = SceneWallpaperLaunchCancellation()
        do {
            _ = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
                .prepareDefinitions(rootPaths: ["particles/hidden.json"], checkCancellation: {
                    if hiddenFileIsOpen() { hiddenCancellation.cancel() }
                    try hiddenCancellation.check()
                }) { _, _ in }
            checks["hiddenDiscoveryCancellationEscapesImmediately"] = false
        } catch SceneDesktopWallpaperHostLaunchError.cancelled {
            checks["hiddenDiscoveryCancellationEscapesImmediately"] = true
        }
        try writeJSON(definition("materials/primary.json", children: [
            "Particles/RenamedChild.JSON", "particles/bad.json"]),
            to: primary.appendingPathComponent("Particles/Renamed.JSON"))
        var boundaries = 0
        _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
            preparedParticleVisibilityLayerIDs: [2], stockTextureBundleURL: nil,
            checkCancellation: { boundaries += 1 })
        var allCancelled = boundaries > 0
        for stopAt in 1...boundaries {
            let token = SceneWallpaperLaunchCancellation()
            var reached = 0
            do {
                _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
                    preparedParticleVisibilityLayerIDs: [2], stockTextureBundleURL: nil,
                    checkCancellation: {
                        reached += 1
                        if reached == stopAt { token.cancel() }
                        try token.check()
                    })
                allCancelled = false
            } catch SceneDesktopWallpaperHostLaunchError.cancelled {
                allCancelled = allCancelled && reached == stopAt
            } catch { allCancelled = false }
        }
        checks["everyBoundaryPreservesProductionCancellation"] = allCancelled
        var allInvalidHandlesEscape = true
        for stopAt in 1...boundaries {
            var reached = 0
            do {
                _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view,
                    preparedParticleVisibilityLayerIDs: [2], stockTextureBundleURL: nil,
                    checkCancellation: {
                        reached += 1
                        if reached == stopAt { throw SceneResourceView.ReadError.invalidHandle }
                    })
                allInvalidHandlesEscape = false
            } catch SceneResourceView.ReadError.invalidHandle {
                allInvalidHandlesEscape = allInvalidHandlesEscape && reached == stopAt
            } catch { allInvalidHandlesEscape = false }
        }
        checks["invalidHandleAtEveryReadBoundaryIsNotLocalFailure"] = allInvalidHandlesEscape
        // The selected Root is captured before its directory is replaced by
        // an alias. This is ResourceView's real sourceChanged producer.
        try FileManager.default.moveItem(at: primary,
            to: root.appendingPathComponent("previous-primary"))
        try FileManager.default.createSymbolicLink(at: primary, withDestinationURL: lower)
        do {
            _ = try SceneParticleRuntime.prepareAssets(descriptor: descriptor,
                resourceView: view, stockTextureBundleURL: nil)
            checks["selectedRootChangeIsHardFailure"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["selectedRootChangeIsHardFailure"] = true
        }
        try printJSON(["checks": checks, "cancellationBoundaries": boundaries,
                       "gpuDeviceCreated": false])
    }

'''


class SceneParticleAssetPreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-preparation-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        directory = Path(cls.temporary_directory.name)
        source = runtime.HARNESS_SOURCES[0].read_text()
        start = source.index("    static func main() throws {")
        end = source.index("    static func renderDescriptor(", start)
        harness = directory / "ParticlePreparation.swift"
        harness.write_text("import Darwin\nenum ParticleDefinitionProbe { static var parses = 0; static var reads: [String: Int] = [:] }\n"
            + source[:start] + MAIN + source[end:])
        sources = list(dict.fromkeys(path.resolve() for path in [*runtime.SWIFT_SOURCES, *assets.SWIFT_SOURCES,
            SCENE / "Runtime/Session/SceneDesktopWallpaperLaunchModels.swift"]))
        parser = (SCENE / "Systems/Particles/SceneParticleDefinitionParser.swift").resolve()
        counted_parser = directory / parser.name
        counted_parser.write_text(parser.read_text().replace(
            "func parse(data: Data) throws -> SceneParticleDefinition {",
            "func parse(data: Data) throws -> SceneParticleDefinition {\n        ParticleDefinitionProbe.parses += 1", 1))
        view = (SCENE / "Resources/Assets/SceneResourceView.swift").resolve()
        counted_view = directory / view.name
        counted_view.write_text(view.read_text().replace("""        ) throws -> Data {
            try owner.readBytes(self, maximumBytes: maximumBytes, within: directory,""",
            """        ) throws -> Data {
            ParticleDefinitionProbe.reads[relativePath, default: 0] += 1
            return try owner.readBytes(self, maximumBytes: maximumBytes, within: directory,""", 1))
        sources = [counted_parser if path == parser else counted_view if path == view else path for path in sources]
        cls.binary = directory / "particle-preparation"
        result = subprocess.run([swiftc, *(str(path) for path in sources), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(directory / "module-cache"), "-o", str(cls.binary)],
            capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    def test_real_preparation_keeps_namespace_local_failures_and_hard_exits(self) -> None:
        result = subprocess.run([str(self.binary)], capture_output=True, text=True, check=True)
        report = json.loads(result.stdout)
        self.assertFalse(report["gpuDeviceCreated"])
        self.assertGreater(report["cancellationBoundaries"], 0)
        for name, passed in report["checks"].items():
            with self.subTest(check=name):
                self.assertTrue(passed)

    def test_throwing_preparation_precedes_launch_candidate_and_runtime_has_no_reader(self) -> None:
        host = (SCENE / "Runtime/Session/SceneDesktopWallpaperHost+Launch.swift").read_text()
        preparation = host.index("preparedParticleAssets = try SceneParticleRuntime.prepareAssets(")
        context = host.index("let context = SceneDesktopWallpaperLaunchContext(", preparation)
        self.assertLess(preparation, context)
        self.assertIn("checkCancellation: { try cancellation?.check() }", host[preparation:context])
        product = (SCENE / "Systems/Particles/SceneParticleRuntime.swift").read_text()
        initializer = product[product.index("    init("):]
        self.assertNotIn("SceneParticleAssetGraphLoader(", initializer)
        self.assertNotIn("Data(contentsOf:", initializer)
        graph = (SCENE / "Systems/Particles/SceneParticleAssetGraph.swift").read_text()
        self.assertNotIn("SceneResourceIndexBuilder", graph)
        self.assertNotIn("cacheDirectory", graph)


if __name__ == "__main__":
    unittest.main()
