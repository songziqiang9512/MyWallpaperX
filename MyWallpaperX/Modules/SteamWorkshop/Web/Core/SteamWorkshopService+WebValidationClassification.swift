#if DEBUG
import Foundation

extension SteamWorkshopService {
    func isDependencyShellPreconditionResourcePath(_ loweredPath: String) -> Bool {
        let normalizedPath = loweredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedPath.isEmpty == false else { return false }
        let prefixes = [
            "file/", "files/",
            "image/", "images/", "img/",
            "background/", "backgrounds/", "bg/",
            "audio/", "music/", "bgm/",
            "video/", "videos/",
            "font/", "fonts/",
            "subtitle/", "subtitles/",
            "voice/", "voices/"
        ]
        return prefixes.contains { normalizedPath.hasPrefix($0) }
    }

    func isWebPlaybackFailurePreconditionRelated(_ loweredMessage: String) -> Bool {
        let markers = [
            "directory_path_empty",
            "directory_not_found",
            "directory_path_is_not_directory",
            "directory_enumerator_unavailable",
            "file doesn’t exist",
            "file doesn't exist",
            "no such file",
            "not permitted",
            "permission denied",
            "operation not permitted",
            "could not be opened"
        ]
        return markers.contains { loweredMessage.contains($0) }
    }

    func isWebPlaybackFailureEnvironmentRelated(_ loweredMessage: String) -> Bool {
        let markers = [
            "network",
            "internet",
            "offline",
            "timed out",
            "timeout",
            "host could not be found",
            "third-party",
            "third party"
        ]
        return markers.contains { loweredMessage.contains($0) }
    }
}
#endif
