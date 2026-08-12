#!/usr/bin/env python3
"""pulse planner 的 fail-closed 准入与逐指纹 profile 测试。

与 tint/opacity 的关键差异，各有专门断言：
- shader 源按 ScenePulseShaderProfile 多指纹白名单准入，stock 与 legacy 变体
  绑定不同的 phase 偏移、noise UV 系数、noisespeed 默认/range 与输出 clamp；
- `AUDIOPROCESSING != 0`（无音频管线）、未知常量键（语料把编辑器 label 当 key）、
  SceneScript 绑定、bounds x >= y 全部整条拒绝；
- slot 1 只接受缺省或显式 `util/noise`，slot 2 遮罩挂在实例上。
"""

from __future__ import annotations

import base64
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_SHADERS = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/pulse/shaders/effects"
)
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceGraphBuilder.swift",
    SOURCE_ROOT / "Resources/SceneShaderSourceResolver.swift",
    SOURCE_ROOT / "Resources/SceneResourceView.swift",
    SOURCE_ROOT / "Resources/SceneResourceIndex.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader+SourceGraph.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "RenderGraph/ScenePulseShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/ScenePulseExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredPulsePlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredPulsePlanner+Constants.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Runtime/SceneAudioResponse.swift",
    SOURCE_ROOT / "RenderGraph/SceneAudioResponseAdmission.swift",
]

# 语料历史版本 shader 源（v-a=1937925563/2131872317/2241938645，
# v-b=2419444134，v-c=2473638329），指纹已进 ScenePulseShaderProfile 白名单。
LEGACY_VERT_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19hdWRpb19yZXNw"
    "b25zZSIsImNvbWJvIjoiQVVESU9QUk9DRVNTSU5HIiwidHlwZSI6ImF1ZGlvcHJvY2Vzc2luZ29w"
    "dGlvbnMiLCJkZWZhdWx0IjowfQ0KDQp1bmlmb3JtIG1hdDQgZ19Nb2RlbFZpZXdQcm9qZWN0aW9u"
    "TWF0cml4Ow0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFSZXNvbHV0aW9uOw0KDQojaWYgTUFTSyA9"
    "PSAxDQp1bmlmb3JtIHZlYzQgZ19UZXh0dXJlMlJlc29sdXRpb247DQojZW5kaWYNCg0KYXR0cmli"
    "dXRlIHZlYzMgYV9Qb3NpdGlvbjsNCmF0dHJpYnV0ZSB2ZWMyIGFfVGV4Q29vcmQ7DQoNCnZhcnlp"
    "bmcgdmVjNCB2X1RleENvb3JkOw0KDQojaWYgQVVESU9QUk9DRVNTSU5HDQp2YXJ5aW5nIGZsb2F0"
    "IHZfQXVkaW9QdWxzZTsNCnVuaWZvcm0gZmxvYXQgZ19BdWRpb1NwZWN0cnVtMTZMZWZ0WzE2XTsN"
    "CnVuaWZvcm0gZmxvYXQgZ19BdWRpb1NwZWN0cnVtMTZSaWdodFsxNl07DQoNCnVuaWZvcm0gZmxv"
    "YXQgZ19BdWRpb0ZyZXF1ZW5jeU1pbjsgLy8geyJtYXRlcmlhbCI6ImZyZXF1ZW5jeW1pbiIsImxh"
    "YmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfZnJlcXVlbmN5X21pbiIsImRlZmF1bHQiOjAsImlu"
    "dCI6dHJ1ZSwicmFuZ2UiOlswLDE1XX0NCnVuaWZvcm0gZmxvYXQgZ19BdWRpb0ZyZXF1ZW5jeU1h"
    "eDsgLy8geyJtYXRlcmlhbCI6ImZyZXF1ZW5jeW1heCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3Bl"
    "cnRpZXNfZnJlcXVlbmN5X21heCIsImRlZmF1bHQiOjEsImludCI6dHJ1ZSwicmFuZ2UiOlswLDE1"
    "XX0NCnVuaWZvcm0gZmxvYXQgZ19BdWRpb1Bvd2VyOyAvLyB7Im1hdGVyaWFsIjoiYXVkaW9leHBv"
    "bmVudCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfYXVkaW9fZXhwb25lbnQiLCJkZWZh"
    "dWx0IjoxLjAsInJhbmdlIjpbMCw0XX0NCnVuaWZvcm0gdmVjMiBnX0F1ZGlvQm91bmRzOyAvLyB7"
    "Im1hdGVyaWFsIjoiYXVkaW9ib3VuZHMiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2F1"
    "ZGlvX2JvdW5kcyIsImRlZmF1bHQiOiIwLjUgMS4wIn0NCnVuaWZvcm0gZmxvYXQgZ19BdWRpb011"
    "bHRpcGx5OyAvLyB7Im1hdGVyaWFsIjoiYXVkaW9hbW91bnQiLCJsYWJlbCI6InVpX2VkaXRvcl9w"
    "cm9wZXJ0aWVzX2F1ZGlvX2Ftb3VudCIsImRlZmF1bHQiOjEsInJhbmdlIjpbMCwyXX0NCg0KZmxv"
    "YXQgQ3JlYXRlQXVkaW9SZXNwb25zZShmbG9hdCBidWZmZXJMZWZ0WzE2XSwgZmxvYXQgYnVmZmVy"
    "UmlnaHRbMTZdKQ0Kew0KCWZsb2F0IGF1ZGlvRnJlcXVlbmN5RW5kID0gbWF4KGdfQXVkaW9GcmVx"
    "dWVuY3lNaW4sIGdfQXVkaW9GcmVxdWVuY3lNYXgpOw0KCWZsb2F0IGF1ZGlvUmVzcG9uc2UgPSAw"
    "LjA7DQoNCiNpZiBBVURJT1BST0NFU1NJTkcgPT0gMQ0KCWZvciAoaW50IGEgPSBpbnQoZ19BdWRp"
    "b0ZyZXF1ZW5jeU1pbik7IGEgPD0gaW50KGdfQXVkaW9GcmVxdWVuY3lNYXgpOyArK2EpDQoJew0K"
    "CQlhdWRpb1Jlc3BvbnNlICs9IGJ1ZmZlckxlZnRbYV07DQoJfQ0KCWF1ZGlvUmVzcG9uc2UgLz0g"
    "KGdfQXVkaW9GcmVxdWVuY3lNYXggLSBnX0F1ZGlvRnJlcXVlbmN5TWluICsgMS4wKTsNCiNlbmRp"
    "Zg0KI2lmIEFVRElPUFJPQ0VTU0lORyA9PSAyDQoJZm9yIChpbnQgYSA9IGludChnX0F1ZGlvRnJl"
    "cXVlbmN5TWluKTsgYSA8PSBpbnQoZ19BdWRpb0ZyZXF1ZW5jeU1heCk7ICsrYSkNCgl7DQoJCWF1"
    "ZGlvUmVzcG9uc2UgKz0gYnVmZmVyUmlnaHRbYV07DQoJfQ0KCWF1ZGlvUmVzcG9uc2UgLz0gKGdf"
    "QXVkaW9GcmVxdWVuY3lNYXggLSBnX0F1ZGlvRnJlcXVlbmN5TWluICsgMS4wKTsNCiNlbmRpZg0K"
    "I2lmIEFVRElPUFJPQ0VTU0lORyA9PSAzDQoJZm9yIChpbnQgYSA9IGludChnX0F1ZGlvRnJlcXVl"
    "bmN5TWluKTsgYSA8PSBpbnQoZ19BdWRpb0ZyZXF1ZW5jeU1heCk7ICsrYSkNCgl7DQoJCWF1ZGlv"
    "UmVzcG9uc2UgKz0gYnVmZmVyTGVmdFthXTsNCgkJYXVkaW9SZXNwb25zZSArPSBidWZmZXJSaWdo"
    "dFthXTsNCgl9DQoJYXVkaW9SZXNwb25zZSAvPSAoZ19BdWRpb0ZyZXF1ZW5jeU1heCAtIGdfQXVk"
    "aW9GcmVxdWVuY3lNaW4gKyAxLjApICogMi4wOw0KI2VuZGlmDQoNCglhdWRpb1Jlc3BvbnNlID0g"
    "c21vb3Roc3RlcChnX0F1ZGlvQm91bmRzLngsIGdfQXVkaW9Cb3VuZHMueSwgYXVkaW9SZXNwb25z"
    "ZSk7DQoJYXVkaW9SZXNwb25zZSA9IHNhdHVyYXRlKHBvdyhhdWRpb1Jlc3BvbnNlLCBnX0F1ZGlv"
    "UG93ZXIpKSAqIGdfQXVkaW9NdWx0aXBseTsNCglyZXR1cm4gYXVkaW9SZXNwb25zZTsNCn0NCiNl"
    "bmRpZg0KDQp2b2lkIG1haW4oKSB7DQoJZ2xfUG9zaXRpb24gPSBtdWwodmVjNChhX1Bvc2l0aW9u"
    "LCAxLjApLCBnX01vZGVsVmlld1Byb2plY3Rpb25NYXRyaXgpOw0KCXZfVGV4Q29vcmQgPSBhX1Rl"
    "eENvb3JkLnh5eHk7DQoJDQojaWYgTUFTSyA9PSAxDQoJdl9UZXhDb29yZC56dyA9IHZlYzIoYV9U"
    "ZXhDb29yZC54ICogZ19UZXh0dXJlMlJlc29sdXRpb24ueiAvIGdfVGV4dHVyZTJSZXNvbHV0aW9u"
    "LngsDQoJCQkJCQlhX1RleENvb3JkLnkgKiBnX1RleHR1cmUyUmVzb2x1dGlvbi53IC8gZ19UZXh0"
    "dXJlMlJlc29sdXRpb24ueSk7DQojZW5kaWYNCg0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCXZfQXVk"
    "aW9QdWxzZSA9IENyZWF0ZUF1ZGlvUmVzcG9uc2UoZ19BdWRpb1NwZWN0cnVtMTZMZWZ0LCBnX0F1"
    "ZGlvU3BlY3RydW0xNlJpZ2h0KTsNCiNlbmRpZg0KfQ0K"
)
LEGACY_FRAG_SATURATE_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ibGVuZF9tb2Rl"
    "IiwiY29tYm8iOiJCTEVORE1PREUiLCJ0eXBlIjoiaW1hZ2VibGVuZGluZyIsImRlZmF1bHQiOjl9"
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wdWxzZV9hbHBo"
    "YSIsImNvbWJvIjoiUFVMU0VBTFBIQSIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MH0NCi8v"
    "IFtDT01CT10geyJtYXRlcmlhbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2NvbG9yIiwi"
    "Y29tYm8iOiJQVUxTRUNPTE9SIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjoxfQ0KDQojaW5j"
    "bHVkZSAiY29tbW9uX2JsZW5kaW5nLmgiDQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KDQoj"
    "aWYgQVVESU9QUk9DRVNTSU5HDQp2YXJ5aW5nIGZsb2F0IHZfQXVkaW9QdWxzZTsNCiNlbmRpZg0K"
    "DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7Im1hdGVyaWFsIjoiZnJhbWVidWZm"
    "ZXIiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2ZyYW1lYnVmZmVyIiwiaGlkZGVuIjp0"
    "cnVlfQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMTsgLy8geyJtYXRlcmlhbCI6Im5vaXNl"
    "IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZSIsImRlZmF1bHQiOiJ1dGlsL25v"
    "aXNlIn0NCg0KI2lmIE1BU0sgPT0gMQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMjsgLy8g"
    "eyJtYXRlcmlhbCI6Im1hc2siLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX29wYWNpdHlf"
    "bWFzayIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoiTUFTSyIsImRlZmF1bHQiOiJ1dGls"
    "L3doaXRlIiwicGFpbnRkZWZhdWx0Y29sb3IiOiIwIDAgMCAxIn0NCiNlbmRpZg0KDQp1bmlmb3Jt"
    "IGZsb2F0IGdfVGltZTsNCg0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlU3BlZWQ7IC8vIHsibWF0ZXJp"
    "YWwiOiJzcGVlZCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vfc3BlZWQiLCJk"
    "ZWZhdWx0IjozLCJyYW5nZSI6WzAsMTBdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlUGhhc2U7IC8v"
    "IHsibWF0ZXJpYWwiOiJwaGFzZSIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vf"
    "cGhhc2UiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsNi4yODJdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1"
    "bHNlQW1vdW50OyAvLyB7Im1hdGVyaWFsIjoiYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJv"
    "cGVydGllc19wdWxzZV9hbW91bnQiLCJkZWZhdWx0IjoxLCJyYW5nZSI6WzAsMl19DQp1bmlmb3Jt"
    "IHZlYzIgZ19QdWxzZVRocmVzaG9sZHM7IC8vIHsibWF0ZXJpYWwiOiJib3VuZHMiLCJsYWJlbCI6"
    "InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2JvdW5kcyIsImRlZmF1bHQiOiIwIDEifQ0KDQp1"
    "bmlmb3JtIGZsb2F0IGdfTm9pc2VTcGVlZDsgLy8geyJtYXRlcmlhbCI6Im5vaXNlc3BlZWQiLCJs"
    "YWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX25vaXNlX3NwZWVkIiwiZGVmYXVsdCI6MC4xLCJy"
    "YW5nZSI6WzAsMC41XX0NCnVuaWZvcm0gZmxvYXQgZ19Ob2lzZUFtb3VudDsgLy8geyJtYXRlcmlh"
    "bCI6Im5vaXNlYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZV9hbW91"
    "bnQiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsMl19DQoNCnVuaWZvcm0gZmxvYXQgZ19Qb3dlcjsg"
    "Ly8geyJtYXRlcmlhbCI6InBvd2VyIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wb3dl"
    "ciIsImRlZmF1bHQiOjEsInJhbmdlIjpbMCw0XX0NCnVuaWZvcm0gdmVjMyBnX1RpbnRDb2xvcjE7"
    "IC8vIHsibWF0ZXJpYWwiOiJ0aW50bG93IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc190"
    "aW50X2xvdyIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIxIDEgMSJ9DQp1bmlmb3JtIHZl"
    "YzMgZ19UaW50Q29sb3IyOyAvLyB7Im1hdGVyaWFsIjoidGludGhpZ2giLCJsYWJlbCI6InVpX2Vk"
    "aXRvcl9wcm9wZXJ0aWVzX3RpbnRfaGlnaCIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIx"
    "IDEgMSJ9DQoNCnZvaWQgbWFpbigpIHsNCgl2ZWM0IHNhbXBsZSA9IHRleFNhbXBsZTJEKGdfVGV4"
    "dHVyZTAsIHZfVGV4Q29vcmQueHkpOw0KCXZlYzQgYWxiZWRvID0gc2FtcGxlOw0KCWZsb2F0IHB1"
    "bHNlID0gMC4wOw0KCQ0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCXB1bHNlID0gdl9BdWRpb1B1bHNl"
    "Ow0KI2Vsc2UNCglwdWxzZSA9IHNtb290aHN0ZXAoZ19QdWxzZVRocmVzaG9sZHMueCwgZ19QdWxz"
    "ZVRocmVzaG9sZHMueSwgc2luKGdfVGltZSAqIGdfUHVsc2VTcGVlZCArIGdfUHVsc2VQaGFzZSkg"
    "KiAwLjUgKyAwLjUpICogZ19QdWxzZUFtb3VudDsNCglmbG9hdCBub2lzZSA9IHRleFNhbXBsZTJE"
    "KGdfVGV4dHVyZTEsIHZlYzIoZ19UaW1lLCBnX1RpbWUgKiAwLjMzMykgKiBnX05vaXNlU3BlZWQp"
    "LnIgKiBnX05vaXNlQW1vdW50Ow0KCQ0KCXB1bHNlICs9IG5vaXNlOw0KCXB1bHNlID0gcG93KHB1"
    "bHNlLCBnX1Bvd2VyKTsNCiNlbmRpZg0KCQ0KI2lmIFBVTFNFQ09MT1INCglhbGJlZG8ucmdiID0g"
    "QXBwbHlCbGVuZGluZyhCTEVORE1PREUsIGFsYmVkby5yZ2IgKiBnX1RpbnRDb2xvcjEsIGFsYmVk"
    "by5yZ2IgKiBnX1RpbnRDb2xvcjIsIHB1bHNlKTsNCiNlbmRpZg0KDQojaWYgUFVMU0VBTFBIQQ0K"
    "CWFsYmVkby5hICo9IHB1bHNlOw0KI2VuZGlmDQoNCiNpZiBNQVNLID09IDENCglmbG9hdCBtYXNr"
    "ID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhDb29yZC56dykucjsNCglhbGJlZG8gPSBt"
    "aXgoc2FtcGxlLCBhbGJlZG8sIG1hc2spOw0KI2VuZGlmDQoNCglnbF9GcmFnQ29sb3IgPSBzYXR1"
    "cmF0ZShhbGJlZG8pOw0KfQ0K"
)
LEGACY_FRAG_CAST3_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ibGVuZF9tb2Rl"
    "IiwiY29tYm8iOiJCTEVORE1PREUiLCJ0eXBlIjoiaW1hZ2VibGVuZGluZyIsImRlZmF1bHQiOjl9"
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wdWxzZV9hbHBo"
    "YSIsImNvbWJvIjoiUFVMU0VBTFBIQSIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MH0NCi8v"
    "IFtDT01CT10geyJtYXRlcmlhbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2NvbG9yIiwi"
    "Y29tYm8iOiJQVUxTRUNPTE9SIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjoxfQ0KDQojaW5j"
    "bHVkZSAiY29tbW9uX2JsZW5kaW5nLmgiDQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KDQoj"
    "aWYgQVVESU9QUk9DRVNTSU5HDQp2YXJ5aW5nIGZsb2F0IHZfQXVkaW9QdWxzZTsNCiNlbmRpZg0K"
    "DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7Im1hdGVyaWFsIjoiZnJhbWVidWZm"
    "ZXIiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2ZyYW1lYnVmZmVyIiwiaGlkZGVuIjp0"
    "cnVlfQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMTsgLy8geyJtYXRlcmlhbCI6Im5vaXNl"
    "IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZSIsImRlZmF1bHQiOiJ1dGlsL25v"
    "aXNlIn0NCg0KI2lmIE1BU0sgPT0gMQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMjsgLy8g"
    "eyJtYXRlcmlhbCI6Im1hc2siLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX29wYWNpdHlf"
    "bWFzayIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoiTUFTSyIsImRlZmF1bHQiOiJ1dGls"
    "L3doaXRlIiwicGFpbnRkZWZhdWx0Y29sb3IiOiIwIDAgMCAxIn0NCiNlbmRpZg0KDQp1bmlmb3Jt"
    "IGZsb2F0IGdfVGltZTsNCg0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlU3BlZWQ7IC8vIHsibWF0ZXJp"
    "YWwiOiJzcGVlZCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vfc3BlZWQiLCJk"
    "ZWZhdWx0IjozLCJyYW5nZSI6WzAsMTBdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlUGhhc2U7IC8v"
    "IHsibWF0ZXJpYWwiOiJwaGFzZSIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vf"
    "cGhhc2UiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsNi4yODJdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1"
    "bHNlQW1vdW50OyAvLyB7Im1hdGVyaWFsIjoiYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJv"
    "cGVydGllc19wdWxzZV9hbW91bnQiLCJkZWZhdWx0IjoxLCJyYW5nZSI6WzAsMl19DQp1bmlmb3Jt"
    "IHZlYzIgZ19QdWxzZVRocmVzaG9sZHM7IC8vIHsibWF0ZXJpYWwiOiJib3VuZHMiLCJsYWJlbCI6"
    "InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2JvdW5kcyIsImRlZmF1bHQiOiIwIDEifQ0KDQp1"
    "bmlmb3JtIGZsb2F0IGdfTm9pc2VTcGVlZDsgLy8geyJtYXRlcmlhbCI6Im5vaXNlc3BlZWQiLCJs"
    "YWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX25vaXNlX3NwZWVkIiwiZGVmYXVsdCI6MC4xLCJy"
    "YW5nZSI6WzAsMC41XX0NCnVuaWZvcm0gZmxvYXQgZ19Ob2lzZUFtb3VudDsgLy8geyJtYXRlcmlh"
    "bCI6Im5vaXNlYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZV9hbW91"
    "bnQiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsMl19DQoNCnVuaWZvcm0gZmxvYXQgZ19Qb3dlcjsg"
    "Ly8geyJtYXRlcmlhbCI6InBvd2VyIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wb3dl"
    "ciIsImRlZmF1bHQiOjEsInJhbmdlIjpbMCw0XX0NCnVuaWZvcm0gdmVjMyBnX1RpbnRDb2xvcjE7"
    "IC8vIHsibWF0ZXJpYWwiOiJ0aW50bG93IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc190"
    "aW50X2xvdyIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIxIDEgMSJ9DQp1bmlmb3JtIHZl"
    "YzMgZ19UaW50Q29sb3IyOyAvLyB7Im1hdGVyaWFsIjoidGludGhpZ2giLCJsYWJlbCI6InVpX2Vk"
    "aXRvcl9wcm9wZXJ0aWVzX3RpbnRfaGlnaCIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIx"
    "IDEgMSJ9DQoNCnZvaWQgbWFpbigpIHsNCgl2ZWM0IHNhbXBsZSA9IHRleFNhbXBsZTJEKGdfVGV4"
    "dHVyZTAsIHZfVGV4Q29vcmQueHkpOw0KCXZlYzQgYWxiZWRvID0gc2FtcGxlOw0KCWZsb2F0IHB1"
    "bHNlID0gMC4wOw0KCQ0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCXB1bHNlID0gdl9BdWRpb1B1bHNl"
    "Ow0KI2Vsc2UNCglwdWxzZSA9IHNtb290aHN0ZXAoZ19QdWxzZVRocmVzaG9sZHMueCwgZ19QdWxz"
    "ZVRocmVzaG9sZHMueSwgc2luKGdfVGltZSAqIGdfUHVsc2VTcGVlZCArIGdfUHVsc2VQaGFzZSkg"
    "KiAwLjUgKyAwLjUpICogZ19QdWxzZUFtb3VudDsNCglmbG9hdCBub2lzZSA9IHRleFNhbXBsZTJE"
    "KGdfVGV4dHVyZTEsIHZlYzIoZ19UaW1lLCBnX1RpbWUgKiAwLjMzMykgKiBnX05vaXNlU3BlZWQp"
    "LnIgKiBnX05vaXNlQW1vdW50Ow0KCQ0KCXB1bHNlICs9IG5vaXNlOw0KCXB1bHNlID0gcG93KHB1"
    "bHNlLCBnX1Bvd2VyKTsNCiNlbmRpZg0KCQ0KI2lmIFBVTFNFQ09MT1INCglhbGJlZG8ucmdiID0g"
    "QXBwbHlCbGVuZGluZyhCTEVORE1PREUsIGFsYmVkby5yZ2IgKiBnX1RpbnRDb2xvcjEsIGFsYmVk"
    "by5yZ2IgKiBnX1RpbnRDb2xvcjIsIHB1bHNlKTsNCiNlbmRpZg0KDQojaWYgUFVMU0VBTFBIQQ0K"
    "CWFsYmVkby5hICo9IHB1bHNlOw0KI2VuZGlmDQoNCiNpZiBNQVNLID09IDENCglmbG9hdCBtYXNr"
    "ID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhDb29yZC56dykucjsNCglhbGJlZG8gPSBt"
    "aXgoc2FtcGxlLCBhbGJlZG8sIG1hc2spOw0KI2VuZGlmDQoNCglnbF9GcmFnQ29sb3IgPSB2ZWM0"
    "KG1heChDQVNUMygwKSwgYWxiZWRvLnJnYiksIGFsYmVkby5hKTsNCn0NCg=="
)
LEGACY_FRAG_LITERAL_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ibGVuZF9tb2Rl"
    "IiwiY29tYm8iOiJCTEVORE1PREUiLCJ0eXBlIjoiaW1hZ2VibGVuZGluZyIsImRlZmF1bHQiOjl9"
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wdWxzZV9hbHBo"
    "YSIsImNvbWJvIjoiUFVMU0VBTFBIQSIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MH0NCi8v"
    "IFtDT01CT10geyJtYXRlcmlhbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2NvbG9yIiwi"
    "Y29tYm8iOiJQVUxTRUNPTE9SIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjoxfQ0KDQojaW5j"
    "bHVkZSAiY29tbW9uX2JsZW5kaW5nLmgiDQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KDQoj"
    "aWYgQVVESU9QUk9DRVNTSU5HDQp2YXJ5aW5nIGZsb2F0IHZfQXVkaW9QdWxzZTsNCiNlbmRpZg0K"
    "DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7Im1hdGVyaWFsIjoiZnJhbWVidWZm"
    "ZXIiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2ZyYW1lYnVmZmVyIiwiaGlkZGVuIjp0"
    "cnVlfQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMTsgLy8geyJtYXRlcmlhbCI6Im5vaXNl"
    "IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZSIsImRlZmF1bHQiOiJ1dGlsL25v"
    "aXNlIn0NCg0KI2lmIE1BU0sgPT0gMQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMjsgLy8g"
    "eyJtYXRlcmlhbCI6Im1hc2siLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX29wYWNpdHlf"
    "bWFzayIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoiTUFTSyIsImRlZmF1bHQiOiJ1dGls"
    "L3doaXRlIiwicGFpbnRkZWZhdWx0Y29sb3IiOiIwIDAgMCAxIn0NCiNlbmRpZg0KDQp1bmlmb3Jt"
    "IGZsb2F0IGdfVGltZTsNCg0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlU3BlZWQ7IC8vIHsibWF0ZXJp"
    "YWwiOiJzcGVlZCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vfc3BlZWQiLCJk"
    "ZWZhdWx0IjozLCJyYW5nZSI6WzAsMTBdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1bHNlUGhhc2U7IC8v"
    "IHsibWF0ZXJpYWwiOiJwaGFzZSIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcHVsc2Vf"
    "cGhhc2UiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsNi4yODJdfQ0KdW5pZm9ybSBmbG9hdCBnX1B1"
    "bHNlQW1vdW50OyAvLyB7Im1hdGVyaWFsIjoiYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJv"
    "cGVydGllc19wdWxzZV9hbW91bnQiLCJkZWZhdWx0IjoxLCJyYW5nZSI6WzAsMl19DQp1bmlmb3Jt"
    "IHZlYzIgZ19QdWxzZVRocmVzaG9sZHM7IC8vIHsibWF0ZXJpYWwiOiJib3VuZHMiLCJsYWJlbCI6"
    "InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3B1bHNlX2JvdW5kcyIsImRlZmF1bHQiOiIwIDEifQ0KDQp1"
    "bmlmb3JtIGZsb2F0IGdfTm9pc2VTcGVlZDsgLy8geyJtYXRlcmlhbCI6Im5vaXNlc3BlZWQiLCJs"
    "YWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX25vaXNlX3NwZWVkIiwiZGVmYXVsdCI6MC4xLCJy"
    "YW5nZSI6WzAsMC41XX0NCnVuaWZvcm0gZmxvYXQgZ19Ob2lzZUFtb3VudDsgLy8geyJtYXRlcmlh"
    "bCI6Im5vaXNlYW1vdW50IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZV9hbW91"
    "bnQiLCJkZWZhdWx0IjowLCJyYW5nZSI6WzAsMl19DQoNCnVuaWZvcm0gZmxvYXQgZ19Qb3dlcjsg"
    "Ly8geyJtYXRlcmlhbCI6InBvd2VyIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19wb3dl"
    "ciIsImRlZmF1bHQiOjEsInJhbmdlIjpbMCw0XX0NCnVuaWZvcm0gdmVjMyBnX1RpbnRDb2xvcjE7"
    "IC8vIHsibWF0ZXJpYWwiOiJ0aW50bG93IiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc190"
    "aW50X2xvdyIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIxIDEgMSJ9DQp1bmlmb3JtIHZl"
    "YzMgZ19UaW50Q29sb3IyOyAvLyB7Im1hdGVyaWFsIjoidGludGhpZ2giLCJsYWJlbCI6InVpX2Vk"
    "aXRvcl9wcm9wZXJ0aWVzX3RpbnRfaGlnaCIsICJ0eXBlIjogImNvbG9yIiwgImRlZmF1bHQiOiIx"
    "IDEgMSJ9DQoNCnZvaWQgbWFpbigpIHsNCgl2ZWM0IHNhbXBsZSA9IHRleFNhbXBsZTJEKGdfVGV4"
    "dHVyZTAsIHZfVGV4Q29vcmQueHkpOw0KCXZlYzQgYWxiZWRvID0gc2FtcGxlOw0KCWZsb2F0IHB1"
    "bHNlID0gMC4wOw0KCQ0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCXB1bHNlID0gdl9BdWRpb1B1bHNl"
    "Ow0KI2Vsc2UNCglwdWxzZSA9IHNtb290aHN0ZXAoZ19QdWxzZVRocmVzaG9sZHMueCwgZ19QdWxz"
    "ZVRocmVzaG9sZHMueSwgc2luKGdfVGltZSAqIGdfUHVsc2VTcGVlZCArIGdfUHVsc2VQaGFzZSkg"
    "KiAwLjUgKyAwLjUpICogZ19QdWxzZUFtb3VudDsNCglmbG9hdCBub2lzZSA9IHRleFNhbXBsZTJE"
    "KGdfVGV4dHVyZTEsIHZlYzIoZ19UaW1lLCBnX1RpbWUgKiAwLjMzMykgKiBnX05vaXNlU3BlZWQp"
    "LnIgKiBnX05vaXNlQW1vdW50Ow0KCQ0KCXB1bHNlICs9IG5vaXNlOw0KCXB1bHNlID0gcG93KHB1"
    "bHNlLCBnX1Bvd2VyKTsNCiNlbmRpZg0KCQ0KI2lmIFBVTFNFQ09MT1INCglhbGJlZG8ucmdiID0g"
    "QXBwbHlCbGVuZGluZyhCTEVORE1PREUsIGFsYmVkby5yZ2IgKiBnX1RpbnRDb2xvcjEsIGFsYmVk"
    "by5yZ2IgKiBnX1RpbnRDb2xvcjIsIHB1bHNlKTsNCiNlbmRpZg0KDQojaWYgUFVMU0VBTFBIQQ0K"
    "CWFsYmVkby5hICo9IHB1bHNlOw0KI2VuZGlmDQoNCiNpZiBNQVNLID09IDENCglmbG9hdCBtYXNr"
    "ID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhDb29yZC56dykucjsNCglhbGJlZG8gPSBt"
    "aXgoc2FtcGxlLCBhbGJlZG8sIG1hc2spOw0KI2VuZGlmDQoNCglnbF9GcmFnQ29sb3IgPSB2ZWM0"
    "KG1heCgwLCBhbGJlZG8ucmdiKSwgYWxiZWRvLmEpOw0KfQ0K"
)


HARNESS = r'''
import Foundation
import simd

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneEffectTextureInput { let name: String }

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer {
        let id: Int
        let contentKind: String
        let effects: [EffectDescriptor]
    }
    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let materialRawSHA256: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        var userShaderValues: [String: String] { [:] }
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String? = nil
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Constant = ScenePulseExecutionPlan.Constant
    static let definitionPath = "effects/pulse/effect.json"
    static let materialPath = "materials/effects/pulse.json"
    static let shaderIdentity = "effects/pulse"

    struct Options {
        var contentKind = "image"
        var constants: [String: SceneDocument.ShaderValue] = [:]
        var instanceCombos: [String: Int] = [:]
        var instanceSlots: [String?] = []
        var instancePaths: [String] = []
        var instanceUserTexture = false
        var materialCombos: [String: Int] = [:]
        var materialTexture = false
        var materialConstant = false
        var blending = "normal"
        var depthTest = "disabled"
        var materialPath = Harness.materialPath
        var materialRawSHA256 =
            "76a64c2e4e0b72c056b7dc3e35f333ca5fbc3b04b345b3bdccbedd3f2334deee"
        var materialPassIndex = 0
        var shaderIdentity = Harness.shaderIdentity
        var visible: Bool? = true
        var definitionMutation = "none"
        var duplicateMaterial = false
    }

    struct GraphOptions {
        var priorInput = false
        var definitionPath = Harness.definitionPath
        var blocker = false
        var extraTarget = false
        var binding = false
        var command = false
        var condition = false
        var nodeKind = Graph.NodeKind.material
        var outputMismatch = false
        var extraEffect = false
        var extraNode = false
        var materialPath = Harness.materialPath
    }

    static func value(
        _ components: [Double],
        kind: String,
        binding: String? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: kind,
            userBinding: binding,
            components: components
        )
    }

    static func fullConstants() -> [String: SceneDocument.ShaderValue] {
        [
            "speed": value([2], kind: "number"),
            "phase": value([1.5], kind: "number"),
            "amount": value([0.8], kind: "number"),
            "bounds": value([0.1, 0.9], kind: "vector"),
            "noisespeed": value([0.25], kind: "number"),
            "noiseamount": value([0.5], kind: "number"),
            "power": value([2], kind: "number"),
            "tintlow": value([0.1, 0.2, 0.3], kind: "vector"),
            "tinthigh": value([0.9, 0.8, 0.7], kind: "vector"),
        ]
    }

    static func definition(_ mutation: String) -> SceneEffectDefinition {
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: mutation == "passMaterial" ? "materials/other.json" : materialPath,
            target: mutation == "passTarget" ? "other" : nil,
            bindings: mutation == "passBinding" ? [
                .init(name: "previous", index: 0, conditions: nil, extraFields: [:])
            ] : [],
            compose: mutation == "compose" ? .bool(true) : nil,
            command: nil,
            source: nil,
            conditions: nil,
            extraFields: mutation == "passExtra" ? ["extra": .bool(true)] : [:]
        )
        let dependencies = [
            materialPath,
            "shaders/effects/pulse.frag",
            "shaders/effects/pulse.vert",
        ]
        return SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: mutation == "missingReplacement"
                ? nil
                : mutation == "replacement" ? "other" : "pulse",
            name: mutation == "name" ? "Other" : "ui_editor_effect_pulse_title",
            description: mutation == "description"
                ? "Other"
                : "ui_editor_effect_pulse_description",
            group: mutation == "group" ? "other" : "animate",
            performance: mutation == "performance" ? "high" : nil,
            previewPath: mutation == "preview" ? "other/project.json" : "preview/project.json",
            editable: mutation == "editable" ? true : nil,
            passes: [pass],
            framebuffers: mutation == "framebuffer" ? [
                .init(
                    name: "rt", scale: nil, width: nil, height: nil, fit: nil,
                    format: nil, unique: nil, clear: nil, uvs: nil, conditions: nil,
                    extraFields: [:]
                )
            ] : [],
            dependencies: mutation == "dependencies"
                ? Array(dependencies.reversed())
                : dependencies,
            functions: mutation == "functions" ? .object([:]) : nil,
            gizmos: mutation == "gizmos" ? .array([]) : nil,
            extraFields: mutation == "extra" ? ["extra": .bool(true)] : [:],
            unknownFieldPaths: mutation == "extra" ? ["extra"] : []
        )
    }

    static func descriptor(
        _ options: Options = .init(),
        priorInput: Bool = false
    ) -> SceneRenderDescriptor {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: options.instancePaths,
            textureSlots: options.instanceSlots,
            userTextureInputs: options.instanceUserTexture ? [.init(name: "mask")] : [],
            combos: options.instanceCombos,
            constantShaderValues: options.constants
        )
        let pulse = SceneRenderDescriptor.EffectDescriptor(
            id: priorInput ? "20#effect#305" : "20#effect#21",
            file: definitionPath,
            visible: options.visible,
            passes: [pass]
        )
        let dummy = SceneRenderDescriptor.EffectDescriptor(
            id: "20#effect#21",
            file: "effects/other/effect.json",
            visible: true,
            passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(options.materialPath)#0",
            materialPath: options.materialPath,
            materialRawSHA256: options.materialRawSHA256,
            passIndex: options.materialPassIndex,
            shaderPath: options.shaderIdentity,
            texturePaths: options.materialTexture ? ["asset.png"] : [],
            textureSlots: options.materialTexture ? ["asset.png"] : [],
            userTextureInputs: [],
            combos: options.materialCombos,
            constantShaderValues: options.materialConstant
                ? ["extra": value([1], kind: "number")]
                : [:],
            blending: options.blending,
            depthTest: options.depthTest,
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        var materials = [material]
        if options.duplicateMaterial { materials.append(material) }
        let definitions = options.definitionMutation == "missing"
            ? []
            : [definition(options.definitionMutation)]
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: priorInput ? [dummy, pulse] : [pulse]
            )],
            materialPasses: materials,
            effectDefinitions: definitions
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 20, effect: effect, name: name)
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let effectIndex = options.priorInput ? 1 : 0
        let key = Graph.EffectKey(
            layerID: 20,
            effectIndex: effectIndex,
            descriptorID: options.priorInput ? "20#effect#305" : "20#effect#21"
        )
        let previousKey = Graph.EffectKey(
            layerID: 20,
            effectIndex: 0,
            descriptorID: "20#effect#21"
        )
        let input = options.priorInput
            ? texture(.effectOutput, effect: previousKey)
            : texture(.layerSource)
        let output = texture(.effectOutput, effect: key)
        let node = Graph.Node(
            nodeIndex: options.priorInput ? 2 : 0,
            effect: key,
            definitionPassIndex: 0,
            materialOrdinal: 0,
            instancePassIndex: 0,
            kind: options.nodeKind,
            materialPath: options.materialPath,
            materialPassID: "\(options.materialPath)#0",
            target: output,
            bindings: options.binding ? [
                .init(slot: 0, authoredName: "previous", texture: input, conditions: nil)
            ] : [],
            commandSource: options.command ? input : nil,
            commandTarget: nil,
            compose: nil,
            conditions: options.condition ? .bool(true) : nil
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: options.definitionPath,
            input: input,
            output: options.outputMismatch ? input : output,
            nodeIndices: [node.nodeIndex]
        )
        let target = Graph.RenderTarget(
            texture: texture(.framebuffer, effect: key, name: "extra"),
            extent: .init(kind: .input, first: nil, second: nil),
            format: "rgba_backbuffer",
            declaredUnique: false,
            clear: nil,
            uvs: nil,
            conditions: nil
        )
        let blocker: [Graph.Blocker] = options.blocker ? [
            .init(
                effect: key,
                definitionPassIndex: 0,
                reason: .unsupportedCondition,
                detail: "bad"
            )
        ] : []
        return .init(
            layerID: 20,
            effects: options.extraEffect ? [effect, effect] : [effect],
            renderTargets: options.extraTarget ? [target] : [],
            nodes: options.extraNode ? [node, node] : [node],
            finalOutput: options.outputMismatch ? input : effect.output,
            blockers: blocker
        )
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        _ mode: String
    ) -> [SceneShaderContract] {
        guard mode != "none", let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if mode == "source" || mode == "raw" {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw" ? String(repeating: "0", count: 64) : stage.rawSHA256,
                includes: stage.includes,
                annotations: stage.annotations,
                declarations: stage.declarations
            )
        }
        if mode == "metadata" {
            let stage = stages[1]
            stages[1] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: stage.source,
                rawSHA256: stage.rawSHA256,
                includes: stage.includes,
                annotations: [],
                declarations: stage.declarations
            )
        }
        let changed = SceneShaderContract(
            identity: contract.identity,
            sourceKind: mode == "builtin" ? .hostBuiltin : contract.sourceKind,
            stages: stages,
            diagnostics: contract.diagnostics,
            canonicalSHA256: mode == "canonical"
                ? String(repeating: "0", count: 64)
                : contract.canonicalSHA256
        )
        return mode == "duplicate" ? [contract, contract] : [changed]
    }

    static func planned(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> ScenePulseExecutionPlan? {
        SceneAuthoredPulsePlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(descriptorOptions, priorInput: graphOptions.priorInput),
            shaderContracts: contracts,
            inputRole: role
        )
    }

    static func accepted(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        planned(
            graphOptions: graphOptions,
            descriptorOptions: descriptorOptions,
            contracts: contracts,
            role: role
        ) != nil
    }

    static func scalar(
        _ plan: ScenePulseExecutionPlan,
        _ constant: Constant
    ) -> Double {
        plan.staticOrFallbackValues[constant]!.x
    }

    static func main() throws {
        let stockRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let legacyRoots = CommandLine.arguments[2...].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let loader = SceneShaderContractLoader()
        let stockContracts = loader.load(
            shaderReferences: [shaderIdentity], rootURL: stockRoot
        )
        let legacyContracts = legacyRoots.map {
            loader.load(shaderReferences: [shaderIdentity], rootURL: $0)
        }

        let stockProfile = ScenePulseShaderProfile.resolve(stockContracts)
        let saturateProfile = ScenePulseShaderProfile.resolve(legacyContracts[0])
        let cast3Profile = ScenePulseShaderProfile.resolve(legacyContracts[1])
        let literalProfile = ScenePulseShaderProfile.resolve(legacyContracts[2])

        let staticPlan = planned(
            descriptorOptions: {
                var options = Options()
                options.constants = fullConstants()
                options.instanceCombos = [
                    "AUDIOPROCESSING": 0, "BLENDMODE": 9, "PULSEALPHA": 0, "PULSECOLOR": 1,
                ]
                options.instanceSlots = [nil, "util/noise", "masks/pulse_mask_a"]
                options.instancePaths = ["util/noise", "masks/pulse_mask_a"]
                return options
            }(),
            contracts: stockContracts
        )
        let defaultsPlan = planned(contracts: stockContracts)
        let legacyDefaultsPlan = planned(contracts: legacyContracts[0])
        var missingReplacement = Options()
        missingReplacement.definitionMutation = "missingReplacement"

        var boundOptions = Options()
        boundOptions.constants = [
            "tinthigh": value([1, 0, 1], kind: "binding", binding: "neoncolor"),
            "noiseamount": value([0.5], kind: "binding", binding: "noiselevel"),
        ]
        let boundPlan = planned(descriptorOptions: boundOptions, contracts: stockContracts)!
        let tintTarget = boundPlan.bindings[.tintHigh]!.dynamicTarget
        let noiseTarget = boundPlan.bindings[.noiseAmount]!.dynamicTarget
        let definitions = [
            SceneDynamicTargetDefinition(
                target: tintTarget,
                valueType: .vector3,
                authoredValue: .vector3(1, 0, 1)
            ),
            SceneDynamicTargetDefinition(
                target: noiseTarget,
                valueType: .scalar,
                authoredValue: .scalar(0.5)
            ),
        ]
        let liveSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: definitions,
            userValues: [tintTarget: .vector3(0.2, 0.4, 0.6), noiseTarget: .scalar(1.5)]
        ).snapshot
        let invalidSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: definitions,
            userValues: [tintTarget: .vector3(2, 0, 0), noiseTarget: .scalar(9)]
        ).snapshot

        var audio = Options(); audio.instanceCombos = ["AUDIOPROCESSING": 3]
        var audioFull = Options()
        audioFull.instanceCombos = ["AUDIOPROCESSING": 3]
        audioFull.constants = [
            "frequencymin": value([1], kind: "number"),
            "frequencymax": value([5], kind: "number"),
            "audioexponent": value([0.5], kind: "number"),
            "audiobounds": value([0.25, 0.75], kind: "vector"),
            "audioamount": value([2], kind: "number"),
        ]
        var audioOutOfRange = Options()
        audioOutOfRange.instanceCombos = ["AUDIOPROCESSING": 4]
        var audioBoundConstant = Options()
        audioBoundConstant.instanceCombos = ["AUDIOPROCESSING": 3]
        audioBoundConstant.constants = [
            "audioamount": value([1], kind: "binding", binding: "newproperty9")
        ]
        let audioPlan = planned(descriptorOptions: audio, contracts: stockContracts)
        let audioFullPlan = planned(descriptorOptions: audioFull, contracts: stockContracts)
        let nonAudioPlan = planned(contracts: stockContracts)
        var unknownKey = Options()
        unknownKey.constants = [
            "ui_editor_properties_pulse_speed": value([2], kind: "number")
        ]
        var audioConstant = Options()
        audioConstant.constants = ["audioamount": value([1], kind: "number")]
        var script = Options()
        script.constants = ["amount": value([0.8], kind: "binding", binding: nil)]
        var wrongKind = Options()
        wrongKind.constants = ["amount": value([0.8], kind: "vector")]
        var emptyBinding = Options()
        emptyBinding.constants = ["amount": value([0.8], kind: "binding", binding: "  ")]
        var equalBounds = Options()
        equalBounds.constants = ["bounds": value([0.5, 0.5], kind: "vector")]
        var invertedBounds = Options()
        invertedBounds.constants = ["bounds": value([0.7, 0.3], kind: "vector")]
        var speedHigh = Options(); speedHigh.constants = ["speed": value([11], kind: "number")]
        var powerHigh = Options(); powerHigh.constants = ["power": value([4.5], kind: "number")]
        var tintHigh = Options()
        tintHigh.constants = ["tinthigh": value([1.5, 0, 0], kind: "vector")]
        var noiseSpeedFast = Options()
        noiseSpeedFast.constants = ["noisespeed": value([0.6], kind: "number")]
        var shortBounds = Options()
        shortBounds.constants = ["bounds": value([0.5], kind: "vector")]

        var noiseOnly = Options()
        noiseOnly.instanceSlots = [nil, "util/noise"]
        noiseOnly.instancePaths = ["util/noise"]
        var maskOnly = Options()
        maskOnly.instanceSlots = [nil, nil, "masks/pulse_mask_a"]
        maskOnly.instancePaths = ["masks/pulse_mask_a"]
        var slotZero = Options()
        slotZero.instanceSlots = ["asset.png", "util/noise"]
        slotZero.instancePaths = ["asset.png", "util/noise"]
        var noiseOverride = Options()
        noiseOverride.instanceSlots = [nil, "textures/custom_noise"]
        noiseOverride.instancePaths = ["textures/custom_noise"]
        var blankMask = Options()
        blankMask.instanceSlots = [nil, nil, "  "]
        blankMask.instancePaths = ["  "]
        var extraSlot = Options()
        extraSlot.instanceSlots = [nil, "util/noise", "masks/pulse_mask_a", "extra.png"]
        extraSlot.instancePaths = ["util/noise", "masks/pulse_mask_a", "extra.png"]
        var pathsMismatch = Options()
        pathsMismatch.instanceSlots = [nil, "util/noise"]
        pathsMismatch.instancePaths = []
        var userTexture = Options()
        userTexture.instanceSlots = [nil, "util/noise"]
        userTexture.instancePaths = ["util/noise"]
        userTexture.instanceUserTexture = true

        var blendMax = Options()
        blendMax.instanceCombos = ["BLENDMODE": 32]
        var blendHigh = Options()
        blendHigh.instanceCombos = ["BLENDMODE": 33]
        var blendNegative = Options()
        blendNegative.instanceCombos = ["BLENDMODE": -1]
        var pulseAlphaOn = Options()
        pulseAlphaOn.instanceCombos = ["PULSEALPHA": 1, "PULSECOLOR": 0]
        var maskCombo = Options()
        maskCombo.instanceCombos = ["MASK": 1]
        var duplicateCombo = Options()
        duplicateCombo.instanceCombos = ["BLENDMODE": 9, "blendmode": 9]

        var hidden = Options(); hidden.visible = false
        var content = Options(); content.contentKind = "particle"
        var state = Options(); state.blending = "additive"
        var depth = Options(); depth.depthTest = "enabled"
        var materialPathOption = Options()
        materialPathOption.materialPath = "materials/other.json"
        var materialHash = Options()
        materialHash.materialRawSHA256 = String(repeating: "0", count: 64)
        var materialPass = Options(); materialPass.materialPassIndex = 1
        var shader = Options(); shader.shaderIdentity = "effects/other"
        var materialCombo = Options(); materialCombo.materialCombos = ["AUDIOPROCESSING": 3]
        var materialTexture = Options(); materialTexture.materialTexture = true
        var materialConstant = Options(); materialConstant.materialConstant = true
        var duplicateMaterial = Options(); duplicateMaterial.duplicateMaterial = true

        var prior = GraphOptions(); prior.priorInput = true
        var blocker = GraphOptions(); blocker.blocker = true
        var targetGraph = GraphOptions(); targetGraph.extraTarget = true
        var binding = GraphOptions(); binding.binding = true
        var command = GraphOptions(); command.command = true
        var condition = GraphOptions(); condition.condition = true
        var copy = GraphOptions(); copy.nodeKind = .copy
        var output = GraphOptions(); output.outputMismatch = true
        var effectCount = GraphOptions(); effectCount.extraEffect = true
        var nodeCount = GraphOptions(); nodeCount.extraNode = true
        var workshop = GraphOptions()
        workshop.definitionPath = "effects/workshop/123/pulse/effect.json"
        var graphMaterial = GraphOptions(); graphMaterial.materialPath = "materials/other.json"

        let definitionMutations = [
            "missing", "version", "replacement", "name", "description", "group",
            "performance", "preview", "editable", "passMaterial", "passTarget",
            "passBinding", "compose", "passExtra", "framebuffer", "dependencies",
            "functions", "gizmos", "extra",
        ]
        let definitionRejected = definitionMutations.allSatisfy { mutation in
            var options = Options(); options.definitionMutation = mutation
            return !accepted(descriptorOptions: options, contracts: stockContracts)
        }
        let contractRejected = ["source", "raw", "metadata", "builtin", "canonical", "duplicate"]
            .allSatisfy { !accepted(contracts: mutate(stockContracts, $0)) }

        let result: [String: Any] = [
            "stockProfileResolved": stockProfile == .stock2842
                && stockProfile!.phaseOffset == -1.57079632679
                && stockProfile!.noiseUVScale == SIMD2<Float>(0.08333333, 0.02777777)
                && stockProfile!.noiseSpeedDefault == 0.5
                && stockProfile!.noiseSpeedRange == 0 ... 1
                && stockProfile!.saturatesOutput == false,
            "legacySaturateResolved": saturateProfile == .directPhaseSaturateV1
                && saturateProfile!.phaseOffset == 0
                && saturateProfile!.noiseUVScale == SIMD2<Float>(1, 0.333)
                && saturateProfile!.noiseSpeedDefault == 0.1
                && saturateProfile!.noiseSpeedRange == 0 ... 0.5
                && saturateProfile!.saturatesOutput == true,
            "legacyMaxClampResolved": cast3Profile == .directPhaseMaxClampV1
                && literalProfile == .directPhaseMaxClampV1
                && cast3Profile!.saturatesOutput == false,
            "staticAccepted": staticPlan != nil
                && staticPlan!.shaderProfile == .stock2842
                && staticPlan!.blendMode == 9
                && staticPlan!.pulseColor == true
                && staticPlan!.pulseAlpha == false
                && scalar(staticPlan!, .speed) == 2
                && scalar(staticPlan!, .phase) == 1.5
                && scalar(staticPlan!, .amount) == 0.8
                && staticPlan!.staticOrFallbackValues[.bounds]!.x == 0.1
                && staticPlan!.staticOrFallbackValues[.bounds]!.y == 0.9
                && scalar(staticPlan!, .noiseSpeed) == 0.25
                && scalar(staticPlan!, .noiseAmount) == 0.5
                && scalar(staticPlan!, .power) == 2
                && staticPlan!.staticOrFallbackValues[.tintHigh]!
                    == SIMD3<Double>(0.9, 0.8, 0.7)
                && staticPlan!.maskTexturePath == "masks/pulse_mask_a"
                && staticPlan!.noiseTexturePath == "util/noise"
                && staticPlan!.requiresNoiseTexture == true
                && staticPlan!.bindings.isEmpty
                && staticPlan!.liveConsumerTargets.isEmpty,
            "defaultsApplied": defaultsPlan != nil
                && defaultsPlan!.blendMode == 9
                && defaultsPlan!.pulseColor == true
                && defaultsPlan!.pulseAlpha == false
                && scalar(defaultsPlan!, .speed) == 3
                && scalar(defaultsPlan!, .amount) == 1
                && scalar(defaultsPlan!, .noiseSpeed) == 0.5
                && scalar(defaultsPlan!, .noiseAmount) == 0
                && scalar(defaultsPlan!, .power) == 1
                && defaultsPlan!.staticOrFallbackValues[.tintLow]!
                    == SIMD3<Double>(1, 1, 1)
                && defaultsPlan!.maskTexturePath == nil
                && defaultsPlan!.noiseTexturePath == nil
                && defaultsPlan!.requiresNoiseTexture == false,
            "legacyNoiseSpeedDefault": legacyDefaultsPlan != nil
                && legacyDefaultsPlan!.shaderProfile == .directPhaseSaturateV1
                && scalar(legacyDefaultsPlan!, .noiseSpeed) == 0.1,
            "legacyMissingReplacementAccepted": accepted(
                descriptorOptions: missingReplacement,
                contracts: legacyContracts[0]
            ),
            "stockMissingReplacementRejected": !accepted(
                descriptorOptions: missingReplacement,
                contracts: stockContracts
            ),
            "legacyNoiseSpeedRange": !accepted(
                descriptorOptions: noiseSpeedFast, contracts: legacyContracts[0]
            ) && accepted(descriptorOptions: noiseSpeedFast, contracts: stockContracts),
            "audioDisabledPlanHasNoParameters": nonAudioPlan.map { $0.audio == nil } ?? false,
            "audioStockDefaultsBackfilled": audioPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .average,
                    frequencyMin: 0,
                    frequencyMax: 1,
                    boundsLower: 0.5,
                    boundsUpper: 1,
                    exponent: 1,
                    multiply: 1
                )
            } ?? false,
            "audioStockFullAccepted": audioFullPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .average,
                    frequencyMin: 1,
                    frequencyMax: 5,
                    boundsLower: 0.25,
                    boundsUpper: 0.75,
                    exponent: 0.5,
                    multiply: 2
                )
            } ?? false,
            "audioRejected": [audioOutOfRange, audioBoundConstant]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: stockContracts) },
            "legacyAudioRejected": legacyContracts.allSatisfy {
                !accepted(descriptorOptions: audio, contracts: $0)
            },
            "audioZeroAccepted": accepted(
                descriptorOptions: {
                    var options = Options()
                    options.instanceCombos = ["AUDIOPROCESSING": 0]
                    return options
                }(),
                contracts: stockContracts
            ),
            "unknownConstantRejected": !accepted(
                descriptorOptions: unknownKey, contracts: stockContracts
            ) && !accepted(descriptorOptions: audioConstant, contracts: stockContracts),
            "sceneScriptRejected": !accepted(
                descriptorOptions: script, contracts: stockContracts
            ),
            "wrongBindingKindRejected": !accepted(
                descriptorOptions: wrongKind, contracts: stockContracts
            ),
            "emptyBindingRejected": !accepted(
                descriptorOptions: emptyBinding, contracts: stockContracts
            ),
            "boundsRejected": [equalBounds, invertedBounds, shortBounds].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "rangeRejected": [speedHigh, powerHigh, tintHigh].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "slotFormsAccepted": [noiseOnly, maskOnly].allSatisfy {
                accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "slotFormsRejected": [
                slotZero, noiseOverride, blankMask, extraSlot, pathsMismatch, userTexture,
            ].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "maskPathExtracted": planned(
                descriptorOptions: maskOnly, contracts: stockContracts
            )!.maskTexturePath == "masks/pulse_mask_a"
                && planned(
                    descriptorOptions: noiseOnly, contracts: stockContracts
                )!.maskTexturePath == nil,
            "bindingsAccepted": boundPlan.bindings[.tintHigh]!.propertyKey == "neoncolor"
                && boundPlan.bindings[.tintHigh]!.layerID == 20
                && boundPlan.bindings[.tintHigh]!.effectIndex == 0
                && boundPlan.bindings[.noiseAmount]!.propertyKey == "noiselevel"
                && boundPlan.staticOrFallbackValues[.tintHigh]! == SIMD3<Double>(1, 0, 1)
                && boundPlan.requiresNoiseTexture == true
                && boundPlan.liveConsumerTargets.count == 2,
            "snapshotApplied": boundPlan.resolvedComponents(.tintHigh, in: liveSnapshot)
                == SIMD3<Double>(0.2, 0.4, 0.6),
            "snapshotFallback": boundPlan.resolvedComponents(.tintHigh, in: invalidSnapshot)
                == SIMD3<Double>(1, 0, 1)
                && boundPlan.resolvedComponents(.noiseAmount, in: invalidSnapshot).x == 0.5,
            "blendModeResolved": planned(
                descriptorOptions: blendMax, contracts: stockContracts
            )!.blendMode == 32
                && planned(
                    descriptorOptions: pulseAlphaOn, contracts: stockContracts
                )!.pulseAlpha == true
                && planned(
                    descriptorOptions: pulseAlphaOn, contracts: stockContracts
                )!.pulseColor == false,
            "comboRejected": [blendHigh, blendNegative, maskCombo, duplicateCombo].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "materialRejected": [
                state, depth, materialPathOption, materialHash, materialPass,
                shader, materialCombo, materialTexture, materialConstant, duplicateMaterial,
            ].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "hiddenRejected": !accepted(descriptorOptions: hidden, contracts: stockContracts),
            "contentKindRejected": !accepted(
                descriptorOptions: content, contracts: stockContracts
            ),
            "candidateDetected": SceneAuthoredPulsePlanner.containsCandidate(graph: graph()),
            "priorInputAccepted": accepted(
                graphOptions: prior, contracts: stockContracts, role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: stockContracts),
            "workshopVariantRejected": !accepted(
                graphOptions: workshop, contracts: stockContracts
            ),
            "graphShapeRejected": [
                blocker, targetGraph, binding, command, condition, copy,
                output, effectCount, nodeCount, graphMaterial,
            ].allSatisfy {
                !accepted(graphOptions: $0, contracts: stockContracts)
            },
            "definitionRejected": definitionRejected,
            "contractRejected": contractRejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: result.mapValues { $0 as Any })
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class ScenePulsePlannerTests(unittest.TestCase):
    def test_planner(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stock_root = root / "stock"
            shader_dir = stock_root / "shaders/effects"
            shader_dir.mkdir(parents=True)
            shutil.copy(STOCK_SHADERS / "pulse.vert", shader_dir / "pulse.vert")
            shutil.copy(STOCK_SHADERS / "pulse.frag", shader_dir / "pulse.frag")
            legacy_roots = []
            for name, frag in (
                ("legacy-saturate", LEGACY_FRAG_SATURATE_BASE64),
                ("legacy-cast3", LEGACY_FRAG_CAST3_BASE64),
                ("legacy-literal", LEGACY_FRAG_LITERAL_BASE64),
            ):
                legacy_root = root / name
                legacy_dir = legacy_root / "shaders/effects"
                legacy_dir.mkdir(parents=True)
                (legacy_dir / "pulse.vert").write_bytes(
                    base64.b64decode(LEGACY_VERT_BASE64)
                )
                (legacy_dir / "pulse.frag").write_bytes(base64.b64decode(frag))
                legacy_roots.append(legacy_root)

            harness = root / "Harness.swift"
            executable = root / "pulse-harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(executable), str(stock_root), *(str(p) for p in legacy_roots)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                completed.returncode, 0,
                f"stdout={completed.stdout}\nstderr={completed.stderr}",
            )

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
