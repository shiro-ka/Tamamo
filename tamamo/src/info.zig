const std = @import("std");
const Io = std.Io;

const header = "( ' < }<3 ~ Tamamo INFO ~ . o O *\n";

const Item = struct {
    label: []const u8,
    value: []const u8,
};

pub fn run(io: Io, out: *Io.Writer) !void {
    var os_buffer: [4096]u8 = undefined;
    var kernel_buffer: [160]u8 = undefined;
    var uptime_buffer: [32]u8 = undefined;
    var memory_buffer: [48]u8 = undefined;

    const items = [_]Item{
        .{ .label = "OS", .value = try osValue(io, &os_buffer) },
        .{ .label = "Kernel", .value = try kernelValue(&kernel_buffer) },
        .{ .label = "Uptime", .value = try uptimeValue(io, &uptime_buffer) },
        .{ .label = "Memory", .value = try memoryValue(io, &memory_buffer) },
    };

    try out.writeAll(header);
    try printItems(out, &items);
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

fn osValue(io: Io, buffer: []u8) ![]const u8 {
    const os_release = try Io.Dir.cwd().readFile(io, "/etc/os-release", buffer);
    return prettyName(os_release) orelse "unknown";
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

fn kernelValue(buffer: []u8) ![]const u8 {
    const uts = std.posix.uname();
    return std.fmt.bufPrint(buffer, "{s} {s}", .{
        std.mem.sliceTo(&uts.sysname, 0),
        std.mem.sliceTo(&uts.release, 0),
    });
}

fn uptimeValue(io: Io, buffer: []u8) ![]const u8 {
    var file_buffer: [64]u8 = undefined;
    const proc_uptime = try Io.Dir.cwd().readFile(io, "/proc/uptime", &file_buffer);
    return formatUptime(buffer, try uptimeSeconds(proc_uptime));
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

fn memoryValue(io: Io, buffer: []u8) ![]const u8 {
    var file_buffer: [4096]u8 = undefined;
    const meminfo = try Io.Dir.cwd().readFile(io, "/proc/meminfo", &file_buffer);
    const total_kib = try meminfoKib(meminfo, "MemTotal:");
    const available_kib = try meminfoKib(meminfo, "MemAvailable:");
    return formatMemory(buffer, total_kib - available_kib, total_kib);
}

fn meminfoKib(meminfo: []const u8, prefix: []const u8) !u64 {
    const value = lineValue(meminfo, prefix) orelse return error.InvalidMeminfo;
    const number = std.mem.trim(u8, std.mem.trimEnd(u8, value, "kB"), " ");
    return std.fmt.parseInt(u64, number, 10);
}

fn formatMemory(buffer: []u8, used_kib: u64, total_kib: u64) ![]const u8 {
    const kib_per_gib: f64 = 1024 * 1024;
    const used: f64 = @as(f64, @floatFromInt(used_kib)) / kib_per_gib;
    const total: f64 = @as(f64, @floatFromInt(total_kib)) / kib_per_gib;
    const percent = (used_kib * 100 + total_kib / 2) / total_kib;
    return std.fmt.bufPrint(buffer, "{d:.1} / {d:.1} GiB ({d}%)", .{ used, total, percent });
}

test meminfoKib {
    const meminfo = "MemTotal:       16148572 kB\nMemFree:         1234567 kB\nMemAvailable:   10733492 kB\n";
    try std.testing.expectEqual(16148572, try meminfoKib(meminfo, "MemTotal:"));
    try std.testing.expectEqual(10733492, try meminfoKib(meminfo, "MemAvailable:"));
    try std.testing.expectError(error.InvalidMeminfo, meminfoKib(meminfo, "SwapTotal:"));
}

test formatMemory {
    var buffer: [48]u8 = undefined;
    try std.testing.expectEqualStrings("5.2 / 15.4 GiB (34%)", try formatMemory(&buffer, 5415080, 16148572));
}
