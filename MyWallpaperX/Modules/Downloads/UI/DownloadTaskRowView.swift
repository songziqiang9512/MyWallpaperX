import AppKit

/// The original source adapters supply commands and consumer leases directly.
/// The row holds no downloader, cache or account state.
@MainActor final class DownloadTaskRowView: NSView {
    struct Bindings {
        var perform: (DownloadTaskRow, DownloadTaskAction) -> Void
        var loadThumbnail: ((DownloadTaskRow, @escaping (NSImage?) -> Void) -> (() -> Void)?)? = nil
        var observeProgress: ((DownloadTaskRow, @escaping (DownloadTaskProgress) -> Void) -> (() -> Void)?)? = nil
    }

    private let bindings: Bindings
    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSLevelIndicator()
    private let actionsStack = NSStackView()
    private var buttons: [DownloadTaskAction: NSButton] = [:]
    private var row: DownloadTaskRow?
    private var thumbnailKey: String?
    private var cancelThumbnail: (() -> Void)?
    private var cancelProgress: (() -> Void)?
    private var lastByteSample: (bytes: Int64, date: Date)?
    private var lastProgressSequence = -1
    var displayedTask: DownloadTaskRow? { row }

    init(bindings: Bindings) {
        self.bindings = bindings
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
        thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        thumbnailView.contentTintColor = .tertiaryLabelColor
        thumbnailView.setAccessibilityElement(false)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.levelIndicatorStyle = .continuousCapacity
        progressBar.fillColor = .controlAccentColor
        progressBar.warningValue = 2
        progressBar.criticalValue = 2
        progressBar.drawsTieredCapacityLevels = false
        progressBar.controlSize = .small
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.setAccessibilityElement(true)
        progressBar.setAccessibilityRole(.progressIndicator)
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .centerY
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        for child in [thumbnailView, titleLabel, statusLabel, progressBar, actionsStack] { addSubview(child) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 76),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 48),
            thumbnailView.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            progressBar.trailingAnchor.constraint(equalTo: actionsStack.leadingAnchor, constant: -8),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(_ next: DownloadTaskRow) {
        let changedAttempt = row?.id != next.id
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
        titleLabel.stringValue = next.title
        progressBar.setAccessibilityLabel("下载进度：\(next.title)")
        for action in DownloadTaskAction.allCases where next.actions.contains(action) { _ = button(for: action) }
        for (action, button) in buttons {
            button.isHidden = !next.actions.contains(action)
            button.toolTip = Self.title(action)
            button.setAccessibilityLabel("\(Self.title(action))：\(next.title)")
        }
        if let progress = next.progress { apply(progress) }
        else if changedAttempt || changedPhase || next.phase != .transferring { applyFallback(next) }
        if !next.phase.isTerminal, needsProgressBinding {
            cancelProgress = bindings.observeProgress?(next) { [weak self] progress in
                guard let self, self.row?.id == next.id else { return }
                self.apply(progress)
            }
        }
        if changedAttempt || thumbnailKey != next.thumbnailKey {
            cancelThumbnail?()
            cancelThumbnail = nil
            thumbnailKey = next.thumbnailKey
            thumbnailView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            if next.thumbnailKey != nil {
                cancelThumbnail = bindings.loadThumbnail?(next) { [weak self] image in
                    guard let self, self.row?.id == next.id,
                          self.thumbnailKey == next.thumbnailKey, let image else { return }
                    self.thumbnailView.image = image
                }
            }
        }
    }

    private func button(for action: DownloadTaskAction) -> NSButton {
        if let existing = buttons[action] { return existing }
        let button = NSButton(title: Self.title(action), target: self, action: #selector(invoke(_:)))
        button.controlSize = .small
        button.bezelStyle = .rounded
        if [.cancel, .abandon, .removeHistory].contains(action) {
            button.title = ""
            button.isBordered = false
            button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: Self.title(action))?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
            button.contentTintColor = .secondaryLabelColor
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        } else if action == .revealFile {
            button.title = ""
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: Self.title(action))
        }
        let preceding = DownloadTaskAction.allCases.prefix { $0 != action }.filter { buttons[$0] != nil }.count
        buttons[action] = button
        actionsStack.insertArrangedSubview(button, at: preceding)
        return button
    }

    func unbind() {
        cancelProgress?()
        cancelThumbnail?()
        cancelProgress = nil
        cancelThumbnail = nil
        row = nil
        thumbnailKey = nil
        lastByteSample = nil
        lastProgressSequence = -1
    }

    private func applyFallback(_ row: DownloadTaskRow) {
        var text = row.statusText ?? row.phase.title
        if row.phase.isTerminal, let date = row.recordedAt {
            text += " · " + Self.dateFormatter.string(from: date)
        }
        status(text, phase: row.phase, fraction: row.phase == .completed ? 1 : nil)
    }

    private func apply(_ progress: DownloadTaskProgress) {
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
        status(parts.joined(separator: " · "), phase: progress.phase, fraction: progress.fraction)
    }

    private func status(_ text: String, phase: DownloadTaskPhase, fraction: Double?) {
        statusLabel.stringValue = text
        statusLabel.toolTip = text
        statusLabel.textColor = phase == .failed ? .systemRed : .secondaryLabelColor
        progressBar.isHidden = fraction == nil
        progressBar.doubleValue = fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
        progressBar.setAccessibilityValue(text)
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

    @objc private func invoke(_ sender: NSButton) {
        guard let row, let action = buttons.first(where: { $0.value === sender })?.key,
              row.actions.contains(action) else { return }
        bindings.perform(row, action)
    }

    private static func title(_ action: DownloadTaskAction) -> String {
        switch action {
        case .promote: return "优先下载"
        case .pause: return "暂停"
        case .resume: return "继续"
        case .retry: return "重试"
        case .revealFile: return "在访达中显示"
        case .cancel: return "取消下载"
        case .abandon: return "放弃任务"
        case .removeHistory: return "清除记录"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
