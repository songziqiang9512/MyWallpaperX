#!/usr/bin/env python3
"""Exercise the production shutdown owners with real Metal and capture exports."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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
HARNESS = r'''
import AppKit
@preconcurrency import Metal

struct SceneUserPropertyValue {}
struct SceneResolvedMaterialFrameTargetPlan {}
@MainActor final class SceneDesktopWallpaperSession {
    final class Renderer { let commandQueue: MTLCommandQueue; init(_ q: MTLCommandQueue) { commandQueue=q } }
    final class View {
        let renderer: Renderer
        let debugFrameCapture: SceneDebugFrameCapture
        init(_ q: MTLCommandQueue, _ c: SceneDebugFrameCapture) { renderer=Renderer(q);debugFrameCapture=c }
    }
    final class Surface {
        let metalView: View
        init(_ q: MTLCommandQueue, _ c: SceneDebugFrameCapture) { metalView=View(q,c) }
    }
    var surfaces: [Int: Surface] = [:]
    var retiringSurfaces: [ObjectIdentifier: Surface] = [:]
    var drainStarted=false
    var drainResult: Bool?
    var surfaceDrainFailed=false
    let retiringSurfaceDrain=DispatchGroup()
    var drainCallbacks: [@MainActor (Bool)->Void] = []
    func stop() { surfaces.removeAll() }
}
enum PlaybackPerformanceProfile:Int {case fps60=60;var maxFPS:Int {rawValue}}
@MainActor final class SceneDesktopWallpaperHost {
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
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    check(waitForControlledStopBarrier(),"stop barrier was not reached")
                    continuation.resume()
                }
            }
            // Inverted event: the earlier retirement callback remains withheld.
            let premature = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning:finished.wait(timeout:.now()+0.1) == .success)
                }
            }
            deliverControlledRetirementFailure()
            if !premature { await wait(finished) }
            check(!premature && results == [false],"stop reported success before retirement failure delivery")
            let missing=SceneDesktopWallpaperSession()
            let missingSurface=SceneDesktopWallpaperSession.Surface(controlledRetirementQueue(queue,true),SceneDebugFrameCapture())
            missing.retireSurface(missingSurface)
            check(missing.retiringSurfaces.count == 1,"creation failure discarded surface")
            let missingDone=DispatchSemaphore(value:0)
            var missingResult:Bool?
            missing.stopAndDrainGPU {missingResult=$0;missingDone.signal()}
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
        session.surfaces[1]=surface
        capture.request(reason:"retired",outputDirectory:dir)
        let command=queue.makeCommandBuffer()!
        capture.encodeIfRequested(texture:texture,commandBuffer:command)
        command.commit()
        await wait(entered)
        session.retireSurface(surface)
        session.surfaces.removeAll()
        let barrier=queue.makeCommandBuffer()!
        let terminal=DispatchSemaphore(value:0)
        barrier.addCompletedHandler {_ in terminal.signal()};barrier.commit()
        await wait(terminal)
        check(session.retiringSurfaces.count == 1,"retired surface released before export")
        var results:[Bool]=[]
        let drained=DispatchSemaphore(value:0)
        session.stopAndDrainGPU { results.append($0);drained.signal() }
        session.stopAndDrainGPU { results.append($0);drained.signal() }
        check(results.isEmpty && session.drainResult == nil,"session reported early drain")
        release.signal()
        await wait(drained);await wait(drained)
        check(results == [true,true] && session.retiringSurfaces.isEmpty,"retired capture or repeated drain failed")
        check(FileManager.default.fileExists(atPath:dir.appendingPathComponent("scene-retired-window.png").path),"drain preceded file")
        session.stopAndDrainGPU { results.append($0) }
        check(results == [true,true,true],"completed drain not idempotent")
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
        print("PASS: real retired capture drain, repeated/empty session drain, Runner coalesced finish and late launch")
    }
}
'''

APPKIT_TEMPLATE = r'''
import AppKit
@preconcurrency import Metal
@MainActor final class SceneDesktopWallpaperSession {
    final class Renderer { let commandQueue: MTLCommandQueue; init(_ queue: MTLCommandQueue) {commandQueue=queue} }
    final class View { let renderer:Renderer;let debugFrameCapture:SceneDebugFrameCapture;init(_ queue:MTLCommandQueue,_ capture:SceneDebugFrameCapture) {renderer=Renderer(queue);debugFrameCapture=capture} }
    final class Surface { let metalView:View;init(_ queue:MTLCommandQueue,_ capture:SceneDebugFrameCapture) {metalView=View(queue,capture)} }
    var surfaces:[Int:Surface]=[:]
    var retiringSurfaces:[ObjectIdentifier:Surface]=[:]
    let retiringSurfaceDrain=DispatchGroup()
    var surfaceDrainFailed=false,drainStarted=false
    var drainResult:Bool?
    var drainCallbacks:[@MainActor(Bool)->Void]=[]
    func stop() {surfaces.removeAll()}
}
enum PlaybackPerformanceProfile:Int {case fps60=60;var maxFPS:Int {rawValue}}
@MainActor final class SceneDesktopWallpaperHost {
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
@MainActor enum DebugSceneDaemonClientRunner {static let isRequested=false}
@MainActor enum DebugWebPlaybackRunner {static let runsIsolatedWebWorkshopSample=false}
@MainActor final class SceneDaemonClient {
    static let shared=SceneDaemonClient()
    func shutdown(_ completion:()->Void) {completion()}
}
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
        if args.contains("--terminal-failed") {DebugScenePlaybackRunner.runtimeHost.session.surfaceDrainFailed=true}
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
    # Compile the actual owner method without the AppDelegate's unrelated UI
    # services. Assertions below observe AppKit events, never source spelling.
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

class SceneDebugCaptureShutdownTests(unittest.TestCase):
    def test_retirement_and_runner_finish_wait_for_real_export(self):
        with tempfile.TemporaryDirectory(prefix="mwx-capture-shutdown-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            binary = directory / "harness"
            sources = [
                "Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift",
                "Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
                "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift",
                "App/DebugScenePlaybackRunner+HostOwnership.swift",
                "App/DebugScenePlaybackRunner+SceneSwitch.swift",
                "App/DebugScenePlaybackRunner+PauseResume.swift",
                "App/DebugScenePlaybackRunner+SurfaceStopRelaunch.swift",
            ]
            proxy = directory / "Proxy.m"
            proxy.write_text(PROXY_SOURCE)
            header = directory / "Proxy.h"
            header.write_text(PROXY_HEADER)
            obj = directory / "Proxy.o"
            objc_result = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-c", str(proxy), "-o", str(obj)], capture_output=True, text=True)
            self.assertEqual(objc_result.returncode, 0, objc_result.stderr)
            compile_result = subprocess.run(["xcrun", "swiftc", "-import-objc-header", str(header), str(obj), "-D", "DEBUG", *[str(ROOT / "MyWallpaperX" / p) for p in sources], str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary), "--mwx-debug-scene-evidence-dir", str(directory / "evidence")], capture_output=True, text=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS:", result.stdout)
            failure = subprocess.run([str(binary), "--retirement-failure", "--mwx-debug-scene-evidence-dir", str(directory / "failure-evidence")], capture_output=True, text=True, timeout=20)
            self.assertEqual(failure.returncode, 0, failure.stderr)
            self.assertIn("PASS:", failure.stdout)

    def test_real_appkit_termination_delivers_pending_and_completed_drains(self):
        with tempfile.TemporaryDirectory(prefix="mwx-appkit-shutdown-") as raw:
            directory = Path(raw)
            delegate = (ROOT / "MyWallpaperX/App/AppDelegate.swift").read_text()
            runner = (ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner.swift").read_text()
            source = APPKIT_TEMPLATE.replace("// PRODUCTION_TERMINATION_METHOD", production_method(
                delegate, " func applicationShouldTerminate(_ sender: NSApplication)").replace("func applicationShouldTerminate(", "func ownedApplicationShouldTerminate("))
            source = source.replace("// PRODUCTION_RUNNER_TERMINATION", production_method(
                runner, "    static func terminate(after delay: TimeInterval)"))
            performance = (ROOT / "MyWallpaperX/App/DebugScenePlaybackRunner+Performance.swift").read_text()
            source = source.replace("// PRODUCTION_PERFORMANCE_PROFILE", production_method(
                performance, "    static func applyRequestedPerformanceProfile() -> Bool"))
            harness = directory / "AppKit.swift"
            harness.write_text(source)
            binary = directory / "appkit"
            sources = ["Core/SteamWorkshopScene/Diagnostics/SceneDebugFrameCapture.swift",
                       "Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
                       "Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+Shutdown.swift",
                       "App/DebugScenePlaybackRunner+HostOwnership.swift"]
            compilation = subprocess.run(["xcrun", "swiftc", "-D", "DEBUG", *[str(ROOT / "MyWallpaperX" / p) for p in sources],
                                          str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            for mode in ("predrained", "pending", "terminal-failed", "owned", "export", "retiring-export", "overlap-owned", "invalid-profile"):
                with self.subTest(mode=mode):
                    evidence = directory / mode
                    evidence.mkdir()
                    result = subprocess.run([str(binary), "--" + mode, "--mwx-debug-scene-performance-fps", "invalid", "--mwx-debug-scene-evidence-dir", str(evidence)],
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr.count("APPKIT TEST did-terminate"), 1, result.stderr)
                    self.assertEqual(result.stderr.count("APPKIT TEST reply=true"), 1, result.stderr)
                    self.assertLess(result.stderr.index("phase=stopped"), result.stderr.index("APPKIT TEST did-terminate"))
                    if mode in ("export", "retiring-export", "overlap-owned", "invalid-profile"):
                        self.assertTrue((evidence / "scene-appkit-pending-window.png").is_file())
                        self.assertLess(result.stderr.index("phase=snapshot "), result.stderr.index("phase=stopped"))
                        self.assertIn("APPKIT TEST repeated-finish completed", result.stderr)

if __name__ == "__main__":
    unittest.main()
