import Foundation

/// Info / warning / error band kind.
enum InfoBandKind: String, CaseIterable, Sendable {
    case info
    case warning
    case error

    var markSystemImage: String? {
        switch self {
        case .info: nil
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}
