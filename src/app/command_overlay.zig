const std = @import("std");
const xev = @import("xev");
const ghostty_vt = @import("ghostty-vt");
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
    overlays: []*CommandOverlay,
    active_index: ?usize = null,

    pub fn init(
        allocator: std.mem.Allocator,
        count: usize,
        shell_path: []const u8,
        initial_size: pty_mod.winsize,
        notify_sock: [:0]const u8,
        theme: colors.Theme,
    ) !CommandOverlaySet {
        const overlays = try allocator.alloc(*CommandOverlay, count);
        errdefer allocator.free(overlays);

        var initialized: usize = 0;
        errdefer {
            for (overlays[0..initialized]) |*overlay| {
                overlay.*.deinit();
                allocator.destroy(overlay.*);
            }
        }

        for (overlays) |*overlay| {
            overlay.* = try allocator.create(CommandOverlay);
            errdefer allocator.destroy(overlay.*);
            overlay.*.* = try CommandOverlay.init(allocator, shell_path, initial_size, notify_sock, theme);
            initialized += 1;
        }

        return .{
            .allocator = allocator,
            .overlays = overlays,
        };
    }

    pub fn deinit(self: *CommandOverlaySet) void {
        for (self.overlays) |overlay| {
            overlay.deinit();
            self.allocator.destroy(overlay);
        }
        self.allocator.free(self.overlays);
        self.overlays = &[_]*CommandOverlay{};
        self.active_index = null;
    }

    pub fn activeOverlay(self: *CommandOverlaySet) ?*CommandOverlay {
        const idx = self.active_index orelse return null;
        if (idx >= self.overlays.len) return null;
        return self.overlays[idx];
    }

    pub fn activeOverlayConst(self: *const CommandOverlaySet) ?*const CommandOverlay {
        const idx = self.active_index orelse return null;
        if (idx >= self.overlays.len) return null;
        return self.overlays[idx];
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

    pub fn despawnAt(self: *CommandOverlaySet, index: usize) void {
        if (index >= self.overlays.len) return;
        self.overlays[index].despawn();
        if (self.active_index == index) {
            self.active_index = null;
        }
    }

    pub fn swapSlots(self: *CommandOverlaySet, a: usize, b: usize) void {
        if (a >= self.overlays.len or b >= self.overlays.len or a == b) return;
        std.mem.swap(*CommandOverlay, &self.overlays[a], &self.overlays[b]);
        if (self.active_index) |active_idx| {
            if (active_idx == a) {
                self.active_index = b;
            } else if (active_idx == b) {
                self.active_index = a;
            }
        }
    }

    pub fn foregroundProcessCount(self: *const CommandOverlaySet) usize {
        var total: usize = 0;
        for (self.overlays) |overlay| {
            if (overlay.session.hasForegroundProcess()) {
                total += 1;
            }
        }
        return total;
    }

    pub fn hasForegroundProcessAt(self: *const CommandOverlaySet, index: usize) bool {
        if (index >= self.overlays.len) return false;
        return self.overlays[index].session.hasForegroundProcess();
    }

    pub fn processOutput(self: *CommandOverlaySet, now_ms: i64) bool {
        var dirty = false;
        for (self.overlays) |overlay| {
            dirty = overlay.processOutput(now_ms) or dirty;
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

    pub fn resetActiveScrollIfNeeded(self: *CommandOverlaySet) void {
        const overlay = self.activeOverlay() orelse return;
        overlay.resetScrollIfNeeded();
    }

    pub fn scrollActive(self: *CommandOverlaySet, delta: isize, now_ms: i64) void {
        const overlay = self.activeOverlay() orelse return;
        overlay.scroll(delta, now_ms);
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

pub fn terminalSizeForRect(font: *const font_mod.Font, rect: geom.Rect, ui_scale: f32) pty_mod.winsize {
    const cols_px = @max(1, font.cell_width);
    const rows_px = @max(1, font.cell_height);
    const padding = dpi.scale(renderer_mod.terminal_padding, ui_scale) * 2;
    const drawable_w = @max(1, rect.w - padding);
    const drawable_h = @max(1, rect.h - padding);
    const cols: c_int = @max(1, @divFloor(drawable_w, cols_px));
    const rows: c_int = @max(1, @divFloor(drawable_h, rows_px));
    const width_px: c_int = @min(cols * cols_px, std.math.maxInt(u16));
    const height_px: c_int = @min(rows * rows_px, std.math.maxInt(u16));
    return .{
        .ws_row = @intCast(rows),
        .ws_col = @intCast(cols),
        .ws_xpixel = @intCast(width_px),
        .ws_ypixel = @intCast(height_px),
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
        self.hide();
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

    pub fn processOutput(self: *CommandOverlay, now_ms: i64) bool {
        if (!self.session.spawned) return false;
        self.session.checkAlive();
        if (self.session.dead) return false;
        self.session.flushPendingWrites() catch |err| {
            log.warn("failed to flush command overlay pending input: {}", .{err});
        };
        self.session.processOutput() catch |err| {
            log.warn("failed to process command overlay output: {}", .{err});
        };
        _ = self.session.expireSynchronizedOutput(now_ms);
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
        self.resetScrollIfNeeded();
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
        self.resetScrollIfNeeded();
        try self.session.sendInput(text);
    }

    pub fn resetScrollIfNeeded(self: *CommandOverlay) void {
        if (!self.view.is_viewing_scrollback) return;
        if (self.session.terminal) |*terminal| {
            terminal.screens.active.pages.scroll(.{ .active = {} });
            self.view.clearScroll();
            self.session.markDirty();
        }
    }

    pub fn scroll(self: *CommandOverlay, delta: isize, now_ms: i64) void {
        if (!self.session.spawned or self.session.dead or delta == 0) return;

        self.view.last_scroll_time = now_ms;
        self.view.scroll_remainder = 0.0;
        self.view.scroll_inertia_allowed = true;

        if (self.session.terminal) |*terminal| {
            var pages = &terminal.screens.active.pages;
            pages.scroll(.{ .delta_row = delta });
            self.view.is_viewing_scrollback = (pages.viewport != .active);
            self.view.terminal_scrollbar.noteActivity(now_ms);
            self.session.markDirty();
        }
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
        const size = terminalSizeForRect(terminal_font, rect, ui_scale);
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

test "terminal size reserves renderer padding" {
    var font: font_mod.Font = undefined;
    font.cell_width = 10;
    font.cell_height = 20;

    const size = terminalSizeForRect(&font, .{ .x = 0, .y = 0, .w = 139, .h = 131 }, 2.0);

    try std.testing.expectEqual(@as(u16, 4), size.ws_row);
    try std.testing.expectEqual(@as(u16, 10), size.ws_col);
    try std.testing.expectEqual(@as(u16, 100), size.ws_xpixel);
    try std.testing.expectEqual(@as(u16, 80), size.ws_ypixel);
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
    try std.testing.expect(overlays.activeOverlay() == overlays.overlays[1]);
}

test "process output expires stuck synchronized output" {
    var overlay = try CommandOverlay.init(std.testing.allocator, "/bin/sh", .{}, "", colors.Theme.default());
    defer overlay.deinit();

    overlay.visible = true;
    overlay.session.spawned = true;
    overlay.session.dead = false;
    overlay.session.render_epoch = 1;
    overlay.session.synchronized_output_started_ms = 100;
    overlay.session.terminal = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 10,
        .rows = 3,
        .max_scrollback = 5,
    });
    if (overlay.session.terminal) |*terminal| {
        terminal.modes.set(.synchronized_output, true);
    } else {
        return error.MissingTerminal;
    }

    try std.testing.expect(overlay.processOutput(1100));
    try std.testing.expect(!overlay.session.synchronizedOutputActive());
    try std.testing.expectEqual(@as(u64, 2), overlay.session.render_epoch);
}

test "text input leaves remote terminal scrollback" {
    var overlay = try CommandOverlay.init(std.testing.allocator, "/bin/sh", .{}, "", colors.Theme.default());
    defer overlay.deinit();

    overlay.session.spawned = true;
    overlay.session.dead = false;
    overlay.session.render_epoch = 1;
    overlay.session.terminal = try ghostty_vt.Terminal.init(std.testing.allocator, .{
        .cols = 10,
        .rows = 3,
        .max_scrollback = 5,
    });
    overlay.view.is_viewing_scrollback = true;
    if (overlay.session.terminal) |*terminal| {
        terminal.screens.active.pages.scroll(.{ .delta_row = -1 });
    } else {
        return error.MissingTerminal;
    }

    try overlay.sendText("x");

    try std.testing.expect(!overlay.view.is_viewing_scrollback);
    try std.testing.expectEqual(@as(u64, 2), overlay.session.render_epoch);
}
