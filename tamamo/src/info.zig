const std = @import("std");

pub fn run(out: *std.Io.Writer) !void {
    try out.writeAll("Tamamo\n");
}
