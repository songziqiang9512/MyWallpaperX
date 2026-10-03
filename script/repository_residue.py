#!/usr/bin/env python3
"""Read-only inventory of session residue in product source; never delete evidence."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SESSION_DIRECTORIES = {'.mimosa'}


def inventory(root: Path) -> list[dict]:
    found = []
    for source in ('MyWallpaperX', 'WallpaperDaemonSources'):
        for directory, dirs, _ in os.walk(root / source, followlinks=False):
            for name in sorted(set(dirs) & SESSION_DIRECTORIES):
                path = Path(directory) / name
                if path.is_symlink():
                    found.append({'path': path.relative_to(root).as_posix(), 'files': 0,
                                  'bytes': 0, 'symlinks': 1,
                                  'disposition': 'preserve link; target not traversed'})
                    dirs.remove(name)
                    continue
                files, size, links = 0, 0, 0
                for nested, _, names in os.walk(path, followlinks=False):
                    for item in names:
                        file = Path(nested) / item
                        if file.is_symlink(): links += 1
                        elif file.is_file(): files += 1; size += file.stat().st_size
                found.append({'path': path.relative_to(root).as_posix(), 'files': files,
                              'bytes': size, 'symlinks': links,
                              'disposition': 'preserve; identify owner or relocate with exact manifest'})
                dirs.remove(name)
            dirs[:] = sorted(d for d in dirs if not (Path(directory) / d).is_symlink())
    return sorted(found, key=lambda row: row['path'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='reject session residue in product source')
    args = parser.parse_args()
    rows = inventory(ROOT)
    print(json.dumps({'residue': rows, 'boundary': 'Directory names, sizes and counts only; no payload interpretation or deletion.'}, ensure_ascii=False, indent=2))
    return int(args.check and bool(rows))


if __name__ == '__main__': raise SystemExit(main())
