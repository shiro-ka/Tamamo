const std = @import("std");
const Io = std.Io;

pub fn run(io: Io, out: *Io.Writer) !void {
    var buffer: [4096]u8 = undefined;
    const os_release = try Io.Dir.cwd().readFile(io, "/etc/os-release", &buffer);

    try out.print("OS: {s}\n", .{prettyName(os_release) orelse "unknown"});

    const uts = std.posix.uname();
    try out.print("Kernel: {s} {s}\n", .{
        std.mem.sliceTo(&uts.sysname, 0),
        std.mem.sliceTo(&uts.release, 0),
    });
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
