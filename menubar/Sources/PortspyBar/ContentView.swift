import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: PortMonitor
    @ObservedObject var aliases: AliasStore
    @ObservedObject var toast: ToastCenter
    let onOpenURL: (URL) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var editingId: String?
    @State private var category: PortCategory = .web

    var allGroups: [PortGroup] {
        monitor.listeners.grouped()
    }

    var matchedGroups: [PortGroup] {
        guard !query.isEmpty else { return allGroups }
        let q = query.lowercased()
        return allGroups.filter { g in
            let alias = aliases.alias(for: g.representative)?.lowercased() ?? ""
            let path = (g.cwd ?? "").lowercased()
            return String(g.port).contains(q)
                || g.command.lowercased().contains(q)
                || g.user.lowercased().contains(q)
                || g.addressLabel.lowercased().contains(q)
                || alias.contains(q)
                || path.contains(q)
        }
    }

    var grouped: [PortCategory: [PortGroup]] {
        Dictionary(grouping: matchedGroups) { Categorizer.category(for: $0.representative) }
    }

    var visible: [PortGroup] {
        grouped[category] ?? []
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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
            ToastView(toast: toast)
                .animation(.easeInOut(duration: 0.2), value: toast.message)
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter port, process, alias, user, path", text: $query)
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
                    Text(allGroups.isEmpty
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
                        ForEach(visible) { group in
                            PortRow(
                                group: group,
                                alias: aliases.alias(for: group.representative),
                                isEditing: editingId == group.id,
                                onStartEdit: { editingId = group.id },
                                onCommit: { newValue in
                                    aliases.setAlias(newValue, for: group.representative)
                                    editingId = nil
                                    if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                        toast.show("Renamed to \(newValue)", icon: "pencil.circle.fill")
                                    }
                                },
                                onCancel: { editingId = nil },
                                onClear: {
                                    aliases.clear(for: group.representative)
                                    editingId = nil
                                    toast.show("Alias cleared", icon: "arrow.uturn.backward.circle.fill")
                                },
                                onKill: {
                                    Task {
                                        let outcome = await monitor.kill(group)
                                        handleKillOutcome(outcome, for: group)
                                    }
                                },
                                onOpenURL: onOpenURL
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
    }

    private func handleKillOutcome(_ outcome: KillOutcome, for group: PortGroup) {
        let label = group.workerCount > 1 ? "\(group.workerCount) PIDs" : "PID \(group.pids.first ?? 0)"
        switch outcome {
        case .killed:
            toast.show("Killed \(label)", icon: "xmark.circle.fill")
        case .escalated:
            toast.show("Killed \(label) (admin)", icon: "lock.open.fill")
        case .respawned(let hint):
            if let hint {
                let cmd = "brew services stop \(hint)"
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(cmd, forType: .string)
                toast.show("Respawned. Copied: \(cmd)", icon: "arrow.clockwise.circle.fill", duration: 4)
            } else {
                toast.show("Process respawned (managed by launchd)", icon: "arrow.clockwise.circle.fill", duration: 4)
            }
        case .failed(let msg):
            toast.show("Kill failed: \(msg)", icon: "exclamationmark.triangle.fill", duration: 4)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(allGroups.count) services")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { monitor.refresh() }
                .buttonStyle(.borderless)
            Button("Close") { onClose() }
                .buttonStyle(.borderless)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct PortRow: View {
    let group: PortGroup
    let alias: String?
    let isEditing: Bool
    let onStartEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onClear: () -> Void
    let onKill: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var draft: String = ""
    @State private var hover = false
    @State private var expanded = false
    @FocusState private var focused: Bool

    private var displayName: String { alias ?? group.command }
    private var category: PortCategory { Categorizer.category(for: group.representative) }
    private var webURL: URL? {
        category == .web ? Categorizer.webURL(for: group.representative) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if let path = group.prettyPath, !isEditing {
                pathRow(path)
            }
            if expanded && group.workerCount > 1 {
                pidsList
            }
        }
        .background((hover && !isEditing) ? Color.gray.opacity(0.12) : Color.clear)
        .onHover { hover = $0 }
    }

    private func pathRow(_ path: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(group.port)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Text(group.proto.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                    Text(group.addressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isEditing {
                    HStack(spacing: 6) {
                        TextField(group.command, text: $draft)
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
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(alias != nil ? .primary : .secondary)
                            .fontWeight(alias != nil ? .medium : .regular)
                        if alias != nil {
                            Text("(\(group.command))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if group.workerCount > 1 {
                            Button {
                                expanded.toggle()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text("\(group.workerCount) workers")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("PID \(group.pids.first ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("• \(group.user)")
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
                        onOpenURL(url)
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
                .help(group.workerCount > 1
                      ? "SIGKILL all \(group.workerCount) PIDs"
                      : "SIGKILL PID \(group.pids.first ?? 0)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onChange(of: isEditing) { editing in
            if editing { focused = true }
        }
    }

    private var pidsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.pids, id: \.self) { pid in
                Text("PID \(pid)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}
