"""Authored reflection media and independent readback for Scene runtime gates."""
from __future__ import annotations

import json
import math
from pathlib import Path
import struct
import zlib

from script.tests.scene.test_scene_static_model_reader import build_model
from script.web.web_benchmark_capture import png_rgb_pixels

CANVAS = (160, 96)
NORMAL_RGB = (230, 128, 204)
ROIS = {"receiver": (80, 48), "lateRed": (140, 48), "greenPeer": (20, 80)}
MODEL_ROIS = {"grazing": (80, 34), "front": (80, 62), "unoccludedBlue": (80, 48),
              "historyRed": (119, 48), "opaquePeer": (45, 68), "exterior": (67, 48)}
PIXEL_TOLERANCE = 4

def rgba_png(rgb: tuple[int, int, int]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    scanlines = (b"\0" + bytes((*rgb, 255)) * 4) * 4
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def fixture_entries(reflection: int) -> dict[str, bytes]:
    # Runtime/Frame/SceneRenderDescriptor preserves objects.map(id) as order.
    # The receiver precedes this red suffix and does not overlap it.
    scene = {
        "version": 3,
        "general": {
            "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
            "clearcolor": "0 0 0", "clearenabled": True, "hdr": False,
            "ambientcolor": "0 0 0", "skylightcolor": "0 0 0",
        },
        "objects": [
            {"id": 1, "name": "Default F5 receiver", "image": "models/receiver.json",
             "origin": "80 48 0", "size": "40 40"},
            {"id": 2, "name": "Late red source", "image": "models/util/solidlayer.json",
             "origin": "140 48 0", "size": "40 96", "color": "1 0 0"},
            {"id": 3, "name": "Healthy green peer", "image": "models/util/solidlayer.json",
             "origin": "20 16 0", "size": "12 12", "color": "0 1 0"},
        ],
    }
    material = {"passes": [{
        "shader": "genericimage2", "textures": ["materials/albedo.png", "materials/normal.png"],
        "combos": {"LIGHTING": 0, "NORMALMAP": 1, "REFLECTION": reflection},
        "constantshadervalues": {"reflectivity": 4, "reflectivitydistance": 80,
                                 "roughness": 0, "metallic": 0},
        "blending": "normal", "depthtest": "disabled", "depthwrite": "disabled",
        "cullmode": "nocull",
    }]}
    return {
        "scene.json": json.dumps(scene, sort_keys=True).encode(),
        "models/receiver.json": json.dumps({"material": "materials/receiver.json"}).encode(),
        "materials/receiver.json": json.dumps(material, sort_keys=True).encode(),
        "materials/albedo.png": rgba_png((128, 128, 128)),
        "materials/normal.png": rgba_png(NORMAL_RGB),
    }


def model_reflection_entries(reflection: int, *, reflectivity: int = 1,
                             stem: str = "receiver") -> dict[str, bytes]:
    entries, objects = {}, []
    encode = lambda value: json.dumps(value, sort_keys=True).encode()
    receiver_material = f"materials/{stem}.json"

    def paint(path, rgb, *, shader="genericimage", **authored):
        texture = path.removesuffix(".json") + ".png"
        entries[texture] = rgba_png(rgb)
        entries[path] = encode({"passes": [{"shader": shader, "textures": [texture],
            "combos": {"LIGHTING": 0}, "blending": "normal", "cullmode": "nocull",
            "depthtest": "enabled", "depthwrite": "enabled", **authored}]})

    def mesh(path, material, bounds, z, normal=(0., 0., 1.)):
        x0, y0, x1, y1 = bounds
        vertices = [((x, y, z), normal, (0., 1., 0., 1.), uv)
                    for x, y, uv in ((x0, y0, (0., 0.)), (x1, y0, (1., 0.)),
                                     (x1, y1, (1., 1.)), (x0, y1, (0., 1.)))]
        entries[path] = build_model(vertices=vertices, indices=(0, 2, 1, 0, 3, 2),
            bounds=(x0, y0, z, x1, y1, z), material=material.encode())
        objects.append({"id": 10 + len(objects), "model": path, "origin": "0 96 0",
                        "scale": "1 -1 1", "perspective": True, "castshadow": False})

    paint(receiver_material, (0, 0, 0), shader="generic4",
        combos={"LIGHTING": 0, "NORMALMAP": 0, "REFLECTION": reflection},
        constantshadervalues={"reflectivity": reflectivity, "roughness": 0, "metallic": 0})
    paint("materials/late-blue.json", (0, 0, 255))
    paint("materials/opaque-green.json", (0, 255, 0))
    # The fitted perspective camera preserves the z=0 canvas. Both normals
    # tilt toward the red source, but only the grazing patch should respond
    # strongly. The blue model checks black receiver depth even without history.
    mesh(f"models/{stem}-grazing.mdl", receiver_material, (73, 26, 87, 42), 0,
         (.8146, 0., .58))
    mesh(f"models/{stem}-front.mdl", receiver_material, (73, 54, 87, 70), 0,
         (.12, 0., .9928))
    mesh("models/late-blue.mdl", "materials/late-blue.json", (73, 24, 87, 72), -24)
    mesh("models/opaque-green.mdl", "materials/opaque-green.json", (37, 60, 53, 76), 0)
    objects.append({"id": 30, "image": "models/util/solidlayer.json", "origin": "126 48 0",
                    "size": "72 96", "color": "1 0 0"})
    entries["scene.json"] = encode({"version": 3, "objects": objects, "general": {
        "orthogonalprojection": {"width": CANVAS[0], "height": CANVAS[1]},
        "perspectiveoverridefov": 35, "cameraparallax": False, "bloom": False, "hdr": False,
        "clearcolor": "0 0 0", "clearenabled": True, "ambientcolor": "0 0 0",
        "skylightcolor": "0 0 0"}})
    return entries


def reflection_oracle() -> dict:
    # Independent double calculation for the project's documented F5 profile.
    # Y-down card orientation flips the decoded normal Y; orthographic view is
    # (0,0,1). Reflection travels 80 world units, then uses the scene camera.
    raw = (NORMAL_RGB[0] / 255 * 2 - 1, -(NORMAL_RGB[1] / 255 * 2 - 1),
           NORMAL_RGB[2] / 255 * 2 - 1)
    length = math.sqrt(sum(value * value for value in raw))
    normal = tuple(value / length for value in raw)
    direction = (2 * normal[2] * normal[0], 2 * normal[2] * normal[1],
                 2 * normal[2] * normal[2] - 1)
    sample = (80 + 80 * direction[0], 48 + 80 * direction[1])
    fresnel = .04 + .96 * (1 - abs(normal[2])) ** 5
    return {
        "normal": normal, "direction": direction, "sampleWorld": sample,
        "Ref0": [128, 128, 128], "Ref1": [128 + 255 * 4 * fresnel, 128, 128],
        "lateRed": [255, 0, 0], "greenPeer": [0, 255, 0],
        "receiverHalfExtent": 3, "pixelTolerance": PIXEL_TOLERANCE,
        "sourceRangeForReceiverROI": [sample[0] - 3, sample[0] + 3,
                                       sample[1] - 3, sample[1] + 3],
        "distinguishes": "Current first-consumer prefix is black at this UV; completed suffix is red.",
    }


def measure_capture(path: Path, rois: dict | None = None) -> dict:
    decoded = png_rgb_pixels(path)
    if decoded is None:
        raise AssertionError(f"undecodable capture: {path}")
    width, height, rows = decoded
    scale = max(width / CANVAS[0], height / CANVAS[1])
    measurements = {"size": [width, height], "coverScale": scale}
    for label, (world_x, world_y) in (ROIS if rois is None else rois).items():
        center_x = width / 2 + (world_x - CANVAS[0] / 2) * scale
        center_y = height / 2 + (world_y - CANVAS[1] / 2) * scale
        radius = 3 * scale
        bounds = (math.ceil(center_x - radius), math.ceil(center_y - radius),
                  math.floor(center_x + radius), math.floor(center_y + radius))
        x0, y0, x1, y1 = bounds
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            raise AssertionError(f"declared {label} ROI cropped: {bounds}, capture={width}x{height}")
        samples = [rows[y][x * 3:x * 3 + 3] for y in range(y0, y1) for x in range(x0, x1)]
        measurements[label] = {
            "bounds": bounds, "count": len(samples),
            "mean": [sum(pixel[c] for pixel in samples) / len(samples) for c in range(3)],
            "minimum": [min(pixel[c] for pixel in samples) for c in range(3)],
            "maximum": [max(pixel[c] for pixel in samples) for c in range(3)],
        }
    return measurements
