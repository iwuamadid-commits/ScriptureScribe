//
//  NetworkMonitor.swift
//  ScriptureScribe
//
//  Watches the device's network path in real time using NWPathMonitor.
//  Publishes `isConnected` so any SwiftUI view can react instantly
//  when the user toggles airplane mode or loses Wi-Fi.
//

import Combine
import Network
import SwiftUI

@MainActor
final class NetworkMonitor: ObservableObject {

    @Published var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
