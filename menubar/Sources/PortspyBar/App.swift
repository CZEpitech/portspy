import SwiftUI

@main
struct PortspyBarApp: App {
    @StateObject private var monitor = PortMonitor()
    @StateObject private var aliases = AliasStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor, aliases: aliases)
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
