#!/usr/bin/env python3
"""Web 兼容脚本的行为回归：F01 / F40 / F29 / F19，外加多 frame 注入面边界。

前四条行为此前只有一次性 vm/人工验证，仓库内没有可复跑断言。本用例沿用
`test_web_playback_pause` 的模式：从产品源码提取 `webCompatibilityScript` 与
`applyVolume`，与全部兼容脚本段、内联桩一起用 swiftc 编译成一个 harness 可执行
文件，再由 harness 把脚本注入真实 WKWebView 文档后逐条断言：

- F01：attachShadow 包装器作用域错误令 Shadow DOM 壁纸整页脚本中断。
- F40：DOMContentLoaded 包装器破坏 addEventListener/removeEventListener 同一性。
- F29：宿主音量只对快照节点生效，动态新建的媒体节点以默认音量播放。
- F19：网络代理回填非 UTF-8 响应体时缺少编码标志，fetch/XHR 只能拿到文本。
- frames：D5 frame 定向投递合同——每个注入文档 hello 登记后宿主按 frame 定向
  回写 ack；属性/音量推送经宿主逐 endpoint 定向投递直达全部已注册 frame（含
  跨源子 frame，无需主 frame 中继）；网络回包按发送 frame 定向送达；dom.ready
  唯一、子 frame 交互区域登记被丢弃。
- bridge-budget：网络桥接在飞预算守恒——单桶上限、换代整桶作废不挤压新世代、
  256 总预算打满拒绝、释放后完整归还。

各场景由命令行参数选择，一次编译、多次独立执行。F19 的原生 fetch 由
document-start 桩替换为必然失败的 Promise（生产中对应原生 fetch 的跨域失败），
因此整个用例不发出任何真实网络请求；XHR 代理路径在产品侧本就拦截 send()，
同样不发真实请求。bridge-budget 场景只操作内存中的在飞预算登记，无任何网络。
"""

from pathlib import Path
import base64
import io
import subprocess
import tempfile
import unittest
import wave

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]


def source_block(source: str, marker: str) -> str:
    """从 marker 行起做花括号配平，截取完整声明文本（供顶层类型提取）。"""
    index = source.index(marker)
    line_start = source.rfind("\n", 0, index) + 1
    depth = 0
    started = False
    for position in range(index, len(source)):
        char = source[position]
        if char == "{":
            depth += 1
            started = True
        elif char == "}":
            depth -= 1
            if started and depth == 0:
                return source[line_start:position + 1]
    raise AssertionError(f"声明未闭合: {marker}")


HARNESS = (ROOT / "script/tests/fixtures/WebCompatibilityParityHarness.swift").read_text()


class WebCompatibilityParityTests(unittest.TestCase):
    temporary: tempfile.TemporaryDirectory | None = None
    directory: Path | None = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-web-compat-parity-")
        directory = Path(cls.temporary.name)
        host = ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host"
        types_source = (host / "WebWallpaperHostTypes.swift").read_text()
        runtime_source = (
            host / "DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift"
        ).read_text()
        adapter = method(types_source, "static func webCompatibilityScript(")
        adapter += "\n" + method(runtime_source, "func applyVolume(")
        # D5：推送投递面与序号包装随 applyVolume 一起提取（拆分后从
        # FrameReply.swift 提取，sequencedPushScript 已放宽 internal），harness
        # 内的 WebWallpaperFrameEndpointRegistry 桩提供其依赖表面。
        frame_reply_source = (
            host / "DedicatedWebWallpaperHostPlaceholderAdapter+FrameReply.swift"
        ).read_text()
        adapter += "\n" + method(frame_reply_source, "func deliverStatePush(")
        adapter += "\n" + method(frame_reply_source, "func sequencedPushScript(")
        # 在飞预算守恒场景用真实登记表（按 owner 匹配桶计数派生总量）。
        registry = source_block(runtime_source, "private final class WebNetworkBridgeInflightRegistry")
        audio = io.BytesIO()
        with wave.open(audio, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(1)
            wav.setframerate(8000)
            wav.writeframes(bytes([128]) * 8000)
        harness = HARNESS.replace("// RUNTIME_HELPERS", registry).replace(
            "// ADAPTER_METHODS", adapter
        ).replace(
            "__MEDIA__", base64.b64encode(audio.getvalue()).decode()
        )
        (directory / "Harness.swift").write_text(harness)
        result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library", "-D", "DEBUG",
                str(host / "WebWallpaperPlaybackScript.swift"),
                *map(str, sorted(host.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
                str(directory / "Harness.swift"),
                "-o",
                str(directory / "harness"),
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if result.returncode != 0:
            raise AssertionError(f"harness 编译失败:\n{result.stderr}")
        cls.directory = directory

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.temporary is not None:
            cls.temporary.cleanup()

    def scenario(self, name: str) -> None:
        directory = self.directory
        self.assertIsNotNone(directory, "harness 未编译")
        result = subprocess.run(
            ["./harness", name],
            cwd=str(directory),
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"web-compat-parity-pass: {name}", result.stdout)

    def test_empty_source_is_retained_for_late_author_assignment(self) -> None:
        self.scenario("empty-source")

    def test_f01_shadow_root_attach_and_media_takeover(self) -> None:
        self.scenario("f01")

    def test_f40_dom_content_loaded_listener_identity(self) -> None:
        self.scenario("f40")

    def test_f29_dynamic_media_volume_backfill(self) -> None:
        self.scenario("f29")

    def test_f19_network_bridge_binary_restore(self) -> None:
        self.scenario("f19")

    def test_release_has_no_diagnostics_but_keeps_ready_and_audio(self) -> None:
        self.scenario("release-diagnostics")

    def test_frames_injection_boundaries(self) -> None:
        self.scenario("frames")

    def test_bridge_budget_conservation(self) -> None:
        self.scenario("bridge-budget")


if __name__ == "__main__":
    unittest.main()
