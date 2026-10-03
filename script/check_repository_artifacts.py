#!/usr/bin/env python3
"""Keep generated bulk out of the tracked tool and documentation roots."""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TEXT_ROOTS = ('script', 'docs', '.agents', '.github')
MAX_BYTES = 5_000_000
BASELINE = 'script/repository_artifact_baseline.json'


def exceptions(root: Path) -> dict[str, dict]:
    path = root / BASELINE
    if not path.exists():
        return {}
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or value.get('schemaVersion') != 1 or not isinstance(value.get('exceptions'), list):
        raise ValueError('invalid artifact exception baseline')
    result = {}
    for entry in value['exceptions']:
        if not isinstance(entry, dict):
            raise ValueError('invalid artifact exception')
        name = entry.get('path')
        if not isinstance(name, str):
            raise ValueError('exception requires an exact path')
        relative = PurePosixPath(name)
        if (relative.is_absolute() or '..' in relative.parts or relative.as_posix() != name
                or relative.parts[0] not in TEXT_ROOTS or any(c in name for c in '*?[]') or name in result):
            raise ValueError(f'invalid or duplicate artifact exception: {name}')
        if type(entry.get('maximumBytes')) is not int or entry['maximumBytes'] <= MAX_BYTES:
            raise ValueError('exception must specify a finite byte cap above the normal limit')
        if not all(isinstance(entry.get(key), str) and entry[key].strip() for key in ('owner', 'reason', 'retirement')):
            raise ValueError('exception requires owner, reason and retirement')
        if not (root / name).is_file() or (root / name).stat().st_size <= MAX_BYTES:
            raise ValueError(f'retire stale artifact exception: {name}')
        result[name] = entry
    return result


def inspect(root: Path) -> list[dict]:
    allowed = exceptions(root)
    output = subprocess.check_output([
        'git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', *TEXT_ROOTS
    ], cwd=root)
    violations = []
    for relative in sorted(set(output.decode().split('\0')) - {''}):
        path = root / relative
        if not path.is_file() or path.is_symlink():
            continue
        size = path.stat().st_size
        maximum = allowed.get(relative, {}).get('maximumBytes', MAX_BYTES)
        if size > maximum:
            violations.append({'path': relative, 'bytes': size, 'maximumBytes': maximum})
    return violations


def historical_errors(root: Path, base_ref: str) -> list[str]:
    resolved = subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options',
                                        f'{base_ref}^{{commit}}'], cwd=root, text=True).strip()
    present = subprocess.check_output(['git', 'ls-tree', '-z', resolved, '--', BASELINE], cwd=root)
    if not present:
        return []  # Explicit first adoption; the current metadata still validates.
    previous = json.loads(subprocess.check_output(['git', 'show', f'{resolved}:{BASELINE}'], cwd=root))
    old = {entry['path']: entry for entry in previous['exceptions']}
    errors = []
    for path, entry in exceptions(root).items():
        if path not in old or entry['maximumBytes'] > old[path]['maximumBytes']:
            errors.append(f'artifact exception may only shrink: {path}')
        elif any(entry[key] != old[path][key] for key in ('owner', 'reason', 'retirement')):
            errors.append(f'artifact exception responsibility cannot be silently replaced: {path}')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='read-only check (default)')
    parser.add_argument('--base-ref', default='HEAD', help='independent comparison base for the exception ratchet')
    args = parser.parse_args()
    try:
        violations = inspect(ROOT)
        errors = historical_errors(ROOT, args.base_ref)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(2, f'artifact check: {error}\n')
    print(json.dumps({'roots': TEXT_ROOTS, 'violations': violations, 'historyErrors': errors}, ensure_ascii=False, indent=2))
    return int(bool(violations or errors))


if __name__ == '__main__':
    raise SystemExit(main())
