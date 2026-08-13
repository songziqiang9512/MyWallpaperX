#!/usr/bin/env python3

from __future__ import annotations

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
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderSourceGraph.swift",
    SOURCE_ROOT / "RenderGraph/ShaderContract/SceneShaderContract.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredLocalContrastPlanner.swift",
]


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

struct SceneEffectTextureInput {
    let name: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
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
        let shaderPath: String?
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
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let shaderSourceBase64 = [
        "downsample.vert": "DQphdHRyaWJ1dGUgdmVjMyBhX1Bvc2l0aW9uOw0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29yZDsNCg0KdmFyeWluZyB2ZWMyIHZfVGV4Q29vcmRbNF07DQoNCnVuaWZvcm0gdmVjNCBnX1RleHR1cmUwUmVzb2x1dGlvbjsNCg0Kdm9pZCBtYWluKCkgew0KCWdsX1Bvc2l0aW9uID0gdmVjNChhX1Bvc2l0aW9uLCAxLjApOw0KCQ0KCXZlYzIgb2Zmc2V0cyA9IDEuMCAvIGdfVGV4dHVyZTBSZXNvbHV0aW9uLnh5Ow0KCXZfVGV4Q29vcmRbMF0gPSBhX1RleENvb3JkIC0gb2Zmc2V0czsNCgl2X1RleENvb3JkWzFdID0gYV9UZXhDb29yZCArIHZlYzIob2Zmc2V0cy54LCAtb2Zmc2V0cy55KTsNCgl2X1RleENvb3JkWzJdID0gYV9UZXhDb29yZCArIHZlYzIoLW9mZnNldHMueCwgb2Zmc2V0cy55KTsNCgl2X1RleENvb3JkWzNdID0gYV9UZXhDb29yZCArIG9mZnNldHM7DQp9DQo=",
        "downsample.frag": "DQp2YXJ5aW5nIHZlYzIgdl9UZXhDb29yZFs0XTsNCg0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMDsgLy8geyJoaWRkZW4iOnRydWV9DQoNCnZvaWQgbWFpbigpIHsNCg0KCWZsb2F0IHdlaWdodCA9IDAuMDsNCgl2ZWM0IHJlc3VsdCA9IENBU1Q0KDAuMCk7DQoJZm9yIChpbnQgaSA9IDA7IGkgPCA0OyArK2kpDQoJew0KCQl2ZWM0IHNhbXBsZSA9IHRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbaV0pOw0KCQlyZXN1bHQgKz0gc2FtcGxlICogc2FtcGxlLmE7DQoJCXdlaWdodCArPSBzYW1wbGUuYTsNCgl9DQoJDQoJZ2xfRnJhZ0NvbG9yLnJnYiA9IHJlc3VsdC5yZ2IgLyBtYXgoMC4wMDEsIHdlaWdodCk7DQoJZ2xfRnJhZ0NvbG9yLmEgPSByZXN1bHQuYSAvIDQuMDsNCn0NCg==",
        "gaussian.vert": "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19rZXJuZWxfc2l6ZSIsImNvbWJvIjoiS0VSTkVMIiwidHlwZSI6Im9wdGlvbnMiLCJkZWZhdWx0IjowLCJvcHRpb25zIjp7IjEzeDEzIjowLCI3eDciOjEsIjN4MyI6Mn19DQoNCnVuaWZvcm0gdmVjMiBnX1NjYWxlOyAvLyB7Im1hdGVyaWFsIjoic2NhbGUiLCJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX3NjYWxlIiwiZGVmYXVsdCI6IjEgMSIsImxpbmtlZCI6dHJ1ZSwicmFuZ2UiOlswLjAxLCAyLjBdfQ0KDQphdHRyaWJ1dGUgdmVjMyBhX1Bvc2l0aW9uOw0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29yZDsNCg0KI2lmIEtFUk5FTCA9PSAwDQp2YXJ5aW5nIHZlYzIgdl9UZXhDb29yZFsxM107DQojZW5kaWYNCiNpZiBLRVJORUwgPT0gMQ0KdmFyeWluZyB2ZWMyIHZfVGV4Q29vcmRbN107DQojZW5kaWYNCiNpZiBLRVJORUwgPT0gMg0KdmFyeWluZyB2ZWMyIHZfVGV4Q29vcmRbM107DQojZW5kaWYNCg0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTBSZXNvbHV0aW9uOw0KDQp2b2lkIG1haW4oKSB7DQoJZ2xfUG9zaXRpb24gPSB2ZWM0KGFfUG9zaXRpb24sIDEuMCk7DQoJDQojaWYgVkVSVElDQUwNCglmbG9hdCBvZmZzZXRYID0gMC4wZjsNCglmbG9hdCBvZmZzZXRZID0gZ19TY2FsZS55IC8gZ19UZXh0dXJlMFJlc29sdXRpb24udzsNCiNlbHNlDQoJZmxvYXQgb2Zmc2V0WCA9IGdfU2NhbGUueCAvIGdfVGV4dHVyZTBSZXNvbHV0aW9uLno7DQoJZmxvYXQgb2Zmc2V0WSA9IDAuMGY7DQojZW5kaWYNCgkNCiNpZiBLRVJORUwgPT0gMA0KCXZfVGV4Q29vcmRbMF0gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFggKiA2LjAsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkgKiA2LjApOw0KCXZfVGV4Q29vcmRbMV0gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFggKiA1LjAsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkgKiA1LjApOw0KCXZfVGV4Q29vcmRbMl0gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFggKiA0LjAsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkgKiA0LjApOw0KCXZfVGV4Q29vcmRbM10gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFggKiAzLjAsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkgKiAzLjApOw0KCXZfVGV4Q29vcmRbNF0gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFggKiAyLjAsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkgKiAyLjApOw0KCXZfVGV4Q29vcmRbNV0gPSB2ZWMyKGFfVGV4Q29vcmQueCAtIG9mZnNldFgsIGFfVGV4Q29vcmQueSAtIG9mZnNldFkpOw0KCXZfVGV4Q29vcmRbNl0gPSB2ZWMyKGFfVGV4Q29vcmQueCwgYV9UZXhDb29yZC55KTsNCgl2X1RleENvb3JkWzddID0gdmVjMihhX1RleENvb3JkLnggKyBvZmZzZXRYLCBhX1RleENvb3JkLnkgKyBvZmZzZXRZKTsNCgl2X1RleENvb3JkWzhdID0gdmVjMihhX1RleENvb3JkLnggKyBvZmZzZXRYICogMi4wLCBhX1RleENvb3JkLnkgKyBvZmZzZXRZICogMi4wKTsNCgl2X1RleENvb3JkWzldID0gdmVjMihhX1RleENvb3JkLnggKyBvZmZzZXRYICogMy4wLCBhX1RleENvb3JkLnkgKyBvZmZzZXRZICogMy4wKTsNCgl2X1RleENvb3JkWzEwXSA9IHZlYzIoYV9UZXhDb29yZC54ICsgb2Zmc2V0WCAqIDQuMCwgYV9UZXhDb29yZC55ICsgb2Zmc2V0WSAqIDQuMCk7DQoJdl9UZXhDb29yZFsxMV0gPSB2ZWMyKGFfVGV4Q29vcmQueCArIG9mZnNldFggKiA1LjAsIGFfVGV4Q29vcmQueSArIG9mZnNldFkgKiA1LjApOw0KCXZfVGV4Q29vcmRbMTJdID0gdmVjMihhX1RleENvb3JkLnggKyBvZmZzZXRYICogNi4wLCBhX1RleENvb3JkLnkgKyBvZmZzZXRZICogNi4wKTsNCiNlbmRpZg0KI2lmIEtFUk5FTCA9PSAxDQoJdl9UZXhDb29yZFswXSA9IHZlYzIoYV9UZXhDb29yZC54IC0gb2Zmc2V0WCAqIDMuMCwgYV9UZXhDb29yZC55IC0gb2Zmc2V0WSAqIDMuMCk7DQoJdl9UZXhDb29yZFsxXSA9IHZlYzIoYV9UZXhDb29yZC54IC0gb2Zmc2V0WCAqIDIuMCwgYV9UZXhDb29yZC55IC0gb2Zmc2V0WSAqIDIuMCk7DQoJdl9UZXhDb29yZFsyXSA9IHZlYzIoYV9UZXhDb29yZC54IC0gb2Zmc2V0WCwgYV9UZXhDb29yZC55IC0gb2Zmc2V0WSk7DQoJdl9UZXhDb29yZFszXSA9IHZlYzIoYV9UZXhDb29yZC54LCBhX1RleENvb3JkLnkpOw0KCXZfVGV4Q29vcmRbNF0gPSB2ZWMyKGFfVGV4Q29vcmQueCArIG9mZnNldFgsIGFfVGV4Q29vcmQueSArIG9mZnNldFkpOw0KCXZfVGV4Q29vcmRbNV0gPSB2ZWMyKGFfVGV4Q29vcmQueCArIG9mZnNldFggKiAyLjAsIGFfVGV4Q29vcmQueSArIG9mZnNldFkgKiAyLjApOw0KCXZfVGV4Q29vcmRbNl0gPSB2ZWMyKGFfVGV4Q29vcmQueCArIG9mZnNldFggKiAzLjAsIGFfVGV4Q29vcmQueSArIG9mZnNldFkgKiAzLjApOw0KI2VuZGlmDQojaWYgS0VSTkVMID09IDINCgl2X1RleENvb3JkWzBdID0gdmVjMihhX1RleENvb3JkLnggLSBvZmZzZXRYLCBhX1RleENvb3JkLnkgLSBvZmZzZXRZKTsNCgl2X1RleENvb3JkWzFdID0gdmVjMihhX1RleENvb3JkLngsIGFfVGV4Q29vcmQueSk7DQoJdl9UZXhDb29yZFsyXSA9IHZlYzIoYV9UZXhDb29yZC54ICsgb2Zmc2V0WCwgYV9UZXhDb29yZC55ICsgb2Zmc2V0WSk7DQojZW5kaWYNCn0NCg==",
        "gaussian.frag": "DQojaWYgS0VSTkVMID09IDANCnZhcnlpbmcgdmVjMiB2X1RleENvb3JkWzEzXTsNCiNlbmRpZg0KI2lmIEtFUk5FTCA9PSAxDQp2YXJ5aW5nIHZlYzIgdl9UZXhDb29yZFs3XTsNCiNlbmRpZg0KI2lmIEtFUk5FTCA9PSAyDQp2YXJ5aW5nIHZlYzIgdl9UZXhDb29yZFszXTsNCiNlbmRpZg0KDQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUwOyAvLyB7ImhpZGRlbiI6dHJ1ZX0NCg0Kdm9pZCBtYWluKCkgew0KI2lmIEtFUk5FTCA9PSAwDQoJdmVjNCBhbGJlZG8gPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzBdKSAqIDAuMDA2Mjk5ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFsxXSkgKiAwLjAxNzI5OCArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbMl0pICogMC4wMzk1MzMgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzNdKSAqIDAuMDc1MTg5ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFs0XSkgKiAwLjExOTAwNyArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbNV0pICogMC4xNTY3NTYgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzZdKSAqIDAuMTcxODM0ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFs3XSkgKiAwLjE1Njc1NiArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbOF0pICogMC4xMTkwMDcgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzldKSAqIDAuMDc1MTg5ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFsxMF0pICogMC4wMzk1MzMgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzExXSkgKiAwLjAxNzI5OCArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbMTJdKSAqIDAuMDA2Mjk5Ow0KI2VuZGlmDQojaWYgS0VSTkVMID09IDENCgl2ZWM0IGFsYmVkbyA9IHRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbMF0pICogMC4wNzEzMDMgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzFdKSAqIDAuMTMxNTE0ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFsyXSkgKiAwLjE4OTg3OSArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbM10pICogMC4yMTQ2MDcgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzRdKSAqIDAuMTg5ODc5ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFs1XSkgKiAwLjEzMTUxNCArDQoJCQkJCXRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIHZfVGV4Q29vcmRbNl0pICogMC4wNzEzMDM7DQojZW5kaWYNCiNpZiBLRVJORUwgPT0gMg0KCXZlYzQgYWxiZWRvID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFswXSkgKiAwLjI1ICsNCgkJCQkJdGV4U2FtcGxlMkQoZ19UZXh0dXJlMCwgdl9UZXhDb29yZFsxXSkgKiAwLjUgKw0KCQkJCQl0ZXhTYW1wbGUyRChnX1RleHR1cmUwLCB2X1RleENvb3JkWzJdKSAqIDAuMjU7DQojZW5kaWYNCg0KCWdsX0ZyYWdDb2xvciA9IGFsYmVkbzsNCn0NCg==",
        "combine.vert": "DQp1bmlmb3JtIG1hdDQgZ19Nb2RlbFZpZXdQcm9qZWN0aW9uTWF0cml4Ow0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTFSZXNvbHV0aW9uOw0KDQphdHRyaWJ1dGUgdmVjMyBhX1Bvc2l0aW9uOw0KYXR0cmlidXRlIHZlYzIgYV9UZXhDb29yZDsNCg0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmQ7DQoNCnZvaWQgbWFpbigpIHsNCglnbF9Qb3NpdGlvbiA9IG11bCh2ZWM0KGFfUG9zaXRpb24sIDEuMCksIGdfTW9kZWxWaWV3UHJvamVjdGlvbk1hdHJpeCk7DQoJDQoJdl9UZXhDb29yZC54eSA9IGFfVGV4Q29vcmQ7DQoJdl9UZXhDb29yZC56dyA9IHZlYzIodl9UZXhDb29yZC54ICogZ19UZXh0dXJlMVJlc29sdXRpb24ueiAvIGdfVGV4dHVyZTFSZXNvbHV0aW9uLngsDQoJCQkJCQl2X1RleENvb3JkLnkgKiBnX1RleHR1cmUxUmVzb2x1dGlvbi53IC8gZ19UZXh0dXJlMVJlc29sdXRpb24ueSk7DQp9DQo=",
        "combine.frag": "DQovLyBbQ09NQk9dIHsibWF0ZXJpYWwiOiJ1aV9lZGl0b3JfcHJvcGVydGllc19ncmV5c2NhbGUiLCJjb21ibyI6IkdSRVlTQ0FMRSIsInR5cGUiOiJvcHRpb25zIiwiZGVmYXVsdCI6MH0NCg0KdmFyeWluZyB2ZWM0IHZfVGV4Q29vcmQ7DQoNCnVuaWZvcm0gc2FtcGxlcjJEIGdfVGV4dHVyZTA7IC8vIHsiaGlkZGVuIjp0cnVlfQ0KdW5pZm9ybSBzYW1wbGVyMkQgZ19UZXh0dXJlMTsgLy8geyJsYWJlbCI6InVpX2VkaXRvcl9wcm9wZXJ0aWVzX29wYWNpdHlfbWFzayIsIm1vZGUiOiJvcGFjaXR5bWFzayIsImNvbWJvIjoiTUFTSyIsInBhaW50ZGVmYXVsdGNvbG9yIjoiMCAwIDAgMSJ9DQp1bmlmb3JtIHNhbXBsZXIyRCBnX1RleHR1cmUyOyAvLyB7ImhpZGRlbiI6dHJ1ZX0NCg0KI2lmZGVmIEhMU0xfU00zMA0KdW5pZm9ybSB2ZWM0IGdfVGV4dHVyZTBSZXNvbHV0aW9uOw0KI2VuZGlmDQoNCnVuaWZvcm0gZmxvYXQgZ19BbW91bnQ7IC8vIHsibWF0ZXJpYWwiOiJzdHJlbmd0aCIsImxhYmVsIjoidWlfZWRpdG9yX3Byb3BlcnRpZXNfc3RyZW5ndGgiLCJkZWZhdWx0IjoxLjAsInJhbmdlIjpbMC4wMSwgNV19DQoNCnZvaWQgbWFpbigpIHsNCg0KCXZlYzIgYmx1cnJlZENvb3JkcyA9IHZfVGV4Q29vcmQueHk7DQoJDQojaWZkZWYgSExTTF9TTTMwDQoJYmx1cnJlZENvb3JkcyArPSAwLjc1IC8gZ19UZXh0dXJlMFJlc29sdXRpb24uenc7DQojZW5kaWYNCg0KCXZlYzQgYmx1cnJlZCA9IHRleFNhbXBsZTJEKGdfVGV4dHVyZTAsIGJsdXJyZWRDb29yZHMpOw0KCXZlYzQgYWxiZWRvID0gdGV4U2FtcGxlMkQoZ19UZXh0dXJlMiwgdl9UZXhDb29yZC54eSk7DQoJDQoJdmVjMyBkZWx0YSA9IGFsYmVkby5yZ2IgLSBibHVycmVkLnJnYjsNCiNpZiBHUkVZU0NBTEUNCglkZWx0YSA9IENBU1QzKGRvdCh2ZWMzKDAuMTEsIDAuNTksIDAuMyksIGRlbHRhKSk7DQojZW5kaWYNCgl2ZWMzIGVuaGFuY2VkID0gYWxiZWRvLnJnYiArIGRlbHRhICogZ19BbW91bnQ7DQoJDQojaWYgTUFTSw0KCWZsb2F0IG1hc2sgPSB0ZXhTYW1wbGUyRChnX1RleHR1cmUxLCB2X1RleENvb3JkLnp3KS5yOw0KI2Vsc2UNCglmbG9hdCBtYXNrID0gMS4wOw0KI2VuZGlmDQoJYWxiZWRvLnJnYiA9IG1peChhbGJlZG8ucmdiLCBlbmhhbmNlZC5yZ2IsIG1hc2spOw0KCQ0KCWdsX0ZyYWdDb2xvciA9IGFsYmVkbzsNCn0NCg==",
    ]

    struct DescriptorOptions {
        var contentKind = "image"
        var userBinding: String?
        var strength = 0.32
        var strengthKind = "number"
        var scale = [1.0, 1.0]
        var includesScale = true
        var includesStrength = true
        var xCombos: [String: Int] = [:]
        var yCombos: [String: Int] = ["VERTICAL": 1]
        var combineCombos: [String: Int] = [:]
        var blending = "normal"
        var downsampleShader = "effects/localcontrast_downsample4"
        var materialTexture: String?
    }

    struct GraphOptions {
        var mixed = false
        var definitionPath = "effects/localcontrast/effect.json"
        var targetScale = 4.0
        var targetFormat = "rgba8888"
        var combineSourceSlot = 2
        var secondTargetName = "_rt_QuarterCompoBuffer2"
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

    static func descriptor(_ options: DescriptorOptions = .init()) -> SceneRenderDescriptor {
        let scale = options.includesScale
            ? ["scale": value(options.scale, kind: "vector")]
            : [:]
        let strength = options.includesStrength
            ? ["strength": value([options.strength], kind: options.strengthKind, binding: options.userBinding)]
            : [:]
        let effect = SceneRenderDescriptor.EffectDescriptor(
            id: "42#effect#7",
            visible: true,
            passes: [
                .init(passIndex: 0, textureSlots: [], userTextureInputs: [], combos: [:], constantShaderValues: [:]),
                .init(passIndex: 1, textureSlots: [], userTextureInputs: [], combos: options.xCombos, constantShaderValues: scale),
                .init(passIndex: 2, textureSlots: [], userTextureInputs: [], combos: options.yCombos, constantShaderValues: scale),
                .init(passIndex: 3, textureSlots: [], userTextureInputs: [], combos: options.combineCombos, constantShaderValues: strength),
            ]
        )
        let paths = [
            "localcontrast_downsample4": options.downsampleShader,
            "localcontrast_gaussian_x": "effects/localcontrast_gaussian",
            "localcontrast_gaussian_y": "effects/localcontrast_gaussian",
            "localcontrast_combine": "effects/localcontrast_combine",
        ]
        let materials = paths.map { name, shader in
            SceneRenderDescriptor.MaterialPassDescriptor(
                id: "materials/effects/\(name).json#0",
                materialPath: "materials/effects/\(name).json",
                shaderPath: shader,
                textureSlots: name == "localcontrast_downsample4" && options.materialTexture != nil
                    ? [options.materialTexture]
                    : [],
                userTextureInputs: [],
                combos: name == "localcontrast_gaussian_y" ? ["VERTICAL": 1] : [:],
                constantShaderValues: [:],
                blending: options.blending,
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull"
            )
        }
        return .init(
            layers: [.init(id: 42, contentKind: options.contentKind, effects: [effect])],
            materialPasses: materials
        )
    }

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: 42, effect: effect, name: name)
    }

    static func graph(_ options: GraphOptions = .init()) -> Graph {
        let key = Graph.EffectKey(layerID: 42, effectIndex: 0, descriptorID: "42#effect#7")
        let source = texture(.layerSource)
        let output = texture(.effectOutput, effect: key)
        let first = texture(.framebuffer, effect: key, name: "_rt_QuarterCompoBuffer1")
        let second = texture(.framebuffer, effect: key, name: options.secondTargetName)
        let materials = [
            "localcontrast_downsample4",
            "localcontrast_gaussian_x",
            "localcontrast_gaussian_y",
            "localcontrast_combine",
        ]
        let bindings: [[Graph.Binding]] = [
            [.init(slot: 0, authoredName: "previous", texture: source, conditions: nil)],
            [.init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: first, conditions: nil)],
            [.init(slot: 0, authoredName: options.secondTargetName, texture: second, conditions: nil)],
            [
                .init(slot: 0, authoredName: "_rt_QuarterCompoBuffer1", texture: first, conditions: nil),
                .init(slot: options.combineSourceSlot, authoredName: "previous", texture: source, conditions: nil),
            ],
        ]
        let targets = [first, second, first, output]
        let nodes = materials.indices.map { index in
            Graph.Node(
                nodeIndex: index,
                effect: key,
                definitionPassIndex: index,
                materialOrdinal: index,
                instancePassIndex: index,
                kind: .material,
                materialPath: "materials/effects/\(materials[index]).json",
                materialPassID: "materials/effects/\(materials[index]).json#0",
                target: targets[index],
                bindings: bindings[index],
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }
        let effect = Graph.Effect(
            key: key,
            definitionPath: options.definitionPath,
            input: source,
            output: output,
            nodeIndices: [0, 1, 2, 3]
        )
        let renderTarget: (Graph.TextureIdentity) -> Graph.RenderTarget = { identity in
            .init(
                texture: identity,
                extent: .init(kind: .scale, first: options.targetScale, second: nil),
                format: options.targetFormat,
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )
        }
        return .init(
            layerID: 42,
            effects: options.mixed ? [effect, effect] : [effect],
            renderTargets: [renderTarget(first), renderTarget(second)],
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func source(_ key: String) -> String {
        String(data: Data(base64Encoded: shaderSourceBase64[key]!)!, encoding: .utf8)!
    }

    static func stage(
        kind: SceneShaderContract.StageKind,
        path: String,
        sourceKey: String,
        rawSHA256: String
    ) -> SceneShaderContract.Stage {
        .init(
            kind: kind,
            relativePath: path,
            source: source(sourceKey),
            rawSHA256: rawSHA256,
            includes: [],
            annotations: [],
            declarations: []
        )
    }

    static func contracts(_ mutation: String = "none") -> [SceneShaderContract] {
        let definitions: [(String, String, [(SceneShaderContract.StageKind, String, String, String)])] = [
            (
                "effects/localcontrast_downsample4",
                "4b2678fda69092ea473a8c30e6c14b27a42056a2d9d38bde8ac8ccad1aa54a1b",
                [
                    (.vertex, "shaders/effects/localcontrast_downsample4.vert", "downsample.vert", "522620fd19ca833762e965696c0c55e3136bae5442cec70227d5b32b32955747"),
                    (.fragment, "shaders/effects/localcontrast_downsample4.frag", "downsample.frag", "247c303a1925db1babae53f721710537338fe53810e94c38d1457444878f54f9"),
                ]
            ),
            (
                "effects/localcontrast_gaussian",
                "df9debe2c7f0bea3ead87458b37bcc387d04454a342e379f2f61d21dc56fa997",
                [
                    (.vertex, "shaders/effects/localcontrast_gaussian.vert", "gaussian.vert", "514f192a941cfb2aa0fa1e2e7f8b7a04405f5169e557d10293ed4e3d4f326144"),
                    (.fragment, "shaders/effects/localcontrast_gaussian.frag", "gaussian.frag", "bb847f608de8c34b6c400c8e54da9db33e5438a47ad837ba762390e9eae9f9b6"),
                ]
            ),
            (
                "effects/localcontrast_combine",
                "e107f1264f4170b52c6aeb9925302d22f5b89347304c67be1ce0efc93814ddda",
                [
                    (.vertex, "shaders/effects/localcontrast_combine.vert", "combine.vert", "208d5f52d8ad1d5bac439ad1c653e75fc9dc062ac6bb7f8ff87c1d18827c5dad"),
                    (.fragment, "shaders/effects/localcontrast_combine.frag", "combine.frag", "57a442cc99d46c0a102890e58671acf05dca6c1510a405f5d627d8b67100d151"),
                ]
            ),
        ]
        var result = definitions.enumerated().map { index, definition in
            let stages = definition.2.enumerated().map { stageIndex, value in
                var built = stage(kind: value.0, path: value.1, sourceKey: value.2, rawSHA256: value.3)
                if index == 0 && stageIndex == 0 && mutation == "source" {
                    built = .init(kind: built.kind, relativePath: built.relativePath, source: built.source + "x", rawSHA256: built.rawSHA256, includes: [], annotations: [], declarations: [])
                }
                if index == 0 && stageIndex == 0 && mutation == "raw" {
                    built = .init(kind: built.kind, relativePath: built.relativePath, source: built.source, rawSHA256: String(repeating: "0", count: 64), includes: [], annotations: [], declarations: [])
                }
                return built
            }
            let diagnostic: [SceneShaderContract.Diagnostic] = index == 0 && mutation == "diagnostic"
                ? [.init(code: .malformedAnnotation, message: "bad", relativePath: nil, line: nil)]
                : []
            return SceneShaderContract(
                identity: definition.0,
                sourceKind: index == 0 && mutation == "builtin" ? .hostBuiltin : .authoredSource,
                stages: stages,
                diagnostics: diagnostic,
                canonicalSHA256: index == 0 && mutation == "canonical"
                    ? String(repeating: "0", count: 64)
                    : definition.1
            )
        }
        if mutation == "duplicate" { result.append(result[0]) }
        return result
    }

    static func accepted(
        graphOptions: GraphOptions = .init(),
        descriptorOptions: DescriptorOptions = .init(),
        contractMutation: String = "none"
    ) -> Bool {
        SceneAuthoredLocalContrastPlanner.plan(
            graph: graph(graphOptions),
            descriptor: descriptor(descriptorOptions),
            shaderContracts: contracts(contractMutation)
        ) != nil
    }

    static func main() throws {
        let staticPlan = SceneAuthoredLocalContrastPlanner.plan(
            graph: graph(), descriptor: descriptor(), shaderContracts: contracts()
        )!
        var bindingOptions = DescriptorOptions()
        bindingOptions.userBinding = "brcontraststrength"
        bindingOptions.strengthKind = "binding"
        let boundPlan = SceneAuthoredLocalContrastPlanner.plan(
            graph: graph(), descriptor: descriptor(bindingOptions), shaderContracts: contracts()
        )!
        let target = boundPlan.liveStrengthTarget!
        let definition = SceneDynamicTargetDefinition(
            target: target,
            valueType: .scalar,
            authoredValue: .scalar(0.32)
        )
        let liveSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1,
            generation: 1,
            definitions: [definition],
            userValues: [target: .scalar(1.75)]
        ).snapshot
        let invalidSnapshot = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 2,
            generation: 2,
            definitions: [definition],
            userValues: [target: .scalar(6)]
        ).snapshot

        var mixed = GraphOptions(); mixed.mixed = true
        var wrongDefinition = GraphOptions(); wrongDefinition.definitionPath = "effects/other/effect.json"
        var wrongScale = GraphOptions(); wrongScale.targetScale = 2
        var wrongFormat = GraphOptions(); wrongFormat.targetFormat = "rgba_backbuffer"
        var wrongSlot = GraphOptions(); wrongSlot.combineSourceSlot = 1
        var wrongTarget = GraphOptions(); wrongTarget.secondTargetName = "other"
        var wrongContent = DescriptorOptions(); wrongContent.contentKind = "particle"
        var wrongState = DescriptorOptions(); wrongState.blending = "additive"
        var wrongShader = DescriptorOptions(); wrongShader.downsampleShader = "effects/other"
        var unknownSource = DescriptorOptions(); unknownSource.materialTexture = "assets/other.png"
        var wrongKernel = DescriptorOptions(); wrongKernel.xCombos = ["KERNEL": 1]
        var wrongMask = DescriptorOptions(); wrongMask.combineCombos = ["MASK": 1]
        var wrongScaleConstant = DescriptorOptions(); wrongScaleConstant.scale = [0.5, 1]
        var omittedDefaults = DescriptorOptions()
        omittedDefaults.includesScale = false; omittedDefaults.includesStrength = false
        let defaultedPlan = SceneAuthoredLocalContrastPlanner.plan(
            graph: graph(), descriptor: descriptor(omittedDefaults), shaderContracts: contracts()
        )!
        var zeroStrength = DescriptorOptions(); zeroStrength.strength = 0
        let zeroPlan = SceneAuthoredLocalContrastPlanner.plan(
            graph: graph(), descriptor: descriptor(zeroStrength), shaderContracts: contracts()
        )!
        var wrongStrength = DescriptorOptions(); wrongStrength.strength = -0.01
        var wrongStrengthKind = DescriptorOptions(); wrongStrengthKind.strengthKind = "vector"

        let binding = boundPlan.directStrengthBinding!
        let output: [String: Any] = [
            "validStatic": staticPlan.directStrengthBinding == nil,
            "staticStrength": staticPlan.staticOrFallbackStrength,
            "omittedDefaultsAccepted": defaultedPlan.staticOrFallbackStrength == 1,
            "zeroStrengthAccepted": zeroPlan.staticOrFallbackStrength == 0,
            "effectIdentityPreserved": staticPlan.effectKey.effectIndex == 0
                && staticPlan.firstQuarterTarget.name == "_rt_QuarterCompoBuffer1"
                && staticPlan.secondQuarterTarget.name == "_rt_QuarterCompoBuffer2",
            "validBinding": binding.propertyKey == "brcontraststrength"
                && binding.layerID == 42
                && binding.effectIndex == 0
                && binding.passIndex == 3
                && binding.constantName == "strength",
            "snapshotStrength": boundPlan.resolvedStrength(in: liveSnapshot) == 1.75,
            "snapshotFallback": boundPlan.resolvedStrength(in: invalidSnapshot) == 0.32,
            "mixedRejected": !accepted(graphOptions: mixed),
            "definitionRejected": !accepted(graphOptions: wrongDefinition),
            "targetScaleRejected": !accepted(graphOptions: wrongScale),
            "targetFormatRejected": !accepted(graphOptions: wrongFormat),
            "bindingSlotRejected": !accepted(graphOptions: wrongSlot),
            "targetIdentityRejected": !accepted(graphOptions: wrongTarget),
            "contentRejected": !accepted(descriptorOptions: wrongContent),
            "stateRejected": !accepted(descriptorOptions: wrongState),
            "shaderRejected": !accepted(descriptorOptions: wrongShader),
            "unknownTextureSourceRejected": !accepted(descriptorOptions: unknownSource),
            "kernelRejected": !accepted(descriptorOptions: wrongKernel),
            "maskRejected": !accepted(descriptorOptions: wrongMask),
            "scaleConstantRejected": !accepted(descriptorOptions: wrongScaleConstant),
            "strengthRangeRejected": !accepted(descriptorOptions: wrongStrength),
            "strengthKindRejected": !accepted(descriptorOptions: wrongStrengthKind),
            "builtinContractRejected": !accepted(contractMutation: "builtin"),
            "diagnosticRejected": !accepted(contractMutation: "diagnostic"),
            "canonicalRejected": !accepted(contractMutation: "canonical"),
            "rawHashRejected": !accepted(contractMutation: "raw"),
            "sourceMutationRejected": !accepted(contractMutation: "source"),
            "duplicateContractRejected": !accepted(contractMutation: "duplicate"),
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneLocalContrastPlannerTests(unittest.TestCase):
    def test_stock_profile_is_exact_and_fail_closed(self) -> None:
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc is unavailable")

        with tempfile.TemporaryDirectory(prefix="scene-local-contrast-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            executable = root / "local-contrast-harness"
            harness.write_text(HARNESS, encoding="utf-8")
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )

        output = json.loads(completed.stdout)
        self.assertAlmostEqual(output.pop("staticStrength"), 0.32, places=5)
        self.assertTrue(output)
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
