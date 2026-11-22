"""Real text pixels preserve content anchors while padding grows each edge."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.scene.test_scene_text_row_limit import HARNESS_SOURCE as ROW_HARNESS
from script.tests.scene.test_scene_text_row_limit import SWIFT_SOURCES as ROW_SOURCES

SWIFT_SOURCES = [*ROW_SOURCES, Path(__file__).resolve().parents[3]
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneTextLayerPivot.swift"]


def fixture_scene():
    base = {"text": "HO", "font": "systemfont_arial", "pointsize": 16,
        "color": "1 1 1", "size": "1 1", "opaquebackground": True,
        "backgroundcolor": "0 0 1"}
    objects = []
    for horizontal in ["left", "center", "right"]:
        for vertical in ["top", "center", "bottom"]:
            for padding in [0, 32, 64]:
                objects.append(base | {"id": len(objects) + 1,
                    "name": f"{horizontal}-{vertical}-{padding}", "padding": padding,
                    "horizontalalign": horizontal, "verticalalign": vertical})
    for name, fields in [
        ("size-small", {"size": "1 1"}),
        ("size-large", {"size": "640 320"}),
        ("wrap-small", {"size": "1 1", "limitwidth": True}),
        ("wrap-large", {"size": "640 320", "limitwidth": True}),
        ("wrap-pad0", {"size": "1 1", "limitwidth": True, "padding": 0}),
    ]:
        objects.append(base | {"id": len(objects) + 1, "name": name,
            "text": "AAAA BBBB" if name.startswith("wrap-") else "HO",
            "pointsize": 12, "padding": 32, "horizontalalign": "left",
            "verticalalign": "top", "maxwidth": 200} | fields)
    for padding in [0, 64]:
        objects.append(base | {"id": len(objects) + 1, "name": f"scaled-{padding}",
            "text": "W" * 260, "pointsize": 32, "padding": padding,
            "horizontalalign": "left", "verticalalign": "top"})
    objects.append(base | {"id": len(objects) + 1, "name": "center-arial-official",
        "text": "H0", "pointsize": 32, "padding": 32,
        "horizontalalign": "center", "verticalalign": "center"})
    return {"version": 3, "objects": objects}


HARNESS = ROW_HARNESS.partition("\n@main\n")[0] + r'''
import simd
import CryptoKit
@main enum PaddingProbe {
 static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let project = SceneProject(
            rootURL: sceneURL.deletingLastPathComponent(),
            entryPath: sceneURL.lastPathComponent,
            userProperties: .empty
        )
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: project,
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [],
                materials: [],
                effectDefinitions: [],
                effectDefinitionDiagnostics: [],
                shaderReferences: [],
                textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else {
            throw HarnessError.descriptorRejected
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let resourceView = SceneResourceView(projectRoot: .init(source: .loose,
            url: sceneURL.deletingLastPathComponent()), packageRoot: nil, stockRoot: nil)

        let loaded = SceneTextTextureLoader.load(
            descriptor: descriptor,
            resourceView: resourceView,
            device: device
        )

 var result: [String:Any] = [:]
 for layer in descriptor.layers {
  guard let raster = loaded.rasters[layer.id], let style = layer.textStyle else { continue }
  func measure(_ raster: SceneTextTextureLoader.RasterizedTexture) -> [String:Any] {
   let tex=raster.texture, logical=raster.renderSizeWH
   let w=tex.width, h=tex.height
   var bytes=[UInt8](repeating:0,count:w*h*4)
   tex.getBytes(&bytes,bytesPerRow:w*4,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0)
   let scaleX=Double(w)/Double(logical[0]), logicalHeight=Double(logical[1])
   func contentPivot(_ vertical: String, height: Double, offsetY: Double) -> SIMD2<Float> {
    SceneTextLayerPivot.unitOffset(horizontal:style.horizontalAlignment,vertical:vertical,
        renderSize:SIMD2(logical[0],Float(height)),padding:style.padding,
        centerOffsetY:raster.centerOffsetY,rasterOffsetY:Float(offsetY))
   }
   func worldY(_ y: Double, rows: Int, height: Double, pivotY: Float) -> Double {
    (y/Double(rows)-0.5-Double(pivotY))*height
   }
   let pivot=contentPivot(style.verticalAlignment,height:logicalHeight,offsetY:Double(raster.rasterOffsetY))
   var minX=w, minY=h, maxX = -1, maxY = -1, ink=0
   var minAlphaX=w, minAlphaY=h, maxAlphaX = -1, maxAlphaY = -1
   var inkRows=Set<Int>()
   for y in 0..<h { for x in 0..<w { let i=(y*w+x)*4
    if bytes[i+3]>0 { minAlphaX=min(minAlphaX,x); maxAlphaX=max(maxAlphaX,x); minAlphaY=min(minAlphaY,y); maxAlphaY=max(maxAlphaY,y) }
    if bytes[i+1]>=128 && bytes[i+2]>=128 { minX=min(minX,x); maxX=max(maxX,x); minY=min(minY,y); maxY=max(maxY,y); ink += 1; inkRows.insert(y) }
   }}
   let dx=Double(pivot.x*logical[0])
   let firstInkY=Double(minY)+0.5, lastInkY=Double(maxY)+0.5
   var facts: [String:Any] = ["size":logical,"raster":[w,h],"ink":ink,
    "rows":inkRows.filter { !inkRows.contains($0-1) }.count,
    "pixelSHA256":SHA256.hash(data:Data(bytes)).map { String(format:"%02x", $0) }.joined(),
    "glyphWorld":[(Double(minX)+0.5-Double(w)/2)/scaleX+dx,
        worldY(firstInkY,rows:h,height:logicalHeight,pivotY:pivot.y),
        (Double(maxX)+0.5-Double(w)/2)/scaleX+dx,
        worldY(lastInkY,rows:h,height:logicalHeight,pivotY:pivot.y)],
    "backgroundWorld":[(Double(minAlphaX)-Double(w)/2)/scaleX+dx,
        worldY(Double(minAlphaY),rows:h,height:logicalHeight,pivotY:pivot.y),
        (Double(maxAlphaX+1)-Double(w)/2)/scaleX+dx,
        worldY(Double(maxAlphaY+1),rows:h,height:logicalHeight,pivotY:pivot.y)]]
   if layer.name == "scaled-0" {
    // Reuse the actual ink rows. One leading and five trailing rows give
    // an asymmetric canvas without depending on a host font clipping.
    let rowHeight=logicalHeight/Double(h)
    let expandedHeight=logicalHeight+6*rowHeight
    var anchors: [String:[[Double]]] = [:]
    for (vertical, offsetInRows) in [("top",1.0),("center",-2.0),("bottom",-5.0)] {
     let before=contentPivot(vertical,height:logicalHeight,offsetY:0)
     let after=contentPivot(vertical,height:expandedHeight,offsetY:offsetInRows*rowHeight)
     anchors[vertical] = [firstInkY,lastInkY].map { y in
      [worldY(y,rows:h,height:logicalHeight,pivotY:before.y),
       worldY(y+1,rows:h+6,height:expandedHeight,pivotY:after.y)]
     }
    }
    facts["asymmetricAnchors"] = anchors
   }
   return facts
  }
  guard let same=try SceneTextTextureLoader.makeDynamicTexture(for:layer,content:layer.text!,pointSize:style.pointSize,colorRGB:style.colorRGB,resourceView:resourceView,device:device),
    let changed=try SceneTextTextureLoader.makeDynamicTexture(for:layer,content:"HOHO",pointSize:style.pointSize,colorRGB:style.colorRGB,resourceView:resourceView,device:device) else { throw HarnessError.descriptorRejected }
  var entry: [String:Any] = ["static":measure(raster),"same":measure(same),"changed":measure(changed)]
  if style.limitWidth {
   guard let widened=try SceneTextTextureLoader.makeDynamicTexture(for:layer,content:layer.text!,pointSize:style.pointSize,colorRGB:style.colorRGB,maxWidth:400,resourceView:resourceView,device:device) else { throw HarnessError.descriptorRejected }
   entry["widened"]=measure(widened)
  }
  result[layer.name ?? String(layer.id)] = entry
 }
 print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
 }
 enum HarnessError:Error {case missingFixture,descriptorRejected,noMetal}
}
'''


class SceneTextPaddingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        evidence = os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE")
        if evidence:
            Path(evidence).mkdir(parents=True, exist_ok=True)
            cls.temporary = None
            cls.root = Path(tempfile.mkdtemp(prefix="mwx-text-padding-", dir=evidence))
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-text-padding-")
            cls.root = Path(cls.temporary.name)
        fixture, harness, binary = [cls.root / name for name in ["scene.json", "Harness.swift", "probe"]]
        fixture.write_text(json.dumps(fixture_scene(), indent=2), encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, SWIFT_SOURCES),
            str(harness), "-framework", "Metal", "-framework", "CoreText", "-o", str(binary)]
        inputs = [*SWIFT_SOURCES, fixture, harness, Path(__file__).resolve()]
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (cls.root / "compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        run = subprocess.run([str(binary), str(fixture)], capture_output=True, text=True, timeout=60)
        after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        (cls.root / "identity.json").write_text(json.dumps({"command": command, "inputs": before,
            "unchanged": before == after, "binary": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "exit": run.returncode}, indent=2))
        (cls.root / "result.json").write_text(run.stdout)
        if run.returncode or before != after:
            raise AssertionError(run.stderr or "source changed during execution")
        cls.result = json.loads(run.stdout)

    @classmethod
    def tearDownClass(cls):
        if cls.temporary:
            cls.temporary.cleanup()

    def pairs(self):
        for horizontal in ["left", "center", "right"]:
            for vertical in ["top", "center", "bottom"]:
                key = horizontal + "-" + vertical
                for padding in [32, 64]:
                    yield key, padding, self.result[key + "-0"], self.result[key + "-" + str(padding)]

    def test_centered_arial_ink_matches_bounded_official_anchor(self):
        # Fixed official client, Arial 133px: H/0 ink center is 7.5..8px below
        # origin at 0.6 projected scale. Allow cross-platform raster rounding.
        glyph = self.result["center-arial-official"]["static"]["glyphWorld"]
        self.assertAlmostEqual((glyph[1] + glyph[3]) / 2, 12.9, delta=2)

    def test_padding_keeps_all_nine_content_anchors_for_static_and_changed_text(self):
        for key, padding, baseline, padded in self.pairs():
            for phase in ["static", "changed"]:
                with self.subTest(alignment=key, padding=padding, phase=phase):
                    self.assertGreater(padded[phase]["ink"], 0)
                    for actual, expected in zip(padded[phase]["glyphWorld"], baseline[phase]["glyphWorld"]):
                        self.assertAlmostEqual(actual, expected, delta=1)

    def test_padding_expands_each_background_edge_without_becoming_a_wrap_limit(self):
        for key, padding, baseline, padded in self.pairs():
            for phase in ["static", "changed"]:
                with self.subTest(alignment=key, padding=padding, phase=phase):
                    for axis in [0, 1]:
                        self.assertAlmostEqual(padded[phase]["size"][axis] - baseline[phase]["size"][axis], 2 * padding, delta=1)
                    for index, expected in enumerate([-padding, -padding, padding, padding]):
                        self.assertAlmostEqual(padded[phase]["backgroundWorld"][index] - baseline[phase]["backgroundWorld"][index], expected, delta=1)
                    self.assertAlmostEqual(padded[phase]["ink"], baseline[phase]["ink"], delta=4)

    def test_initial_and_same_content_update_produce_identical_geometry_and_pixels(self):
        self.assertEqual(len(self.result), 35)
        for name, case in self.result.items():
            with self.subTest(name=name):
                self.assertEqual(case["static"], case["same"])
                if name.startswith(("wrap-", "scaled-")):
                    continue
                self.assertGreater(case["changed"]["ink"], case["static"]["ink"])
                self.assertGreater(case["changed"]["glyphWorld"][2] - case["changed"]["glyphWorld"][0],
                    case["static"]["glyphWorld"][2] - case["static"]["glyphWorld"][0])

    def test_saved_size_is_not_a_content_limit_or_an_extra_blank_frame(self):
        for prefix in ["size", "wrap"]:
            with self.subTest(profile=prefix):
                self.assertEqual(self.result[prefix + "-small"], self.result[prefix + "-large"])

    def test_width_limit_and_dynamic_width_are_independent_of_padding_and_saved_size(self):
        for name in ["wrap-small", "wrap-large", "wrap-pad0"]:
            with self.subTest(name=name):
                case = self.result[name]
                self.assertGreater(case["static"]["ink"], 0)
                self.assertEqual(case["static"]["rows"], 2)
                self.assertEqual(case["widened"]["rows"], 1)
        padded, plain = [self.result[name]["static"] for name in ["wrap-small", "wrap-pad0"]]
        for actual, expected in zip(padded["glyphWorld"], plain["glyphWorld"]):
            self.assertAlmostEqual(actual, expected, delta=1)
        for axis in [0, 1]:
            self.assertAlmostEqual(padded["size"][axis] - plain["size"][axis], 64, delta=1)

    def test_intrinsic_2048_downsampling_does_not_rewrap_or_clip_the_last_line(self):
        plain, padded = [self.result[name]["static"] for name in ["scaled-0", "scaled-64"]]
        for case in [plain, padded]:
            self.assertGreater(case["size"][0], 2048)
            self.assertEqual(max(case["raster"]), 2048)
            self.assertEqual(case["rows"], 2)
        # One output pixel plus a logical pixel for integral extent rounding.
        tolerance = max(plain["size"][0], padded["size"][0]) / 2048 + 1
        for actual, expected in zip(padded["glyphWorld"], plain["glyphWorld"]):
            self.assertAlmostEqual(actual, expected, delta=tolerance)
        for vertical in ["top", "center", "bottom"]:
            with self.subTest(asymmetric_alignment=vertical):
                for original, expanded in plain["asymmetricAnchors"][vertical]:
                    self.assertAlmostEqual(expanded, original, delta=0.001)


if __name__ == "__main__":
    unittest.main()
