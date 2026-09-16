//
//  SteamWorkshopFilterPanel.swift
//  MyWallpaperX
//

import AppKit
import Combine

/// 浏览筛选面板（工具栏「筛选」按钮的 popover 内容）：四个分面
/// （类型/分级/分辨率/分类）各自多选，面内 OR、跨面 AND，变更即时
/// 生效并保持面板打开；底部提供清空筛选。状态唯一 Owner 是
/// `SteamWorkshopService.facetFilters`，本面板只是其投影。
/// popover 的持有与锚定由工具栏控制器负责（与下载任务面板同构）。
@MainActor
final class SteamWorkshopFilterPanelController: NSViewController {
    private let service: SteamWorkshopService
    private var cancellables = Set<AnyCancellable>()

    private let facetStack = NSStackView()
    private var facetCheckboxes: [(button: NSButton, option: FacetOption)] = []
    /// 分类多选由 browserContentMode 持有，与其他分面共同组成查询键。
    private var contentTypeCheckboxes: [(button: NSButton, mode: SteamWorkshopBrowserContentMode)] = []
    private let clearButton = NSButton(title: "清空筛选", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")

    static let panelWidth: CGFloat = 400
    /// 面板内容高度（分面网格自适应拟合），供 popover.contentSize 使用。
    private(set) var preferredPanelHeight: CGFloat = 320

    init(service: SteamWorkshopService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        view = root

        facetStack.orientation = .vertical
        facetStack.alignment = .leading
        facetStack.spacing = 10
        facetStack.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(handleClearFilters)
        clearButton.setAccessibilityLabel("清空全部筛选")

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail

        let footer = NSStackView(views: [clearButton, summaryLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(facetStack)
        root.addSubview(separator)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            facetStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            facetStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            facetStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: facetStack.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            footer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            summaryLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.panelWidth - 130)
        ])

        rebuildFacetViews()
        syncFacetStates()
        observeFilters()
    }

    // MARK: - 结构

    private struct FacetSpec {
        let header: String
        let options: [FacetOption]
        let columns: Int
    }

    /// 一行选项：`isAll` 表示「全部」开关（该面选择集为空时勾选）。
    /// 勾选状态永远由 service 投影回填；闭包只描述「怎么改」。
    private struct FacetOption {
        let title: String
        var isMarked: (SteamWorkshopBrowseFacetFilters) -> Bool
        var toggle: (inout SteamWorkshopBrowseFacetFilters) -> Void
    }

    private func makeFacetSpecs() -> [FacetSpec] {
        let themeOptions: [FacetOption] = [
            FacetOption(title: "全部", isMarked: { $0.themes.isEmpty }, toggle: { $0.themes = [] })
        ] + SteamWorkshopThemeFilter.allCases.filter { $0 != .all }.map { filter in
            FacetOption(
                title: filter.displayName,
                isMarked: { $0.themes.contains(filter) },
                toggle: { $0.themes.formSymmetricDifference([filter]) }
            )
        }
        let ratingOptions: [FacetOption] = [
            FacetOption(title: "全部", isMarked: { $0.ageRating == .all }, toggle: { $0.ageRating = .all })
        ] + SteamWorkshopAgeRatingFilter.selectableRatings.map { rating in
            FacetOption(
                title: rating.displayName,
                isMarked: { $0.ageRating != .all && $0.ageRating.contains(rating) },
                toggle: { filters in
                    if filters.ageRating == .all { filters.ageRating = rating; return }
                    filters.ageRating.formSymmetricDifference(rating)
                    if filters.ageRating.isEmpty { filters.ageRating = .all }
                }
            )
        }
        let resolutionOptions: [FacetOption] = [
            FacetOption(title: "全部", isMarked: { $0.resolutions.isEmpty }, toggle: { $0.resolutions = [] })
        ] + SteamWorkshopResolutionFilter.allCases.filter { $0 != .all }.map { filter in
            FacetOption(
                title: filter.displayName,
                isMarked: { $0.resolutions.contains(filter) },
                toggle: { $0.resolutions.formSymmetricDifference([filter]) }
            )
        }
        return [
            FacetSpec(header: "类型", options: themeOptions, columns: 4),
            FacetSpec(header: "分级", options: ratingOptions, columns: 2),
            FacetSpec(header: "分辨率", options: resolutionOptions, columns: 3)
        ]
    }

    /// 分类区（全部/视频/网页/场景）直接绑定 `browserContentMode`，
    /// 同组任选；与其他分面共同过滤。
    private func makeContentTypeBlock() -> NSView {
        let header = NSTextField(labelWithString: "分类")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        var checkboxes: [NSView] = []
        for mode in SteamWorkshopBrowserContentMode.allCases {
            let checkbox = NSButton(checkboxWithTitle: mode.shortDisplayName, target: self, action: #selector(handleContentTypeToggle(_:)))
            checkbox.font = .systemFont(ofSize: 12.5)
            checkbox.controlSize = .small
            checkbox.contentTintColor = .labelColor
            checkbox.setAccessibilityLabel("分类：\(mode.displayName)")
            contentTypeCheckboxes.append((checkbox, mode))
            checkboxes.append(checkbox)
        }
        let grid = NSGridView(views: [checkboxes])
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        for index in 0..<grid.numberOfColumns {
            grid.column(at: index).width = (Self.panelWidth - 64) / 4
        }

        let block = NSStackView(views: [header, grid])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 6
        return block
    }

    private func rebuildFacetViews() {
        facetCheckboxes = []
        contentTypeCheckboxes = []
        let contentWidth = Self.panelWidth - 28 // root 左右各 14pt 边距

        // 分类多选区置顶。
        facetStack.addArrangedSubview(makeContentTypeBlock())

        for spec in makeFacetSpecs() {
            let header = NSTextField(labelWithString: spec.header)
            header.font = .systemFont(ofSize: 11, weight: .semibold)
            header.textColor = .secondaryLabelColor

            var checkboxes: [NSView] = []
            for option in spec.options {
                let checkbox = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(handleFacetToggle(_:)))
                checkbox.font = .systemFont(ofSize: 12.5)
                checkbox.controlSize = .small
                checkbox.contentTintColor = .labelColor
                checkbox.setAccessibilityLabel("\(spec.header)：\(option.title)")
                facetCheckboxes.append((checkbox, option))
                checkboxes.append(checkbox)
            }

            let grid = NSGridView(views: chunked(checkboxes, size: spec.columns))
            grid.rowSpacing = 6
            grid.columnSpacing = 12
            grid.translatesAutoresizingMaskIntoConstraints = false
            // 每列等宽且网格整体填满面板内容宽度：四个分区同宽、列缘
            // 对齐，不再按 checkbox 固有宽度各自收缩造成参差。
            let columnWidth = ((contentWidth - CGFloat(spec.columns - 1) * grid.columnSpacing)
                / CGFloat(spec.columns)).rounded(.down)
            for columnIndex in 0..<grid.numberOfColumns {
                grid.column(at: columnIndex).width = columnWidth
            }

            let block = NSStackView(views: [header, grid])
            block.orientation = .vertical
            block.alignment = .leading
            block.spacing = 6
            facetStack.addArrangedSubview(block)
        }
    }

    private func chunked(_ views: [NSView], size: Int) -> [[NSView]] {
        guard size > 0 else { return [views] }
        return stride(from: 0, to: views.count, by: size).map { start in
            Array(views[start..<min(start + size, views.count)])
        }
    }

    // MARK: - 状态

    private func observeFilters() {
        service.$facetFilters
            .combineLatest(service.$browserContentMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFacetStates()
            }
            .store(in: &cancellables)
    }

    private func syncFacetStates() {
        let filters = service.facetFilters
        for (checkbox, option) in facetCheckboxes {
            checkbox.state = option.isMarked(filters) ? .on : .off
        }
        let currentMode = service.browserContentMode
        for (checkbox, mode) in contentTypeCheckboxes {
            checkbox.state = (mode == .all ? currentMode.isAll : !currentMode.isAll && currentMode.contains(mode)) ? .on : .off
        }
        clearButton.isEnabled = !filters.isEmpty || !currentMode.isAll
        summaryLabel.stringValue = "当前筛选：\(service.activeFilterSummary)"
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize.height
        preferredPanelHeight = min(max(fitting, 240), 560)
    }

    @objc private func handleContentTypeToggle(_ sender: NSButton) {
        guard let mode = contentTypeCheckboxes.first(where: { $0.button === sender })?.mode else { return }
        var selection = service.browserContentMode
        selection.toggle(mode)
        service.browserContentMode = selection
        syncFacetStates()
    }

    @objc private func handleFacetToggle(_ sender: NSButton) {
        guard let option = facetCheckboxes.first(where: { $0.button === sender })?.option else { return }
        var filters = service.facetFilters
        option.toggle(&filters)
        service.facetFilters = filters
        syncFacetStates()
    }

    @objc private func handleClearFilters() {
        service.clearFilters()
        syncFacetStates()
    }
}
