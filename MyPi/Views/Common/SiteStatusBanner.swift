import SwiftUI

/// Shown at the top of Dashboard and Query Log when the active site's
/// connection state is anything other than `.connected`. Communicates both
/// the problem and the current retry cadence so the user knows the app is
/// still trying rather than silently serving stale data.
struct SiteStatusBanner: View {
    let siteName: String
    let state: SiteConnectionState
    /// Effective poll interval in seconds, including any failure backoff.
    let retryIntervalSeconds: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(state.color)
                .font(.subheadline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.footnote).bold()
                    .foregroundStyle(state.color)
                if let detail = subline {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            state.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal)
    }

    private var icon: String {
        switch state {
        case .probing, .unknown: return "antenna.radiowaves.left.and.right"
        case .unauthorized:      return "lock.slash"
        case .offline:           return "wifi.slash"
        case .tlsError:          return "lock.trianglebadge.exclamationmark"
        case .error:             return "exclamationmark.triangle.fill"
        case .connected:         return "checkmark.circle.fill"
        }
    }

    private var headline: String {
        switch state {
        case .probing:      return "Checking “\(siteName)”…"
        case .unknown:      return "“\(siteName)” status unknown"
        case .unauthorized: return "“\(siteName)” rejected the API key"
        case .offline:      return "“\(siteName)” is offline"
        case .tlsError:     return "“\(siteName)” TLS error"
        case .error:        return "“\(siteName)” is currently unreachable"
        case .connected:    return "“\(siteName)” connected"
        }
    }

    private var subline: String? {
        let detail = state.detail
        switch state {
        case .connected, .probing, .unknown:
            return detail
        default:
            if let interval = retryIntervalSeconds {
                let retry = "Retrying every \(formatted(interval))"
                if let detail, !detail.isEmpty {
                    return "\(detail) · \(retry)"
                }
                return retry
            }
            return detail
        }
    }

    private func formatted(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}
