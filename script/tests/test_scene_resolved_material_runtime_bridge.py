#!/usr/bin/env python3

"""R3 production catalog/resource bridge contracts."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RUNTIME_CATALOG = (
    SCENE_ROOT / "RenderGraph/SceneResolvedMaterialRuntimeCatalog.swift"
)
RUNTIME_BRIDGE = (
    SCENE_ROOT / "Runtime/SceneResolvedMaterialRuntimeBridge.swift"
)
ASSET_CATALOG = (
    SCENE_ROOT / "Resources/SceneMaterialAssetTextureCatalog.swift"
)
LAUNCH = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
HOST = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
TEXTURE_FRAME = SCENE_ROOT / "Rendering/SceneMetalRenderer+TextureFrame.swift"
COMPOSITOR = SCENE_ROOT / "Rendering/SceneImageLayerCompositor.swift"

ASSET_HARNESS = r'''
import Foundation
import Metal

struct SceneVFSAssetPath: Hashable { let value: String }
enum SceneTextureLoadPurpose: String, Hashable {
    case mask, flow
    var reportToken: String { rawValue }
}
struct SceneAssetTextureIdentity: Hashable {
    let path: SceneVFSAssetPath
    let purpose: SceneTextureLoadPurpose
    var reportToken: String { "\(path.value):\(purpose.rawValue)" }
}
enum SceneFrameTextureIdentity: Equatable { case asset(SceneAssetTextureIdentity) }
struct SceneTextureCandidate { let purpose: SceneTextureLoadPurpose; let complete: Bool }
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var isComplete: Bool { candidate.complete }
}
enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication), absent, pending, unavailable
}
struct SceneRenderDescriptor {}
struct SceneResourceView { let urls: [String: URL] }
struct SceneTexturePathResolver {
    let resourceView: SceneResourceView
    init(resourceView: SceneResourceView, descriptor: SceneRenderDescriptor) {
        self.resourceView = resourceView
    }
    func resolveTextureFile(named name: String) -> URL? { resourceView.urls[name] }
}
enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate), failed(Int)
}
final class SceneTextureLoader {
    func loadCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureCandidateLoadOutcome {
        if url.lastPathComponent == "bad" { return .failed(1) }
        return .loaded(.init(
            purpose: purpose,
            complete: url.lastPathComponent != "incomplete"
        ))
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        func identity(_ path: String, _ purpose: SceneTextureLoadPurpose) -> SceneAssetTextureIdentity {
            .init(path: .init(value: path), purpose: purpose)
        }
        let goodMask = identity("good", .mask)
        let goodFlow = identity("good", .flow)
        let missing = identity("missing", .mask)
        let bad = identity("bad", .mask)
        let incomplete = identity("incomplete", .mask)
        let catalog = SceneMaterialAssetTextureCatalog(
            demands: [goodMask, goodFlow, missing, bad, incomplete],
            resourceView: .init(urls: [
                "good": URL(fileURLWithPath: "/tmp/good"),
                "bad": URL(fileURLWithPath: "/tmp/bad"),
                "incomplete": URL(fileURLWithPath: "/tmp/incomplete"),
            ]),
            descriptor: .init(),
            device: device
        )
        func disposition(_ identity: SceneAssetTextureIdentity) -> String {
            switch catalog.states[identity] {
            case let .ready(publication):
                return publication.requestIdentity == .asset(identity)
                    && publication.candidate.purpose == identity.purpose
                    && publication.contentGeneration == 1 ? "ready" : "invalid"
            case .absent: return "absent"
            case .pending: return "pending"
            case .unavailable: return "unavailable"
            case nil: return "missing-state"
            }
        }
        let output: [String: Any] = [
            "available": true,
            "goodMask": disposition(goodMask),
            "goodFlow": disposition(goodFlow),
            "missing": disposition(missing),
            "bad": disposition(bad),
            "incomplete": disposition(incomplete),
            "stateCount": catalog.states.count,
            "report": catalog.reportLines.joined(separator: "\n"),
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

VFS_SUPPORT = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer { let imagePath: String? }
    struct ModelMaterialLink { let modelPath: String; let materialPath: String? }
    struct MaterialPassDescriptor { let materialPath: String; let texturePaths: [String] }
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

@main
enum Harness {
    static func main() throws {
        let package = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loose = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stock = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: loose,
            packageRootURL: package,
            stockAssetsRootURL: stock
        )
        let resolver = SceneTexturePathResolver(
            resourceView: view,
            descriptor: .init(modelMaterialLinks: [], materialPasses: [])
        )
        let output = [
            "shared": resolver.resolveTextureFile(named: "materials/shared.png")?.path ?? "",
            "bare": resolver.resolveTextureFile(named: "bare")?.path ?? "",
            "stock": resolver.resolveTextureFile(named: "assets/stock-only.png")?.path ?? "",
            "missing": resolver.resolveTextureFile(named: "missing")?.path ?? "",
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

RUNTIME_BRIDGE_HARNESS = r'''
import Foundation
import simd

struct SceneTextureLoadPurpose: Hashable {
    let name: String
    static let premultipliedColor = Self(name: "premultiplied-color")
}
struct SceneAssetTextureIdentity: Hashable {}
enum SceneTextureProviderState { case unavailable }
struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose

    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey
        self.purpose = purpose
    }
}
struct SceneResolvedMaterialTemplate {}
struct SceneResolvedMaterialProgram {}

struct SceneResolvedMaterialFailure: Error {
    enum Phase: String { case graph }
    enum Code: String { case graphNodeInvalid }
    let phase: Phase
    let code: Code
    let details: [String]
    init(phase: Phase, code: Code, details: [String] = []) {
        self.phase = phase
        self.code = code
        self.details = details
    }
}

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Hashable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
    struct TextureIdentity: Hashable { let value: Int }
    enum NodeKind { case material, copy, swap }
    struct Node {
        let kind: NodeKind
        let effect: EffectKey
        let nodeIndex: Int
        let target: TextureIdentity?
    }
    let nodes: [Node]
}

struct SceneResolvedMaterialRuntimeCatalog {
    struct Key: Hashable {
        let effect: SceneAuthoredEffectRenderPlan.EffectKey
        let nodeIndex: Int
    }
    enum Entry {
        case template(SceneResolvedMaterialTemplate)
        case failure(SceneResolvedMaterialFailure)
    }
    struct SystemProviderDemand: Hashable {
        let name: String
        let purpose: SceneTextureLoadPurpose
    }
    let entries: [Key: Entry]
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SystemProviderDemand>
    func entry(for node: SceneAuthoredEffectRenderPlan.Node) -> Entry? {
        entries[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
    }
}

struct SceneMaterialAssetTextureCatalog {
    let states: [SceneAssetTextureIdentity: SceneTextureProviderState]
}
struct SceneFrameTextureRegistrySnapshot { let valid: Bool }
struct SceneDynamicSnapshot {}
struct SceneAuthoredShaderFrameInputs {}
struct SceneResolvedMaterialFinalizationInput {}

struct SceneResolvedMaterialFrameSnapshot {
    static func validated(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) -> Result<Self, SceneResolvedMaterialFailure> {
        textureSnapshot.valid
            ? .success(.init())
            : .failure(.init(phase: .graph, code: .graphNodeInvalid))
    }
    func finalizationInput(
        template: SceneResolvedMaterialTemplate,
        renderSize: CGSize,
        modelViewProjection: simd_float4x4
    ) -> SceneResolvedMaterialFinalizationInput {
        .init()
    }
}

enum SceneResolvedMaterialProgramFinalizer {
    static var calls = 0
    static func finalize(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<SceneResolvedMaterialProgram, SceneResolvedMaterialFailure> {
        calls += 1
        return .success(.init())
    }
}

struct StubTarget { let width: Int; let height: Int }
struct SceneGraphRenderTargetTable {
    let targets: [SceneAuthoredEffectRenderPlan.TextureIdentity: StubTarget]
    func texture(
        for identity: SceneAuthoredEffectRenderPlan.TextureIdentity
    ) -> StubTarget? {
        targets[identity]
    }
}

final class StubTexture {}
enum SceneFrameTextureIdentity: Equatable { case system(String) }
struct StubCandidate { let purpose: SceneTextureLoadPurpose }
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let texture: StubTexture
    let candidate: StubCandidate
    let isComplete: Bool
}
enum SceneFrameTextureRegistry {
    enum ProviderStatus { case unavailable }
}
enum SceneMediaThumbnailTextureStore {
    struct Snapshot {
        let systemTextures: [String: StubTexture]
        let publications: [String: SceneTextureProviderPublication]
    }
}

@main
enum Harness {
    static func main() throws {
        let effect = SceneAuthoredEffectRenderPlan.EffectKey(
            layerID: 7,
            effectIndex: 3,
            descriptorID: "raw"
        )
        let target = SceneAuthoredEffectRenderPlan.TextureIdentity(value: 1)
        let node = SceneAuthoredEffectRenderPlan.Node(
            kind: .material,
            effect: effect,
            nodeIndex: 4,
            target: target
        )
        let graph = SceneAuthoredEffectRenderPlan(nodes: [node])
        let observedKey = SceneResolvedMaterialRuntimeCatalog.Key(
            effect: effect,
            nodeIndex: 4
        )
        let rawOnlyKey = SceneResolvedMaterialRuntimeCatalog.Key(
            effect: .init(layerID: 8, effectIndex: 0, descriptorID: "raw-only"),
            nodeIndex: 0
        )
        let purpose = SceneTextureLoadPurpose(name: "color")
        let catalog = SceneResolvedMaterialRuntimeCatalog(
            entries: [
                observedKey: .template(.init()),
                rawOnlyKey: .template(.init()),
            ],
            userPropertyDemands: [],
            systemProviderDemands: [.init(name: "current", purpose: purpose)]
        )
        let rawBridge = SceneResolvedMaterialRuntimeBridge(
            catalog: catalog,
            assets: .init(states: [:])
        )
        rawBridge.beginFrame(
            textureSnapshot: .init(valid: true),
            dynamicSnapshot: .init(),
            frameInputs: .init()
        )
        let rawReport = rawBridge.endFrame().joined(separator: "\n")

        let bridge = SceneResolvedMaterialRuntimeBridge(
            catalog: catalog,
            assets: .init(states: [:])
        )
        let declaredDemands = bridge.userPropertyDemands(
            including: ["declared", ""]
        )
        bridge.beginFrame(
            textureSnapshot: .init(valid: true),
            dynamicSnapshot: .init(),
            frameInputs: .init()
        )
        bridge.auditResolvedMaterials(
            graph: graph,
            targets: .init(targets: [target: .init(width: 16, height: 8)])
        )
        let observedReport = bridge.endFrame().joined(separator: "\n")
        let callsAfterFrame = SceneResolvedMaterialProgramFinalizer.calls
        bridge.beginFrame(
            textureSnapshot: .init(valid: true),
            dynamicSnapshot: .init(),
            frameInputs: .init()
        )
        bridge.auditResolvedMaterials(
            graph: graph,
            targets: .init(targets: [target: .init(width: 16, height: 8)])
        )
        let repeatedReport = bridge.endFrame().joined(separator: "\n")

        let missing = bridge.systemProviderBlocks(for: .init(
            systemTextures: [:],
            publications: [:]
        ))
        let texture = StubTexture()
        let publication = SceneTextureProviderPublication(
            requestIdentity: .system("current"),
            texture: texture,
            candidate: .init(purpose: purpose),
            isComplete: true
        )
        let ready = bridge.systemProviderBlocks(for: .init(
            systemTextures: ["current": texture],
            publications: ["current": publication]
        ))
        let mismatch = bridge.systemProviderBlocks(for: .init(
            systemTextures: ["current": texture],
            publications: ["current": .init(
                requestIdentity: .system("current"),
                texture: texture,
                candidate: .init(purpose: .init(name: "mask")),
                isComplete: true
            )]
        ))
        func status(
            _ values: [String: SceneFrameTextureRegistry.ProviderStatus]
        ) -> String {
            guard let value = values["current"] else { return "ready" }
            switch value { case .unavailable: return "unavailable" }
        }
        let output: [String: Any] = [
            "rawReport": rawReport,
            "observedReport": observedReport,
            "repeatedReport": repeatedReport,
            "callsAfterFrame": callsAfterFrame,
            "callsAfterInactiveAudit": SceneResolvedMaterialProgramFinalizer.calls,
            "missing": status(missing),
            "ready": status(ready),
            "mismatch": status(mismatch),
            "declaredDemandCount": declaredDemands.count,
            "declaredDemandPurpose": declaredDemands.first?.purpose.name ?? "",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: output,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResolvedMaterialRuntimeBridgeTests(unittest.TestCase):
    def test_static_catalog_is_built_from_raw_graph_nodes(self) -> None:
        source = RUNTIME_CATALOG.read_text(encoding="utf-8")
        self.assertIn("authoredPlans: [Graph]", source)
        self.assertIn("for graph in authoredPlans", source)
        self.assertIn("node.kind == .material", source)
        self.assertIn("let effect: Graph.EffectKey", source)
        self.assertIn("let nodeIndex: Int", source)
        self.assertNotIn("SceneAuthoredEffectExecutionCatalog", source)
        self.assertNotIn("sampleID", source)

    def test_resource_demands_share_schema_and_never_guess_regular_assets(self) -> None:
        source = RUNTIME_CATALOG.read_text(encoding="utf-8")
        self.assertIn("SceneResolvedMaterialShaderSchema.unconditionalSamplers", source)
        self.assertIn("sampler.purpose(for: reference)", source)
        self.assertIn("userPropertyDemands", source)
        self.assertIn("systemProviderDemands", source)
        self.assertIn("sampler-schema-unavailable", source)
        self.assertIn("texture-purpose-unproven", source)
        self.assertNotIn("purpose: .premultipliedColor", source)

    def test_asset_catalog_is_eager_exact_and_fail_closed(self) -> None:
        source = ASSET_CATALOG.read_text(encoding="utf-8")
        self.assertIn("SceneTexturePathResolver", source)
        self.assertIn("resolveTextureFile(named: identity.path.value)", source)
        self.assertIn("purpose: identity.purpose", source)
        self.assertIn("requestIdentity: request", source)
        self.assertIn("loaded[identity] = .absent", source)
        self.assertIn("loaded[identity] = .unavailable", source)
        self.assertIn("let states:", source)
        self.assertNotIn("sampleID", source)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_runtime_bridge_counts_raw_nodes_and_closes_frame_lifecycle(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-r3-runtime-bridge-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "runtime-bridge"
            harness.write_text(RUNTIME_BRIDGE_HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(RUNTIME_BRIDGE), str(harness),
                    "-framework", "Metal",
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            result = json.loads(completed.stdout)
            self.assertIn(
                "nodes=2 finalizationAttempted=0 accepted=0 failures=2",
                result["rawReport"],
            )
            self.assertIn(
                "code=render-path-unavailable count=2",
                result["rawReport"],
            )
            self.assertIn(
                "nodes=2 finalizationAttempted=1 accepted=1 failures=1",
                result["observedReport"],
            )
            self.assertIn("mode=first-active-frame", result["observedReport"])
            self.assertIn(
                "code=render-path-unavailable count=1",
                result["observedReport"],
            )
            self.assertIn("state=inactive", result["repeatedReport"])
            self.assertEqual(result["callsAfterFrame"], 1)
            self.assertEqual(result["callsAfterInactiveAudit"], 1)
            self.assertEqual(result["missing"], "unavailable")
            self.assertEqual(result["ready"], "ready")
            self.assertEqual(result["mismatch"], "unavailable")
            self.assertEqual(result["declaredDemandCount"], 1)
            self.assertEqual(result["declaredDemandPurpose"], "premultiplied-color")

    def test_production_wiring_uses_frame_snapshot_without_gpu_admission(self) -> None:
        launch = LAUNCH.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        texture_frame = TEXTURE_FRAME.read_text(encoding="utf-8")
        compositor = COMPOSITOR.read_text(encoding="utf-8")
        runtime_bridge = RUNTIME_BRIDGE.read_text(encoding="utf-8")
        self.assertIn("SceneResolvedMaterialRuntimeCatalog", launch)
        self.assertIn("SceneMaterialAssetTextureCatalog", launch)
        self.assertIn("assetStates:", texture_frame)
        self.assertIn("SceneResolvedMaterialFrameSnapshot.validated", runtime_bridge)
        self.assertIn("for (key, entry) in catalog.entries", runtime_bridge)
        self.assertIn("finalizationAttempted=", runtime_bridge)
        self.assertIn("auditResolvedMaterials", compositor)
        self.assertIn("gpuEncoded=0", runtime_bridge)
        self.assertIn('logSink: @escaping LogSink = { NSLog("%@", $0) }', runtime_bridge)
        self.assertIn("lines.forEach(logSink)", runtime_bridge)
        self.assertNotIn("sourceIsExact", runtime_bridge + compositor)
        self.assertNotIn("FileHandle", runtime_bridge)
        self.assertIn("resolvedMaterialStartupReportLines", launch)
        self.assertIn("appendResolvedMaterialStartupReport", host)
        self.assertIn("missingState=unavailable", launch)
        self.assertIn("systemProviderBlocks", runtime_bridge)
        self.assertIn("textureRegistry.set(status, for: .system(name))", texture_frame)
        registry_begin = texture_frame.index("textureRegistry.beginFrame")
        system_blocks = texture_frame.index("resolvedMaterialSystemProviderBlocks")
        snapshot = texture_frame.index("textureRegistry.snapshot()")
        envelope_begin = texture_frame.index("beginResolvedMaterialFrame")
        self.assertLess(registry_begin, system_blocks)
        self.assertLess(system_blocks, snapshot)
        self.assertLess(registry_begin, envelope_begin)
        self.assertLess(envelope_begin, snapshot)
        chain_audit = compositor.index("auditResolvedMaterials")
        chain_render = compositor.index("SceneAuthoredEffectChainRenderer.render")
        standalone_audit = compositor.index("auditResolvedMaterials", chain_audit + 1)
        standalone_render = compositor.index("SceneStandaloneAuthoredEffectRenderer.render")
        self.assertLess(chain_audit, chain_render)
        self.assertLess(standalone_audit, standalone_render)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_asset_states_keep_purpose_absence_and_failure_distinct(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-r3-asset-catalog-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "asset-catalog"
            harness.write_text(ASSET_HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(ASSET_CATALOG), str(harness),
                    "-framework", "Metal",
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)], check=True, capture_output=True, text=True
            )
            result = json.loads(completed.stdout)
            if not result["available"]:
                self.skipTest("Metal device unavailable")
            self.assertEqual(result["goodMask"], "ready")
            self.assertEqual(result["goodFlow"], "ready")
            self.assertEqual(result["missing"], "absent")
            self.assertEqual(result["bad"], "unavailable")
            self.assertEqual(result["incomplete"], "unavailable")
            self.assertEqual(result["stateCount"], 5)
            self.assertIn("ready=2 absent=1", result["report"])
            self.assertIn("unavailable=2", result["report"])

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_texture_vfs_preserves_package_loose_stock_precedence(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-r3-vfs-") as directory:
            root = Path(directory)
            package, loose, stock = root / "package", root / "loose", root / "stock"
            for path in (package, loose, stock):
                path.mkdir()
            for base in (package, loose, stock):
                (base / "materials").mkdir()
                (base / "materials/shared.png").write_bytes(b"x")
            (package / "materials/bare.png").write_bytes(b"x")
            (stock / "stock-only.png").write_bytes(b"x")
            harness = root / "Harness.swift"
            binary = root / "vfs"
            harness.write_text(VFS_SUPPORT, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    str(SCENE_ROOT / "Resources/SceneResourceIndex.swift"),
                    str(SCENE_ROOT / "Resources/SceneResourceView.swift"),
                    str(SCENE_ROOT / "Resources/SceneTexturePathResolver.swift"),
                    str(harness), "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(package), str(loose), str(stock)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = json.loads(completed.stdout)
            self.assertTrue(Path(result["shared"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["bare"]).resolve().is_relative_to(package.resolve()))
            self.assertTrue(Path(result["stock"]).resolve().is_relative_to(stock.resolve()))
            self.assertEqual(result["missing"], "")


if __name__ == "__main__":
    unittest.main()
