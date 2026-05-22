const std = @import("std");
const config_mod = @import("config.zig");

pub const ParseError = error{
    MissingInstanceName,
    MissingSessionName,
    UnknownArgument,
} || std.mem.Allocator.Error;

pub const CuteSessionName = struct {
    id: []const u8,
    display_name: []const u8,
    emoji: []const u8,
};

const cute_session_names = [_]CuteSessionName{
    .{ .id = "HappyOtter", .display_name = "Happy Otter", .emoji = "🦦" },
    .{ .id = "CozyPanda", .display_name = "Cozy Panda", .emoji = "🐼" },
    .{ .id = "BraveFox", .display_name = "Brave Fox", .emoji = "🦊" },
    .{ .id = "QuietKoala", .display_name = "Quiet Koala", .emoji = "🐨" },
    .{ .id = "SunnySeal", .display_name = "Sunny Seal", .emoji = "🦭" },
    .{ .id = "CleverOwl", .display_name = "Clever Owl", .emoji = "🦉" },
    .{ .id = "TinyTurtle", .display_name = "Tiny Turtle", .emoji = "🐢" },
    .{ .id = "GentleDeer", .display_name = "Gentle Deer", .emoji = "🦌" },
    .{ .id = "BrightFinch", .display_name = "Bright Finch", .emoji = "🐦" },
    .{ .id = "CalmRabbit", .display_name = "Calm Rabbit", .emoji = "🐰" },
    .{ .id = "LuckyPenguin", .display_name = "Lucky Penguin", .emoji = "🐧" },
    .{ .id = "NimbleSquirrel", .display_name = "Nimble Squirrel", .emoji = "🐿️" },
    .{ .id = "KindWhale", .display_name = "Kind Whale", .emoji = "🐋" },
    .{ .id = "SoftHedgehog", .display_name = "Soft Hedgehog", .emoji = "🦔" },
    .{ .id = "BoldBadger", .display_name = "Bold Badger", .emoji = "🦡" },
    .{ .id = "WarmLlama", .display_name = "Warm Llama", .emoji = "🦙" },
    .{ .id = "SwiftDolphin", .display_name = "Swift Dolphin", .emoji = "🐬" },
    .{ .id = "CheerfulDuck", .display_name = "Cheerful Duck", .emoji = "🦆" },
    .{ .id = "CuriousCat", .display_name = "Curious Cat", .emoji = "🐱" },
    .{ .id = "SleepySloth", .display_name = "Sleepy Sloth", .emoji = "🦥" },
    .{ .id = "FriendlyFrog", .display_name = "Friendly Frog", .emoji = "🐸" },
    .{ .id = "ShyMouse", .display_name = "Shy Mouse", .emoji = "🐭" },
    .{ .id = "BreezySwan", .display_name = "Breezy Swan", .emoji = "🦢" },
    .{ .id = "TenderMoose", .display_name = "Tender Moose", .emoji = "🫎" },
    .{ .id = "PoliteBeaver", .display_name = "Polite Beaver", .emoji = "🦫" },
    .{ .id = "PeppyParrot", .display_name = "Peppy Parrot", .emoji = "🦜" },
    .{ .id = "DreamyAlpaca", .display_name = "Dreamy Alpaca", .emoji = "🦙" },
    .{ .id = "TrustyHound", .display_name = "Trusty Hound", .emoji = "🐶" },
    .{ .id = "HumbleGoose", .display_name = "Humble Goose", .emoji = "🪿" },
    .{ .id = "GoldenBee", .display_name = "Golden Bee", .emoji = "🐝" },
    .{ .id = "SandyCrab", .display_name = "Sandy Crab", .emoji = "🦀" },
    .{ .id = "StarryBat", .display_name = "Starry Bat", .emoji = "🦇" },
    .{ .id = "ChipperChipmunk", .display_name = "Chipper Chipmunk", .emoji = "🐿️" },
    .{ .id = "BouncyKangaroo", .display_name = "Bouncy Kangaroo", .emoji = "🦘" },
    .{ .id = "SnugHamster", .display_name = "Snug Hamster", .emoji = "🐹" },
    .{ .id = "NobleHorse", .display_name = "Noble Horse", .emoji = "🐴" },
    .{ .id = "PeacefulDove", .display_name = "Peaceful Dove", .emoji = "🕊️" },
};

pub const Options = struct {
    channel_name: ?[]const u8 = null,
    session_name: ?[]const u8 = null,

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        if (self.channel_name) |name| {
            allocator.free(name);
            self.channel_name = null;
        }
        if (self.session_name) |name| {
            allocator.free(name);
            self.session_name = null;
        }
    }
};

pub fn cuteSessionNameCount() usize {
    return cute_session_names.len;
}

pub fn lookupCuteSessionName(id: []const u8) ?CuteSessionName {
    for (cute_session_names) |name| {
        if (std.mem.eql(u8, name.id, id)) return name;
    }
    const base_id = idWithoutNumericSuffix(id) orelse return null;
    for (cute_session_names) |name| {
        if (std.mem.eql(u8, name.id, base_id)) return name;
    }
    return null;
}

fn idWithoutNumericSuffix(id: []const u8) ?[]const u8 {
    var base_len = id.len;
    while (base_len > 0 and std.ascii.isDigit(id[base_len - 1])) {
        base_len -= 1;
    }
    if (base_len == id.len or base_len == 0) return null;
    return id[0..base_len];
}

pub fn generateSessionName(allocator: std.mem.Allocator) ![]u8 {
    const idx = std.crypto.random.uintLessThan(usize, cute_session_names.len);
    return try allocator.dupe(u8, cute_session_names[idx].id);
}

pub fn generateSessionNameForChannel(allocator: std.mem.Allocator, channel_name: []const u8) ![]u8 {
    const start_idx = std.crypto.random.uintLessThan(usize, cute_session_names.len);
    const config_root = config_mod.Persistence.getConfigRootPath(allocator) catch {
        return try generateSessionName(allocator);
    };
    defer allocator.free(config_root);

    for (0..cute_session_names.len) |offset| {
        const idx = (start_idx + offset) % cute_session_names.len;
        const candidate = cute_session_names[idx].id;
        const session_dir = config_mod.Persistence.sessionDirectoryPathUnderConfigRoot(
            allocator,
            config_root,
            channel_name,
            candidate,
        ) catch |err| {
            std.log.warn("failed to check generated session name {s}: {}", .{ candidate, err });
            continue;
        };
        defer allocator.free(session_dir);

        if (!directoryExists(session_dir)) {
            return try allocator.dupe(u8, candidate);
        }
    }

    const suffix = std.crypto.random.uintLessThan(u32, 10_000);
    return try std.fmt.allocPrint(allocator, "{s}{d}", .{ cute_session_names[start_idx].id, suffix });
}

pub fn parseProcessArgs(allocator: std.mem.Allocator) !Options {
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const executable_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(executable_path);

    return try parseArgsWithExecutablePath(allocator, argv, executable_path);
}

pub fn parseArgsWithExecutablePath(allocator: std.mem.Allocator, argv: []const []const u8, executable_path: []const u8) ParseError!Options {
    var options = try parseArgs(allocator, argv);
    errdefer options.deinit(allocator);

    if (options.channel_name == null) {
        options.channel_name = try inferInstanceNameFromAppBundlePath(allocator, executable_path);
    }

    if (options.channel_name == null) {
        return error.MissingInstanceName;
    }

    if (options.session_name == null) {
        options.session_name = try generateSessionNameForChannel(allocator, options.channel_name.?);
    }

    return options;
}

pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) ParseError!Options {
    var options = Options{};
    errdefer options.deinit(allocator);

    var idx: usize = 1;
    while (idx < argv.len) : (idx += 1) {
        const arg = argv[idx];
        if (std.mem.eql(u8, arg, "--instance")) {
            idx += 1;
            if (idx >= argv.len) return error.MissingInstanceName;
            if (options.channel_name) |old_name| allocator.free(old_name);
            options.channel_name = try allocator.dupe(u8, argv[idx]);
        } else if (std.mem.eql(u8, arg, "--session")) {
            idx += 1;
            if (idx >= argv.len) return error.MissingSessionName;
            if (options.session_name) |old_name| allocator.free(old_name);
            options.session_name = try allocator.dupe(u8, argv[idx]);
        } else if (std.mem.startsWith(u8, arg, "-psn_")) {
            // Finder may pass a process serial number to bundled macOS apps.
        } else {
            return error.UnknownArgument;
        }
    }

    return options;
}

pub fn inferInstanceNameFromAppBundlePath(allocator: std.mem.Allocator, executable_path: []const u8) !?[]u8 {
    const marker = ".app/Contents/MacOS/";
    const marker_index = std.mem.indexOf(u8, executable_path, marker) orelse return null;
    const app_path = executable_path[0 .. marker_index + ".app".len];
    const app_dir = std.fs.path.basename(app_path);
    if (!std.mem.endsWith(u8, app_dir, ".app")) return null;

    const app_name = app_dir[0 .. app_dir.len - ".app".len];
    return try inferInstanceNameFromAppName(allocator, app_name);
}

fn inferInstanceNameFromAppName(allocator: std.mem.Allocator, app_name: []const u8) !?[]u8 {
    const prefix = "Architect (";
    const suffix = ")";
    if (!std.mem.startsWith(u8, app_name, prefix) or !std.mem.endsWith(u8, app_name, suffix)) {
        return null;
    }

    const raw_name = app_name[prefix.len .. app_name.len - suffix.len];
    const trimmed = std.mem.trim(u8, raw_name, " \t\r\n");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

fn directoryExists(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

test "parseArgs captures channel and session names" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "architect", "--instance", "Stable", "--session", "HappyOtter" };

    var options = try parseArgs(allocator, &argv);
    defer options.deinit(allocator);

    try std.testing.expectEqualStrings("Stable", options.channel_name.?);
    try std.testing.expectEqualStrings("HappyOtter", options.session_name.?);
}

test "parseArgs rejects missing instance value" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "architect", "--instance" };

    try std.testing.expectError(error.MissingInstanceName, parseArgs(allocator, &argv));
}

test "parseArgs rejects missing session value" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "architect", "--instance", "Stable", "--session" };

    try std.testing.expectError(error.MissingSessionName, parseArgs(allocator, &argv));
}

test "parseArgsWithExecutablePath requires explicit or bundle-derived instance name" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{"architect"};

    try std.testing.expectError(
        error.MissingInstanceName,
        parseArgsWithExecutablePath(allocator, &argv, "/tmp/architect"),
    );
}

test "parseArgsWithExecutablePath generates a cute session name" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "architect", "--instance", "Stable" };

    var options = try parseArgsWithExecutablePath(allocator, &argv, "/tmp/architect");
    defer options.deinit(allocator);

    try std.testing.expectEqualStrings("Stable", options.channel_name.?);
    try std.testing.expect(options.session_name != null);
    try std.testing.expect(lookupCuteSessionName(options.session_name.?) != null);
}

test "generated session name pool uses emoji-backed names" {
    try std.testing.expect(cuteSessionNameCount() >= 30);
    const happy_otter = lookupCuteSessionName("HappyOtter") orelse return error.MissingHappyOtter;
    try std.testing.expectEqualStrings("Happy Otter", happy_otter.display_name);
    try std.testing.expect(happy_otter.emoji.len > 0);
}

test "lookupCuteSessionName resolves numeric fallback suffixes" {
    const happy_otter = lookupCuteSessionName("HappyOtter1234") orelse return error.MissingHappyOtter;
    try std.testing.expectEqualStrings("Happy Otter", happy_otter.display_name);
    try std.testing.expectEqualStrings("🦦", happy_otter.emoji);
}

test "inferInstanceNameFromAppBundlePath captures bundle suffix" {
    const allocator = std.testing.allocator;

    const stable_name_opt = try inferInstanceNameFromAppBundlePath(allocator, "/Applications/Architect (Stable).app/Contents/MacOS/architect");
    if (stable_name_opt) |stable_name| {
        defer allocator.free(stable_name);
        try std.testing.expectEqualStrings("Stable", stable_name);
    } else {
        return error.MissingStableInstanceName;
    }

    const scratch_name_opt = try inferInstanceNameFromAppBundlePath(allocator, "/Applications/Architect (Scratch).app/Contents/MacOS/architect");
    if (scratch_name_opt) |scratch_name| {
        defer allocator.free(scratch_name);
        try std.testing.expectEqualStrings("Scratch", scratch_name);
    } else {
        return error.MissingScratchInstanceName;
    }
}

test "inferInstanceNameFromAppBundlePath ignores base bundle" {
    const allocator = std.testing.allocator;

    const instance_name = try inferInstanceNameFromAppBundlePath(allocator, "/Applications/Architect.app/Contents/MacOS/architect");

    try std.testing.expect(instance_name == null);
}
