import Foundation
import WebKit
import Darwin

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func startDirectoryWatcher(for propertyName: String, path: String) {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: .main
        )
        let watcher = DirectoryWatcher(path: path, fileDescriptor: fileDescriptor, source: source)
        source.setEventHandler { [weak self] in
            self?.pollFetchAllDirectoryProperties()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        directoryWatchersByProperty[propertyName] = watcher
        source.resume()
    }

    func stopDirectoryWatcher(for propertyName: String) {
        guard let watcher = directoryWatchersByProperty.removeValue(forKey: propertyName) else { return }
        watcher.source.setEventHandler {}
        watcher.source.cancel()
    }

    func stopAllDirectoryWatchers() {
        for propertyName in Array(directoryWatchersByProperty.keys) {
            stopDirectoryWatcher(for: propertyName)
        }
    }

    func pollFetchAllDirectoryProperties() {
        guard phase == .ready || phase == .launching,
              let propertiesJSON = currentRequest?.propertiesJSON else { return }
        syncFetchAllDirectoryProperties(using: propertiesJSON)
    }

    func notifyFetchAllDirectoryChanges(
        propertyName: String,
        addedOrChangedFiles: [String],
        removedFiles: [String],
        webView: WKWebView
    ) {
        let escapedPropertyName = WebWallpaperHostSupport.javaScriptQuotedString(propertyName)
        let addedJSON = WebWallpaperHostSupport.javaScriptArrayLiteral(from: addedOrChangedFiles)
        let removedJSON = WebWallpaperHostSupport.javaScriptArrayLiteral(from: removedFiles)
        // D5：目录变更逐已注册 endpoint 定向投递（跨源子 frame 同样可达），
        // 不再依赖主 frame 的同源中继。
        deliverStatePush(to: webView) { endpoint in
            """
            (() => {
              const sequence = \(endpoint.advancePushSequence());
              if (typeof window.__mwxHostPushSequence === 'number' && sequence <= window.__mwxHostPushSequence) return;
              window.__mwxHostPushSequence = sequence;
              window.__myWallpaperNotifyDirectoryFilesChanged(
                \(escapedPropertyName),
                \(addedJSON),
                \(removedJSON)
              );
            })();
            """
        }
    }

    func notifyFetchAllDirectoryAccessState(
        propertyName: String,
        errorMessage: String?,
        webView: WKWebView
    ) {
        // 去重键含屏幕标识：applyFetchAllDirectorySyncResult 会逐屏传入同一批
        // 通知，键只有属性名时第一屏写入后其余屏会被同一共享键去重拦截，
        // 多显示器下只有迭代序第一个屏幕能收到目录访问状态迁移。
        let dedupKey = DirectoryAccessErrorKey(propertyName: propertyName, screenID: screenID(for: webView))
        let previousError = directoryAccessErrorsByProperty[dedupKey]
        let trimmedError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextError = trimmedError.isEmpty ? nil : trimmedError
        guard previousError != nextError else { return }
        directoryAccessErrorsByProperty[dedupKey] = nextError
        let escapedPropertyName = WebWallpaperHostSupport.javaScriptQuotedString(propertyName)
        let escapedError = WebWallpaperHostSupport.javaScriptQuotedString(nextError ?? "")
        // D5：目录访问状态迁移逐 endpoint 定向投递。
        deliverStatePush(to: webView) { endpoint in
            """
            (() => {
              const sequence = \(endpoint.advancePushSequence());
              if (typeof window.__mwxHostPushSequence === 'number' && sequence <= window.__mwxHostPushSequence) return;
              window.__mwxHostPushSequence = sequence;
              window.__myWallpaperNotifyDirectoryAccessError(\(escapedPropertyName), \(escapedError));
            })();
            """
        }
    }
}
