const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Deployment = struct {
    booted: bool = false,
    staged: bool = false,
    timestamp: i64 = 0,
};

const Status = struct {
    deployments: []const Deployment,
};

pub fn deployments(arena: Allocator, io: Io) ![]const Deployment {
    const result = try std.process.run(arena, io, .{
        .argv = &.{ "rpm-ostree", "status", "--json" },
    });
    if (!result.term.success()) return error.RpmOstreeFailed;
    return parseDeployments(arena, result.stdout);
}

fn parseDeployments(arena: Allocator, json: []const u8) ![]const Deployment {
    const status = try std.json.parseFromSliceLeaky(Status, arena, json, .{ .ignore_unknown_fields = true });
    return status.deployments;
}

pub fn booted(list: []const Deployment) ?Deployment {
    for (list) |deployment| {
        if (deployment.booted) return deployment;
    }
    return null;
}

test parseDeployments {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const list = try parseDeployments(arena_state.allocator(),
        \\{"deployments": [
        \\  {"booted": true, "staged": false, "timestamp": 1794791004, "checksum": "abc"},
        \\  {"booted": false, "staged": false, "timestamp": 1794747314}
        \\], "transaction": null}
    );
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqual(1794791004, booted(list).?.timestamp);
}
