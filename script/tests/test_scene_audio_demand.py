#!/usr/bin/env python3
"""Scene 频谱采集需求判定门（A2 生命周期段）。

采集需求必须由「执行目录里是否真的存在 audio consumer」决定，而不是 project 的
`supportsaudioprocessing` 声明——45 样本中后者为 true 的 12 个与真正带 audio
声明的样本互有出入，按它采集会让没有任何 consumer 的壁纸也占用系统音频权限。
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DEMAND_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+AudioDemand.swift"
HOST_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
FRAME_DRIVER_SOURCE = (
    SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
)
FRAME_CONTEXT_SOURCE = SCENE_ROOT / "Runtime/SceneFrameContext.swift"
CHAIN_RENDERER_SOURCE = SCENE_ROOT / "RenderGraph/SceneAuthoredEffectChainRenderer.swift"
COMPOSITOR_SOURCE = SCENE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
SHAKE_PIPELINE_SOURCE = SCENE_ROOT / "Effects/SceneShakePipeline.swift"
SHAKE_PLANNER_AUDIO_SOURCE = SCENE_ROOT / "RenderGraph/SceneAuthoredShakePlanner+Audio.swift"
AUDIO_ADMISSION_SOURCE = SCENE_ROOT / "RenderGraph/SceneAudioResponseAdmission.swift"
PULSE_CONSTANTS_SOURCE = (
    SCENE_ROOT / "RenderGraph/SceneAuthoredPulsePlanner+Constants.swift"
)


class SceneAudioDemandWiringTests(unittest.TestCase):
    def test_demand_is_driven_by_actual_consumers(self) -> None:
        source = DEMAND_SOURCE.read_text(encoding="utf-8")
        self.assertIn("$0.shake?.audio != nil", source)
        self.assertIn("$0.workshopAudioBars != nil", source)
        self.assertIn("$0.workshopAudioHueShift != nil", source)
        self.assertNotIn(
            "supportsAudioProcessing",
            source,
            "project 级声明不是 consumer 信号",
        )

    def test_host_claims_and_revokes_demand_across_the_lifecycle(self) -> None:
        source = HOST_SOURCE.read_text(encoding="utf-8")
        activate_index = source.index(
            "func activate(_ context: SceneDesktopWallpaperLaunchContext) throws"
        )
        demand_index = source.index(
            "SceneAudioSpectrumInbox.shared.setDemand(Self.requiresAudioSpectrum(",
            activate_index,
        )
        self.assertIn("in: context.authoredEffectCatalog", source[demand_index:])
        self.assertLess(
            demand_index,
            source.index("guard rebuildSurfaces(resetClock: true)", activate_index),
            "launch 时必须在创建 surface 前按 consumer 存在性声明需求",
        )
        self.assertIn(
            "SceneAudioSpectrumInbox.shared.setDemand(false)",
            source,
            "teardown 必须撤销需求，否则停止播放后仍在采集",
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

    def test_spectrum_reaches_the_shake_backend(self) -> None:
        self.assertIn("let audioSpectrum: SceneAudioSpectrumSnapshot", FRAME_CONTEXT_SOURCE.read_text(encoding="utf-8"))
        chain = CHAIN_RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "SceneAudioResponse.evaluate(spectrum: audioSpectrum, parameters: $0)",
            chain,
            "chain 路径必须用共享求值器，不得就地另写一份公式",
        )
        compositor = COMPOSITOR_SOURCE.read_text(encoding="utf-8")
        self.assertIn("spectrum: request.audioSpectrum", compositor)


class SceneShakeAudioContractTests(unittest.TestCase):
    def test_legacy_profile_keeps_audio_fail_closed(self) -> None:
        self.assertRegex(
            SHAKE_PLANNER_AUDIO_SOURCE.read_text(encoding="utf-8"),
            r"case \.legacyUnconditionalPhase:\s*\n\s*return false",
            "legacy Shake 指纹尚无 audio 正反例，必须继续整段拒绝",
        )
        self.assertIn(
            "isAudioCapableProfile: profile == .stock2842",
            PULSE_CONSTANTS_SOURCE.read_text(encoding="utf-8"),
            "两个 legacy Pulse 指纹同样继续拒绝 audio",
        )

    def test_audio_defaults_match_the_official_annotations(self) -> None:
        # 四个共享默认值来自 shake/pulse 同名 annotation：frequencymin 0、
        # frequencymax 1、audioexponent 1.0、audioamount 1。
        shared = AUDIO_ADMISSION_SOURCE.read_text(encoding="utf-8")
        for pattern in (
            r'values\["frequencymin"\], range: 0 ?\.\.\. ?15, fallback: 0',
            r'values\["frequencymax"\], range: 0 ?\.\.\. ?15, fallback: 1',
            r'values\["audioexponent"\], range: 0 ?\.\.\. ?4, fallback: 1',
            r'values\["audioamount"\], range: 0 ?\.\.\. ?2, fallback: 1',
        ):
            self.assertRegex(shared, pattern)
        # audiobounds 默认值两个 effect 不同，必须由各自 planner 给出。
        self.assertIn(
            "defaultBounds: SIMD2(0, 1.2)",
            SHAKE_PLANNER_AUDIO_SOURCE.read_text(encoding="utf-8"),
            "stock shake.vert 的 audiobounds 默认值是 0.0 1.2",
        )
        self.assertIn(
            "defaultBounds: SIMD2(0.5, 1)",
            PULSE_CONSTANTS_SOURCE.read_text(encoding="utf-8"),
            "stock pulse.vert 的 audiobounds 默认值是 0.5 1.0",
        )
        for literal in ("SIMD2(0, 1.2)", "SIMD2(0.5, 1)"):
            self.assertNotIn(
                literal,
                shared,
                "共享层只接收 defaultBounds 参数，不得内置任一 effect 的默认值",
            )

    def test_shader_skips_the_time_driven_block_when_audio_is_enabled(self) -> None:
        source = SHAKE_PIPELINE_SOURCE.read_text(encoding="utf-8")
        # 官方 shake.frag 把时间驱动整段包在 `#if AUDIOPROCESSING == 0` 内。
        match = re.search(
            r"if \(uniforms\.audio\.y > 0\.5\) \{\s*\n\s*offset = uniforms\.audio\.x;\s*\n\s*\} else \{",
            source,
        )
        self.assertIsNotNone(
            match,
            "启用 audio 后 speed/friction/bounds/flowPhase 都不得参与 offset 计算",
        )
        self.assertIn("float4 audio;", source)


if __name__ == "__main__":
    unittest.main()
