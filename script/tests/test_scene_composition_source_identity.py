#!/usr/bin/env python3
"""Actual composition source allocation and frame-lifetime behavior."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_offscreen_texture_pool as pool_fixture
from script.tests import test_scene_dependency_render_plan as dependency_fixture

SWIFT_SOURCES = list(dict.fromkeys(pool_fixture.SWIFT_SOURCES + dependency_fixture.SWIFT_SOURCES + [
    pool_fixture.SOURCE_ROOT / "Rendering/Composition/SceneMainPassEncoder.swift",
]))


HARNESS = pool_fixture.HARNESS.split("@main", 1)[0] + r'''
@main
enum CompositionSourceProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let queue = device.makeCommandQueue()!
        if CommandLine.arguments.contains("--gpu") {
            let gpuPool = SceneOffscreenTexturePool(device: device, maxDimension: 64,
                residentByteBudget: 512)
            func frame(_ command: MTLCommandBuffer) -> SceneCompositionGroupFrameRuntime {
                let main = device.makeTexture(descriptor: .texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: 16, height: 8, mipmapped: false))!
                let parent = SceneMainPassEncoder(commandBuffer: command, target: main,
                    clearColor: MTLClearColor(), clearEnabled: true)
                let runtime = SceneCompositionGroupFrameRuntime(parentPass: parent,
                    commandBuffer: command, offscreenTexturePool: gpuPool,
                    memberRootsByLayerID: [2: 1], membersByRootID: [1: [2]],
                    viewportSize: CGSize(width: 16, height: 8))
                runtime.reserveSources(orderedRootIDs: [1], visibleLayerIDs: [1])
                return runtime
            }
            let command = queue.makeCommandBuffer()!
            let runtime = frame(command)
            // Write a visible old frame into the selected source, then let its
            // actual command completion return it to the existing pool.
            let source = runtime.preparedSource(forLayerID: 1,
                mainTarget: device.makeTexture(descriptor: .texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false))!)!
            let redPass = MTLRenderPassDescriptor()
            redPass.colorAttachments[0].texture = source
            redPass.colorAttachments[0].loadAction = .clear
            redPass.colorAttachments[0].storeAction = .store
            redPass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
            command.makeRenderCommandEncoder(descriptor: redPass)!.endEncoding()
            let firstDone = DispatchSemaphore(value: 0)
            runtime.arm()
            command.addCompletedHandler { _ in firstDone.signal() }
            command.commit()
            precondition(firstDone.wait(timeout: .now() + 5) == .success)
            let second = queue.makeCommandBuffer()!
            let next = frame(second)
            let readable = next.groupTexture(forRootID: 1)!
            let reused = readable === source
            let pixels = device.makeBuffer(length: 256 * 8, options: .storageModeShared)!
            let blit = second.makeBlitCommandEncoder()!
            blit.copy(from: readable, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: 16, height: 8, depth: 1),
                to: pixels, destinationOffset: 0, destinationBytesPerRow: 256,
                destinationBytesPerImage: 256 * 8)
            blit.endEncoding()
            let event = device.makeSharedEvent()!
            second.encodeWaitForEvent(event, value: 1)
            let done = DispatchSemaphore(value: 0)
            next.arm()
            second.addCompletedHandler { _ in done.signal() }
            second.commit()
            gpuPool.reset()
            let heldUntilCompletion = gpuPool.residentByteCost == 512
                && gpuPool.compositionGroupTarget(layerID: 1, width: 16, height: 8,
                    commandBuffer: queue.makeCommandBuffer()!) == nil
            event.signaledValue = 1
            precondition(done.wait(timeout: .now() + 5) == .success)
            let bytes = pixels.contents().bindMemory(to: UInt8.self, capacity: 256 * 8)
            let transparent = (0..<8).allSatisfy { y in
                (0..<64).allSatisfy { x in bytes[y * 256 + x] == 0 }
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: [
                "reusedOldRedSource": reused, "emptySourceTransparent": transparent,
                "heldUntilCompletion": heldUntilCompletion,
                "releasedAfterCompletion": gpuPool.residentByteCost == 0,
                "completed": command.status == .completed && second.status == .completed,
            ], options: [.sortedKeys]), as: UTF8.self))
            return
        }
        let command = queue.makeCommandBuffer()!
        let pool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, residentByteBudget: 4096
        )
        let first = pool.compositionGroupTarget(layerID: 101, width: 16, height: 8, commandBuffer: command)
        let repeated = pool.compositionGroupTarget(layerID: 101, width: 16, height: 8, commandBuffer: command)
        let other = pool.compositionGroupTarget(layerID: 102, width: 16, height: 8, commandBuffer: command)
        let coldBytes = pool.residentByteCost
        let nextCommand = queue.makeCommandBuffer()!
        let replaced = pool.compositionGroupTarget(layerID: 101, width: 16, height: 8,
            commandBuffer: nextCommand)
        let replacedRetained = pool.residentByteCost == 1536
            && replaced?.texture !== first?.texture
        first?.pin.release()
        let firstPinReleaseKeepsOther = pool.residentByteCost == 1536
        repeated?.pin.release()
        let lastOldPinReleaseDropsRetired = pool.residentByteCost == 1024
        let oldGeneration = replaced?.pin.generation
        pool.reset()
        let resetRetainsPins = pool.residentByteCost == 1024
        let resized = pool.compositionGroupTarget(layerID: 101, width: 8, height: 16,
            commandBuffer: queue.makeCommandBuffer()!)
        let resizeDistinct = resized?.texture !== replaced?.texture
            && resized?.pin.generation != oldGeneration && pool.residentByteCost == 1536
        other?.pin.release(); replaced?.pin.release()
        let releasedOldGeneration = pool.residentByteCost == 512
        resized?.pin.release()
        let reused = pool.compositionGroupTarget(layerID: 101, width: 8, height: 16,
            commandBuffer: queue.makeCommandBuffer()!)
        let idleReuse = reused?.texture === resized?.texture
        reused?.pin.release()
        let exactRefusal = pool.compositionGroupTarget(layerID: 101, width: 65, height: 8,
            commandBuffer: command) == nil && pool.residentByteCost == 512
        let limited = SceneOffscreenTexturePool(device: device, maxDimension: 64,
            residentByteBudget: 512)
        let held = limited.compositionGroupTarget(layerID: 1, width: 16, height: 8,
            commandBuffer: command)
        let pressureRejected = limited.compositionGroupTarget(layerID: 1, width: 16, height: 8,
            commandBuffer: nextCommand) == nil && limited.residentByteCost == 512
        held?.pin.release()
        let afterCancel = limited.compositionGroupTarget(layerID: 1, width: 16, height: 8,
            commandBuffer: nextCommand)
        let cancellationRecovers = afterCancel != nil && afterCancel?.texture === held?.texture
        afterCancel?.pin.release()
        let runtimePool = SceneOffscreenTexturePool(device: device, maxDimension: 64,
            residentByteBudget: 512)
        let runtimeCommand = queue.makeCommandBuffer()!
        let mainTexture = device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 16, height: 8, mipmapped: false))!
        let parent = SceneMainPassEncoder(commandBuffer: runtimeCommand, target: mainTexture,
            clearColor: MTLClearColor(), clearEnabled: true)
        func makeRuntime(_ roots: [Int], _ members: [Int: Int]) -> SceneCompositionGroupFrameRuntime {
            let runtime = SceneCompositionGroupFrameRuntime(parentPass: parent,
                commandBuffer: runtimeCommand, offscreenTexturePool: runtimePool,
                memberRootsByLayerID: members,
                membersByRootID: Dictionary(uniqueKeysWithValues: roots.map { ($0, []) }),
                viewportSize: CGSize(width: 16, height: 8))
            runtime.reserveSources(orderedRootIDs: roots, visibleLayerIDs: Set(roots))
            return runtime
        }
        let runtime = makeRuntime([900, 100], [901: 900, 101: 100])
        let selected = runtime.preparedSource(forLayerID: 900, mainTarget: mainTexture)
        let sameSource = selected != nil && selected !== mainTexture
            && runtime.preparedSource(forLayerID: 901, mainTarget: mainTexture) === selected
        let orderedPressure = runtime.preparedSource(forLayerID: 100, mainTarget: mainTexture) == nil
            && !runtime.sourceIsAvailable(forLayerID: 101)
            && runtime.preparedSource(forLayerID: 99, mainTarget: mainTexture) === mainTexture
        runtimePool.reset()
        let resetBeforeCancel = runtimePool.residentByteCost == 512
            && runtime.groupTexture(forRootID: 900) == nil
        runtime.cancel()
        let cancelReleases = runtimePool.residentByteCost == 0
        let renamed = makeRuntime([100, 900], [101: 100, 901: 900])
        let renamedOrder = renamed.preparedSource(forLayerID: 100, mainTarget: mainTexture) != nil
            && renamed.preparedSource(forLayerID: 900, mainTarget: mainTexture) == nil
        renamed.cancel(); runtimePool.reset()
        let result: [String: Any] = [
            "metalUnavailable": false,
            "coldAllocated": first != nil,
            "exactExtent": first.map { [$0.texture.width, $0.texture.height] } ?? [],
            "sameRootReused": first != nil && first?.texture === repeated?.texture,
            "differentRootsIsolated": first != nil && other != nil
                && first?.texture !== other?.texture,
            "residentBytes": coldBytes,
            "runtime": [sameSource, orderedPressure, resetBeforeCancel, cancelReleases, renamedOrder],
            "lifetime": [replacedRetained, firstPinReleaseKeepsOther,
                lastOldPinReleaseDropsRetired, resetRetainsPins, resizeDistinct,
                releasedOldGeneration, idleReuse, exactRefusal, pressureRejected,
                cancellationRecovers],
        ]
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys]
        ), as: UTF8.self))
    }
}
'''


class SceneCompositionSourceIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-composition-source-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "probe"
        cls.binary = binary
        compiled = subprocess.run(
            ["xcrun", "--sdk", "macosx", "swiftc",
             "-D", "SCENE_ACTUAL_COMPOSITION_TARGETS", *(str(p) for p in SWIFT_SOURCES), str(harness),
             "-framework", "Metal", "-module-cache-path", str(root / "module-cache"),
             "-o", str(binary)],
            capture_output=True, text=True,
        )
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_cold_group_source_is_exact_and_root_isolated(self) -> None:
        self.assertTrue(self.result["coldAllocated"], self.result)
        self.assertEqual(self.result["exactExtent"], [16, 8])
        self.assertTrue(self.result["sameRootReused"])
        self.assertTrue(self.result["differentRootsIsolated"])
        self.assertEqual(self.result["residentBytes"], 1024)
        self.assertEqual(self.result["lifetime"], [True] * 10)
        self.assertEqual(self.result["runtime"], [True] * 5)

    def test_submitted_source_pins_and_empty_gpu_clear(self) -> None:
        import os
        if not os.environ.get("MWX_SCENE_INTEGRATION_APP"):
            self.skipTest("explicit GPU integration run required")
        completed = subprocess.run([str(self.binary), "--gpu"], capture_output=True, text=True, timeout=20)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
            path = Path(destination); path.mkdir(parents=True, exist_ok=True)
            (path / "actual-runtime-gpu.json").write_text(json.dumps(result, indent=2))
        self.assertEqual(result, {"reusedOldRedSource": True, "emptySourceTransparent": True,
            "heldUntilCompletion": True, "releasedAfterCompletion": True, "completed": True})


class SceneCompositionSourceIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import os
        executable = os.environ.get("MWX_SCENE_INTEGRATION_APP")
        if not executable:
            raise unittest.SkipTest("requires frozen Debug App executable")
        cls.app = Path(executable).resolve(strict=True)

    def run_source(self, *, grouped=True, enabled=True, background="0 0 1",
                   child_effect=False, nested=False, empty=False, resize=False, fault=None,
                   capture_main=False, childless_position=None):
        import hashlib
        import os
        import re
        from script.web_benchmark_capture import png_rgb_pixels
        from script.tests.test_scene_pkg_cache_extractor import make_package
        scene = {"version": 3, "general": {"orthogonalprojection": {"width": 160, "height": 96}, "clearcolor": "0 0 1"}, "objects": [
            {"id": 1, "name": "Blue main", "image": "models/util/solidlayer.json", "origin": "80 48 0", "size": "160 96", "color": background},
            {"id": 20, "name": "Selected source", "copybackground": False, "image": "models/util/composelayer.json", "origin": "0 0 0", "size": "160 96", "effects": [{"id": 200, "file": "effects/own_dim/effect.json", "visible": enabled}]},
            {"id": 21, "parent": 20, "name": "Red source", "image": "models/util/solidlayer.json", "origin": "80 48 0", "size": "32 32", "color": "1 0 0"},
            {"id": 99, "name": "Healthy green peer", "image": "models/util/solidlayer.json", "origin": "140 80 0", "size": "12 12", "color": "0 1 0"}
        ]}
        project = {"type":"scene","file":"scene.json"}
        if empty:
            scene["objects"][2]["visible"] = {"script":"export function update(v) { return engine.runtime < 2.5; }", "value": True}
        if child_effect:
            scene["objects"][2]["effects"] = [{"id": 210, "file":"effects/own_dim/effect.json", "visible":True}]
        if nested:
            scene["objects"][2]["parent"] = 30
            scene["objects"].insert(2, {"id":30,"parent":20,"name":"Inner selected source","copybackground":False,"image":"models/util/composelayer.json","origin":"0 0 0","size":"160 96","effects":[{"id":300,"file":"effects/own_dim/effect.json","visible":True}]})
        if childless_position:
            utility = {"id":30,"parent":20,"name":"Childless capture","image":"models/util/composelayer.json","origin":"80 48 0","size":"160 96","effects":[{"id":300,"file":"effects/own_dim/effect.json","visible":True}]}
            scene["objects"].insert(2 if childless_position == "first" else 3, utility)
            if childless_position == "middle":
                scene["objects"].insert(4, {"id":31,"parent":20,"name":"Later member","image":"models/util/solidlayer.json","origin":"40 48 0","size":"4 4","color":"1 0 0"})
        if not grouped:
            scene["objects"].pop(1)
            scene["objects"][1].pop("parent")
            scene["objects"][1]["effects"] = [{"id": 210, "file": "effects/own_dim/effect.json", "visible": enabled}]
        if capture_main:
            scene["objects"][0]["color"] = "1 0 0"
            scene["objects"][1]["origin"] = "80 48 0"
            scene["objects"][1]["copybackground"] = True
            scene["objects"].pop(2)
        entries = {
            "scene.json": json.dumps(scene).encode(),
            "effects/own_dim/effect.json": json.dumps({"passes": [{"material": "materials/own_dim.json"}]}).encode(),
            "materials/own_dim.json": json.dumps({"passes": [{"shader": "own_dim", "textures": [None], "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled", "cullmode": "nocull"}]}).encode(),
            "shaders/own_dim.vert": b"attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n",
            "shaders/own_dim.frag": b"uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=vec3(0.5,1.0,1.0);gl_FragColor=c;}\n",
        }
        with tempfile.TemporaryDirectory(prefix="mwx-composition-app-") as temporary:
            root=Path(temporary); content=root/"content"; content.mkdir(); home=root/"home"; home.mkdir()
            (content/"project.json").write_text(json.dumps(project))
            (content/"scene.pkg").write_bytes(make_package(list(entries.items())))
            evidence=root/"evidence"
            env=os.environ.copy();env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), MWX_SCENE_DEBUG_SURFACE_COUNT="1")
            command=[str(self.app),"--mwx-debug-scene-root",str(content),"--mwx-debug-scene-duration","6","--mwx-debug-scene-evidence-dir",str(evidence)]
            if resize:
                command += ["--mwx-debug-scene-resize-sequence", "1:0.7,3:0.9",
                            "--mwx-debug-scene-after-snapshot-delay", "5"]
            env.update(fault or {})
            result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=70)
            log=result.stdout+result.stderr
            pixels={}
            for capture in sorted(evidence.glob("*-window.png")):
                width,height,rows=png_rgb_pixels(capture)
                red=green=0
                for row in rows[::4]:
                    for x in range(0,width,4):
                        r,g,b=row[x*3:x*3+3]
                        red += r>20 and g<10 and b<10
                        green += r<10 and g>245 and b<10
                pixels[capture.name]={"center":list(rows[height//2][width//2*3:width//2*3+3]),
                    "outside":list(rows[height//2][width//8*3:width//8*3+3]),
                    "redROI":red,"greenPeer":green,"size":[width,height]}
            if destination:=os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved=Path(destination)/self._testMethodName;saved.mkdir(parents=True,exist_ok=True)
                shutil.copytree(content,saved/"content",dirs_exist_ok=True)
                if evidence.exists():shutil.copytree(evidence,saved/"evidence",dirs_exist_ok=True)
                (saved/"app.log").write_text(log)
                (saved/"pixels.json").write_text(json.dumps(pixels,indent=2))
                (saved/"identity.json").write_text(json.dumps({"command":command,"returncode":result.returncode,"inputs":{n:hashlib.sha256(v).hexdigest() for n,v in entries.items()},"app":{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [self.app,self.app.with_name("MyWallpaperX.debug.dylib")] if p.exists()}},indent=2))
            self.assertEqual(result.returncode,0,log[-4000:])
            self.assertIn("gpuDrained=true",log)
            self.assertRegex(log,r"state=completed frame=[1-9]\d* surface=\d+ gpu=completed")
            self.assertGreaterEqual(len(pixels),2,log[-4000:])
            if empty:
                self.assertRegex(log, r"layer=21 source=sceneScript value=false effective=false")
            if resize:
                self.assertIn("phase=surface-resize index=1 scale=0.9000 accepted=true", log)
                self.assertGreater(len({tuple(p["size"]) for p in pixels.values()}), 1)
            if fault:
                self.assertRegex(log, r"state=cancelled frame=\d+ surface=\d+ submitted=false")
            for name,pixel in pixels.items():
                with self.subTest(capture=name):
                    main_color = [round(float(v)*255) for v in background.split()]
                    self.assertEqual(pixel["outside"], [128, 0, 0] if capture_main else main_color, pixel)
                    self.assertGreater(pixel["greenPeer"], 20, pixel)
                    if empty and "after" in name:
                        self.assertEqual(pixel["center"],main_color,pixel)
                        self.assertEqual(pixel["redROI"],0,pixel)
                    else:
                        r,g,b=pixel["center"]
                        expected = round(255 * 0.5 ** ((1 if enabled else 0) + int(child_effect) + int(nested) + int(childless_position in {"middle", "last"})))
                        self.assertLess(g,10,pixel);self.assertLess(b,10,pixel)
                        self.assertLessEqual(abs(r-expected),2,pixel)
                        self.assertGreater(pixel["redROI"],100,pixel)
            return log,pixels

    def test_childless_capture_between_members_stays_in_group(self):
        self.run_source(childless_position="middle")

    def test_childless_capture_last_member_precedes_root(self):
        self.run_source(childless_position="last")

    def test_childless_first_capture_clears_before_sampling(self):
        self.run_source(childless_position="first", empty=True)

    def test_nonidentity_image_positive_control(self):
        self.run_source(grouped=False)

    def test_ordinary_captured_main_applies_nonidentity_filter(self):
        self.run_source(capture_main=True)

    def test_group_graph_reads_selected_red_source(self):
        self.run_source()

    def test_group_source_ignores_main_color_change(self):
        self.run_source(background="1 1 0")

    def test_effect_disabled_positive_control(self):
        self.run_source(enabled=False)

    def test_effectful_member_precedes_root_graph(self):
        self.run_source(child_effect=True)

    def test_nested_effectful_sources_consume_inner_first(self):
        self.run_source(child_effect=True,nested=True)

    def test_empty_next_frame_clears_old_source(self):
        self.run_source(empty=True)

    def test_resize_keeps_current_non_square_source(self):
        self.run_source(resize=True)

    def test_cancelled_prepared_frame_recovers_current_source(self):
        self.run_source(fault={"MWX_SCENE_DEBUG_REJECT_PREPARED_FRAME_ONCE":"1"})


if __name__ == "__main__":
    unittest.main()
