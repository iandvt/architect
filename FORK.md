# Fork Notes

This fork tracks `forketyfork/architect` while carrying local workflow changes for a
Stable/Scratch multi-agent desktop setup.

## Branch Model

- `main`: stable fork base. Build and publish the Stable app bundle from here.
- `scratch`: agent work branch. Build and publish the Scratch app bundle from here.
- `upstream`: local branch synced from `forketyfork/architect` `main`.

Branch names are git workflow roles. Stable and Scratch are runtime channel names
derived from app bundle names; they do not imply that the app is currently running
from a branch with the same name.

The upstream sync flow is intentionally not locked in yet. Keep fork changes easy to
inspect, rebase, cherry-pick, or drop while that policy is still open.

## Application Shape

- Build two macOS apps from the same branch:
  - `Architect (Stable).app`
  - `Architect (Scratch).app`
- App bundle names infer the Architect channel. Direct binary launches should pass
  `--instance <channel>`.
- Stable and Scratch sessions are separated under:

```text
~/.config/architect/
  instances/
    Stable/
      HappyOtter/
        persistence.toml
        instance.toml
    Scratch/
      BoldBadger/
        persistence.toml
        instance.toml
```

- Window titles include the channel and generated session display name, for example
  `Architect - Stable / 🦦 Happy Otter`.
- Session names come from the built-in emoji-backed cute-name pool. The canonical ID
  is compact, for example `HappyOtter`; the display name keeps spaces and emoji.
- Restore only terminal working directories and saved agent session metadata. Do not
  restore terminal scrollback or terminal history.
- Reopen pre-fills the matching agent resume command in the terminal. It must not press
  Enter or auto-run the resume command.

## Validation

Before asking for visual validation or committing this fork base, rebuild and
publish the app bundle from the matching branch, then exercise the installed
channel:

```bash
git switch main
make publish-apps
make stable
make stable SESSION=<SessionId>

git switch scratch
make publish-apps
make scratch
make scratch SESSION=<SessionId>

make sessions
```

Confirm that Stable and Scratch create separate directories under
`~/.config/architect/instances/`, that each title bar includes the channel and named
session, and that restored agent resume commands are prefilled but not executed.

## Keyboard Policy

Keep the shortcut surface small and hardcoded.

Remaining global shortcuts:

- `Cmd+G`: toggle grid/full view. Pressing it again from grid expands the active tile.
- Arrow keys in grid: move active tile.
- `Enter` in grid: expand active tile.
- `Cmd+Arrow` in full view: move between slots.
- `Cmd+N`: create a terminal after the current one.
- `Cmd+W`: close a terminal, or restart the only terminal.
- `Cmd+Q`: quit.
- `Cmd+Shift+R`: reader mode.
- `Cmd+T`: remote terminal overlay.
- `Cmd+/`: help.
- `Cmd+,`: open config.
- `Cmd+C` / `Cmd+V`: copy and paste.
- `Cmd+Shift++` / `Cmd+-`: font size.

Removed or intentionally hidden:

- `Cmd+Return` in grid. Plain `Enter` owns that behavior.
- `Cmd+Arrow` in grid. Plain arrows own grid movement.
- `Cmd+K`. It clears terminals and is too easy to hit accidentally.
- `Cmd+1` through `Cmd+0`. Slot jumps are not needed here.
- `Cmd+O`. Recent folder launching is not a primary fork workflow.
- `Cmd+R`. Reader mode uses `Cmd+Shift+R` to avoid the common refresh binding.
- `Cmd+D`. The diff overlay can still exist, but no global launch hotkey.

## MCP Helper

`architect-mcp` is useful when an MCP client needs to ask a running Architect app to
spawn a terminal in a specific working directory. Keep the helper built from source,
but omit it from release app bundles by default. Use the bundle script's `--with-mcp`
option only when a bundle should carry it.

This keeps the MCP surface available without making it part of the default Stable and
Scratch app experience.

## Rebase Rules

- Keep fork-specific runtime glue in focused modules when practical.
- Avoid growing `src/app/runtime.zig` for behavior that can live in `runtime_instance.zig`,
  `grid_nav.zig`, or another narrow helper module.
- Prefer pure helpers with tests for name generation, persistence shaping, and shortcut
  mapping.
- Keep bundle and release deltas in scripts, `build.zig`, and release documentation.
- Update user-facing documentation in the same change as code behavior.
- Do not add dependencies for fork convenience without a specific review.

## Open Nits

- Upstream sync policy is undecided. After `main` tracks `upstream`, decide whether each
  fork change is rebased, cherry-picked, or rebuilt.
- The Stable base should stay boring: two apps, no session auto-run restore, named
  sessions, and the trimmed shortcut set.
- Scratch can carry new experiments, but main should stay easy to rebuild and validate.
- Watch `runtime.zig` closely during rebases. Any new fork-specific logic added there
  should be a candidate for extraction.
- The MCP helper stays disabled-by-default for bundles until it proves necessary.

## Editor Pairing

Architect should treat VS Code as a paired editor, not as a generic desktop window.
The stable target identity is the Architect named session:

```text
editor_session_id = <channel>/<session_id>
```

Examples:

```text
Stable/HappyOtter
Scratch/BoldBadger
```

Do not target VS Code by process id as the primary contract. The `code` CLI process
can exit after forwarding a request to an already-running VS Code instance, and the
real editor process tree is an implementation detail. Do not target only by macOS
window title either; titles are user-visible and change with workspace state. The
session id should target the editor instance. The active grid slot should target the
workspace opened inside that editor instance.

```text
editor_session_id = Stable/HappyOtter
active_slot       = 2
active_workspace  = /Users/iand/GitHub/iandvt/architect-scratch
```

The first implementation should launch one VS Code instance per Architect named
session with a dedicated user-data directory:

```bash
code --new-window \
  --user-data-dir ~/.config/architect/editor-sessions/Stable/HappyOtter/vscode-user-data \
  --profile "Architect Stable HappyOtter" \
  /Users/iand/GitHub/iandvt/architect
```

Subsequent active-slot changes should reuse the same isolated VS Code instance:

```bash
code --reuse-window \
  --user-data-dir ~/.config/architect/editor-sessions/Stable/HappyOtter/vscode-user-data \
  --profile "Architect Stable HappyOtter" \
  /Users/iand/GitHub/iandvt/architect-scratch
```

This makes the `--user-data-dir` path the practical routing key. It is the closest
thing VS Code exposes to an external session target. The profile name is for human
orientation and should not be treated as a unique target.

Persist the pairing next to the named session:

```text
~/.config/architect/
  instances/
    Stable/
      HappyOtter/
        persistence.toml
        instance.toml
        editor.toml
```

`editor.toml` should store:

```toml
[vscode]
enabled = false
command = "code"
user_data_dir = "~/.config/architect/editor-sessions/Stable/HappyOtter/vscode-user-data"
profile = "Architect Stable HappyOtter"
last_workspace = "/Users/iand/GitHub/iandvt/architect"
last_slot = 0
```

Architect should own only three editor actions at first:

1. Open the paired editor for the named Architect session.
2. Reuse that paired editor when the active grid slot changes.
3. Record the last workspace and slot so relaunching the Architect session can
   re-pair the editor predictably.

Window placement is a separate layer. Keeping Architect on the left and VS Code on
the right probably requires macOS Accessibility or AppleScript automation, and that
should be optional because it needs user permissions and will be more brittle than
the CLI-based editor pairing.

Deep VS Code control should wait for a small VS Code extension or local bridge. A
bridge can report that the expected `editor_session_id` is alive and can run
in-window commands, but opening a new folder in the same window restarts the VS Code
extension host. The CLI-only version is good enough for opening and switching
workspaces; the extension version is for acknowledgements, richer commands, and
recovery when targeting becomes ambiguous.

The fallback behavior should be conservative:

- If the configured `code` command is missing, show a toast and do nothing.
- If VS Code is not running for the session, launch it with `--new-window`.
- If VS Code is already running for the session, send `--reuse-window` with the
  active slot's cwd or worktree path.
- If the active slot has no cwd yet, keep the previous editor workspace.
- If the user manually opens more VS Code windows under the same `user_data_dir`,
  targeting becomes best-effort until the bridge exists.

```text
+---------------------------+---------------------------+
|         Architect         |          VS Code          |
+-------------+-------------+                           |
|  claude     |  codex      |                           |
|  code       |             |    workspace: ~/project   |
+-------------+-------------+    branch: active-agent   |
|  gemini     |  copilot    |                           |
|  cli        |             |                           |
+-------------+-------------+---------------------------+
```

Each cell is one agent session (Claude Code, Codex, Gemini CLI, Copilot, or any
terminal-based coding agent). Optionally a cell can pop open a secondary terminal
(tmux-style split) for build output, logs, or manual commands alongside the agent.
