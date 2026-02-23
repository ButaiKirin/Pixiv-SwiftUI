import Foundation

enum SpotlightCategory: String, CaseIterable, Codable {
    case illustration

    var displayName: String {
        switch self {
        case .illustration:
            return String(localized: "插画")
        }
    }

    var urlPath: String {
        "/zh/c/\(rawValue)"
    }
}
