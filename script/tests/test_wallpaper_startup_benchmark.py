"""Reject misleading startup rows and keep first selection out of W0 statistics."""
from contextlib import ExitStack
import copy
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import wallpaper_startup_benchmark as benchmark
from wallpaper_startup_benchmark import (
    PRODUCTION_BUNDLE_ID, STARTUP_BUNDLE_ID, input_paths_match, native_result_valid,
    reset_startup_defaults, summarize, summarize_paired,
)


class WallpaperStartupBenchmarkTests(unittest.TestCase):
    def web_row(self, request="new", elapsed=20):
        return {"requestID": request, "recordID": "sample", "entryToCommitMs": elapsed}

    def test_requires_matching_new_requests_and_numeric_timings(self):
        row = self.web_row()
        valid = {"passed": True, "timingSchemaVersion": 2, "rows": [row]}
        self.assertTrue(native_result_valid(valid, "web", "sample", "single"))
        self.assertTrue(native_result_valid(dict(valid, timingSchemaVersion=3,
                                               attributionStatus="unavailable"), "web", "sample", "single"))
        self.assertFalse(native_result_valid(dict(valid, timingSchemaVersion=1), "web", "sample", "single"))
        self.assertFalse(native_result_valid(dict(valid, timingSchemaVersion=4), "web", "sample", "single"))
        self.assertFalse(native_result_valid(dict(valid, rows=[row, row]), "web", "sample", "sequence"))
        self.assertFalse(native_result_valid(valid, "web", "other", "single"))
        for elapsed in (None, True, -1, float("nan"), float("inf")):
            self.assertFalse(native_result_valid(dict(valid, rows=[self.web_row(elapsed=elapsed)]),
                                                 "web", "sample", "single"))

    def test_scene_requires_presentation_and_finalization(self):
        row = {"recordID": "sample", "requestID": "new", "entryToPresentedMs": 20,
               "daemonPID": 42, "daemonGeneration": 1}
        result = {"passed": True, "rows": [row]}
        self.assertFalse(native_result_valid(result, "scene", "sample", "single"))
        row["entryToParentFinalizedMs"] = 25
        self.assertTrue(native_result_valid(result, "scene", "sample", "single"))
        row["passed"] = False
        self.assertFalse(native_result_valid(result, "scene", "sample", "single"))

    def test_scene_warm_requires_the_same_daemon_instance(self):
        one = {"recordID": "sample", "requestID": "one", "entryToPresentedMs": 20,
               "entryToParentFinalizedMs": 25, "daemonPID": 42, "daemonGeneration": 1}
        two = dict(one, requestID="two")
        native = {"passed": True, "rows": [one, two]}
        self.assertTrue(native_result_valid(native, "scene", "sample", "sequence"))
        two["daemonGeneration"] = 2
        self.assertFalse(native_result_valid(native, "scene", "sample", "sequence"))
        two.update(daemonGeneration=1, daemonPID=43)
        self.assertFalse(native_result_valid(native, "scene", "sample", "sequence"))

    def test_measured_input_must_match_the_hashed_sample(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            sample = root / "sample"
            sample.mkdir()
            entry = sample / "index.html"
            entry.write_text("owned fixture")
            native = {"recordRoot": str(sample), "entryPath": str(entry), "workshopRoot": str(root)}
            self.assertTrue(input_paths_match(native, "web", sample, root))
            self.assertFalse(input_paths_match(native, "web", root / "other", root))
            native["entryPath"] = str(root / "outside.html")
            self.assertFalse(input_paths_match(native, "web", sample, root))

    def test_warm_summary_excludes_initial_selection_and_failed_runs(self):
        runs = [{"passed": True, "condition": "W0", "native": {"rows": [
            self.web_row("one", 100), self.web_row("two", 20), self.web_row("three", 30)]}},
            {"passed": False, "condition": "W0", "native": {"rows": [self.web_row(elapsed=1)]}}]
        result = summarize(runs, "web")["W0"]
        self.assertEqual(result["count"], 2)
        self.assertEqual(result["medianMs"], 25)
        self.assertEqual(result["rangeMs"], [20, 30])

    def paired_runs(self, baseline=(20, 30), candidate=(10, 21), engine="web"):
        runs = []
        for iteration in range(len(baseline)):
            for arm, values in (("baseline", baseline), ("candidate", candidate)):
                for condition in ("C0", "C1", "W0"):
                    row = self.web_row(elapsed=values[iteration])
                    if engine == "scene":
                        row.update(entryToPresentedMs=values[iteration], entryToCommitMs=9999)
                    rows = [row]
                    if condition == "W0":
                        warm_count = 6 if engine == "web" else 1
                        rows = [dict(row, requestID="initial", entryToCommitMs=999,
                                     entryToPresentedMs=888)] + [
                            dict(row, requestID=f"warm-{index}") for index in range(warm_count)]
                    runs.append({"iteration": iteration, "condition": condition, "arm": arm,
                                 "passed": True, "native": {"passed": True, "rows": rows}})
        return runs

    def test_paired_summary_matches_iteration_and_uses_original_warm_values(self):
        for engine in ("web", "scene"):
            with self.subTest(engine=engine):
                runs = self.paired_runs(engine=engine)
                before = copy.deepcopy(runs)
                result = summarize_paired(list(reversed(runs)), engine, 2)
                self.assertTrue(result["complete"])
                self.assertFalse(result["performanceAccepted"])
                for condition in ("C0", "C1", "W0"):
                    summary = result["conditions"][condition]
                    self.assertEqual(summary["field"], "entryToPresentedMs" if engine == "scene" else "entryToCommitMs")
                    self.assertEqual(summary["count"], 2)
                    self.assertEqual([point["iteration"] for point in summary["pairs"]], [0, 1])
                    self.assertEqual([point["baselineMs"] for point in summary["pairs"]], [20, 30])
                    self.assertEqual([point["candidateMs"] for point in summary["pairs"]], [10, 21])
                    self.assertEqual([point["differenceMs"] for point in summary["pairs"]], [-10, -9])
                    self.assertEqual([point["differencePercent"] for point in summary["pairs"]], [-50, -30])
                    self.assertEqual(summary["medianDifferenceMs"], -9.5)
                    self.assertEqual(summary["medianDifferencePercent"], -40)
                    expected_count = 6 if engine == "web" and condition == "W0" else 1
                    self.assertEqual([point["baselineCount"] for point in summary["pairs"]],
                                     [expected_count, expected_count])
                    self.assertEqual(summary["withinAppAggregation"], "median")
                self.assertEqual(runs, before)

    def test_same_code_label_medians_do_not_replace_paired_differences(self):
        baseline = [238.328, 256.4, 229.955, 247.847, 261.041]
        candidate = [226.391, 231.724, 233.135, 281.215, 262.876]
        runs = self.paired_runs(baseline, candidate)
        result = summarize_paired(runs, "web", 5)["conditions"]["W0"]
        a = summarize([row for row in runs if row["arm"] == "baseline"], "web")["W0"]
        b = summarize([row for row in runs if row["arm"] == "candidate"], "web")["W0"]
        self.assertAlmostEqual(b["medianMs"] - a["medianMs"], -14.712)
        self.assertEqual([round(p["differenceMs"], 3) for p in result["pairs"]],
                         [-11.937, -24.676, 3.180, 33.368, 1.835])
        self.assertAlmostEqual(result["medianDifferenceMs"], 1.835)
        self.assertAlmostEqual(result["medianDifferencePercent"], 0.7029547078805228)

    def test_paired_summary_rejects_incomplete_duplicate_failed_or_mismatched_records(self):
        mutations = {
            "missing": lambda rows: rows.pop(),
            "duplicate": lambda rows: rows.__setitem__(-1, copy.deepcopy(rows[0])),
            "extra": lambda rows: rows.append(copy.deepcopy(rows[0])),
            "failed": lambda rows: rows[-1].update(passed=False),
            "unqualified": lambda rows: rows[-1].update(qualified=False),
            "cross-condition": lambda rows: rows[-1].update(condition="C0"),
            "unknown-condition": lambda rows: rows[-1].update(condition="X0"),
            "wrong-arm": lambda rows: rows[-1].update(arm="other"),
            "negative-iteration": lambda rows: rows[-1].update(iteration=-1),
            "past-iteration": lambda rows: rows[-1].update(iteration=2),
            "bool-iteration": lambda rows: rows[-1].update(iteration=True),
            "float-iteration": lambda rows: rows[-1].update(iteration=1.0),
            "missing-iteration": lambda rows: rows[-1].pop("iteration"),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                runs = self.paired_runs()
                mutate(runs)
                result = summarize_paired(runs, "web", 2)
                self.assertFalse(result["complete"])
                self.assertEqual(result["conditions"], {})
                self.assertFalse(result["performanceAccepted"])
        for iterations in (0, -1, True, 2.0, "2"):
            self.assertFalse(summarize_paired(self.paired_runs(), "web", iterations)["complete"])

    def test_paired_summary_rejects_invalid_or_ambiguous_timing_without_partial_statistics(self):
        for value in (None, True, "1", -1, float("nan"), float("inf")):
            with self.subTest(value=value):
                runs = self.paired_runs()
                runs[-1]["native"]["rows"][-1]["entryToCommitMs"] = value
                result = summarize_paired(runs, "web", 2)
                self.assertFalse(result["complete"])
                self.assertEqual(result["conditions"], {})
        for field in ("native", "rows"):
            runs = self.paired_runs()
            (runs[-1] if field == "native" else runs[-1]["native"]).pop(field)
            self.assertFalse(summarize_paired(runs, "web", 2)["complete"])
        runs = self.paired_runs()
        runs[-1]["native"]["rows"].append(self.web_row(elapsed=40))
        self.assertEqual(summarize_paired(runs, "web", 2)["conditions"], {})

    def test_web_seven_rows_form_one_app_median_not_six_independent_pairs(self):
        runs = self.paired_runs()
        warm = {"baseline": [[100, 1, 2, 3, 4, 100], [100, 101, 102, 103, 104, 105]],
                "candidate": [[20, 21, 22, 23, 24, 25], [90, 91, 92, 93, 94, 95]]}
        for run in runs:
            if run["condition"] == "W0":
                for row, value in zip(run["native"]["rows"][1:], warm[run["arm"]][run["iteration"]]):
                    row["entryToCommitMs"] = value
        before = copy.deepcopy(runs)
        result = summarize_paired(runs, "web", 2)
        self.assertTrue(result["complete"])
        self.assertFalse(result["performanceAccepted"])
        self.assertEqual(result["observationUnit"], "one App per iteration, arm and condition")
        summary = result["conditions"]["W0"]
        self.assertEqual(summary["count"], 2)
        self.assertTrue(summary["initialSelectionExcluded"])
        self.assertEqual([point["baselineMs"] for point in summary["pairs"]], [3.5, 102.5])
        self.assertEqual([point["candidateMs"] for point in summary["pairs"]], [22.5, 92.5])
        self.assertEqual([point["baselineValuesMs"] for point in summary["pairs"]], warm["baseline"])
        self.assertEqual([point["candidateValuesMs"] for point in summary["pairs"]], warm["candidate"])
        self.assertEqual([point["baselineCount"] for point in summary["pairs"]], [6, 6])
        self.assertEqual([point["candidateCount"] for point in summary["pairs"]], [6, 6])
        self.assertEqual([point["differenceMs"] for point in summary["pairs"]], [19, -10])
        self.assertEqual(summary["medianDifferenceMs"], 4.5)
        self.assertAlmostEqual(summary["medianDifferencePercent"], 266.55052264808366)
        # Pooling all warm selections or pairing a selected ordinal changes the estimand.
        a = summarize([run for run in runs if run["arm"] == "baseline"], "web")["W0"]
        b = summarize([run for run in runs if run["arm"] == "candidate"], "web")["W0"]
        self.assertEqual((a["count"], b["count"]), (12, 12))
        self.assertEqual(b["medianMs"] - a["medianMs"], -42.5)
        self.assertEqual(((20 - 100) + (90 - 100)) / 2, -45)
        self.assertEqual(runs, before)

    def test_web_paired_group_rejects_lost_extra_duplicate_failed_and_invalid_warm_rows(self):
        mutations = {
            "lost-warm": lambda rows: rows.pop(),
            "extra-warm": lambda rows: rows.append(self.web_row("extra", 40)),
            "duplicate-request": lambda rows: rows[3].update(requestID=rows[2]["requestID"]),
            "failed-row": lambda rows: rows[3].update(failed=True),
            "unsuccessful-row": lambda rows: rows[3].update(passed=False),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                runs = self.paired_runs()
                mutate(runs[-1]["native"]["rows"])
                result = summarize_paired(runs, "web", 2)
                self.assertFalse(result["complete"])
                self.assertEqual(result["conditions"], {})
        for value in (None, True, "1", -1, float("nan"), float("inf")):
            for index in (0, 3):
                with self.subTest(value=value, index=index):
                    runs = self.paired_runs()
                    runs[-1]["native"]["rows"][index]["entryToCommitMs"] = value
                    self.assertFalse(summarize_paired(runs, "web", 2)["complete"])

    def test_zero_baseline_keeps_every_millisecond_pair_and_nulls_condition_percentage(self):
        result = summarize_paired(self.paired_runs((0, 20), (5, 10)), "web", 2)
        self.assertTrue(result["complete"])
        for summary in result["conditions"].values():
            self.assertEqual(summary["count"], 2)
            self.assertEqual([p["differenceMs"] for p in summary["pairs"]], [5, -10])
            self.assertEqual([p["differencePercent"] for p in summary["pairs"]], [None, -50])
            self.assertEqual(summary["medianDifferenceMs"], -2.5)
            self.assertIsNone(summary["medianDifferencePercent"])
        both_zero = summarize_paired(self.paired_runs((0,), (0,)), "web", 1)["conditions"]["W0"]
        self.assertEqual(both_zero["medianDifferenceMs"], 0)
        self.assertIsNone(both_zero["medianDifferencePercent"])

    def test_defaults_reset_cannot_target_production_and_verifies_emptiness(self):
        with patch("wallpaper_startup_benchmark.subprocess.run") as command:
            with self.assertRaises(ValueError):
                reset_startup_defaults(PRODUCTION_BUNDLE_ID)
            command.assert_not_called()
        with patch("wallpaper_startup_benchmark.defaults_values", side_effect=[{"old": True}, {"old": True}]):
            with patch("wallpaper_startup_benchmark.subprocess.run"):
                with self.assertRaises(RuntimeError):
                    reset_startup_defaults(STARTUP_BUNDLE_ID)


    def test_interrupted_selection_stops_exact_children_before_reraising(self):
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
            root = Path(temporary)
            args = SimpleNamespace(engine="web", workshop_root=root, sample_root=root / "sample",
                                   item_id="sample", fps=30, timeout=10)
            primary = KeyboardInterrupt("cancel selection")
            known = {41: "owned-child-identity"}
            process = Mock(pid=40)
            process.poll.side_effect = [None, 0]
            stack.enter_context(patch.object(benchmark.subprocess, "Popen", return_value=process))
            stack.enter_context(patch.object(benchmark, "child_processes", return_value=known))
            terminate = stack.enter_context(patch.object(benchmark, "terminate_process", return_value=0))
            stack.enter_context(patch.object(benchmark, "living_owned_processes", side_effect=[known, {}]))
            stop = stack.enter_context(patch.object(benchmark, "stop_owned_children", return_value={}))
            stack.enter_context(patch.object(benchmark.time, "monotonic", side_effect=[0, 0, 0, 6]))
            stack.enter_context(patch.object(benchmark.time, "sleep", side_effect=primary))
            with self.assertRaises(KeyboardInterrupt) as raised:
                benchmark.run_selection(root / "app", args, root / "home", "suite", "token",
                                        root / "output", "single")
            self.assertIs(raised.exception, primary)
            terminate.assert_called_once_with(process)
            stop.assert_called_once_with(known)
            self.assertTrue(primary.startup_cleanup["ownedProcessesExited"])
            self.assertEqual(primary.startup_cleanup["remainingAfterFailureCleanup"], {})

    def test_cleanup_failures_do_not_hide_the_selection_exception(self):
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
            root = Path(temporary)
            args = SimpleNamespace(engine="web", workshop_root=root, sample_root=root / "sample",
                                   item_id="sample", fps=30, timeout=10)
            primary = OSError("selection observation failed")
            known = {41: "owned-child-identity"}
            process = Mock(pid=40)
            process.poll.return_value = 0
            stack.enter_context(patch.object(benchmark.subprocess, "Popen", return_value=process))
            stack.enter_context(patch.object(benchmark, "child_processes", side_effect=[primary, known]))
            stack.enter_context(patch.object(benchmark, "terminate_process", side_effect=RuntimeError("stop failed")))
            stack.enter_context(patch.object(benchmark, "living_owned_processes", return_value=known))
            stop = stack.enter_context(patch.object(benchmark, "stop_owned_children", side_effect=PermissionError()))
            stack.enter_context(patch.object(benchmark.time, "monotonic", side_effect=[0, 0, 0, 6]))
            stack.enter_context(patch.object(benchmark.sys, "stderr", io.StringIO()))
            with self.assertRaises(OSError) as raised:
                benchmark.run_selection(root / "app", args, root / "home", "suite", "token",
                                        root / "output", "single")
            self.assertIs(raised.exception, primary)
            stop.assert_called_once_with(known)
            self.assertFalse(primary.startup_cleanup["ownedProcessesExited"])
            self.assertEqual(primary.startup_cleanup["remainingAfterFailureCleanup"], known)
            self.assertEqual({x["operation"] for x in primary.startup_cleanup["errors"]},
                             {"terminate-app", "stop-owned-children"})

    def test_main_rechecks_production_after_an_exception_and_preserves_failure_environment(self):
        for exited, inspection_fails, cleanup_fails in (
            (True, False, False), (False, False, False), (True, True, False), (True, False, True)
        ):
            with self.subTest(exited=exited, inspection_fails=inspection_fails, cleanup_fails=cleanup_fails), \
                    tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
                root = Path(temporary)
                sample = root / "inputs/sample"
                sample.mkdir(parents=True)
                (sample / "project.json").write_text("{}")
                app = root / "staged.app"
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": STARTUP_BUNDLE_ID}))
                identity = {"bundle_identifier": STARTUP_BUNDLE_ID, "runtime_bundle_path": str(app)}
                output, runtime = root / "output", root / "runtime"
                argv = ["benchmark", "--app", str(app / "binary"), "--engine", "web",
                        "--sample-root", str(sample), "--workshop-root", str(sample.parent),
                        "--item-id", "sample", "--output-dir", str(output),
                        "--runtime-root", str(runtime), "--label", "mock-exception"]
                primary = KeyboardInterrupt("cancel benchmark")
                primary.startup_cleanup = {"ownedProcessesExited": exited, "errors": [],
                                           "remainingAfterFailureCleanup": {} if exited else {41: "owned"}}
                events = []
                def selection(*_args):
                    events.append("process-cleanup-completed")
                    raise primary
                def delete_suite(*_args):
                    events.append("delete-suite")
                    if cleanup_fails:
                        raise PermissionError("private suite cleanup failed")
                before = {"semanticSHA256": "before", "fileSHA256": "before"}
                after = OSError("fingerprint unavailable") if inspection_fails else dict(before)
                inspect = stack.enter_context(patch.object(benchmark, "production_preferences_identity",
                                                           side_effect=[before, after]))
                stack.enter_context(patch.object(benchmark, "stage_signed_app", return_value=(app / "binary", identity)))
                stack.enter_context(patch.object(benchmark, "run_selection", side_effect=selection))
                reset = stack.enter_context(patch.object(benchmark, "reset_startup_defaults",
                                                         side_effect=lambda _: events.append("reset-standard")))
                private = stack.enter_context(patch.object(benchmark, "delete_debug_defaults_suite",
                                                           side_effect=delete_suite))
                stack.enter_context(patch.object(benchmark.subprocess, "run"))
                discard = stack.enter_context(patch.object(benchmark, "discard_staged_app"))
                stack.enter_context(patch.object(benchmark.sys, "argv", argv))
                stack.enter_context(patch.object(benchmark.sys, "stderr", io.StringIO()))
                with self.assertRaises(KeyboardInterrupt) as raised:
                    benchmark.main()
                self.assertIs(raised.exception, primary)
                self.assertEqual(inspect.call_count, 2)
                self.assertEqual(reset.call_count, 2 if exited else 1)
                self.assertEqual(private.call_count, int(exited))
                self.assertEqual(events, ["reset-standard", "process-cleanup-completed"]
                                 + (["delete-suite", "reset-standard"] if exited else []))
                self.assertTrue(app.is_dir() and (runtime / "home-0").is_dir())
                discard.assert_not_called()
                diagnostic = json.loads((output / "failure.json").read_text())
                self.assertFalse(diagnostic["passed"])
                self.assertEqual(diagnostic["failureType"], "KeyboardInterrupt")
                self.assertEqual(diagnostic["testDefaultsRetained"], not exited or cleanup_fails)
                self.assertEqual(diagnostic["defaultsCleanupErrors"],
                                 [{"operation": "delete-private-suite", "errorType": "PermissionError"}]
                                 if cleanup_fails else [])
                if inspection_fails:
                    self.assertEqual(diagnostic["productionPreferencesInspectionErrorType"], "OSError")
                    self.assertIsNone(diagnostic["productionPreferencesUnchanged"])
                else:
                    self.assertTrue(diagnostic["productionPreferencesUnchanged"])


    def mock_scheduled_benchmark(self, *, paired, iterations=2, fail_arm=None):
        """Exercise main's scheduling and filesystem layout without any external process."""
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
            root = Path(temporary)
            sample = root / "inputs/sample"
            sample.mkdir(parents=True)
            (sample / "project.json").write_text("{}")
            sources = {arm: root / f"{arm}-source.app/binary" for arm in ("baseline", "candidate")}
            output, runtime = root / "output", root / "runtime"
            argv = ["benchmark", "--app", str(sources["candidate"]), "--engine", "web",
                    "--sample-root", str(sample), "--workshop-root", str(sample.parent),
                    "--item-id", "sample", "--output-dir", str(output), "--runtime-root", str(runtime),
                    "--iterations", str(iterations), "--label", "mock-schedule"]
            if paired:
                argv += ["--baseline-app", str(sources["baseline"])]
            binaries, selections, events = {}, [], []
            primary = KeyboardInterrupt("stop the current arm")
            primary.startup_cleanup = {"ownedProcessesExited": True, "errors": []}
            def stage(source, destination, *, runtime_bundle_name=None):
                arm = next(arm for arm, path in sources.items() if path == source)
                basename = runtime_bundle_name if runtime_bundle_name is not None else source.parent.name
                app = destination / f"runtime-app-{arm}" / basename
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": STARTUP_BUNDLE_ID}))
                binary = app / "Contents/MacOS/MyWallpaperX"
                binaries[str(binary)] = arm
                return binary, {"bundle_identifier": STARTUP_BUNDLE_ID, "runtime_bundle_path": str(app),
                                "executable_sha256": arm, "runtime_retained": True}
            def selection(binary, _args, home, suite, token, destination, mode):
                arm = binaries[str(binary)]
                condition = destination.name.split("-")[1]
                selections.append({"arm": arm, "home": str(home), "output": str(destination),
                                   "suite": suite, "token": token, "condition": condition, "mode": mode})
                events.append(f"{arm}:{condition}")
                if arm == fail_arm:
                    raise primary
                elapsed = 20 if arm == "baseline" else 10
                rows = [self.web_row(elapsed=elapsed)]
                if mode == "sequence":
                    rows = [self.web_row("initial", 999)] + [
                        self.web_row(f"warm-{index}", elapsed) for index in range(6)]
                return {"passed": True, "ownedProcessesExited": True, "native": {"rows": rows}}
            fingerprint = {"semanticSHA256": "mock", "fileSHA256": "mock"}
            inspect = stack.enter_context(patch.object(benchmark, "production_preferences_identity", return_value=fingerprint))
            staged = stack.enter_context(patch.object(benchmark, "stage_signed_app", side_effect=stage))
            stack.enter_context(patch.object(benchmark, "run_selection", side_effect=selection))
            stack.enter_context(patch.object(benchmark, "reset_startup_defaults", side_effect=lambda _: events.append("reset")))
            stack.enter_context(patch.object(benchmark, "delete_debug_defaults_suite", side_effect=lambda *_: events.append("delete-suite")))
            stack.enter_context(patch.object(benchmark.subprocess, "run"))
            verify = stack.enter_context(patch.object(benchmark, "verify_staged_app"))
            discard = stack.enter_context(patch.object(benchmark, "discard_staged_app",
                                                     side_effect=lambda identity: identity.update(runtime_retained=False)))
            stack.enter_context(patch.object(benchmark.sys, "argv", argv))
            stack.enter_context(patch.object(benchmark.sys, "stdout", io.StringIO()))
            stack.enter_context(patch.object(benchmark.sys, "stderr", io.StringIO()))
            if fail_arm is None:
                self.assertEqual(benchmark.main(), 0)
                report = json.loads((output / "report.json").read_text())
            else:
                with self.assertRaises(KeyboardInterrupt) as raised:
                    benchmark.main()
                self.assertIs(raised.exception, primary)
                report = json.loads((output / "failure.json").read_text())
            return {"report": report, "selections": selections, "events": events,
                    "stagedSources": [call.args[0] for call in staged.call_args_list], "sources": sources,
                    "verifyCount": verify.call_count, "discardCount": discard.call_count,
                    "productionInspections": inspect.call_count, "runtimeExists": runtime.exists()}

    def test_paired_arms_alternate_with_contiguous_conditions_and_separate_statistics(self):
        result = self.mock_scheduled_benchmark(paired=True)
        self.assertEqual(result["events"], sum([
            ["reset", f"{arm}:C0", f"{arm}:C1", f"{arm}:W0", "delete-suite", "reset"]
            for arm in ("baseline", "candidate", "candidate", "baseline")
        ], []))
        self.assertEqual(result["stagedSources"], [result["sources"]["baseline"], result["sources"]["candidate"]])
        self.assertEqual((result["verifyCount"], result["discardCount"], result["productionInspections"]), (2, 2, 2))
        self.assertFalse(result["runtimeExists"])
        report = result["report"]
        for identity in report["appIdentities"].values():
            self.assertEqual(Path(identity["runtime_bundle_path"]).name, "MyWallpaperX.app")
        self.assertEqual(set(report["summary"]), {"baseline", "candidate"})
        for arm, elapsed in (("baseline", 20), ("candidate", 10)):
            for condition in ("C0", "C1", "W0"):
                self.assertEqual(report["summary"][arm][condition]["valuesMs"],
                                 [elapsed] * (12 if condition == "W0" else 2))
        self.assertTrue(report["pairedSummary"]["complete"])
        self.assertFalse(report["pairedSummary"]["performanceAccepted"])
        self.assertEqual(report["pairedSummary"]["conditions"]["W0"]["medianDifferenceMs"], -10)

    def test_paired_paths_do_not_share_home_and_failure_retains_both_app_identities(self):
        result = self.mock_scheduled_benchmark(paired=True, iterations=1, fail_arm="candidate")
        selections = result["selections"]
        baseline, candidate = selections[:3], selections[3]
        self.assertEqual(len({row["home"] for row in baseline}), 1)
        self.assertEqual(len({row["suite"] for row in baseline}), 1)
        self.assertEqual(len({row["token"] for row in baseline}), 1)
        self.assertNotEqual(baseline[0]["home"], candidate["home"])
        self.assertNotEqual(baseline[0]["suite"], candidate["suite"])
        self.assertTrue(baseline[0]["home"].endswith("/runtime/baseline/home-0"))
        self.assertTrue(candidate["home"].endswith("/runtime/candidate/home-0"))
        self.assertTrue(baseline[0]["output"].endswith("/output/baseline/0-C0"))
        self.assertTrue(candidate["output"].endswith("/output/candidate/0-C0"))
        self.assertEqual(result["report"]["currentArm"], "candidate")
        self.assertEqual(set(result["report"]["appIdentities"]), {"baseline", "candidate"})
        self.assertEqual({row["arm"] for row in result["report"]["runs"]}, {"baseline"})
        self.assertEqual((result["discardCount"], result["productionInspections"]), (0, 2))
        self.assertTrue(result["runtimeExists"])

    def test_single_arm_keeps_original_paths_and_summary_shape(self):
        result = self.mock_scheduled_benchmark(paired=False, iterations=1)
        report = result["report"]
        self.assertNotIn("appIdentities", report)
        self.assertNotIn("pairedSummary", report)
        self.assertEqual(report["appIdentity"]["executable_sha256"], "candidate")
        self.assertEqual(Path(report["appIdentity"]["runtime_bundle_path"]).name, "MyWallpaperX.app")
        self.assertEqual(set(report["summary"]), {"C0", "C1", "W0"})
        self.assertEqual({row["arm"] for row in report["runs"]}, {"candidate"})
        self.assertTrue(result["selections"][0]["home"].endswith("/runtime/home-0"))
        self.assertTrue(result["selections"][0]["output"].endswith("/output/0-C0"))
        self.assertEqual((len(result["stagedSources"]), result["verifyCount"], result["discardCount"]), (1, 1, 1))
        self.assertEqual(report["summary"]["W0"]["valuesMs"], [10] * 6)


if __name__ == "__main__":
    unittest.main()
