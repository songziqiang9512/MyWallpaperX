#!/usr/bin/env python3

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_failure_state_benchmark import EXPECTED_CHECKS, validate_app_report
import web_failure_state_benchmark as benchmark
from web_debug_defaults import DEBUG_DEFAULTS_PREFIX, make_debug_defaults_suite


def passing_report() -> dict:
    return {
        "checks": {name: True for name in EXPECTED_CHECKS},
        "failureCount": 1,
        "passed": True,
        "preconditionFailure": None,
    }


class WebFailureStateBenchmarkTests(unittest.TestCase):
    def test_accepts_complete_passing_report(self) -> None:
        self.assertEqual(validate_app_report(passing_report()), [])

    def test_rejects_empty_report(self) -> None:
        self.assertTrue(validate_app_report({}))

    def test_rejects_missing_or_false_check(self) -> None:
        missing = passing_report()
        missing["checks"].pop("stopCleared")
        self.assertTrue(validate_app_report(missing))

        failed = passing_report()
        failed["checks"]["terminalCleared"] = False
        self.assertTrue(validate_app_report(failed))

    def test_rejects_precondition_and_duplicate_failure(self) -> None:
        report = passing_report()
        report["preconditionFailure"] = "fixture missing"
        report["failureCount"] = 2
        self.assertTrue(validate_app_report(report))

    def test_real_launch_requires_its_suite_log_and_cleans_up_after_exit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-failure-cli-") as temporary:
            for mode in ("confirmed", "missing", "foreign"):
                with self.subTest(log=mode):
                    root = Path(temporary) / mode
                    root.mkdir()
                    app = root / "FakeApp"
                    app.write_text(f"""#!{sys.executable}
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
suite = args[args.index('--mwx-debug-user-defaults-suite') + 1] if '--mwx-debug-user-defaults-suite' in args else None
report = Path(args[args.index('--mwx-debug-web-failure-state-report') + 1])
(report.parent / 'launch.json').write_text(json.dumps(dict(argv=args, suite=suite, pid=os.getpid(),
    home=os.environ.get('HOME'), fixed_home=os.environ.get('CFFIXED_USER_HOME'))))
if {mode!r} == 'confirmed' and suite:
    print('MWX DEBUG DEFAULTS: suite=' + suite, flush=True)
elif {mode!r} == 'foreign':
    print('MWX DEBUG DEFAULTS: suite={DEBUG_DEFAULTS_PREFIX}other', flush=True)
report.write_text({json.dumps(passing_report())!r})
while True: time.sleep(1)
""")
                    app.chmod(0o755)
                    args = argparse.Namespace(app=app, runtime_home=root / "home",
                        output_dir=root / "report", timeout=3.0, kill_existing=False)

                    def cleanup(suite, environment):
                        launched = json.loads((args.output_dir / "launch.json").read_text())
                        self.assertEqual(suite, launched["suite"])
                        self.assertEqual(environment["HOME"], launched["home"])
                        self.assertEqual(environment["CFFIXED_USER_HOME"], launched["fixed_home"])
                        stopped = terminate.call_args.args[0]
                        self.assertEqual(stopped.pid, launched["pid"])
                        self.assertIsNotNone(stopped.poll(), "suite cleanup preceded the owned process exit")

                    with mock.patch.object(benchmark, "make_debug_defaults_suite",
                            wraps=make_debug_defaults_suite, create=True) as make_suite, \
                         mock.patch.object(benchmark, "terminate_process", wraps=benchmark.terminate_process) as terminate, \
                         mock.patch.object(benchmark, "delete_debug_defaults_suite",
                            side_effect=cleanup, create=True) as delete_suite:
                        result = benchmark.run_benchmark(args)
                    launched = json.loads((args.output_dir / "launch.json").read_text())
                    report = json.loads((args.output_dir / "report.json").read_text())
                    self.assertEqual(launched["argv"].count("--mwx-debug-user-defaults-suite"), 1, launched)
                    make_suite.assert_called_once_with()
                    delete_suite.assert_called_once()
                    terminate.assert_called_once()
                    self.assertTrue(launched["suite"].startswith(DEBUG_DEFAULTS_PREFIX))
                    self.assertEqual(launched["home"], str(args.runtime_home.resolve()))
                    self.assertEqual(launched["fixed_home"], launched["home"])
                    self.assertEqual(report["app_report"], passing_report())
                    self.assertTrue(report["process_survived_until_report"])
                    confirmed = mode == "confirmed"
                    self.assertEqual(result, 0 if confirmed else 1)
                    self.assertEqual(report["passed"], confirmed)
                    self.assertEqual(report.get("debug_defaults_suite"), launched["suite"] if confirmed else None)
                    if not confirmed:
                        self.assertTrue(any("UserDefaults suite" in failure for failure in report["failures"]))

    def test_failed_popen_still_cleans_only_its_generated_suite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-failure-cli-exec-") as temporary:
            root = Path(temporary)
            app = root / "InvalidApp"
            app.write_text("not an executable format\n")
            app.chmod(0o755)
            args = argparse.Namespace(app=app, runtime_home=root / "home",
                output_dir=root / "report", timeout=3.0, kill_existing=False)
            with mock.patch.object(benchmark, "make_debug_defaults_suite",
                    wraps=make_debug_defaults_suite, create=True) as make_suite, \
                 mock.patch.object(benchmark, "terminate_process", wraps=benchmark.terminate_process) as terminate, \
                 mock.patch.object(benchmark, "delete_debug_defaults_suite", create=True) as delete_suite:
                with self.assertRaises(OSError):
                    benchmark.run_benchmark(args)
            make_suite.assert_called_once_with()
            delete_suite.assert_called_once()
            suite, environment = delete_suite.call_args.args
            self.assertTrue(suite.startswith(DEBUG_DEFAULTS_PREFIX))
            self.assertEqual(environment["HOME"], str(args.runtime_home.resolve()))
            self.assertEqual(environment["CFFIXED_USER_HOME"], environment["HOME"])
            terminate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
