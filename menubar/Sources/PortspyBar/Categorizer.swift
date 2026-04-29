import Foundation

enum PortCategory: String, CaseIterable, Identifiable {
    case web
    case system
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .web: return "Web"
        case .system: return "System"
        case .apple: return "Apple"
        }
    }

    var icon: String {
        switch self {
        case .web: return "globe"
        case .system: return "terminal"
        case .apple: return "applelogo"
        }
    }
}

enum Categorizer {
    private static let webCommands: Set<String> = [
        "httpd", "nginx", "caddy", "traefik", "haproxy",
        "node", "next", "vite", "esbuild", "webpack", "deno", "bun",
        "php", "php-fpm", "symfony", "frankenphp",
        "python", "python3", "uvicorn", "gunicorn", "hypercorn", "flask",
        "ruby", "puma", "rails", "unicorn",
        "java", "tomcat", "jetty",
        "go", "gow",
        "dotnet", "kestrel"
    ]

    private static let webPorts: Set<Int> = [
        80, 81, 88, 443, 1313, 3000, 3001, 3030, 4000, 4200, 4321,
        5000, 5001, 5173, 5500, 5555, 6006, 7000, 7860,
        8000, 8001, 8002, 8008, 8010, 8080, 8081, 8082, 8088, 8443,
        8888, 9000, 9001, 9090, 9200
    ]

    private static let appleCommands: Set<String> = [
        "mDNSResponder", "rapportd", "sharingd", "ControlCe", "controlce",
        "nsurlsessiond", "identityservicesd", "AirPlayXPC", "AirPlay",
        "remoted", "rapportd", "secd", "trustd", "nehelper", "useractivityd",
        "homed", "siriknowledged", "searchpartyd", "screensharingd",
        "ScreenSharingD", "SafariBookmarksSyncAgent", "cloudd", "bird",
        "appleeventsd", "configd", "syslogd", "launchd", "loginwindow",
        "WindowServer", "coreaudiod", "Spotlight", "ScreenContinuity",
        "UserEventAgent", "AirDrop", "fmfd", "akd"
    ]

    private static let appleUserPrefixes = ["_"]

    static func category(for listener: PortListener) -> PortCategory {
        let command = listener.command
        let lowerCommand = command.lowercased()

        if isApple(command: command, user: listener.user) {
            return .apple
        }
        if webCommands.contains(lowerCommand) || webPorts.contains(listener.port) {
            return .web
        }
        return .system
    }

    static func isApple(command: String, user: String) -> Bool {
        if appleCommands.contains(command) { return true }
        if appleUserPrefixes.contains(where: { user.hasPrefix($0) }) { return true }
        return false
    }

    static func webURL(for listener: PortListener) -> URL? {
        let host: String
        switch listener.address {
        case "0.0.0.0", "::", "*", "":
            host = "localhost"
        case "::1":
            host = "[::1]"
        default:
            host = listener.address
        }
        let scheme = (listener.port == 443 || listener.port % 1000 == 443) ? "https" : "http"
        return URL(string: "\(scheme)://\(host):\(listener.port)")
    }
}
