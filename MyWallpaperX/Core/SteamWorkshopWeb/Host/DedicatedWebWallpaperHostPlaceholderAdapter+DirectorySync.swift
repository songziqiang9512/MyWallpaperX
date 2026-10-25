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
        guard let request = currentRequest, (request.propertiesJSON ?? "{}") == propertiesJSON else { return }
        directorySyncRequestID &+= 1
        let requestID = directorySyncRequestID
        let previousSnapshots = directorySnapshotsByProperty
        let cancellation = directoryResourceCancellation
        directorySyncQueue.async { [weak self] in
            guard let self else { return }
            let result = self.computeFetchAllDirectorySyncResult(
                using: propertiesJSON,
                previousSnapshots: previousSnapshots,
                rootURL: request.rootURL, grants: request.resourceGrants, cancellation: cancellation
            )
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      requestID == self.directorySyncRequestID,
                      self.phase == .ready || self.phase == .launching,
                      self.currentRequest?.id == request.id,
                      self.currentRequest?.resourceRevision == request.resourceRevision else {
                    return
                }
                self.applyFetchAllDirectorySyncResult(result, previousSnapshots: previousSnapshots)
            }
        }
    }

    func computeFetchAllDirectorySyncResult(
        using propertiesJSON: String,
        previousSnapshots: [String: DirectorySnapshot],
        rootURL: URL, grants: [WebWallpaperResourceGrant],
        cancellation: WebWallpaperLocalSchemeHandler.RequestCancellation? = nil
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
        var statusesByDirectoryPath: [String: DirectorySyncStatus] = [:]

        for property in properties {
            let propertyName = property.name
            let directoryPath = property.path
            // An unselected directory cannot change through filesystem events.
            // Property updates will trigger the next synchronization themselves.
            seenPropertyNames.insert(propertyName)
            let canonicalPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : WebWallpaperResourceGrant.authorizedURL(URL(fileURLWithPath: directoryPath),
                    kind: .directory, rootURL: rootURL, grants: grants)?.path
            let nextStatus: DirectorySyncStatus
            if cancellation?.isCancelled != true,
               let canonicalPath, let existing = statusesByDirectoryPath[canonicalPath] {
                nextStatus = existing
            } else {
                nextStatus = directorySyncStatus(forPath: directoryPath, rootURL: rootURL,
                    grants: grants, cancellation: cancellation)
                if let sourcePath = nextStatus.snapshot.sourceDirectoryPath {
                    statusesByDirectoryPath[sourcePath] = nextStatus
                }
            }
            hasFetchAllDirectory = hasFetchAllDirectory || (!directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && nextStatus.errorMessage != "directory_not_authorized" && cancellation?.isCancelled != true)
            let nextSnapshot = nextStatus.snapshot
            snapshotsByProperty[propertyName] = nextSnapshot

            if nextStatus.isAccessible, let sourcePath = nextSnapshot.sourceDirectoryPath {
                // Watch the same canonical directory that produced the value.
                // A later symlink retarget is resolved by the next synchronization.
                watchedDirectoriesByProperty[propertyName] = sourcePath
            }

            let previousFiles = previousSnapshots[propertyName]?.filesByPath ?? [:]
            let nextFiles = nextSnapshot.filesByPath

            let addedOrChanged = nextFiles.compactMap { path, modifiedAt -> String? in
                guard previousFiles[path] != modifiedAt else { return nil }
                return path
            }.sorted()

            let removed = previousFiles.keys.filter { nextFiles[$0] == nil }.sorted()

            // 变更事件只在有真实差异时投递（与 access 通知的
            // previousError != nextError 去重同纪律）：静止目录的 10s 轮询
            // 不再向每个 endpoint 派发空集事件——`wallpaper-directory-files-changed`
            // 的语义是"发生了变更"。首次同步 previousFiles 为空，非空目录的
            // added 即全量必然非空，初始投递不受影响（零文件目录首同步无事件，
            // 与 access 事件 nil==nil 去重的既有口径一致）。
            if addedOrChanged.isEmpty == false || removed.isEmpty == false {
                changeNotifications.append(
                    FetchAllDirectoryNotification(
                        propertyName: propertyName,
                        addedOrChangedFiles: addedOrChanged,
                        removedFiles: removed
                    )
                )
            }
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

    func directorySyncStatus(forPath path: String, rootURL: URL, grants: [WebWallpaperResourceGrant],
                             cancellation: WebWallpaperLocalSchemeHandler.RequestCancellation? = nil) -> DirectorySyncStatus {
        guard cancellation?.isCancelled != true else {
            return DirectorySyncStatus(snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false, errorMessage: "directory_request_cancelled")
        }
        // URL(fileURLWithPath: "") resolves to the process working directory.
        // Reject before URL construction: an unset author property grants no
        // directory and must never enumerate the App/repository/current folder.
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DirectorySyncStatus(snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false, errorMessage: "directory_path_empty")
        }
        guard let directoryURL = WebWallpaperResourceGrant.authorizedURL(URL(fileURLWithPath: path),
            kind: .directory, rootURL: rootURL, grants: grants) else {
            return DirectorySyncStatus(snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false, errorMessage: "directory_not_authorized")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return DirectorySyncStatus(
                snapshot: DirectorySnapshot(filesByPath: [:]),
                isAccessible: false,
                errorMessage: "directory_not_found"
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
            guard cancellation?.isCancelled != true else {
                return DirectorySyncStatus(snapshot: DirectorySnapshot(filesByPath: [:]),
                    isAccessible: false, errorMessage: "directory_request_cancelled")
            }
            guard let authorized = WebWallpaperResourceGrant.authorizedURL(url,
                rootURL: rootURL, grants: grants) else { continue }
            let values = try? authorized.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .isHiddenKey])
            guard values?.isRegularFile == true, values?.isHidden != true else { continue }
            let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            filesByPath[authorized.path] = modifiedAt
        }
        return DirectorySyncStatus(
            snapshot: DirectorySnapshot(sourceDirectoryPath: directoryURL.path, filesByPath: filesByPath),
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
