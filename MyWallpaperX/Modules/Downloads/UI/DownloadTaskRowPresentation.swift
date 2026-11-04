import AppKit
import Combine

/// One task's presentation lifetime survives native row-view reuse.
@MainActor final class DownloadTaskRowPresentation {
    struct Bindings {
        var perform: (DownloadTaskRow, DownloadTaskAction) -> Void
        var loadThumbnail: ((DownloadTaskRow, ThumbnailRequest, @escaping (NSImage?) -> Void) -> (() -> Void)?)? = nil
        var observeProgress: ((DownloadTaskRow, @escaping (DownloadTaskProgress) -> Void) -> (() -> Void)?)? = nil
    }
    enum Change { case content, progress, thumbnail }
    struct Status {
        let text: String
        let phase: DownloadTaskPhase
        let fraction: Double?
    }

    static let thumbnailSide: CGFloat = 48
    let changes = PassthroughSubject<Change, Never>()
    private(set) var row: DownloadTaskRow?
    private(set) var image: NSImage?
    private let bindings: Bindings
    private var thumbnailRequest: ThumbnailRequest?
    private var cancelThumbnail: (() -> Void)?
    private var cancelProgress: (() -> Void)?
    private var lastByteSample: (bytes: Int64, date: Date)?
    private var lastProgressSequence = -1
    private var progressStatus: Status?

    init(bindings: Bindings) { self.bindings = bindings }
    isolated deinit { cancelProgress?(); cancelThumbnail?() }

    static func thumbnailRequest(for window: NSWindow) -> ThumbnailRequest? {
        ThumbnailRequest(size: NSSize(width: thumbnailSide, height: thumbnailSide),
            scale: window.backingScaleFactor, mode: .fit)
    }

    var status: Status? {
        guard let row else { return nil }
        if let progressStatus { return progressStatus }
        var text = row.statusText ?? row.phase.title
        if row.phase.isTerminal, let date = row.recordedAt {
            text += " · " + Self.dateFormatter.string(from: date)
        }
        return Status(text: text, phase: row.phase, fraction: row.phase == .completed ? 1 : nil)
    }

    func configure(_ next: DownloadTaskRow, request: ThumbnailRequest? = nil) {
        let changedAttempt = row?.id != next.id
        let changedThumbnail = changedAttempt || row?.thumbnailKey != next.thumbnailKey
        let changedPhase = row?.phase != next.phase
        let needsProgressBinding = changedAttempt || row?.phase.isTerminal == true
        if changedAttempt || next.phase.isTerminal {
            cancelProgress?()
            cancelProgress = nil
        }
        if changedAttempt {
            lastByteSample = nil
            lastProgressSequence = -1
        }
        row = next
        if let progress = next.progress {
            if changedAttempt || changedPhase || progress.phase != .transferring || progress.sequence != lastProgressSequence {
                progressStatus = makeStatus(progress)
            }
        }
        else if changedAttempt || changedPhase || next.phase != .transferring { progressStatus = nil }
        if !next.phase.isTerminal, needsProgressBinding {
            cancelProgress = bindings.observeProgress?(next) { [weak self] progress in
                guard let self, self.row?.id == next.id else { return }
                self.progressStatus = self.makeStatus(progress)
                self.changes.send(.progress)
            }
        }
        if changedThumbnail {
            cancelThumbnail?()
            cancelThumbnail = nil
            thumbnailRequest = nil
            image = nil
        }
        changes.send(.content)
        if let request { prepareThumbnail(request) }
    }

    func prepareThumbnail(_ request: ThumbnailRequest) {
        guard let row, let key = row.thumbnailKey, request != thumbnailRequest else { return }
        cancelThumbnail?()
        cancelThumbnail = nil
        thumbnailRequest = request
        let id = row.id
        cancelThumbnail = bindings.loadThumbnail?(row, request) { [weak self] image in
            guard let self, self.row?.id == id, self.row?.thumbnailKey == key,
                  self.thumbnailRequest == request, let image else { return }
            self.image = image
            self.changes.send(.thumbnail)
        }
    }

    func unbind() {
        cancelProgress?()
        cancelThumbnail?()
        cancelProgress = nil
        cancelThumbnail = nil
        row = nil
        image = nil
        thumbnailRequest = nil
        lastByteSample = nil
        lastProgressSequence = -1
        progressStatus = nil
    }

    func perform(_ action: DownloadTaskAction) {
        guard let row, row.actions.contains(action) else { return }
        bindings.perform(row, action)
    }

    private func makeStatus(_ progress: DownloadTaskProgress) -> Status {
        var parts = [progress.statusText ?? progress.phase.title]
        if progress.phase == .transferring, let bytes = progress.verifiedBytes {
            if let rate = sampleRate(bytes: bytes, sequence: progress.sequence) {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file) + "/s")
            }
            var size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            if let total = progress.totalBytes {
                size += " / " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            }
            parts.append(size)
        }
        return Status(text: parts.joined(separator: " · "), phase: progress.phase, fraction: progress.fraction)
    }

    private func sampleRate(bytes: Int64, sequence: Int) -> Double? {
        defer {
            if sequence > lastProgressSequence {
                lastProgressSequence = sequence
                lastByteSample = (bytes, Date())
            }
        }
        guard sequence > lastProgressSequence, let previous = lastByteSample else { return nil }
        let elapsed = Date().timeIntervalSince(previous.date)
        guard elapsed >= 0.08, bytes > previous.bytes else { return nil }
        let rate = Double(bytes - previous.bytes) / elapsed
        return rate.isFinite && rate > 0 ? rate : nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
