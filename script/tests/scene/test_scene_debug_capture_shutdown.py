#!/usr/bin/env python3
"""Exercise production Session reconciliation and shutdown owners."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROXY_HEADER = r'''
#import <Metal/Metal.h>
id<MTLCommandQueue> controlledRetirementQueue(id<MTLCommandQueue> queue, BOOL creationFailure);
BOOL waitForControlledStopBarrier(void);
void deliverControlledRetirementFailure(void);
'''
PROXY_SOURCE = r'''
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static id<MTLCommandBuffer> heldRetirement;
static MTLCommandBufferHandler heldHandler;
static dispatch_semaphore_t stopWaited;
@interface BufferProxy : NSProxy {
    id<MTLCommandBuffer> target;
    BOOL retirement;
}
- (id)initWithTarget:(id<MTLCommandBuffer>)value retirement:(BOOL)first;
@end
@implementation BufferProxy
- (id)initWithTarget:(id<MTLCommandBuffer>)value retirement:(BOOL)first { target=value; retirement=first; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject*)target methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:target]; }
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler {
    if (retirement) { heldHandler=[handler copy]; heldRetirement=(id<MTLCommandBuffer>)self; }
    else { [target addCompletedHandler:handler]; }
}
- (void)commit { if (!retirement) { [target commit]; } }
- (void)waitUntilCompleted { [target waitUntilCompleted]; dispatch_semaphore_signal(stopWaited); }
- (MTLCommandBufferStatus)status { return retirement ? MTLCommandBufferStatusError : target.status; }
- (NSError *)error { return retirement ? [NSError errorWithDomain:@"ControlledFixtureFailure" code:1 userInfo:nil] : target.error; }
@end
@interface QueueProxy : NSProxy { id<MTLCommandQueue> target; NSUInteger count; BOOL failCreation; }
- (id)initWithTarget:(id<MTLCommandQueue>)value failCreation:(BOOL)failure;
@end
@implementation QueueProxy
- (id)initWithTarget:(id<MTLCommandQueue>)value failCreation:(BOOL)failure { target=value; count=0; failCreation=failure; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [(NSObject*)target methodSignatureForSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:target]; }
- (id<MTLCommandBuffer>)commandBuffer {
    BOOL first=count++ == 0;
    if (first && failCreation) { return nil; }
    return (id<MTLCommandBuffer>)[[BufferProxy alloc] initWithTarget:[target commandBuffer] retirement:first];
}
@end
id<MTLCommandQueue> controlledRetirementQueue(id<MTLCommandQueue> queue, BOOL creationFailure) {
    stopWaited=dispatch_semaphore_create(0);
    return (id<MTLCommandQueue>)[[QueueProxy alloc] initWithTarget:queue failCreation:creationFailure];
}
BOOL waitForControlledStopBarrier(void) { return dispatch_semaphore_wait(stopWaited,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0; }
void deliverControlledRetirementFailure(void) {
    heldHandler(heldRetirement);
    heldHandler=nil;heldRetirement=nil;
}
'''
SESSION_SHUTDOWN_SUPPORT = r'''
import AppKit
@preconcurrency import Metal

struct SceneUserPropertyValue {}
struct SceneResolvedMaterialFrameTargetPlan {}

final class ControlledFontWorker: @unchecked Sendable {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let queue=DispatchQueue(label:"test.font-work")
    private let lock=NSLock()
    private var closeCalls=0,cancelCalls=0
    var closeCallCount:Int {lock.lock();defer {lock.unlock()};return closeCalls}
    var cancelCallCount:Int {lock.lock();defer {lock.unlock()};return cancelCalls}
    init(held:Bool=true) {queue.async { [self] in entered.signal();if held {release.wait()} }}
    func close() {lock.lock();closeCalls += 1;lock.unlock()}
    func enqueue(_ work:@escaping @Sendable ()->Void) {queue.async(execute:work)}
    func cancelDeferredPreparation() {}
    func closeAndDrain(completion:@escaping @Sendable ()->Void) {close();queue.async {completion()}}
    func cancelAndDrain(completion:@escaping @Sendable ()->Void) {
        lock.lock();cancelCalls += 1;lock.unlock();queue.async {completion()}
    }
    func cancelAndDrainDeferredPreparation(completion:@escaping @Sendable ()->Void) {closeAndDrain(completion:completion)}
}

enum SceneDesktopWallpaperHostLaunchError:Error {case cancelled,preparationFailed}
// SHARED_PREPARATION_LEAVES
// PRODUCTION_CANCELLATION

enum SceneGraphExecutionResetReason {case surfaceStop}
final class TestResettable {var cancellation:TestResettable {self};func reset() {};func revoke() {};func cancel() {};func stop() {}}
final class TestWindow {var closeCalls=0;func orderOut(_ sender:Any?) {};func close() {closeCalls += 1}}
enum TestCursorState {case empty}
enum TestUserTextureLoad {case empty}
struct TestDeferredUpdate {let generation:UInt64;let layerIDs:Set<Int>}
final class SceneSystemMediaDemandRegistry {static let shared=SceneSystemMediaDemandRegistry();func release(_ id:UUID) {}}

struct TestPreparedResources {let baseImages:ControlledFontWorker}
typealias TestLaunchContext = SceneDesktopWallpaperLaunchContext
extension TestCursorProgram {func restoreEdgeState(_ state:TestCursorState) {}}
@MainActor final class SceneDesktopWallpaperSession {
    var launchContext:TestLaunchContext?
    var dynamicTextTextures:ControlledFontWorker?
    var mediaThumbnailTextures:ControlledFontWorker?
    var pendingProviderUpdate:(dynamicValues:Int,dynamicLayers:[Int],dynamicTextFieldsByLayerID:[Int:Set<Int>],mediaInput:Int)?

    let lifecycleID=UUID()
    let initialPresentationCohort=TestResettable(),userShortcutInput=TestResettable()
    var initialVideoPreparation:TestResettable?,screenReconciliationWorkItem:DispatchWorkItem?
    // PRODUCTION_PENDING_TYPES
    var pendingSurfacePreparation:PendingSurfacePreparation?
    var evaluationTransaction=TestEvaluationTransaction(),sceneClock=TestClock()
    let surfacePreparationQueue=DispatchQueue(label:"test.pending-surface-preparation")
    var screenTopology:[Int]=[]
    var frameTimer:Timer?,frameDriverDeadline:Double?,pausedFrameRetryDeadline:Double?
    var debugSurfaceReferenceFrames:[Int:Int]=[:]
    var pendingDeferredLayerVisibilityUpdate:TestDeferredUpdate?
    var audioDemand=(false,false)
    var onAudioDemandChanged:(()->Void)?
    var debugDropDynamicValuesFrameIndex:UInt64?
    var debugDidDropDynamicValues=false,debugDidLogDynamicValuesRecovery=false
    var videoTextureSourceRegistry:TestResettable?,soundPlaybackRegistry:TestResettable?
    var firstFramePresentationRegistration:Int?
    var userPropertyTextureLoad=TestUserTextureLoad.empty
    var debugPointerOverride:Int?
    func releaseUserShortcutScopes() {};func cancelPendingUserTextureUpdates() {};func removePointerEventMonitors() {}
    func teardownSceneScriptOwners(_ context:TestLaunchContext,reason:SceneGraphExecutionResetReason) {}
    func logDeferredLayerVisibilityTransition(generation:UInt64,layerIDs:Set<Int>,state:String) {}

    final class Renderer { let commandQueue: MTLCommandQueue; init(_ q: MTLCommandQueue) { commandQueue=q } }
    final class View {
        let renderer: Renderer
        let debugFrameCapture: SceneDebugFrameCapture
        var invalidations=0
        func invalidateResolvedMaterialRuntime(reason:SceneGraphExecutionResetReason) {invalidations += 1}
        init(_ q: MTLCommandQueue, _ c: SceneDebugFrameCapture) { renderer=Renderer(q);debugFrameCapture=c }
    }
    final class Surface {
        let metalView: View
        let window=TestWindow()
        // CPU owners are opaque here; the real teardown must release the set.
        var puppetPlaybackStates: [Int: Int] = [17: 1]
        var particleTeardownCalls=0
        func teardownParticlePlayback(reason:SceneGraphExecutionResetReason) {particleTeardownCalls += 1}
        init(_ q: MTLCommandQueue, _ c: SceneDebugFrameCapture) { metalView=View(q,c) }
    }
    var surfaces: [CGDirectDisplayID: Surface] = [:]
    var retiringSurfaces: [ObjectIdentifier: Surface] = [:]
    var drainStarted=false
    var drainResult: Bool?
    var surfaceDrainFailed=false
    let retiringSurfaceDrain=DispatchGroup()
    var drainCallbacks: [@MainActor (Bool)->Void] = []
    func startControlledSurfacePreparation() {
        prepareAddedSurfaces([(NSScreen.screens[0],1)],context:launchContext!)
    }
    static func surfaceScreens(topology:[Int])->[(NSScreen,CGDirectDisplayID)] {
        preconditionFailure("departed pending callback resolved live screens")
    }
    func reconcileSurfaceScreens(_ screens:[(NSScreen,CGDirectDisplayID)],context:TestLaunchContext,
                                 publishMembership:Bool=true)->Bool {
        preconditionFailure("departed pending callback reconciled live surfaces")
    }
    func installPreparedSurfaces(_ prepared:[PreparedSurface],screens:[(NSScreen,CGDirectDisplayID)],
                                context:TestLaunchContext,dynamicValues:SceneDynamicSnapshot?)->Int {
        preconditionFailure("cancelled pending callback installed a surface")
    }
    func updatePreparedSurfaceMembership(_ context:TestLaunchContext) {preconditionFailure("departed membership")}
    func startFrameDriver() {preconditionFailure("departed frame driver")}
    // PRODUCTION_PENDING_METHODS
    func stop() {
        let previous=Array(surfaces.values)
        teardownSurfaces(clearContext:true,reason:.surfaceStop)
        precondition(previous.allSatisfy {$0.puppetPlaybackStates.isEmpty},"shutdown retained CPU Puppet owners")
    }
}
enum PlaybackPerformanceProfile:Int {case fps60=60;var maxFPS:Int {rawValue}}
'''
HARNESS = SESSION_SHUTDOWN_SUPPORT + r'''
@MainActor final class SceneDesktopWallpaperHost {
    static let usesDebugEvidenceWindow=false
    func applyPerformanceProfile(_ profile:PlaybackPerformanceProfile) {}
    struct Snapshot { let surfaceCount: Int; let windowNumbers: [Int] = []; let isPlaybackPaused=false; let isFrameDriverActive=true }
    struct Layer { let id=1 }
    struct Descriptor { let layers=[Layer()] }
    struct Model { let renderDescriptor=Descriptor() }
    var stopCalls=0, drainCalls=0, launchCalls=0, resumeCalls=0, pauseCalls=0
    var didPause: (() -> Void)?
    var completion: (@MainActor (Bool)->Void)?
    var launchContinuation: CheckedContinuation<Model, Error>?
    var launchStarted: (() -> Void)?
    func stop() { stopCalls += 1 }
    func stopAndDrainGPU(completion: @escaping @MainActor (Bool)->Void) {
        stop(); drainCalls += 1; self.completion=completion
    }
    func debugSnapshot()->Snapshot { Snapshot(surfaceCount: stopCalls == 0 ? 1 : 0) }
    func setPlaybackPaused(_ paused: Bool) {
        if paused { pauseCalls += 1; didPause?() } else { resumeCalls += 1 }
    }
    func launch(rootURL:URL, propertyOverrides:[String:SceneUserPropertyValue], userPropertyTextureURLs:[String:URL], logURL:URL?, recordID:String) async throws -> Model {
        launchCalls += 1
        return try await withCheckedThrowingContinuation { continuation in
            launchContinuation=continuation; launchStarted?()
        }
    }
}
@MainActor enum DebugScenePlaybackRunner {
    static var snapshotCalls=0
    static func isIsolatedSampleRoot(_ url: URL)->Bool { true }
    static func requestedUserPropertyTextureURLs(rootURL:URL)->[String:URL] { [:] }
    static func requestSnapshot(reason:String,outputDirectory:URL) { if !isClosing { snapshotCalls += 1 } }
}
@main enum Harness {
    static func check(_ condition: @autoclosure ()->Bool,_ message:String) {
        guard condition() else { fatalError(message) }
    }
    static func wait(_ semaphore:DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                check(semaphore.wait(timeout:.now()+15) == .success,"timeout")
                continuation.resume()
            }
        }
    }
    @MainActor static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {try await run();app.terminate(nil)}
            catch {fatalError(String(describing:error))}
        }
        app.run()
    }
    @MainActor static func run() async throws {
        let dir=URL(fileURLWithPath:CommandLine.arguments.last!,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        if !CommandLine.arguments.contains("--runner-only") {
        let device=MTLCreateSystemDefaultDevice()!,queue=device.makeCommandQueue()!
        if CommandLine.arguments.contains("--retirement-failure") {
            let session=SceneDesktopWallpaperSession()
            let capture=SceneDebugFrameCapture()
            let surface=SceneDesktopWallpaperSession.Surface(controlledRetirementQueue(queue,false),capture)
            session.retireSurface(surface)
            let finished=DispatchSemaphore(value:0)
            var results:[Bool]=[]
            session.stopAndDrainGPU {results.append($0);finished.signal()}
            // Inverted event: the earlier retirement callback remains withheld.
            let premature = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning:finished.wait(timeout:.now()+0.1) == .success)
                }
            }
            deliverControlledRetirementFailure()
            if !premature { await wait(finished) }
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    check(waitForControlledStopBarrier(),"stop barrier was not reached")
                    continuation.resume()
                }
            }
            check(!premature && results == [false],"stop reported success before retirement failure delivery")
            let missing=SceneDesktopWallpaperSession()
            let missingSurface=SceneDesktopWallpaperSession.Surface(controlledRetirementQueue(queue,true),SceneDebugFrameCapture())
            let missingFont=ControlledFontWorker()
            missing.dynamicTextTextures=missingFont
            await wait(missingFont.entered)
            missing.retireSurface(missingSurface)
            let missingRetired=DispatchSemaphore(value:0)
            missing.retiringSurfaceDrain.notify(queue:.global()) {missingRetired.signal()}
            await wait(missingRetired)
            check(missing.retiringSurfaces.isEmpty && missingFont.closeCallCount == 0,
                  "surface retirement closed or waited for the Session font worker")
            let missingDone=DispatchSemaphore(value:0)
            var missingResult:Bool?
            missing.stopAndDrainGPU {missingResult=$0;missingDone.signal()}
            check(missingResult == nil,"nil GPU barrier bypassed font worker")
            check(missing.dynamicTextTextures == nil && missingFont.closeCallCount == 1,
                  "full stop did not detach and drain the sole font owner")
            missingFont.release.signal()
            await wait(missingDone)
            check(missingResult == false && missing.retiringSurfaces.isEmpty,"barrier creation failure lost failure or hung")
            print("PASS: stop waits for delayed retirement failure; nil barrier preserved and drained")
            return
        }
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:4,height:4,mipmapped:false)
        descriptor.storageMode = .shared
        let texture=device.makeTexture(descriptor:descriptor)!
        var pixels=[UInt8](repeating:100,count:64)
        for i in stride(from:3,to:64,by:4) { pixels[i]=255 }
        texture.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,withBytes:pixels,bytesPerRow:16)
        let entered=DispatchSemaphore(value:0), release=DispatchSemaphore(value:0)
        let capture=SceneDebugFrameCapture(beforeExport:{entered.signal();release.wait()})
        let session=SceneDesktopWallpaperSession()
        let surface=SceneDesktopWallpaperSession.Surface(queue,capture)
        session.surfaces[2]=surface
        let keeperCapture=SceneDebugFrameCapture()
        let keeperQueue=device.makeCommandQueue()!
        let keeper=SceneDesktopWallpaperSession.Surface(keeperQueue,keeperCapture)
        session.surfaces[1]=keeper
        capture.request(reason:"retired",outputDirectory:dir)
        let command=queue.makeCommandBuffer()!
        capture.encodeIfRequested(texture:texture,commandBuffer:command)
        command.commit()
        await wait(entered)
        session.teardownSurface(session.surfaces.removeValue(forKey:2)!,reason:.surfaceStop)
        check(session.surfaces[1] === keeper && keeper.particleTeardownCalls == 0
              && keeper.window.closeCalls == 0 && keeper.metalView.invalidations == 0
              && surface.particleTeardownCalls == 1 && surface.puppetPlaybackStates.isEmpty
              && surface.window.closeCalls == 1 && surface.metalView.invalidations == 1,
              "removed teardown touched a survivor or retained removed CPU owners")
        let barrier=queue.makeCommandBuffer()!
        let terminal=DispatchSemaphore(value:0)
        barrier.addCompletedHandler {_ in terminal.signal()};barrier.commit()
        await wait(terminal)
        check(session.retiringSurfaces.count == 1,"retired surface released before export")
        guard case .accepted = keeperCapture.request(reason:"survivor",outputDirectory:dir) else {
            fatalError("removed retirement closed survivor capture admission")
        }
        let keeperCommand=keeperQueue.makeCommandBuffer()!
        keeperCapture.encodeIfRequested(texture:texture,commandBuffer:keeperCommand)
        let keeperDone=DispatchSemaphore(value:0)
        keeperCommand.addCompletedHandler {_ in keeperDone.signal()};keeperCommand.commit()
        await wait(keeperDone)
        check(session.retiringSurfaces.count == 1 && session.surfaces[1] === keeper,
              "removed export blocked survivor GPU progress or disposed its active owner")
        var results:[Bool]=[]
        let drained=DispatchSemaphore(value:0)
        session.stop()
        session.stopAndDrainGPU { results.append($0);drained.signal() }
        session.stopAndDrainGPU { results.append($0);drained.signal() }
        check(results.isEmpty && session.drainResult == nil,"session reported early drain")
        release.signal()
        await wait(drained);await wait(drained)
        check(results == [true,true] && session.retiringSurfaces.isEmpty,"retired capture or repeated drain failed")
        check(surface.particleTeardownCalls == 1 && keeper.particleTeardownCalls == 1
              && surface.window.closeCalls == 1 && keeper.window.closeCalls == 1
              && surface.metalView.invalidations == 1 && keeper.metalView.invalidations == 1,
              "removed and retained CPU owners did not each retire exactly once")
        check(FileManager.default.fileExists(atPath:dir.appendingPathComponent("scene-retired-window.png").path),"drain preceded file")
        check(FileManager.default.fileExists(atPath:dir.appendingPathComponent("scene-survivor-window.png").path),
              "stop drain preceded survivor export")
        session.stopAndDrainGPU { results.append($0) }
        check(results == [true,true,true],"completed drain not idempotent")
        let fontSession=SceneDesktopWallpaperSession()
        let fontWork=ControlledFontWorker()
        let mediaWork=ControlledFontWorker()
        fontSession.dynamicTextTextures=fontWork
        fontSession.mediaThumbnailTextures=mediaWork
        fontSession.surfaces[1] = .init(queue,SceneDebugFrameCapture())
        fontSession.surfaces[2] = .init(queue,SceneDebugFrameCapture())
        await wait(fontWork.entered)
        await wait(mediaWork.entered)
        let deferredWork=ControlledFontWorker()
        fontSession.launchContext = .init(preparedDeviceResources:.init(baseImages:deferredWork))
        await wait(deferredWork.entered)
        let rebuiltSurfaces=Array(fontSession.surfaces.values)
        fontSession.teardownSurfaces(clearContext:false,reason:.surfaceStop)
        check(rebuiltSurfaces.allSatisfy {$0.particleTeardownCalls == 1},
              "surface rebuild did not retire each CPU particle owner once")
        check(rebuiltSurfaces.allSatisfy {$0.puppetPlaybackStates.isEmpty},
              "surface rebuild retained CPU Puppet owners")
        let rebuilt=DispatchSemaphore(value:0)
        fontSession.retiringSurfaceDrain.notify(queue:.global()) {rebuilt.signal()}
        await wait(rebuilt)
        check(fontSession.retiringSurfaces.isEmpty && fontSession.launchContext != nil,
              "surface rebuild retained GPU/export work or disposed the Session")
        check(fontSession.dynamicTextTextures === fontWork && fontWork.closeCallCount == 0,
              "two-surface rebuild closed or replaced the shared font producer")
        check(fontSession.mediaThumbnailTextures === mediaWork && mediaWork.cancelCallCount == 0,
              "two-surface rebuild cancelled or replaced the shared media producer")
        fontSession.surfaces[1] = .init(queue,SceneDebugFrameCapture())
        fontSession.surfaces[2] = .init(queue,SceneDebugFrameCapture())
        let nextFontEntered=DispatchSemaphore(value:0),nextFontRelease=DispatchSemaphore(value:0)
        let nextMediaEntered=DispatchSemaphore(value:0),nextMediaRelease=DispatchSemaphore(value:0)
        fontWork.enqueue {nextFontEntered.signal();nextFontRelease.wait()}
        mediaWork.enqueue {nextMediaEntered.signal();nextMediaRelease.wait()}
        fontWork.release.signal()
        mediaWork.release.signal()
        await wait(nextFontEntered)
        await wait(nextMediaEntered)
        var fontResult:Bool?
        let fontDone=DispatchSemaphore(value:0)
        fontSession.pendingProviderUpdate = (dynamicValues:1,dynamicLayers:[1],dynamicTextFieldsByLayerID:[:],mediaInput:2)
        fontSession.stop()
        check(fontSession.launchContext == nil && fontSession.dynamicTextTextures == nil
                && fontSession.mediaThumbnailTextures == nil && fontSession.pendingProviderUpdate == nil,
              "stop did not clear Session provider/context ownership")
        check(fontWork.closeCallCount == 1,"stop did not drain the sole text producer once")
        check(mediaWork.cancelCallCount == 1,"stop did not drain the sole media producer once")
        fontSession.stopAndDrainGPU {fontResult=$0;fontDone.signal()}
        check(fontResult == nil,"stop-before-drain bypassed the Session font worker")
        let prematureFontDrain = await withCheckedContinuation {continuation in
            DispatchQueue.global().async {continuation.resume(returning:fontDone.wait(timeout:.now()+0.1) == .success)}
        }
        check(!prematureFontDrain && fontResult == nil,"drain completed while rebuilt producer work was held")
        nextFontRelease.signal()
        nextMediaRelease.signal()
        let prematureSharedDrain = await withCheckedContinuation {continuation in
            DispatchQueue.global().async {continuation.resume(returning:fontDone.wait(timeout:.now()+0.1) == .success)}
        }
        check(!prematureSharedDrain && fontResult == nil,"stop-before-drain lost shared deferred worker")
        deferredWork.release.signal();await wait(fontDone)
        check(fontResult == true && fontSession.retiringSurfaces.isEmpty,"font work drain did not settle")
        check(fontWork.closeCallCount == 1 && mediaWork.cancelCallCount == 1,
              "drain enumerated a disposed or per-surface provider owner")
        for textFinishesFirst in [true,false] {
            let noSurface=SceneDesktopWallpaperSession()
            let text=ControlledFontWorker(),media=ControlledFontWorker()
            noSurface.dynamicTextTextures=text
            noSurface.mediaThumbnailTextures=media
            noSurface.pendingProviderUpdate = (dynamicValues:1,dynamicLayers:[1],dynamicTextFieldsByLayerID:[:],mediaInput:2)
            await wait(text.entered);await wait(media.entered)
            if textFinishesFirst {noSurface.stop()}
            var providerResult:Bool?
            let providerDone=DispatchSemaphore(value:0)
            noSurface.stopAndDrainGPU {providerResult=$0;providerDone.signal()}
            check(noSurface.dynamicTextTextures == nil && noSurface.mediaThumbnailTextures == nil
                    && noSurface.pendingProviderUpdate == nil,
                  "surface-free stop retained provider ownership or pending input")
            check(text.closeCallCount == 1 && media.cancelCallCount == 1,
                  "surface-free stop did not drain each producer exactly once")
            (textFinishesFirst ? text : media).release.signal()
            let prematureProviderDrain = await withCheckedContinuation {continuation in
                DispatchQueue.global().async {continuation.resume(returning:providerDone.wait(timeout:.now()+0.1) == .success)}
            }
            check(!prematureProviderDrain && providerResult == nil,
                  "Session finished while one provider tail was still held")
            (textFinishesFirst ? media : text).release.signal();await wait(providerDone)
            check(providerResult == true,"surface-free provider drain did not settle")
            noSurface.stopAndDrainGPU {check($0,"repeated provider drain failed")}
            check(text.closeCallCount == 1 && media.cancelCallCount == 1,
                  "completed drain re-admitted a disposed provider owner")
        }
        let empty=SceneDesktopWallpaperSession()
        let emptyDone=DispatchSemaphore(value:0)
        empty.stopAndDrainGPU {check($0,"empty failed");emptyDone.signal()};await wait(emptyDone)

        }
        // Start a real Runner switch, hold the host's async result, then close.
        let host=DebugScenePlaybackRunner.runtimeHost
        let started=DispatchSemaphore(value:0)
        host.launchStarted={started.signal()}
        let request=DebugScenePlaybackRunner.SceneSwitchRequest(delay:0,rootURL:dir,usesAlternateRoot:false)
        DebugScenePlaybackRunner.scheduleSceneSwitch(request:request,recordID:"test",propertyOverrides:[:],logURL:nil,outputDirectory:dir)
        await wait(started)
        let paused=DispatchSemaphore(value:0)
        host.didPause={paused.signal()}
        DebugScenePlaybackRunner.schedulePauseResume(request:.init(delay:0,dwell:0.05),outputDirectory:dir)
        await wait(paused)
        // This second already-scheduled pause reaches its entry after closing.
        DebugScenePlaybackRunner.schedulePauseResume(request:.init(delay:0.05,dwell:0),outputDirectory:dir)
        var finished:[Bool]=[]
        DebugScenePlaybackRunner.finish {finished.append($0)}
        DebugScenePlaybackRunner.finish {finished.append($0)}
        check(host.drainCalls == 1 && finished.isEmpty,"finish didn't coalesce or waited incorrectly")
        host.launchContinuation?.resume(returning:.init());host.launchContinuation=nil
        // Enqueue late producers on their actual entry points after closing.
        DebugScenePlaybackRunner.scheduleSceneSwitch(request:request,recordID:"late",propertyOverrides:[:],logURL:nil,outputDirectory:dir)
        DebugScenePlaybackRunner.scheduleSurfaceStopRelaunch(delay:0,recordID:"late",rootURL:dir,propertyOverrides:[:],userPropertyTextureURLs:[:],logURL:nil,outputDirectory:dir)
        // Fence the real delayed pause/resume callbacks after their deadlines.
        let producerFence=DispatchSemaphore(value:0)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { producerFence.signal() }
        await wait(producerFence)
        host.completion?(true);host.completion=nil
        check(finished == [true,true],"finish callbacks")
        DebugScenePlaybackRunner.finish {finished.append($0)}
        check(finished == [true,true,true] && host.drainCalls == 1,"repeated finish")
        check(host.launchCalls == 1 && host.pauseCalls == 1 && host.resumeCalls == 0 && DebugScenePlaybackRunner.snapshotCalls == 0,"late launch resumed closed runner")
        print("PASS: real retired capture drain, Session text/media rebuild/no-surface/stop-before-drain, Runner coalesced finish and late launch")
    }
}
'''

APPKIT_TEMPLATE = SESSION_SHUTDOWN_SUPPORT + r'''
@MainActor final class SceneDesktopWallpaperHost {
    static let usesDebugEvidenceWindow=false
    func applyPerformanceProfile(_ profile:PlaybackPerformanceProfile) {}
    struct Snapshot {let surfaceCount=0}
    let session=SceneDesktopWallpaperSession()
    var onDrainStarted:(()->Void)?
    func debugSnapshot()->Snapshot {Snapshot()}
    func stop() {}
    func stopAndDrainGPU(completion:@escaping @MainActor(Bool)->Void) {onDrainStarted?();onDrainStarted=nil;session.stopAndDrainGPU(completion:completion)}
}
@MainActor enum DebugScenePlaybackRunner {
    static let runsIsolatedSceneSample=true
    static func requestTermination(after delay:TimeInterval) {terminate(after:delay)}
    static func argumentValue(after flag:String)->String? {
        let arguments=ProcessInfo.processInfo.arguments
        guard let index=arguments.firstIndex(of:flag),arguments.indices.contains(index+1) else {return nil}
        return arguments[index+1]
    }
    // PRODUCTION_RUNNER_TERMINATION
    // PRODUCTION_PERFORMANCE_PROFILE
}
@MainActor enum DebugSceneDaemonClientRunner {static let isRequested=false;static let requiresProductCoordinator=false}
@MainActor enum DebugWebPlaybackRunner {static let runsIsolatedWebWorkshopSample=false}
@MainActor final class SceneDaemonClient {
    static let shared=SceneDaemonClient()
    func shutdown() {}
}
@MainActor final class WallpaperEngine {
    static let shared=WallpaperEngine()
    func cleanup() {}
}
// Compile the product-only branch too; the isolated runner below takes its
// original drain path and never invokes these metadata/UI leaves.
@MainActor enum MyWallpaperXApplication {
    static func prepareLibraryForTermination() {}
    static func cancelLibraryTermination() {}
    static func flushLibraryBeforeTermination() async -> String? {nil}
}
@MainActor enum MainWindowCoordinator {static func mainWindow()->NSWindow? {nil}}
@MainActor func makeAppAlert(title:String,message:String)->String {title+message}
@MainActor func presentAppAlert(_ alert:String,in window:NSWindow?) {}
@MainActor final class ProbeApplication:NSApplication {
    override func reply(toApplicationShouldTerminate shouldTerminate:Bool) {
        NSLog("APPKIT TEST reply=%@",shouldTerminate ? "true":"false")
        super.reply(toApplicationShouldTerminate:shouldTerminate)
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    private(set) var terminationReplyPending=false
    func prepareProductTermination() {}
    let terminationEntered=DispatchSemaphore(value:0)
    var observedPending=false
    var surfacePreparation:SceneDesktopWallpaperSession.PendingSurfacePreparation?
    var preparationStep:TestPreparationStep?,preparationTrace:TestTrace?
    // PRODUCTION_TERMINATION_METHOD
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        let result=ownedApplicationShouldTerminate(sender)
        if result == .terminateLater && !observedPending {
            observedPending=true
            precondition(!DebugScenePlaybackRunner.isFinished)
            NSLog("APPKIT TEST repeat owned finish while export pending")
            precondition(ownedApplicationShouldTerminate(sender) == .terminateLater)
            DebugScenePlaybackRunner.finish { _ in NSLog("APPKIT TEST repeated-finish completed") }
            DebugScenePlaybackRunner.requestTermination(after:0)
            terminationEntered.signal()
        }
        return result
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let args=CommandLine.arguments
        if args.contains("--surface-worker") || args.contains("--surface-main-tail")
            || args.contains("--surface-stopped-before-drain") {
            let step=TestPreparationStep(held:true),trace=TestTrace()
            let session=DebugScenePlaybackRunner.runtimeHost.session
            session.launchContext = .init([step],trace:trace)
            session.startControlledSurfacePreparation()
            surfacePreparation=session.pendingSurfacePreparation;preparationStep=step;preparationTrace=trace
            if args.contains("--surface-stopped-before-drain") {
                precondition(step.entered.wait(timeout:.now()+5) == .success)
                session.stop()
                precondition(session.pendingSurfacePreparation != nil)
            }
            if args.contains("--surface-main-tail") {
                DispatchQueue.main.async {
                    precondition(step.entered.wait(timeout:.now()+5) == .success)
                    let returned=DispatchSemaphore(value:0)
                    session.surfacePreparationQueue.async {returned.signal()}
                    step.release.signal()
                    precondition(returned.wait(timeout:.now()+5) == .success)
                    precondition(step.prepared.count == 1)
                    NSLog("APPKIT TEST pending preparation main tail queued")
                    NSApp.terminate(nil)
                }
            } else {
                DispatchQueue.global().async {
                    if !args.contains("--surface-stopped-before-drain") {
                        precondition(step.entered.wait(timeout:.now()+5) == .success)
                    }
                    precondition(self.terminationEntered.wait(timeout:.now()+5) == .success)
                    NSLog("APPKIT TEST pending preparation worker release")
                    step.release.signal()
                }
                DispatchQueue.main.async {NSApp.terminate(nil)}
            }
            return
        }
        if args.contains("--terminal-failed") {DebugScenePlaybackRunner.runtimeHost.session.surfaceDrainFailed=true}
        if args.contains("--font-work") || args.contains("--font-without-surface")
            || args.contains("--font-stopped-before-drain") || args.contains("--deferred-work")
            || args.contains("--media-work") || args.contains("--media-without-surface")
            || args.contains("--media-stopped-before-drain") {
            let queue=MTLCreateSystemDefaultDevice()!.makeCommandQueue()!
            let work=ControlledFontWorker()
            let surface=SceneDesktopWallpaperSession.Surface(queue,SceneDebugFrameCapture())
            if args.contains("--deferred-work") {
                DebugScenePlaybackRunner.runtimeHost.session.launchContext = .init(preparedDeviceResources:.init(baseImages:work))
            } else if args.contains("--media-work") || args.contains("--media-without-surface")
                || args.contains("--media-stopped-before-drain") {
                DebugScenePlaybackRunner.runtimeHost.session.mediaThumbnailTextures=work
            } else {DebugScenePlaybackRunner.runtimeHost.session.dynamicTextTextures=work}
            if !args.contains("--font-without-surface") && !args.contains("--media-without-surface") {
                DebugScenePlaybackRunner.runtimeHost.session.surfaces[1]=surface
            }
            if args.contains("--deferred-work") || args.contains("--font-stopped-before-drain")
                || args.contains("--media-stopped-before-drain") {
                DebugScenePlaybackRunner.runtimeHost.session.stop()
            }
            DispatchQueue.global().async {
                precondition(work.entered.wait(timeout:.now()+5) == .success)
                precondition(self.terminationEntered.wait(timeout:.now()+5) == .success)
                NSLog("APPKIT TEST provider worker release")
                work.release.signal()
            }
            DispatchQueue.main.async {NSApp.terminate(nil)}
            return
        }
        if args.contains("--export") || args.contains("--retiring-export") || args.contains("--overlap-owned") || args.contains("--invalid-profile") {
            let device=MTLCreateSystemDefaultDevice()!,queue=device.makeCommandQueue()!
            let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
            let capture=SceneDebugFrameCapture(beforeExport:{entered.signal();release.wait()})
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:4,height:4,mipmapped:false)
            descriptor.storageMode = .shared
            let texture=device.makeTexture(descriptor:descriptor)!
            let pixels=[UInt8](repeating:255,count:64)
            texture.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,withBytes:pixels,bytesPerRow:16)
            let surface=SceneDesktopWallpaperSession.Surface(queue,capture)
            let session=DebugScenePlaybackRunner.runtimeHost.session
            session.surfaces[1]=surface
            capture.request(reason:"appkit-pending",outputDirectory:URL(fileURLWithPath:args.last!,isDirectory:true))
            let command=queue.makeCommandBuffer()!
            capture.encodeIfRequested(texture:texture,commandBuffer:command);command.commit()
            if args.contains("--retiring-export") {session.retireSurface(surface);session.surfaces.removeAll()}
            DispatchQueue.global().async {
                precondition(entered.wait(timeout:.now()+5) == .success)
                DispatchQueue.global().async {
                    precondition(self.terminationEntered.wait(timeout:.now()+5) == .success)
                    if args.contains("--invalid-profile") {Thread.sleep(forTimeInterval:0.2)}
                    NSLog("APPKIT TEST background export release")
                    release.signal()
                }
                DispatchQueue.main.async {
                    NSLog("APPKIT TEST requesting blocked-export termination")
                    if args.contains("--invalid-profile") {
                        precondition(!DebugScenePlaybackRunner.applyRequestedPerformanceProfile())
                        RunLoop.main.perform(inModes:[.common]) {
                            MainActor.assumeIsolated {NSApp.terminate(nil)}
                        }
                    } else if args.contains("--overlap-owned") {
                        DebugScenePlaybackRunner.runtimeHost.onDrainStarted = {
                            RunLoop.main.perform(inModes:[.common]) {
                                MainActor.assumeIsolated {NSApp.terminate(nil)}
                            }
                        }
                        DebugScenePlaybackRunner.requestTermination(after:0)
                    } else {NSApp.terminate(nil)}
                }
            }
            return
        }
        DispatchQueue.main.async {
            if args.contains("--owned") {
                DebugScenePlaybackRunner.requestTermination(after:0)
                DebugScenePlaybackRunner.requestTermination(after:0)
            } else if args.contains("--predrained") || args.contains("--terminal-failed") {
                DebugScenePlaybackRunner.finish { _ in
                    NSLog("APPKIT TEST requesting already-drained termination")
                    NSApp.terminate(nil)
                }
            } else {
                NSLog("APPKIT TEST requesting pending-drain termination")
                NSApp.terminate(nil)
            }
        }
    }
    func applicationWillTerminate(_ notification:Notification) {
        precondition(DebugScenePlaybackRunner.isFinished, "application terminated before owned drain")
        if let surfacePreparation,let preparationStep,let preparationTrace {
            precondition(surfacePreparation.cancellation.isCancelled)
            precondition(DebugScenePlaybackRunner.runtimeHost.session.pendingSurfacePreparation == nil)
            precondition(preparationTrace.values.filter {$0 == "evict-1"}.count == 1)
            if CommandLine.arguments.contains("--surface-main-tail") {
                precondition(preparationStep.prepared[0].teardownReasons == ["preparationCancelled"])
            }
        }
        if CommandLine.arguments.contains("--export") || CommandLine.arguments.contains("--retiring-export") || CommandLine.arguments.contains("--overlap-owned") || CommandLine.arguments.contains("--invalid-profile") {
            let path=URL(fileURLWithPath:CommandLine.arguments.last!,isDirectory:true).appendingPathComponent("scene-appkit-pending-window.png").path
            precondition(FileManager.default.fileExists(atPath:path),"application terminated before PNG")
        }
        NSLog("APPKIT TEST did-terminate")
    }
}
@main enum Harness {
    @MainActor static func main() {
        let app=ProbeApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate=AppDelegate()
        app.delegate=delegate
        withExtendedLifetime(delegate) {app.run()}
    }
}
'''


def production_method(source, signature):
    # Compile the actual owner method without unrelated host services.
    # Assertions observe effects and events, never source spelling.
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def preparation_sources():
    directory = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session"
    session = (directory / "SceneDesktopWallpaperSession.swift").read_text()
    owner = (directory / "SceneDesktopWallpaperSession+SurfacePreparation.swift").read_text()
    models = (directory / "SceneDesktopWallpaperLaunchModels.swift").read_text()
    cancellation = production_method(models, "nonisolated final class SceneWallpaperLaunchCancellation:")
    types = "\n".join(production_method(owner, signature) for signature in
        ("    struct PreparedSurface {", "    final class PendingSurfacePreparation {"))
    pending = "\n".join(production_method(owner, signature) for signature in
        ("    private func prepareAddedSurfaces(", "    private func finishSurfacePreparation("))
    coordinator = "\n".join([
        production_method(session, "    func applyDisplayConfiguration("),
        production_method(session, "    private func scheduleScreenConfigurationReconciliation("),
        production_method(owner, "    func reconcileSurfaceScreens("), pending,
        production_method(owner, "    func updatePreparedSurfaceMembership(")])
    return cancellation, types, pending, coordinator


def shutdown_harness(template):
    fixture = (ROOT / "script/tests/fixtures/SceneSurfacePreparationHarness.swift").read_text()
    leaves = fixture.split("// PREPARATION_LEAVES_BEGIN\n", 1)[1].split("// PREPARATION_LEAVES_END", 1)[0]
    cancellation, types, pending, _ = preparation_sources()
    return (template.replace("// SHARED_PREPARATION_LEAVES", leaves)
            .replace("// PRODUCTION_CANCELLATION", cancellation)
            .replace("// PRODUCTION_PENDING_TYPES", types)
            .replace("// PRODUCTION_PENDING_METHODS", pending))


class SceneDebugCaptureShutdownTests(unittest.TestCase):
    def test_display_reconciliation_preserves_actual_members_and_reuses_resolution(self):
        cancellation, types, pending, coordinator = preparation_sources()
        fixture = (ROOT / "script/tests/fixtures/SceneSurfacePreparationHarness.swift").read_text()
        source = (fixture.replace("// PRODUCTION_CANCELLATION", cancellation)
                  .replace("// PRODUCTION_PREPARATION_TYPES", types)
                  .replace("// PRODUCTION_DISPLAY_METHODS", coordinator))
        with tempfile.TemporaryDirectory(prefix="mwx-display-reconciliation-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(source)
            binary = directory / "harness"
            topology = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneScreenTopology.swift"
            compilation = subprocess.run(["xcrun", "swiftc", "-D", "DEBUG", str(topology), str(harness), "-o", str(binary)],
                                         capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS:", result.stdout)

    def test_retirement_and_runner_finish_wait_for_real_export(self):
        with tempfile.TemporaryDirectory(prefix="mwx-capture-shutdown-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(shutdown_harness(HARNESS))
            binary = directory / "harness"
            sources = [
                "Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift",
                "Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
                "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift",
                "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift",
                "App/Debug/DebugScenePlaybackRunner+HostOwnership.swift",
                "App/Debug/DebugScenePlaybackRunner+SceneSwitch.swift",
                "App/Debug/DebugScenePlaybackRunner+PauseResume.swift",
                "App/Debug/DebugScenePlaybackRunner+SurfaceStopRelaunch.swift",
            ]
            proxy = directory / "Proxy.m"
            proxy.write_text(PROXY_SOURCE)
            header = directory / "Proxy.h"
            header.write_text(PROXY_HEADER)
            obj = directory / "Proxy.o"
            objc_result = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-c", str(proxy), "-o", str(obj)], capture_output=True, text=True)
            self.assertEqual(objc_result.returncode, 0, objc_result.stderr)
            compile_result = subprocess.run(["xcrun", "swiftc", "-import-objc-header", str(header), str(obj), "-D", "DEBUG", "-D", "SCENE_SHUTDOWN_PREPARATION", *[str(ROOT / "MyWallpaperX" / p) for p in sources], str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary), "--mwx-debug-scene-evidence-dir", str(directory / "evidence")], capture_output=True, text=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS:", result.stdout)
            failure = subprocess.run([str(binary), "--retirement-failure", "--mwx-debug-scene-evidence-dir", str(directory / "failure-evidence")], capture_output=True, text=True, timeout=20)
            self.assertEqual(failure.returncode, 0, failure.stderr)
            self.assertIn("PASS:", failure.stdout)

    def test_real_appkit_termination_delivers_pending_and_completed_drains(self):
        self.run_appkit_modes(("predrained", "pending", "terminal-failed", "owned", "export", "retiring-export", "overlap-owned", "invalid-profile", "font-work", "font-without-surface", "font-stopped-before-drain", "media-work", "media-without-surface", "media-stopped-before-drain", "deferred-work"))

    def test_appkit_termination_delivers_added_preparation_tails(self):
        self.run_appkit_modes(("surface-worker", "surface-main-tail", "surface-stopped-before-drain"))

    def run_appkit_modes(self, modes):
        with tempfile.TemporaryDirectory(prefix="mwx-appkit-shutdown-") as raw:
            directory = Path(raw)
            delegate = (ROOT / "MyWallpaperX/App/AppDelegate.swift").read_text()
            runner = (ROOT / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift").read_text()
            source = shutdown_harness(APPKIT_TEMPLATE).replace("// PRODUCTION_TERMINATION_METHOD", production_method(
                delegate, " func applicationShouldTerminate(_ sender: NSApplication)").replace("func applicationShouldTerminate(", "func ownedApplicationShouldTerminate(") + "\n" + production_method(
                delegate, " private func replyAfterPlaybackProcessesExit(_ sender: NSApplication)"))
            source = source.replace("// PRODUCTION_RUNNER_TERMINATION", production_method(
                runner, "    static func terminate(after delay: TimeInterval)"))
            performance = (ROOT / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Performance.swift").read_text()
            source = source.replace("// PRODUCTION_PERFORMANCE_PROFILE", production_method(
                performance, "    static func applyRequestedPerformanceProfile() -> Bool"))
            harness = directory / "AppKit.swift"
            harness.write_text(source)
            binary = directory / "appkit"
            sources = ["Core/DaemonKit/DaemonProcessTransport.swift",
                       "Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift",
                       "Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
                       "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift",
                "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift",
                       "App/Debug/DebugScenePlaybackRunner+HostOwnership.swift"]
            compilation = subprocess.run(["xcrun", "swiftc", "-D", "DEBUG", "-D", "SCENE_SHUTDOWN_PREPARATION", *[str(ROOT / "MyWallpaperX" / p) for p in sources],
                                          str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            for mode in modes:
                with self.subTest(mode=mode):
                    evidence = directory / mode
                    evidence.mkdir()
                    result = subprocess.run([str(binary), "--" + mode, "--mwx-debug-scene-performance-fps", "invalid", "--mwx-debug-scene-evidence-dir", str(evidence)],
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr.count("APPKIT TEST did-terminate"), 1, result.stderr)
                    self.assertEqual(result.stderr.count("APPKIT TEST reply=true"), 1, result.stderr)
                    self.assertLess(result.stderr.index("phase=stopped"), result.stderr.index("APPKIT TEST did-terminate"))
                    if mode in ("font-work", "font-without-surface", "font-stopped-before-drain", "media-work", "media-without-surface", "media-stopped-before-drain", "deferred-work"):
                        self.assertLess(result.stderr.index("APPKIT TEST provider worker release"), result.stderr.index("phase=stopped"))
                    if mode.startswith("surface-"):
                        self.assertLess(result.stderr.index("state=resources-finished"), result.stderr.index("phase=stopped"))
                        if mode == "surface-main-tail":
                            self.assertLess(result.stderr.index("state=worker-returned"), result.stderr.index("APPKIT TEST pending preparation main tail queued"))
                        else:
                            self.assertLess(result.stderr.index("APPKIT TEST pending preparation worker release"), result.stderr.index("state=resources-finished"))
                    if mode in ("export", "retiring-export", "overlap-owned", "invalid-profile"):
                        self.assertTrue((evidence / "scene-appkit-pending-window.png").is_file())
                        self.assertLess(result.stderr.index("phase=snapshot "), result.stderr.index("phase=stopped"))
                        self.assertIn("APPKIT TEST repeated-finish completed", result.stderr)

if __name__ == "__main__":
    unittest.main()
