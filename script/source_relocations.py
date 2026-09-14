"""Recognize exact-content source moves without staging or relaxing ratchets."""
from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path
from typing import Iterable


def unchanged_source_relocations(
    root: Path, base_ref: str, old_paths: Iterable[str], candidates: Iterable[str]
) -> dict[str, str]:
    by_digest: dict[bytes, list[str]] = {}
    for path in sorted(set(candidates)):
        source = root / path
        if source.is_file():
            digest = hashlib.sha256(source.read_bytes()).digest()
            by_digest.setdefault(digest, []).append(path)
    result: dict[str, str] = {}
    claimed: set[str] = set()
    for old in sorted(set(old_paths)):
        if (root / old).exists():
            continue  # A copy cannot transfer a historical exception.
        blob = subprocess.run(
            ["git", "show", f"{base_ref}:{old}"], cwd=root,
            capture_output=True, check=False,
        )
        if blob.returncode != 0:
            continue
        matches = by_digest.get(hashlib.sha256(blob.stdout).digest(), [])
        if len(matches) == 1 and matches[0] not in claimed:
            result[old] = matches[0]
            claimed.add(matches[0])
    return result
