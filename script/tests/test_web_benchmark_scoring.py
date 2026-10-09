from __future__ import annotations

import unittest
from pathlib import Path

import sys

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_wallpaper_benchmark import (  # noqa: E402
    DiagnosticEvent,
    Sample,
    score_sample,
)


def make_event(event_type: str, message: str = "", url: str | None = None) -> DiagnosticEvent:
    return DiagnosticEvent(
        type=event_type,
        severity="warning" if "error" not in event_type else "error",
        message=message,
        url=url,
        line=f"2026-10-10 MyWallpaperX[1:1] MWX WEB DIAG type={event_type} url={url or '-'} message={message}",
        seconds_from_start=1.0,
    )


def resource_dimension(events: list[DiagnosticEvent]):
    result = score_sample(
        sample=Sample(id="probe-sample"),
        events=events,
        metadata={},
        log_path=Path("/tmp/probe-log.txt"),
        screenshot_path=None,
        web_snapshot_paths=[],
        exit_code=0,
        duration_seconds=10.0,
    )
    for dimension in result.dimensions:
        if dimension.name == "resource_compatibility":
            return dimension
    raise AssertionError("resource_compatibility dimension missing")


class WebBenchmarkBridgeScoringTests(unittest.TestCase):
    def test_wholesale_bridge_regression_fails_resource_dimension(self) -> None:
        # 桥整体坏死：任意 host 的代理传输失败（host 不含可选远端名单子串，
        # network.proxy.error 的集合成员资格由本断言钉住——移除该前缀时
        # 罚分降为 8、score 7 仍 fail 但 findings 归因变化，此处用三类各一
        # 条保证移除任一前缀都改变罚分构成）。
        dimension = resource_dimension(
            [
                make_event("network.proxy.error", "GET https://assets.example.net/x timeout", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("fetch.proxy.error", "GET https://api.example.net/y connection lost", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("xhr.proxy.error", "GET https://data.example.net/z request_failed", url="http://127.0.0.1:1/mwx-t/index.html"),
            ]
        )
        self.assertLess(dimension.score, 8, f"bridge death must fail (score={dimension.score})")
        self.assertEqual(dimension.status, "fail")
        self.assertIn("host resource mapping issue", " ".join(dimension.findings))

    def test_swift_side_bridge_signature_alone_fails(self) -> None:
        # 单独移除 network.proxy.error 前缀的回归锚：仅 Swift 侧签名（页面
        # 无 fetch/XHR 回声）也必须触发未封顶罚分。
        dimension = resource_dimension(
            [
                make_event("network.proxy.error", "GET https://assets.example.net/x timeout", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("network.proxy.error", "GET https://api.example.net/y timeout", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("network.proxy.error", "GET https://data.example.net/z timeout", url="http://127.0.0.1:1/mwx-t/index.html"),
            ]
        )
        self.assertLess(dimension.score, 8, f"swift-side-only bridge death must fail (score={dimension.score})")
        self.assertEqual(dimension.status, "fail")

    def test_benign_whitelist_denials_do_not_penalize(self) -> None:
        # 白名单拒绝是正常防护：不计分。
        dimension = resource_dimension(
            [
                make_event("network.proxy.denied", "GET https://not-whitelisted.example.com", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("network.proxy.overloaded", "GET https://whitelisted.example.com too_many_requests", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("network.proxy.authorization.timeout", "GET https://blackholed.example.com", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("network.proxy.too-large", "GET https://heavy.example.com response_too_large", url="http://127.0.0.1:1/mwx-t/index.html"),
            ]
        )
        self.assertEqual(dimension.score, 15, f"protection signatures must stay uncounted (score={dimension.score})")
        self.assertEqual(dimension.status, "pass")

    def test_page_side_protection_token_echoes_stay_capped_noise(self) -> None:
        # 防护 token 的页面侧孪生：宿主回包 {ok:false} 后 fetch/XHR 代理
        # reject 落 fetch.proxy.error/xhr.proxy.error（message 带回包 token）——
        # 与宿主侧专项诊断一致按样本噪音封顶，不触发 host mapping 罚分。
        dimension = resource_dimension(
            [
                make_event("fetch.proxy.error", "GET https://unregistered.example.com destination_not_allowed", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("fetch.proxy.error", "GET https://burst.example.com too_many_requests", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("xhr.proxy.error", "GET https://blackhole.example.com authorization_timeout", url="http://127.0.0.1:1/mwx-t/index.html"),
                make_event("fetch.proxy.error", "GET https://heavy.example.com response_too_large", url="http://127.0.0.1:1/mwx-t/index.html"),
            ]
        )
        self.assertGreaterEqual(dimension.score, 11, f"protection-token echoes must stay noise-capped (score={dimension.score})")
        self.assertNotIn(
            "host resource mapping issue",
            " ".join(dimension.findings),
            "protection-token echoes must not classify as host mapping issues",
        )

    def test_optional_remote_proxy_failures_stay_capped_noise(self) -> None:
        # 可选远端（fonts/google/cdn）的代理失败仍按样本噪音封顶，不触发
        # host mapping 类别——单点远端故障与整体桥回归的区分。
        optional_events = [
            make_event("fetch.proxy.error", f"GET https://fonts.googleapis.com/css{i} timeout", url="http://127.0.0.1:1/mwx-t/index.html")
            for i in range(6)
        ]
        dimension = resource_dimension(optional_events)
        self.assertGreaterEqual(dimension.score, 11, f"optional-remote proxy failures must stay noise-capped (score={dimension.score})")
        self.assertNotIn(
            "host resource mapping issue",
            " ".join(dimension.findings),
            "optional remote failures must not classify as host mapping issues",
        )


if __name__ == "__main__":
    unittest.main()
