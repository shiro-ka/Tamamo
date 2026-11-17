const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ostree = @import("ostree.zig");
const localtime = @import("localtime.zig");
const format = @import("format.zig");
const osrelease = @import("osrelease.zig");
const Item = format.Item;

const header = "( ' < }<3 ~ Tamamo NEXT ~ . o O *\n";

pub fn run(arena: Allocator, io: Io, out: *Io.Writer) !void {
    const deployments = ostree.deployments(arena, io) catch {
        std.debug.print("tamamo next: rpm-ostree is not available\n", .{});
        std.process.exit(1);
    };
    const booted = ostree.booted(deployments) orelse {
        std.debug.print("tamamo next: no booted deployment\n", .{});
        std.process.exit(1);
    };
    const tz = try localtime.load(arena, io);
    const now = Io.Clock.real.now(io).toSeconds();

    var groups: std.ArrayList([]const Item) = .empty;
    const booted_ago = try format.agoText(arena, booted.imageTimestamp(), now);
    try groups.append(arena, try deploymentItems(arena, io, tz, "Now", booted, booted_ago, null));
    if (ostree.staged(deployments)) |staged| {
        const changes = try ostree.diff(arena, io, booted, staged);
        try groups.append(arena, try deploymentItems(arena, io, tz, "Next", staged, "reboot to apply", changes));
    }
    if (ostree.rollback(deployments)) |rollback| {
        const changes = try ostree.diff(arena, io, rollback, booted);
        const rollback_ago = try format.agoText(arena, rollback.imageTimestamp(), now);
        try groups.append(arena, try deploymentItems(arena, io, tz, "Prev", rollback, rollback_ago, changes));
    }

    try out.writeAll(header);
    try format.printGroups(out, groups.items);
}

fn deploymentItems(
    arena: Allocator,
    io: Io,
    tz: std.tz.Tz,
    label: []const u8,
    deployment: ostree.Deployment,
    note: []const u8,
    changes: ?ostree.Diff,
) ![]const Item {
    var items: std.ArrayList(Item) = .empty;
    try items.append(arena, .{ .label = label, .value = try format.timeValue(arena, tz, deployment.imageTimestamp(), note) });

    if (ostree.osRelease(arena, io, deployment)) |os_release| {
        if (osrelease.commit(os_release)) |value| {
            try items.append(arena, .{ .label = "Commit", .value = value });
        }
    } else |_| {}

    if (changes) |value| {
        try items.append(arena, .{ .label = "Diff", .value = try summary(arena, value) });
        for (value.notable) |change| {
            try items.append(arena, .{ .label = "", .value = try changeLine(arena, change) });
        }
    }
    return items.items;
}

fn summary(arena: Allocator, changes: ostree.Diff) ![]const u8 {
    const counts = [_]struct { count: usize, word: []const u8 }{
        .{ .count = changes.upgraded, .word = "upgraded" },
        .{ .count = changes.downgraded, .word = "downgraded" },
        .{ .count = changes.added, .word = "added" },
        .{ .count = changes.removed, .word = "removed" },
    };

    var parts: std.ArrayList(u8) = .empty;
    for (counts) |entry| {
        if (entry.count == 0) continue;
        if (parts.items.len > 0) try parts.appendSlice(arena, ", ");
        try parts.print(arena, "{d} {s}", .{ entry.count, entry.word });
    }
    if (parts.items.len == 0) return "no package changes";
    return parts.items;
}

fn changeLine(arena: Allocator, change: ostree.Change) ![]const u8 {
    const old = change.old orelse return std.fmt.allocPrint(arena, "{s} {s} (added)", .{ change.label, version(change.new.?) });
    const new = change.new orelse return std.fmt.allocPrint(arena, "{s} (removed)", .{change.label});
    if (std.mem.eql(u8, version(old), version(new))) {
        return std.fmt.allocPrint(arena, "{s} {s} -> {s}", .{ change.label, old, new });
    }
    return std.fmt.allocPrint(arena, "{s} {s} -> {s}", .{ change.label, version(old), version(new) });
}

fn version(evr: []const u8) []const u8 {
    const without_epoch = if (std.mem.indexOfScalar(u8, evr, ':')) |i| evr[i + 1 ..] else evr;
    const end = std.mem.lastIndexOfScalar(u8, without_epoch, '-') orelse without_epoch.len;
    return without_epoch[0..end];
}

test version {
    try std.testing.expectEqualStrings("7.3.4", version("7.3.4-200.fc45"));
    try std.testing.expectEqualStrings("620.70.06", version("3:620.70.06-1.fc45"));
    try std.testing.expectEqualStrings("1.0", version("1.0"));
}

test summary {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("12 upgraded, 1 added", try summary(arena, .{ .upgraded = 12, .added = 1 }));
    try std.testing.expectEqualStrings("no package changes", try summary(arena, .{}));
}

test changeLine {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("kernel 7.3.3 -> 7.3.4", try changeLine(arena, .{ .label = "kernel", .old = "7.3.3-300.fc45", .new = "7.3.4-200.fc45" }));
    try std.testing.expectEqualStrings("kernel 7.3.3-300.fc45 -> 7.3.3-301.fc45", try changeLine(arena, .{ .label = "kernel", .old = "7.3.3-300.fc45", .new = "7.3.3-301.fc45" }));
    try std.testing.expectEqualStrings("nvidia 620.70.06 (added)", try changeLine(arena, .{ .label = "nvidia", .old = null, .new = "3:620.70.06-1.fc45" }));
    try std.testing.expectEqualStrings("mutter (removed)", try changeLine(arena, .{ .label = "mutter", .old = "49.1-1.fc45", .new = null }));
}
