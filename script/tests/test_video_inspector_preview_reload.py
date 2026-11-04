#!/usr/bin/env python3
"""视频详情面板预览不随资源补齐刷新（问题 6）的行为测试。

编译真实 VideoLibraryInspectorView + 共享 UI/缓存依赖，配最小 manager 桩
（script/tests/fixtures/VideoInspectorPreviewHarness.swift），断言：
- 初始缺图后缩略图生成完成，无需重开面板即显示预览；
- 无关 publish 不破坏已显示预览；
- 资源替换清空旧图、新源缩略图后到再次刷新；
- 旧代数异步完成不得覆盖新资源状态；
- 面板关闭（视图释放）后的迟到回调安全；
- 无关 manager 发布不重写 footer，注入动作状态仍更新真实按钮与操作。
- 统一预览准备入口观察真实模型查找，内容重建不计入。

缓存与模块编译输出均置于每次运行的临时目录；Foundation 的缓存根通过
CFFIXED_USER_HOME 隔离，harness 在首次构造共享缓存前断言该根生效。
"""

from __future__ import annotations

import os
import hashlib
import json
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]

VIDEO_WALLPAPER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
DECODER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift"
THUMBNAIL_CACHE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift"
FADING_SCROLL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift"
FOOTER_METRICS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift"
INSPECTOR_SUPPORT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorSupport.swift"
INSPECTOR_VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorView.swift"
PROVIDER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridSupport.swift"
PIPELINE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+CachePipeline.swift"
MANAGER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift"
INSPECTOR_HARNESS_SOURCE = REPOSITORY_ROOT / "script/tests/fixtures/VideoInspectorPreviewHarness.swift"
HOST_VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorHostViewController.swift"
TOOLBAR_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/ToolbarMenuPopover.swift"
INSPECTOR_SOURCES = [VIDEO_WALLPAPER_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Shared/ThumbnailRequest.swift", PROVIDER_SOURCE, PIPELINE_SOURCE, MANAGER_SOURCE,
    DECODER_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift", THUMBNAIL_CACHE_SOURCE,
    FADING_SCROLL_SOURCE, FOOTER_METRICS_SOURCE, REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorBadgeView.swift",
    INSPECTOR_SUPPORT_SOURCE, INSPECTOR_VIEW_SOURCE, REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/WallpaperInspectorActions.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/FinderRevealCoordinator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
    INSPECTOR_HARNESS_SOURCE, REPOSITORY_ROOT / "script/tests/fixtures/VideoInspectorHostBackfillChecks.swift",
    HOST_VIEW_SOURCE, TOOLBAR_SOURCE,
    *[REPOSITORY_ROOT / "MyWallpaperX" / name for name in (
        "Shared/UI/InspectorHost.swift", "Shared/UI/InspectorHostActions.swift", "Shared/UI/InspectorHostBridge.swift",
        "Shared/UI/ListThumbnailTintSource.swift", "Shared/UI/WallpaperLibrarySheetPresentation.swift",
        "Shell/AppKitListBackgroundTint.swift", "Shell/AppKitMainSplitView.swift",
        "Shared/UI/ModuleFocusable.swift", "Shared/Components/WallpaperCardControlsView.swift",
        "Shared/Components/WallpaperCardSupportViews.swift")], REPOSITORY_ROOT / "script/tests/fixtures/NativeAppHarness.swift"]

def prepare_inspector_sources(workdir: pathlib.Path, *, observe: bool = True) -> list[pathlib.Path]:
    sources = []
    for index, source in enumerate(INSPECTOR_SOURCES):
        frozen = workdir / f"Source{index}.swift"
        content = source.read_text()
        if source == TOOLBAR_SOURCE:
            content = "import AppKit\n" + declaration(content, "protocol ToolbarGridScrollDismissalSurface:")
        elif source == HOST_VIEW_SOURCE and observe:
            entry = declaration(content, "    func configure(request: InspectorHostRequest?")
            content = content.replace(entry, entry.replace("{\n", "{\n        InspectorContentBuildProbe.hostConfigurations += 1\n", 1), 1)
        elif source == PROVIDER_SOURCE:
            content = "import AppKit\nimport Foundation\n" + declaration(content, "final class AppKitThumbnailProvider")
        elif source == PIPELINE_SOURCE:
            content = "import AppKit\nimport CryptoKit\nimport ImageIO\n" + declaration(content, "nonisolated struct VideoThumbnailAsset") + "\nextension WallpaperManager {\n" + "\n".join(
                declaration(content, signature) for signature in ("    func cacheKey(forNormalizedPath", "    func thumbnailOutputURL(", "    func thumbnailPixelSize(")) + "\n}\n"
        elif source == MANAGER_SOURCE:
            content = "import Foundation\nextension WallpaperManager {\n" + "\n".join(
                declaration(content, signature) for signature in ("    func pathExists(", "    func normalizedSourcePathExists(")) + "\n}\n"
        elif source == DECODER_SOURCE:
            boundary = "        case .sourceFile(let url, let onFailure):"
            if content.count(boundary) != 1:
                raise ValueError("expected one actual source-file decoder entry")
            content = content.replace(boundary, boundary + "\n            InspectorCacheDemandProbe.shared.loaded(url.path)", 1)
        elif source == THUMBNAIL_CACHE_SOURCE:
            # Observe completion of the real public registration call;
            # no queue, cancellation or image result is substituted.
            entry = declaration(content, "    func load(")
            observed = entry.replace("{", "{\n        defer { InspectorCacheDemandProbe.shared.registered(key, request: target, cancellation: cancellation) }", 1)
            content = content.replace(entry, observed, 1)
        elif source == FOOTER_METRICS_SOURCE:
            # Count actual setter entries without replacing their UI work.
            for signature, counter in (("    func setSymbol(", "symbols"), ("    func setTitle(", "titles")):
                entry = declaration(content, signature)
                observed = entry.replace("{", "{\n        InspectorFooterWorkProbe." + counter + " += 1", 1)
                content = content.replace(entry, observed, 1)
        elif source == INSPECTOR_VIEW_SOURCE and observe:
            entry = declaration(content, "    private func makePreviewSection(")
            content = content.replace(entry, entry.replace("{\n", "{\n        InspectorContentBuildProbe.bodies += 1"
                "\n        InspectorContentBuildProbe.bodiesByView[ObjectIdentifier(self), default: 0] += 1\n", 1), 1)
            entry = declaration(content, "    private var currentWallpaper:")
            observed = entry.replace("{\n", "{\n        if let scope = InspectorPreviewLookupProbe.scope { InspectorPreviewLookupProbe.reads[scope, default: 0] += 1 }\n", 1)
            observed = observed.replace("        wallpaperManager.wallpapers.first", "        return wallpaperManager.wallpapers.first", 1)
            content = content.replace(entry, observed, 1)
            entry = declaration(content, "    private func loadPreviewImage(")
            observed = entry.replace("{\n", "{\n        let previousLookupScope = InspectorPreviewLookupProbe.scope\n"
                '        InspectorPreviewLookupProbe.scope = "load"\n'
                '        InspectorPreviewLookupProbe.calls["load", default: 0] += 1\n'
                "        defer { InspectorPreviewLookupProbe.scope = previousLookupScope }\n", 1)
            content = content.replace(entry, observed, 1)
        frozen.write_text(content)
        sources.append(frozen)
    return sources


class VideoInspectorPreviewReloadTests(unittest.TestCase):
    def test_preview_reloads_when_resources_arrive(self) -> None:
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES}
        with tempfile.TemporaryDirectory(prefix="mwx-video-inspector-preview-", dir="/private/tmp") as temporary:
            workdir = pathlib.Path(temporary)
            executable = workdir / "InspectorPreviewHarness"
            module_cache = workdir / "module-cache"
            sources = prepare_inspector_sources(workdir)
            build = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    *map(str, sources),
                    "-module-cache-path",
                    str(module_cache),
                    "-o",
                    str(executable),
                ],
                capture_output=True,
                text=True,
                timeout=240,
                cwd=REPOSITORY_ROOT,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)

            environment = os.environ.copy()
            runtime_home = workdir / "runtime-home"
            runtime_home.mkdir()
            environment.update(HOME=str(runtime_home), CFFIXED_USER_HOME=str(runtime_home))
            run = subprocess.run(
                [str(executable)],
                env=environment,
                capture_output=True,
                text=True,
                timeout=120,
            )
            output = run.stdout + run.stderr
            self.assertEqual(run.returncode, 0, output)
            self.assertNotRegex(run.stderr, r"Unable to simultaneously satisfy constraints|Unsatisfiable constraints")

            required_scenarios = (
                "s16-complete-metadata-template-exists-before-native-mount",
                "s17-subscription-initial-value-does-not-rebuild-mounted-template",
                "s17-first-real-publication-updates-body-and-preview-while-metadata-is-held",
                "s17-later-identical-model-publication-still-refreshes-external-assets",
                "s18-identical-publication-detects-actual-source-removal",
                "s18-identical-publication-clears-notice-after-source-recovery",
                "s10-missing-preview-message-fits-without-covering-its-placeholder",
                "s10-preview-constraints-do-not-grow-on-metadata-or-source-echoes",
                "s10-metadata-and-missing-preview-keep-native-preview-frame",
                "s10-thumbnail-arrival-updates-only-the-same-fixed-preview",
                "s11-first-video-preview-starts-at-safe-unfaded-top",
                "s11-native-video-scroll-enables-fade-only-away-from-top",
                "s1-initial-missing-notice",
                "s1-initial-placeholder-visible",
                "s1-required-store-membership-only",
                "s2-preview-reloads-on-thumbnail-ready",
                "s3-unrelated-publish-keeps-preview",
                "s4-replacement-clears-stale-preview",
                "s5-late-ready-swaps-to-new-image",
                "s6-stale-async-completion-dropped",
                "s8-same-path-static-frame-arrives",
                "s8-same-path-static-frame-replaced",
                "s8-same-path-derived-assets-cleared",
                "s7-closed-panel-view-released",
                "s7-late-callback-after-close-safe",
                "s9-injected-membership-replaces-old-tags-with-new-store-names",
                "s9-fixed-actions-never-write-old-selection-owners",
                "s9-readonly-injected-actions-refuse-organization",
                "s9-original-hidden-inspector-scrollbars-preserved",
                "s12-removed-only-consumer-detaches-before-queued-source",
                "s12-removed-inspector-does-not-reacquire-on-thumbnail-notification",
                "s12-other-consumer-keeps-the-shared-producer-alive",
                "s12-removed-consumer-does-not-receive-shared-result",
                "s12-completed-remount-keeps-current-image-without-new-demand-or-decoding",
                "s12-released-view-cancels-its-registered-consumer",
                "s13-first-mount-does-not-duplicate-inflight-metadata",
                "s13-pending-metadata-remount-restarts-and-reaches-final-values",
                "s13-completed-metadata-remount-does-not-reread",
                "s15-unrelated-manager-change-does-not-rewrite-footer",
                "s15-identical-library-publish-does-not-rewrite-footer",
                "s15-injected-playing-favorite-and-permissions-update-native-footer",
                "s15-stopped-and-disabled-footer-restores-icons-and-refuses-actions",
            )
            results: dict[str, str] = {}
            for line in run.stdout.splitlines():
                parts = line.split()
                if len(parts) == 3 and parts[0] == "RESULT":
                    results[parts[1]] = parts[2]
            missing = [name for name in required_scenarios if name not in results]
            self.assertEqual(missing, [], output)
            failed = {name: verdict for name, verdict in results.items() if verdict != "PASS"}
            self.assertEqual(failed, {}, output)
            self.assertIn("ALL SCENARIOS PASS", run.stdout)
            observations = [json.loads(line.removeprefix("PREVIEW LOOKUPS "))
                for line in run.stdout.splitlines() if line.startswith("PREVIEW LOOKUPS ")]
            self.assertEqual(len(observations), 1, output)
            work = observations[0]
            self.assertEqual(set(work), {"unchanged", "changed"})
            print(json.dumps({"previewLookupWork": work}, sort_keys=True))
            for phase, observation in work.items():
                calls, reads = observation["calls"], observation["reads"]
                self.assertEqual(set(calls), {"load"}, observation)
                self.assertGreater(calls.get("load", 0), 0, observation)
                with self.subTest(phase=phase):
                    self.assertGreaterEqual(reads.get("load", 0), 0)
                    self.assertLessEqual(reads.get("load", 0), 1, observation)
                    self.assertLessEqual(reads.get("load", 0), calls.get("load", 0), observation)
            builds = [json.loads(line.removeprefix("CONTENT BUILDS "))
                for line in run.stdout.splitlines() if line.startswith("CONTENT BUILDS ")]
            self.assertEqual(len(builds), 1, output)
            print(json.dumps({"contentBuilds": builds[0]}, sort_keys=True))
            self.assertEqual(set(builds[0]), {"initial", "firstFinal"}, output)
            self.assertEqual(builds[0], {"initial": 1, "firstFinal": 0}, output)
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES})

    def test_real_host_backfill_keeps_video_content_identity_during_slide(self) -> None:
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES}
        with tempfile.TemporaryDirectory(prefix="mwx-video-host-backfill-", dir="/private/tmp") as temporary:
            work = pathlib.Path(temporary)
            sources = prepare_inspector_sources(work)
            compiled = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
            binary = prepare_native_app(work, "VideoInspectorBackfill")
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=240, cwd=REPOSITORY_ROOT)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, [str(work), "--host-backfill"], timeout=25)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertNotRegex(run.stderr, r"Unable to simultaneously satisfy constraints|Unsatisfiable constraints")
            facts = json.loads(run.stdout)
            print("VIDEO HOST BACKFILL " + json.dumps(facts, sort_keys=True))
            self.assertTrue(facts["checks"], run.stdout + run.stderr)
            for name, passed in facts["checks"].items():
                with self.subTest(check=name): self.assertIs(passed, True, run.stdout + run.stderr)
            self.assertEqual(compiled, {str(path): hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() for path in compiled})
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES})

    def test_unbound_video_inspector_cannot_be_constructed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-required-actions-", dir="/private/tmp") as directory:
            work = pathlib.Path(directory)
            misuse = work / "UnboundInspector.swift"
            misuse.write_text("import AppKit\n@MainActor func cannotBindLegacyOwner(_ value:VideoWallpaper,_ manager:WallpaperManager) {\n"
                "_ = VideoLibraryInspectorView(wallpaper:value,wallpaperManager:manager)\n}\n")
            check = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-typecheck", *map(str, prepare_inspector_sources(work, observe=False)), str(misuse),
                "-module-cache-path", str(work / "modules")], capture_output=True, text=True, timeout=120)
            self.assertNotEqual(check.returncode, 0, check.stdout + check.stderr)
            self.assertIn("missing argument for parameter 'libraryActions'", check.stderr)



if __name__ == "__main__":
    unittest.main()
