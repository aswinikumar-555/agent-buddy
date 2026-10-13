// Jira: tickets assigned to you, and when they're new or move. Read-only.
// Set "jira": {"site": "yourteam.atlassian.net", "email": "you@example.com"} in the
// config, and keep the API token in your Keychain:
//   security add-generic-password -s agent-buddy-jira -a you@example.com -w <token>
import Foundation

struct JiraConfig: Codable, Equatable {
    var site: String
    var email: String
    var jql: String?    // default: your open tickets, newest first
}

struct JiraIssue: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let summary: String
    let status: String
    let category: String   // "new", "indeterminate" (in progress) or "done"
    let priority: String
    let updated: Date
    let url: URL?
}

enum Jira {
    enum Result { case ok([JiraIssue]), noToken, failed(String) }

    static let keychainService = "agent-buddy-jira"

    static func token(email: String) -> String? {
        let (st, out) = runProcess("/usr/bin/security", ["find-generic-password", "-s", keychainService, "-a", email, "-w"], env: nil)
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return st == 0 && !t.isEmpty ? t : nil
    }

    static func fetch(_ c: JiraConfig) -> Result {
        guard let token = token(email: c.email) else { return .noToken }
        let site = c.site.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comps = URLComponents(string: "https://\(site)/rest/api/3/search/jql")
        comps?.queryItems = [
            .init(name: "jql", value: c.jql ?? "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"),
            .init(name: "fields", value: "summary,status,priority,updated"),
            .init(name: "maxResults", value: "30"),
        ]
        guard let url = comps?.url else { return .failed("bad Jira site") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Basic " + Data("\(c.email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let done = DispatchSemaphore(value: 0)
        var result = Result.failed("no answer")
        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { done.signal() }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, code == 200 else {
                result = .failed(error?.localizedDescription ?? (code == 401 ? "Jira says the token is wrong" : "Jira answered \(code)"))
                return
            }
            let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            let issues: [JiraIssue] = ((obj["issues"] as? [[String: Any]]) ?? []).compactMap { i in
                guard let key = i["key"] as? String else { return nil }
                let f = i["fields"] as? [String: Any] ?? [:]
                let status = f["status"] as? [String: Any] ?? [:]
                return JiraIssue(key: key, summary: f["summary"] as? String ?? "",
                                 status: status["name"] as? String ?? "",
                                 category: (status["statusCategory"] as? [String: Any])?["key"] as? String ?? "",
                                 priority: (f["priority"] as? [String: Any])?["name"] as? String ?? "",
                                 updated: iso.date(from: f["updated"] as? String ?? "") ?? Date(),
                                 url: URL(string: "https://\(site)/browse/\(key)"))
            }
            result = .ok(issues)
        }.resume()
        done.wait()
        return result
    }
}
