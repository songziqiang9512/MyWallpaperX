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
DEMAND_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+AudioDemand.swift"
HOST_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
AUDIO_SPECTRUM_SOURCE = SCENE_ROOT / "Runtime/SceneAudioSpectrum.swift"
FRAME_DRIVER_SOURCE = (
    SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
FRAME_CONTEXT_SOURCE = SCENE_ROOT / "Runtime/SceneFrameContext.swift"
FRAME_PREFLIGHT_SOURCE = (
    SCENE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
)
AUDIO_ADMISSION_SOURCE = SCENE_ROOT / "RenderGraph/SceneAudioResponseAdmission.swift"
RESOLVED_CAPABILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift"
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

    def test_helper_combines_consumer_truth_with_sound_capture_scope(self) -> None:
        source = DEMAND_SOURCE.read_text(encoding="utf-8")
        update = swift_body(source, "func updateAudioSpectrumDemand(")
        set_demand_index = update.index(
            "SceneAudioSpectrumInbox.shared.setDemand("
        )
        consumer_truth = update[:set_demand_index]
        self.assertIn(
            "let demandsSpectrum = Self.requiresAudioSpectrum(",
            consumer_truth,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities:",
            consumer_truth,
        )
        self.assertIn("hasParticleAudioConsumer", consumer_truth)
        self.assertNotIn(
            "soundPlaybackProgram",
            consumer_truth,
            "Sound 是声源而不是 consumer，不得单独开启频谱",
        )
        self.assertRegex(
            update[set_demand_index:],
            re.compile(
                r"SceneAudioSpectrumInbox\.shared\.setDemand\(\s*"
                r"demandsSpectrum,\s*"
                r"requiresCurrentProcessAudioCapture:\s*"
                r"!context\.soundPlaybackProgram\.bindings\.isEmpty\s*\)"
            ),
            "consumer 真值决定需求，非空 Sound bindings 只扩大声源范围",
        )

    def test_host_declares_demand_through_helper_before_rebuild(self) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        activate = swift_body(
            host,
            "func activate(_ context: SceneDesktopWallpaperLaunchContext) throws",
        )
        demand_index = activate.index(
            "updateAudioSpectrumDemand(context, hasParticleAudioConsumer: false)"
        )
        rebuild_index = activate.index("guard rebuildSurfaces(")
        self.assertNotIn("SceneAudioSpectrumInbox.shared.setDemand(", activate)
        self.assertLess(
            demand_index,
            rebuild_index,
            "launch 时必须在创建 surface 前经唯一 helper 声明需求",
        )
        self.assertIn("resetClock: true", activate[rebuild_index:])
        self.assertIn("teardownReason: teardownReason", activate[rebuild_index:])

    def test_teardown_revokes_but_surface_reconciliation_preserves_demand(
        self,
    ) -> None:
        host = HOST_SOURCE.read_text(encoding="utf-8")
        frame_driver = FRAME_DRIVER_SOURCE.read_text(encoding="utf-8")
        teardown = swift_body(frame_driver, "func teardownSurfaces(")
        revoke_index = teardown.index(
            "SceneAudioSpectrumInbox.shared.setDemand(false)"
        )
        clear_context_index = teardown.rfind(
            "if clearContext {", 0, revoke_index
        )
        self.assertGreaterEqual(
            clear_context_index,
            0,
            "surface-only rebuild must keep the Scene audio demand alive",
        )
        clear_context = swift_body(
            teardown[clear_context_index:], "if clearContext {"
        )
        self.assertIn(
            "SceneAudioSpectrumInbox.shared.setDemand(false)", clear_context,
            "teardown 必须撤销需求，否则停止播放后仍在采集",
        )
        rebuild = swift_body(host, "private func rebuildSurfaces(")
        self.assertIn("teardownSurfaces(clearContext: false", rebuild)
        self.assertRegex(
            rebuild,
            re.compile(
                r"updateAudioSpectrumDemand\(\s*launchContext,\s*"
                r"hasParticleAudioConsumer:\s*surfaces\.values\.contains\s*"
                r"\{\s*\$0\.metalView\.hasParticleAudioConsumer\s*\}\s*\)"
            ),
            "particle graph 只有在 surface 装载并确认 bounded consumer 后才声明需求",
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
        self.assertIn("let audioSpectrum = SceneAudioSpectrumInbox.shared.latest()", source)
        # 采样必须在 surface 循环之外：频谱是 host-shared 输入，
        # 同一帧内所有屏幕必须看到同一份数据。
        sample_index = source.index("let audioSpectrum = SceneAudioSpectrumInbox")
        loop_index = source.index("for surface in surfaces.values", sample_index - 400)
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


class SceneAudioResponseContractTests(unittest.TestCase):
    def test_shared_defaults_remain_parameterized(self) -> None:
        shared = AUDIO_ADMISSION_SOURCE.read_text(encoding="utf-8")
        for pattern in (
            r'values\["frequencymin"\], range: 0 ?\.\.\. ?15, fallback: 0',
            r'values\["frequencymax"\], range: 0 ?\.\.\. ?15, fallback: 1',
            r'values\["audioexponent"\], range: 0 ?\.\.\. ?4, fallback: 1',
            r'values\["audioamount"\], range: 0 ?\.\.\. ?2, fallback: 1',
        ):
            self.assertRegex(shared, pattern)
        self.assertNotIn("SIMD2(0.5, 1)", shared)


if __name__ == "__main__":
    unittest.main()
