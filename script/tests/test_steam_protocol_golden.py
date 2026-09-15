#!/usr/bin/env python3

"""SK1.1 双端协议 golden 消息合同测试（纯解析，不执行任何二进制）。

golden 文件是 C# 与 Swift 两侧协议实现的单一事实源：
- requests.jsonl / responses.jsonl：正向 envelope 形状
- negative-frames.jsonl：必须被拒绝的帧（自描述期望错误）
- error-codes.json：错误码 taxonomy 单一事实源

运行：python3.12 -B script/tests/test_steam_protocol_golden.py
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPOSITORY_ROOT / "script/tests/fixtures/steam-protocol"

ALLOWED_TYPES = {"request", "result", "event", "ready"}
SECRET_KEYS = {
    "access_token",
    "accesstoken",
    "refresh_token",
    "refreshtoken",
    "guard_data",
    "guarddata",
    "password",
    "steamloginsecure",
    "secret",
}
PRIVATE_KEY = "private"


def load_jsonl(name: str) -> list[str]:
    lines = (FIXTURES / name).read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line.strip()]


def secret_keys_in(node: object, path: str = "", inside_private: bool = False) -> list[str]:
    """收集 private 包装之外出现的凭据形状键。"""
    leaks: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            child_path = f"{path}.{key}" if path else key
            child_inside = inside_private or key == PRIVATE_KEY
            if key.lower() in SECRET_KEYS and not child_inside:
                leaks.append(child_path)
            leaks.extend(secret_keys_in(value, child_path, child_inside))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            leaks.extend(secret_keys_in(value, f"{path}[{index}]", inside_private))
    return leaks


class SteamProtocolGoldenTests(unittest.TestCase):
    def setUp(self) -> None:
        self.codes = json.loads((FIXTURES / "error-codes.json").read_text(encoding="utf-8"))["codes"]
        self.requests = [json.loads(line) for line in load_jsonl("requests.jsonl")]
        self.responses = [json.loads(line) for line in load_jsonl("responses.jsonl")]
        self.negatives = [json.loads(line) for line in load_jsonl("negative-frames.jsonl")]

    def test_camel_case_secrets_cannot_escape_private(self) -> None:
        self.assertEqual(secret_keys_in({"data": {"accessToken": "fake"}}), ["data.accessToken"])
        self.assertEqual(secret_keys_in({"private": {"accessToken": "fake"}}), [])

    def test_error_code_taxonomy_single_source(self) -> None:
        self.assertIsInstance(self.codes, list)
        self.assertEqual(len(self.codes), len(set(self.codes)))
        self.assertIn("protocolMismatch", self.codes)
        self.assertIn("network", self.codes)

    def test_golden_requests_follow_envelope(self) -> None:
        self.assertGreaterEqual(len(self.requests), 4)
        for frame in self.requests:
            self.assertEqual(frame["v"], 1)
            self.assertEqual(frame["type"], "request")
            self.assertTrue(frame["requestId"])
            self.assertTrue(frame["command"])
            self.assertIsInstance(frame["processEpoch"], int)

    def test_golden_responses_follow_envelope(self) -> None:
        self.assertGreaterEqual(len(self.responses), 6)
        for frame in self.responses:
            self.assertEqual(frame["v"], 1)
            self.assertIn(frame["type"], ALLOWED_TYPES)
            if frame["type"] == "result":
                self.assertIsInstance(frame["ok"], bool)
                if frame["ok"] is False:
                    self.assertIn(frame["error"]["code"], self.codes)
            if frame["type"] == "event":
                self.assertTrue(frame["event"])

    def test_terminal_once_per_request(self) -> None:
        terminals = [
            frame["requestId"]
            for frame in self.responses
            if frame["type"] == "result"
        ]
        self.assertEqual(len(terminals), len(set(terminals)))

    def test_out_of_order_progress_is_tolerable_shape(self) -> None:
        sequences = [
            frame["sequence"]
            for frame in self.responses
            if frame["type"] == "event" and frame["event"] == "downloadProgress"
        ]
        self.assertEqual(sorted(sequences), [1, 2])
        self.assertEqual(sequences, [2, 1], "golden 必须保留乱序进度样例")

    def test_uint64_max_id_is_decimal_string(self) -> None:
        max_frames = [
            frame
            for frame in self.requests
            if frame.get("payload", {}).get("workshopId") == "18446744073709551615"
        ]
        self.assertEqual(len(max_frames), 1)
        for frame in self.responses:
            steam_id = frame.get("data", {}).get("steamId") if isinstance(frame.get("data"), dict) else None
            if steam_id is not None:
                # 合同点：64 位 ID 必须是十进制字符串（golden 允许中段脱敏）。
                self.assertIsInstance(steam_id, str)
                self.assertRegex(steam_id, r"^[0-9*]+$")

    def test_negative_frames_self_describing(self) -> None:
        self.assertGreaterEqual(len(self.negatives), 5)
        for wrapper in self.negatives:
            self.assertIn(wrapper["expect"], self.codes)
            self.assertTrue(wrapper["reason"])
            # 帧体要么解析失败（bad json 反例），要么是 dict；真正的拒绝行为
            # 由 C#/Swift selftest 验证，这里只保证 golden 自描述一致。
            try:
                frame = json.loads(wrapper["frame"])
            except json.JSONDecodeError:
                continue
            self.assertIsInstance(frame, dict)

    def test_no_secrets_outside_private_wrapper(self) -> None:
        leaked = []
        for frame in self.requests:
            leaked.extend(secret_keys_in(frame))
        for frame in self.responses:
            leaked.extend(secret_keys_in(frame))
        self.assertEqual(leaked, [], f"private 包装外出现凭据形状键: {leaked}")

    def test_private_wrapper_present_exactly_once(self) -> None:
        privates = [
            frame
            for frame in self.responses
            if PRIVATE_KEY in frame
        ]
        self.assertEqual(len(privates), 1)
        self.assertEqual(privates[0]["type"], "result")

    def test_all_golden_lines_within_frame_limit(self) -> None:
        limit = 1_048_576
        for name in ("requests.jsonl", "responses.jsonl", "negative-frames.jsonl"):
            for line in load_jsonl(name):
                self.assertLessEqual(len(line.encode("utf-8")), limit)

    def test_unicode_frame_round_trip(self) -> None:
        unicode_frames = [
            frame
            for frame in self.requests
            if frame["requestId"] == "req-query-中文-✅"
        ]
        self.assertEqual(len(unicode_frames), 1)
        self.assertEqual(unicode_frames[0]["payload"]["searchText"], "中文搜索✅")
        raw_lines = load_jsonl("requests.jsonl")
        self.assertTrue(
            any("req-query-中文-✅" in line for line in raw_lines),
            "golden 文件必须以 UTF-8 原文保留 unicode 帧",
        )


if __name__ == "__main__":
    unittest.main()
