import SwiftUI

/// Connection state for a configured site, shown in the Sites list and Settings.
enum SiteConnectionState: Equatable {
    case unknown
    case probing
    case connected(serverVersion: String)
    case unauthorized
    case offline
    case tlsError(String)
    case error(String)

    var label: String {
        switch self {
        case .unknown:          return "Unknown"
        case .probing:          return "Connecting…"
        case .connected:        return "Connected"
        case .unauthorized:     return "Unauthorized"
        case .offline:          return "Offline"
        case .tlsError:         return "TLS error"
        case .error:            return "Error"
        }
    }

    var detail: String? {
        switch self {
        case .connected(let v): return v
        case .tlsError(let m),
             .error(let m):     return m
        default:                return nil
        }
    }

    var color: Color {
        switch self {
        case .connected:                     return .green
        case .probing, .unknown:             return .secondary
        case .unauthorized, .tlsError,
             .offline, .error:               return .red
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
