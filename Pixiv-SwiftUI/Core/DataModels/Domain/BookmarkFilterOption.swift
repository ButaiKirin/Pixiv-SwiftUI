import Foundation

enum BookmarkFilterOption: Int, CaseIterable, Identifiable, Hashable {
    case none = 0
    case users100 = 100
    case users250 = 250
    case users500 = 500
    case users1000 = 1000
    case users5000 = 5000
    case users7500 = 7500
    case users10000 = 10000
    case users20000 = 20000
    case users30000 = 30000
    case users50000 = 50000

    var id: Int { self.rawValue }

    var displayName: String {
        if self == .none {
            return String(localized: "无过滤")
        }
        return "\(self.rawValue)+"
    }

    var suffix: String {
        if self == .none {
            return ""
        }
        return " \(self.rawValue)users入り"
    }
}
