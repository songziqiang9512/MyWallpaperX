import AppKit

extension SteamWorkshopToolbarController {
    func populateSourceMenu(_ menu: NSMenu?) {
        menu?.autoenablesItems = false
        SteamWorkshopSource.publicSources.forEach { source in
            let item = NSMenuItem(title: source.displayName, action: nil, keyEquivalent: "")
            item.representedObject = source.rawValue
            if SteamWorkshopService.shared.isSteamKitBrowseEnabled && source == .updated {
                item.isEnabled = false
                item.title += "（暂不支持）"
            }
            menu?.addItem(item)
        }
    }

    func populatePersonalListMenu(_ menu: NSMenu?) {
        SteamWorkshopSource.personalSources.forEach { source in
            let item = NSMenuItem(title: source.displayName, action: nil, keyEquivalent: "")
            item.representedObject = source.rawValue
            menu?.addItem(item)
        }
    }

    func populatePersonalSortMenu(_ menu: NSMenu?) {
        menu?.autoenablesItems = false
        SteamWorkshopPersonalSort.allCases.forEach { sort in
            let item = NSMenuItem(title: sort.displayName, action: nil, keyEquivalent: "")
            item.representedObject = sort.rawValue
            if SteamWorkshopService.shared.isSteamKitBrowseEnabled && (sort == .rating || sort == .favorites) {
                item.isEnabled = false
                item.title += "（暂不支持）"
            }
            menu?.addItem(item)
        }
    }
}
