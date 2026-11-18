import Foundation

/// How ready a machine is for its Herdr server to restart, as after the machine reboots: whether
/// Herdr comes back on its own, and whether the agents' conversations are recorded so Herdr can
/// resume them.
public struct RestartReadiness: Equatable, Sendable {
    public enum Integration: String, Equatable, Sendable {
        case current, outdated, missing
    }

    /// A service that starts a Herdr server: a systemd unit, or a launchd agent on a Mac.
    public struct Service: Equatable, Sendable {
        public let name: String
        public let session: String
        public let isEnabled: Bool
    }

    /// `Linux` or `Darwin`.
    public var system: String?
    /// The agents installed there, `claude` and `codex`, and Herdr's integration for each.
    public var agents: [String: Integration?] = [:]
    public var hasPython: Bool?
    /// Whether Codex runs one shared server for all its sessions: its hooks then report
    /// conversations on the wrong pane, or on none.
    public var codexSharesServer: Bool?
    public var services: [Service] = []
    /// Whether systemd starts the user's services at boot, before anyone logs in.
    public var lingers: Bool?

    public init() {}

    public var isMac: Bool { system == "Darwin" }

    /// Whether a service starts the Herdr server of `session` once the machine starts.
    public func startsHerdr(session: String) -> Bool {
        services.contains { $0.isEnabled && $0.session == session }
    }
}

/// Something about a machine that decides what a restart of its Herdr server costs, with what
/// Shepherdr can do about it there.
public struct RestartFinding: Identifiable, Equatable, Sendable {
    public enum Fix: Equatable, Sendable {
        case installIntegration(String)
        case stopCodexSharedServer
        case startAtBoot(session: String)
    }

    public let id: String
    public let isReady: Bool
    public let text: String
    public var fix: Fix?
    /// What to do by hand, such as a command to run there.
    public var hint: String?
}

extension Agent {
    /// Whether this session would come back as a shell after its machine's Herdr restarts: Herdr
    /// resumes this agent's conversations, but recorded none for it.
    public var isUnrecorded: Bool { !isLaunchPending && conversation == nil && RestartCheck.resumableAgents.contains(kind) }
}

public enum RestartCheck {
    /// The agents Herdr's integrations resume, as Herdr names them.
    public static let resumableAgents = ["claude", "codex"]

    private static let findTool = """
    find_tool() {
      found=$(command -v "$1" 2>/dev/null) || found=
      if [ -z "$found" ]; then
        for candidate in "$HOME/.local/bin/$1" "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "$HOME/.cargo/bin/$1" "$HOME/.npm-global/bin/$1"; do
          if [ -x "$candidate" ]; then found=$candidate; break; fi
        done
      fi
      printf '%s' "$found"
    }
    """

    static let script = """
    export LC_ALL=C
    \(findTool)
    echo 'shepherdr-restarts 1'
    echo "system $(uname -s 2>/dev/null)"
    if [ -d "$HOME/.claude" ]; then echo 'agent claude'; fi
    if [ -d "${CODEX_HOME:-$HOME/.codex}" ]; then echo 'agent codex'; fi
    herdr=$(find_tool herdr)
    if [ -n "$herdr" ]; then
      "$herdr" integration status 2>/dev/null | awk -F': ' '$1 == "claude" || $1 == "codex" { split($2, state, " [(]"); print "integration", $1, state[1] }'
    fi
    if command -v python3 >/dev/null 2>&1; then echo 'python3 yes'; else echo 'python3 no'; fi
    codex=$(find_tool codex)
    if [ -n "$codex" ]; then
      "$codex" features list 2>/dev/null | awk '$1 == "daemon_auto_start" { print "codex-daemon", $NF }'
    fi
    case $(uname -s 2>/dev/null) in
    Darwin)
      for plist in "$HOME"/Library/LaunchAgents/*.plist; do
        [ -f "$plist" ] || continue
        program=$(plutil -extract ProgramArguments json -o - "$plist" 2>/dev/null) || continue
        case $program in *herdr*server*) ;; *) continue ;; esac
        session=$(plutil -extract EnvironmentVariables.HERDR_SESSION raw -o - "$plist" 2>/dev/null) || session=
        state=disabled
        if [ "$(plutil -extract RunAtLoad raw -o - "$plist" 2>/dev/null)" = true ]; then state=enabled; fi
        echo "service $state ${session:-default} $(basename "$plist" .plist)"
      done
      ;;
    Linux)
      for dir in "$HOME/.config/systemd/user" /etc/systemd/user /usr/lib/systemd/user /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
        for unit in "$dir"/*.service; do
          [ -f "$unit" ] || continue
          grep -q 'herdr.* server' "$unit" 2>/dev/null || continue
          case $dir in */user) scope=--user ;; *) scope= ;; esac
          state=$(systemctl $scope is-enabled "$(basename "$unit")" 2>/dev/null) || state=${state:-disabled}
          session=$(awk 'match($0, /HERDR_SESSION=[A-Za-z0-9._-]+/) { print substr($0, RSTART + 14, RLENGTH - 14); exit }' "$unit")
          echo "service $state ${session:-default} $(basename "$unit")"
        done
      done
      linger=$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null) || linger=
      echo "linger ${linger:-unknown}"
      ;;
    esac
    echo 'shepherdr-restarts end'
    """

    /// Looks at a machine. Nothing there is changed.
    public static func check(_ machine: Machine) async throws -> RestartReadiness {
        guard let command = machine.shell(script) else {
            throw HerdrFailure(.incompatible, "Shepherdr can't reach \(machine.name) over SSH.")
        }
        let output = try await Mailbox.run(command, on: machine, action: "check how restarts go on")
        return try parse(String(decoding: output.stdout, as: UTF8.self))
    }

    static func parse(_ output: String) throws -> RestartReadiness {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.firstIndex(of: "shepherdr-restarts 1"), lines[start...].contains("shepherdr-restarts end") else {
            throw HerdrFailure(.unreachable, "The machine didn't say how restarts go there.")
        }
        var readiness = RestartReadiness()
        for line in lines[start...] {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let key = fields.first else { continue }
            switch (key, fields.count) {
            case ("system", 2...):
                readiness.system = fields[1]
            case ("agent", 2) where resumableAgents.contains(fields[1]):
                if readiness.agents[fields[1]] == nil { readiness.agents[fields[1]] = .some(nil) }
            case ("integration", 3...) where resumableAgents.contains(fields[1]):
                let state = fields[2...].joined(separator: " ")
                let integration: RestartReadiness.Integration? = switch state {
                case "current": .current
                case "outdated": .outdated
                case "not installed": .missing
                default: nil
                }
                // Herdr knows of the integration whether or not the agent is installed.
                if readiness.agents.keys.contains(fields[1]) { readiness.agents[fields[1]] = .some(integration) }
            case ("python3", 2):
                readiness.hasPython = fields[1] == "yes"
            case ("codex-daemon", 2):
                readiness.codexSharesServer = fields[1] == "true"
            case ("service", 4...):
                readiness.services.append(.init(name: fields[3...].joined(separator: " "), session: fields[2],
                                                isEnabled: fields[1] == "enabled"))
            case ("linger", 2):
                readiness.lingers = fields[1] == "unknown" ? nil : fields[1] == "yes"
            default:
                continue
            }
        }
        return readiness
    }

    /// What a machine's restart would cost, from what it said and what Shepherdr sees of it: its
    /// Herdr server's version and its sessions. Ready ones first say what works.
    public static func findings(_ readiness: RestartReadiness, machine: Machine, herdrVersion: String?,
                                sessions: [Agent]) -> [RestartFinding] {
        var findings: [RestartFinding] = []
        let name = machine.isLocal ? "this Mac" : machine.name
        // From 0.9.4, saves are atomic and Macs that restart keep their agents' sessions.
        if let herdrVersion, HerdrRelease.isBehind(herdrVersion) {
            findings.append(RestartFinding(id: "herdr", isReady: false,
                text: "Herdr \(herdrVersion): \(HerdrRelease.recommended) or later keeps agent sessions through a restart more reliably.",
                hint: "Run herdr update on \(name), then restart its Herdr server when no agent is in the middle of something."))
        }
        for agent in resumableAgents {
            guard let entry = readiness.agents[agent] else { continue }
            let title = AgentProgram(label: agent).name
            switch entry {
            case .current?:
                findings.append(RestartFinding(id: "integration-\(agent)", isReady: true,
                    text: "\(title): Herdr records its conversations and resumes them after a restart."))
            case .outdated?:
                findings.append(RestartFinding(id: "integration-\(agent)", isReady: false,
                    text: "\(title): Herdr's integration is out of date, so its conversations may not resume after a restart.",
                    fix: .installIntegration(agent)))
            case .missing?:
                findings.append(RestartFinding(id: "integration-\(agent)", isReady: false,
                    text: "\(title): Herdr's integration isn't installed, so its conversations don't resume after a restart.",
                    fix: .installIntegration(agent)))
            case nil:
                continue
            }
        }
        let integrated = readiness.agents.values.contains { $0 != nil && $0 != .some(.missing) }
        if integrated, readiness.hasPython == false {
            findings.append(RestartFinding(id: "python", isReady: false,
                text: "python3 is missing: Herdr's integrations need it to record conversations.",
                hint: "Install python3 on \(name)."))
        }
        if readiness.codexSharesServer == true {
            findings.append(RestartFinding(id: "codex-server", isReady: false,
                text: "Codex runs one shared server for all its sessions, so Herdr may record a conversation on the wrong session, or on none. Turned off, new Codex sessions run on their own once that server stops, as after a restart.",
                fix: .stopCodexSharedServer))
        }
        if readiness.system == "Linux" || readiness.isMac {
            if readiness.startsHerdr(session: machine.session) {
                if readiness.isMac {
                    findings.append(RestartFinding(id: "service", isReady: true,
                        text: "Herdr starts as you log in, and restores its sessions."))
                } else if readiness.lingers == false {
                    findings.append(RestartFinding(id: "service", isReady: false,
                        text: "Herdr starts once you log in, not when the machine starts.",
                        hint: "Run sudo loginctl enable-linger $USER on \(name)."))
                } else {
                    findings.append(RestartFinding(id: "service", isReady: true,
                        text: "Herdr starts with the machine, and restores its sessions."))
                }
            } else {
                findings.append(RestartFinding(id: "service", isReady: false,
                    text: readiness.isMac
                        ? "Herdr doesn't start on its own: after a restart, its sessions come back only once something starts it."
                        : "Herdr doesn't start with the machine: after a restart, its sessions come back only once something starts it.",
                    fix: .startAtBoot(session: machine.session)))
            }
        }
        let unrecorded = sessions.filter(\.isUnrecorded)
        if !unrecorded.isEmpty {
            let names = unrecorded.map(\.name).sorted().prefix(3).joined(separator: ", ")
            let more = unrecorded.count > 3 ? " and \(unrecorded.count - 3) more" : ""
            findings.append(RestartFinding(id: "unrecorded", isReady: false,
                text: "\(unrecorded.count == 1 ? "1 session" : "\(unrecorded.count) sessions") would come back as a shell after a restart, with no conversation to resume: \(names)\(more)."))
        }
        return findings.filter(\.isReady) + findings.filter { !$0.isReady }
    }

    // MARK: Fixing

    static func fixScript(_ fix: RestartFinding.Fix) -> (script: String, arguments: [String]) {
        switch fix {
        case .installIntegration(let agent):
            return ("""
            \(findTool)
            herdr=$(find_tool herdr)
            if [ -z "$herdr" ]; then echo 'Herdr is not on the PATH there.' >&2; exit 127; fi
            "$herdr" integration install "$1"
            """, [agent])
        case .stopCodexSharedServer:
            return ("""
            \(findTool)
            codex=$(find_tool codex)
            if [ -z "$codex" ]; then echo 'Codex is not on the PATH there.' >&2; exit 127; fi
            "$codex" features disable daemon_auto_start
            """, [])
        case .startAtBoot(let session):
            return (startAtBootScript, [session])
        }
    }

    /// Sets up a service that starts the Herdr server of a session as the machine starts, or as
    /// you log in on a Mac. It isn't started now: the server already running stays as it is.
    static let startAtBootScript = """
    \(findTool)
    session=$1
    case $session in '' | *[!A-Za-z0-9._-]*) echo 'That session name is not one Shepherdr can use.' >&2; exit 2 ;; esac
    herdr=$(find_tool herdr)
    if [ -z "$herdr" ]; then echo 'Herdr is not on the PATH there.' >&2; exit 127; fi
    path=
    add_dir() { case ":$path:" in *":$1:"*) ;; *) path="${path:+$path:}$1" ;; esac; }
    for tool in herdr claude codex node python3; do
      found=$(find_tool "$tool")
      if [ -n "$found" ]; then add_dir "$(dirname "$found")"; fi
    done
    for dir in "$HOME/.local/bin" "$HOME/.cargo/bin" /opt/homebrew/bin /usr/local/bin /usr/bin /bin; do
      if [ -d "$dir" ]; then add_dir "$dir"; fi
    done
    case $herdr$path in *'"'* | *'&'* | *'<'* | *'>'* | *'%'*) echo 'Herdr is installed in a folder Shepherdr can not write into a service.' >&2; exit 2 ;; esac
    # Agents in its panes need a UTF-8 locale, which services don't get by themselves.
    lang=${LANG:-C.UTF-8}
    case $lang in *[!A-Za-z0-9._@-]*) lang=C.UTF-8 ;; esac
    case $(uname -s) in
    Linux)
      name="herdr-$session.service"
      mkdir -p "$HOME/.config/systemd/user" || exit 1
      {
        echo '[Unit]'
        echo "Description=Herdr server for the $session session, set up by Shepherdr"
        echo
        echo '[Service]'
        echo "Environment=\\"PATH=$path\\""
        echo "Environment=LANG=$lang"
        if [ "$session" != default ]; then echo "Environment=HERDR_SESSION=$session"; fi
        echo "ExecStart=\\"$herdr\\" server"
        echo 'Restart=on-failure'
        echo 'RestartSec=10'
        echo
        echo '[Install]'
        echo 'WantedBy=default.target'
      } >"$HOME/.config/systemd/user/$name" || exit 1
      systemctl --user daemon-reload && systemctl --user enable "$name" || exit 1
      if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != yes ]; then
        loginctl enable-linger "$(id -un)" 2>/dev/null || echo "Herdr starts once you log in there. To start it with the machine, run sudo loginctl enable-linger $(id -un) there."
      fi
      ;;
    Darwin)
      label="com.theagilemonkeys.shepherdr.herdr-$session"
      mkdir -p "$HOME/Library/LaunchAgents" || exit 1
      file="$HOME/Library/LaunchAgents/$label.plist"
      {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo "<key>Label</key><string>$label</string>"
        echo "<key>ProgramArguments</key><array><string>$herdr</string><string>server</string></array>"
        echo '<key>EnvironmentVariables</key><dict>'
        echo "<key>PATH</key><string>$path</string>"
        echo "<key>LANG</key><string>$lang</string>"
        if [ "$session" != default ]; then echo "<key>HERDR_SESSION</key><string>$session</string>"; fi
        echo '</dict>'
        echo '<key>RunAtLoad</key><true/>'
        echo '</dict></plist>'
      } >"$file" || exit 1
      plutil -lint "$file" >/dev/null || exit 1
      ;;
    *)
      echo 'Shepherdr sets up services on Linux and macOS only.' >&2
      exit 2
      ;;
    esac
    """

    /// Carries out a fix on a machine. Returns what it said worth showing, if anything.
    public static func apply(_ fix: RestartFinding.Fix, on machine: Machine) async throws -> String? {
        let (script, arguments) = fixScript(fix)
        guard let command = machine.shell(script, arguments: arguments) else {
            throw HerdrFailure(.incompatible, "Shepherdr can't reach \(machine.name) over SSH.")
        }
        let output: CommandOutput
        do {
            output = try await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 60)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, "\(machine.name) took too long to answer.")
        }
        guard output.exitCode == 0 else {
            let said = String(decoding: output.stderr.prefix(2_048), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.incompatible, said.isEmpty ? "That didn't work on \(machine.name)." : said)
        }
        let said = String(decoding: output.stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("Herdr starts once") }
        return said.map(String.init)
    }
}
