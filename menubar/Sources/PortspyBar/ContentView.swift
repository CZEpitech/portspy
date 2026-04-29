import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: PortMonitor
    @State private var query = ""

    var filtered: [PortListener] {
        guard !query.isEmpty else { return monitor.listeners }
        let q = query.lowercased()
        return monitor.listeners.filter { l in
            String(l.port).contains(q)
                || l.command.lowercased().contains(q)
                || l.user.lowercased().contains(q)
                || l.address.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = monitor.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                Divider()
            }
            list
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter port, process, user", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.body))
            if monitor.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var list: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(monitor.listeners.isEmpty ? "No listening ports" : "No match")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { listener in
                            PortRow(listener: listener) {
                                monitor.kill(pid: listener.pid)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(monitor.listeners.count) listening")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { monitor.refresh() }
                .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct PortRow: View {
    let listener: PortListener
    let onKill: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(listener.port)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Text(listener.proto.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    Text(listener.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(listener.command) • PID \(listener.pid) • \(listener.user)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hover {
                Button(action: onKill) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Send SIGTERM to PID \(listener.pid)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(hover ? Color.gray.opacity(0.12) : Color.clear)
        .onHover { hover = $0 }
    }
}
