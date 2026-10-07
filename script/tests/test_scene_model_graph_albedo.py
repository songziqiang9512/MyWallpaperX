"""Owned hidden effect graph -> named static model color and shadow regression.

Set MWX_SCENE_INTEGRATION_APP to a frozen Debug App. The visible image witness
uses the same owned shader and frame clock, so pixel expectations do not depend
on a guessed snapshot time. No corpus/private shader or official pixels are used.
CPU tests execute the production dependency plan without allocating GPU work.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_dependency_render_plan import SWIFT_SOURCES
from script.tests.test_scene_directional_shadow_integration import fixture_entries as shadow_fixture, png, quad
from script.tests.test_scene_fullscreen_visibility_integration import app_hashes, file_hashes
from script.tests.test_scene_pkg_cache_extractor import make_package
from script.scene_swift_source_sets import scene_swift_sources


REPO = Path(__file__).resolve().parents[2]
CANVAS = (160, 96)
TOLERANCE = 4
POINTS = {"model": (80, 48), "shadow": (60, 48), "receiver": (140, 48),
          "witness": (120, 72), "healthy": (145, 80), "hiddenProvider": (20, 72)}
# Display-domain model light contract: 180 * intensity 2 * energy 0.30 * cos(45°).
RECEIVER_RGB = [76, 76, 76]
PLATFORMS = {"dim": [0, 50, 0], "bright": [0, 100, 0], "transparent": RECEIVER_RGB}
SOURCES = tuple(REPO / "script/tests" / name for name in (
    "test_scene_model_graph_albedo.py", "test_scene_directional_shadow_integration.py",
    "test_scene_static_model_reader.py", "test_scene_pkg_cache_extractor.py",
    "test_scene_fullscreen_visibility_integration.py"))
VERTEX = b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n"
FRAGMENT = b'''uniform sampler2D g_Texture0;
uniform float g_Time;
varying vec2 v_TexCoord;
void main() {
    vec4 color = texSample2D(g_Texture0, v_TexCoord);
    float blue = step(2.0, g_Time) * (1.0 - step(4.0, g_Time));
    float transparent = step(4.0, g_Time) * (1.0 - step(6.0, g_Time));
    color.rgb *= 0.25 + 0.25 * blue;
    color.a *= 1.0 - transparent;
    gl_FragColor = color;
}
'''


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture_entries(*, early=False, source_only=False, visibility=False, bad_material=False,
                    retire_provider=False):
    scene, entries = shadow_fixture(caster_lit=False)
    scene["general"].update(lightconfig={"directional": 1}, ambientcolor="0 0 0")
    next(layer for layer in scene["objects"] if layer.get("light") == "ldirectional")["intensity"] = 2
    caster = next(layer for layer in scene["objects"] if layer["id"] == 2)
    caster["dependencies"] = [11]
    if visibility:
        caster["visible"] = {"user": {"name": "mode", "condition": "shown"}, "value": True}
    material = json.loads(entries["materials/caster.json"])
    material["passes"][0].update(textures=["_rt_imageLayerComposite_11_a"], blending="translucent")
    if bad_material:
        material["passes"][0].update(shader="own_model_interface", constantshadervalues={
            "Alpha": "1 2", "Color": "1 1 1", "Brigtness": 1})
        entries["shaders/own_model_interface.vert"] = b"attribute vec3 a_Position;\nvoid main(){gl_Position=vec4(a_Position,1.0);}\n"
        entries["shaders/own_model_interface.frag"] = b'''uniform float g_TintAlpha; // {"material":"Alpha","default":1}
uniform vec3 g_TintColor; // {"material":"Color","default":[1,1,1]}
uniform float g_Brightness; // {"material":"Brigtness","default":1}
void main(){gl_FragColor=vec4(1.0);}
'''
    entries["materials/caster.json"] = encoded(material)
    effect = {"id": 110, "file": "effects/own_model_clock/effect.json", "visible": True}
    provider = {"id": 11, "image": "models/provider.json", "origin": "20 24 0",
                "size": "8 8", "visible": False}
    if not source_only:
        provider["effects"] = [effect]
    scene["objects"].insert(0 if early else len(scene["objects"]), provider)
    scene["objects"] += [
        {"id": 40, "image": "models/provider.json", "origin": "120 24 0", "size": "8 8",
         "effects": [{**effect, "id": 400}]},
        {"id": 41, "model": "models/healthy.mdl", "origin": "0 96 0",
         "perspective": False, "castshadow": False}]
    if bad_material:
        # The rejected model is followed by a healthy graph before its hidden
        # provider. An orphan provider transaction must not block that graph.
        scene["objects"].remove(provider)
        scene["objects"].append(provider)
    if retire_provider:
        provider["name"] = "retired-provider"
        witness = next(layer for layer in scene["objects"] if layer["id"] == 40)
        witness["visible"] = {"value": True, "script": """
let removed = false;
export function update(value) {
    if (engine.runtime > 2 && !removed) {
        thisScene.destroyLayer('retired-provider'); removed = true;
    }
    return true;
}
"""}
    entries.update({
        "models/provider.json": encoded({"material": "materials/provider.json"}),
        "materials/provider.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/green.png"]}]}),
        "effects/own_model_clock/effect.json": encoded({"passes": [{"material": "materials/own_model_clock.json"}]}),
        "materials/own_model_clock.json": encoded({"passes": [{"shader": "own_model_clock",
            "textures": [None], "blending": "normal", "depthtest": "disabled",
            "depthwrite": "disabled", "cullmode": "nocull"}]}),
        "shaders/own_model_clock.vert": VERTEX, "shaders/own_model_clock.frag": FRAGMENT,
        "models/healthy.mdl": quad(141, 149, 76, 84, 25, "materials/healthy.json"),
        "materials/healthy.json": encoded({"passes": [{"shader": "genericimage",
            "textures": ["materials/blue.png"], "combos": {"LIGHTING": 0},
            "blending": "normal", "cullmode": "nocull", "depthwrite": "enabled"}]}),
        "materials/blue.png": png([0, 0, 255, 255])})
    entries["scene.json"] = encoded(scene)
    project = {"type": "scene", "file": "scene.json", "general": {"properties": {
        "mode": {"type": "combo", "value": "shown", "options": [
            {"label": value, "value": value} for value in ("hidden", "shown")]}}}}
    return project, entries


def measure(path):
    from PIL import Image, ImageStat
    with Image.open(path) as source:
        image = source.convert("RGB")
    width, height = image.size
    scale = max(width / CANVAS[0], height / CANVAS[1])
    pixels = {}
    for name, (x, y) in POINTS.items():
        cx, cy = width / 2 + (x - 80) * scale, height / 2 + (y - 48) * scale
        if not (3 <= cx < width - 3 and 3 <= cy < height - 3):
            raise AssertionError(f"preregistered ROI cropped: {name}, {(width, height)}")
        pixels[name] = ImageStat.Stat(image.crop((round(cx) - 2, round(cy) - 2,
            round(cx) + 2, round(cy) + 2))).mean
    return {"dimensions": [width, height], "pixels": pixels}


def app_identity(executable):
    contents = executable.parent.parent
    return {**app_hashes(executable), **file_hashes([
        contents / "Helpers/glslang", contents / "Helpers/spirv-cross",
        contents / "Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/product-manifest.json"])}


PLAN_HARNESS = r'''
import Foundation
import Metal
extension SceneMainPassEncoder {
    convenience init(commandBuffer: MTLCommandBuffer, target: MTLTexture,
                     clearColor: MTLClearColor, clearEnabled: Bool,
                     submissionOwner: SceneMainPassEncoder) {
        self.init(commandBuffer: commandBuffer, target: target,
                  clearColor: clearColor, clearEnabled: clearEnabled)
    }
}
@main enum Harness {
    static func plan(_ kind: String) -> [String: Any] {
        let sourceOnly = kind == "source"
        let early = kind == "early"
        let named = kind == "secondary" ? "_rt_imageLayerComposite_11_b" : "_rt_imageLayerComposite_11_a"
        let graphPath = kind == "background" ? "_rt_FullFrameBuffer" : nil
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0, texturePaths: graphPath.map { [$0] } ?? [],
            textureSlots: [graphPath], combos: [:], constantShaderValues: [:])
        let provider = SceneRenderDescriptor.Layer(id: 11, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: kind == "dependency" ? [12] : [],
            childLayerIDs: kind == "child" ? [12] : [], visible: kind == "visible",
            effects: sourceOnly ? [] : [.init(id: "owned-clock", file: "effects/owned/effect.json",
                visible: true, passes: [pass])])
        let model = SceneRenderDescriptor.Layer(id: 2, staticModelPath: "models/owned.mdl",
            contentKind: "model", utilityLayer: nil, dependencyLayerIDs: [11],
            childLayerIDs: [], visible: false, effects: [])
        let neighbor = SceneRenderDescriptor.Layer(id: 40, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [], childLayerIDs: [], visible: true, effects: [])
        let effectConsumer = SceneRenderDescriptor.Layer(id: 50, contentKind: "image", utilityLayer: nil,
            dependencyLayerIDs: [11], childLayerIDs: [], visible: true, effects: [.init(id: "sample",
                file: "effects/own_sample/effect.json", visible: true, passes: [.init(passIndex: 0,
                    texturePaths: ["_rt_imageLayerComposite_11_a"], textureSlots: [nil, "_rt_imageLayerComposite_11_a"],
                    combos: [:], constantShaderValues: [:])])])
        let order = kind == "mixed" ? [2, 40, 50, 11] : early ? [11, 2, 40] : [2, 40, 11]
        let layers = [model, neighbor, provider] + (kind == "mixed" ? [effectConsumer] : [])
        let descriptor = SceneRenderDescriptor(layers: layers, renderOrderLayerIDs: order,
            modelMaterialLinks: [.init(modelPath: "models/owned.mdl", materialPath: "materials/owned.json")],
            materialPasses: [.init(materialPath: "materials/owned.json", passIndex: 0,
                texturePaths: [named], textureSlots: [named], userTextureInputs: [])])
        let plan = SceneDependencyRenderPlan(descriptor: descriptor, visibleLayerIDs: kind == "mixed" ? [40, 50] : [40],
            admittedResolvedMaterialReferences: Set(SceneDependencyGraphAnalysis.references(in: layers)))
        return ["binding": plan.staticModelBindingsByConsumerLayerID[2] != nil,
            "effectBinding": plan.bindingsByConsumerLayerID[50] != nil,
            "required": plan.requiredProviderLayerIDs.sorted(),
            "graph": plan.requiredGraphOutputProviderLayerIDs.sorted(),
            "active": plan.resolvedMaterialExecutionLayerIDs(visibleRootLayerIDs: [2, 40],
                availableExecutionLayerIDs: [11, 40]).sorted(),
            "inactive": plan.resolvedMaterialExecutionLayerIDs(visibleRootLayerIDs: [40],
                availableExecutionLayerIDs: [11, 40]).sorted(),
            "forward": plan.forwardDependencyPreparationOrder(authoredLayerIDs: order,
                activeExecutionLayerIDs: [11, 40], activeStaticModelConsumerLayerIDs: [2]) ?? [],
            "inactiveForward": plan.forwardDependencyPreparationOrder(authoredLayerIDs: order,
                activeExecutionLayerIDs: [40], activeStaticModelConsumerLayerIDs: []) ?? [],
            "preparation": plan.resolvedMaterialPreparationOrder(authoredLayerIDs: [40, 11]) ?? [],
            "authored": descriptor.renderOrderLayerIDs]
    }
    static func main() throws {
        let cases = ["late", "early", "source", "background", "secondary", "dependency", "child", "visible", "mixed"]
        let rows = Dictionary(uniqueKeysWithValues: cases.map { ($0, plan($0)) })
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneModelGraphAlbedoPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            raise unittest.SkipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="model-graph-plan-") as temporary:
            root = Path(temporary)
            source, binary = root / "Harness.swift", root / "plan"
            source.write_text(PLAN_HARNESS)
            built = subprocess.run([swiftc, *map(str, SWIFT_SOURCES), str(source),
                "-module-cache-path", str(root / "cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            if built.returncode:
                raise AssertionError(built.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            if result.returncode:
                raise AssertionError(result.stderr)
            cls.rows = json.loads(result.stdout)

    def test_model_roots_activate_only_required_graph_and_prepare_before_shadow(self):
        for name in ("early", "late"):
            with self.subTest(case=name):
                row = self.rows[name]
                self.assertTrue(row["binding"], row)
                self.assertEqual(row["required"], [11])
                self.assertEqual(row["graph"], [11])
                self.assertEqual(row["active"], [11, 40])
                self.assertEqual(row["inactive"], [40])
                self.assertEqual(row["forward"], [11])
                self.assertEqual(row["inactiveForward"], [])
                self.assertEqual(row["preparation"], [11, 40])
                self.assertEqual(row["authored"], [11, 2, 40] if name == "early" else [2, 40, 11])

    def test_source_only_contract_and_unsafe_graph_shapes_stay_bounded(self):
        row = self.rows["source"]
        self.assertTrue(row["binding"])
        self.assertEqual(row["graph"], [])
        self.assertEqual(row["active"], [40])
        self.assertEqual(row["forward"], [11])
        self.assertEqual(row["preparation"], [40, 11])
        for name in ("background", "secondary", "dependency", "child", "visible"):
            with self.subTest(case=name):
                row = self.rows[name]
                self.assertFalse(row["binding"], row)
                self.assertEqual(row["required"], [])
                self.assertEqual(row["graph"], [])
                self.assertEqual(row["active"], [40])
        mixed = self.rows["mixed"]
        self.assertFalse(mixed["binding"], mixed)
        self.assertTrue(mixed["effectBinding"], mixed)
        self.assertEqual(mixed["graph"], [11])


class SceneModelGraphAlbedoShaderTests(unittest.TestCase):
    def test_owned_shader_has_existing_source_carried_color_contract(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc unavailable")
        harness = '''import Foundation
@main enum Harness {
    static func main() throws {
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let fact = SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
        print(fact == .straightAlpha(textureSlot: 0) ? "accepted" : "rejected")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="model-graph-shader-") as temporary:
            root = Path(temporary)
            source, fragment, binary = root / "Harness.swift", root / "owned.frag", root / "proof"
            source.write_text(harness)
            fragment.write_bytes(FRAGMENT)
            built = subprocess.run([swiftc, "-parse-as-library",
                *map(str, scene_swift_sources("authored_shader_frontend_core")), str(source),
                "-module-cache-path", str(root / "cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stderr)
            result = subprocess.run([str(binary), str(fragment)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "accepted")


NATIVE_MAIN = r'''
@main enum ModelGraphProbe {
    static func texture(_ d: MTLDevice, _ width: Int, _ height: Int, _ byte: UInt8) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        desc.storageMode = .shared; desc.usage = [.shaderRead, .renderTarget]
        let t = d.makeSceneTexture(descriptor: desc)!
        let bytes = [UInt8](repeating: byte, count: width * height * 4)
        bytes.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        return t
    }
    static func main() throws {
        guard let d = MTLCreateSystemDefaultDevice(), let queue = d.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        let provider = SceneRenderDescriptor.Layer(id: 11, contentKind: "image",
            utilityLayer: nil, alpha: 1, colorRGB: [1, 1, 1], effects: [.init(visible: true)])
        let runtime = SceneDependencyFrameRuntime(descriptor: .init(layers: [provider], bindings: [:],
            graphOutputProviderLayerIDs: [11], staticModelConsumerProviders: [2: 11, 3: 11]),
            visibleLayerIDs: [2, 3], executableUtilityConsumerLayerIDs: [], device: d)
        let registry = SceneFrameTextureRegistry(), reference = SceneNamedTextureReference(providerLayerID: 11, variant: .primary)
        func input(_ consumer: Int = 2) -> SceneStaticModelNamedAlbedoInput? {
            runtime.staticModelNamedAlbedo(for: consumer, materialPath: "materials/unseen/runtime.json",
                expectedReference: reference, textureRegistry: registry)
        }
        func reserve(_ epoch: UInt64, _ width: Int, _ height: Int) -> Bool {
            var reason: String?
            return runtime.reserveStaticModelGraphOutput(providerLayer: provider,
                preparedOutputExtent: (width, height), frameEpoch: epoch, failureReason: &reason)
        }
        func isPublished(_ result: SceneGraphOutputPublicationResult?) -> Bool {
            result == .published
        }
        var rows: [[String: Any]] = []
        // The prepared-plan scaffold returns the intersected roots. Listing a
        // model as available here observes only wrapper input projection/memo;
        // the real plan test above proves models never gain graph identities.
        let memoRoots = [[2], [], [2]].map { prepared -> [Int] in
            runtime.resolvedMaterialFrameDemand(visibleRootLayerIDs: [2, 40],
                availableExecutionLayerIDs: [2, 40], liveLayerIDs: [2, 11, 40],
                activeStaticModelConsumerLayerIDs: Set(prepared)).activeExecutionLayerIDs.sorted()
        }
        for frame in 1...2 {
            let epoch = registry.beginFrame(frameIndex: UInt64(frame), layerSources: [:])
            let graph = texture(d, frame * 8, frame * 4, UInt8(frame * 40))
            let staleUnavailable = input() == nil
            let reserved = reserve(epoch, graph.width, graph.height)
            let unpublished = input() == nil
            let installed = runtime.installPreparedGraphOutputs([11: graph], frameEpoch: epoch)
            let cb = queue.makeCommandBuffer()!, before = ScenePerformanceCounterHub.shared.snapshot()[.graphOutputPublicationCopies] ?? 0
            let published = runtime.publishGraphOutputIfRequired(layerID: 11, texture: graph,
                publicationRole: .namedProviderPrepass, textureRegistry: registry, commandBuffer: cb)
            let repeated = runtime.publishGraphOutputIfRequired(layerID: 11, texture: graph,
                publicationRole: .namedProviderPrepass, textureRegistry: registry, commandBuffer: cb)
            let first = input(), second = input(3)
            let readback = texture(d, graph.width, graph.height, 0), blit = cb.makeBlitCommandEncoder()!
            blit.copy(from: first!.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: graph.width, height: graph.height, depth: 1), to: readback,
                destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding(); cb.commit(); cb.waitUntilCompleted(); registry.commitFramePublication()
            var bytes = [UInt8](repeating: 0, count: graph.width * graph.height * 4)
            readback.getBytes(&bytes, bytesPerRow: graph.width * 4,
                from: MTLRegionMake2D(0, 0, graph.width, graph.height), mipmapLevel: 0)
            rows.append(["epoch": epoch, "extent": [first!.texture.width, first!.texture.height],
                "staleUnavailable": staleUnavailable, "reserved": reserved, "unpublished": unpublished,
                "installed": installed, "published": isPublished(published), "repeated": isPublished(repeated),
                "distinct": first!.texture !== graph, "shared": first!.texture === second?.texture,
                "current": first!.frameEpoch == epoch && first!.isPremultiplied,
                "copies": (ScenePerformanceCounterHub.shared.snapshot()[.graphOutputPublicationCopies] ?? 0) - before,
                "completed": cb.status == .completed && cb.error == nil,
                "exactBytes": bytes.allSatisfy { $0 == UInt8(frame * 40) }])
        }
        let epoch = registry.beginFrame(frameIndex: 3, layerSources: [:]), graph = texture(d, 8, 4, 120)
        let missing = runtime.publishGraphOutputIfRequired(layerID: 11, texture: graph,
            publicationRole: .namedProviderPrepass, textureRegistry: registry, commandBuffer: queue.makeCommandBuffer()!)
        var report: [String: Any] = ["frames": rows, "memoRoots": memoRoots, "oldPublicationUnavailable": input() == nil,
            "staleReservationRejected": missing == .invalid(reasonCode: "named-provider-reservation-missing"),
            "demandCleared": runtime.demandedGraphOutputProviderLayerIDs.isEmpty,
            "zeroEpochRejected": !reserve(0, 8, 4), "invalidExtentRejected": !reserve(epoch, 0, 4)]
        let budget = SceneResourceBudget.shared, held = budget.maximumBytes - budget.snapshot.residentBytes
        precondition(budget.reserve(held, kind: .gpu))
        report["allocationFailureLocal"] = !reserve(epoch, 8, 4) && input() == nil
        budget.release(held, kind: .gpu)
        report["allocationRecovers"] = reserve(epoch, 8, 4)
        report["wrongExtentRejected"] = !runtime.installPreparedGraphOutputs([11: texture(d, 9, 4, 120)], frameEpoch: epoch)
        let cb = queue.makeCommandBuffer()!
        let data = runtime.publishGraphOutputIfRequired(layerID: 11, texture: graph,
            publicationRole: .namedProviderPrepass, textureRegistry: registry, commandBuffer: cb, content: .data)
        cb.commit(); cb.waitUntilCompleted()
        report["dataNotAlbedo"] = input() == nil
        report["dataPublished"] = isPublished(data)
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(os.environ.get("MWX_SCENE_INTEGRATION_APP"), "requires explicit isolated GPU/App run")
class SceneModelGraphAlbedoNativeTests(unittest.TestCase):
    def test_real_reservation_publication_epoch_content_and_budget(self):
        from script.tests import test_scene_named_model_shadow as native
        from script.tests.test_scene_directional_shadow import run_swift
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        previous = os.environ.get("MWX_DIRECTIONAL_SHADOW_EVIDENCE")
        if parent:
            os.environ["MWX_DIRECTIONAL_SHADOW_EVIDENCE"] = parent
        try:
            report = run_swift(native.DEPENDENCY_SOURCES, native.dependency_support() + NATIVE_MAIN,
                label="model-graph-epoch")
        finally:
            if previous is None:
                os.environ.pop("MWX_DIRECTIONAL_SHADOW_EVIDENCE", None)
            else:
                os.environ["MWX_DIRECTIONAL_SHADOW_EVIDENCE"] = previous
        self.assertEqual([row["extent"] for row in report["frames"]], [[8, 4], [16, 8]])
        self.assertEqual(report["memoRoots"], [[2, 40], [40], [2, 40]])
        self.assertLess(report["frames"][0]["epoch"], report["frames"][1]["epoch"])
        for row in report["frames"]:
            self.assertEqual(row["copies"], 1, row)
            for key in ("staleUnavailable", "reserved", "unpublished", "installed", "published", "repeated",
                        "distinct", "shared", "current", "completed", "exactBytes"):
                self.assertTrue(row[key], (key, row))
        for key in ("oldPublicationUnavailable", "staleReservationRejected", "demandCleared",
                    "zeroEpochRejected", "invalidExtentRejected", "allocationFailureLocal",
                    "allocationRecovers", "wrongExtentRejected", "dataPublished", "dataNotAlbedo"):
            self.assertTrue(report[key], (key, report))


class SceneModelGraphAlbedoAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not configured:
            raise unittest.SkipTest("requires frozen MWX_SCENE_INTEGRATION_APP")
        app = Path(configured).resolve(strict=True)
        cls.exe = app / "Contents/MacOS/MyWallpaperX" if app.suffix == ".app" else app
        cls.app_identity, cls.source_identity = app_identity(cls.exe), file_hashes(SOURCES)
        parent = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-graph-app-", dir=parent))
        cls.runs = {}
        print(f"model graph albedo evidence: {cls.root}", flush=True)

    def run_case(self, name, **options):
        if name in self.runs:
            return self.runs[name]
        work = self.root / name
        (work / "content").mkdir(parents=True)
        (work / "home").mkdir()
        project, entries = fixture_entries(**options)
        (work / "content/project.json").write_bytes(encoded(project))
        (work / "content/scene.pkg").write_bytes(make_package(list(entries.items())))
        (work / "scene-input.json").write_bytes(entries["scene.json"])
        inputs = tuple((work / "content").iterdir())
        sequence = [{"mode": "hidden"}, {"mode": "shown"}] if options.get("visibility") else []
        duration = 10 if not options.get("source_only") else 6
        command = [str(self.exe), "--mwx-debug-scene-root", str(work / "content"),
            "--mwx-debug-scene-duration", str(duration), "--mwx-debug-scene-evidence-dir", str(work / "evidence"),
            "--mwx-debug-scene-after-snapshot-delay", "7.2" if duration == 10 else "4.2"]
        if duration == 10:
            command += ["--mwx-debug-scene-periodic-snapshot-interval", "0.5"]
        if sequence:
            command += ["--mwx-debug-scene-properties-json", encoded({"mode": "shown"}).decode(),
                "--mwx-debug-scene-live-property-sequence-json", encoded(sequence).decode()]
        identity = {"app": self.app_identity, "sources": self.source_identity,
            "inputs": file_hashes(inputs), "entries": {
                key: hashlib.sha256(data).hexdigest() for key, data in entries.items()}}
        (work / "prerun.json").write_bytes(encoded({**identity, "command": command}))
        (work / "preregistration.json").write_bytes(encoded({"canvas": CANVAS, "points": POINTS,
            "rawSourceRGB": [0, 200, 0], "platforms": PLATFORMS, "tolerance": TOLERANCE,
            "shadowOpaqueMaximum": 15, "sourceOnly": options.get("source_only", False),
            "oracle": "same-frame owned image witness gives dynamic graph-final phase; model z20 shadows receiver x60",
            "boundary": "owned effectful named static model slice, no official parity"}))
        self.assertEqual(app_identity(self.exe), self.app_identity)
        self.assertEqual(file_hashes(SOURCES), self.source_identity)
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("MWX_SCENE_DEBUG_", "MYWALLPAPERX_SCENE_DEBUG_"))}
        env.update(HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"),
            MWX_SCENE_DEBUG_SURFACE_COUNT="1", MWX_SCENE_GENERIC_SHADER_CACHE=str(work / "cache"))
        with (work / "app.log").open("w") as output:
            result = subprocess.run(command, cwd=REPO, env=env, stdout=output,
                stderr=subprocess.STDOUT, timeout=90)
        log = (work / "app.log").read_text()
        pixels = {path.name: measure(path) for path in sorted((work / "evidence").glob("*window.png"))}
        report = {"exit": result.returncode, "pixels": pixels, "command": command,
            "appAfter": app_identity(self.exe), "sourcesAfter": file_hashes(SOURCES),
            "inputsAfter": file_hashes(inputs), "work": str(work),
            "publicationEvents": [line for line in log.splitlines() if "phase=named-graph-output-publication layer=11" in line],
            "shadowEvents": [line for line in log.splitlines() if "shadow phase=" in line]}
        (work / "result.json").write_bytes(encoded(report))
        self.assertEqual(result.returncode, 0, log[-6000:])
        for key, expected in (("appAfter", self.app_identity), ("sourcesAfter", self.source_identity),
                              ("inputsAfter", identity["inputs"])):
            self.assertEqual(report[key], expected)
        self.assertRegex(log, r"state=completed frame=1 surface=\d+ gpu=completed")
        self.assertRegex(log, r"state=completed frame=2 surface=\d+ gpu=completed")
        self.assertIn("gpuDrained=true", log)
        self.assertNotRegex(log, r"phase=launch-failed|phase=snapshot-(?:failed|rejected)|failure=exception")
        self.assertIn("scene-ready-window.png", pixels)
        self.assertIn("scene-after-window.png", pixels)
        for row in pixels.values():
            self.assert_rgb(row["pixels"]["healthy"], [0, 0, 255])
            self.assert_rgb(row["pixels"]["receiver"], RECEIVER_RGB)
            self.assert_rgb(row["pixels"]["hiddenProvider"], RECEIVER_RGB)
        self.runs[name] = report
        return report

    def assert_rgb(self, actual, expected):
        for value, wanted in zip(actual, expected):
            self.assertAlmostEqual(value, wanted, delta=TOLERANCE)

    def platform(self, rgb):
        return next((name for name, expected in PLATFORMS.items()
            if all(abs(a - b) <= TOLERANCE for a, b in zip(rgb, expected))), None)

    def assert_graph_pixels(self, result):
        observed = set()
        for row in result["pixels"].values():
            pixels = row["pixels"]
            phase = self.platform(pixels["witness"])
            if phase is None:
                continue  # Only compare preregistered stable plateaus.
            observed.add(phase)
            self.assert_rgb(pixels["model"], pixels["witness"])
            if phase == "transparent":
                self.assert_rgb(pixels["shadow"], pixels["receiver"])
            else:
                self.assertLess(max(pixels["shadow"]), 15)
        self.assertEqual(observed, set(PLATFORMS), result)
        self.assertTrue(result["publicationEvents"], result)

    def test_effectful_provider_after_model_uses_graph_final_and_current_shadow(self):
        source = self.run_case("source-only", source_only=True)
        for row in source["pixels"].values():
            self.assert_rgb(row["pixels"]["model"], [0, 200, 0])
            self.assertLess(max(row["pixels"]["shadow"]), 15)
        self.assert_graph_pixels(self.run_case("effectful-late"))

    def test_effectful_provider_before_model_uses_same_graph_once(self):
        self.assert_graph_pixels(self.run_case("effectful-early", early=True))

    def test_model_visibility_removes_and_restores_graph_demand(self):
        result = self.run_case("model-visibility", visibility=True)
        log = (Path(result["work"]) / "app.log").read_text()
        self.assertEqual(re.findall(r"phase=live-property-sequence-step index=(\d+) accepted=(true|false)", log),
                         [("0", "true"), ("1", "true")])
        updates = log.split("phase=live-property-sequence-step")
        self.assertEqual(len(updates), 3)
        for name in ("scene-ready-window.png", "scene-after-window.png"):
            pixels = result["pixels"][name]["pixels"]
            self.assert_rgb(pixels["model"], pixels["witness"])
            self.assertLess(max(pixels["shadow"]), 15)
        hidden = result["pixels"]["scene-series-0002-window.png"]["pixels"]
        self.assert_rgb(hidden["model"], hidden["receiver"])
        self.assert_rgb(hidden["shadow"], hidden["receiver"])

    def test_unprepared_model_keeps_provider_idle_and_independent_graph_live(self):
        result = self.run_case("unprepared-model", bad_material=True)
        work = Path(result["work"])
        log, preview = (work / "app.log").read_text(), (work / "evidence/scene-preview.log").read_text()
        self.assertRegex(log, r"model-material layer=2 state=rejected reason=\S+")
        self.assertIn("prepared static model layers: [1, 41]", preview)
        order = [layer["id"] for layer in json.loads((work / "scene-input.json").read_text())["objects"]]
        self.assertLess(order.index(2), order.index(40))
        self.assertLess(order.index(40), order.index(11))
        # Confirm the real reader still published the MDL material link and
        # authored primary reference; this is a rejected Entry, not a lost link.
        runtime = json.loads((work / "evidence/scene-runtime-evidence.json").read_text())["runtimeInput"]["renderDescriptor"]
        self.assertTrue(any(link.get("modelPath") == "models/caster.mdl"
            and link.get("materialPath") == "materials/caster.json" for link in runtime["modelMaterialLinks"]))
        self.assertTrue(any(material.get("materialPath") == "materials/caster.json"
            and material.get("textureSlots") == ["_rt_imageLayerComposite_11_a"] for material in runtime["materialPasses"]))
        material = next(item for item in runtime["materialPasses"] if item.get("materialPath") == "materials/caster.json")
        self.assertIn("Alpha", material["constantShaderValues"])
        self.assertEqual(material["staticModelMaterialBindings"]["state"], "rejected")
        self.assertFalse(result["publicationEvents"], result)
        observed = set()
        for row in result["pixels"].values():
            pixels = row["pixels"]
            phase = self.platform(pixels["witness"])
            if phase:
                observed.add(phase)
            self.assert_rgb(pixels["model"], pixels["receiver"])
            self.assert_rgb(pixels["shadow"], pixels["receiver"])
        self.assertEqual(observed, set(PLATFORMS), result)


    def test_deleted_named_provider_does_not_block_healthy_output(self):
        result = self.run_case("deleted-provider", retire_provider=True)
        before = result["pixels"]["scene-ready-window.png"]["pixels"]
        after = result["pixels"]["scene-after-window.png"]["pixels"]
        self.assert_rgb(before["model"], before["witness"])
        self.assertLess(max(before["shadow"]), 15)
        self.assert_rgb(after["model"], after["receiver"])
        self.assert_rgb(after["shadow"], after["receiver"])
        self.assert_rgb(after["healthy"], [0, 0, 255])
        self.assertTrue(result["publicationEvents"], result)

if __name__ == "__main__":
    unittest.main()
