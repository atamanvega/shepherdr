Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.10.0

From 0.8.7 on, Shepherdr offers this version itself, at the foot of the sidebar.

- **Your queue in your pocket.** Shepherdr Remote, a new iPhone companion, shows your queue with its groups and holds, search, Compass's page and each session's resources. It opens any session's live terminal, fitted to the phone, with a keys row, a prompt composer and on-device dictation. Turn on the relay in **Settings → Remote** and pair the phone with a QR code. It reaches Shepherdr on your Mac through Tailscale, over TLS pinned to your Mac's key, never SSH. When your Mac's firewall blocks incoming connections, it goes through Tailscale Serve. Its **herd mode** turns unblocking sessions into an arcade game, with combos, a countdown and a table of high scores. The iPhone app isn't on the App Store yet: build it from the repository with Xcode, as the [development guide](https://github.com/theam/shepherdr/blob/main/docs/DEVELOPMENT.md#shepherdr-remote-ios) explains.
- **Sessions survive Herdr restarts.** When a machine reboots or its Herdr server restarts, Herdr brings the sessions back with new terminals. Shepherdr now moves their holds, place in the queue, groups, tabs and mail to the new terminals instead of dropping them. **Settings → Agents** checks what each machine needs to come back well and offers to fix it: Herdr's version, its Claude Code and Codex integrations, Codex's shared server, and Herdr starting by itself.
- **Agents open files for you.** Ask an agent to show you a page or a file and it opens it in its session's browser. Agents also write the paths of the files they mention relative to their folder, so you can click them. Your machines are offered the updated agent tools.
- **One New Session, with an agent.** **⌘N** and a group's **+** open the same sheet. It starts Claude Code, Codex or another agent with its first prompt, or a shell, and remembers your last agent.
- **Files in the browser.** A session's address field takes a path such as `~/notes/plan.md` or a `file://` link.
- **Time to update Herdr?** Below Herdr 0.9.5, the foot of the sidebar suggests updating, and says how. Herdr 0.9.4 keeps agents' sessions through a Mac restart, and 0.9.5 shows Claude Code's questions in named sessions.

### Fixed

- A `file://` link pasted into a session's address field did nothing.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3. Herdr 0.9.5 or later is recommended, so agents' sessions come back after a restart.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles, watch pull requests' CI checks and fill the GitHub inbox.
- **Shepherdr Remote** needs Tailscale on the Mac and the iPhone, and iOS 26 or later. The relay stays off until you turn it on.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals, folder checks, machine load and commands left running use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- The agent tools are optional. Shepherdr installs them over SSH only when you accept, writing only `~/.shepherdr` and the agents' skill folders, without `sudo`; on each machine they need only `sh` and Herdr.
- Once installed, Shepherdr offers new versions as they come out and updates itself in place, only with an app signed by the same team and notarized by Apple.
- Shepherdr is **signed with The Agile Monkeys' Developer ID and notarized by Apple**: it opens like any other download, with no trip to **Privacy & Security**.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
