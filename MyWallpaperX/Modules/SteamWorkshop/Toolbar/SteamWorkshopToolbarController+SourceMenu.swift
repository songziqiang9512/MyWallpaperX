import AppKit

extension SteamWorkshopToolbarController {
    func populateSourceMenu(_ menu: NSMenu?) {
        SteamWorkshopSource.publicSources.forEach { source in
            let item = NSMenuItem(title: source.displayName, action: nil, keyEquivalent: "")
            item.representedObject = source.rawValue
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
        SteamWorkshopPersonalSort.allCases.forEach { sort in
            let item = NSMenuItem(title: sort.displayName, action: nil, keyEquivalent: "")
            item.representedObject = sort.rawValue
            menu?.addItem(item)
        }
    }
}
