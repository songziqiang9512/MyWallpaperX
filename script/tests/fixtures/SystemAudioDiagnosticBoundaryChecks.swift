import AudioToolbox
import CoreAudio
import Foundation

// Only the two CoreAudio property I/O symbols in a task copy are redirected.
// The actual factory decisions and captured-frame implementation stay intact.
nonisolated enum CaptureError: Error { case osStatus(OSStatus) }

nonisolated enum PropertyIO {
    nonisolated(unsafe) static var events: [String] = []
    nonisolated(unsafe) static var range = AudioValueRange(mMinimum: 128, mMaximum: 2048)
    nonisolated(unsafe) static var rangeStatus: OSStatus = noErr
    nonisolated(unsafe) static var setStatus: OSStatus = noErr
    nonisolated(unsafe) static var frameCount: UInt32 = 1024
    nonisolated(unsafe) static var requested: UInt32?

    static func reset() {
        events = []
        range = AudioValueRange(mMinimum: 128, mMaximum: 2048)
        rangeStatus = noErr
        setStatus = noErr
        frameCount = 1024
        requested = nil
    }
}

nonisolated func fixtureAudioObjectGetPropertyData(
    _ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UnsafeMutablePointer<UInt32>, _ output: UnsafeMutableRawPointer
) -> OSStatus {
    precondition(object == 17 && qualifierSize == 0 && qualifier == nil)
    switch address.pointee.mSelector {
    case kAudioDevicePropertyBufferFrameSizeRange:
        PropertyIO.events.append("range")
        if PropertyIO.rangeStatus == noErr {
            output.assumingMemoryBound(to: AudioValueRange.self).pointee = PropertyIO.range
            size.pointee = UInt32(MemoryLayout<AudioValueRange>.size)
        }
        return PropertyIO.rangeStatus
    case kAudioDevicePropertyBufferFrameSize:
        PropertyIO.events.append("actual")
        output.assumingMemoryBound(to: UInt32.self).pointee = PropertyIO.frameCount
        size.pointee = UInt32(MemoryLayout<UInt32>.size)
        return noErr
    default: preconditionFailure("Unexpected device read")
    }
}

nonisolated func fixtureAudioObjectSetPropertyData(
    _ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UInt32, _ input: UnsafeRawPointer
) -> OSStatus {
    precondition(object == 17 && qualifierSize == 0 && qualifier == nil)
    precondition(address.pointee.mSelector == kAudioDevicePropertyBufferFrameSize)
    precondition(size == UInt32(MemoryLayout<UInt32>.size))
    PropertyIO.events.append("set")
    PropertyIO.requested = input.assumingMemoryBound(to: UInt32.self).pointee
    if PropertyIO.setStatus == noErr { PropertyIO.frameCount = PropertyIO.requested! }
    return PropertyIO.setStatus
}

@main enum SystemAudioDiagnosticBoundaryChecks {
    static func main() throws {
#if DEBUG
        let debug = true
#else
        let debug = false
#endif
        var rows: [[String: Any]] = []
        for name in ["normal", "range-failed", "invalid-rate", "empty-range", "set-failed"] {
            PropertyIO.reset()
            var rate = 48_000.0
            switch name {
            case "range-failed": PropertyIO.rangeStatus = -50
            case "invalid-rate": rate = .nan
            case "empty-range": PropertyIO.range = AudioValueRange(mMinimum: 2.5, mMaximum: 2.8)
            case "set-failed": PropertyIO.setStatus = -50
            default: break
            }
            SystemAudioCaptureDeviceFactory.configureCaptureBufferFrameSize(for: 17, sampleRate: rate)
            let shouldSet = name == "normal" || name == "set-failed"
            let expected = shouldSet ? (debug ? ["range", "set", "actual"] : ["range", "set"]) : ["range"]
            precondition(PropertyIO.events == expected, "Property I/O sequence: \(name)")
            precondition(PropertyIO.requested == (shouldSet ? 512 : nil))
            rows.append(["name": name, "events": PropertyIO.events,
                         "requested": PropertyIO.requested.map(Int.init) ?? -1,
                         "finalFrames": Int(PropertyIO.frameCount)])
        }

        let capture = SystemAudioCaptureBuffer(maximumFrameCount: 8)
        var samples: [Float] = [0.25, -0.5, 0.75, -1]
        let accepted = samples.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: UInt32(buffer.count * 4), mData: buffer.baseAddress))
            let format = AudioStreamBasicDescription(
                mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            return withUnsafePointer(to: &list) { capture.append($0, streamDescription: format) }
        }
        precondition(accepted)
        let frame = capture.decodedFrame!
        precondition(frame.signedChannels == [[0.25, 0.75], [-0.5, -1]])
        let frameFields = Mirror(reflecting: frame).children.compactMap(\.label)
        precondition(frameFields == ["signedChannels"], "Retired diagnostic payload must not remain in the frame")
        let report: [String: Any] = ["debug": debug, "propertyRows": rows,
                                    "frameFields": frameFields, "signedChannels": frame.signedChannels]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]))
    }
}
