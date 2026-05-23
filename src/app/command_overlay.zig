const std = @import("std");
const xev = @import("xev");
const c = @import("../c.zig");
const colors = @import("../colors.zig");
const dpi = @import("../dpi.zig");
const font_mod = @import("../font.zig");
const geom = @import("../geom.zig");
const input = @import("../input/mapper.zig");
const layout = @import("layout.zig");
const pty_mod = @import("../pty.zig");
const renderer_mod = @import("../render/renderer.zig");
const session_state = @import("../session/state.zig");
const view_state = @import("../ui/session_view_state.zig");

const log = std.log.scoped(.command_overlay);

const SessionState = session_state.SessionState;
const SessionViewState = view_state.SessionViewState;

const overlay_slot_index = std.math.maxInt(usize);
const outer_margin: c_int = 40;
const title_height: c_int = 50;
const text_padding: c_int = 12;

pub const CommandOverlaySet = struct {
    allocator: std.mem.Allocator,
    overlays: []CommandOverlay,
    active_index: ?usize = null,

    pub fn init(
        allocator: std.mem.Allocator,
        count: usize,
        shell_path: []const u8,
        initial_size: pty_mod.winsize,
        notify_sock: [:0]const u8,
        theme: colors.Theme,
    ) !CommandOverlaySet {
        const overlays = try allocator.alloc(CommandOverlay, count);
        errdefer allocator.free(overlays);

        var initialized: usize = 0;
        errdefer {
            for (overlays[0..initialized]) |*overlay| {
                overlay.deinit();
            }
        }

        for (overlays) |*overlay| {
            overlay.* = try CommandOverlay.init(allocator, shell_path, initial_size, notify_sock, theme);
            initialized += 1;
        }

        return .{
            .allocator = allocator,
            .overlays = overlays,
        };
    }

    pub fn deinit(self: *CommandOverlaySet) void {
        for (self.overlays) |*overlay| {
            overlay.deinit();
        }
        self.allocator.free(self.overlays);
        self.overlays = &[_]CommandOverlay{};
        self.active_index = null;
    }

    pub fn activeOverlay(self: *CommandOverlaySet) ?*CommandOverlay {
        const idx = self.active_index orelse return null;
        if (idx >= self.overlays.len) return null;
        return &self.overlays[idx];
    }

    pub fn activeOverlayConst(self: *const CommandOverlaySet) ?*const CommandOverlay {
        const idx = self.active_index orelse return null;
        if (idx >= self.overlays.len) return null;
        return &self.overlays[idx];
    }

    pub fn isVisible(self: *const CommandOverlaySet) bool {
        const overlay = self.activeOverlayConst() orelse return false;
        return overlay.isVisible();
    }

    pub fn showFor(self: *CommandOverlaySet, index: usize, cwd: ?[]const u8, size: pty_mod.winsize, loop: *xev.Loop) !void {
        if (index >= self.overlays.len) return error.InvalidSlot;
        if (self.active_index) |active_idx| {
            if (active_idx != index and active_idx < self.overlays.len) {
                self.overlays[active_idx].hide();
            }
        }

        self.active_index = index;
        try self.overlays[index].show(cwd, size, loop);
    }

    pub fn hideActive(self: *CommandOverlaySet) void {
        if (self.activeOverlay()) |overlay| {
            overlay.hide();
        }
    }

    pub fn processOutput(self: *CommandOverlaySet) bool {
        var dirty = false;
        for (self.overlays) |*overlay| {
            dirty = overlay.processOutput() or dirty;
        }
        return dirty;
    }

    pub fn sendKey(self: *CommandOverlaySet, key: c.SDL_Keycode, mod: c.SDL_Keymod) !void {
        const overlay = self.activeOverlay() orelse return;
        try overlay.sendKey(key, mod);
    }

    pub fn sendText(self: *CommandOverlaySet, text: []const u8) !void {
        const overlay = self.activeOverlay() orelse return;
        try overlay.sendText(text);
    }
};

pub fn panelRect(window_w: c_int, window_h: c_int, ui_scale: f32) geom.Rect {
    const margin = dpi.scale(outer_margin, ui_scale);
    return .{
        .x = margin,
        .y = margin,
        .w = @max(1, window_w - margin * 2),
        .h = @max(1, window_h - margin * 2),
    };
}

pub fn terminalRectFromPanel(panel: geom.Rect, ui_scale: f32) geom.Rect {
    const title_h = dpi.scale(title_height, ui_scale);
    const padding = dpi.scale(text_padding, ui_scale);
    return .{
        .x = panel.x + padding,
        .y = panel.y + title_h + padding,
        .w = @max(1, panel.w - padding * 2),
        .h = @max(1, panel.h - title_h - padding * 2),
    };
}

pub fn terminalRect(window_w: c_int, window_h: c_int, ui_scale: f32) geom.Rect {
    return terminalRectFromPanel(panelRect(window_w, window_h, ui_scale), ui_scale);
}

pub fn terminalSizeForRect(font: *const font_mod.Font, rect: geom.Rect) pty_mod.winsize {
    const cols_px = @max(1, font.cell_width);
    const rows_px = @max(1, font.cell_height);
    const cols: c_int = @max(1, @divFloor(rect.w, cols_px));
    const rows: c_int = @max(1, @divFloor(rect.h, rows_px));
    return .{
        .ws_row = @intCast(rows),
        .ws_col = @intCast(cols),
        .ws_xpixel = @intCast(@min(rect.w, std.math.maxInt(u16))),
        .ws_ypixel = @intCast(@min(rect.h, std.math.maxInt(u16))),
    };
}

pub const CommandOverlay = struct {
    allocator: std.mem.Allocator,
    session: SessionState,
    view: SessionViewState = .{},
    cache_entry: renderer_mod.RenderCache.Entry = .{},
    visible: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        shell_path: []const u8,
        initial_size: pty_mod.winsize,
        notify_sock: [:0]const u8,
        theme: colors.Theme,
    ) !CommandOverlay {
        return .{
            .allocator = allocator,
            .session = try SessionState.init(allocator, overlay_slot_index, shell_path, initial_size, notify_sock, theme),
        };
    }

    pub fn deinit(self: *CommandOverlay) void {
        self.despawn();
        self.session.deinit(self.allocator);
        self.destroyCache();
        self.view.reset();
    }

    pub fn isVisible(self: *const CommandOverlay) bool {
        return self.visible;
    }

    pub fn show(self: *CommandOverlay, cwd: ?[]const u8, size: pty_mod.winsize, loop: *xev.Loop) !void {
        if (self.session.spawned and !self.session.dead) {
            self.visible = true;
            _ = self.resizeIfNeeded(size);
            return;
        }

        if (self.session.spawned) {
            self.despawn();
        }

        self.view.reset();
        self.destroyCache();
        self.session.pty_size = size;

        const cwd_z = if (cwd) |path| try allocZ(self.allocator, path) else null;
        defer if (cwd_z) |buf| self.allocator.free(buf);

        const cwd_slice: ?[:0]const u8 = if (cwd_z) |buf| buf[0 .. buf.len - 1 :0] else null;
        try self.session.ensureSpawnedWithDir(cwd_slice, loop);
        self.visible = true;
    }

    pub fn hide(self: *CommandOverlay) void {
        self.visible = false;
        self.view.clearHover();
    }

    pub fn despawn(self: *CommandOverlay) void {
        self.hide();
        if (self.session.spawned) {
            self.session.despawn(self.allocator);
        }
        self.view.reset();
        self.destroyCache();
    }

    pub fn processOutput(self: *CommandOverlay) bool {
        if (!self.session.spawned) return false;
        self.session.checkAlive();
        if (self.session.dead) return false;
        self.session.flushPendingWrites() catch |err| {
            log.warn("failed to flush command overlay pending input: {}", .{err});
        };
        self.session.processOutput() catch |err| {
            log.warn("failed to process command overlay output: {}", .{err});
        };
        return self.visible and self.session.render_epoch != self.cache_entry.presented_epoch;
    }

    pub fn resizeIfNeeded(self: *CommandOverlay, size: pty_mod.winsize) bool {
        if (!self.session.spawned) {
            self.session.pty_size = size;
            return false;
        }
        const terminal_size = layout.TerminalSize{
            .cols = size.ws_col,
            .rows = size.ws_row,
            .width_px = size.ws_xpixel,
            .height_px = size.ws_ypixel,
        };
        const sizes = layout.Sizes{ .grid = terminal_size, .full = terminal_size };
        const sessions = [_]*SessionState{&self.session};
        return layout.applyTerminalResize(&sessions, self.allocator, sizes, .{ .primary = 0 });
    }

    pub fn sendKey(self: *CommandOverlay, key: c.SDL_Keycode, mod: c.SDL_Keymod) !void {
        if (!self.session.spawned or self.session.dead) return;
        const cursor_keys = if (self.session.terminal) |*terminal|
            terminal.modes.get(.cursor_keys)
        else
            false;

        const kitty_enabled = if (self.session.terminal) |*terminal|
            terminal.screens.active.kitty_keyboard.current().int() != 0
        else
            false;

        var buf: [16]u8 = undefined;
        const n = input.encodeKeyWithMod(key, mod, cursor_keys, kitty_enabled, &buf);
        if (n > 0) {
            try self.session.sendInput(buf[0..n]);
        }
    }

    pub fn sendText(self: *CommandOverlay, text: []const u8) !void {
        if (!self.session.spawned or self.session.dead) return;
        try self.session.sendInput(text);
    }

    pub fn render(
        self: *CommandOverlay,
        renderer: *c.SDL_Renderer,
        terminal_font: *font_mod.Font,
        rect: geom.Rect,
        now_ms: i64,
        theme: *const colors.Theme,
        ui_scale: f32,
    ) renderer_mod.RenderError!void {
        if (!self.visible or !self.session.spawned) return;
        const size = terminalSizeForRect(terminal_font, rect);
        _ = self.resizeIfNeeded(size);
        try renderer_mod.renderSessionIntoRect(
            renderer,
            &self.session,
            &self.view,
            &self.cache_entry,
            rect,
            terminal_font,
            now_ms,
            theme,
            ui_scale,
        );
    }

    fn destroyCache(self: *CommandOverlay) void {
        if (self.cache_entry.texture) |texture| {
            c.SDL_DestroyTexture(texture);
        }
        self.cache_entry = .{};
    }
};

fn allocZ(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, value.len + 1);
    @memcpy(out[0..value.len], value);
    out[value.len] = 0;
    return out;
}

test "terminal rect reserves frame title and padding" {
    const panel = panelRect(1200, 800, 1.0);
    try std.testing.expectEqual(@as(geom.Rect, .{ .x = 40, .y = 40, .w = 1120, .h = 720 }), panel);

    const terminal = terminalRect(1200, 800, 1.0);
    try std.testing.expectEqual(@as(geom.Rect, .{ .x = 52, .y = 102, .w = 1096, .h = 646 }), terminal);
}

test "hide preserves the overlay terminal session" {
    var overlay = try CommandOverlay.init(std.testing.allocator, "/bin/sh", .{}, "", colors.Theme.default());
    defer overlay.deinit();

    overlay.visible = true;
    overlay.session.spawned = true;

    overlay.hide();

    try std.testing.expect(!overlay.visible);
    try std.testing.expect(overlay.session.spawned);
}

test "overlay set keeps a distinct remote terminal per grid slot" {
    var overlays = try CommandOverlaySet.init(std.testing.allocator, 2, "/bin/sh", .{}, "", colors.Theme.default());
    defer overlays.deinit();

    overlays.active_index = 0;
    overlays.overlays[0].visible = true;
    overlays.overlays[0].session.spawned = true;
    overlays.overlays[1].session.spawned = true;

    var loop: xev.Loop = undefined;
    try overlays.showFor(1, null, .{}, &loop);

    try std.testing.expect(!overlays.overlays[0].visible);
    try std.testing.expect(overlays.overlays[0].session.spawned);
    try std.testing.expect(overlays.overlays[1].visible);
    try std.testing.expect(overlays.overlays[1].session.spawned);
    try std.testing.expect(overlays.activeOverlay() == &overlays.overlays[1]);
}
