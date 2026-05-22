# frozen_string_literal: true

# Homebrew formula for the Architect fork app bundles.
class Architect < Formula
  desc "Terminal window manager with AI-powered workspace orchestration"
  homepage "https://github.com/iandvt/architect"
  license "MIT"
  head "https://github.com/iandvt/architect.git", branch: "main"

  depends_on "pkg-config" => :build
  depends_on xcode: :build
  depends_on "zig@0.15" => :build
  depends_on "sdl3"
  depends_on "sdl3_ttf"

  def install
    system "bash", "-c",
           ". ./scripts/setup-macos-sdk-workaround.sh >/tmp/architect-sdk-workaround.log && " \
           "zig build -Doptimize=ReleaseFast"

    system "scripts/bundle-macos.sh", "zig-out/bin/architect", prefix, "--app-name", "Architect (Stable)"
    system "scripts/bundle-macos.sh", "zig-out/bin/architect", prefix, "--app-name", "Architect (Scratch)"

    bin.install buildpath/"zig-out/bin/architect-mcp"
  end

  def caveats
    <<~EOS
      Architect apps have been installed to:
        #{prefix}/Architect (Stable).app
        #{prefix}/Architect (Scratch).app

      To add it to your Applications folder (for Spotlight/Launchpad access):
        cp -r "#{prefix}/Architect (Stable).app" /Applications/
        cp -r "#{prefix}/Architect (Scratch).app" /Applications/

      Launch with:
        open "#{prefix}/Architect (Stable).app"
        open "#{prefix}/Architect (Scratch).app"

      MCP helper command:
        architect-mcp
    EOS
  end

  test do
    assert_path_exists prefix/"Architect (Stable).app/Contents/MacOS/architect"
    assert_path_exists prefix/"Architect (Scratch).app/Contents/MacOS/architect"
    assert_path_exists bin/"architect-mcp"
  end
end
