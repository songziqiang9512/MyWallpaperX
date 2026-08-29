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

    static func configureCaptureBufferFrameSize(for deviceID: AudioObjectID) {
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

        var frameCount = UInt32(max(range.mMinimum, min(4096, range.mMaximum)))
        var frameSizeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID,
            &frameSizeAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &frameCount
        )
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
