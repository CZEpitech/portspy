import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: PortMonitor
    @ObservedObject var aliases: AliasStore

    @State private var query = ""
    @State private var editingKey: String?
    @State private var category: PortCategory = .web

    var matched: [PortListener] {
        guard !query.isEmpty else { return monitor.listeners }
        let q = query.lowercased()
        return monitor.listeners.filter { l in
            let alias = aliases.alias(for: l)?.lowercased() ?? ""
            return String(l.port).contains(q)
                || l.command.lowercased().contains(q)
                || l.user.lowercased().contains(q)
                || l.address.lowercased().contains(q)
                || alias.contains(q)
        }
    }

    var grouped: [PortCategory: [PortListener]] {
        Dictionary(grouping: matched) { Categorizer.category(for: $0) }
    }

    var visible: [PortListener] {
        grouped[category] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
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
        .frame(width: 420)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter port, process, alias, user", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.body))
            if monitor.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PortCategory.allCases) { cat in
                let count = grouped[cat]?.count ?? 0
                Button {
                    category = cat
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon)
                        Text(cat.label)
                        Text("\(count)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(category == cat ? 0.25 : 0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(category == cat ? Color.accentColor.opacity(0.18) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var list: some View {
        Group {
            if visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(monitor.listeners.isEmpty
                         ? "No listening ports"
                         : "Nothing in \(category.label)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { listener in
                            PortRow(
                                listener: listener,
                                alias: aliases.alias(for: listener),
                                isEditing: editingKey == aliases.key(for: listener),
                                onStartEdit: { editingKey = aliases.key(for: listener) },
                                onCommit: { newValue in
                                    aliases.setAlias(newValue, for: listener)
                                    editingKey = nil
                                },
                                onCancel: { editingKey = nil },
                                onClear: {
                                    aliases.clear(for: listener)
                                    editingKey = nil
                                },
                                onKill: { monitor.kill(pid: listener.pid) }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 400)
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
    let alias: String?
    let isEditing: Bool
    let onStartEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onClear: () -> Void
    let onKill: () -> Void

    @State private var draft: String = ""
    @State private var hover = false
    @FocusState private var focused: Bool

    private var displayName: String { alias ?? listener.command }
    private var category: PortCategory { Categorizer.category(for: listener) }
    private var webURL: URL? {
        category == .web ? Categorizer.webURL(for: listener) : nil
    }

    var body: some View {
        HStack(spacing: 8) {
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
                if isEditing {
                    HStack(spacing: 6) {
                        TextField(listener.command, text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .focused($focused)
                            .onSubmit { onCommit(draft) }
                        Button("Save") { onCommit(draft) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .keyboardShortcut(.defaultAction)
                        Button("Cancel") { onCancel() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(alias != nil ? .primary : .secondary)
                            .fontWeight(alias != nil ? .medium : .regular)
                        if alias != nil {
                            Text("(\(listener.command))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("• PID \(listener.pid) • \(listener.user)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            if !isEditing && hover {
                if let url = webURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(url.absoluteString)")
                }
                if alias != nil {
                    Button(action: onClear) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset alias")
                }
                Button {
                    draft = alias ?? ""
                    onStartEdit()
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Rename")
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
        .background((hover && !isEditing) ? Color.gray.opacity(0.12) : Color.clear)
        .onHover { hover = $0 }
        .onChange(of: isEditing) { editing in
            if editing { focused = true }
        }
        .onTapGesture(count: 2) {
            if !isEditing {
                draft = alias ?? ""
                onStartEdit()
            }
        }
    }
}
