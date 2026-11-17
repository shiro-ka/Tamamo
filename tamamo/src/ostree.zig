const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Deployment = struct {
    booted: bool = false,
    staged: bool = false,
    timestamp: i64 = 0,
    @"base-timestamp": ?i64 = null,
    @"container-image-reference": []const u8 = "",
    osname: []const u8 = "",
    checksum: []const u8 = "",
    serial: u32 = 0,
    packages: []const []const u8 = &.{},
    @"requested-local-packages": []const []const u8 = &.{},

    pub fn imageTimestamp(self: Deployment) i64 {
        return self.@"base-timestamp" orelse self.timestamp;
    }

    pub fn layeredCount(self: Deployment) usize {
        return self.packages.len + self.@"requested-local-packages".len;
    }

    pub fn imageName(self: Deployment) ?[]const u8 {
        const reference = self.@"container-image-reference";
        const colon = std.mem.indexOfScalar(u8, reference, ':') orelse return null;
        const rest = reference[colon + 1 ..];
        return std.mem.cutPrefix(u8, rest, "docker://") orelse rest;
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

pub fn osRelease(arena: Allocator, io: Io, deployment: Deployment) ![]const u8 {
    const path = try std.fmt.allocPrint(arena, "/ostree/deploy/{s}/deploy/{s}.{d}/usr/lib/os-release", .{
        deployment.osname,
        deployment.checksum,
        deployment.serial,
    });
    return Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 16));
}

pub const Change = struct {
    label: []const u8,
    old: ?[]const u8,
    new: ?[]const u8,
};

pub const Diff = struct {
    added: usize = 0,
    removed: usize = 0,
    upgraded: usize = 0,
    downgraded: usize = 0,
    notable: []const Change = &.{},
};

const notable_packages = [_]struct { package: []const u8, label: []const u8 }{
    .{ .package = "kernel", .label = "kernel" },
    .{ .package = "linux-firmware", .label = "firmware" },
    .{ .package = "mesa-dri-drivers", .label = "mesa" },
    .{ .package = "nvidia-driver", .label = "nvidia" },
    .{ .package = "gnome-shell", .label = "gnome-shell" },
    .{ .package = "mutter", .label = "mutter" },
    .{ .package = "systemd", .label = "systemd" },
};

pub fn diff(arena: Allocator, io: Io, from: Deployment, to: Deployment) !Diff {
    const result = try std.process.run(arena, io, .{
        .argv = &.{ "rpm-ostree", "db", "diff", "--format=json", from.checksum, to.checksum },
    });
    if (!result.term.success()) return error.RpmOstreeFailed;
    return parseDiff(arena, result.stdout);
}

fn parseDiff(arena: Allocator, json: []const u8) !Diff {
    const root = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    const pkgdiff = root.object.get("pkgdiff") orelse return error.InvalidDiff;

    var result: Diff = .{};
    var found: [notable_packages.len]?Change = @splat(null);
    for (pkgdiff.array.items) |entry| {
        const fields = entry.array.items;
        const name = fields[0].string;
        switch (fields[1].integer) {
            0 => result.added += 1,
            1 => result.removed += 1,
            2 => result.upgraded += 1,
            3 => result.downgraded += 1,
            else => {},
        }
        for (notable_packages, 0..) |notable, i| {
            if (!std.mem.eql(u8, name, notable.package)) continue;
            const packages = fields[2].object;
            found[i] = .{
                .label = notable.label,
                .old = if (packages.get("PreviousPackage")) |package| package.array.items[1].string else null,
                .new = if (packages.get("NewPackage")) |package| package.array.items[1].string else null,
            };
        }
    }

    var notable: std.ArrayList(Change) = .empty;
    for (found) |change| {
        if (change) |value| try notable.append(arena, value);
    }
    result.notable = notable.items;
    return result;
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
        \\   "packages": ["input-remapper", "socat"], "requested-local-packages": [],
        \\   "timestamp": 1794887740, "base-timestamp": 1794826618},
        \\  {"booted": false, "container-image-reference": "ostree-image-signed:docker://ghcr.io/shiro-ka/tamamo:latest"}
        \\]}
    );
    try std.testing.expectEqual(2, list[0].layeredCount());
    try std.testing.expectEqual(1794826618, list[0].imageTimestamp());
    try std.testing.expectEqual(0, list[1].imageTimestamp());
    try std.testing.expect(!list[0].isVerified());
    try std.testing.expectEqual(0, list[1].layeredCount());
    try std.testing.expect(list[1].isVerified());
    try std.testing.expectEqualStrings("ghcr.io/shiro-ka/tamamo-nvidia:latest", list[0].imageName().?);
    try std.testing.expectEqualStrings("ghcr.io/shiro-ka/tamamo:latest", list[1].imageName().?);
}

test parseDiff {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const result = try parseDiff(arena_state.allocator(),
        \\{"ostree-commit-from": "a", "ostree-commit-to": "b", "pkgdiff": [
        \\  ["kernel", 2, {"PreviousPackage": ["kernel", "7.3.3-300.fc45", "x86_64"], "NewPackage": ["kernel", "7.3.4-200.fc45", "x86_64"]}],
        \\  ["sl", 0, {"NewPackage": ["sl", "5.02-26.fc45", "x86_64"]}],
        \\  ["mesa-dri-drivers", 2, {"PreviousPackage": ["mesa-dri-drivers", "26.2.6-1.fc45", "x86_64"], "NewPackage": ["mesa-dri-drivers", "26.2.7-1.fc45", "x86_64"]}],
        \\  ["gamescope", 1, {"PreviousPackage": ["gamescope", "3.16.29-1.fc45", "x86_64"]}]
        \\], "advisories": []}
    );
    try std.testing.expectEqual(1, result.added);
    try std.testing.expectEqual(1, result.removed);
    try std.testing.expectEqual(2, result.upgraded);
    try std.testing.expectEqual(2, result.notable.len);
    try std.testing.expectEqualStrings("kernel", result.notable[0].label);
    try std.testing.expectEqualStrings("7.3.4-200.fc45", result.notable[0].new.?);
    try std.testing.expectEqualStrings("mesa", result.notable[1].label);
}
