#!/usr/bin/env python3
"""视频详情面板预览不随资源补齐刷新（问题 6）的行为测试。

编译真实 VideoLibraryInspectorView + 共享 UI/缓存依赖，配最小 manager 桩
（script/tests/fixtures/VideoInspectorPreviewHarness.swift），断言：
- 初始缺图后缩略图生成完成，无需重开面板即显示预览；
- 无关 publish 不破坏已显示预览；
- 资源替换清空旧图、新源缩略图后到再次刷新；
- 旧代数异步完成不得覆盖新资源状态；
- 面板关闭（视图释放）后的迟到回调安全。

缓存隔离：编译模块缓存进临时目录（-module-cache-path）；
harness 的 ThumbnailCache 磁盘层只写专属 namespace
`videolibrary-inspector-test`（本测试独占、可重建），setUp/tearDown 按精确路径清理。
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]

VIDEO_WALLPAPER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
THUMBNAIL_CACHE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift"
FADING_SCROLL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift"
FOOTER_METRICS_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift"
INSPECTOR_SUPPORT_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorSupport.swift"
INSPECTOR_VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorView.swift"
INSPECTOR_HARNESS_SOURCE = REPOSITORY_ROOT / "script/tests/fixtures/VideoInspectorPreviewHarness.swift"

# ThumbnailCache 磁盘层（bundleIdentifier 为 nil 时根为 MyWallpaperX）下的
# 本测试专属 namespace，精确清单清理，不触碰其他子目录。
CACHE_NAMESPACE_DIR = (
    pathlib.Path.home()
    / "Library"
    / "Caches"
    / "MyWallpaperX"
    / "thumbnails"
    / "videolibrary-inspector-test"
)


class VideoInspectorPreviewReloadTests(unittest.TestCase):
    def test_preview_reloads_when_resources_arrive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-video-inspector-preview-", dir="/private/tmp") as temporary:
            workdir = pathlib.Path(temporary)
            executable = workdir / "InspectorPreviewHarness"
            module_cache = workdir / "module-cache"
            build = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    str(VIDEO_WALLPAPER_SOURCE),
                    str(THUMBNAIL_CACHE_SOURCE),
                    str(FADING_SCROLL_SOURCE),
                    str(FOOTER_METRICS_SOURCE),
                    str(INSPECTOR_SUPPORT_SOURCE),
                    str(INSPECTOR_VIEW_SOURCE),
                    str(INSPECTOR_HARNESS_SOURCE),
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

            run = subprocess.run(
                [str(executable)],
                capture_output=True,
                text=True,
                timeout=120,
            )
            output = run.stdout + run.stderr
            self.assertEqual(run.returncode, 0, output)

            required_scenarios = (
                "s1-initial-missing-notice",
                "s1-initial-placeholder-visible",
                "s2-preview-reloads-on-thumbnail-ready",
                "s3-unrelated-publish-keeps-preview",
                "s4-replacement-clears-stale-preview",
                "s5-late-ready-swaps-to-new-image",
                "s6-stale-async-completion-dropped",
                "s7-closed-panel-view-released",
                "s7-late-callback-after-close-safe",
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

    def setUp(self) -> None:
        shutil.rmtree(CACHE_NAMESPACE_DIR, ignore_errors=True)

    def tearDown(self) -> None:
        shutil.rmtree(CACHE_NAMESPACE_DIR, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
