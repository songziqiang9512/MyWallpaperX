//
//  SystemAudioCaptureDeviceFactory.swift
//  MyWallpaperX
//

import AudioToolbox
import CoreAudio
import Foundation

enum SystemAudioCaptureDeviceFactory {
    @available(macOS 14.2, *)
    static func createProcessTap(description: CATapDescription) throws -> AudioObjectID {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapID
    }

    static func currentProcessObjectID() -> AudioObjectID? {
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }
        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }
        return processObjectID
    }

    static func createAggregateDevice(tapUID: CFString) throws -> AudioObjectID {
        let tapList: [[String: Any]] = [[
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: NSNumber(value: false)
        ]]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MyWallpaperX System Audio Spectrum",
            kAudioAggregateDeviceUIDKey: "com.songziqiang.MyWallpaperX.system-audio-spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: NSNumber(value: 1),
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceTapAutoStartKey: NSNumber(value: 1)
        ]

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &deviceID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return deviceID
    }

    static func configureCaptureBufferFrameSize(for deviceID: AudioObjectID, sampleRate: Double) {
        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &rangeAddress,
            0,
            nil,
            &rangeSize,
            &range
        ) == noErr else {
            return
        }

        guard let requestedFrames = captureBufferFrameCount(sampleRate: sampleRate, range: range) else { return }
        var frameCount = requestedFrames
        var frameSizeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            deviceID,
            &frameSizeAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &frameCount
        )
        var actualFrames: UInt32 = 0
        var actualSize = UInt32(MemoryLayout<UInt32>.size)
        let readStatus = AudioObjectGetPropertyData(deviceID, &frameSizeAddress, 0, nil, &actualSize, &actualFrames)
        NSLog("MWX AUDIO CAPTURE: buffer requested=%u actual=%u setStatus=%d readStatus=%d",
              frameCount, actualFrames, status, readStatus)
    }

    /// Only configures our private tap aggregate. About 10 ms of PCM keeps the
    /// analysis cadence responsive without requesting a tiny hardware quantum.
    static func captureBufferFrameCount(sampleRate: Double, range: AudioValueRange) -> UInt32? {
        guard sampleRate.isFinite, sampleRate > 0,
              range.mMinimum.isFinite, range.mMaximum.isFinite,
              range.mMinimum >= 1, range.mMaximum >= range.mMinimum,
              range.mMinimum.rounded(.up) <= range.mMaximum.rounded(.down),
              range.mMaximum <= Double(UInt32.max) else { return nil }
        var frames = 128.0
        let target = min(2048, max(128, sampleRate * 0.01))
        while frames < target { frames *= 2 }
        return UInt32(max(range.mMinimum.rounded(.up), min(frames, range.mMaximum.rounded(.down))))
    }

    static func fetchTapUID(for tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &tapUID) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapUID
    }

    static func fetchTapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return format
    }

    static func isDeviceAlive(_ deviceID: AudioObjectID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isAlive)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return isAlive != 0
    }

    enum CaptureError: LocalizedError {
        case osStatus(OSStatus)
        case currentProcessUnavailable

        var errorDescription: String? {
            switch self {
            case let .osStatus(status):
                return "CoreAudio OSStatus \(status)"
            case .currentProcessUnavailable:
                return "CoreAudio current process identity is unavailable"
            }
        }
    }
}
