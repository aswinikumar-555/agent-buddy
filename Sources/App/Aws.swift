// AWS CLI login status: asks AWS "who am I?" (`aws sts get-caller-identity`,
// read-only and free) every couple of minutes. That's the only reliable check
// for `aws login` sessions: the cached token says "expired" while the CLI
// quietly refreshes it.
import Foundation

enum AwsStatus: Equatable {
    case unknown              // not checked yet, aws not installed, or offline
    case active(String)       // the identity, e.g. "you@example.com"
    case loggedOut(String)    // short reason from the CLI

    var isLoggedOut: Bool { if case .loggedOut = self { return true } else { return false } }
}

enum AwsLogin {
    static let bin = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Runs the identity check (blocking; call off the main thread).
    static func check() -> AwsStatus {
        guard let bin else { return .unknown }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["AWS_PAGER"] = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["sts", "get-caller-identity", "--output", "json"]
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return .unknown }
        // Never hang the checker on a stuck network call.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        let out = String(data: data, encoding: .utf8) ?? ""

        if p.terminationStatus == 0,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arn = obj["Arn"] as? String {
            return .active(arn.split(separator: "/").last.map(String.init) ?? arn)
        }
        let lower = out.lowercased()
        let offline = ["could not connect", "connect timeout", "name resolution", "network", "timed out", "endpoint url"]
        if p.terminationReason == .uncaughtSignal || offline.contains(where: lower.contains) { return .unknown }
        let reason = out.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { oneLine(String($0), max: 140) } ?? "Not logged in"
        return .loggedOut(reason)
    }

    /// Opens Terminal and runs `aws login` (it opens your browser to sign in).
    static func openLogin() {
        let script = ["tell application \"Terminal\"", "activate", "do script \"aws login\"", "end tell"]
        _ = runProcess("/usr/bin/osascript", script.flatMap { ["-e", $0] }, env: nil)
    }
}
