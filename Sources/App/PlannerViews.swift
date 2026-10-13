// Panel cards for meetings, the to-do list, Claude plan usage, the timesheet,
// and pull request stats.
import SwiftUI

private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) { content() }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised))
}

private func timeText(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: d)
}

// MARK: - Meetings

struct MeetingsCard: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        let today = tracker.meetings.filter { Calendar.current.isDate($0.start, inSameDayAs: now) || $0.isNow(now) }
        card {
            HStack {
                eyebrow("Meetings")
                Spacer()
                if tracker.currentMeeting != nil {
                    Text("in a meeting · reminders paused").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
            }
            if tracker.calendarAccess == .denied {
                Text("Allow calendar access to get a heads-up before meetings.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy settings") { tracker.openCalendarPrivacy() }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Palette.blue)
            } else if today.isEmpty {
                Text("No more meetings today 🎉").font(.system(size: 12)).foregroundStyle(Palette.muted)
                if let next = tracker.meetings.first {
                    Text("Next: \(next.title), \(Tracker.when(next.start))").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            } else {
                ForEach(today.prefix(4)) { m in row(m) }
                if today.count > 4 {
                    Text("+ \(today.count - 4) more today").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    private func row(_ m: Meeting) -> some View {
        let live = m.isNow(now)
        let until = m.start.timeIntervalSince(now)
        return HStack(spacing: 10) {
            Text(live ? "now" : timeText(m.start))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(live ? Palette.red : Palette.muted)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.system(size: 13)).lineLimit(1)
                Text(live ? "until \(timeText(m.end))" : until < 3600 ? "in \(max(1, Int(until / 60))) min" : m.calendar)
                    .font(.system(size: 11)).foregroundStyle(until < 600 && !live ? Palette.orange : Palette.faint)
            }
            Spacer(minLength: 4)
            if m.joinURL != nil && until < 900 {
                Button("Join") { tracker.joinMeeting(m) }.buttonStyle(.borderedProminent).controlSize(.small).tint(Palette.blue)
            }
        }
    }
}

// MARK: - To-do list

struct TodoCard: View {
    @ObservedObject var tracker: Tracker
    @ObservedObject var draft: CardDraft

    var body: some View {
        let open = tracker.todos.filter { $0.done == nil }
        let done = tracker.todos.filter { $0.done != nil }.sorted { ($0.done ?? .distantPast) > ($1.done ?? .distantPast) }
        card {
            HStack {
                eyebrow("To-do")
                Spacer()
                if !tracker.todos.isEmpty {
                    Text(open.isEmpty ? "all done" : "\(open.count) left").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
                if !done.isEmpty {
                    Button("Clear done") { tracker.clearDoneTodos() }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Palette.blue)
                }
            }
            HStack(spacing: 6) {
                TextField("Add a to-do…", text: $draft.text)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(open + done.prefix(5)) { todo in row(todo) }
            if tracker.todos.isEmpty {
                Text("Agents can add to it too: buddy todo \"…\"")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
        }
    }

    private func add() {
        tracker.addTodo(draft.text)
        draft.text = ""
    }

    private func row(_ todo: Todo) -> some View {
        let isDone = todo.done != nil
        return HStack(alignment: .top, spacing: 8) {
            Button { tracker.toggleTodo(todo) } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isDone ? Palette.green : Palette.muted)
            }
            .buttonStyle(.plain)
            Text(todo.text)
                .font(.system(size: 13))
                .strikethrough(isDone)
                .foregroundStyle(isDone ? Palette.faint : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { tracker.deleteTodo(todo) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
    }
}

// MARK: - Claude plan usage

struct UsageCard: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        card {
            HStack {
                eyebrow("Claude plan")
                Spacer()
                if let u = tracker.usage, now.timeIntervalSince(u.at) > 1800 {
                    Text("as of \(formatDuration(now.timeIntervalSince(u.at))) ago").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
            }
            if let u = tracker.usage, u.fiveHour != nil || u.week != nil {
                if let w = u.fiveHour { bar("5-hour limit", w) }
                if let w = u.week { bar("Weekly limit", w) }
            } else {
                Text("Shows how much of your 5-hour and weekly limits you've used, after Claude Code's next reply. It comes from Claude Code's status line (set up by install.sh).")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bar(_ label: String, _ w: ClaudeUsage.Window) -> some View {
        let color = UsageCard.color(w.percent)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text("\(Int(w.percent.rounded()))%").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.well)
                    Capsule().fill(color).frame(width: max(4, g.size.width * min(1, w.percent / 100)))
                }
            }
            .frame(height: 6)
            if let r = w.resets {
                Text("Resets \(Tracker.when(r))").font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
        }
    }

    static func color(_ percent: Double) -> Color {
        percent >= 95 ? Palette.red : percent >= 80 ? Palette.orange : Palette.green
    }
}

// MARK: - Timesheet

struct TimesheetCard: View {
    @ObservedObject var tracker: Tracker
    let now: Date

    var body: some View {
        card {
            HStack {
                eyebrow("Timesheet")
                Spacer()
                Picker("", selection: $tracker.timesheetWeek) {
                    Text("Today").tag(false)
                    Text("Week").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 120).controlSize(.small)
                Button("Copy") { tracker.copyTimesheet(week: tracker.timesheetWeek) }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(Palette.blue)
                    .help("Copy as rows for a spreadsheet")
            }
            if tracker.timesheetWeek {
                let days = Timesheet.week(of: now)
                let f = { (d: Date) -> String in let x = DateFormatter(); x.dateFormat = "EEE d"; return x.string(from: d) }
                ForEach(days) { d in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(f(d.date)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 48, alignment: .leading)
                        Text(d.projects.isEmpty ? "–" : d.projects.prefix(3).map { "\($0.name) \(Timesheet.hours($0.seconds))h" }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Palette.pillText).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Timesheet.hours(d.total)) h").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                let total = days.reduce(0) { $0 + $1.total }
                HStack {
                    Text("This week").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("\(Timesheet.hours(total)) h").font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .padding(.top, 2)
            } else {
                let day = Timesheet.day(tracker.today, date: now)
                if day.projects.isEmpty {
                    Text("Nothing yet. Time counts toward the project you last gave an agent a prompt in, and meetings from your calendar.")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                }
                let top = day.projects.first?.seconds ?? 1
                ForEach(day.projects, id: \.name) { p in
                    HStack(spacing: 8) {
                        Text(p.name).font(.system(size: 12)).lineLimit(1).frame(width: 120, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(p.name == "Meetings" ? Palette.orange : p.name == "Other" ? Palette.faint : Palette.blue)
                                .frame(width: max(4, g.size.width * p.seconds / top))
                        }
                        .frame(height: 6)
                        Text("\(Timesheet.hours(p.seconds)) h").font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - PR stats

struct PRStatsSection: View {
    @ObservedObject var tracker: Tracker

    var body: some View {
        let closed = tracker.closedSections.contains("prstats")
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(tracker: tracker, key: "prstats", title: "PR stats · 7 days") {
                if let s = tracker.prStats, let rank = s.myRank {
                    Text(rank <= 3 ? "\(["🥇", "🥈", "🥉"][rank - 1]) #\(rank) on the team" : "#\(rank) on the team")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if !closed {
                if let s = tracker.prStats {
                    HStack(spacing: 6) {
                        stat("\(s.merged)", "merged")
                        stat("\(s.opened)", "opened")
                        stat("\(s.reviewed)", "reviewed")
                        stat(s.mergeHours.map { $0 < 48 ? "\(Int($0.rounded())) h" : "\(Int(($0 / 24).rounded())) d" } ?? "–", "to merge")
                    }
                    if !s.board.isEmpty {
                        Text("Merged PRs, whole team").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                        let top = s.board.first?.merged ?? 1
                        let shown = Array(s.board.prefix(5)) + (s.myRank.map { $0 > 5 ? [s.board[$0 - 1]] : [] } ?? [])
                        ForEach(shown) { p in
                            let rank = (s.board.firstIndex(of: p) ?? 0) + 1
                            HStack(spacing: 8) {
                                Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "\(rank).")
                                    .font(.system(size: 11, design: .monospaced)).frame(width: 22, alignment: .leading)
                                Text(p.login == s.me ? "\(p.login) (you)" : p.login)
                                    .font(.system(size: 12, weight: p.login == s.me ? .semibold : .regular)).lineLimit(1)
                                    .frame(width: 130, alignment: .leading)
                                GeometryReader { g in
                                    Capsule().fill(p.login == s.me ? Palette.blue : Palette.faint.opacity(0.6))
                                        .frame(width: max(4, g.size.width * Double(p.merged) / Double(top)))
                                }
                                .frame(height: 6)
                                Text("\(p.merged)").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    Text(PRWatcher.gh == nil ? "Install GitHub's gh to see PR stats." : "Counting…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
