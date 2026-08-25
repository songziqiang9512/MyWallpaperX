#!/usr/bin/env python3

"""Contract gate for the bounded QuickJS-NG SceneScript scalar owner."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_SCRIPT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript"
QUICKJS = SCENE_SCRIPT / "QuickJSNG"

HARNESS = r'''
#include "SceneQuickJS.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}

static int update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    double output = 0;
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &output, diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected
            && (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}

static int mutation(
    MWXSceneQuickJSOwner *owner,
    size_t index,
    uint32_t expected_effect,
    const char *expected_name,
    const char *label
) {
    char diagnostic[512] = {0};
    char name[128] = {0};
    uint32_t effect = 0;
    MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_material_function_at(
        owner, index, &effect, name, sizeof(name), diagnostic, sizeof(diagnostic)
    );
    return check(
        result == MWX_SCENE_QUICKJS_OK
            && effect == expected_effect
            && strcmp(name, expected_name) == 0,
        label,
        diagnostic
    );
}

int main(void) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic)
    );
    if (check(domain != NULL, "domain", diagnostic)) return 1;

    int failures = 0;
    MWXSceneQuickJSOwner *positive = mwx_scene_quickjs_owner_create(
        domain,
        "'use strict';\n"
        "export let __workshopId = 'contract';\n"
        "export function init(value) { return value + 1; }\n"
        "export function update(value) {\n"
        "  thisLayer.getEffect(2).executeMaterialFunction('clearHistory');\n"
        "  return value * 2;\n"
        "}",
        strlen(
            "'use strict';\n"
            "export let __workshopId = 'contract';\n"
            "export function init(value) { return value + 1; }\n"
            "export function update(value) {\n"
            "  thisLayer.getEffect(2).executeMaterialFunction('clearHistory');\n"
            "  return value * 2;\n"
            "}"
        ),
        1,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(positive != NULL, "positive compile", diagnostic);
    failures += update(
        positive, 1, 3, MWX_SCENE_QUICKJS_OK, 8, "init/update"
    );
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(positive) == 1,
        "mutation count",
        ""
    );
    failures += mutation(positive, 0, 2, "clearHistory", "mutation identity");

    MWXSceneQuickJSOwner *cross_owner = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) {\n"
        "  thisLayer.getEffect(9).executeMaterialFunction('crossOwner');\n"
        "  return value;\n"
        "}",
        strlen(
            "export function update(value) {\n"
            "  thisLayer.getEffect(9).executeMaterialFunction('crossOwner');\n"
            "  return value;\n"
            "}"
        ),
        10, diagnostic, sizeof(diagnostic)
    );
    failures += check(cross_owner != NULL, "cross-owner compile", diagnostic);
    failures += update(
        cross_owner, 10, 3, MWX_SCENE_QUICKJS_OK, 3, "cross-owner callback"
    );
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(cross_owner) == 1,
        "cross-owner mutation count",
        ""
    );
    failures += update(
        positive, 1, 7, MWX_SCENE_QUICKJS_OK, 14, "second callback"
    );
    failures += mutation(positive, 0, 2, "clearHistory", "cross-owner isolation");
    failures += check(
        mwx_scene_quickjs_owner_material_function_count(positive) == 1,
        "mutation reset",
        ""
    );

    MWXSceneQuickJSOwner *isolated = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) { return value + 10; }",
        strlen("export function update(value) { return value + 10; }"),
        2,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(isolated != NULL, "owner isolation compile", diagnostic);
    failures += update(
        isolated, 2, 3, MWX_SCENE_QUICKJS_OK, 13, "owner isolation"
    );

    MWXSceneQuickJSOwner *metadata_only = mwx_scene_quickjs_owner_create(
        domain,
        "export let __workshopId = 'metadata-only';",
        strlen("export let __workshopId = 'metadata-only';"),
        7, diagnostic, sizeof(diagnostic)
    );
    failures += check(metadata_only != NULL, "export metadata compile", diagnostic);
    failures += update(
        metadata_only, 7, 5, MWX_SCENE_QUICKJS_OK, 5, "missing callbacks preserve input"
    );

    MWXSceneQuickJSOwner *unresolved_import = mwx_scene_quickjs_owner_create(
        domain,
        "import * as WEMath from 'WEMath';\n"
        "export function update(value) { return WEMath.abs(value); }",
        strlen(
            "import * as WEMath from 'WEMath';\n"
            "export function update(value) { return WEMath.abs(value); }"
        ),
        8, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        unresolved_import == NULL,
        "unresolved import fails closed",
        diagnostic
    );

    MWXSceneQuickJSOwner *compile_error = mwx_scene_quickjs_owner_create(
        domain, "function update(value) {", strlen("function update(value) {"),
        3, diagnostic, sizeof(diagnostic)
    );
    failures += check(compile_error == NULL, "compile exception", diagnostic);

    MWXSceneQuickJSOwner *callback_error = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) { throw new Error('callback'); }",
        strlen("export function update(value) { throw new Error('callback'); }"),
        4, diagnostic, sizeof(diagnostic)
    );
    failures += check(callback_error != NULL, "callback compile", diagnostic);
    failures += update(
        callback_error, 4, 1, MWX_SCENE_QUICKJS_EXCEPTION, 0,
        "callback exception"
    );
    failures += update(
        callback_error, 4, 1, MWX_SCENE_QUICKJS_DISABLED, 0,
        "callback disabled after exception"
    );

    MWXSceneQuickJSOwner *bad_return = mwx_scene_quickjs_owner_create(
        domain, "export function update(value) { return {}; }",
        strlen("export function update(value) { return {}; }"),
        5, diagnostic, sizeof(diagnostic)
    );
    failures += check(bad_return != NULL, "bad return compile", diagnostic);
    failures += update(
        bad_return, 5, 1, MWX_SCENE_QUICKJS_BAD_RETURN, 0, "bad return"
    );

    MWXSceneQuickJSOwner *budget = mwx_scene_quickjs_owner_create(
        domain, "export function update(value) { while (true) { value = value; }; }",
        strlen("export function update(value) { while (true) { value = value; }; }"),
        6, diagnostic, sizeof(diagnostic)
    );
    failures += check(budget != NULL, "budget compile", diagnostic);
    mwx_scene_quickjs_domain_reset_budget(domain, 32);
    failures += update(
        budget, 6, 1, MWX_SCENE_QUICKJS_BUDGET_EXCEEDED, 0, "interrupt budget"
    );

    MWXSceneQuickJSOwner *mutation_overflow = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value) {\n"
        "  for (let i = 0; i < 17; ++i) {\n"
        "    thisLayer.getEffect(i).executeMaterialFunction('clear');\n"
        "  }\n"
        "  return value;\n"
        "}",
        strlen(
            "export function update(value) {\n"
            "  for (let i = 0; i < 17; ++i) {\n"
            "    thisLayer.getEffect(i).executeMaterialFunction('clear');\n"
            "  }\n"
            "  return value;\n"
            "}"
        ),
        9, diagnostic, sizeof(diagnostic)
    );
    failures += check(mutation_overflow != NULL, "mutation overflow compile", diagnostic);
    failures += update(
        mutation_overflow, 9, 1, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 0,
        "mutation overflow"
    );

    mwx_scene_quickjs_owner_invalidate(positive);
    failures += update(
        positive, 1, 3, MWX_SCENE_QUICKJS_STALE_OWNER, 0, "stale owner"
    );

    mwx_scene_quickjs_owner_destroy(budget);
    mwx_scene_quickjs_owner_destroy(cross_owner);
    mwx_scene_quickjs_owner_destroy(mutation_overflow);
    mwx_scene_quickjs_owner_destroy(bad_return);
    mwx_scene_quickjs_owner_destroy(callback_error);
    mwx_scene_quickjs_owner_destroy(isolated);
    mwx_scene_quickjs_owner_destroy(positive);
    mwx_scene_quickjs_owner_destroy(metadata_only);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS contract gate")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-"
        )
        root = Path(cls._temporary_directory.name)
        harness = root / "harness.c"
        binary = root / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        command = [
            clang,
            "-std=c11",
            "-O0",
            "-I",
            str(SCENE_SCRIPT),
            "-I",
            str(QUICKJS),
            str(SCENE_SCRIPT / "SceneQuickJS.c"),
            str(QUICKJS / "quickjs.c"),
            str(QUICKJS / "dtoa.c"),
            str(QUICKJS / "libregexp.c"),
            str(QUICKJS / "libunicode.c"),
            str(harness),
            "-lm",
            "-o",
            str(binary),
        ]
        compilation = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True
        )
        if compilation.returncode != 0:
            cls._temporary_directory.cleanup()
            raise AssertionError(
                "QuickJS contract harness did not compile:\n"
                + compilation.stdout
                + compilation.stderr
            )
        cls._binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_real_ecmascript_owner_contract(self) -> None:
        completed = subprocess.run(
            [str(self._binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )

    def test_host_wiring_preserves_public_frame_order_and_route(self) -> None:
        launch = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        frame = (
            ROOT
            / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("excludedTargets: boundedSceneScriptTargets", launch)
        self.assertIn("fallback=bounded-swift-prefer-generic", launch)
        bounded_ownership = launch[
            launch.index("let boundedProducerTargets:"):
            launch.index("nextSceneScriptGeneration &+= 1")
        ]
        for producer in (
            "launch-origin",
            "hover-origin",
            "audio-scaled",
            "property-vector",
            "media-placeholder",
            "media-color",
        ):
            self.assertIn(f'("{producer}"', bounded_ownership)
        self.assertNotIn('("time-of-day"', bounded_ownership)
        self.assertIn(
            "targets.isDisjoint(with: propertyBindingTargets)",
            bounded_ownership,
        )
        self.assertIn(
            "targets.isDisjoint(with: timelineTargets)",
            bounded_ownership,
        )
        self.assertIn(
            "targets.isDisjoint(with: boundedSceneScriptTargets)",
            bounded_ownership,
        )
        scalar_ownership = launch[
            launch.index("let sceneScriptScalarTargets ="):
            launch.index("let provenSceneScriptValueTargets =")
        ]
        self.assertIn(
            "sceneScriptScalarTargets.isDisjoint(with: boundedSceneScriptTargets)",
            scalar_ownership,
        )
        self.assertNotIn("propertyBindingProgram", scalar_ownership)
        self.assertNotIn("timelineProgram", scalar_ownership)
        time_of_day_ownership = launch[
            launch.index("let sceneScriptConsumerTargets ="):
            launch.index("guard let mediaPlaybackPlaceholderFadeProgram =")
        ]
        self.assertIn(
            "SceneTimeOfDayEffectScriptProgram.validatedConsumers(",
            time_of_day_ownership,
        )
        self.assertIn(
            "candidates: timeOfDayEffectScriptCandidates",
            time_of_day_ownership,
        )
        self.assertIn(
            "consumerTargets: sceneScriptConsumerTargets",
            time_of_day_ownership,
        )
        self.assertIn(
            "conflictingTargets: timeOfDayEffectScriptConflictingTargets",
            time_of_day_ownership,
        )
        self.assertLess(
            launch.index("let sceneScriptConsumerTargets ="),
            launch.index("SceneTimeOfDayEffectScriptProgram.validatedConsumers("),
        )
        timeline = frame.index("let timelineValues = SceneTimelineRuntime.values")
        preliminary = frame.index("let preliminaryForSceneScript =")
        evaluate = frame.index("let sceneScriptResult = launchContext.sceneScriptScalarProgram.evaluate")
        final_snapshot = frame.index("let resolvedDynamicValues = surface.evaluationTransaction.evaluate")
        self.assertLess(timeline, preliminary)
        self.assertLess(preliminary, evaluate)
        self.assertLess(evaluate, final_snapshot)
        self.assertIn("sceneScriptScalarProgram.invalidate()", frame)


if __name__ == "__main__":
    unittest.main()
