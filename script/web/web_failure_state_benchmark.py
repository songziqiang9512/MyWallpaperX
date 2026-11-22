#!/usr/bin/env python3
"""Verify terminal Web failure ownership and Video recovery."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from web_debug_defaults import debug_defaults_suites, delete_debug_defaults_suite, make_debug_defaults_suite
from web_wallpaper_benchmark import APP_NAME, REPO_ROOT, terminate_process


DEFAULT_APP_BINARY = (
    REPO_ROOT / ".codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
)
EXPECTED_CHECKS = {
    "currentRecoveryNavigationFinished",
    "hostCleared",
    "managerStopped",
    "pageNavigationFinished",
    "payloadPreserved",
    "staleFailureIgnored",
    "staleNavigationIgnored",
    "staleRecoveryNavigationIgnored",
    "stopCleared",
    "terminalCleared",
    "videoRecovered",
    "webStarted",
}


def validate_app_report(report: Any) -> list[str]:
    failures: list[str] = []
    if not isinstance(report, dict):
        return ["app report is not a JSON object"]
    checks = report.get("checks")
    if not isinstance(checks, dict):
        failures.append("app report is missing named checks")
    else:
        names = set(checks)
        if names != EXPECTED_CHECKS:
            failures.append(f"check schema mismatch: {sorted(names)}")
        failed_checks = sorted(name for name, passed in checks.items() if passed is not True)
        if failed_checks:
            failures.append(f"failed checks: {failed_checks}")
    if report.get("failureCount") != 1:
        failures.append(f"expected one terminal failure notification, got {report.get('failureCount')!r}")
    if report.get("preconditionFailure") is not None:
        failures.append(f"runner precondition failed: {report.get('preconditionFailure')}")
    if report.get("passed") is not True:
        failures.append("runner did not report pass")
    return failures


def write_reports(output_dir: Path, report: dict[str, Any]) -> tuple[Path, Path]:
    json_path = output_dir / "report.json"
    markdown_path = output_dir / "report.md"
    json_path.write_text(json.dumps(report, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# MyWallpaperX Web Failure State Benchmark",
        "",
        f"- Result: {'PASS' if report['passed'] else 'FAIL'}",
        f"- Process survived until report: {report['process_survived_until_report']}",
        f"- Isolated runtime home: `{report['runtime_home']}`",
        f"- UserDefaults suite: `{report['debug_defaults_suite'] or '-'}`",
    ]
    if report["failures"]:
        lines.extend(["", "## Failures", ""])
        lines.extend(f"- {failure}" for failure in report["failures"])
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, markdown_path


def run_benchmark(args: argparse.Namespace) -> int:
    app_binary = Path(args.app).expanduser().resolve()
    runtime_home = Path(args.runtime_home).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    if not app_binary.is_file() or not os.access(app_binary, os.X_OK):
        print(f"App binary is missing or not executable: {app_binary}", file=sys.stderr)
        return 2
    runtime_home.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    app_report_path = output_dir / "app-report.json"
    app_report_path.unlink(missing_ok=True)
    log_path = output_dir / "app.log"
    if args.kill_existing:
        subprocess.run(["/usr/bin/pkill", "-x", APP_NAME], check=False)
        time.sleep(0.25)

    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    defaults_suite = make_debug_defaults_suite()
    command = [
        str(app_binary),
        "--mwx-debug-user-defaults-suite",
        defaults_suite,
        "--mwx-debug-suppress-main-window",
        "--mwx-debug-web-failure-state-report",
        str(app_report_path),
    ]
    process: subprocess.Popen[Any] | None = None
    process_survived = False
    app_report: Any = None
    failures: list[str] = []
    with log_path.open("w", encoding="utf-8") as log:
        try:
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                stdout=log,
                stderr=subprocess.STDOUT,
                env=environment,
                start_new_session=True,
            )
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                if app_report_path.is_file():
                    try:
                        app_report = json.loads(app_report_path.read_text(encoding="utf-8"))
                        process_survived = process.poll() is None
                        break
                    except (json.JSONDecodeError, OSError):
                        pass
                if process.poll() is not None:
                    failures.append(f"app exited before report with code {process.returncode}")
                    break
                time.sleep(0.1)
            else:
                failures.append("timed out waiting for app report")
        finally:
            if process is not None:
                terminate_process(process)
            delete_debug_defaults_suite(defaults_suite, environment)
    if not process_survived:
        failures.append("app did not survive until the report was complete")
    failures.extend(validate_app_report(app_report))
    defaults_confirmed = defaults_suite in debug_defaults_suites(log_path.read_text(encoding="utf-8", errors="replace"))
    if not defaults_confirmed:
        failures.append("isolated UserDefaults suite was not confirmed in app log")

    report = {
        "app_report": app_report,
        "failures": failures,
        "passed": not failures,
        "process_survived_until_report": process_survived,
        "runtime_home": str(runtime_home),
        "debug_defaults_suite": defaults_suite if defaults_confirmed else None,
    }
    json_path, markdown_path = write_reports(output_dir, report)
    print(f"Report JSON: {json_path}")
    print(f"Report Markdown: {markdown_path}")
    print(f"Web failure state result: {'PASS' if report['passed'] else 'FAIL'}")
    return 0 if report["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default=str(DEFAULT_APP_BINARY))
    parser.add_argument("--runtime-home", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--timeout", type=float, default=12.0)
    parser.add_argument("--kill-existing", action="store_true")
    return run_benchmark(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
