# Agent Buddy

**A 3D desktop buddy for your Mac that watches your AI coding agents, your deploys and your dev stack, and tells you when something needs you.**

You start Claude Code or Codex on a few tasks, switch to something else, and lose track. Agent Buddy sits in the corner of your screen as a small 3D cat (or robot), keeps an eye on everything, and acts it out: it types while agents work, raises a paw when one needs you, and jumps when a task is done. Click it for the full picture.

Everything runs on your Mac. No account, no server, no tracking.

<p align="center"><img src="docs/demo.gif" width="330" alt="Nori the cat on the desktop: it types while an agent works, raises a paw when one needs you, and jumps with confetti when the task is done, with a speech bubble for each"></p>

```bash
git clone https://github.com/aswinikumar-555/agent-buddy.git ~/agent-buddy && cd ~/agent-buddy && bash install.sh
```

That's the whole install ([details](#install-on-your-mac)). It builds on your Mac in about a minute.

<p align="center">
  <img src="docs/panel-agents.png" width="270" alt="The Agents tab: a permission request with Allow and Deny, running agents, and what finished today">
  <img src="docs/panel-code.png" width="270" alt="The Code tab: pull requests with the first CI error, the local dev stack, and deploys">
  <img src="docs/panel-cloud.png" width="270" alt="The Cloud tab: site health, AWS ECS and Google Cloud Run">
</p>
<p align="center"><sub>Click the buddy to open the panel: <b>Agents</b>, <b>Code</b>, <b>Cloud</b> and <b>Me</b> tabs, with status pills at the bottom.</sub></p>

---

## What it does

<img src="docs/bubble.png" width="300" align="right" alt="A speech bubble: payments-api: Fixed the flaky refund test; all 214 tests pass.">

**Your agents (Claude Code and Codex)**
- Shows which agents are running, which need you, and what each one finished, in the agent's own words ("Fixed the flaky refund test; all 214 tests pass").
- Click a bubble to jump straight to that agent's terminal.
- **Remote mode:** approve permission prompts, answer an agent's questions, and reply when it finishes, all from the buddy. It can switch on by itself when you step away.
- **Chat:** send a message to any agent from the buddy, whether it's working or idle.
- **`buddy say "…"`:** any agent or script can put a message on your screen.
- Alerts when an agent has been waiting on you too long, seems stuck, or you're running too many at once.
- Works with agents in any terminal, and with [herdr](https://herdr.dev) panes.

**Your code and cloud**
- **Pull requests:** CI failing, ready to merge, merged, review requested. For a failing PR it shows the first CI error and the local agent working on that branch, with one click to send it the failure.
- **GitHub deploys:** started, succeeded, failed.
- **Local dev stack:** a light per service, alerts when one crashes, and new errors from its logs (with "ask an agent to fix").
- **AWS:** whether your CLI login is still valid, and ECS service health (with why a service is down).
- **Google Cloud:** whether your `gcloud` login is still valid, and Cloud Run service health (with why a service isn't ready).
- **Sites:** health checks for your staging and production URLs.
- **Production warning:** a red **PROD** band when an agent runs a command against production or a production database tunnel is open.
- **Housekeeping:** low disk space, huge log files, old git worktrees (it only reports; it never deletes).

**Your day**
- Reminders for water, breaks, lunch and sleep, acted out by the buddy (it eats, drinks and sleeps). Quiet while your microphone is in use.
- Work hours: outside them, work alerts go quiet.
- End of day: a summary of what got done, ready to paste into standup, plus a note for tomorrow.
- Nap: hold every alert for a while.

All alerts appear in the buddy's speech bubble. Mac notifications are off by default (turn them on in ⚙︎).

---

## Pick your buddy

Five 3D characters, lit and shaded on your Mac. Switch with ⚙︎ → Character:

| | |
|---|---|
| **Nori** | a cat whose collar glows in the mood's color |
| **Bolt** | a chrome robot with a glowing face, antenna and ears |
| **Quackers** | a rubber duck floating on a little pond, flapping its wings while agents work |
| **Sage** | an owl that turns its head right round to watch your agents |
| **Nova** | an astronaut drifting in zero gravity, with a glowing visor ring |

Each one acts out what's going on: idle, working, needs you, done, and break time. Its accent color (collar, ears, cap, eyes or visor) follows the mood.

<p align="center"><img src="docs/characters.png" width="820" alt="Nori the cat, Bolt the robot, Quackers the rubber duck, Sage the owl and Nova the astronaut in five moods: idle, working with spinning gears, needs you with a question mark, done with confetti, and break time stretching"></p>

It acts out your day too: it eats at lunch, drinks when it's time for water, falls asleep at night, and wears a red **PROD** band when something touches production.

<p align="center"><img src="docs/day.png" width="640" alt="Nori eating noodles at lunch, sipping a drink, sleeping with floating Zs, and wearing a red PROD badge"></p>

---

## Install on your Mac

### 1. What you need

| | |
|---|---|
| **macOS 14 (Sonoma) or later** | Apple silicon or Intel |
| **Apple's command line tools** | Builds the app on your Mac. If you don't have them, run `xcode-select --install` |
| **Claude Code and/or Codex** | The agents it watches |
| *Optional:* [`gh`](https://cli.github.com) | For pull requests and deploys. Log in with `gh auth login` |
| *Optional:* [`aws`](https://aws.amazon.com/cli/) | For the AWS login light and ECS health |
| *Optional:* [`gcloud`](https://cloud.google.com/sdk/docs/install) | For the Google Cloud login light and Cloud Run health |
| *Optional:* [`herdr`](https://herdr.dev) | To see agents in herdr panes and send them messages |

### 2. Install

```bash
git clone https://github.com/aswinikumar-555/agent-buddy.git ~/agent-buddy
cd ~/agent-buddy
bash install.sh
```

The installer:
1. Checks the requirements above.
2. Builds the app from source on your Mac (about a minute the first time). Nothing is downloaded.
3. Installs it to `~/Applications/AgentBuddy.app` and starts it at login.
4. Adds its hooks to Claude Code (`~/.claude/settings.json`) and Codex (`~/.codex/hooks.json`). Your existing hooks are kept, and a backup is saved next to each file (`.bak-agent-buddy`).
5. Installs the `buddy` command, and adds a short note to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` telling agents when to use `buddy say`.
6. Creates your config at `~/.agent-buddy/config.json` from `config.example.json`.

### 3. After installing

- **Restart any open Claude Code or Codex sessions** so they pick up the hooks.
- **Codex:** open Codex → Settings → **Hooks** → **Trust all**, or Codex won't run them.
- **Edit `~/.agent-buddy/config.json`** to add your repos, sites and so on (see [Configuration](#configuration)), then restart the buddy: right-click it → ⚙︎ → Quit, then `open ~/Applications/AgentBuddy.app`.
- macOS may ask once whether Agent Buddy may **control Terminal**. That's only used when you click "jump to agent" or send a message to an agent in a Terminal tab.

To update later: `cd ~/agent-buddy && git pull && bash install.sh`.

---

## Using it

| You want to… | Do this |
|---|---|
| See everything | Click the buddy |
| Hide the panel | Click the buddy again, or **×** |
| Make the panel smaller | **⤡** in the panel header (minimize), or drag its top-left corner or edges |
| Move the buddy | Drag it |
| Make the buddy bigger or smaller | ⚙︎ → Bigger / Smaller |
| Switch between the cat and the robot | ⚙︎ → Character |
| Light or dark panel, or another color scheme | ⚙︎ → Theme |
| Answer agents from the buddy | Turn on **Remote** in the panel header |
| Message an agent | Click the agent in the panel, type, send |
| Hold all alerts | ⚙︎ → Nap |
| Let an agent or script tell you something | `buddy say "Tests are green"` (add `--urgent` to keep it until dismissed) |

The panel has four tabs: **Agents**, **Code** (PRs, local stack, deploys, errors), **Cloud** (sites, AWS ECS, Google Cloud Run, Codex cloud) and **Me** (reminders, today's summary, nap). The number tiles and status pills open the right tab.

<p align="center">
  <img src="docs/panel-me.png" width="270" alt="The Me tab: work time, water, lunch and sleep reminders, work hours, and today's summary with Copy for standup">
  <img src="docs/panel-minimized.png" width="300" alt="The minimized panel: just the number tiles and status pills">
</p>
<p align="center"><sub>Left: the <b>Me</b> tab. Right: the panel minimized to just the numbers and status.</sub></p>

### Themes

Pick a look for the panel with ⚙︎ → **Theme**: **Midnight**, **Daylight**, **Ocean** or **Sunset**, or **Auto** to follow your Mac's light/dark setting.

<p align="center"><img src="docs/themes.png" width="900" alt="The panel in four themes: Midnight (dark grey), Daylight (light), Ocean (navy) and Sunset (warm brown)"></p>

---

## Configuration

Edit `~/.agent-buddy/config.json`, then restart the buddy. Every setting is optional; `config.example.json` shows them all. If the file has a mistake, the buddy says so in its bubble and runs on defaults (your file is never overwritten).

| Setting | What it does | Default |
|---|---|---|
| `repos` | GitHub repos (`owner/name`) watched for deploys and your PRs | none |
| `deployWorkflowPattern` | Which GitHub Actions workflows count as deploys (regex) | `deploy\|promote\|rollback\|release` |
| `workHours` | `start`, `end`, `days`. Outside them, work alerts are quiet | 09:30–20:00, Mon–Sat |
| `breakMinutes` / `waterMinutes` | Break and water reminder intervals | 90 / 60 |
| `dailyReminders` | Fixed-time reminders: `time`, `title`, `message`, `emoji`, and `activity` (`eat`, `drink` or `sleep`) for the buddy to act out | lunch 14:00, sleep 23:00 |
| `stuckWaitingMinutes` / `stuckQuietMinutes` | When an agent counts as waiting too long / stuck | 10 / 20 |
| `juggle` | Agents at once before it suggests finishing one | 5 |
| `autoRemote` / `autoRemoteMinutes` | Remote mode on after being away this long | on / 5 |
| `stackRoots` | Folders holding your projects (scanned for dev stacks, big logs, old worktrees) | `~/Developer`, `~/code`, `~/projects` |
| `dbTunnels` | Local database tunnel ports to watch: `{ "env": "prod", "port": 5439 }` | none |
| `ecsRegion` / `ecsClusters` | AWS ECS clusters to watch (read-only) | none |
| `gcpProjects` | Google Cloud projects whose Cloud Run services to watch (read-only): `{ "project": "my-proj", "region": "us-central1" }` (leave out `region` for all regions) | none |
| `sites` | Health checks: `{ "name", "url", "prod" }`. Any 2xx/3xx answer counts as up | none |
| `prodEnvs` | Names that mean production (in cluster names, tunnels, stack envs) | `prod`, `production` |
| `prodPatterns` | Regexes for shell commands that touch production (secret names, prod hosts, …) | a few generic ones |

### The local dev stack monitor

This watches projects that start their services with a `scripts/dev/ports.sh` port map, PID files in `.dev-pids/` and logs in `.dev-logs/` (the convention it was built for). Projects that don't use that layout are simply skipped.

---

## Privacy and what it touches

- **Local only.** No server and no telemetry. Its data lives in `~/.agent-buddy/` (events, settings, notes, daily summaries).
- **Network calls happen only through tools you already use and only for features you configure:** `gh` (PRs, deploys), `aws` (read-only: `sts get-caller-identity`, ECS describe and list calls), `gcloud` (read-only: `auth print-access-token`, `run services list`), `codex cloud list`, and plain GET requests to the `sites` you list.
- **It never deploys, scales, deletes or changes anything** in your cloud accounts or repos. The production warning only warns.
- Files it changes outside its own folder: `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` (a marked section), the `buddy` command in `/opt/homebrew/bin` (or `~/.local/bin`), and a login item in `~/Library/LaunchAgents`. The uninstaller removes all of them.

---

## Uninstall

```bash
cd ~/agent-buddy && bash uninstall.sh
```

This stops the app and removes it, its login item, its hooks, the `buddy` command, the `CLAUDE.md` / `AGENTS.md` section, and `~/.agent-buddy/`.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `xcrun: error` or `swiftc` not found during install | Run `xcode-select --install`, then `bash install.sh` again |
| The buddy doesn't appear | `open ~/Applications/AgentBuddy.app`. If it's off-screen after unplugging a display, it moves back on its own at the next start |
| Agents don't show up | Restart the agent sessions after installing. For Codex, trust the hooks (Settings → Hooks → Trust all) |
| No PRs or deploys | Install `gh`, run `gh auth login`, and list your repos in `repos` |
| AWS light is grey | `aws` isn't installed or you're offline. Red means run `aws login` (or click the light) |
| GCP light is red | Your `gcloud` login expired: click it to run `gcloud auth login` |
| Settings didn't change | Restart the buddy after editing the config. A bubble at start-up tells you if the file has an error |

---

## Building by hand

```bash
swiftc -O -swift-version 5 Sources/App/*.swift -o build/AgentBuddy
swiftc -O -swift-version 5 Sources/Hook/main.swift -o build/buddy-hook
```

The images in this README are drawn by the app itself from made-up sample data, so they always match the real UI. To redraw them after a change:

```bash
./build/AgentBuddy --render-docs docs
```

- `Sources/App/` is the app (SwiftUI + SceneKit): `main.swift` (tracking and the buddy), `Panel.swift` (the panel), `Buddy3D.swift` (the 3D characters), plus one file per feature area.
- `Sources/Hook/main.swift` is the small program Claude Code and Codex run for each hook event. It appends one line to `~/.agent-buddy/events.jsonl`, and in Remote mode waits for your answer from the app.

## Contributing

Ideas, bug reports and pull requests are welcome.

- **Suggest a feature:** [open a feature request](https://github.com/aswinikumar-555/agent-buddy/issues/new?template=feature_request.md)
- **Report a bug:** [open a bug report](https://github.com/aswinikumar-555/agent-buddy/issues/new?template=bug_report.md)
- **Send code:** see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, where things are, and house rules.

## Credits

Built with [Claude Code](https://claude.com/claude-code).

## License

[MIT](LICENSE)
