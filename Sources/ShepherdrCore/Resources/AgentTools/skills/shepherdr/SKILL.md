---
name: shepherdr
description: "Start agent sessions on this machine or on other machines in the user's Shepherdr network and wait for them; when the user asks, hand results back to the session coordinating you or close sessions; open pages and files in your session's browser in Shepherdr, pin links or notify the user. Use when the user asks to create, start or launch a session or agent on a machine or server by name, to hand off or report back to a coordinating session, to wait for another session, to close a session, this one included, or to open, show or preview a page or a file in Shepherdr or its browser. Requires HERDR_ENV=1. Whenever you mention a file, write its path relative to your working folder, such as src/api/cache.ts:42, never a bare file name or a shortened path: Shepherdr turns those paths into links."
---

# Shepherdr

Shepherdr is the user's Mac app for the Herdr sessions on all their machines. Its command line, `~/.shepherdr/bin/shepherdr`, starts sessions that Shepherdr links to yours, and, when the user asks, sends work back to the session that coordinates you.

It never connects to the user's Mac. It writes letters in `~/.shepherdr/outbox` on this machine, and Shepherdr collects them within seconds while it is open. If Shepherdr is closed, they wait there.

Check that you run inside Herdr first:

```bash
test "${HERDR_ENV:-}" = 1
```

Outside Herdr, Shepherdr can't tell which session you are. Only `handoff --to`, `notify` and `spawn` without links work there.

## Machines

Before you use a machine name, run:

```bash
~/.shepherdr/bin/shepherdr machines
```

It says which machine you are on and how each of the others is reached. Never guess names.

- Route `here` or `direct`: `spawn` starts the session right away.
- Route `shepherdr`: this machine can't reach it. `spawn` files a request that the user approves in Shepherdr. Tell the user it is waiting for their approval.

## Start a session

```bash
~/.shepherdr/bin/shepherdr spawn --machine buildbox --cwd ~/src/api --name api-fix \
  --prompt "Fix the failing API test."
```

- Leave out `--machine` for this machine. `--split right` or `--split down` opens it beside your pane instead of in a new workspace (this machine only).
- `--cwd` defaults to your folder here, and to the home folder elsewhere. `shepherdr folders --machine NAME` lists the folders where sessions already work.
- `--kind claude|codex|…` defaults to your own agent. `--shell` starts a plain shell, only when the user asks for one: run builds, tests and scripts yourself, with your own tools, so their output comes back to you and no session is left behind.
- `--name` is the new agent's Herdr name: a lowercase letter, then lowercase letters, digits, `-` or `_`. It is made up from the folder if you leave it out.
- Starting sessions fans out from yours: Shepherdr nests each new one under yours and keeps yours on hold until they finish. Add `--no-wait` only when the user asks for a session that isn't linked to yours.
- Don't ask it in the prompt to hand off or close when it finishes: the user decides when a session hands off.
- If the agent stops at a startup question, such as trusting the folder, Shepherdr sends your prompt once the user answers it.

To follow it from here, use Herdr with the agent name: `herdr agent read NAME`, or `herdr --machine PROFILE agent read NAME` on another machine. `spawn` prints which.

## Hand work back

Hand off only when the user asks you to, or when Shepherdr asks you to for them. A handoff wraps up your work for the session waiting for you:

```bash
~/.shepherdr/bin/shepherdr handoff --file REPORT.md "Opened theam/api#41. The flaky test was a race in the cache; tests pass."
```

- It goes to the session waiting for you. `--to NAME` picks another session by its agent or workspace name; add `@machine` when two machines have one with that name.
- Shepherdr delivers it as a prompt once that session is free. When it comes from another machine, the user may approve it first.
- Write the message so it stands alone: what you did, the results, links, and what is left.
- `--file` attaches files, up to 5 MB in all. `--message-file FILE` takes the message from a file, and `-` from standard input.

## Wait and resume

```bash
~/.shepherdr/bin/shepherdr wait-for reviewer tester
~/.shepherdr/bin/shepherdr resume
```

`wait-for` puts your session on hold until those sessions finish. `resume` takes it off hold, or stops waiting for the sessions you name.

## Close sessions

Close a session only when the user asks you to. Shepherdr then shows the user a close request, and the session ends only when they press **CLOSE**. Closing ends its Herdr pane and the agent in it, and nothing in it can be recovered.

```bash
~/.shepherdr/bin/shepherdr close
~/.shepherdr/bin/shepherdr close reviewer tester@buildbox
```

- With no name, it asks to close your own session. Once the user confirms, it closes after you finish this turn.
- With names, it asks to close those sessions, by agent or workspace name like `handoff --to`. Shepherdr doesn't ask about a session that is working or waiting for the user, and shows you why; add `--force` only when the user asked to close it anyway.
- When the user asks you to hand off and close, run `handoff` first, then `close`.

## Pages, files and notices

```bash
~/.shepherdr/bin/shepherdr open http://localhost:3000
~/.shepherdr/bin/shepherdr open coverage/index.html
~/.shepherdr/bin/shepherdr pin https://github.com/theam/api/pull/41 --title "Cache race fix"
~/.shepherdr/bin/shepherdr notify "Migration finished: 1,204 rows moved."
```

- `open` opens a page or a file in your session's browser in Shepherdr, beside your terminal. Use it when the user asks you to open, show or preview something there. It renders Markdown, and shows HTML, pictures, PDFs and text.
  - On the user's Mac, the file itself opens, with the pictures and pages beside it.
  - From another machine, Shepherdr opens a copy of the file, up to 5 MB, once the user lets it: files beside it don't come along. A page there only gets suggested, and `localhost` means the user's Mac, not this machine.
- `pin` adds a link to your session's resources in Shepherdr.
- `notify` shows the user a notification.

`pin` takes only http and https links; `open` takes those or a file's path.

## Files you mention

Shepherdr turns the file paths in your answers into links the user clicks to open the file. It finds a file only by the path you write, relative to your working folder:

- Write `src/api/cache.ts` or `src/api/cache.ts:42`, never just `cache.ts` or a path cut short such as `…/cache.ts`.
- For a file outside your working folder, write its absolute path, or one from `~`.
- Write the path itself, not a Markdown link that shows other text.

## When something fails

- `shepherdr status` shows this machine, your pane and the letters Shepherdr hasn't collected yet.
- A machine name that isn't in the list fails with the names that are. Pick one or ask the user.
- `shepherdr help` lists every option.
