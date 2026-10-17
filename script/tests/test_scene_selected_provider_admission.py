"""CPU selected-provider admission through complete production owners."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_dependency_render_plan as dependency
from script.tests import test_scene_resolved_material_graph_executor as graph
from script.tests import scene_dependency_binding_test_support as binding_support
from script.tests.scene_dependency_binding_test_support import (
    SCENE_DEPENDENCY_BINDING_SUPPORT,
)


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name("fixtures") / "SceneSelectedProviderAdmissionChecks.swift"


def production_inputs():
    # The shared graph gate normally supplies a dependency implementation
    # double. Replace that complete test-support section, not any production
    # function, with the real dependency family and this fixture's data DTOs.
    support = graph.SUPPORT
    if not support.endswith(SCENE_DEPENDENCY_BINDING_SUPPORT):
        raise AssertionError("shared binding support boundary changed")
    support = support.removesuffix(SCENE_DEPENDENCY_BINDING_SUPPORT)
    start = support.index("struct SceneUtilityLayer {")
    end = support.index("struct SceneEffectStageProgram {", start)
    support = support[:start] + support[end:]
    sources = [
        *graph.CONTRACT_FIXTURE["SWIFT_SOURCES"],
        *(p for p in dependency.SWIFT_SOURCES
          if p.name != "SceneDependencyRenderPlanTestSupport.swift"),
    ]
    return support, list(dict.fromkeys(sources))


def identities(paths):
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in paths}


class SceneSelectedProviderAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        support, sources = production_inputs()
        retained = os.environ.get("MWX_SELECTED_PROVIDER_TEST_WORK")
        cls.temporary = None
        if retained:
            work = Path(retained).resolve()
            work.mkdir(parents=True, exist_ok=False)
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-selected-provider-")
            work = Path(cls.temporary.name)
            cls.addClassCleanup(cls.temporary.cleanup)
        cls.work = work
        support_path = work / "Support.swift"
        support_path.write_text(support, encoding="utf-8")
        binary = work / "selected-provider"
        inputs = [*sources, FIXTURE, Path(__file__).resolve(),
                  Path(graph.__file__).resolve(), Path(dependency.__file__).resolve(),
                  Path(binding_support.__file__).resolve(), graph.CONTRACT_GATE,
                  graph.CONTRACT_FIXTURE["PUBLICATION_GATE"]]
        before = identities(inputs)
        environment = os.environ.copy()
        for key in ("CLANG_MODULE_CACHE_PATH", "SWIFT_MODULECACHE_PATH"):
            environment[key] = str(work / key.lower())
        environment.pop("MWX_SCENE_NAMED_PROVIDER_ROUTE", None)
        argv = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                "-D", "SCENE_GRAPH_TESTING", str(support_path),
                *(str(p) for p in sources), str(FIXTURE),
                "-framework", "Metal", "-framework", "CoreGraphics",
                "-framework", "ImageIO", "-module-cache-path",
                str(work / "module-cache"), "-o", str(binary)]
        (work / "command.json").write_text(json.dumps(argv, indent=2) + "\n")
        (work / "generated-support.json").write_text(json.dumps({
            "sha256": hashlib.sha256(support.encode()).hexdigest(),
            "bytes": len(support.encode()),
        }, indent=2) + "\n")
        (work / "input-before.json").write_text(json.dumps(before, indent=2) + "\n")
        compiled = subprocess.run(argv, cwd=ROOT, env=environment,
                                  capture_output=True, text=True)
        (work / "compile.stdout").write_text(compiled.stdout)
        (work / "compile.stderr").write_text(compiled.stderr)
        after = identities(inputs)
        (work / "input-after.json").write_text(json.dumps(after, indent=2) + "\n")
        if before != after:
            raise AssertionError("production/test inputs changed during compilation")
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        completed = subprocess.run([str(binary)], cwd=ROOT, env=environment,
                                   capture_output=True, text=True)
        (work / "run.stdout").write_text(completed.stdout)
        (work / "run.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise AssertionError(completed.stderr)
        cls.facts = json.loads(completed.stdout)

    def test_single_active_superset_switches_and_renames_without_mutation(self):
        for variant in self.facts["variants"]:
            for key in ("first", "second"):
                case = variant[key]
                self.assertTrue(case["structural"])
                self.assertTrue(case["owner"])
                self.assertFalse(case["refused"])
                self.assertTrue(case["executable"])
                self.assertEqual(case["bindingProvider"], case["selected"])
                self.assertEqual(case["requiredProviders"], [case["selected"]])
                self.assertEqual(case["rawBefore"], case["rawAfter"])
                self.assertEqual(case["issues"], [])
                self.assertEqual(case["bindingSlots"], [case["selectedSlot"]])

    def test_two_active_providers_retain_the_aggregate(self):
        for variant in self.facts["variants"]:
            case = variant["both"]
            self.assertTrue(case["owner"])
            self.assertTrue(case["executable"])
            self.assertTrue(case["aggregateStrict"])
            self.assertEqual(case["aggregateProviders"], case["rawBefore"])
            self.assertEqual(case["bindingProvider"], -1)

    def test_unexplained_missing_cyclic_and_unsafe_shapes_stay_rejected(self):
        for variant in self.facts["variants"]:
            for name, case in variant["rejected"].items():
                with self.subTest(variant=variant["name"], case=name):
                    self.assertFalse(case["owner"])
                    self.assertTrue(case["refused"])
                    self.assertFalse(case["executable"])
                    self.assertEqual(case["bindingProvider"], -1)
                    self.assertFalse(case["aggregateStrict"])
                    self.assertNotEqual(case["issues"], [])
                    self.assertEqual(case["rawBefore"], case["rawAfter"])

    def test_existing_plain_blend_and_program_authority_are_preserved(self):
        for variant in self.facts["variants"]:
            plain = variant["plain"]
            self.assertTrue(plain["owner"])
            self.assertFalse(plain["structural"])
            self.assertFalse(plain["executable"])
            self.assertEqual(plain["bindingProvider"], plain["selected"])
            unadmitted = variant["unadmitted"]
            self.assertFalse(unadmitted["owner"])
            self.assertTrue(unadmitted["refused"])
            self.assertFalse(unadmitted["executable"])


if __name__ == "__main__":
    unittest.main()
