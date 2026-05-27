const std = @import("std");
const c = @import("../../c.zig");
const colors = @import("../../colors.zig");
const geom = @import("../../geom.zig");
const primitives = @import("../../gfx/primitives.zig");
const types = @import("../types.zig");
const UiComponent = @import("../component.zig").UiComponent;
const dpi = @import("../../dpi.zig");
const FirstFrameGuard = @import("../first_frame_guard.zig").FirstFrameGuard;
const ExpandingOverlay = @import("expanding_overlay.zig").ExpandingOverlay;
const flowing_line = @import("flowing_line.zig");
const search_utils = @import("search_utils.zig");

const log = std.log.scoped(.session_picker_overlay);

pub const SessionPickerOverlayComponent = struct {
    allocator: std.mem.Allocator,
    overlay: ExpandingOverlay = ExpandingOverlay.init(3, button_margin, button_size_small, button_size_large, button_animation_duration_ms),
    first_frame: FirstFrameGuard = .{},

    sessions: std.ArrayList(Session) = .{},
    filtered_indices: std.ArrayList(usize) = .{},
    search_query: std.ArrayList(u8) = .{},
    selected_index: usize = 0,
    hovered_entry: ?usize = null,
    escape_pressed: bool = false,
    flow_animation_start_ms: i64 = 0,

    const button_size_small: c_int = 40;
    const button_size_large: c_int = 480;
    const button_margin: c_int = 20;
    const button_animation_duration_ms: i64 = 200;
    const line_height: c_int = 32;
    const max_display: usize = 12;
    const search_bar_height: c_int = 28;
    const title = "Saved Sessions";

    pub const Session = struct {
        id: []const u8,
        label: []const u8,
        detail: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !*SessionPickerOverlayComponent {
        const self = try allocator.create(SessionPickerOverlayComponent);
        self.* = .{ .allocator = allocator };
        return self;
    }

    pub fn asComponent(self: *SessionPickerOverlayComponent) UiComponent {
        return .{
            .ptr = self,
            .vtable = &vtable,
            .z_index = 1000,
        };
    }

    pub fn addSession(self: *SessionPickerOverlayComponent, id: []const u8, label: []const u8, detail: []const u8) !void {
        const id_copy = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(id_copy);
        const label_copy = try self.allocator.dupe(u8, label);
        errdefer self.allocator.free(label_copy);
        const detail_copy = try self.allocator.dupe(u8, detail);
        errdefer self.allocator.free(detail_copy);

        try self.sessions.append(self.allocator, .{
            .id = id_copy,
            .label = label_copy,
            .detail = detail_copy,
        });
        self.refilter();
    }

    pub fn collapse(self: *SessionPickerOverlayComponent, now_ms: i64) void {
        self.closeOverlay(now_ms);
    }

    fn deinit(self_ptr: *anyopaque, _: *c.SDL_Renderer) void {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));
        self.clearSessions();
        self.sessions.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        self.search_query.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn clearSessions(self: *SessionPickerOverlayComponent) void {
        for (self.sessions.items) |session| {
            self.allocator.free(session.id);
            self.allocator.free(session.label);
            self.allocator.free(session.detail);
        }
        self.sessions.clearRetainingCapacity();
        self.filtered_indices.clearRetainingCapacity();
        self.selected_index = 0;
        self.hovered_entry = null;
    }

    fn refilter(self: *SessionPickerOverlayComponent) void {
        self.filtered_indices.clearRetainingCapacity();
        const query = std.mem.trim(u8, self.search_query.items, " \t");
        for (self.sessions.items, 0..) |session, idx| {
            if (self.filtered_indices.items.len >= max_display) break;
            if (sessionMatchesQuery(session, query)) {
                self.filtered_indices.append(self.allocator, idx) catch |err| {
                    log.warn("failed to append filtered session index: {}", .{err});
                    break;
                };
            }
        }
        if (self.selected_index >= self.filtered_indices.items.len) {
            self.selected_index = if (self.filtered_indices.items.len > 0) self.filtered_indices.items.len - 1 else 0;
        }
    }

    fn filteredSession(self: *SessionPickerOverlayComponent, display_idx: usize) ?Session {
        if (display_idx >= self.filtered_indices.items.len) return null;
        const source_idx = self.filtered_indices.items[display_idx];
        if (source_idx >= self.sessions.items.len) return null;
        return self.sessions.items[source_idx];
    }

    fn isActive(self: *const SessionPickerOverlayComponent) bool {
        return self.overlay.state == .Open or self.overlay.state == .Expanding;
    }

    fn handleEvent(self_ptr: *anyopaque, host: *const types.UiHost, event: *const c.SDL_Event, actions: *types.UiActionQueue) bool {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));

        if (event.type == c.SDL_EVENT_KEY_UP and self.escape_pressed) {
            if (event.key.key == c.SDLK_ESCAPE) {
                self.escape_pressed = false;
                return true;
            }
        }

        switch (event.type) {
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const mouse_x: c_int = @intFromFloat(event.button.x);
                const mouse_y: c_int = @intFromFloat(event.button.y);
                const rect = self.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
                const inside = geom.containsPoint(rect, mouse_x, mouse_y);

                if (inside and self.overlay.state == .Open) {
                    if (self.entryIndexAtPoint(host, mouse_y)) |idx| {
                        if (self.filteredSession(idx)) |session| {
                            self.emitOpenSession(actions, session.id);
                            self.closeOverlay(host.now_ms);
                        }
                        return true;
                    }
                    return true;
                }
                if (inside and self.overlay.state == .Expanding) return true;

                if (inside) {
                    switch (self.overlay.state) {
                        .Closed => self.openOverlay(host.now_ms),
                        .Open => self.closeOverlay(host.now_ms),
                        else => {},
                    }
                    return true;
                }

                if (self.isActive() and !inside) {
                    self.closeOverlay(host.now_ms);
                    return true;
                }
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                if (!self.isActive()) return false;
                const mouse_x: c_int = @intFromFloat(event.motion.x);
                const mouse_y: c_int = @intFromFloat(event.motion.y);
                const rect = self.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
                if (!geom.containsPoint(rect, mouse_x, mouse_y)) {
                    self.hovered_entry = null;
                    return true;
                }
                self.hovered_entry = self.entryIndexAtPoint(host, mouse_y);
                return true;
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_WHEEL => {
                if (self.isActive()) return true;
            },
            c.SDL_EVENT_KEY_DOWN => {
                const key = event.key.key;
                const mod = event.key.mod;
                const has_gui = (mod & c.SDL_KMOD_GUI) != 0;
                const has_shift = (mod & c.SDL_KMOD_SHIFT) != 0;
                const has_blocking_mod = (mod & (c.SDL_KMOD_CTRL | c.SDL_KMOD_ALT)) != 0;

                if (has_gui and has_shift and !has_blocking_mod and key == c.SDLK_S) {
                    if (self.overlay.state == .Open or self.overlay.state == .Expanding) {
                        self.closeOverlay(host.now_ms);
                    } else {
                        self.openOverlay(host.now_ms);
                    }
                    return true;
                }

                if (self.isActive()) {
                    if (key == c.SDLK_BACKSPACE) {
                        if (self.search_query.items.len > 0) {
                            self.search_query.items.len -= 1;
                            self.refilter();
                        }
                        return true;
                    }
                    if (key == c.SDLK_UP) {
                        if (self.filtered_indices.items.len > 0) {
                            self.selected_index = if (self.selected_index > 0) self.selected_index - 1 else self.filtered_indices.items.len - 1;
                        }
                        return true;
                    }
                    if (key == c.SDLK_DOWN) {
                        if (self.filtered_indices.items.len > 0) {
                            self.selected_index = if (self.selected_index + 1 < self.filtered_indices.items.len) self.selected_index + 1 else 0;
                        }
                        return true;
                    }
                    if (key == c.SDLK_RETURN or key == c.SDLK_KP_ENTER) {
                        if (self.filteredSession(self.selected_index)) |session| {
                            self.emitOpenSession(actions, session.id);
                            self.closeOverlay(host.now_ms);
                        }
                        return true;
                    }
                    if (key == c.SDLK_ESCAPE) {
                        self.escape_pressed = true;
                        self.closeOverlay(host.now_ms);
                        return true;
                    }
                    return true;
                }
            },
            c.SDL_EVENT_TEXT_INPUT => {
                if (self.isActive()) {
                    const text = std.mem.span(event.text.text);
                    self.search_query.appendSlice(self.allocator, text) catch |err| {
                        log.warn("failed to append session picker search input: {}", .{err});
                    };
                    self.refilter();
                    return true;
                }
            },
            c.SDL_EVENT_TEXT_EDITING => {
                if (self.isActive()) return true;
            },
            else => {},
        }

        return false;
    }

    fn openOverlay(self: *SessionPickerOverlayComponent, now_ms: i64) void {
        self.refilter();
        self.overlay.startExpanding(now_ms);
    }

    fn closeOverlay(self: *SessionPickerOverlayComponent, now_ms: i64) void {
        self.overlay.startCollapsing(now_ms);
        self.search_query.clearRetainingCapacity();
        self.refilter();
    }

    fn emitOpenSession(self: *SessionPickerOverlayComponent, actions: *types.UiActionQueue, session_id: []const u8) void {
        _ = self;
        const id_copy = actions.allocator.dupe(u8, session_id) catch return;
        actions.append(.{ .OpenNamedSession = id_copy }) catch {
            actions.allocator.free(id_copy);
        };
    }

    fn hitTest(self_ptr: *anyopaque, host: *const types.UiHost, x: c_int, y: c_int) bool {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));
        const rect = self.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
        return geom.containsPoint(rect, x, y);
    }

    fn update(self_ptr: *anyopaque, host: *const types.UiHost, _: *types.UiActionQueue) void {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));
        if (self.overlay.isAnimating() and self.overlay.isComplete(host.now_ms)) {
            self.overlay.state = switch (self.overlay.state) {
                .Expanding => .Open,
                .Collapsing => .Closed,
                else => self.overlay.state,
            };
            if (self.overlay.state == .Open) {
                self.first_frame.markTransition();
                self.flow_animation_start_ms = host.now_ms;
            }
            if (self.overlay.state == .Closed) {
                self.hovered_entry = null;
                self.flow_animation_start_ms = 0;
            }
        }
    }

    fn render(self_ptr: *anyopaque, host: *const types.UiHost, renderer: *c.SDL_Renderer, assets: *types.UiAssets) void {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));
        const rect = self.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
        const radius: c_int = 8;

        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
        const sel = host.theme.selection;
        _ = c.SDL_SetRenderDrawColor(renderer, sel.r, sel.g, sel.b, 245);
        primitives.fillRoundedRect(renderer, rect, radius);

        const accent = host.theme.accent;
        _ = c.SDL_SetRenderDrawColor(renderer, accent.r, accent.g, accent.b, 255);
        primitives.drawRoundedBorder(renderer, rect, radius);

        switch (self.overlay.state) {
            .Closed, .Collapsing, .Expanding => renderGlyph(renderer, rect, host.ui_scale, assets, host.theme),
            .Open => self.renderOverlay(renderer, host, rect, host.ui_scale, assets),
        }

        self.first_frame.markDrawn();
    }

    fn renderGlyph(renderer: *c.SDL_Renderer, rect: geom.Rect, ui_scale: f32, assets: *types.UiAssets, theme: *const colors.Theme) void {
        const cache = assets.font_cache orelse return;
        const font_size = dpi.scale(@max(11, @min(18, @divFloor(rect.h, 2))), ui_scale);
        const fonts = cache.get(font_size) catch return;
        const fg = theme.foreground;
        const fg_color = c.SDL_Color{ .r = fg.r, .g = fg.g, .b = fg.b, .a = 255 };
        const glyph = "Sess";
        renderText(renderer, fonts.regular, glyph, fg_color, rect.x + @divFloor(rect.w, 2), rect.y + @divFloor(rect.h, 2), .center);
    }

    fn renderOverlay(self: *SessionPickerOverlayComponent, renderer: *c.SDL_Renderer, host: *const types.UiHost, rect: geom.Rect, ui_scale: f32, assets: *types.UiAssets) void {
        const font_cache = assets.font_cache orelse return;
        const title_fonts = font_cache.get(dpi.scale(20, ui_scale)) catch return;
        const entry_fonts = font_cache.get(dpi.scale(15, ui_scale)) catch return;
        const detail_fonts = font_cache.get(dpi.scale(13, ui_scale)) catch return;
        const fg = host.theme.foreground;
        const title_color = c.SDL_Color{ .r = fg.r, .g = fg.g, .b = fg.b, .a = 255 };
        const detail_color = c.SDL_Color{ .r = 171, .g = 178, .b = 191, .a = 255 };

        const scaled_margin = dpi.scale(button_margin, ui_scale);
        const scaled_line_height = dpi.scale(line_height, ui_scale);
        var y_offset = rect.y + scaled_margin;

        renderText(renderer, title_fonts.regular, title, title_color, rect.x + @divFloor(rect.w, 2), y_offset, .top_center);
        y_offset += dpi.scale(30, ui_scale);

        const search_bar_rect = geom.Rect{
            .x = rect.x + scaled_margin,
            .y = y_offset,
            .w = rect.w - 2 * scaled_margin,
            .h = dpi.scale(search_bar_height, ui_scale),
        };
        search_utils.renderSearchBar(
            self.allocator,
            renderer,
            host,
            search_bar_rect,
            font_cache,
            self.search_query.items,
            self.filtered_indices.items.len,
            if (self.filtered_indices.items.len > 0) self.selected_index else null,
        ) catch |err| {
            log.warn("failed to render session search bar: {}", .{err});
        };
        y_offset += dpi.scale(search_bar_height + 10, ui_scale);

        for (self.filtered_indices.items, 0..) |source_idx, display_idx| {
            const session = self.sessions.items[source_idx];
            const is_selected = display_idx == self.selected_index;
            const is_hovered = if (self.hovered_entry) |h| h == display_idx else false;
            if (is_selected or is_hovered) {
                const alpha: u8 = if (is_selected) 64 else 40;
                _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);
                _ = c.SDL_SetRenderDrawColor(renderer, host.theme.accent.r, host.theme.accent.g, host.theme.accent.b, alpha);
                _ = c.SDL_RenderFillRect(renderer, &c.SDL_FRect{
                    .x = @floatFromInt(rect.x + dpi.scale(12, ui_scale)),
                    .y = @floatFromInt(y_offset - dpi.scale(4, ui_scale)),
                    .w = @floatFromInt(rect.w - dpi.scale(24, ui_scale)),
                    .h = @floatFromInt(scaled_line_height),
                });
            }

            renderText(renderer, entry_fonts.regular, session.label, title_color, rect.x + scaled_margin, y_offset, .top_left);
            renderText(renderer, detail_fonts.regular, session.detail, detail_color, rect.x + rect.w - scaled_margin, y_offset + dpi.scale(2, ui_scale), .top_right);

            if (is_selected) {
                const flow_y = y_offset + @divFloor(scaled_line_height, 2);
                flowing_line.render(renderer, self.flow_animation_start_ms, host.now_ms, rect, flow_y, ui_scale, host.theme);
            }

            y_offset += scaled_line_height;
        }

        if (self.filtered_indices.items.len == 0) {
            renderText(renderer, entry_fonts.regular, "No saved sessions", detail_color, rect.x + @divFloor(rect.w, 2), y_offset, .top_center);
        }

        const content_height = scaled_margin * 2 + dpi.scale(30 + search_bar_height + 10, ui_scale) +
            @as(c_int, @intCast(@max(self.filtered_indices.items.len, 1))) * scaled_line_height;
        self.overlay.setContentHeight(content_height);
    }

    fn entryIndexAtPoint(self: *SessionPickerOverlayComponent, host: *const types.UiHost, y: c_int) ?usize {
        const rect = self.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
        const scaled_margin = dpi.scale(button_margin, host.ui_scale);
        const scaled_lh = dpi.scale(line_height, host.ui_scale);
        const start_y = rect.y + scaled_margin + dpi.scale(30 + search_bar_height + 10, host.ui_scale);
        if (y < start_y) return null;
        const rel = y - start_y;
        const idx: usize = @intCast(@divFloor(rel, scaled_lh));
        if (idx >= self.filtered_indices.items.len) return null;
        return idx;
    }

    fn wantsFrame(self_ptr: *anyopaque, _: *const types.UiHost) bool {
        const self: *SessionPickerOverlayComponent = @ptrCast(@alignCast(self_ptr));
        return self.overlay.isAnimating() or self.first_frame.wantsFrame() or self.overlay.state == .Open;
    }

    const vtable = UiComponent.VTable{
        .handleEvent = handleEvent,
        .hitTest = hitTest,
        .update = update,
        .render = render,
        .deinit = deinit,
        .wantsFrame = wantsFrame,
    };
};

fn sessionMatchesQuery(session: SessionPickerOverlayComponent.Session, query: []const u8) bool {
    if (query.len == 0) return true;
    return search_utils.findCaseInsensitive(session.label, query, 0) != null or
        search_utils.findCaseInsensitive(session.id, query, 0) != null or
        search_utils.findCaseInsensitive(session.detail, query, 0) != null;
}

const TextAnchor = enum { center, top_left, top_center, top_right };

fn renderText(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    text: []const u8,
    color: c.SDL_Color,
    x: c_int,
    y: c_int,
    anchor: TextAnchor,
) void {
    const surface = c.TTF_RenderText_Blended(font, text.ptr, @intCast(text.len), color) orelse return;
    defer c.SDL_DestroySurface(surface);
    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return;
    defer c.SDL_DestroyTexture(texture);

    var w_f: f32 = 0;
    var h_f: f32 = 0;
    _ = c.SDL_GetTextureSize(texture, &w_f, &h_f);

    var draw_x: c_int = x;
    var draw_y: c_int = y;
    const w_i: c_int = @intFromFloat(w_f);
    const h_i: c_int = @intFromFloat(h_f);
    switch (anchor) {
        .center => {
            draw_x -= @divFloor(w_i, 2);
            draw_y -= @divFloor(h_i, 2);
        },
        .top_left => {},
        .top_center => draw_x -= @divFloor(w_i, 2),
        .top_right => draw_x -= w_i,
    }

    _ = c.SDL_RenderTexture(renderer, texture, null, &c.SDL_FRect{
        .x = @floatFromInt(draw_x),
        .y = @floatFromInt(draw_y),
        .w = w_f,
        .h = h_f,
    });
}

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

fn mouseButtonEvent(event_type: u32, button: u8, x: f32, y: f32) c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = event_type;
    event.button.button = button;
    event.button.x = x;
    event.button.y = y;
    return event;
}

fn mouseMotionEvent(x: f32, y: f32) c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = c.SDL_EVENT_MOUSE_MOTION;
    event.motion.x = x;
    event.motion.y = y;
    return event;
}

fn mouseWheelEvent() c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = c.SDL_EVENT_MOUSE_WHEEL;
    event.wheel.y = 1;
    event.wheel.integer_y = 1;
    return event;
}

fn textInputEvent(text: [:0]const u8) c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = c.SDL_EVENT_TEXT_INPUT;
    event.text.text = text.ptr;
    return event;
}

fn textEditingEvent(text: [:0]const u8) c.SDL_Event {
    var event: c.SDL_Event = undefined;
    @memset(std.mem.asBytes(&event), 0);
    event.type = c.SDL_EVENT_TEXT_EDITING;
    event.edit.text = text.ptr;
    event.edit.start = 0;
    event.edit.length = @intCast(text.len);
    return event;
}

fn openComponentForTest(component: *SessionPickerOverlayComponent) void {
    component.overlay.startExpanding(0);
    component.overlay.state = .Open;
}

fn deinitTestComponent(component: *SessionPickerOverlayComponent) void {
    component.clearSessions();
    component.sessions.deinit(component.allocator);
    component.filtered_indices.deinit(component.allocator);
    component.search_query.deinit(component.allocator);
}

test "command shift s opens saved session picker" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);

    const host = testHost(&theme);
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();
    var event = keyDownEvent(c.SDLK_S, c.SDL_KMOD_GUI | c.SDL_KMOD_SHIFT);

    const ui_component = component.asComponent();
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &event, &actions));
    try std.testing.expectEqual(ExpandingOverlay.State.Expanding, component.overlay.state);
    try std.testing.expect(actions.pop() == null);
}

test "enter emits selected saved session action" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);
    try component.addSession("Alpha", "Alpha Display", "Alpha - 2 terminals");
    component.overlay.state = .Open;

    const host = testHost(&theme);
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();
    var event = keyDownEvent(c.SDLK_RETURN, 0);

    const ui_component = component.asComponent();
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &event, &actions));
    const action = actions.pop() orelse return error.TestExpectedNonNull;
    switch (action) {
        .OpenNamedSession => |session_id| {
            defer std.testing.allocator.free(session_id);
            try std.testing.expectEqualStrings("Alpha", session_id);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(actions.pop() == null);
}

test "clicking session picker search area keeps picker open" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);
    try component.addSession("Alpha", "Alpha Display", "Alpha - 2 terminals");
    try component.search_query.appendSlice(component.allocator, "alp");
    component.refilter();
    openComponentForTest(&component);

    var host = testHost(&theme);
    host.now_ms = 1000;
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();

    const rect = component.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
    var event = mouseButtonEvent(
        c.SDL_EVENT_MOUSE_BUTTON_DOWN,
        c.SDL_BUTTON_LEFT,
        @floatFromInt(rect.x + @divFloor(rect.w, 2)),
        @floatFromInt(rect.y + dpi.scale(SessionPickerOverlayComponent.button_margin + 34, host.ui_scale)),
    );

    const ui_component = component.asComponent();
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &event, &actions));
    try std.testing.expectEqual(ExpandingOverlay.State.Open, component.overlay.state);
    try std.testing.expectEqualStrings("alp", component.search_query.items);
    try std.testing.expect(actions.pop() == null);
}

test "expanding session picker consumes text input" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);
    try component.addSession("Alpha", "Alpha Display", "Alpha - 2 terminals");

    const host = testHost(&theme);
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();

    const ui_component = component.asComponent();
    var open_event = keyDownEvent(c.SDLK_S, c.SDL_KMOD_GUI | c.SDL_KMOD_SHIFT);
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &open_event, &actions));
    try std.testing.expectEqual(ExpandingOverlay.State.Expanding, component.overlay.state);

    var text_event = textInputEvent("a");
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &text_event, &actions));
    try std.testing.expectEqualStrings("a", component.search_query.items);
    try std.testing.expect(actions.pop() == null);
}

test "active session picker consumes ime editing events" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);
    try component.addSession("Alpha", "Alpha Display", "Alpha - 2 terminals");

    const host = testHost(&theme);
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();

    const ui_component = component.asComponent();
    var open_event = keyDownEvent(c.SDLK_S, c.SDL_KMOD_GUI | c.SDL_KMOD_SHIFT);
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &open_event, &actions));
    try std.testing.expectEqual(ExpandingOverlay.State.Expanding, component.overlay.state);

    var editing_event = textEditingEvent("a");
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &editing_event, &actions));
    try std.testing.expectEqual(@as(usize, 0), component.search_query.items.len);
    try std.testing.expect(actions.pop() == null);
}

test "open session picker consumes pointer events" {
    var theme = colors.Theme.default();
    var component = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer deinitTestComponent(&component);
    try component.addSession("Alpha", "Alpha Display", "Alpha - 2 terminals");
    openComponentForTest(&component);

    var host = testHost(&theme);
    host.now_ms = 1000;
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();

    const rect = component.overlay.rect(host.now_ms, host.window_w, host.window_h, host.ui_scale);
    const ui_component = component.asComponent();
    var motion = mouseMotionEvent(@floatFromInt(rect.x + 20), @floatFromInt(rect.y + 20));
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &motion, &actions));

    var button_up = mouseButtonEvent(
        c.SDL_EVENT_MOUSE_BUTTON_UP,
        c.SDL_BUTTON_LEFT,
        @floatFromInt(rect.x + 20),
        @floatFromInt(rect.y + 20),
    );
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &button_up, &actions));

    var wheel = mouseWheelEvent();
    try std.testing.expect(ui_component.vtable.handleEvent.?(ui_component.ptr, &host, &wheel, &actions));
    try std.testing.expect(actions.pop() == null);
}

test "sessionMatchesQuery checks label id and detail" {
    const session = SessionPickerOverlayComponent.Session{
        .id = "SleepySloth",
        .label = "Sleepy Sloth",
        .detail = "3 terminals",
    };

    try std.testing.expect(sessionMatchesQuery(session, ""));
    try std.testing.expect(sessionMatchesQuery(session, "sleepy"));
    try std.testing.expect(sessionMatchesQuery(session, "sloth"));
    try std.testing.expect(sessionMatchesQuery(session, "3 term"));
    try std.testing.expect(!sessionMatchesQuery(session, "missing"));
}
