"""Small generated PKGV fixture writer; no product imports or test execution."""
from __future__ import annotations

import struct


def make_package(entries: list[tuple[str, bytes]]) -> bytes:
    magic = b"PKGV001"
    table = bytearray(struct.pack("<I", len(magic)) + magic)
    table.extend(struct.pack("<I", len(entries)))
    offset = 0
    payload = bytearray()
    for path, value in entries:
        encoded_path = path.encode("utf-8")
        table.extend(struct.pack("<I", len(encoded_path)))
        table.extend(encoded_path)
        table.extend(struct.pack("<II", offset, len(value)))
        payload.extend(value)
        offset += len(value)
    return bytes(table + payload)

