const std = @import("std");
const c = @import("../../c.zig");
const colors = @import("../../colors.zig");
const types = @import("../types.zig");
const UiComponent = @import("../component.zig").UiComponent;
const HelpOverlayComponent = @import("help_overlay.zig").HelpOverlayComponent;
const WorktreeOverlayComponent = @import("worktree_overlay.zig").WorktreeOverlayComponent;
const RecentFoldersOverlayComponent = @import("recent_folders_overlay.zig").RecentFoldersOverlayComponent;
const SessionPickerOverlayComponent = @import("session_picker_overlay.zig").SessionPickerOverlayComponent;

const ExpandingOverlay = @import("expanding_overlay.zig").ExpandingOverlay;

pub const PillGroupComponent = struct {
    allocator: std.mem.Allocator,
    help: *HelpOverlayComponent,
    recent_folders: *RecentFoldersOverlayComponent,
    worktree: *WorktreeOverlayComponent,
    sessions: *SessionPickerOverlayComponent,
    last_help_state: ExpandingOverlay.State = .Closed,
    last_recent_folders_state: ExpandingOverlay.State = .Closed,
    last_worktree_state: ExpandingOverlay.State = .Closed,
    last_sessions_state: ExpandingOverlay.State = .Closed,

    pub fn create(
        allocator: std.mem.Allocator,
        help: *HelpOverlayComponent,
        recent_folders: *RecentFoldersOverlayComponent,
        worktree: *WorktreeOverlayComponent,
        sessions: *SessionPickerOverlayComponent,
    ) !UiComponent {
        const comp = try allocator.create(PillGroupComponent);
        comp.* = .{
            .allocator = allocator,
            .help = help,
            .recent_folders = recent_folders,
            .worktree = worktree,
            .sessions = sessions,
        };

        return UiComponent{
            .ptr = comp,
            .vtable = &vtable,
            .z_index = 999,
        };
    }

    fn deinit(self_ptr: *anyopaque, _: *c.SDL_Renderer) void {
        const self: *PillGroupComponent = @ptrCast(@alignCast(self_ptr));
        self.allocator.destroy(self);
    }

    fn handleEvent(_: *anyopaque, _: *const types.UiHost, _: *const c.SDL_Event, _: *types.UiActionQueue) bool {
        return false;
    }

    fn hitTest(_: *anyopaque, _: *const types.UiHost, _: c_int, _: c_int) bool {
        return false;
    }

    fn update(self_ptr: *anyopaque, host: *const types.UiHost, _: *types.UiActionQueue) void {
        const self: *PillGroupComponent = @ptrCast(@alignCast(self_ptr));

        const help_state = self.help.overlay.state;
        const recent_folders_state = self.recent_folders.overlay.state;
        const worktree_state = self.worktree.overlay.state;
        const sessions_state = self.sessions.overlay.state;

        const help_started_expanding = self.last_help_state != .Expanding and help_state == .Expanding;
        const recent_folders_started_expanding = self.last_recent_folders_state != .Expanding and recent_folders_state == .Expanding;
        const worktree_started_expanding = self.last_worktree_state != .Expanding and worktree_state == .Expanding;
        const sessions_started_expanding = self.last_sessions_state != .Expanding and sessions_state == .Expanding;

        // When one overlay starts expanding, collapse the others
        if (help_started_expanding) {
            if (recent_folders_state == .Open or recent_folders_state == .Expanding) {
                self.recent_folders.overlay.startCollapsing(host.now_ms);
            }
            if (worktree_state == .Open or worktree_state == .Expanding) {
                self.worktree.overlay.startCollapsing(host.now_ms);
            }
            if (sessions_state == .Open or sessions_state == .Expanding) {
                self.sessions.collapse(host.now_ms);
            }
        }

        if (recent_folders_started_expanding) {
            if (help_state == .Open or help_state == .Expanding) {
                self.help.overlay.startCollapsing(host.now_ms);
            }
            if (worktree_state == .Open or worktree_state == .Expanding) {
                self.worktree.overlay.startCollapsing(host.now_ms);
            }
            if (sessions_state == .Open or sessions_state == .Expanding) {
                self.sessions.collapse(host.now_ms);
            }
        }

        if (worktree_started_expanding) {
            if (help_state == .Open or help_state == .Expanding) {
                self.help.overlay.startCollapsing(host.now_ms);
            }
            if (recent_folders_state == .Open or recent_folders_state == .Expanding) {
                self.recent_folders.overlay.startCollapsing(host.now_ms);
            }
            if (sessions_state == .Open or sessions_state == .Expanding) {
                self.sessions.collapse(host.now_ms);
            }
        }

        if (sessions_started_expanding) {
            if (help_state == .Open or help_state == .Expanding) {
                self.help.overlay.startCollapsing(host.now_ms);
            }
            if (recent_folders_state == .Open or recent_folders_state == .Expanding) {
                self.recent_folders.overlay.startCollapsing(host.now_ms);
            }
            if (worktree_state == .Open or worktree_state == .Expanding) {
                self.worktree.overlay.startCollapsing(host.now_ms);
            }
        }

        self.last_help_state = help_state;
        self.last_recent_folders_state = recent_folders_state;
        self.last_worktree_state = worktree_state;
        self.last_sessions_state = sessions_state;
    }

    fn render(_: *anyopaque, _: *const types.UiHost, _: *c.SDL_Renderer, _: *types.UiAssets) void {}

    fn deinitComp(self_ptr: *anyopaque, renderer: *c.SDL_Renderer) void {
        deinit(self_ptr, renderer);
    }

    const vtable = UiComponent.VTable{
        .handleEvent = handleEvent,
        .hitTest = hitTest,
        .update = update,
        .render = render,
        .deinit = deinitComp,
    };
};

fn testHost(theme: *const colors.Theme) types.UiHost {
    return .{
        .now_ms = 1000,
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

test "pill group clears session picker search when collapsing it" {
    var theme = colors.Theme.default();
    var help = HelpOverlayComponent{ .allocator = std.testing.allocator };
    var recent_folders = RecentFoldersOverlayComponent{ .allocator = std.testing.allocator };
    defer recent_folders.all_folders.deinit(std.testing.allocator);
    defer recent_folders.filtered_indices.deinit(std.testing.allocator);
    defer recent_folders.search_query.deinit(std.testing.allocator);
    var worktree = WorktreeOverlayComponent{ .allocator = std.testing.allocator };
    defer worktree.worktrees.deinit(std.testing.allocator);
    defer worktree.create_input.deinit(std.testing.allocator);
    var sessions = SessionPickerOverlayComponent{ .allocator = std.testing.allocator };
    defer sessions.sessions.deinit(std.testing.allocator);
    defer sessions.filtered_indices.deinit(std.testing.allocator);
    defer sessions.search_query.deinit(std.testing.allocator);

    help.overlay.state = .Expanding;
    sessions.overlay.state = .Open;
    try sessions.search_query.appendSlice(sessions.allocator, "alpha");

    var group = PillGroupComponent{
        .allocator = std.testing.allocator,
        .help = &help,
        .recent_folders = &recent_folders,
        .worktree = &worktree,
        .sessions = &sessions,
    };
    var actions = types.UiActionQueue.init(std.testing.allocator);
    defer actions.deinit();

    const host = testHost(&theme);
    PillGroupComponent.update(@ptrCast(&group), &host, &actions);

    try std.testing.expectEqual(ExpandingOverlay.State.Collapsing, sessions.overlay.state);
    try std.testing.expectEqual(@as(usize, 0), sessions.search_query.items.len);
}
