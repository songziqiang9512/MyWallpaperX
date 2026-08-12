#!/usr/bin/env python3
"""Read-only binary and virtual-file helpers for the Scene corpus census."""

from __future__ import annotations

import hashlib
import json
import mmap
import os
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Iterable, Iterator


DERIVED_SAMPLE_NAMES = {
    ".DS_Store",
    ".mywallpaperx-scene-interpretation.json",
    ".mywallpaperx-scene-preview-log.txt",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_sha256(value: Any) -> str:
    payload = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return sha256_bytes(payload)


def normalize_path(raw: str) -> str:
    normalized = raw.strip().replace("\\", "/")
    return normalized[2:] if normalized.startswith("./") else normalized


def path_identity(raw: str) -> str:
    return normalize_path(raw).casefold()


def safe_relative_path(raw: str) -> str | None:
    normalized = raw.replace("\\", "/")
    if not normalized or normalized.startswith("/"):
        return None
    if len(normalized) >= 3 and normalized[1:3] == ":/":
        return None
    components = normalized.split("/")
    if any(component in ("", ".", "..") for component in components):
        return None
    return normalized


def tree_manifest(root: Path) -> tuple[str, int, int]:
    digest = hashlib.sha256()
    file_count = 0
    byte_count = 0
    for path in sorted(
        item for item in root.rglob("*") if item.is_file() and not item.is_symlink()
    ):
        if path.name in DERIVED_SAMPLE_NAMES:
            continue
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256_file(path).encode("ascii"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\n")
        file_count += 1
        byte_count += size
    return digest.hexdigest(), file_count, byte_count


def directory_manifest(root: Path) -> tuple[str, int, int]:
    """Hash a read-only resource tree without retaining machine-local paths."""
    digest = hashlib.sha256()
    file_count = 0
    byte_count = 0
    for path in sorted(
        item for item in root.rglob("*") if item.is_file() and not item.is_symlink()
    ):
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256_file(path).encode("ascii"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\n")
        file_count += 1
        byte_count += size
    return digest.hexdigest(), file_count, byte_count


@dataclass(frozen=True)
class PkgEntry:
    index: int
    path: str
    offset: int
    size: int


class PkgArchive:
    """Bounded PKGV index reader that never extracts or mutates the package."""

    maximum_entry_count = 1_000_000
    maximum_path_byte_count = 1_048_576

    def __init__(self, path: Path) -> None:
        self.path = path
        self._handle = path.open("rb")
        self._mapping = mmap.mmap(self._handle.fileno(), 0, access=mmap.ACCESS_READ)
        self.magic = ""
        self.entries: list[PkgEntry] = []
        self.data_start = 0
        self.diagnostics: list[dict[str, Any]] = []
        self._by_identity: dict[str, list[PkgEntry]] = {}
        try:
            self._parse_index()
        except Exception:
            self.close()
            raise

    def __enter__(self) -> PkgArchive:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        mapping = getattr(self, "_mapping", None)
        if mapping is not None:
            mapping.close()
            self._mapping = None  # type: ignore[assignment]
        handle = getattr(self, "_handle", None)
        if handle is not None:
            handle.close()
            self._handle = None  # type: ignore[assignment]

    @property
    def file_size(self) -> int:
        return len(self._mapping)

    def _u32(self, offset: int) -> int:
        if offset < 0 or offset + 4 > len(self._mapping):
            raise ValueError("truncated PKGV integer")
        return struct.unpack_from("<I", self._mapping, offset)[0]

    def _parse_index(self) -> None:
        if len(self._mapping) < 16:
            raise ValueError("PKGV package is too small")
        cursor = 0
        magic_length = self._u32(cursor)
        cursor += 4
        if not 1 <= magic_length <= 64 or cursor + magic_length > len(self._mapping):
            raise ValueError("invalid PKGV magic length")
        try:
            self.magic = bytes(self._mapping[cursor:cursor + magic_length]).decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError("invalid PKGV magic encoding") from error
        cursor += magic_length
        if not self.magic.startswith("PKGV"):
            raise ValueError(f"invalid PKGV magic {self.magic!r}")
        entry_count = self._u32(cursor)
        cursor += 4
        if entry_count > self.maximum_entry_count:
            raise ValueError("PKGV entry count exceeds the census budget")

        raw_entries: list[tuple[int, str, int, int]] = []
        for index in range(entry_count):
            path_length = self._u32(cursor)
            cursor += 4
            if (
                not 1 <= path_length <= self.maximum_path_byte_count
                or cursor + path_length > len(self._mapping)
            ):
                raise ValueError("invalid PKGV path length")
            try:
                path = bytes(self._mapping[cursor:cursor + path_length]).decode("utf-8")
            except UnicodeDecodeError as error:
                raise ValueError("invalid PKGV path encoding") from error
            cursor += path_length
            offset = self._u32(cursor)
            size = self._u32(cursor + 4)
            cursor += 8
            raw_entries.append((index, path, offset, size))

        self.data_start = cursor
        payload_size = len(self._mapping) - self.data_start
        ranges: list[tuple[int, int, str]] = []
        for index, raw_path, offset, size in raw_entries:
            end = offset + size
            if end > payload_size:
                raise ValueError(
                    f"PKGV entry is out of bounds: {raw_path} offset={offset} size={size}"
                )
            normalized = raw_path.replace("\\", "/")
            entry = PkgEntry(index=index, path=normalized, offset=offset, size=size)
            self.entries.append(entry)
            if safe_relative_path(normalized) is None:
                self.diagnostics.append({
                    "code": "unsafe-package-path",
                    "entry_index": index,
                    "path_sha256": sha256_bytes(normalized.encode("utf-8")),
                })
            else:
                self._by_identity.setdefault(path_identity(normalized), []).append(entry)
            if size == 0:
                self.diagnostics.append({
                    "code": "zero-size-package-entry",
                    "entry_index": index,
                    "path": normalized,
                })
            if size > 0:
                ranges.append((offset, end, normalized))

        for identity, matches in sorted(self._by_identity.items()):
            if len(matches) > 1:
                self.diagnostics.append({
                    "code": "duplicate-package-path",
                    "path": matches[-1].path,
                    "entry_indices": [entry.index for entry in matches],
                    "content_equal": len({self.entry_sha256(entry) for entry in matches}) == 1,
                })

        case_forms: dict[str, set[str]] = {}
        for entry in self.entries:
            if safe_relative_path(entry.path) is not None:
                case_forms.setdefault(path_identity(entry.path), set()).add(entry.path)
        for forms in case_forms.values():
            if len(forms) > 1:
                self.diagnostics.append({
                    "code": "case-colliding-package-path",
                    "paths": sorted(forms),
                })

        ranges.sort()
        previous: tuple[int, int, str] | None = None
        for current in ranges:
            if previous is not None and current[0] < previous[1]:
                exact = current[0] == previous[0] and current[1] == previous[1]
                self.diagnostics.append({
                    "code": "exact-overlapping-package-entry" if exact else "partial-package-overlap",
                    "paths": [previous[2], current[2]],
                })
            if previous is None or current[1] > previous[1]:
                previous = current

    def matches(self, path: str) -> list[PkgEntry]:
        return list(self._by_identity.get(path_identity(path), []))

    def entry(self, path: str) -> PkgEntry | None:
        matches = self.matches(path)
        return matches[-1] if matches else None

    def read_entry(self, entry_or_path: PkgEntry | str) -> bytes | None:
        entry = entry_or_path if isinstance(entry_or_path, PkgEntry) else self.entry(entry_or_path)
        if entry is None:
            return None
        start = self.data_start + entry.offset
        return bytes(self._mapping[start:start + entry.size])

    def read_at(self, entry: PkgEntry, offset: int, size: int) -> bytes:
        if offset < 0 or size < 0 or offset + size > entry.size:
            raise ValueError("PKGV entry-relative read is out of bounds")
        start = self.data_start + entry.offset + offset
        return bytes(self._mapping[start:start + size])

    def entry_sha256(self, entry: PkgEntry) -> str:
        digest = hashlib.sha256()
        start = self.data_start + entry.offset
        remaining = entry.size
        while remaining:
            size = min(1024 * 1024, remaining)
            digest.update(self._mapping[start:start + size])
            start += size
            remaining -= size
        return digest.hexdigest()


@dataclass(frozen=True)
class ResolvedResource:
    origin: str
    relative_path: str
    file_path: Path | None = None
    archive: PkgArchive | None = None
    entry: PkgEntry | None = None

    @property
    def size(self) -> int:
        if self.entry is not None:
            return self.entry.size
        if self.file_path is not None:
            return self.file_path.stat().st_size
        return 0

    def read_bytes(self) -> bytes:
        if self.archive is not None and self.entry is not None:
            payload = self.archive.read_entry(self.entry)
            if payload is None:
                raise FileNotFoundError(self.relative_path)
            return payload
        if self.file_path is not None:
            return self.file_path.read_bytes()
        raise FileNotFoundError(self.relative_path)

    def read_at(self, offset: int, size: int) -> bytes:
        if self.archive is not None and self.entry is not None:
            return self.archive.read_at(self.entry, offset, size)
        if self.file_path is not None:
            with self.file_path.open("rb") as handle:
                handle.seek(offset)
                payload = handle.read(size)
            if len(payload) != size:
                raise ValueError("resource-relative read is out of bounds")
            return payload
        raise FileNotFoundError(self.relative_path)

    def sha256(self) -> str:
        if self.archive is not None and self.entry is not None:
            return self.archive.entry_sha256(self.entry)
        if self.file_path is not None:
            return sha256_file(self.file_path)
        raise FileNotFoundError(self.relative_path)


class SceneResourceView:
    """Package -> loose -> stock read-only resource precedence."""

    def __init__(
        self,
        sample_root: Path,
        stock_root: Path,
        archive: PkgArchive,
        json_observer: Callable[[ResolvedResource, Any], None] | None = None,
    ) -> None:
        self.sample_root = sample_root
        self.stock_root = stock_root
        self.archive = archive
        self.json_observer = json_observer

    def resolve(self, raw_path: str, base_dir: str = "") -> ResolvedResource | None:
        path = normalize_path(raw_path)
        candidates: list[str] = []
        if base_dir:
            candidates.append(normalize_path(f"{base_dir}/{path}"))
        candidates.append(path)
        seen: set[str] = set()
        for candidate in candidates:
            identity = path_identity(candidate)
            if identity in seen or safe_relative_path(candidate) is None:
                continue
            seen.add(identity)
            entry = self.archive.entry(candidate)
            if entry is not None:
                return ResolvedResource(
                    origin="package",
                    relative_path=entry.path,
                    archive=self.archive,
                    entry=entry,
                )
            loose = self._contained_file(self.sample_root, candidate)
            if loose is not None:
                return ResolvedResource("loose", candidate, file_path=loose)
            stock = self._contained_file(self.stock_root, candidate)
            if stock is not None:
                return ResolvedResource("stock", candidate, file_path=stock)
        return None

    @staticmethod
    def _contained_file(root: Path, candidate: str) -> Path | None:
        root_resolved = root.resolve()
        path = root / PurePosixPath(candidate)
        try:
            resolved = path.resolve()
            resolved.relative_to(root_resolved)
        except (OSError, ValueError):
            return None
        return resolved if resolved.is_file() else None

    def resolve_json(
        self,
        raw_path: str,
        base_dir: str = "",
    ) -> tuple[Any, ResolvedResource | None, str | None]:
        resource = self.resolve(raw_path, base_dir)
        if resource is None:
            return None, None, "resource-missing"
        try:
            value = decode_json(resource.read_bytes())
        except ValueError as error:
            return None, resource, str(error)
        if self.json_observer is not None:
            self.json_observer(resource, value)
        return value, resource, None

    def resolve_texture(self, raw_reference: str) -> ResolvedResource | None:
        reference = normalize_path(raw_reference)
        extension = PurePosixPath(reference).suffix.casefold()
        candidates = [reference]
        if extension not in {".tex", ".png", ".jpg", ".jpeg"}:
            candidates = [
                f"materials/{reference}.tex",
                f"materials/{reference}.png",
                f"materials/{reference}.jpg",
                f"materials/{reference}.jpeg",
                f"{reference}.tex",
                f"{reference}.png",
                f"{reference}.jpg",
                f"{reference}.jpeg",
            ]
        for candidate in candidates:
            resource = self.resolve(candidate)
            if resource is not None:
                self._observe_texture_sidecar(resource)
                return resource
        return None

    def _observe_texture_sidecar(self, texture: ResolvedResource) -> None:
        if self.json_observer is None:
            return
        path = normalize_path(texture.relative_path)
        if PurePosixPath(path).suffix.casefold() != ".tex":
            return
        sidecar = self.resolve(f"{path[:-4]}.tex-json")
        if sidecar is None:
            return
        try:
            value = decode_json(sidecar.read_bytes())
        except ValueError:
            return
        self.json_observer(sidecar, value)


def decode_json(payload: bytes) -> Any:
    for encoding in ("utf-8-sig", "utf-16", "latin-1"):
        try:
            return json.loads(payload.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    raise ValueError("json-decode-failed")


def parse_tex_summary(resource: ResolvedResource) -> dict[str, Any]:
    """Parse TEX structure without decoding or retaining image payload bytes."""

    def read(offset: int, size: int) -> bytes:
        return resource.read_at(offset, size)

    def u32(offset: int) -> int:
        return struct.unpack("<I", read(offset, 4))[0]

    def i32(offset: int) -> int:
        return struct.unpack("<i", read(offset, 4))[0]

    def c_string_end(offset: int) -> int:
        cursor = offset
        while cursor < resource.size:
            chunk_size = min(4096, resource.size - cursor)
            chunk = read(cursor, chunk_size)
            hit = chunk.find(b"\0")
            if hit >= 0:
                return cursor + hit + 1
            cursor += chunk_size
        raise ValueError("unterminated TEX metadata string")

    try:
        if resource.size < 55 or read(0, 18) != b"TEXV0005\0TEXI0001\0":
            raise ValueError("invalid TEXV0005/TEXI0001 header")
        volume_header = (
            resource.size >= 59
            and read(58, 1) == b"\0"
            and read(50, 8).startswith(b"TEXB")
        )
        marker_offset = 50 if volume_header else 46
        marker = read(marker_offset, 8).decode("ascii")
        if marker not in {"TEXB0001", "TEXB0002", "TEXB0003", "TEXB0004"}:
            raise ValueError("unsupported TEXB marker")
        if read(marker_offset + 8, 1) != b"\0":
            raise ValueError("unterminated TEXB marker")

        format_code = u32(18)
        flags = u32(22)
        texture_width = u32(26)
        texture_height = u32(30)
        image_width = u32(34)
        image_height = u32(38)
        texture_depth = u32(42) if volume_header else 1
        cursor = marker_offset + 9
        image_count = u32(cursor)
        cursor += 4
        if not 1 <= image_count <= 512:
            raise ValueError("invalid TEX image count")

        free_image_format = -1
        metadata_entry_count = 0
        effective_marker = marker
        if marker == "TEXB0003":
            free_image_format = i32(cursor)
            cursor += 4
        elif marker == "TEXB0004":
            free_image_format = i32(cursor)
            metadata_entry_count = u32(cursor + 4)
            cursor += 8
            if metadata_entry_count > 32:
                raise ValueError("TEX metadata count exceeds the census budget")
            if metadata_entry_count == 0:
                effective_marker = "TEXB0003"

        mip_counts: list[int] = []
        compression_codes: set[int] = set()
        first_mips: list[dict[str, int]] = []
        for _ in range(image_count):
            mip_count = u32(cursor)
            cursor += 4
            if not 1 <= mip_count <= 32:
                raise ValueError("invalid TEX mip count")
            mip_counts.append(mip_count)
            for mip_index in range(mip_count):
                if effective_marker == "TEXB0004":
                    for _ in range(metadata_entry_count):
                        cursor += 8
                        cursor = c_string_end(cursor)
                        cursor += 4
                width = u32(cursor)
                height = u32(cursor + 4)
                cursor += 8
                depth = u32(cursor) if volume_header else 1
                if volume_header:
                    cursor += 4
                if width == 0 or height == 0 or depth == 0:
                    raise ValueError("invalid TEX mip extent")
                compression = 0
                decoded_size = 0
                if effective_marker != "TEXB0001":
                    compression = u32(cursor)
                    decoded_size = i32(cursor + 4)
                    cursor += 8
                stored_size = i32(cursor)
                cursor += 4
                if stored_size < 0 or cursor + stored_size > resource.size:
                    raise ValueError("invalid TEX stored byte count")
                compression_codes.add(compression)
                if mip_index == 0:
                    first_mips.append({
                        "width": width,
                        "height": height,
                        "depth": depth,
                        "stored_bytes": stored_size,
                        "decoded_bytes": decoded_size,
                    })
                cursor += stored_size

        sprite_version = None
        sprite_frame_count = 0
        if flags & 4:
            sprite_version = read(cursor, 8).decode("ascii")
            if sprite_version not in {"TEXS0001", "TEXS0002", "TEXS0003"}:
                raise ValueError("unsupported TEX sprite marker")
            if read(cursor + 8, 1) != b"\0":
                raise ValueError("unterminated TEX sprite marker")
            cursor += 9
            sprite_frame_count = i32(cursor)
            cursor += 4
            if not 0 <= sprite_frame_count <= 65_536:
                raise ValueError("invalid TEX sprite frame count")
            if sprite_version == "TEXS0003":
                cursor += 8
            cursor += sprite_frame_count * 32
            if cursor > resource.size:
                raise ValueError("truncated TEX sprite table")

        return {
            "state": "parsed",
            "container_version": marker,
            "effective_container_version": effective_marker,
            "format_code": format_code,
            "flags": flags,
            "texture_extent": [texture_width, texture_height, texture_depth],
            "image_extent": [image_width, image_height],
            "image_count": image_count,
            "mip_counts": mip_counts,
            "first_mips": first_mips,
            "compression_codes": sorted(compression_codes),
            "free_image_format": free_image_format,
            "is_video_mp4": marker == "TEXB0004" and metadata_entry_count == 1,
            "is_volume": volume_header or texture_depth > 1,
            "is_animated": bool(flags & 4),
            "sprite_version": sprite_version,
            "sprite_frame_count": sprite_frame_count,
        }
    except (UnicodeDecodeError, struct.error, ValueError) as error:
        return {
            "state": "malformed",
            "diagnostic": str(error),
        }


def package_category(path: str) -> str:
    normalized = normalize_path(path).casefold()
    first = normalized.split("/", 1)[0]
    extension = PurePosixPath(normalized).suffix
    if extension == ".tex" or extension == ".tex-json":
        return "texture"
    if extension in {".frag", ".vert", ".comp", ".inc"} or first == "shaders":
        return "shader"
    if first in {
        "effects",
        "particles",
        "materials",
        "models",
        "fonts",
        "sounds",
        "images",
        "img",
        "textures",
    }:
        return first.rstrip("s")
    if extension == ".json":
        return "json"
    return extension.lstrip(".") or "other"


def atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        temporary.write_bytes(payload)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def ensure_outputs_outside_roots(outputs: Iterable[Path], roots: Iterable[Path]) -> None:
    expanded_roots = [root.expanduser() for root in roots]
    lexical_roots = [Path(os.path.abspath(root)) for root in expanded_roots]
    resolved_roots = [root.resolve() for root in expanded_roots]
    for output in outputs:
        expanded = output.expanduser()
        lexical_candidate = Path(os.path.abspath(expanded))
        resolved_candidate = expanded.resolve()
        resolved_parent = expanded.parent.resolve()
        for lexical_root, resolved_root in zip(lexical_roots, resolved_roots):
            candidates = (lexical_candidate, resolved_candidate, resolved_parent)
            if any(_path_is_within(candidate, root) for candidate, root in (
                (lexical_candidate, lexical_root),
                (resolved_candidate, resolved_root),
                (resolved_parent, resolved_root),
            )):
                raise ValueError(
                    f"refusing to write census output inside read-only input root: {resolved_root}"
                )


def _path_is_within(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
    except ValueError:
        return False
    return True


def iter_numeric_sample_directories(root: Path) -> Iterator[Path]:
    yield from sorted(
        (
            item
            for item in root.iterdir()
            if item.is_dir() and not item.is_symlink() and item.name.isdigit()
        ),
        key=lambda item: item.name,
    )
