const std = @import("std");
const runtime = @import("app/runtime.zig");
const logging = @import("logging.zig");
const cli = @import("cli.zig");

pub const std_options: std.Options = .{
    // Keep compile-time logging permissive; runtime filtering is handled by
    // logging.zig with the user-configured minimum level.
    .log_level = .debug,
    .logFn = logging.logFn,
};

pub fn main() !void {
    var options = try cli.parseProcessArgs(std.heap.page_allocator);
    defer options.deinit(std.heap.page_allocator);
    const channel_name = options.channel_name orelse return error.MissingInstanceName;
    const session_id = options.session_name orelse return error.MissingSessionName;
    const cute_name = cli.lookupCuteSessionName(session_id);
    try runtime.run(.{
        .channel_name = channel_name,
        .session_id = session_id,
        .session_display_name = if (cute_name) |name| name.display_name else session_id,
        .session_emoji = if (cute_name) |name| name.emoji else "",
    });
}

test {
    _ = @import("cli.zig");
    _ = @import("app/layout.zig");
    _ = @import("app/runtime.zig");
    _ = @import("app/runtime_instance.zig");
    _ = @import("input/mapper.zig");
    _ = @import("ui/components/diff_comment_layout.zig");
}

test "new terminal grid split starts stacked" {
    const GridLayout = @import("app/grid_layout.zig").GridLayout;
    const dims = GridLayout.calculateDimensions(2);
    try std.testing.expectEqual(@as(usize, 1), dims.cols);
    try std.testing.expectEqual(@as(usize, 2), dims.rows);
}
