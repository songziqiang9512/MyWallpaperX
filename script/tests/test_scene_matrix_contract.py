import json
import sys
import unittest
from collections import defaultdict
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPOSITORY_ROOT / "script"
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import generate_scene_full_matrix as matrix_generator
from scene_matrix_contract import AUTHORED_EFFECT_RUNTIME_EXPECTATIONS


def synthetic_result(sample_id: str = "fixture") -> dict[str, object]:
    evidence = defaultdict(int)
    evidence.update({
        metric: 0 for metric in matrix_generator.RUNTIME_EVIDENCE_METRICS
    })
    evidence.update({
        "shader_contract_aggregate_sha256": "a" * 64,
        "effect_graph_sha256": "b" * 64,
        "stock_opacity_single_effect_candidate_layer_ids": [],
    })
    runtime = defaultdict(int)
    runtime["runtime_evidence"] = evidence
    return {
        "id": sample_id,
        "title": "Fixture",
        "package_file": "scene.pkg",
        "hashes": {
            "project_sha256": "c" * 64,
            "package_sha256": "d" * 64,
        },
        "runtime": runtime,
    }


class SceneMatrixContractTests(unittest.TestCase):
    def test_authored_effect_registry_has_unique_keys_and_metrics(self) -> None:
        matrix_keys = [
            expectation.matrix_key
            for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        ]
        benchmark_metrics = [
            expectation.benchmark_metric
            for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        ]
        self.assertEqual(len(matrix_keys), len(set(matrix_keys)))
        self.assertEqual(len(benchmark_metrics), len(set(benchmark_metrics)))

    def test_tracked_matrices_have_no_unclassified_sample_keys(self) -> None:
        for relative_path in (
            "script/scene_wallpaper_sample_matrix.json",
            "script/scene_wallpaper_full_sample_matrix.json",
        ):
            matrix = json.loads((REPOSITORY_ROOT / relative_path).read_text())
            for old_sample in matrix["samples"]:
                with self.subTest(matrix=relative_path, sample=old_sample["id"]):
                    refreshed = matrix_generator.matrix_sample(
                        synthetic_result(old_sample["id"]),
                        old_sample,
                    )
                    self.assertEqual(
                        set(old_sample) - {"package_file"},
                        set(old_sample).intersection(refreshed),
                    )

    def test_unknown_matrix_key_fails_closed(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "unclassified matrix keys: expected_new_runtime_contract",
        ):
            matrix_generator.matrix_sample(
                synthetic_result(),
                {"expected_new_runtime_contract": 1},
            )

    def test_optional_runtime_contract_is_refreshed_when_already_tracked(
        self,
    ) -> None:
        result = synthetic_result()
        runtime = result["runtime"]
        runtime["particle_refract_loaded"] = 3
        runtime["particle_skipped_transparent"] = 2
        runtime["text_script_binding_count"] = 1
        runtime["text_script_binding_layer_ids"] = [42]
        sample = matrix_generator.matrix_sample(
            result,
            {
                "expected_particle_refract_loaded": 0,
                "expected_particle_skipped_transparent": 0,
                "expected_text_script_binding_count": 0,
                "required_text_script_binding_layer_ids": [],
            },
        )
        self.assertEqual(sample["expected_particle_refract_loaded"], 3)
        self.assertEqual(sample["expected_particle_skipped_transparent"], 2)
        self.assertEqual(sample["expected_text_script_binding_count"], 1)
        self.assertEqual(
            sample["required_text_script_binding_layer_ids"],
            [42],
        )


if __name__ == "__main__":
    unittest.main()
