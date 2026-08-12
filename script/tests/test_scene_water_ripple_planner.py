#!/usr/bin/env python3
"""water ripple planner 的 fail-closed 准入与逐指纹 profile 测试。

与 pulse 的关键差异，各有专门断言：
- shader 源按 SceneWaterRippleShaderProfile 三指纹白名单准入：stock 2.8.42、
  `invertedScrollV1`（1937925563/2131872317，scroll 基向量 vec2(0,-1)，
  折算为 scrolldirection + π）、`maskComboV1`（2470144420，数学同 stock，
  仅缺 PERSPECTIVE 分支）；
- legacy 两族 effect.json 无 gizmos、实例常量只写非默认键（准入放宽为白名单
  键子集），1937925563 的 effect.json 变体无 replacementkey；
- stock 准入面保持不变：全 6 常量键、带 PERSPECTIVE gizmos 的 effect.json；
- mask 槽在所有 profile 下必须显式绑定（legacy 的无条件 mask 采样不放宽装载门）。
"""

from __future__ import annotations

import base64
import hashlib
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
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects/waterripple"
    / "shaders/effects"
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
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneWaterRippleShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredWaterRipplePlanner.swift",
]

# 语料历史版本 shader 源，字节从 scene.pkg 原样提取（legacy-inverted =
# 1937925563/2131872317，legacy-maskcombo = 2470144420），指纹已进
# SceneWaterRippleShaderProfile 白名单。
LEGACY_INVERTED_VERT_BASE64 = (
    "DQojaW5jbHVkZSAiY29tbW9uLmgiDQoNCnVuaWZvcm0gbWF0NCBnX01vZGVsVmlld1Byb2plY3Rp"
    "b25NYXRyaXg7DQp1bmlmb3JtIGZsb2F0IGdfVGltZTsNCnVuaWZvcm0gdmVjNCBnX1RleHR1cmUw"
    "UmVzb2x1dGlvbjsNCnVuaWZvcm0gdmVjNCBnX1RleHR1cmUxUmVzb2x1dGlvbjsNCg0KdW5pZm9y"
    "bSBmbG9hdCBnX0FuaW1hdGlvblNwZWVkOyAvLyB7Im1hdGVyaWFsIjoiYW5pbWF0aW9uc3BlZWQi"
    "LCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2FuaW1hdGlvbl9zcGVlZCIsImRlZmF1bHQi"
    "OjAuMTUsInJhbmdlIjpbMCwwLjVdfQ0KdW5pZm9ybSBmbG9hdCBnX1NjYWxlOyAvLyB7Im1hdGVy"
    "aWFsIjoic2NhbGUiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpcHBsZV9zY2FsZSIs"
    "ImRlZmF1bHQiOjEsInJhbmdlIjpbMCwxMF19DQp1bmlmb3JtIGZsb2F0IGdfU2Nyb2xsU3BlZWQ7"
    "IC8vIHsibWF0ZXJpYWwiOiJzY3JvbGxzcGVlZCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRp"
    "ZXNfc2Nyb2xsX3NwZWVkIiwiZGVmYXVsdCI6MCwicmFuZ2UiOlswLDAuNV19DQp1bmlmb3JtIGZs"
    "b2F0IGdfRGlyZWN0aW9uOyAvLyB7Im1hdGVyaWFsIjoic2Nyb2xsZGlyZWN0aW9uIiwibGFiZWwi"
    "OiJ1aV9lZGl0b3JfcHJvcGVydGllc19zY3JvbGxfZGlyZWN0aW9uIiwiZGVmYXVsdCI6MCwicmFu"
    "Z2UiOlswLDYuMjhdfQ0KdW5pZm9ybSBmbG9hdCBnX1JhdGlvOyAvLyB7Im1hdGVyaWFsIjoicmF0"
    "aW8iLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JhdGlvIiwiZGVmYXVsdCI6MSwicmFu"
    "Z2UiOlswLDEwXX0NCg0KYXR0cmlidXRlIHZlYzMgYV9Qb3NpdGlvbjsNCmF0dHJpYnV0ZSB2ZWMy"
    "IGFfVGV4Q29vcmQ7DQoNCnZhcnlpbmcgdmVjNCB2X1RleENvb3JkOw0KdmFyeWluZyB2ZWM0IHZf"
    "VGV4Q29vcmRSaXBwbGU7DQoNCnZvaWQgbWFpbigpIHsNCglnbF9Qb3NpdGlvbiA9IG11bCh2ZWM0"
    "KGFfUG9zaXRpb24sIDEuMCksIGdfTW9kZWxWaWV3UHJvamVjdGlvbk1hdHJpeCk7DQoJdl9UZXhD"
    "b29yZC54eSA9IGFfVGV4Q29vcmQ7DQoJDQoJZmxvYXQgcGlGcmFjID0gMC43ODUzOTgxNjMzOTc0"
    "NDgzMDk2MTU2NjA4NDU4MTk4OCAqIDAuNTsNCglmbG9hdCBwaSA9IDMuMTQxOw0KCQ0KCXZlYzIg"
    "Y29vcmRzUm90YXRlZCA9IHZfVGV4Q29vcmQueHk7DQoJdmVjMiBjb29yZHNSb3RhdGVkMiA9IHZf"
    "VGV4Q29vcmQueHkgKiAxLjMzMzsNCgkNCgl2ZWMyIHNjcm9sbCA9IHJvdGF0ZVZlYzIodmVjMigw"
    "LCAtMSksIGdfRGlyZWN0aW9uKSAqIGdfU2Nyb2xsU3BlZWQgKiBnX1Njcm9sbFNwZWVkICogZ19U"
    "aW1lOw0KCQ0KCXZfVGV4Q29vcmRSaXBwbGUueHkgPSBjb29yZHNSb3RhdGVkICsgZ19UaW1lICog"
    "Z19BbmltYXRpb25TcGVlZCAqIGdfQW5pbWF0aW9uU3BlZWQgKyBzY3JvbGw7DQoJdl9UZXhDb29y"
    "ZFJpcHBsZS56dyA9IGNvb3Jkc1JvdGF0ZWQyIC0gZ19UaW1lICogZ19BbmltYXRpb25TcGVlZCAq"
    "IGdfQW5pbWF0aW9uU3BlZWQgKyBzY3JvbGw7DQoJdl9UZXhDb29yZFJpcHBsZSAqPSBnX1NjYWxl"
    "Ow0KDQoJZmxvYXQgcmlwcGxlVGV4dHVyZUFkanVzdG1lbnQgPSAoZ19UZXh0dXJlMFJlc29sdXRp"
    "b24ueCAvIGdfVGV4dHVyZTBSZXNvbHV0aW9uLnkpOw0KCXZfVGV4Q29vcmRSaXBwbGUueHogKj0g"
    "cmlwcGxlVGV4dHVyZUFkanVzdG1lbnQ7DQoJdl9UZXhDb29yZFJpcHBsZS55dyAqPSBnX1JhdGlv"
    "Ow0KCQ0KCXZfVGV4Q29vcmQuencgPSB2ZWMyKHZfVGV4Q29vcmQueCAqIGdfVGV4dHVyZTFSZXNv"
    "bHV0aW9uLnogLyBnX1RleHR1cmUxUmVzb2x1dGlvbi54LA0KCQkJCQkJdl9UZXhDb29yZC55ICog"
    "Z19UZXh0dXJlMVJlc29sdXRpb24udyAvIGdfVGV4dHVyZTFSZXNvbHV0aW9uLnkpOw0KfQ0K"
)
LEGACY_INVERTED_FRAG_BASE64 = (
    "DQovLyBbQ09NQk9fT0ZGXSB7Im1hdGVyaWFsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc3BlY3Vs"
    "YXIiLCJjb21ibyI6IlNQRUNVTEFSIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjowfQ0KDQp2"
    "YXJ5aW5nIHZlYzQgdl9UZXhDb29yZDsNCnZhcnlpbmcgdmVjMiB2X1Njcm9sbDsNCg0KdW5pZm9y"
    "bSBzYW1wbGVyMkQgZ19UZXh0dXJlMDsgLy8geyJtYXRlcmlhbCI6ImZyYW1lYnVmZmVyIiwibGFi"
    "ZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19mcmFtZWJ1ZmZlciIsImhpZGRlbiI6dHJ1ZX0NCnVu"
    "aWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTE7IC8vIHsibWF0ZXJpYWwiOiJtYXNrIiwibGFiZWwi"
    "OiJ1aV9lZGl0b3JfcHJvcGVydGllc19vcGFjaXR5X21hc2siLCJtb2RlIjoib3BhY2l0eW1hc2si"
    "LCJkZWZhdWx0IjoidXRpbC93aGl0ZSIsInBhaW50ZGVmYXVsdGNvbG9yIjoiMCAwIDAgMSJ9DQp1"
    "bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUyOyAvLyB7Im1hdGVyaWFsIjoibm9ybWFsIiwibGFi"
    "ZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc193YXRlcl9ub3JtYWwifQ0KDQp1bmlmb3JtIGZsb2F0"
    "IGdfU3RyZW5ndGg7IC8vIHsibWF0ZXJpYWwiOiJyaXBwbGVzdHJlbmd0aCIsImxhYmVsIjoidWlf"
    "ZWRpdG9yX3Byb3BlcnRpZXNfcmlwcGxlX3N0cmVuZ3RoIiwiZGVmYXVsdCI6MC4xLCJyYW5nZSI6"
    "WzAsMV19DQp1bmlmb3JtIGZsb2F0IGdfU3BlY3VsYXJQb3dlcjsgLy8geyJtYXRlcmlhbCI6InJp"
    "cHBsZXNwZWN1bGFycG93ZXIiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpcHBsZV9z"
    "cGVjdWxhcl9wb3dlciIsImRlZmF1bHQiOjEuMCwicmFuZ2UiOlswLDEwMF19DQp1bmlmb3JtIGZs"
    "b2F0IGdfU3BlY3VsYXJTdHJlbmd0aDsgLy8geyJtYXRlcmlhbCI6InJpcHBsZXNwZWN1bGFyc3Ry"
    "ZW5ndGgiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpcHBsZV9zcGVjdWxhcl9zdHJl"
    "bmd0aCIsImRlZmF1bHQiOjEuMCwicmFuZ2UiOlswLDEwXX0NCnVuaWZvcm0gdmVjMyBnX1NwZWN1"
    "bGFyQ29sb3I7IC8vIHsibWF0ZXJpYWwiOiJyaXBwbGVzcGVjdWxhcmNvbG9yIiwibGFiZWwiOiJ1"
    "aV9lZGl0b3JfcHJvcGVydGllc19yaXBwbGVfc3BlY3VsYXJfY29sb3IiLCJkZWZhdWx0IjoiMSAx"
    "IDEiLCJ0eXBlIjoiY29sb3IifQ0KDQp2YXJ5aW5nIHZlYzQgdl9UZXhDb29yZFJpcHBsZTsNCg0K"
    "dm9pZCBtYWluKCkgew0KCXZlYzIgdGV4Q29vcmQgPSB2X1RleENvb3JkLnh5Ow0KCQ0KCWZsb2F0"
    "IG1hc2sgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUxLCB2X1RleENvb3JkLnp3KS5yOw0KCQ0KCXZl"
    "YzMgbjEgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUyLCB2X1RleENvb3JkUmlwcGxlLnh5KS54eXog"
    "KiAyIC0gMTsNCgl2ZWMzIG4yID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhDb29yZFJp"
    "cHBsZS56dykueHl6ICogMiAtIDE7DQoJdmVjMyBub3JtYWwgPSBub3JtYWxpemUodmVjMyhuMS54"
    "eSArIG4yLnh5LCBuMS56KSk7DQoJDQoJdGV4Q29vcmQueHkgKz0gbm9ybWFsLnh5ICogZ19TdHJl"
    "bmd0aCAqIGdfU3RyZW5ndGggKiBtYXNrOw0KCQ0KCWdsX0ZyYWdDb2xvciA9IHRleFNhbXBsZTJE"
    "KGdfVGV4dHVyZTAsIHRleENvb3JkKTsNCgkNCiNpZiBTUEVDVUxBUiA9PSAxDQoJdmVjMiBkaXJl"
    "Y3Rpb24gPSB2ZWMyKDAuNSwgMC4wKSAtIHZfVGV4Q29vcmQueHk7DQoJZGlyZWN0aW9uID0gbm9y"
    "bWFsaXplKGRpcmVjdGlvbik7DQoJZmxvYXQgc3BlY3VsYXIgPSBtYXgoMC4wLCBkb3Qobm9ybWFs"
    "Lnh5LCBkaXJlY3Rpb24pKSAqIG1heCgwLjAsIGRvdChkaXJlY3Rpb24sIHZlYzIoMC4wLCAtMS4w"
    "KSkpOw0KCQ0KCXNwZWN1bGFyID0gcG93KHNwZWN1bGFyLCBnX1NwZWN1bGFyUG93ZXIpICogZ19T"
    "cGVjdWxhclN0cmVuZ3RoOw0KCWdsX0ZyYWdDb2xvci5yZ2IgKz0gc3BlY3VsYXIgKiBnX1NwZWN1"
    "bGFyQ29sb3IgKiBnbF9GcmFnQ29sb3IuYTsNCiNlbmRpZg0KfQ0K"
)
LEGACY_MASKCOMBO_VERT_BASE64 = (
    "DQojaW5jbHVkZSAiY29tbW9uLmgiDQoNCnVuaWZvcm0gbWF0NCBnX01vZGVsVmlld1Byb2plY3Rp"
    "b25NYXRyaXg7DQp1bmlmb3JtIGZsb2F0IGdfVGltZTsNCnVuaWZvcm0gdmVjNCBnX1RleHR1cmUw"
    "UmVzb2x1dGlvbjsNCnVuaWZvcm0gdmVjNCBnX1RleHR1cmUxUmVzb2x1dGlvbjsNCg0KdW5pZm9y"
    "bSBmbG9hdCBnX0FuaW1hdGlvblNwZWVkOyAvLyB7Im1hdGVyaWFsIjoiYW5pbWF0aW9uc3BlZWQi"
    "LCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2FuaW1hdGlvbl9zcGVlZCIsImRlZmF1bHQi"
    "OjAuMTUsInJhbmdlIjpbMCwwLjVdfQ0KdW5pZm9ybSBmbG9hdCBnX1NjYWxlOyAvLyB7Im1hdGVy"
    "aWFsIjoic2NhbGUiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpcHBsZV9zY2FsZSIs"
    "ImRlZmF1bHQiOjEsInJhbmdlIjpbMCwxMF19DQp1bmlmb3JtIGZsb2F0IGdfU2Nyb2xsU3BlZWQ7"
    "IC8vIHsibWF0ZXJpYWwiOiJzY3JvbGxzcGVlZCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRp"
    "ZXNfc2Nyb2xsX3NwZWVkIiwiZGVmYXVsdCI6MCwicmFuZ2UiOlswLDAuNV19DQp1bmlmb3JtIGZs"
    "b2F0IGdfRGlyZWN0aW9uOyAvLyB7Im1hdGVyaWFsIjoic2Nyb2xsZGlyZWN0aW9uIiwibGFiZWwi"
    "OiJ1aV9lZGl0b3JfcHJvcGVydGllc19zY3JvbGxfZGlyZWN0aW9uIiwiZGVmYXVsdCI6MCwicmFu"
    "Z2UiOlswLDYuMjhdLCJkaXJlY3Rpb24iOnRydWV9DQp1bmlmb3JtIGZsb2F0IGdfUmF0aW87IC8v"
    "IHsibWF0ZXJpYWwiOiJyYXRpbyIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcmF0aW8i"
    "LCJkZWZhdWx0IjoxLCJyYW5nZSI6WzAsMTBdfQ0KDQphdHRyaWJ1dGUgdmVjMyBhX1Bvc2l0aW9u"
    "Ow0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29yZDsNCg0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmQ7"
    "DQp2YXJ5aW5nIHZlYzQgdl9UZXhDb29yZFJpcHBsZTsNCg0Kdm9pZCBtYWluKCkgew0KCWdsX1Bv"
    "c2l0aW9uID0gbXVsKHZlYzQoYV9Qb3NpdGlvbiwgMS4wKSwgZ19Nb2RlbFZpZXdQcm9qZWN0aW9u"
    "TWF0cml4KTsNCgl2X1RleENvb3JkLnh5ID0gYV9UZXhDb29yZDsNCgkNCglmbG9hdCBwaUZyYWMg"
    "PSAwLjc4NTM5ODE2MzM5NzQ0ODMwOTYxNTY2MDg0NTgxOTg4ICogMC41Ow0KCWZsb2F0IHBpID0g"
    "My4xNDE7DQoJDQoJdmVjMiBjb29yZHNSb3RhdGVkID0gdl9UZXhDb29yZC54eTsNCgl2ZWMyIGNv"
    "b3Jkc1JvdGF0ZWQyID0gdl9UZXhDb29yZC54eSAqIDEuMzMzOw0KCQ0KCXZlYzIgc2Nyb2xsID0g"
    "cm90YXRlVmVjMih2ZWMyKDAsIDEpLCBnX0RpcmVjdGlvbikgKiBnX1Njcm9sbFNwZWVkICogZ19T"
    "Y3JvbGxTcGVlZCAqIGdfVGltZTsNCgkNCgl2X1RleENvb3JkUmlwcGxlLnh5ID0gY29vcmRzUm90"
    "YXRlZCArIGdfVGltZSAqIGdfQW5pbWF0aW9uU3BlZWQgKiBnX0FuaW1hdGlvblNwZWVkICsgc2Ny"
    "b2xsOw0KCXZfVGV4Q29vcmRSaXBwbGUuencgPSBjb29yZHNSb3RhdGVkMiAtIGdfVGltZSAqIGdf"
    "QW5pbWF0aW9uU3BlZWQgKiBnX0FuaW1hdGlvblNwZWVkICsgc2Nyb2xsOw0KCXZfVGV4Q29vcmRS"
    "aXBwbGUgKj0gZ19TY2FsZTsNCg0KCWZsb2F0IHJpcHBsZVRleHR1cmVBZGp1c3RtZW50ID0gKGdf"
    "VGV4dHVyZTBSZXNvbHV0aW9uLnggLyBnX1RleHR1cmUwUmVzb2x1dGlvbi55KTsNCgl2X1RleENv"
    "b3JkUmlwcGxlLnh6ICo9IHJpcHBsZVRleHR1cmVBZGp1c3RtZW50Ow0KCXZfVGV4Q29vcmRSaXBw"
    "bGUueXcgKj0gZ19SYXRpbzsNCgkNCgl2X1RleENvb3JkLnp3ID0gdmVjMih2X1RleENvb3JkLngg"
    "KiBnX1RleHR1cmUxUmVzb2x1dGlvbi56IC8gZ19UZXh0dXJlMVJlc29sdXRpb24ueCwNCgkJCQkJ"
    "CXZfVGV4Q29vcmQueSAqIGdfVGV4dHVyZTFSZXNvbHV0aW9uLncgLyBnX1RleHR1cmUxUmVzb2x1"
    "dGlvbi55KTsNCn0NCg=="
)
LEGACY_MASKCOMBO_FRAG_BASE64 = (
    "DQovLyBbQ09NQk9fT0ZGXSB7Im1hdGVyaWFsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc3BlY3Vs"
    "YXIiLCJjb21ibyI6IlNQRUNVTEFSIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjowfQ0KDQp2"
    "YXJ5aW5nIHZlYzQgdl9UZXhDb29yZDsNCnZhcnlpbmcgdmVjMiB2X1Njcm9sbDsNCg0KdW5pZm9y"
    "bSBzYW1wbGVyMkQgZ19UZXh0dXJlMDsgLy8geyJtYXRlcmlhbCI6ImZyYW1lYnVmZmVyIiwibGFi"
    "ZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19mcmFtZWJ1ZmZlciIsImhpZGRlbiI6dHJ1ZX0NCnVu"
    "aWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTE7IC8vIHsibWF0ZXJpYWwiOiJtYXNrIiwibGFiZWwi"
    "OiJ1aV9lZGl0b3JfcHJvcGVydGllc19vcGFjaXR5X21hc2siLCJtb2RlIjoib3BhY2l0eW1hc2si"
    "LCJkZWZhdWx0IjoidXRpbC93aGl0ZSIsImNvbWJvIjoiTUFTSyIsInBhaW50ZGVmYXVsdGNvbG9y"
    "IjoiMCAwIDAgMSJ9DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUyOyAvLyB7Im1hdGVyaWFs"
    "Ijoibm9ybWFsIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc193YXRlcl9ub3JtYWwifQ0K"
    "DQp1bmlmb3JtIGZsb2F0IGdfU3RyZW5ndGg7IC8vIHsibWF0ZXJpYWwiOiJyaXBwbGVzdHJlbmd0"
    "aCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfcmlwcGxlX3N0cmVuZ3RoIiwiZGVmYXVs"
    "dCI6MC4xLCJyYW5nZSI6WzAsMV19DQp1bmlmb3JtIGZsb2F0IGdfU3BlY3VsYXJQb3dlcjsgLy8g"
    "eyJtYXRlcmlhbCI6InJpcHBsZXNwZWN1bGFycG93ZXIiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9w"
    "ZXJ0aWVzX3JpcHBsZV9zcGVjdWxhcl9wb3dlciIsImRlZmF1bHQiOjEuMCwicmFuZ2UiOlswLDEw"
    "MF19DQp1bmlmb3JtIGZsb2F0IGdfU3BlY3VsYXJTdHJlbmd0aDsgLy8geyJtYXRlcmlhbCI6InJp"
    "cHBsZXNwZWN1bGFyc3RyZW5ndGgiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpcHBs"
    "ZV9zcGVjdWxhcl9zdHJlbmd0aCIsImRlZmF1bHQiOjEuMCwicmFuZ2UiOlswLDEwXX0NCnVuaWZv"
    "cm0gdmVjMyBnX1NwZWN1bGFyQ29sb3I7IC8vIHsibWF0ZXJpYWwiOiJyaXBwbGVzcGVjdWxhcmNv"
    "bG9yIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19yaXBwbGVfc3BlY3VsYXJfY29sb3Ii"
    "LCJkZWZhdWx0IjoiMSAxIDEiLCJ0eXBlIjoiY29sb3IifQ0KDQp2YXJ5aW5nIHZlYzQgdl9UZXhD"
    "b29yZFJpcHBsZTsNCg0Kdm9pZCBtYWluKCkgew0KCXZlYzIgdGV4Q29vcmQgPSB2X1RleENvb3Jk"
    "Lnh5Ow0KCQ0KI2lmIE1BU0sgPT0gMQ0KCWZsb2F0IG1hc2sgPSB0ZXhTYW1wbGUyRChnX1RleHR1"
    "cmUxLCB2X1RleENvb3JkLnp3KS5yOw0KI2Vsc2UNCglmbG9hdCBtYXNrID0gMTsNCiNlbmRpZg0K"
    "CQ0KCXZlYzMgbjEgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUyLCB2X1RleENvb3JkUmlwcGxlLnh5"
    "KS54eXogKiAyIC0gMTsNCgl2ZWMzIG4yID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhD"
    "b29yZFJpcHBsZS56dykueHl6ICogMiAtIDE7DQoJdmVjMyBub3JtYWwgPSBub3JtYWxpemUodmVj"
    "MyhuMS54eSArIG4yLnh5LCBuMS56KSk7DQoJDQoJdGV4Q29vcmQueHkgKz0gbm9ybWFsLnh5ICog"
    "Z19TdHJlbmd0aCAqIGdfU3RyZW5ndGggKiBtYXNrOw0KCQ0KCWdsX0ZyYWdDb2xvciA9IHRleFNh"
    "bXBsZTJEKGdfVGV4dHVyZTAsIHRleENvb3JkKTsNCgkNCiNpZiBTUEVDVUxBUiA9PSAxDQoJdmVj"
    "MiBkaXJlY3Rpb24gPSB2ZWMyKDAuNSwgMC4wKSAtIHZfVGV4Q29vcmQueHk7DQoJZGlyZWN0aW9u"
    "ID0gbm9ybWFsaXplKGRpcmVjdGlvbik7DQoJZmxvYXQgc3BlY3VsYXIgPSBtYXgoMC4wLCBkb3Qo"
    "bm9ybWFsLnh5LCBkaXJlY3Rpb24pKSAqIG1heCgwLjAsIGRvdChkaXJlY3Rpb24sIHZlYzIoMC4w"
    "LCAtMS4wKSkpOw0KCQ0KCXNwZWN1bGFyID0gcG93KHNwZWN1bGFyLCBnX1NwZWN1bGFyUG93ZXIp"
    "ICogZ19TcGVjdWxhclN0cmVuZ3RoOw0KCWdsX0ZyYWdDb2xvci5yZ2IgKz0gc3BlY3VsYXIgKiBn"
    "X1NwZWN1bGFyQ29sb3IgKiBnbF9GcmFnQ29sb3IuYTsNCiNlbmRpZg0KfQ0K"
)

# 指纹自校验：内嵌字节必须与 SceneWaterRippleShaderProfile 白名单严格一致。
LEGACY_STAGE_SHA256 = {
    "legacy-inverted": (
        LEGACY_INVERTED_VERT_BASE64,
        LEGACY_INVERTED_FRAG_BASE64,
        "274a3349c945f230350a23fdb1baf6e973ba10306d13822338822fc0ca989cdf",
        "795cda51fe98cd21cea8d95594e003aff4746546a7d828d0b4b9bbef326cff6b",
    ),
    "legacy-maskcombo": (
        LEGACY_MASKCOMBO_VERT_BASE64,
        LEGACY_MASKCOMBO_FRAG_BASE64,
        "3745865023a909b697917183c2aca2ef1fb789854129f9676daaa1c41c8920c8",
        "84716ced71b6a46cb354ac6135f3d38514cebd991c81f372dab1000d46f21b07",
    ),
}


HARNESS = r'''
import Foundation

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
    static let definitionPath = "effects/waterripple/effect.json"
    static let materialPath = "materials/effects/waterripple.json"
    static let shaderIdentity = "effects/waterripple"
    static let normalTexturePath = "effects/waterripplenormal"
    static let maskTexturePath = "masks/waterripple_mask_a"

    struct Options {
        var contentKind = "image"
        var constants = Harness.fullConstants(direction: 0.5)
        var instanceCombos: [String: Int] = [:]
        var instanceSlots: [String?] = [
            nil, Harness.maskTexturePath, Harness.normalTexturePath,
        ]
        var instancePaths: [String] = [
            Harness.maskTexturePath, Harness.normalTexturePath,
        ]
        var instanceUserTexture = false
        var materialCombos: [String: Int] = [:]
        var materialSlots: [String?] = [nil, nil, Harness.normalTexturePath]
        var materialPaths: [String] = [Harness.normalTexturePath]
        var materialConstant = false
        var blending = "normal"
        var depthTest = "disabled"
        var materialPath = Harness.materialPath
        var materialRawSHA256 =
            "27b3a48c79990eaf1731b5d4871d0138ccc79a108b967b6e9a9e204d5d5e2360"
        var materialPassIndex = 0
        var shaderIdentity = Harness.shaderIdentity
        var visible: Bool? = true
        var definitionShape = "stock"
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

    static func value(_ components: [Double]) -> SceneDocument.ShaderValue {
        .init(
            rawValue: components.map { String($0) }.joined(separator: " "),
            valueKind: "number",
            userBinding: nil,
            components: components
        )
    }

    static func fullConstants(direction: Double) -> [String: SceneDocument.ShaderValue] {
        [
            "animationspeed": value([0.15]),
            "ratio": value([1]),
            "ripplestrength": value([0.1]),
            "scale": value([1]),
            "scrolldirection": value([direction]),
            "scrollspeed": value([0.2]),
        ]
    }

    /// 2131872317 实例 #52 的形态：legacy 编辑器只写非默认键。
    static func sparseConstants() -> [String: SceneDocument.ShaderValue] {
        [
            "animationspeed": value([0.07]),
            "ratio": value([2.51]),
            "ripplestrength": value([0.07]),
            "scale": value([2.15]),
        ]
    }

    static let stockGizmos = SceneJSONValue.array([
        .object([
            "condition": .object(["PERSPECTIVE": .number(1)]),
            "type": .string("EffectPerspectiveUV"),
            "vars": .object([
                "p0": .string("point0"),
                "p1": .string("point1"),
                "p2": .string("point2"),
                "p3": .string("point3"),
            ]),
        ]),
    ])

    static func definition(shape: String, mutation: String) -> SceneEffectDefinition {
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
            "materials/effects/waterripplenormal.png",
            "materials/effects/waterripplenormal.tex-json",
            "shaders/effects/waterripple.frag",
            "shaders/effects/waterripple.vert",
        ]
        let replacementKey: String?
        if mutation == "replacement" {
            replacementKey = "other"
        } else {
            replacementKey = shape == "legacyBare" ? nil : "waterripple"
        }
        return SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: replacementKey,
            name: mutation == "name" ? "Other" : "ui_editor_effect_water_ripple_title",
            description: mutation == "description"
                ? "Other"
                : "ui_editor_effect_water_ripple_description",
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
            gizmos: mutation == "gizmos"
                ? .array([])
                : (shape == "stock" ? stockGizmos : nil),
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
        let ripple = SceneRenderDescriptor.EffectDescriptor(
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
            texturePaths: options.materialPaths,
            textureSlots: options.materialSlots,
            userTextureInputs: [],
            combos: options.materialCombos,
            constantShaderValues: options.materialConstant
                ? ["extra": value([1])]
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
            : [definition(shape: options.definitionShape, mutation: options.definitionMutation)]
        return .init(
            layers: [.init(
                id: 20,
                contentKind: options.contentKind,
                effects: priorInput ? [dummy, ripple] : [ripple]
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
    ) -> SceneWaterRippleExecutionPlan? {
        SceneAuthoredWaterRipplePlanner.plan(
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

    static func options(
        shape: String,
        constants: [String: SceneDocument.ShaderValue]? = nil
    ) -> Options {
        var options = Options()
        options.definitionShape = shape
        if let constants { options.constants = constants }
        return options
    }

    static func main() throws {
        let roots = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let loader = SceneShaderContractLoader()
        let stockContracts = loader.load(
            shaderReferences: [shaderIdentity], rootURL: roots[0]
        )
        let invertedContracts = loader.load(
            shaderReferences: [shaderIdentity], rootURL: roots[1]
        )
        let maskComboContracts = loader.load(
            shaderReferences: [shaderIdentity], rootURL: roots[2]
        )
        let mixedContracts = loader.load(
            shaderReferences: [shaderIdentity], rootURL: roots[3]
        )

        let stockProfile = SceneWaterRippleShaderProfile.resolve(stockContracts)
        let invertedProfile = SceneWaterRippleShaderProfile.resolve(invertedContracts)
        let maskComboProfile = SceneWaterRippleShaderProfile.resolve(maskComboContracts)

        let stockPlan = planned(descriptorOptions: options(shape: "stock"), contracts: stockContracts)
        let invertedSparsePlan = planned(
            descriptorOptions: options(shape: "legacyKeyed", constants: sparseConstants()),
            contracts: invertedContracts
        )
        let invertedFullPlan = planned(
            descriptorOptions: options(shape: "legacyBare"),
            contracts: invertedContracts
        )
        let maskComboPlan = planned(
            descriptorOptions: options(
                shape: "legacyKeyed",
                constants: fullConstants(direction: -1.128422103818152)
            ),
            contracts: maskComboContracts
        )

        var unknownKey = options(shape: "legacyKeyed", constants: sparseConstants())
        unknownKey.constants["rippleamount"] = value([1])
        var maskCombo = options(shape: "legacyKeyed", constants: sparseConstants())
        maskCombo.instanceCombos = ["MASK": 1]
        var specularCombo = options(shape: "legacyKeyed", constants: sparseConstants())
        specularCombo.instanceCombos = ["SPECULAR": 1]
        var missingMask = options(shape: "legacyKeyed", constants: sparseConstants())
        missingMask.instanceSlots = [nil, nil, normalTexturePath]
        missingMask.instancePaths = [normalTexturePath]
        var slotZero = options(shape: "stock")
        slotZero.instanceSlots = ["asset.png", maskTexturePath, normalTexturePath]
        slotZero.instancePaths = ["asset.png", maskTexturePath, normalTexturePath]
        var extraSlot = options(shape: "stock")
        extraSlot.instanceSlots = [nil, maskTexturePath, normalTexturePath, "extra.png"]
        extraSlot.instancePaths = [maskTexturePath, normalTexturePath, "extra.png"]
        var wrongNormal = options(shape: "stock")
        wrongNormal.instanceSlots = [nil, maskTexturePath, "textures/other_normal"]
        wrongNormal.instancePaths = [maskTexturePath, "textures/other_normal"]
        var pathsMismatch = options(shape: "stock")
        pathsMismatch.instancePaths = [maskTexturePath]
        var userTexture = options(shape: "stock")
        userTexture.instanceUserTexture = true

        var hidden = options(shape: "stock"); hidden.visible = false
        var content = options(shape: "stock"); content.contentKind = "particle"
        var state = options(shape: "stock"); state.blending = "additive"
        var depth = options(shape: "stock"); depth.depthTest = "enabled"
        var materialPathOption = options(shape: "stock")
        materialPathOption.materialPath = "materials/other.json"
        var materialHash = options(shape: "stock")
        materialHash.materialRawSHA256 = String(repeating: "0", count: 64)
        var materialPass = options(shape: "stock"); materialPass.materialPassIndex = 1
        var shader = options(shape: "stock"); shader.shaderIdentity = "effects/other"
        var materialCombo = options(shape: "stock")
        materialCombo.materialCombos = ["SPECULAR": 1]
        var materialSlotsBroken = options(shape: "stock")
        materialSlotsBroken.materialSlots = []
        materialSlotsBroken.materialPaths = []
        var materialConstant = options(shape: "stock")
        materialConstant.materialConstant = true
        var duplicateMaterial = options(shape: "stock")
        duplicateMaterial.duplicateMaterial = true

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
        workshop.definitionPath = "effects/workshop/123/waterripple/effect.json"
        var graphMaterial = GraphOptions(); graphMaterial.materialPath = "materials/other.json"

        let definitionMutations = [
            "missing", "version", "replacement", "name", "description", "group",
            "performance", "preview", "editable", "passMaterial", "passTarget",
            "passBinding", "compose", "passExtra", "framebuffer", "dependencies",
            "functions", "gizmos", "extra",
        ]
        let stockDefinitionRejected = definitionMutations.allSatisfy { mutation in
            var mutated = options(shape: "stock")
            mutated.definitionMutation = mutation
            return !accepted(descriptorOptions: mutated, contracts: stockContracts)
        }
        let legacyDefinitionRejected = definitionMutations.allSatisfy { mutation in
            var mutated = options(shape: "legacyKeyed", constants: sparseConstants())
            mutated.definitionMutation = mutation
            return !accepted(descriptorOptions: mutated, contracts: invertedContracts)
        }
        let contractMutations = ["source", "raw", "metadata", "builtin", "canonical", "duplicate"]
        let contractRejected = contractMutations.allSatisfy {
            !accepted(
                descriptorOptions: options(shape: "stock"),
                contracts: mutate(stockContracts, $0)
            )
        } && contractMutations.allSatisfy {
            !accepted(
                descriptorOptions: options(shape: "legacyKeyed", constants: sparseConstants()),
                contracts: mutate(invertedContracts, $0)
            )
        } && contractMutations.allSatisfy {
            !accepted(
                descriptorOptions: options(shape: "legacyKeyed"),
                contracts: mutate(maskComboContracts, $0)
            )
        }

        let result: [String: Any] = [
            "stockProfileResolved": stockProfile == .stock2842
                && stockProfile!.scrollDirectionOffset == 0
                && stockProfile!.expectsPerspectiveGizmos == true
                && stockProfile!.acceptsMissingReplacementKey == false
                && stockProfile!.allowsSparseConstants == false,
            "invertedProfileResolved": invertedProfile == .invertedScrollV1
                && invertedProfile!.scrollDirectionOffset == Float.pi
                && invertedProfile!.expectsPerspectiveGizmos == false
                && invertedProfile!.acceptsMissingReplacementKey == true
                && invertedProfile!.allowsSparseConstants == true,
            "maskComboProfileResolved": maskComboProfile == .maskComboV1
                && maskComboProfile!.scrollDirectionOffset == 0
                && maskComboProfile!.expectsPerspectiveGizmos == false
                && maskComboProfile!.acceptsMissingReplacementKey == false
                && maskComboProfile!.allowsSparseConstants == true,
            "mixedFingerprintRejected":
                SceneWaterRippleShaderProfile.resolve(mixedContracts) == nil,
            "stockAccepted": stockPlan != nil
                && stockPlan!.runtimePlan.direction == Float(0.5)
                && stockPlan!.runtimePlan.animationSpeed == Float(0.15)
                && stockPlan!.runtimePlan.scrollSpeed == Float(0.2)
                && stockPlan!.maskTexturePath == maskTexturePath
                && stockPlan!.normalTexturePath == normalTexturePath,
            "stockSparseRejected": !accepted(
                descriptorOptions: options(shape: "stock", constants: sparseConstants()),
                contracts: stockContracts
            ),
            "stockLegacyDefinitionRejected": !accepted(
                descriptorOptions: options(shape: "legacyKeyed"),
                contracts: stockContracts
            ) && !accepted(
                descriptorOptions: options(shape: "legacyBare"),
                contracts: stockContracts
            ),
            "invertedSparseAccepted": invertedSparsePlan != nil
                && invertedSparsePlan!.runtimePlan.animationSpeed == Float(0.07)
                && invertedSparsePlan!.runtimePlan.ratio == Float(2.51)
                && invertedSparsePlan!.runtimePlan.strength == Float(0.07)
                && invertedSparsePlan!.runtimePlan.scale == Float(2.15)
                && invertedSparsePlan!.runtimePlan.scrollSpeed == 0
                && invertedSparsePlan!.runtimePlan.direction == Float.pi,
            "invertedFullAccepted": invertedFullPlan != nil
                && invertedFullPlan!.runtimePlan.direction == Float(0.5) + Float.pi,
            "invertedStockDefinitionRejected": !accepted(
                descriptorOptions: options(shape: "stock"),
                contracts: invertedContracts
            ),
            "maskComboAccepted": maskComboPlan != nil
                && maskComboPlan!.runtimePlan.direction == Float(-1.128422103818152),
            "maskComboBareRejected": !accepted(
                descriptorOptions: options(shape: "legacyBare"),
                contracts: maskComboContracts
            ),
            "maskComboSparseAccepted": accepted(
                descriptorOptions: options(shape: "legacyKeyed", constants: sparseConstants()),
                contracts: maskComboContracts
            ),
            "unknownConstantRejected": !accepted(
                descriptorOptions: unknownKey, contracts: invertedContracts
            ),
            "comboRejected": !accepted(descriptorOptions: maskCombo, contracts: invertedContracts)
                && !accepted(descriptorOptions: specularCombo, contracts: invertedContracts),
            "maskSlotRequired": !accepted(
                descriptorOptions: missingMask, contracts: invertedContracts
            ),
            "slotFormsRejected": [
                slotZero, extraSlot, wrongNormal, pathsMismatch, userTexture,
            ].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "materialRejected": [
                state, depth, materialPathOption, materialHash, materialPass, shader,
                materialCombo, materialSlotsBroken, materialConstant, duplicateMaterial,
            ].allSatisfy {
                !accepted(descriptorOptions: $0, contracts: stockContracts)
            },
            "hiddenRejected": !accepted(descriptorOptions: hidden, contracts: stockContracts),
            "contentKindRejected": !accepted(
                descriptorOptions: content, contracts: stockContracts
            ),
            "priorInputAccepted": accepted(
                graphOptions: prior,
                descriptorOptions: options(shape: "stock"),
                contracts: stockContracts,
                role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(
                graphOptions: prior,
                descriptorOptions: options(shape: "stock"),
                contracts: stockContracts
            ),
            "workshopVariantRejected": !accepted(
                graphOptions: workshop, contracts: stockContracts
            ),
            "graphShapeRejected": [
                blocker, targetGraph, binding, command, condition, copy,
                output, effectCount, nodeCount, graphMaterial,
            ].allSatisfy {
                !accepted(graphOptions: $0, contracts: stockContracts)
            },
            "stockDefinitionRejected": stockDefinitionRejected,
            "legacyDefinitionRejected": legacyDefinitionRejected,
            "contractRejected": contractRejected,
        ]
        let data = try JSONSerialization.data(withJSONObject: result.mapValues { $0 as Any })
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneWaterRipplePlannerTests(unittest.TestCase):
    def test_planner(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            stock_root = root / "stock"
            stock_dir = stock_root / "shaders/effects"
            stock_dir.mkdir(parents=True)
            shutil.copy(STOCK_SHADERS / "waterripple.vert", stock_dir / "waterripple.vert")
            shutil.copy(STOCK_SHADERS / "waterripple.frag", stock_dir / "waterripple.frag")
            legacy_roots = []
            for name, (vert_b64, frag_b64, vert_sha, frag_sha) in (
                LEGACY_STAGE_SHA256.items()
            ):
                vert = base64.b64decode(vert_b64)
                frag = base64.b64decode(frag_b64)
                self.assertEqual(hashlib.sha256(vert).hexdigest(), vert_sha, name)
                self.assertEqual(hashlib.sha256(frag).hexdigest(), frag_sha, name)
                legacy_root = root / name
                legacy_dir = legacy_root / "shaders/effects"
                legacy_dir.mkdir(parents=True)
                (legacy_dir / "waterripple.vert").write_bytes(vert)
                (legacy_dir / "waterripple.frag").write_bytes(frag)
                legacy_roots.append(legacy_root)
            # legacy vert + stock frag：不成对的指纹组合必须整体拒绝。
            mixed_root = root / "mixed"
            mixed_dir = mixed_root / "shaders/effects"
            mixed_dir.mkdir(parents=True)
            (mixed_dir / "waterripple.vert").write_bytes(
                base64.b64decode(LEGACY_INVERTED_VERT_BASE64)
            )
            shutil.copy(STOCK_SHADERS / "waterripple.frag", mixed_dir / "waterripple.frag")

            harness = root / "Harness.swift"
            executable = root / "waterripple-harness"
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
                [
                    str(executable),
                    str(stock_root),
                    *(str(path) for path in legacy_roots),
                    str(mixed_root),
                ],
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
