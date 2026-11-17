const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ostree = @import("ostree.zig");
const localtime = @import("localtime.zig");
const format = @import("format.zig");
const osrelease = @import("osrelease.zig");
const text = @import("text.zig");
const Item = format.Item;

const header = "( ' < }<3 ~ Tamamo INFO ~ . o O *\n";

pub fn run(arena: Allocator, io: Io, out: *Io.Writer) !void {
    const os_release = try Io.Dir.cwd().readFileAlloc(io, "/etc/os-release", arena, .limited(1 << 16));
    const now = Io.Clock.real.now(io).toSeconds();
    const deployments: []const ostree.Deployment = ostree.deployments(arena, io) catch &.{};
    const tz: ?std.tz.Tz = if (deployments.len > 0) try localtime.load(arena, io) else null;

    const system = [_]Item{
        .{ .label = "OS", .value = osrelease.prettyName(os_release) orelse "unknown" },
        .{ .label = "Kernel", .value = try kernelValue(arena) },
    };

    var image: std.ArrayList(Item) = .empty;
    if (ostree.booted(deployments)) |deployment| {
        const ago = try format.agoText(arena, deployment.imageTimestamp(), now);
        try image.append(arena, .{ .label = "Built", .value = try format.timeValue(arena, tz.?, deployment.imageTimestamp(), ago) });
        if (osrelease.commit(os_release)) |value| {
            try image.append(arena, .{ .label = "Commit", .value = value });
        }
    }
    if (ostree.staged(deployments)) |deployment| {
        try image.append(arena, .{ .label = "Next", .value = try format.timeValue(arena, tz.?, deployment.imageTimestamp(), "reboot to apply") });
    }
    if (ostree.rollback(deployments)) |deployment| {
        const ago = try format.agoText(arena, deployment.imageTimestamp(), now);
        try image.append(arena, .{ .label = "Prev", .value = try format.timeValue(arena, tz.?, deployment.imageTimestamp(), ago) });
    }
    if (ostree.booted(deployments)) |deployment| {
        const count = deployment.layeredCount();
        if (count > 0) {
            const noun = if (count == 1) "package" else "packages";
            try image.append(arena, .{ .label = "Added", .value = try std.fmt.allocPrint(arena, "{d} {s}", .{ count, noun }) });
        }
        if (!deployment.isVerified()) {
            try image.append(arena, .{ .label = "Note", .value = "image signature is not verified" });
        }
    }

    const machine = [_]Item{
        .{ .label = "Uptime", .value = try uptimeValue(arena, io) },
        .{ .label = "Memory", .value = try memoryValue(arena, io) },
    };

    try out.writeAll(header);
    try format.printGroups(out, &.{ &system, image.items, &machine });
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
    return format.formatDuration(arena, try uptimeSeconds(proc_uptime));
}

fn uptimeSeconds(proc_uptime: []const u8) !u64 {
    const end = std.mem.indexOfScalar(u8, proc_uptime, '.') orelse return error.InvalidUptime;
    return std.fmt.parseInt(u64, proc_uptime[0..end], 10);
}

test uptimeSeconds {
    try std.testing.expectEqual(12345, try uptimeSeconds("12345.67 45678.90\n"));
    try std.testing.expectError(error.InvalidUptime, uptimeSeconds(""));
}

fn memoryValue(arena: Allocator, io: Io) ![]const u8 {
    var file_buffer: [4096]u8 = undefined;
    const meminfo = try Io.Dir.cwd().readFile(io, "/proc/meminfo", &file_buffer);
    const total_kib = try meminfoKib(meminfo, "MemTotal:");
    const available_kib = try meminfoKib(meminfo, "MemAvailable:");
    return formatMemory(arena, total_kib - available_kib, total_kib);
}

fn meminfoKib(meminfo: []const u8, prefix: []const u8) !u64 {
    const value = text.lineValue(meminfo, prefix) orelse return error.InvalidMeminfo;
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
    const memory = try formatMemory(allocator, 5415080, 16148572);
    defer allocator.free(memory);
    try std.testing.expectEqualStrings("5.2 / 15.4 GiB (34%)", memory);
}
