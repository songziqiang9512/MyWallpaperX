import Foundation

enum SteamWorkshopGridKeyboardNavigation {
    static func destinationIndex(
        keyCode: UInt16,
        currentIndex: Int?,
        itemCount: Int,
        columnCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        let current = min(max(0, currentIndex ?? 0), itemCount - 1)
        let delta: Int
        switch keyCode {
        case 123:
            delta = -1
        case 124:
            delta = 1
        case 126:
            delta = -max(1, columnCount)
        case 125:
            delta = max(1, columnCount)
        default:
            return nil
        }
        let destination = min(max(0, current + delta), itemCount - 1)
        guard destination != current || currentIndex == nil else { return nil }
        return destination
    }

    static func isPrimaryActionKey(_ keyCode: UInt16) -> Bool {
        keyCode == 36 || keyCode == 76
    }
}
