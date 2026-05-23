const std = @import("std");
const c = @import("../../c.zig");
const colors = @import("../../colors.zig");
const command_overlay_mod = @import("../../app/command_overlay.zig");
const dpi = @import("../../dpi.zig");
const input = @import("../../input/mapper.zig");
const input_keys = @import("../../app/input_keys.zig");
const types = @import("../types.zig");
const UiComponent = @import("../component.zig").UiComponent;
const FullscreenOverlay = @import("fullscreen_overlay.zig").FullscreenOverlay;
const search_utils = @import("search_utils.zig");

const log = std.log.scoped(.command_overlay_component);

pub const CommandOverlayComponent = struct {
    allocator: std.mem.Allocator,
    command_overlays: *command_overlay_mod.CommandOverlaySet,
    overlay: FullscreenOverlay = .{},

    pub fn init(allocator: std.mem.Allocator, command_overlays: *command_overlay_mod.CommandOverlaySet) !*CommandOverlayComponent {
        const comp = try allocator.create(CommandOverlayComponent);
        comp.* = .{
            .allocator = allocator,
            .command_overlays = command_overlays,
        };
        return comp;
    }

    pub fn asComponent(self: *CommandOverlayComponent) UiComponent {
        return .{
            .ptr = self,
            .vtable = &vtable,
            .z_index = 1160,
        };
    }

    pub fn setOpen(self: *CommandOverlayComponent, open: bool, now_ms: i64) void {
        if (open) {
            if (!self.overlay.visible or self.overlay.animation_state == .closing) {
                self.overlay.show(now_ms);
            }
        } else if (self.overlay.visible and self.overlay.animation_state != .closing) {
            self.overlay.hide(now_ms);
        }
    }

    fn markRenderedFrame(self: *CommandOverlayComponent) void {
        self.overlay.first_frame.markDrawn();
    }

    fn handleEventFn(self_ptr: *anyopaque, host: *const types.UiHost, event: *const c.SDL_Event, actions: *types.UiActionQueue) bool {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));

        if (!self.overlay.visible) {
            if (event.type == c.SDL_EVENT_KEY_DOWN and input.commandOverlayShortcut(event.key.key, event.key.mod)) {
                actions.append(.ToggleCommandOverlay) catch |err| {
                    log.warn("failed to queue ToggleCommandOverlay action: {}", .{err});
                };
                return true;
            }
            return false;
        }

        if (self.overlay.animation_state == .closing) {
            return switch (event.type) {
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP, c.SDL_EVENT_TEXT_INPUT, c.SDL_EVENT_TEXT_EDITING, c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_WHEEL, c.SDL_EVENT_MOUSE_MOTION => true,
                else => false,
            };
        }

        switch (event.type) {
            c.SDL_EVENT_KEY_DOWN => {
                const key = event.key.key;
                const mod = event.key.mod;

                if (input.commandOverlayShortcut(key, mod)) {
                    actions.append(.ToggleCommandOverlay) catch |err| {
                        log.warn("failed to queue ToggleCommandOverlay action: {}", .{err});
                    };
                    return true;
                }

                if (key == c.SDLK_ESCAPE and mod == 0) {
                    actions.append(.ToggleCommandOverlay) catch |err| {
                        log.warn("failed to queue command overlay escape close action: {}", .{err});
                    };
                    return true;
                }

                if (!input_keys.isModifierKey(key)) {
                    actions.append(.{ .CommandOverlayKey = .{ .key = key, .mod = mod } }) catch |err| {
                        log.warn("failed to queue command overlay key input: {}", .{err});
                    };
                }
                return true;
            },
            c.SDL_EVENT_TEXT_INPUT => {
                const text = std.mem.span(event.text.text);
                if (text.len > 0) {
                    const copy = self.allocator.dupe(u8, text) catch |err| {
                        log.warn("failed to copy command overlay text input: {}", .{err});
                        return true;
                    };
                    actions.append(.{ .CommandOverlayTextInput = copy }) catch |err| {
                        self.allocator.free(copy);
                        log.warn("failed to queue command overlay text input: {}", .{err});
                    };
                }
                return true;
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const mouse_x: c_int = @intFromFloat(event.button.x);
                const mouse_y: c_int = @intFromFloat(event.button.y);
                if (event.button.button == c.SDL_BUTTON_LEFT and FullscreenOverlay.isCloseButtonHit(mouse_x, mouse_y, host)) {
                    actions.append(.ToggleCommandOverlay) catch |err| {
                        log.warn("failed to queue command overlay close action: {}", .{err});
                    };
                }
                return true;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                const mouse_x: c_int = @intFromFloat(event.motion.x);
                const mouse_y: c_int = @intFromFloat(event.motion.y);
                self.overlay.updateCloseHover(mouse_x, mouse_y, host);
                return true;
            },
            c.SDL_EVENT_KEY_UP, c.SDL_EVENT_TEXT_EDITING, c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_WHEEL => return true,
            else => return false,
        }
    }

    fn updateFn(self_ptr: *anyopaque, host: *const types.UiHost, _: *types.UiActionQueue) void {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));
        if (self.command_overlays.isVisible() and !self.overlay.visible) {
            self.overlay.show(host.now_ms);
        } else if (!self.command_overlays.isVisible() and self.overlay.visible and self.overlay.animation_state != .closing) {
            self.overlay.hide(host.now_ms);
        }
        _ = self.overlay.updateAnimation(host.now_ms);
    }

    fn hitTestFn(self_ptr: *anyopaque, host: *const types.UiHost, x: c_int, y: c_int) bool {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));
        return self.overlay.hitTest(host, x, y);
    }

    fn wantsFrameFn(self_ptr: *anyopaque, _: *const types.UiHost) bool {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));
        return self.overlay.wantsFrame();
    }

    fn renderFn(self_ptr: *anyopaque, host: *const types.UiHost, renderer: *c.SDL_Renderer, assets: *types.UiAssets) void {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));
        if (!self.overlay.visible) return;

        const progress = self.overlay.renderProgress(host.now_ms);
        self.overlay.render_alpha = progress;
        if (progress <= 0.001) return;
        defer self.markRenderedFrame();

        const panel = FullscreenOverlay.animatedOverlayRect(host, progress);
        self.overlay.renderFrame(renderer, host, panel, progress);

        const font_cache = assets.font_cache orelse return;
        const title_fonts = font_cache.get(dpi.scale(18, host.ui_scale)) catch return;
        const title_tex = search_utils.makeTextTexture(self.allocator, renderer, title_fonts.bold orelse title_fonts.regular, "Remote Terminal", host.theme.foreground) catch return;
        defer c.SDL_DestroyTexture(title_tex.tex);
        self.overlay.renderTitle(renderer, panel, title_tex.tex, title_tex.w, title_tex.h, host);
        FullscreenOverlay.renderTitleSeparator(renderer, host, panel, progress);
        self.overlay.renderCloseButton(renderer, host, panel);

        const terminal_font = assets.terminal_font orelse return;
        const terminal_rect = command_overlay_mod.terminalRectFromPanel(panel, host.ui_scale);
        const active_overlay = self.command_overlays.activeOverlay() orelse return;
        active_overlay.render(renderer, terminal_font, terminal_rect, host.now_ms, host.theme, host.ui_scale) catch |err| {
            log.warn("failed to render command overlay terminal: {}", .{err});
        };
    }

    fn deinitFn(self_ptr: *anyopaque, _: *c.SDL_Renderer) void {
        const self: *CommandOverlayComponent = @ptrCast(@alignCast(self_ptr));
        self.allocator.destroy(self);
    }

    const vtable = UiComponent.VTable{
        .deinit = deinitFn,
        .handleEvent = handleEventFn,
        .hitTest = hitTestFn,
        .update = updateFn,
        .render = renderFn,
        .wantsFrame = wantsFrameFn,
    };
};

fn testHost(theme: *const colors.Theme) types.UiHost {
    return .{
        .now_ms = 0,
        .window_w = 800,
        .window_h = 600,
        .ui_scale = 1.0,
        .grid_cols = 1,
        .grid_rows = 1,
        .cell_w = 800,
        .cell_h = 600,
        .term_cols = 80,
        .term_rows = 24,
        .view_mode = .Full,
        .focused_session = 0,
        .focused_cwd = null,
        .focused_has_foreground_process = false,
        .sessions = &[_]types.SessionUiInfo{},
        .theme = theme,
    };
}

fn keyDownEvent(key: c.SDL_Keycode, mod: c.SDL_Keymod) c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = c.SDL_EVENT_KEY_DOWN;
    event.key.key = key;
    event.key.mod = mod;
    return event;
}

test "escape closes remote terminal overlay instead of sending terminal input" {
    var theme = colors.Theme.default();
    var remote_terminals = try command_overlay_mod.CommandOverlaySet.init(std.testing.allocator, 1, "/bin/sh", .{}, "", theme);
    defer remote_terminals.deinit();
    remote_terminals.active_index = 0;

    var component = CommandOverlayComponent{
        .allocator = std.testing.allocator,
        .command_overlays = &remote_terminals,
    };
    component.overlay.visible = true;
    component.overlay.animation_state = .open;

    const host = testHost(&theme);
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();
    var event = keyDownEvent(c.SDLK_ESCAPE, 0);

    const ui_component = component.asComponent();
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &event, &actions));
    const action = actions.pop() orelse return error.TestExpectedNonNull;
    switch (action) {
        .ToggleCommandOverlay => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(actions.pop() == null);
}

test "rendered remote terminal frame clears first-frame render request" {
    var theme = colors.Theme.default();
    var remote_terminals = try command_overlay_mod.CommandOverlaySet.init(std.testing.allocator, 1, "/bin/sh", .{}, "", theme);
    defer remote_terminals.deinit();

    var component = CommandOverlayComponent{
        .allocator = std.testing.allocator,
        .command_overlays = &remote_terminals,
    };
    component.setOpen(true, 0);
    component.overlay.animation_state = .open;

    const host = testHost(&theme);
    const ui_component = component.asComponent();
    try std.testing.expect(ui_component.vtable.wantsFrame.?(ui_component.ptr, &host));

    component.markRenderedFrame();

    try std.testing.expect(!ui_component.vtable.wantsFrame.?(ui_component.ptr, &host));
}
