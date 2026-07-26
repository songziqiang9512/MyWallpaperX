#!/usr/bin/env python3
"""从本机合法安装的 Wallpaper Engine 客户端提取 assets 之外的结构化证据。

现有取证文档已经覆盖 `assets/**`、`projects/defaultprojects`、`projects/templates`
和 `ui/dist/monaco/autocomplete`。本脚本负责剩下三个证据面：

1. `ui/dist/scripts/scripts.js` 内嵌的官方 changelog（逐 REV 变更记录）；
2. `locale/ui_en-us.json` 等字符串表（编辑器字段的官方英文标签）；
3. `bin/` 的磁盘依赖清单（技术栈推断输入）。

只做只读静态提取，不执行任何 Windows 二进制，也不复制官方 shader、纹理、
模型或 payload。输出是事实索引，供 docs/scene/semantics 下的取证文档引用。

用法：

    python3 script/extract_wallpaper_engine_client_evidence.py \\
        --client-root ~/Downloads/wallpaper_engine \\
        --output-dir /tmp/we-evidence
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


CHANGELOG_HEADLINE = re.compile(r'changelogHeadline">([^<]+)<')
CHANGELOG_BODY = re.compile(r'changelogBody">(.*?)</pre>', re.S)
REV_NUMBER = re.compile(r'REV\s+(\d+)')


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unescape_js(text: str) -> str:
    return text.replace("\\n", "\n").replace("\\'", "'").replace('\\"', '"')


def extract_changelog(scripts_js: Path) -> dict:
    """提取内嵌 changelog。headline 与 body 按出现顺序一一配对。"""
    source = read_text(scripts_js)
    headlines = CHANGELOG_HEADLINE.findall(source)
    bodies = [unescape_js(body) for body in CHANGELOG_BODY.findall(source)]
    if len(headlines) != len(bodies):
        raise SystemExit(
            f"changelog headline/body 数量不一致：{len(headlines)} vs {len(bodies)}"
        )

    revisions = []
    for headline, body in zip(headlines, bodies):
        match = REV_NUMBER.search(headline)
        entries = [
            line.strip().lstrip("-").strip()
            for line in body.split("\n")
            if line.strip().startswith("-")
        ]
        revisions.append(
            {
                "headline": headline.strip(),
                "revision": int(match.group(1)) if match else None,
                "entries": entries,
            }
        )
    return {
        "source": str(scripts_js),
        "sha256": sha256_of(scripts_js),
        "revisionCount": len(revisions),
        "entryCount": sum(len(item["entries"]) for item in revisions),
        "revisions": revisions,
    }


def extract_locale(locale_dir: Path) -> dict:
    """提取字符串表。只记录 en-us 内容，其他语言只记录 key 数用于交叉校验。"""
    tables = {}
    for path in sorted(locale_dir.glob("*_en-us.json")):
        tables[path.name] = json.loads(read_text(path))

    languages = Counter()
    for path in sorted(locale_dir.glob("*.json")):
        family, _, language = path.stem.rpartition("_")
        languages[language] += 1

    return {
        "source": str(locale_dir),
        "tables": {name: {"keyCount": len(data)} for name, data in tables.items()},
        "languageCount": len(languages),
        "strings": tables,
    }


def extract_binary_manifest(client_root: Path) -> dict:
    """记录 bin/ 与顶层可执行文件的磁盘清单。不读取二进制内容，只记录身份。"""
    entries = []
    for path in sorted((client_root / "bin").glob("*")):
        if path.is_file():
            entries.append(
                {
                    "path": f"bin/{path.name}",
                    "bytes": path.stat().st_size,
                    "sha256": sha256_of(path),
                }
            )
    for name in ("wallpaper32.exe", "wallpaper64.exe", "launcher.exe", "installer.exe"):
        path = client_root / name
        if path.is_file():
            entries.append(
                {
                    "path": name,
                    "bytes": path.stat().st_size,
                    "sha256": sha256_of(path),
                }
            )
    return {"source": str(client_root), "fileCount": len(entries), "files": entries}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--client-root",
        type=Path,
        default=Path.home() / "Downloads/wallpaper_engine",
        help="本机合法安装的 Wallpaper Engine 客户端根目录",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="提取结果输出目录（生成物工作区，不进仓库）",
    )
    args = parser.parse_args()

    client_root = args.client_root.expanduser()
    if not client_root.is_dir():
        raise SystemExit(f"客户端目录不存在：{client_root}")

    output_dir = args.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    version_path = client_root / "version.json"
    version = json.loads(read_text(version_path)) if version_path.is_file() else {}

    payloads = {
        "changelog.json": extract_changelog(
            client_root / "ui/dist/scripts/scripts.js"
        ),
        "locale.json": extract_locale(client_root / "locale"),
        "binaries.json": extract_binary_manifest(client_root),
    }
    for name, payload in payloads.items():
        payload["clientVersion"] = version.get("version")
        (output_dir / name).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    changelog = payloads["changelog.json"]
    locale = payloads["locale.json"]
    binaries = payloads["binaries.json"]
    print(f"client version : {version.get('version')}")
    print(
        f"changelog      : {changelog['revisionCount']} revisions, "
        f"{changelog['entryCount']} entries"
    )
    print(
        "locale         : "
        + ", ".join(
            f"{name} {info['keyCount']} keys"
            for name, info in locale["tables"].items()
        )
        + f", {locale['languageCount']} languages"
    )
    print(f"binaries       : {binaries['fileCount']} files")
    print(f"written to     : {output_dir}")


if __name__ == "__main__":
    main()
