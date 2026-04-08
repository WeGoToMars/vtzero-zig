const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

fn encodeZigZag32(value: i32) u32 {
    return (@as(u32, @bitCast(value)) << 1) ^ @as(u32, @bitCast(value >> 31));
}

test "geometry_decoder" {
    var decoder = try vtzero.GeometryDecoder.init(&.{}, 0);
    try std.testing.expectEqual(@as(u32, 0), decoder.count());
    try std.testing.expect(decoder.done());
    try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
}

test "geometry_decoder with point" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 50, 34 });
    {
        var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
        try std.testing.expectEqual(@as(u32, 0), decoder.count());
        try std.testing.expect(!decoder.done());
        try std.testing.expectError(error.UnexpectedCommand, decoder.nextCommand(.LINE_TO));
    }
    {
        var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
        try std.testing.expectError(error.UnexpectedCommand, decoder.nextCommand(.CLOSE_PATH));
    }
    {
        var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
        try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
        try std.testing.expectEqual(@as(u32, 1), decoder.count());
        try std.testing.expectEqual(vtzero.Point{ .x = 25, .y = 17 }, try decoder.nextPoint());

        try std.testing.expect(decoder.done());
        try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
    }
}

test "geometry_decoder with incomplete point" {
    // half a point
    {
        var buf: [16]u8 = undefined;
        const bytes = testlib.packInts(&buf, &.{ 9, 50 });
        var decoder = try vtzero.GeometryDecoder.init(bytes, 100);
        try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
        try std.testing.expectError(error.TooFewPoints, decoder.nextPoint());
    }

    // missing point
    {
        var buf: [16]u8 = undefined;
        const bytes = testlib.packInts(&buf, &.{9});
        var decoder = try vtzero.GeometryDecoder.init(bytes, 100);
        try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
        try std.testing.expectError(error.TooFewPoints, decoder.nextPoint());
    }
}

test "geometry_decoder with multipoint" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 17, 10, 14, 3, 9 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(@as(u32, 2), decoder.count());
    try std.testing.expectEqual(vtzero.Point{ .x = 5, .y = 7 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 3, .y = 2 }, try decoder.nextPoint());
    try std.testing.expect(decoder.done());
}

test "geometry_decoder with linestring" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(@as(u32, 1), decoder.count());
    try std.testing.expectEqual(vtzero.Point{ .x = 2, .y = 2 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(@as(u32, 2), decoder.count());
    try std.testing.expectEqual(vtzero.Point{ .x = 2, .y = 10 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 10, .y = 10 }, try decoder.nextPoint());
    try std.testing.expect(decoder.done());
    try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
}

test "geometry_decoder with linestring with equal points" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 0, 0 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    _ = try decoder.nextPoint();
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    _ = try decoder.nextPoint();
    const p = try decoder.nextPoint();
    try std.testing.expectEqual(vtzero.Point{ .x = 2, .y = 10 }, p);
    try std.testing.expect(decoder.done());
}

test "geometry_decoder with multilinestring" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 4, 4, 18, 0, 16, 16, 0, 9, 17, 17, 10, 4, 8 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    _ = try decoder.nextPoint();
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    _ = try decoder.nextPoint();
    _ = try decoder.nextPoint();

    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 1, .y = 1 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 3, .y = 5 }, try decoder.nextPoint());

    try std.testing.expect(decoder.done());
    try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
}

test "geometry_decoder with polygon" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 15 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 3, .y = 6 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 8, .y = 12 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 20, .y = 34 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.CLOSE_PATH));
    try std.testing.expect(decoder.done());
    try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
}

test "geometry_decoder with polygon with wrong ClosePath count 2" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 23 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    _ = try decoder.nextPoint();
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    _ = try decoder.nextPoint();
    _ = try decoder.nextPoint();
    try std.testing.expectError(error.InvalidClosePathCount, decoder.nextCommand(.CLOSE_PATH));
}

test "geometry_decoder with polygon with wrong ClosePath count 0" {
    var buf: [32]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ 9, 6, 12, 18, 10, 12, 24, 44, 7 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    _ = try decoder.nextPoint();
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    _ = try decoder.nextPoint();
    _ = try decoder.nextPoint();
    try std.testing.expectError(error.InvalidClosePathCount, decoder.nextCommand(.CLOSE_PATH));
}

test "geometry_decoder with multipolygon" {
    var buf: [128]u8 = undefined;
    const ints = [_]u32{
        9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15, 9, 22, 2, 26, 18,
        0, 0, 18, 17, 0, 15, 9, 4, 13, 26, 0, 8, 8, 0, 0, 7, 15,
    };
    const bytes = testlib.packInts(&buf, &ints);
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);

    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 0, .y = 0 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 10, .y = 0 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 10, .y = 10 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 0, .y = 10 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.CLOSE_PATH));

    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 11, .y = 11 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 20, .y = 11 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 20, .y = 20 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 11, .y = 20 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.CLOSE_PATH));

    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 13, .y = 13 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 13, .y = 17 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 17, .y = 17 }, try decoder.nextPoint());
    try std.testing.expectEqual(vtzero.Point{ .x = 17, .y = 13 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.CLOSE_PATH));

    try std.testing.expect(decoder.done());
    try std.testing.expect(!(try decoder.nextCommand(.MOVE_TO)));
}

test "geometry_decoder decoding linestring with int32 overflow in x coordinate" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{
        vtzero.commandMoveTo(1),
        encodeZigZag32(std.math.maxInt(i32)),
        encodeZigZag32(0),
        vtzero.commandLineTo(1),
        encodeZigZag32(1),
        encodeZigZag32(1),
    });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = std.math.maxInt(i32), .y = 0 }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = std.math.minInt(i32), .y = 1 }, try decoder.nextPoint());
}

test "geometry_decoder decoding linestring with int32 overflow in y coordinate" {
    var buf: [64]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{
        vtzero.commandMoveTo(1),
        encodeZigZag32(0),
        encodeZigZag32(std.math.minInt(i32)),
        vtzero.commandLineTo(1),
        encodeZigZag32(-1),
        encodeZigZag32(-1),
    });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expect(try decoder.nextCommand(.MOVE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = 0, .y = std.math.minInt(i32) }, try decoder.nextPoint());
    try std.testing.expect(try decoder.nextCommand(.LINE_TO));
    try std.testing.expectEqual(vtzero.Point{ .x = -1, .y = std.math.maxInt(i32) }, try decoder.nextPoint());
}

test "geometry_decoder with multipoint with a huge count" {
    var buf: [16]u8 = undefined;
    const huge_value: u32 = (1 << 29) - 1;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(huge_value), 10, 10 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, bytes.len / 2);
    try std.testing.expectError(error.CountTooLarge, decoder.nextCommand(.MOVE_TO));
}

test "geometry_decoder with multipoint with not enough points" {
    var buf: [16]u8 = undefined;
    const bytes = testlib.packInts(&buf, &.{ vtzero.commandMoveTo(2), 10 });
    var decoder = try vtzero.GeometryDecoder.init(bytes, 1);
    try std.testing.expectError(error.CountTooLarge, decoder.nextCommand(.MOVE_TO));
}

