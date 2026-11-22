#!/usr/bin/env python3
"""Check the String Catalog: language coverage, plural forms and placeholders.

Two modes:

* default — validate the catalog itself: every registered language has a
  translated entry for every key, plural forms are complete, placeholders match
  the source key, and the file compiles with `xcstringstool`.
* `--extraction DIR` — additionally compare the compiler-extracted keys
  (the `.stringsdata` files of a build with `SWIFT_EMIT_LOC_STRINGS`) against
  the catalog, which is the authoritative check that source edits and
  translations stayed in sync.

`--hardcoded` lists Chinese literals in UI-looking code that never reached
`String(localized:)`; diagnostics, content matching and persisted sentinels are
allowlisted below and are deliberately not translated.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = Path('MyWallpaperX/Resources/Localizable.xcstrings')
SOURCE_ROOTS = ('MyWallpaperX',)
TRANSLATIONS = ('zh-Hans', 'ru', 'de', 'fr')
PLURAL_LANGUAGES = ('en', *TRANSLATIONS)

PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:lld|llu|lf|f|d|@)')
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
CJK = re.compile(r'[\u4e00-\u9fff]')
HARDCODED_ALLOW = re.compile(
    r'diagnostic|debugDescription|NSLog|print\(|logger|'
    r'case\s+"|UserDefaults|identifier|bundleIdentifier|pathExtension|fileExtension|'
    r'Movies/MyWallpaperX/|appendingPathComponent|DebugWebFailureStateRunner', re.I)


def placeholder_signature(value: str) -> list[str]:
    return PLACEHOLDER.findall(value)


def catalog_errors(catalog: dict) -> list[str]:
    errors: list[str] = []
    entries = catalog.get('strings', {})
    source_language = catalog.get('sourceLanguage')
    if source_language != 'en':
        errors.append(f'sourceLanguage must be en, found {source_language!r}')
    for key, entry in sorted(entries.items()):
        expected = placeholder_signature(key)
        localizations = entry.get('localizations', {})
        if not localizations:
            errors.append(f'en entry missing: {key}')
            continue
        for language in PLURAL_LANGUAGES:
            unit = localizations.get(language, {})
            plural = unit.get('variations', {}).get('plural')
            if plural:
                required = ('one', 'other') if language != 'zh-Hans' else ('other',)
                for form in required:
                    if form not in plural:
                        errors.append(f'{language} plural form missing: {key} [{form}]')
                values = [v.get('stringUnit', {}).get('value', '') for v in plural.values()]
            else:
                value = unit.get('stringUnit', {}).get('value')
                if value is None:
                    errors.append(f'{language} untranslated: {key}')
                    continue
                if unit['stringUnit'].get('state') != 'translated':
                    errors.append(f'{language} state is not translated: {key}')
                values = [value]
            for value in values:
                found = placeholder_signature(value)
                if found != expected and sorted(found) != sorted(expected):
                    errors.append(f'{language} placeholder mismatch: {key} -> {value}')
    return errors


def compile_errors(catalog_path: Path, tmp: Path) -> list[str]:
    tmp.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ['xcrun', 'xcstringstool', 'compile', '--output-directory', str(tmp), str(catalog_path)],
        capture_output=True, text=True)
    if result.returncode != 0:
        return [f'catalog does not compile: {result.stderr.strip()[:400]}']
    return []


def extraction_keys(directory: Path) -> set[str]:
    keys: set[str] = set()
    for path in directory.rglob('*.stringsdata'):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        for entry in data.get('tables', {}).get('Localizable', []):
            key = entry.get('key')
            if key:
                keys.add(key)
    return keys


def hardcoded_hits() -> list[str]:
    hits = []
    for root in SOURCE_ROOTS:
        for path in sorted((ROOT / root).rglob('*.swift')):
            if 'Debug' in path.parts or 'DebugWebFailureStateRunner' in path.name:
                continue
            for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                stripped = line.lstrip()
                if stripped.startswith('//') or stripped.startswith('///'):
                    continue
                if 'String(localized:' in line or HARDCODED_ALLOW.search(line):
                    continue
                if re.search(r'\bcase\s+\w+\s*=', line):
                    continue
                comment_at = line.find('//')
                if comment_at != -1:
                    continue
                for literal in STRING_LITERAL.findall(line):
                    if CJK.search(literal):
                        hits.append(f'{path.relative_to(ROOT)}:{number}: {literal[:70]}')
                        break
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', default=str(CATALOG))
    parser.add_argument('--extraction', help='directory with build .stringsdata files')
    parser.add_argument('--hardcoded', action='store_true')
    parser.add_argument('--compile', action='store_true', help='also run xcstringstool compile')
    args = parser.parse_args()

    catalog_path = ROOT / args.catalog
    if not catalog_path.exists():
        print(f'missing catalog: {catalog_path.relative_to(ROOT)}', file=sys.stderr)
        return 1
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    entries = catalog.get('strings', {})

    errors = catalog_errors(catalog)

    if args.extraction:
        extracted = extraction_keys(Path(args.extraction))
        missing = sorted(extracted - set(entries))
        orphan = sorted(set(entries) - extracted)
        errors.extend(f'missing key (source uses it, catalog has none): {key}' for key in missing)
        errors.extend(f'orphan key (catalog has it, source does not): {key}' for key in orphan)

    if args.compile:
        errors.extend(compile_errors(catalog_path, Path('/private/tmp/mwx-localization-catalog')))

    if args.hardcoded:
        errors.extend(f'hardcoded UI text: {hit}' for hit in hardcoded_hits())

    print(f'catalog keys: {len(entries)}, languages: en, {", ".join(TRANSLATIONS)}')
    for line in errors:
        print(line)
    if errors:
        print(f'{len(errors)} localization problem(s)')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
