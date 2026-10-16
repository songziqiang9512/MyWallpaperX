#!/usr/bin/env python3

"""Strict Boolean publication with read-only scene lookup visibility."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from . import scene_vector_vm_test_support as vm
    from .scene_vector_vm_test_support import compile_vector_harness
except ImportError:
    import scene_vector_vm_test_support as vm
    from scene_vector_vm_test_support import compile_vector_harness


HARNESS = (Path(__file__).parent / "fixtures/SceneScriptBooleanVisibilityHarness.swift").read_text()


class SceneScriptBooleanVisibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-bool-visible-"
        )
        cls.binary = compile_vector_harness(
            Path(cls.temporary_directory.name),
            HARNESS,
            "scene-bool-visible",
            preamble=vm.SWIFT_PREAMBLE.replace("    struct Camera {\n",
                "    struct Camera {\n        var bloom = SceneBloomConfiguration.disabled\n", 1),
            extra_swift_sources=(
                Path(__file__).parent / "fixtures/SceneScriptBooleanReturnChecks.swift",
                vm.SCENE / "Rendering/Composition/SceneBloomPostProcess.swift",
                vm.SCENE / "Resources/Textures/SceneResourceBudget.swift",
            ),
        )
        result = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.value = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_boolean_input_and_return_are_published_without_coercion(self) -> None:
        self.assertEqual(self.value["definitions"], 1)
        self.assertFalse(self.value["first"])
        self.assertTrue(self.value["second"])

    def test_non_boolean_return_preserves_input_without_fusing_owner(self) -> None:
        self.assertFalse(self.value["badValue"])
        self.assertIsNone(self.value["badCode"])
        self.assertFalse(self.value["badAgainValue"])
        self.assertFalse(self.value["badAgainFailed"])
        self.assertIsNone(self.value["badAgainCode"])

    def test_native_bool_return_contract_and_stateful_continuity(self) -> None:
        for fact, accepted in self.value["returnContract"].items():
            with self.subTest(fact=fact):
                self.assertTrue(accepted)

    def test_undefined_preserves_the_boolean_input(self) -> None:
        self.assertTrue(self.value["undefinedValue"])

    def test_outer_user_and_parented_layer_use_the_same_typed_owner(self) -> None:
        self.assertEqual(self.value["parentedProjected"], 1)
        self.assertEqual(self.value["userWrappedProjected"], 1)

    def test_ordinary_text_leaf_uses_the_value_only_boolean_owner(self) -> None:
        self.assertEqual(self.value["textLeafProjected"], 1)

    def test_effect_bearing_leaf_uses_the_same_value_only_owner(self) -> None:
        self.assertEqual(self.value["effectBearingDefinitions"], 1)
        self.assertTrue(self.value["effectBearingValue"])

    def test_named_graph_participants_keep_independent_visibility_owners(self) -> None:
        self.assertEqual(self.value["namedConsumerProjected"], 1)
        self.assertEqual(self.value["namedProviderProjected"], 1)
        self.assertEqual(self.value["shadowedNamedConsumerProjected"], 1)

    def test_shared_state_owner_is_admitted_without_dynamic_code(self) -> None:
        self.assertEqual(self.value["cursorOnlyProjected"], 1)
        self.assertEqual(self.value["sharedUpdateProjected"], 1)
        self.assertEqual(self.value["statefulParentedProjected"], 1)
        self.assertEqual(self.value["handleUpdateProjected"], 1)
        self.assertEqual(self.value["dynamicGlobalWriteProjected"], 1)
        self.assertEqual(self.value["eventfulDefinitions"], 1)
        self.assertEqual(self.value["statefulCursorDefinitions"], 1)
        self.assertFalse(self.value["statefulCursorValue"])
        self.assertEqual(self.value["statefulCursorRegistrationCount"], 1)
        self.assertEqual(
            self.value["statefulCursorEvents"],
            ["cursorDown", "cursorUp"],
        )

    def test_source_spelling_does_not_select_visibility_owner_admission(self) -> None:
        self.assertEqual(self.value["escapedStatefulDefinitions"], 1)
        self.assertFalse(self.value["escapedStatefulValue"])

    def test_authored_self_destroy_overrides_return_and_property_event(self) -> None:
        self.assertFalse(self.value["selfDestroyValue"])
        self.assertTrue(self.value["selfDestroyMutation"])
        self.assertFalse(self.value["propertyDestroyValue"])
        self.assertTrue(self.value["propertyDestroyMutation"])

    def test_layer_bone_visibility_uses_effectful_owner_and_publishes_matrix(self) -> None:
        self.assertEqual(self.value["boneDefinitions"], 1)
        self.assertTrue(self.value["boneValue"], self.value["boneFailure"])
        self.assertEqual(self.value["boneMutationCount"], 1)
        self.assertEqual(self.value["boneTranslation"], 12)
        self.assertEqual(self.value["boneCursorOwners"], 1)

    def test_shared_heap_persists_when_typed_frame_is_discarded(self) -> None:
        self.assertTrue(self.value["sharedHeapFirst"])
        self.assertFalse(self.value["sharedHeapRetry"])
        self.assertFalse(self.value["sharedHeapCommitted"])

    def test_effectful_boolean_owner_publishes_prepared_dynamic_image_layers(self) -> None:
        self.assertEqual(self.value["authoredStyleAlpha"], 0.25)
        self.assertEqual(self.value["authoredStyleColorY"], 0.4)
        self.assertTrue(self.value["failedStyleDiscarded"])
        self.assertEqual(self.value["dynamicDefinitions"], 1)
        self.assertTrue(self.value["dynamicHasAudio"])
        self.assertEqual(self.value["dynamicMediaOwnerCount"], 1)
        self.assertTrue(self.value["dynamicValue"])
        self.assertTrue(self.value["dynamicMediaVisible"])
        self.assertEqual(self.value["dynamicAudioScaleY"], 10)
        self.assertEqual(self.value["dynamicFailureCount"], 0)
        self.assertTrue(self.value["dynamicDuplicateValue"])
        self.assertEqual(self.value["dynamicDuplicateFailureCount"], 0)
        self.assertEqual(self.value["dynamicLayerCount"], 4)
        self.assertEqual(self.value["dynamicOwnerEffectsCount"], 1)
        self.assertTrue(self.value["dynamicOwnerEffectsTarget"])
        self.assertEqual(self.value["dynamicOwnerEffectsLayerCount"], 4)
        self.assertTrue(self.value["dynamicPeerMutation"])
        self.assertEqual(
            self.value["dynamicModelPaths"],
            [
                "models/workshop/2727665642/bar.json",
                "models/workshop/2727665642/bar.json",
            ],
        )

    def test_event_only_media_owner_reads_audio_and_quiesces_without_new_events(self) -> None:
        self.assertEqual(self.value["eventOnlyAudioDefinitions"], 1)
        self.assertEqual(self.value["eventAudioFailures"], 0)
        self.assertAlmostEqual(self.value["eventAudioX"], 0.4)
        self.assertAlmostEqual(self.value["eventAudioY"], 0.7)
        self.assertEqual(self.value["eventSilentX"], 0)
        self.assertEqual(self.value["eventCallbackCount"], 2)
        self.assertTrue(self.value["eventQuiet"])

    def test_value_only_host_allows_read_only_scene_lookup_only(self) -> None:
        self.assertEqual(self.value["hiddenSharedCode"], "exception")
        self.assertIsNone(self.value["hiddenHandleCode"])
        self.assertEqual(self.value["timerCode"], "exception")
        self.assertEqual(self.value["audioDefinitions"], 1)

    def test_stateful_visibility_owner_admits_destroy_and_teardown_dispatches_once(self) -> None:
        self.assertEqual(self.value["destroyDefinitions"], 1)
        self.assertTrue(self.value["destroyTeardownInvoked"])
        self.assertTrue(self.value["destroyTeardownQuiescent"])
        self.assertFalse(self.value["destroyTeardownFailed"])
        self.assertFalse(self.value["teardownDestroyInvoked"])
        self.assertTrue(self.value["teardownQuiescent"])
        self.assertFalse(self.value["teardownFailed"])


if __name__ == "__main__":
    unittest.main()
