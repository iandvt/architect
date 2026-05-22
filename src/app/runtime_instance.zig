const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("../config.zig");
const session_state = @import("../session/state.zig");
const terminal_history = @import("terminal_history.zig");

const log = std.log.scoped(.runtime_instance);
const SessionState = session_state.SessionState;

pub const RunOptions = struct {
    channel_name: []const u8,
    session_id: []const u8,
    session_display_name: []const u8,
    session_emoji: []const u8 = "",
};

pub fn windowTitleForSession(
    allocator: std.mem.Allocator,
    channel_name: []const u8,
    session_emoji: []const u8,
    session_display_name: []const u8,
) ![:0]u8 {
    const base_title = "Architect";
    const channel_sep = " - ";
    const session_sep = " / ";
    const emoji_sep = " ";
    const include_emoji = session_emoji.len != 0;
    const title_len = base_title.len +
        channel_sep.len +
        channel_name.len +
        session_sep.len +
        (if (include_emoji) session_emoji.len + emoji_sep.len else 0) +
        session_display_name.len;

    const title = try allocator.alloc(u8, title_len + 1);
    errdefer allocator.free(title);

    var pos: usize = 0;
    @memcpy(title[pos .. pos + base_title.len], base_title);
    pos += base_title.len;
    @memcpy(title[pos .. pos + channel_sep.len], channel_sep);
    pos += channel_sep.len;
    @memcpy(title[pos .. pos + channel_name.len], channel_name);
    pos += channel_name.len;
    @memcpy(title[pos .. pos + session_sep.len], session_sep);
    pos += session_sep.len;
    if (include_emoji) {
        @memcpy(title[pos .. pos + session_emoji.len], session_emoji);
        pos += session_emoji.len;
        @memcpy(title[pos .. pos + emoji_sep.len], emoji_sep);
        pos += emoji_sep.len;
    }
    @memcpy(title[pos .. pos + session_display_name.len], session_display_name);
    pos += session_display_name.len;
    std.debug.assert(pos == title_len);
    title[title_len] = 0;
    return title[0..title_len :0];
}

pub fn restoredTerminalEntriesForStartup(persistence: *const config_mod.Persistence) []const config_mod.Persistence.TerminalEntry {
    if (builtin.os.tag != .macos) return &.{};
    return persistence.terminal_entries.items;
}

pub fn seedSessionAgentMetadataFromEntry(
    session: *SessionState,
    entry: config_mod.Persistence.TerminalEntry,
    allocator: std.mem.Allocator,
) void {
    const agent_type_str = entry.agent_type orelse return;
    const session_id = entry.agent_session_id orelse return;
    if (session_id.len == 0) return;
    const agent_kind = session_state.AgentKind.fromString(agent_type_str) orelse return;

    session.agent_kind = agent_kind;
    if (session.agent_session_id) |sid| {
        allocator.free(sid);
        session.agent_session_id = null;
    }
    session.agent_session_id = allocator.dupe(u8, session_id) catch |err| {
        log.warn("failed to seed agent session id for restored session {d}: {}", .{ session.slot_index, err });
        return;
    };
    session.agent_metadata_captured = true;
}

pub fn prefillManualResumeCommandFromEntry(
    allocator: std.mem.Allocator,
    session: *SessionState,
    entry: config_mod.Persistence.TerminalEntry,
) bool {
    if (!session.spawned) return false;
    const agent_type_str = entry.agent_type orelse return false;
    const session_id = entry.agent_session_id orelse return false;
    if (session_id.len == 0) return false;
    const agent_kind = session_state.AgentKind.fromString(agent_type_str) orelse return false;

    const resume_cmd = terminal_history.buildResumeCommand(allocator, agent_kind, session_id) catch |err| {
        log.warn("failed to build manual resume command for session {d}: {}", .{ session.slot_index, err });
        return false;
    };
    defer allocator.free(resume_cmd);

    const prompt_text = std.mem.trimRight(u8, resume_cmd, "\r\n");
    if (prompt_text.len == 0) return false;

    session.pending_write.appendSlice(allocator, prompt_text) catch |err| {
        log.warn("failed to prefill manual resume command for session {d}: {}", .{ session.slot_index, err });
        return false;
    };
    return true;
}

fn optionalStringEql(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null and rhs == null) return true;
    if (lhs == null or rhs == null) return false;
    return std.mem.eql(u8, lhs.?, rhs.?);
}

fn persistedAgentType(session: *const SessionState) ?[]const u8 {
    if (!session.agent_metadata_captured) return null;
    if (session.agent_kind == null or session.agent_session_id == null) return null;
    return session.agent_kind.?.name();
}

fn persistedAgentSessionId(session: *const SessionState, agent_type: ?[]const u8) ?[]const u8 {
    if (agent_type == null) return null;
    return session.agent_session_id;
}

fn terminalEntriesMatchSessions(
    persistence: *const config_mod.Persistence,
    sessions: []const *SessionState,
) bool {
    var entry_idx: usize = 0;
    for (sessions) |session| {
        if (!session.spawned or session.dead) continue;
        const path = session.cwd_path orelse continue;
        if (path.len == 0) continue;

        if (entry_idx >= persistence.terminal_entries.items.len) return false;
        const entry = persistence.terminal_entries.items[entry_idx];
        const agent_type = persistedAgentType(session);
        const agent_session_id = persistedAgentSessionId(session, agent_type);

        if (!std.mem.eql(u8, entry.path, path)) return false;
        if (!optionalStringEql(entry.agent_type, agent_type)) return false;
        if (!optionalStringEql(entry.agent_session_id, agent_session_id)) return false;

        entry_idx += 1;
    }
    return entry_idx == persistence.terminal_entries.items.len;
}

pub const TerminalEntrySyncPolicy = enum {
    normal,
    preserve_existing,
};

pub fn syncPersistenceTerminalEntriesFromSessions(
    persistence: *config_mod.Persistence,
    sessions: []const *SessionState,
    allocator: std.mem.Allocator,
) !bool {
    if (terminalEntriesMatchSessions(persistence, sessions)) return false;

    persistence.clearTerminalEntries(allocator);
    for (sessions) |session| {
        if (!session.spawned or session.dead) continue;
        const path = session.cwd_path orelse continue;
        if (path.len == 0) continue;

        const agent_type = persistedAgentType(session);
        const agent_session_id = persistedAgentSessionId(session, agent_type);
        try persistence.appendTerminalEntry(allocator, path, agent_type, agent_session_id);
    }
    return true;
}

pub fn syncPersistenceTerminalEntriesFromSessionsWithPolicy(
    persistence: *config_mod.Persistence,
    sessions: []const *SessionState,
    allocator: std.mem.Allocator,
    policy: TerminalEntrySyncPolicy,
) !bool {
    switch (policy) {
        .normal => return try syncPersistenceTerminalEntriesFromSessions(persistence, sessions, allocator),
        .preserve_existing => return false,
    }
}

pub fn savePersistenceIfDirty(
    persistence: *config_mod.Persistence,
    allocator: std.mem.Allocator,
    dirty: *bool,
    options: RunOptions,
) void {
    if (!dirty.*) return;
    persistence.saveForSession(allocator, options.channel_name, options.session_id) catch |err| {
        std.debug.print("Failed to save persistence: {}\n", .{err});
        return;
    };
    dirty.* = false;
}

test "windowTitleForSession includes channel and display name" {
    const allocator = std.testing.allocator;

    const stable_title = try windowTitleForSession(allocator, "Stable", "🦦", "Happy Otter");
    defer allocator.free(stable_title);
    try std.testing.expectEqualStrings("Architect - Stable / 🦦 Happy Otter", stable_title);

    const scratch_title = try windowTitleForSession(allocator, "Scratch", "", "Custom");
    defer allocator.free(scratch_title);
    try std.testing.expectEqualStrings("Architect - Scratch / Custom", scratch_title);
}

test "startup restore returns persisted terminal entries" {
    const allocator = std.testing.allocator;

    var persistence = config_mod.Persistence.init(allocator);
    defer persistence.deinit(allocator);
    try persistence.appendTerminalEntry(allocator, "/tmp/old-session", "codex", "abc-123");

    const startup_entries = restoredTerminalEntriesForStartup(&persistence);
    if (builtin.os.tag == .macos) {
        try std.testing.expectEqual(@as(usize, 1), startup_entries.len);
        try std.testing.expectEqualStrings("/tmp/old-session", startup_entries[0].path);
    } else {
        try std.testing.expectEqual(@as(usize, 0), startup_entries.len);
    }
}

test "prefillManualResumeCommandFromEntry queues resume command without newline" {
    const allocator = std.testing.allocator;

    var session: SessionState = undefined;
    session.slot_index = 0;
    session.spawned = true;
    session.pending_write = .empty;
    defer session.pending_write.deinit(allocator);

    const entry = config_mod.Persistence.TerminalEntry{
        .path = "/one",
        .agent_type = "codex",
        .agent_session_id = "abc-123",
    };

    try std.testing.expect(prefillManualResumeCommandFromEntry(allocator, &session, entry));
    try std.testing.expectEqualStrings("codex resume abc-123", session.pending_write.items);
}

test "seedSessionAgentMetadataFromEntry seeds known restored metadata" {
    const allocator = std.testing.allocator;

    var session: SessionState = undefined;
    session.slot_index = 3;
    session.agent_kind = null;
    session.agent_session_id = null;
    session.agent_metadata_captured = true;

    const entry = config_mod.Persistence.TerminalEntry{
        .path = "/tmp/test",
        .agent_type = "codex",
        .agent_session_id = "abc-123",
    };
    seedSessionAgentMetadataFromEntry(&session, entry, allocator);

    try std.testing.expect(session.agent_kind != null);
    try std.testing.expectEqual(session_state.AgentKind.codex, session.agent_kind.?);
    try std.testing.expect(session.agent_session_id != null);
    try std.testing.expectEqualStrings("abc-123", session.agent_session_id.?);
    try std.testing.expect(session.agent_session_id.?.ptr != entry.agent_session_id.?.ptr);
    try std.testing.expect(session.agent_metadata_captured);

    if (session.agent_session_id) |sid| allocator.free(sid);
}

test "syncPersistenceTerminalEntriesFromSessions preserves restored agent metadata for manual resume" {
    const allocator = std.testing.allocator;

    var persistence = config_mod.Persistence.init(allocator);
    defer persistence.deinit(allocator);

    try persistence.appendTerminalEntry(allocator, "/one", "codex", "stale-seed");

    var session: SessionState = undefined;
    session.slot_index = 0;
    session.spawned = true;
    session.dead = false;
    session.cwd_path = "/one";
    session.agent_kind = null;
    session.agent_session_id = null;
    session.agent_metadata_captured = false;

    seedSessionAgentMetadataFromEntry(&session, persistence.terminal_entries.items[0], allocator);
    defer if (session.agent_session_id) |sid| allocator.free(sid);

    var sessions = [_]*SessionState{&session};

    try std.testing.expect(!(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator)));
    try std.testing.expectEqual(@as(usize, 1), persistence.terminal_entries.items.len);
    try std.testing.expectEqualStrings("codex", persistence.terminal_entries.items[0].agent_type.?);
    try std.testing.expectEqualStrings("stale-seed", persistence.terminal_entries.items[0].agent_session_id.?);
}

test "syncPersistenceTerminalEntriesFromSessionsWithPolicy preserves entries after restore failure" {
    const allocator = std.testing.allocator;

    var persistence = config_mod.Persistence.init(allocator);
    defer persistence.deinit(allocator);

    try persistence.appendTerminalEntry(allocator, "/restored-one", "codex", "sid-one");
    try persistence.appendTerminalEntry(allocator, "/restored-two", null, null);

    var session: SessionState = undefined;
    session.slot_index = 0;
    session.spawned = true;
    session.dead = false;
    session.cwd_path = "/fallback";
    session.agent_kind = null;
    session.agent_session_id = null;
    session.agent_metadata_captured = false;

    var sessions = [_]*SessionState{&session};

    try std.testing.expect(!(try syncPersistenceTerminalEntriesFromSessionsWithPolicy(
        &persistence,
        &sessions,
        allocator,
        .preserve_existing,
    )));
    try std.testing.expectEqual(@as(usize, 2), persistence.terminal_entries.items.len);
    try std.testing.expectEqualStrings("/restored-one", persistence.terminal_entries.items[0].path);
    try std.testing.expectEqualStrings("codex", persistence.terminal_entries.items[0].agent_type.?);
    try std.testing.expectEqualStrings("sid-one", persistence.terminal_entries.items[0].agent_session_id.?);
    try std.testing.expectEqualStrings("/restored-two", persistence.terminal_entries.items[1].path);

    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessionsWithPolicy(
        &persistence,
        &sessions,
        allocator,
        .normal,
    ));
    try std.testing.expectEqual(@as(usize, 1), persistence.terminal_entries.items.len);
    try std.testing.expectEqualStrings("/fallback", persistence.terminal_entries.items[0].path);
}

test "syncPersistenceTerminalEntriesFromSessions reacts to cd, spawn, and despawn" {
    const allocator = std.testing.allocator;

    var persistence = config_mod.Persistence.init(allocator);
    defer persistence.deinit(allocator);

    var sessions_storage: [2]SessionState = undefined;
    for (&sessions_storage) |*session| {
        session.* = undefined;
        session.spawned = false;
        session.dead = false;
        session.cwd_path = null;
        session.agent_kind = null;
        session.agent_session_id = null;
        session.agent_metadata_captured = false;
    }
    var sessions = [_]*SessionState{ &sessions_storage[0], &sessions_storage[1] };

    sessions_storage[0].spawned = true;
    sessions_storage[0].cwd_path = "/one";

    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator));
    try std.testing.expectEqual(@as(usize, 1), persistence.terminal_entries.items.len);
    try std.testing.expectEqualStrings("/one", persistence.terminal_entries.items[0].path);

    sessions_storage[0].cwd_path = "/two";
    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator));
    try std.testing.expectEqualStrings("/two", persistence.terminal_entries.items[0].path);
    try std.testing.expect(!(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator)));

    sessions_storage[0].spawned = false;
    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator));
    try std.testing.expectEqual(@as(usize, 0), persistence.terminal_entries.items.len);

    sessions_storage[1].spawned = true;
    sessions_storage[1].cwd_path = "/three";
    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator));
    try std.testing.expectEqual(@as(usize, 1), persistence.terminal_entries.items.len);
    try std.testing.expectEqualStrings("/three", persistence.terminal_entries.items[0].path);

    sessions_storage[1].agent_kind = .codex;
    sessions_storage[1].agent_session_id = "sid-42";
    sessions_storage[1].agent_metadata_captured = true;
    try std.testing.expect(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator));
    try std.testing.expectEqualStrings("codex", persistence.terminal_entries.items[0].agent_type.?);
    try std.testing.expectEqualStrings("sid-42", persistence.terminal_entries.items[0].agent_session_id.?);
    try std.testing.expect(!(try syncPersistenceTerminalEntriesFromSessions(&persistence, &sessions, allocator)));
}
