"""Execute the preparation-only WebM reader against authored format inputs."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format/SceneWebMContainer.swift"


def vint(value: int, width: int | None = None) -> bytes:
    if width is None:
        width = next(n for n in range(1, 9) if value < (1 << (7 * n)) - 1)
    return (value | 1 << (7 * width)).to_bytes(width, "big")


def element(identifier: int, payload: bytes, *, unknown: bool = False) -> bytes:
    raw_id = identifier.to_bytes((identifier.bit_length() + 7) // 8, "big")
    return raw_id + (b"\x01" + b"\xff" * 7 if unknown else vint(len(payload))) + payload


def uint(identifier: int, value: int) -> bytes:
    return element(identifier, value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big"))


def vp9(*, profile: int = 0, depth: int = 8, color: int = 0,
        full: bool = False, width: int = 16, height: int = 8,
        key: bool = True, show: bool = True, x: int = 0, y: int = 0) -> bytes:
    bits: list[int] = []

    def write(value: int, count: int) -> None:
        bits.extend((value >> shift) & 1 for shift in range(count - 1, -1, -1))

    write(2, 2)
    write(profile & 1, 1)
    write(profile >> 1, 1)
    if profile == 3:
        write(0, 1)
    write(0, 1)  # show_existing_frame
    write(not key, 1)
    write(show, 1)
    write(1, 1)  # error_resilient
    if key:
        write(0x498342, 24)
        if profile >= 2:
            write(depth == 12, 1)
        write(color, 3)
        if color != 7:
            write(full, 1)
            if profile & 1:
                write(x, 1)
                write(y, 1)
                write(0, 1)
        elif profile & 1:
            write(0, 1)
        write(width - 1, 16)
        write(height - 1, 16)
        write(0, 1)  # render size matches
    bits.extend([0] * (-len(bits) % 8))
    return bytes(sum(bits[pos + bit] << (7 - bit) for bit in range(8))
                 for pos in range(0, len(bits), 8)) + b"\x11\x22\x00"


def track(*, extra: bytes = b"", video_extra: bytes = b"",
          colour: bytes = b"", private: bytes | None = None,
          default_duration: int | None = 16_666_666,
          width: int = 16, height: int = 8, codec: str = "V_VP9",
          kind: int = 1) -> bytes:
    payload = uint(0xD7, 1) + uint(0x73C5, 1) + uint(0x83, kind)
    payload += element(0x86, codec.encode())
    if default_duration is not None:
        payload += uint(0x23E383, default_duration)
    if private is not None:
        payload += element(0x63A2, private)
    video = uint(0xB0, width) + uint(0xBA, height) + video_extra
    if colour:
        video += element(0x55B0, colour)
    return element(0xAE, payload + element(0xE0, video) + extra)


def block(payload: bytes, *, relative: int = 0, flags: int = 0x80,
          number: int = 1, group_duration: int | None = None,
          group_extra: bytes = b"", group: bool = False) -> bytes:
    body = vint(number) + struct.pack(">hB", relative, flags) + payload
    if not group:
        return element(0xA3, body)
    body = element(0xA1, body)
    if group_duration is not None:
        body += uint(0x9B, group_duration)
    return element(0xA0, body + group_extra)


def cluster(blocks: bytes, *, timestamp: int = 0, unknown: bool = False) -> bytes:
    return element(0x1F43B675, uint(0xE7, timestamp) + blocks, unknown=unknown)


def webm(*, tracks: bytes | None = None, clusters: bytes | None = None,
         info_extra: bytes = b"", duration: float | None = 40,
         scale: int = 1_000_000, unknown: bool = False,
         segment_extra: bytes = b"", header_extra: bytes = b"",
         doctype: str = "webm") -> bytes:
    header = element(0x4282, doctype.encode()) + uint(0x42F7, 1) + uint(0x4285, 4)
    info = uint(0x2AD7B1, scale) + info_extra
    if duration is not None:
        info += element(0x4489, struct.pack(">d", duration))
    if clusters is None:
        clusters = cluster(block(vp9()))
    segment = element(0x1549A966, info) + element(0x1654AE6B, tracks or track())
    return element(0x1A45DFA3, header + header_extra) + element(
        0x18538067, segment + clusters + segment_extra, unknown=unknown)


HARNESS = r'''
import Foundation
import CryptoKit
@main enum Harness {
    static func main() throws {
        let requests = try JSONSerialization.jsonObject(with:
            Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        var results: [[String: Any]] = []
        for request in requests {
            do {
                var data = try Data(contentsOf: URL(fileURLWithPath: request["path"] as! String))
                if request["slice"] as? Bool == true {
                    data = Data(repeating: 7, count: 7) + data
                    data.removeFirst(7)
                }
                var limits = SceneWebMContainer.Limits()
                let values = request["limits"] as? [String: Int] ?? [:]
                if let value = values["payload"] { limits.maximumPayloadBytes = value }
                if let value = values["packet"] { limits.maximumPacketBytes = value }
                if let value = values["packets"] { limits.maximumPackets = value }
                if let value = values["elements"] { limits.maximumElements = value }
                if let value = values["clusters"] { limits.maximumClusters = value }
                if let value = values["dimension"] { limits.maximumDimension = value }
                if let value = values["duration"] { limits.maximumDurationNanoseconds = Int64(value) }
                let cancelled = request["cancel"] as? Bool == true
                let result = try SceneWebMContainer.parse(data, limits: limits) {
                    if cancelled { throw CancellationError() }
                }
                let packets: [[String: Any]] = result.packets.map {
                    let range = (data.startIndex + $0.dataRange.lowerBound)..<(data.startIndex + $0.dataRange.upperBound)
                    return ["pts": $0.presentationTimeNanoseconds, "duration": $0.durationNanoseconds,
                            "key": $0.isKeyframe, "offset": $0.dataRange.lowerBound,
                            "size": $0.dataRange.count,
                            "sha256": SHA256.hash(data: data.subdata(in: range)).map {
                                String(format: "%02x", $0)
                            }.joined()]
                }
                results.append(["width": result.track.width, "height": result.track.height,
                                "number": result.track.number, "scale": result.track.timecodeScaleNanoseconds,
                                "defaultDuration": result.track.defaultDurationNanoseconds as Any? ?? NSNull(),
                                "duration": result.track.durationNanoseconds as Any? ?? NSNull(),
                                "configuration": result.track.vpCodecConfiguration.map {
                                    String(format: "%02x", $0)
                                }.joined(), "packets": packets])
            } catch { results.append(["error": String(describing: error)]) }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneWebMContainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("xcrun"):
            raise unittest.SkipTest("Swift toolchain unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-webm-parser-")
        cls.directory = Path(cls.temporary.name)
        harness = cls.directory / "Harness.swift"
        harness.write_text(HARNESS)
        cls.binary = cls.directory / "reader"
        result = subprocess.run(["xcrun", "swiftc", "-swift-version", "6",
                                 "-default-isolation", "MainActor", "-parse-as-library",
                                 str(SOURCE), str(harness), "-o", str(cls.binary)],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            cls.temporary.cleanup()
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def parse(self, inputs: list[bytes], **options) -> list[dict]:
        requests = []
        for index, value in enumerate(inputs):
            path = self.directory / f"input-{index}.webm"
            path.write_bytes(value)
            requests.append(dict(path=str(path), **options))
        return self.run_requests(requests)

    def run_requests(self, requests: list[dict]) -> list[dict]:
        manifest = self.directory / "requests.json"
        manifest.write_text(json.dumps(requests))
        result = subprocess.run([str(self.binary), str(manifest)], check=True,
                                capture_output=True, text=True, timeout=30)
        return json.loads(result.stdout)

    def rejects(self, inputs: list[bytes], category: str = "unsupported", **options) -> None:
        for index, result in enumerate(self.parse(inputs, **options)):
            with self.subTest(index=index):
                self.assertIn(f"webm-{category}:", result.get("error", ""))

    def test_packet_bytes_timestamps_and_explicit_duration(self) -> None:
        first, second = vp9(), vp9(key=False)
        clusters = cluster(block(first), timestamp=0) + cluster(
            block(second, relative=-10, flags=0, group=True, group_duration=19,
                  group_extra=element(0xFB, b"\xff")), timestamp=27)
        result = self.parse([webm(clusters=clusters)])[0]
        self.assertNotIn("error", result)
        self.assertEqual((result["width"], result["height"], result["scale"]), (16, 8, 1_000_000))
        self.assertEqual(result["configuration"], "010000000000820202020000")
        self.assertEqual([p["pts"] for p in result["packets"]], [0, 17_000_000])
        self.assertEqual([p["duration"] for p in result["packets"]], [16_666_666, 19_000_000])
        self.assertEqual([p["key"] for p in result["packets"]], [True, False])
        self.assertEqual([p["sha256"] for p in result["packets"]],
                         [hashlib.sha256(value).hexdigest() for value in (first, second)])

    def test_unknown_segment_and_cluster_sizes_preserve_next_cluster(self) -> None:
        clusters = cluster(block(vp9()), unknown=True) + cluster(
            block(vp9(key=False), flags=0), timestamp=20, unknown=True)
        result = self.parse([webm(clusters=clusters, unknown=True)])[0]
        self.assertEqual([p["pts"] for p in result["packets"]], [0, 20_000_000])
        self.assertEqual(result["packets"][1]["sha256"], hashlib.sha256(vp9(key=False)).hexdigest())

    def test_duration_inference_requires_final_duration_authority(self) -> None:
        clusters = cluster(block(vp9()) + block(vp9(key=False), relative=17, flags=0))
        result = self.parse([webm(tracks=track(default_duration=None), clusters=clusters)])[0]
        self.assertEqual([p["duration"] for p in result["packets"]], [17_000_000, 23_000_000])
        self.rejects([webm(tracks=track(default_duration=None), duration=None)])

    def test_configuration_comes_from_keyframe_and_track_colour(self) -> None:
        colour = uint(0x55BB, 9) + uint(0x55BA, 16) + uint(0x55B1, 9) + uint(0x55B9, 2)
        high = webm(tracks=track(colour=colour, private=b"\x01\x01\x02\x02\x01\x33\x03\x01\x0a\x04\x01\x01"),
                    clusters=cluster(block(vp9(profile=2, depth=10, color=5, full=True))))
        rgb = webm(clusters=cluster(block(vp9(profile=1, color=7))))
        results = self.parse([high, rgb])
        self.assertEqual(results[0]["configuration"], "010000000233a30910090000")
        self.assertEqual(results[1]["configuration"], "01000000010087010d000000")
        self.rejects([webm(tracks=track(private=b"\x01\x01\x02")),
                      webm(tracks=track(colour=uint(0x55B9, 2))),
                      webm(tracks=track(colour=uint(0x55B1, 9)),
                           clusters=cluster(block(vp9(color=2))))], category="malformed")

    def test_refuses_media_features_that_cannot_be_preserved(self) -> None:
        self.rejects([
            webm(tracks=track(codec="V_VP8")),
            webm(tracks=track(kind=2)),
            webm(tracks=track() + track()),
            webm(tracks=track(video_extra=uint(0x53C0, 1))),
            webm(tracks=track(extra=element(0x6D80, b""))),
            webm(tracks=track(extra=uint(0x56AA, 1))),
            webm(tracks=track(video_extra=uint(0x54B0, 32))),
            webm(clusters=cluster(block(vp9(), flags=0x82))),
            webm(clusters=cluster(block(vp9(), flags=0x88))),
            webm(clusters=cluster(element(0xAF, b"encrypted"))),
            webm(clusters=cluster(block(vp9(), flags=0, group=True,
                                        group_extra=element(0x75A1, b"")))),
            webm(clusters=cluster(block(vp9(show=False)))),
            webm(clusters=cluster(block(vp9() + b"\xc0\x01\xc0"))),
            webm(doctype="matroska"),
            webm(segment_extra=element(0x18538067, b"")),
        ])

    def test_rejects_truncation_vint_and_parent_range_corruption(self) -> None:
        valid = webm()
        malformed = [b"", b"\x00", b"\x1a\x45", valid[:-1],
                     element(0x1A45DFA3, b"\x42\x82\xffwebm"),
                     element(0x1A45DFA3, b"\x42\x82\x88webm"),
                     webm(info_extra=uint(0x2AD7B1, 1)),
                     webm(clusters=cluster(block(vp9(), number=2))),
                     webm(clusters=cluster(block(vp9(), flags=0))),
                     webm(clusters=cluster(block(vp9(), relative=-1))),
                     webm(duration=float("nan")), webm(duration=float("inf")),
                     webm(scale=(1 << 63) - 1, clusters=cluster(block(vp9()), timestamp=2))]
        # Unknown-size fields have a distinct unsupported failure, never an
        # out-of-parent read or an unbounded scan into compressed media.
        self.rejects(malformed[:4] + malformed[5:], category="malformed")
        self.rejects([malformed[4]])
        self.rejects([webm(info_extra=element(0x7BA9, b"", unknown=True))])

    def test_rejects_timing_and_configuration_changes(self) -> None:
        self.rejects([webm(clusters=cluster(block(vp9()) + block(vp9(key=False), flags=0))),
                      webm(clusters=cluster(block(vp9()) + block(vp9(profile=2, depth=10), relative=17))),
                      webm(clusters=cluster(block(vp9(key=False), flags=0)))])
        self.rejects([webm(tracks=track(width=17))], category="malformed")

    def test_work_budgets_and_cancellation(self) -> None:
        pair = webm(clusters=cluster(block(vp9())) + cluster(block(vp9(key=False), flags=0), timestamp=17))
        for limits in [{"payload": 1}, {"packet": 1}, {"packets": 1}, {"elements": 1},
                       {"clusters": 1}, {"dimension": 1}, {"duration": 1}, {"packets": -1}]:
            with self.subTest(limits=limits):
                self.rejects([pair], category="budget", limits=limits)
        self.assertEqual(self.parse([pair], cancel=True)[0]["error"], "CancellationError()")

    def test_nonzero_data_start_index_has_zero_based_packet_ranges(self) -> None:
        ordinary = self.parse([webm()])[0]
        sliced = self.parse([webm()], slice=True)[0]
        self.assertEqual(ordinary, sliced)

    def test_real_webm_optional_packet_hash_and_pts_oracle(self) -> None:
        source = os.environ.get("MWX_WEBM_TEST_SOURCE")
        if not source:
            self.skipTest("set MWX_WEBM_TEST_SOURCE for a read-only real-media check")
        if not shutil.which("ffprobe"):
            self.skipTest("ffprobe is needed only for the optional independent media oracle")
        result = self.run_requests([dict(path=source)])[0]
        self.assertNotIn("error", result)
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_packets", "-show_streams",
                                "-show_entries", "packet=pts_time,size,flags,data_hash:stream=width,height",
                                "-show_data_hash", "sha256", "-of", "json", source],
                               check=True, capture_output=True, text=True, timeout=30)
        reference = json.loads(probe.stdout)
        self.assertEqual((result["width"], result["height"]),
                         (reference["streams"][0]["width"], reference["streams"][0]["height"]))
        self.assertEqual(len(result["packets"]), len(reference["packets"]))
        for packet, expected in zip(result["packets"], reference["packets"]):
            self.assertEqual(packet["sha256"], expected["data_hash"].split(":")[1].lower())
            self.assertEqual(packet["size"], int(expected["size"]))
            self.assertEqual(packet["pts"], round(float(expected["pts_time"]) * 1_000_000_000))
            self.assertEqual(packet["key"], "K" in expected["flags"])
        print(json.dumps({"schema": "webm-parser-oracle-v1", "packets": len(result["packets"]),
                          "configuration": result["configuration"],
                          "dimensions": [result["width"], result["height"]],
                          "scale": result["scale"], "defaultDuration": result["defaultDuration"],
                          "firstPTS": result["packets"][0]["pts"],
                          "lastPTS": result["packets"][-1]["pts"]}, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
