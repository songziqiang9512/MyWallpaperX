//
//  SteamWorkshopService+Paths.swift
//  MyWallpaperX
//

import Foundation

extension SteamWorkshopService {
#if DEBUG
    private var debugWorkshopLibraryRootURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-workshop-root"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        let rawPath = arguments[flagIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }
        return URL(fileURLWithPath: rawPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
#endif

    var bundledSteamBundleURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent(Constants.bundledSteamBundleName, isDirectory: true)
    }

    var bundledSteamRootURL: URL? {
        bundledSteamBundleURL?
            .appendingPathComponent(Constants.bundledSteamRootName, isDirectory: true)
    }

    var bundledSteamCmdURL: URL? {
        bundledSteamRootURL?.appendingPathComponent("steamcmd.sh")
    }

    var activeSteamRootURL: URL? {
        guard let bundledSteamRootURL, validateSteamRuntime(at: bundledSteamRootURL) else {
            return nil
        }
        return bundledSteamRootURL
    }

    var activeSteamCmdURL: URL? {
        guard let bundledSteamCmdURL,
              let bundledSteamRootURL,
              validateSteamRuntime(at: bundledSteamRootURL) else {
            return nil
        }
        return bundledSteamCmdURL
    }

    var runtimeInstallRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopRuntime", isDirectory: true)
    }

    var steamDownloadStagingRootURL: URL {
        let configured = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MyWallpaperX/SteamJobs/Staging", isDirectory: true)
        return (try? SteamWorkshopLibraryTransaction.configuredRoot(configured)) ?? configured
    }

    var steamDownloadLibraryRootURL: URL {
        (try? SteamWorkshopLibraryTransaction.configuredRoot(libraryRootURL)) ?? libraryRootURL
    }

    var stagingWorkshopContentRootURL: URL {
        runtimeInstallRootURL
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("workshop", isDirectory: true)
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(Constants.workshopAppID, isDirectory: true)
    }

    var libraryRootURL: URL {
#if DEBUG
        if let debugWorkshopLibraryRootURL {
            return debugWorkshopLibraryRootURL
        }
#endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("创意工坊", isDirectory: true)
    }

    var videoLibraryRootURL: URL {
        libraryRootURL.appendingPathComponent("Video", isDirectory: true)
    }

    var webLibraryRootURL: URL {
        libraryRootURL.appendingPathComponent("Web", isDirectory: true)
    }

    var sceneLibraryRootURL: URL {
        libraryRootURL.appendingPathComponent("Scene", isDirectory: true)
    }

    var exportedVideosRootURL: URL { videoLibraryRootURL }

    var cacheDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshop", isDirectory: true)
    }

    var steamAuthDebugLogURL: URL {
        cacheDirectoryURL.appendingPathComponent("steamcmd-auth-debug.log")
    }

    var bundledSteamMetadataURL: URL? {
        bundledSteamBundleURL?
            .appendingPathComponent(Constants.bundledSteamMetadataName)
    }
}
