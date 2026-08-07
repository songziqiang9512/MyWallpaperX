#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPOSITORY_ROOT / "script/scene_shader_preparation_census.py"
BASELINE_REF = "9d655ce294b1d656a1b66f50c77b156685e7f3f8"

SPEC = importlib.util.spec_from_file_location(
    "scene_shader_preparation_census",
    SCRIPT_PATH,
)
assert SPEC is not None and SPEC.loader is not None
CENSUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CENSUS)


VERTEX_SOURCE = r'''
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
'''


PLAIN_FRAGMENT_SOURCE = r'''
uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
uniform float g_Strength;
varying vec2 v_TexCoord;
void main() {
    vec4 color = texture2D(g_Texture0, v_TexCoord);
    gl_FragColor = vec4(color.rgb * g_Strength, color.a);
}
'''


CONDITIONAL_FRAGMENT_SOURCE = r'''
// [COMBO] {"combo":"OPTION","default":0,"options":[0,1]}
#if OPTION == 1
uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
#else
uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
#endif
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = texture2D(g_Texture0, v_TexCoord);
}
'''


READINESS_FRAGMENT_SOURCE = r'''
#define APPLY(value) value
uniform sampler2D g_Texture0; // {"material":"framebuffer","hidden":true}
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = APPLY(texture2D(g_Texture0, v_TexCoord));
}
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SceneShaderPreparationCensusTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> dict[str, Path]:
        sample_id = "1000000001"
        sample_root = root / "isolated-samples"
        sample = sample_root / sample_id
        sample.mkdir(parents=True)
        project = sample / "project.json"
        project.write_text(
            json.dumps({"file": "scene.json", "title": "owned tiny corpus"}),
            encoding="utf-8",
        )
        package = sample / "scene.pkg"
        package.write_bytes(b"project-owned-placeholder-package")

        runtime_homes = root / "isolated-runtime-homes"
        cache = (
            runtime_homes
            / sample_id
            / "Library/Caches/MyWallpaperX/SteamWorkshopScene/fixture-cache"
        )
        materials = cache / "materials/effects"
        shaders = cache / "shaders/effects"
        materials.mkdir(parents=True)
        shaders.mkdir(parents=True)

        (shaders / "plain.vert").write_text(VERTEX_SOURCE, encoding="utf-8")
        (shaders / "plain.frag").write_text(
            PLAIN_FRAGMENT_SOURCE,
            encoding="utf-8",
        )
        (shaders / "conditional.vert").write_text(VERTEX_SOURCE, encoding="utf-8")
        (shaders / "conditional.frag").write_text(
            CONDITIONAL_FRAGMENT_SOURCE,
            encoding="utf-8",
        )
        (shaders / "readiness.vert").write_text(VERTEX_SOURCE, encoding="utf-8")
        (shaders / "readiness.frag").write_text(
            READINESS_FRAGMENT_SOURCE,
            encoding="utf-8",
        )

        normal_state = {
            "blending": "normal",
            "depthtest": "disabled",
            "depthwrite": "disabled",
            "cullmode": "nocull",
        }
        (materials / "accepted.json").write_text(
            json.dumps({
                "passes": [{
                    "shader": "effects/plain",
                    "constantshadervalues": {"g_Strength": 0.75},
                    **normal_state,
                }]
            }),
            encoding="utf-8",
        )
        (materials / "texture-rejected.json").write_text(
            json.dumps({
                "passes": [{
                    "shader": "effects/plain",
                    "textures": [None, "materials/mask.tex"],
                    "constantshadervalues": {"g_Strength": 0.5},
                    **normal_state,
                }]
            }),
            encoding="utf-8",
        )
        (materials / "conditional.json").write_text(
            json.dumps({
                "passes": [{
                    "shader": "effects/conditional",
                    "combos": {"OPTION": 1},
                    **normal_state,
                }]
            }),
            encoding="utf-8",
        )
        (materials / "readiness.json").write_text(
            json.dumps({
                "passes": [{
                    "shader": "effects/readiness",
                    **normal_state,
                }]
            }),
            encoding="utf-8",
        )
        # Mirrors SceneAssetCatalog exactly: a non-[String:Int] combo dictionary
        # is discarded as a whole, and the unsupported `alphawrite` alias is not
        # promoted to the production `alphawriting` field.
        (materials / "production-parser-boundary.json").write_text(
            json.dumps({
                "passes": [{
                    "shader": "effects/plain",
                    "combos": {"FLOAT_OPTION": 0.5},
                    "alphawrite": "enabled",
                    "constantshadervalues": {"g_Strength": 0.25},
                    **normal_state,
                }]
            }),
            encoding="utf-8",
        )

        stock_root = root / "stock-assets"
        (stock_root / "shaders").mkdir(parents=True)
        reference_report = root / "reference-report.json"
        reference_report.write_text(
            json.dumps({"schema_version": 2, "samples": [{"id": sample_id}]}),
            encoding="utf-8",
        )
        fixture = root / "fixture.json"
        fixture.write_text(
            json.dumps({
                "schema_version": 1,
                "sample_root": str(sample_root),
                "runtime_homes": str(runtime_homes),
                "report": str(reference_report),
            }),
            encoding="utf-8",
        )
        matrix = root / "matrix.json"
        matrix.write_text(
            json.dumps({
                "schema_version": 1,
                "name": "project-owned-shader-preparation-corpus",
                "samples": [{
                    "id": sample_id,
                    "project_sha256": sha256(project),
                    "package_sha256": sha256(package),
                }],
            }),
            encoding="utf-8",
        )
        return {
            "fixture": fixture,
            "matrix": matrix,
            "stock_root": stock_root,
        }

    def test_project_owned_corpus_report_contract_and_repeatability(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = self.make_fixture(root)
            output = root / "evidence/report.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--fixture",
                    str(paths["fixture"]),
                    "--matrix",
                    str(paths["matrix"]),
                    "--stock-root",
                    str(paths["stock_root"]),
                    "--baseline-ref",
                    BASELINE_REF,
                    "--output",
                    str(output),
                ],
                cwd=REPOSITORY_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report_bytes = output.read_bytes()
            report = json.loads(report_bytes)

            self.assertEqual(report["schema_version"], 1)
            self.assertEqual(report["kind"], "scene-shader-preparation-census")
            self.assertEqual(
                report["inputs"]["current_sources"]["implementation_kind"],
                "worktree-snapshot",
            )
            self.assertEqual(report["summary"]["sample_count"], 1)
            self.assertEqual(report["summary"]["contract_count"], 3)
            self.assertEqual(report["summary"]["material_pass_count"], 5)
            self.assertEqual(
                report["summary"]["source_graph"]["graph_contract_count"],
                3,
            )
            self.assertEqual(
                report["summary"]["source_graph"]["stage_root_provenance_counts"],
                {"package": 6},
            )
            self.assertTrue(report["determinism"]["current"]["byte_equal"])
            self.assertEqual(
                len(set(report["determinism"]["current"]["raw_sha256"])),
                1,
            )
            self.assertEqual(report["comparison"]["raw_projection_diff"]["count"], 0)
            self.assertEqual(report["comparison"]["canonical_diff"]["count"], 0)
            self.assertEqual(report["comparison"]["newly_accepted"], [])
            self.assertEqual(report["comparison"]["current_accepted"], [])
            self.assertEqual(
                report["comparison"]["lost_accepted"],
                report["comparison"]["baseline_accepted"],
            )
            self.assertEqual(
                sum(report["summary"]["gpu_admission"]["current"].values()),
                5,
            )
            self.assertEqual(
                report["summary"]["gpu_admission"]["current"],
                {"removed": 5},
            )
            self.assertEqual(report["summary"]["preparation"], {"accepted": 5})
            self.assertEqual(len(report["results"]["baseline"]["passes"]), 5)
            self.assertEqual(len(report["results"]["current"]["passes"]), 5)
            parser_boundary = next(
                item
                for item in report["results"]["current"]["passes"]
                if item["materialPath"].endswith("production-parser-boundary.json")
            )
            self.assertEqual(parser_boundary["gpuAdmission"], "removed")
            readiness = next(
                item
                for item in report["results"]["current"]["passes"]
                if item["materialPath"].endswith("readiness.json")
            )
            self.assertEqual(readiness["preparation"], "accepted")
            self.assertEqual(readiness["gpuAdmission"], "removed")
            self.assertNotIn(str(root), report_bytes.decode("utf-8"))
            self.assertNotIn(
                "uniform mat4 g_ModelViewProjectionMatrix;",
                report_bytes.decode("utf-8"),
            )
            forbidden_payload_keys = {
                "source",
                "shaderSource",
                "preparedSource",
                "materialJSON",
                "materialPayload",
            }
            stack = [report]
            while stack:
                value = stack.pop()
                if isinstance(value, dict):
                    self.assertFalse(forbidden_payload_keys.intersection(value))
                    stack.extend(value.values())
                elif isinstance(value, list):
                    stack.extend(value)

            self.assertEqual(
                CENSUS.publish_atomic(output, report_bytes),
                "unchanged",
            )
            with self.assertRaises(CENSUS.CensusError):
                CENSUS.publish_atomic(output, b"different\n")

    def test_missing_baseline_ref_is_rejected_by_cli(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--output", "/private/tmp/unused.json"],
            cwd=REPOSITORY_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("--baseline-ref", completed.stderr)

    def test_real_workshop_and_output_inside_inputs_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workshop = root / "real-workshop"
            workshop.mkdir()
            with mock.patch.object(CENSUS, "REAL_WORKSHOP_ROOT", workshop.resolve()):
                with self.assertRaises(CENSUS.CensusError):
                    CENSUS.require_safe_input_root(workshop, "sample_root")

            paths = self.make_fixture(root)
            fixture = json.loads(paths["fixture"].read_text(encoding="utf-8"))
            with self.assertRaises(CENSUS.CensusError):
                CENSUS.validate_inputs(
                    paths["fixture"],
                    paths["matrix"],
                    paths["stock_root"],
                    Path(fixture["sample_root"]) / "report.json",
                )


if __name__ == "__main__":
    unittest.main()
