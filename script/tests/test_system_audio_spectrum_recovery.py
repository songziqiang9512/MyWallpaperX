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

            var configuredOverlayLevels: [Float] = []
            service.onLevels = { configuredOverlayLevels = $0 }

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

            // Overlay presentation changes stay inside the same capture owner.
            // They must replace only the queue-confined analyzer and must not
            // stop or restart Scene/Web capture.
            service.updateConfiguration(
                style: .balanced,
                sensitivity: .normal,
                barCount: 36
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.overlayBarCount == 36,
                   "bar-count update must reconfigure the live service")
            expect(configuredOverlayLevels.count == 36,
                   "bar-count update must publish the new cleared overlay shape")
            expect(snapshot.captureStopCount == 0,
                   "bar-count update must not tear down shared capture")
            expect(snapshot.captureStartTokens.count == 1,
                   "bar-count update must not create a second capture owner")

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
            // stops the old resource generation and enters the one shared
            // resource-retirement start gate.
            service.debugScheduleCaptureRestartForTesting()
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.scheduledRecoveryKinds == ["retry", "retry", "restart"],
                   "invalidation must retain its restart closure")
            expect(snapshot.hasCaptureRestartWorkItem, "restart must be pending")
            expect(service.debugPerformScheduledRecoveryForTesting(at: 2),
                   "current restart closure must execute")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStopCount == 1, "current restart must stop once")
            expect(snapshot.scheduledRecoveryKinds.last == "resource-retirement-start",
                   "current restart must schedule the shared delayed start")
            let delayedRestartIndex = snapshot.scheduledRecoveryKinds.count - 1

            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: true,
                sceneCaptureScopeEpoch: 3
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.hasCaptureRestartWorkItem,
                   "scope transition must replace the stale delayed start")
            expect(snapshot.scheduledRecoveryKinds.last == "resource-retirement-start",
                   "replacement scope must retain the shared retirement boundary")
            let replacementRestartIndex = snapshot.scheduledRecoveryKinds.count - 1
            let startsBeforeStaleRestart = snapshot.captureStartTokens.count
            let stopsBeforeStaleRestart = snapshot.captureStopCount
            expect(service.debugPerformScheduledRecoveryForTesting(at: delayedRestartIndex),
                   "retained restart-start closure must exist")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.count == startsBeforeStaleRestart,
                   "stale restart-start must not revive the prior scope")
            expect(snapshot.captureStopCount == stopsBeforeStaleRestart,
                   "stale restart-start must not alter capture lifecycle")
            expect(service.debugPerformScheduledRecoveryForTesting(
                at: replacementRestartIndex
            ), "replacement scope delayed start must execute")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.last == token(3, includesCurrent: true),
                   "replacement delayed start must use the new scope identity")

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

            // A real source-scope transition retires a live tap and aggregate
            // before the replacement can be created. That branch must wait for
            // CoreAudio to retire the old object identity instead of attempting
            // an immediate start that can fail with kAudioHardwareBadObjectError.
            service.debugSetSyntheticCaptureResourcesActiveForTesting(true)
            let startsBeforeResourceRetirement = snapshot.captureStartTokens.count
            let stopsBeforeResourceRetirement = snapshot.captureStopCount
            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: true,
                sceneCaptureScopeEpoch: 5
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStopCount == stopsBeforeResourceRetirement + 1,
                   "live scope transition must retire exactly one resource set")
            expect(snapshot.captureStartTokens.count == startsBeforeResourceRetirement,
                   "replacement scope must not start synchronously after retirement")
            expect(snapshot.scheduledRecoveryKinds.last == "resource-retirement-start",
                   "resource retirement must schedule the shared scope-aware start")
            expect(snapshot.hasCaptureRestartWorkItem,
                   "scope-aware delayed start must remain pending")
            let scopeTransitionStartIndex = snapshot.scheduledRecoveryKinds.count - 1
            expect(service.debugPerformScheduledRecoveryForTesting(
                at: scopeTransitionStartIndex
            ), "scope transition start closure must execute")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.last == token(5, includesCurrent: true),
                   "delayed start must use the replacement scope identity")
            expect(!snapshot.hasCaptureRestartWorkItem,
                   "executed delayed start must clear its pending identity")

            // A full demand stop has no consumer to schedule for, but a rapid
            // stop -> start must still honor the same retired CoreAudio object
            // boundary instead of taking the no-resource immediate path.
            service.debugSetSyntheticCaptureResourcesActiveForTesting(true)
            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: false,
                includeCurrentProcessAudio: false,
                sceneCaptureScopeEpoch: 6
            )
            snapshot = service.debugRecoverySnapshot()
            expect(!snapshot.hasCaptureRestartWorkItem,
                   "stopped demand must not schedule capture without a consumer")
            let startsBeforeRapidRestart = snapshot.captureStartTokens.count
            service.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: true,
                includeCurrentProcessAudio: false,
                sceneCaptureScopeEpoch: 7
            )
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.count == startsBeforeRapidRestart,
                   "rapid restart must not bypass the retirement boundary")
            expect(snapshot.scheduledRecoveryKinds.last == "resource-retirement-start",
                   "rapid restart must schedule the remaining retirement delay")
            let rapidRestartIndex = snapshot.scheduledRecoveryKinds.count - 1
            expect(service.debugPerformScheduledRecoveryForTesting(at: rapidRestartIndex),
                   "rapid restart closure must execute")
            snapshot = service.debugRecoverySnapshot()
            expect(snapshot.captureStartTokens.last == token(7, includesCurrent: false),
                   "rapid delayed restart must use the newest scope identity")

            func verifyTeardownFailure(
                _ name: String,
                stopStatuses: [OSStatus] = [],
                destroyIOProcStatuses: [OSStatus] = [],
                destroyAggregateStatuses: [OSStatus] = [],
                destroyTapStatuses: [OSStatus] = [],
                expectedIOProcAfterFailure: Bool,
                expectedAggregateAfterFailure: Bool,
                expectedTapAfterFailure: Bool,
                expectedCallbackStateResetCountAfterFailure: Int
            ) {
                let candidate = SystemAudioSpectrumService(barCount: 16)
                candidate.debugEnableRecoveryTesting()
                candidate.setConsumers(
                    overlayEnabled: false,
                    webEnabled: true,
                    sceneEnabled: true,
                    includeCurrentProcessAudio: false,
                    sceneCaptureScopeEpoch: 0
                )
                var state = candidate.debugRecoverySnapshot()
                expect(state.captureStartTokens == [token(0, includesCurrent: false)],
                       "\(name): initial shared capture must start once")
                candidate.debugSetSyntheticCaptureResourcesActiveForTesting(true)
                candidate.debugSetCaptureTeardownStatusesForTesting(
                    stop: stopStatuses,
                    destroyIOProc: destroyIOProcStatuses,
                    destroyAggregate: destroyAggregateStatuses,
                    destroyTap: destroyTapStatuses
                )
                candidate.setConsumers(
                    overlayEnabled: false,
                    webEnabled: true,
                    sceneEnabled: true,
                    includeCurrentProcessAudio: true,
                    sceneCaptureScopeEpoch: 1
                )
                state = candidate.debugRecoverySnapshot()
                expect(state.hasCaptureTeardownRetryWorkItem,
                       "\(name): failed teardown must retain a retry owner")
                expect(state.scheduledRecoveryKinds.last == "resource-teardown-retry",
                       "\(name): failed teardown must schedule only teardown")
                expect(state.captureStartTokens.count == 1,
                       "\(name): failed teardown must block replacement capture")
                expect(state.hasSyntheticIOProc == expectedIOProcAfterFailure,
                       "\(name): IOProc identity retention mismatch")
                expect(state.hasSyntheticAggregate == expectedAggregateAfterFailure,
                       "\(name): aggregate identity retention mismatch")
                expect(state.hasSyntheticTap == expectedTapAfterFailure,
                       "\(name): tap identity retention mismatch")
                expect(state.callbackStateResetCount
                        == expectedCallbackStateResetCountAfterFailure,
                       "\(name): callback-owned state reset before IOProc retirement")

                candidate.debugSimulateStaleCapturedFrameProcessingForTesting()
                state = candidate.debugRecoverySnapshot()
                expect(state.capturedFrameReadCount == 0,
                       "\(name): stale generation must not read callback-owned frame state")
                expect(state.callbackStateResetCount
                        == expectedCallbackStateResetCountAfterFailure,
                       "\(name): stale processing must not mutate callback-owned state")

                let teardownRetryIndex = state.scheduledRecoveryKinds.count - 1
                expect(candidate.debugPerformScheduledRecoveryForTesting(
                    at: teardownRetryIndex
                ), "\(name): teardown retry closure must execute")
                state = candidate.debugRecoverySnapshot()
                expect(!state.hasCaptureTeardownRetryWorkItem,
                       "\(name): successful retry must clear teardown owner")
                expect(!state.hasSyntheticIOProc
                        && !state.hasSyntheticAggregate
                        && !state.hasSyntheticTap,
                       "\(name): successful retry must retire every resource")
                expect(state.callbackStateResetCount == 1,
                       "\(name): callback-owned state must reset exactly once after IOProc retirement")
                expect(state.captureStartTokens.count == 1,
                       "\(name): retirement delay must still block immediate replacement")
                expect(state.scheduledRecoveryKinds.last == "resource-retirement-start",
                       "\(name): successful teardown must enter the shared retirement gate")
                let replacementIndex = state.scheduledRecoveryKinds.count - 1
                expect(candidate.debugPerformScheduledRecoveryForTesting(
                    at: replacementIndex
                ), "\(name): replacement start closure must execute")
                state = candidate.debugRecoverySnapshot()
                expect(state.captureStartTokens.last == token(1, includesCurrent: true),
                       "\(name): replacement must use current scope after teardown")
            }

            let teardownFailure = OSStatus(-7777)
            verifyTeardownFailure(
                "device-stop",
                stopStatuses: [teardownFailure],
                expectedIOProcAfterFailure: true,
                expectedAggregateAfterFailure: true,
                expectedTapAfterFailure: true,
                expectedCallbackStateResetCountAfterFailure: 0
            )
            verifyTeardownFailure(
                "destroy-ioproc",
                destroyIOProcStatuses: [teardownFailure],
                expectedIOProcAfterFailure: true,
                expectedAggregateAfterFailure: true,
                expectedTapAfterFailure: true,
                expectedCallbackStateResetCountAfterFailure: 0
            )
            verifyTeardownFailure(
                "destroy-aggregate",
                destroyAggregateStatuses: [teardownFailure],
                expectedIOProcAfterFailure: false,
                expectedAggregateAfterFailure: true,
                expectedTapAfterFailure: true,
                expectedCallbackStateResetCountAfterFailure: 1
            )
            verifyTeardownFailure(
                "destroy-tap",
                destroyTapStatuses: [teardownFailure],
                expectedIOProcAfterFailure: false,
                expectedAggregateAfterFailure: false,
                expectedTapAfterFailure: true,
                expectedCallbackStateResetCountAfterFailure: 1
            )

            // CoreAudio's bad-object status proves the device identity is
            // already absent, so it can close the dependency chain without a
            // teardown retry while still preserving the retirement delay.
            let absent = SystemAudioSpectrumService(barCount: 16)
            absent.debugEnableRecoveryTesting()
            absent.setConsumers(
                overlayEnabled: true,
                webEnabled: false,
                sceneEnabled: false
            )
            absent.debugSetSyntheticCaptureResourcesActiveForTesting(true)
            absent.debugSetCaptureTeardownStatusesForTesting(
                stop: [kAudioHardwareBadObjectError]
            )
            absent.setConsumers(
                overlayEnabled: false,
                webEnabled: false,
                sceneEnabled: false,
                sceneCaptureScopeEpoch: 1
            )
            let absentState = absent.debugRecoverySnapshot()
            expect(!absentState.hasCaptureTeardownRetryWorkItem,
                   "bad-object must count as an already absent device")
            expect(!absentState.hasSyntheticIOProc
                    && !absentState.hasSyntheticAggregate
                    && !absentState.hasSyntheticTap,
                   "bad-object must clear only the proven-absent dependency chain")

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
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                completed.returncode,
                0,
                f"harness failed:\n{completed.stdout}\n{completed.stderr}",
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
