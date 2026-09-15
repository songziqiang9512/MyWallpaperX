//
//  ImportedVideoPlaybackObserver.swift
//  MyWallpaperX
//

import Foundation

enum ImportedVideoPlaybackObserver {
    static func make(
        name: Notification.Name,
        context: ImportContext,
        wallpaperManager: WallpaperManager
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            guard let request = ImportedVideoPlaybackRequest(notification: notification) else { return }
            wallpaperManager.processImportedVideos(
                from: [request.localURL],
                presentingIn: nil,
                context: context,
                autoplayToken: request.autoplayToken,
                resourceLifetime: request.resourceLifetime
            )
        }
    }
}
