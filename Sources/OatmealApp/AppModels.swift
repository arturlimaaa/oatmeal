import Foundation

enum SidebarItem: Hashable, Codable {
    case upcoming
    case allNotes
    case folder(UUID)
    case templates
}
