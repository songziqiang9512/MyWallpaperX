//
//  BundledVideoLibrary.swift
//  MyWallpaperX
//

import CryptoKit
import Foundation

enum BundledVideoLibrary {
    static let expectedFileNames = [
        "Video1.mp4",
        "Video2.mp4",
        "Video3.mp4",
        "Video4.mp4",
        "Video5.mp4"
    ]

    private static let preparedDirectoryURL: URL? = {
        do {
            guard let archiveURL = Bundle.main.url(forResource: "Videos", withExtension: "zip") else {
                throw PreparationError.archiveMissing
            }
            guard let applicationSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw PreparationError.applicationSupportUnavailable
            }
            let appDirectoryURL = applicationSupportURL.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "MyWallpaperX",
                isDirectory: true
            )
            return try prepare(
                archiveURL: archiveURL,
                destinationDirectoryURL: appDirectoryURL.appendingPathComponent(
                    "BundledVideos",
                    isDirectory: true
                )
            )
        } catch {
            NSLog("MyWallpaperX bundled videos unavailable: %@", error.localizedDescription)
            return nil
        }
    }()

    static var videoURLs: [URL] {
        expectedFileNames.compactMap(videoURL(forFileName:))
    }

    static func videoURL(named name: String) -> URL? {
        let fileName = name.lowercased().hasSuffix(".mp4") ? name : "\(name).mp4"
        return videoURL(forFileName: fileName)
    }

    static func migratedURL(forPersistedPath path: String) -> URL? {
        let oldURL = URL(fileURLWithPath: path).standardizedFileURL
        guard expectedFileNames.contains(oldURL.lastPathComponent),
              oldURL.path.contains(".app/Contents/Resources/") else {
            return nil
        }
        return videoURL(forFileName: oldURL.lastPathComponent)
    }

    static func prepare(
        archiveURL: URL,
        destinationDirectoryURL: URL,
        expectedFileNames: [String] = BundledVideoLibrary.expectedFileNames,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard archiveURL.isFileURL, fileManager.fileExists(atPath: archiveURL.path) else {
            throw PreparationError.archiveMissing
        }
        guard !expectedFileNames.isEmpty,
              Set(expectedFileNames).count == expectedFileNames.count,
              expectedFileNames.allSatisfy({
                  $0 == URL(fileURLWithPath: $0).lastPathComponent && !$0.hasPrefix(".")
              }) else {
            throw PreparationError.invalidExpectedFiles
        }

        let signature = try archiveSignature(archiveURL)
        if extractedDirectoryIsCurrent(
            destinationDirectoryURL,
            signature: signature,
            expectedFileNames: expectedFileNames,
            fileManager: fileManager
        ) {
            return destinationDirectoryURL
        }

        let parentURL = destinationDirectoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let stagingURL = parentURL.appendingPathComponent(
            ".BundledVideos-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupURL = parentURL.appendingPathComponent(
            ".BundledVideos-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingURL) }

        try extractArchive(archiveURL, to: stagingURL)
        guard extractedFileNames(in: stagingURL, fileManager: fileManager) == Set(expectedFileNames) else {
            throw PreparationError.unexpectedArchiveContents
        }
        for fileName in expectedFileNames {
            let fileURL = stagingURL.appendingPathComponent(fileName)
            guard fileManager.isReadableFile(atPath: fileURL.path) else {
                throw PreparationError.extractedFileUnreadable(fileName)
            }
        }
        try signature.write(
            to: stagingURL.appendingPathComponent(".archive-sha256"),
            atomically: true,
            encoding: .utf8
        )

        var movedExistingDirectory = false
        do {
            if fileManager.fileExists(atPath: destinationDirectoryURL.path) {
                try fileManager.moveItem(at: destinationDirectoryURL, to: backupURL)
                movedExistingDirectory = true
            }
            try fileManager.moveItem(at: stagingURL, to: destinationDirectoryURL)
            if movedExistingDirectory {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if movedExistingDirectory,
               !fileManager.fileExists(atPath: destinationDirectoryURL.path),
               fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationDirectoryURL)
            }
            throw error
        }
        return destinationDirectoryURL
    }

    private static func videoURL(forFileName fileName: String) -> URL? {
        guard expectedFileNames.contains(fileName), let preparedDirectoryURL else { return nil }
        let url = preparedDirectoryURL.appendingPathComponent(fileName)
        return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }

    private static func archiveSignature(_ archiveURL: URL) throws -> String {
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func extractedDirectoryIsCurrent(
        _ directoryURL: URL,
        signature: String,
        expectedFileNames: [String],
        fileManager: FileManager
    ) -> Bool {
        let markerURL = directoryURL.appendingPathComponent(".archive-sha256")
        guard (try? String(contentsOf: markerURL, encoding: .utf8)) == signature,
              extractedFileNames(in: directoryURL, fileManager: fileManager) == Set(expectedFileNames) else {
            return false
        }
        return expectedFileNames.allSatisfy {
            fileManager.isReadableFile(atPath: directoryURL.appendingPathComponent($0).path)
        }
    }

    private static func extractedFileNames(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> Set<String> {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Set(urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url.lastPathComponent
        })
    }

    private static func extractArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PreparationError.extractionFailed(message ?? "ditto exited with \(process.terminationStatus)")
        }
    }

    private enum PreparationError: LocalizedError {
        case archiveMissing
        case applicationSupportUnavailable
        case invalidExpectedFiles
        case unexpectedArchiveContents
        case extractedFileUnreadable(String)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .archiveMissing:
                "Videos.zip is missing"
            case .applicationSupportUnavailable:
                "Application Support directory is unavailable"
            case .invalidExpectedFiles:
                "bundled video file contract is invalid"
            case .unexpectedArchiveContents:
                "Videos.zip contains unexpected files"
            case .extractedFileUnreadable(let fileName):
                "extracted bundled video is unreadable: \(fileName)"
            case .extractionFailed(let message):
                "Videos.zip extraction failed: \(message)"
            }
        }
    }
}
