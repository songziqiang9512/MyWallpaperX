"""Real subprocess exits through the shared renderer watchdog and physical registry."""
from pathlib import Path
import os
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "MyWallpaperX/Core/DaemonKit"

HARNESS = r'''
import CoreFoundation
import Darwin
import Foundation

@main enum Harness {
    static func main() throws {
        let args = CommandLine.arguments
        let mode = args.count > 1 ? args[1] : "registry"
        if mode == "--launch" {
            let child = DaemonProcessTransport(executableURL: URL(fileURLWithPath: args[0]),
                arguments: [args[2], args[3]], playbackRenderer: true)
            try child.start()
            try "\(child.process.processIdentifier)".write(toFile: args[4], atomically: true, encoding: .utf8)
            while true { Thread.sleep(forTimeInterval: 1) }
        }
        if mode.hasPrefix("--child-") {
            signal(SIGPIPE, SIG_IGN)
            if mode == "--child-stubborn" {
                signal(SIGTERM, SIG_IGN)
                if args.count > 2 { try "ready".write(toFile: args[2], atomically: true, encoding: .utf8) }
                while true { Thread.sleep(forTimeInterval: 1) }
            }
            if mode == "--child-late-install" {
                try "entry".write(toFile: args[2] + ".entry", atomically: true, encoding: .utf8)
                Thread.sleep(forTimeInterval: 0.2)
            }
            let lifetime = DaemonParentLifetime(hardExitDelay: 0.45)
            if mode != "--child-initializing" {
                lifetime.setShutdownHandler {
                    if args.count > 2 {
                        try? "graceful".write(toFile: args[2] + ".exit", atomically: true, encoding: .utf8)
                    }
                    Darwin._exit(0)
                }
            }
            if args.count > 2 { try "ready".write(toFile: args[2], atomically: true, encoding: .utf8) }
            if mode == "--child-eof" || mode == "--child-eof-blocked" {
                DispatchQueue.global().async {
                    while readLine() != nil {}
                    lifetime.requestShutdown()
                    lifetime.requestShutdown()
                }
            }
            if mode == "--child-blocked" || mode == "--child-initializing" || mode == "--child-eof-blocked" {
                while true { Thread.sleep(forTimeInterval: 1) }
            }
            withExtendedLifetime(lifetime) { RunLoop.main.run() }
            return
        }

        let executable = URL(fileURLWithPath: args[0])
        let registry = DaemonPlaybackProcessRegistry(gracePeriod: 0.3, terminatePeriod: 0.2, killPeriod: 0.5)
        let nonPlayback = DaemonProcessTransport(executableURL: executable, arguments: ["--child-stubborn"])
        try nonPlayback.start()
        var renderers: [DaemonProcessTransport] = []
        // Active and candidate observe normal EOF; idle and already-retiring
        // intentionally ignore both EOF and TERM to require the common KILL tier.
        for mode in ["--child-eof", "--child-eof", "--child-stubborn", "--child-stubborn"] {
            let child = DaemonProcessTransport(executableURL: executable, arguments: [mode],
                playbackRenderer: true, playbackRegistry: registry)
            try child.start()
            renderers.append(child)
        }
        Thread.sleep(forTimeInterval: 0.1)
        precondition(registry.liveProcessIdentifiers.count == 4)
        // Remove the logical retiring reference. Registry must retain it until
        // actual exit, without depending on engine active/candidate dictionaries.
        renderers.removeLast()
        registry.closeAdmission()
        registry.closeAdmission()
        for child in renderers {
            child.requestGracefulStop(gracePeriod: 0.8)
            child.requestGracefulStop(gracePeriod: 0.9)
        }
        let rejected = DaemonProcessTransport(executableURL: executable, arguments: ["--child-stubborn"],
            playbackRenderer: true, playbackRegistry: registry)
        do { try rejected.start(); preconditionFailure("closed admission accepted a renderer") }
        catch { precondition(!rejected.isRunning) }
        var completions = 0
        var allExited = true
        for _ in 0..<2 {
            registry.waitForExit { result in
                allExited = allExited && result.allExited
                completions += 1
            }
        }
        let modal = RunLoop.Mode("NSModalPanelRunLoopMode")
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in }
        RunLoop.main.add(timer, forMode: modal)
        let started = ProcessInfo.processInfo.systemUptime
        while completions < 2 && ProcessInfo.processInfo.systemUptime - started < 2 {
            RunLoop.main.run(mode: modal, before: Date().addingTimeInterval(0.01))
        }
        precondition(completions == 2 && allExited, "actual exits must finish in AppKit's modal mode")
        precondition(registry.liveProcessIdentifiers.isEmpty)
        precondition(ProcessInfo.processInfo.systemUptime - started < 1.5, "shutdown multiplied deadlines per child")
        precondition(nonPlayback.isRunning, "non-playback process entered renderer shutdown")
        // A fresh instance has another physical identity and cannot be killed
        // by an old registry's pending deadline or a repeated stop callback.
        let newRegistry = DaemonPlaybackProcessRegistry()
        let fresh = DaemonProcessTransport(executableURL: executable, arguments: ["--child-stubborn"],
            playbackRenderer: true, playbackRegistry: newRegistry)
        try fresh.start()
        Thread.sleep(forTimeInterval: 0.7)
        precondition(fresh.isRunning && nonPlayback.isRunning)
        fresh.killIfRunning(); nonPlayback.killIfRunning()
        fresh.process.waitUntilExit(); nonPlayback.process.waitUntilExit()
        timer.invalidate()
        print("daemon-process-lifetime-pass")
    }
}
'''


class DaemonProcessLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-daemon-lifetime-")
        cls.work = Path(cls.directory.name)
        source = cls.work / "Harness.swift"
        source.write_text(HARNESS)
        cls.binary = cls.work / "harness"
        result = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library",
            str(KIT / "DaemonProcessTransport.swift"),
            str(KIT / "DaemonParentLifetime.swift"), str(source), "-o", str(cls.binary),
        ], capture_output=True, text=True, timeout=60)
        if result.returncode:
            cls.directory.cleanup()
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def wait_file(self, path):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.01)
        self.fail(f"child never reached watchdog installation: {path}")

    def wait_exit(self, pid):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            status = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "stat="],
                                    capture_output=True, text=True)
            if not status.stdout.strip() or status.stdout.strip().startswith("Z"):
                return
            time.sleep(0.02)
        self.fail(f"exact child {pid} survived parent death")

    def parent_death(self, mode, graceful):
        with tempfile.TemporaryDirectory(dir=self.work) as directory:
            root = Path(directory)
            ready, pidfile = root / "ready", root / "pid"
            parent = subprocess.Popen([str(self.binary), "--launch", mode, str(ready), str(pidfile)],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            pid = None
            try:
                self.wait_file(pidfile)
                pid = int(pidfile.read_text())
                self.wait_file(Path(str(ready) + ".entry") if mode == "--child-late-install" else ready)
                parent.kill()
                parent.wait(timeout=2)
                self.wait_exit(pid)
                pid = None
                self.assertEqual(Path(str(ready) + ".exit").exists(), graceful)
            finally:
                if parent.poll() is None:
                    parent.kill()
                parent.communicate(timeout=2)
                if pid is not None:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_parent_sigkill_requests_graceful_exit(self):
        self.parent_death("--child-parent", graceful=True)

    def test_parent_death_exits_with_child_main_blocked(self):
        self.parent_death("--child-blocked", graceful=False)

    def test_parent_death_during_initialization(self):
        self.parent_death("--child-initializing", graceful=False)

    def test_parent_exits_before_watchdog_installation(self):
        self.parent_death("--child-late-install", graceful=True)

    def test_eof_with_child_main_blocked_uses_hard_deadline(self):
        ready = self.work / "blocked-eof-ready"
        child = subprocess.Popen([str(self.binary), "--child-eof-blocked", str(ready)],
                                 stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.PIPE)
        try:
            self.wait_file(ready)
            child.stdin.close()
            self.assertEqual(child.wait(timeout=2), 70)
            self.assertFalse(Path(str(ready) + ".exit").exists())
        finally:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=2)
            child.stderr.close()

    def test_normal_eof_and_duplicate_shutdown(self):
        ready = self.work / "eof-ready"
        child = subprocess.Popen([str(self.binary), "--child-eof", str(ready)],
                                 stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.PIPE)
        try:
            self.wait_file(ready)
            child.stdin.close()
            self.assertEqual(child.wait(timeout=2), 0)
            self.assertEqual(Path(str(ready) + ".exit").read_text(), "graceful")
        finally:
            if child.poll() is None:
                child.kill()
            child.wait(timeout=2)
            child.stderr.close()

    def test_actual_exit_registry_deadlines_candidates_idle_and_instance_isolation(self):
        result = subprocess.run([str(self.binary)], capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("daemon-process-lifetime-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
