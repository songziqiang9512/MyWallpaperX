#!/usr/bin/env python3

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
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContractLoader.swift",
    SOURCE_ROOT / "RenderGraph/SceneShakeShaderProfile.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredShakePlanner.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Runtime/SceneAudioResponse.swift",
    SOURCE_ROOT / "RenderGraph/SceneAudioResponseAdmission.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredShakePlanner+Audio.swift",
]

VERTEX_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19hdWRp"
    "b19yZXNwb25zZSIsImNvbWJvIjoiQVVESU9QUk9DRVNTSU5HIiwidHlwZSI6ImF1ZGlv"
    "cHJvY2Vzc2luZ29wdGlvbnMiLCJkZWZhdWx0IjowfQ0KDQp1bmlmb3JtIG1hdDQgZ19N"
    "b2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4Ow0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFS"
    "ZXNvbHV0aW9uOw0KDQojaWYgTUFTSyA9PSAxDQp1bmlmb3JtIHZlYzQgZ19UZXh0dXJl"
    "MFJlc29sdXRpb247DQp1bmlmb3JtIHZlYzQgZ19UZXh0dXJlM1Jlc29sdXRpb247DQp2"
    "YXJ5aW5nIHZlYzQgdl9UZXhDb29yZE1hc2s7DQojZW5kaWYNCg0KYXR0cmlidXRlIHZl"
    "YzMgYV9Qb3NpdGlvbjsNCmF0dHJpYnV0ZSB2ZWMyIGFfVGV4Q29vcmQ7DQoNCnVuaWZv"
    "cm0gdmVjMiBnX0JvdW5kczsgLy8geyJtYXRlcmlhbCI6ImJvdW5kcyIsImxhYmVsIjoi"
    "dWlfZWRpdG9yX3Byb3BlcnRpZXNfYm91bmRzIiwiZGVmYXVsdCI6IjAgMSJ9DQoNCnZh"
    "cnlpbmcgdmVjNCB2X1RleENvb3JkOw0KdmFyeWluZyB2ZWMyIHZfQm91bmRzOw0KDQoj"
    "aWYgQVVESU9QUk9DRVNTSU5HDQp2YXJ5aW5nIGZsb2F0IHZfQXVkaW9QdWxzZTsNCnVu"
    "aWZvcm0gZmxvYXQgZ19BdWRpb1NwZWN0cnVtMTZMZWZ0WzE2XTsNCnVuaWZvcm0gZmxv"
    "YXQgZ19BdWRpb1NwZWN0cnVtMTZSaWdodFsxNl07DQoNCnVuaWZvcm0gZmxvYXQgZ19B"
    "dWRpb0ZyZXF1ZW5jeU1pbjsgLy8geyJtYXRlcmlhbCI6ImZyZXF1ZW5jeW1pbiIsImxh"
    "YmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfZnJlcXVlbmN5X21pbiIsImRlZmF1bHQi"
    "OjAsImludCI6dHJ1ZSwicmFuZ2UiOlswLDE1XX0NCnVuaWZvcm0gZmxvYXQgZ19BdWRp"
    "b0ZyZXF1ZW5jeU1heDsgLy8geyJtYXRlcmlhbCI6ImZyZXF1ZW5jeW1heCIsImxhYmVs"
    "IjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfZnJlcXVlbmN5X21heCIsImRlZmF1bHQiOjEs"
    "ImludCI6dHJ1ZSwicmFuZ2UiOlswLDE1XX0NCnVuaWZvcm0gZmxvYXQgZ19BdWRpb1Bv"
    "d2VyOyAvLyB7Im1hdGVyaWFsIjoiYXVkaW9leHBvbmVudCIsImxhYmVsIjoidWlfZWRp"
    "dG9yX3Byb3BlcnRpZXNfYXVkaW9fZXhwb25lbnQiLCJkZWZhdWx0IjoxLjAsInJhbmdl"
    "IjpbMCw0XX0NCnVuaWZvcm0gdmVjMiBnX0F1ZGlvQm91bmRzOyAvLyB7Im1hdGVyaWFs"
    "IjoiYXVkaW9ib3VuZHMiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2F1ZGlv"
    "X2JvdW5kcyIsImRlZmF1bHQiOiIwLjAgMS4yIn0NCnVuaWZvcm0gZmxvYXQgZ19BdWRp"
    "b011bHRpcGx5OyAvLyB7Im1hdGVyaWFsIjoiYXVkaW9hbW91bnQiLCJsYWJlbCI6InVp"
    "X2VkaXRvcl9wcm9wZXJ0aWVzX2F1ZGlvX2Ftb3VudCIsImRlZmF1bHQiOjEsInJhbmdl"
    "IjpbMCwyXX0NCg0KZmxvYXQgQ3JlYXRlQXVkaW9SZXNwb25zZShmbG9hdCBidWZmZXJM"
    "ZWZ0WzE2XSwgZmxvYXQgYnVmZmVyUmlnaHRbMTZdKQ0Kew0KCWZsb2F0IGF1ZGlvRnJl"
    "cXVlbmN5RW5kID0gbWF4KGdfQXVkaW9GcmVxdWVuY3lNaW4sIGdfQXVkaW9GcmVxdWVu"
    "Y3lNYXgpOw0KCWZsb2F0IGF1ZGlvUmVzcG9uc2UgPSAwLjA7DQoNCiNpZiBBVURJT1BS"
    "T0NFU1NJTkcgPT0gMQ0KCWZvciAoaW50IGEgPSBpbnQoZ19BdWRpb0ZyZXF1ZW5jeU1p"
    "bik7IGEgPD0gaW50KGdfQXVkaW9GcmVxdWVuY3lNYXgpOyArK2EpDQoJew0KCQlhdWRp"
    "b1Jlc3BvbnNlICs9IGJ1ZmZlckxlZnRbYV07DQoJfQ0KCWF1ZGlvUmVzcG9uc2UgLz0g"
    "KGdfQXVkaW9GcmVxdWVuY3lNYXggLSBnX0F1ZGlvRnJlcXVlbmN5TWluICsgMS4wKTsN"
    "CiNlbmRpZg0KI2lmIEFVRElPUFJPQ0VTU0lORyA9PSAyDQoJZm9yIChpbnQgYSA9IGlu"
    "dChnX0F1ZGlvRnJlcXVlbmN5TWluKTsgYSA8PSBpbnQoZ19BdWRpb0ZyZXF1ZW5jeU1h"
    "eCk7ICsrYSkNCgl7DQoJCWF1ZGlvUmVzcG9uc2UgKz0gYnVmZmVyUmlnaHRbYV07DQoJ"
    "fQ0KCWF1ZGlvUmVzcG9uc2UgLz0gKGdfQXVkaW9GcmVxdWVuY3lNYXggLSBnX0F1ZGlv"
    "RnJlcXVlbmN5TWluICsgMS4wKTsNCiNlbmRpZg0KI2lmIEFVRElPUFJPQ0VTU0lORyA9"
    "PSAzDQoJZm9yIChpbnQgYSA9IGludChnX0F1ZGlvRnJlcXVlbmN5TWluKTsgYSA8PSBp"
    "bnQoZ19BdWRpb0ZyZXF1ZW5jeU1heCk7ICsrYSkNCgl7DQoJCWF1ZGlvUmVzcG9uc2Ug"
    "Kz0gYnVmZmVyTGVmdFthXTsNCgkJYXVkaW9SZXNwb25zZSArPSBidWZmZXJSaWdodFth"
    "XTsNCgl9DQoJYXVkaW9SZXNwb25zZSAvPSAoZ19BdWRpb0ZyZXF1ZW5jeU1heCAtIGdf"
    "QXVkaW9GcmVxdWVuY3lNaW4gKyAxLjApICogMi4wOw0KI2VuZGlmDQoNCglhdWRpb1Jl"
    "c3BvbnNlID0gc21vb3Roc3RlcChnX0F1ZGlvQm91bmRzLngsIGdfQXVkaW9Cb3VuZHMu"
    "eSwgYXVkaW9SZXNwb25zZSk7DQoJYXVkaW9SZXNwb25zZSA9IHNhdHVyYXRlKHBvdyhh"
    "dWRpb1Jlc3BvbnNlLCBnX0F1ZGlvUG93ZXIpKSAqIGdfQXVkaW9NdWx0aXBseTsNCgly"
    "ZXR1cm4gYXVkaW9SZXNwb25zZTsNCn0NCiNlbmRpZg0KDQp2b2lkIG1haW4oKSB7DQoJ"
    "Z2xfUG9zaXRpb24gPSBtdWwodmVjNChhX1Bvc2l0aW9uLCAxLjApLCBnX01vZGVsVmll"
    "d1Byb2plY3Rpb25NYXRyaXgpOw0KCXZfVGV4Q29vcmQueHkgPSBhX1RleENvb3JkOw0K"
    "CXZfVGV4Q29vcmQuencgPSB2ZWMyKHZfVGV4Q29vcmQueCAqIGdfVGV4dHVyZTFSZXNv"
    "bHV0aW9uLnogLyBnX1RleHR1cmUxUmVzb2x1dGlvbi54LA0KCQkJCQkJdl9UZXhDb29y"
    "ZC55ICogZ19UZXh0dXJlMVJlc29sdXRpb24udyAvIGdfVGV4dHVyZTFSZXNvbHV0aW9u"
    "LnkpOw0KCXZfQm91bmRzLnggPSBnX0JvdW5kcy54Ow0KCXZfQm91bmRzLnkgPSAxLjAg"
    "LyAoZ19Cb3VuZHMueSAtIGdfQm91bmRzLngpOw0KDQojaWYgQVVESU9QUk9DRVNTSU5H"
    "DQoJdl9BdWRpb1B1bHNlID0gQ3JlYXRlQXVkaW9SZXNwb25zZShnX0F1ZGlvU3BlY3Ry"
    "dW0xNkxlZnQsIGdfQXVkaW9TcGVjdHJ1bTE2UmlnaHQpOw0KI2VuZGlmDQoNCiNpZiBN"
    "QVNLID09IDENCgl2X1RleENvb3JkTWFzay54eSA9IHZlYzIoYV9UZXhDb29yZC54ICog"
    "Z19UZXh0dXJlM1Jlc29sdXRpb24ueiAvIGdfVGV4dHVyZTNSZXNvbHV0aW9uLngsDQoJ"
    "CQkJCQlhX1RleENvb3JkLnkgKiBnX1RleHR1cmUzUmVzb2x1dGlvbi53IC8gZ19UZXh0"
    "dXJlM1Jlc29sdXRpb24ueSk7DQoJdl9UZXhDb29yZE1hc2suencgPSB2ZWMyKGdfVGV4"
    "dHVyZTNSZXNvbHV0aW9uLnogLyBnX1RleHR1cmUzUmVzb2x1dGlvbi54LCBnX1RleHR1"
    "cmUzUmVzb2x1dGlvbi53IC8gZ19UZXh0dXJlM1Jlc29sdXRpb24ueSk7DQojZW5kaWYN"
    "Cn0NCg=="
)

FRAGMENT_BASE64 = "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lzZSIsImNvbWJvIjoiTk9JU0UiLCJ0eXBlIjoib3B0aW9ucyIsImRlZmF1bHQiOjB9DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19kaXJlY3Rpb24iLCJjb21ibyI6IkRJUkVDVElPTiIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MCwib3B0aW9ucyI6eyJ1aV9lZGl0b3JfcHJvcGVydGllc19jZW50ZXIiOjAsInVpX2VkaXRvcl9wcm9wZXJ0aWVzX2xlZnQiOjEsInVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpZ2h0IjoyfX0NCg0KI2luY2x1ZGUgImNvbW1vbi5oIg0KDQp2YXJ5aW5nIHZlYzQgdl9UZXhDb29yZDsNCnZhcnlpbmcgdmVjMiB2X0JvdW5kczsNCg0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMDsgLy8geyJoaWRkZW4iOnRydWV9DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUxOyAvLyB7ImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc2hha2VfZGlyZWN0aW9uX21hcCIsIm1vZGUiOiJmbG93bWFzayIsImRlZmF1bHQiOiJ1dGlsL25vZmxvdyJ9DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUyOyAvLyB7ImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfdGltZV9vZmZzZXQiLCJtb2RlIjoib3BhY2l0eW1hc2siLCJkZWZhdWx0IjoidXRpbC93aGl0ZSJ9DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUzOyAvLyB7ImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfb3BhY2l0eSIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoiTUFTSyJ9DQp1bmlmb3JtIGZsb2F0IGdfVGltZTsNCg0KdW5pZm9ybSBmbG9hdCBnX1NwZWVkOyAvLyB7Im1hdGVyaWFsIjoic3BlZWQiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3NwZWVkIiwiZGVmYXVsdCI6MSwicmFuZ2UiOlswLjAsIDEwXX0NCnVuaWZvcm0gZmxvYXQgZ19BbXA7IC8vIHsibWF0ZXJpYWwiOiJzdHJlbmd0aCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc3RyZW5ndGgiLCJkZWZhdWx0IjowLjEsInJhbmdlIjpbMC4wMSwgMC41XX0NCnVuaWZvcm0gdmVjMiBnX0ZyaWN0aW9uOyAvLyB7Im1hdGVyaWFsIjoiZnJpY3Rpb24iLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX2ZyaWN0aW9uIiwiZGVmYXVsdCI6IjEgMSIsImxpbmtlZCI6dHJ1ZSwicmFuZ2UiOlswLjAxLCAxMC4wXX0NCg0KI2lmIEFVRElPUFJPQ0VTU0lORw0KdmFyeWluZyBmbG9hdCB2X0F1ZGlvUHVsc2U7DQojZW5kaWYNCg0KI2lmIE1BU0sgPT0gMQ0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmRNYXNrOw0KI2VuZGlmDQoNCnZvaWQgbWFpbigpIHsNCg0KCWZsb2F0IGZsb3dQaGFzZSA9IHRleFNhbXBsZTJEKGdfVGV4dHVyZTIsIHZfVGV4Q29vcmQuencpLnIgKiBNX1BJXzI7DQoJdmVjMiBmbG93Q29sb3JzID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMSwgdl9UZXhDb29yZC56dykucmc7DQoJdmVjMiBmbG93TWFzayA9IChmbG93Q29sb3JzLnJnIC0gdmVjMigwLjQ5OCwgMC40OTgpKSAqIDIuMDsNCglmbG9hdCBvZmZzZXQgPSAwLjA7DQoJDQojaWYgQVVESU9QUk9DRVNTSU5HID09IDANCiNpZiBOT0lTRQ0KCXZlYzQgc2luZXMgPSBmbG93UGhhc2UgKyBmcmFjKGdfU3BlZWQgKiBnX1RpbWUgLyBNX1BJXzIgKiB2ZWM0KDEsIC0wLjE2MTYxNjE2LCAwLjAwODMzMzMsIC0wLjAwMDE5ODQxKSkgKiBNX1BJXzI7DQoJdmVjNCBjc2luZXMgPSBjb3Moc2luZXMpOw0KCXNpbmVzID0gc2luKHNpbmVzKTsNCgkNCgl2ZWM0IGJhc2UgPSBzdGVwKDAuMCwgY3NpbmVzKTsNCglzaW5lcyA9IHNpbmVzICogMC40OTggKyAwLjU7DQoJc2luZXMgPSBtaXgoMS4wIC0gcG93KDEuMCAtIHNpbmVzLCBDQVNUNChnX0ZyaWN0aW9uLngpKSwgcG93KHNpbmVzLCBDQVNUNChnX0ZyaWN0aW9uLnkpKSwgYmFzZSk7DQoJb2Zmc2V0ID0gZG90KENBU1Q0KDAuNSksIHNpbmVzKTsNCiNlbHNlDQoJZmxvYXQgdGltZSA9IGdfU3BlZWQgKiBnX1RpbWUgKyBmbG93UGhhc2U7DQoJb2Zmc2V0ID0gc2luKGZyYWModGltZSAvIE1fUElfMikgKiBNX1BJXzIpOw0KCW9mZnNldCA9IG9mZnNldCAqIDAuNDk4ICsgMC41Ow0KCWZsb2F0IGJhc2UgPSBzdGVwKDAuMCwgY29zKHRpbWUpKTsNCglvZmZzZXQgPSBtaXgoMS4wIC0gcG93KDEuMCAtIG9mZnNldCwgZ19GcmljdGlvbi54KSwgcG93KG9mZnNldCwgZ19GcmljdGlvbi55KSwgYmFzZSk7DQojZW5kaWYNCglvZmZzZXQgPSBzYXR1cmF0ZSgob2Zmc2V0IC0gdl9Cb3VuZHMueCkgKiB2X0JvdW5kcy55KTsNCiNlbmRpZg0KDQoNCiNpZiBESVJFQ1RJT04gPT0gMA0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCW9mZnNldCArPSB2X0F1ZGlvUHVsc2U7DQojZWxzZQ0KCW9mZnNldCA9IG9mZnNldCAqIDIuMCAtIDEuMDsNCiNlbmRpZg0KI2VuZGlmDQoNCiNpZiBESVJFQ1RJT04gPT0gMQ0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCW9mZnNldCA9IDEuMCAtIHZfQXVkaW9QdWxzZTsNCiNlbmRpZg0KI2VuZGlmDQoNCiNpZiBESVJFQ1RJT04gPT0gMg0KI2lmIEFVRElPUFJPQ0VTU0lORw0KCW9mZnNldCAtPSB2X0F1ZGlvUHVsc2U7DQojZWxzZQ0KCW9mZnNldCA9IG9mZnNldCAtIDEuMDsNCiNlbmRpZg0KI2VuZGlmDQoJDQoJdmVjMiB0ZXhDb29yZE9mZnNldCA9IG9mZnNldCAqIGdfQW1wICogZ19BbXAgKiBmbG93TWFzazsNCglnbF9GcmFnQ29sb3IgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB0ZXhDb29yZE9mZnNldCArIHZfVGV4Q29vcmQueHkpOw0KCQ0KI2lmIE1BU0sNCgkvLyBPbmx5IGFsbG93IHNhbXBsaW5nIGZyb20gbWFzaw0KCWZsb2F0IG1hc2sgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUzLCB0ZXhDb29yZE9mZnNldCAqIHZfVGV4Q29vcmRNYXNrLnp3ICsgdl9UZXhDb29yZE1hc2sueHkpLnI7DQoJZ2xfRnJhZ0NvbG9yID0gbWl4KHRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmQueHkpLCBnbF9GcmFnQ29sb3IsIG1hc2spOw0KI2VuZGlmDQp9DQo="

# Raw bytes of shaders/effects/shake.frag extracted from workshop item
# 2131872317 scene.pkg (legacy fragment, SHA256
# c4911d58042b97b814c0562800463c85af0a6354035d5fc9d7e1b342bc8014ef).
LEGACY_FRAGMENT_BASE64 = (
    "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ub2lz"
    "ZSIsImNvbWJvIjoiTk9JU0UiLCJ0eXBlIjoib3B0aW9ucyIsImRlZmF1bHQiOjB9DQov"
    "LyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19kaXJlY3Rp"
    "b24iLCJjb21ibyI6IkRJUkVDVElPTiIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6"
    "MCwib3B0aW9ucyI6eyJ1aV9lZGl0b3JfcHJvcGVydGllc19jZW50ZXIiOjAsInVpX2Vk"
    "aXRvcl9wcm9wZXJ0aWVzX2xlZnQiOjEsInVpX2VkaXRvcl9wcm9wZXJ0aWVzX3JpZ2h0"
    "IjoyfX0NCg0KI2luY2x1ZGUgImNvbW1vbi5oIg0KDQp2YXJ5aW5nIHZlYzQgdl9UZXhD"
    "b29yZDsNCnZhcnlpbmcgdmVjMiB2X0JvdW5kczsNCg0KdW5pZm9ybSBzYW1wbGVyMkQg"
    "Z19UZXh0dXJlMDsgLy8geyJtYXRlcmlhbCI6ImZyYW1lYnVmZmVyIiwibGFiZWwiOiJ1"
    "aV9lZGl0b3JfcHJvcGVydGllc19mcmFtZWJ1ZmZlciIsImhpZGRlbiI6dHJ1ZX0NCnVu"
    "aWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTE7IC8vIHsibWF0ZXJpYWwiOiJmbG93Iiwi"
    "bGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19zaGFrZV9kaXJlY3Rpb25fbWFwIiwi"
    "bW9kZSI6ImZsb3dtYXNrIiwiZGVmYXVsdCI6InV0aWwvbm9mbG93In0NCnVuaWZvcm0g"
    "c2FtcGxlcjJEIGdfVGV4dHVyZTI7IC8vIHsibWF0ZXJpYWwiOiJwaGFzZSIsImxhYmVs"
    "IjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfdGltZV9vZmZzZXQiLCJtb2RlIjoib3BhY2l0"
    "eW1hc2siLCJkZWZhdWx0IjoidXRpbC93aGl0ZSJ9DQp1bmlmb3JtIHNhbXBsZXIyRCBn"
    "X1RleHR1cmUzOyAvLyB7Im1hdGVyaWFsIjoibWFzayIsImxhYmVsIjoidWlfZWRpdG9y"
    "X3Byb3BlcnRpZXNfb3BhY2l0eSIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoi"
    "TUFTSyIsImRlZmF1bHQiOiJ1dGlsL3doaXRlIn0NCnVuaWZvcm0gZmxvYXQgZ19UaW1l"
    "Ow0KDQp1bmlmb3JtIGZsb2F0IGdfU3BlZWQ7IC8vIHsibWF0ZXJpYWwiOiJzcGVlZCIs"
    "ImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc3BlZWQiLCJkZWZhdWx0IjoxLCJy"
    "YW5nZSI6WzAuMCwgMTBdfQ0KdW5pZm9ybSBmbG9hdCBnX0FtcDsgLy8geyJtYXRlcmlh"
    "bCI6InN0cmVuZ3RoIiwibGFiZWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19zdHJlbmd0"
    "aCIsImRlZmF1bHQiOjAuMSwicmFuZ2UiOlswLjAxLCAwLjVdfQ0KdW5pZm9ybSB2ZWMy"
    "IGdfRnJpY3Rpb247IC8vIHsibWF0ZXJpYWwiOiJmcmljdGlvbiIsImxhYmVsIjoidWlf"
    "ZWRpdG9yX3Byb3BlcnRpZXNfZnJpY3Rpb24iLCJkZWZhdWx0IjoiMSAxIiwibGlua2Vk"
    "Ijp0cnVlLCJyYW5nZSI6WzAuMDEsIDEwLjBdfQ0KDQojaWYgQVVESU9QUk9DRVNTSU5H"
    "DQp2YXJ5aW5nIGZsb2F0IHZfQXVkaW9QdWxzZTsNCiNlbmRpZg0KDQojaWYgTUFTSyA9"
    "PSAxDQp2YXJ5aW5nIHZlYzQgdl9UZXhDb29yZE1hc2s7DQojZW5kaWYNCg0Kdm9pZCBt"
    "YWluKCkgew0KDQoJZmxvYXQgZmxvd1BoYXNlID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJl"
    "Miwgdl9UZXhDb29yZC56dykuciAqIE1fUElfMjsNCgl2ZWMyIGZsb3dDb2xvcnMgPSB0"
    "ZXhTYW1wbGUyRChnX1RleHR1cmUxLCB2X1RleENvb3JkLnp3KS5yZzsNCgl2ZWMyIGZs"
    "b3dNYXNrID0gKGZsb3dDb2xvcnMucmcgLSB2ZWMyKDAuNDk4LCAwLjQ5OCkpICogMi4w"
    "Ow0KCWZsb2F0IG9mZnNldCA9IDAuMDsNCgkNCiNpZiBBVURJT1BST0NFU1NJTkcgPT0g"
    "MA0KI2lmIE5PSVNFDQoJdmVjNCBzaW5lcyA9IGZsb3dQaGFzZSArIGZyYWMoZ19TcGVl"
    "ZCAqIGdfVGltZSAvIE1fUElfMiAqIHZlYzQoMSwgLTAuMTYxNjE2MTYsIDAuMDA4MzMz"
    "MywgLTAuMDAwMTk4NDEpKSAqIE1fUElfMjsNCgl2ZWM0IGNzaW5lcyA9IGNvcyhzaW5l"
    "cyk7DQoJc2luZXMgPSBzaW4oc2luZXMpOw0KCQ0KCXZlYzQgYmFzZSA9IHN0ZXAoMC4w"
    "LCBjc2luZXMpOw0KCXNpbmVzID0gc2luZXMgKiAwLjQ5OCArIDAuNTsNCglzaW5lcyA9"
    "IG1peCgxLjAgLSBwb3coMS4wIC0gc2luZXMsIENBU1Q0KGdfRnJpY3Rpb24ueCkpLCBw"
    "b3coc2luZXMsIENBU1Q0KGdfRnJpY3Rpb24ueSkpLCBiYXNlKTsNCglvZmZzZXQgPSBk"
    "b3QoQ0FTVDQoMC41KSwgc2luZXMpOw0KI2Vsc2UNCglmbG9hdCB0aW1lID0gZ19TcGVl"
    "ZCAqIGdfVGltZSArIGZsb3dQaGFzZTsNCglvZmZzZXQgPSBzaW4oZnJhYyh0aW1lIC8g"
    "TV9QSV8yKSAqIE1fUElfMik7DQoJb2Zmc2V0ID0gb2Zmc2V0ICogMC40OTggKyAwLjU7"
    "DQoJZmxvYXQgYmFzZSA9IHN0ZXAoMC4wLCBjb3ModGltZSkpOw0KCW9mZnNldCA9IG1p"
    "eCgxLjAgLSBwb3coMS4wIC0gb2Zmc2V0LCBnX0ZyaWN0aW9uLngpLCBwb3cob2Zmc2V0"
    "LCBnX0ZyaWN0aW9uLnkpLCBiYXNlKTsNCiNlbmRpZg0KCW9mZnNldCA9IHNhdHVyYXRl"
    "KChvZmZzZXQgLSB2X0JvdW5kcy54KSAqIHZfQm91bmRzLnkpOw0KI2VuZGlmDQoNCg0K"
    "I2lmIERJUkVDVElPTiA9PSAwDQojaWYgQVVESU9QUk9DRVNTSU5HDQoJb2Zmc2V0ICs9"
    "IHZfQXVkaW9QdWxzZTsNCiNlbHNlDQoJb2Zmc2V0ID0gb2Zmc2V0ICogMi4wIC0gMS4w"
    "Ow0KI2VuZGlmDQojZW5kaWYNCg0KI2lmIERJUkVDVElPTiA9PSAxDQojaWYgQVVESU9Q"
    "Uk9DRVNTSU5HDQoJb2Zmc2V0ID0gMS4wIC0gdl9BdWRpb1B1bHNlOw0KI2VuZGlmDQoj"
    "ZW5kaWYNCg0KI2lmIERJUkVDVElPTiA9PSAyDQojaWYgQVVESU9QUk9DRVNTSU5HDQoJ"
    "b2Zmc2V0IC09IHZfQXVkaW9QdWxzZTsNCiNlbHNlDQoJb2Zmc2V0ID0gb2Zmc2V0IC0g"
    "MS4wOw0KI2VuZGlmDQojZW5kaWYNCgkNCgl2ZWMyIHRleENvb3JkT2Zmc2V0ID0gb2Zm"
    "c2V0ICogZ19BbXAgKiBnX0FtcCAqIGZsb3dNYXNrOw0KCWdsX0ZyYWdDb2xvciA9IHRl"
    "eFNhbXBsZTJEKGdfVGV4dHVyZTAsIHRleENvb3JkT2Zmc2V0ICsgdl9UZXhDb29yZC54"
    "eSk7DQoJDQojaWYgTUFTSyA9PSAxDQoJLy8gT25seSBhbGxvdyBzYW1wbGluZyBmcm9t"
    "IG1hc2sNCglmbG9hdCBtYXNrID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMywgdGV4Q29v"
    "cmRPZmZzZXQgKiB2X1RleENvb3JkTWFzay56dyArIHZfVGV4Q29vcmRNYXNrLnh5KS5y"
    "Ow0KCWdsX0ZyYWdDb2xvciA9IG1peCh0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1Rl"
    "eENvb3JkLnh5KSwgZ2xfRnJhZ0NvbG9yLCBtYXNrKTsNCiNlbmRpZg0KfQ0K"
)

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
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }
    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    static let layerID = 20
    static let definitionPath = "effects/shake/effect.json"
    static let materialPath = "materials/effects/shake.json"
    static let shaderIdentity = "effects/shake"
    static let flowPath = "masks/flow"
    static let phasePath = "masks/phase"

    struct Options {
        var contentKind = "image"
        var visible: Bool? = true
        var includePhase = true
        var trimOmittedPhase = false
        var missingFlow = false
        var texturePathMismatch = false
        var extraTextureSlot = false
        var instanceCombos: [String: Int] = [:]
        var materialCombos: [String: Int] = [:]
        var missingConstant: String?
        var extraConstant = false
        var constantSubset: [String]?
        var boundConstant: String?
        var wrongKindConstant: String?
        var bounds = [0.0, 1.0]
        var friction = [1.0, 1.0]
        var speed = 1.0
        var strength = 0.1
        var materialHash = "03e3f5fce8ce7b25e56e79405ba43bc150838e80c1b337c763637465369761fd"
        var shader = shaderIdentity
        var blending = "normal"
        var depthTest = "disabled"
        var duplicateMaterial = false
        var definitionMutation = "none"
        // audio 常量：nil 表示不写该键，交由 shader annotation 默认值填充
        var frequencyMin: Double?
        var frequencyMax: Double?
        var audioExponent: Double?
        var audioBounds: [Double]?
        var audioAmount: Double?
        var boundAudioConstant: String?
        var unknownAudioConstant = false
    }

    struct GraphOptions {
        var priorInput = false
        var blocker = false
        var extraTarget = false
        var binding = false
        var command = false
        var condition = false
        var nodeKind = Graph.NodeKind.material
        var outputMismatch = false
        var definitionPath = Harness.definitionPath
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

    static func constants(_ options: Options) -> [String: SceneDocument.ShaderValue] {
        var result = [
            "bounds": value(options.bounds, kind: "vector"),
            "friction": value(options.friction, kind: "vector"),
            "speed": value([options.speed], kind: "number"),
            "strength": value([options.strength], kind: "number"),
        ]
        if let subset = options.constantSubset {
            result = result.filter { subset.contains($0.key) }
        }
        if let value = options.frequencyMin { result["frequencymin"] = self.value([value], kind: "number") }
        if let value = options.frequencyMax { result["frequencymax"] = self.value([value], kind: "number") }
        if let value = options.audioExponent { result["audioexponent"] = self.value([value], kind: "number") }
        if let value = options.audioAmount { result["audioamount"] = self.value([value], kind: "number") }
        if let value = options.audioBounds { result["audiobounds"] = self.value(value, kind: "vector") }
        if options.unknownAudioConstant { result["audiounknown"] = self.value([1], kind: "number") }
        if let key = options.boundAudioConstant, let existing = result[key] {
            result[key] = self.value(
                existing.components ?? [],
                kind: existing.valueKind,
                binding: "newproperty7"
            )
        }
        if let key = options.missingConstant { result.removeValue(forKey: key) }
        if options.extraConstant { result["extra"] = value([1], kind: "number") }
        if let key = options.boundConstant, let existing = result[key] {
            result[key] = value(
                existing.components ?? [],
                kind: existing.valueKind,
                binding: "newproperty4"
            )
        }
        if let key = options.wrongKindConstant, let existing = result[key] {
            result[key] = value(existing.components ?? [], kind: "binding")
        }
        return result
    }

    static func definition(_ mutation: String) -> SceneEffectDefinition {
        let pass = SceneEffectDefinition.Pass(
            passIndex: 0,
            materialPath: mutation == "passMaterial" ? "materials/other.json" : materialPath,
            target: mutation == "passTarget" ? "other" : nil,
            bindings: mutation == "passBinding"
                ? [.init(name: "previous", index: 0, conditions: nil, extraFields: [:])]
                : [],
            compose: mutation == "compose" ? .bool(true) : nil,
            command: nil,
            source: nil,
            conditions: mutation == "condition" ? .bool(true) : nil,
            extraFields: mutation == "passExtra" ? ["extra": .bool(true)] : [:]
        )
        return SceneEffectDefinition(
            relativePath: definitionPath,
            version: mutation == "version" ? 2 : 1,
            replacementKey: mutation == "replacement"
                ? "other"
                : (mutation == "missingReplacement" ? nil : "shake"),
            name: mutation == "name" ? "other" : "ui_editor_effect_shake_title",
            description: mutation == "description"
                ? "other"
                : "ui_editor_effect_shake_description",
            group: mutation == "group" ? "other" : "animate",
            performance: mutation == "performance" ? "low" : nil,
            previewPath: mutation == "preview" ? "other/project.json" : "preview/project.json",
            editable: mutation == "editable" ? false : nil,
            passes: [pass],
            framebuffers: mutation == "framebuffer" ? [
                .init(
                    name: "rt", scale: nil, width: nil, height: nil, fit: nil,
                    format: nil, unique: nil, clear: nil, uvs: nil, conditions: nil,
                    extraFields: [:]
                )
            ] : [],
            dependencies: mutation == "dependencies" ? [] : [
                materialPath,
                "shaders/effects/shake.frag",
                "shaders/effects/shake.vert",
            ],
            functions: mutation == "functions" ? .object([:]) : nil,
            gizmos: mutation == "gizmos" ? .object([:]) : nil,
            extraFields: mutation == "extra" ? ["extra": .bool(true)] : [:],
            unknownFieldPaths: mutation == "extra" ? ["extra"] : []
        )
    }

    static func descriptor(_ options: Options = .init(), priorInput: Bool = false)
        -> SceneRenderDescriptor {
        let effectIndex = priorInput ? 1 : 0
        var slots: [String?] = [
            nil,
            options.missingFlow ? nil : flowPath,
            options.includePhase ? phasePath : nil,
        ]
        if options.trimOmittedPhase { slots.removeLast() }
        if options.extraTextureSlot { slots.append("extra") }
        var paths = slots.compactMap { $0 }
        if options.texturePathMismatch { paths.reverse() }
        let shake = SceneRenderDescriptor.EffectDescriptor(
            id: "\(layerID)#effect#\(effectIndex)",
            file: definitionPath,
            visible: options.visible,
            passes: [
                .init(
                    passIndex: 0,
                    texturePaths: paths,
                    textureSlots: slots,
                    userTextureInputs: [],
                    combos: options.instanceCombos,
                    constantShaderValues: constants(options)
                )
            ]
        )
        let dummy = SceneRenderDescriptor.EffectDescriptor(
            id: "\(layerID)#effect#0",
            file: "effects/other/effect.json",
            visible: true,
            passes: []
        )
        let material = SceneRenderDescriptor.MaterialPassDescriptor(
            id: "\(materialPath)#0",
            materialPath: materialPath,
            materialRawSHA256: options.materialHash,
            passIndex: 0,
            shaderPath: options.shader,
            texturePaths: [],
            textureSlots: [],
            userTextureInputs: [],
            combos: options.materialCombos,
            constantShaderValues: [:],
            blending: options.blending,
            depthTest: options.depthTest,
            depthWrite: "disabled",
            cullMode: "nocull"
        )
        return .init(
            layers: [
                .init(
                    id: layerID,
                    contentKind: options.contentKind,
                    effects: priorInput ? [dummy, shake] : [shake]
                )
            ],
            materialPasses: options.duplicateMaterial ? [material, material] : [material],
            effectDefinitions: options.definitionMutation == "missing"
                ? []
                : [definition(options.definitionMutation)]
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let effectIndex = options.priorInput ? 1 : 0
        let key = Graph.EffectKey(
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: "\(layerID)#effect#\(effectIndex)"
        )
        let previousKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "\(layerID)#effect#0"
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
            materialPath: materialPath,
            materialPassID: "\(materialPath)#0",
            target: output,
            bindings: options.binding
                ? [.init(slot: 0, authoredName: "previous", texture: input, conditions: nil)]
                : [],
            commandSource: options.command ? input : nil,
            commandTarget: nil,
            compose: nil,
            conditions: options.condition ? .bool(true) : nil
        )
        let effect = Graph.Effect(
            key: key,
            definitionPath: options.definitionPath,
            input: input,
            output: output,
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
        return .init(
            layerID: layerID,
            effects: [effect],
            renderTargets: options.extraTarget ? [target] : [],
            nodes: [node],
            finalOutput: options.outputMismatch ? input : output,
            blockers: options.blocker
                ? [.init(
                    effect: key,
                    definitionPassIndex: 0,
                    reason: .unsupportedCondition,
                    detail: "bad"
                )]
                : []
        )
    }

    static func mutate(
        _ contracts: [SceneShaderContract],
        _ mode: String
    ) -> [SceneShaderContract] {
        guard mode != "none", let contract = contracts.first else { return contracts }
        var stages = contract.stages
        if ["source", "raw", "metadata"].contains(mode) {
            let stage = stages[0]
            stages[0] = .init(
                kind: stage.kind,
                relativePath: stage.relativePath,
                source: mode == "source" ? stage.source + "x" : stage.source,
                rawSHA256: mode == "raw"
                    ? String(repeating: "0", count: 64)
                    : stage.rawSHA256,
                includes: stage.includes,
                annotations: mode == "metadata" ? [] : stage.annotations,
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
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract]
    ) -> SceneShakeExecutionPlan? {
        SceneAuthoredShakePlanner.plan(
            graph: graph(),
            descriptor: descriptor(descriptorOptions),
            shaderContracts: contracts
        )
    }

    static func accepted(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: Options = .init(),
        contracts: [SceneShaderContract],
        role: SceneAuthoredEffectInputRole = .layerSource
    ) -> Bool {
        SceneAuthoredShakePlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(
                descriptorOptions,
                priorInput: graphOptions.priorInput
            ),
            shaderContracts: contracts,
            inputRole: role
        ) != nil
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let contracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: root
        )
        let legacyRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let legacyContracts = SceneShaderContractLoader().load(
            shaderReferences: [shaderIdentity],
            rootURL: legacyRoot
        )
        let plan = SceneAuthoredShakePlanner.plan(
            graph: graph(),
            descriptor: descriptor(),
            shaderContracts: contracts
        )!

        var noPhase = Options(); noPhase.includePhase = false
        var prior = GraphOptions(); prior.priorInput = true
        var blocker = GraphOptions(); blocker.blocker = true
        var target = GraphOptions(); target.extraTarget = true
        var binding = GraphOptions(); binding.binding = true
        var command = GraphOptions(); command.command = true
        var condition = GraphOptions(); condition.condition = true
        var copy = GraphOptions(); copy.nodeKind = .copy
        var output = GraphOptions(); output.outputMismatch = true
        var wrongDefinition = GraphOptions(); wrongDefinition.definitionPath = "effects/other/effect.json"

        var noise = Options(); noise.materialCombos = ["NOISE": 1]
        var direction = Options(); direction.instanceCombos = ["DIRECTION": 2]
        var mask = Options(); mask.materialCombos = ["MASK": 1]
        var unknownCombo = Options(); unknownCombo.instanceCombos = ["OTHER": 0]
        var boundSpeed = Options(); boundSpeed.boundConstant = "speed"
        var wrongKind = Options(); wrongKind.wrongKindConstant = "strength"
        var missing = Options(); missing.missingConstant = "friction"
        var extra = Options(); extra.extraConstant = true
        var badBounds = Options(); badBounds.bounds = [0.5, 0.5]
        var badFriction = Options(); badFriction.friction = [0, 1]
        var badSpeed = Options(); badSpeed.speed = 10.1
        var badStrength = Options(); badStrength.strength = 0
        var missingFlow = Options(); missingFlow.missingFlow = true
        var pathMismatch = Options(); pathMismatch.texturePathMismatch = true
        var extraSlot = Options(); extraSlot.extraTextureSlot = true
        var badHash = Options(); badHash.materialHash = String(repeating: "0", count: 64)
        var badShader = Options(); badShader.shader = "effects/other"
        var badState = Options(); badState.blending = "additive"
        var badDepth = Options(); badDepth.depthTest = "enabled"
        var duplicateMaterial = Options(); duplicateMaterial.duplicateMaterial = true
        var hidden = Options(); hidden.visible = false
        var particle = Options(); particle.contentKind = "particle"

        var emptyConstants = Options(); emptyConstants.constantSubset = []
        var strengthOnly = Options(); strengthOnly.constantSubset = ["strength"]
        strengthOnly.strength = 0.3
        var strengthOutOfRange = Options(); strengthOutOfRange.constantSubset = ["strength"]
        strengthOutOfRange.strength = 0.6
        var legacyAudio = Options()
        legacyAudio.instanceCombos = ["AUDIOPROCESSING": 3]
        legacyAudio.includePhase = false
        legacyAudio.trimOmittedPhase = true
        legacyAudio.frequencyMax = 0
        legacyAudio.audioAmount = 2
        legacyAudio.audioBounds = [0, 1.2]

        // --- AUDIOPROCESSING 正门 ---
        // 全部五个 audio 常量齐备（3767460992 形态）
        var audioFull = Options()
        audioFull.instanceCombos = ["AUDIOPROCESSING": 3]
        audioFull.frequencyMin = 0
        audioFull.frequencyMax = 4
        audioFull.audioExponent = 0.5
        audioFull.audioBounds = [0.25, 0.75]
        audioFull.audioAmount = 2
        // 仅部分常量（1937925563 形态：缺 frequencymin 与 audioexponent）
        var audioPartial = Options()
        audioPartial.instanceCombos = ["AUDIOPROCESSING": 1]
        audioPartial.frequencyMax = 0
        audioPartial.audioAmount = 2
        audioPartial.audioBounds = [0, 1.2]
        // 全部缺省，走 shader annotation 默认值
        var audioDefaults = Options()
        audioDefaults.instanceCombos = ["AUDIOPROCESSING": 2]
        // --- AUDIOPROCESSING 反门 ---
        var audioOutOfRange = Options()
        audioOutOfRange.instanceCombos = ["AUDIOPROCESSING": 4]
        var audioBoundConstant = Options()
        audioBoundConstant.instanceCombos = ["AUDIOPROCESSING": 3]
        audioBoundConstant.audioAmount = 1
        audioBoundConstant.boundAudioConstant = "audioamount"
        var audioUnknownConstant = Options()
        audioUnknownConstant.instanceCombos = ["AUDIOPROCESSING": 3]
        audioUnknownConstant.unknownAudioConstant = true
        var audioFrequencyOutOfRange = Options()
        audioFrequencyOutOfRange.instanceCombos = ["AUDIOPROCESSING": 3]
        audioFrequencyOutOfRange.frequencyMax = 16
        var audioExponentOutOfRange = Options()
        audioExponentOutOfRange.instanceCombos = ["AUDIOPROCESSING": 3]
        audioExponentOutOfRange.audioExponent = 5
        var audioWithDirection = Options()
        audioWithDirection.instanceCombos = ["AUDIOPROCESSING": 3, "DIRECTION": 1]

        let audioFullPlan = planned(descriptorOptions: audioFull, contracts: contracts)
        let audioPartialPlan = planned(descriptorOptions: audioPartial, contracts: contracts)
        let audioDefaultsPlan = planned(descriptorOptions: audioDefaults, contracts: contracts)
        let nonAudioPlan = planned(contracts: contracts)
        var legacyTimeOffset = Options(); legacyTimeOffset.instanceCombos = ["TIMEOFFSET": 1]
        let legacyPlan = planned(contracts: legacyContracts)
        let legacyEmptyPlan = planned(
            descriptorOptions: emptyConstants,
            contracts: legacyContracts
        )
        let legacyStrengthPlan = planned(
            descriptorOptions: strengthOnly,
            contracts: legacyContracts
        )
        let legacyAudioPlan = planned(
            descriptorOptions: legacyAudio,
            contracts: legacyContracts
        )
        var legacyMissingReplacement = Options()
        legacyMissingReplacement.definitionMutation = "missingReplacement"
        let stockEmptyPlan = planned(
            descriptorOptions: emptyConstants,
            contracts: contracts
        )
        let stockStrengthPlan = planned(
            descriptorOptions: strengthOnly,
            contracts: contracts
        )
        let stockMissingPlan = planned(
            descriptorOptions: missing,
            contracts: contracts
        )

        let definitionMutations = [
            "missing", "version", "replacement", "name", "description", "group",
            "performance", "preview", "editable", "passMaterial", "passTarget",
            "passBinding", "compose", "condition", "passExtra", "framebuffer",
            "dependencies", "functions", "gizmos", "extra",
        ]
        let contractMutations = [
            "source", "raw", "metadata", "builtin", "canonical", "duplicate",
        ]
        let result: [String: Bool] = [
            "canonicalContract": contracts.first?.canonicalSHA256
                == "9b94cf5844faf7b0a5a01f1d81195f9a26752e6e55057aa821a8074e6187ac76",
            "exactAccepted": plan.layerID == layerID
                && plan.flowTexturePath == flowPath
                && plan.phaseTexturePath == phasePath
                && plan.bounds == SIMD2(0, 1)
                && plan.friction == SIMD2(1, 1)
                && plan.speed == 1
                && plan.strength == 0.1,
            "whitePhaseAccepted": accepted(descriptorOptions: noPhase, contracts: contracts),
            "candidateDetected": SceneAuthoredShakePlanner.containsCandidate(graph: graph()),
            "priorInputAccepted": accepted(
                graphOptions: prior,
                contracts: contracts,
                role: .priorEffectOutput
            ),
            "roleMismatchRejected": !accepted(graphOptions: prior, contracts: contracts),
            "graphRejected": [blocker, target, binding, command, condition, copy, output,
                              wrongDefinition]
                .allSatisfy { !accepted(graphOptions: $0, contracts: contracts) },
            "comboRejected": [noise, direction, mask, unknownCombo]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "audioDisabledPlanHasNoParameters": nonAudioPlan.map { $0.audio == nil } ?? false,
            "audioFullAccepted": audioFullPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .average,
                    frequencyMin: 0,
                    frequencyMax: 4,
                    boundsLower: 0.25,
                    boundsUpper: 0.75,
                    exponent: 0.5,
                    multiply: 2
                )
            } ?? false,
            "audioPartialBackfilled": audioPartialPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .left,
                    frequencyMin: 0,
                    frequencyMax: 0,
                    boundsLower: 0,
                    boundsUpper: 1.2,
                    exponent: 1,
                    multiply: 2
                )
            } ?? false,
            "audioDefaultsBackfilled": audioDefaultsPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .right,
                    frequencyMin: 0,
                    frequencyMax: 1,
                    boundsLower: 0,
                    boundsUpper: 1.2,
                    exponent: 1,
                    multiply: 1
                )
            } ?? false,
            "audioMotionConstantsPreserved": audioFullPlan.map {
                $0.bounds == SIMD2(0, 1) && $0.speed == 1 && $0.strength == 0.1
            } ?? false,
            "audioRejected": [audioOutOfRange, audioBoundConstant, audioUnknownConstant,
                              audioFrequencyOutOfRange, audioExponentOutOfRange,
                              audioWithDirection]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "dynamicRejected": [boundSpeed, wrongKind]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "parameterRejected": [extra, badBounds, badFriction, badSpeed, badStrength]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "resourceRejected": [missingFlow, pathMismatch, extraSlot]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "materialRejected": [badHash, badShader, badState, badDepth, duplicateMaterial]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "layerRejected": [hidden, particle]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "definitionRejected": definitionMutations.allSatisfy { mutation in
                var options = Options(); options.definitionMutation = mutation
                return !accepted(descriptorOptions: options, contracts: contracts)
            },
            "contractRejected": contractMutations.allSatisfy {
                !accepted(contracts: mutate(contracts, $0))
            },
            "stockEmptyConstantsBackfilled": stockEmptyPlan.map {
                $0.bounds == SIMD2(0, 1)
                    && $0.friction == SIMD2(1, 1)
                    && $0.speed == 1
                    && $0.strength == 0.1
            } ?? false,
            "stockStrengthOnlyBackfilled": stockStrengthPlan.map {
                $0.bounds == SIMD2(0, 1)
                    && $0.friction == SIMD2(1, 1)
                    && $0.speed == 1
                    && $0.strength == 0.3
            } ?? false,
            "stockMissingFrictionBackfilled": stockMissingPlan.map {
                $0.friction == SIMD2(1, 1)
            } ?? false,
            "legacyCanonicalContract": legacyContracts.first?.canonicalSHA256
                == "af9b4c97f86d10182d73b239cea9fd377ffcd4ac9ee8f7947c3dddea58898963",
            "legacyExactAccepted": legacyPlan.map {
                $0.layerID == layerID
                    && $0.flowTexturePath == flowPath
                    && $0.phaseTexturePath == phasePath
                    && $0.bounds == SIMD2(0, 1)
                    && $0.friction == SIMD2(1, 1)
                    && $0.speed == 1
                    && $0.strength == 0.1
            } ?? false,
            "legacyWhitePhaseAccepted": accepted(
                descriptorOptions: noPhase,
                contracts: legacyContracts
            ),
            "legacyEmptyConstantsBackfilled": legacyEmptyPlan.map {
                $0.bounds == SIMD2(0, 1)
                    && $0.friction == SIMD2(1, 1)
                    && $0.speed == 1
                    && $0.strength == 0.1
            } ?? false,
            "legacyStrengthOnlyBackfilled": legacyStrengthPlan.map {
                $0.bounds == SIMD2(0, 1)
                    && $0.friction == SIMD2(1, 1)
                    && $0.speed == 1
                    && $0.strength == 0.3
            } ?? false,
            "legacyAudioAccepted": legacyAudioPlan.map {
                $0.audio == SceneAudioResponse.Parameters(
                    channel: .average,
                    frequencyMin: 0,
                    frequencyMax: 0,
                    boundsLower: 0,
                    boundsUpper: 1.2,
                    exponent: 1,
                    multiply: 2
                )
            } ?? false,
            "legacyMissingReplacementAccepted": accepted(
                descriptorOptions: legacyMissingReplacement,
                contracts: legacyContracts
            ),
            "legacyParameterRejected": [extra, badBounds, badFriction, badSpeed,
                                        badStrength, strengthOutOfRange]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: legacyContracts) },
            "legacyDynamicRejected": [boundSpeed, wrongKind]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: legacyContracts) },
            "legacyComboRejected": [noise, direction, mask, legacyTimeOffset]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: legacyContracts) },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


_HARNESS_OUTPUT: dict[str, bool] | None = None


def harness_output(test: unittest.TestCase) -> dict[str, bool]:
    global _HARNESS_OUTPUT
    if _HARNESS_OUTPUT is not None:
        return _HARNESS_OUTPUT
    swiftc = shutil.which("swiftc")
    if not swiftc:
        test.skipTest("swiftc is unavailable")

    with tempfile.TemporaryDirectory(prefix="scene-shake-planner-") as directory:
        root = Path(directory)
        stock_root = root / "stock"
        legacy_root = root / "legacy"
        for shader_root, fragment_base64 in (
            (stock_root, FRAGMENT_BASE64),
            (legacy_root, LEGACY_FRAGMENT_BASE64),
        ):
            effects = shader_root / "shaders/effects"
            effects.mkdir(parents=True)
            (effects / "shake.vert").write_bytes(base64.b64decode(VERTEX_BASE64))
            (effects / "shake.frag").write_bytes(base64.b64decode(fragment_base64))
        harness = root / "Harness.swift"
        executable = root / "shake-planner-harness"
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
        test.assertEqual(compilation.returncode, 0, compilation.stderr)
        completed = subprocess.run(
            [str(executable), str(stock_root), str(legacy_root)],
            check=False,
            capture_output=True,
            text=True,
        )
        test.assertEqual(completed.returncode, 0, completed.stderr)

    _HARNESS_OUTPUT = json.loads(completed.stdout)
    return _HARNESS_OUTPUT


class SceneShakePlannerTests(unittest.TestCase):
    def assert_flags(self, legacy: bool) -> None:
        output = harness_output(self)
        flags = {
            key: value
            for key, value in output.items()
            if key.startswith("legacy") == legacy
        }
        self.assertTrue(flags)
        self.assertTrue(all(flags.values()), flags)

    def test_stock_profile_backfills_exact_shader_defaults_and_fails_closed(self) -> None:
        self.assert_flags(legacy=False)

    def test_legacy_profile_backfills_shader_defaults(self) -> None:
        self.assert_flags(legacy=True)


if __name__ == "__main__":
    unittest.main()
