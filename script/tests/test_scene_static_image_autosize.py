"""Source-size preparation through the real loader; no GPU work is submitted."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from .test_scene_image_upload_completion import LOADER_SOURCES, SOURCE, RESAMPLE_SOURCE

SWIFT_SOURCES = [*LOADER_SOURCES, SOURCE, RESAMPLE_SOURCE]
from .scene_vector_vm_test_support import compile_vector_harness


HARNESS = r'''
import Foundation
import CoreGraphics
import ImageIO
@main enum HeaderChecks {
    static func writeImage(_ url: URL, width: Int, height: Int, type: CFString) throws {
        let bytes = Data(repeating: 255, count: width * height * 4)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CheckError.encoding }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queue = SceneTextureUploadCommandQueue()
        let budget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let loader = SceneTextureLoader(uploadCommandQueue: queue, decodeCacheBudget: budget)
        var sizes: [[Double]] = []
        var oldSourceRejected = false
        for (name, type) in [("renamed-Ä.png", "public.png"), ("other-resource.jpg", "public.jpeg")] {
            let url = root.appendingPathComponent(name)
            try writeImage(url, width: 200, height: 100, type: type as CFString)
            let source = (try loader.sourceKey(for: url))!
            let size = (try loader.preparedNaturalImageSize(from: url, source: source))!
            sizes.append([size.width, size.height])
            loader.evictDecodedCaches()
            let again = (try loader.preparedNaturalImageSize(from: url, source: source))!
            sizes.append([again.width, again.height])
            try writeImage(url, width: 120, height: 60, type: type as CFString)
            do { _ = try loader.preparedNaturalImageSize(from: url, source: source) }
            catch SceneResourceView.ReadError.sourceChanged { oldSourceRejected = true }
            let changed = (try loader.sourceKey(for: url))!
            let changedSize = (try loader.preparedNaturalImageSize(from: url, source: changed))!
            sizes.append([changedSize.width, changedSize.height])
        }
        let invalid = root.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let failureIsLocal = (try loader.preparedNaturalImageSize(from: invalid, source: (try loader.sourceKey(for: invalid))!)) == nil
        let payload: [String: Any] = ["sizes": sizes, "oldSourceRejected": oldSourceRejected,
            "failureIsLocal": failureIsLocal, "decodeAttempts": loader.directImageDecodeAttemptCount,
            "decodeResidentBytes": budget.residentBytes, "queueCreationAttempts": queue.creationAttemptCount]
        print(String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
    }
    enum CheckError: Error { case encoding }
}
'''


class SceneStaticImageAutosizeHeaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-static-autosize-header-")
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(cls.directory.name)
        harness = root / "HeaderChecks.swift"
        harness.write_text(HARNESS)
        binary = root / "checks"
        result = subprocess.run(["xcrun", "swiftc", *map(str, SWIFT_SOURCES), str(harness),
                                 "-framework", "Metal", "-module-cache-path", str(root / "modules"),
                                 "-o", str(binary)], capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        run = subprocess.run([str(binary), str(root / "images")], capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise AssertionError(run.stdout + run.stderr)
        cls.facts = json.loads(run.stdout)

    def test_png_and_jpeg_natural_size_does_not_decode_or_upload(self) -> None:
        self.assertEqual(self.facts["sizes"], [[200, 100], [200, 100], [120, 60]] * 2)
        for key in ("decodeAttempts", "decodeResidentBytes", "queueCreationAttempts"):
            self.assertEqual(self.facts[key], 0, key)

    def test_changed_source_and_invalid_header_do_not_reuse_dimensions(self) -> None:
        self.assertTrue(self.facts["oldSourceRejected"])
        self.assertTrue(self.facts["failureIsLocal"])


VM_HARNESS = r'''
import Foundation
@main enum VMChecks {
    static func check(_ resource: String, _ variable: String, equivalent: Bool) throws -> [String: Any] {
        let dimensions: [[Float]] = [[200,100],[120,60],[1,1],[0,0]]
        var layers: [SceneRenderDescriptor.Layer] = []
        for index in dimensions.indices {
            var layer = SceneRenderDescriptor.Layer(id: 17+index, layerIndex: index,
                name: "renamed-anchor-\(index)", visible: true, originXYZ: [0,0,0],
                scaleXYZ: [1,1,1], alpha: 1, effects: [])
            layer.sizeWH = dimensions[index]; layer.imagePath = resource
            layer.initialConfiguration = .object(["image":.string(resource),"size":.string("120 60")])
            layers.append(layer)
        }
        let descriptor = SceneRenderDescriptor(layers: layers)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerRuntimeFields(descriptor)
        func owner(_ source: String) throws -> SceneScriptValueOwner {
            try .init(domain: domain, source: source, target: .layer(layerID:17, field:.color),
                valueType: .vector3, effectNames: [], allowsStatefulLayerSideEffects: true,
                generation:1, budget:.default)
        }
        func evaluate(_ value: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try value.evaluate(input:.vector3(0,0,0), frame:.init(timing:.init(
                wallDate:Date(timeIntervalSince1970:0), simulationFrameTime:1/60, sceneTime:0)),
                scriptPropertiesJSON:"", userPropertiesJSON:"{}", expectedGeneration:1,
                interruptBudget:nil).get()
        }
        let source = """
            export function update(v) {
                const \(variable) = thisScene.getLayer(\(equivalent ? "0+0" : "'renamed-anchor-0'"));
                const logical = \(variable)\(equivalent ? "['si'+'ze']" : ".size");
                if (thisScene.getLayer(1).size.x !== 120 || thisScene.getLayer(2).size.x !== 1 ||
                    thisScene.getLayer(3).size.x !== 0) throw Error('prepared-neighbor-size');
                const authored = thisScene.getInitialLayerConfig(\(variable));
                if (authored.size !== '120 60' || authored.image !== '\(resource)') throw Error('prepared-config');
                \(variable).alpha = 0.5;
                return new Vec3(\(equivalent ? "logical.x/2*2" : "logical.x"),logical.y+0,1);
            }
            """
        let healthy = try owner(source)
        let result = try evaluate(healthy)
        healthy.discardLayerMutations()
        let failing = try owner("export function update(v){thisLayer.alpha=0.2;throw Error('prepared-failure');}")
        var rejected = false
        do { _ = try evaluate(failing) } catch { rejected = String(describing:error).contains("prepared-failure") }
        let after = try owner("export function update(v){if(thisLayer.alpha!==1)throw Error('rollback');return new Vec3(thisLayer.size.x,thisLayer.size.y,1);}")
        let later = try evaluate(after)
        after.discardLayerMutations()
        return ["value": result.value == .vector3(200,100,1), "later":later.value == .vector3(200,100,1),
            "healthyAlpha":result.layerMutations.first?.alpha == 0.5, "rejected":rejected,
            "cursorNatural":SceneScriptCursorHitAdmission.accepts(layers[0]),
            "cursorDefault":SceneScriptCursorHitAdmission.accepts(layers[2]),
            "cursorZeroRejected":!SceneScriptCursorHitAdmission.accepts(layers[3])]
    }
    static func main() throws {
        let facts = [try check("models/original.json", "sample", equivalent:false),
            try check("models/relocated-Ä.json", "otherBinding", equivalent:true)]
        print(String(decoding:try JSONSerialization.data(withJSONObject:facts),as:UTF8.self))
    }
}
'''


class SceneStaticImageAutosizeVMConsumerTests(unittest.TestCase):
    def test_real_catalog_getter_cursor_and_rollback_consume_prepared_dimensions(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-static-autosize-vm-") as directory:
            binary = compile_vector_harness(Path(directory), VM_HARNESS, "vm-checks")
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            for variant in json.loads(run.stdout):
                for key, value in variant.items():
                    self.assertTrue(value, key)


if __name__ == "__main__":
    unittest.main()
