import AppKit
import Combine
import Darwin
import Foundation

struct PortListener: Identifiable, Hashable {
    let proto: String
    let port: Int
    let address: String
    let pid: Int
    let user: String
    let command: String
    let cwd: String?

    var id: String { "\(pid)-\(proto)-\(port)-\(address)" }
}

struct PortGroup: Identifiable, Hashable {
    let proto: String
    let port: Int
    let command: String
    let user: String
    let addresses: [String]
    let pids: [Int]
    let cwd: String?

    var id: String { "\(proto)-\(port)-\(command)" }
    var representative: PortListener {
        PortListener(
            proto: proto,
            port: port,
            address: addresses.first ?? "",
            pid: pids.first ?? 0,
            user: user,
            command: command,
            cwd: cwd
        )
    }
    var workerCount: Int { pids.count }
    var addressLabel: String {
        let unique = Array(Set(addresses)).sorted()
        return unique.joined(separator: ", ")
    }
    var prettyPath: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let home = NSHomeDirectory()
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }
}

extension Array where Element == PortListener {
    func grouped() -> [PortGroup] {
        let dict = Dictionary(grouping: self) { l in "\(l.proto)-\(l.port)-\(l.command)" }
        return dict.values.map { items -> PortGroup in
            let first = items[0]
            let cwds = items.compactMap(\.cwd).filter { !$0.isEmpty }
            let groupCwd: String? = {
                let unique = Set(cwds)
                if unique.count == 1 { return unique.first }
                return cwds.first
            }()
            return PortGroup(
                proto: first.proto,
                port: first.port,
                command: first.command,
                user: first.user,
                addresses: items.map(\.address),
                pids: items.map(\.pid).sorted(),
                cwd: groupCwd
            )
        }
        .sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            return $0.command < $1.command
        }
    }
}

enum KillOutcome {
    case killed
    case escalated
    case respawned(hint: String?)
    case failed(String)
}

@MainActor
final class PortMonitor: ObservableObject {
    @Published var listeners: [PortListener] = []
    @Published var isRefreshing = false
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { await self?.refreshAsync() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        Task { await refreshAsync() }
    }

    func refreshAsync() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            listeners = try await Self.queryListeners()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func kill(_ group: PortGroup) async -> KillOutcome {
        var needsAdmin = false
        var firstFailure: String?
        for pid in group.pids {
            let result = Darwin.kill(pid_t(pid), SIGKILL)
            if result != 0 {
                let err = errno
                if err == EPERM {
                    needsAdmin = true
                } else if firstFailure == nil {
                    firstFailure = String(cString: strerror(err))
                }
            }
        }
        if needsAdmin {
            return await killWithAdmin(group)
        }
        if let firstFailure {
            return .failed(firstFailure)
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await refreshAsync()
        let respawned = listeners.contains { l in
            l.port == group.port && l.command == group.command
        }
        if respawned {
            return .respawned(hint: Self.brewServiceHint(for: group.command))
        }
        return .killed
    }

    private func killWithAdmin(_ group: PortGroup) async -> KillOutcome {
        let pids = group.pids.map(String.init).joined(separator: " ")
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = [
                    "-e",
                    "do shell script \"kill -9 \(pids)\" with administrator privileges"
                ]
                let errPipe = Pipe()
                task.standardError = errPipe
                task.standardOutput = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    if task.terminationStatus == 0 {
                        cont.resume(returning: .escalated)
                    } else {
                        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let raw = String(data: data, encoding: .utf8) ?? ""
                        let msg = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        cont.resume(returning: .failed(msg.isEmpty ? "admin auth declined" : msg))
                    }
                } catch {
                    cont.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    static func brewServiceHint(for command: String) -> String? {
        let map: [String: String] = [
            "mysqld": "mysql",
            "mariadbd": "mariadb",
            "mongod": "mongodb-community",
            "redis-server": "redis",
            "postgres": "postgresql",
            "httpd": "httpd",
            "nginx": "nginx",
            "php-fpm": "php",
            "memcached": "memcached",
            "elasticsearch": "elasticsearch",
            "rabbitmq-server": "rabbitmq",
            "ollama": "ollama"
        ]
        return map[command]
    }

    static func queryListeners() async throws -> [PortListener] {
        let raw = try await runLsofPorts()
        let pids = Array(Set(raw.map(\.pid)))
        let cwds = (try? await runLsofCWDs(pids: pids)) ?? [:]
        return raw.map { l in
            PortListener(
                proto: l.proto,
                port: l.port,
                address: l.address,
                pid: l.pid,
                user: l.user,
                command: l.command,
                cwd: cwds[l.pid]
            )
        }
        .sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            return $0.command < $1.command
        }
    }

    static func runLsofPorts() async throws -> [PortListener] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/usr/sbin/lsof"
                task.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pcunPL"]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(returning: parseLsof(output))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static func runLsofCWDs(pids: [Int]) async throws -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let pidArg = pids.map(String.init).joined(separator: ",")
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/usr/sbin/lsof"
                task.arguments = ["-p", pidArg, "-a", "-d", "cwd", "-F", "pn"]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()
                do {
                    try task.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(returning: parseCWDs(output))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    nonisolated static func parseCWDs(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var pid = 0
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())
            switch first {
            case "p":
                pid = Int(value) ?? 0
            case "n":
                if pid != 0 && !value.isEmpty {
                    result[pid] = value
                }
            default:
                break
            }
        }
        return result
    }

    nonisolated static func parseLsof(_ output: String) -> [PortListener] {
        var result: [PortListener] = []
        var pid = 0
        var command = ""
        var user = ""
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())
            switch first {
            case "p":
                pid = Int(value) ?? 0
            case "c":
                command = value
            case "u":
                user = resolveUser(value)
            case "n":
                if let parsed = parseAddrPort(value) {
                    result.append(PortListener(
                        proto: "tcp",
                        port: parsed.port,
                        address: parsed.addr,
                        pid: pid,
                        user: user,
                        command: command,
                        cwd: nil
                    ))
                }
            default:
                break
            }
        }
        return result
    }

    nonisolated static func parseAddrPort(_ s: String) -> (addr: String, port: Int)? {
        var trimmed = s
        if let arrow = trimmed.range(of: "->") {
            trimmed = String(trimmed[..<arrow.lowerBound])
        }
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        var addr = String(trimmed[..<colon])
        let portString = String(trimmed[trimmed.index(after: colon)...])
        guard let port = Int(portString) else { return nil }
        addr = addr.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        if addr == "*" { addr = "0.0.0.0" }
        return (addr, port)
    }

    nonisolated static func resolveUser(_ uid: String) -> String {
        guard let id = uid_t(uid) else { return uid }
        guard let pwd = getpwuid(id), let name = pwd.pointee.pw_name else { return uid }
        return String(cString: name)
    }
}
