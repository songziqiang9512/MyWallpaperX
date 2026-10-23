//
//  AppKitSettingsComponents.swift
//  MyWallpaperX
//

import AppKit

final class SettingsGroupView: NSView {
    private let titleLabel: NSTextField
    private let showsTitle: Bool
    private let backgroundView: NSBox = {
        let view = NSBox()
        view.boxType = .custom
        view.borderWidth = 0
        view.cornerRadius = 0
        view.titlePosition = .noTitle
        view.contentViewMargins = .zero
        view.fillColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.white.withAlphaComponent(0.02)
            }
            return NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .underPageBackgroundColor)
                ?? .textBackgroundColor
        }
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let rowStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var contentRows: [NSView] = []
    private var separators: [NSView] = []

    init(title: String?) {
        let normalizedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        titleLabel = NSTextField(labelWithString: normalizedTitle)
        showsTitle = !normalizedTitle.isEmpty
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = !showsTitle

        addSubview(titleLabel)
        addSubview(backgroundView)
        addSubview(rowStack)

        var constraints: [NSLayoutConstraint] = [
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]

        if showsTitle {
            constraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: topAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
                backgroundView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
            ])
        } else {
            constraints.append(backgroundView.topAnchor.constraint(equalTo: topAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func addRow(_ row: NSView) {
        if !contentRows.isEmpty {
            let separator = makeSeparator()
            rowStack.addArrangedSubview(separator)
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
            separators.append(separator)
        }
        rowStack.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        contentRows.append(row)
        refreshSeparators()
    }

    func refreshSeparators() {
        guard !separators.isEmpty else { return }

        for (index, separator) in separators.enumerated() {
            guard index + 1 < contentRows.count else {
                separator.isHidden = true
                continue
            }

            let previousRow = contentRows[index]
            let nextRow = contentRows[index + 1]
            separator.isHidden = previousRow.isHidden || nextRow.isHidden
        }
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.cornerRadius = 0
        separator.titlePosition = .noTitle
        separator.contentViewMargins = .zero
        separator.fillColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.separatorColor.withAlphaComponent(isDark ? 0.12 : 0.16)
        }
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }
}
