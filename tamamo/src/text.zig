const std = @import("std");

pub fn lineValue(text: []const u8, prefix: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.cutPrefix(u8, line, prefix)) |value| return value;
    }
    return null;
}

test lineValue {
    try std.testing.expectEqualStrings("b", lineValue("x=a\ny=b\n", "y=").?);
    try std.testing.expectEqual(null, lineValue("x=a\n", "y="));
}
