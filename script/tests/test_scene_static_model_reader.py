#!/usr/bin/env python3
"""Contract tests for the bounded direct MDLV0016/MDLV0023 model reader."""

from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneMdlStaticModel.swift",
    SCENE_ROOT / "Format/SceneMdlStaticModelReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var results: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            var entry: [String: Any] = ["file": url.lastPathComponent]
            do {
                let loaded = try Data(contentsOf: url)
                // A non-zero Data startIndex and unaligned backing must retain
                // the same checked reader behavior as an ordinary file buffer.
                let data = ProcessInfo.processInfo.environment["MWX_READER_SLICE"] == "1"
                    ? (Data([0xA5]) + loaded).dropFirst() : loaded
                let parts = ProcessInfo.processInfo.environment["MWX_READER_SINGLE"] == "1"
                    ? [try SceneMdlStaticModelReader.read(data: data)]
                    : try SceneMdlStaticModelReader.readParts(data: data)
                let model = parts[0]
                entry["materialPaths"] = parts.map(\.materialPath)
                if ProcessInfo.processInfo.environment["MWX_READER_COMPACT"] == "1" {
                    // Exercise the complete decoder without serializing millions
                    // of vectors. Tail samples also prove the widened range is read.
                    let selected = [0, 1, 2, model.vertices.count - 3,
                                    model.vertices.count - 2, model.vertices.count - 1]
                    entry["ok"] = true
                    entry["partCount"] = parts.count
                    entry["vertexCount"] = model.vertices.count
                    entry["decodedVertexBytes"] = model.vertices.count
                        * MemoryLayout<SceneMdlStaticModel.Vertex>.stride
                    entry["indexElementSize"] = model.indexElementSize
                    entry["indices"] = model.indices.map(Int.init)
                    entry["samples"] = selected.map { index in
                        let vertex = model.vertices[index]
                        return ["index": index,
                            "position": [vertex.position.x, vertex.position.y, vertex.position.z].map(Double.init),
                            "normal": [vertex.normal.x, vertex.normal.y, vertex.normal.z].map(Double.init),
                            "tangent": [vertex.tangent.x, vertex.tangent.y, vertex.tangent.z, vertex.tangent.w].map(Double.init),
                            "uv": [vertex.uv.x, vertex.uv.y].map(Double.init)] as [String: Any]
                    }
                    results.append(entry)
                    continue
                }
                entry["parts"] = parts.map { part in
                    ["material": part.materialPath, "indices": part.indices.map(Int.init),
                     "elementSize": part.indexElementSize,
                     "positions": part.vertices.map { [Double($0.position.x), Double($0.position.y), Double($0.position.z)] }] as [String: Any]
                }
                entry["ok"] = true
                entry["version"] = model.version
                entry["headerFormat"] = model.headerFormat
                entry["vertexFormat"] = model.vertexFormat
                entry["vertexStride"] = model.vertexStride
                entry["indexElementSize"] = model.indexElementSize
                entry["materialPath"] = model.materialPath
                entry["vertexMemoryStride"] = MemoryLayout<SceneMdlStaticModel.Vertex>.stride
                entry["positionOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.position
                )
                entry["normalOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.normal
                )
                entry["tangentOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.tangent
                )
                entry["uvOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.uv
                )
                entry["boundsMinimum"] = model.bounds.minimum.map(Double.init)
                entry["boundsMaximum"] = model.bounds.maximum.map(Double.init)
                entry["triangleCount"] = model.triangleCount
                entry["indices"] = model.indices.map(Int.init)
                entry["vertices"] = model.vertices.map { vertex in
                    [
                        "position": [
                            vertex.position.x, vertex.position.y, vertex.position.z,
                        ].map(Double.init),
                        "normal": [
                            vertex.normal.x, vertex.normal.y, vertex.normal.z,
                        ].map(Double.init),
                        "tangent": [
                            vertex.tangent.x, vertex.tangent.y,
                            vertex.tangent.z, vertex.tangent.w,
                        ].map(Double.init),
                        "uv": [vertex.uv.x, vertex.uv.y].map(Double.init),
                    ]
                }
            } catch let error as SceneMdlStaticModelReadError {
                entry["ok"] = false
                entry["error"] = error.description
                if case let .unsupportedMaterialCount(count) = error {
                    entry["unsupportedCount"] = Int(count)
                }
            }
            results.append(entry)
        }
        let payload = try JSONSerialization.data(
            withJSONObject: results,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(payload)
    }
}
'''


DEFAULT_VERTICES = [
    (
        (-1.0, -1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (0.0, 0.0),
    ),
    (
        (1.0, -1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (1.0, 0.0),
    ),
    (
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (0.5, 1.0),
    ),
]
VERTEX_CHANNELS = ("position.x", "position.y", "position.z", "normal.x", "normal.y", "normal.z",
                   "tangent.x", "tangent.y", "tangent.z", "tangent.w", "uv.x", "uv.y")
NONFINITE_VALUES = (("nan", float("nan")), ("inf", float("inf")), ("negative-inf", -float("inf")))


def build_model(
    *,
    magic: bytes = b"MDLV0023\0",
    header_format: int = 15,
    mesh_count: int = 1,
    material_count: int = 1,
    material: bytes = b"materials/models/fixture/default.json",
    index_flag: int = 0,
    bounds=(-1.0, -1.0, -1.0, 1.0, 1.0, 1.0),
    vertex_format: int = 15,
    vertices=DEFAULT_VERTICES,
    indices=(0, 1, 2),
    declared_vertex_byte_count: int | None = None,
    declared_index_byte_count: int | None = None,
    trailer: bytes = b"\0" * 7,
) -> bytes:
    vertex_blob = b"".join(
        struct.pack("<12f", *(position + normal + tangent + uv))
        for position, normal, tangent, uv in vertices
    )
    if index_flag == 1:
        index_blob = struct.pack(f"<{len(indices)}I", *indices)
    else:
        index_blob = struct.pack(f"<{len(indices)}H", *indices)
    return b"".join(
        [
            magic,
            struct.pack("<III", header_format, mesh_count, material_count),
            material,
            b"\0",
            struct.pack(
                "<I6fII",
                index_flag,
                *bounds,
                vertex_format,
                declared_vertex_byte_count
                if declared_vertex_byte_count is not None
                else len(vertex_blob),
            ),
            vertex_blob,
            struct.pack(
                "<I",
                declared_index_byte_count
                if declared_index_byte_count is not None
                else len(index_blob),
            ),
            index_blob,
            trailer,
        ]
    )


def build_parts(count, *, last_changes=None):
    """Complete self-authored parts, distinct material/geometry, alternating index width."""
    blobs = []
    for i in range(count):
        x = float(i * 4)
        vertices = [((x + dx, y, 0.), normal, tangent, uv)
                    for (dx, y), (_, normal, tangent, uv) in zip(
                        [(0., 0.), (2., 0.), (0., 2.)], DEFAULT_VERTICES)]
        options = dict(material_count=count, material=f'materials/parts/p{i:03}.json'.encode(),
                       vertices=vertices, bounds=(x, 0., 0., x+2., 2., 0.), index_flag=i % 2)
        if i == count - 1:
            options.update(last_changes or {})
        body = build_model(**options)
        blobs.append(body[:-7] if i == 0 else b'\0' * 6 + body[21:-7])
    return b''.join(blobs) + b'\0' * 7


def build_legacy_model(
    *,
    material: bytes = b"materials/models/fixture/legacy.json",
    vertices=DEFAULT_VERTICES,
    indices=(0, 1, 2),
    trailer: bytes = b"\0",
) -> bytes:
    vertex_blob = b"".join(
        struct.pack("<12f", *(position + normal + tangent + uv))
        for position, normal, tangent, uv in vertices
    )
    index_blob = struct.pack(f"<{len(indices)}H", *indices)
    return b"".join(
        [
            b"MDLV0016\0",
            struct.pack("<III", 15, 1, 1),
            material,
            b"\0",
            struct.pack("<III", 0, 15, len(vertex_blob)),
            vertex_blob,
            struct.pack("<I", len(index_blob)),
            index_blob,
            trailer,
        ]
    )


def write_large_valid_model(path: Path) -> tuple[int, int]:
    """Stream self-authored triangles just beyond the retired 64 MiB limit."""
    triangle = b"".join(struct.pack("<12f", *(p + n + t + uv))
                        for p, n, t, uv in DEFAULT_VERTICES)
    repetitions = (64 * 1024 * 1024) // len(triangle) + 1
    vertex_count = repetitions * 3
    vertex_bytes = repetitions * len(triangle)
    header = b"".join([
        b"MDLV0023\0", struct.pack("<III", 15, 1, 1),
        b"materials/models/fixture/large.json\0",
        struct.pack("<I6fII", 1, -1, -1, -1, 1, 1, 1, 15, vertex_bytes),
    ])
    with path.open("wb") as handle:
        handle.write(header)
        block_count, remainder = divmod(repetitions, 1024)
        block = triangle * 1024
        for _ in range(block_count):
            handle.write(block)
        handle.write(triangle * remainder)
        handle.write(struct.pack("<I3I", 12, 0, vertex_count - 2, vertex_count - 1))
        handle.write(b"\0" * 7)
    return vertex_count, len(header)


def reader_fixtures():
    """Self-authored byte corpus shared by the CPU gate and task-only comparison."""
    first = build_model(material_count=2, material=b"materials/first.json")[:-7]
    second = build_model(index_flag=1, material=b"materials/second.json")[21:]
    multipart = first + b"\0" * 6 + second
    fixtures = {
        "empty.mdl": b"",
        "parts.mdl": multipart,
        "bad-separator.mdl": first + b"\0" * 5 + b"\1" + second,
        "short-second.mdl": multipart[:-12],
        "bad-second-index.mdl": first + b"\0" * 6 + build_model(
            index_flag=1, indices=(0, 1, 99))[21:],
        "valid.mdl": build_model(),
        "legacy-valid.mdl": build_legacy_model(),
        "windows-material.mdl": build_model(
            material=b"materials\\models\\fixture\\default.json"
        ),
        "old-version.mdl": build_model(magic=b"MDLV0015\0"),
        "bad-nul.mdl": build_model(magic=b"MDLV0023X"),
        "bad-header-format.mdl": build_model(header_format=14),
        "multi-mesh.mdl": build_model(mesh_count=2),
        "short-declared-65.mdl": build_model(material_count=65)[:-7],
        "short-declared-huge.mdl": build_model(material_count=0xffffffff)[:-7],
        "zero-material.mdl": build_model(material_count=0),
        "legacy-multipart.mdl": build_model(magic=b"MDLV0016\0", material_count=2),
        "unsafe-material.mdl": build_model(material=b"../escape.json"),
        "invalid-utf8-material.mdl": build_model(material=b"materials/\xff.json"),
        "uint32-indices.mdl": build_model(index_flag=1),
        "wide-indices.mdl": build_model(index_flag=1,
            vertices=DEFAULT_VERTICES * 21846, indices=(0, 65536, 65537)),
        "unknown-indices.mdl": build_model(index_flag=2),
        "bad-wide-index.mdl": build_model(index_flag=1, indices=(0, 1, 0xffffffff)),
        "partial-wide-triangle.mdl": build_model(index_flag=1, indices=(0, 1)),
        "nan-bounds.mdl": build_model(
            bounds=(float("nan"), -1, -1, 1, 1, 1)
        ),
        "inverted-bounds.mdl": build_model(bounds=(2, -1, -1, 1, 1, 1)),
        "bad-vertex-format.mdl": build_model(vertex_format=7),
        "empty-vertices.mdl": build_model(vertices=[]),
        "bad-vertex-bytes.mdl": build_model(declared_vertex_byte_count=47),
        "vertex-budget.mdl": build_model(
            declared_vertex_byte_count=268_435_488
        ),
        "nan-vertex.mdl": build_model(
            vertices=[
                (
                    (float("nan"), -1, 0),
                    (0, 0, 1),
                    (1, 0, 0, -1),
                    (0, 0),
                ),
                *DEFAULT_VERTICES[1:],
            ]
        ),
        "outside-bounds.mdl": build_model(
            vertices=[
                (
                    (-2, -1, 0),
                    (0, 0, 1),
                    (1, 0, 0, -1),
                    (0, 0),
                ),
                *DEFAULT_VERTICES[1:],
            ]
        ),
        "extreme-channel.mdl": build_model(
            vertices=[
                (
                    (-1, -1, 0),
                    (2_000_000, 0, 1),
                    (1, 0, 0, -1),
                    (0, 0),
                ),
                *DEFAULT_VERTICES[1:],
            ]
        ),
        "bad-index.mdl": build_model(indices=(0, 1, 3)),
        "non-triangle-indices.mdl": build_model(indices=(0, 1)),
        "index-budget.mdl": build_model(
            declared_index_byte_count=33_554_436
        ),
        "nonzero-trailer.mdl": build_model(trailer=b"\0" * 6 + b"\1"),
        "extra-tail.mdl": build_model(trailer=b"\0" * 8),
        "legacy-nonzero-trailer.mdl": build_legacy_model(trailer=b"\1"),
        "legacy-extra-tail.mdl": build_legacy_model(trailer=b"\0\0"),
        "truncated.mdl": build_model()[:-1],
    }
    for count in (4, 5, 8, 64, 65):
        fixtures[f"complete-{count}.mdl"] = build_parts(count)
    fixtures["complete-65-renamed.mdl"] = build_parts(65).replace(
        b"materials/parts/p", "materials/renamed Ω/coat".encode())
    fixtures["complete-65-equivalent.mdl"] = build_parts(65).replace(
        b"materials/parts/p", b"././materials//./parts/p")
    fixtures.update({
        "late-truncated.mdl": build_parts(8)[:-13],
        "late-index.mdl": build_parts(8, last_changes={"indices": (0, 1, 99)}),
        "late-path.mdl": build_parts(8, last_changes={"material": b"../escape.json"}),
        "late-finite.mdl": build_parts(8, last_changes={"vertices": [
            ((float("nan"), 0., 0.), *DEFAULT_VERTICES[0][1:]), *DEFAULT_VERTICES[1:]]}),
        "late-trailer.mdl": build_parts(8)[:-1] + b"\1",
        # Each later declaration fits the individual byte limit, but adding
        # already validated first-part bytes crosses the unchanged model budget.
        "cumulative-vertex.mdl": build_parts(2, last_changes={"declared_vertex_byte_count": 268_435_440}),
        "cumulative-index.mdl": (build_model(material_count=2, indices=(0,1,2)*4)[:-7]
            + b"\0"*6 + build_model(index_flag=1, declared_index_byte_count=33_554_424)[21:]),
    })
    for label, changes in (
        ("index", {"indices": (0, 1, 99)}),
        ("path", {"material": b"../escape.json"}),
        ("finite", {"vertices": [
            ((float("nan"), 0., 0.), *DEFAULT_VERTICES[0][1:]), *DEFAULT_VERTICES[1:]]}),
    ):
        fixtures[f"late-65-{label}.mdl"] = build_parts(65, last_changes=changes)
    fixtures["late-65-truncated.mdl"] = build_parts(65)[:-13]
    fixtures["late-65-trailer.mdl"] = build_parts(65)[:-1] + b"\1"
    posix_material_paths = {}
    for profile, make in (("0023", build_model), ("0016", build_legacy_model)):
        for label, path, canonical in (
            ("drive-component", "materials/C:/paint.json", "materials/C:/paint.json"),
            ("colon-leaf", "materials/file:paint.json", "materials/file:paint.json"),
            ("backslashes", r"materials\C:\paint.json", "materials/C:/paint.json"),
            ("renamed", "materials/theme:blue/coat Ω.json", "materials/theme:blue/coat Ω.json"),
            ("leading-dots", "././materials/C:/paint.json", "materials/C:/paint.json"),
            ("repeated-separators", "materials//C:////paint.json", "materials/C:/paint.json"),
            ("internal-dots", "materials/./C:/./paint.json", "materials/C:/paint.json"),
            ("mixed-backslashes", r".\.\materials\\.\C:\paint.json", "materials/C:/paint.json"),
            ("dot-name", "materials/.hidden/file..name.json", "materials/.hidden/file..name.json"),
            ("renamed-dots", "./materials//Theme Ω/./coating:blue.json", "materials/Theme Ω/coating:blue.json"),
            ("previous-length-boundary", "materials/" + "a" * (4096 - len("materials/")),
             "materials/" + "a" * (4096 - len("materials/"))),
            ("long-canonical", "materials/" + "a" * 8192, "materials/" + "a" * 8192),
            ("long-unicode", "materials/Theme Ω/" + "地" * 1800 + ":paint.json",
             "materials/Theme Ω/" + "地" * 1800 + ":paint.json"),
            ("long-leading-dots", "./" * 8192 + "materials/C:/paint.json", "materials/C:/paint.json"),
            ("long-internal-dots", "materials/" + "./" * 4096 + "paint.json", "materials/paint.json"),
            ("long-mixed-slashes", ".\\" * 4096 + "materials\\\\.\\C:\\paint.json",
             "materials/C:/paint.json"),
        ):
            name = f"posix-{profile}-{label}.mdl"
            fixtures[name] = make(material=path.encode())
            posix_material_paths[name] = [canonical]
        for label, path in (
            ("absolute", b"/materials/C:/paint.json"),
            ("escape", b"../materials/C:/paint.json"),
            ("bad-utf8", b"materials/C:/\xff.json"),
            ("control", b"materials/C:/bad\x1f.json"),
            ("trailing-slash", b"materials/C:/paint.json/"),
            ("trailing-dot", b"materials/C:/paint.json/."),
            ("trailing-separators", b"materials/C:/paint.json//"),
            ("dot-only", b"."),
            ("all-dots", b"././."),
            ("internal-parent", b"materials/sub/../C:/paint.json"),
            ("parent-after-dot", b"materials/./../C:/paint.json"),
            ("double-absolute", b"//materials/C:/paint.json"),
        ):
            fixtures[f"invalid-posix-{profile}-{label}.mdl"] = make(material=path)
        fixtures[f"missing-nul-{profile}.mdl"] = make()[:21] + b"materials/" + b"a" * 8192
        fixtures[f"long-invalid-utf8-{profile}.mdl"] = make(material=b"materials/" + b"a" * 8192 + b"\xff")
        fixtures[f"long-parent-{profile}.mdl"] = make(material=b"materials/" + b"./" * 4096 + b"../escape.json")
        fixtures[f"long-control-{profile}.mdl"] = make(material=b"materials/" + b"a" * 8192 + b"\x1f.json")
        fixtures[f"long-truncated-{profile}.mdl"] = make(material=b"materials/" + b"a" * 8192)[:-12]
    for label, path, canonical in (
            ("drive", r"materials\C:\paint.json", "materials/C:/paint.json"),
            ("renamed", "materials/New Name:α/other.json", "materials/New Name:α/other.json"),
            ("dots", "materials//./C:/paint.json", "materials/C:/paint.json"),
            ("backslash-dots", r".\materials\\.\New Name:β\coat.json", "materials/New Name:β/coat.json")):
        name = f"posix-later-{label}.mdl"
        first = build_model(material_count=2, material=b"materials/first.json")[:-7]
        fixtures[name] = first + b"\0" * 6 + build_model(material=path.encode())[21:]
        posix_material_paths[name] = ["materials/first.json", canonical]
    for profile, builder in (("0023", build_model), ("0016", build_legacy_model)):
        for channel, name in enumerate(VERTEX_CHANNELS):
            for label, value in NONFINITE_VALUES:
                fields = list(sum(DEFAULT_VERTICES[-1], ()))
                fields[channel] = value
                vertex = (tuple(fields[:3]), tuple(fields[3:6]),
                          tuple(fields[6:10]), tuple(fields[10:12]))
                fixtures[f"nonfinite-{profile}-{name}-{label}.mdl"] = builder(
                    vertices=[*DEFAULT_VERTICES[:-1], vertex])
    return fixtures, posix_material_paths


class SceneMdlStaticModelReaderTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory(prefix="mwx-static-model-reader-")
        root = Path(cls._tmp.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "harness"
        compilation = subprocess.run(
            ["swiftc", "-O", *map(str, SWIFT_SOURCES), str(harness),
             "-module-cache-path", str(root / "cache"), "-o", str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")

        fixtures, cls.posix_material_paths = reader_fixtures()
        for name, value in fixtures.items():
            (root / name).write_bytes(value)
        completed = subprocess.run(
            [str(cls.binary), *(str(root / name) for name in fixtures)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            timeout=60,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {
            result["file"]: result for result in json.loads(completed.stdout)
        }
        sliced = subprocess.run(
            [str(cls.binary), *(str(root / name) for name in fixtures)],
            cwd=REPOSITORY_ROOT, capture_output=True, text=True,
            env={**os.environ, "MWX_READER_SLICE": "1"},
            timeout=60,
        )
        if sliced.returncode != 0:
            raise AssertionError(f"sliced harness run failed:\n{sliced.stderr}")
        cls.sliced_results = {
            result["file"]: result for result in json.loads(sliced.stdout)
        }
        single = subprocess.run(
            [str(cls.binary), str(root / "valid.mdl"), str(root / "complete-65.mdl")],
            cwd=REPOSITORY_ROOT, capture_output=True, text=True, timeout=60,
            env={**os.environ, "MWX_READER_SINGLE": "1"},
        )
        if single.returncode != 0:
            raise AssertionError(f"single-model harness run failed:\n{single.stderr}")
        cls.single_results = {result["file"]: result for result in json.loads(single.stdout)}

    def test_geometry_above_retired_budget_validates_and_decodes_through_its_tail(self):
        path = Path(self._tmp.name) / "large-valid.mdl"
        count, vertex_offset = write_large_valid_model(path)
        self.assertGreater(count * 48, 64 * 1024 * 1024)
        self.assertLess(count * 48, 256 * 1024 * 1024)
        started = time.monotonic()
        completed = subprocess.run(
            [str(self.binary), str(path)], cwd=REPOSITORY_ROOT,
            capture_output=True, text=True, timeout=60,
            env={**os.environ, "MWX_READER_COMPACT": "1"},
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertLess(len(completed.stdout), 4096)
        row = json.loads(completed.stdout)[0]
        self.assertTrue(row["ok"], row)
        self.assertEqual(row["partCount"], 1)
        self.assertEqual(row["materialPaths"], ["materials/models/fixture/large.json"])
        self.assertEqual(row["vertexCount"], count)
        self.assertEqual(row["decodedVertexBytes"], count * 64)
        self.assertEqual(row["indexElementSize"], 4)
        self.assertEqual(row["indices"], [0, count - 2, count - 1])
        for sample in row["samples"]:
            position, normal, tangent, uv = DEFAULT_VERTICES[sample["index"] % 3]
            self.assertEqual(sample, {"index": sample["index"], "position": list(position),
                "normal": list(normal), "tangent": list(tangent), "uv": list(uv)})
        print(f"Large model reader: {count * 48} authored bytes, {count * 64} decoded bytes, "
              f"{len(completed.stdout)} output bytes, {time.monotonic() - started:.3f}s", flush=True)

        # Corruption beyond the old cap rejects the complete model before
        # publishing material paths or any part.
        with path.open("r+b") as handle:
            handle.seek(vertex_offset + (count - 1) * 48)
            handle.write(struct.pack("<f", float("nan")))
        corrupted = subprocess.run(
            [str(self.binary), str(path)], cwd=REPOSITORY_ROOT,
            capture_output=True, text=True, timeout=60,
            env={**os.environ, "MWX_READER_COMPACT": "1"},
        )
        self.assertEqual(corrupted.returncode, 0, corrupted.stderr)
        rejected = json.loads(corrupted.stdout)[0]
        self.assertFalse(rejected["ok"])
        self.assertNotIn("materialPaths", rejected)
        self.assertIn(f"non-finite static mdl vertex data at index {count - 1}", rejected["error"])
        self.assertNotIn("partCount", rejected)
        path.unlink()

    def test_nonzero_data_slice_preserves_every_value_and_rejection(self):
        self.assertEqual(self.sliced_results, self.results)
        self.assertFalse(self.results["empty.mdl"]["ok"])

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()


    def test_complete_segments_preserve_every_part(self):
        for count in (4, 5, 8, 64, 65):
            row = self.results[f"complete-{count}.mdl"]
            self.assertTrue(row["ok"], row)
            expected = [{"material": f"materials/parts/p{i:03}.json",
                         "indices": [0,1,2], "elementSize": 4 if i % 2 else 2,
                         "positions": [[i*4,0,0],[i*4+2,0,0],[i*4,2,0]]}
                        for i in range(count)]
            self.assertEqual(row["parts"], expected)
            self.assertEqual(row["materialPaths"], [p["material"] for p in expected])

    def test_65_parts_preserve_renamed_and_equivalent_materials(self):
        original = self.results["complete-65.mdl"]
        equivalent = dict(self.results["complete-65-equivalent.mdl"], file=original["file"])
        self.assertEqual(equivalent, original)
        renamed = self.results["complete-65-renamed.mdl"]
        expected = dict(original, file=renamed["file"])
        expected["materialPath"] = "materials/renamed Ω/coat000.json"
        expected["materialPaths"] = [f"materials/renamed Ω/coat{i:03}.json" for i in range(65)]
        expected["parts"] = [dict(part, material=expected["materialPaths"][i])
                             for i, part in enumerate(original["parts"])]
        self.assertEqual(renamed, expected)

    def test_single_model_api_still_requires_one_complete_part(self):
        self.assertEqual(self.single_results["valid.mdl"], self.results["valid.mdl"])
        rejected = self.single_results["complete-65.mdl"]
        self.assertFalse(rejected["ok"], rejected)
        self.assertEqual(rejected["unsupportedCount"], 65)
        self.assertNotIn("parts", rejected)
        self.assertNotIn("materialPaths", rejected)

    def test_declared_parts_still_require_bytes_and_supported_profile(self):
        for name in ("short-declared-65.mdl", "short-declared-huge.mdl"):
            row = self.results[name]
            self.assertFalse(row["ok"], row)
            self.assertIn("truncated", row["error"])
            self.assertNotIn("unsupportedCount", row)
            self.assertNotIn("parts", row)
            self.assertNotIn("materialPaths", row)
        for name, count in (("zero-material.mdl", 0), ("legacy-multipart.mdl", 2)):
            self.assertEqual(self.results[name]["unsupportedCount"], count)

    def test_late_corruption_and_cumulative_budget_reject_complete_parts(self):
        for name, message in (("late-truncated.mdl","truncated"), ("late-index.mdl","index 99"),
                ("late-path.mdl","material path"), ("late-finite.mdl","non-finite"),
                ("late-trailer.mdl","trailer"), ("cumulative-vertex.mdl","vertex byte budget"),
                ("cumulative-index.mdl","index byte budget")):
            row = self.results[name]
            self.assertFalse(row["ok"], row)
            self.assertIn(message, row["error"])
            self.assertNotIn("materialPaths", row)
            self.assertNotIn("parts", row)
        for label, message in (("truncated", "truncated"), ("index", "index 99"),
                               ("path", "material path"), ("finite", "non-finite"), ("trailer", "trailer")):
            row = self.results[f"late-65-{label}.mdl"]
            self.assertFalse(row["ok"], row)
            self.assertIn(message, row["error"])
            self.assertNotIn("materialPaths", row)
            self.assertNotIn("parts", row)

    def test_valid_profile_preserves_all_geometry_channels(self) -> None:
        result = self.results["valid.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["version"], "MDLV0023")
        self.assertEqual((result["headerFormat"], result["vertexFormat"]), (15, 15))
        self.assertEqual((result["vertexStride"], result["indexElementSize"]), (48, 2))
        self.assertEqual(result["vertexMemoryStride"], 64)
        self.assertEqual(
            [
                result["positionOffset"], result["normalOffset"],
                result["tangentOffset"], result["uvOffset"],
            ],
            [0, 16, 32, 48],
        )
        self.assertEqual(result["materialPath"], "materials/models/fixture/default.json")
        self.assertEqual(result["boundsMinimum"], [-1, -1, -1])
        self.assertEqual(result["boundsMaximum"], [1, 1, 1])
        self.assertEqual(result["triangleCount"], 1)
        self.assertEqual(result["indices"], [0, 1, 2])
        self.assertEqual(result["vertices"][0], {
            "position": [-1, -1, 0],
            "normal": [0, 0, 1],
            "tangent": [1, 0, 0, -1],
            "uv": [0, 0],
        })

    def test_material_path_is_normalized_without_identity_dispatch(self) -> None:
        result = self.results["windows-material.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["materialPath"], "materials/models/fixture/default.json")

    def test_posix_colon_material_names_preserve_parts_and_adjacent_path_failures(self) -> None:
        for name, expected in self.posix_material_paths.items():
            with self.subTest(name=name):
                result = self.results[name]
                self.assertTrue(result["ok"], result)
                self.assertEqual(result["materialPaths"], expected)
                self.assertEqual(result["indices"], [0, 1, 2])
                self.assertEqual(self.sliced_results[name], result)
        for profile in ("0023", "0016"):
            for label in ("absolute", "escape", "bad-utf8", "control",
                          "trailing-slash", "trailing-dot", "trailing-separators", "dot-only", "all-dots",
                          "internal-parent", "parent-after-dot", "double-absolute"):
                name = f"invalid-posix-{profile}-{label}.mdl"
                with self.subTest(name=name):
                    result = self.results[name]
                    self.assertFalse(result["ok"], result)
                    self.assertIn("material path", result["error"])
                    self.assertNotIn("materialPaths", result)
                    self.assertEqual(self.sliced_results[name], result)

    def test_long_material_paths_keep_real_delimiter_utf8_and_geometry_boundaries(self):
        for profile in ("0023", "0016"):
            for label in ("long-canonical", "long-unicode", "long-leading-dots",
                          "long-internal-dots", "long-mixed-slashes"):
                name = f"posix-{profile}-{label}.mdl"
                row = self.results[name]
                self.assertTrue(row["ok"], row)
                self.assertEqual(row["materialPaths"], self.posix_material_paths[name])
                if label in ("long-canonical", "long-unicode"):
                    self.assertGreater(len(row["materialPath"].encode()), 4096)
                else:
                    self.assertLess(len(row["materialPath"].encode()), 64)
                baseline = self.results["valid.mdl" if profile == "0023" else "legacy-valid.mdl"]
                for key in ("vertices", "indices", "boundsMinimum", "boundsMaximum", "triangleCount"):
                    self.assertEqual(row[key], baseline[key])
            for prefix, message in (("missing-nul", "truncated in material path"),
                                    ("long-invalid-utf8", "invalid static mdl material path"),
                                    ("long-parent", "invalid static mdl material path"),
                                    ("long-control", "invalid static mdl material path"),
                                    ("long-truncated", "truncated")):
                row = self.results[f"{prefix}-{profile}.mdl"]
                self.assertFalse(row["ok"], row)
                self.assertIn(message, row["error"])
                self.assertNotIn("parts", row)
                self.assertNotIn("materialPaths", row)

    def test_legacy_profile_derives_bounds_from_validated_vertices(self) -> None:
        result = self.results["legacy-valid.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["version"], "MDLV0016")
        self.assertEqual(
            result["materialPath"],
            "materials/models/fixture/legacy.json",
        )
        self.assertEqual(result["boundsMinimum"], [-1, -1, 0])
        self.assertEqual(result["boundsMaximum"], [1, 1, 0])
        self.assertEqual(result["indices"], [0, 1, 2])

    def test_material_segments_retain_identity_and_local_indices(self) -> None:
        result = self.results["parts.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["materialPaths"], ["materials/first.json", "materials/second.json"])
        self.assertEqual(result["parts"], [
            {"material": "materials/first.json", "indices": [0, 1, 2], "elementSize": 2, "positions": [[-1,-1,0],[1,-1,0],[0,1,0]]},
            {"material": "materials/second.json", "indices": [0, 1, 2], "elementSize": 4, "positions": [[-1,-1,0],[1,-1,0],[0,1,0]]},
        ])
        for name in ("bad-separator.mdl", "short-second.mdl", "bad-second-index.mdl"):
            self.assertFalse(self.results[name]["ok"], self.results[name])

    def test_wide_indices_preserve_values_and_validate_ranges(self) -> None:
        for name, indices in (("uint32-indices.mdl", [0, 1, 2]),
                              ("wide-indices.mdl", [0, 65536, 65537])):
            result = self.results[name]
            self.assertTrue(result["ok"], result)
            self.assertEqual(result["indexElementSize"], 4)
            self.assertEqual(result["indices"], indices)
        for name, token in (("bad-wide-index.mdl", "4294967295"),
                            ("partial-wide-triangle.mdl", "index byte count")):
            self.assertFalse(self.results[name]["ok"])
            self.assertIn(token, self.results[name]["error"])

    def test_unsupported_versions_flags_and_counts_fail_closed(self) -> None:
        for name, token in (
            ("old-version.mdl", "magic MDLV0015"),
            ("bad-nul.mdl", "magic MDLV0023"),
            ("bad-header-format.mdl", "header format 14"),
            ("multi-mesh.mdl", "mesh count 2"),
            ("zero-material.mdl", "material count 0"),
            ("legacy-multipart.mdl", "material count 2"),
            ("unknown-indices.mdl", "index flag 2"),
            ("bad-vertex-format.mdl", "vertex format 7"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_invalid_paths_bounds_and_vertex_values_fail_closed(self) -> None:
        for name, token in (
            ("unsafe-material.mdl", "material path"),
            ("invalid-utf8-material.mdl", "material path"),
            ("nan-bounds.mdl", "bounds"),
            ("inverted-bounds.mdl", "bounds"),
            ("nan-vertex.mdl", "non-finite"),
            ("outside-bounds.mdl", "out of range"),
            ("extreme-channel.mdl", "out of range"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_each_immutable_vertex_channel_rejects_nonfinite_values(self) -> None:
        for profile in ("0023", "0016"):
            for channel in VERTEX_CHANNELS:
                for label, _ in NONFINITE_VALUES:
                    name = f"nonfinite-{profile}-{channel}-{label}.mdl"
                    with self.subTest(profile=profile, channel=channel, value=label):
                        result = self.results[name]
                        self.assertFalse(result["ok"], result)
                        self.assertIn("non-finite", result["error"])
                        self.assertEqual(self.sliced_results[name], result)

    def test_empty_or_invalid_geometry_fails_closed(self) -> None:
        for name, token in (
            ("empty-vertices.mdl", "vertex byte count"),
            ("bad-vertex-bytes.mdl", "vertex byte count"),
            ("vertex-budget.mdl", "vertex byte budget"),
            ("bad-index.mdl", "exceeds vertex count"),
            ("non-triangle-indices.mdl", "index byte count"),
            ("index-budget.mdl", "index byte budget"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_truncation_nonzero_trailer_and_extra_tail_fail_closed(self) -> None:
        for name in (
            "truncated.mdl",
            "nonzero-trailer.mdl",
            "extra-tail.mdl",
            "legacy-nonzero-trailer.mdl",
            "legacy-extra-tail.mdl",
        ):
            with self.subTest(name=name):
                self.assertFalse(self.results[name]["ok"], self.results[name])


if __name__ == "__main__":
    unittest.main()
