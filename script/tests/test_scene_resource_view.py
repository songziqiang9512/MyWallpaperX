#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
    SCENE_ROOT / "Format/ScenePkgReader.swift",
    SCENE_ROOT / "Resources/Assets/SceneResourceIdentity.swift",
    SCENE_ROOT / "Resources/Assets/SceneResourceView+Backing.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTexturePathResolver.swift",
]

HARNESS = r'''
import Foundation
import Dispatch
import CryptoKit

struct SceneRenderDescriptor {
    struct Layer {
        let imagePath: String?
        var staticBaseTexturePath: String? = nil
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let texturePaths: [String]
    }

    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

final class ConcurrentViews: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SceneResourceView] = []

    func append(_ view: SceneResourceView) {
        lock.lock()
        storage.append(view)
        lock.unlock()
    }

    var views: [SceneResourceView] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@main
enum Harness {
    static func namespace(_ view: SceneResourceView) -> [String] {
        // Compare the selected physical file, preserving logical keys and order.
        // /var and /private/var can name the same App resource on macOS.
        let resources = view.roots.flatMap { root in
            root.index.resources.map {
                "\(root.source.rawValue):\($0.relativePath):\($0.kind.rawValue):\($0.fileSize):\($0.directoryURL!.resolvingSymlinksInPath().standardizedFileURL.path)"
            }
        }
        let lookups = view.availableRelativePaths.flatMap { path in
            [path, path.uppercased()].map { reference in
                reference + "=" + (view.resource(relativePath: reference)?.directoryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? "missing")
            }
        }
        return resources + view.availableRelativePaths + lookups
    }

    static func write(_ path: String, under root: URL, _ contents: String = "fixture") throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
    }

    static func manifestCase(_ mode: String, root: URL) throws -> [String: Any] {
        let fm = FileManager.default
        let loose = root.appendingPathComponent("loose")
        try fm.createDirectory(at: loose, withIntermediateDirectories: true)
        let stock = Bundle.main.resourceURL!.appendingPathComponent("SceneStockAssets.bundle/assets")
        let sidecar = stock.deletingLastPathComponent()
            .appendingPathComponent(SceneResourceIndexBuilder.bundledManifestFilename)
        for path in ["materials/Entry 10.tex", "materials/Entry 2.tex", "materials/İmage.tex",
                     "materials/ışık.tex", "shaders/entry.vert", "fonts/sample.ttf", "C:/valid.tex",
                     ".hidden.tex", ".hidden/inside.tex", "editor.bundle/inside.tex"] {
            try write(path, under: stock, path)
        }
        let builder = SceneResourceIndexBuilder()
        let original = builder.buildWithCompleteness(rootURL: stock)
        let generated = try builder.bundledManifestData(rootURL: stock)
        let envelope = try JSONSerialization.jsonObject(with: generated) as! [String: Any]
        let rows = try JSONSerialization.jsonObject(with: Data(base64Encoded: envelope["payload"] as! String)!)
            as! [[String: Any]]
        func encoded(_ entries: [[String: Any]], schema: Int = 1) throws -> Data {
            let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return try JSONSerialization.data(withJSONObject: ["schemaVersion": schema,
                "payload": data.base64EncodedString(), "sha256": digest], options: [.sortedKeys])
        }
        func loaded() -> SceneResourceIndex? {
            builder.loadBundledManifest(rootURL: stock, manifestURL: sidecar)
        }
        func view() -> SceneResourceView { SceneResourceView(projectRootURL: loose, packageRootURL: nil) }
        func fresh() -> SceneResourceView {
            SceneResourceView(projectRootURL: loose, packageRootURL: nil, stockAssetsRootURL: stock)
        }
        if mode == "manifest-invalid" {
            var cases: [Data] = [Data("{broken".utf8), try encoded(rows, schema: 99)]
            var badHash = envelope; badHash["sha256"] = String(repeating: "0", count: 64)
            cases.append(try JSONSerialization.data(withJSONObject: badHash))
            cases.append(Data(repeating: 32, count: SceneResourceIndexBuilder.maximumBundledManifestBytes + 1))
            for path in ["", "/absolute", "../escape", "a/../b", "a/./b", "a//b", "a\\b", "a\0b"] {
                cases.append(try encoded([["relativePath": path, "fileSize": 1]]))
            }
            cases.append(try encoded([["relativePath": "negative.tex", "fileSize": -1]]))
            cases.append(try encoded(rows + [rows[0]]))
            var rejected = true
            for data in cases { try data.write(to: sidecar); rejected = rejected && loaded() == nil }
            try Data("{broken".utf8).write(to: sidecar)
            return ["allInvalidRejected": rejected, "caseCount": cases.count,
                    "fallbackMatchesOriginal": namespace(view()) == namespace(fresh())]
        }
        if mode == "manifest-symlink" {
            let target = sidecar.deletingLastPathComponent().appendingPathComponent("other-index.json")
            // A coherent sidecar with a false size distinguishes rejection from
            // accidentally consuming the linked metadata. It is not an author input.
            let altered = rows.map { ["relativePath": $0["relativePath"]!, "fileSize": 9999] }
            try encoded(altered).write(to: target)
            try fm.createSymbolicLink(at: sidecar, withDestinationURL: target)
            return ["linkedSidecarRejected": loaded() == nil,
                    "defaultFallbackMatchesOriginal": namespace(view()) == namespace(fresh())]
        }
        if mode == "manifest-route" {
            // Deliberately distinct metadata in this synthetic immutable bundle
            // proves the default slot consumes the sidecar, even through /tmp.
            // Explicit roots must still discover the real filesystem sizes.
            let altered = rows.map { ["relativePath": $0["relativePath"]!, "fileSize": 9999] }
            try encoded(altered).write(to: sidecar)
            let bundled = view().roots.last!.index.resources
            let explicit = fresh().roots.last!.index.resources
            return ["defaultActuallyUsesManifest": bundled.count == rows.count
                        && bundled.allSatisfy { $0.fileSize == 9999 },
                    "explicitStillEnumerates": explicit.count == rows.count
                        && explicit.allSatisfy { $0.fileSize != 9999 }]
        }
        // Reversing producer order falsifies accidental use of build-time
        // ordering. Both locale children must reconstruct the current ordering.
        try encoded(Array(rows.reversed())).write(to: sidecar)
        let index = loaded()!
        let actual = view(), reference = fresh()
        return ["locale": Locale.current.identifier, "loadedManifest": true,
                "complete": original.isComplete,
                "orderedIndexMatchesOriginal": index.resources.map(\.relativePath) == original.index.resources.map(\.relativePath),
                "completeNamespaceMatchesOriginal": namespace(actual) == namespace(reference),
                "stockRootShared": actual.roots.last === view().roots.last,
                "hiddenNotIndexed": !index.resources.contains { $0.relativePath.hasPrefix(".") },
                "packageDescendantsNotIndexed": !index.resources.contains { $0.relativePath.hasPrefix("editor.bundle/") },
                "explicitRootRemainsIndependent": actual.roots.last !== reference.roots.last]
    }

    static func stockCase(_ mode: String, root: URL) throws -> [String: Any] {
        if mode.hasPrefix("manifest-") { return try manifestCase(mode, root: root) }
        let fm = FileManager.default
        let package = root.appendingPathComponent("package")
        let loose = root.appendingPathComponent("loose")
        let custom = root.appendingPathComponent("custom")
        let stock = Bundle.main.resourceURL!.appendingPathComponent("SceneStockAssets.bundle/assets")
        for directory in [package, loose, custom] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func view() -> SceneResourceView {
            SceneResourceView(projectRootURL: loose, packageRootURL: package)
        }
        func fresh(_ url: URL) -> SceneResourceView {
            SceneResourceView(projectRootURL: loose, packageRootURL: package,
                              stockAssetsRootURL: url)
        }
        func stockRoot(_ view: SceneResourceView) -> SceneResourceView.Root? {
            view.roots.first { $0.source == .stock }
        }
        if mode == "missing" {
            let missing = view()
            try write("materials/recovered.tex", under: stock)
            let recovered = view()
            return ["missingWasAbsent": stockRoot(missing) == nil,
                    "retryMatchesFresh": namespace(recovered) == namespace(fresh(stock)),
                    "retryFoundResource": recovered.resource(relativePath: "materials/recovered.tex") != nil,
                    "successfulRootShared": stockRoot(recovered) === stockRoot(view())]
        }
        try write("materials/shared.tex", under: stock, "stock")
        try write("materials/unique.tex", under: stock)
        try write("models/util/solidlayer_depthtest.json", under: stock, "{}")
        try write("materials/Album art 3  test .tex", under: stock)
        if mode == "incomplete" {
            let protected = stock.appendingPathComponent("blocked")
            try write("hidden.tex", under: protected)
            try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: protected.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path) }
            let incomplete = SceneResourceIndexBuilder().buildWithCompleteness(rootURL: stock)
            let first = view()
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protected.path)
            let recovered = view()
            return ["incompleteDetected": !incomplete.isComplete,
                    "incompleteRootNotRetained": stockRoot(first) !== stockRoot(recovered),
                    "recoveredComplete": SceneResourceIndexBuilder().buildWithCompleteness(rootURL: stock).isComplete,
                    "retryMatchesFresh": namespace(recovered) == namespace(fresh(stock)),
                    "retryFoundResource": recovered.resource(relativePath: "blocked/hidden.tex") != nil,
                    "successfulRootShared": stockRoot(recovered) === stockRoot(view())]
        }
        if mode == "outside" {
            try SceneResourceIndexBuilder().bundledManifestData(rootURL: stock.resolvingSymlinksInPath()).write(to:
                stock.deletingLastPathComponent().appendingPathComponent(SceneResourceIndexBuilder.bundledManifestFilename))
            let first = view()
            try write("materials/later.tex", under: stock)
            let second = view()
            return ["redirectedRootNotRetained": stockRoot(first) !== stockRoot(second),
                    "redirectedRootMatchesFresh": namespace(second) == namespace(fresh(stock))]
        }
        try write("materials/shared.tex", under: package, "package")
        try write("materials/shared.tex", under: loose, "loose")
        try SceneResourceIndexBuilder().bundledManifestData(rootURL: stock).write(to:
            stock.deletingLastPathComponent().appendingPathComponent(SceneResourceIndexBuilder.bundledManifestFilename))
        let concurrent = ConcurrentViews()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in concurrent.append(view()) }
        let views = concurrent.views
        let first = views[0]
        let initialRoot = stockRoot(first)!
        let baseline = fresh(stock)
        let oneRoot = views.allSatisfy { stockRoot($0) === initialRoot }
        let allEquivalent = views.allSatisfy { namespace($0) == namespace(baseline) }
        let explicitRootNotShared = stockRoot(baseline) !== initialRoot
            && stockRoot(fresh(stock)) !== stockRoot(baseline)
        let packageWins = first.resource(relativePath: "materials/shared.tex")?.directoryURL?.resolvingSymlinksInPath().path
            == package.appendingPathComponent("materials/shared.tex").resolvingSymlinksInPath().path
        try fm.removeItem(at: package.appendingPathComponent("materials/shared.tex"))
        let looseView = view()
        let looseWins = looseView.resource(relativePath: "materials/shared.tex")?.directoryURL?.resolvingSymlinksInPath().path
            == loose.appendingPathComponent("materials/shared.tex").resolvingSymlinksInPath().path
        try fm.removeItem(at: loose.appendingPathComponent("materials/shared.tex"))
        let stockView = view()
        let stockWins = stockView.resource(relativePath: "materials/shared.tex")?.directoryURL?.resolvingSymlinksInPath().path
            == stock.appendingPathComponent("materials/shared.tex").resolvingSymlinksInPath().path
        try write("materials/old.tex", under: package)
        try fm.moveItem(at: package.appendingPathComponent("materials/old.tex"),
                        to: package.appendingPathComponent("materials/new.tex"))
        let renamed = view()
        let authorRenameObserved = renamed.resource(relativePath: "materials/old.tex") == nil
            && renamed.resource(relativePath: "materials/new.tex") != nil
        try write("materials/edit.tex", under: custom, "old")
        try write("materials/delete.tex", under: custom)
        try write("materials/old.tex", under: custom)
        let customBefore = fresh(custom)
        try write("materials/edit.tex", under: custom, "replacement")
        try fm.removeItem(at: custom.appendingPathComponent("materials/delete.tex"))
        try fm.moveItem(at: custom.appendingPathComponent("materials/old.tex"),
                        to: custom.appendingPathComponent("materials/new.tex"))
        let customAfter = fresh(custom)
        let customChangesObserved = customAfter.resource(relativePath: "materials/edit.tex")?.fileSize == 11
            && customAfter.resource(relativePath: "materials/delete.tex") == nil
            && customAfter.resource(relativePath: "materials/old.tex") == nil
            && customAfter.resource(relativePath: "materials/new.tex") != nil
        return ["concurrentCount": views.count, "oneCompleteRoot": oneRoot,
                "completeNamespaceEquivalent": allEquivalent,
                "explicitBundleRootNotShared": explicitRootNotShared,
                "packageWins": packageWins, "looseWinsAfterDelete": looseWins,
                "stockWinsAfterDelete": stockWins, "authorRenameObserved": authorRenameObserved,
                "authorChangesMatchFresh": namespace(renamed) == namespace(fresh(stock)),
                "stockRootStillShared": stockRoot(renamed) === initialRoot,
                "customRootNotShared": stockRoot(customBefore) !== stockRoot(customAfter),
                "customChangesObserved": customChangesObserved,
                "explicitStockAlias": renamed.resource(relativePath: "assets/models/util/solidlayer_depthtest.json")
                    != nil,
                "stockTrailingSpacePreserved": renamed.resource(relativePath: "materials/Album art 3  test .tex") != nil
                    && renamed.resource(relativePath: "materials/Album art 3  test.tex") == nil]
    }

    static func main() throws {
        if CommandLine.arguments[1] == "--stock-case" {
            let result = try stockCase(CommandLine.arguments[2],
                                       root: URL(fileURLWithPath: CommandLine.arguments[3]))
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        let package = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let loose = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stock = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let view = SceneResourceView(
            projectRootURL: loose,
            packageRootURL: package,
            stockAssetsRootURL: stock
        )
        let descriptor = SceneRenderDescriptor(
            modelMaterialLinks: [
                .init(modelPath: "models/loose.json", materialPath: "materials/loose.json")
            ],
            materialPasses: [
                .init(materialPath: "materials/loose.json", texturePaths: ["loose"])
            ]
        )
        let resolver = SceneTexturePathResolver(resourceView: view, descriptor: descriptor)
        let layer = SceneRenderDescriptor.Layer(imagePath: "models/loose.json")
        let result: [String: Any] = [
            "duplicate": view.resource(relativePath: "materials/duplicate.tex")?.directoryURL?.path ?? "missing",
            "loose": resolver.resolvePrimaryTexture(for: layer).map { $0.diagnosticPath } ?? "missing",
            "stock": resolver.resolveTextureFile(named: "stock").map { $0.diagnosticPath } ?? "missing",
            "exactRelative": resolver.resolveTextureFile(
                named: "materials/exact.tex"
            ).map { $0.diagnosticPath } ?? "missing",
            "caseInsensitive": view.resource(
                relativePath: "MATERIALS/EXACT.TEX"
            )?.directoryURL?.path ?? "missing",
            "exactStock": resolver.resolveTextureFile(
                named: "materials/exact-stock.tex"
            ).map { $0.diagnosticPath } ?? "missing",
            "absolute": resolver.resolveTextureFile(
                named: package.appendingPathComponent("materials/exact.tex").path
            ).map { $0.diagnosticPath } ?? "missing",
            "resolverEscape": resolver.resolveTextureFile(
                named: "../outside.tex"
            ).map { $0.diagnosticPath } ?? "missing",
            "colonRelative": resolver.resolveTextureFile(
                named: "C:\\outside.tex"
            ).map { $0.diagnosticPath } ?? "missing",
            "explicitSuffixFallback": resolver.resolveTextureFile(
                named: "missing.tex"
            ).map { $0.diagnosticPath } ?? "missing",
            "explicitStock": view.resource(
                relativePath: "assets/models/util/solidlayer_depthtest.json"
            )?.directoryURL?.path ?? "missing",
            "diagnosticSeesExplicitStock": view.availableRelativePaths.contains(
                "assets/models/util/solidlayer_depthtest.json"
            ),
            "trailingSpace": view.resource(
                relativePath: "materials/Album art 3  test .tex"
            )?.directoryURL?.path ?? "missing",
            "trimmed": view.resource(
                relativePath: "materials/Album art 3  test.tex"
            )?.directoryURL?.path ?? "missing",
            "escape": view.resource(relativePath: "../outside.tex")?.directoryURL?.path ?? "missing",
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneResourceViewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-resource-view-"
        )
        root = Path(cls.temporary_directory.name)
        cls.package = root / "package"
        cls.loose = root / "loose"
        cls.stock = root / "stock-assets"
        for directory in (cls.package, cls.loose, cls.stock):
            (directory / "materials").mkdir(parents=True)

        (cls.package / "materials/duplicate.tex").write_bytes(b"package")
        (cls.package / "materials/missing.tex.tex").write_bytes(b"suffix-lure")
        colon_relative_resource = cls.package / "C:/outside.tex"
        colon_relative_resource.parent.mkdir(parents=True)
        colon_relative_resource.write_bytes(b"colon-relative-resource")
        (cls.package / "loose").write_bytes(b"bare-stem-shadow")
        (cls.loose / "materials/duplicate.tex").write_bytes(b"loose")
        (cls.loose / "materials/loose.tex").write_bytes(b"loose")
        (cls.loose / "materials/exact.tex").write_bytes(b"exact")
        (cls.loose / "materials/Album art 3  test .tex").write_bytes(b"space")
        (cls.stock / "materials/stock.tex").write_bytes(b"stock")
        (cls.stock / "materials/exact-stock.tex").write_bytes(b"exact-stock")
        stock_model = cls.stock / "models/util/solidlayer_depthtest.json"
        stock_model.parent.mkdir(parents=True)
        stock_model.write_text("{}", encoding="utf-8")

        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-resource-view-harness"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-module-cache-path", str(root / "modules"), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary), str(cls.package), str(cls.loose), str(cls.stock)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)
        # Input diagnostic paths preserve their selected Root spelling; compare
        # physical selection with the pre-existing canonical URL expectations.
        cls.result = {key: str(Path(value).resolve())
                      if isinstance(value, str) and value != "missing" else value
                      for key, value in cls.result.items()}

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_precedence_is_package_then_loose_then_stock(self) -> None:
        self.assertEqual(
            self.result["duplicate"],
            str((self.package / "materials/duplicate.tex").resolve()),
        )
        self.assertEqual(
            self.result["loose"],
            str((self.loose / "materials/loose.tex").resolve()),
        )
        self.assertEqual(
            self.result["stock"],
            str((self.stock / "materials/stock.tex").resolve()),
        )

    def test_stock_assets_prefix_maps_to_the_same_read_only_namespace(self) -> None:
        self.assertEqual(
            self.result["explicitStock"],
            str((self.stock / "models/util/solidlayer_depthtest.json").resolve()),
        )
        self.assertTrue(self.result["diagnosticSeesExplicitStock"])

    def test_exact_relative_texture_paths_use_the_shared_resource_namespace(self) -> None:
        self.assertEqual(
            self.result["exactRelative"],
            str((self.loose / "materials/exact.tex").resolve()),
        )
        self.assertEqual(
            self.result["caseInsensitive"],
            str((self.loose / "materials/exact.tex").resolve()),
        )
        self.assertEqual(
            self.result["exactStock"],
            str((self.stock / "materials/exact-stock.tex").resolve()),
        )

    def test_file_identity_preserves_trailing_space_and_rejects_escape(self) -> None:
        self.assertEqual(
            self.result["trailingSpace"],
            str((self.loose / "materials/Album art 3  test .tex").resolve()),
        )
        self.assertEqual(self.result["trimmed"], "missing")
        self.assertEqual(self.result["escape"], "missing")
        self.assertEqual(self.result["absolute"], "missing")
        self.assertEqual(self.result["resolverEscape"], "missing")
        self.assertEqual(self.result["colonRelative"], str((self.package / "C:/outside.tex").resolve()))
        self.assertEqual(self.result["explicitSuffixFallback"], "missing")

    def run_stock_case(self, mode: str, locale: str | None = None) -> dict:
        with tempfile.TemporaryDirectory(prefix="mwx-bundled-stock-") as directory:
            root = Path(directory)
            contents = root / "ResourceViewHarness.app/Contents"
            executable = contents / "MacOS/ResourceViewHarness"
            executable.parent.mkdir(parents=True)
            resources = contents / "Resources"
            resources.mkdir()
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.mywallpaperx.test.ResourceView",
                "CFBundleExecutable": executable.name,
                "CFBundlePackageType": "APPL",
            }))
            shutil.copy2(self.binary, executable)
            if mode == "outside":
                outside = root / "mutable-stock"
                outside.mkdir()
                stock_bundle = resources / "SceneStockAssets.bundle"
                stock_bundle.mkdir()
                (stock_bundle / "assets").symlink_to(outside, target_is_directory=True)
            arguments = [str(executable), "--stock-case", mode, str(root)]
            if locale:
                arguments += ["-AppleLocale", locale]
            completed = subprocess.run(
                arguments,
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0,
                             f"{arguments!r}\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}")
            return json.loads(completed.stdout)

    def test_default_bundle_shares_complete_root_under_concurrent_construction(self) -> None:
        result = self.run_stock_case("shared")
        self.assertEqual(result["concurrentCount"], 32)
        for key in ("oneCompleteRoot", "completeNamespaceEquivalent", "explicitBundleRootNotShared",
                    "packageWins", "looseWinsAfterDelete", "stockWinsAfterDelete",
                    "authorRenameObserved", "authorChangesMatchFresh", "stockRootStillShared",
                    "customRootNotShared", "customChangesObserved", "explicitStockAlias",
                    "stockTrailingSpacePreserved"):
            with self.subTest(key=key):
                self.assertTrue(result[key])

    def test_missing_bundle_root_can_retry_and_share_after_success(self) -> None:
        result = self.run_stock_case("missing")
        self.assertTrue(all(result.values()), result)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses the unreadable-directory counterexample")
    def test_incomplete_enumeration_is_not_retained_as_success(self) -> None:
        result = self.run_stock_case("incomplete")
        self.assertTrue(all(result.values()), result)

    def test_default_stock_redirected_outside_bundle_is_not_shared(self) -> None:
        result = self.run_stock_case("outside")
        self.assertTrue(all(result.values()), result)

    def test_bundled_manifest_reconstructs_current_locale_namespace(self) -> None:
        route = self.run_stock_case("manifest-route")
        self.assertTrue(all(route.values()), route)
        for locale in ("en_US", "tr_TR"):
            with self.subTest(locale=locale):
                result = self.run_stock_case("manifest-valid", locale=locale)
                self.assertEqual(result.pop("locale"), locale)
                self.assertTrue(all(result.values()), result)

    def test_invalid_bundled_manifest_falls_back_to_original_index(self) -> None:
        result = self.run_stock_case("manifest-invalid")
        self.assertEqual(result.pop("caseCount"), 14)
        self.assertTrue(all(result.values()), result)

    def test_bundled_manifest_rejects_linked_sidecar_inside_same_bundle(self) -> None:
        result = self.run_stock_case("manifest-symlink")
        self.assertTrue(all(result.values()), result)



if __name__ == "__main__":
    unittest.main()
