const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2 or !std.mem.eql(u8, args[1], "info")) {
        std.debug.print("usage: tamamo info\n", .{});
        std.process.exit(2);
    }

    var buffer: [1024]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const out = &stdout.interface;

    try out.writeAll("Tamamo\n");
    try out.flush();
}
