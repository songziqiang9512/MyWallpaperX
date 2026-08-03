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
SCRIPT_PATH = REPOSITORY_ROOT / "script/scene_material_program_census.py"
SPEC = importlib.util.spec_from_file_location("scene_material_program_census", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
CENSUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CENSUS)


VERTEX_SOURCE = """\
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
"""


FRAGMENT_SOURCE = """\
uniform sampler2D g_Texture2; // {"material":"framebuffer","hidden":true}
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = texture2D(g_Texture2, v_TexCoord);
}
"""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SceneMaterialProgramCensusTests(unittest.TestCase):
    maxDiff = None

    def make_fixture(self, root: Path) -> dict[str, Path]:
        sample_id = "1000000001"
        sample_root = root / "isolated-samples"
        sample = sample_root / sample_id
        sample.mkdir(parents=True)
        project = sample / "project.json"
        project.write_text(
            json.dumps({"file": "scene.json", "title": "owned R3 census"}),
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
        (cache / "materials").mkdir(parents=True)
        (cache / "shaders/effects").mkdir(parents=True)
        material = cache / "materials/test.json"
        material.write_text(
            json.dumps({"passes": [{"shader": "unused"}]}),
            encoding="utf-8",
        )
        (cache / "shaders/effects/test.vert").write_text(
            VERTEX_SOURCE,
            encoding="utf-8",
        )
        (cache / "shaders/effects/test.frag").write_text(
            FRAGMENT_SOURCE,
            encoding="utf-8",
        )

        stock_root = root / "stock-assets"
        (stock_root / "shaders").mkdir(parents=True)

        effect_key = {
            "layerID": 10,
            "effectIndex": 0,
            "descriptorID": "10#effect#11",
        }
        layer_source = {"kind": "layerSource", "layerID": 10}
        effect_output = {
            "kind": "effectOutput",
            "layerID": 10,
            "effect": effect_key,
        }
        graph = {
            "layerID": 10,
            "effects": [{
                "key": effect_key,
                "definitionPath": "effects/test/effect.json",
                "input": layer_source,
                "output": effect_output,
                "nodeIndices": [0],
            }],
            "renderTargets": [],
            "nodes": [{
                "nodeIndex": 0,
                "effect": effect_key,
                "definitionPassIndex": 7,
                "materialOrdinal": 0,
                "instancePassIndex": 1,
                "kind": "material",
                "materialPath": "materials/test.json",
                "materialPassID": "materials/test.json#1",
                "target": effect_output,
                "bindings": [],
            }],
            "finalOutput": effect_output,
            "blockers": [],
        }
        effect_definition = {
            "relativePath": "effects/test/effect.json",
            "version": 1,
            "replacementKey": "test",
            "passes": [{
                "passIndex": 7,
                "materialPath": "materials/test.json",
                "bindings": [],
                "extraFields": {},
            }],
            "framebuffers": [],
            "dependencies": [
                "materials/test.json",
                "shaders/effects/test.vert",
                "shaders/effects/test.frag",
            ],
            "extraFields": {},
            "unknownFieldPaths": [],
        }
        multi_contributor_value = {
            "rawValue": "1.0",
            "valueKind": "binding",
            "userBinding": None,
            "components": [1.0],
            "timeline": {
                "isRelative": False,
                "lanes": [[{"frame": 0}, {"frame": 60}]],
                "options": {"mode": "single", "startsPaused": False},
            },
            "timelineDiagnostics": [],
            "scriptSource": (
                "export function mediaThumbnailChanged(event) { "
                "if (event.hasThumbnail) { var anim = thisObject.getAnimation(); "
                "anim.stop(); anim.play(); } }"
            ),
            "bindingKeys": ["animation", "script", "value"],
        }
        descriptor = {
            "entryPath": "scene.json",
            "layers": [{
                "id": 10,
                "effects": [{
                    "id": "10#effect#11",
                    "file": "effects/test/effect.json",
                    "visible": True,
                    "passes": [{
                        "passIndex": 1,
                        "textureSlots": [None, None, "materials/instance.tex"],
                        "userTextureInputs": [],
                        "combos": {},
                        "constantShaderValues": {
                            "gain": multi_contributor_value,
                        },
                    }],
                }],
            }],
            "materialPasses": [{
                "id": "materials/test.json#1",
                "materialPath": "materials/test.json",
                "materialRawSHA256": sha256(material),
                "passIndex": 1,
                "shaderPath": "effects/test",
                "textureSlots": [
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    "materials/data.tex",
                ],
                "userTextureInputs": [],
                "combos": {},
                "constantShaderValues": {},
                "userShaderValues": {},
                "blending": "normal",
                "depthTest": "disabled",
                "depthWrite": "disabled",
                "cullMode": "nocull",
            }],
            "effectDefinitions": [effect_definition],
            "shaderReferences": ["effects/test"],
        }
        runtime_input = {
            "renderDescriptor": descriptor,
            "authoredEffectRenderPlans": [graph],
            # Current contracts are reloaded from the VFS. This deliberately
            # tiny owned fixture has no archived contract projection.
            "shaderContracts": [],
        }
        report_root = root / "runtime-report"
        evidence = report_root / "results" / sample_id / "scene-runtime-evidence.json"
        evidence.parent.mkdir(parents=True)
        evidence.write_text(
            json.dumps({
                "schemaVersion": 1,
                "sourceEntryPath": "scene.json",
                "runtimeInput": runtime_input,
            }),
            encoding="utf-8",
        )
        matrix = root / "matrix.json"
        matrix.write_text(
            json.dumps({
                "schema_version": 1,
                "name": "owned-r3-material-program-census",
                "samples": [{
                    "id": sample_id,
                    "project_sha256": sha256(project),
                    "package_sha256": sha256(package),
                }],
            }),
            encoding="utf-8",
        )
        runtime_report = report_root / "report.json"
        runtime_report.write_text(
            json.dumps({
                "schema_version": 2,
                "matrix": "owned-r3-material-program-census",
                "matrix_sha256": "0" * 64,
                "samples": [{
                    "id": sample_id,
                    "hashes": {
                        "project_sha256": sha256(project),
                        "package_sha256": sha256(package),
                    },
                    "evidence": {"runtime_evidence": str(evidence)},
                }],
            }),
            encoding="utf-8",
        )
        fixture = root / "fixture.json"
        fixture.write_text(
            json.dumps({
                "schema_version": 1,
                "sample_root": str(sample_root),
                "runtime_homes": str(runtime_homes),
                "report": "explicit-runtime-report-is-authoritative",
            }),
            encoding="utf-8",
        )
        return {
            "fixture": fixture,
            "matrix": matrix,
            "runtime_report": runtime_report,
            "stock_root": stock_root,
        }

    def test_owned_graph_uses_material_id_preserves_holes_and_skips_program(self) -> None:
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
                    "--runtime-report",
                    str(paths["runtime_report"]),
                    "--stock-root",
                    str(paths["stock_root"]),
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
            self.assertEqual(report["schema_version"], 2)
            self.assertEqual(report["kind"], "scene-material-program-census")
            self.assertTrue(report["determinism"]["byte_equal"])
            self.assertEqual(len(set(report["determinism"]["raw_sha256"])), 1)
            self.assertEqual(report["summary"]["graph_node_count"], 1)
            self.assertEqual(
                report["summary"]["program"]["outcomes"],
                {"notAttempted": 1},
            )
            self.assertEqual(report["summary"]["program"]["attempted_count"], 0)
            bootstrap = report["summary"]["r2_variant_bootstrap"]
            self.assertEqual(bootstrap["outcomes"], {"accepted": 1})
            self.assertEqual(bootstrap["active_sampler_slot_count"], 1)
            self.assertEqual(
                bootstrap["active_sampler_final_candidate_kind_counts"],
                {"asset": 1},
            )
            self.assertEqual(bootstrap["authored_purpose_field_count"], 0)
            self.assertEqual(
                bootstrap["semantic_evidence_counts"],
                {"unproven": 1},
            )
            self.assertEqual(
                report["summary"]["program_blockers"]["texture-purpose-unproven"],
                1,
            )
            node = report["results"]["samples"][0]["nodes"][0]
            self.assertEqual(node["definitionPassIndex"], 7)
            self.assertEqual(node["descriptorMaterialPassIndex"], 1)
            self.assertEqual(node["materialPassID"], "materials/test.json#1")
            self.assertEqual(node["resolvedFixedSlotCount"], 8)
            self.assertEqual(
                [slot["index"] for slot in node["resolvedSlots"]],
                [2, 7],
            )
            self.assertEqual(node["template"]["status"], "accepted")
            self.assertEqual(len(node["multiContributorUniforms"]), 1)
            self.assertEqual(
                node["multiContributorUniforms"][0]["contributorKinds"],
                ["timeline", "scene-script"],
            )
            self.assertEqual(node["fixedSlotCount"], 8)
            self.assertEqual([slot["index"] for slot in node["slots"]], [2, 7])
            self.assertEqual(
                node["program"]["code"],
                "runtime-snapshot-unavailable",
            )
            decoded = report_bytes.decode("utf-8")
            self.assertNotIn(str(root), decoded)
            self.assertNotIn("uniform mat4 g_ModelViewProjectionMatrix", decoded)
            self.assertNotIn("texture2D(g_Texture2", decoded)
            for forbidden in (
                "metalSource",
                "preparedSource",
                "materialPayload",
                "objectIdentifier",
                "textureObjectIdentifier",
            ):
                self.assertNotIn(f'"{forbidden}"', decoded)

            self.assertEqual(CENSUS.publish_atomic(output, report_bytes), "unchanged")
            with self.assertRaises(CENSUS.CensusError):
                CENSUS.publish_atomic(output, b"different\n")

    def test_wrong_report_identity_and_partial_snapshot_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = self.make_fixture(root)
            output = root / "report.json"
            report = json.loads(paths["runtime_report"].read_text(encoding="utf-8"))
            report["matrix"] = "wrong-matrix"
            paths["runtime_report"].write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(CENSUS.CensusError, "matrix identity"):
                CENSUS.validate_inputs(
                    paths["fixture"],
                    paths["matrix"],
                    paths["runtime_report"],
                    paths["stock_root"],
                    output,
                )

            report["matrix"] = "owned-r3-material-program-census"
            report["samples"][0]["hashes"]["project_sha256"] = "f" * 64
            paths["runtime_report"].write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(CENSUS.CensusError, "identity differs"):
                CENSUS.validate_inputs(
                    paths["fixture"],
                    paths["matrix"],
                    paths["runtime_report"],
                    paths["stock_root"],
                    output,
                )

            self.assertEqual(CENSUS.runtime_snapshot_state({}), "unavailable")
            with self.assertRaisesRegex(CENSUS.CensusError, "partial immutable"):
                CENSUS.runtime_snapshot_state({"textureSnapshot": {}})

    def test_real_workshop_and_missing_explicit_report_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workshop = root / "real-workshop"
            workshop.mkdir()
            with mock.patch.object(CENSUS, "REAL_WORKSHOP_ROOT", workshop.resolve()):
                with self.assertRaises(CENSUS.CensusError):
                    CENSUS.require_safe_input_root(workshop, "sample_root")

        completed = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--output", "/private/tmp/unused.json"],
            cwd=REPOSITORY_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("--runtime-report", completed.stderr)

    def test_sampler_semantics_use_public_mode_or_regular_graph_only(self) -> None:
        def sampler(
            *, modes: list[str] | None = None, formats: list[str] | None = None
        ) -> dict:
            return {"modeValues": modes or [], "formatValues": formats or []}

        self.assertEqual(
            CENSUS.sampler_semantic_evidence(sampler(), "graph"),
            "graph-color-boundary",
        )
        self.assertEqual(
            CENSUS.sampler_semantic_evidence(sampler(), "asset"),
            "unproven",
        )
        for mode in ("opacitymask", "rgbmask", "flowmask"):
            self.assertEqual(
                CENSUS.sampler_semantic_evidence(sampler(modes=[mode]), "asset"),
                f"mode:{mode}",
            )
        for unsupported in (
            sampler(modes=["normal"]),
            sampler(modes=["depth"]),
            sampler(formats=["normalmap"]),
            sampler(modes=["opacitymask"], formats=["normalmap"]),
        ):
            self.assertEqual(
                CENSUS.sampler_semantic_evidence(unsupported, "asset"),
                "unproven",
            )


if __name__ == "__main__":
    unittest.main()
