// Google Cloud: whether your gcloud login is still valid, and Cloud Run service
// health. Read-only (`gcloud auth print-access-token`, `gcloud run services list`),
// and only for the projects you list as "gcpProjects" in the config.
import Foundation

struct GcpProject: Codable, Equatable {
    var project: String
    var region: String?   // nil = every region
}

struct CloudRunService: Identifiable, Equatable {
    var id: String { "\(project)/\(region)/\(name)" }
    let project: String
    let region: String
    let name: String
    let ready: String      // "True", "False" or "Unknown"
    let message: String    // why it isn't ready
    let url: String
    let deploying: Bool    // a new revision is rolling out

    var isUnhealthy: Bool { ready == "False" }
    var isProduction: Bool { ProdGuard.prodEnvs.contains { project.lowercased().contains($0) || name.lowercased().contains($0) } }
    var consoleURL: URL? {
        URL(string: "https://console.cloud.google.com/run/detail/\(region)/\(name)/metrics?project=\(project)")
    }
}

enum Gcp {
    static let bin = ["/opt/homebrew/bin/gcloud", "/usr/local/bin/gcloud",
                      "/opt/homebrew/share/google-cloud-sdk/bin/gcloud", "/usr/local/share/google-cloud-sdk/bin/gcloud",
                      NSHomeDirectory() + "/google-cloud-sdk/bin/gcloud"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// gcloud is installed (or we're drawing the README images, which show sample Cloud Run data).
    static var available: Bool { bin != nil || DocsRenderer.active }

    private static func run(_ args: [String]) -> (Int32, String) {
        guard let bin else { return (-1, "") }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["CLOUDSDK_CORE_DISABLE_PROMPTS"] = "1"   // never wait for input
        return runProcess(bin, args, env: env)
    }

    /// Same states as the AWS light: .active(account), .loggedOut(reason), .unknown (offline / not installed).
    static func loginStatus() -> AwsStatus {
        guard bin != nil else { return .unknown }
        let (st, out) = run(["auth", "print-access-token", "--quiet"])
        if st == 0, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let (_, account) = run(["config", "get-value", "account", "--quiet"])
            let who = account.trimmingCharacters(in: .whitespacesAndNewlines)
            return .active(who.isEmpty ? "logged in" : who)
        }
        let lower = out.lowercased()
        if ["could not resolve", "connection", "timed out", "network"].contains(where: lower.contains) { return .unknown }
        let reason = out.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { oneLine(String($0), max: 140) } ?? "Not logged in"
        return .loggedOut(reason)
    }

    enum Result { case ok([CloudRunService], [String]), loggedOut, unavailable }

    static func cloudRun(_ projects: [GcpProject]) -> Result {
        guard bin != nil else { return .unavailable }
        var services: [CloudRunService] = []
        var problems: [String] = []
        for p in projects {
            var args = ["run", "services", "list", "--project", p.project, "--format", "json", "--quiet"]
            if let r = p.region { args += ["--region", r] }
            let (st, out) = run(args)
            if st != 0 {
                let lower = out.lowercased()
                if lower.contains("reauthentication") || lower.contains("gcloud auth login") || lower.contains("credentials") {
                    return .loggedOut
                }
                problems.append("\(p.project): \(oneLine(out, max: 100))")
                continue
            }
            services += parse(out, project: p.project)
        }
        services.sort { ($0.project, $0.region, $0.name) < ($1.project, $1.region, $1.name) }
        return .ok(services, problems)
    }

    /// `gcloud run services list --format json` (Knative Service objects).
    static func parse(_ json: String, project: String) -> [CloudRunService] {
        guard let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return [] }
        return items.map { s in
            let meta = s["metadata"] as? [String: Any] ?? [:]
            let labels = meta["labels"] as? [String: Any] ?? [:]
            let status = s["status"] as? [String: Any] ?? [:]
            let conditions = status["conditions"] as? [[String: Any]] ?? []
            let readyCond = conditions.first { $0["type"] as? String == "Ready" }
            let ready = readyCond?["status"] as? String ?? "Unknown"
            let created = status["latestCreatedRevisionName"] as? String
            let readyRev = status["latestReadyRevisionName"] as? String
            return CloudRunService(
                project: project,
                region: labels["cloud.googleapis.com/location"] as? String ?? "",
                name: meta["name"] as? String ?? "?",
                ready: ready,
                message: oneLine((readyCond?["message"] as? String) ?? "", max: 200),
                url: status["url"] as? String ?? "",
                deploying: ready == "Unknown" || (created != nil && created != readyRev && ready != "False"))
        }
    }

    /// Opens Terminal and runs `gcloud auth login` (it opens your browser).
    static func openLogin() {
        let script = ["tell application \"Terminal\"", "activate", "do script \"gcloud auth login\"", "end tell"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] }, env: nil)
    }
}
