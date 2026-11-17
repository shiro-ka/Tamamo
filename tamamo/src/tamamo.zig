const std = @import("std");
const Io = std.Io;
const info = @import("info.zig");
const next = @import("next.zig");

const Command = enum { info, next };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const command = if (args.len >= 2) std.meta.stringToEnum(Command, args[1]) else null;
    if (command == null) {
        std.debug.print("usage: tamamo info | tamamo next\n", .{});
        std.process.exit(2);
    }

    var buffer: [1024]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const out = &stdout.interface;

    switch (command.?) {
        .info => try info.run(arena, init.io, out),
        .next => try next.run(arena, init.io, out),
    }
    try out.flush();
}

test {
    _ = @import("info.zig");
    _ = @import("next.zig");
    _ = @import("ostree.zig");
    _ = @import("localtime.zig");
    _ = @import("format.zig");
    _ = @import("osrelease.zig");
    _ = @import("text.zig");
}
