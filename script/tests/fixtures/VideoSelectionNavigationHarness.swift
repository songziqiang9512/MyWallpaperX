// Focused Video selection inputs. Production value types, source context,
// filtering, sorting, setter and arrow bodies are inserted by the runner.
import Foundation

// PRODUCTION_VALUE_TYPES

struct NavigationSettings: Equatable {
    var sortMode = WallpaperSortMode.none
    var sortAscending = true
}
struct NavigationInputs: Equatable {
    let library: [VideoWallpaper]
    let recent: [VideoWallpaper]
    let category: Category
    let tag: String?
    let query: String
    let settings: NavigationSettings
    let perSelection: [String: SortState]
    let multiSelect: Bool
    let searchFieldActive: Bool
    let columns: Int
}
@MainActor final class WallpaperManager {
    var wallpapers: [VideoWallpaper] = []
    var recentlyUsedWallpapers: [VideoWallpaper] = []
    var selectedCategory = Category.myWallpapers
    var selectedTag: String?
    var searchQuery = ""
    var settings = NavigationSettings()
    var perSelectionSortStates: [String: SortState] = [:]
    var isMultiSelectMode = false
    var isSearchFieldActive = false
    var visibleGridColumnCount = 3
    var selectedWallpaperId: String? {
        didSet { selectionWrites.append(selectedWallpaperId) }
    }
    var selectionWrites: [String?] = []
    var sortInputs: [[String]] = []
    var sortComparisons = 0
    var inputs: NavigationInputs {
        .init(
            library: wallpapers, recent: recentlyUsedWallpapers,
            category: selectedCategory, tag: selectedTag, query: searchQuery,
            settings: settings, perSelection: perSelectionSortStates,
            multiSelect: isMultiSelectMode, searchFieldActive: isSearchFieldActive,
            columns: visibleGridColumnCount
        )
    }
    func resetObservations() {
        selectionWrites = []
        sortInputs = []
        sortComparisons = 0
    }
    // PRODUCTION_MANAGER_METHODS
}

@main
@MainActor struct VideoSelectionNavigationHarness {
    static func record(_ id: String, _ title: String, tags: [String] = [], favorite: Bool = false,
        bytes: Int64? = 10, used: TimeInterval = 100, path: String? = nil) -> VideoWallpaper {
        VideoWallpaper(
            id: id, title: title, path: path ?? "/fixture/\(id).mp4", isFavorite: favorite,
            lastUsed: Date(timeIntervalSince1970: used), tags: tags, fileSize: bytes
        )
    }

    // Frozen reference for the old product sequence. Do not call the production
    // sorter/filter here: an incorrect rewrite must disagree with this result.
    static func legacyVisible(_ manager: WallpaperManager) -> [VideoWallpaper] {
        let context = manager.currentSelectionContext
        let source = context.sourceWallpapers(from: manager)
        let state = manager.perSelectionSortStates[context.scrollPersistenceKey]
            ?? SortState(mode: manager.settings.sortMode, ascending: manager.settings.sortAscending)
        let ordered: [VideoWallpaper]
        switch state.mode {
        case .none:
            ordered = source
        case .name:
            let ascending = source.sorted {
                $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending
            }
            ordered = state.ascending ? ascending : Array(ascending.reversed())
        case .size:
            let ascending = source.sorted {
                ($0.fileSize ?? Int64.max) < ($1.fileSize ?? Int64.max)
            }
            ordered = state.ascending ? ascending : Array(ascending.reversed())
        case .dateAdded:
            let ascending = source.sorted { $0.lastUsed < $1.lastUsed }
            ordered = state.ascending ? ascending : Array(ascending.reversed())
        }
        let query = manager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return ordered }
        return ordered.filter {
            $0.title.lowercased().contains(query) || $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    static func legacyTarget(_ rows: [VideoWallpaper], selected: String?, key: UInt16, columns: Int) -> String? {
        guard !rows.isEmpty else { return selected }
        let index = rows.firstIndex { $0.id == selected } ?? 0
        let destination: Int
        switch key {
        case 123:
            destination = max(0, index - 1)
        case 124:
            destination = min(rows.count - 1, index + 1)
        case 126:
            destination = max(0, index - max(1, columns))
        case 125:
            destination = min(rows.count - 1, index + max(1, columns))
        default:
            return selected
        }
        return rows[destination].id
    }

    static func navigate(_ manager: WallpaperManager, selected: String?, key: UInt16,
        ignoreSearch: Bool = false) -> (handled: Bool, id: String?, writes: [String?]) {
        manager.selectedWallpaperId = selected
        manager.resetObservations()
        let handled = manager.moveSingleSelectionByArrowKey(key, ignoreSearchFieldState: ignoreSearch)
        return (handled, manager.selectedWallpaperId, manager.selectionWrites)
    }

    static func testMatrix(_ checks: inout [String: Bool]) -> Int {
        let manager = WallpaperManager()
        manager.wallpapers = [
            record("c", "Needle same", tags: ["blue"], favorite: true),
            record("dup", "Needle same", tags: ["blue"], favorite: true),
            record("a", "Needle same", tags: ["blue"]),
            record("d", "Other", tags: ["needle", "red"], bytes: nil),
            record("e", "Alpha", tags: ["Blue"], bytes: 20, used: 1),
            record("f", "", tags: ["red"], favorite: true, bytes: Int64.max, used: 50, path: "/fixture/NeedleFile.mp4"),
            record("dup", "Needle secondary", tags: ["blue"], used: 200),
            record("g", "Text", tags: ["red"], bytes: 20, used: 1),
            record("h", "中文 needle", tags: ["green"], favorite: true, bytes: 20, used: 200),
            record("i", "neEdle", bytes: 1, used: 10)]
        manager.recentlyUsedWallpapers = [
            manager.wallpapers[5], manager.wallpapers[0], manager.wallpapers[7], manager.wallpapers[1]]
        let contexts: [(Category, String?)] = [
            (.myWallpapers, nil), (.favorites, nil), (.recentlyUsed, nil), (.tags, nil),
            (.settings, nil), (.myWallpapers, "blue"), (.tags, "absent")]
        var resultMatches = true
        var writesMatch = true
        var inputsUnchanged = true
        var steps = 0, states = 0
        for mode in WallpaperSortMode.allCases {
            for ascending in [false, true] {
                for usePerSelection in [false, true] {
                    for (category, tag) in contexts {
                        manager.selectedCategory = category
                        manager.selectedTag = tag
                        for query in ["", " NEEDLE \n", "blue", "no-match"] {
                            manager.searchQuery = query
                            manager.visibleGridColumnCount = [0, 1, 3][states % 3]
                            if usePerSelection {
                                manager.settings = NavigationSettings(
                                    sortMode: mode == .name ? .size : .name, sortAscending: !ascending)
                                manager.perSelectionSortStates = [manager.currentSelectionContext.scrollPersistenceKey:
                                    SortState(mode: mode, ascending: ascending)]
                            } else {
                                manager.settings = NavigationSettings(sortMode: mode, sortAscending: ascending)
                                manager.perSelectionSortStates = [
                                    "unrelated": SortState(mode: .none, ascending: !ascending)]
                            }
                            let visible = legacyVisible(manager)
                            let selections: [String?] = [nil, visible.dropFirst().first?.id, "not-present"]
                            for selected in selections {
                                for key in [UInt16(123), 124, 125, 126] {
                                    let before = manager.inputs
                                    let expected = legacyTarget(visible, selected: selected,
                                        key: key, columns: manager.visibleGridColumnCount)
                                    let actual = navigate(manager, selected: selected, key: key)
                                    resultMatches = resultMatches
                                        && actual.handled == !visible.isEmpty && actual.id == expected
                                    writesMatch = writesMatch && actual.writes == (visible.isEmpty ? [] : [expected])
                                    inputsUnchanged = inputsUnchanged && manager.inputs == before
                                    steps += 1
                                }
                            }
                            states += 1
                        }
                    }
                }
            }
        }
        checks["matrixArrowResultMatchesLegacySortThenFilter"] = resultMatches && steps == 5376
        checks["matrixSelectionWritesMatchHandledNavigation"] = writesMatch
        checks["matrixNavigationLeavesInputsUnchanged"] = inputsUnchanged
        return steps
    }

    static func testLiteralCases(_ checks: inout [String: Bool]) {
        let manager = WallpaperManager()
        manager.wallpapers = [
            record("a", "A", tags: ["blue"]), record("b", "B"), record("c", "C"), record("d", "D")]
        manager.selectedCategory = .settings
        let fallback = navigate(manager, selected: "a", key: 124)
        checks["settingsCategoryUsesRealLibraryFallback"] = manager.currentSelectionContext == .category(.myWallpapers)
            && manager.currentSelectionContext.scrollPersistenceKey == "category.myWallpapers"
            && fallback.handled && fallback.id == "b"
        manager.selectedTag = "blue"
        let tagged = navigate(manager, selected: nil, key: 124)
        checks["selectedTagOverridesCategoryAndSortKey"] = manager.currentSelectionContext == .tag("blue")
            && manager.currentSelectionContext.scrollPersistenceKey == "tag.blue"
            && tagged.handled && tagged.id == "a"
        manager.selectedTag = nil
        manager.selectedCategory = .myWallpapers

        manager.wallpapers = [record("tie-2", "Same"), record("tie-1", "Same"), record("tie-3", "Same")]
        manager.settings = NavigationSettings(sortMode: .name, sortAscending: false)
        let nameFirst = navigate(manager, selected: nil, key: 123)
        let nameNext = navigate(manager, selected: "tie-3", key: 124)
        checks["equalNameKeysReverseTheirInputOrderWhenDescending"] = nameFirst.id == "tie-3" && nameNext.id == "tie-1"
        manager.wallpapers = [
            record("small", "Small", bytes: 5), record("unknown", "Unknown", bytes: nil),
            record("maximum", "Maximum", bytes: Int64.max)]
        manager.settings = NavigationSettings(sortMode: .size, sortAscending: false)
        let sizeFirst = navigate(manager, selected: nil, key: 123)
        let sizeNext = navigate(manager, selected: "maximum", key: 124)
        let sizeLast = navigate(manager, selected: "unknown", key: 124)
        checks["unknownAndMaximumSizesKeepTheFormerTieOrder"] = sizeFirst.id == "maximum"
            && sizeNext.id == "unknown" && sizeLast.id == "small"
        manager.wallpapers = [
            record("early-2", "Z", used: 1), record("early-1", "A", used: 1), record("late", "M", used: 2)]
        manager.settings = NavigationSettings(sortMode: .dateAdded, sortAscending: false)
        let dateFirst = navigate(manager, selected: nil, key: 123)
        let dateNext = navigate(manager, selected: "late", key: 124)
        checks["dateSortUsesLastUsedAndKeepsItsFormerTieOrder"] = dateFirst.id == "late" && dateNext.id == "early-1"
        manager.settings = NavigationSettings(sortMode: .none, sortAscending: false)
        checks["defaultSortIgnoresDescendingAndKeepsSourceOrder"] =
            navigate(manager, selected: nil, key: 123).id == "early-2"

        manager.wallpapers = [
            record("visible", "Z visible"), record("fallback", "", path: "/fixture/A display.mp4")]
        manager.settings = NavigationSettings(sortMode: .name, sortAscending: true)
        let displayFirst = navigate(manager, selected: nil, key: 123)
        manager.searchQuery = "a display"
        let pathOnly = navigate(manager, selected: "kept", key: 124)
        checks["displayTitleFallbackSortDoesNotMakeThePathSearchable"] = displayFirst.id == "fallback"
            && !pathOnly.handled && pathOnly.id == "kept" && pathOnly.writes.isEmpty
        manager.wallpapers = [
            record("tag-hit", "Other", tags: ["NeEdLe"]),
            record("title-hit", "needle title"), record("miss", "Other")]
        manager.settings = NavigationSettings(sortMode: .none, sortAscending: false)
        manager.searchQuery = " \n NEEDLE \t"
        checks["normalizedQueryMatchesTitlesAndTagsInVisibleOrder"] =
            navigate(manager, selected: "tag-hit", key: 124).id == "title-hit"
        manager.searchQuery = ""
        manager.wallpapers = [
            record("dup", "First"), record("middle", "Middle"), record("dup", "Last"), record("end", "End")]
        checks["duplicateIDsStillLocateTheFirstVisibleOccurrence"] =
            navigate(manager, selected: "dup", key: 124).id == "middle"
        manager.wallpapers = [
            record("a", "A"), record("b", "B"), record("c", "C"), record("d", "D")]
        let missingRight = navigate(manager, selected: "not-present", key: 124)
        let missingLeft = navigate(manager, selected: nil, key: 123)
        checks["missingCurrentSelectionStillStartsFromIndexZero"] = missingRight.id == "b" && missingLeft.id == "a"
        manager.visibleGridColumnCount = 3
        let firstLeft = navigate(manager, selected: "a", key: 123)
        let firstUp = navigate(manager, selected: "a", key: 126)
        let firstDown = navigate(manager, selected: "a", key: 125)
        let lastRight = navigate(manager, selected: "d", key: 124)
        let lastDown = navigate(manager, selected: "d", key: 125)
        manager.visibleGridColumnCount = 0
        let zeroColumns = navigate(manager, selected: "a", key: 125)
        manager.visibleGridColumnCount = -3
        let negativeColumns = navigate(manager, selected: "b", key: 126)
        checks["directionalBoundsAndColumnFallbackStayUnchanged"] = firstLeft.id == "a" && firstUp.id == "a"
            && firstDown.id == "d" && lastRight.id == "d" && lastDown.id == "d"
            && zeroColumns.id == "b" && negativeColumns.id == "a"

        manager.selectedTag = "absent"
        let emptyContext = navigate(manager, selected: "a", key: 124)
        manager.selectedTag = nil
        manager.searchQuery = "no-match"
        let noMatch = navigate(manager, selected: "a", key: 124)
        checks["emptyContextAndNoMatchDoNotWriteSelection"] = !emptyContext.handled
            && emptyContext.id == "a" && emptyContext.writes.isEmpty
            && !noMatch.handled && noMatch.id == "a" && noMatch.writes.isEmpty
        manager.searchQuery = ""
        manager.isMultiSelectMode = true
        let multi = navigate(manager, selected: "a", key: 124)
        let multiDidNoSort = manager.sortInputs.isEmpty
        manager.isMultiSelectMode = false
        manager.isSearchFieldActive = true
        let focused = navigate(manager, selected: "a", key: 124)
        let focusedDidNoSort = manager.sortInputs.isEmpty
        manager.isSearchFieldActive = false
        let unsupported = navigate(manager, selected: "a", key: 49)
        checks["multiSelectSearchFieldAndUnsupportedGuardsDoNotSortOrWrite"] = !multi.handled
            && multi.id == "a" && multi.writes.isEmpty && multiDidNoSort
            && !focused.handled && focused.id == "a" && focused.writes.isEmpty && focusedDidNoSort
            && !unsupported.handled && unsupported.id == "a" && unsupported.writes.isEmpty
            && manager.sortInputs.isEmpty
        manager.isSearchFieldActive = true
        let ignoredFocus = navigate(manager, selected: "a", key: 124, ignoreSearch: true)
        checks["explicitIgnoreSearchFieldStillNavigates"] = ignoredFocus.handled
            && ignoredFocus.id == "b" && ignoredFocus.writes == ["b"]
    }

    static func testWork(_ checks: inout [String: Bool]) -> [String: Int] {
        let manager = WallpaperManager()
        manager.wallpapers = (0..<1024).map { index in
            let matches = [0, 333, 666, 999].contains(index)
            return record("item-\(index)", matches ? "needle \(1024 - index)" : "background \(1024 - index)")
        }
        manager.settings = NavigationSettings(sortMode: .name, sortAscending: true)
        manager.searchQuery = "needle"
        let legacy = legacyVisible(manager)
        let narrow = navigate(manager, selected: nil, key: 124)
        let narrowComparisons = manager.sortComparisons
        let narrowInputCount = manager.sortInputs.first?.count ?? -1
        checks["largeNarrowSearchKeepsLegacySelection"] = narrow.handled
            && narrow.id == legacy[1].id && narrow.writes == [legacy[1].id]
        checks["narrowSearchSortsOnlyMatchingInputs"] = manager.sortInputs == [["item-0", "item-333", "item-666", "item-999"]]
            && narrowComparisons > 0 && narrowComparisons < 1024
        manager.searchQuery = "no-match"
        let noMatch = navigate(manager, selected: "unchanged", key: 124)
        let noMatchComparisons = manager.sortComparisons
        checks["noMatchSearchDoesNoSortComparisons"] = noMatchComparisons == 0
            && !noMatch.handled && noMatch.id == "unchanged" && noMatch.writes.isEmpty
        manager.searchQuery = ""
        let whole = navigate(manager, selected: nil, key: 124)
        let wholeComparisons = manager.sortComparisons
        checks["emptyQueryRetainsFullSortingInput"] = manager.sortInputs == [manager.wallpapers.map(\.id)]
            && wholeComparisons > 0 && whole.handled
        manager.settings = NavigationSettings(sortMode: .none, sortAscending: false)
        let unsorted = navigate(manager, selected: nil, key: 124)
        checks["defaultModeAlwaysAvoidsSortComparisons"] = manager.sortComparisons == 0 && unsorted.id == "item-1"
        return [
            "narrowInputCount": narrowInputCount,
            "narrowComparisons": narrowComparisons,
            "noMatchComparisons": noMatchComparisons,
            "emptyQueryComparisons": wholeComparisons,
        ]
    }

    static func main() throws {
        var checks: [String: Bool] = [:]
        let steps = testMatrix(&checks)
        testLiteralCases(&checks)
        let observations = testWork(&checks)
        let metricValues: [String: Any] = ["navigationSteps": steps, "sortMetrics": observations]
        let metrics = try JSONSerialization.data(withJSONObject: metricValues, options: [.sortedKeys])
        FileHandle.standardError.write(metrics + Data("\n".utf8))
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
