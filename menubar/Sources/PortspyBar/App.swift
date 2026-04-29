import AppKit
import Combine
import SwiftUI

@main
struct PortspyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let monitor = PortMonitor()
    private let aliases = AliasStore()
    private let toast = ToastCenter()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        configurePopover()
        observeListeners()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "portspy")
        button.imagePosition = .imageLeading
        button.title = " 0"
        button.font = .menuBarFont(ofSize: 0)
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.behavior = .semitransient
        popover.animates = true

        let root = ContentView(
            monitor: monitor,
            aliases: aliases,
            toast: toast,
            onOpenURL: { [weak self] url in self?.openInBrowser(url) },
            onClose: { [weak self] in self?.closePopover() }
        )
        popover.contentViewController = NSHostingController(rootView: root)
    }

    private func observeListeners() {
        monitor.$listeners
            .receive(on: DispatchQueue.main)
            .sink { [weak self] listeners in
                self?.statusItem?.button?.title = " \(listeners.count)"
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            installEscapeMonitor()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        removeEscapeMonitor()
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func openInBrowser(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.toast.show("Failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill")
                } else {
                    self.toast.show("Opened \(url.absoluteString)")
                }
            }
        }
    }
}
