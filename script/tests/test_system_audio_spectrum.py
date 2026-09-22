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
    ROOT / "MyWallpaperX/Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift",
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

            struct SceneAudioSpectrumSnapshot {
                static let bandCount = 16
                static let mediumBandCount = 32
                static let extendedBandCount = 64
            }

            enum PlaybackContentKind {
                case web
            }

            enum WebRuntimeCommand {
                case pushAudioSpectrum([Float])
            }

            final class WallpaperEngine {
                var currentPlaybackContentKind: PlaybackContentKind = .web
                var currentSystemAudioSpectrumEnabled = true
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

            let canonicalAnalyzer = SystemAudioSceneSpectrumAnalyzer()!
            let webAnalyzer = SystemAudioWebSpectrumAnalyzer()
            func webLevels(_ channels: [[Float]]) -> [Float] {
                canonicalAnalyzer.reset()
                return webAnalyzer.analyze(
                    canonicalAnalyzer.analyze(signedChannels: channels, sampleRate: sampleRate)
                )
            }

            let silence = webLevels([[Float](repeating: 0, count: sampleCount)])
            expect(silence.count == 128, "Web output must contain 128 levels")
            expect(silence.allSatisfy { $0 == 0 }, "silence must stay silent")
            expect(Array(silence[0..<64]) == Array(silence[64..<128]), "mono must duplicate L/R")

            let toneFrequencies: [Float] = [125, 500, 2_000, 8_000]
            let tonePeaks = toneFrequencies.map { frequency in
                let levels = webLevels([sine(frequency: frequency)])
                let peak = peakIndex(levels, channel: 0)
                return peak
            }
            expect(zip(tonePeaks, tonePeaks.dropFirst()).allSatisfy(<), "tone peak bins must increase with frequency")
            expect(tonePeaks.first! >= 0 && tonePeaks.last! < 64, "tone peaks must stay within the 64-band axis")

            let isolatedTone = webLevels([sine(frequency: 1_000)])
            let isolatedLeft = Array(isolatedTone.prefix(64))
            let isolatedPeak = isolatedLeft.max()!
            let quietBandCount = isolatedLeft.filter { $0 < isolatedPeak * 0.25 }.count
            expect(
                quietBandCount >= 56,
                "an isolated tone must not lift unrelated bars into a broadband floor"
            )

            let lowTonePeak = webLevels([sine(frequency: 125)]).prefix(64).max()!
            let highTonePeak = webLevels([sine(frequency: 8_000)]).prefix(64).max()!
            expect(
                highTonePeak > lowTonePeak * 0.45,
                "frequency compensation must keep the high end from collapsing"
            )

            let tone750 = sine(frequency: 750)
            let opposite750 = tone750.map(-)
            let antiPhase = webLevels([tone750, opposite750])
            let left750Peak = peakIndex(antiPhase, channel: 0)
            let right750Peak = peakIndex(antiPhase, channel: 1)
            expect(left750Peak == right750Peak, "anti-phase 750 Hz must retain the same frequency identity")
            expect(
                left750Peak > tonePeaks[1] && left750Peak < tonePeaks[2],
                "750 Hz must remain between 500 Hz and 2 kHz, not rectify to another band"
            )

            let stereo = webLevels([sine(frequency: 250), sine(frequency: 4_000)])
            expect(
                peakIndex(stereo, channel: 0) < peakIndex(stereo, channel: 1),
                "stereo channels must retain independent low-to-high frequency order"
            )

            canonicalAnalyzer.reset()
            let canonicalAttack = canonicalAnalyzer.analyze(
                signedChannels: [sine(frequency: 1_000, amplitude: 0.8)],
                sampleRate: sampleRate
            )
            expect(
                canonicalAttack.left.count == 16
                    && canonicalAttack.left32.count == 32
                    && canonicalAttack.left64.count == 64,
                "Producer must expose 16/32/64 projections"
            )
            expect(
                (canonicalAttack.left + canonicalAttack.left32 + canonicalAttack.left64)
                    .allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 },
                "Producer projections must stay finite and within 0...1"
            )
            for index in 0..<16 {
                let block = canonicalAttack.left64[(index * 4)..<(index * 4 + 4)]
                let average = block.reduce(0, +) / 4
                expectNear(
                    canonicalAttack.left[index],
                    average,
                    tolerance: 0.000_001,
                    "16-band projection must average its 64-band block"
                )
            }
            for index in 0..<32 {
                let block = canonicalAttack.left64[(index * 2)..<(index * 2 + 2)]
                let average = block.reduce(0, +) / 2
                expectNear(
                    canonicalAttack.left32[index],
                    average,
                    tolerance: 0.000_001,
                    "32-band projection must average its 64-band block"
                )
            }
            let ramp = (0..<64).map { Float($0) / 63 }
            let ramp28 = SystemAudioSceneSpectrumAnalyzer.resample(ramp, count: 28)
            expect(ramp28.count == 28, "64→28 projection must preserve requested count")
            expectNear(ramp28[0], 0.5 / 63, tolerance: 0.000_001, "64→28 first block")
            expectNear(ramp28[1], 2.5 / 63, tolerance: 0.000_001, "64→28 second block")
            expectNear(ramp28[27], 62 / 63, tolerance: 0.000_001, "64→28 final block")
            let ramp48 = SystemAudioSceneSpectrumAnalyzer.resample(ramp, count: 48)
            expect(ramp48.count == 48, "64→48 projection must preserve requested count")
            expectNear(ramp48[0], 0, tolerance: 0.000_001, "64→48 first block")
            expectNear(ramp48[2], 2.5 / 63, tolerance: 0.000_001, "64→48 split block")
            expectNear(ramp48[47], 62.5 / 63, tolerance: 0.000_001, "64→48 final block")
            let ramp96 = SystemAudioSceneSpectrumAnalyzer.resample(ramp, count: 96)
            expect(ramp96.count == 96, "64→96 projection must preserve requested count")
            expectNear(ramp96[0], 0, tolerance: 0.000_001, "64→96 first repeated block")
            expectNear(ramp96[1], 0, tolerance: 0.000_001, "64→96 repeated block")
            expectNear(ramp96[95], 1, tolerance: 0.000_001, "64→96 final repeated block")
            let canonicalRelease = canonicalAnalyzer.analyze(
                signedChannels: [[Float](repeating: 0, count: sampleCount)],
                sampleRate: sampleRate
            )
            expect(
                canonicalRelease.left64.max()! > 0
                    && canonicalRelease.left64.max()! < canonicalAttack.left64.max()!,
                "Producer release should remain visible while decaying"
            )
            var releaseTail = canonicalRelease.left64.max()!
            for _ in 0..<3 {
                releaseTail = canonicalAnalyzer.analyze(
                    signedChannels: [[Float](repeating: 0, count: sampleCount)],
                    sampleRate: sampleRate
                ).left64.max()!
            }
            expect(
                releaseTail < canonicalAttack.left64.max()! * 0.50,
                "release should not leave a long wave-like tail"
            )

            let amplitudes: [Float] = [0.05, 0.2, 0.8]
            let amplitudeLevels = amplitudes.map { amplitude in
                webLevels([sine(frequency: 1_000, amplitude: amplitude)]).prefix(64).max()!
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
            let expectedCompatibilityPeak = amplitudeLevels[2]
            expectNear(
                compatibilityEngine.dispatchedWebLevels.max()!,
                expectedCompatibilityPeak,
                tolerance: 0.000_001,
                "Web dispatch should preserve producer values"
            )
            expect(
                compatibilityEngine.dispatchedWebLevels.allSatisfy { $0 >= 0 && $0 <= 1 },
                "Web dispatch must preserve finite 0...1 values"
            )

            let consecutiveWebEngine = WallpaperEngine()
            let firstWebSnapshot = Array(repeating: Float(0.8), count: 128)
            let secondWebSnapshot = Array(repeating: Float(0.2), count: 128)
            expect(
                consecutiveWebEngine.dispatchWebAudioSpectrumIfNeeded(firstWebSnapshot),
                "First Web snapshot should dispatch"
            )
            expect(
                consecutiveWebEngine.dispatchWebAudioSpectrumIfNeeded(secondWebSnapshot),
                "Second Web snapshot should dispatch"
            )
            expectArrayNear(
                consecutiveWebEngine.dispatchedWebLevels,
                secondWebSnapshot,
                tolerance: 0,
                "Web dispatch must not add a second temporal tail"
            )

            let throttledWebEngine = WallpaperEngine()
            throttledWebEngine.webSpectrumPushMinInterval = 10
            throttledWebEngine.lastWebSpectrumPushAt = Double.greatestFiniteMagnitude
            let pendingFirst = Array(repeating: Float(0.8), count: 128)
            let pendingLatest = Array(repeating: Float(0.3), count: 128)
            expect(
                throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(pendingFirst),
                "Throttled first Web snapshot should be accepted"
            )
            expect(
                throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(pendingLatest),
                "Throttled latest Web snapshot should be accepted"
            )
            expect(
                throttledWebEngine.dispatchedWebLevels.isEmpty,
                "Throttled snapshots must wait for the next publish window"
            )
            expectArrayNear(
                throttledWebEngine.currentWebSpectrumSnapshot()!,
                pendingLatest,
                tolerance: 0,
                "Web snapshot reads must expose pending latest values"
            )
            throttledWebEngine.lastWebSpectrumPushAt = -1
            let pendingPublished = Array(repeating: Float(0.6), count: 128)
            expect(
                throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(pendingPublished),
                "Web snapshot should publish after throttle opens"
            )
            expectArrayNear(
                throttledWebEngine.dispatchedWebLevels,
                pendingPublished,
                tolerance: 0,
                "Throttle release must publish the latest pending value"
            )

            throttledWebEngine.lastWebSpectrumPushAt = Double.greatestFiniteMagnitude
            let silenceSnapshot = [Float](repeating: 0, count: 128)
            expect(
                throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(silenceSnapshot),
                "Silence should be accepted while throttled"
            )
            expectArrayNear(
                throttledWebEngine.dispatchedWebLevels,
                silenceSnapshot,
                tolerance: 0,
                "Silence must bypass throttle and clear the running Web value"
            )

            let dispatchedBeforeInvalid = throttledWebEngine.dispatchedWebLevels
            expect(
                !throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(
                    [Float](repeating: 0.4, count: 127)
                ),
                "Wrong-count Web input must be rejected"
            )
            expect(
                throttledWebEngine.currentWebSpectrumSnapshot()!.allSatisfy { $0 == 0 },
                "Wrong-count Web input must clear the pending snapshot"
            )
            expectArrayNear(
                throttledWebEngine.dispatchedWebLevels,
                dispatchedBeforeInvalid,
                tolerance: 0,
                "Wrong-count Web input must not dispatch an error command"
            )
            var nonFiniteWebInput = [Float](repeating: 0.4, count: 128)
            nonFiniteWebInput[7] = .nan
            expect(
                !throttledWebEngine.dispatchWebAudioSpectrumIfNeeded(nonFiniteWebInput),
                "Non-finite Web input must be rejected"
            )
            expect(
                throttledWebEngine.currentWebSpectrumSnapshot()!.allSatisfy { $0 == 0 },
                "Non-finite Web input must clear the pending snapshot"
            )

            let malformedWebEngine = WallpaperEngine()
            let malformedBaseline = Array(repeating: Float(0.7), count: 128)
            expect(
                malformedWebEngine.dispatchWebAudioSpectrumIfNeeded(malformedBaseline),
                "Malformed-input lifecycle should start from a non-zero Web value"
            )
            expect(
                !malformedWebEngine.dispatchWebAudioSpectrumIfNeeded(
                    [Float](repeating: 0.2, count: 127)
                ),
                "Wrong-count input after non-zero Web output must be rejected"
            )
            expect(
                malformedWebEngine.dispatchedWebLevels.allSatisfy { $0 == 0 },
                "Wrong-count input must immediately publish Web silence"
            )
            expect(
                malformedWebEngine.currentWebSpectrumSnapshot()!.allSatisfy { $0 == 0 },
                "Wrong-count input must clear the visible Web snapshot"
            )
            expect(
                malformedWebEngine.dispatchWebAudioSpectrumIfNeeded(malformedBaseline),
                "Web output should recover after malformed input"
            )
            var malformedNaNInput = malformedBaseline
            malformedNaNInput[3] = .nan
            expect(
                !malformedWebEngine.dispatchWebAudioSpectrumIfNeeded(malformedNaNInput),
                "Non-finite input after non-zero Web output must be rejected"
            )
            expect(
                malformedWebEngine.dispatchedWebLevels.allSatisfy { $0 == 0 },
                "Non-finite input must immediately publish Web silence"
            )
            expect(
                malformedWebEngine.currentWebSpectrumSnapshot()!.allSatisfy { $0 == 0 },
                "Non-finite input must clear the visible Web snapshot"
            )

            let inactiveMalformedWebEngine = WallpaperEngine()
            expect(
                inactiveMalformedWebEngine.dispatchWebAudioSpectrumIfNeeded(malformedBaseline),
                "Inactive-gate malformed test should start from a non-zero value"
            )
            let inactiveDispatchedBeforeMalformed = inactiveMalformedWebEngine.dispatchedWebLevels
            inactiveMalformedWebEngine.currentSystemAudioSpectrumEnabled = false
            expect(
                !inactiveMalformedWebEngine.dispatchWebAudioSpectrumIfNeeded(
                    [Float](repeating: 0.1, count: 127)
                ),
                "Inactive-gate malformed input must be rejected"
            )
            expectArrayNear(
                inactiveMalformedWebEngine.dispatchedWebLevels,
                inactiveDispatchedBeforeMalformed,
                tolerance: 0,
                "Inactive-gate malformed input must not dispatch"
            )
            expect(
                inactiveMalformedWebEngine.currentWebSpectrumSnapshot()!.allSatisfy { $0 == 0 },
                "Inactive-gate malformed input must clear local snapshot"
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
            let finiteLevels = webLevels([nonFiniteTone])
            expect(
                finiteLevels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 },
                "Web levels must contain only finite 0...1 values"
            )

            let overlay = SystemAudioOverlaySpectrumAnalyzer(barCount: 16)
            canonicalAnalyzer.reset()
            let overlayLevels = canonicalAnalyzer.analyze(
                signedChannels: [sine(frequency: 750, amplitude: 0.4)],
                sampleRate: sampleRate
            )
            let balanced = overlay.analyze(
                leftLevels: overlayLevels.left64,
                rightLevels: overlayLevels.right64
            )
            expect(balanced.count == 16, "Overlay must preserve configured bar count")
            expect(balanced.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "balanced overlay range")
            let shapedInput = [Float](repeating: 0.2, count: 16)
                + [Float](repeating: 0.5, count: 16)
                + [Float](repeating: 0.8, count: 16)
                + [Float](repeating: 0.35, count: 16)
            let freshOverlay = SystemAudioOverlaySpectrumAnalyzer(barCount: 16)
            let shaped = freshOverlay.analyze(
                leftLevels: shapedInput,
                rightLevels: shapedInput
            )
            expect(shaped[0] < shaped[4], "Overlay must retain a rising low-to-mid band")
            expect(shaped[4] < shaped[8], "Overlay must retain the stronger upper band")
            expect(shaped[12] < shaped[8], "Overlay must retain a falling right band")
            expect(
                shaped.max()! - shaped.min()! > 0.1,
                "A fresh loud frame must not clip every bar to the same height"
            )
            _ = freshOverlay.reset()
            let alternating = freshOverlay.analyze(
                leftLevels: (0..<16).map { $0.isMultiple(of: 2) ? 0.8 : 0.02 },
                rightLevels: (0..<16).map { $0.isMultiple(of: 2) ? 0.8 : 0.02 }
            )
            expect(
                alternating.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
                    && alternating[0] > alternating[1] * 3,
                "Overlay must preserve independent neighboring bars"
            )
            overlay.updateConfiguration(style: .banded, sensitivity: .normal)
            let banded = overlay.analyze(
                leftLevels: overlayLevels.left64,
                rightLevels: overlayLevels.right64
            )
            let repeatedBanded = overlay.analyze(
                leftLevels: overlayLevels.left64,
                rightLevels: overlayLevels.right64
            )
            expectArrayNear(
                repeatedBanded,
                banded,
                tolerance: 0,
                "Overlay projection must not add a second temporal envelope"
            )
            let silentOverlay = overlay.analyze(
                leftLevels: [Float](repeating: 0, count: 64),
                rightLevels: [Float](repeating: 0, count: 64)
            )
            expect(silentOverlay.allSatisfy { $0 == 0 }, "Overlay silence must clear immediately")
            expect(overlay.reset().allSatisfy { $0 == 0 }, "Overlay reset must return silence")

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
            source.index("private func startCaptureIfNeeded(")
            : source.index("private func reconcileCaptureState()")
        ]
        self.assertIn("let resourceGeneration = captureResourceGeneration", start_capture)
        self.assertIn("let captureProcessScope = processScope", start_capture)
        self.assertIn("let captureToken = SceneAudioSpectrumCaptureToken(", start_capture)
        self.assertIn("resourceGeneration: resourceGeneration", start_capture)
        self.assertIn("token: captureToken", start_capture)

        process_frame_start = source.index("private func processCapturedAudio()")
        process_frame = source[
            process_frame_start : source.index("\n    private func clearSceneLevels", process_frame_start)
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

    def test_bar_count_reconfigures_the_stable_capture_service(self) -> None:
        source = ENGINE_SOURCE.read_text(encoding="utf-8")
        configuration = source[
            source.index("public func configureSystemAudioSpectrum(")
            : source.index("func setWebAudioSpectrumRequested(")
        ]
        self.assertNotIn(
            "systemAudioSpectrumService =",
            configuration,
            "presentation changes must not replace the shared capture owner",
        )
        self.assertNotIn(
            "systemAudioSpectrumService.setConsumers(overlayEnabled: false",
            configuration,
            "bar-count changes must not tear down Web/Scene capture",
        )
        self.assertRegex(
            configuration,
            r"systemAudioSpectrumService\.updateConfiguration\(\s*"
            r"style: style,\s*sensitivity: sensitivity,\s*"
            r"barCount: normalizedBarCount\s*\)",
        )

    def test_global_spectrum_policy_gates_all_capture_consumers(self) -> None:
        engine = ENGINE_SOURCE.read_text(encoding="utf-8")
        web = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebAudioSpectrum.swift").read_text(encoding="utf-8")
        self.assertIn(
            "captureAllowed && currentSystemAudioSpectrumEnabled",
            engine,
        )
        self.assertIn(
            "currentSystemAudioSpectrumEnabled,",
            web,
        )
        self.assertIn(
            "|| !currentSystemAudioSpectrumEnabled",
            engine,
        )


if __name__ == "__main__":
    unittest.main()
