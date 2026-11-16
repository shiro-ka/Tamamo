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

    const items = [_]Item{
        .{ .label = "OS", .value = prettyName(os_release) orelse "unknown" },
        .{ .label = "Kernel", .value = kernel },
    };

    try out.writeAll("( ' < }<3 ~ Tamamo INFO ~ . o O *\n");
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
