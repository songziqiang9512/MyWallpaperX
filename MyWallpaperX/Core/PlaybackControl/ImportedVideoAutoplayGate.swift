//
//  ImportedVideoAutoplayGate.swift
//  MyWallpaperX
//

import Foundation

final class ImportedVideoAutoplayGate: @unchecked Sendable {
    nonisolated struct Token: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    static let shared = ImportedVideoAutoplayGate()
    static let resourceLifetimeUserInfoKey = "importedVideoResourceLifetime"

    private let lock = NSLock()
    private var generation: UInt64 = 0

    func claim() -> Token {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return Token(generation: generation)
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token.generation == generation
    }
}

struct ImportedVideoPlaybackRequest {
    let localURL: URL
    let admission: ImportedVideoPlaybackAdmission
    let resourceLifetime: PlaybackResourceLifetime?

    init(
        localURL: URL,
        admission: ImportedVideoPlaybackAdmission,
        resourceLifetime: PlaybackResourceLifetime? = nil
    ) {
        self.localURL = localURL
        self.admission = admission
        self.resourceLifetime = resourceLifetime
    }

    init?(notification: Notification) {
        guard let localURL = notification.userInfo?["localURL"] as? URL,
              let admission = notification.userInfo?[ImportedVideoPlaybackAdmission.notificationUserInfoKey]
                as? ImportedVideoPlaybackAdmission else { return nil }
        self.init(
            localURL: localURL,
            admission: admission,
            resourceLifetime: notification.userInfo?[ImportedVideoAutoplayGate.resourceLifetimeUserInfoKey]
                as? PlaybackResourceLifetime
        )
    }

    func post(name: Notification.Name) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [
                "localURL": localURL,
                ImportedVideoPlaybackAdmission.notificationUserInfoKey: admission,
                ImportedVideoAutoplayGate.resourceLifetimeUserInfoKey: resourceLifetime as Any
            ]
        )
    }
}
