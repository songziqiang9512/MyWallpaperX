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
func cursorWorldFrames(_ marker:Float) -> [Int:simd_float4x4] {
    var frame = matrix_identity_float4x4
    frame.columns.3.x = marker
    return [1:frame]
}
func cursorAttachmentFrames(_ marker:Float) -> ScenePuppetAttachmentFrameSnapshot {
    .init(framesByParentLayerID:[7:["camera":cursorWorldFrames(marker)[1]!]])
}
final class SceneMetalView {
    let identity:UInt32
    init(_ identity:UInt32 = 10) { self.identity = identity }
    var worldResolveCount = 0
    var frameMarker: Float = 31
    var consumedFrameMarkers: [Float] = []
    var surfaceInputFrameMarkers: [Float] = []
    var resolvedAttachmentMarkers: [Float] = []
    var requiresSceneScriptCameraWorldFrames = false
    func sceneScriptCursorWorldFrames(dynamicValues:SceneDynamicSnapshot,
        puppetAttachmentFrames:ScenePuppetAttachmentFrameSnapshot) -> [Int:simd_float4x4] {
        worldResolveCount += 1
        let attachmentMarker = puppetAttachmentFrames.frame(parentLayerID:7,attachmentName:"camera")?.columns.3.x
        resolvedAttachmentMarkers.append(attachmentMarker ?? -1)
        return cursorWorldFrames(attachmentMarker ?? frameMarker)
    }
    var pointerState = SceneSurfacePointerState()
    var events = SceneSurfacePointerEventBuffer()
    func drainSceneScriptPointerEvents() -> SceneSurfacePointerEventBatch { events.drain() }
    func sceneScriptSurfaceInput(pointer:SceneSurfacePointerEvent,timing:SceneFrameTiming,
        dynamicValues:SceneDynamicSnapshot,worldFrames:[Int:simd_float4x4]) -> SceneScriptSurfaceInput? {
        let marker = worldFrames[1]?.columns.3.x ?? -1
        surfaceInputFrameMarkers.append(marker)
        return .init(canvasSize:.init(100,100),screenSize:.init(Double(identity),100),
            cursorWorldPosition:.init(Double(pointer.normalizedPosition.x),Double(marker),0),
            cursorScreenPosition:.init(Double(pointer.normalizedPosition.x),0),cursorLeftDown:pointer.primaryButtonIsDown)
    }
    func sceneScriptCursorFrameSample(pointer:SceneSurfacePointerEvent,surfaceID:UInt32,leavingSurface:SceneScriptSurfaceInput?,
        ownerLayerIDs:Set<Int>,capturedOwnerLayerIDs:Set<Int>,timing:SceneFrameTiming,
        dynamicValues:SceneDynamicSnapshot,worldFrames:[Int:simd_float4x4]
    ) -> SceneScriptCursorFrameSample {
        consumedFrameMarkers.append(worldFrames[1]?.columns.3.x ?? -1)
        let hit = SceneScriptCursorHit(layerID:1,worldPosition:.init(Double(pointer.normalizedPosition.x),0,0),localPosition:.init(Double(pointer.normalizedPosition.x),0,0))
        let projectedOwners = pointer.isInside ? ownerLayerIDs : capturedOwnerLayerIDs
        let projections = projectedOwners.contains(1) ? [1:hit] : [:]
        return .init(hits:pointer.isInside ? projections : [:],ownerProjections:projections,
            pointerPosition:pointer.normalizedPosition,primaryButtonIsDown:pointer.primaryButtonIsDown,
            surface:sceneScriptSurfaceInput(pointer:pointer,timing:timing,
                dynamicValues:dynamicValues,worldFrames:worldFrames),surfaceID:surfaceID,leavingSurface:leavingSurface)
    }
}
struct SceneDesktopWallpaperLaunchContext { let sceneScriptCursorProgram:SceneScriptCursorProgram }
final class SceneDesktopWallpaperSession {
    struct Surface { let metalView:SceneMetalView }
    var surfaces:[UInt32:Surface] = [20:.init(metalView:.init(20)),10:.init(metalView:.init())]
    func feed(_ time:Double,_ down:Bool,inside:UInt32) {
        for (id,surface) in surfaces {
            let x:Float = id == inside ? 0.2 : 2
            _ = surface.metalView.pointerState.apply(.init(current:.init(x,0),isInside:id == inside,isPrimaryButtonDown:down))
            surface.metalView.events.append(.init(normalizedPosition:.init(x,0),isInside:id == inside,primaryButtonIsDown:down,timestamp:time))
        }
    }
    func prepare(_ program:SceneScriptCursorProgram,failed:Bool=false,
        puppetAttachmentFramesBySurface:[UInt32:ScenePuppetAttachmentFrameSnapshot]=[:]) -> SceneScriptCursorFrameBatch {
        var worldFramesBySurface: [UInt32:[Int:simd_float4x4]] = [:]
        return prepare(program,failed:failed,puppetAttachmentFramesBySurface:puppetAttachmentFramesBySurface,
            worldFramesBySurface:&worldFramesBySurface)
    }
    func prepare(_ program:SceneScriptCursorProgram,failed:Bool=false,
        puppetAttachmentFramesBySurface:[UInt32:ScenePuppetAttachmentFrameSnapshot]=[:],
        worldFramesBySurface:inout [UInt32:[Int:simd_float4x4]]) -> SceneScriptCursorFrameBatch {
        prepareSceneScriptCursorBatch(launchContext:.init(sceneScriptCursorProgram:program),
            timing:.init(wallDate:Date(timeIntervalSince1970:0),simulationFrameTime:0.016,sceneTime:1),
            preliminaryForSceneScript:.empty(frameIndex:0),puppetAttachmentFramesBySurface:puppetAttachmentFramesBySurface,
            worldFramesBySurface:&worldFramesBySurface,
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
        let denseHost = SceneDesktopWallpaperSession()
        let (dense,_) = try make([(.origin,script)])
        for i in 0..<64 { denseHost.feed(Double(i),i%2 == 0,inside:10) }
        let denseBatch = denseHost.prepare(dense)
        let denseView = denseHost.surfaces[10]!.metalView
        out["denseEvents"] = denseBatch.samples.count
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
        let entryHost = SceneDesktopWallpaperSession()
        entryHost.feed(1,false,inside:99);entryHost.feed(2,false,inside:10)
        _ = entryHost.prepare(dense)
        out["outsideThenEntryResolves"] = entryHost.surfaces[10]!.metalView.worldResolveCount
        out["outsideThenEntryFrames"] = entryHost.surfaces[10]!.metalView.consumedFrameMarkers
        let cameraHost = SceneDesktopWallpaperSession()
        let camera10 = cameraHost.surfaces[10]!.metalView
        let camera20 = cameraHost.surfaces[20]!.metalView
        camera10.requiresSceneScriptCameraWorldFrames = true
        camera20.requiresSceneScriptCameraWorldFrames = true
        camera10.frameMarker = 71;camera20.frameMarker = 83
        cameraHost.feed(5000,false,inside:10)
        _ = dispatch(noOwners,cameraHost.prepare(noOwners).samples)
        noOwners.finalizeLayerMutations(committing:true)
        camera10.frameMarker = 97;camera20.frameMarker = 113
        camera10.surfaceInputFrameMarkers = []
        cameraHost.feed(5001,true,inside:20);cameraHost.feed(5002,false,inside:20)
        let cameraFailed = cameraHost.prepare(noOwners,failed:true)
        out["cameraFailedResolveCounts"] = [camera10.worldResolveCount,camera20.worldResolveCount]
        out["cameraFailedHasNoSamples"] = cameraFailed.samples.isEmpty
        let cameraBatch = cameraHost.prepare(noOwners)
        out["cameraNoOwnerSurfaces"] = cameraBatch.samples.compactMap(\.surfaceID)
        out["cameraNoOwnerWorldMarkers"] = cameraBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        out["cameraLeavingWorldMarkers"] = cameraBatch.samples.compactMap { $0.leavingSurface?.cursorWorldPosition.y }
        out["cameraNoOwnerResolveCounts"] = [camera10.worldResolveCount,camera20.worldResolveCount]
        out["cameraLeavingInputMarkers"] = camera10.surfaceInputFrameMarkers
        out["cameraActiveInputMarkers"] = camera20.surfaceInputFrameMarkers
        let attachmentHost = SceneDesktopWallpaperSession()
        let (attachmentProgram,_) = try make([])
        let attachment10 = attachmentHost.surfaces[10]!.metalView
        let attachment20 = attachmentHost.surfaces[20]!.metalView
        attachment10.requiresSceneScriptCameraWorldFrames = true
        attachment20.requiresSceneScriptCameraWorldFrames = true
        attachmentHost.feed(9000,false,inside:10)
        let initialAttachmentBatch = attachmentHost.prepare(attachmentProgram,
            puppetAttachmentFramesBySurface:[10:cursorAttachmentFrames(211),20:cursorAttachmentFrames(239)])
        _ = dispatch(attachmentProgram,initialAttachmentBatch.samples)
        attachmentProgram.finalizeLayerMutations(committing:true)
        attachmentHost.feed(9001,true,inside:20);attachmentHost.feed(9002,false,inside:20)
        let attachmentBatch = attachmentHost.prepare(attachmentProgram,
            puppetAttachmentFramesBySurface:[10:cursorAttachmentFrames(251),20:cursorAttachmentFrames(277)])
        out["surface10AttachmentMarkers"] = attachment10.resolvedAttachmentMarkers
        out["surface20AttachmentMarkers"] = attachment20.resolvedAttachmentMarkers
        out["attachmentActiveWorldMarkers"] = attachmentBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        out["attachmentLeavingWorldMarkers"] = attachmentBatch.samples.compactMap { $0.leavingSurface?.cursorWorldPosition.y }
        out["attachmentResolveCounts"] = [attachment10.worldResolveCount,attachment20.worldResolveCount]
        let seededHost = SceneDesktopWallpaperSession()
        let (seedProgram,_) = try make([])
        let seeded10 = seededHost.surfaces[10]!.metalView
        let seeded20 = seededHost.surfaces[20]!.metalView
        seeded10.requiresSceneScriptCameraWorldFrames = true
        seeded20.requiresSceneScriptCameraWorldFrames = true
        var phaseWorlds: [UInt32:[Int:simd_float4x4]] = [10:cursorWorldFrames(151),20:cursorWorldFrames(179)]
        seededHost.feed(6000,true,inside:10);seededHost.feed(6001,false,inside:20)
        let seededBatch = seededHost.prepare(seedProgram,worldFramesBySurface:&phaseWorlds)
        out["seededWorldMarkers"] = seededBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        out["seededLeavingWorldMarkers"] = seededBatch.samples.compactMap { $0.leavingSurface?.cursorWorldPosition.y }
        seeded10.frameMarker = 171;seeded20.frameMarker = 189
        let samePhaseBatch = seededHost.prepare(seedProgram,worldFramesBySurface:&phaseWorlds)
        out["samePhaseWorldMarkers"] = samePhaseBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        out["seededResolveCounts"] = [seeded10.worldResolveCount,seeded20.worldResolveCount]
        seededHost.feed(6002,true,inside:10);seededHost.feed(6003,false,inside:20)
        let refreshedBatch = seededHost.prepare(seedProgram)
        out["refreshedWorldMarkers"] = refreshedBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        out["refreshedLeavingWorldMarkers"] = refreshedBatch.samples.compactMap { $0.leavingSurface?.cursorWorldPosition.y }
        out["refreshedResolveCounts"] = [seeded10.worldResolveCount,seeded20.worldResolveCount]
        let emptySeedHost = SceneDesktopWallpaperSession()
        emptySeedHost.surfaces.removeValue(forKey:20)
        emptySeedHost.surfaces[10]!.metalView.requiresSceneScriptCameraWorldFrames = true
        var emptySeed: [UInt32:[Int:simd_float4x4]] = [10:[:]]
        emptySeedHost.feed(7000,true,inside:10);emptySeedHost.feed(7001,false,inside:10)
        let emptySeedBatch = emptySeedHost.prepare(seedProgram,worldFramesBySurface:&emptySeed)
        out["emptySeedResolveCount"] = emptySeedHost.surfaces[10]!.metalView.worldResolveCount
        out["emptySeedWorldMarkers"] = emptySeedBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        let noOwner2DHost = SceneDesktopWallpaperSession()
        noOwner2DHost.feed(8000,false,inside:10);noOwner2DHost.feed(8001,false,inside:20)
        let noOwner2DBatch = noOwner2DHost.prepare(seedProgram)
        out["noOwner2DResolveCounts"] = noOwner2DHost.surfaces.keys.sorted().map { noOwner2DHost.surfaces[$0]!.metalView.worldResolveCount }
        out["noOwner2DWorldMarkers"] = noOwner2DBatch.samples.compactMap { $0.surface?.cursorWorldPosition.y }
        let host = SceneDesktopWallpaperSession()
        let (multi,_) = try make([(.origin,script)])
        host.feed(1,true,inside:10);host.feed(2,false,inside:10)
        let firstBatch = host.prepare(multi)
        out["multiRapid"] = values(dispatch(multi,firstBatch.samples))
        out["multiRapidSurfaces"] = firstBatch.samples.compactMap(\.surfaceID)
        multi.finalizeLayerMutations(committing:true)
        host.feed(3,true,inside:20);host.feed(4,false,inside:20)
        out["secondSurface"] = values(dispatch(multi,host.prepare(multi).samples))
        multi.finalizeLayerMutations(committing:true)
        let (drag,_) = try make([(.origin,script)])
        host.feed(5,true,inside:10)
        _ = dispatch(drag,host.prepare(drag).samples);drag.finalizeLayerMutations(committing:true)
        out["capturedSurface"] = drag.edgeStateSnapshot().capturedSurfaceID ?? 0
        host.feed(6,true,inside:20);host.feed(7,false,inside:20)
        let cross = host.prepare(drag)
        out["crossSurfaces"] = cross.samples.compactMap(\.surfaceID)
        out["crossPositions"] = cross.samples.map { Double($0.pointerPosition!.x) }
        out["crossDrag"] = values(dispatch(drag,cross.samples))
        drag.finalizeLayerMutations(committing:true)
        out["captureReleased"] = drag.edgeStateSnapshot().capturedSurfaceID == nil
        host.feed(8,true,inside:10);host.feed(9,false,inside:10)
        let consumed = host.prepare(multi)
        out["consumedClick"] = values(dispatch(multi,consumed.samples))
        multi.finalizeLayerMutations(committing:true)
        let next = host.prepare(multi)
        out["nextBatchHasNoHistoricalEdges"] = next.samples.count == 1
        _ = dispatch(multi,next.samples)
        multi.finalizeLayerMutations(committing:true)
        host.feed(9.5,true,inside:10);host.feed(9.6,false,inside:10)
        out["nextClickNotReplayed"] = values(dispatch(multi,host.prepare(multi).samples))
        multi.finalizeLayerMutations(committing:true)
        let (overflow,_) = try make([(.origin,script)])
        for i in 0...512 { host.surfaces[10]!.metalView.events.append(.init(normalizedPosition:.zero,isInside:true,primaryButtonIsDown:i%2 == 0,timestamp:Double(i+10))) }
        let lost = host.prepare(overflow)
        out["overflowRejected"] = lost.overflowed
        out["overflowQuiet"] = dispatch(overflow,lost.samples,overflow:lost.overflowed).ownerEffects.isEmpty
        overflow.finalizeLayerMutations(committing:true)
        host.feed(1000,true,inside:20);host.feed(1001,false,inside:20)
        let deferred = host.prepare(overflow,failed:true)
        out["snapshotFailureKeepsQueue"] = deferred.samples.isEmpty && host.prepare(overflow).samples.count == 2
        let singleHost = SceneDesktopWallpaperSession()
        singleHost.surfaces.removeValue(forKey:20)
        let (single,_) = try make([(.origin,script)])
        singleHost.feed(2000,true,inside:10);singleHost.feed(2001,false,inside:10)
        let singleBatch = singleHost.prepare(single)
        out["singleRapid"] = values(dispatch(single,singleBatch.samples))
        out["singleSamples"] = singleBatch.samples.count
        let (hover,_) = try make([(.origin,"""
          let enters=0,leaves=0;
          export function cursorEnter(e){thisLayer.origin=new Vec3(++enters,leaves,engine.screenResolution.x);}
          export function cursorLeave(e){thisLayer.origin=new Vec3(enters,++leaves,engine.screenResolution.x);}
        """)])
        host.feed(1002,false,inside:10)
        _ = dispatch(hover,host.prepare(hover).samples);hover.finalizeLayerMutations(committing:true)
        host.feed(1003,false,inside:20)
        let beforeCrossing = hover.edgeStateSnapshot()
        let crossingBatch = host.prepare(hover)
        out["surfaceHoverEdges"] = values(dispatch(hover,crossingBatch.samples))
        hover.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        func contexts(_ program:SceneScriptCursorProgram) -> [[Double]] {
            program.edgeStateSnapshot().pendingEvents.map { [$0.surface!.screenSize.x,$0.surface!.cursorWorldPosition.x,$0.hit.worldPosition.x] }
        }
        out["crossingContexts"] = contexts(hover)
        hover.restoreEdgeState(beforeCrossing)
        _ = dispatch(hover,crossingBatch.samples)
        hover.finalizeLayerMutations(committing:true,rejectedOwnerTargets:[target()])
        out["retryContexts"] = contexts(hover)
        let (recreated,_) = try make([(.origin,script)])
        host.feed(3000,true,inside:10)
        _ = dispatch(recreated,host.prepare(recreated).samples);recreated.finalizeLayerMutations(committing:true)
        // The actual Host teardown now invokes this existing edge reset even
        // for clearContext:false. A new view may keep the same display ID.
        recreated.restoreEdgeState(.empty)
        host.surfaces[10] = .init(metalView:.init(10))
        host.feed(3001,false,inside:10)
        out["recreatedReleaseQuiet"] = dispatch(recreated,host.prepare(recreated).samples).ownerEffects.isEmpty
'''

class CursorSurfaceRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        product = '\n'.join((SCENE / p).read_text() for p in (
            'Runtime/Frame/SceneSurfacePointerState.swift',
            'Runtime/Session/SceneDesktopWallpaperSession+FrameDriverCursor.swift'))
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

    def test_native_camera_without_owners_resolves_active_and_leaving_surface_once(self):
        self.assertEqual(self.result['cameraFailedResolveCounts'],[1,0])
        self.assertTrue(self.result['cameraFailedHasNoSamples'])
        self.assertEqual(self.result['cameraNoOwnerSurfaces'],[20,20])
        self.assertEqual(self.result['cameraNoOwnerWorldMarkers'],[113,113])
        self.assertEqual(self.result['cameraLeavingWorldMarkers'],[97])
        self.assertEqual(self.result['cameraNoOwnerResolveCounts'],[2,1])
        self.assertEqual(self.result['cameraLeavingInputMarkers'],[97])
        self.assertEqual(self.result['cameraActiveInputMarkers'],[113,113])

    def test_preseeded_phase_worlds_are_reused_and_next_phase_refreshes(self):
        self.assertEqual(self.result['seededWorldMarkers'],[151,179])
        self.assertEqual(self.result['seededLeavingWorldMarkers'],[151])
        self.assertEqual(self.result['samePhaseWorldMarkers'],[179])
        self.assertEqual(self.result['seededResolveCounts'],[0,0])
        self.assertEqual(self.result['refreshedWorldMarkers'],[171,189])
        self.assertEqual(self.result['refreshedLeavingWorldMarkers'],[171])
        self.assertEqual(self.result['refreshedResolveCounts'],[1,1])
        self.assertEqual(self.result['emptySeedResolveCount'],0)
        self.assertEqual(self.result['emptySeedWorldMarkers'],[-1,-1])

    def test_active_and_leaving_surface_resolvers_receive_their_current_attachments(self):
        self.assertEqual(self.result['surface10AttachmentMarkers'],[211,251])
        self.assertEqual(self.result['surface20AttachmentMarkers'],[277])
        self.assertEqual(self.result['attachmentActiveWorldMarkers'],[277,277])
        self.assertEqual(self.result['attachmentLeavingWorldMarkers'],[251])
        self.assertEqual(self.result['attachmentResolveCounts'],[2,1])

    def test_2d_without_owners_does_not_resolve_active_or_leaving_surface(self):
        self.assertEqual(self.result['noOwner2DResolveCounts'],[0,0])
        self.assertEqual(self.result['noOwner2DWorldMarkers'],[-1,-1])

    def test_single_surface_uses_same_click_route_without_duplicate_final_sample(self):
        self.assertEqual(self.result['singleRapid'],[1,1,1])
        self.assertEqual(self.result['singleSamples'],2)

    def test_drag_keeps_press_surface_until_release_without_clicking_other_surface(self):
        self.assertEqual(self.result['capturedSurface'],10)
        self.assertEqual(self.result['crossSurfaces'],[10,10,20])
        self.assertEqual(self.result['crossPositions'][:2],[2,2])
        self.assertEqual(self.result['crossDrag'],[1,1,0])
        self.assertTrue(self.result['captureReleased'])

    def test_presentation_retry_cannot_replay_physical_edges(self):
        self.assertTrue(self.result['nextBatchHasNoHistoricalEdges'])
        self.assertEqual(self.result['consumedClick'], [3,3,3])
        self.assertEqual(self.result['nextClickNotReplayed'], [4,4,4])

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
