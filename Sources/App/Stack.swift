// Local dev stack monitor: watches the services `make <env>` / `make debug`
// starts in each checkout (a project and its git worktrees), using the repo's own
// conventions: scripts/dev/ports.sh (slot-based ports), .dev-pids/<svc>.pid,
// .dev-logs/<svc>.log and .dev-logs/current-env. Also shows open RDS tunnels.
import AppKit
import Foundation

enum ServiceStatus: Equatable {
    case up, starting, down
    case notListening // process alive but its port isn't open
}

struct StackService: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let port: Int?
    var status: ServiceStatus
    var portOwner: String? // "python (pid 123)" when the port is held by someone else
    var logPath: String
    var error: String? = nil // last error line from its log, when it's down
}

struct DevStack: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    let slot: String
    let env: String
    var services: [StackService]

    var downCount: Int { services.filter { $0.status == .down || $0.status == .notListening }.count }
}

struct Tunnel: Identifiable, Equatable {
    var id: Int { port }
    let env: String
    let port: Int
    var isProduction: Bool { ProdGuard.prodEnvs.contains(env.lowercased()) }
}

final class StackMonitor {
    /// Local ports of database tunnels to watch ("dbTunnels" in the config), e.g. stage 5437, prod 5439.
    var tunnelPorts: [(String, Int)] = []
    /// Service (pidfile name) → the ports.sh variable holding its port.
    static let portVars: [String: String] = [
        "backend": "PORT_BACKEND", "euler-api": "PORT_EULER_V2", "tutor-api": "PORT_TUTOR",
        "platform-node": "PORT_PLATFORM", "frontend": "PORT_VITE", "flower": "PORT_FLOWER",
        "live-tutorial": "PORT_LIVE",
    ]
    static let order = ["frontend", "backend", "euler-api", "tutor-api", "platform-node",
                        "celery-default", "celery-heavy", "flower", "live-tutorial", "redis", "postgres", "mongo"]

    private let roots: [String]
    private var portCache: [String: (ports: [String: Int], at: Date)] = [:]
    private var stackDirs: [String] = []
    private var lastDiscover = Date.distantPast

    init(roots: [String]) {
        self.roots = roots.map { NSString(string: $0).expandingTildeInPath }
    }

    /// One snapshot of every active stack (one with services started) plus open tunnels.
    func poll() -> ([DevStack], [Tunnel]) {
        if Date().timeIntervalSince(lastDiscover) > 60 { discover() }
        let listening = listeningPorts()
        var stacks: [DevStack] = []
        for dir in stackDirs {
            if let s = snapshot(dir, listening) { stacks.append(s) }
        }
        let tunnels = tunnelPorts.compactMap { env, port in
            listening[port] != nil ? Tunnel(env: env, port: port) : nil
        }
        return (stacks, tunnels)
    }

    private func discover() {
        lastDiscover = Date()
        let fm = FileManager.default
        var found: [String] = []
        for root in roots {
            let candidates = [root] + ((try? fm.contentsOfDirectory(atPath: root)) ?? []).map { "\(root)/\($0)" }
            for dir in candidates where fm.fileExists(atPath: "\(dir)/scripts/dev/ports.sh") {
                found.append(dir)
            }
        }
        stackDirs = found
    }

    private func snapshot(_ dir: String, _ listening: [Int: String]) -> DevStack? {
        let fm = FileManager.default
        let pidDir = "\(dir)/.dev-pids"
        let pidFiles = ((try? fm.contentsOfDirectory(atPath: pidDir)) ?? []).filter { $0.hasSuffix(".pid") }
        guard !pidFiles.isEmpty else { return nil } // nothing started in this checkout

        let ports = portsFor(dir)
        let env = (try? String(contentsOfFile: "\(dir)/.dev-logs/current-env", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        var services: [StackService] = []

        for file in pidFiles {
            let name = String(file.dropLast(4))
            let path = "\(pidDir)/\(file)"
            let pid = Int32((try? String(contentsOfFile: path, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            let alive = pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
            let started = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            let port = StackMonitor.portVars[name].flatMap { ports[$0] }
            var status: ServiceStatus
            var owner: String?
            if alive {
                if let port, listening[port] == nil {
                    status = Date().timeIntervalSince(started) < 120 ? .starting : .notListening
                } else {
                    status = .up
                }
            } else {
                status = .down
                if let port, let who = listening[port] { owner = who }
            }
            let log = "\(dir)/.dev-logs/\(name).log"
            let error = status == .down || status == .notListening ? StackMonitor.lastError(in: log) : nil
            services.append(StackService(name: name, port: port, status: status, portOwner: owner,
                                         logPath: log, error: error))
        }

        // Docker infra: redis always; postgres + mongo only when running in local mode.
        // Host ports come from docker-compose.override.yml (in local mode infra-up.sh
        // rewrites it from the local secrets), falling back to the slot formula.
        let compose = composePorts("\(dir)/docker-compose.override.yml")
        var infra: [(String, String, String)] = [("redis", "redis", "PORT_REDIS")]
        if env == "local" { infra += [("postgres", "postgres", "PORT_PG"), ("mongo", "mongodb", "PORT_MONGO")] }
        for (name, composeName, key) in infra {
            guard let port = compose[composeName] ?? ports[key] else { continue }
            services.append(StackService(name: name, port: port, status: listening[port] != nil ? .up : .down,
                                         portOwner: nil, logPath: ""))
        }

        services.sort {
            (StackMonitor.order.firstIndex(of: $0.name) ?? 99) < (StackMonitor.order.firstIndex(of: $1.name) ?? 99)
        }
        return DevStack(path: dir, name: (dir as NSString).lastPathComponent, slot: String(ports["SLOT"] ?? 0),
                        env: env, services: services)
    }

    /// Host ports per compose service, from lines like `- "6399:6379"` under `ports:`.
    private func composePorts(_ path: String) -> [String: Int] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [String: Int] = [:]
        var service: String?
        for line in text.split(separator: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 2, trimmed.hasSuffix(":"), !trimmed.hasPrefix("#") {
                service = String(trimmed.dropLast())
            } else if let svc = service, result[svc] == nil, trimmed.hasPrefix("- ") {
                let mapping = trimmed.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                let parts = mapping.split(separator: ":")
                // "6399:6379" or "127.0.0.1:27038:27017": host port is the second-to-last part.
                if parts.count >= 2, let host = Int(parts[parts.count - 2]) { result[svc] = host }
            }
        }
        return result
    }

    /// The checkout's port map, straight from its own scripts/dev/ports.sh.
    private func portsFor(_ dir: String) -> [String: Int] {
        if let c = portCache[dir], Date().timeIntervalSince(c.at) < 120 { return c.ports }
        let vars = ["SLOT", "PORT_VITE", "PORT_BACKEND", "PORT_EULER_V2", "PORT_FLOWER", "PORT_TUTOR",
                    "PORT_PLATFORM", "PORT_LIVE", "PORT_PG", "PORT_REDIS", "PORT_MONGO"]
        let script = "cd \"$1\" && source scripts/dev/ports.sh >/dev/null 2>&1; echo " + vars.map { "$\($0)" }.joined(separator: " ")
        let (status, out) = runProcess("/bin/bash", ["-c", script, "bash", dir], env: nil)
        var ports: [String: Int] = [:]
        if status == 0 {
            let values = out.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Int($0) }
            if values.count == vars.count { for (k, v) in zip(vars, values) { ports[k] = v } }
        }
        portCache[dir] = (ports, Date())
        return ports
    }

    /// Every TCP port something is listening on → "command (pid N)".
    private func listeningPorts() -> [Int: String] {
        let (_, out) = runProcess("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"], env: nil)
        var result: [Int: String] = [:]
        var pid = "", cmd = ""
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = value
            case "c": cmd = value
            case "n":
                if let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) {
                    result[port] = "\(cmd) (pid \(pid))"
                }
            default: break
            }
        }
        return result
    }

    /// The most recent error-looking line in a service's log (reads only the tail).
    static func lastError(in path: String) -> String? {
        guard !path.isEmpty, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        let pattern = try? NSRegularExpression(pattern: "(Traceback|Error|Exception|FATAL|ERR!|EADDRINUSE|panic|Killed)")
        let ansi = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")
        for raw in text.split(separator: "\n").reversed() {
            var line = String(raw)
            if let ansi { line = ansi.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "") }
            if let pattern, pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return oneLine(line.trimmingCharacters(in: .whitespaces), max: 220)
            }
        }
        return nil
    }

    /// The last lines of a log, for handing to an agent.
    static func tail(of path: String, lines: Int = 40) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > 16_384 ? size - 16_384 : 0)
        let text = String(data: (try? fh.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    /// Opens a Terminal window in the checkout and runs `make debug` there, so it
    /// gets your normal shell environment (PATH, AWS login, node, …).
    static func restart(_ stack: DevStack) {
        let script = ["on run argv", "tell application \"Terminal\"", "activate",
                      "do script (\"cd \" & quoted form of (item 1 of argv) & \" && make debug\")",
                      "end tell", "end run"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] } + [stack.path], env: nil)
    }
}
