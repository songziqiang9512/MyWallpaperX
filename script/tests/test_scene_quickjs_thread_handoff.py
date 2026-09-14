"""Exclusive preparation-thread -> frame-thread QuickJS handoff regression."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
HARNESS = r'''
#include "SceneQuickJS.h"
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static MWXSceneQuickJSDomain *domain;
static MWXSceneQuickJSOwner *owner;
static char diagnostic[512];
static void *prepare(void *unused) {
    domain = mwx_scene_quickjs_domain_create(16*1024*1024, 512*1024,
        100000, diagnostic, sizeof(diagnostic));
    if (!domain) return NULL;
    const char *source = "export var scriptProperties = {}; export function update(value) {"
        "return scriptProperties.prefix + (Number(value) + 1); }";
    owner = mwx_scene_quickjs_owner_create(domain, source, strlen(source),
        1, diagnostic, sizeof(diagnostic));
    return NULL;
}
int main(int argc, char **argv) {
    pthread_t worker;
    if (pthread_create(&worker, NULL, prepare, NULL) || pthread_join(worker, NULL)) return 2;
    if (!owner) { fprintf(stderr, "%s", diagnostic); return 3; }
    if (argc == 1) mwx_scene_quickjs_domain_adopt_current_thread(domain);
    MWXSceneQuickJSFrameInput frame = {.time_of_day=.25, .frame_time=.016, .runtime=1};
    char output[128]; size_t length;
    const char *properties = "{\"prefix\":\"clock-\"}";
    for (int i=0; i<2; ++i) {
        mwx_scene_quickjs_domain_reset_budget(domain, 100000);
        MWXSceneQuickJSResult result = mwx_scene_quickjs_owner_update_string(
            owner, 1, i ? "2" : "1", 1, &frame, properties, strlen(properties),
            "{}", 2, output, sizeof(output), &length, diagnostic, sizeof(diagnostic));
        if (result != MWX_SCENE_QUICKJS_OK || strcmp(output, i ? "clock-3" : "clock-2")) {
            fprintf(stderr, "frame %d: %s\n", i, diagnostic); return 4;
        }
    }
    MWXSceneQuickJSResult stale = mwx_scene_quickjs_owner_update_string(
        owner, 2, "1", 1, &frame, properties, strlen(properties), "{}", 2,
        output, sizeof(output), &length, diagnostic, sizeof(diagnostic));
    if (stale != MWX_SCENE_QUICKJS_STALE_OWNER) return 5;
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return 0;
}
'''


class ThreadHandoffTests(unittest.TestCase):
    def test_background_preparation_then_main_thread_frames(self):
        with tempfile.TemporaryDirectory(prefix="mwx-vm-thread-") as directory:
            directory = Path(directory)
            harness = directory / "test.c"
            harness.write_text(HARNESS)
            binary = directory / "test"
            quickjs = SOURCE / "QuickJSNG"
            sources = sorted(SOURCE.glob("SceneQuickJS*.c")) + [
                quickjs / name for name in ("quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c")
            ]
            subprocess.run(["clang", "-std=c11", "-O0", "-I", str(SOURCE),
                            "-I", str(quickjs), *map(str, sources), str(harness),
                            "-lm", "-pthread", "-o", str(binary)], check=True,
                           capture_output=True, text=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            if sys.platform == "darwin":
                # macOS worker and main stacks have distinct native boundaries.
                stale_stack = subprocess.run([str(binary), "skip-handoff"],
                                             capture_output=True, text=True)
                self.assertEqual(stale_stack.returncode, 4, stale_stack.stderr)


if __name__ == "__main__":
    unittest.main()
