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
- native-abort：真实 Request/fetch 在 CSP connect-src 'none' 下核取消与 signal 覆盖；
  不发外部请求，代理仍用既有回包桩，全部事实先打印再统一断言。
- native-xhr：捕获原生 XHR 方法、data: / CSP 拒绝对照与延迟桥回包，核复用及事件重入。
- native-xhr-abort：原生与代理的 abort 状态、事件重入、空响应及旧回包拒绝。
- frames：D5 frame 定向投递合同——每个注入文档 hello 登记后宿主按 frame 定向
  回写 ack；属性/音量推送经宿主逐 endpoint 定向投递直达全部已注册 frame（含
  跨源子 frame，无需主 frame 中继）；网络回包按发送 frame 定向送达；dom.ready
  唯一、子 frame 交互区域登记被丢弃。
- bridge-budget：网络桥接在飞预算守恒——单桶上限、换代整桶作废不挤压新世代、
  256 总预算打满拒绝、释放后完整归还。
- audio-output：仅此场景用受控 loopback HTTP 同源页面/WAV 测真实 PCM，
  不访问外网；HTML 可播放不等于跨源媒体获准送入 WebAudio。

各场景由命令行参数选择，一次编译、多次独立执行。F19 的原生 fetch 由
document-start 桩替换为必然失败的 Promise（生产中对应原生 fetch 的跨域失败），
因此该路径不发真实网络请求；XHR 代理路径在产品侧本就拦截 send()。
除 audio-output 的本机 HTTP 外，其余场景不发真实请求；bridge-budget 只操作内存。
"""

from pathlib import Path
import base64
import http.server
import io
import json
import math
import re
import subprocess
import tempfile
import threading
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
NETWORK_FIXTURE = ROOT / "script/tests/fixtures/WebCompatibilityNetworkChecks.swift"
AUDIO_FIXTURE = ROOT / "script/tests/fixtures/WebCompatibilityAudioOutputChecks.swift"


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
        tone = io.BytesIO()
        with wave.open(tone, "wb") as wav:
            wav.setparams((2, 2, 44100, 0, "NONE", "not compressed"))
            wav.writeframes(b"".join(int(16000 * math.sin(2 * math.pi * 440 * sample / 44100)).to_bytes(2, "little", signed=True) * 2
                                     for sample in range(44100)))
        cls.audio_output_tone = tone.getvalue()
        result = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library", "-D", "DEBUG",
                str(host / "WebWallpaperPlaybackScript.swift"),
                *map(str, sorted(host.glob("DedicatedWebWallpaperHostCompatibilityScript+*.swift"))),
                str(directory / "Harness.swift"),
                str(NETWORK_FIXTURE),
                str(AUDIO_FIXTURE),
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

    def scenario(self, name: str, *arguments: str) -> None:
        directory = self.directory
        self.assertIsNotNone(directory, "harness 未编译")
        result = subprocess.run(
            ["./harness", name, *arguments],
            cwd=str(directory),
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        if name == "audio-output":
            print(result.stdout.strip())
        self.assertIn(f"web-compat-parity-pass: {name}", result.stdout)

    def test_empty_source_is_retained_for_late_author_assignment(self) -> None:
        self.scenario("empty-source")

    def test_f01_shadow_root_attach_and_media_takeover(self) -> None:
        self.scenario("f01")

    def test_f40_dom_content_loaded_listener_identity(self) -> None:
        self.scenario("f40")

    def test_f29_dynamic_media_volume_backfill(self) -> None:
        self.scenario("f29")

    def test_real_audio_output_master_and_native_api_boundaries(self) -> None:
        bodies = {"/audio-output.html": (b"<html><body></body></html>", "text/html"),
                  "/tone.wav": (self.audio_output_tone, "audio/wav")}
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                path = self.path.partition("?")[0]
                if path not in bodies:
                    self.send_error(404)
                    return
                body, mime = bodies[path]
                start, end, status = 0, len(body) - 1, 200
                if header := self.headers.get("Range"):
                    match = re.fullmatch(r"bytes=(\d*)-(\d*)", header)
                    if match and any(match.groups()):
                        first, last = match.groups()
                        start = int(first) if first else max(0, len(body) - int(last))
                        end = min(int(last), end) if first and last else end
                    else:
                        start = len(body)
                    if start > end:
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{len(body)}")
                        self.end_headers()
                        return
                    status = 206
                requests.append((path, status, start, end))
                self.send_response(status)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(end - start + 1))
                self.send_header("Accept-Ranges", "bytes")
                if status == 206:
                    self.send_header("Content-Range", f"bytes {start}-{end}/{len(body)}")
                self.end_headers()
                self.wfile.write(body[start:end + 1])

            def log_message(self, *_):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                self.scenario("audio-output", f"http://127.0.0.1:{server.server_port}/audio-output.html")
            finally:
                server.shutdown()
                thread.join()
                print("audio-output-loopback: " + json.dumps(requests))
        self.assertEqual({path for path, *_ in requests}, set(bodies))

    def test_f19_network_bridge_binary_restore(self) -> None:
        self.scenario("f19")

    def test_native_fetch_cancellation_preserves_signal_overrides(self) -> None:
        """Compare the product wrapper with native WK fetch, including custom reasons."""
        self.scenario("native-abort-matrix")

    def test_native_xhr_reuse_dispatch_and_reentrant_open(self) -> None:
        self.scenario("native-xhr-lifecycle")

    def test_native_xhr_abort_state_events_and_late_reply(self) -> None:
        self.scenario("native-xhr-abort")

    def test_release_has_no_diagnostics_but_keeps_ready_and_audio(self) -> None:
        self.scenario("release-diagnostics")

    def test_frames_injection_boundaries(self) -> None:
        self.scenario("frames")

    def test_bridge_budget_conservation(self) -> None:
        self.scenario("bridge-budget")


if __name__ == "__main__":
    unittest.main()
