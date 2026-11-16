const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ostree = @import("ostree.zig");
const localtime = @import("localtime.zig");

const header = "( ' < }<3 ~ Tamamo INFO ~ . o O *\n";

const Item = struct {
    label: []const u8,
    value: []const u8,
};

pub fn run(arena: Allocator, io: Io, out: *Io.Writer) !void {
    const os_release = try Io.Dir.cwd().readFileAlloc(io, "/etc/os-release", arena, .limited(1 << 16));
    const now = Io.Clock.real.now(io).toSeconds();

    var items: std.ArrayList(Item) = .empty;
    try items.append(arena, .{ .label = "OS", .value = prettyName(os_release) orelse "unknown" });
    try items.append(arena, .{ .label = "Kernel", .value = try kernelValue(arena) });
    try items.append(arena, .{ .label = "Uptime", .value = try uptimeValue(arena, io) });
    try items.append(arena, .{ .label = "Memory", .value = try memoryValue(arena, io) });

    if (ostree.deployments(arena, io)) |deployments| {
        if (ostree.booted(deployments)) |booted| {
            try items.append(arena, .{ .label = "Built", .value = try builtValue(arena, io, booted.timestamp, now) });
        }
    } else |_| {}
    if (commit(os_release)) |value| try items.append(arena, .{ .label = "Commit", .value = value });

    try out.writeAll(header);
    try printItems(out, items.items);
}

fn printItems(out: *Io.Writer, items: []const Item) !void {
    var width: usize = 0;
    for (items) |item| width = @max(width, item.label.len);

    for (items) |item| {
        try out.splatByteAll(' ', width - item.label.len);
        try out.print("{s}: {s}\n", .{ item.label, item.value });
    }
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

fn lineValue(text: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.cutPrefix(u8, line, prefix)) |value| return value;
    }
    return null;
}

fn prettyName(os_release: []const u8) ?[]const u8 {
    const value = lineValue(os_release, "PRETTY_NAME=") orelse return null;
    return std.mem.trim(u8, value, "\"");
}

test prettyName {
    try std.testing.expectEqualStrings(
        "Fedora Linux 44 (Silverblue)",
        prettyName("NAME=\"Fedora Linux\"\nPRETTY_NAME=\"Fedora Linux 44 (Silverblue)\"\nID=fedora\n").?,
    );
    try std.testing.expectEqual(null, prettyName("NAME=\"Fedora Linux\"\n"));
}

fn commit(os_release: []const u8) ?[]const u8 {
    const build_id = std.mem.trim(u8, lineValue(os_release, "BUILD_ID=") orelse return null, "\"");
    var parts = std.mem.splitScalar(u8, build_id, '.');
    _ = parts.next();
    _ = parts.next();
    return parts.next();
}

test commit {
    try std.testing.expectEqualStrings("147d64b", commit("NAME=\"Tamamo OS\"\nBUILD_ID=\"0.20261116.147d64b\"\n").?);
    try std.testing.expectEqual(null, commit("BUILD_ID=\"0.20261116\"\n"));
    try std.testing.expectEqual(null, commit("NAME=\"Debian\"\n"));
}

fn kernelValue(arena: Allocator) ![]const u8 {
    const uts = std.posix.uname();
    return std.fmt.allocPrint(arena, "{s} {s}", .{
        std.mem.sliceTo(&uts.sysname, 0),
        std.mem.sliceTo(&uts.release, 0),
    });
}

fn uptimeValue(arena: Allocator, io: Io) ![]const u8 {
    var file_buffer: [64]u8 = undefined;
    const proc_uptime = try Io.Dir.cwd().readFile(io, "/proc/uptime", &file_buffer);
    return formatDuration(arena, try uptimeSeconds(proc_uptime));
}

fn uptimeSeconds(proc_uptime: []const u8) !u64 {
    const end = std.mem.indexOfScalar(u8, proc_uptime, '.') orelse return error.InvalidUptime;
    return std.fmt.parseInt(u64, proc_uptime[0..end], 10);
}

fn formatDuration(arena: Allocator, seconds: u64) ![]const u8 {
    const days = seconds / std.time.s_per_day;
    const hours = seconds % std.time.s_per_day / std.time.s_per_hour;
    const minutes = seconds % std.time.s_per_hour / std.time.s_per_min;

    if (days > 0) return std.fmt.allocPrint(arena, "{d}d, {d}h {d}m", .{ days, hours, minutes });
    if (hours > 0) return std.fmt.allocPrint(arena, "{d}h {d}m", .{ hours, minutes });
    return std.fmt.allocPrint(arena, "{d}m", .{minutes});
}

test uptimeSeconds {
    try std.testing.expectEqual(12345, try uptimeSeconds("12345.67 45678.90\n"));
    try std.testing.expectError(error.InvalidUptime, uptimeSeconds(""));
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

fn memoryValue(arena: Allocator, io: Io) ![]const u8 {
    var file_buffer: [4096]u8 = undefined;
    const meminfo = try Io.Dir.cwd().readFile(io, "/proc/meminfo", &file_buffer);
    const total_kib = try meminfoKib(meminfo, "MemTotal:");
    const available_kib = try meminfoKib(meminfo, "MemAvailable:");
    return formatMemory(arena, total_kib - available_kib, total_kib);
}

fn meminfoKib(meminfo: []const u8, prefix: []const u8) !u64 {
    const value = lineValue(meminfo, prefix) orelse return error.InvalidMeminfo;
    const number = std.mem.trim(u8, std.mem.trimEnd(u8, value, "kB"), " ");
    return std.fmt.parseInt(u64, number, 10);
}

fn formatMemory(arena: Allocator, used_kib: u64, total_kib: u64) ![]const u8 {
    const kib_per_gib: f64 = 1024 * 1024;
    const used: f64 = @as(f64, @floatFromInt(used_kib)) / kib_per_gib;
    const total: f64 = @as(f64, @floatFromInt(total_kib)) / kib_per_gib;
    const percent = (used_kib * 100 + total_kib / 2) / total_kib;
    return std.fmt.allocPrint(arena, "{d:.1} / {d:.1} GiB ({d}%)", .{ used, total, percent });
}

test meminfoKib {
    const meminfo = "MemTotal:       16148572 kB\nMemFree:         1234567 kB\nMemAvailable:   10733492 kB\n";
    try std.testing.expectEqual(16148572, try meminfoKib(meminfo, "MemTotal:"));
    try std.testing.expectEqual(10733492, try meminfoKib(meminfo, "MemAvailable:"));
    try std.testing.expectError(error.InvalidMeminfo, meminfoKib(meminfo, "SwapTotal:"));
}

test formatMemory {
    const allocator = std.testing.allocator;
    const text = try formatMemory(allocator, 5415080, 16148572);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("5.2 / 15.4 GiB (34%)", text);
}

fn builtValue(arena: Allocator, io: Io, timestamp: i64, now: i64) ![]const u8 {
    const when = try localtime.format(arena, timestamp, try localtime.offset(arena, io, timestamp));
    const ago = try formatDuration(arena, @intCast(@max(now - timestamp, 0)));
    return std.fmt.allocPrint(arena, "{s} ({s} ago)", .{ when, ago });
}
