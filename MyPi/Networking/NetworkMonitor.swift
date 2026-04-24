import Foundation
import Network
import Observation

/// Observes network path changes. ViewModels subscribe to `isConnected` to
/// pause/resume polling without burning battery when offline.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    // Default to false so fetches don't slip through the NWPathMonitor guard
    // during the brief window before its first callback fires. The monitor
    // flips this to true inside the path-update handler immediately if the
    // device is actually online.
    private(set) var isConnected: Bool = false
    private(set) var connectionType: NWInterface.InterfaceType? = nil

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.myssdomain.mypi.netmonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
