"""Real structural-resource/SourceFacts cancellation, mutation and local failures.

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
import Darwin
import CryptoKit
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
            "descriptor": descriptor ?? "missing",
        ], options: [.sortedKeys])
    }

    static func sourceCases(_ root: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for name in ["valid", "bad-model", "bad-tail", "bad-document", "bad-project", "bad-package"] {
            let folder = root.appendingPathComponent(name)
            ProofLeaf.reset()
            let plain = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
            let plainProjection = try projection(plain)
            let plainProofCalls = ProofLeaf.calls
            ProofLeaf.reset()
            var total = 0
            let observed = try SceneRuntimeSourceFactsBuilder().build(
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
            if name == "bad-model" || name == "bad-tail" {
                checks[name + "-keepsPeerAndMaterialCatalog"] =
                    plain.renderDescriptor?.modelMaterialLinks.contains { $0.modelPath == "models/parts.mdl" } == false
                    && plain.renderDescriptor?.modelMaterialLinks.contains { $0.modelPath == "models/peer.mdl" } == true
                    && plain.assetCatalog?.materials.map(\.relativePath) == ["materials/peer.json"]
            } else if name == "bad-project" {
                checks["ordinaryProjectFailureRemainsOptional"] = plain.project == nil && plain.renderDescriptor == nil
            } else if name == "bad-document" {
                checks["ordinaryDocumentFailureRetainsDescription"] = plain.sceneDocument == nil
                    && plain.sceneDocumentLoadErrorDescription != nil && plain.renderDescriptor == nil
            } else if name == "bad-package" {
                checks["ordinaryPackageFailureKeepsCompleteLooseScene"] = plain.sceneDocument != nil
                    && plain.renderDescriptor != nil
                    && plain.resourceView.roots.allSatisfy { $0.source != .package }
            }
        }
        return checks
    }

    static func structuralSourceChangeCases(_ root: URL) throws -> [String: Bool] {
        let folder = root.appendingPathComponent("valid")
        var checks: [String: Bool] = [:]
        let plain = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
        checks["literalDynamicModelRetainsMaterialLink"] = plain.renderDescriptor?
            .modelMaterialLinks.contains {
                $0.modelPath == "models/unreferenced.json"
                    && $0.materialPath == "materials/unreferenced.json"
            } == true
        for relativePath in ["project.json", "scene.json", "models/parts.mdl", "models/unreferenced.json",
            "materials/unreferenced.json", "models/attachment.mdl", "effects/probe/effect.json"] {
            let target = folder.appendingPathComponent(relativePath)
            let original = try Data(contentsOf: target)
            let expectedPath = target.resolvingSymlinksInPath().standardizedFileURL.path
            for caller in ["facts", "model"] {
                var changed = false
                func mutateOpenedResource() throws {
                    guard !changed else { return }
                    for descriptor: Int32 in 0..<512 {
                        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                        if fcntl(descriptor, F_GETPATH, &path) == 0,
                           URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expectedPath {
                            try original.dropLast().write(to: target, options: .atomic)
                            changed = true
                            return
                        }
                    }
                }
                do {
                    if caller == "facts" {
                        _ = try SceneRuntimeSourceFactsBuilder().build(
                            rootURL: folder, checkCancellation: mutateOpenedResource)
                    } else {
                        _ = try SceneRuntimeModelBuilder().build(
                            rootURL: folder, checkCancellation: mutateOpenedResource)
                    }
                    checks[caller + "-" + relativePath + "-sourceChangeEscapes"] = false
                } catch SceneResourceView.ReadError.sourceChanged {
                    checks[caller + "-" + relativePath + "-sourceChangeEscapes"] = changed
                }
                try original.write(to: target, options: .atomic)
            }
        }
        let recovered = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
        checks["structuralReadFailureDoesNotPoisonLaterFacts"] = try projection(recovered) == projection(plain)
        checks["fullMdlMetadataRetainsAllThreeMaterials"] = recovered.renderDescriptor?
            .modelMaterialLinks.filter { $0.modelPath == "models/parts.mdl" }.count == 3
        return checks
    }

    static func entrySelectionCases(_ root: URL) throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for (name, expectedID) in [
            ("entry-hidden", 17), ("entry-dot", 17), ("entry-package", 29),
            ("entry-package-miss", 17), ("entry-derived-package", 41)
        ] {
            let facts = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent(name))
            checks[name + "-keepsLiteralSelection"] = facts.sceneDocument?.objects.map(\.id) == [expectedID]
            checks[name + "-noParseFailure"] = facts.sceneDocumentLoadErrorDescription == nil
        }
        let derived = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent("entry-derived-package"))
        checks["entryBasePackagePrecedesScenePackage"] = derived.project?.packageURL?.lastPathComponent == "Entry.pkg"
        let fallback = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent("entry-package"))
        checks["scenePackageRemainsDerivedPackageFallback"] = fallback.project?.packageURL?.lastPathComponent == "scene.pkg"
        for name in ["entry-package-invalid", "entry-package-duplicate"] {
            let facts = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent(name))
            checks[name + "-doesNotParseLowerLooseDocument"] = facts.sceneDocument == nil
                && facts.sceneDocumentLoadErrorDescription != nil && facts.renderDescriptor == nil
        }
        let missingDot = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent("entry-dot-missing"))
        checks["literalDotMissingComponentRemainsMissing"] = missingDot.sceneDocument == nil
            && missingDot.sceneDocumentLoadErrorDescription != nil
        let folder = root.appendingPathComponent("entry-package")
        let normal = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
        guard let selected = normal.project?.packageURL,
              let entry = normal.project?.entryPath,
              case .package? = try normal.resourceView.literalEntry(relativePath: entry)?.currentIdentity() else {
            fatalError("selected document must be mounted directly from the package")
        }
        let packageBytes = try Data(contentsOf: selected)
        let expectedPath = selected.resolvingSymlinksInPath().standardizedFileURL.path
        var removed = false
        var entryReadReady = false
        do {
            _ = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder, checkCancellation: {
                guard entryReadReady, !removed else { return }
                for descriptor: Int32 in 0..<512 {
                    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                    if fcntl(descriptor, F_GETPATH, &path) == 0,
                       URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expectedPath {
                        try FileManager.default.removeItem(at: selected)
                        removed = true
                        return
                    }
                }
            }, willReadResourceRoots: { _ in entryReadReady = true })
            checks["selectedDocumentDeletionEscapesWithoutLooseFallback"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["selectedDocumentDeletionEscapesWithoutLooseFallback"] = removed
        }
        try packageBytes.write(to: selected, options: .atomic)
        let recovered = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
        checks["restoredPackageRecoversOnNextRequest"] = try projection(recovered) == projection(normal)
        let propertyRoot = root.appendingPathComponent("entry-properties")
        let overrides: [String: SceneUserPropertyValue] = ["enabled": .bool(false), "amount": .number(0.7)]
        let properties = try SceneRuntimeSourceFactsBuilder().build(rootURL: propertyRoot, propertyOverrides: overrides)
        let project = properties.project!, document = properties.sceneDocument!
        let legacy = try SceneDocumentLoader().load(from: project.entryURL,
            propertyCatalog: project.userProperties, propertyOverrides: overrides)
        checks["capturedDocumentKeepsScriptsAuthoredProvidersAndOverrides"] = document.authoredRoot == legacy.authoredRoot
            && !document.scriptBindings.isEmpty && document.scriptBindings == legacy.scriptBindings
            && document.scriptSourceEvidence == legacy.scriptSourceEvidence
            && document.scriptBindingDiagnostics == legacy.scriptBindingDiagnostics
            && document.objects.first?.visible == false && document.objects.first?.alpha == 0.7
        let alternate = try SceneRuntimeSourceFactsBuilder().build(rootURL: propertyRoot,
            propertyOverrides: ["enabled": .bool(true), "amount": .number(0.2)])
        func witness(_ url: URL) throws -> String {
            SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        checks["projectAndDocumentWitnessUseAuthoredBytesAcrossOverrides"] = try project.sourceWitness == witness(project.projectFileURL)
            && document.sourceWitness == witness(project.entryURL)
            && alternate.project?.sourceWitness == project.sourceWitness
            && alternate.sceneDocument?.sourceWitness == document.sourceWitness
            && alternate.sceneDocument?.authoredRoot == document.authoredRoot
        return checks
    }

    static func sourceChangeCases(_ root: URL) throws -> [String: Bool] {
        let folder = root.appendingPathComponent("valid")
        let target = folder.appendingPathComponent("shaders/handles/probe.vert")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("void main() {}".utf8).write(to: target)
        try Data("void main() {}".utf8).write(to: target.deletingPathExtension().appendingPathExtension("frag"))
        try Data(#"{"passes":[{"shader":"handles/probe"}]}"#.utf8)
            .write(to: folder.appendingPathComponent("materials/handle-probe.json"))
        let expectedPath = target.resolvingSymlinksInPath().standardizedFileURL.path
        var changed = false
        func mutateOpenedShader() throws {
            guard !changed else { return }
            for descriptor: Int32 in 0..<512 {
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                if fcntl(descriptor, F_GETPATH, &path) == 0,
                   URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL.path == expectedPath {
                    try Data("// changed source\nvoid main() {}".utf8).write(to: target, options: .atomic)
                    changed = true
                    return
                }
            }
        }
        var checks: [String: Bool] = [:]
        do {
            _ = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder,
                checkCancellation: mutateOpenedShader)
            checks["shaderSourceChangeEscapesGraphCatalogAndFacts"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["shaderSourceChangeEscapesGraphCatalogAndFacts"] = changed
        }
        changed = false
        do {
            _ = try SceneRuntimeModelBuilder().build(rootURL: folder,
                checkCancellation: mutateOpenedShader)
            checks["shaderSourceChangeReachesModelCaller"] = false
        } catch SceneResourceView.ReadError.sourceChanged {
            checks["shaderSourceChangeReachesModelCaller"] = changed
        }
        let recovered = try SceneRuntimeSourceFactsBuilder().build(rootURL: folder)
        checks["sourceFailureDoesNotPoisonLaterFacts"] = recovered.assetCatalog != nil
            && recovered.renderDescriptor != nil
        return checks
    }

    static func descriptorCases(_ root: URL) throws -> [String: Bool] {
        ProofLeaf.reset()
        let facts = try SceneRuntimeSourceFactsBuilder().build(rootURL: root.appendingPathComponent("valid"))
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
        checks.merge(try sourceChangeCases(root)) { _, new in new }
        checks.merge(try structuralSourceChangeCases(root)) { _, new in new }
        checks.merge(try entrySelectionCases(root)) { _, new in new }
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
            for name in ["valid", "bad-model", "bad-tail", "bad-document", "bad-project", "bad-package"]:
                entries, _ = parts.native_fixture(3, bad=name == "bad-model")
                if name == "valid":
                    # The selected script and effect make these definitions
                    # actual closure members; unrelated author files stay unread.
                    scene = json.loads(entries["scene.json"])
                    scene["objects"][0]["color"] = {"value": "1 1 1", "script":
                        "export function init() { thisScene.createLayer('models/unreferenced.json'); }"}
                    scene["objects"][0]["effects"] = [{"file": "effects/probe/effect.json"}]
                    entries["scene.json"] = json.dumps(scene).encode()
                    entries["models/unreferenced.json"] = json.dumps({
                        "material": "materials/unreferenced.json",
                        "puppet": "models/attachment.mdl",
                    }).encode()
                    entries["materials/unreferenced.json"] = b'{"passes":[{"shader":"genericimage"}]}'
                    entries["models/attachment.mdl"] = parts.puppet_mesh.build_attachment_mdl()
                    entries["effects/probe/effect.json"] = b'{"passes":[{"material":"materials/unreferenced.json"}],"dependencies":["materials/handle-probe.json"]}'
                elif name == "bad-tail":
                    entries["models/parts.mdl"] = entries["models/parts.mdl"][:-1] + b"\x01"
                elif name == "bad-document":
                    entries["scene.json"] = b"{invalid"
                elif name == "bad-project":
                    entries["project.json"] = b"{invalid"
                elif name == "bad-package":
                    entries["scene.pkg"] = b"invalid-package"
                for relative, data in entries.items():
                    path = root / name / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
            # Each entry uses the actual project/package/source-facts path.
            # The loose peer is deliberately valid when the package is invalid.
            for name in ["entry-hidden", "entry-dot", "entry-dot-missing", "entry-package", "entry-package-miss",
                         "entry-derived-package", "entry-package-invalid", "entry-package-duplicate"]:
                folder = root / name
                entry = "models/.authored/Entry.JSON"
                project_entry = "ignored/../" + entry if name in ["entry-dot", "entry-dot-missing"] else entry
                folder.mkdir(parents=True)
                (folder / "project.json").write_text(json.dumps({"type": "scene", "file": project_entry}))
                loose = folder / entry
                loose.parent.mkdir(parents=True)
                loose.write_text(json.dumps({"objects": [{"id": 17}]}))
                if name == "entry-dot":
                    (folder / "ignored").mkdir()
                if name in ["entry-hidden", "entry-dot", "entry-dot-missing"]:
                    continue
                data = json.dumps({"objects": [{"id": 29}]}).encode()
                if name == "entry-package-invalid":
                    data = b"{invalid"
                elif name == "entry-package-duplicate":
                    data = b'{"objects":[{"id":29},{"id":29}]}'
                package_entry = "other.json" if name == "entry-package-miss" else entry
                (folder / "scene.pkg").write_bytes(parts.make_package([(package_entry, data)]))
                if name == "entry-derived-package":
                    (folder / "Entry.pkg").write_bytes(parts.make_package([
                        (entry, b'{"objects":[{"id":41}]}')]))
            property_folder = root / "entry-properties"
            property_folder.mkdir()
            (property_folder / "project.json").write_text(json.dumps({
                "type": "scene", "file": "scene.json", "general": {"properties": {
                    "enabled": {"type": "bool", "value": True},
                    "amount": {"type": "slider", "value": 0.4},
                }}}))
            (property_folder / "scene.json").write_text(json.dumps({"objects": [{
                "id": 17, "visible": {"user": "enabled", "value": True},
                "alpha": {"user": "amount", "value": 0.4},
                "origin": {"script": "export function update(value) { return value; }", "value": "1 2 3",
                           "scriptproperties": {"rate": {"user": "amount", "value": 1}}},
            }]}))
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
