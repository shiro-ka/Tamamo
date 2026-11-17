const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const localtime = @import("localtime.zig");

pub const Item = struct {
    label: []const u8,
    value: []const u8,
};

pub fn printGroups(out: *Io.Writer, groups: []const []const Item) !void {
    var width: usize = 0;
    for (groups) |items| {
        for (items) |item| width = @max(width, item.label.len);
    }

    for (groups) |items| {
        if (items.len == 0) continue;
        try out.writeAll("\n");
        for (items) |item| {
            if (item.label.len == 0) {
                try out.splatByteAll(' ', width + 2);
                try out.print("{s}\n", .{item.value});
            } else {
                try out.splatByteAll(' ', width - item.label.len);
                try out.print("{s}: {s}\n", .{ item.label, item.value });
            }
        }
    }
}

test printGroups {
    var buffer: [160]u8 = undefined;
    var out: Io.Writer = .fixed(&buffer);
    try printGroups(&out, &.{
        &.{ .{ .label = "OS", .value = "Tamamo OS 0" }, .{ .label = "Kernel", .value = "Linux 7.3.3" } },
        &.{},
        &.{ .{ .label = "Diff", .value = "1 upgraded" }, .{ .label = "", .value = "kernel 7.3.3 -> 7.3.4" } },
    });
    try std.testing.expectEqualStrings(
        "\n    OS: Tamamo OS 0\nKernel: Linux 7.3.3\n\n  Diff: 1 upgraded\n        kernel 7.3.3 -> 7.3.4\n",
        out.buffered(),
    );
}

pub fn formatDuration(arena: Allocator, seconds: u64) ![]const u8 {
    const days = seconds / std.time.s_per_day;
    const hours = seconds % std.time.s_per_day / std.time.s_per_hour;
    const minutes = seconds % std.time.s_per_hour / std.time.s_per_min;

    if (days > 0) return std.fmt.allocPrint(arena, "{d}d, {d}h {d}m", .{ days, hours, minutes });
    if (hours > 0) return std.fmt.allocPrint(arena, "{d}h {d}m", .{ hours, minutes });
    return std.fmt.allocPrint(arena, "{d}m", .{minutes});
}

test formatDuration {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("5m", try formatDuration(arena, 5 * 60));
    try std.testing.expectEqualStrings("2h 5m", try formatDuration(arena, 2 * 3600 + 5 * 60));
    try std.testing.expectEqualStrings("1d, 0h 7m", try formatDuration(arena, 86400 + 7 * 60));
    try std.testing.expectEqualStrings("3d, 4h 12m", try formatDuration(arena, 3 * 86400 + 4 * 3600 + 12 * 60));
    try std.testing.expectEqualStrings("12d, 23h 59m", try formatDuration(arena, 12 * 86400 + 23 * 3600 + 59 * 60 + 59));
}

pub fn timeValue(arena: Allocator, tz: std.tz.Tz, timestamp: i64, note: []const u8) ![]const u8 {
    const when = try localtime.format(arena, timestamp, localtime.offsetAt(tz, timestamp));
    return std.fmt.allocPrint(arena, "{s} ({s})", .{ when, note });
}

pub fn agoText(arena: Allocator, timestamp: i64, now: i64) ![]const u8 {
    const elapsed = try formatDuration(arena, @intCast(@max(now - timestamp, 0)));
    return std.fmt.allocPrint(arena, "{s} ago", .{elapsed});
}
