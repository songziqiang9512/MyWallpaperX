#include "SceneQuickJSInternal.h"

#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum PuppetBoneFunction {
    PUPPET_BONE_COUNT, PUPPET_BONE_INDEX, PUPPET_BONE_PARENT_INDEX,
    PUPPET_BONE_GET_WORLD, PUPPET_BONE_GET_LOCAL,
    PUPPET_BONE_SET_WORLD, PUPPET_BONE_SET_LOCAL,
    PUPPET_BONE_GET_LOCAL_ORIGIN, PUPPET_BONE_SET_LOCAL_ORIGIN,
    PUPPET_BONE_APPLY_IMPULSE,
};

JSValue mwx_scene_quickjs_layer_make_mat4(JSContext *context, MWXSceneQuickJSDomain *domain,
                         const double matrix[16]) {
    JSValue values = JS_NewArray(context);
    if (JS_IsException(values)) return values;
    for (uint32_t i = 0; i < 16; ++i) {
        JSValue v = JS_NewFloat64(context, matrix[i]);
        if (JS_SetPropertyUint32(context, values, i, v) < 0) {
            JS_FreeValue(context, values);
            return JS_EXCEPTION;
        }
    }
    JSValue args[1] = { values };
    JSValue result = JS_CallConstructor(context, domain->mat4_constructor, 1, args);
    JS_FreeValue(context, values);
    return result;
}

static bool read_mat4(JSContext *context, JSValueConst value, double output[16]) {
    if (!JS_IsObject(value)) return false;
    JSValue elements = JS_GetPropertyStr(context, value, "m");
    if (JS_IsException(elements) || !JS_IsObject(elements)) {
        JS_FreeValue(context, elements); return false;
    }
    for (uint32_t i = 0; i < 16; ++i) {
        JSValue component = JS_GetPropertyUint32(context, elements, i);
        double candidate = 0;
        bool valid = !JS_IsException(component) &&
            JS_ToFloat64(context, &candidate, component) >= 0 && isfinite(candidate);
        JS_FreeValue(context, component);
        if (!valid) { JS_FreeValue(context, elements); return false; }
        output[i] = candidate;
    }
    JS_FreeValue(context, elements);
    return true;
}

static bool bone_handle_ready(MWXSceneQuickJSLayerAccessHandle *handle,
                              MWXSceneQuickJSOwner **owner_out) {
    if (handle == NULL || !handle->owner_target) return false;
    MWXSceneQuickJSLayerRecord *record = mwx_scene_quickjs_layer_record_for_handle(handle, MWX_SCENE_QUICKJS_LAYER_OWNER_BOUND);
    if (record == NULL) return false;
    MWXSceneQuickJSOwner *owner = handle->domain->active_owner;
    if (owner->puppet_bone_layer_id != record->layer_id) return false;
    if (owner_out) *owner_out = owner;
    return owner->puppet_bone_count > 0;
}

// Column-major matrices at the VM boundary. Reject values that cannot reach
// the Float skinning ABI; all candidate work stays off the committed pose.
static bool puppet_matrix_finite(const double m[16]) {
    for (int i = 0; i < 16; ++i)
        if (!isfinite(m[i]) || fabs(m[i]) > FLT_MAX) return false;
    return true;
}

static bool puppet_matrix_multiply(const double a[16], const double b[16], double out[16]) {
    double result[16] = {0};
    for (int col = 0; col < 4; ++col)
        for (int row = 0; row < 4; ++row)
            for (int k = 0; k < 4; ++k)
                result[col * 4 + row] += a[k * 4 + row] * b[col * 4 + k];
    if (!puppet_matrix_finite(result)) return false;
    memcpy(out, result, sizeof(result));
    return true;
}

static bool puppet_matrix_inverse(const double source[16], double result[16]) {
    double rows[4][8] = {0};
    if (!puppet_matrix_finite(source)) return false;
    for (int row = 0; row < 4; ++row) {
        for (int col = 0; col < 4; ++col) rows[row][col] = source[col * 4 + row];
        rows[row][row + 4] = 1;
    }
    for (int col = 0; col < 4; ++col) {
        int pivot = col;
        for (int row = col + 1; row < 4; ++row)
            if (fabs(rows[row][col]) > fabs(rows[pivot][col])) pivot = row;
        if (!isfinite(rows[pivot][col]) || rows[pivot][col] == 0) return false;
        for (int k = 0; k < 8; ++k) {
            double swap = rows[col][k]; rows[col][k] = rows[pivot][k]; rows[pivot][k] = swap;
        }
        double divisor = rows[col][col];
        for (int k = 0; k < 8; ++k) rows[col][k] /= divisor;
        for (int row = 0; row < 4; ++row) if (row != col) {
            double factor = rows[row][col];
            for (int k = 0; k < 8; ++k) rows[row][k] -= factor * rows[col][k];
        }
    }
    for (int row = 0; row < 4; ++row)
        for (int col = 0; col < 4; ++col) result[col * 4 + row] = rows[row][col + 4];
    return puppet_matrix_finite(result);
}

static bool puppet_world_pose(uint32_t count, const int32_t *parents,
    const double layer[16], const double local[][16], double world[][16]) {
    for (uint32_t bone = 0; bone < count; ++bone) {
        int32_t parent = parents[bone];
        if (parent < -1 || parent >= (int32_t)bone || !puppet_matrix_finite(local[bone])) return false;
        if (!puppet_matrix_multiply(parent < 0 ? layer : world[parent], local[bone], world[bone])) return false;
    }
    return true;
}

static JSValue puppet_bone_call(JSContext *context, JSValueConst this_value,
                                int argc, JSValueConst *argv, int magic,
                                void *opaque) {
    (void)this_value;
    MWXSceneQuickJSLayerAccessHandle *handle = opaque;
    MWXSceneQuickJSOwner *owner = NULL;
    if (!bone_handle_ready(handle, &owner))
        return JS_ThrowTypeError(context, "Puppet bone handle is unavailable");
    if (magic == PUPPET_BONE_COUNT) {
        if (argc != 0) return JS_ThrowTypeError(context, "getBoneCount expects no arguments");
        return JS_NewInt32(context, (int32_t)owner->puppet_bone_count);
    }
    const bool lookup = magic == PUPPET_BONE_INDEX || magic == PUPPET_BONE_PARENT_INDEX;
    const bool setter = magic == PUPPET_BONE_SET_WORLD || magic == PUPPET_BONE_SET_LOCAL
        || magic == PUPPET_BONE_SET_LOCAL_ORIGIN;
    const bool impulse = magic == PUPPET_BONE_APPLY_IMPULSE;
    if (impulse ? (argc != 2 && argc != 3) : argc != (setter ? 2 : 1))
        return JS_ThrowTypeError(context, "invalid bone API argument count");
    int32_t bone_index = -1;
    if (JS_IsString(argv[0])) {
        size_t length = 0;
        const char *name = JS_ToCStringLen(context, &length, argv[0]);
        if (name == NULL) return JS_EXCEPTION;
        for (uint32_t i = 0; i < owner->puppet_bone_count; ++i) {
            if (length > 0 && owner->puppet_bone_names[i] != NULL &&
                strlen(owner->puppet_bone_names[i]) == length &&
                memcmp(owner->puppet_bone_names[i], name, length) == 0) {
                bone_index = (int32_t)i; break;
            }
        }
        JS_FreeCString(context, name);
    } else {
        double index;
        if (JS_ToFloat64(context, &index, argv[0]) < 0) return JS_EXCEPTION;
        if (isfinite(index) && index >= 0 && index < owner->puppet_bone_count && floor(index) == index)
            bone_index = (int32_t)index;
    }
    if (lookup) return JS_NewInt32(context,
        magic == PUPPET_BONE_PARENT_INDEX && bone_index >= 0
            ? owner->puppet_bone_parent[bone_index] : bone_index);
    if (bone_index < 0) return JS_ThrowRangeError(context, "bone index is out of range");
    uint32_t bone = (uint32_t)bone_index;
    if (impulse && owner->puppet_bone_impulse_unavailable[bone] != 0)
        return JS_ThrowTypeError(context, "bone physics impulse is unsupported for this bone");
    if (magic == PUPPET_BONE_GET_LOCAL_ORIGIN)
        return mwx_scene_quickjs_layer_make_vec3(context, handle->domain, &owner->puppet_bone_local[bone][12]);
    if (magic == PUPPET_BONE_GET_WORLD || magic == PUPPET_BONE_GET_LOCAL)
        return mwx_scene_quickjs_layer_make_mat4(context, handle->domain,
            magic == PUPPET_BONE_GET_WORLD
                ? owner->puppet_bone_world[bone] : owner->puppet_bone_local[bone]);
    double matrix[16];
    if (impulse) {
        if (!JS_IsObject(argv[1]) ||
            !mwx_scene_quickjs_layer_read_vec3(context, argv[1], matrix, NULL))
            return JS_ThrowTypeError(context, "bone impulse expects finite Vec3");
        if (argc == 3) {
            double angular[3];
            if (!JS_IsObject(argv[2]) ||
                !mwx_scene_quickjs_layer_read_vec3(context, argv[2], angular, NULL))
                return JS_ThrowTypeError(context, "bone angular impulse expects finite Vec3");
            if (angular[0] != 0 || angular[1] != 0 || angular[2] != 0)
                return JS_ThrowTypeError(context, "nonzero bone angular impulse is unsupported");
        }
    } else if (magic == PUPPET_BONE_SET_LOCAL_ORIGIN) {
        // Position-only writes retain the existing rotation, scale and affine
        // basis, then use the same hierarchy validation and matrix journal.
        memcpy(matrix, owner->puppet_bone_local[bone], sizeof(matrix));
        if (!JS_IsObject(argv[1]) || !mwx_scene_quickjs_layer_read_vec3(context, argv[1], &matrix[12], NULL))
            return JS_ThrowTypeError(context, "bone origin expects finite Vec3");
    } else if (!read_mat4(context, argv[1], matrix)) {
        return JS_ThrowTypeError(context, "bone transform expects Mat4");
    }
    if (owner->puppet_bone_mutation_count >= MWX_SCENE_QUICKJS_MAX_PUPPET_BONE_MUTATIONS)
        return JS_ThrowInternalError(context, "Puppet bone mutation buffer exceeded");
    if (!impulse) {
        double local[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
        double render_local[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
        double world[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
        memcpy(local, owner->puppet_bone_local, sizeof(local));
        memcpy(render_local, owner->puppet_bone_render_local,
               owner->puppet_bone_count * sizeof(render_local[0]));
        if (magic == PUPPET_BONE_SET_WORLD) {
            int32_t parent = owner->puppet_bone_parent[bone];
            double inverse[16];
            if (!puppet_matrix_inverse(parent < 0 ? owner->puppet_layer_to_world
                                                   : owner->puppet_bone_world[parent], inverse) ||
                !puppet_matrix_multiply(inverse, matrix, local[bone]))
                return JS_ThrowRangeError(context, "Puppet parent transform is singular or out of range");
        } else {
            memcpy(local[bone], matrix, sizeof(matrix));
        }
        // A matrix write replaces both views for its bone. Impulses leave the
        // published getters unchanged until the existing physics owner commits.
        memcpy(render_local[bone], local[bone], sizeof(matrix));
        if (!puppet_world_pose(owner->puppet_bone_count, owner->puppet_bone_parent,
                              owner->puppet_layer_to_world, render_local, world))
            return JS_ThrowRangeError(context, "Puppet pose is out of range");
        memcpy(matrix, local[bone], sizeof(matrix));
        memcpy(owner->puppet_bone_local, local, owner->puppet_bone_count * sizeof(local[0]));
        memcpy(owner->puppet_bone_render_local, render_local,
               owner->puppet_bone_count * sizeof(render_local[0]));
        memcpy(owner->puppet_bone_world, world, owner->puppet_bone_count * sizeof(world[0]));
    }
    size_t mutation_index = owner->puppet_bone_mutation_count++;
    MWXSceneQuickJSPuppetBoneMutation *mutation = &owner->puppet_bone_mutations[mutation_index];
    mutation->layer_id = owner->puppet_bone_layer_id;
    mutation->bone_index = (int16_t)bone_index;
    mutation->kind = impulse ? MWX_SCENE_QUICKJS_PUPPET_BONE_LINEAR_IMPULSE
                             : MWX_SCENE_QUICKJS_PUPPET_BONE_MATRIX;
    mutation->callback_epoch = owner->domain->callback_epoch;
    mutation->ordinal = mutation_index > 0
        && owner->puppet_bone_mutations[mutation_index - 1].callback_epoch == mutation->callback_epoch
        ? owner->puppet_bone_mutations[mutation_index - 1].ordinal + 1 : 0;
    // Publish the resolved parent-relative transform, never a surface-world
    // coordinate mislabeled as evaluator-local data.
    if (impulse) memcpy(mutation->payload.impulse, matrix, 3 * sizeof(double));
    else memcpy(mutation->payload.matrix, matrix, sizeof(matrix));
    return JS_UNDEFINED;
}

bool mwx_scene_quickjs_layer_define_puppet_bone_functions(
    JSContext *context, JSValue layer, MWXSceneQuickJSOwner *owner,
    uint32_t index, bool owner_target, bool persistent
) {
    if (!owner_target) return true;
    const struct { const char *name; enum PuppetBoneFunction function; int argc; } functions[] = {
        {"getBoneCount", PUPPET_BONE_COUNT, 0},
        {"getBoneIndex", PUPPET_BONE_INDEX, 1},
        {"getBoneParentIndex", PUPPET_BONE_PARENT_INDEX, 1},
        {"getBoneTransform", PUPPET_BONE_GET_WORLD, 1},
        {"getLocalBoneTransform", PUPPET_BONE_GET_LOCAL, 1},
        {"setBoneTransform", PUPPET_BONE_SET_WORLD, 2},
        {"setLocalBoneTransform", PUPPET_BONE_SET_LOCAL, 2},
        {"getLocalBoneOrigin", PUPPET_BONE_GET_LOCAL_ORIGIN, 1},
        {"setLocalBoneOrigin", PUPPET_BONE_SET_LOCAL_ORIGIN, 2},
        {"applyBonePhysicsImpulse", PUPPET_BONE_APPLY_IMPULSE, 2},
    };
    for (size_t i = 0; i < sizeof(functions) / sizeof(functions[0]); ++i) {
        MWXSceneQuickJSLayerAccessHandle *handle = calloc(1, sizeof(*handle));
        if (handle == NULL) { JS_ThrowOutOfMemory(context); return false; }
        *handle = (MWXSceneQuickJSLayerAccessHandle){
            .domain = owner->domain, .owner_identity = owner->identity,
            .layer_index = index, .callback_epoch = owner->domain->callback_epoch,
            .expected_layer_id = owner_target ? 0 : owner->domain->layers[index].layer_id,
            .owner_target = owner_target, .persistent = persistent,
        };
        JSValue function = mwx_scene_quickjs_layer_access_closure(
            context, puppet_bone_call, functions[i].name, functions[i].argc, functions[i].function, handle
        );
        if (JS_IsException(function) || JS_DefinePropertyValueStr(
                context, layer, functions[i].name, function,
                JS_PROP_ENUMERABLE
            ) < 0) return false;
    }
    return true;
}

size_t mwx_scene_quickjs_owner_puppet_bone_mutation_count(
    MWXSceneQuickJSOwner *owner
) {
    return owner == NULL || owner->disabled ? 0 : owner->puppet_bone_mutation_count;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_puppet_bone_mutation_at(
    MWXSceneQuickJSOwner *owner, size_t requested,
    MWXSceneQuickJSPuppetBoneMutation *mutation,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->disabled || mutation == NULL ||
        requested >= owner->puppet_bone_mutation_count) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid Puppet bone mutation index"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    *mutation = owner->puppet_bone_mutations[requested];
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_configure_puppet_bones(
    MWXSceneQuickJSOwner *owner, int64_t layer_id, uint32_t bone_count,
    const double *local_matrices, const double *render_local_matrices,
    const int32_t *parents,
    const double *layer_to_world,
    const uint8_t *impulse_unavailable,
    char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || owner->domain == NULL || owner->domain->callback_active ||
        !owner->target_layer_configured || bone_count == 0 ||
        bone_count > MWX_SCENE_QUICKJS_MAX_PUPPET_BONES ||
        local_matrices == NULL || render_local_matrices == NULL ||
        parents == NULL || layer_to_world == NULL ||
        layer_id != owner->domain->layers[owner->target_layer_index].layer_id) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid Puppet bone catalog"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    // Derive and validate the complete pose before publishing any field. A
    // malformed refresh must leave the previous matrices and hierarchy intact.
    double world[MWX_SCENE_QUICKJS_MAX_PUPPET_BONES][16];
    bool local_finite = true;
    for (uint32_t bone = 0; bone < bone_count; ++bone) {
        if (!puppet_matrix_finite(local_matrices + bone * 16)) {
            local_finite = false;
            break;
        }
    }
    if (!local_finite || !puppet_matrix_finite(layer_to_world) ||
        !puppet_world_pose(bone_count, parents, layer_to_world,
                          (const double (*)[16])render_local_matrices, world)) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid Puppet pose or hierarchy"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    if (bone_count > owner->puppet_bone_render_capacity) {
        double (*candidate)[16] = malloc(bone_count * 2 * sizeof(*candidate));
        if (candidate == NULL) {
            mwx_scene_quickjs_write_diagnostic(
                diagnostic, diagnostic_capacity, "Puppet render pose allocation failed"
            );
            return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
        }
        double (*baseline)[16] = candidate + bone_count;
        memset(baseline, 0, bone_count * sizeof(*baseline));
        if (owner->puppet_bone_render_capacity > 0) {
            memcpy(baseline, owner->puppet_bone_render_local_baseline,
                   owner->puppet_bone_render_capacity * sizeof(*baseline));
        }
        memcpy(candidate, render_local_matrices, bone_count * sizeof(*candidate));
        free(owner->puppet_bone_render_local);
        owner->puppet_bone_render_local = candidate;
        owner->puppet_bone_render_local_baseline = baseline;
        owner->puppet_bone_render_capacity = bone_count;
    } else {
        memcpy(owner->puppet_bone_render_local, render_local_matrices,
               bone_count * sizeof(world[0]));
    }
    memcpy(owner->puppet_bone_local, local_matrices, bone_count * sizeof(world[0]));
    memcpy(owner->puppet_bone_world, world, bone_count * sizeof(world[0]));
    memcpy(owner->puppet_bone_parent, parents, bone_count * sizeof(int32_t));
    memcpy(owner->puppet_layer_to_world, layer_to_world, sizeof(double) * 16);
    // Immutable launch capability; ordinary pose refreshes pass NULL.
    if (impulse_unavailable != NULL)
        memcpy(owner->puppet_bone_impulse_unavailable, impulse_unavailable, bone_count);
    owner->puppet_bone_layer_id = layer_id;
    owner->puppet_bone_count = bone_count;
    return MWX_SCENE_QUICKJS_OK;
}

MWXSceneQuickJSResult mwx_scene_quickjs_owner_set_puppet_bone_name(
    MWXSceneQuickJSOwner *owner, uint32_t bone_index, const char *name,
    size_t name_length, char *diagnostic, size_t diagnostic_capacity
) {
    mwx_scene_quickjs_write_diagnostic(diagnostic, diagnostic_capacity, "");
    if (owner == NULL || name == NULL || bone_index >= owner->puppet_bone_count ||
        name_length == 0 || name_length > MWX_SCENE_QUICKJS_MAX_LAYER_NAME ||
        memchr(name, '\0', name_length) != NULL) {
        mwx_scene_quickjs_write_diagnostic(
            diagnostic, diagnostic_capacity, "invalid Puppet bone name"
        );
        return MWX_SCENE_QUICKJS_INVALID_ARGUMENT;
    }
    char *copy = malloc(name_length + 1);
    if (copy == NULL) return MWX_SCENE_QUICKJS_MEMORY_EXCEEDED;
    memcpy(copy, name, name_length); copy[name_length] = '\0';
    free(owner->puppet_bone_names[bone_index]);
    owner->puppet_bone_names[bone_index] = copy;
    return MWX_SCENE_QUICKJS_OK;
}
