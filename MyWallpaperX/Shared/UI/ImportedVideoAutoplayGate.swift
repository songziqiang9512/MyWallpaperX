//
//  ImportedVideoAutoplayGate.swift
//  MyWallpaperX
//

import Foundation

final class ImportedVideoAutoplayGate: @unchecked Sendable {
    struct Token: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    static let shared = ImportedVideoAutoplayGate()
    static let notificationUserInfoKey = "importedVideoAutoplayToken"
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
    let autoplayToken: ImportedVideoAutoplayGate.Token
    let resourceLifetime: PlaybackResourceLifetime?

    init(
        localURL: URL,
        autoplayToken: ImportedVideoAutoplayGate.Token,
        resourceLifetime: PlaybackResourceLifetime? = nil
    ) {
        self.localURL = localURL
        self.autoplayToken = autoplayToken
        self.resourceLifetime = resourceLifetime
    }

    init?(notification: Notification) {
        guard let localURL = notification.userInfo?["localURL"] as? URL,
              let autoplayToken = notification.userInfo?[ImportedVideoAutoplayGate.notificationUserInfoKey]
                as? ImportedVideoAutoplayGate.Token else { return nil }
        self.init(
            localURL: localURL,
            autoplayToken: autoplayToken,
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
                ImportedVideoAutoplayGate.notificationUserInfoKey: autoplayToken,
                ImportedVideoAutoplayGate.resourceLifetimeUserInfoKey: resourceLifetime as Any
            ]
        )
    }
}
