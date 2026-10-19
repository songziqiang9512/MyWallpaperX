"""Real SourceFacts/descriptor/MDL cancellation boundaries and ordinary failures.

The existing disk-builder source set supplies production parsing, source facts,
descriptor and ModelBuilder. The production cancellation token/error are linked
unchanged. Only the shader-interface leaf is a controlled unavailable result;
its callback cancels during one synchronous proof to test the next boundary.
No App, GPU execution or performance measurement is involved.
"""
from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_static_model_parts as parts


REPO = Path(__file__).resolve().parents[2]
SCENE = REPO / "MyWallpaperX/Core/SteamWorkshopScene"

PROOF_LEAF = r'''
enum ProofLeaf {
    static var calls: [String] = []
    static var onCompile: (() -> Void)?
    static func reset() { calls = []; onCompile = nil }
}
enum SceneStaticModelMaterialBindingCompiler {
    static func defaultAlbedoAssetPath<Contract>(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        shaderContracts: [Contract]
    ) -> String? { nil }
    static func compile<Contract>(
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        shaderContracts: [Contract]
    ) -> SceneStaticModelMaterialBindings {
        ProofLeaf.calls.append(pass.id)
        ProofLeaf.onCompile?()
        return .init(state: .unavailable, bindings: [], rejectionReason: "fixture-shader-boundary")
    }
}
'''

MAIN = r'''
@main enum CancellationProbe {
    static func projection(_ facts: SceneRuntimeSourceFacts) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let descriptor = try facts.renderDescriptor.map { try encoder.encode($0).base64EncodedString() }
        return try JSONSerialization.data(withJSONObject: [
            "project": facts.project?.entryPath ?? "missing",
            "document": facts.sceneDocument != nil,
            "documentError": facts.sceneDocumentLoadErrorDescription ?? "",
            "catalog": facts.assetCatalog != nil,
            "materials": facts.assetCatalog?.materials.map(\.relativePath) ?? [],
            "packageFailure": facts.packageReport?.blockingMessage ?? "",
            "descriptor": descriptor ?? "missing",
        ], options: [.sortedKeys])
    }

    static func sourceCases(_ root: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for name in ["valid", "bad-model", "bad-document", "bad-project", "bad-package"] {
            let folder = root.appendingPathComponent(name)
            ProofLeaf.reset()
            // These calls deliberately omit `try`: the default nil and a
            // nonthrowing callback must preserve all existing caller syntax.
            let plain = SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
            let plainProjection = try projection(plain)
            let plainProofCalls = ProofLeaf.calls
            ProofLeaf.reset()
            var total = 0
            let observed = SceneRuntimeSourceFactsBuilder().build(
                rootURL: folder, checkCancellation: { total += 1 })
            checks[name + "-ordinaryProjectionUnchanged"] = try projection(observed) == plainProjection
                && ProofLeaf.calls == plainProofCalls
            var allCancelled = total > 0
            for offset in 0..<total {
                let stopAt = offset + 1
                ProofLeaf.reset()
                let token = SceneWallpaperLaunchCancellation()
                var reached = 0
                do {
                    _ = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder,
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
            checks[name + "-everyBoundaryPreservesCancellation"] = allCancelled
            if name == "bad-model" {
                checks["badModelKeepsPeerAndMaterialCatalog"] =
                    plain.renderDescriptor?.modelMaterialLinks.contains { $0.modelPath == "models/parts.mdl" } == false
                    && plain.renderDescriptor?.modelMaterialLinks.contains { $0.modelPath == "models/peer.mdl" } == true
                    && plain.assetCatalog?.materials.count == 4
            } else if name == "bad-project" {
                checks["ordinaryProjectFailureRemainsOptional"] = plain.project == nil && plain.renderDescriptor == nil
            } else if name == "bad-document" {
                checks["ordinaryDocumentFailureRetainsDescription"] = plain.sceneDocument == nil
                    && plain.sceneDocumentLoadErrorDescription != nil && plain.renderDescriptor == nil
            } else if name == "bad-package" {
                checks["ordinaryPackageFailureRetainsReport"] = plain.packageReport?.blockingMessage != nil
            }
        }
        return checks
    }

    static func descriptorCases(_ root: URL) throws -> [String: Bool] {
        ProofLeaf.reset()
        let facts = SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent("valid"))
        guard let project = facts.project, let document = facts.sceneDocument,
              let catalog = facts.assetCatalog, let descriptor = facts.renderDescriptor else {
            fatalError("valid disk chain did not prepare descriptor")
        }
        let builder = SceneRenderDescriptorBuilder()
        let direct = descriptor.modelMaterialLinks
        ProofLeaf.reset()
        let ordinary = builder.build(project: project, sceneDocument: document, assetCatalog: catalog,
            directStaticModelMaterialLinks: direct)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let expected = try encoder.encode(ordinary)
        let expectedCalls = ProofLeaf.calls
        var count = 0
        ProofLeaf.reset()
        let observed = builder.build(project: project, sceneDocument: document, assetCatalog: catalog,
            directStaticModelMaterialLinks: direct, checkCancellation: { count += 1 })
        var checks = ["descriptorNoopPreservesFullProjection": try encoder.encode(observed) == expected
            && ProofLeaf.calls == expectedCalls && expectedCalls.count > 1]
        let token = SceneWallpaperLaunchCancellation()
        ProofLeaf.reset()
        ProofLeaf.onCompile = { token.cancel() }
        do {
            _ = try builder.build(project: project, sceneDocument: document, assetCatalog: catalog,
                directStaticModelMaterialLinks: direct, checkCancellation: { try token.check() })
            checks["cancelDuringProofStopsBeforeNextPass"] = false
        } catch SceneDesktopWallpaperHostLaunchError.cancelled {
            checks["cancelDuringProofStopsBeforeNextPass"] = ProofLeaf.calls.count == 1
        }
        ProofLeaf.reset()
        let recovered = builder.build(project: project, sceneDocument: document, assetCatalog: catalog,
            directStaticModelMaterialLinks: direct)
        checks["cancelledInvocationDoesNotPoisonNextBuild"] = try encoder.encode(recovered) == expected
            && ProofLeaf.calls == expectedCalls
        return checks
    }

    static func modelCases(_ root: URL) throws -> [String: Bool] {
        let token = SceneWallpaperLaunchCancellation(); token.cancel()
        var checks: [String: Bool] = [:]
        do {
            _ = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent("bad-project"),
                checkCancellation: { try token.check() })
            checks["modelCancellationPrecedesMissingProject"] = false
        } catch SceneDesktopWallpaperHostLaunchError.cancelled {
            checks["modelCancellationPrecedesMissingProject"] = true
        }
        do {
            _ = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent("bad-project"))
            checks["modelOrdinaryMissingProjectUnchanged"] = false
        } catch SceneRuntimeModelBuilder.BuildError.missingProject {
            checks["modelOrdinaryMissingProjectUnchanged"] = true
        }
        ProofLeaf.reset()
        let plain = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent("valid"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let observed = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent("valid"),
            checkCancellation: {})
        checks["modelDefaultAndNoopResultsEqual"] = try encoder.encode(plain.renderDescriptor)
            == encoder.encode(observed.renderDescriptor)
        return checks
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let home = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        precondition(FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL == home,
            "refusing fixture package work outside isolated HOME")
        var checks = try sourceCases(root)
        checks.merge(try descriptorCases(root)) { _, new in new }
        checks.merge(try modelCases(root)) { _, new in new }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneSourcePreparationCancellationTests(unittest.TestCase):
    def test_real_source_descriptor_mdl_and_model_boundaries(self):
        if shutil.which("xcrun") is None:
            self.skipTest("Xcode tools unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-source-cancellation-") as temporary:
            work = Path(temporary)
            root, home = work / "fixtures", work / "home"
            home.mkdir()
            for name in ["valid", "bad-model", "bad-document", "bad-project", "bad-package"]:
                entries, _ = parts.native_fixture(3, bad=name == "bad-model")
                if name == "bad-document":
                    entries["scene.json"] = b"{invalid"
                elif name == "bad-project":
                    entries["project.json"] = b"{invalid"
                elif name == "bad-package":
                    entries["scene.pkg"] = b"invalid-package"
                for relative, data in entries.items():
                    path = root / name / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
            support = parts.builder_support().split("@main enum PartsDependencies", 1)[0]
            sources = list(dict.fromkeys([*parts.builder.SWIFT_SOURCES, *parts.reader.SWIFT_SOURCES,
                SCENE / "Runtime/Session/SceneDesktopWallpaperLaunchModels.swift"]))
            sources = [p for p in sources if p.name != "SceneStaticModelMaterialBindingUnavailableStub.swift"]
            harness, binary = work / "Harness.swift", work / "probe"
            harness.write_text(support + PROOF_LEAF + MAIN)
            identities = {path: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in [*sources, harness, Path(__file__)]}
            built = subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
                *map(str, sources), str(harness), "-module-cache-path", str(work / "module-cache"),
                "-framework", "Metal", "-o", str(binary)], capture_output=True, text=True, timeout=240)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            for path, identity in identities.items():
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), identity,
                    f"shared input modified during compilation: {path}")
            environment = {**os.environ, "HOME": str(home), "CFFIXED_USER_HOME": str(home)}
            ran = subprocess.run([str(binary), str(root), str(home)], env=environment,
                capture_output=True, text=True, timeout=60)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            for path, identity in identities.items():
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), identity,
                    f"shared input modified during execution: {path}")
            result = json.loads(ran.stdout)
            self.assertGreaterEqual(len(result), 18)
            for name, passed in result.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)


if __name__ == "__main__":
    unittest.main()
