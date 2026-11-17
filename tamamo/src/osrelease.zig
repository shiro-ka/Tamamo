const std = @import("std");
const text = @import("text.zig");

pub fn prettyName(os_release: []const u8) ?[]const u8 {
    const value = text.lineValue(os_release, "PRETTY_NAME=") orelse return null;
    return std.mem.trim(u8, value, "\"");
}

pub fn commit(os_release: []const u8) ?[]const u8 {
    const build_id = std.mem.trim(u8, text.lineValue(os_release, "BUILD_ID=") orelse return null, "\"");
    var parts = std.mem.splitScalar(u8, build_id, '.');
    _ = parts.next();
    _ = parts.next();
    return parts.next();
}

test prettyName {
    try std.testing.expectEqualStrings(
        "Fedora Linux 44 (Silverblue)",
        prettyName("NAME=\"Fedora Linux\"\nPRETTY_NAME=\"Fedora Linux 44 (Silverblue)\"\nID=fedora\n").?,
    );
    try std.testing.expectEqual(null, prettyName("NAME=\"Fedora Linux\"\n"));
}

test commit {
    try std.testing.expectEqualStrings("147d64b", commit("NAME=\"Tamamo OS\"\nBUILD_ID=\"0.20261116.147d64b\"\n").?);
    try std.testing.expectEqual(null, commit("BUILD_ID=\"0.20261116\"\n"));
    try std.testing.expectEqual(null, commit("NAME=\"Debian\"\n"));
}
