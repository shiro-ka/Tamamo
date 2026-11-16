const std = @import("std");
const Io = std.Io;

const Item = struct {
    label: []const u8,
    value: []const u8,
};

pub fn run(io: Io, out: *Io.Writer) !void {
    var buffer: [4096]u8 = undefined;
    const os_release = try Io.Dir.cwd().readFile(io, "/etc/os-release", &buffer);

    const uts = std.posix.uname();
    var kernel_buffer: [160]u8 = undefined;
    const kernel = try std.fmt.bufPrint(&kernel_buffer, "{s} {s}", .{
        std.mem.sliceTo(&uts.sysname, 0),
        std.mem.sliceTo(&uts.release, 0),
    });

    var uptime_file: [64]u8 = undefined;
    const proc_uptime = try Io.Dir.cwd().readFile(io, "/proc/uptime", &uptime_file);
    var uptime_buffer: [32]u8 = undefined;
    const uptime = try formatUptime(&uptime_buffer, try uptimeSeconds(proc_uptime));

    const items = [_]Item{
        .{ .label = "OS", .value = prettyName(os_release) orelse "unknown" },
        .{ .label = "Kernel", .value = kernel },
        .{ .label = "Uptime", .value = uptime },
    };

    try out.writeAll("( ' < }<3 ~ Tamamo INFO ~ . o O *\n");
    try printItems(out, &items);
}

fn uptimeSeconds(proc_uptime: []const u8) !u64 {
    const end = std.mem.indexOfScalar(u8, proc_uptime, '.') orelse return error.InvalidUptime;
    return std.fmt.parseInt(u64, proc_uptime[0..end], 10);
}

fn formatUptime(buffer: []u8, seconds: u64) ![]const u8 {
    const days = seconds / std.time.s_per_day;
    const hours = seconds % std.time.s_per_day / std.time.s_per_hour;
    const minutes = seconds % std.time.s_per_hour / std.time.s_per_min;

    if (days > 0) return std.fmt.bufPrint(buffer, "{d}d, {d}h {d}m", .{ days, hours, minutes });
    if (hours > 0) return std.fmt.bufPrint(buffer, "{d}h {d}m", .{ hours, minutes });
    return std.fmt.bufPrint(buffer, "{d}m", .{minutes});
}

fn printItems(out: *Io.Writer, items: []const Item) !void {
    var width: usize = 0;
    for (items) |item| width = @max(width, item.label.len);

    for (items) |item| {
        try out.splatByteAll(' ', width - item.label.len);
        try out.print("{s}: {s}\n", .{ item.label, item.value });
    }
}

fn prettyName(os_release: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, os_release, '\n');
    while (lines.next()) |line| {
        if (std.mem.cutPrefix(u8, line, "PRETTY_NAME=")) |value| {
            return std.mem.trim(u8, value, "\"");
        }
    }
    return null;
}

test prettyName {
    try std.testing.expectEqualStrings(
        "Fedora Linux 44 (Silverblue)",
        prettyName("NAME=\"Fedora Linux\"\nPRETTY_NAME=\"Fedora Linux 44 (Silverblue)\"\nID=fedora\n").?,
    );
    try std.testing.expectEqual(null, prettyName("NAME=\"Fedora Linux\"\n"));
}

test printItems {
    var buffer: [64]u8 = undefined;
    var out: Io.Writer = .fixed(&buffer);
    try printItems(&out, &.{
        .{ .label = "OS", .value = "Tamamo OS 0" },
        .{ .label = "Kernel", .value = "Linux 7.3.3" },
    });
    try std.testing.expectEqualStrings("    OS: Tamamo OS 0\nKernel: Linux 7.3.3\n", out.buffered());
}

test uptimeSeconds {
    try std.testing.expectEqual(12345, try uptimeSeconds("12345.67 45678.90\n"));
    try std.testing.expectError(error.InvalidUptime, uptimeSeconds(""));
}

test formatUptime {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("5m", try formatUptime(&buffer, 5 * 60));
    try std.testing.expectEqualStrings("2h 5m", try formatUptime(&buffer, 2 * 3600 + 5 * 60));
    try std.testing.expectEqualStrings("1d, 0h 7m", try formatUptime(&buffer, 86400 + 7 * 60));
    try std.testing.expectEqualStrings("3d, 4h 12m", try formatUptime(&buffer, 3 * 86400 + 4 * 3600 + 12 * 60));
    try std.testing.expectEqualStrings("12d, 23h 59m", try formatUptime(&buffer, 12 * 86400 + 23 * 3600 + 59 * 60 + 59));
}
