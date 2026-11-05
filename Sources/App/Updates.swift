// New versions: a look at the latest GitHub release a few times a day. One small
// request to api.github.com, no account; nothing about you is sent.
import Foundation

struct AppUpdate: Equatable {
    let version: String
    let url: URL
}

enum Updates {
    static let repo = "aswinikumar-555/agent-buddy"

    /// The latest release, if it's newer than `current`. Calls back on the main queue.
    static func check(current: String, _ done: @escaping (AppUpdate?) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var found: AppUpdate?
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = obj["tag_name"] as? String, obj["draft"] as? Bool != true, obj["prerelease"] as? Bool != true,
               let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if isNewer(version, than: current) { found = AppUpdate(version: version, url: page) }
            }
            DispatchQueue.main.async { done(found) }
        }.resume()
    }

    /// "1.10.0" is newer than "1.9.2"; anything that isn't a version number never is.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let parse = { (s: String) -> [Int]? in
            let parts = s.split(separator: ".").map { Int($0) }
            return parts.isEmpty || parts.contains(nil) ? nil : parts.map { $0! }
        }
        guard let x = parse(a), let y = parse(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
