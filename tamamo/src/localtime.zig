const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const epoch = std.time.epoch;

pub fn offset(arena: Allocator, io: Io, unix: i64) !i32 {
    const data = try Io.Dir.cwd().readFileAlloc(io, "/etc/localtime", arena, .limited(1 << 20));
    var reader: Io.Reader = .fixed(data);
    const tz = try std.tz.Tz.parse(arena, &reader);
    return offsetAt(tz, unix);
}

fn offsetAt(tz: std.tz.Tz, unix: i64) i32 {
    var result = tz.timetypes[0].offset;
    for (tz.transitions) |transition| {
        if (transition.ts > unix) break;
        result = transition.timetype.offset;
    }
    return result;
}

pub fn format(arena: Allocator, unix: i64, utc_offset: i32) ![]const u8 {
    const seconds: epoch.EpochSeconds = .{ .secs = @intCast(unix + utc_offset) };
    const year_day = seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = seconds.getDaySeconds();
    return std.fmt.allocPrint(arena, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
    });
}

test format {
    const allocator = std.testing.allocator;
    const text = try format(allocator, 1794791004, 9 * 3600);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("2026-11-16 10:03", text);
}
