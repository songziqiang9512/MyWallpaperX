"""Compile the real diagnostic owners in both configurations, then execute them.

This checks the exclusion boundary rather than assuming an optimized Debug App
represents distribution. Full App playback/IPC still requires runtime evidence.
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


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Diagnostics/ScenePerformanceCounterHub.swift",
    SCENE / "Diagnostics/SceneGPUCensus.swift",
    SCENE / "Diagnostics/SceneSignposts.swift",
    SCENE / "Diagnostics/SceneGPUCompletionTelemetry.swift",
    SCENE / "Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+CompileProfile.swift",
    ROOT / "WallpaperDaemonSources/Daemon/Core/DaemonLogging.swift",
]
HARNESS = r'''
import Foundation
@main enum Probe {
    static func main() {
        var evaluated = false
        daemonLog({ evaluated = true; return "diagnostic payload" }())
        let observation = SceneGPUCompletionTelemetry(phase: "test")
        observation.recordFailure(layerID: 1)
#if DEBUG
        precondition(evaluated)
        let counters = ScenePerformanceCounterHub.shared
        counters.bump(.frameAttempts)
        precondition(counters.snapshot()[.frameAttempts] == 1)
        SceneResolvedMaterialVariantCompileProfile.reset()
        print("debug-observation-pass")
#else
        precondition(!evaluated, "Release must not evaluate a log payload")
        precondition(MemoryLayout<SceneGPUCompletionTelemetry>.size == 0,
                     "Release must not allocate GPU observation state")
        print("release-exclusion-pass")
#endif
    }
}
'''


class ReleaseDiagnosticIsolationTests(unittest.TestCase):
    def test_shared_audio_keeps_real_configuration_without_diagnostic_frame_or_release_readback(self):
        source = ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureDeviceFactory.swift"
        capture = ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureBuffer.swift"
        checks = ROOT / "script/tests/fixtures/SystemAudioDiagnosticBoundaryChecks.swift"
        parent = os.environ.get("MWX_AUDIO_MEDIA_DIAGNOSTIC_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        reports = []
        for debug in (False, True):
            directory = Path(tempfile.mkdtemp(prefix="shared-audio-diagnostic-", dir=parent))
            try:
                copied = directory / source.name
                text = source.read_text()
                for name in ("AudioObjectGetPropertyData", "AudioObjectSetPropertyData"):
                    self.assertRegex(text, rf"\b{name}\b")
                    text = re.sub(rf"\b{name}\b", "fixture" + name, text)
                copied.write_text(text)
                inputs = [source, capture, checks, copied]
                before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
                binary = directory / "check"
                command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                           "-swift-version", "6", "-default-isolation", "MainActor",
                           "-O", "-whole-module-optimization", *(["-D", "DEBUG"] if debug else []),
                           str(capture), str(copied), str(checks), "-module-cache-path",
                           str(directory / "modules"), "-o", str(binary)]
                home = directory / "home"
                home.mkdir()
                environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
                compiled = subprocess.run(command, cwd=ROOT, env=environment,
                                          capture_output=True, text=True, timeout=120)
                (directory / "compile.json").write_text(json.dumps({
                    "command": command, "returncode": compiled.returncode,
                    "stdout": compiled.stdout, "stderr": compiled.stderr, "sourceSHA256": before,
                    "sourceAdaptation": "Only property I/O identifiers redirected; no real device access.",
                }, indent=2))
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                result = subprocess.run([str(binary)], cwd=directory, env=environment,
                                        capture_output=True, text=True, timeout=15)
                after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
                (directory / "result.json").write_text(json.dumps({
                    "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
                    "sourceSHA256Before": before, "sourceSHA256After": after,
                }, indent=2))
                self.assertEqual(before, after)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual("MWX AUDIO CAPTURE: buffer" in result.stderr, debug)
                report = json.loads(result.stdout)
                self.assertEqual(report["debug"], debug)
                reports.append(report)
            finally:
                if not parent:
                    shutil.rmtree(directory)
        self.assertEqual(reports[0]["signedChannels"], reports[1]["signedChannels"])
        for release, debug in zip(reports[0]["propertyRows"], reports[1]["propertyRows"]):
            self.assertEqual(release["name"], debug["name"])
            self.assertEqual(release["requested"], debug["requested"])
            self.assertEqual(release["finalFrames"], debug["finalFrames"])

    def test_system_media_release_has_no_log_state_calls_or_interpolation_before_optimization(self):
        from script.tests import test_scene_system_media_provider as provider
        support, separator, _ = provider.HARNESS.partition("@main struct Main")
        self.assertTrue(separator)
        parent = os.environ.get("MWX_AUDIO_MEDIA_DIAGNOSTIC_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        for debug in (False, True):
            directory = Path(tempfile.mkdtemp(prefix="shared-media-diagnostic-", dir=parent))
            try:
                harness, output = directory / "Support.swift", directory / "diagnostics.sil"
                harness.write_text(support)
                inputs = [*provider.SOURCE_PATHS, harness]
                before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
                command = ["xcrun", "swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
                           "-parse-as-library", "-Onone", "-whole-module-optimization", "-emit-silgen",
                           *(["-D", "DEBUG"] if debug else []), *map(str, inputs),
                           "-module-name", "SharedMediaDiagnosticGate", "-module-cache-path",
                           str(directory / "modules"), "-o", str(output)]
                compiled = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
                (directory / "compile.json").write_text(json.dumps({
                    "command": command, "returncode": compiled.returncode,
                    "stdout": compiled.stdout, "stderr": compiled.stderr,
                    "sourceSHA256Before": before, "sourceSHA256After": after,
                }, indent=2))
                self.assertEqual(before, after)
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                sil = output.read_text()
                self.assertIn("sil_stage raw", sil)
                for marker in ["var lastStatus:", "SystemMediaService.report(_:)",
                               "MWX shared media source: source=%@ status=%@",
                               '"authorization-"', '"apple-unavailable-"']:
                    self.assertEqual(marker in sil, debug, marker)
            finally:
                if not parent:
                    shutil.rmtree(directory)

    def compile_and_run(self, debug: bool) -> tuple[str, str]:
        with tempfile.TemporaryDirectory(prefix="mwx-diagnostic-exclusion-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            binary = directory / "probe"
            command = ["xcrun", "swiftc", "-O", "-whole-module-optimization"]
            if debug:
                command += ["-D", "DEBUG"]
            command += ["-module-cache-path", str(directory / "modules")]
            command += [str(path) for path in SOURCES]
            if not debug:
                command += [str(SCENE / "Diagnostics" / name) for name in [
                    "SceneFramePerformanceTelemetry.swift", "SceneEffectExecutionFrameTrace.swift",
                    "SceneEffectExecutionTelemetry.swift", "SceneGraphExecutionTelemetry.swift",
                ]]
            command += [str(harness), "-o", str(binary)]
            compiled = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            executed = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
            symbols = subprocess.run(
                ["nm", str(binary)], capture_output=True, text=True, check=True
            ).stdout
            return executed.stdout + executed.stderr, symbols

    def test_release_excludes_counter_signpost_and_gpu_observation_work(self):
        output, symbols = self.compile_and_run(False)
        self.assertIn("release-exclusion-pass", output)
        self.assertNotIn("diagnostic payload", output)
        for owner in ["ScenePerformanceCounterHub", "SceneGPUCensus", "SceneSignpost",
                      "SceneResolvedMaterialVariantCompileProfile", "SceneDiagnosticsBuilder",
                      "recordRouteTransition", "recordParticleSubmission"]:
            self.assertNotIn(owner, symbols, owner)
        self.assertNotIn("NSLock", symbols)
        self.assertNotIn("os_signpost", symbols)

    def test_debug_keeps_real_counters_and_lazy_log_delivery(self):
        output, _ = self.compile_and_run(True)
        self.assertIn("debug-observation-pass", output)
        self.assertIn("diagnostic payload", output)

    def test_sound_playing_observer_is_debug_only_without_changing_player_state(self):
        from script.tests.test_scene_sound_playback_program import REGISTRY_SWIFT_SOURCES, STUB_SOURCE
        _, separator, carriers = STUB_SOURCE.partition("struct SceneScriptMediaPlaybackCommand")
        self.assertTrue(separator)
        harness = r'''
        import AVFoundation
        import Foundation
        @main enum Check {
            static func main() {
                let program = SceneSoundPlaybackProgram(bindings: [.init(
                    layerID: 7, resources: [.init(file: nil, displayPath: "selected-unavailable.wav")],
                    playbackMode: .single, startsSilent: true, authoredVolume: 0.5,
                    volumePropertyKey: nil)], diagnostics: [])
                let registry = SceneSoundPlaybackRegistry(program: program, epoch: 9)
                registry.start(paused: true, userValues: [:])
                precondition(registry.sceneScriptSnapshots() == [7: false])
                let sources = Mirror(reflecting: registry).children.first { $0.label == "sources" }!.value
                let pair = Mirror(reflecting: sources).children.first!.value
                let source = Array(Mirror(reflecting: pair).children)[1].value
                let observation = Mirror(reflecting: source).children.first { $0.label == "timeControlObservation" }
        #if DEBUG
                precondition(observation != nil && !Mirror(reflecting: observation!.value).children.isEmpty,
                             "Debug must install its actual playing-log KVO token")
        #else
                precondition(observation == nil, "Release must not store or install a log-only KVO token")
        #endif
                registry.stop()
                precondition(registry.sceneScriptSnapshots().isEmpty)
                print("sound-observation-isolation-pass")
            }
        }
        '''
        for debug in (False, True):
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-sound-observation-") as raw:
                directory = Path(raw)
                stub, main, binary = directory / "Carriers.swift", directory / "Harness.swift", directory / "check"
                stub.write_text("import AVFoundation\nimport Foundation\n" + separator + carriers)
                main.write_text(harness)
                flags = ["-D", "DEBUG"] if debug else []
                compiled = subprocess.run(
                    ["xcrun", "swiftc", "-parse-as-library", "-O", *flags, *map(str, REGISTRY_SWIFT_SOURCES),
                     str(stub), str(main), "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                    capture_output=True, text=True, timeout=90,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
                self.assertIn("sound-observation-isolation-pass", executed.stdout)

    def test_web_media_logging_source_and_observers_are_debug_only(self):
        from script.tests.test_web_audio_demand import property_replay_behavior_script
        from script.tests.test_web_response_transformer import remote_stylesheet_behavior_script
        host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
        sources = [host / ("DedicatedWebWallpaperHostCompatibilityScript+" + part + ".swift")
                   for part in ["BootstrapFoundation", "MediaObservers", "InteractionAndRuntimeMedia",
                                "InteractionAndRuntimeLogging", "HostBridge", "Scheduling", "RemoteStylesheets"]]
        harness = r'''
        import Foundation
        @main enum Check {
            static func main() {
                let foundation = webCompatibilityScriptBootstrapFoundation
                let media = webCompatibilityScriptMediaObservers
                let interaction = webCompatibilityScriptInteractionAndRuntimeMedia
                let logging = webCompatibilityScriptInteractionAndRuntimeLogging
                let properties = webCompatibilityScriptHostBridge
        #if DEBUG
                precondition(foundation.contains("const lastLogTimes = new Map()"))
                precondition(logging.contains("const serializedConsoleArgs"))
                precondition(logging.contains("window.addEventListener('unhandledrejection'"))
                precondition(logging.contains("__mwxXHRLoggingInstalled"))
                precondition(media.contains("first-media-node-found"))
                precondition(media.contains("postMediaState('media.initial'"))
                precondition(properties.contains("reportedSkips"))
                precondition(properties.contains("let appliedCount = 0"))
                precondition(properties.contains("properties.applied.partial"))
                precondition(foundation.contains("let failedAudioListeners;"))
                precondition(properties.contains("audio.spectrum.dispatched"))
                precondition(properties.contains("audio.spectrum.changed"))
                precondition(properties.contains("audio.listener.error"))
                precondition(media.components(separatedBy: "node.addEventListener('playing'").count == 2,
                             "Debug keeps one media event observer")
        #else
                precondition(foundation.contains("const hostLogger = undefined;"))
                precondition(!foundation.contains("lastLogTimes"))
                precondition(!foundation.contains("noisyTypeIntervals"))
                for audioOnly in ["failedAudioListeners", "hasLoggedAudioSpectrumDelivery",
                                  "hasLoggedAudioSpectrumChange", "firstDeliveredAudioSpectrum"] {
                    precondition(!foundation.contains(audioOnly) && !properties.contains(audioOnly),
                                 "Release contains audio log bookkeeping")
                }
                for audioOnly in ["audio.spectrum.dispatched", "audio.spectrum.changed", "audio.listener.error"] {
                    precondition(!properties.contains(audioOnly), "Release contains pure audio logging")
                }
                for consoleOnly in ["serializedConsoleArgs", "isTransientLoaderReferenceError",
                                    "window.addEventListener('unhandledrejection'", "console[name] ="] {
                    precondition(!logging.contains(consoleOnly), "Release contains unused console logging")
                }
                precondition(!logging.contains("__mwxXHRLoggingInstalled"))
                precondition(!logging.contains("this.addEventListener('error'"))
                precondition(!logging.contains("this.addEventListener('loadend'"))
                for loggingOnly in ["first-media-node-found", "mediaStateSummary", "postMediaState",
                                    "node.addEventListener('playing'", "media.initial"] {
                    precondition(!media.contains(loggingOnly), "Release contains unused media logging")
                }
                for loggingOnly in ["reportedSkips", "myWallpaperReportSkippedProperty", "appliedCount",
                                    "skippedCount", "isolatedResult", "properties.applied.partial"] {
                    precondition(!properties.contains(loggingOnly), "Release contains property log bookkeeping")
                }
        #endif
                for playbackConsumer in ["const networkRequestHandler", "const hostNetworkRequest",
                                         "const base64ToUint8Array", "XMLHttpRequest.prototype.send ="] {
                    precondition(logging.contains(playbackConsumer), "real network compatibility was stripped")
                }
                precondition(foundation.contains("window.wallpaperRegisterAudioStream"))
                precondition(foundation.contains("window.wallpaperRegisterPropertyListener"))
                precondition(!interaction.contains("installWallpaperMediaRuntimeLogging"))
                precondition(!interaction.contains("media.event"))
                precondition(media.contains("__mwxOriginalMediaPause"))
                precondition(media.contains("node.volume = hostVolume"))
                precondition(media.contains("node.playbackRate = hostPlaybackRate"))
                precondition(media.contains("attachWallpaperMediaNodesFromRoot"))
                precondition(interaction.contains("originalPlay.apply(this, args)"))
                precondition(properties.contains("callback.call(listener, singleProperty)"))
                precondition(properties.contains("myWallpaperSchedulePendingPropertyApply(80)"))
                precondition(properties.contains("myWallpaperColorArrayCompatibleProperty(value)"))
                print("foundation-script=" + String(data: try! JSONEncoder().encode(foundation), encoding: .utf8)!)
                print("xhr-script=" + String(data: try! JSONEncoder().encode(logging), encoding: .utf8)!)
                print("property-script=" + String(data: try! JSONEncoder().encode(properties), encoding: .utf8)!)
                print("scheduling-script=" + String(data: try! JSONEncoder().encode(webCompatibilityScriptScheduling), encoding: .utf8)!)
                print("media-script-isolation-pass")
                print("remote-script=" + String(data: try! JSONEncoder().encode(webRemoteStylesheetCompatibilityScript), encoding: .utf8)!)
            }
        }
        '''
        for debug in [False, True]:
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-web-media-exclusion-") as raw:
                directory = Path(raw)
                swift, binary = directory / "Harness.swift", directory / "probe"
                swift.write_text(harness)
                flags = ["-D", "DEBUG"] if debug else []
                compiled = subprocess.run(
                    ["xcrun", "swiftc", "-parse-as-library", "-O", *flags,
                     *map(str, sources), str(swift), "-o", str(binary)],
                    capture_output=True, text=True, timeout=90,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
                self.assertIn("media-script-isolation-pass", executed.stdout)
                remote = json.loads(next(line.removeprefix("remote-script=") for line in executed.stdout.splitlines()
                                         if line.startswith("remote-script=")))
                observed_remote = subprocess.run(
                    ["node", "-e", remote_stylesheet_behavior_script(remote, debug)],
                    capture_output=True, text=True, timeout=15,
                )
                self.assertEqual(observed_remote.returncode, 0, observed_remote.stdout + observed_remote.stderr)
                self.assertIn("remote-stylesheet-state-machine-pass", observed_remote.stdout)
                logging = json.loads(next(line.removeprefix("xhr-script=") for line in executed.stdout.splitlines()
                                          if line.startswith("xhr-script=")))
                foundation = json.loads(next(line.removeprefix("foundation-script=") for line in executed.stdout.splitlines()
                                             if line.startswith("foundation-script=")))
                properties = json.loads(next(line.removeprefix("property-script=") for line in executed.stdout.splitlines()
                                             if line.startswith("property-script=")))
                scheduling = json.loads(next(line.removeprefix("scheduling-script=") for line in executed.stdout.splitlines()
                                             if line.startswith("scheduling-script=")))
                audio_body = properties[properties.index("  window.__myWallpaperPushAudioSpectrum ="):
                                        properties.index("  window.__myWallpaperSetGlobalVolume =")]
                audio_state = "\n".join(line for line in foundation.splitlines() if any(name in line for name in (
                    "let failedAudioListeners;", "let hasLoggedAudioSpectrumDelivery", "let hasLoggedAudioSpectrumChange",
                    "let firstDeliveredAudioSpectrum;")))
                properties = properties[properties.index("  window.__myWallpaperStablePropertySignature ="):
                                        properties.index("  window.__myWallpaperApplyGeneralProperties =")]
                replay = subprocess.run(["node", "-e", property_replay_behavior_script(properties, scheduling, debug)],
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(replay.returncode, 0, replay.stdout + replay.stderr)
                self.assertIn("web-pending-property-replay-pass", replay.stdout)
                logger = foundation[foundation.index("  const hostLogger ="):foundation.index("  resumeAudioContexts();")]
                audio_fixture = r"""
                const reports=[], delivered=[], events=[];
                const audioListeners=[()=>{throw Error('author-listener-error');}, value=>delivered.push(value.slice())];
                const window={webkit:{messageHandlers:{wallpaperHostLog:{postMessage:value=>reports.push(value)}}},
                  addEventListener(){}, dispatchEvent(event){events.push(event.detail.slice());}};
                class CustomEvent { constructor(type, options){this.type=type;this.detail=options.detail;} }
                """
                audio_fixture += logger + "\n" + audio_state + "\n" + audio_body + r"""
                window.__myWallpaperPushAudioSpectrum([0.2,-0.4,NaN,Infinity]);
                window.__myWallpaperPushAudioSpectrum([0.9,0.8,0.7,0.6]);
                window.__myWallpaperPushAudioSpectrum([0.9,0.8,0.7,0.6]);
                if(delivered.length!==3 || JSON.stringify(delivered)!==JSON.stringify(events))
                  throw Error('author event/callback delivery changed');
                if(JSON.stringify(delivered[0])!=='[0.2,0,0,0]') throw Error('audio normalization changed');
                const types=reports.map(value=>value.type);
                """
                if debug:
                    audio_fixture += "\nfor(const type of ['audio.spectrum.dispatched','audio.spectrum.changed','audio.listener.error']) if(types.filter(x=>x===type).length!==1) throw Error('Debug diagnostic dedup changed: '+type);\n"
                else:
                    audio_fixture += "\nif(types.length) throw Error('Release emitted audio diagnostics');\n"
                audio_fixture += "process.stdout.write('web-audio-delivery-isolation-pass');"
                audio_result = subprocess.run(["node", "-e", audio_fixture], capture_output=True, text=True, timeout=15)
                self.assertEqual(audio_result.returncode, 0, audio_result.stdout + audio_result.stderr)
                self.assertIn("web-audio-delivery-isolation-pass", audio_result.stdout)
                console_logging = logging[:logging.index("  const networkRequestHandler =")]
                # These are actual Debug/Release Swift-composed JS values. The
                # fixture controls native console/message sinks, not installers.
                console_fixture = r"""
                const reports=[], nativeCalls=[], listeners={};
                const console={warn(...args){nativeCalls.push(['warn',args.length]);},
                               error(...args){nativeCalls.push(['error',args.length]);}};
                const window={webkit:{messageHandlers:{wallpaperHostLog:{postMessage:value=>reports.push(value)}}},
                              addEventListener(type, callback){(listeners[type] ||= []).push(callback);}};
                """
                console_fixture += logger + "\n" + console_logging + r"""
                console.warn('author-warning'); console.error(new Error('author-error'));
                for(const callback of listeners.error || []) callback({target:window,message:'page-error',filename:'page.js',lineno:7,colno:2});
                for(const callback of listeners.unhandledrejection || []) callback({reason:'author-rejection'});
                process.stdout.write(JSON.stringify({active:typeof hostLogger !== 'undefined',nativeCalls,
                  listeners:Object.keys(listeners),reports:reports.map(report=>report.type)}));
                """
                console_result = subprocess.run(["node", "-e", console_fixture], capture_output=True, text=True, timeout=15)
                self.assertEqual(console_result.returncode, 0, console_result.stderr)
                console_state = json.loads(console_result.stdout)
                self.assertEqual(console_state["nativeCalls"], [["warn", 1], ["error", 1]])
                self.assertEqual(console_state["active"], debug)
                self.assertEqual(console_state["listeners"], ["error", "unhandledrejection"] if debug else [])
                self.assertEqual(console_state["reports"], ["console.warn", "console.error", "window.error", "promise.rejection"] if debug else [])
                # Execute the actual compiled wrapper with a reusable XHR. The
                # fixture controls transport/events, not the logging installer.
                wrapper = logging[logging.index("  const originalOpen = XMLHttpRequest.prototype.open;"):]
                wrapper = wrapper.split("  // 代理路径下 send 被拦截", 1)[0]
                fixture = r'''
                const logs=[];
                const hostLogger={post:(type,message)=>logs.push({type,message})};
                const canProxyNetworkRequest=()=>false;
                const wallpaperHostReplyReachable=()=>true;
                class XMLHttpRequest {
                  constructor(){this.events={};this.listenerCount=0;this.openCount=0;}
                  addEventListener(type,callback){(this.events[type] ||= []).push(callback);this.listenerCount++;}
                  open(){this.openCount++;this.status=404;return 'native-open';}
                  send(){}
                  fire(type){for(const fn of this.events[type] || []) fn.call(this,{type});}
                }
                '''
                fixture += wrapper + "\nconst request=new XMLHttpRequest();\n"
                fixture += "for(let i=0;i<20;i++){if(request.open('GET','/resource/'+i)!=='native-open') throw Error('native open changed');}\n"
                fixture += "request.fire('error');request.fire('loadend');console.log(JSON.stringify({listeners:request.listenerCount,opens:request.openCount,logs}));"
                observed = subprocess.run(["node", "-e", fixture], capture_output=True, text=True, timeout=15)
                self.assertEqual(observed.returncode, 0, observed.stderr)
                current = json.loads(observed.stdout)
                self.assertEqual(current["opens"], 20)
                self.assertEqual(current["listeners"], 2 if debug else 0)
                self.assertEqual(current["logs"], [
                    {"type": "xhr.error", "message": "GET /resource/19"},
                    {"type": "xhr.status", "message": "GET /resource/19 status=404"},
                ] if debug else [])

    def test_navigation_observation_is_debug_only_and_policy_actions_survive(self):
        from script.tests.test_steam_library_interactions import method
        from script.tests.test_web_compat_parity import source_block
        host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
        navigation = (host / "DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift").read_text()
        types = (host / "WebWallpaperHostTypes.swift").read_text()
        surface = (host / "DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift").read_text()

        def debug_block(source, marker):
            marker_at = source.index(marker)
            start = source.rfind("#if DEBUG\n", 0, marker_at)
            self.assertGreaterEqual(start, 0)
            return source[start:source.index("#endif", marker_at) + len("#endif")]

        declarations = source_block(navigation, "enum NavigationDecision")
        declarations += "\n" + method(navigation, "private func publishNavigationDecision(").replace(
            "private func publishNavigationDecision", "func publishNavigationDecision")
        declarations += "\n" + debug_block(navigation, "private func publishNavigationBlockedToWebView(")
        declarations += "\n" + debug_block(types, "static let webNavigationStateScript")
        injection = debug_block(surface, "source: Self.webNavigationStateScript")
        declarations += "\nfunc installNavigationObservation(in controller: WKUserContentController) {\n" + injection + "\n}\n"
        harness = r'''
        import Foundation
        typealias CGDirectDisplayID = UInt32
        final class WKWebView {
            var scripts: [String] = []
            func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?) {
                scripts.append(script); completionHandler?(nil, nil)
            }
        }
        struct WKUserScript {
            enum InjectionTime { case atDocumentStart }
            let source: String
            let injectionTime: InjectionTime
            let forMainFrameOnly: Bool
        }
        final class WKUserContentController {
            var scripts: [WKUserScript] = []
            func addUserScript(_ script: WKUserScript) { scripts.append(script) }
        }
        final class NSWorkspace {
            static let shared = NSWorkspace()
            var opened: [URL] = []
            func open(_ url: URL) { opened.append(url) }
        }
        enum WebRuntimeDiagnosticEvent { enum Severity { case info } }
        enum WebWallpaperHostSupport {
            static func javaScriptQuotedString(_ value: String) -> String {
                String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
            }
        }
        final class Adapter {
            var diagnosticCount = 0
            func screenID(for view: WKWebView) -> CGDirectDisplayID? { nil }
            func recordDiagnostic(type: String, severity: WebRuntimeDiagnosticEvent.Severity,
                                  message: String, screenID: CGDirectDisplayID?, url: String?) {
                diagnosticCount += 1
            }
        }
        extension Adapter {
        // ACTUAL NAVIGATION
        }
        @main enum Check {
            static func main() {
                let host = Adapter(), view = WKWebView(), controller = WKUserContentController()
                let internalURL = URL(string: "mwx-local://wallpaper/page.html")!
                let externalURL = URL(string: "https://example.com/help")!
                host.installNavigationObservation(in: controller)
                host.publishNavigationDecision(.allow, targetURL: internalURL, webView: view)
                host.publishNavigationDecision(.cancel(reason: "internal_link_cancelled"), targetURL: internalURL, webView: view)
                host.publishNavigationDecision(.handoffExternal(externalURL), targetURL: externalURL, webView: view)
                precondition(NSWorkspace.shared.opened == [externalURL], "cancel/allow must not hand off; external action remains")
        #if DEBUG
                precondition(controller.scripts.count == 1 && view.scripts.count == 2 && host.diagnosticCount == 2)
        #else
                precondition(controller.scripts.isEmpty && view.scripts.isEmpty && host.diagnosticCount == 0,
                             "Release must not inject or evaluate navigation observations")
        #endif
                let script = (controller.scripts.first?.source ?? "") + "\n" + view.scripts.joined(separator: "\n")
                print("navigation-script=" + String(data: try! JSONEncoder().encode(script), encoding: .utf8)!)
                print("navigation-isolation-pass")
            }
        }
        '''
        for debug in [False, True]:
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-web-navigation-exclusion-") as raw:
                directory = Path(raw)
                swift, binary = directory / "Harness.swift", directory / "probe"
                swift.write_text(harness.replace("// ACTUAL NAVIGATION", declarations))
                flags = ["-D", "DEBUG"] if debug else []
                compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O", *flags,
                                           str(swift), "-o", str(binary)], capture_output=True, text=True, timeout=90)
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
                projected = json.loads(next(line.removeprefix("navigation-script=") for line in executed.stdout.splitlines()
                                            if line.startswith("navigation-script=")))
                fixture = "const events=[]; const window={dispatchEvent:e=>events.push(e)}; const CustomEvent=function(type,init){this.type=type;this.detail=init.detail};\n"
                fixture += projected + "\nconsole.log(JSON.stringify({state:window.__mwxNavigationState ?? null,events}));"
                observed = subprocess.run(["node", "-e", fixture], capture_output=True, text=True, timeout=15)
                self.assertEqual(observed.returncode, 0, observed.stderr)
                current = json.loads(observed.stdout)
                if debug:
                    self.assertEqual(current["state"]["blockedCount"], 2)
                    self.assertEqual(current["state"]["lastBlockedReason"], "link_handoff")
                    self.assertEqual(current["state"]["lastBlockedURL"], "https://example.com/help")
                    self.assertEqual(len(current["events"]), 2)
                else:
                    self.assertEqual(current, {"state": None, "events": []})

    def test_web_release_rejects_development_commands(self):
        source = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift").read_text()
        def declaration(signature):
            start = source.index(signature)
            opening = source.index("{", start)
            depth, end = 1, opening + 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end]
        command = declaration("nonisolated enum WebDaemonCommand:")
        stubs = """
        import Foundation
        struct WebDaemonLaunch: Codable {}
        struct WebDaemonMediaSnapshot: Codable {}
        struct WebDaemonActivationRequest: Codable {}
        struct WebDaemonActivationIdentity: Codable {}
        enum WallpaperEngine {
            enum WebWallpaperRuntimeCommand: Codable { case pushAudioSpectrum([Double]) }
        }
        """
        harness = r'''
        @main enum Check {
            static func main() throws {
                let decoder = JSONDecoder()
                let inspect = Data(#"{"inspect":{}}"#.utf8)
                let developmentAccepted = (try? decoder.decode(WebDaemonCommand.self, from: inspect)) != nil
        #if DEBUG
                precondition(developmentAccepted)
        #else
                precondition(!developmentAccepted)
        #endif
                guard case .shutdown = try decoder.decode(WebDaemonCommand.self,
                    from: Data(#"{"shutdown":{}}"#.utf8)) else { fatalError("product command lost") }
                print("protocol-isolation-pass")
            }
        }
        '''
        for debug in [False, True]:
            with self.subTest(debug=debug), tempfile.TemporaryDirectory(prefix="mwx-web-protocol-") as raw:
                directory = Path(raw)
                swift = directory / "Harness.swift"
                swift.write_text(stubs + command + harness)
                binary = directory / "probe"
                flags = ["-D", "DEBUG"] if debug else []
                compiled = subprocess.run(
                    ["xcrun", "swiftc", "-parse-as-library", "-O", *flags, str(swift), "-o", str(binary)],
                    capture_output=True, text=True,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)
                executed = subprocess.run([str(binary)], capture_output=True, text=True)
                self.assertEqual(executed.returncode, 0, executed.stderr)
                self.assertIn("protocol-isolation-pass", executed.stdout)


    def test_release_web_admission_keeps_entry_checks_without_sample_scan(self):
        # Compile the real Release service owner. The leaf doubles supply only
        # record facts; selected-file metadata is real. No descriptor
        # implementation is provided: even the first admission must stay narrow.
        harness = r'''
        import Foundation
        enum Dependency { case none, missing(String) }
        struct SteamWorkshopDownloadRecord {
            var id = "wallpaper"
            var dependencyStatus = Dependency.none
            var dependencyItemID: String?
            var webEntryURL: URL?
            var folderURL: URL
        }
        final class SteamWorkshopService {
            var lastWebPlaybackFailureRecordID: String?
            var lastWebPlaybackFailureMessage: String?
            var lastWebPlaybackFailurePath: String?
        }
        @main enum Check {
            static func main() throws {
                let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                let entry = folder.appendingPathComponent("index.html")
                try Data("<html></html>".utf8).write(to: entry)
                var record = SteamWorkshopDownloadRecord(webEntryURL: entry, folderURL: folder)
                let service = SteamWorkshopService()
                precondition(service.webLaunchEntryIsValid(for: record))
                precondition(service.webLaunchEntryIsValid(for: record))
                // Capture owns declaration/fallback selection. The Release
                // front door checks the selected file without rescanning JSON.
                try Data(#"{"file":"missing.html"}"#.utf8).write(to: folder.appendingPathComponent("project.json"))
                precondition(service.webLaunchEntryIsValid(for: record), "readable selected entry rejected by unrelated declaration")
                record.dependencyItemID = "host"; record.dependencyStatus = .missing("host")
                precondition(service.webLaunchEntryIsValid(for: record), "readable selected entry rejected by dependency metadata")
                record.webEntryURL = nil
                precondition(!service.webLaunchEntryIsValid(for: record), "dependency metadata invented a missing selected entry")
                record.webEntryURL = folder
                precondition(!service.webLaunchEntryIsValid(for: record), "directory admitted as entry")
                record.webEntryURL = entry; try FileManager.default.removeItem(at: entry)
                precondition(!service.webLaunchEntryIsValid(for: record), "deleted file admitted")
                try Data("<html>restored</html>".utf8).write(to: entry)
                precondition(service.webLaunchEntryIsValid(for: record), "restored selected entry retained a stale refusal")
                service.lastWebPlaybackFailureRecordID = record.id
                service.lastWebPlaybackFailureMessage = "playback error"
                precondition(service.webPlaybackFailureMessage(for: record) == "playback error")
                print("release-web-admission-pass")
            }
        }
        '''
        with tempfile.TemporaryDirectory(prefix="mwx-release-web-admission-") as raw:
            directory = Path(raw)
            main = directory / "Harness.swift"; main.write_text(harness)
            binary = directory / "check"
            source = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift"
            compiled = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), str(main),
                                       "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                                      capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary), str(directory)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("release-web-admission-pass", run.stdout)
            symbols = subprocess.run(["nm", str(binary)], capture_output=True, text=True, check=True).stdout
            self.assertNotIn("webValidationReport", symbols)


if __name__ == "__main__":
    unittest.main()
