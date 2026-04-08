const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "Calling decode_polygon_geometry() with empty input" {
    const geometry = vtzero.Geometry{ .data = &.{}, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectEqual(@as(i32, 0), try vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with a valid polygon" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 15 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectEqual(@as(i32, 10401), try vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with a duplicate end point" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 26, 10, 12, 24, 44, 33, 55, 15 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 10501), handler.result());
}

test "Calling decode_polygon_geometry() with a valid multipolygon" {
    var buf: [128]u8 = undefined;
    const ints = [_]u32{
        9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18,
        0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15,
    };
    const bytes = testlib.packInts(&buf, &ints);
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 31503), handler.result());
}

test "Calling decode_polygon_geometry() with a point geometry fails" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 50, 34 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.ExpectedPolygonLineTo, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with a linestring geometry fails" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.ExpectedClosePath, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with something other than MoveTo command" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandLineTo(3) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with a count of 0" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(0) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.InvalidPolygonMoveToCount, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with a count of 2" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(2), 1, 2, 3, 4 });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.InvalidPolygonMoveToCount, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with 2nd command not a LineTo" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandMoveTo(1) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() with LineTo and 0 count" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandLineTo(0), vtzero.commandClosePath() });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 10201), handler.result());
}

test "Calling decode_polygon_geometry() with LineTo and 1 count" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandLineTo(1), 5, 6, vtzero.commandClosePath() });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 10301), handler.result());
}

test "Calling decode_polygon_geometry() with 3nd command not a ClosePath" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 3, 4, vtzero.commandLineTo(2), 4, 5, 6, 7, vtzero.commandLineTo(0) });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodePolygonGeometry(geometry, &handler));
}

test "Calling decode_polygon_geometry() on polygon with zero area" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(1), 0, 0, vtzero.commandLineTo(3), 2, 0, 0, 4, 2, 0, vtzero.commandClosePath() });
    const geometry = vtzero.Geometry{ .data = bytes, .geom_type = .POLYGON };
    var handler = testlib.DummyPolygonHandler{};
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(i32, 10501), handler.result());
}

test "Calling decode_polygon_geometry() with a handler accepting ring area" {
    var buf: [32]u8 = undefined;
    const area_bytes = testlib.packInts(&buf, &.{ 9, 3, 6, 18, 8, 12, 20, 34, 15 });
    const geometry = vtzero.Geometry{ .data = area_bytes, .geom_type = .POLYGON };

    var handler = testlib.AreaPolygonHandler{};
    defer handler.deinit(std.testing.allocator);
    _ = try vtzero.decodePolygonGeometry(geometry, &handler);
    try std.testing.expectEqual(@as(usize, 1), handler.areas.items.len);
    try std.testing.expectEqual(@as(i64, 4), handler.areas.items[0]);

    try std.testing.expectEqual(@as(usize, 1), handler.rings.items.len);
    const ring = handler.rings.items[0].items;
    const expected = [_]vtzero.Point{
        .{ .x = -2, .y = 3 },
        .{ .x = 2, .y = 9 },
        .{ .x = 12, .y = 26 },
        .{ .x = -2, .y = 3 },
    };
    try std.testing.expectEqual(expected.len, ring.len);
    for (expected, 0..) |pt, idx| try std.testing.expectEqual(pt, ring[idx]);
}

