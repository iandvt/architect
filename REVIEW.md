# Review

This is the five agent merge readiness review for the current fork base. The goal is
to make the Stable and Scratch application work mergeable before starting the next
round of VS Code management experiments.

## Verdict

The blocking review items have been addressed in the merge cleanup. The runtime and
session work did not receive a functional stop-ship finding, and the branch should
be treated as mergeable if the verification checklist at the end of this file passes.
The remaining runtime notes below are follow-up risks, not blockers for the local
Stable and Scratch fork base.

## Agent 1: Merge Surface

The overall patch is coherent for a fork base. The new `FORK.md` and `Makefile` are
intentional fork workflow files, not accidental top-level churn. `FORK.md` explains
the branch model, Stable and Scratch channels, shortcut policy, MCP helper posture,
and rebase rules. `Makefile` gives repeatable local commands for building and
launching the app bundles.

The staged surface is large enough to deserve one careful merge commit. At the time
of review it covered 32 files, with 1,766 insertions and 766 deletions. The main
change clusters are named sessions, app bundle packaging, keyboard trim, runtime
extraction, configuration persistence, and fork documentation. That is broad, but it
is one product-level change: turn this checkout into a Stable and Scratch fork base.

The review found no merge organization blocker. The `FORK.md` desk layout edit is
part of the fork note and should be included with the staged documentation.

## Agent 2: Runtime And Sessions

The runtime and session behavior has no immediate functional blocker. The important
shape is sound: app bundle names infer the channel, direct binary launches take
`--instance`, sessions are stored under `instances/<channel>/<session>/`, restore
brings back terminal working directories, and agent resume commands are prefilled
without being executed.

There are four follow-up risks to keep visible.

First, restore failure handling can overwrite saved state. Startup sizes the grid
from restored entries, then always spawns slot 0 and syncs live sessions back to
persistence. If a persisted working directory is missing or temporarily unavailable,
the fallback working directory can replace the saved value on the first save.

Second, session path names are lossy. `pathComponentForName` collapses distinct
inputs into the same directory component. That is acceptable for the built-in cute
names, but user-provided channel or session names can collide unless the code moves
to reversible escaping or stricter validation.

Third, generated session names are not atomically reserved. Two concurrent launches
can choose the same free name, and the suffix fallback is not collision checked.
This is low risk for normal interactive use, but it is worth fixing before treating
named sessions as a public API.

Fourth, restored agent metadata is retained as captured metadata. That preserves
manual resume behavior, but it can also keep stale agent IDs if the user never
resumes the agent or if prefill fails. This should either be documented as retention
behavior or tightened later.

These are not reasons to block the local fork base. They are reasons to avoid calling
session persistence complete beyond the current lightweight reopen workflow.

## Agent 3: Build, Release, And Packaging

The release shape is mostly aligned. The GitHub release workflow now packages
`Architect (Stable).app` and `Architect (Scratch).app`. The bundle script accepts an
explicit `--app-name`, derives distinct bundle identifiers, and omits
`architect-mcp` unless requested. The Homebrew formula now installs both app
bundles and keeps `architect-mcp` on `PATH`.

The Homebrew style blocker was dependency order. `depends_on xcode: :build` must be
ordered before `depends_on "zig@0.15" => :build`, and the formula now follows that
order.

There is also one packaging follow-up. The Makefile sources
`scripts/setup-macos-sdk-workaround.sh` before release builds, but the Homebrew
formula runs plain `zig build`. If the formula must work on affected Command Line
Tools SDK hosts, either source the workaround there or document that the formula
expects a safe selected SDK.

Packaging evidence from the review was otherwise good: Ruby syntax passed, release
YAML parsed, shell syntax checks passed, shellcheck passed for the touched scripts,
the SDK workaround test passed, and temporary Stable and Scratch bundles produced
valid plist files with distinct bundle identifiers. The default bundles contained
`architect` and omitted `architect-mcp`, which matches the intended policy.

## Agent 4: Documentation And Workflow

The user-facing documentation mostly explains the new workflow. `README.md`,
`docs/development.md`, `docs/configuration.md`, and `FORK.md` describe Stable and
Scratch, named session storage, restore commands, app bundle behavior, and the
Makefile launch helpers.

The documentation blocker was stale agent guidance. `CLAUDE.md` now uses
`zig build run -- --instance Dev`, keeps `just run` as the short path, and points
bundle validation at `make apps stable scratch`.

The lower-risk documentation nits are also resolved. `README.md` now says window
state and font size persist within each named session. `FORK.md` separates git branch
roles from runtime channel names and includes a Stable and Scratch validation
checklist.

## Agent 5: Upstream Rebase Risk

The rebase risk is moderate because the patch touches core runtime, persistence,
input mapping, packaging, and documentation. The work is still more rebase-friendly
than it was before the extraction. Fork-specific runtime behavior now lives mostly in
`src/cli.zig` and `src/app/runtime_instance.zig`, while shared grid behavior moved
into `src/app/grid_nav.zig`.

The likely conflict hotspots are:

- `src/app/runtime.zig`
- `src/config.zig`
- `src/input/mapper.zig`
- `scripts/bundle-macos.sh`
- `.github/workflows/release.yaml`
- `Formula/architect.rb`
- documentation around shortcuts and persistence

Before rebasing onto `forketyfork/architect` `main`, fetch upstream and check whether
those files changed. If upstream touched runtime loop structure, persistence shape,
key mapping, release packaging, Homebrew formula, or shortcut documentation, rebase
with extra scrutiny. Also decide whether the current local commit that puts `main`
ahead of `origin/main` is part of the fork stack or should be separated from this
merge.

## Merge Verification

Run this verification set before the merge commit:

```bash
git diff --check
git diff --cached --check
brew style Formula/architect.rb
ruby -c Formula/architect.rb
bash -n scripts/bundle-macos.sh scripts/test-macos-sdk-workaround.sh
sh -n scripts/setup-macos-sdk-workaround.sh
shellcheck scripts/bundle-macos.sh scripts/setup-macos-sdk-workaround.sh scripts/test-macos-sdk-workaround.sh
bash scripts/test-macos-sdk-workaround.sh
. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && mise exec zig@0.15.2 -- zig build
. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && mise exec zig@0.15.2 -- zig build test
. ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && mise exec zig@0.15.2 just@1.51.0 ruff@0.15.13 -- just lint
make apps
make stable
make scratch
make sessions
```

For `make stable` and `make scratch`, visual validation is still human-assisted:
confirm the title bar includes the channel and named session, confirm the grid opens
correctly, then restore one session with `make stable SESSION=<SessionId>` or
`make scratch SESSION=<SessionId>`.
