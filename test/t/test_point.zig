const std = @import("std");
const vtzero = @import("vtzero");

test "default constructed point" {
    const p = vtzero.Point{};
    try std.testing.expectEqual(@as(i32, 0), p.x);
    try std.testing.expectEqual(@as(i32, 0), p.y);
}

test "point" {
    const p1 = vtzero.Point{ .x = 4, .y = 5 };
    const p2 = vtzero.Point{ .x = 5, .y = 4 };
    const p3 = vtzero.Point{ .x = 4, .y = 5 };

    try std.testing.expectEqual(@as(i32, 4), p1.x);
    try std.testing.expectEqual(@as(i32, 5), p1.y);
    try std.testing.expect(!std.meta.eql(p1, p2));
    try std.testing.expect(std.meta.eql(p1, p3));
}

