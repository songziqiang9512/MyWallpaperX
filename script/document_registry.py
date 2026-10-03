#!/usr/bin/env python3
"""Query the existing document role index; check complete Git-visible discovery."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
INDEX = Path('docs/document-role-index.json')
HISTORY_ROOTS = ('docs/history', 'docs/scene/history')
ROLES = {'active-plan', 'stable-contract', 'historical-evidence',
         'navigation', 'current-state', 'reference'}
LINK = re.compile(r'!?\[[^\]]*\]\(([^)\n]+)\)')
REQUIRED = {
    'active-plan': ['retirementCondition'],
    'stable-contract': ['currentStateAuthority', 'lastReviewed', 'reviewBasis'],
    'historical-evidence': ['commandPolicy', 'currentAuthorities'],
    'navigation': ['purpose'], 'current-state': ['purpose'],
    'reference': ['purpose', 'commandPolicy'],
}
MARKER = re.compile(r'<!--\s*document-role:\s*(active-plan|stable-contract)\s*-->')
HTML_LINK = re.compile(r'<a\s+[^>]*href=[\"\']([^\"\']+)[\"\']', re.I)


def managed_documents(root: Path) -> set[str]:
    output = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'docs'],
        cwd=root,
    )
    return {p for p in output.decode().split('\0')
            if p.endswith('.md') and (root / p).is_file()}


def local_targets(root: Path, source: str) -> set[str]:
    text = (root / source).read_text(encoding='utf-8')
    targets = set()
    for raw in LINK.findall(text) + HTML_LINK.findall(text):
        raw = raw.strip()
        raw = raw[1:raw.index('>')] if raw.startswith('<') and '>' in raw else raw.split()[0]
        parsed = urlsplit(raw)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        path = ((root / source).parent / unquote(parsed.path)).resolve()
        if path.is_relative_to(root.resolve()):
            targets.add(path.relative_to(root.resolve()).as_posix())
    return targets


def valid_path(path: object) -> bool:
    return (isinstance(path, str) and bool(path) and '\\' not in path
            and not PurePosixPath(path).is_absolute()
            and '..' not in PurePosixPath(path).parts
            and str(PurePosixPath(path)) == path)


def validate(root: Path, index: dict, discovered: set[str] | None = None) -> list[str]:
    errors = []
    if index.get('schemaVersion') != 2 or set(index.get('roleDefinitions', {})) != ROLES:
        errors.append('schemaVersion must be 2 with all six explicit document roles')
    for role, fields in REQUIRED.items():
        if index.get('roleDefinitions', {}).get(role, {}).get('requiredMetadata') != fields:
            errors.append(f'{role}: required metadata schema mismatch')
    documents = index.get('documents', [])
    if not isinstance(documents, list) or any(not isinstance(d, dict) for d in documents):
        return errors + ['documents must be a list of objects']
    paths = [d.get('path') for d in documents]
    if any(not valid_path(p) for p in paths):
        return errors + ['document paths must be normalized repository-relative paths']
    if paths != sorted(set(paths)):
        errors.append('document paths must be unique and sorted')
    discovered = managed_documents(root) if discovered is None else discovered
    errors.extend(f'unregistered Markdown: {p}' for p in sorted(discovered - set(paths)))
    errors.extend(f'indexed Markdown is missing or ignored: {p}' for p in sorted(set(paths) - discovered))
    targets_by_entry = {}
    declared = set()
    for document in documents:
        path, role = document['path'], document.get('role')
        if role not in ROLES:
            errors.append(f'{path}: unknown role {role}')
            continue
        if (any(path.startswith(h + '/') for h in HISTORY_ROOTS)
                and path not in {h + '/README.md' for h in HISTORY_ROOTS}
                and role != 'historical-evidence'):
            errors.append(f'{path}: history cannot acquire current authority')
        for field in REQUIRED[role]:
            value = document.get(field)
            if field == 'reviewBasis':
                if not isinstance(value, dict) or not value:
                    errors.append(f'{path}: missing or invalid {field}')
            elif field == 'currentAuthorities':
                if not isinstance(value, list) or not value:
                    errors.append(f'{path}: missing or invalid {field}')
            elif not isinstance(value, str) or not value.strip():
                errors.append(f'{path}: missing or invalid {field}')
        authorities = document.get('currentAuthorities', []) if role == 'historical-evidence' else [document.get('currentStateAuthority')] if role == 'stable-contract' else []
        if isinstance(authorities, list):
            for authority in authorities:
                if not valid_path(authority) or not (root / authority).is_file():
                    errors.append(f'{path}: authority missing {authority}')
        if (root / path).is_file():
            header = '\n'.join((root / path).read_text(encoding='utf-8').splitlines()[:12])
            marker = MARKER.search(header)
            if marker:
                declared.add(path)
                if marker.group(1) != role:
                    errors.append(f'{path}: header role contradicts index')
            if role in ('active-plan', 'stable-contract') and not marker:
                errors.append(f'{path}: current plan/contract needs header marker')
            if role == 'historical-evidence' and '> **历史证据 — 非现役入口**' not in header:
                errors.append(f'{path}: missing historical banner')
        if role == 'historical-evidence' and document.get('commandPolicy') != 'historical-only':
            errors.append(f'{path}: history commandPolicy must be historical-only')
        if role == 'reference' and document.get('commandPolicy') != 'reference-only':
            errors.append(f'{path}: reference commandPolicy must be reference-only')
        entry = document.get('entrypoint')
        if not valid_path(entry) or not (root / entry).is_file():
            errors.append(f'{path}: missing entrypoint {entry}')
        else:
            if entry not in targets_by_entry:
                targets_by_entry[entry] = local_targets(root, entry)
            if path not in targets_by_entry[entry]:
                errors.append(f'{path}: entrypoint {entry} does not link document')
        if role == 'stable-contract' and (root / path).is_file():
            if document.get('currentStateAuthority') not in local_targets(root, path):
                errors.append(f'{path}: stable contract does not link current-state authority')
    if set(index.get('discovery', {}).get('additionalPaths', [])) != declared:
        errors.append('discovery.additionalPaths must exactly match current role markers')
    routes = index.get('taskRoutes', [])
    route_ids = set()
    for route in routes:
        key = route.get('id')
        if not isinstance(key, str) or not key or key in route_ids:
            errors.append(f'invalid or repeated task route: {key}')
        route_ids.add(key)
        if not route.get('title') or not route.get('verification') or not route.get('documents'):
            errors.append(f'{key}: title, documents and verification are required')
        for path in route.get('documents', []):
            if path not in paths:
                errors.append(f'{key}: unregistered route document {path}')
        for path in route.get('sourcePaths', []):
            if not valid_path(path) or not (root / path).exists():
                errors.append(f'{key}: source path missing {path}')
    errors.extend(validate_routing(root, index))
    return errors


def validate_routing(root: Path, index: dict) -> list[str]:
    """Resolve gate and nearest-test pointers against their existing sole registry."""
    from script.document_health import anchors
    errors = []
    registry_path = root / 'script/scene_validation_gates.json'
    registry = json.loads(registry_path.read_text()) if registry_path.exists() else {'gates': {}, 'path_groups': []}
    groups = {g['id']: g for g in registry['path_groups']}
    covered = set()
    for route in index.get('taskRoutes', []):
        key = route['id']
        covered.update(route.get('documents', []))
        if not route.get('owner') or not route.get('nearestTestGroups') or not route.get('verificationPhases'):
            errors.append(f'{key}: owner, nearestTestGroups and verificationPhases are required')
        first = route.get('firstRead', '')
        path, _, fragment = first.partition('#')
        if path not in route.get('documents', []) or not (root / path).is_file():
            errors.append(f'{key}: firstRead must directly name a route document')
        elif fragment and fragment not in anchors((root / path).read_text()):
            errors.append(f'{key}: firstRead anchor missing')
        for group in route.get('nearestTestGroups', []):
            if group not in groups or not groups[group].get('modules'):
                errors.append(f'{key}: unknown or empty nearest test group {group}')
        for phase in route.get('verificationPhases', []):
            if phase.get('phase') not in ('inner', 'checkpoint', 'integration', 'milestone'):
                errors.append(f'{key}: invalid verification phase')
            if not phase.get('gateRefs') or not isinstance(phase.get('requiredArguments'), list):
                errors.append(f'{key}: phase needs gateRefs and requiredArguments')
            for gate in phase.get('gateRefs', []):
                if gate not in registry['gates']:
                    errors.append(f'{key}: unknown gate reference {gate}')
            if 'targeted-sample' in phase.get('gateRefs', []) and not {'--app', '--sample-id', '--sample-root', '--output-dir'} <= set(phase.get('requiredArguments', [])):
                errors.append(f'{key}: targeted sample requires explicit execution identity arguments')
            if 'matrix-tier-selection' in phase.get('gateRefs', []) and not {'--matrix-tier', '--reason'} <= set(phase.get('requiredArguments', [])):
                errors.append(f'{key}: matrix tier requires tier and reason')
    for document in index['documents']:
        if document['role'] == 'stable-contract' and document['path'] not in covered:
            errors.append(f"{document['path']}: stable contract has no task route")
    evidence = index.get('taskFrequencyEvidence')
    if evidence:
        try:
            if not re.fullmatch(r'[0-9a-f]{40}', evidence['revision']) or evidence['sampleLimit'] != 100:
                raise ValueError('fixed revision/sample limit')
            records = subprocess.check_output(['git', 'log', '-100', '--format=%H%x09%s', evidence['revision']], cwd=root, text=True)
            counts = Counter()
            for line in records.splitlines():
                match = re.match(r'[^()]+\(([^)]+)\):', line.split('\t', 1)[1])
                counts[match[1] if match else 'unclassified'] += 1
            if (len(records.splitlines()) != evidence['sampleCount'] or dict(counts) != evidence['scopeCounts']
                    or hashlib.sha256(records.encode()).hexdigest() != evidence['recordsSHA256']):
                errors.append('task frequency evidence does not match frozen Git sample')
            if evidence['path'] not in {d['path'] for d in index['documents']}:
                errors.append('task frequency evidence must be a registered historical document')
        except (KeyError, ValueError, subprocess.CalledProcessError):
            errors.append('invalid task frequency evidence')
    term_ids = set()
    for term in index.get('terminology', []):
        key = term.get('term')
        if not key or key in term_ids or not term.get('owner'):
            errors.append(f'invalid or duplicate terminology owner: {key}')
        term_ids.add(key)
        path, _, fragment = term.get('authority', '').partition('#')
        if not (root / path).is_file() or not fragment or fragment not in anchors((root / path).read_text()):
            errors.append(f'{key}: terminology authority must name a real anchor')
    if index.get('routingContract') == 'repository-task-routing-v1':
        required_terms = {'S0-S5', 'E-*', 'named source taxonomy', 'recognized/wired', 'owned paths', '家族/防御面'}
        if term_ids != required_terms:
            errors.append('repository terminology must preserve all six unique authority routes')
        if not evidence:
            errors.append('repository routing needs frozen frequency evidence')
    for pointer in index.get('pointerEntrypoints', []):
        path = pointer['path']
        lines = (root / path).read_text().splitlines()
        if pointer.get('maxLines') != 10 or len(lines) > 10:
            errors.append(f'{path}: pointer AGENTS must stay within 10 lines')
        content = [line for line in lines if line.strip()]
        if not content or not content[0].startswith('# ') or any(not re.fullmatch(r'- \[[^\]]+\]\([^)]+\)', line) for line in content[1:]):
            errors.append(f'{path}: subtree AGENTS may contain only a title and link pointers')
        if pointer.get('authority') != 'AGENTS.md' or 'AGENTS.md' not in local_targets(root, path):
            errors.append(f'{path}: subtree pointer must link root AGENTS')
        for target in LINK.findall('\n'.join(lines)):
            parsed = urlsplit(target)
            destination = ((root / path).parent / unquote(parsed.path)).resolve()
            if not destination.is_relative_to(root.resolve()) or not destination.is_file() or (parsed.fragment and parsed.fragment not in anchors(destination.read_text())):
                errors.append(f'{path}: broken subtree pointer {target}')
    return errors


def query(index: dict, term: str, root: Path) -> dict:
    """Return pointers, never load research bodies or run validation/build commands."""
    needle = term.casefold()
    routes = [r for r in index.get('taskRoutes', [])
              if any(needle in str(r.get(k, '')).casefold() for k in ('id', 'title', 'keywords'))]
    documents = [d for d in index['documents'] if needle in d['path'].casefold()]
    terms = [t for t in index.get('terminology', []) if any(needle in str(t.get(k, '')).casefold() for k in ('term', 'aliases'))]
    # Design ownership stays in its existing authority, not copied into task routes.
    areas_path = root / 'script/design_gated_areas.json'
    areas = []
    if areas_path.is_file():
        for area in json.loads(areas_path.read_text())['areas']:
            if any(r['id'] == 'design' for r in routes) or any(needle in str(area.get(k, '')).casefold() for k in ('id', 'title', 'owner', 'designDoc')):
                areas.append({k: area.get(k) for k in ('id', 'title', 'owner', 'status', 'designDoc')})
    registry_path = root / 'script/scene_validation_gates.json'
    if registry_path.is_file():
        registry = json.loads(registry_path.read_text())
        groups = {g['id']: g for g in registry['path_groups']}
        routes = [dict(r, nearestTests=sorted({m for g in r.get('nearestTestGroups', []) for m in groups.get(g, {}).get('modules', [])}),
                       gates={g: registry['gates'][g] for p in r.get('verificationPhases', []) for g in p['gateRefs'] if g in registry['gates']}) for r in routes]
    return {'routes': routes, 'documents': documents, 'designAreas': areas, 'terminology': terms}


def first_read_lines(root: Path, pointer: str) -> int:
    """Count the selected Markdown section, including its nested subsections."""
    from script.document_health import anchors
    path, _, fragment = pointer.partition('#')
    lines = (root / path).read_text().splitlines()
    if not fragment:
        return len(lines)
    start = next((i for i, line in enumerate(lines) if fragment in anchors(line)), None)
    if start is None:
        return 0  # validate_routing reports the missing anchor.
    level = None
    for i in range(start, len(lines)):
        heading = re.match(r'^\s{0,3}(#{1,6})\s+', lines[i])
        if heading:
            if level is None:
                level = len(heading[1])
            elif len(heading[1]) <= level:
                return i - start
    return len(lines) - start


def audit(root: Path, index: dict) -> dict:
    """Machine acceptance for M1/M3/M8; no runtime or private research execution."""
    errors = validate(root, index)
    if index.get('routingContract') != 'repository-task-routing-v1':
        errors.append('repository audit requires routingContract repository-task-routing-v1')
    if not index.get('taskFrequencyEvidence'):
        errors.append('repository audit requires frozen task frequency evidence')
    if {p.get('path') for p in index.get('pointerEntrypoints', [])} != {'MyWallpaperX/Core/SteamWorkshopScene/AGENTS.md'}:
        errors.append('repository audit requires the Scene subtree pointer entrypoint')
    queries = ('修复 Scene 视觉缺陷', '发布新版本', '设计前置判定')
    first_hops = {term: [r.get('firstRead') for r in query(index, term, root)['routes']] for term in queries}
    for term, pointers in first_hops.items():
        if not pointers:
            errors.append(f'missing required first-hop query: {term}')
    reading_sizes = {r['id']: first_read_lines(root, r['firstRead']) for r in index.get('taskRoutes', [])
                     if r.get('firstRead') and (root / r['firstRead'].partition('#')[0]).is_file()}
    errors.extend(f'{key}: first-read snapshot exceeds 150 lines ({size})' for key, size in reading_sizes.items() if size > 150)
    stable = {d['path'] for d in index['documents'] if d['role'] == 'stable-contract'}
    covered = {p for r in index.get('taskRoutes', []) for p in r['documents']}
    return {'managedDocuments': len(managed_documents(root)), 'registeredDocuments': len(index['documents']),
            'stableContracts': len(stable), 'routedContracts': len(stable & covered),
            'firstHopQueries': first_hops, 'firstReadLines': reading_sizes, 'terminologyOwners': len(index.get('terminology', [])), 'errors': errors}



def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--check', action='store_true')
    action.add_argument('--list', action='store_true')
    action.add_argument('--audit', action='store_true')
    action.add_argument('--query')
    args = parser.parse_args()
    try:
        index = json.loads((ROOT / INDEX).read_text())
        if args.audit:
            result = audit(ROOT, index)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return int(bool(result['errors']))
        if args.check:
            errors = audit(ROOT, index)['errors']
            print(json.dumps({'documents': len(index['documents']), 'errors': errors}, ensure_ascii=False, indent=2))
            return int(bool(errors))
        if args.list:
            result = index.get('taskRoutes', [])
        else:
            if not args.query.strip():
                parser.error('--query requires nonempty text')
            result = query(index, args.query.strip(), ROOT)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(2, f'document registry: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
