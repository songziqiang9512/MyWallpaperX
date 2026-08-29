from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPECTRUM_SOURCES = [
    ROOT / "MyWallpaperX/Core/Playback/SystemAudioCaptureBuffer.swift",
    ROOT / "MyWallpaperX/Core/Playback/SystemAudioOverlaySpectrumAnalyzer.swift",
    ROOT / "MyWallpaperX/Core/Playback/SystemAudioWebSpectrumAnalyzer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebAudioSpectrum.swift",
]
SERVICE_SOURCE = ROOT / "MyWallpaperX/Core/Playback/SystemAudioSpectrumService.swift"
ENGINE_SOURCE = ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+SystemAudioSpectrum.swift"


class SystemAudioSpectrumTests(unittest.TestCase):
    def test_production_capture_and_analyzers(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import AudioToolbox
            import CoreAudio
            import Foundation

            enum SystemAudioSpectrumStyle {
                case balanced
                case banded
            }

            enum SystemAudioSpectrumSensitivity {
                case soft
                case normal
                case lively
            }

            enum PlaybackContentKind {
                case web
            }

            enum WebRuntimeCommand {
                case pushAudioSpectrum([Float])
            }

            final class WallpaperEngine {
                var currentPlaybackContentKind: PlaybackContentKind = .web
                var currentWebAudioSpectrumRequested = true
                var lastWebSpectrumPushAt: CFTimeInterval = 0
                var webSpectrumPushMinInterval: CFTimeInterval = 0
                var lastWebSpectrumLevels: [Float] = []
                var dispatchedWebLevels: [Float] = []

                func dispatchWebRuntimeCommand(_ command: WebRuntimeCommand) {
                    guard case let .pushAudioSpectrum(levels) = command else { return }
                    dispatchedWebLevels = levels
                }
            }

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            func expectNear(_ actual: Float, _ expected: Float, tolerance: Float, _ message: String) {
                expect(abs(actual - expected) <= tolerance, "\(message): \(actual) != \(expected)")
            }

            func expectArrayNear(
                _ actual: [Float],
                _ expected: [Float],
                tolerance: Float,
                _ message: String
            ) {
                expect(actual.count == expected.count, "\(message): count mismatch")
                for index in actual.indices {
                    expectNear(actual[index], expected[index], tolerance: tolerance, "\(message)[\(index)]")
                }
            }

            func format(
                flags: AudioFormatFlags,
                bits: UInt32,
                channelCount: Int,
                interleaved: Bool
            ) -> AudioStreamBasicDescription {
                let bytesPerSample = bits / 8
                let bytesPerFrame = bytesPerSample * UInt32(interleaved ? channelCount : 1)
                var resolvedFlags = flags | kAudioFormatFlagIsPacked
                if !interleaved {
                    resolvedFlags |= kAudioFormatFlagIsNonInterleaved
                }
                return AudioStreamBasicDescription(
                    mSampleRate: 48_000,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: resolvedFlags,
                    mBytesPerPacket: bytesPerFrame,
                    mFramesPerPacket: 1,
                    mBytesPerFrame: bytesPerFrame,
                    mChannelsPerFrame: UInt32(channelCount),
                    mBitsPerChannel: bits,
                    mReserved: 0
                )
            }

            func capturedFloatInterleaved(_ source: [Float], channelCount: Int) -> SystemAudioCapturedFrame {
                var samples = source
                let list = AudioBufferList.allocate(maximumBuffers: 1)
                defer { list.unsafeMutablePointer.deallocate() }
                list.count = 1
                let capture = SystemAudioCaptureBuffer(maximumFrameCount: source.count / channelCount)
                let didCapture = samples.withUnsafeMutableBufferPointer { pointer in
                    list[0] = AudioBuffer(
                        mNumberChannels: UInt32(channelCount),
                        mDataByteSize: UInt32(pointer.count * MemoryLayout<Float>.stride),
                        mData: pointer.baseAddress
                    )
                    return capture.capture(
                        list.unsafePointer,
                        streamDescription: format(
                            flags: kAudioFormatFlagIsFloat,
                            bits: 32,
                            channelCount: channelCount,
                            interleaved: true
                        )
                    )
                }
                expect(didCapture, "Float32 interleaved capture should succeed")
                return capture.decodedFrame!
            }

            func capturedFloatNoninterleaved(
                left sourceLeft: [Float],
                right sourceRight: [Float]
            ) -> SystemAudioCapturedFrame {
                var left = sourceLeft
                var right = sourceRight
                let list = AudioBufferList.allocate(maximumBuffers: 2)
                defer { list.unsafeMutablePointer.deallocate() }
                list.count = 2
                let capture = SystemAudioCaptureBuffer(maximumFrameCount: min(left.count, right.count))
                let didCapture = left.withUnsafeMutableBufferPointer { leftPointer in
                    right.withUnsafeMutableBufferPointer { rightPointer in
                        list[0] = AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(leftPointer.count * MemoryLayout<Float>.stride),
                            mData: leftPointer.baseAddress
                        )
                        list[1] = AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize: UInt32(rightPointer.count * MemoryLayout<Float>.stride),
                            mData: rightPointer.baseAddress
                        )
                        return capture.capture(
                            list.unsafePointer,
                            streamDescription: format(
                                flags: kAudioFormatFlagIsFloat,
                                bits: 32,
                                channelCount: 2,
                                interleaved: false
                            )
                        )
                    }
                }
                expect(didCapture, "Float32 noninterleaved capture should succeed")
                return capture.decodedFrame!
            }

            func capturedInt16Interleaved(_ source: [Int16], channelCount: Int) -> SystemAudioCapturedFrame {
                var samples = source
                let list = AudioBufferList.allocate(maximumBuffers: 1)
                defer { list.unsafeMutablePointer.deallocate() }
                list.count = 1
                let capture = SystemAudioCaptureBuffer(maximumFrameCount: source.count / channelCount)
                let didCapture = samples.withUnsafeMutableBufferPointer { pointer in
                    list[0] = AudioBuffer(
                        mNumberChannels: UInt32(channelCount),
                        mDataByteSize: UInt32(pointer.count * MemoryLayout<Int16>.stride),
                        mData: pointer.baseAddress
                    )
                    return capture.capture(
                        list.unsafePointer,
                        streamDescription: format(
                            flags: kAudioFormatFlagIsSignedInteger,
                            bits: 16,
                            channelCount: channelCount,
                            interleaved: true
                        )
                    )
                }
                expect(didCapture, "Int16 interleaved capture should succeed")
                return capture.decodedFrame!
            }

            func capturedInt32Interleaved(_ source: [Int32], channelCount: Int) -> SystemAudioCapturedFrame {
                var samples = source
                let list = AudioBufferList.allocate(maximumBuffers: 1)
                defer { list.unsafeMutablePointer.deallocate() }
                list.count = 1
                let capture = SystemAudioCaptureBuffer(maximumFrameCount: source.count / channelCount)
                let didCapture = samples.withUnsafeMutableBufferPointer { pointer in
                    list[0] = AudioBuffer(
                        mNumberChannels: UInt32(channelCount),
                        mDataByteSize: UInt32(pointer.count * MemoryLayout<Int32>.stride),
                        mData: pointer.baseAddress
                    )
                    return capture.capture(
                        list.unsafePointer,
                        streamDescription: format(
                            flags: kAudioFormatFlagIsSignedInteger,
                            bits: 32,
                            channelCount: channelCount,
                            interleaved: true
                        )
                    )
                }
                expect(didCapture, "Int32 interleaved capture should succeed")
                return capture.decodedFrame!
            }

            let left: [Float] = [0.25, -0.25, 0.75, -0.75]
            let right: [Float] = [-0.5, 0.5, -0.5, 0.5]
            let interleaved = zip(left, right).flatMap { [$0.0, $0.1] }
            let floatInterleaved = capturedFloatInterleaved(interleaved, channelCount: 2)
            expectArrayNear(floatInterleaved.signedChannels[0], left, tolerance: 0, "Float32 left")
            expectArrayNear(floatInterleaved.signedChannels[1], right, tolerance: 0, "Float32 right")
            expectArrayNear(
                floatInterleaved.rectifiedMono,
                [0.375, 0.375, 0.625, 0.625],
                tolerance: 0,
                "rectified mono"
            )

            let floatNoninterleaved = capturedFloatNoninterleaved(left: left, right: right)
            expectArrayNear(
                floatNoninterleaved.signedChannels[0],
                floatInterleaved.signedChannels[0],
                tolerance: 0,
                "Float32 layouts left"
            )
            expectArrayNear(
                floatNoninterleaved.signedChannels[1],
                floatInterleaved.signedChannels[1],
                tolerance: 0,
                "Float32 layouts right"
            )

            let int16 = interleaved.map { Int16(($0 * 32_768).rounded()) }
            let int32 = interleaved.map { Int32(($0 * 2_147_483_648).rounded()) }
            let decodedInt16 = capturedInt16Interleaved(int16, channelCount: 2)
            let decodedInt32 = capturedInt32Interleaved(int32, channelCount: 2)
            for channelIndex in 0..<2 {
                expectArrayNear(
                    decodedInt16.signedChannels[channelIndex],
                    floatInterleaved.signedChannels[channelIndex],
                    tolerance: 0.000_04,
                    "Int16 equivalence"
                )
                expectArrayNear(
                    decodedInt32.signedChannels[channelIndex],
                    floatInterleaved.signedChannels[channelIndex],
                    tolerance: 0.000_001,
                    "Int32 equivalence"
                )
            }

            let invalidPCM = capturedFloatInterleaved([Float.nan, Float.infinity], channelCount: 1)
            expect(invalidPCM.signedChannels[0] == [0, 0], "capture should sanitize non-finite PCM")
            expect(invalidPCM.rectifiedMono == [0, 0], "rectified mono should remain finite")

            let sampleRate: Float = 48_000
            let sampleCount = 4096
            func sine(frequency: Float, amplitude: Float = 0.8, phase: Float = 0) -> [Float] {
                (0..<sampleCount).map { index in
                    amplitude * sin(2 * .pi * frequency * Float(index) / sampleRate + phase)
                }
            }

            func peakIndex(_ levels: [Float], channel: Int) -> Int {
                let start = channel * SystemAudioWebSpectrumAnalyzer.channelBandCount
                let end = start + SystemAudioWebSpectrumAnalyzer.channelBandCount
                return levels[start..<end].enumerated().max { $0.element < $1.element }!.offset
            }

            func expectedBand(for frequency: Float) -> Int {
                let progress = log(frequency / 32) / log(20_000 / 32)
                return min(63, max(0, Int(floor(progress * 64))))
            }

            let webAnalyzer = SystemAudioWebSpectrumAnalyzer()
            let silence = webAnalyzer.analyze(signedChannels: [[Float](repeating: 0, count: sampleCount)], sampleRate: sampleRate)
            expect(silence.count == 128, "Web output must contain 128 levels")
            expect(silence.allSatisfy { $0 == 0 }, "silence must stay silent")
            expect(Array(silence[0..<64]) == Array(silence[64..<128]), "mono must duplicate L/R")

            let toneFrequencies: [Float] = [125, 500, 2_000, 8_000]
            let tonePeaks = toneFrequencies.map { frequency in
                let levels = webAnalyzer.analyze(signedChannels: [sine(frequency: frequency)], sampleRate: sampleRate)
                let peak = peakIndex(levels, channel: 0)
                expect(abs(peak - expectedBand(for: frequency)) <= 2, "tone peak should land near \(frequency) Hz")
                return peak
            }
            expect(zip(tonePeaks, tonePeaks.dropFirst()).allSatisfy(<), "tone peak bins must increase with frequency")

            let tone750 = sine(frequency: 750)
            let opposite750 = tone750.map(-)
            let antiPhase = webAnalyzer.analyze(
                signedChannels: [tone750, opposite750],
                sampleRate: sampleRate
            )
            let left750Peak = peakIndex(antiPhase, channel: 0)
            let right750Peak = peakIndex(antiPhase, channel: 1)
            expect(abs(left750Peak - expectedBand(for: 750)) <= 2, "750 Hz must not rectify to 1500 Hz")
            expect(abs(right750Peak - expectedBand(for: 750)) <= 2, "anti-phase 750 Hz must retain frequency")

            let stereo = webAnalyzer.analyze(
                signedChannels: [sine(frequency: 250), sine(frequency: 4_000)],
                sampleRate: sampleRate
            )
            expect(abs(peakIndex(stereo, channel: 0) - expectedBand(for: 250)) <= 2, "left 250 Hz")
            expect(abs(peakIndex(stereo, channel: 1) - expectedBand(for: 4_000)) <= 2, "right 4 kHz")

            let amplitudes: [Float] = [0.05, 0.2, 0.8]
            let amplitudeLevels = amplitudes.map { amplitude in
                webAnalyzer.analyze(
                    signedChannels: [sine(frequency: 1_000, amplitude: amplitude)],
                    sampleRate: sampleRate
                ).prefix(64).max()!
            }
            expect(amplitudeLevels[0] < amplitudeLevels[1], "fixed dBFS scale must retain 0.05 < 0.2")
            expect(amplitudeLevels[1] < amplitudeLevels[2], "fixed dBFS scale must retain 0.2 < 0.8")

            let compatibilityEngine = WallpaperEngine()
            expect(
                compatibilityEngine.dispatchWebAudioSpectrumIfNeeded(
                    Array(repeating: amplitudeLevels[2], count: 128)
                ),
                "Web spectrum should dispatch when requested"
            )
            let expectedCompatibilityPeak = pow(amplitudeLevels[2], 1.35) * 0.18
            expectNear(
                compatibilityEngine.dispatchedWebLevels.max()!,
                expectedCompatibilityPeak,
                tolerance: 0.000_001,
                "Web compatibility response"
            )
            expect(
                compatibilityEngine.dispatchedWebLevels.allSatisfy { $0 >= 0 && $0 <= 0.18 },
                "Web compatibility response must prevent overdriven sample visuals"
            )

            let stereoCompatibilityEngine = WallpaperEngine()
            let stereoInput = Array(repeating: Float(0.2), count: 64)
                + Array(repeating: Float(0.8), count: 64)
            expect(
                stereoCompatibilityEngine.dispatchWebAudioSpectrumIfNeeded(stereoInput),
                "Stereo Web spectrum should dispatch"
            )
            let deliveredStereo = stereoCompatibilityEngine.dispatchedWebLevels
            expect(deliveredStereo.count == 128, "Web compatibility response must retain 128 levels")
            expect(
                deliveredStereo[0] < deliveredStereo[64],
                "Web compatibility response must preserve independent stereo channels"
            )

            var nonFiniteTone = sine(frequency: 500)
            nonFiniteTone[10] = .nan
            nonFiniteTone[20] = .infinity
            nonFiniteTone[30] = -.infinity
            let finiteLevels = webAnalyzer.analyze(signedChannels: [nonFiniteTone], sampleRate: sampleRate)
            expect(
                finiteLevels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 },
                "Web levels must contain only finite 0...1 values"
            )

            let overlay = SystemAudioOverlaySpectrumAnalyzer(barCount: 16)
            let rectifiedTone = sine(frequency: 750, amplitude: 0.4).map(abs)
            let balanced = overlay.analyze(rectifiedMono: rectifiedTone, sampleRate: sampleRate)
            expect(balanced.count == 16, "Overlay must preserve configured bar count")
            expect(balanced.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "balanced overlay range")
            overlay.updateConfiguration(style: .banded, sensitivity: .normal)
            let banded = overlay.analyze(rectifiedMono: rectifiedTone, sampleRate: sampleRate)
            let released = overlay.analyze(
                rectifiedMono: [Float](repeating: 0, count: sampleCount),
                sampleRate: sampleRate
            )
            for index in banded.indices {
                expectNear(released[index], banded[index] * 0.84, tolerance: 0.000_001, "Overlay release smoothing")
            }
            expect(overlay.reset().allSatisfy { $0 == 0 }, "Overlay reset must clear smoothing")

            print("System audio spectrum tests passed")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-system-audio-tests-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "SystemAudioSpectrumTests"
            harness_path.write_text(harness, encoding="utf-8")
            subprocess.run(
                [swiftc, *(str(path) for path in SPECTRUM_SOURCES), str(harness_path), "-o", str(binary_path)],
                cwd=ROOT,
                check=True,
            )
            completed = subprocess.run(
                [str(binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("tests passed", completed.stdout)

    def test_scene_frames_preserve_capture_generation_and_scope(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        callback_declaration = source[
            source.index("var onSceneLevels:") : source.index("init(barCount:")
        ]
        self.assertIn("_ token: SceneAudioSpectrumCaptureToken", callback_declaration)

        start_capture = source[
            source.index("private func startCaptureIfNeeded()")
            : source.index("private func reconcileCaptureState()")
        ]
        self.assertIn("let resourceGeneration = captureResourceGeneration", start_capture)
        self.assertIn("let captureProcessScope = processScope", start_capture)
        self.assertIn("let captureToken = SceneAudioSpectrumCaptureToken(", start_capture)
        self.assertIn("resourceGeneration: resourceGeneration", start_capture)
        self.assertIn("token: captureToken", start_capture)

        process_frame = source[
            source.index("private func processCapturedAudio()")
            : source.index("private func clearSceneLevels()")
        ]
        identity_guard = process_frame.index(
            "pendingCaptureResourceGeneration == captureResourceGeneration"
        )
        scope_guard = process_frame.index(
            "pendingSceneCaptureToken.scopeEpoch == sceneCaptureScopeEpoch"
        )
        decoded_frame = process_frame.index("captureBuffer.decodedFrame")
        scene_callback = process_frame.index("onSceneLevels?(")
        self.assertLess(identity_guard, scope_guard)
        self.assertLess(scope_guard, decoded_frame)
        self.assertLess(decoded_frame, scene_callback)
        self.assertIn(
            "pendingSceneCaptureToken",
            process_frame,
            "Scene callback must report the captured frame's immutable scope token",
        )

    def test_scope_change_cancels_recovery_before_immediate_reconcile(self) -> None:
        source = SERVICE_SOURCE.read_text(encoding="utf-8")
        set_consumers = source[
            source.index("func setConsumers(") : source.index("func updateConfiguration(")
        ]
        self.assertNotIn(
            "if processScopeChanged, self.hasCaptureResources",
            set_consumers,
            "scope cleanup must also run while no capture resources exist",
        )
        self.assertRegex(
            set_consumers,
            r"(?s)if processScopeChanged \{\s*"
            r".*?self\.captureRetryWorkItem\?\.cancel\(\)\s*"
            r"self\.captureRetryWorkItem = nil\s*"
            r"self\.captureRetryAttempt = 0\s*"
            r"self\.cancelCaptureRestart\(\).*?"
            r"if self\.hasCaptureResources \{\s*self\.stopCapture\(\)\s*\}\s*"
            r"\}\s*self\.reconcileCaptureState\(\)",
        )

    def test_engine_publishes_scope_checked_system_capture(self) -> None:
        source = ENGINE_SOURCE.read_text(encoding="utf-8")
        scene_wiring = source[
            source.index("service.onSceneLevels =") : source.index("return service")
        ]
        self.assertEqual(
            scene_wiring.count("SceneAudioSpectrumInbox.shared.publishSystemCapture("),
            1,
        )
        self.assertNotIn("SceneAudioSpectrumInbox.shared.publish(", scene_wiring)
        self.assertIn("token in", scene_wiring)
        self.assertIn("token: token", scene_wiring)
        self.assertIn("sceneCaptureScopeEpoch: sceneDemand.scopeEpoch", source)


if __name__ == "__main__":
    unittest.main()
