# Development

This document covers local setup, build/test commands, and release steps.

## Prerequisites

- Nix with flakes enabled
- macOS: Xcode Command Line Tools if you plan to use Homebrew dependencies

## Setup

1. (Optional) Pre-fetch the ghostty dependency to speed up the first build:
   ```bash
   just setup
   ```
   `just setup` caches the `ghostty` source tarball; the regular build will fetch it automatically if you skip this step.

2. Enter the development shell:
   ```bash
   nix develop
   ```

   Or, if using direnv:
   ```bash
   direnv allow
   ```

   On macOS hosts where the active `MacOSX.sdk` only exposes `arm64e` targets, Zig 0.15.2 can fail during native Darwin linking with errors such as `undefined symbol: __availability_version_check`. The upstream tracker for this regression is https://codeberg.org/ziglang/zig/issues/31756.

   The dev shell works around that by exposing `MacOSX15.4.sdk` through a fake `DEVELOPER_DIR` whose `usr/bin/xcrun` is a narrow shim for the SDK probes used by Zig and Ghostty. It answers `macosx`, `iphoneos`, and `iphonesimulator` `--show-sdk-path` queries because Ghostty initializes an xcframework dependency path on Darwin even though Architect only consumes `ghostty-vt`; the synthetic iOS paths are only for dependency graph construction and are not a replacement for real iOS SDKs. `build.zig` also resolves framework paths through `DEVELOPER_DIR` and `xcrun` before it falls back to hardcoded SDK locations, so the workaround does not need to force `SDKROOT`. Keeping the shim inside the fake developer tree means tools like `git` can still invoke `/usr/bin/xcrun` without tripping over the overridden `DEVELOPER_DIR`.

   Remove this workaround once Architect no longer uses Zig 0.15.2, or once Zig handles the arm64e-only macOS SDK stubs correctly. If the active `MacOSX.sdk/usr/lib/libSystem.tbd` advertises `arm64-macos` again, the shell hook becomes a no-op.

3. Verify the environment:
   ```bash
   zig version  # Should show 0.15.2+ (compatible with ghostty-vt)
   just --list  # Show available commands
   ```

## Build and Run

Build the project:
```bash
just build
# or
zig build
```

Build optimized release:
```bash
zig build -Doptimize=ReleaseFast
```

Run the application:
```bash
just run          # uses --instance Dev
just run Stable   # uses --instance Stable and generates a session name
```

Direct binary launches must pass an instance channel, for example `zig build run -- --instance Dev`. Use `--session HappyOtter` to reopen a named session. App bundles named `Architect (Stable).app` and `Architect (Scratch).app` infer `Stable` and `Scratch` from the bundle name, then generate a fresh named session under that channel unless a session is provided from the command line.

For local app-bundle launches, use the Makefile from the repository root:

```bash
make publish-apps                      # rebuild, install to /Applications, and refresh Dock icons
make apps                              # rebuild this branch's app bundle under .tmp/current-apps
make stable                            # launch a new Stable session through /Applications
make stable SESSION=HappyOtter         # restore a Stable session by session ID
make scratch                           # launch a new Scratch session through /Applications
make scratch-restore SESSION=BoldBadger
make sessions                          # list saved sessions under ~/.config/architect/instances
```

The `publish-apps` target is branch-aware. From `main`, it rebuilds and replaces only `/Applications/Architect (Stable).app`; from `scratch`, it rebuilds and replaces only `/Applications/Architect (Scratch).app`. It clears quarantine attributes, registers the refreshed app with Launch Services, removes stale Architect Dock tiles, adds Dock icons for installed Stable/Scratch bundles, and restarts the Dock. Never build Stable from `scratch` or Scratch from `main`. The `stable` and `scratch` targets launch the matching installed `/Applications` bundle, start a fresh named session when `SESSION` is unset, and restore that session when `SESSION` is set. The explicit `stable-new`, `scratch-new`, `stable-restore`, and `scratch-restore` targets are available for scripts that should avoid that conditional behavior. While running, `Cmd+Shift+S` opens saved sessions for the current channel in a new window.

## Dependencies and Tooling

- **ghostty-vt** is fetched as a pinned tarball via the Zig package manager (`build.zig.zon`).
- **SDL3** and **SDL3_ttf** are provided by Nix. SDL3 is pinned to 3.4.0 via `overlays/sdl3-3-4-0.nix` with binaries cached in the public `forketyfork` Cachix to avoid rebuilds.

## Tests and Formatting

Run tests:
```bash
just test
# or
zig build test
```

Check formatting and script linting:
```bash
just lint
# or
zig fmt --check src/
shellcheck scripts/*.sh scripts/verify-setup.sh
ruff check scripts/*.py
```

Format code:
```bash
zig fmt src/
```

## Release Process

macOS release binaries are automatically built for both ARM64 (Apple Silicon) and x86_64 (Intel) architectures via GitHub Actions when a version tag is pushed:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow packages ad-hoc-signed app bundles with local `codesign --sign -`. It does not import macOS signing certificates, does not produce Developer ID-signed artifacts, and does not notarize the app. Release downloads therefore still require clearing the quarantine attribute after extraction. This fork has not published Stable/Scratch release archives yet; the quarantine command is kept in README troubleshooting for future release testing. You can also run the Release workflow manually with `workflow_dispatch` to validate the packaging flow before pushing a real release tag.

The forked Homebrew formula is currently HEAD-only. The release workflow does not update formula `url` or `sha256` fields until the fork switches to a stable formula policy.

Each release includes:
- `architect-macos-arm64.tar.gz` - Apple Silicon
- `architect-macos-x86_64.tar.gz` - Intel

Each archive contains two app bundles built from the same branch:
- `Architect (Stable).app`
- `Architect (Scratch).app`

Both bundles contain `Contents/MacOS/architect`. The bundle name gives each app a distinct macOS bundle identifier and default Architect channel, so Stable and Scratch named sessions stay separate even though they share the same executable bits. The `architect-mcp` helper is still built by `zig build`, but app bundles omit it unless `scripts/bundle-macos.sh` is called with `--with-mcp <path>`.
