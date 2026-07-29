#!/usr/bin/env python3
"""按模块并行运行仓库 Python 测试。

默认保持历史行为，运行 ``script/tests`` 下的全部 ``test_*.py`` 模块。
``--scope scene`` 只选择 ``test_scene_*.py``；共享的非 Scene 前缀模块可用
可重复的 ``--module`` 精确追加。可重复的 ``-k`` 对 scope 选择结果执行
OR 过滤。本入口保持逐模块独立进程的语义（与手工
``python3 -m unittest script.tests.<mod>`` 一致），只做调度与失败聚合。

用法：

    python3 script/run_scene_tests.py
    python3 script/run_scene_tests.py --scope scene -j 4
    python3 script/run_scene_tests.py --scope scene -k particle -k audio
    python3 script/run_scene_tests.py --scope scene \
        --module test_system_audio_spectrum
    python3 script/run_scene_tests.py --scope scene --list
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import subprocess
import sys
import time
from collections.abc import Iterable, Sequence
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TESTS_DIRECTORY = REPOSITORY_ROOT / "script/tests"


def discover_modules(
    available_modules: Iterable[str],
    *,
    scope: str = "all",
    keywords: Sequence[str] = (),
    requested_modules: Sequence[str] = (),
) -> list[str]:
    """Select fully qualified unittest modules without reading global state."""
    if scope not in {"all", "scene"}:
        raise ValueError(f"unsupported test scope: {scope}")

    available = sorted(set(available_modules))
    available_set = set(available)
    unknown = sorted(set(requested_modules) - available_set)
    if unknown:
        raise ValueError(f"unknown test module(s): {', '.join(unknown)}")

    scoped = (
        available
        if scope == "all"
        else [name for name in available if name.startswith("test_scene_")]
    )
    if keywords:
        scoped = [
            name
            for name in scoped
            if any(keyword in name for keyword in keywords)
        ]

    selected = sorted(set(scoped).union(requested_modules))
    return [f"script.tests.{name}" for name in selected]


def positive_job_count(value: str) -> int:
    try:
        jobs = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("jobs must be an integer") from error
    if jobs < 1:
        raise argparse.ArgumentTypeError("jobs must be at least 1")
    return jobs


def nonempty_value(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise argparse.ArgumentTypeError("value must not be empty")
    return stripped


def parse_arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--scope",
        choices=("all", "scene"),
        default="all",
        help="all runs every test_*.py module; scene selects only test_scene_*.py",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=positive_job_count,
        default=max(2, min(8, (os.cpu_count() or 4) - 2)),
        help="并行进程数（默认 min(8, cpu-2)）",
    )
    parser.add_argument(
        "-k",
        "--keyword",
        action="append",
        default=[],
        type=nonempty_value,
        help="按模块名子串过滤 scope；可重复，多个值按 OR 匹配",
    )
    parser.add_argument(
        "--module",
        action="append",
        default=[],
        type=nonempty_value,
        help="精确追加测试模块 basename（例如 test_system_audio_spectrum）；可重复",
    )
    parser.add_argument("--list", action="store_true", help="仅列出模块，不运行")
    return parser.parse_args(argv)


def run_module(module: str) -> tuple[str, int, float, str]:
    started = time.monotonic()
    completed = subprocess.run(
        [sys.executable, "-m", "unittest", module],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - started
    output = (completed.stdout + completed.stderr).strip()
    return module, completed.returncode, elapsed, output


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments(argv)
    available_modules = sorted(
        path.stem for path in TESTS_DIRECTORY.glob("test_*.py")
    )
    try:
        modules = discover_modules(
            available_modules,
            scope=args.scope,
            keywords=args.keyword,
            requested_modules=args.module,
        )
    except ValueError as error:
        print(f"测试选择失败: {error}", file=sys.stderr)
        return 2
    if not modules:
        print("没有匹配的测试模块", file=sys.stderr)
        return 2
    if args.list:
        for module in modules:
            print(module)
        return 0

    started = time.monotonic()
    failures: list[tuple[str, str]] = []
    slowest: list[tuple[float, str]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(run_module, module): module for module in modules}
        for future in concurrent.futures.as_completed(futures):
            module, returncode, elapsed, output = future.result()
            slowest.append((elapsed, module))
            status = "OK" if returncode == 0 else "FAIL"
            print(f"{status:4s} {elapsed:6.1f}s  {module.rsplit('.', 1)[-1]}", flush=True)
            if returncode != 0:
                failures.append((module, output))

    total = time.monotonic() - started
    print(f"\n{len(modules)} modules in {total:.1f}s with {args.jobs} jobs")
    slowest.sort(reverse=True)
    print("slowest:", ", ".join(f"{name.rsplit('.', 1)[-1]} {dt:.1f}s" for dt, name in slowest[:5]))

    if failures:
        print(f"\n{len(failures)} module(s) FAILED:", file=sys.stderr)
        for module, output in failures:
            tail = "\n".join(output.splitlines()[-30:])
            print(f"\n===== {module} =====\n{tail}", file=sys.stderr)
        return 1
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
