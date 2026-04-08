const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "Calling decode_linestring_geometry() with empty input" {
    const geometry = vtzero.Geometry{ .data = &.{}, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectEqual(@as(i32, 0), try vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with a valid linestring" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectEqual(@as(i32, 10301), try vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with a valid multilinestring" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    _ = try vtzero.decodeLinestringGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 20502), handler.result());
}

test "Calling decode_linestring_geometry() with a point geometry fails" {
    var buf: [16]u8 = undefined;
    const point_bytes = testlib.packInts(&buf, &.{ 9, 50, 34 });
    const geometry = vtzero.Geometry{ .data = point_bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.ExpectedLineTo, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with a polygon geometry fails" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 15 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with something other than MoveTo command" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandLineTo(3) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with a count of 0" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(0) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.InvalidLinestringMoveToCount, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with a count of 2" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(2), 10, 20, 20, 10 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.InvalidLinestringMoveToCount, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with 2nd command not a LineTo" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandMoveTo(1) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodeLinestringGeometry(geometry, &handler));
}

test "Calling decode_linestring_geometry() with LineTo and 0 count" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandLineTo(0) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .LINESTRING };
    var handler = testlib.DummyLineHandler{};
    try std.testing.expectError(error.ZeroLineToCount, vtzero.decodeLinestringGeometry(geometry, &handler));
}

