#!/usr/bin/env python3
"""Executable recovery/scope coordination tests for the shared audio service."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SERVICE_SOURCE = ROOT / "MyWallpaperX/Core/Playback/SystemAudioSpectrumService.swift"


class SystemAudioSpectrumRecoveryTests(unittest.TestCase):
    def test_retry_restart_and_scope_transitions_use_current_identity(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc is required for the executable service gate")

        harness = textwrap.dedent(
            r'''
            import Foundation
            import AudioToolbox
            import CoreAudio

            struct SceneAudioSpectrumCaptureToken: Equatable {
                let scopeEpoch: UInt64
                let includesCurrentProcessOutput: Bool
            }

            enum SystemAudioSpectrumStyle {
                case balanced
            }

            enum SystemAudioSpectrumSensitivity {
                case normal
            }

            struct SystemAudioCapturedFrame {
                let signedChannels: [[Float]]
                let rectifiedMono: [Float]
            }

            final class SystemAudioCaptureBuffer {
                init(maximumFrameCount: Int) {}
                var decodedFrame: SystemAudioCapturedFrame? { nil }
                func capture(
                    _ inputData: UnsafePointer<AudioBufferList>,
                    streamDescription: AudioStreamBasicDescription
                ) -> Bool {
                    false
                }
                func reset() {}
            }

            final class SystemAudioOverlaySpectrumAnalyzer {
                init(barCount: Int) {}
                func reset() -> [Float] { [] }
                func updateConfiguration(
                    style: SystemAudioSpectrumStyle,
                    sensitivity: SystemAudioSpectrumSensitivity
                ) {}
                func analyze(rectifiedMono: [Float], sampleRate: Float) -> [Float] { [] }
            }

            final class SystemAudioWebSpectrumAnalyzer {
                static let outputLevelCount = 128
                func analyze(_ frame: SystemAudioCapturedFrame, sampleRate: Float) -> [Float] { [] }
            }

            final class SystemAudioSceneSpectrumAnalyzer {
                struct Bands {
                    let left: [Float] = []
                    let right: [Float] = []
                    let left32: [Float] = []
                    let right32: [Float] = []
                    let left64: [Float] = []
                    let right64: [Float] = []
                }

                static let bandCount = 16
                static let mediumBandCount = 32
                static let extendedBandCount = 64
                init?() {}
                func reset() {}
                func analyze(_ frame: SystemAudioCapturedFrame, sampleRate: Float) -> Bands {
                    Bands()
                }
            }

            final class SystemAudioCaptureConfigurationMonitor {
                init(queue: DispatchQueue) {}
                func install(
                    tapID: AudioObjectID,
                    aggregateDeviceID: AudioObjectID,
                    onInvalidation: @escaping (String) -> Void
                ) throws {}
                func remove() {}
            }

            enum SystemAudioCaptureDeviceFactory {
                enum CaptureError: Error {
                    case currentProcessUnavailable
                    case osStatus(OSStatus)
                }

                static func currentProcessObjectID() -> AudioObjectID? { nil }
                static func createProcessTap(description: CATapDescription) throws -> AudioObjectID {
                    fatalError("DEBUG start suppression must prevent CoreAudio access")
                }
                static func fetchTapUID(for tapID: AudioObjectID) throws -> String { "" }
                static func fetchTapFormat(
                    for tapID: AudioObjectID
                ) throws -> AudioStreamBasicDescription {
                    AudioStreamBasicDescription()
                }
                static func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
                    fatalError("DEBUG start suppression must prevent CoreAudio access")
                }
                static func configureCaptureBufferFrameSize(for deviceID: AudioObjectID) {}
            }

            func expect(
                _ condition: @autoclosure () -> Bool,
                _ message: String,
                file: StaticString = #filePath,
                line: UInt = #line
            ) {
                guard condition() else {
                    fatalError("\(message) @ \(file):\(line)")
                }
            }

            func token(_ epoch: UInt64, includesCurrent: Bool) -> SceneAudioSpectrumCaptureToken {
                SceneAudioSpectrumCaptureToken(
                    scopeEpoch: epoch,
                    includesCurrentProcessOutput: includesCurrent
                )
            }

            #if DEBUG
            let service = SystemAudioSpectrumService(barCount: 16)
            service.debugEnableRecoveryTesting()

            // Initial consumer reconciliation executes the real start gate, but
            // the DEBUG seam suppresses all CoreAudio creation.
            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: false,
                sceneCaptureScopeEpoch: 0
            )
            var snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens == [token(0, includesCurrent: false)],
                   "initial exclude scope must reconcile immediately")

            // A pending retry has no capture resources. Both source-set
            // transitions must still cancel/reset it and immediately reconcile.
            service.debugScheduleCaptureRetryForTesting()
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureRetryAttempt == 1, "retry must advance backoff")
            expect(snapshot.hasCaptureRetryWorkItem, "retry must be pending")
            expect(snapshot.scheduledRecoveryKinds == ["retry"], "retry closure must be retained")

            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: true,
                sceneCaptureScopeEpoch: 1
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureRetryAttempt == 0, "include transition must reset backoff")
            expect(!snapshot.hasCaptureRetryWorkItem, "include transition must cancel retry")
            expect(snapshot.captureStartTokens.last == token(1, includesCurrent: true),
                   "include transition must reconcile with its new token")
            let startCountAfterInclude = snapshot.captureStartTokens.count
            expect(service.debugPerformScheduledRecoveryForTesting(at: 0),
                   "retained exclude retry closure must exist")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.count == startCountAfterInclude,
                   "stale exclude retry must not revive after include transition")

            service.debugScheduleCaptureRetryForTesting()
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureRetryAttempt == 1, "include retry must start from attempt one")
            expect(snapshot.hasCaptureRetryWorkItem, "include retry must be pending")
            expect(snapshot.scheduledRecoveryKinds == ["retry", "retry"],
                   "include retry closure must be retained")

            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: false,
                sceneCaptureScopeEpoch: 2
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureRetryAttempt == 0, "exclude transition must reset backoff")
            expect(!snapshot.hasCaptureRetryWorkItem, "exclude transition must cancel retry")
            expect(snapshot.captureStartTokens.last == token(2, includesCurrent: false),
                   "exclude transition must reconcile with a fresh epoch")
            let startCountAfterRoundTrip = snapshot.captureStartTokens.count
            expect(service.debugPerformScheduledRecoveryForTesting(at: 1),
                   "retained include retry closure must exist")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.count == startCountAfterRoundTrip,
                   "stale include retry must not revive after exclude round trip")

            // Execute the real invalidation closure in the current scope. It
            // stops the old resource generation and schedules restart-start.
            service.debugScheduleCaptureRestartForTesting()
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.scheduledRecoveryKinds == ["retry", "retry", "restart"],
                   "invalidation must retain its restart closure")
            expect(snapshot.hasCaptureRestartWorkItem, "restart must be pending")
            expect(service.debugPerformScheduledRecoveryForTesting(at: 2),
                   "current restart closure must execute")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStopCount == 1, "current restart must stop once")
            expect(snapshot.scheduledRecoveryKinds.last == "restart-start",
                   "current restart must schedule delayed start")
            let delayedRestartIndex = snapshot.scheduledRecoveryKinds.count - 1

            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: true,
                sceneCaptureScopeEpoch: 3
            )
            snapshot = service.debugRecoverySnapshot()
            expect(!snapshot.hasCaptureRestartWorkItem,
                   "scope transition must cancel delayed restart-start")
            expect(snapshot.captureStartTokens.last == token(3, includesCurrent: true),
                   "transition must immediately reconcile after restart cancellation")
            let startsBeforeStaleRestart = snapshot.captureStartTokens.count
            let stopsBeforeStaleRestart = snapshot.captureStopCount
            expect(service.debugPerformScheduledRecoveryForTesting(at: delayedRestartIndex),
                   "retained restart-start closure must exist")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.count == startsBeforeStaleRestart,
                   "stale restart-start must not revive the prior scope")
            expect(snapshot.captureStopCount == stopsBeforeStaleRestart,
                   "stale restart-start must not alter capture lifecycle")

            // An invalidation closure canceled before its delay must also stay
            // inert even when the test forces its body after a new epoch.
            service.debugScheduleCaptureRestartForTesting()
            snapshot = service.debugRecoverySnapshot()
            let staleInvalidationIndex = snapshot.scheduledRecoveryKinds.count - 1
            expect(snapshot.scheduledRecoveryKinds[staleInvalidationIndex] == "restart",
                   "second invalidation closure must be retained")
            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: false,
                sceneCaptureScopeEpoch: 4
            )
            snapshot = service.debugRecoverySnapshot()
            let scheduledBeforeStaleInvalidation = snapshot.scheduledRecoveryKinds.count
            let stopsBeforeStaleInvalidation = snapshot.captureStopCount
            expect(service.debugPerformScheduledRecoveryForTesting(at: staleInvalidationIndex),
                   "retained stale invalidation closure must exist")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.scheduledRecoveryKinds.count == scheduledBeforeStaleInvalidation,
                   "stale invalidation must not schedule another recovery")
            expect(snapshot.captureStopCount == stopsBeforeStaleInvalidation,
                   "stale invalidation must not stop the current scope")
            expect(snapshot.currentToken == token(4, includesCurrent: false),
                   "final scope identity must remain current")

            print("System audio recovery coordination tests passed")
            #else
            print("System audio recovery release compile passed")
            #endif
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-audio-recovery-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "SystemAudioSpectrumRecoveryTests"
            harness_path.write_text(harness, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    swiftc,
                    "-D",
                    "DEBUG",
                    str(SERVICE_SOURCE),
                    str(harness_path),
                    "-o",
                    str(binary_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                f"swiftc failed:\n{compile_result.stdout}\n{compile_result.stderr}",
            )
            completed = subprocess.run(
                [str(binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("recovery coordination tests passed", completed.stdout)

            release_binary_path = temporary / "SystemAudioSpectrumRecoveryReleaseCompile"
            release_compile_result = subprocess.run(
                [
                    swiftc,
                    str(SERVICE_SOURCE),
                    str(harness_path),
                    "-o",
                    str(release_binary_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                release_compile_result.returncode,
                0,
                "release swiftc failed:\n"
                f"{release_compile_result.stdout}\n{release_compile_result.stderr}",
            )
            release_completed = subprocess.run(
                [str(release_binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("release compile passed", release_completed.stdout)


if __name__ == "__main__":
    unittest.main()
