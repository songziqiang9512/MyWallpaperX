#!/usr/bin/env python3
"""视频详情面板预览不随资源补齐刷新（问题 6）的行为测试。

编译真实 VideoLibraryInspectorView + 共享 UI/缓存依赖，配最小 manager 桩
（script/tests/fixtures/VideoInspectorPreviewHarness.swift），断言：
- 初始缺图后缩略图生成完成，无需重开面板即显示预览；
- 无关 publish 不破坏已显示预览；
- 资源替换清空旧图、新源缩略图后到再次刷新；
- 旧代数异步完成不得覆盖新资源状态；
- 面板关闭（视图释放）后的迟到回调安全。

缓存与模块编译输出均置于每次运行的临时目录；Foundation 的缓存根通过
CFFIXED_USER_HOME 隔离，harness 在首次构造共享缓存前断言该根生效。
"""

from __future__ import annotations

import os
import hashlib
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]

VIDEO_WALLPAPER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
THUMBNAIL_CACHE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift"
FADING_SCROLL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift"
FOOTER_METRICS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift"
INSPECTOR_SUPPORT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorSupport.swift"
INSPECTOR_VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorView.swift"
INSPECTOR_HARNESS_SOURCE = REPOSITORY_ROOT / "script/tests/fixtures/VideoInspectorPreviewHarness.swift"
INSPECTOR_SOURCES = [VIDEO_WALLPAPER_SOURCE,
    REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift", THUMBNAIL_CACHE_SOURCE,
    FADING_SCROLL_SOURCE, FOOTER_METRICS_SOURCE, REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorBadgeView.swift",
    INSPECTOR_SUPPORT_SOURCE, INSPECTOR_VIEW_SOURCE, REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/WallpaperInspectorActions.swift",
    INSPECTOR_HARNESS_SOURCE]

class VideoInspectorPreviewReloadTests(unittest.TestCase):
    def test_preview_reloads_when_resources_arrive(self) -> None:
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES}
        with tempfile.TemporaryDirectory(prefix="mwx-video-inspector-preview-", dir="/private/tmp") as temporary:
            workdir = pathlib.Path(temporary)
            executable = workdir / "InspectorPreviewHarness"
            module_cache = workdir / "module-cache"
            sources = []
            for index, source in enumerate(INSPECTOR_SOURCES):
                frozen = workdir / f"Source{index}.swift"
                content = source.read_text()
                if source == THUMBNAIL_CACHE_SOURCE:
                    # Observe completion of the real public registration call;
                    # no queue, cancellation or image result is substituted.
                    entry = declaration(content, "    func load(")
                    observed = entry[:-1] + "    InspectorCacheDemandProbe.shared.registered(key, cancellation: cancellation)\n    }"
                    content = content.replace(entry, observed, 1)
                frozen.write_text(content)
                sources.append(frozen)
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

            required_scenarios = (
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
                "s12-removed-only-consumer-detaches-before-queued-loader",
                "s12-removed-inspector-does-not-reacquire-on-thumbnail-notification",
                "s12-other-consumer-keeps-the-shared-producer-alive",
                "s12-removed-consumer-does-not-receive-shared-result",
                "s12-remount-reacquires-without-clearing-or-decoding-current-image",
                "s12-released-view-cancels-its-registered-consumer",
                "s13-first-mount-does-not-duplicate-inflight-metadata",
                "s13-pending-metadata-remount-restarts-and-reaches-final-values",
                "s13-completed-metadata-remount-does-not-reread",
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
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in INSPECTOR_SOURCES})

    def test_unbound_video_inspector_cannot_be_constructed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-required-actions-", dir="/private/tmp") as directory:
            work = pathlib.Path(directory)
            misuse = work / "UnboundInspector.swift"
            misuse.write_text("import AppKit\n@MainActor func cannotBindLegacyOwner(_ value:VideoWallpaper,_ manager:WallpaperManager) {\n"
                "_ = VideoLibraryInspectorView(wallpaper:value,wallpaperManager:manager)\n}\n")
            check = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-typecheck", *map(str, INSPECTOR_SOURCES), str(misuse),
                "-module-cache-path", str(work / "modules")], capture_output=True, text=True, timeout=120)
            self.assertNotEqual(check.returncode, 0, check.stdout + check.stderr)
            self.assertIn("missing argument for parameter 'libraryActions'", check.stderr)



if __name__ == "__main__":
    unittest.main()
