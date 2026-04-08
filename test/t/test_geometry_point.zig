const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "Calling decode_point() with empty input" {
    const geometry = vtzero.Geometry{ .data = &.{}, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.ExpectedMoveToPoint, vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with a valid point" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 50, 34 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectEqual(@as(i32, 10101), try vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with a valid multipoint" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 17, 10, 14, 3, 9 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectEqual(@as(i32, 10201), try vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with a linestring geometry fails" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.AdditionalPointData, vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with a polygon geometry fails" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 15 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.AdditionalPointData, vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with something other than MoveTo command" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandLineTo(3) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with a count of 0" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(0) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.ZeroPointCount, vtzero.decodePointGeometry(geometry, &handler));
}

test "Calling decode_point() with more data then expected" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 50, 34, 9 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POINT };
    var handler = testlib.DummyPointHandler{};
    try std.testing.expectError(error.AdditionalPointData, vtzero.decodePointGeometry(geometry, &handler));
}

