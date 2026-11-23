#!/usr/bin/env python3
"""Check the String Catalog: language coverage, plural forms and placeholders.

The default validates translation coverage, plural forms and placeholders.
Use --source for source lookups, --changed for staged changes and --compile
to compile the catalogs with `xcstringstool`.
`--extraction DIR` — additionally compare the compiler-extracted keys
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
from collections import defaultdict
from contextlib import nullcontext
from pathlib import Path
from tempfile import TemporaryDirectory

def _repository_root() -> Path:
    """Locate the checkout regardless of where the script is filed."""
    for parent in Path(__file__).resolve().parents:
        if (parent / 'MyWallpaperX' / 'Resources').is_dir():
            return parent
    return Path(__file__).resolve().parents[1]


ROOT = _repository_root()
CATALOGS = {
    target: Path(target) / "Resources/Localizable.xcstrings"
    for target in ("MyWallpaperX", "ScreenSaverSources")
}
INFO_CATALOG = Path("MyWallpaperX/Resources/InfoPlist.xcstrings")
PLURAL_FORMS = {
    'en': {'one', 'other'},
    'zh-Hans': {'other'},
    'ru': {'one', 'few', 'many', 'other'},
    'de': {'one', 'other'},
    'fr': {'one', 'other'},
}

PLACEHOLDER = re.compile(r'%%|%(?:(\d+)\$)?([hlLzjtq]{0,2}[diuoxXfFeEgGcs]|@)')
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
CJK = re.compile(r'[\u4e00-\u9fff]')
HARDCODED_ALLOW = re.compile(
    r'diagnostic|debugDescription|NSLog|print\(|logger|'
    r'case\s+"|UserDefaults|identifier|bundleIdentifier|pathExtension|fileExtension|'
    r'Movies/MyWallpaperX/|appendingPathComponent|DebugWebFailureStateRunner', re.I)


def placeholder_signature(value: str) -> list[tuple[int, str]] | None:
    arguments = [(position, kind) for position, kind in PLACEHOLDER.findall(value) if kind]
    numbered = [position for position, _ in arguments if position]
    if numbered and len(numbered) != len(arguments):
        return None
    return sorted((int(position) if position else index, kind)
                  for index, (position, kind) in enumerate(arguments, 1))


def catalog_errors(catalog: dict, only_keys: set[str] | None = None) -> list[str]:
    errors: list[str] = []
    entries = catalog.get('strings', {})
    source_language = catalog.get('sourceLanguage')
    if source_language != 'en':
        errors.append(f'sourceLanguage must be en, found {source_language!r}')
    for key, entry in sorted(entries.items()):
        if only_keys is not None and key not in only_keys:
            continue
        expected = placeholder_signature(key)
        if expected is None:
            errors.append(f'mixed placeholder positions in source: {key}')
            continue
        localizations = entry.get('localizations', {})
        if not localizations:
            errors.append(f'en entry missing: {key}')
            continue
        for language, required in PLURAL_FORMS.items():
            unit = localizations.get(language, {})
            plural = unit.get('variations', {}).get('plural')
            if plural:
                for form in sorted(required):
                    if form not in plural:
                        errors.append(f'{language} plural form missing: {key} [{form}]')
                units = [v.get('stringUnit', {}) for v in plural.values()]
            else:
                units = [unit.get('stringUnit', {})]
            for string_unit in units:
                value = string_unit.get('value')
                if not value or string_unit.get('state') != 'translated':
                    errors.append(f'{language} untranslated: {key}')
                    continue
                found = placeholder_signature(value)
                if found != expected:
                    errors.append(f'{language} placeholder mismatch: {key} -> {value}')
    return errors


TOKEN = re.compile(
    r'//[^\n]*|/\*|#*"""|#*"|[()]|\b(?:String|LocalizedStringResource)\b'
)
TRIVIA = re.compile(r'\s+|//[^\n]*|/\*')
QUOTE = re.compile(r'#*"')
BLOCK_COMMENT = re.compile(r'/\*|\*/')
ESCAPES = {'n': '\n', 'r': '\r', 't': '\t', '0': '\0', '\\': '\\', '"': '"', "'": "'"}
INTERPOLATION = "\0argument\0"


def source_keys(source: str) -> set[str]:
    """Extract literal lookup keys and preserve interpolation positions."""
    keys: set[str] = set()

    def block_end(offset: int) -> int:
        depth = 1
        for marker in BLOCK_COMMENT.finditer(source, offset):
            depth += 1 if marker[0] == "/*" else -1
            if not depth:
                return marker.end()
        return len(source)

    def skip_trivia(offset: int) -> int:
        while match := TRIVIA.match(source, offset):
            offset = block_end(match.end()) if match[0] == "/*" else match.end()
        return offset

    def code(offset: int, depth: int = 0) -> int:
        while token := TOKEN.search(source, offset):
            value = token[0]
            offset = token.end()
            if value == "/*":
                offset = block_end(offset)
            elif value == "(" and depth:
                depth += 1
            elif value == ")" and depth:
                depth -= 1
                if not depth:
                    return offset
            elif value in {"String", "LocalizedStringResource"}:
                opening = skip_trivia(offset)
                if source[opening:opening + 1] != "(":
                    continue
                argument = skip_trivia(opening + 1)
                if value == "String":
                    if not source.startswith("localized", argument):
                        continue
                    colon = skip_trivia(argument + len("localized"))
                    if source[colon:colon + 1] != ":":
                        continue
                    argument = skip_trivia(colon + 1)
                if not QUOTE.match(source, argument):
                    continue
                key, offset = literal(argument)
                keys.add(key)
                if depth:
                    depth += 1
            elif not value.startswith("//") and value.endswith('"'):
                _, offset = literal(token.start())
        return len(source)

    def literal(offset: int) -> tuple[str, int]:
        quote = source.index('"', offset)
        hashes = source[offset:quote]
        multiline = source.startswith('"""', quote)
        quotes = '"""' if multiline else '"'
        closing = quotes + hashes
        escape = "\\" + hashes
        tokens = re.compile("|".join(map(re.escape, (closing, escape))))
        escapes = re.compile(re.escape(escape) + r'(?:u\{([0-9A-Fa-f]+)\}|([^\S\n]*\n)|(.))')
        pieces: list[str] = []
        offset = quote + len(quotes)
        while token := tokens.search(source, offset):
            pieces.append(source[offset:token.start()])
            offset = token.end()
            if token[0] == closing:
                key = "".join(pieces)
                if multiline:
                    line_start = source.rfind("\n", 0, token.start()) + 1
                    margin = source[line_start:token.start()]
                    key = key.removeprefix("\n").removesuffix("\n" + margin)
                    key = "\n".join(line.removeprefix(margin) for line in key.split("\n"))
                def decode(match: re.Match[str]) -> str:
                    unicode_value, continuation, character = match.groups()
                    if unicode_value is not None:
                        return chr(int(unicode_value, 16))
                    return "" if continuation else ESCAPES.get(character, character)
                return escapes.sub(decode, key), offset
            if source[offset:offset + 1] == "(":
                offset = code(offset + 1, 1)
                pieces.append(INTERPOLATION)
            elif escaped := escapes.match(source, token.start()):
                pieces.append(escaped[0])
                offset = escaped.end()
            elif offset < len(source):
                offset += 1
        return "", len(source)

    code(0)
    return keys


def git_text(revision: str, *, optional: bool = False) -> str | None:
    result = subprocess.run(
        ["git", "show", revision], cwd=ROOT, capture_output=True, text=True, check=not optional,
    )
    return result.stdout if result.returncode == 0 else None


def staged_inputs() -> tuple[dict[str, set[str]], set[Path]]:
    paths = {
        Path(name) for name in subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "-z", "--no-renames"], cwd=ROOT,
        ).decode().split("\0") if name
    }
    keys: dict[str, set[str]] = defaultdict(set)
    for path in paths:
        target = path.parts[0]
        if target in CATALOGS and path.suffix == ".swift":
            new = git_text(f":{path.as_posix()}", optional=True)
            if new is not None:
                old = git_text(f"HEAD:{path.as_posix()}", optional=True) or ""
                keys[target].update(source_keys(new) - source_keys(old))
    return keys, paths


def source_catalog_errors(keys: set[str], entries: dict) -> tuple[list[str], set[str]]:
    by_shape: dict[str, set[str]] = defaultdict(set)
    for key in entries:
        shape = PLACEHOLDER.sub(lambda match: INTERPOLATION if match[2] else "%", key)
        by_shape[shape].add(key)
    matches: set[str] = set()
    missing: list[str] = []
    for key in sorted(keys):
        if key in entries:
            matches.add(key)
        elif key in by_shape:
            matches.update(by_shape[key])
        else:
            missing.append("missing key (source uses it, catalog has none): "
                           + key.replace(INTERPOLATION, "%@"))
    return missing, matches


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
    for root in CATALOGS:
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
    parser.add_argument('--catalog', type=Path, help='validate a single catalog instead of the product tables')
    parser.add_argument('--changed', action='store_true', help='check staged Swift and catalog changes')
    parser.add_argument('--source', action='store_true', help='compare literal Swift lookups with each target table')
    parser.add_argument('--extraction', type=Path, help='compare the main App catalog against compiler stringsdata')
    parser.add_argument('--hardcoded', action='store_true')
    parser.add_argument('--compile', action='store_true', help='also run xcstringstool compile')
    args = parser.parse_args()
    if (args.changed and (args.catalog or args.source or args.extraction or args.compile)
            or args.catalog and args.source):
        parser.error('choose staged, product source, or a single catalog')

    errors: list[str] = []
    staged_keys, staged_paths = staged_inputs() if args.changed else ({}, set())
    tables = {"MyWallpaperX": args.catalog} if args.catalog else {**CATALOGS, "InfoPlist": INFO_CATALOG}
    with TemporaryDirectory(prefix="mwx-localization-") if args.compile else nullcontext() as temporary:
        for target, path in tables.items():
            keys = staged_keys.get(target, set())
            if args.changed and not keys and path not in staged_paths:
                continue
            catalog_path = ROOT / path
            data = git_text(f":{path.as_posix()}") if args.changed else catalog_path.read_text(encoding='utf-8')
            catalog = json.loads(data)
            entries = catalog.get('strings', {})
            if args.source and target in CATALOGS:
                for file in (ROOT / target).rglob("*.swift"):
                    keys.update(source_keys(file.read_text(encoding="utf-8")))
            findings, matched = source_catalog_errors(keys, entries)
            findings.extend(catalog_errors(catalog, matched if args.changed and path not in staged_paths else None))
            if args.extraction and target == "MyWallpaperX":
                extracted = extraction_keys(args.extraction)
                if not extracted:
                    findings.append("no compiler-extracted Localizable keys found")
                findings.extend(f'missing key (compiler extracted): {key}' for key in sorted(extracted - entries.keys()))
                findings.extend(f'orphan key (compiler did not extract): {key}' for key in sorted(entries.keys() - extracted))
            if args.compile:
                findings.extend(compile_errors(catalog_path, Path(temporary) / target))
            errors.extend(f"{path}: {finding}" for finding in findings)
            print(f'{path}: {len(entries)} catalog keys')

    if args.hardcoded:
        errors.extend(f'hardcoded UI text: {hit}' for hit in hardcoded_hits())
    for error in errors:
        print(error, file=sys.stderr)
    return int(bool(errors))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"localization: {error}")
