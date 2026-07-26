#!/usr/bin/env python3
"""并行运行 Scene Python 测试套件。

现有 72 个测试模块里 66 个各自用 swiftc 编译独立 probe 且互不共享状态，
串行 unittest 一轮约 124s；按模块多进程并行后约 25s。本入口保持逐模块
独立进程的语义（与手工 `python3 -m unittest script.tests.<mod>` 一致），
只做调度与失败聚合，不改变任何测试内容。

用法：

    python3 script/run_scene_tests.py            # 全部 Scene 相关模块
    python3 script/run_scene_tests.py -j 4       # 限制并行度
    python3 script/run_scene_tests.py -k particle # 只跑名字含 particle 的模块
    python3 script/run_scene_tests.py --list     # 列出将要运行的模块
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import subprocess
import sys
import time
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TESTS_DIRECTORY = REPOSITORY_ROOT / "script/tests"


def discover_modules(keyword: str | None) -> list[str]:
    modules = []
    for path in sorted(TESTS_DIRECTORY.glob("test_*.py")):
        name = path.stem
        if keyword and keyword not in name:
            continue
        modules.append(f"script.tests.{name}")
    return modules


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=max(2, min(8, (os.cpu_count() or 4) - 2)),
        help="并行进程数（默认 min(8, cpu-2)）",
    )
    parser.add_argument("-k", "--keyword", help="只运行模块名包含该子串的模块")
    parser.add_argument("--list", action="store_true", help="仅列出模块，不运行")
    args = parser.parse_args()

    modules = discover_modules(args.keyword)
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
