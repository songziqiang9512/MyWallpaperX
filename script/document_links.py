"""Validate portable repository links independently of optional local evidence caches."""

from __future__ import annotations

import html
from bisect import bisect_right
from itertools import accumulate
from pathlib import Path
import re
import subprocess
from collections.abc import Iterable
from urllib.parse import unquote, urlsplit

INLINE_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
EXPLICIT_ANCHOR_PATTERN = re.compile(
    r"<a\s+(?:[^>]*?\s)?id=[\"']([^\"']+)[\"'][^>]*>", re.IGNORECASE
)


def _markdown_visible_lines(text: str) -> list[tuple[int, str]]:
    visible_lines: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines()):
        match = re.match(r"^\s*(```|~~~)", line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker == fence:
                fence = None
            continue
        if fence is None:
            visible_lines.append((number, line))
    return visible_lines


def markdown_without_fenced_code(text: str) -> str:
    return "\n".join(line for _, line in _markdown_visible_lines(text))


def markdown_link_targets(text: str) -> list[str]:
    targets: list[str] = []
    for raw in INLINE_LINK_PATTERN.findall(markdown_without_fenced_code(text)):
        target = raw.strip()
        target = target[1:target.index(">")] if target.startswith("<") and ">" in target else target.split(maxsplit=1)[0]
        targets.append(target)
    return targets


def github_heading_slug(value: str) -> str:
    """Keep the repository's existing compact ASCII/CJK heading contract.

    Punctuation-sensitive public links should use explicit permanent IDs.
    """
    value = re.sub(r"<[^>]+>", "", html.unescape(value)).strip().lower()
    value = re.sub(r"[^\w\-\u3400-\u9fff ]", "", value)
    return re.sub(r"[ _]+", "-", value).strip("-")


def markdown_outline(text: str) -> tuple[dict[str, int], list[tuple[int, int]]]:
    """Return zero-based source-line anchor positions and heading levels."""
    visible_lines = _markdown_visible_lines(text)
    visible = "\n".join(line for _, line in visible_lines)
    offsets = list(accumulate([0] + [len(line) + 1 for _, line in visible_lines]))
    anchors: dict[str, int] = {}
    # Explicit IDs may span lines; match the same visible text as link validation.
    for match in EXPLICIT_ANCHOR_PATTERN.finditer(visible):
        source_line = visible_lines[bisect_right(offsets, match.start()) - 1][0]
        anchors.setdefault(match.group(1), source_line)
    generated: set[str] = set()
    headings: list[tuple[int, int]] = []
    for number, line in visible_lines:
        heading = re.match(r"^\s{0,3}(#{1,6})\s+", line)
        if not heading:
            continue
        headings.append((number, len(heading.group(1))))
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not match:
            continue
        original = github_heading_slug(match.group(1))
        slug, suffix = original, 0
        while slug in generated:
            suffix += 1
            slug = f"{original}-{suffix}"
        generated.add(slug)
        if slug:
            anchors[slug] = min(anchors.get(slug, number), number)
    return anchors, headings


def markdown_anchors(text: str) -> set[str]:
    return set(markdown_outline(text)[0])


def relative_link_violations(root: Path, documents: Iterable[str]) -> list[str]:
    root = root.resolve()
    links = []
    local_paths: set[str] = set()
    for relative in sorted(documents):
        document = root / relative
        for target in markdown_link_targets(document.read_text(encoding="utf-8")):
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith(("#", "/", "//")) or not parsed.path:
                continue
            resolved = (document.parent / unquote(parsed.path)).resolve()
            local = resolved.relative_to(root).as_posix() if resolved.is_relative_to(root) else None
            if local:
                local_paths.add(local)
            links.append((relative, target, resolved, unquote(parsed.fragment), local))
    ignored: set[str] = set()
    if local_paths:
        result = subprocess.run(
            ["git", "check-ignore", "--stdin", "-z"], cwd=root,
            input="\0".join(sorted(local_paths)) + "\0", capture_output=True, text=True,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(f"Cannot classify repository link targets: {result.stderr.strip()}")
        ignored.update(filter(None, result.stdout.split("\0")))
    violations: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}
    for relative, target, resolved, fragment, local in links:
        if local in ignored:
            violations.append(f"{relative} -> {target} (ignored local artifact; retain its path as text, not a repository link)")
        elif not resolved.exists():
            violations.append(f"{relative} -> {target}")
        elif fragment and resolved.is_file() and resolved.suffix == ".md":
            if resolved not in anchor_cache:
                anchor_cache[resolved] = markdown_anchors(resolved.read_text(encoding="utf-8"))
            if fragment not in anchor_cache[resolved]:
                violations.append(f"{relative} -> {target} (missing fragment)")
    return violations
