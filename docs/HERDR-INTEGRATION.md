# Herdr integration notes

Inspected on 2026-09-29 before implementation:

- [Herdr repository](https://github.com/herdrdev/herdr): CLI dispatch, machine catalog serialization, machine target routing, snapshot collection, schema types and protocol guards.
- [Documentation overview](https://herdr.dev/docs/).
- [Socket API](https://herdr.dev/docs/socket-api/).
- [Connecting machines](https://herdr.dev/docs/connecting-machines/).
- [CLI reference](https://herdr.dev/docs/cli-reference/).
- [Agents](https://herdr.dev/docs/agents/).
- Installed Herdr 0.9.0: `api schema --json`, `api snapshot`, `status server --json`, `machine list --json`, and a read-only probe of `--machine` support.

Rechecked on 2026-10-01 with installed CLI 0.9.3: `--machine` is supported, and the unchanged Shepherdr probe successfully reads the existing local 0.9.0 server. Herdr reports that server as compatible with no restart required.

## Commands and envelopes

| Purpose | Invocation | Consumed shape |
| --- | --- | --- |
| Saved profiles | `herdr machine list --json` | Array of `id`, `label`, `target`, `session`, `enabled`; `selected` is irrelevant to routing |
| Local session | `herdr api snapshot` | `result.type == session_snapshot`, `result.snapshot` |
| Remote session | `herdr --machine <opaque-profile-id> api snapshot` | Same snapshot envelope, remote session chosen by Herdr |
| Diagnose older local socket failures | `herdr status server --json` | `running`, `compatible` |
| Split a session's pane (⌘D, ⇧⌘D) | `herdr [--machine <profile>] pane split <pane> --direction right\|down --cwd <folder> --no-focus` | `result.pane.terminal_id` |
| Close a split, or a session | `herdr [--machine <profile>] pane close <pane>` | Exit status |

Snapshot and catalog invocations use an executable URL and an argument array, without a shell. For snapshots, Herdr owns forwarding, saved session selection and protocol negotiation. The originally inspected 0.9.0 CLI rejects `--machine`; installed CLI 0.9.3 supports it. There is no fallback from a failed remote request to Local. Terminal streaming has a separate SSH adapter, described below. Neither path scrapes the TUI or parses human listings for application data.

API failures can be JSON on stderr with a nonzero exit status. Decode those envelopes first. Older CLI usage errors have exit status 2 without an envelope; these are reported as incompatible commands. Unstructured transport diagnostics are shown as details, not parsed into agent data. Remote authentication, install and bridge failures without a structured error remain actionable **Unreachable** states. Snapshot/catalog stdin is closed and SSH askpass is disabled.

## Snapshot mapping

The snapshot contains `version`, private `protocol`, `workspaces`, `tabs`, `panes`, `layouts`, and `agents`. Each layout names its tab (`tab_id`), the tab's `area` and each pane's `rect`, in cells, with `pane_id`; Shepherdr places a split session's panes by their share of the area and ignores `splits`, `zoomed` and focus, which don't affect it. A layout it can't read leaves that tab showing one pane, and a snapshot without `layouts`, from an earlier Herdr, shows every tab that way. Focus does not affect the overview and is ignored. Core consumed collections are required; omitted/malformed collections cannot erase last-known data. Additional fields are ignored.

Only the `agents` array creates agent rows. Join its `workspace_id`, `tab_id` and `pane_id` to the corresponding records. Identity is `(machine ID, terminal_id)`, retaining all routing IDs for future actions. Names are optional: use `name`, then `display_agent`/`agent`. Preserve reported semantic `agent_status`; display-only labels, titles and metadata must not override it. Unknown future state strings map to **Unknown** and remain visible in the inspector. Workspace labels are distinct from filesystem paths. Prefer an agent's foreground directory, pane foreground directory, reported cwd, then worktree checkout information.

Herdr owns agent detection and lifecycle authority. Shepherdr does not infer agent progress from screen contents, timing, process names or shell output. In particular, idle does not imply completion, and a custom summary does not imply blocked. The snapshot's explicit done state is shown as Done. New completion sequence fields are not used to invent local unread-completion state.

JSON compatibility is based on the response contract, not a hard-coded private binary protocol number. Herdr's CLI may itself enforce CLI/server compatibility and emit `protocol_mismatch`; Shepherdr surfaces that error. A newer server with additional fields or states can remain usable.

## Refresh and events

The inspected CLI exposes snapshot/schema commands but no general event-stream wrapper. `events.subscribe` requires a persistent raw socket connection; `agent.wait` is targeted coordination, not a cluster subscription. v0 therefore uses bounded periodic CLI snapshots and manual refresh, without a helper daemon or plugin.

A future socket transport must subscribe and receive acknowledgement **before** taking the bootstrap snapshot, buffer events during bootstrap, then reconcile them in order. It must resnapshot on reconnect and apply workspace/tab/pane/agent lifecycle updates. Do not assume that subscriptions replay earlier events. Expose changes to the store through the client boundary; SwiftUI should remain transport-independent.

Queries run concurrently, each with a 12-second process deadline and an 8 MB output bound. Both output pipes drain off the main actor. Cancellation kills the child-owned process group when available, and terminates the child otherwise. The store publishes each response as it arrives. Catalog failure retains known profiles, successful discovery removes deleted profiles, disabled profiles are not queried, and failed snapshots retain their last data and timestamp. Refreshes do not overlap. The refresh interval starts after the prior refresh completes, so unavailable remotes can lengthen a whole cluster cycle by up to the command deadline; manual refresh is disabled during that cycle. `RefreshSchedule` decides what each tick asks. While Shepherdr is on screen, every machine is due at the user's interval. Off screen (the window occluded, the displays asleep, the screen locked, or the user session inactive), the local machine keeps that interval and remote ones are asked every 30 seconds. `machine list --json` runs about once a minute, and on the next tick after it failed. A manual refresh, a change to the machines, waking, or coming back on screen asks everything at once. A machine the catalog brings that wasn't enabled before is asked right away. A change to a session (creating, closing or splitting one, renaming its workspace, starting its agent) reads its machine again at once, without waiting for a refresh in flight, which a slow remote can hold up for seconds. Every snapshot is numbered when it is asked for, and a machine only takes an answer newer than the one it shows, so a slow answer asked before the change never brings back what changed. A pane Herdr closed leaves the snapshot as soon as Herdr confirms it.

## Deliberate limits

- Local is the default session. Remote profiles each identify one session.
- No cluster event subscriptions; terminal windows do consume live CLI frame streams.
- Herdr's snapshots aren't kept across launches. What Shepherdr adds to them is: priorities, groups, holds, each session's tabs and resources, its mail, and each machine's [footprints](#restarts).
- No server lifecycle management. Shepherdr never starts, stops or updates a Herdr server; **Settings → Agents** can set one up to start with the machine, at your request (see [Restarts](#restarts)). Shepherdr creates workspaces, closes panes and changes saved machines only when you ask; enabled terminal input and resizing affect the selected existing terminal through Herdr's API. The [agent tools](AGENT-TOOLS.md) also prompt agents with the handoffs their sessions receive, and Compass starts, prompts and replaces its own agent in its own workspace.
- Actual multi-host SSH validation needs configured machines; automated tests exercise multiple synthetic machines and failures through the same store/client boundary.

## Existing terminals (0.2)

Inspected again on 2026-10-03 using Herdr CLI 0.9.3, its `terminal session` help, the public `src/client/terminal_sessions.rs` implementation and an isolated 0.9.3 server. The reference client [herdrm](https://github.com/missuo/herdrm) demonstrates daemon-owned terminals with native rendering; its current code uses Ghostty, while its README also mentions an earlier SwiftTerm implementation. Shepherdr uses its own adapter and SwiftTerm 1.10.1's AppKit renderer. No Herdr or herdrm implementation is copied.

Local connections explicitly target the saved session and stable terminal ID:

```sh
herdr --session default terminal session observe TERMINAL_ID --cols 100 --rows 30
herdr --session default terminal session control TERMINAL_ID --cols 100 --rows 30
```

Both commands stream newline-delimited JSON: `terminal.frame` includes `encoding: ansi`, `width`, `height`, `full` and base64 `bytes`; `terminal.closed` includes a reason. Control accepts `terminal.input` with base64 bytes, `terminal.resize`, `terminal.scroll` and `terminal.mouse` on stdin. Herdr encodes a `terminal.mouse` event for the program's mouse mode and drops it when the program hasn't enabled mouse reporting; frames never carry the program's input modes, so Shepherdr can't tell which programs read the mouse. Herdr before 0.9.2 doesn't know `terminal.mouse`: it notes the unknown command on stderr and keeps the stream. Observation is read-only and cannot resize through stdin, so changing its viewport reopens that observer connection. Shepherdr never passes `--takeover`. Closing the window releases its client connection, not the server or shell.

A split session attaches each pane of its tab with its own `terminal session control`, at the size that pane has in the window, so a pane can be narrower than the tab Herdr's own client draws. Checked on 2026-10-29 with an isolated 0.9.3 server: `pane split` from the menus put the new pane where `layouts` then placed it, in the given folder, and closing a split with `pane close` let the remaining pane take the tab. Splitting on another machine goes through `--machine` as `pane close` does, which wasn't checked against a remote machine.

`herdr --machine PROFILE terminal session control …` is explicitly rejected as not API-backed by CLI 0.9.3. For remote streams, the transport therefore launches `/usr/bin/ssh -T` with the saved target, then invokes the remote installed Herdr executable with the same session/terminal arguments. A fixed POSIX script locates Herdr; every variable argument is quoted independently, including the outer `sh -c` command. Tests execute adversarial quoted values as literal arguments. User terminal input travels as JSON on stdin and is never interpolated into the SSH command. There is no remote PTY, install/bootstrap, password prompt, host-key bypass, or agent forwarding. Existing OpenSSH configuration and authentication apply.

Every SSH call Shepherdr makes itself shares one option list (`SSHOptions`): `-T`, `BatchMode=yes`, `StrictHostKeyChecking=yes`, `ConnectTimeout=10`, `ClearAllForwardings=yes`, `ForwardAgent=no`, and `ServerAliveInterval=10` with `ServerAliveCountMax=2`. Commands (folder checks, clones, load and background-work readings, agent tools, mail, dropped files) add `ControlMaster=auto`, `ControlPath` in `$HOME/.shepherdr/ssh/%C`, quoted and with `%` escaped, and `ControlPersist=60`, so they share a connection per machine, as Herdr's `--machine` calls do with their own. The folder is made `0700` at launch and used only while it is a private directory of the user's, not a link; ssh fails outright when it is missing. `%C` is a 40-character hash and ssh first binds the socket under a 17-character temporary suffix, so a folder path over 45 bytes, under a very long home, goes without sharing. A backgrounded master hands its standard streams to `/dev/null`, so a command's pipes still reach EOF when it ends. Terminal streams pass `ControlMaster=no` and `ControlPath=none` instead, overriding any sharing in the user's own configuration: killing a shared client leaves its remote command running with the master holding its pipes, and ending a stream must end `terminal session control` and release the terminal.

`HerdrTerminalClient` and `HerdrTerminalConnection` carry domain frames/input independently of the renderer. `TerminalStore` owns observation/control state, input ordering, resize debounce and reconnect. Each connection drains stdout/stderr asynchronously, requires an initial frame within 15 seconds, bounds records to 4 MB, diagnostics to 16 KB, pending writes to 1 MB, and buffered frames to eight. Backpressure fails visibly rather than silently discarding ANSI deltas. Reconnect starts with Herdr's fresh full frame. Cancelling a connection that is still starting, as a terminal that rests does, closes it without waiting for its queue, which may be resuming the cancelled task. After a dropped connection, `TerminalStore` reconnects on its own under a `ReconnectPolicy`: waits that double from 1 second to 5 minutes, for up to an hour, on `SuspendingClock` so time asleep doesn't count. It doesn't retry a terminal Herdr ended because its program exited (`terminal <id> exited`, as when a shell's `exit` closes its pane) or reports as not found: its pane leaves the snapshot at once and its machine is read again, as after closing it from Shepherdr. Nor does it retry an incompatible failure, or another client's control: that still falls back to observing. A terminal nobody can see for 30 seconds (its session left for another, the window occluded or minimized, the screens asleep, locked or switched to another user) rests: `TerminalStore.setVisible` detaches it on purpose, with no reconnect pending, and attaches it again in the same mode when it shows, keeping the last frame until Herdr's full one arrives. `TerminalHolder` keeps a store with its SwiftTerm view while its session is out of sight, so going back reuses both; `SessionCache` decides which holders and browser pages to let go. Resource scans wait for the window to show. No terminal contents are logged or persisted by Shepherdr.

The window supports keyboard input, paste, text selection and copying, scrolling through Herdr's history, and plain clicks for programs that read the mouse; dragging always selects natively. Terminal escape sequences cannot write to the system clipboard through OSC 52. Clicked links are restricted to HTTP(S).

Pane IDs such as `w3:p1` are numbered per Herdr server, so the same one exists on several machines; terminal IDs look like `term_65de5e979051a2` in 0.9.3. `SessionDirectory` turns either, or a session's agent or workspace name, written in a terminal into a link to that session: a pane ID on the session's own machine, unless `@machine` or a `--machine PROFILE` option on the same line names another, which only this Mac's Herdr profiles can. Agents Herdr didn't name report their program's name, such as `Claude Code`, which Shepherdr never takes for a session's name.

## Agent tools (0.9)

Checked on 2026-10-15 with Herdr 0.9.3 in disposable sessions. The [agent tools](AGENT-TOOLS.md) use these parts of Herdr:

- **Doorbells.** `herdr pane report-metadata <pane> --source shepherdr --token shepherdr-mail=<id>` sets a token that the snapshot reports in `panes[].tokens`, on shell panes too, and in `agents[].tokens`. The same source can rewrite it any number of times. Values are cut at 80 characters and names must match `[A-Za-z0-9_-]{1,32}`. Tokens follow the terminal across agent start, release and replacement and `pane move`; a server restart drops them, and changes terminal IDs too. Shepherdr reads only well-formed letter IDs from them.
- **Holds.** Shepherdr copies each waiting session's holds into tokens on its pane: `shepherdr-waits`, then `shepherdr-waits-2` up to `-6` when they don't fit in 80 characters. Each hold is its phase's letter (`p` pending, `s` started, `f` finished) and the awaited terminal ID, with `@<machine ID>` when it is on another machine, comma-separated: `sterm_65e3751a172063,fterm_65e3751a2a7e74@remote:buildbox`. Checked on 2026-10-19 with Herdr 0.9.3: tokens from the same source add up rather than replace each other, `--clear-token` removes one and clearing a missing one is no error, one report sets or clears at most 16 tokens, and a pane keeps at most 32 from all sources, refusing the whole report past that. The copy on this Mac is the one Shepherdr writes; it reads the tokens back only for a waiting session it has no record of and hasn't changed since Herdr last showed it.
- **Letters carried out once.** Shepherdr marks a session started for a session request with `shepherdr-letter=<letter ID>`, and a pane that got a handoff or a first prompt with `shepherdr-delivered=<letter ID>/<place>`, so neither happens twice, even from another Shepherdr or after a restart. Both are set with `pane report-metadata --source shepherdr` and read back from the snapshot, like the holds.
- **Caller context.** Herdr gives every pane `HERDR_ENV`, `HERDR_PANE_ID` and `HERDR_BIN_PATH`. `herdr pane current --current` answers with the caller's `terminal_id` and, when an agent runs there, its `agent` label. The API records no parent for a pane, so links come from what `shepherdr` writes, never from guesses.
- **Creating sessions.** `workspace create --cwd … --label … --no-focus` answers with `.result.root_pane`, and `pane split <pane> --direction right|down --cwd … --no-focus` with `.result.pane`. Both name the new pane's `pane_id`, `terminal_id` and `workspace_id` once in compact JSON, so the command reads them with a fixed pattern instead of parsing JSON in sh. Herdr expands `~` in `--cwd` on its own machine, and opens a missing folder's workspace in the home folder without an error, so the command checks local folders first.
- **Shells.** A pane without an agent reports `agent_status: unknown`, and its `revision` doesn't change with its output. `pane process-info --pane <pane>` answers with `shell_pid` and `foreground_processes`: just the shell while it waits at its prompt, the command otherwise. Shepherdr reads it only for shells that a session waits for, while that hold hasn't finished, and compares `pane read` output to notice a command that finished between two looks.
- **Worktrees.** `worktree open --cwd <repository> --branch <branch> --label … --no-focus` opens the branch's existing worktree, answering like `workspace create` plus `already_open: true` when a workspace already has it, or fails with `worktree_not_found`. `worktree create --cwd … --branch … [--base <ref>] --label … --no-focus` checks an existing local branch out, or creates the branch from `--base` or the repository's `HEAD`, under `<worktrees.directory>/<repo>/<branch-slug>` (`~/.herdr/worktrees` by default), and opens the repository's own workspace too when it isn't open. Git's refusals, such as a branch already checked out elsewhere, come back as `worktree_create_failed` with Git's message; a folder outside a repository as `not_git_worktree`. Remote `--cwd` paths must be absolute or start with `~`. New Session uses both, and fetches a pull request's commits itself first, with plain Git over the same SSH connection as its folder check.
- **Agents.** `agent start <name> --kind <kind> --pane <pane> --timeout 60000` returns once the agent is ready, or `agent_not_ready` when it stopped at a startup question. Names must match `[a-z][a-z0-9_-]{0,31}`; the timeout must be over 3,000 ms and at most 300,000 ms. `agent prompt <pane> <text>` takes a text starting with `-` as text; it fails with `agent_not_ready` when the agent isn't the pane's foreground process, and refuses one that shows a question.
- **Other machines.** All of these go through `--machine <profile>`, which Herdr forwards over its own SSH connection. Errors are JSON on stderr, `{"error":{"code":…,"message":…}}`.

`Tests/AgentTools/herdr-live.sh` checks the command against a real Herdr in a server of its own, and CI runs it with Herdr from Homebrew.

## Restarts

Checked on 2026-11-03 with Herdr 0.9.3 in a server of its own, in a scratch home, with stand-in `claude` and `codex` scripts. Also read on 2026-11-03 from a Linux machine running Herdr 0.9.2 that rebooted, through its logs and session files, without changing anything there:

- **What comes back.** Herdr keeps each session in `~/.config/herdr/session.json`, or `~/.config/herdr/sessions/<name>/session.json` for a named session, with up to 48 earlier copies in `session-snapshots/` beside it. That includes workspaces with their IDs and labels, tabs, layouts, and per pane its number, folder and `agent_session`. After `server stop` and a new `herdr server`, every workspace came back with the same workspace ID, label and pane IDs, such as `w1:p1`, in the same folders.
- **What doesn't.** Terminals get new IDs: `term_65f5d69354ce71` came back as `term_65f5d6ad762711`. Tokens set with `pane report-metadata`, Shepherdr's included, are gone. Processes don't survive.
- **Conversations.** `pane report-agent-session <pane> --source herdr:claude --agent claude --agent-session-id <id>` records a conversation, as Herdr's own integrations do from the agents' hooks. `api snapshot` reports it as `agent_session: {agent, kind: "id", source, value}` on the pane and on its agent, since Herdr 0.6.5. On restart, Herdr ran `claude --resume <id>` and `codex resume <id>` in those panes. Panes without one came back as shells.
- **The rebooted machine.** All 40 workspaces came back. Of 36 agents, the 33 Claude Code sessions had a conversation recorded and resumed. Of the 3 Codex sessions, 2 had none and came back as shells; the third had a months-old conversation recorded.
  - Codex 0.157 and later runs one shared server per machine, which runs its hooks with the environment of whichever pane started it, so Herdr's Codex integration reports conversations on the wrong pane or on none ([herdr#4649](https://github.com/herdrdev/herdr/issues/4649)).
  - `codex features list` shows the setting as `daemon_auto_start`, and `codex features disable daemon_auto_start` turns it off in `~/.codex/config.toml`.
- **Starting.** Nothing starts a server after a reboot: on that machine both servers were started by hand over SSH. A second `herdr server` for a session that has one exits with status 1 and `error: herdr server is already running`.
- **Integrations.** `herdr integration status` works without a server and prints one line per agent: `claude: current (v10) (<path>)`, `codex: outdated (v3 < v8) (<path>)` or `codex: not installed (<path>)`. `herdr integration install claude|codex` needs the agent's folder, `~/.claude` or `~/.codex`, and fails without it.

How Shepherdr uses this:

- **Footprints.** For each machine, Shepherdr keeps the pane ID, workspace label and conversation of every terminal it last saw there (`sessionFootprints.v1`). When a machine that answers shows new terminals, it pairs them with the terminals that left:
  - First by conversation, when exactly one terminal on each side has it.
  - Then, only when none of the old terminals is left, which means Herdr restarted, by pane ID and workspace label.
  - It moves holds, priorities, groups, tabs, resources, mail and drafts to the new terminal before anything drops the old one as closed. Its holds are written to Herdr again as tokens on the new panes.
- **State files.** On machines with the agent tools, Shepherdr writes the holds of the sessions there to `~/.shepherdr/state/<instance ID>`, by footprint. See [AGENT-TOOLS](AGENT-TOOLS.md#state-files).
- **Version.** `HerdrRelease.recommended`, 0.9.5, is the release Shepherdr asks for. Release notes read on 2026-11-06: 0.9.4 saves before a Mac shuts down, so agents' sessions survive its restart ([#4414](https://github.com/herdrdev/herdr/issues/4414)), and writes saves atomically; 0.9.5 shows Claude Code's questions as blocked in named sessions ([#4573](https://github.com/herdrdev/herdr/issues/4573)) and no longer installs Codex turn hooks. Shepherdr reads each server's version from `api snapshot` and offers the update in the sidebar while one is older. It never updates or restarts a server itself.
- **Checks.** Along with the agent tools, Shepherdr asks each machine for a few things:
  - its system;
  - which of `~/.claude` and `~/.codex` exist;
  - `herdr integration status`;
  - whether `python3` is on the PATH;
  - `codex features list`;
  - the services that run `herdr … server`: systemd units in the user and system unit folders, with `systemctl is-enabled`, and launch agents in `~/Library/LaunchAgents` with `RunAtLoad`;
  - on Linux, `loginctl show-user $(id -un) -p Linger`.

  The server's version comes from the snapshot. Nothing is changed by a check.
- **Fixes.** Each runs only when you press its button in **Settings → Agents**:
  - `herdr integration install <agent>`.
  - `codex features disable daemon_auto_start`.
  - Starting with the machine. On Linux this writes `~/.config/systemd/user/herdr-<session>.service`, then runs `systemctl --user daemon-reload` and `systemctl --user enable` (not `--now`), then `loginctl enable-linger` if the user's services don't start at boot yet. On a Mac it writes `~/Library/LaunchAgents/com.theagilemonkeys.shepherdr.herdr-<session>.plist` with `RunAtLoad`, without loading it.
  - The service runs `herdr server` by its full path, with `HERDR_SESSION` for a named session, and a `PATH` with the folders of `herdr`, `claude`, `codex`, `node` and `python3`.

## Compass (0.9)

Checked on 2026-10-15 with Herdr 0.9.3 in a server of its own, in a scratch home, with a stand-in `claude` that reports itself with `pane report-agent`:

- **Its workspace.** `workspace create --cwd ~/.shepherdr/compass --label compass --no-focus`, then `agent start compass --kind <kind> --pane <pane> --timeout 60000` in its root pane, so a failed start leaves a pane Shepherdr can start the agent in again. A name another agent has fails with `agent_name_taken`; Shepherdr then starts it as `compass-<4 hex>`. Herdr reports pane folders with symbolic links resolved (`/tmp` as `/private/tmp`), so Shepherdr compares resolved paths.
- **Finding it again.** Shepherdr keeps the terminal ID it started. After a Herdr restart, which changes terminal IDs, it looks for a pane whose workspace starts with `compass` and whose folder is Compass's. Before the local machine's first snapshot, it doesn't start anything: only Herdr's answer tells whether the agent is there.
- **Runs.** `agent prompt <pane> <text>` once the agent is `idle` or `done`, as handoffs are delivered. `agent_blocked`, `agent_not_ready` and `agent_busy` are tried again later.
- **A new day.** `pane close` on every pane in Compass's workspace and folder, then a new workspace. Closing a workspace's only pane closes the workspace.
- **Awake and online.** Shepherdr runs `agent start` and `agent prompt` for Compass only while this Mac is fully awake and online (see [AGENT-TOOLS](AGENT-TOOLS.md#runs)): Herdr types the agent's plain command, such as `claude`, into the pane's shell, so the moment is the only difference from starting it by hand. An agent started across a sleep or a lost network is replaced before its first prompt as on a new day: `pane close`, then a new workspace and `agent start`.

## Shepherdr Remote (unreleased)

Checked on 2026-11-01 with Herdr 0.9.3 in a server of its own, through the relay of a copy of the app and a test client:

- **A phone's pane.** The relay opens `terminal session control` for each pane a phone shows, at the phone's columns and rows, through the same `TerminalStore` and SSH adapter as the window. Herdr resized the pane's terminal to it: a shell's long line wrapped at the phone's 60 columns. Frames go on to the phone as Herdr sends them, full first, with mode 2026 and OSC 8 taken out.
- **One controller.** Herdr lets one client control a terminal, so before attaching, the relay has this Mac's own window let go of that pane (`TerminalStore.disconnect`), with a notice; when the phone is done, the window attaches again if it shows the pane. Another client in control makes the phone watch, as the window does, and **TAKE OVER** passes `--takeover` only when you tap it.
- **Prompts** from the phone go through the phone's control connection as the prompt editor's do, a bracketed paste and a separate Return, or through `agent prompt` when the phone isn't attached to that pane.
- **Herd mode** reads only the statuses the queue already sends. `agent prompt` refuses an agent that asks something (`agent_blocked`), so answers go through the terminal the phone attaches, with its keys, which Herdr delivers to the question. A session whose agent exits leaves the queue's sessions: its pane shows as a shell, or is gone. Checked on 2026-11-04 with Herdr 0.9.3 and a fake agent that calls `pane release-agent` as it exits.
- Not checked: a pane on another machine from the phone, though it goes through the same SSH adapter as the window's.
