# Contributing to Agent Buddy

Thanks for helping! Ideas, bug reports and code are all welcome.

## Suggest a feature

Open an issue with the **Feature request** template: [new feature request](https://github.com/aswinikumar-555/agent-buddy/issues/new?template=feature_request.md). Say what problem it solves for you; a sketch or screenshot helps.

## Report a bug

Open an issue with the **Bug report** template: [new bug report](https://github.com/aswinikumar-555/agent-buddy/issues/new?template=bug_report.md). Include your macOS version, what you expected, and what happened. Please remove anything private (repo names, URLs, tokens) from logs and screenshots.

## Work on the code

You need macOS 14+ and Apple's command line tools (`xcode-select --install`).

```bash
# 1. Fork the repo on GitHub, then:
git clone https://github.com/<you>/agent-buddy.git
cd agent-buddy
git checkout -b my-change

# 2. Edit, then build, install and run your version:
bash install.sh
```

`install.sh` rebuilds everything and restarts the buddy, so run it after each change. To only check that it compiles:

```bash
swiftc -O -swift-version 5 Sources/App/*.swift -o build/AgentBuddy
swiftc -O -swift-version 5 Sources/Hook/main.swift -o build/buddy-hook
```

### Where things are

| File | What it does |
|---|---|
| `Sources/App/main.swift` | Tracking (agents, events, reminders) and the buddy window |
| `Sources/App/Panel.swift` | The panel you see when you click the buddy, and its themes |
| `Sources/App/Buddy3D.swift` | The 3D characters and their moods |
| `Sources/App/Chat.swift` | Chatting with an agent |
| `Sources/App/Herdr.swift`, `Stack.swift`, `Cloud.swift`, `Gcp.swift`, `Aws.swift`, `Watch.swift`, `Extras.swift`, `Deploys.swift` | One feature area each (herdr, local dev stack, ECS and Codex cloud, Google Cloud, AWS login, sites/production/logs/day summary, PRs/disk, deploys and settings) |
| `Sources/App/DocsRenderer.swift` | Draws the README images |
| `Sources/Hook/main.swift` | The small program Claude Code and Codex run for each hook event |

### Screenshots

If you change something visible, redraw the README images and include them in your pull request:

```bash
./build/AgentBuddy --render-docs docs
```

They're drawn from made-up sample data, so no personal information ends up in them.

## House rules

- **Local only.** No telemetry, no servers, no accounts. Network calls go only through tools the user already has (`gh`, `aws`, `gcloud`) or to URLs they configured.
- **Read-only in the cloud.** The buddy watches; it never deploys, scales, deletes or changes anything.
- **Never block an agent.** The hook must always exit 0 and stay fast. Only Remote mode waits, and only when the user turned it on.
- **Nothing company-specific.** Names of your repos, clusters, secrets or domains go in your own `~/.agent-buddy/config.json`, never in the code.
- **Light on the battery.** Keep polling gentle and animations at a low frame rate when nothing is happening.
- **Match the surrounding code:** small focused changes, plain names, short comments that explain why.

## Send a pull request

1. Push your branch to your fork and open a pull request against `main`.
2. Describe what changed and why, how you tested it, and add screenshots for anything visible.
3. Keep it focused: one feature or fix per pull request.

By contributing, you agree your contribution is released under the [MIT license](LICENSE).
