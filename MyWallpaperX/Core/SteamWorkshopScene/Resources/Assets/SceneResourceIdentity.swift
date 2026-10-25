import Foundation

/// One parsed range in one opened package revision. The Root keeps the FD alive.
nonisolated struct ScenePackageContentIdentity: Hashable, Sendable {
    let packagePath: String
    let fileRevision: ScenePackageFileRevision
    let rawEntryPath: String
    let dataStartOffset: UInt64
    let offset: UInt32
    let byteCount: UInt32

    var isValid: Bool {
        guard !packagePath.isEmpty, !rawEntryPath.isEmpty,
              dataStartOffset <= fileRevision.byteCount else { return false }
        let payloadBytes = fileRevision.byteCount - dataStartOffset
        return UInt64(offset) <= payloadBytes && UInt64(byteCount) <= payloadBytes - UInt64(offset)
    }
}
