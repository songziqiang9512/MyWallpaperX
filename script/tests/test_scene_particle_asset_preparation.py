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
        try writeJSON(definition("materials/ambient.json"),
            to: primary.appendingPathComponent("particles/ambient.json"))
        try writeJSON(definition("materials/renamed-ambient.json"),
            to: primary.appendingPathComponent("particles/renamed-ambient.json"))
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

        func ambientGraph(lamps: [SceneRenderDescriptor.Layer] = [],
                          classes: SceneRenderDescriptor.Lighting.Classes = .init(),
                          combos: [String: Int] = ["REFRACT": 1, "LIGHTING": 1],
                          textures: [String] = ["probe"], layerID: Int = 70,
                          height: Float? = 1080, sourceOrtho: Bool? = true,
                          path: String = "particles/ambient.json", material: String = "materials/ambient.json",
                          cullMode: String = "nocull") throws -> SceneParticleAssetGraph {
            let litPass = SceneRenderDescriptor.MaterialPassDescriptor(
                materialPath: material, shaderPath: "genericparticle",
                texturePaths: textures, blending: "translucent", combos: combos, cullMode: cullMode)
            let unlitPass = SceneRenderDescriptor.MaterialPassDescriptor(materialPath: pass.materialPath,
                shaderPath: "genericparticle", texturePaths: ["probe"], blending: "translucent",
                combos: ["REFRACT": 1, "LIGHTING": 0])
            var input = SceneRenderDescriptor(layers: [layer(layerID, path),
                layer(71, "Particles/Renamed.JSON")] + lamps,
                renderOrderLayerIDs: [layerID, 71] + lamps.map(\.id), materialPasses: [litPass, unlitPass])
            input.lighting = .init(lightClasses: classes)
            input.camera = .init(authoredOrthographicProjectionActive: sourceOrtho)
            input.camera.orthoHeight = height
            return try SceneParticleRuntime.prepareAssets(descriptor: input, resourceView: view,
                stockTextureBundleURL: nil)
        }
        func lightingCheck(_ name: String, _ value: SceneParticleAssetGraph, accepted: Bool,
                           path: String = "particles/ambient.json", expectedLighting: Bool = true) {
            let asset = value.assetsByPath[path]
            checks[name] = (accepted
                ? asset?.textureSource != nil && asset?.refraction?.usesAmbientLighting == expectedLighting
                : asset?.textureSource == nil && value.diagnostics.contains {
                    $0.assetPath == path && $0.kind == .refractionUnsupported })
                && value.assetsByPath["particles/renamed.json"]?.textureSource != nil
                && value.assetsByPath["particles/renamed.json"]?.refraction?.usesAmbientLighting == false
        }
        func lamp(_ id: Int, point: SceneRenderDescriptor.Layer.PointLight? = nil,
                  directional: SceneRenderDescriptor.Layer.DirectLight? = nil,
                  spot: SceneRenderDescriptor.Layer.DirectLight? = nil) -> SceneRenderDescriptor.Layer {
            .init(id: id, name: "renamed hidden zero-strength lamp", contentKind: "light",
                particlePath: nil, particleInstanceOverride: nil, parentID: nil,
                visible: false, displayScriptOwnership: .init(visible: true, alpha: false), alpha: 1,
                pointLight: point, directionalLight: directional, spotLight: spot)
        }
        lightingCheck("ambientWithNoPotentialLights", try ambientGraph(), accepted: true)
        lightingCheck("ambientRenamedLayerID", try ambientGraph(layerID: 970), accepted: true)
        lightingCheck("ambientMissingOrthoHeightRejected", try ambientGraph(height: nil), accepted: false)
        lightingCheck("ambientNativePerspectiveRejected", try ambientGraph(height: nil, sourceOrtho: false), accepted: false)
        let modern = lamp(301, point: .init(kind: "lpoint", intensity: 0))
        let legacy = lamp(302, point: .init(kind: "point", intensity: 0))
        let directional = lamp(303, directional: .init(intensity: 0))
        let spot = lamp(304, spot: .init(intensity: 0))
        lightingCheck("disabledModernPointClassIsInert", try ambientGraph(lamps: [modern]), accepted: true)
        lightingCheck("legacyPointRemainsPotentialWithoutClass", try ambientGraph(lamps: [legacy]), accepted: false)
        lightingCheck("hiddenZeroModernPointRemainsPotential", try ambientGraph(lamps: [modern],
            classes: .init(point: true)), accepted: false)
        lightingCheck("disabledDirectionalAndSpotClassesAreInert", try ambientGraph(lamps: [directional, spot]), accepted: true)
        lightingCheck("hiddenZeroDirectionalRemainsPotential", try ambientGraph(lamps: [directional],
            classes: .init(directional: true)), accepted: false)
        lightingCheck("hiddenZeroSpotRemainsPotential", try ambientGraph(lamps: [spot],
            classes: .init(spot: true)), accepted: false)
        for double in [0, 1] {
            let combos = ["REFRACT": 1, "LIGHTING": 1, "DOUBLESIDEDLIGHTING": double]
            let value = try ambientGraph(combos: combos)
            lightingCheck("ambientAcceptsDouble-\(double)", value, accepted: true)
            checks["doubleKeepsNoCull-\(double)"] = value.assetsByPath["particles/ambient.json"]?.renderState?.cullMode == .noCull
                && value.assetsByPath["particles/ambient.json"]?.pipelineState?.cullMode == SceneParticlePipelineCullMode.none
            lightingCheck("unlitAcceptsDouble-\(double)", try ambientGraph(
                combos: ["REFRACT": 1, "LIGHTING": 0, "DOUBLESIDEDLIGHTING": double]),
                accepted: true, expectedLighting: false)
            lightingCheck("missingLightingAcceptsDouble-\(double)", try ambientGraph(
                combos: ["REFRACT": 1, "DOUBLESIDEDLIGHTING": double]),
                accepted: true, expectedLighting: false)
        }
        let doubleOne = ["REFRACT": 1, "LIGHTING": 1, "DOUBLESIDEDLIGHTING": 1]
        let unlitDouble = ["REFRACT": 1, "LIGHTING": 0, "DOUBLESIDEDLIGHTING": 1]
        lightingCheck("unlitDoubleWithoutAmbientEnvironment", try ambientGraph(combos: unlitDouble, height: nil),
            accepted: true, expectedLighting: false)
        lightingCheck("unlitDoubleWithPotentialLamp", try ambientGraph(lamps: [modern],
            classes: .init(point: true), combos: unlitDouble), accepted: true, expectedLighting: false)
        let renamedDouble = try ambientGraph(combos: doubleOne, layerID: 971,
            path: "particles/renamed-ambient.json", material: "materials/renamed-ambient.json")
        lightingCheck("doubleRenamedMaterialAndID", renamedDouble, accepted: true,
            path: "particles/renamed-ambient.json")
        checks["doubleRenamedConsumerEquivalent"] = renamedDouble.assetsByPath["particles/renamed-ambient.json"]?.refraction
            == (try ambientGraph(combos: doubleOne)).assetsByPath["particles/ambient.json"]?.refraction
        let backCull = try ambientGraph(combos: doubleOne, cullMode: "normal")
        lightingCheck("doubleWithBackCull", backCull, accepted: true)
        checks["doubleDoesNotDisableRasterCull"] = backCull.assetsByPath["particles/ambient.json"]?.renderState?.cullMode == .normal
            && backCull.assetsByPath["particles/ambient.json"]?.pipelineState?.cullMode == .back
        lightingCheck("doubleMissingAmbientEnvironment", try ambientGraph(combos: doubleOne, height: nil), accepted: false)
        lightingCheck("doubleHiddenZeroLampStillPotential", try ambientGraph(lamps: [modern],
            classes: .init(point: true), combos: doubleOne), accepted: false)
        lightingCheck("doubleLegacyLampStillPotential", try ambientGraph(lamps: [legacy], combos: doubleOne), accepted: false)
        lightingCheck("doubleOutOfDomain", try ambientGraph(
            combos: ["REFRACT": 1, "LIGHTING": 1, "DOUBLESIDEDLIGHTING": 2]), accepted: false)
        lightingCheck("doubleUnsupportedLighting", try ambientGraph(
            combos: ["REFRACT": 1, "LIGHTING": 2, "DOUBLESIDEDLIGHTING": 1]), accepted: false)
        for name in ["UNKNOWN", "CUTOUT"] {
            lightingCheck("ambientRejects-\(name)", try ambientGraph(
                combos: ["REFRACT": 1, "LIGHTING": 1, name: 1]), accepted: false)
            lightingCheck("doubleRejects-\(name)", try ambientGraph(
                combos: ["REFRACT": 1, "LIGHTING": 1, "DOUBLESIDEDLIGHTING": 1, name: 1]), accepted: false)
        }
        lightingCheck("ambientBadNormalKeepsPeer", try ambientGraph(textures: ["probe", "absent-normal"]), accepted: false)
        let missingColor = try ambientGraph(textures: ["absent-color"])
        checks["ambientBadColorKeepsPeer"] = missingColor.assetsByPath["particles/ambient.json"]?.textureSource == nil
            && missingColor.diagnostics.contains { $0.kind == .missingTextureFile
                && $0.assetPath == "particles/ambient.json" }
            && missingColor.assetsByPath["particles/renamed.json"]?.textureSource != nil
            && missingColor.assetsByPath["particles/renamed.json"]?.refraction?.usesAmbientLighting == false
        let rawLit = SceneParticleMaterialPass(materialPath: "materials/ambient.json", shaderPath: "genericparticle",
            texturePaths: ["probe"], blending: "translucent",
            combos: ["REFRACT": 1, "LIGHTING": 1, "DOUBLESIDEDLIGHTING": 1])
        let state = SceneMaterialRenderState.compile(blending: "translucent", depthTest: "disabled",
            depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!
        checks["planRequiresExplicitAmbientSupport"] = SceneParticleRefractionPlanner.plan(
            for: rawLit, renderState: state) == nil && SceneParticleRefractionPlanner.plan(
                for: rawLit, renderState: state, supportsAmbientLighting: true)?.usesAmbientLighting == true
        let conservative = try SceneParticleAssetGraphLoader(resourceView: view, stockTextureBundleURL: nil)
            .load(rootPaths: ["particles/ambient.json"], materialPasses: [rawLit])
        checks["graphDefaultDoesNotAssumeAmbientSupport"] =
            conservative.assetsByPath["particles/ambient.json"]?.textureSource == nil

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
