//
//  SystemAudioCaptureConfigurationMonitor.swift
//  MyWallpaperX
//

import CoreAudio
import Foundation

nonisolated final class SystemAudioCaptureConfigurationMonitor {
    private let queue: DispatchQueue
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var tapFormatListener: AudioObjectPropertyListenerBlock?
    private var aggregateAliveListener: AudioObjectPropertyListenerBlock?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    deinit {
        remove()
    }

    func install(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID,
        onInvalidated: @escaping (String) -> Void
    ) throws {
        self.tapID = tapID
        self.aggregateDeviceID = aggregateDeviceID

        var tapAddress = Self.tapFormatAddress
        let tapListener: AudioObjectPropertyListenerBlock = { count, addresses in
            guard (0..<Int(count)).contains(where: {
                addresses[$0].mSelector == kAudioTapPropertyFormat
            }) else { return }
            onInvalidated("tap-format")
        }
        let tapStatus = AudioObjectAddPropertyListenerBlock(
            tapID,
            &tapAddress,
            queue,
            tapListener
        )
        guard tapStatus == noErr else {
            throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(tapStatus)
        }
        tapFormatListener = tapListener

        var aliveAddress = Self.aggregateAliveAddress
        let aliveListener: AudioObjectPropertyListenerBlock = { count, addresses in
            guard (0..<Int(count)).contains(where: {
                addresses[$0].mSelector == kAudioDevicePropertyDeviceIsAlive
            }) else { return }
            let isAlive = (try? SystemAudioCaptureDeviceFactory.isDeviceAlive(aggregateDeviceID)) ?? false
            if !isAlive {
                onInvalidated("aggregate-not-alive")
            }
        }
        let aliveStatus = AudioObjectAddPropertyListenerBlock(
            aggregateDeviceID,
            &aliveAddress,
            queue,
            aliveListener
        )
        guard aliveStatus == noErr else {
            throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(aliveStatus)
        }
        aggregateAliveListener = aliveListener
#if DEBUG
        NSLog("MWX AUDIO CAPTURE: listeners installed")
#endif
    }

    func remove() {
        let hadListeners = tapFormatListener != nil || aggregateAliveListener != nil
        if let listener = aggregateAliveListener, aggregateDeviceID != kAudioObjectUnknown {
            var address = Self.aggregateAliveAddress
            let status = AudioObjectRemovePropertyListenerBlock(
                aggregateDeviceID,
                &address,
                queue,
                listener
            )
            if status != noErr {
#if DEBUG
                NSLog("MWX AUDIO CAPTURE: listener removal failed target=aggregate status=%d", status)
#endif
            }
        }
        aggregateAliveListener = nil
        if let listener = tapFormatListener, tapID != kAudioObjectUnknown {
            var address = Self.tapFormatAddress
            let status = AudioObjectRemovePropertyListenerBlock(tapID, &address, queue, listener)
            if status != noErr {
#if DEBUG
                NSLog("MWX AUDIO CAPTURE: listener removal failed target=tap status=%d", status)
#endif
            }
        }
        tapFormatListener = nil
        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        if hadListeners {
#if DEBUG
            NSLog("MWX AUDIO CAPTURE: listeners removed")
#endif
        }
    }
}

nonisolated private extension SystemAudioCaptureConfigurationMonitor {
    static let tapFormatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    static let aggregateAliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsAlive,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}
