import Foundation

enum SidebarItem: Hashable {
    case upcoming
    case allNotes
    case folder(UUID)
    case templates
}
