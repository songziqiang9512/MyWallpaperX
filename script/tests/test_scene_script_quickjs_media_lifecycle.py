#!/usr/bin/env python3

"""Focused QuickJS media-value, export-probe, and teardown contracts."""

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

static int update_owner(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double input,
    MWXSceneQuickJSResult expected,
    double expected_output,
    const char *label
) {
    char diagnostic[512] = {0};
    double output = 0;
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSResult actual = mwx_scene_quickjs_owner_update_scalar(
        owner, generation, input, &frame, &output,
        diagnostic, sizeof(diagnostic)
    );
    return check(
        actual == expected &&
            (expected != MWX_SCENE_QUICKJS_OK || output == expected_output),
        label,
        diagnostic
    );
}

static int configure_owner_layer(
    MWXSceneQuickJSOwner *owner,
    int64_t layer_id,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_layer_identity(
            owner, layer_id, diagnostic, sizeof(diagnostic)
        );
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int configure_effects(
    MWXSceneQuickJSOwner *owner,
    uint32_t count,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_owner_configure_effect_catalog(
            owner, count, diagnostic, sizeof(diagnostic)
        );
    return check(result == MWX_SCENE_QUICKJS_OK, label, diagnostic);
}

static int configure_layers(MWXSceneQuickJSDomain *domain) {
    char diagnostic[512] = {0};
    const double origin[3] = {0, 0, 0};
    MWXSceneQuickJSResult result =
        mwx_scene_quickjs_domain_configure_layer_catalog(
            domain, 1, diagnostic, sizeof(diagnostic)
        );
    if (result == MWX_SCENE_QUICKJS_OK) {
        result = mwx_scene_quickjs_domain_set_layer_descriptor(
            domain, 0, 42, 0, 0, "media", strlen("media"), origin,
            diagnostic, sizeof(diagnostic)
        );
    }
    return check(result == MWX_SCENE_QUICKJS_OK, "layer catalog", diagnostic);
}

static int dispatch_colors(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    double primary_red,
    MWXSceneQuickJSResult expected,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 1.0 / 60.0,
        .runtime = 2.0,
    };
    MWXSceneQuickJSMediaThumbnailEvent event = {
        .has_thumbnail = 1,
        .primary_red = primary_red,
        .primary_green = 0.2,
        .primary_blue = 0.3,
        .secondary_red = 0,
        .secondary_green = 0,
        .secondary_blue = 0,
        .tertiary_red = 0.7,
        .tertiary_green = 0.8,
        .tertiary_blue = 0.9,
        .text_red = 1,
        .text_green = 1,
        .text_blue = 1,
        .high_contrast_red = 0,
        .high_contrast_green = 0,
        .high_contrast_blue = 0,
    };
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_dispatch_media_thumbnail(
            owner, generation, &event, &frame, "{}", 2,
            diagnostic, sizeof(diagnostic)
        );
    return check(actual == expected, label, diagnostic);
}

static int teardown_owner(
    MWXSceneQuickJSOwner *owner,
    uint64_t generation,
    MWXSceneQuickJSResult expected,
    uint32_t expected_invoked,
    uint32_t expected_threw,
    uint32_t expected_destroy_count,
    const char *label
) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSFrameInput frame = {
        .time_of_day = 0.25,
        .frame_time = 0,
        .runtime = 3,
    };
    uint32_t invoked = 0;
    uint32_t threw = 0;
    MWXSceneQuickJSResult actual =
        mwx_scene_quickjs_owner_teardown_with_provenance(
            owner, generation, &frame, NULL, 0, "{}", 2,
            &invoked, &threw, diagnostic, sizeof(diagnostic)
        );
    MWXSceneQuickJSLifecycleSnapshot snapshot = {0};
    MWXSceneQuickJSResult snapshot_result =
        mwx_scene_quickjs_owner_lifecycle_snapshot(owner, &snapshot);
    return check(
        actual == expected && invoked == expected_invoked &&
            threw == expected_threw &&
            snapshot_result == MWX_SCENE_QUICKJS_OK &&
            snapshot.teardown_started == 1 &&
            snapshot.destroy_callback_count == expected_destroy_count &&
            snapshot.active_timer_count == 0 &&
            snapshot.pending_layer_mutation_count == 0 &&
            snapshot.active_dynamic_layer_count == 0 &&
            snapshot.has_job_residue == 0 && snapshot.callback_active == 0,
        label,
        diagnostic
    );
}

int main(void) {
    char diagnostic[512] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 200000,
        diagnostic, sizeof(diagnostic)
    );
    if (check(domain != NULL, "domain", diagnostic)) return 1;

    int failures = 0;
    failures += configure_layers(domain);
    const char *media_source =
        "'use strict';let score=0;"
        "export function mediaThumbnailChanged(event){"
        "if(!event.hasThumbnail||!Object.isFrozen(event)||"
        "!Object.isFrozen(event.primaryColor)||"
        "!Object.isFrozen(event.secondaryColor)||"
        "!Object.isFrozen(event.tertiaryColor)||"
        "!Object.isFrozen(event.textColor)||"
        "!Object.isFrozen(event.highContrastColor))throw new Error('freeze');"
        "if(event.primaryColor.toString()!=='0.1 0.2 0.3'||"
        "event.tertiaryColor.toString()!=='0.7 0.8 0.9'||"
        "new Vec3('0 0 0').toString()!=='0 0 0'||"
        "new Vec3('1, 2, 3').toString()!=='1 2 3')throw new Error('Vec3');"
        "let invalid=false;try{new Vec3('0 0');}catch(e){invalid=true;}"
        "if(!invalid)throw new Error('invalid Vec3 accepted');"
        "let rejected=false;try{event.primaryColor.x=0.9;}catch(e){rejected=true;}"
        "if(!rejected||event.primaryColor.x!==0.1)throw new Error('mutable');"
        "score=event.primaryColor.x+event.tertiaryColor.z+event.textColor.x+"
        "(event.secondaryColor=='0 0 0'?10:0);"
        "}export function update(){return score;}";
    MWXSceneQuickJSOwner *media = mwx_scene_quickjs_owner_create(
        domain, media_source, strlen(media_source),
        100, diagnostic, sizeof(diagnostic)
    );
    failures += check(media != NULL, "media colors compile", diagnostic);
    if (media == NULL) {
        mwx_scene_quickjs_domain_destroy(domain);
        return 1;
    }

    uint32_t available = 0;
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "mediaThumbnailChanged", 21, &available,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && available == 1,
        "present callback export is explicit",
        diagnostic
    );
    available = 1;
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "cursorClick", 11, &available,
            diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_OK && available == 0,
        "missing callback export is explicit",
        diagnostic
    );
    failures += check(
        mwx_scene_quickjs_owner_has_function(
            media, "", 0, &available, diagnostic, sizeof(diagnostic)
        ) == MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "callback export query failure is typed",
        diagnostic
    );
    failures += dispatch_colors(
        media, 100, 0.1, MWX_SCENE_QUICKJS_OK,
        "five-color event is an immutable Vec3 DTO"
    );
    failures += update_owner(
        media, 100, 0, MWX_SCENE_QUICKJS_OK, 12,
        "five-color event state reaches update"
    );
    failures += dispatch_colors(
        media, 100, NAN, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "five-color event rejects nonfinite payload"
    );
    failures += dispatch_colors(
        media, 100, 1.1, MWX_SCENE_QUICKJS_INVALID_ARGUMENT,
        "five-color event rejects out-of-range payload"
    );
    failures += update_owner(
        media, 100, 0, MWX_SCENE_QUICKJS_OK, 12,
        "invalid media payload does not disable its owner"
    );

    const char *peer_source =
        "export function update(value){return value+10;}";
    MWXSceneQuickJSOwner *peer = mwx_scene_quickjs_owner_create(
        domain, peer_source, strlen(peer_source),
        101, diagnostic, sizeof(diagnostic)
    );
    failures += check(peer != NULL, "peer owner compile", diagnostic);
    if (peer == NULL) {
        mwx_scene_quickjs_owner_destroy(media);
        mwx_scene_quickjs_domain_destroy(domain);
        return 1;
    }
    failures += update_owner(
        peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
        "peer owner precondition"
    );

    const char *teardown_source =
        "export function init(value){"
        "thisScene.createLayer({text:'live'});"
        "engine.setInterval(()=>{},1000);return value;}"
        "export function destroy(){"
        "thisScene.createLayer({text:'destroy'});"
        "engine.setTimeout(()=>{},0);Promise.resolve().then(()=>{});}";
    MWXSceneQuickJSOwner *teardown = mwx_scene_quickjs_owner_create(
        domain, teardown_source, strlen(teardown_source),
        102, diagnostic, sizeof(diagnostic)
    );
    failures += check(teardown != NULL, "teardown owner compile", diagnostic);
    if (teardown != NULL) {
        failures += configure_owner_layer(
            teardown, 42, "teardown owner identity"
        );
        failures += update_owner(
            teardown, 102, 1, MWX_SCENE_QUICKJS_OK, 1,
            "teardown owner initialized"
        );
        MWXSceneQuickJSLifecycleSnapshot before_teardown = {0};
        failures += check(
            mwx_scene_quickjs_owner_lifecycle_snapshot(
                teardown, &before_teardown
            ) == MWX_SCENE_QUICKJS_OK &&
                before_teardown.active_timer_count == 1 &&
                before_teardown.active_dynamic_layer_count == 1,
            "teardown precondition has live resources",
            diagnostic
        );
        failures += teardown_owner(
            teardown, 102, MWX_SCENE_QUICKJS_OK, 1, 0, 1,
            "destroy succeeds once and resources quiesce"
        );
        failures += teardown_owner(
            teardown, 102, MWX_SCENE_QUICKJS_OK, 0, 0, 1,
            "teardown is idempotent"
        );
        failures += update_owner(
            teardown, 102, 1, MWX_SCENE_QUICKJS_STALE_OWNER, 0,
            "teardown revokes old generation"
        );
    }

    const char *exception_source =
        "export function update(value){return value;}"
        "export function destroy(){thisScene.createLayer({text:'discard'});"
        "engine.setInterval(()=>{},1);throw new Error('destroy failure');}";
    MWXSceneQuickJSOwner *exception = mwx_scene_quickjs_owner_create(
        domain, exception_source, strlen(exception_source),
        103, diagnostic, sizeof(diagnostic)
    );
    failures += check(exception != NULL, "teardown exception compile", diagnostic);
    if (exception != NULL) {
        failures += configure_owner_layer(
            exception, 42, "teardown exception identity"
        );
        failures += update_owner(
            exception, 103, 2, MWX_SCENE_QUICKJS_OK, 2,
            "teardown exception owner active"
        );
        failures += teardown_owner(
            exception, 103, MWX_SCENE_QUICKJS_EXCEPTION, 1, 1, 1,
            "destroy exception is proven and quiescent"
        );
        failures += update_owner(
            peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
            "destroy exception preserves peer owner"
        );
    }

    const char *overflow_source =
        "export function update(value){return value;}"
        "export function destroy(){for(let i=0;i<17;i+=1)"
        "thisLayer.getEffect(i).executeMaterialFunction('clear');}";
    MWXSceneQuickJSOwner *overflow = mwx_scene_quickjs_owner_create(
        domain, overflow_source, strlen(overflow_source),
        104, diagnostic, sizeof(diagnostic)
    );
    failures += check(overflow != NULL, "teardown overflow compile", diagnostic);
    if (overflow != NULL) {
        failures += configure_owner_layer(
            overflow, 42, "teardown overflow identity"
        );
        failures += configure_effects(
            overflow, 17, "teardown overflow effect catalog"
        );
        failures += teardown_owner(
            overflow, 104, MWX_SCENE_QUICKJS_MUTATION_OVERFLOW, 1, 1, 1,
            "destroy mutation overflow is integrity-typed and quiescent"
        );
        failures += update_owner(
            peer, 101, 2, MWX_SCENE_QUICKJS_OK, 12,
            "destroy overflow preserves peer owner"
        );
    }

    if (overflow != NULL) mwx_scene_quickjs_owner_destroy(overflow);
    if (exception != NULL) mwx_scene_quickjs_owner_destroy(exception);
    if (teardown != NULL) mwx_scene_quickjs_owner_destroy(teardown);
    mwx_scene_quickjs_owner_destroy(peer);
    mwx_scene_quickjs_owner_destroy(media);
    mwx_scene_quickjs_domain_destroy(domain);
    return failures == 0 ? 0 : 1;
}
'''


class SceneScriptQuickJSMediaLifecycleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required for the QuickJS contract gate")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-quickjs-media-lifecycle-"
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
            str(SCENE_SCRIPT / "SceneQuickJSValueHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSModuleHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSAnimationHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSAudioHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSMediaEventHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSHandleHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSLayerHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSLayerSnapshotHost.c"),
            str(SCENE_SCRIPT / "SceneQuickJSStorageHost.c"),
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
        if compilation.returncode != 0:
            cls._temporary_directory.cleanup()
            raise AssertionError(
                "QuickJS media/lifecycle harness did not compile:\n"
                + compilation.stdout
                + compilation.stderr
            )
        cls._binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_media_value_export_and_teardown_contracts(self) -> None:
        completed = subprocess.run(
            [str(self._binary)], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stdout + completed.stderr,
        )

    def test_export_probe_errors_fail_owner_construction(self) -> None:
        bridge = (SCENE_SCRIPT / "SceneScriptMediaEventBridge.swift").read_text(
            encoding="utf-8"
        )
        owner_runtimes = [
            (SCENE_SCRIPT / name).read_text(encoding="utf-8")
            for name in (
                "SceneScriptScalarRuntime.swift",
                "SceneScriptStringRuntime.swift",
                "SceneScriptVectorRuntime.swift",
            )
        ]
        self.assertIn(
            "static func contains(_ name: String, owner: OpaquePointer) throws -> Bool",
            bridge,
        )
        self.assertIn("guard result == MWX_SCENE_QUICKJS_OK else", bridge)
        self.assertIn("throw failure(result, diagnostic: diagnostic)", bridge)
        self.assertNotIn(
            "return result == MWX_SCENE_QUICKJS_OK && available == 1",
            bridge,
        )
        for owner_runtime in owner_runtimes:
            self.assertIn(
                "try SceneScriptOwnerExportBridge.contains(", owner_runtime
            )


if __name__ == "__main__":
    unittest.main()
