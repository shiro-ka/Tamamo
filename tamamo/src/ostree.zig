const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Deployment = struct {
    booted: bool = false,
    staged: bool = false,
    timestamp: i64 = 0,
    @"container-image-reference": []const u8 = "",
    packages: []const []const u8 = &.{},
    @"requested-local-packages": []const []const u8 = &.{},

    pub fn layeredCount(self: Deployment) usize {
        return self.packages.len + self.@"requested-local-packages".len;
    }

    pub fn isVerified(self: Deployment) bool {
        return !std.mem.startsWith(u8, self.@"container-image-reference", "ostree-unverified-");
    }
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

pub fn staged(list: []const Deployment) ?Deployment {
    for (list) |deployment| {
        if (deployment.staged) return deployment;
    }
    return null;
}

pub fn rollback(list: []const Deployment) ?Deployment {
    for (list, 0..) |deployment, i| {
        if (!deployment.booted) continue;
        if (i + 1 < list.len and !list[i + 1].staged) return list[i + 1];
        return null;
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

test rollback {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const list = try parseDeployments(arena_state.allocator(),
        \\{"deployments": [
        \\  {"booted": false, "staged": true, "timestamp": 300},
        \\  {"booted": true, "staged": false, "timestamp": 200},
        \\  {"booted": false, "staged": false, "timestamp": 100}
        \\]}
    );
    try std.testing.expectEqual(300, staged(list).?.timestamp);
    try std.testing.expectEqual(200, booted(list).?.timestamp);
    try std.testing.expectEqual(100, rollback(list).?.timestamp);
    try std.testing.expectEqual(null, rollback(list[0..2]));
}

test "layeredCount and isVerified" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const list = try parseDeployments(arena_state.allocator(),
        \\{"deployments": [
        \\  {"booted": true, "container-image-reference": "ostree-unverified-registry:ghcr.io/shiro-ka/tamamo-nvidia:latest",
        \\   "packages": ["input-remapper", "socat"], "requested-local-packages": []},
        \\  {"booted": false, "container-image-reference": "ostree-image-signed:docker://ghcr.io/shiro-ka/tamamo:latest"}
        \\]}
    );
    try std.testing.expectEqual(2, list[0].layeredCount());
    try std.testing.expect(!list[0].isVerified());
    try std.testing.expectEqual(0, list[1].layeredCount());
    try std.testing.expect(list[1].isVerified());
}
