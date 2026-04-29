import Combine
import Foundation

@MainActor
final class AliasStore: ObservableObject {
    @Published private(set) var aliases: [String: String] = [:]

    private let key = "com.czepitech.portspybar.aliases"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.dictionary(forKey: key) as? [String: String] {
            self.aliases = raw
        }
    }

    func key(for listener: PortListener) -> String {
        "\(listener.command)@\(listener.port)"
    }

    func alias(for listener: PortListener) -> String? {
        aliases[key(for: listener)]
    }

    func setAlias(_ alias: String, for listener: PortListener) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key(for: listener)
        if trimmed.isEmpty {
            aliases.removeValue(forKey: k)
        } else {
            aliases[k] = trimmed
        }
        defaults.set(aliases, forKey: key)
    }

    func clear(for listener: PortListener) {
        setAlias("", for: listener)
    }
}
