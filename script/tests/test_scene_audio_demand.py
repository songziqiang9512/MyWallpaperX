#!/usr/bin/env python3
"""Scene 频谱采集需求与当前进程声源范围门。

采集需求必须由「执行目录里是否真的存在 audio consumer」决定，而不是 project 的
`supportsaudioprocessing` 声明——45 样本中后者为 true 的 12 个与真正带 audio
声明的样本互有出入，按它采集会让没有任何 consumer 的壁纸也占用系统音频权限。
已准入的 Sound 只是声源，不是频谱 consumer；只有 consumer 真值与 Sound binding
同时存在时，采集范围才包含当前进程输出。
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DEMAND_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+AudioDemand.swift"
HOST_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
AUDIO_SPECTRUM_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift"
FRAME_DRIVER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
)
SURFACE_TEARDOWN_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfaceTeardown.swift"
)
FRAME_CONTEXT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneFrameContext.swift"
FRAME_PREFLIGHT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
RESOLVED_CAPABILITY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
)


def swift_body(source: str, signature: str) -> str:
    signature_start = source.index(signature)
    body_start = source.index("{", signature_start)
    depth = 0
    for position in range(body_start, len(source)):
        character = source[position]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[body_start + 1:position]
    raise AssertionError(f"unterminated Swift body: {signature}")


class SceneAudioDemandWiringTests(unittest.TestCase):
    def test_demand_is_driven_by_actual_consumers(self) -> None:
        source = DEMAND_SOURCE.read_text(encoding="utf-8")
        capability = RESOLVED_CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("$0.variants.hasAudioSpectrumConsumer", capability)
        self.assertNotIn("workshopAudioBars", capability)
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.hasAudioSpectrumConsumer",
            source,
        )
        self.assertIn("hasParticleAudioConsumer", source)
        self.assertNotIn(
            "supportsAudioProcessing",
            source,
            "project 级声明不是 consumer 信号",
        )


    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_compiled_activation_demand_transitions_are_atomic(self) -> None:
        """Run the production host demand helper through rebuild transitions."""
        harness = r'''
import Foundation

struct SceneResolvedMaterialExecutionCapabilityCatalog {
    let hasAudioSpectrumConsumer: Bool
}

struct StubScriptProgram {
    let hasAudioConsumers: Bool
}

struct StubSoundProgram {
    let bindings: [Int]
}

struct SceneDesktopWallpaperLaunchContext {
    let resolvedMaterialExecutionCapabilities:
        SceneResolvedMaterialExecutionCapabilityCatalog
    let propertyVectorScriptProgram: StubScriptProgram
    let sceneScriptScalarProgram: StubScriptProgram
    let sceneScriptStringProgram: StubScriptProgram
    let sceneScriptCursorProgram: StubScriptProgram
    let soundPlaybackProgram: StubSoundProgram

    init(
        material: Bool = false,
        script: Bool = false,
        sound: Bool = false
    ) {
        resolvedMaterialExecutionCapabilities = .init(
            hasAudioSpectrumConsumer: material
        )
        propertyVectorScriptProgram = .init(hasAudioConsumers: script)
        sceneScriptScalarProgram = .init(hasAudioConsumers: false)
        sceneScriptStringProgram = .init(hasAudioConsumers: false)
        sceneScriptCursorProgram = .init(hasAudioConsumers: false)
        soundPlaybackProgram = .init(bindings: sound ? [1] : [])
    }
}

final class SceneAudioSpectrumInbox {
    static let shared = SceneAudioSpectrumInbox()

    struct Update: Equatable {
        let demanded: Bool
        let includesCurrentProcess: Bool
    }

    private(set) var current = Update(
        demanded: false,
        includesCurrentProcess: false
    )
    private(set) var updates: [Update] = []

    func reset(demanded: Bool, includesCurrentProcess: Bool = false) {
        current = Update(
            demanded: demanded,
            includesCurrentProcess: demanded && includesCurrentProcess
        )
        updates = []
    }

    func setDemand(
        _ demanded: Bool,
        requiresCurrentProcessAudioCapture: Bool
    ) {
        let requested = Update(
            demanded: demanded,
            includesCurrentProcess:
                demanded && requiresCurrentProcessAudioCapture
        )
        guard requested != current else { return }
        current = requested
        updates.append(requested)
    }
}

final class SceneDesktopWallpaperSession {
    var audioDemand = (spectrum: false, currentProcess: false)
    var onAudioDemandChanged: (() -> Void)?
    init() {
        onAudioDemandChanged = { [unowned self] in
            SceneAudioSpectrumInbox.shared.setDemand(audioDemand.spectrum, requiresCurrentProcessAudioCapture: audioDemand.currentProcess)
        }
    }
    var rebuildSucceeds = true
    var resolvedParticleConsumer = false
    private(set) var rebuildCalls = 0
    private(set) var stopCalls = 0
    var context: SceneDesktopWallpaperLaunchContext!

    func rebuildSurfaces() -> Bool {
        rebuildCalls += 1
        guard rebuildSucceeds else { return false }
        updateAudioSpectrumDemand(
            context,
            hasParticleAudioConsumer: resolvedParticleConsumer
        )
        return true
    }

    func stop() {
        stopCalls += 1
        SceneAudioSpectrumInbox.shared.setDemand(
            false,
            requiresCurrentProcessAudioCapture: false
        )
    }
}

@main
enum AudioDemandTransitionHarness {
    static func main() {
        let host = SceneDesktopWallpaperSession()
        let inbox = SceneAudioSpectrumInbox.shared
        let particleOnly = SceneDesktopWallpaperLaunchContext()

        inbox.reset(demanded: true)
        host.context = particleOnly
        host.resolvedParticleConsumer = true
        precondition(host.rebuildSurfacesReconcilingAudioDemand(
            particleOnly,
            rebuild: host.rebuildSurfaces,
            revokeLaunch: host.stop
        ))
        precondition(inbox.current.demanded)
        precondition(inbox.updates.isEmpty)
        precondition(host.rebuildCalls == 1)
        precondition(host.stopCalls == 0)

        inbox.reset(demanded: true)
        let noConsumerHost = SceneDesktopWallpaperSession()
        noConsumerHost.context = particleOnly
        precondition(noConsumerHost.rebuildSurfacesReconcilingAudioDemand(
            particleOnly,
            rebuild: noConsumerHost.rebuildSurfaces,
            revokeLaunch: noConsumerHost.stop
        ))
        precondition(!inbox.current.demanded)
        precondition(inbox.updates == [.init(
            demanded: false,
            includesCurrentProcess: false
        )])
        precondition(noConsumerHost.rebuildCalls == 1)
        precondition(noConsumerHost.stopCalls == 0)

        inbox.reset(demanded: false)
        let initialParticleHost = SceneDesktopWallpaperSession()
        initialParticleHost.context = particleOnly
        initialParticleHost.resolvedParticleConsumer = true
        precondition(initialParticleHost.rebuildSurfacesReconcilingAudioDemand(
            particleOnly,
            rebuild: initialParticleHost.rebuildSurfaces,
            revokeLaunch: initialParticleHost.stop
        ))
        precondition(inbox.current.demanded)
        precondition(inbox.updates == [.init(
            demanded: true,
            includesCurrentProcess: false
        )])

        inbox.reset(demanded: false)
        let materialAndSound = SceneDesktopWallpaperLaunchContext(
            material: true,
            sound: true
        )
        let knownConsumerHost = SceneDesktopWallpaperSession()
        knownConsumerHost.context = materialAndSound
        precondition(knownConsumerHost.rebuildSurfacesReconcilingAudioDemand(
            materialAndSound,
            rebuild: knownConsumerHost.rebuildSurfaces,
            revokeLaunch: knownConsumerHost.stop
        ))
        precondition(inbox.current.demanded)
        precondition(inbox.current.includesCurrentProcess)
        precondition(inbox.updates == [.init(
            demanded: true,
            includesCurrentProcess: true
        )])

        inbox.reset(demanded: true, includesCurrentProcess: true)
        let failedHost = SceneDesktopWallpaperSession()
        failedHost.context = particleOnly
        failedHost.rebuildSucceeds = false
        precondition(!failedHost.rebuildSurfacesReconcilingAudioDemand(
            particleOnly,
            rebuild: failedHost.rebuildSurfaces,
            revokeLaunch: failedHost.stop
        ))
        precondition(!inbox.current.demanded)
        precondition(inbox.updates == [.init(
            demanded: false,
            includesCurrentProcess: false
        )])
        precondition(failedHost.rebuildCalls == 1)
        precondition(failedHost.stopCalls == 1)

        print("audio-demand-transition-ok")
    }
}
'''
        with tempfile.TemporaryDirectory(
            prefix="scene-audio-demand-transition-"
        ) as temp:
            temp_path = Path(temp)
            harness_path = temp_path / "AudioDemandTransitionHarness.swift"
            executable_path = temp_path / "AudioDemandTransitionHarness"
            harness_path.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    shutil.which("swiftc") or "swiftc",
                    str(DEMAND_SOURCE),
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                compile_result.stdout + compile_result.stderr,
            )
            run_result = subprocess.run(
                [str(executable_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                run_result.returncode,
                0,
                run_result.stdout + run_result.stderr,
            )
            self.assertEqual(
                run_result.stdout.strip(),
                "audio-demand-transition-ok",
            )


    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_compiled_sound_scope_requires_consumer_and_binding(self) -> None:
        """Run the production inbox policy through all consumer/source pairs."""
        harness = r'''
@main
enum AudioCaptureDemandHarness {
    static func main() {
        let checks: [(String, Bool, Bool, Bool, Bool)] = [
            ("neither", false, false, false, false),
            ("sound-only", false, true, false, false),
            ("consumer-only", true, false, true, false),
            ("consumer-and-sound", true, true, true, true),
        ]

        for (name, hasConsumer, hasSoundBinding, expectedDemand, expectedScope)
            in checks {
            let inbox = SceneAudioSpectrumInbox()
            inbox.setDemand(
                hasConsumer,
                requiresCurrentProcessAudioCapture: hasSoundBinding
            )
            let demand = inbox.captureDemand
            guard demand.requiresSpectrum == expectedDemand,
                  demand.includesCurrentProcessOutput == expectedScope else {
                fatalError(
                    "\(name): got demand=\(demand.requiresSpectrum) "
                        + "scope=\(demand.includesCurrentProcessOutput)"
                )
            }
        }
        print("audio-capture-demand-ok")
    }
}
'''
        with tempfile.TemporaryDirectory(
            prefix="scene-audio-capture-demand-"
        ) as temp:
            temp_path = Path(temp)
            harness_path = temp_path / "AudioCaptureDemandHarness.swift"
            executable_path = temp_path / "AudioCaptureDemandHarness"
            harness_path.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    shutil.which("swiftc") or "swiftc",
                    str(AUDIO_SPECTRUM_SOURCE),
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                compile_result.stdout + compile_result.stderr,
            )
            run_result = subprocess.run(
                [str(executable_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                run_result.returncode,
                0,
                run_result.stdout + run_result.stderr,
            )
            self.assertEqual(
                run_result.stdout.strip(),
                "audio-capture-demand-ok",
            )

    def test_host_samples_one_spectrum_per_frame_for_all_surfaces(self) -> None:
        source = (
            HOST_SOURCE.read_text(encoding="utf-8")
            + FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        )
        self.assertIn(
            "let audioSpectrumFrame = SceneAudioSpectrumInbox.shared.prepareFrame()",
            source,
        )
        self.assertIn("let audioSpectrum = audioSpectrumFrame.snapshot", source)
        # 采样必须在 surface 循环之外：频谱是 host-shared 输入，
        # 同一帧内所有屏幕必须看到同一份数据。
        sample_index = source.index(
            "let audioSpectrumFrame = SceneAudioSpectrumInbox"
        )
        loop_index = source.index("for (displayID, surface) in surfaces", sample_index)
        self.assertLess(
            sample_index,
            loop_index,
            "频谱必须每帧采样一次并广播，不能逐 surface 各取一次",
        )

    def test_spectrum_reaches_the_unified_executor_inputs(self) -> None:
        self.assertIn("let audioSpectrum: SceneAudioSpectrumSnapshot", FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8"))
        frame_preflight = FRAME_PREFLIGHT_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "audioSpectrum: frameContext.audioSpectrum",
            frame_preflight,
            "统一 GraphExecutor 的 frame inputs 必须收到同一帧频谱",
        )

    def test_unified_program_audio_consumer_source_contract(self) -> None:
        source = RESOLVED_CAPABILITY_SOURCE.read_text(encoding="utf-8")
        body = swift_body(source, "var hasAudioSpectrumConsumer: Bool")
        self.assertIn("case .resolved(_, let materials, _):", body)
        self.assertIn("$0.variants.hasAudioSpectrumConsumer", body)
        self.assertNotIn("case .dedicated:", body)
        self.assertNotIn("workshopAudioBars", body)

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
    def test_compiled_unified_program_audio_consumer_truth_table(self) -> None:
        """Compile the production property body against a minimal typed catalog."""
        source = RESOLVED_CAPABILITY_SOURCE.read_text(encoding="utf-8")
        body = swift_body(source, "var hasAudioSpectrumConsumer: Bool")
        harness = """
struct VariantCapabilities {
    let hasAudioSpectrumConsumer: Bool
}

struct MaterialCapability {
    let variants: VariantCapabilities
}

enum StageCapability {
    case resolved(Int, [String: MaterialCapability], Int?)
    case visualFailurePassthrough
    case initiallyInactivePassthrough
}

struct LayerCapability {
    let stages: [StageCapability]
}

struct Catalog {
    let capabilitiesByLayerID: [Int: LayerCapability]

    var hasAudioSpectrumConsumer: Bool {
""" + body + """
    }
}

func demandsAudio(_ stage: StageCapability) -> Bool {
    Catalog(
        capabilitiesByLayerID: [1: LayerCapability(stages: [stage])]
    ).hasAudioSpectrumConsumer
}

@main
enum AudioDemandHarness {
    static func main() {
        let checks: [(String, Bool, Bool)] = [
            (
                "resolved-positive",
                demandsAudio(.resolved(
                    1,
                    ["material": MaterialCapability(
                        variants: VariantCapabilities(
                            hasAudioSpectrumConsumer: true
                        )
                    )],
                    nil
                )),
                true
            ),
            (
                "resolved-negative",
                demandsAudio(.resolved(
                    1,
                    ["material": MaterialCapability(
                        variants: VariantCapabilities(
                            hasAudioSpectrumConsumer: false
                        )
                    )],
                    nil
                )),
                false
            )
        ]

        for (name, actual, expected) in checks where actual != expected {
            fatalError("\\(name): expected \\(expected), got \\(actual)")
        }
        if Catalog(capabilitiesByLayerID: [:]).hasAudioSpectrumConsumer {
            fatalError("empty catalog must not demand audio")
        }
        print("audio-demand-ok")
    }
}
"""
        with tempfile.TemporaryDirectory(prefix="scene-audio-demand-") as temp:
            temp_path = Path(temp)
            harness_path = temp_path / "AudioDemandHarness.swift"
            executable_path = temp_path / "AudioDemandHarness"
            harness_path.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    shutil.which("swiftc") or "swiftc",
                    "-parse-as-library",
                    str(harness_path),
                    "-o",
                    str(executable_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                compile_result.stdout + compile_result.stderr,
            )
            run_result = subprocess.run(
                [str(executable_path)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(
                run_result.returncode,
                0,
                run_result.stdout + run_result.stderr,
            )
            self.assertEqual(run_result.stdout.strip(), "audio-demand-ok")


if __name__ == "__main__":
    unittest.main()
