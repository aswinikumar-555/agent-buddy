// Switch between Claude accounts: when one runs out of usage or credits, switch to another.
//
// Claude Code keeps its login in the Keychain ("Claude Code-credentials") and which account
// that is in ~/.claude.json ("oauthAccount"). The buddy remembers every account you log in
// to (run /login in Claude Code), each in its own Keychain item, and switching puts the
// chosen account's login back in Claude Code's place. Other parts of the Keychain item
// (MCP server logins) are left as they are. New Claude sessions use the switched account.
import Foundation

struct ClaudeAccount: Codable, Identifiable, Equatable {
    let id: String              // accountUuid:organizationUuid (one email can have a personal plan and a team plan)
    var email: String
    var org: String?
    var plan: String?           // "max", "pro", "team", …
    var savedAt: Date
    // The last plan usage seen while this account was active.
    var fiveHour: Double?
    var fiveHourResets: Date?
    var week: Double?
    var weekResets: Date?
    var usageAt: Date?

    /// The highest of its limits, ignoring windows that have reset since.
    func usedPercent(_ now: Date = Date()) -> Double? {
        var parts: [Double] = []
        if let p = fiveHour { parts.append((fiveHourResets.map { $0 < now } ?? false) ? 0 : p) }
        if let p = week { parts.append((weekResets.map { $0 < now } ?? false) ? 0 : p) }
        return parts.max()
    }
}

enum ClaudeAccounts {
    static let claudeService = "Claude Code-credentials"
    static let buddyService = "agent-buddy-claude-account"
    static var listURL = buddyDir.appendingPathComponent("claude-accounts.json")
    static var claudeJSON: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent(".claude.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }
    private static var user: String { NSUserName() }

    // MARK: The list (no secrets: those live in the Keychain)

    static func load() -> [ClaudeAccount] {
        guard let data = try? Data(contentsOf: listURL) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        return (try? d.decode([ClaudeAccount].self, from: data)) ?? []
    }

    static func save(_ list: [ClaudeAccount]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        if let data = try? e.encode(list) { try? data.write(to: listURL, options: .atomic) }
    }

    // MARK: The account Claude Code is using now

    /// ~/.claude.json's "oauthAccount", or nil when you're not logged in with a Claude account.
    static func liveAccount() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeJSON),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = obj["oauthAccount"] as? [String: Any], acct["accountUuid"] is String else { return nil }
        return acct
    }

    static func liveID() -> String? { liveAccount().flatMap(id(of:)) }

    /// A login is an account in an organization: the same email can be on a personal
    /// plan and on a team plan, with the same accountUuid.
    static func id(of acct: [String: Any]) -> String? {
        guard let user = acct["accountUuid"] as? String else { return nil }
        return user + ":" + (acct["organizationUuid"] as? String ?? "")
    }

    /// "Personal" for your own organization, otherwise the team's name.
    static func orgName(_ acct: [String: Any]) -> String? {
        guard let name = acct["organizationName"] as? String else { return nil }
        return name.hasSuffix("'s Organization") ? "Personal" : name
    }

    /// "Max", "Team", "Pro", "Enterprise" from the organization type.
    static func planName(_ acct: [String: Any], _ oauth: [String: Any]) -> String? {
        if let t = acct["organizationType"] as? String, t.hasPrefix("claude_") {
            return String(t.dropFirst(7)).capitalized
        }
        return (oauth["subscriptionType"] as? String)?.capitalized
    }

    /// Lists saved before logins were told apart by organization: re-key them.
    static func migrate(_ list: inout [ClaudeAccount]) {
        guard list.contains(where: { !$0.id.contains(":") }) else { return }
        list = list.compactMap { entry in
            guard !entry.id.contains(":") else { return entry }
            guard let text = keychainRead(service: buddyService, account: entry.id), let stored = json(text),
                  let acct = stored["oauthAccount"] as? [String: Any], let newID = id(of: acct),
                  keychainWrite(service: buddyService, account: newID, value: text) else { return nil }
            _ = runProcess("/usr/bin/security", ["delete-generic-password", "-s", buddyService, "-a", entry.id], env: nil)
            var e = ClaudeAccount(id: newID, email: entry.email, savedAt: entry.savedAt)
            e.org = orgName(acct)
            e.plan = planName(acct, stored["claudeAiOauth"] as? [String: Any] ?? [:])
            return e
        }
        var seen = Set<String>()
        list = list.filter { seen.insert($0.id).inserted }
    }

    /// Saves the current login under its account, adding it to the list if it's new.
    /// Run often, so a login Claude Code refreshed is saved before you switch away from it.
    @discardableResult
    static func remember(into list: inout [ClaudeAccount]) -> ClaudeAccount? {
        migrate(&list)
        guard let acct = liveAccount(), let id = Self.id(of: acct),
              let creds = keychainRead(service: claudeService, account: user),
              let blob = json(creds), let oauth = blob["claudeAiOauth"] as? [String: Any],
              oauth["refreshToken"] != nil else { return nil }
        let stored: [String: Any] = ["claudeAiOauth": oauth, "oauthAccount": acct]
        guard let storedData = try? JSONSerialization.data(withJSONObject: stored),
              let storedText = String(data: storedData, encoding: .utf8) else { return nil }
        if keychainRead(service: buddyService, account: id) != storedText {
            guard keychainWrite(service: buddyService, account: id, value: storedText) else { return nil }
        }
        let plan = planName(acct, oauth)
        var entry = list.first { $0.id == id }
            ?? ClaudeAccount(id: id, email: acct["emailAddress"] as? String ?? id, savedAt: Date())
        entry.email = acct["emailAddress"] as? String ?? entry.email
        entry.org = orgName(acct)
        entry.plan = plan
        if let i = list.firstIndex(where: { $0.id == id }) {
            if list[i] != entry { list[i] = entry }
        } else {
            entry.savedAt = Date()
            list.append(entry)
        }
        return entry
    }

    enum SwitchError: LocalizedError {
        case notSaved, keychain, config
        var errorDescription: String? {
            switch self {
            case .notSaved: "The buddy doesn't have this account's login any more. Run /login in Claude Code with it."
            case .keychain: "Couldn't update Claude Code's login in the Keychain."
            case .config: "Couldn't update ~/.claude.json."
            }
        }
    }

    /// Makes `id` the account Claude Code uses.
    static func switchTo(_ id: String, list: inout [ClaudeAccount]) throws {
        remember(into: &list)   // keep the latest login of the account you're leaving
        guard let text = keychainRead(service: buddyService, account: id), let stored = json(text),
              let oauth = stored["claudeAiOauth"], let acct = stored["oauthAccount"] else { throw SwitchError.notSaved }
        // Swap only the Claude login; keep the rest of the item (MCP server logins).
        var blob = keychainRead(service: claudeService, account: user).flatMap(json) ?? [:]
        let previous = blob["claudeAiOauth"]
        blob["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: blob),
              let value = String(data: data, encoding: .utf8),
              keychainWrite(service: claudeService, account: user, value: value) else { throw SwitchError.keychain }
        do {
            try setLiveAccount(acct)
        } catch {
            // Put the old login back so the Keychain and ~/.claude.json agree.
            blob["claudeAiOauth"] = previous
            if let d = try? JSONSerialization.data(withJSONObject: blob), let v = String(data: d, encoding: .utf8) {
                _ = keychainWrite(service: claudeService, account: user, value: v)
            }
            throw SwitchError.config
        }
    }

    /// Forgets an account: removes its saved login (it stays logged in if it's the current one).
    static func forget(_ id: String, list: inout [ClaudeAccount]) {
        _ = runProcess("/usr/bin/security", ["delete-generic-password", "-s", buddyService, "-a", id], env: nil)
        list.removeAll { $0.id == id }
    }

    private static func setLiveAccount(_ acct: Any) throws {
        let url = claudeJSON
        guard let data = try? Data(contentsOf: url),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SwitchError.config }
        obj["oauthAccount"] = acct
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        try out.write(to: url, options: .atomic)
    }

    // MARK: Keychain, through /usr/bin/security (Claude Code's item already trusts it)

    private static func keychainRead(service: String, account: String) -> String? {
        let (st, out) = runProcess("/usr/bin/security", ["find-generic-password", "-s", service, "-a", account, "-w"], env: nil)
        guard st == 0 else { return nil }
        let v = out.trimmingCharacters(in: .newlines)
        return v.isEmpty ? nil : v
    }

    /// Writes through `security -i` on stdin, so the secret never shows in the process list.
    private static func keychainWrite(service: String, account: String, value: String) -> Bool {
        let hex = value.utf8.map { String(format: "%02x", $0) }.joined()
        let cmd = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \(hex)\n"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["-i"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        guard (try? p.run()) != nil else { return false }
        input.fileHandleForWriting.write(cmd.data(using: .utf8)!)
        try? input.fileHandleForWriting.close()
        let errText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return p.terminationStatus == 0 && !errText.contains("error") && keychainRead(service: service, account: account) == value
    }

    private static func json(_ text: String) -> [String: Any]? {
        text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
