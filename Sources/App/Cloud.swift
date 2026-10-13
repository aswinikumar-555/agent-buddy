// Cloud tasks: your AWS ECS services (read-only health) and Codex Cloud tasks.
// Claude Code cloud sessions (claude.ai/code) have no local or CLI listing,
// so they can't be tracked from here.
import Foundation

// MARK: - AWS ECS

struct EcsService: Identifiable, Equatable {
    var id: String { "\(cluster)/\(name)" }
    let cluster: String
    let name: String
    let desired: Int
    let running: Int
    let pending: Int
    let rollout: String   // IN_PROGRESS, COMPLETED, FAILED
    let lastEvent: String
    var stopReason: String? = nil // why its last task stopped, when it's short on tasks

    /// A cluster whose name contains one of your production environment names ("prodEnvs" in the config).
    var isProduction: Bool { ProdGuard.prodEnvs.contains { cluster.lowercased().contains($0) } }
    var deploying: Bool { rollout == "IN_PROGRESS" }
    var short: String {
        // "acme-shop-prod-core-api" in cluster "shop-prod" → "core-api": drop everything up to the cluster name.
        guard let r = name.range(of: cluster + "-") else { return name }
        let rest = name[r.upperBound...]
        return rest.isEmpty ? name : String(rest)
    }
    var isUnhealthy: Bool { rollout == "FAILED" || (running < desired && !deploying) }
    func consoleURL(region: String) -> URL? {
        URL(string: "https://\(region).console.aws.amazon.com/ecs/v2/clusters/\(cluster)/services/\(name)/health?region=\(region)")
    }
}

enum EcsMonitor {
    enum Result { case ok([EcsService], [String]), loggedOut, unavailable }

    private static func aws(_ args: [String]) -> (Int32, String) {
        guard let bin = AwsLogin.bin else { return (-1, "") }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["AWS_PAGER"] = ""
        return runProcess(bin, args + ["--output", "json"], env: env)
    }

    private static var reasonCache: [String: (reason: String?, at: Date)] = [:]

    /// Why a service's most recent task stopped (cached 10 min; read-only).
    private static func stopReason(cluster: String, service: String, region: String) -> String? {
        let key = "\(cluster)/\(service)"
        if let c = reasonCache[key], Date().timeIntervalSince(c.at) < 600 { return c.reason }
        var reason: String?
        let (st, out) = aws(["ecs", "list-tasks", "--region", region, "--cluster", cluster, "--service-name", service,
                             "--desired-status", "STOPPED", "--max-items", "1", "--query", "taskArns[0]"])
        if st == 0, let arn = (try? JSONSerialization.jsonObject(with: Data(out.utf8), options: .fragmentsAllowed)) as? String {
            let (st2, out2) = aws(["ecs", "describe-tasks", "--region", region, "--cluster", cluster, "--tasks", arn,
                                   "--query", "tasks[0].[stoppedReason, containers[0].reason]"])
            if st2 == 0, let parts = try? JSONSerialization.jsonObject(with: Data(out2.utf8)) as? [Any] {
                reason = parts.compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
                if reason?.isEmpty == true { reason = nil }
            }
        }
        reasonCache[key] = (reason.map { shorten($0) }, Date())
        return reasonCache[key]?.reason
    }

    /// Long ECS errors → the useful part (drops registry URLs and digests).
    private static func shorten(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/", with: "",
                                       options: .regularExpression)
        t = t.replacingOccurrences(of: "@sha256:[0-9a-f]{64}", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: ":([0-9a-f]{12})[0-9a-f]{28}", with: ":$1", options: .regularExpression)
        if let r = t.range(of: "failed to resolve ref "), let colon = t[r.upperBound...].range(of: ": ") {
            t = t.replacingCharacters(in: r.lowerBound..<colon.upperBound, with: "")
        }
        return oneLine(t, max: 220)
    }

    /// Read-only: list-services + describe-services for each cluster.
    static func poll(clusters: [String], region: String) -> Result {
        guard AwsLogin.bin != nil else { return .unavailable }
        var services: [EcsService] = []
        var problems: [String] = []
        for cluster in clusters {
            let (st, out) = aws(["ecs", "list-services", "--region", region, "--cluster", cluster, "--query", "serviceArns"])
            if st != 0 {
                let lower = out.lowercased()
                if lower.contains("expired") || lower.contains("aws login") || lower.contains("credentials") { return .loggedOut }
                problems.append("\(cluster): \(oneLine(out, max: 100))")
                continue
            }
            let arns = (try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String]) ?? []
            let names = arns.compactMap { $0.split(separator: "/").last.map(String.init) }
            for chunk in stride(from: 0, to: names.count, by: 10).map({ Array(names[$0..<min($0 + 10, names.count)]) }) {
                let query = "services[].{name:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount,"
                    + "rollout:deployments[0].rolloutState,event:events[0].message}"
                let (st2, out2) = aws(["ecs", "describe-services", "--region", region, "--cluster", cluster,
                                       "--services"] + chunk + ["--query", query])
                guard st2 == 0, let rows = try? JSONSerialization.jsonObject(with: Data(out2.utf8)) as? [[String: Any]] else {
                    problems.append("\(cluster): couldn't describe services")
                    continue
                }
                services += rows.map { r in
                    EcsService(cluster: cluster, name: r["name"] as? String ?? "?",
                               desired: r["desired"] as? Int ?? 0, running: r["running"] as? Int ?? 0,
                               pending: r["pending"] as? Int ?? 0, rollout: r["rollout"] as? String ?? "",
                               lastEvent: oneLine(r["event"] as? String ?? "", max: 200))
                }
            }
        }
        for i in services.indices where services[i].running < services[i].desired {
            services[i].stopReason = stopReason(cluster: services[i].cluster, service: services[i].name, region: region)
        }
        services.sort { ($0.cluster, $0.name) < ($1.cluster, $1.name) }
        return .ok(services, problems)
    }
}

// MARK: - Codex Cloud

struct CodexCloudTask: Identifiable, Equatable {
    enum State { case working, done, failed, other }
    let id: String
    let title: String
    let status: String
    let url: String?
    let updated: Date?

    var state: State {
        let s = status.lowercased()
        if ["pending", "running", "progress", "queued", "working"].contains(where: s.contains) { return .working }
        if ["error", "fail", "cancel"].contains(where: s.contains) { return .failed }
        if ["ready", "complete", "done", "success", "applied", "finished"].contains(where: s.contains) { return .done }
        return .other
    }
}

enum CodexCloud {
    enum Result { case ok([CodexCloudTask]), notSignedIn, unavailable(String) }

    static let bin = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }

    static func poll() -> Result {
        guard let bin else { return .unavailable("Codex isn't installed") }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let (st, out) = runProcess(bin, ["cloud", "list", "--json", "--limit", "20"], env: env)
        if out.lowercased().contains("not signed in") || out.contains("codex login") { return .notSignedIn }
        guard st == 0, let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) else {
            return .unavailable(oneLine(out, max: 120))
        }
        // Accept a bare array or an object wrapping it.
        let rows: [[String: Any]] = (json as? [[String: Any]])
            ?? ["tasks", "items", "data", "results"].lazy.compactMap { (json as? [String: Any])?[$0] as? [[String: Any]] }.first
            ?? []
        let iso = ISO8601DateFormatter()
        return .ok(rows.map { r in
            let status: String = (r["status"] as? String) ?? ((r["status"] as? [String: Any])?["type"] as? String)
                ?? (r["state"] as? String) ?? ""
            let updatedRaw = r["updated_at"] ?? r["updatedAt"]
            let updated = (updatedRaw as? String).flatMap { iso.date(from: $0) }
                ?? (updatedRaw as? Double).map { Date(timeIntervalSince1970: $0 > 1e12 ? $0 / 1000 : $0) }
            return CodexCloudTask(
                id: (r["id"] as? String) ?? (r["task_id"] as? String) ?? UUID().uuidString,
                title: oneLine((r["title"] as? String) ?? (r["name"] as? String) ?? (r["prompt"] as? String) ?? "Codex task", max: 90),
                status: status,
                url: (r["url"] as? String) ?? (r["html_url"] as? String),
                updated: updated)
        })
    }

    /// Opens Terminal and runs `codex login` (sign in with ChatGPT).
    static func openLogin() {
        let script = ["tell application \"Terminal\"", "activate", "do script \"codex login\"", "end tell"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] }, env: nil)
    }
}
