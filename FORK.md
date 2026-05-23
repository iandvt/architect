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

Keep the shortcut surface small and hardcoded. Update this section in the same commit
as any shortcut behavior change.

Current global shortcuts:

- `Cmd+Arrow`: move between slots in full view.
- `Cmd+T`: open the worktree picker.
- `Cmd+D`: open the git diff overlay.
- `Cmd+R`: reader mode.
- `Cmd+N`: create a terminal after the current one.
- `Cmd+W`: close a terminal, or restart the only terminal.
- `Cmd+Q`: quit.
- `Cmd+/`: help.
- `Cmd+,`: open config.
- `Cmd+C` / `Cmd+V`: copy and paste.
- `Cmd+Shift++` / `Cmd+-`: font size.

Retired shortcuts:

- `Cmd+Return` in grid. Grid expansion will get a simpler replacement.
- `Cmd+Arrow` in grid. Plain arrows will own grid movement.
- `Cmd+1` through `Cmd+0`. Slot jumps are not needed here.
- `Cmd+K`. It clears terminals and is too easy to hit accidentally.
- `Cmd+O`. Recent folder launching is not a primary fork workflow.

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
  sessions, and a deliberately small shortcut set.
- Scratch can carry new experiments, but main should stay easy to rebuild and validate.
- Watch `runtime.zig` closely during rebases. Any new fork-specific logic added there
  should be a candidate for extraction.
- The MCP helper stays disabled-by-default for bundles until it proves necessary.
