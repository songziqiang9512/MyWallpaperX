#include "SceneQuickJS.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Baseline call-boundary probe. Future supported-profile tests must publish
// real Swift-prepared particle facts here; do not invent a playing Bool.
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    FILE *file = fopen(argv[1], "rb");
    if (!file) return 2;
    fseek(file, 0, SEEK_END); long length = ftell(file); rewind(file);
    char *source = calloc((size_t)length + 1, 1);
    if (!source || fread(source, 1, (size_t)length, file) != (size_t)length) return 2;
    fclose(file);
    char diagnostic[1024] = {0};
    MWXSceneQuickJSDomain *domain = mwx_scene_quickjs_domain_create(
        2 * 1024 * 1024, 512 * 1024, 100000, diagnostic, sizeof(diagnostic));
    if (!domain) { fprintf(stderr, "domain: %s\n", diagnostic); return 2; }
    double origin[3] = {0}, size[2] = {100, 100};
    MWXSceneQuickJSResult result = mwx_scene_quickjs_domain_configure_layer_catalog(
        domain, 1, diagnostic, sizeof(diagnostic));
    if (result == MWX_SCENE_QUICKJS_OK) result = mwx_scene_quickjs_domain_set_layer_descriptor(
        domain, 0, 42, 0, 0, "particles", 9, origin, size, diagnostic, sizeof(diagnostic));
    MWXSceneQuickJSOwner *owner = result == MWX_SCENE_QUICKJS_OK
        ? mwx_scene_quickjs_owner_create(domain, source, (size_t)length, 47, diagnostic, sizeof(diagnostic)) : NULL;
    free(source);
    if (!owner) { fprintf(stderr, "owner: %s\n", diagnostic); return 2; }
    result = mwx_scene_quickjs_owner_configure_layer_identity(owner, 42, diagnostic, sizeof(diagnostic));
    if (result == MWX_SCENE_QUICKJS_OK) result = mwx_scene_quickjs_owner_set_property_object_scope(
        owner, 1, diagnostic, sizeof(diagnostic));
    if (result != MWX_SCENE_QUICKJS_OK) { fprintf(stderr, "identity: %s\n", diagnostic); return 2; }
    double scenario = strtod(argv[2], NULL), output = 0;
    MWXSceneQuickJSFrameInput frame = {.frame_time = 1.0 / 60.0, .runtime = 1.0};
    if (scenario >= 100) {
        uint32_t did_initialize = 0;
        result = mwx_scene_quickjs_owner_initialize_primitive_with_properties(
            owner, 47, scenario, 0, &frame, "", 0, "{}", 2,
            &output, &did_initialize, diagnostic, sizeof(diagnostic));
    } else {
        result = mwx_scene_quickjs_owner_update_scalar(
            owner, 47, scenario, &frame, &output, diagnostic, sizeof(diagnostic));
    }
    printf("scenario=%.0f result=%d output=%.0f diagnostic=%s\n", scenario, result, output, diagnostic);
    mwx_scene_quickjs_owner_destroy(owner);
    mwx_scene_quickjs_domain_destroy(domain);
    return result == MWX_SCENE_QUICKJS_OK ? 0 : 1;
}
