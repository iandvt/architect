# Public Main Relayer Design

## Goal

Rebuild the fork patch stack so `main` reads like a deliberate public branch instead of a session log. The relayer branch should preserve the current behavior, keep dates recoverable from the existing commits, and expose a clean sequence of product decisions.

## Branch Policy

Use a sandbox branch for all relayer work first:

```text
upstream/main
  |
  v
relayer/public-main-<stamp>
```

Do not move `main` or push rewritten history until the relayer branch has a locked commit map, full verification, and explicit approval.

`origin/main` remains the stable reference until the final handoff. The final update, if approved, should use `git push --force-with-lease` rather than a blind force push.

## Commit Principles

Split by user-facing product decision, not by file or implementation layer.

Each commit must build on its own unless a commit is explicitly documentation-only. Each hotkey removal should be independent and test-backed. Replacement hotkeys should land after removals, so the history clearly shows old affordances being retired before new affordances are added.

The directory chrome removal is one product decision, not multiple file-level commits. Keep it as a single commit even though it touches layout, renderer bounds, UI host data, and documentation.

## Date Policy

When replaying an existing commit, preserve the original author and committer timestamps where possible:

```bash
GIT_AUTHOR_DATE="<old author date>" \
GIT_COMMITTER_DATE="<old committer date>" \
git commit -m "<new title>"
```

For newly split commits that come from an existing mixed commit, use the source commit's date unless a later commit clearly introduced that behavior. For the current directory chrome removal, use the date of the relayer work unless it is intentionally folded into an older removal layer.

## Clean Stack

Target stack:

```text
0de1ade  upstream/main
NEW      chore(project): ignore local agent worktrees
NEW      feat(app): add Stable/Scratch named sessions
NEW      chore(input): remove command-return grid expand shortcut
NEW      chore(input): remove command-arrow grid navigation shortcut
NEW      chore(input): remove command-digit slot shortcuts
NEW      chore(input): remove command-k terminal clear shortcut
NEW      chore(input): remove command-o recent folders shortcut
NEW      chore(input): remove command-d diff shortcut
NEW      chore(input): remove command-r reader shortcut
NEW      feat(input): add command-g grid toggle shortcut
NEW      feat(input): add plain arrow grid navigation
NEW      feat(input): add enter grid expand
NEW      feat(input): add command-shift-r reader shortcut
NEW      feat(ui): add command-t remote terminal overlay
NEW      feat(app): add command-shift-s saved session picker
NEW      fix(ui): polish saved session picker rows
NEW      chore(ui): remove grid directory chrome
NEW      chore(packaging): publish bundles by branch
```

## Commit Boundaries

### 1. `chore(project): ignore local agent worktrees`

Scope:

- Add `.claude/worktrees/` to `.gitignore`.

Do not include Worktrunk usage instructions here. Worktrunk is installed globally and should not be part of the public fork story.

### 2. `feat(app): add Stable/Scratch named sessions`

Scope:

- Add named app channels and sessions.
- Add `--instance` and `--session` launch handling.
- Add per-channel session persistence and display metadata.
- Add startup restore for terminal working directories and manual agent resume prefill.
- Add `FORK.md` with fork identity, branch roles, validation flow, and session policy.

Exclude:

- Shortcut removals.
- Removed reader or directory chrome.
- VS Code pairing notes.
- Packaging publish policy beyond what is needed for the session behavior.

### 3. Removed Hotkey Commits

Each removed shortcut gets one commit:

```text
chore(input): remove command-return grid expand shortcut
chore(input): remove command-arrow grid navigation shortcut
chore(input): remove command-digit slot shortcuts
chore(input): remove command-k terminal clear shortcut
chore(input): remove command-o recent folders shortcut
chore(input): remove command-d diff shortcut
chore(input): remove command-r reader shortcut
```

Each commit should include:

- Input/runtime change.
- Focused input test.
- Help overlay or documentation update if the shortcut was visible.

Each commit should exclude replacement shortcut behavior.

### 4. Added Hotkey Commits

Add the preferred shortcuts after the removals:

```text
feat(input): add command-g grid toggle shortcut
feat(input): add plain arrow grid navigation
feat(input): add enter grid expand
feat(input): add command-shift-r reader shortcut
```

Each commit should include:

- Input predicate or runtime behavior.
- Focused test.
- Help overlay or user documentation update when visible.

### 5. `feat(ui): add command-t remote terminal overlay`

Scope:

- Add the remote terminal overlay.
- Add its runtime state.
- Add `command-t` as its primary entry point.
- Add tests for overlay input ownership and scroll behavior.
- Update README and architecture documentation.

Keep this as one feature commit because `command-t` is the overlay's primary entry point.

### 6. `feat(app): add command-shift-s saved session picker`

Scope:

- Add saved session picker UI.
- Add saved-session listing and relaunch behavior.
- Add `command-shift-s` as the picker entry point.
- Add tests for picker open, search, selection, and launch action.
- Update README, configuration, architecture, and development documentation.

Keep picker polish separate.

### 7. `fix(ui): polish saved session picker rows`

Scope:

- Keep emoji rendering separate from row labels.
- Cap emoji size.
- Show the current session as disabled.
- Prevent opening the current session from itself.
- Add tests for row label text, emoji size, skipped keyboard selection, and disabled click behavior.

### 8. `chore(ui): remove grid directory chrome`

Scope:

- Remove the grid cwd bar component and metrics.
- Stop reserving grid height for directory chrome.
- Stop reducing renderer draw bounds for the removed bar.
- Remove per-session directory display fields from `SessionUiInfo`.
- Keep underlying working directory tracking for persistence, remote terminal, MCP spawning, and focused-cwd workflows.
- Update README and architecture documentation.

This should stay one commit.

### 9. `chore(packaging): publish bundles by branch`

Scope:

- Add or revise branch-aware app publishing.
- Keep Stable publishing tied to `main`.
- Keep Scratch publishing tied to `scratch`.
- Update Makefile, release script, formula, and development documentation.

This belongs after the public product surface is shaped.

## Source Commit Map

Use this map as the first pass when replaying:

```text
e178fd1 -> chore(project): ignore local agent worktrees
436c6da -> feat(app): add Stable/Scratch named sessions
436c6da/e4cf343 -> removed hotkey commits
436c6da/e4cf343 -> added hotkey commits
81469b9 -> feat(ui): add command-t remote terminal overlay
29f1de7 -> feat(app): add command-shift-s saved session picker
b063d4d -> fix(ui): polish saved session picker rows
working tree -> chore(ui): remove grid directory chrome
e92eafb -> chore(packaging): publish bundles by branch
```

Some commits are intentionally split because the existing history mixes app sessions, shortcut policy, and documentation updates.

## Verification Gates

After each relayer checkpoint:

```bash
zig fmt src/
git diff --check
```

After the full stack:

```bash
. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk.log
mise x zig@0.15.2 -- zig build test --summary all
mise x zig@0.15.2 -- zig build --summary all
mise x zig@0.15.2 just@1.51.0 ruff@0.15.13 shellcheck@0.11.0 node@24 -- just lint
git diff --check
```

Before updating `main`, produce:

- Old commit to new commit map.
- Final `git log --oneline --decorate --graph`.
- Final verification output summary.
- Explicit list of any behavior that changed during relayer work.

## Open Decisions

Resolve these before execution:

- Whether `FORK.md` should include only current policy or also future editor pairing notes.
- Whether command-t remote terminal overlay should be one feature commit or split into overlay core plus shortcut entry point.
- Whether packaging should be last, as proposed, or earlier to support app-bundle validation during intermediate commits.
- Whether to preserve committer dates exactly for all replayed commits or preserve only author dates.
