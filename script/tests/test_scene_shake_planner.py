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
    SOURCE_ROOT / "RenderGraph/SceneAuthoredShakePlanner.swift",
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
        var missingFlow = false
        var texturePathMismatch = false
        var extraTextureSlot = false
        var instanceCombos: [String: Int] = [:]
        var materialCombos: [String: Int] = [:]
        var missingConstant: String?
        var extraConstant = false
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
            replacementKey: mutation == "replacement" ? "other" : "shake",
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

        var audio = Options(); audio.instanceCombos = ["AUDIOPROCESSING": 1]
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
            "comboRejected": [audio, noise, direction, mask, unknownCombo]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "dynamicRejected": [boundSpeed, wrongKind]
                .allSatisfy { !accepted(descriptorOptions: $0, contracts: contracts) },
            "parameterRejected": [missing, extra, badBounds, badFriction, badSpeed, badStrength]
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
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShakePlannerTests(unittest.TestCase):
    def test_stock_profile_is_exact_and_fail_closed(self) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")

        with tempfile.TemporaryDirectory(prefix="scene-shake-planner-") as directory:
            root = Path(directory)
            shader_root = root / "shaders/effects"
            shader_root.mkdir(parents=True)
            (shader_root / "shake.vert").write_bytes(base64.b64decode(VERTEX_BASE64))
            (shader_root / "shake.frag").write_bytes(base64.b64decode(FRAGMENT_BASE64))
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
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(executable), str(root)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
