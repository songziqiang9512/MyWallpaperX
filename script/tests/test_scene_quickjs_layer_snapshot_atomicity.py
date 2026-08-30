#!/usr/bin/env python3

"""Atomic QuickJS layer-snapshot staging and rollback gate."""

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
#include "SceneQuickJSInternal.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void mwx_scene_quickjs_write_diagnostic(
    char *diagnostic,
    size_t capacity,
    const char *message
) {
    if (diagnostic == NULL || capacity == 0) return;
    snprintf(diagnostic, capacity, "%s", message == NULL ? "" : message);
}

static char *duplicate_string(const char *source) {
    size_t length = strlen(source);
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    memcpy(copy, source, length + 1);
    return copy;
}

static int check(int condition, const char *label, const char *diagnostic) {
    if (condition) return 0;
    fprintf(stderr, "FAIL %s: %s\n", label, diagnostic == NULL ? "" : diagnostic);
    return 1;
}

static int check_number(double actual, double expected, const char *label) {
    if (fabs(actual - expected) < 0.000001) return 0;
    fprintf(stderr, "FAIL %s: actual=%f expected=%f\n", label, actual, expected);
    return 1;
}

static int configure_record(
    MWXSceneQuickJSLayerRecord *record,
    int64_t layer_id,
    double authored_origin,
    const char *text
) {
    memset(record, 0, sizeof(*record));
    record->layer_id = layer_id;
    record->configured = true;
    record->visible = true;
    record->alpha = 1;
    record->point_size = 32;
    record->name = duplicate_string("layer");
    record->text = duplicate_string(text);
    record->font = duplicate_string("font");
    for (size_t index = 0; index < 3; ++index) {
        record->authored_origin[index] = authored_origin;
        record->current_origin[index] = authored_origin;
        record->scale[index] = 1;
        record->color[index] = 1;
    }
    return record->name != NULL && record->text != NULL && record->font != NULL;
}

static MWXSceneQuickJSResult stage_fields(
    MWXSceneQuickJSDomain *domain,
    uint32_t layer_index,
    double scale_value,
    double color_value,
    const char *text,
    char diagnostic[256]
) {
    double scale[3] = {scale_value, scale_value, scale_value};
    double angles[3] = {0, 0, 0};
    double color[3] = {color_value, color_value, color_value};
    return mwx_scene_quickjs_domain_update_layer_runtime_fields(
        domain,
        layer_index,
        scale,
        angles,
        1,
        1,
        text,
        strlen(text),
        "font",
        4,
        32,
        color,
        diagnostic,
        256
    );
}

int main(void) {
    int failures = 0;
    char diagnostic[256] = {0};
    MWXSceneQuickJSDomain domain = {0};
    domain.layers = calloc(2, sizeof(*domain.layers));
    failures += check(domain.layers != NULL, "layer allocation", diagnostic);
    if (domain.layers == NULL) return 1;
    domain.layer_count = 2;
    domain.authored_layer_count = 2;
    domain.layer_snapshot_generation = 7;
    failures += check(
        configure_record(&domain.layers[0], 10, 0, "old-a"),
        "first record configuration",
        diagnostic
    );
    failures += check(
        configure_record(&domain.layers[1], 20, 1, "old-b"),
        "second record configuration",
        diagnostic
    );

    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        &domain, 8, diagnostic, sizeof(diagnostic)
    );
    failures += check(result == MWX_SCENE_QUICKJS_OK, "begin commit", diagnostic);
    result = stage_fields(&domain, 0, 2, 0.25, "new-a", diagnostic);
    failures += check(result == MWX_SCENE_QUICKJS_OK, "stage first", diagnostic);
    result = stage_fields(&domain, 1, 3, 0.75, "new-b", diagnostic);
    failures += check(result == MWX_SCENE_QUICKJS_OK, "stage second", diagnostic);
    double committed_origin[3] = {9, 8, 7};
    result = mwx_scene_quickjs_domain_set_layer_origin(
        &domain, 0, committed_origin, diagnostic, sizeof(diagnostic)
    );
    failures += check(result == MWX_SCENE_QUICKJS_OK, "stage origin", diagnostic);
    result = mwx_scene_quickjs_domain_commit_layer_snapshot(
        &domain, diagnostic, sizeof(diagnostic)
    );
    failures += check(result == MWX_SCENE_QUICKJS_OK, "commit", diagnostic);
    failures += check(domain.layer_snapshot_generation == 8, "committed generation", diagnostic);
    failures += check(strcmp(domain.layers[0].text, "new-a") == 0, "committed first text", diagnostic);
    failures += check_number(domain.layers[0].scale[0], 2, "committed first scale");
    failures += check_number(domain.layers[0].color[0], 0.25, "committed first color");
    failures += check_number(domain.layers[0].current_origin[0], 9, "committed explicit origin");
    failures += check(strcmp(domain.layers[1].text, "new-b") == 0, "committed second text", diagnostic);
    failures += check_number(domain.layers[1].scale[0], 3, "committed second scale");
    failures += check_number(domain.layers[1].color[0], 0.75, "committed second color");
    failures += check_number(domain.layers[1].current_origin[0], 1, "committed authored origin");

    result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        &domain, 9, diagnostic, sizeof(diagnostic)
    );
    failures += check(result == MWX_SCENE_QUICKJS_OK, "begin rollback", diagnostic);
    result = stage_fields(&domain, 0, 7, 0.9, "poisoned-a", diagnostic);
    failures += check(result == MWX_SCENE_QUICKJS_OK, "stage rollback first", diagnostic);
    double invalid_scale[3] = {NAN, 4, 4};
    double angles[3] = {0, 0, 0};
    double color[3] = {1, 1, 1};
    result = mwx_scene_quickjs_domain_update_layer_runtime_fields(
        &domain, 1, invalid_scale, angles, 1, 1,
        "poisoned-b", 10, "font", 4, 32, color,
        diagnostic, sizeof(diagnostic)
    );
    failures += check(
        result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "later layer failure is typed",
        diagnostic
    );
    failures += check(domain.layer_snapshot_generation == 8, "failed generation unchanged", diagnostic);
    failures += check(strcmp(domain.layers[0].text, "new-a") == 0, "first active text unchanged before abort", diagnostic);
    failures += check_number(domain.layers[0].scale[0], 2, "first active scale unchanged before abort");
    failures += check_number(domain.layers[0].color[0], 0.25, "first active color unchanged before abort");
    mwx_scene_quickjs_domain_abort_layer_snapshot(&domain);
    failures += check(domain.pending_layer_snapshot == NULL, "abort clears pending", diagnostic);
    failures += check(domain.layer_snapshot_generation == 8, "aborted generation unchanged", diagnostic);
    failures += check(strcmp(domain.layers[0].text, "new-a") == 0, "first active text unchanged after abort", diagnostic);
    failures += check_number(domain.layers[0].scale[0], 2, "first active scale unchanged after abort");
    failures += check_number(domain.layers[0].color[0], 0.25, "first active color unchanged after abort");

    result = mwx_scene_quickjs_domain_begin_layer_snapshot(
        &domain, 9, diagnostic, sizeof(diagnostic)
    );
    failures += check(result == MWX_SCENE_QUICKJS_OK, "begin incomplete", diagnostic);
    result = stage_fields(&domain, 0, 5, 0.6, "incomplete-a", diagnostic);
    failures += check(result == MWX_SCENE_QUICKJS_OK, "stage incomplete first", diagnostic);
    result = mwx_scene_quickjs_domain_commit_layer_snapshot(
        &domain, diagnostic, sizeof(diagnostic)
    );
    failures += check(
        result == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "incomplete commit rejected",
        diagnostic
    );
    failures += check(domain.layer_snapshot_generation == 8, "incomplete generation unchanged", diagnostic);
    failures += check(strcmp(domain.layers[0].text, "new-a") == 0, "incomplete active text unchanged", diagnostic);
    failures += check_number(domain.layers[0].color[0], 0.25, "incomplete active color unchanged");
    mwx_scene_quickjs_domain_abort_layer_snapshot(&domain);

    for (uint32_t index = 0; index < domain.layer_count; ++index) {
        free(domain.layers[index].name);
        free(domain.layers[index].text);
        free(domain.layers[index].font);
    }
    free(domain.layers);
    return failures == 0 ? 0 : 1;
}
'''


class SceneQuickJSLayerSnapshotAtomicityTest(unittest.TestCase):
    def test_late_layer_failure_preserves_active_snapshot(self) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the layer snapshot gate")
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-layer-snapshot-"
        ) as temporary_directory:
            temporary = Path(temporary_directory)
            harness = temporary / "harness.c"
            binary = temporary / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    clang,
                    "-std=c11",
                    "-O0",
                    "-I",
                    str(SCENE_SCRIPT),
                    "-I",
                    str(QUICKJS),
                    str(SCENE_SCRIPT / "SceneQuickJSLayerSnapshotHost.c"),
                    str(harness),
                    "-lm",
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
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
