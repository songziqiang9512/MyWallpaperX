import Foundation
import Metal

/// Lexical alias so the nested session can reach the tier's private plumbing.
private typealias Tier = SceneResolvedMaterialPipelineBinaryArchive

/// Persistent device-pipeline warm start for the resolved material pass
/// encoder's launch envelope. One `MTLBinaryArchive` file per exact pipeline
/// identity; the identity digest binds the tier schema version, host OS
/// version, Metal device registry, attachment pixel format, sample count,
/// color write mask, pipeline function names, render state and the prepared
/// MSL source digest. A digest, file or archive mismatch is always a safe
/// miss: the pipeline still compiles from source on the launch warmup worker
/// and only the warm start is lost. Serialization runs on the background
/// launch warmup workers; ordinary frame preparation never constructs a
/// session, never reads and never writes this tier. A disk hit warms the
/// first pipeline state only — it never publishes ready before the state
/// exists and is cached in the encoder.
nonisolated enum SceneResolvedMaterialPipelineBinaryArchive {
    /// The single invalidation lever. Any change to the identity fields,
    /// framing or archive semantics bumps this and retires the tier as a
    /// safe miss.
    static let schemaVersion = 1
    static let cacheDirectoryName =
        "SceneResolvedMaterialPipelineBinaryArchive-v\(schemaVersion)"
    private static let environmentKey = "MWX_SCENE_PIPELINE_BINARY_ARCHIVE"
    private static let fileExtension = "metalarchive"
    private static let maximumArchiveBytes = 16 * 1_024 * 1_024
    private static let retainedEntryLimit = 512

    private static let lock = NSLock()
    private static var pruned = false
    private static var counters = Counters()

    private struct Counters {
        var absentLoads = 0
        var invalidLoads = 0
        var hits = 0
        var publications = 0
        var publicationFailures = 0
        var archiveRetries = 0
    }

    struct Snapshot: Equatable {
        var absentLoads = 0
        var invalidLoads = 0
        var hits = 0
        var publications = 0
        var publicationFailures = 0
        var archiveRetries = 0
    }

    static func counterSnapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            absentLoads: counters.absentLoads,
            invalidLoads: counters.invalidLoads,
            hits: counters.hits,
            publications: counters.publications,
            publicationFailures: counters.publicationFailures,
            archiveRetries: counters.archiveRetries
        )
    }

    /// One launch-warmup key's archive handle. Prepared only from the launch
    /// warmup path; the frame path passes no session at all.
    struct Session {
        let archive: MTLBinaryArchive
        let loadedFromDisk: Bool
        let digest: String

        /// A fresh archive has no matching entry, so Metal compiles from
        /// source as usual; a loaded archive serves its matching entry.
        func attach(to descriptor: MTLRenderPipelineDescriptor) {
            descriptor.binaryArchives = [archive]
        }

        /// Called once the pipeline state exists. A disk hit keeps the entry
        /// as loaded; a fresh archive publishes its entry for the next launch.
        func recordReadyOutcome(descriptor: MTLRenderPipelineDescriptor) {
            if loadedFromDisk {
                Tier.bump { $0.hits += 1 }
                NSLog(
                    "MWX resolved material pipeline binary archive"
                        + " schema=\(Tier.schemaName)"
                        + " phase=launch-preparation outcome=hit digest=%@",
                    shortDigest
                )
            } else {
                publish(descriptor: descriptor)
            }
        }

        /// Republishes after the attached archive could not serve the state.
        /// The freshly compiled entry overwrites a stale or corrupted file.
        func republishAfterRetry(descriptor: MTLRenderPipelineDescriptor) {
            Tier.bump { $0.archiveRetries += 1 }
            publish(descriptor: descriptor)
        }

        private var shortDigest: String { String(digest.prefix(12)) }

        private func publish(descriptor: MTLRenderPipelineDescriptor) {
            guard let directory = Tier.publishDirectory() else {
                recordPublicationFailure(reason: "cache-unavailable")
                return
            }
            let temporary = directory.appendingPathComponent(
                ".\(digest).\(Tier.fileExtension).tmp-\(UUID().uuidString)",
                isDirectory: false
            )
            do {
                try archive.addRenderPipelineFunctions(descriptor: descriptor)
                try archive.serialize(to: temporary)
                let destination = directory.appendingPathComponent(
                    "\(digest).\(Tier.fileExtension)", isDirectory: false
                )
                // First publication has no previous entry; removal is only
                // part of replacing an existing one.
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                Tier.bump { $0.publications += 1 }
                NSLog(
                    "MWX resolved material pipeline binary archive"
                        + " schema=\(Tier.schemaName)"
                        + " phase=launch-preparation outcome=store digest=%@",
                    shortDigest
                )
                Tier.pruneOnce(directory: directory)
            } catch {
                // A failed publication must not leak the serialized scratch
                // file; the live pipeline state is already independent.
                try? FileManager.default.removeItem(at: temporary)
                recordPublicationFailure(reason: String(describing: error))
            }
        }

        private func recordPublicationFailure(reason: String) {
            Tier.bump { $0.publicationFailures += 1 }
            NSLog(
                "MWX resolved material pipeline binary archive"
                    + " schema=\(Tier.schemaName)"
                    + " phase=launch-preparation outcome=store-failed"
                    + " digest=%@ reason=%@",
                shortDigest,
                reason
            )
        }
    }

    /// Resolves the per-key session: loads this identity's archive when a
    /// valid regular file exists, otherwise prepares a fresh empty archive.
    /// Any mismatch degrades to a fresh archive; `nil` only means Metal
    /// could not even create an empty archive and the caller compiles plain.
    static func prepareSession(
        frontend: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        writeMask: MTLColorWriteMask,
        passRole: SceneResolvedMaterialProgram.PassRole = .offscreenOverwrite,
        device: MTLDevice
    ) -> Session? {
        guard let digest = keyDigest(
            frontend: frontend,
            renderState: renderState,
            pixelFormat: pixelFormat,
            sampleCount: sampleCount,
            writeMask: writeMask,
            passRole: passRole,
            device: device
        ) else { return nil }
        var loadedArchive: MTLBinaryArchive?
        var loadedFromDisk = false
        var hadDiskEntry = false
        if let directory = readDirectory() {
            let url = directory.appendingPathComponent(
                "\(digest).\(fileExtension)", isDirectory: false
            )
            // The size-bounded regular-file probe also proves the entry is
            // not a symlink before Metal is pointed at it. The read path
            // never creates the directory and never mutates entries.
            if ScenePersistentCacheSupport.regularFileData(
                url, maximumBytes: maximumArchiveBytes
            ) != nil {
                hadDiskEntry = true
                let descriptor = MTLBinaryArchiveDescriptor()
                descriptor.url = url
                do {
                    loadedArchive = try device.makeBinaryArchive(
                        descriptor: descriptor
                    )
                    loadedFromDisk = true
                } catch {
                    bump { $0.invalidLoads += 1 }
                    NSLog(
                        "MWX resolved material pipeline binary archive"
                            + " schema=\(schemaName)"
                            + " phase=launch-preparation outcome=invalid"
                            + " digest=%@ reason=%@",
                        String(digest.prefix(12)),
                        String(describing: error)
                    )
                }
            }
        }
        if loadedArchive == nil {
            if !hadDiskEntry {
                bump { $0.absentLoads += 1 }
            }
            do {
                loadedArchive = try device.makeBinaryArchive(
                    descriptor: MTLBinaryArchiveDescriptor()
                )
            } catch {
                return nil
            }
        }
        guard let archive = loadedArchive else { return nil }
        return Session(
            archive: archive,
            loadedFromDisk: loadedFromDisk,
            digest: digest
        )
    }

    /// Stable cross-process identity digest. Fields are length-prefixed by
    /// the shared digest accumulator, so no field boundary can collide.
    static func keyDigest(
        frontend: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        writeMask: MTLColorWriteMask,
        passRole: SceneResolvedMaterialProgram.PassRole = .offscreenOverwrite,
        device: MTLDevice
    ) -> String? {
        guard device.registryID != 0,
              pixelFormat != .invalid,
              sampleCount > 0,
              writeMask.rawValue != 0,
              !frontend.vertexFunctionName.isEmpty,
              !frontend.fragmentFunctionName.isEmpty,
              !frontend.metalSource.isEmpty else { return nil }
        let renderStateIdentity = SceneResolvedMaterialProgramIdentity.renderState(
            renderState
        )
        var digest = ScenePersistentCacheDigest()
        digest.append(schemaName)
        // The OS version string carries the build number, so a driver or
        // Metal compiler update produces a new digest.
        digest.append(ProcessInfo.processInfo.operatingSystemVersionString)
        digest.append(String(device.registryID))
        digest.append(String(pixelFormat.rawValue))
        digest.append(String(sampleCount))
        digest.append(String(writeMask.rawValue))
        digest.append(passRole.rawValue)
        digest.append(frontend.vertexFunctionName)
        digest.append(frontend.fragmentFunctionName)
        digest.append(String(frontend.uniformBufferIndex))
        digest.append(
            [
                renderStateIdentity.blending.rawValue,
                renderStateIdentity.depthTest.rawValue,
                renderStateIdentity.depthWrite.rawValue,
                renderStateIdentity.cullMode.rawValue,
                renderStateIdentity.alphaWriting.rawValue,
            ].joined(separator: "|")
        )
        digest.append(
            SceneGenericShaderProgramArtifact.sha256(
                Data(frontend.metalSource.utf8)
            )
        )
        return digest.sha256Hex()
    }

    // MARK: - Tier plumbing

    private static var schemaName: String {
        "scene-resolved-material-pipeline-binary-archive-v\(schemaVersion)"
    }

    private static func readDirectory() -> URL? {
        ScenePersistentCacheSupport.versionedCacheDirectory(
            environmentKey: environmentKey,
            versionedName: cacheDirectoryName,
            createIfNeeded: false
        )
    }

    private static func publishDirectory() -> URL? {
        ScenePersistentCacheSupport.versionedCacheDirectory(
            environmentKey: environmentKey,
            versionedName: cacheDirectoryName,
            createIfNeeded: true
        )
    }

    private static func pruneOnce(directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !pruned else { return }
        pruned = true
        ScenePersistentCacheSupport.prune(
            directory,
            retainedEntryLimit: retainedEntryLimit,
            entryExtension: fileExtension
        )
    }

    private static func bump(_ mutate: (inout Counters) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&counters)
    }
}
