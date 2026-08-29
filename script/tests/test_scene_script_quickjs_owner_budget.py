#!/usr/bin/env python3

"""QuickJS owner-construction instruction budget regression gate."""

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

#include <stdio.h>
#include <string.h>

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic ? diagnostic : "");
    return 1;
}

static MWXSceneQuickJSResult update(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    double *output,
    char diagnostic[512]
) {
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    return mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &frame, output, diagnostic, 512
    );
}

int main(void) {
    int failures = 0;
    char diagnostic[512] = {0};
    const uint64_t owner_budget = 160;
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, owner_budget,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(domain != NULL, "domain create", diagnostic);
    if (domain == NULL) return 1;

    const char *work_source =
        "let total=0;"
        "for(let index=0;index<600000;++index){total+=index;}"
        "export function update(value){return value+(total>=0?1:0);}";
    MWXSceneQuickJSOwner *first = mwx_scene_quickjs_owner_create(
        domain, work_source, strlen(work_source), 1,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(first != NULL, "first bounded owner", diagnostic);

    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *second = mwx_scene_quickjs_owner_create(
        domain, work_source, strlen(work_source), 2,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(
        second != NULL,
        "later owner receives independent construction budget",
        diagnostic
    );

    const char *infinite_source =
        "for(;;){} export function update(value){return value;}";
    MWXSceneQuickJSResult creation_result = MWX_SCENE_QUICKJS_OK;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *over_budget =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, infinite_source, strlen(infinite_source), 3, 2,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        over_budget == NULL &&
            creation_result == MWX_SCENE_QUICKJS_BUDGET_EXCEEDED,
        "single owner construction budget is typed",
        diagnostic
    );

    const char *syntax_error = "export function update( {";
    creation_result = MWX_SCENE_QUICKJS_OK;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *invalid =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, syntax_error, strlen(syntax_error), 4, owner_budget,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        invalid == NULL && creation_result == MWX_SCENE_QUICKJS_COMPILE_ERROR,
        "syntax failure remains compile error",
        diagnostic
    );

    const char *callback_source =
        "export function update(value){for(;;){}}";
    creation_result = MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *callback =
        mwx_scene_quickjs_owner_create_with_budget(
            domain, callback_source, strlen(callback_source), 5, owner_budget,
            &creation_result, diagnostic, sizeof(diagnostic)
        );
    failures += check(
        callback != NULL && creation_result == MWX_SCENE_QUICKJS_OK,
        "callback owner create",
        diagnostic
    );
    if (callback != NULL) {
        double output = 0;
        mwx_scene_quickjs_domain_reset_budget(domain, 2);
        diagnostic[0] = '\0';
        MWXSceneQuickJSResult callback_result = update(
            callback, 5, 1, &output, diagnostic
        );
        failures += check(
            callback_result == MWX_SCENE_QUICKJS_BUDGET_EXCEEDED,
            "frame callback budget remains typed",
            diagnostic
        );
    }

    diagnostic[0] = '\0';
    MWXSceneQuickJSOwner *after_callback = mwx_scene_quickjs_owner_create(
        domain,
        "export function update(value){return value+2;}",
        strlen("export function update(value){return value+2;}"),
        6,
        diagnostic,
        sizeof(diagnostic)
    );
    failures += check(
        after_callback != NULL,
        "callback exhaustion does not poison owner construction",
        diagnostic
    );
    if (after_callback != NULL) {
        double output = 0;
        mwx_scene_quickjs_domain_reset_budget(domain, owner_budget);
        diagnostic[0] = '\0';
        MWXSceneQuickJSResult result = update(
            after_callback, 6, 3, &output, diagnostic
        );
        failures += check(
            result == MWX_SCENE_QUICKJS_OK && output == 5,
            "frame budget reset remains independent",
            diagnostic
        );
    }

    if (after_callback != NULL) mwx_scene_quickjs_owner_destroy(after_callback);
    if (callback != NULL) mwx_scene_quickjs_owner_destroy(callback);
    if (invalid != NULL) mwx_scene_quickjs_owner_destroy(invalid);
    if (over_budget != NULL) mwx_scene_quickjs_owner_destroy(over_budget);
    if (second != NULL) mwx_scene_quickjs_owner_destroy(second);
    if (first != NULL) mwx_scene_quickjs_owner_destroy(first);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSOwnerBudgetTest(unittest.TestCase):
    def test_owner_construction_budget_is_independent_and_typed(self) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS budget gate")
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-owner-budget-"
        ) as temporary_directory:
            root = Path(temporary_directory)
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
                str(SCENE_SCRIPT / "SceneQuickJSValueHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSModuleHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSAnimationHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSAudioHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSMediaEventHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSHandleHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSLayerHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSLayerSnapshotHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSJobHost.c"),
                str(SCENE_SCRIPT / "SceneQuickJSTimerHost.c"),
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
            self.assertEqual(
                compilation.returncode,
                0,
                compilation.stdout + compilation.stderr,
            )
            execution = subprocess.run(
                [str(binary)], cwd=ROOT, capture_output=True, text=True
            )
            self.assertEqual(
                execution.returncode,
                0,
                execution.stdout + execution.stderr,
            )


if __name__ == "__main__":
    unittest.main()
