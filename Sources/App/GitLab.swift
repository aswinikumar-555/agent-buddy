// GitLab: the same as GitHub, through the `glab` CLI (log in with `glab auth login`):
// your merge requests and their pipelines, review requests, deployments, MR stats,
// and claude/ branches. List projects as "gitlab": {"projects": ["group/project"]},
// plus "host" for a self-hosted GitLab. Read-only.
import Foundation

struct GitLabConfig: Codable, Equatable {
    var host: String?          // default gitlab.com
    var projects: [String]
}

enum GitLab {
    static let bin = ["/opt/homebrew/bin/glab", "/usr/local/bin/glab"].first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func api(_ path: String, host: String?) -> Any? {
        guard let bin else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["NO_PROMPT"] = "1"
        let (st, out) = runProcess(bin, ["api", path] + (host.map { ["--hostname", $0] } ?? []), env: env)
        guard st == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(out.utf8))
    }

    static func encode(_ project: String) -> String { project.replacingOccurrences(of: "/", with: "%2F") }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Your username (cached).
    private static var cachedMe: String?
    static func me(host: String?) -> String? {
        if let cachedMe { return cachedMe }
        cachedMe = (api("user", host: host) as? [String: Any])?["username"] as? String
        return cachedMe
    }

    // MARK: Merge requests

    /// Your open merge requests in the listed projects, with pipeline and approval state.
    static func mine(_ c: GitLabConfig) -> [PullRequest]? {
        guard bin != nil, !c.projects.isEmpty, let rows = api("merge_requests?scope=created_by_me&state=opened&per_page=50", host: c.host) as? [[String: Any]]
        else { return nil }
        return rows.compactMap { r -> PullRequest? in
            guard let project = projectPath(r), c.projects.contains(project), let iid = r["iid"] as? Int else { return nil }
            // The list doesn't include the pipeline; one more call per MR.
            let detail = api("projects/\(encode(project))/merge_requests/\(iid)", host: c.host) as? [String: Any] ?? r
            let pipeline = (detail["head_pipeline"] as? [String: Any])?["status"] as? String ?? ""
            let checks: PullRequest.Checks = switch pipeline {
            case "failed": .failing
            case "success": .passing
            case "": .none
            case "canceled", "skipped": .none
            default: .pending
            }
            let status = detail["detailed_merge_status"] as? String ?? ""
            var pr = PullRequest(repo: project, number: iid, title: r["title"] as? String ?? "", url: r["web_url"] as? String ?? "",
                                 isDraft: r["draft"] as? Bool ?? false,
                                 review: status == "not_approved" ? "REVIEW_REQUIRED" : (detail["approved"] as? Bool == true ? "APPROVED" : ""),
                                 mergeable: status == "conflict" || status == "need_rebase" ? "CONFLICTING" : "MERGEABLE",
                                 checks: checks, headRef: r["source_branch"] as? String ?? "")
            pr.host = "gitlab"
            if checks == .failing, let pid = (detail["head_pipeline"] as? [String: Any])?["id"] as? Int {
                pr.ciError = failedJobs(project: project, pipeline: pid, host: c.host)
            }
            return pr
        }
    }

    /// "Pipeline: unit-tests, lint failed".
    private static func failedJobs(project: String, pipeline: Int, host: String?) -> String? {
        let jobs = api("projects/\(encode(project))/pipelines/\(pipeline)/jobs?scope=failed", host: host) as? [[String: Any]] ?? []
        let names = jobs.compactMap { $0["name"] as? String }
        return names.isEmpty ? nil : "Pipeline: " + names.prefix(3).joined(separator: ", ") + " failed"
    }

    /// Open merge requests where you're a reviewer.
    static func reviewRequests(_ c: GitLabConfig) -> [PullRequest] {
        guard let me = me(host: c.host),
              let rows = api("merge_requests?scope=all&state=opened&reviewer_username=\(me)&per_page=20", host: c.host) as? [[String: Any]]
        else { return [] }
        return rows.compactMap { r in
            guard let project = projectPath(r) else { return nil }
            var pr = PullRequest(repo: project, number: r["iid"] as? Int ?? 0, title: r["title"] as? String ?? "",
                                 url: r["web_url"] as? String ?? "", isDraft: r["draft"] as? Bool ?? false,
                                 review: "", mergeable: "", checks: .none)
            pr.host = "gitlab"
            return pr
        }
    }

    static func wasMerged(_ pr: PullRequest, _ c: GitLabConfig) -> Bool {
        (api("projects/\(encode(pr.repo))/merge_requests/\(pr.number)", host: c.host) as? [String: Any])?["state"] as? String == "merged"
    }

    /// "group/project" from an MR's web URL (…/group/project/-/merge_requests/12).
    private static func projectPath(_ r: [String: Any]) -> String? {
        guard let url = r["web_url"] as? String, let u = URL(string: url), let range = u.path.range(of: "/-/") else { return nil }
        return String(u.path[u.path.index(after: u.path.startIndex)..<range.lowerBound])
    }

    // MARK: Deployments

    /// Deployments from the last 6 hours, as deploy runs.
    static func deployments(_ c: GitLabConfig) -> [(String, [DeployRun])] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        let since = f.string(from: Date().addingTimeInterval(-6 * 3600))
        return c.projects.compactMap { project in
            guard let rows = api("projects/\(encode(project))/deployments?updated_after=\(since)&order_by=updated_at&sort=desc&per_page=20",
                                 host: c.host) as? [[String: Any]] else { return nil }
            let runs: [DeployRun] = rows.compactMap { d in
                guard let id = d["id"] as? Int else { return nil }
                let status = d["status"] as? String ?? ""
                let active = ["created", "running", "blocked"].contains(status)
                let env = (d["environment"] as? [String: Any])?["name"] as? String ?? "?"
                let job = d["deployable"] as? [String: Any]
                return DeployRun(id: id, repo: project, workflow: "Deploy \(env)", branch: d["ref"] as? String ?? "",
                                 status: active ? "in_progress" : "completed",
                                 conclusion: active ? "" : (status == "canceled" ? "cancelled" : status),
                                 created: date(d["created_at"]) ?? Date(), updated: date(d["updated_at"]) ?? Date(),
                                 url: job?["web_url"] as? String ?? "")
            }
            return (project, runs)
        }
    }

    // MARK: Stats

    /// Merged MRs per author, your opened and reviewed counts, and your merge times, for the last 7 days.
    static func stats(_ c: GitLabConfig) -> (me: String, merged: [String: Int], opened: Int, reviewed: Int, hours: [Double])? {
        guard bin != nil, let me = me(host: c.host) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        let sinceDate = Date().addingTimeInterval(-7 * 86_400)
        let since = f.string(from: sinceDate)
        var merged: [String: Int] = [:]
        var opened = 0, reviewed = 0
        var hours: [Double] = []
        for project in c.projects {
            let rows = api("projects/\(encode(project))/merge_requests?state=merged&updated_after=\(since)&per_page=100", host: c.host) as? [[String: Any]] ?? []
            for r in rows {
                guard let at = date(r["merged_at"]), at >= sinceDate else { continue }
                let author = (r["author"] as? [String: Any])?["username"] as? String ?? ""
                if author.isEmpty || author.hasSuffix("-bot") || author.contains("[bot]") { continue }
                merged[author, default: 0] += 1
                if author == me, let created = date(r["created_at"]) { hours.append(at.timeIntervalSince(created) / 3600) }
            }
            opened += (api("projects/\(encode(project))/merge_requests?author_username=\(me)&created_after=\(since)&per_page=100",
                           host: c.host) as? [Any])?.count ?? 0
            reviewed += (api("projects/\(encode(project))/merge_requests?reviewer_username=\(me)&updated_after=\(since)&per_page=100",
                             host: c.host) as? [[String: Any]])?
                .filter { ($0["author"] as? [String: Any])?["username"] as? String != me }.count ?? 0
        }
        return (me, merged, opened, reviewed, hours)
    }

    // MARK: Claude cloud branches

    /// claude/ branches with a commit in the last day.
    static func cloudBranches(_ c: GitLabConfig) -> [CloudBranch] {
        var out: [CloudBranch] = []
        for project in c.projects {
            let rows = api("projects/\(encode(project))/repository/branches?search=%5Eclaude/&per_page=100", host: c.host) as? [[String: Any]] ?? []
            for b in rows {
                guard let name = b["name"] as? String, let commit = b["commit"] as? [String: Any],
                      let at = date(commit["committed_date"]), Date().timeIntervalSince(at) < 86_400 else { continue }
                let mr = (api("projects/\(encode(project))/merge_requests?source_branch=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)&per_page=1",
                              host: c.host) as? [[String: Any]])?.first
                out.append(CloudBranch(repo: project, branch: name, committed: at, headline: commit["title"] as? String ?? "",
                                       prNumber: mr?["iid"] as? Int, prTitle: mr?["title"] as? String,
                                       prState: (mr?["state"] as? String)?.uppercased(),
                                       url: URL(string: (mr?["web_url"] as? String) ?? (b["web_url"] as? String ?? ""))))
            }
        }
        return out
    }
}
