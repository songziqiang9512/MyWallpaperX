#!/usr/bin/env python3

"""R4 atomic material Program preflight, pipeline cache and Metal encoding gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    SCENE_ROOT / "Diagnostics/SceneEffectExecutionFrameTrace.swift",
    SCENE_ROOT / "Diagnostics/SceneEffectExecutionTelemetry.swift",
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("shader_variant_environment"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    *scene_swift_sources("resolved_material_program_model"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/ScenePersistentCacheSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentKind.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialAttachmentStorage.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Failure.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder+Warmup.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPassEncoder.swift",
    SCENE_ROOT / "Rendering/Composition/SceneMainPassEncoder.swift",
    REPOSITORY_ROOT / "script/tests/fixtures/SceneMaterialPipelinePreparation.swift",
]


SUPPORT = r'''
import Foundation
import Metal

final class SceneGraphRenderTargetResidencyPin { func release() {} }

nonisolated struct SceneResolvedMaterialNode {
    enum TextureProvenance: String, Hashable {
        case material, instance, userTexture, explicitBinding
    }
}

nonisolated enum SceneDynamicTarget: Hashable {
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated enum SceneDynamicSource: Hashable {
    case authored, userProperty, timeline, sceneScript
}

nonisolated enum SceneFrameTextureIdentity: Hashable {
    case layerSource(Int)
    case namedLayerTarget(SceneNamedTextureReference)
    case sceneBackground(Int)
    case sceneEnvironment
    case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    case asset(SceneAssetTextureIdentity)
    case userProperty(String)
    case materialUserProperty(SceneUserPropertyTextureIdentity)
    case system(SceneSystemProviderTextureIdentity)
}
'''


FIXTURE_ROOT = Path(__file__).parent / "fixtures"
ARCHIVE_FAULT_HEADER = r'''
#import <Metal/Metal.h>
BOOL MWXArmArchivePublicationBarrier(id<MTLDevice> device, NSString *prefix);
BOOL MWXWaitArchivePublicationStarted(double seconds);
BOOL MWXArchivePublicationIsHeld(void);
void MWXReleaseArchivePublication(void);
BOOL MWXWaitArchivePublicationFinished(double seconds);
NSUInteger MWXArchiveSerializationAttempts(void);
'''
ARCHIVE_FAULT_SOURCE = r'''
#import "ArchivePublicationFault.h"
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdbool.h>
#import <stdatomic.h>
static NSString *archivePrefix;
static dispatch_semaphore_t archiveStarted, archiveRelease, archiveFinished;
static atomic_bool archiveEntered, archiveReleased, archiveDone, archiveTimedOut;
static atomic_uint archiveAttempts;
static IMP archiveOriginal;
static dispatch_time_t archiveDeadline(double seconds) {
    return dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC));
}
static BOOL archiveSerialize(id receiver, SEL selector, NSURL *url, NSError **error) {
    if (![url.lastPathComponent hasPrefix:archivePrefix]) {
        return ((BOOL (*)(id, SEL, NSURL *, NSError **))archiveOriginal)(receiver, selector, url, error);
    }
    unsigned int attempt = atomic_fetch_add(&archiveAttempts, 1) + 1;
    if (attempt == 1) {
        atomic_store(&archiveEntered, true);
        dispatch_semaphore_signal(archiveStarted);
        if (dispatch_semaphore_wait(archiveRelease, archiveDeadline(5)) != 0) {
            atomic_store(&archiveTimedOut, true);
        }
    }
    BOOL result = ((BOOL (*)(id, SEL, NSURL *, NSError **))archiveOriginal)(receiver, selector, url, error);
    if (attempt == 1) {
        atomic_store(&archiveDone, true);
        dispatch_semaphore_signal(archiveFinished);
    }
    return result;
}
BOOL MWXArmArchivePublicationBarrier(id<MTLDevice> device, NSString *prefix) {
    if (archiveOriginal) return NO;
    id<MTLBinaryArchive> archive = [device newBinaryArchiveWithDescriptor:[MTLBinaryArchiveDescriptor new] error:NULL];
    if (!archive) return NO;
    Method method = class_getInstanceMethod(object_getClass(archive), @selector(serializeToURL:error:));
    if (!method) return NO;
    archivePrefix = [prefix copy];
    archiveStarted = dispatch_semaphore_create(0);
    archiveRelease = dispatch_semaphore_create(0);
    archiveFinished = dispatch_semaphore_create(0);
    archiveOriginal = method_getImplementation(method);
    method_setImplementation(method, (IMP)archiveSerialize);
    return YES;
}
BOOL MWXWaitArchivePublicationStarted(double seconds) {
    return dispatch_semaphore_wait(archiveStarted, archiveDeadline(seconds)) == 0;
}
BOOL MWXArchivePublicationIsHeld(void) {
    return atomic_load(&archiveEntered) && !atomic_load(&archiveReleased)
        && !atomic_load(&archiveDone) && !atomic_load(&archiveTimedOut);
}
void MWXReleaseArchivePublication(void) {
    atomic_store(&archiveReleased, true);
    dispatch_semaphore_signal(archiveRelease);
}
BOOL MWXWaitArchivePublicationFinished(double seconds) {
    return dispatch_semaphore_wait(archiveFinished, archiveDeadline(seconds)) == 0;
}
NSUInteger MWXArchiveSerializationAttempts(void) { return atomic_load(&archiveAttempts); }
'''
# Keep the production source closure reusable by the independent texture gate.
FIXTURE_SOURCES = [
    FIXTURE_ROOT / "SceneResolvedMaterialPassFixture.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPassColorCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPassDisplacementCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPassScalarCases.swift",
    FIXTURE_ROOT / "SceneResolvedMaterialPassPipelineCases.swift",
]
HARNESS = (FIXTURE_ROOT / "SceneResolvedMaterialPassHarness.swift").read_text(
    encoding="utf-8"
)


HARNESS = HARNESS.replace(
    "// TERMINAL_REPLAY_PROBE",
    (Path(__file__).parent / "fixtures/SceneTerminalMaterialReplayProbe.swift").read_text(),
)

@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialPassEncoderTests(unittest.TestCase):
    def test_program_is_prepared_and_encoded_atomically(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-resolved-material-pass-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "resolved-material-pass-test"
            support.write_text(SUPPORT, encoding="utf-8")
            harness.write_text(HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            # The binary archive tier must never touch the real user cache
            # from a test run; the whole harness shares one isolated root.
            # Environment override roots must pre-exist, like every other
            # persistent tier's test root.
            (root / "pipeline-binary-archive").mkdir(parents=True, exist_ok=True)
            environment["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"] = str(
                root / "pipeline-binary-archive"
            )
            (root / "ArchivePublicationFault.h").write_text(ARCHIVE_FAULT_HEADER)
            (root / "ArchivePublicationFault.m").write_text(ARCHIVE_FAULT_SOURCE)
            archive_fault = subprocess.run(
                ["xcrun", "clang", "-fobjc-arc", "-c", str(root / "ArchivePublicationFault.m"),
                 "-o", str(root / "archive-publication-fault.o")],
                cwd=REPOSITORY_ROOT, env=environment,
                capture_output=True, text=True,
            )
            self.assertEqual(archive_fault.returncode, 0, archive_fault.stderr)
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library", "-D", "SCENE_GRAPH_TESTING",
                    "-import-objc-header", str(root / "ArchivePublicationFault.h"),
                    str(root / "archive-publication-fault.o"),
                    str(support),
                    *(str(path) for path in [*SWIFT_SOURCES, *FIXTURE_SOURCES]),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        results = payload["results"]
        if not results["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [name for name, passed in results.items() if not passed],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
