import SwiftUI

@main
struct PortspyBarApp: App {
    @StateObject private var monitor = PortMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                Text("\(monitor.listeners.count)")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
