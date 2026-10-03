#!/usr/bin/env python3
"""Bound current document bodies, preserve archive anchors, and expose review age."""
from __future__ import annotations

import argparse
from datetime import date
import hashlib
import html
import json
import math
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = Path('script/document_health_baseline.json')
HISTORY_ROOTS = ('docs/history', 'docs/scene/history')
AUTHORITY_ROLES = {'stable-contract', 'current-state', 'active-plan'}
REDIRECT = re.compile(r'^<a id="([^"]+)"></a> \[归档记录\]\(([^)]+)\) <!-- archive-redirect -->$')
START, END = '<!-- preserved-body:start -->\n', '<!-- preserved-body:end -->'


def load_json(text: str) -> dict:
    def invalid_constant(value: str):
        raise ValueError(f'non-finite JSON number is forbidden: {value}')
    def finite_float(value: str):
        number = float(value)
        if not math.isfinite(number):
            return invalid_constant(value)
        return number
    return json.loads(text, parse_constant=invalid_constant, parse_float=finite_float)


def document_path(value: object, *, history: bool = False) -> bool:
    if not isinstance(value, str) or not value or any(ord(c) < 32 for c in value) or '\\' in value:
        return False
    path = PurePosixPath(value)
    return (not path.is_absolute() and '..' not in path.parts and path.as_posix() == value
            and value.startswith(tuple(h + '/' for h in HISTORY_ROOTS) if history else 'docs/') and value.endswith('.md'))


def schema_errors(value: object) -> list[str]:
    """Reject malformed budgets before any arithmetic or filesystem access."""
    if not isinstance(value, dict):
        return ['document health baseline must be an object']
    errors = []
    required = {'schemaVersion', 'maxReviewAgeDays', 'bodies', 'archives', 'snapshots'}
    if not required <= value.keys() or value.keys() - required - {'owner', 'policy', 'adjustments'}:
        errors.append('document health baseline fields are missing or unknown')
    if type(value.get('schemaVersion')) is not int or value['schemaVersion'] != 1:
        errors.append('document health schemaVersion must be integer 1')
    def nonnegative(number):
        return type(number) is int and number >= 0
    if not nonnegative(value.get('maxReviewAgeDays')) or value['maxReviewAgeDays'] > 60:
        errors.append('maxReviewAgeDays must be an integer from 0 to 60')
    for field in ('owner', 'policy'):
        if field in value and (not isinstance(value[field], str) or not value[field].strip()):
            errors.append(f'{field} must be nonempty text')
    bodies = value.get('bodies')
    if not isinstance(bodies, dict):
        errors.append('bodies must map normalized docs Markdown paths to budgets')
    else:
        for path, budget in bodies.items():
            if not document_path(path):
                errors.append(f'invalid body path: {path!r}')
            if (not isinstance(budget, dict) or set(budget) != {'lines', 'bytes'}
                    or any(not nonnegative(budget.get(k)) for k in ('lines', 'bytes'))):
                errors.append(f'{path}: lines and bytes must be nonnegative integers, excluding booleans')
    def string(value):
        return isinstance(value, str) and bool(value.strip())
    def fragment(value):
        return string(value) and not re.search(r'[\s<>"#]', value)
    def sha(value):
        return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None
    archives = value.get('archives')
    if not isinstance(archives, list):
        errors.append('archives must be a list')
    else:
        seen = set()
        for record in archives:
            fields = {'source', 'archive', 'anchors', 'preservedBodySHA256'}
            optional = {'originalBodySHA256', 'originalLines', 'originalBytes'}
            if not isinstance(record, dict) or not fields <= record.keys() or record.keys() - fields - optional:
                errors.append('archive record has missing or unknown fields')
                continue
            if not document_path(record['source']) or not document_path(record['archive'], history=True):
                errors.append('archive source and destination must be normalized documentation history paths')
            if not sha(record['preservedBodySHA256']) or ('originalBodySHA256' in record and not sha(record['originalBodySHA256'])):
                errors.append('archive identities must be SHA-256 strings')
            for field in ('originalLines', 'originalBytes'):
                if field in record and not nonnegative(record[field]):
                    errors.append(f'archive {field} must be a nonnegative integer')
            ids = record['anchors']
            if not isinstance(ids, list) or not ids or any(not fragment(a) for a in ids) or len(ids) != len(set(ids)):
                errors.append('archive anchors must be unique nonempty fragment strings')
            if isinstance(record['archive'], str):
                if record['archive'] in seen:
                    errors.append('duplicate archive path')
                seen.add(record['archive'])
    snapshots = value.get('snapshots')
    if not isinstance(snapshots, list):
        errors.append('snapshots must be a list')
    else:
        seen = set()
        for record in snapshots:
            if (not isinstance(record, dict) or set(record) != {'path', 'start', 'end'}
                    or not document_path(record.get('path')) or not fragment(record.get('start'))
                    or not fragment(record.get('end')) or record['start'] == record['end']):
                errors.append('snapshot needs normalized docs path and distinct fragment boundaries')
                continue
            if record['path'] in seen:
                errors.append('duplicate snapshot path')
            seen.add(record['path'])
    adjustments = value.get('adjustments', [])
    if not isinstance(adjustments, list):
        errors.append('adjustments must be a list')
    else:
        seen = set()
        fields = {'section', 'path', 'before', 'after', 'owner', 'reason', 'decision'}
        for record in adjustments:
            if not isinstance(record, dict) or set(record) != fields:
                errors.append('adjustment needs section/path, before/after SHA256, owner, reason and decision')
                continue
            if record['section'] not in ('bodies', 'archives', 'snapshots') or not document_path(record['path']):
                errors.append('invalid adjustment section or document path')
            if not sha(record['before']) or not sha(record['after']) or record['before'] == record['after']:
                errors.append('adjustment must bind distinct before/after SHA256 identities')
            if any(not string(record[k]) for k in ('owner', 'reason', 'decision')):
                errors.append('adjustment owner, reason and decision must be nonempty text')
            decision = record['decision'] if isinstance(record['decision'], str) else ''
            path, separator, anchor = decision.partition('#')
            if not document_path(path) or (separator and not fragment(anchor)):
                errors.append('adjustment decision must name a repository document and optional anchor')
            key = (str(record['section']), str(record['path']))
            if key in seen:
                errors.append('duplicate adjustment section/path')
            seen.add(key)
    return errors


def anchors(text: str) -> set[str]:
    """Match repository Markdown links: explicit IDs and visible GitHub headings."""
    result = set(re.findall(r"<a\s+(?:[^>]*?\s)?id=[\"']([^\"']+)[\"'][^>]*>", text, re.I))
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^\s*(```|~~~)", line)
        if marker:
            if fence is None:
                fence = marker[1]
            elif marker[1] == fence:
                fence = None
            continue
        if fence is not None:
            continue
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if match:
            value = re.sub(r"<[^>]+>", "", html.unescape(match[1])).strip().lower()
            value = re.sub(r"[^\w\-\u3400-\u9fff ]", "", value)
            slug = re.sub(r"[ _]+", "-", value).strip("-")
            if slug:
                result.add(slug)
    return result


def body_size(text: str) -> dict[str, int]:
    """Only exact, independently validated compatibility redirects are excluded."""
    body = '\n'.join(line for line in text.splitlines() if not REDIRECT.fullmatch(line))
    return {'lines': len(body.splitlines()), 'bytes': len(body.encode())}


def value_identity(value: object) -> str:
    """Stable identity for one baseline value; JSON null represents absence."""
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)
    return hashlib.sha256(encoded.encode()).hexdigest()


def required_adjustments(old: dict, new: dict) -> list[dict]:
    """Describe exact transitions, without granting permission or changing files."""
    changes = []
    def add(section, path, before, after):
        changes.append({'section': section, 'path': path,
                        'before': value_identity(before), 'after': value_identity(after)})
    for path in sorted(old.get('bodies', {}).keys() | new.get('bodies', {}).keys()):
        budget = old.get('bodies', {}).get(path)
        current = new.get('bodies', {}).get(path)
        if budget is None or current is None or any(current[k] > budget[k] for k in ('lines', 'bytes')):
            add('bodies', path, budget, current)
    for section, key in (('archives', 'archive'), ('snapshots', 'path')):
        before = {r[key]: r for r in old.get(section, [])}
        after = {r[key]: r for r in new.get(section, [])}
        for path in sorted(before.keys() | after.keys()):
            record = before.get(path)
            if record != after.get(path):
                add(section, path, record, after.get(path))
    return changes


def ratchet_errors(old: dict, new: dict) -> list[str]:
    errors = schema_errors(old) + schema_errors(new)
    if errors:
        return errors
    for change in required_adjustments(old, new):
        if not any(all(record[k] == v for k, v in change.items()) for record in new.get('adjustments', [])):
            messages = {'bodies': 'authority budget was added, grew or was removed',
                        'archives': 'preserved archive identity changed',
                        'snapshots': 'snapshot boundaries changed'}
            errors.append(f"{change['path']}: {messages[change['section']]}; exact documented adjustment required")
    if new.get('maxReviewAgeDays', 0) > old.get('maxReviewAgeDays', 0):
        errors.append('review freshness budget may only decrease')
    return errors


def review_errors(root: Path, document: dict, today: date, max_age: int) -> list[str]:
    path = document['path']
    basis = document.get('reviewBasis', {})
    if not isinstance(basis, dict):
        return [f'{path}: reviewBasis must be an object']
    try:
        reviewed = date.fromisoformat(document.get('lastReviewed', ''))
    except (ValueError, TypeError):
        return [f'{path}: invalid lastReviewed']
    errors = []
    if not 0 <= (today - reviewed).days <= max_age:
        errors.append(f'{path}: stale or future lastReviewed {reviewed}')
    if any(not isinstance(basis.get(field), str) or not basis[field].strip() for field in ('scope', 'limitations')):
        errors.append(f'{path}: reviewBasis needs scope and limitations')
    if basis.get('kind') == 'git-document-change':
        revision = basis.get('revision', '')
        if not isinstance(revision, str) or not re.fullmatch(r'[0-9a-f]{40}', revision):
            return errors + [f'{path}: review revision must be full commit identity']
        try:
            record = subprocess.check_output(['git', 'show', '--format=%cs', '--name-only', revision, '--', path], cwd=root, text=True, stderr=subprocess.DEVNULL).splitlines()
            if not record or record[0] != str(reviewed) or path not in record:
                errors.append(f'{path}: review date/source commit does not match document maintenance')
        except subprocess.CalledProcessError:
            errors.append(f'{path}: review source commit unavailable')
    elif basis.get('kind') == 'navigation-audit':
        # A bounded audit is a hash-bound receipt, never a claim of runtime/parity review.
        if basis.get('sourceSHA256') != hashlib.sha256((root / path).read_bytes()).hexdigest():
            errors.append(f'{path}: navigation review receipt no longer matches source')
        if basis.get('method') != 'document_registry --audit + document_health --check':
            errors.append(f'{path}: missing navigation review method')
    else:
        errors.append(f'{path}: unknown reviewBasis kind')
    return errors


def validate(root: Path, index: dict, baseline: dict, today: date | None = None) -> list[str]:
    today = today or date.today()
    errors = schema_errors(baseline)
    if errors:
        return errors
    if (not isinstance(index, dict) or not isinstance(index.get('documents'), list)
            or any(not isinstance(d, dict) or not document_path(d.get('path'))
                   or not isinstance(d.get('role'), str) for d in index['documents'])):
        return ['document index needs normalized docs paths and explicit roles']
    if not (root / 'docs').resolve().is_relative_to(root.resolve()):
        return ['docs root escapes repository']
    paths = {d['path'] for d in index['documents'] if d['role'] in AUTHORITY_ROLES}
    paths.update(r[k] for r in baseline['archives'] for k in ('source', 'archive'))
    paths.update(r['path'] for r in baseline['snapshots'])
    paths.update(r['decision'].partition('#')[0] for r in baseline.get('adjustments', []))
    for path in paths:
        target = root / path
        if not target.resolve().is_relative_to((root / 'docs').resolve()) or not target.is_file():
            errors.append(f'{path}: document missing or escapes docs root')
    for record in baseline['archives']:
        if not any((root / record['archive']).resolve().is_relative_to((root / h).resolve()) for h in HISTORY_ROOTS):
            errors.append(f'{record["archive"]}: archive escapes history root')
    if errors:
        return errors
    for record in baseline.get('adjustments', []):
        path, separator, anchor = record['decision'].partition('#')
        if separator and anchor not in anchors((root / path).read_text()):
            errors.append(f'{path}: adjustment decision anchor missing: {anchor}')
    current = {d['path'] for d in index['documents'] if d['role'] in AUTHORITY_ROLES}
    budgets = baseline.get('bodies', {})
    errors.extend(f'{p}: unbudgeted current authority' for p in sorted(current - budgets.keys()))
    errors.extend(f'{p}: budget no longer names current authority' for p in sorted(budgets.keys() - current))
    anchor_cache = {}
    for path in sorted(current):
        text = (root / path).read_text()
        size = body_size(text)
        budget = budgets.get(path, {})
        if any(size[k] > budget.get(k, 0) for k in size):
            errors.append(f'{path}: retained body exceeds baseline {size}')
        elif any(size[k] < budget.get(k, 0) for k in size):
            errors.append(f'{path}: reduced retained body must ratchet baseline down')
        if size['lines'] > 600:
            errors.append(f'{path}: retained authority body exceeds 600 lines')
        for line in text.splitlines():
            if 'archive-redirect' not in line:
                continue
            match = REDIRECT.fullmatch(line)
            if not match:
                errors.append(f'{path}: malformed archive redirect')
                continue
            anchor, target = match.groups()
            target_path, separator, fragment = target.partition('#')
            destination = ((root / path).parent / target_path).resolve()
            if any(destination.is_relative_to((root / h).resolve()) for h in HISTORY_ROOTS) and destination.is_file() and destination not in anchor_cache:
                anchor_cache[destination] = anchors(destination.read_text())
            if (not any(destination.is_relative_to((root / h).resolve()) for h in HISTORY_ROOTS)
                    or not separator or fragment != anchor or not destination.is_file()
                    or anchor not in anchor_cache.get(destination, set())):
                errors.append(f'{path}: broken permanent archive redirect {anchor}')
    for snapshot in baseline.get('snapshots', []):
        text = (root / snapshot['path']).read_text()
        start, end = f'<a id="{snapshot["start"]}"></a>', f'<a id="{snapshot["end"]}"></a>'
        if start not in text or end not in text or text.index(start) >= text.index(end):
            errors.append(f'{snapshot["path"]}: missing or reordered snapshot anchors')
        elif len(text[text.index(start):text.index(end)].splitlines()) > 150:
            errors.append(f'{snapshot["path"]}: initial reading snapshot exceeds 150 lines')
    for record in baseline.get('archives', []):
        archive = (root / record['archive']).read_text()
        if archive.count(START) != 1 or archive.count(END) != 1:
            errors.append(f"{record['archive']}: missing preserved payload boundary")
            continue
        body = archive.split(START)[1].split(END)[0]
        if hashlib.sha256(body.encode()).hexdigest() != record['preservedBodySHA256']:
            errors.append(f"{record['archive']}: preserved payload changed")
        source = (root / record['source']).read_text()
        redirects = {m.group(1): m.group(2) for line in source.splitlines() if (m := REDIRECT.fullmatch(line))}
        for anchor in record['anchors']:
            if anchor not in anchors(body) or anchor not in redirects:
                errors.append(f"{record['source']}: missing permanent anchor {anchor}")
    for document in index['documents']:
        if document['role'] == 'stable-contract':
            errors.extend(review_errors(root, document, today, baseline['maxReviewAgeDays']))
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', required=True)
    parser.add_argument('--base', default='HEAD', help='compare tracked prior baseline, if any')
    args = parser.parse_args(argv)
    try:
        index = load_json((ROOT / 'docs/document-role-index.json').read_text())
        baseline = load_json((ROOT / BASELINE).read_text())
        errors = schema_errors(baseline)
        if errors:
            print(json.dumps({'errors': errors}, ensure_ascii=False, indent=2))
            return 1
        errors = validate(ROOT, index, baseline)
        previous = subprocess.run(['git', 'show', f'{args.base}:{BASELINE}'], cwd=ROOT, text=True, capture_output=True)
        changes = []
        if previous.returncode == 0:
            old = load_json(previous.stdout)
            errors.extend(ratchet_errors(old, baseline))
            if not schema_errors(old):
                changes = required_adjustments(old, baseline)
        else:
            # Missing first-adoption baseline is allowed; an invalid base is not.
            subprocess.run(['git', 'rev-parse', '--verify', f'{args.base}^{{commit}}'], cwd=ROOT, check=True, capture_output=True)
        print(json.dumps({'currentAuthorities': len(baseline['bodies']), 'archives': len(baseline['archives']),
                          'baseRef': args.base, 'baselineBootstrap': previous.returncode != 0,
                          'requiredAdjustments': changes,
                          'errors': errors}, ensure_ascii=False, indent=2))
        return int(bool(errors))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(2, f'document health: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
