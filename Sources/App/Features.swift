// Every feature can be turned off: in ⚙︎ → Features, or with "features" in the
// config ({"jira": false, "walking": true, …}). A choice made in ⚙︎ wins over the config.
import Foundation

enum Feature: String, CaseIterable, Identifiable {
    // Agents
    case stuckAlerts, autoRemote, juggling, claudeUsage, backgroundAgents, cloudBranches
    // Code
    case pullRequests, prStats, deploys, devStack, logErrors, housekeeping, jira, systemStats
    // Cloud
    case sites, aws, ecs, gcp, codexCloud, prodWarning
    // Your day
    case water, breaks, dailyReminders, endOfDay, meetings, todos, timesheet, festivals, quickCapture
    // The buddy
    case idleTricks, eyesFollow, walking

    var id: String { rawValue }

    enum Group: String, CaseIterable { case agents = "Agents", code = "Code", cloud = "Cloud", day = "Your day", buddy = "The buddy" }

    var group: Group {
        switch self {
        case .stuckAlerts, .autoRemote, .juggling, .claudeUsage, .backgroundAgents, .cloudBranches: .agents
        case .pullRequests, .prStats, .deploys, .devStack, .logErrors, .housekeeping, .jira, .systemStats: .code
        case .sites, .aws, .ecs, .gcp, .codexCloud, .prodWarning: .cloud
        case .water, .breaks, .dailyReminders, .endOfDay, .meetings, .todos, .timesheet, .festivals, .quickCapture: .day
        case .idleTricks, .eyesFollow, .walking: .buddy
        }
    }

    var title: String {
        switch self {
        case .stuckAlerts: "Stuck and waiting-too-long alerts"
        case .autoRemote: "Remote mode when you step away"
        case .juggling: "Too-many-agents nudge"
        case .claudeUsage: "Claude plan usage"
        case .backgroundAgents: "Claude background agents"
        case .cloudBranches: "Claude cloud sessions (claude/ branches)"
        case .pullRequests: "Pull requests"
        case .prStats: "PR stats and leaderboard"
        case .deploys: "GitHub deploys"
        case .devStack: "Local dev stack"
        case .logErrors: "Errors from local logs"
        case .housekeeping: "Disk, big logs, old worktrees"
        case .jira: "Jira"
        case .systemStats: "This Mac (CPU, memory, disk)"
        case .sites: "Site health checks"
        case .aws: "AWS login"
        case .ecs: "AWS ECS services"
        case .gcp: "Google Cloud"
        case .codexCloud: "Codex cloud tasks"
        case .prodWarning: "Production warning"
        case .water: "Water reminders"
        case .breaks: "Break reminders"
        case .dailyReminders: "Daily reminders (lunch, sleep)"
        case .endOfDay: "End-of-day wrap-up"
        case .meetings: "Meeting heads-up"
        case .todos: "To-do list"
        case .timesheet: "Timesheet"
        case .festivals: "Festival costumes"
        case .quickCapture: "Quick capture (⌥Space)"
        case .idleTricks: "Idle tricks"
        case .eyesFollow: "Eyes follow your mouse"
        case .walking: "Walks along the screen"
        }
    }

    /// Off unless you turn it on.
    var defaultOn: Bool { self != .walking && self != .autoRemote }

    /// Where the choice from ⚙︎ is remembered (two older settings keep their keys).
    var defaultsKey: String {
        switch self {
        case .water: "waterReminders"
        case .festivals: "festivalCostumes"
        default: "feature." + rawValue
        }
    }

    /// From the config's "features" (set when the config is loaded).
    nonisolated(unsafe) static var configured: [String: Bool] = [:]

    var isOn: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? Feature.configured[rawValue] ?? defaultOn
    }
}
