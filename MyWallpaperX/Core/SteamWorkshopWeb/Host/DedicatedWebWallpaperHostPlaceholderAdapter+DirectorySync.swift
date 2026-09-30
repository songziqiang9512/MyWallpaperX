//
//  DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift
//  MyWallpaperX
//

import Foundation
import Darwin

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func parseFetchAllDirectoryProperties(from propertiesJSON: String) -> [FetchAllDirectoryProperty]? {
        guard let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var properties: [FetchAllDirectoryProperty] = []
        for (propertyName, rawPayload) in root {
            guard let payload = rawPayload as? [String: Any],
                  let rawType = payload["type"] as? String,
                  rawType == "directory",
                  let mode = payload["mode"] as? String,
                  mode == "fetchall",
                  let directoryPath = payload["value"] as? String else {
                continue
            }

            properties.append(FetchAllDirectoryProperty(name: propertyName, path: directoryPath))
        }
        return properties
    }

    func syncFetchAllDirectoryProperties(using propertiesJSON: String) {
        directorySyncRequestID &+= 1
        let requestID = directorySyncRequestID
        let previousSnapshots = directorySnapshotsByProperty
        directorySyncQueue.async { [weak self] in
            guard let self else { return }
            let result = self.computeFetchAllDirectorySyncResult(
                using: propertiesJSON,
                previousSnapshots: previousSnapshots
            )
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      requestID == self.directorySyncRequestID,
                      self.phase == .ready || self.phase == .launching,
                      self.currentRequest?.propertiesJSON == propertiesJSON else {
                    return
                }
                self.applyFetchAllDirectorySyncResult(result, previousSnapshots: previousSnapshots)
            }
        }
    }

    func computeFetchAllDirectorySyncResult(
        using propertiesJSON: String,
        previousSnapshots: [String: DirectorySnapshot]
    ) -> FetchAllDirectorySyncResult {
        guard let properties = parseFetchAllDirectoryProperties(from: propertiesJSON) else {
            let changeNotifications = previousSnapshots.map { propertyName, snapshot in
                FetchAllDirectoryNotification(
                    propertyName: propertyName,
                    addedOrChangedFiles: [],
                    removedFiles: snapshot.filesByPath.keys.sorted()
                )
            }
            return FetchAllDirectorySyncResult(
                seenPropertyNames: [],
                watchedDirectoriesByProperty: [:],
                snapshotsByProperty: [:],
                accessNotifications: [],
                changeNotifications: changeNotifications.sorted { $0.propertyName < $1.propertyName },
                hasFetchAllDirectory: false
            )
        }

        var seenPropertyNames = Set<String>()
        var watchedDirectoriesByProperty: [String: String] = [:]
        var snapshotsByProperty: [String: DirectorySnapshot] = [:]
        var hasFetchAllDirectory = false
        var changeNotifications: [FetchAllDirectoryNotification] = []
        var accessNotifications: [FetchAllDirectoryAccessNotification] = []

        for property in properties {
            hasFetchAllDirectory = true
            let propertyName = property.name
            let directoryPath = property.path
            seenPropertyNames.insert(propertyName)
            let nextStatus = directorySyncStatus(forPath: directoryPath)
            let nextSnapshot = nextStatus.snapshot
            snapshotsByProperty[propertyName] = nextSnapshot

            if nextStatus.isAccessible {
                watchedDirectoriesByProperty[propertyName] = URL(fileURLWithPath: directoryPath)
                    .standardizedFileURL
                    .path
            }

            let previousFiles = previousSnapshots[propertyName]?.filesByPath ?? [:]
            let nextFiles = nextSnapshot.filesByPath

            let addedOrChanged = nextFiles.compactMap { path, modifiedAt -> String? in
                guard previousFiles[path] != modifiedAt else { return nil }
                return path
            }.sorted()

            let removed = previousFiles.keys.filter { nextFiles[$0] == nil }.sorted()

            changeNotifications.append(
                FetchAllDirectoryNotification(
                    propertyName: propertyName,
                    addedOrChangedFiles: addedOrChanged,
                    removedFiles: removed
                )
            )
            accessNotifications.append(
                FetchAllDirectoryAccessNotification(
                    propertyName: propertyName,
                    errorMessage: nextStatus.errorMessage
                )
            )
        }

        let obsoletePropertyNames = Set(previousSnapshots.keys).subtracting(seenPropertyNames)
        for propertyName in obsoletePropertyNames {
            let removed = previousSnapshots[propertyName]?.filesByPath.keys.sorted() ?? []
            changeNotifications.append(
                FetchAllDirectoryNotification(
                    propertyName: propertyName,
                    addedOrChangedFiles: [],
                    removedFiles: removed
                )
            )
        }

        return FetchAllDirectorySyncResult(
            seenPropertyNames: seenPropertyNames,
            watchedDirectoriesByProperty: watchedDirectoriesByProperty,
            snapshotsByProperty: snapshotsByProperty,
            accessNotifications: accessNotifications.sorted { $0.propertyName < $1.propertyName },
            changeNotifications: changeNotifications.sorted { $0.propertyName < $1.propertyName },
            hasFetchAllDirectory: hasFetchAllDirectory
        )
    }

    func applyFetchAllDirectorySyncResult(
        _ result: FetchAllDirectorySyncResult,
        previousSnapshots _: [String: DirectorySnapshot]
    ) {
        directorySnapshotsByProperty = result.snapshotsByProperty
        let obsoleteErrorKeys = directoryAccessErrorsByProperty.keys.filter {
            result.seenPropertyNames.contains($0.propertyName) == false
        }
        for key in obsoleteErrorKeys {
            directoryAccessErrorsByProperty.removeValue(forKey: key)
        }

        reconfigureDirectoryWatchers(with: result.watchedDirectoriesByProperty)

        if result.hasFetchAllDirectory {
            startDirectoryWatchTimer()
        } else {
            stopAllDirectoryWatchers()
            stopDirectoryWatchTimer()
        }

        forEachWebView { webView in
            for notification in result.changeNotifications {
                notifyFetchAllDirectoryChanges(
                    propertyName: notification.propertyName,
                    addedOrChangedFiles: notification.addedOrChangedFiles,
                    removedFiles: notification.removedFiles,
                    webView: webView
                )
            }
            for notification in result.accessNotifications {
                notifyFetchAllDirectoryAccessState(
                    propertyName: notification.propertyName,
                    errorMessage: notification.errorMessage,
                    webView: webView
                )
            }
        }
    }

    func directorySyncStatus(forPath path: String) -> DirectorySyncStatus {
        let directoryURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return DirectorySyncStatus(
                snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false,
                errorMessage: path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "directory_path_empty"
                    : "directory_not_found"
            )
        }
        guard isDirectory.boolValue else {
            return DirectorySyncStatus(
                snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false,
                errorMessage: "directory_path_is_not_directory"
            )
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return DirectorySyncStatus(
                snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false,
                errorMessage: "directory_enumerator_unavailable"
            )
        }

        var filesByPath: [String: TimeInterval] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .isHiddenKey])
            guard values?.isRegularFile == true, values?.isHidden != true else { continue }
            let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            filesByPath[url.path] = modifiedAt
        }
        return DirectorySyncStatus(
            snapshot: DirectorySnapshot(filesByPath: filesByPath),
            isAccessible: true,
            errorMessage: nil
        )
    }

    func startDirectoryWatchTimer() {
        guard directoryWatchTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10))
        timer.setEventHandler { [weak self] in
            self?.pollFetchAllDirectoryProperties()
        }
        directoryWatchTimer = timer
        timer.resume()
    }

    func stopDirectoryWatchTimer() {
        directoryWatchTimer?.setEventHandler {}
        directoryWatchTimer?.cancel()
        directoryWatchTimer = nil
    }

    func reconfigureDirectoryWatchers(with watchedDirectoriesByProperty: [String: String]) {
        let obsoletePropertyNames = Set(directoryWatchersByProperty.keys).subtracting(watchedDirectoriesByProperty.keys)
        for propertyName in obsoletePropertyNames {
            stopDirectoryWatcher(for: propertyName)
        }

        for (propertyName, path) in watchedDirectoriesByProperty {
            if let existingWatcher = directoryWatchersByProperty[propertyName], existingWatcher.path == path {
                continue
            }
            stopDirectoryWatcher(for: propertyName)
            startDirectoryWatcher(for: propertyName, path: path)
        }
    }

}
