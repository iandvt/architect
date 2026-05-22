class Architect < Formula
  desc "Terminal window manager with AI-powered workspace orchestration"
  homepage "https://github.com/forketyfork/architect"
  url "https://github.com/forketyfork/architect/archive/refs/tags/v0.65.3.tar.gz"
  sha256 "2c1fd238db019d8a1bba6dcdea15dc28275e3f34e9c9d94706b67fbe05bc80e7"
  license "MIT"

  depends_on "pkg-config" => :build
  depends_on xcode: :build
  depends_on "zig@0.15" => :build
  depends_on "sdl3"
  depends_on "sdl3_ttf"

  def install
    system "zig", "build",
           "-Doptimize=ReleaseFast"

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
