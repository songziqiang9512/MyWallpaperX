"""Execute the common Host cursor queue with real Swift/QuickJS dispatch."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from .scene_vector_vm_test_support import compile_vector_harness, ROOT
from .test_scene_cursor_owner_transaction import HARNESS

SCENE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene'
SUPPORT = r'''
import AppKit
import simd
final class SceneMetalView {
    let identity:UInt32
    init(_ identity:UInt32 = 10) { self.identity = identity }
    var worldResolveCount = 0
    var frameMarker: Float = 31
    var consumedFrameMarkers: [Float] = []
    func sceneScriptCursorWorldFrames(dynamicValues:SceneDynamicSnapshot,
        puppetAttachmentFrames:ScenePuppetAttachmentFrameSnapshot) -> [Int:simd_float4x4] {
        worldResolveCount += 1
        var frame = matrix_identity_float4x4
        frame.columns.3.x = frameMarker
        return [1:frame]
    }
    var pointerState = SceneSurfacePointerState()
    var events = SceneSurfacePointerEventBuffer()
    func drainSceneScriptPointerEvents() -> SceneSurfacePointerEventBatch { events.drain() }
    func sceneScriptSurfaceInput(pointer:SceneSurfacePointerEvent,timing:SceneFrameTiming,dynamicValues:SceneDynamicSnapshot) -> SceneScriptSurfaceInput? {
        .init(canvasSize:.init(100,100),screenSize:.init(Double(identity),100),
            cursorWorldPosition:.init(Double(pointer.normalizedPosition.x),0,0),
            cursorScreenPosition:.init(Double(pointer.normalizedPosition.x),0),cursorLeftDown:pointer.primaryButtonIsDown)
    }
    func sceneScriptCursorFrameSample(pointer:SceneSurfacePointerEvent,surfaceID:UInt32,leavingSurface:SceneScriptSurfaceInput?,
        ownerLayerIDs:Set<Int>,capturedOwnerLayerIDs:Set<Int>,timing:SceneFrameTiming,
        dynamicValues:SceneDynamicSnapshot,worldFrames:[Int:simd_float4x4]
    ) -> SceneScriptCursorFrameSample {
        consumedFrameMarkers.append(worldFrames[1]?.columns.3.x ?? -1)
        let hit = SceneScriptCursorHit(layerID:1,worldPosition:.init(Double(pointer.normalizedPosition.x),0,0),localPosition:.init(Double(pointer.normalizedPosition.x),0,0))
        return .init(hits:pointer.isInside ? [1:hit] : [:],ownerProjections:[1:hit],
            pointerPosition:pointer.normalizedPosition,primaryButtonIsDown:pointer.primaryButtonIsDown,
            surface:.init(canvasSize:.init(100,100),screenSize:.init(Double(surfaceID),100),
                cursorWorldPosition:hit.worldPosition,cursorScreenPosition:.init(Double(pointer.normalizedPosition.x),0),cursorLeftDown:pointer.primaryButtonIsDown),surfaceID:surfaceID,leavingSurface:leavingSurface)
    }
}
struct SceneDesktopWallpaperLaunchContext { let sceneScriptCursorProgram:SceneScriptCursorProgram }
final class SceneDesktopWallpaperHost {
    struct Surface { let metalView:SceneMetalView }
    var surfaces:[UInt32:Surface] = [20:.init(metalView:.init(20)),10:.init(metalView:.init())]
    func feed(_ time:Double,_ down:Bool,inside:UInt32) {
        for (id,surface) in surfaces {
            let x:Float = id == inside ? 0.2 : 2
            _ = surface.metalView.pointerState.apply(.init(current:.init(x,0),isInside:id == inside,isPrimaryButtonDown:down))
            surface.metalView.events.append(.init(normalizedPosition:.init(x,0),isInside:id == inside,primaryButtonIsDown:down,timestamp:time))
        }
    }
    func prepare(_ program:SceneScriptCursorProgram,failed:Bool=false) -> SceneScriptCursorBatchPreparation {
        prepareSceneScriptCursorBatch(launchContext:.init(sceneScriptCursorProgram:program),
            timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1),
            preliminaryForSceneScript:.empty(frameIndex:0),puppetAttachmentFrames:.empty,
            layerSnapshotFailure:failed ? .invalidArgument("test") : nil)
    }
}
'''
CHECKS = r'''
        let script = """
          let down=0,up=0,click=0;
          function publish(){thisLayer.origin=new Vec3(down,up,click);}
          export function cursorDown(e){down++;publish();}
          export function cursorUp(e){up++;publish();}
          export function cursorClick(e){click++;publish();}
        """
        let denseHost = SceneDesktopWallpaperHost()
        let (dense,_) = try make([(.origin,script)])
        for i in 0..<64 { denseHost.feed(Double(i),i%2 == 0,inside:10) }
        let denseBatch = denseHost.prepare(dense)
        let denseView = denseHost.surfaces[10]!.metalView
        out["denseEvents"] = denseBatch.batch.samples.count
        out["denseResolves"] = denseView.worldResolveCount
        out["denseFrameMarkers"] = denseView.consumedFrameMarkers
        out["unusedSurfaceResolves"] = denseHost.surfaces[20]!.metalView.worldResolveCount
        denseView.frameMarker = 47
        denseView.consumedFrameMarkers = []
        denseHost.feed(100,true,inside:10);denseHost.feed(101,false,inside:10)
        _ = denseHost.prepare(dense)
        out["nextBatchResolves"] = denseView.worldResolveCount
        out["nextFrameMarkers"] = denseView.consumedFrameMarkers
        _ = denseHost.prepare(dense,failed:true)
        out["failedSnapshotResolves"] = denseView.worldResolveCount
        let (noOwners,_) = try make([])
        _ = denseHost.prepare(noOwners)
        out["noOwnerResolves"] = denseView.worldResolveCount
        denseHost.feed(102,false,inside:99)
        _ = denseHost.prepare(dense)
        out["outsideIdleResolves"] = denseView.worldResolveCount
        let entryHost = SceneDesktopWallpaperHost()
        entryHost.feed(1,false,inside:99);entryHost.feed(2,false,inside:10)
        _ = entryHost.prepare(dense)
        out["outsideThenEntryResolves"] = entryHost.surfaces[10]!.metalView.worldResolveCount
        out["outsideThenEntryFrames"] = entryHost.surfaces[10]!.metalView.consumedFrameMarkers
        let host = SceneDesktopWallpaperHost()
        let (multi,_) = try make([(.origin,script)])
        host.feed(1,true,inside:10);host.feed(2,false,inside:10)
        let firstBatch = host.prepare(multi)
        out["multiRapid"] = values(dispatch(multi,firstBatch.batch.samples))
        out["multiRapidSurfaces"] = firstBatch.batch.samples.compactMap(\.surfaceID)
        multi.finalizeLayerMutations(committing:true)
        host.feed(3,true,inside:20);host.feed(4,false,inside:20)
        out["secondSurface"] = values(dispatch(multi,host.prepare(multi).batch.samples))
        multi.finalizeLayerMutations(committing:true)
        let (drag,_) = try make([(.origin,script)])
        host.feed(5,true,inside:10)
        _ = dispatch(drag,host.prepare(drag).batch.samples);drag.finalizeLayerMutations(committing:true)
        out["capturedSurface"] = drag.edgeStateSnapshot().capturedSurfaceID ?? 0
        host.feed(6,true,inside:20);host.feed(7,false,inside:20)
        let cross = host.prepare(drag)
        out["crossSurfaces"] = cross.batch.samples.compactMap(\.surfaceID)
        out["crossPositions"] = cross.batch.samples.map { Double($0.pointerPosition!.x) }
        out["crossDrag"] = values(dispatch(drag,cross.batch.samples))
        drag.finalizeLayerMutations(committing:true)
        out["captureReleased"] = drag.edgeStateSnapshot().capturedSurfaceID == nil
        let savedSurface = multi.edgeStateSnapshot()
        host.feed(8,true,inside:10);host.feed(9,false,inside:10)
        let rejected = host.prepare(multi)
        _ = dispatch(multi,rejected.batch.samples)
        multi.finalizeLayerMutations(committing:false);multi.restoreEdgeState(savedSurface)
        for (id,batch) in rejected.drainedPointerBatches { host.surfaces[id]!.metalView.events.restore(batch) }
        out["retrySameBatch"] = host.prepare(multi).batch == rejected.batch
        out["retrySameSurfaceState"] = multi.edgeStateSnapshot().previousSurfaceID == savedSurface.previousSurfaceID
        let (overflow,_) = try make([(.origin,script)])
        for i in 0...512 { host.surfaces[10]!.metalView.events.append(.init(normalizedPosition:.zero,isInside:true,primaryButtonIsDown:i%2 == 0,timestamp:Double(i+10))) }
        let lost = host.prepare(overflow)
        out["overflowRejected"] = lost.batch.overflowed
        out["overflowQuiet"] = dispatch(overflow,lost.batch.samples,overflow:lost.batch.overflowed).ownerEffects.isEmpty
        overflow.finalizeLayerMutations(committing:true)
        host.feed(1000,true,inside:20);host.feed(1001,false,inside:20)
        let deferred = host.prepare(overflow,failed:true)
        out["snapshotFailureKeepsQueue"] = deferred.drainedPointerBatches.isEmpty && deferred.batch.samples.isEmpty && host.prepare(overflow).batch.samples.count == 2
        let singleHost = SceneDesktopWallpaperHost()
        singleHost.surfaces.removeValue(forKey:20)
        let (single,_) = try make([(.origin,script)])
        singleHost.feed(2000,true,inside:10);singleHost.feed(2001,false,inside:10)
        let singleBatch = singleHost.prepare(single)
        out["singleRapid"] = values(dispatch(single,singleBatch.batch.samples))
        out["singleSamples"] = singleBatch.batch.samples.count
        let (hover,_) = try make([(.origin,"""
          let enters=0,leaves=0;
          export function cursorEnter(e){thisLayer.origin=new Vec3(++enters,leaves,engine.screenResolution.x);}
          export function cursorLeave(e){thisLayer.origin=new Vec3(enters,++leaves,engine.screenResolution.x);}
        """)])
        host.feed(1002,false,inside:10)
        _ = dispatch(hover,host.prepare(hover).batch.samples);hover.finalizeLayerMutations(committing:true)
        host.feed(1003,false,inside:20)
        let beforeCrossing = hover.edgeStateSnapshot()
        let crossingBatch = host.prepare(hover)
        out["surfaceHoverEdges"] = values(dispatch(hover,crossingBatch.batch.samples))
        hover.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        func contexts(_ program:SceneScriptCursorProgram) -> [[Double]] {
            program.edgeStateSnapshot().pendingEvents.map { [$0.surface!.screenSize.x,$0.surface!.cursorWorldPosition.x,$0.hit.worldPosition.x] }
        }
        out["crossingContexts"] = contexts(hover)
        hover.restoreEdgeState(beforeCrossing)
        _ = dispatch(hover,crossingBatch.batch.samples)
        hover.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["retryContexts"] = contexts(hover)
        let (recreated,_) = try make([(.origin,script)])
        host.feed(3000,true,inside:10)
        _ = dispatch(recreated,host.prepare(recreated).batch.samples);recreated.finalizeLayerMutations(committing:true)
        // The actual Host teardown now invokes this existing edge reset even
        // for clearContext:false. A new view may keep the same display ID.
        recreated.restoreEdgeState(.empty)
        host.surfaces[10] = .init(metalView:.init(10))
        host.feed(3001,false,inside:10)
        out["recreatedReleaseQuiet"] = dispatch(recreated,host.prepare(recreated).batch.samples).ownerEffects.isEmpty
'''

class CursorSurfaceRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        product = '\n'.join((SCENE / p).read_text() for p in (
            'Runtime/Frame/SceneSurfacePointerState.swift',
            'Runtime/Session/SceneDesktopWallpaperHost+FrameDriverCursor.swift'))
        helpers = HARNESS.split('    static func main() throws {')[0]
        source = SUPPORT + product + helpers + 'static func main() throws { var out:[String:Any] = [:]\n' + CHECKS + '\nprint(String(data:try JSONSerialization.data(withJSONObject:out),encoding:.utf8)!)\n}\n}'
        with tempfile.TemporaryDirectory(prefix='mwx-cursor-surfaces-') as tmp:
            binary = compile_vector_harness(Path(tmp), source, 'surfaces')
            result = subprocess.run([str(binary)],capture_output=True,text=True,timeout=45)
            if result.returncode: raise AssertionError(result.stdout+result.stderr)
            cls.result = json.loads(result.stdout)

    def test_dense_batch_resolves_only_consumed_surface_once(self):
        self.assertEqual(self.result['denseEvents'],64)
        self.assertEqual(self.result['denseResolves'],1)
        self.assertEqual(self.result['denseFrameMarkers'],[31]*64)
        self.assertEqual(self.result['unusedSurfaceResolves'],0)

    def test_next_batch_refreshes_frames_and_failed_or_empty_consumers_do_no_work(self):
        self.assertEqual(self.result['nextBatchResolves'],2)
        self.assertEqual(self.result['nextFrameMarkers'],[47,47])
        self.assertEqual(self.result['failedSnapshotResolves'],2)
        self.assertEqual(self.result['noOwnerResolves'],2)
        self.assertEqual(self.result['outsideIdleResolves'],2)
        self.assertEqual(self.result['outsideThenEntryResolves'],1)
        self.assertEqual(self.result['outsideThenEntryFrames'],[-1,31])

    def test_two_surfaces_keep_subframe_click_once_and_surface_order(self):
        self.assertEqual(self.result['multiRapid'],[1,1,1])
        self.assertEqual(self.result['multiRapidSurfaces'],[10,10])
        self.assertEqual(self.result['secondSurface'],[2,2,2])

    def test_single_surface_uses_same_click_route_without_duplicate_final_sample(self):
        self.assertEqual(self.result['singleRapid'],[1,1,1])
        self.assertEqual(self.result['singleSamples'],2)

    def test_drag_keeps_press_surface_until_release_without_clicking_other_surface(self):
        self.assertEqual(self.result['capturedSurface'],10)
        self.assertEqual(self.result['crossSurfaces'],[10,10,20])
        self.assertEqual(self.result['crossPositions'][:2],[2,2])
        self.assertEqual(self.result['crossDrag'],[1,1,0])
        self.assertTrue(self.result['captureReleased'])

    def test_frame_retry_restores_order_and_surface_identity(self):
        self.assertTrue(self.result['retrySameBatch'])
        self.assertTrue(self.result['retrySameSurfaceState'])

    def test_overflow_and_failed_snapshot_do_not_consume_partial_input(self):
        self.assertTrue(self.result['overflowRejected'])
        self.assertTrue(self.result['overflowQuiet'])
        self.assertTrue(self.result['snapshotFailureKeepsQueue'])

    def test_same_local_position_on_new_surface_produces_leave_and_enter(self):
        self.assertEqual(self.result['surfaceHoverEdges'],[2,1,20])

    def test_leave_and_enter_keep_their_own_surface_context_across_retry(self):
        for key in ('crossingContexts','retryContexts'):
            contexts = self.result[key]
            self.assertEqual(len(contexts),2)
            self.assertEqual(contexts[0][:2],[10,2])
            self.assertAlmostEqual(contexts[0][2],0.2,places=5)
            self.assertEqual(contexts[1][0],20)
            self.assertAlmostEqual(contexts[1][1],0.2,places=5)
            self.assertAlmostEqual(contexts[1][2],0.2,places=5)

    def test_same_display_replacement_after_teardown_cannot_inherit_capture(self):
        self.assertTrue(self.result['recreatedReleaseQuiet'])
