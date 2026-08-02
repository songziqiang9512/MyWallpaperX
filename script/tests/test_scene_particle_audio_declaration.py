#!/usr/bin/env python3
"""粒子 audio response 声明门（A4 第一段：声明 IR 正确性）。

背景：粒子与 effect 是两套独立 schema。effect 侧走 shader constant
（`audiobounds`/`audioamount`/`audioexponent` + `frequencymin`/`frequencymax`），
粒子侧只有 `audioprocessing*` 一套且没有 amount。此前 parser 误用 effect 字段名，
导致解析出恒为 nil 的字段，同时漏掉真实存在的 `audioprocessingfrequencyend`。

本门只覆盖声明的保真解析与诊断，不覆盖执行——粒子 audio 的求值公式与默认值
官方均未公开，第三方参考实现同样是未接通的 TODO 占位，证据不足以实现执行。
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PARTICLES_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Particles"
DEFINITION_SOURCE = PARTICLES_ROOT / "SceneParticleDefinition.swift"
VORTEX_SOURCE = PARTICLES_ROOT / "SceneParticleVortex.swift"
PARSER_SOURCE = PARTICLES_ROOT / "SceneParticleDefinitionParser.swift"
OPERATOR_PARSER_SOURCE = PARTICLES_ROOT / "SceneParticleDefinitionParser+Operator.swift"
SIMULATION_SOURCE = PARTICLES_ROOT / "SceneParticleSimulationSupport.swift"
BOIDS_SOURCE = PARTICLES_ROOT / "SceneParticleBoids.swift"
CONTROL_POINT_FORCE_SOURCE = PARTICLES_ROOT / "SceneParticleControlPointForce.swift"
PERIODIC_SOURCE = PARTICLES_ROOT / "SceneParticlePeriodicEmission.swift"

# 真实语料中出现过的三个字段（45 样本、11 处启用 audio 的组件）。
OFFICIAL_PARTICLE_AUDIO_KEYS = (
    "audioprocessingmode",
    "audioprocessingbounds",
    "audioprocessingfrequencyend",
)
# 第三方 parser 交叉验证补充的两个字段，语料未出现但属同一 schema。
CROSS_VERIFIED_KEYS = (
    "audioprocessingexponent",
    "audioprocessingfrequencystart",
)
# effect 侧 shader constant 字段名，粒子 parser 不得再解析。
EFFECT_ONLY_KEYS = ("audioamount", "audioexponent", "audiofrequency", "audiobounds")

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        // 取自真实样本 2131872317 particles/workshop/2110548715/presets/fireworks1.json
        // 的 sphererandom emitter：语料中唯一带 audioprocessingfrequencyend 的声明。
        let fireworksEmitter: [String: Any] = [
            "name": "sphererandom",
            "id": 6,
            "rate": 1,
            "instantaneous": 0,
            "origin": "0 0 0",
            "directions": "1 1 0",
            "distancemin": 0,
            "distancemax": 0,
            "audioprocessingmode": 3,
            "audioprocessingbounds": "0 1",
            "audioprocessingfrequencyend": 10,
        ]
        // 取自 2419444134 Stars_copy1.json 的 boxrandom emitter。
        let starsEmitter: [String: Any] = [
            "name": "boxrandom",
            "rate": 40,
            "distancemax": "1000 500 0",
            "audioprocessingmode": 3,
            "audioprocessingbounds": "0.5 1",
        ]
        // 3299228616 形态：只有 mode，其余缺省。
        let modeOnlyEmitter: [String: Any] = [
            "name": "boxrandom",
            "audioprocessingmode": 3,
        ]
        // 作者未启用。
        let disabledEmitter: [String: Any] = [
            "name": "boxrandom",
            "audioprocessingmode": 0,
            "audioprocessingbounds": "0.5 1",
        ]
        // effect 侧字段名不得被粒子 parser 采信。
        let effectSchemaEmitter: [String: Any] = [
            "name": "boxrandom",
            "audiobounds": "0 1.2",
            "audioamount": 2,
            "audioexponent": 0.5,
            "audiofrequency": "0 3",
        ]
        // 完整 schema（含第三方交叉验证的两个字段）。
        let fullEmitter: [String: Any] = [
            "name": "sphererandom",
            "audioprocessingmode": 1,
            "audioprocessingbounds": "0.8 1",
            "audioprocessingexponent": 2,
            "audioprocessingfrequencystart": 2,
            "audioprocessingfrequencyend": 12,
        ]

        let definition: [String: Any] = [
            "emitter": [
                fireworksEmitter, starsEmitter, modeOnlyEmitter,
                disabledEmitter, effectSchemaEmitter, fullEmitter,
            ],
            "initializer": [
                [
                    "name": "turbulentvelocityrandom",
                    "audioprocessingmode": 3,
                    "audioprocessingbounds": "0.8 1",
                ],
            ],
            "operator": [
                [
                    "name": "vortex",
                    "audioprocessingmode": 3,
                    "audioprocessingbounds": "0.5 1",
                ],
            ],
            "renderer": [["name": "sprite"]],
            "material": "materials/particle.json",
        ]

        let data = try JSONSerialization.data(withJSONObject: definition)
        let parsed: SceneParticleDefinition = try SceneParticleDefinitionParser()
            .parse(data: data)

        func describe(_ response: SceneParticleAudioResponse) -> [String: Any] {
            var payload: [String: Any] = ["enabled": response.isEnabled]
            payload["mode"] = response.mode ?? -1
            payload["exponent"] = response.exponent ?? -1
            payload["frequencyStart"] = response.frequencyStart ?? -1
            payload["frequencyEnd"] = response.frequencyEnd ?? -1
            if case let .vector(components)? = response.bounds {
                payload["bounds"] = components
            } else if case let .scalar(value)? = response.bounds {
                payload["bounds"] = [value]
            } else {
                payload["bounds"] = []
            }
            return payload
        }

        let diagnostics = SceneParticleSimulationMath.diagnostics(parsed, nil)

        let payload: [String: Any] = [
            "emitters": parsed.emitters.map { describe($0.audioResponse) },
            "turbulent": parsed.initializers.compactMap {
                $0.turbulentVelocity.map { describe($0.audioResponse) }
            },
            "operators": parsed.operators.map { describe($0.audioResponse) },
            "audioIgnoredComponents": diagnostics
                .filter { $0.kind == .audioResponseIgnored }
                .compactMap { $0.componentName }
                .sorted(),
        ]
        let out = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: out, as: UTF8.self))
    }
}
'''


class SceneParticleAudioDeclarationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-particle-audio-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-particle-audio"
        # 只编译声明、解析与诊断三段，避免拖入渲染/资源图等无关依赖。
        sources = [
            DEFINITION_SOURCE,
            VORTEX_SOURCE,
            PARSER_SOURCE,
            OPERATOR_PARSER_SOURCE,
            BOIDS_SOURCE,
            SIMULATION_SOURCE,
            CONTROL_POINT_FORCE_SOURCE,
            PERIODIC_SOURCE,
        ]
        compilation = subprocess.run(
            ["swiftc", *[str(path) for path in sources], str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_real_sample_declaration_is_preserved_in_full(self) -> None:
        # 2131872317 是语料中唯一带 audioprocessingfrequencyend 的声明，
        # 修正前该字段被静默丢弃。
        fireworks = self.result["emitters"][0]
        self.assertTrue(fireworks["enabled"])
        self.assertEqual(fireworks["mode"], 3)
        self.assertEqual(fireworks["bounds"], [0.0, 1.0])
        self.assertEqual(
            fireworks["frequencyEnd"],
            10,
            "audioprocessingfrequencyend 必须进入 IR，不得静默丢失",
        )

    def test_bounds_only_declaration_parses(self) -> None:
        stars = self.result["emitters"][1]
        self.assertTrue(stars["enabled"])
        self.assertEqual(stars["bounds"], [0.5, 1.0])
        self.assertEqual(stars["frequencyEnd"], -1, "未声明的字段保持缺省")

    def test_mode_only_declaration_parses(self) -> None:
        mode_only = self.result["emitters"][2]
        self.assertTrue(mode_only["enabled"])
        self.assertEqual(mode_only["mode"], 3)
        self.assertEqual(mode_only["bounds"], [])

    def test_author_disabled_declaration_is_not_enabled(self) -> None:
        disabled = self.result["emitters"][3]
        self.assertFalse(
            disabled["enabled"], "mode=0 是作者关闭，必须与启用区分"
        )
        self.assertEqual(
            disabled["bounds"],
            [0.5, 1.0],
            "关闭时其余字段仍应保真保存",
        )

    def test_effect_schema_field_names_are_not_accepted(self) -> None:
        effect_schema = self.result["emitters"][4]
        self.assertFalse(
            effect_schema["enabled"],
            "effect 的 audiobounds/audioamount 不是粒子字段，不得据此启用",
        )
        self.assertEqual(effect_schema["bounds"], [])
        self.assertEqual(effect_schema["exponent"], -1)
        self.assertEqual(effect_schema["frequencyEnd"], -1)

    def test_full_schema_round_trips(self) -> None:
        full = self.result["emitters"][5]
        self.assertEqual(full["mode"], 1)
        self.assertEqual(full["bounds"], [0.8, 1.0])
        self.assertEqual(full["exponent"], 2)
        self.assertEqual(full["frequencyStart"], 2)
        self.assertEqual(full["frequencyEnd"], 12)

    def test_initializer_and_operator_share_the_same_declaration(self) -> None:
        self.assertEqual(len(self.result["turbulent"]), 1)
        self.assertTrue(self.result["turbulent"][0]["enabled"])
        self.assertEqual(self.result["turbulent"][0]["bounds"], [0.8, 1.0])
        self.assertEqual(len(self.result["operators"]), 1)
        self.assertTrue(self.result["operators"][0]["enabled"])
        self.assertEqual(self.result["operators"][0]["bounds"], [0.5, 1.0])

    def test_every_enabled_component_reports_audio_ignored(self) -> None:
        # 修正前 operator 的 audio 启用不产生任何诊断，会静默按无音频路径模拟。
        components = self.result["audioIgnoredComponents"]
        self.assertIn("emitter", components)
        self.assertIn("operator", components)
        self.assertIn("turbulentvelocityrandom", components)


class SceneParticleAudioSchemaContractTests(unittest.TestCase):
    """锁定字段名合同，防止 effect 与粒子两套 schema 再次混用。"""

    def test_parser_reads_only_the_particle_schema(self) -> None:
        source = PARSER_SOURCE.read_text(encoding="utf-8")
        for key in OFFICIAL_PARTICLE_AUDIO_KEYS + CROSS_VERIFIED_KEYS:
            self.assertIn(
                f'root["{key}"]', source, f"粒子 schema 字段 {key} 必须被解析"
            )
        for key in EFFECT_ONLY_KEYS:
            self.assertNotIn(
                f'root["{key}"]',
                source,
                f"{key} 属于 effect shader constant schema，粒子 parser 不得解析",
            )

    def test_audio_declaration_is_shared_by_all_three_component_kinds(self) -> None:
        source = DEFINITION_SOURCE.read_text(encoding="utf-8")
        self.assertEqual(
            source.count("let audioResponse: SceneParticleAudioResponse"),
            3,
            "emitter、turbulent velocity 与 operator 共用同一声明类型",
        )
        self.assertIn("struct SceneParticleAudioResponse", source)

    def test_declaration_carries_no_default_values(self) -> None:
        source = DEFINITION_SOURCE.read_text(encoding="utf-8")
        start = source.index("struct SceneParticleAudioResponse")
        end = source.index("nonisolated struct SceneParticleEmitter", start)
        declaration = source[start:end]
        # 默认值官方未公开，第三方 parser 自身在 emitter 与 initializer 两处
        # 给出的默认值还互相矛盾，因此这里不得内置任何默认值。
        for literal in ("0.8", "15", "= 2", "= 1.0"):
            self.assertNotIn(
                literal,
                declaration,
                "粒子 audio 默认值官方未公开，不得在 IR 层内置",
            )

    def test_simulation_still_refuses_to_execute_audio_response(self) -> None:
        source = SIMULATION_SOURCE.read_text(encoding="utf-8")
        self.assertIn("audioResponseIgnored", source)
        self.assertIn(
            "guard let value, !value.audioResponse.isEnabled else { return .zero }",
            source,
            "turbulent velocity 的 audio profile 必须继续 fail closed",
        )


if __name__ == "__main__":
    unittest.main()
