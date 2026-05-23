# Architect

[![Build status](https://github.com/forketyfork/architect/actions/workflows/build.yml/badge.svg)](https://github.com/forketyfork/architect/actions/workflows/build.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/language-Zig-orange.svg)](https://ziglang.org/)

https://github.com/user-attachments/assets/a4e28a63-557a-44f3-9bae-47b2fd0a5dc6

A terminal built for multi-agent AI coding workflows. Run Claude Code, Codex, or Gemini in parallel and see at a glance which agents need your attention. See more in [my article](https://forketyfork.github.io/blog/2026/01/21/running-4-ai-coding-agents-at-once-the-terminal-i-built-to-keep-up/).

Built on [ghostty-vt](https://github.com/ghostty-org/ghostty) for terminal emulation and SDL3 for rendering.

## Why Architect?

Running multiple AI coding agents is the new normal. But existing terminals weren't built for this:

- **Agents sit idle** waiting for approval while you're focused elsewhere
- **Context switching** between tmux panes or tabs kills your flow
- **No visibility** into which agent needs attention right now

Architect solves this with a grid view that keeps all your agents visible, with **status-aware highlighting** that shows you instantly when an agent is awaiting approval or has completed its task.

> [!WARNING]
> **This project is in the early stages of development. Use at your own risk.**
>
> The application is experimental and may have bugs, stability issues, or unexpected behavior.

## Features

### Agent-Focused
- **Status highlights** — agents glow when awaiting approval or done, so you never miss a prompt
- **Named sessions** — app bundles run as Stable or Scratch channels; each launch gets a named session such as `Stable / 🦦 Happy Otter`; reopen that session by name to restore terminal working directories and pre-fill saved agent resume commands for manual restart
- **Dynamic grid** — starts with a single terminal in full view; press ⌘N to add a terminal after the current one, and closing terminals compacts the grid forward
- **Grid view** — keep all agents visible simultaneously, expand any one to full screen
- **Worktree picker** (⌘T) — quickly `cd` into git worktrees for parallel agent work on separate branches; new worktrees are created outside the repository tree (configurable via `[worktree]` in `config.toml`) with automatic post-create initialization
- **Diff review comments** — click diff lines in the ⌘D overlay to leave inline comments with multiline wrapping, then send them all to a running agent (or start one) with the "Send to agent" button
- **Story viewer** — inside an Architect terminal, run `architect story <filename>` to open a scrollable overlay that renders PR story files with prose text and diff-colored code blocks
- **MCP session spawning** — run `architect-mcp` from an MCP client to ask the running Architect app to create a terminal session in a requested working directory
- **Reader mode** (⌘R) — open a centered markdown reader for the selected terminal's history (works in full view and grid) with live updates, bottom pinning, incremental search (⌘F, Enter/Shift+Enter), markdown tables with inline cell styling (bold/italic/code/links/strikethrough), task checkboxes (emoji), clickable links, shared draggable scrollbar, and left-to-right gradient separators before command prompts (OSC 133 + fallback heuristics)

### Terminal Essentials
- Smooth animated transitions for grid expansion, contraction, and reflow (cells and borders move/resize together)
- Wakeable idle input handling keeps typing responsive after short idle periods instead of waiting on a fixed sleep window
- Keyboard navigation: ⌘Arrow to move between slots from full view, ⌘N to add, ⌘W to close a terminal (restarts if it's the only terminal), ⌘T for worktrees, ⌘D for repository-wide git diff (staged + unstaged + untracked), ⌘R for reader mode, ⌘/ for shortcuts; quit with ⌘Q or the window close button
- Git diff overlay title shows the repository root folder being diffed
- Per-cell cwd bar in grid view reserves space, and terminal dimensions track grid/full mode so content wraps inside the visible area
- Scrollback with trackpad/wheel support and an auto-hiding draggable scrollbar in terminal views
- OSC 8 hyperlink support (Cmd+Click to open)
- Replies to OSC 4/10/11 color queries using the live terminal palette/default colors so Codex and similar CLIs do not stall on startup probes
- Kitty keyboard protocol for enhanced key handling
- Persistent window state and font size within each named session

## Installation

### Download Pre-built Binary (macOS)

This fork has not published Stable/Scratch release archives yet. Use the source build or HEAD-only Homebrew flow below for the forked app names.

Upstream release archives are available from the [forketyfork releases page](https://github.com/forketyfork/architect/releases), but those artifacts track upstream packaging rather than this fork's unreleased Stable/Scratch bundle flow.

### Homebrew (macOS)

**Prerequisites**: Xcode Command Line Tools must be installed:
```bash
xcode-select --install
```

Install this fork's HEAD-only formula from its tap:
```bash
brew tap iandvt/architect https://github.com/iandvt/architect
brew install --HEAD iandvt/architect/architect

# Copy the apps to your Applications folder
cp -r "$(brew --prefix)/opt/architect/Architect (Stable).app" /Applications/
cp -r "$(brew --prefix)/opt/architect/Architect (Scratch).app" /Applications/

# MCP clients can use the helper on PATH
architect-mcp
```

From a local checkout, prefer the source app targets because Homebrew expects external formulae to live in a tap:
```bash
make publish-apps            # run from main for Stable, scratch for Scratch
make stable
```

### Build from Source

See [`docs/development.md`](docs/development.md) for the full development setup. Quick start:
```bash
nix develop
just build
```

Source builds install both executables under `zig-out/bin/`: `architect` and `architect-mcp`.

For local macOS app bundle launches from this checkout:
```bash
make publish-apps            # branch-aware publish: main -> Stable, scratch -> Scratch
make stable                  # new Stable session from /Applications
make stable SESSION=HappyOtter
make scratch                 # new Scratch session from /Applications
make sessions                # list saved named sessions
```

## Hooks

To add hooks for Claude Code, Codex or Gemini, use the injected `architect` helper available inside Architect terminals:
```bash
architect hook claude
architect hook codex
architect hook gemini
```

The built `architect` app binary accepts launch flags such as `--instance` and `--session`. It does not provide the `hook`, `notify`, or `story` helper subcommands unless you are inside an Architect-managed terminal where the injected helper is first on `PATH`.

## MCP

`architect-mcp` is a stdio MCP server for local clients. It exposes one tool, `spawn_session`, which forwards the request to the running Architect app. It does not launch Architect by itself.

`spawn_session` arguments:
```json
{
  "cwd": "/absolute/path/to/worktree",
  "command": "codex",
  "display_name": "Issue 291"
}
```

`cwd` is required. `command` and `display_name` are optional. On success, the tool returns structured content with `status`, `session_id`, and `slot_index`. If Architect is not running, the grid is full, `cwd` is invalid, or spawning fails, the tool returns an MCP tool error with a stable `code` and `message`.

Source builds place the helper at `zig-out/bin/architect-mcp`. Release app bundles omit it by default. For Homebrew installs, `architect-mcp` is installed on `PATH`.

## Configuration

Architect stores configuration in `~/.config/architect/`:

* `config.toml`: read-only user preferences (edit via `⌘,`).
* `instances/<channel>/<session>/persistence.toml`: runtime state (window position/size, font size, terminal cwds), managed automatically.
* `instances/<channel>/<session>/instance.toml`: display metadata for named sessions.

Common settings include font family, theme colors, grid font scale, and logging minimum severity (`[logging].min_level`). On macOS, structured app logs are written to `~/Library/Logs/Architect/` with size-based rotation at 10 MiB, including startup/shutdown markers and grid/full view transition events at `INFO`. The grid size is dynamic and adapts to the number of terminals. Remove the files to reset to the default values.

## Troubleshooting

* **App won't open (Gatekeeper)**: run `xattr -dr com.apple.quarantine "Architect (Stable).app" "Architect (Scratch).app"` after extracting the release.
* **Font not found**: ensure the font is installed and set `font.family` in `config.toml`. The app falls back to `SFNSMono` on macOS.
* **Missing symbol glyphs**: fallbacks try the bundled Symbols Nerd Font, then `Arial Unicode MS`, then `STIXTwoMath` (if available) before emoji.
* **Emoji alignment**: single-codepoint emoji are centered using glyph metrics; if they appear off, try a different primary font or font size.
* **Reset configuration**: delete `~/.config/architect/config.toml` and `~/.config/architect/instances/`.
* **Crash after closing a terminal**: update to the latest build; older builds could crash after terminal close events on macOS.
* **Known limitations**: emoji fallback is macOS-only; keybindings are currently fixed.

## Documentation

* [`docs/ai-integration.md`](docs/ai-integration.md): set up Claude Code, Codex, and Gemini CLI hooks for status notifications, plus the `architect-mcp` `spawn_session` interface.
* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): architecture overview and system boundaries.
* [`docs/configuration.md`](docs/configuration.md): detailed configuration reference for `config.toml` and `persistence.toml`.
* [`docs/development.md`](docs/development.md): build, test, and release process.
* [`CLAUDE.md`](CLAUDE.md): agent guidelines for code assistants.

## Related Tools

Architect is part of a suite of tools I'm building for AI-assisted development:

- [**Stepcat**](https://github.com/forketyfork/stepcat) — Multi-step agent orchestration with Claude Code and Codex
- [**Marx**](https://github.com/forketyfork/marx) — Run Claude, Codex, and Gemini in parallel for PR code review
- [**Claude Nein**](https://github.com/forketyfork/claude-nein) — macOS menu bar app to monitor Claude Code spending

## License

MIT
