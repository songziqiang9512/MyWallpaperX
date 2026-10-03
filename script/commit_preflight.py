#!/usr/bin/env python3
"""Optional staged-index preflight. Never stages, commits, builds or runs tests."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = '# MyWallpaperX optional preflight v1'
AREAS = {'App', 'Video', 'Web', 'Scene', 'Steam', 'Shared', 'Governance', 'Build', 'Release'}


def git(root: Path, *args: str, input: str | None = None) -> str:
    output = subprocess.check_output(['git', *args], cwd=root, input=input, text=True)
    return output if '-z' in args else output.removesuffix('\n')


def area_trailers(message: str, root: Path = ROOT) -> list[str]:
    parsed = git(root, 'interpret-trailers', '--parse', input=message)
    areas = set()
    for line in parsed.splitlines():
        key, _, value = line.partition(':')
        if key.casefold() == 'area':
            areas.update(part.strip() for part in value.split(',') if part.strip())
    unknown = areas - AREAS
    if unknown:
        raise ValueError(f'Unknown Area trailer values: {sorted(unknown)}')
    return sorted(areas)


def owned_paths(values: list[str]) -> set[str]:
    result = set()
    for value in values:
        path = PurePosixPath(value)
        if not value or path.is_absolute() or '..' in path.parts or path.as_posix() != value:
            raise ValueError(f'Owned path must be exact and repository-relative: {value!r}')
        result.add(value)
    return result


def inspect(root: Path, owned: set[str]) -> dict:
    # No rename folding: both removed and added paths require ownership.
    paths = sorted(filter(None, git(root, 'diff', '--cached', '--name-only', '--no-renames', '-z').split('\0')))
    findings = []
    if paths and not owned:
        findings.append('No owned paths supplied; staged ownership is unverified.')
    outside = sorted(set(paths) - owned)
    if owned and outside:
        findings.append('Staged paths outside this batch: ' + ', '.join(outside))
    objects = {}
    for path in paths:
        if not path.endswith('.json'):
            continue
        result = subprocess.run(['git', 'show', f':{path}'], cwd=root, capture_output=True, text=True)
        if result.returncode:  # deletion from the index
            if not git(root, 'ls-files', '--', path):
                continue
            findings.append(f'Cannot read staged JSON: {path}')
            continue
        try:
            objects[path] = json.loads(result.stdout)
        except (ValueError, TypeError) as error:
            findings.append(f'Invalid staged JSON {path}: {error}')
    if 'script/scene_validation_gates.json' in objects:
        registry = objects['script/scene_validation_gates.json']
        gates = registry.get('gates') if isinstance(registry, dict) else None
        required = {'risk', 'trigger', 'cost', 'retirement'}
        if not isinstance(gates, dict) or not gates or not isinstance(registry.get('method_gates'), dict):
            findings.append('Malformed staged gate registry')
            return {'stagedPaths': paths, 'unownedPaths': outside, 'findings': findings}
        for key, value in gates.items():
            if not isinstance(value, dict) or not all(isinstance(value.get(field), str) and value[field].strip() for field in required) or not isinstance(value.get('serialized'), bool):
                findings.append(f'Incomplete staged gate lifecycle: {key}')
        for key in registry.get('method_gates', {}):
            if key not in gates:
                findings.append(f'Staged method gate is not registered: {key}')
    return {'stagedPaths': paths, 'unownedPaths': outside if owned else paths,
            'findings': findings, 'scope': 'Staged ownership, JSON syntax and gate lifecycle only; no product validation.'}


def hook_content(payload_digest: str | None = None) -> str:
    # The owned snapshot lives in the common Git directory, not a removable
    # worktree. main still resolves the committing worktree and its index.
    if payload_digest is None:
        payload_digest = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    return ('#!/bin/sh\n' + MARKER + '\n# payload-sha256: ' + payload_digest + '\n'
            'exec python3.12 -B "$(dirname "$0")/commit_preflight.py"\n')


def config_value(root: Path, *scope: str) -> str | None:
    result = subprocess.run(['git', 'config', *scope, '--get', 'core.hooksPath'],
                            cwd=root, capture_output=True, text=True)
    if result.returncode == 1:
        return None
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return result.stdout.removesuffix('\n')


def install(root: Path, remove: bool = False) -> str:
    common = Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
    directory = common / 'mwx-preflight-hooks'
    hook = directory / 'pre-commit'
    payload = directory / 'commit_preflight.py'
    current = config_value(root, '--local')
    effective = config_value(root)
    if directory.is_symlink() or hook.is_symlink() or payload.is_symlink():
        raise ValueError('Refusing symlink hook ownership')
    if directory.exists() and (not directory.is_dir() or any(p.name not in {'pre-commit', 'commit_preflight.py'} for p in directory.iterdir())):
        raise ValueError('Existing hook directory contains unowned entries')
    if hook.exists() or payload.exists():
        if not hook.is_file() or not payload.is_file():
            raise ValueError('Existing hook differs from the exact owned content')
        recorded = re.search(r'^# payload-sha256: ([0-9a-f]{64})$', hook.read_text(), re.M)
        if (recorded is None or hook.read_text() != hook_content(recorded[1])
                or hashlib.sha256(payload.read_bytes()).hexdigest() != recorded[1]):
            raise ValueError('Existing hook differs from the exact owned content')
    if remove:
        if current != str(directory) or effective != current or not hook.is_file():
            raise ValueError('Refusing to remove an unowned hooks configuration')
        git(root, 'config', '--local', '--unset', 'core.hooksPath')
        hook.unlink()
        payload.unlink()
        directory.rmdir()
        return 'Removed this optional hook and its local configuration.'
    if effective is not None and (effective != str(directory) or current != effective):
        raise ValueError(f'Existing effective hooksPath is preserved: {effective}')
    # core.hooksPath replaces the complete hook directory, including commit-msg
    # and post-* hooks. Preserve every existing default hook, not only ours.
    defaults = common / 'hooks'
    if defaults.exists() and any(not p.name.endswith('.sample') for p in defaults.iterdir()):
        raise ValueError('Existing default hooks are preserved; installation would bypass them')
    directory.mkdir(exist_ok=True)
    snapshot = Path(__file__).read_bytes()
    payload.write_bytes(snapshot)
    hook.write_text(hook_content(hashlib.sha256(snapshot).hexdigest()))
    hook.chmod(0o755)
    git(root, 'config', '--local', 'core.hooksPath', str(directory))
    return 'Installed optional warning-only hook. Local core.hooksPath affects all worktrees sharing this repository config.'


def main(argv=None, *, root: Path | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owned-path', action='append', default=[])
    parser.add_argument('--owned-file', default=os.environ.get('MWX_OWNED_PATHS'), help='JSON array of exact batch paths')
    parser.add_argument('--strict', action='store_true', help='reject findings instead of warning only')
    parser.add_argument('--message-file', help='read-only Area trailer validation')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--install', action='store_true')
    mode.add_argument('--uninstall', action='store_true')
    args = parser.parse_args(argv)
    try:
        root = root if root is not None else Path(git(Path.cwd(), 'rev-parse', '--show-toplevel'))
        if args.install or args.uninstall:
            print(install(root, args.uninstall)); return 0
        values = list(args.owned_path)
        if args.owned_file:
            supplied = json.loads(Path(args.owned_file).read_text())
            if not isinstance(supplied, list) or not all(isinstance(v, str) for v in supplied):
                raise ValueError('owned-file must be a JSON array of paths')
            values.extend(supplied)
        report = inspect(root, owned_paths(values))
        if args.message_file:
            report['areas'] = area_trailers(Path(args.message_file).read_text(), root)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1 if args.strict and report['findings'] else 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(2, f'commit preflight: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
