const std = @import("std");
const vtzero = @import("vtzero");

const Lines = std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point));

const LinestringHandler = struct {
    allocator: std.mem.Allocator,
    data: Lines = .empty,

    pub fn deinit(self: *LinestringHandler) void {
        for (self.data.items) |*line| line.deinit(self.allocator);
        self.data.deinit(self.allocator);
    }

    pub fn linestring_begin(self: *LinestringHandler, count: u32) !void {
        try self.data.append(self.allocator, .empty);
        try self.data.items[self.data.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn linestring_point(self: *LinestringHandler, point: vtzero.Point) !void {
        try self.data.items[self.data.items.len - 1].append(self.allocator, point);
    }

    pub fn linestring_end(_: *LinestringHandler) void {}
};

fn decodeLines(feature: vtzero.Feature) !Lines {
    var handler = LinestringHandler{ .allocator = std.testing.allocator };
    errdefer handler.deinit();
    _ = try vtzero.decodeLinestringGeometry(feature.geometry(), &handler);
    // return ownership to caller
    const out = handler.data;
    handler.data = .empty;
    handler.deinit();
    return out;
}

fn freeLines(lines: *Lines) void {
    for (lines.items) |*line| line.deinit(std.testing.allocator);
    lines.deinit(std.testing.allocator);
}

fn expectLinesEqual(actual: Lines, expected: []const []const vtzero.Point) !void {
    try std.testing.expectEqual(expected.len, actual.items.len);
    for (expected, 0..) |exp_line, li| {
        const got = actual.items[li].items;
        try std.testing.expectEqual(exp_line.len, got.len);
        for (exp_line, 0..) |pt, i| try std.testing.expectEqual(pt, got[i]);
    }
}

fn testLinestringBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    {
        var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        if (with_id) try fbuilder.setId(17);

        try fbuilder.addLinestring(3);
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
        try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
        try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });

        if (with_prop) try fbuilder.addProperty(allocator, "foo", "bar");
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    try std.testing.expectEqualStrings("test", layer.name());
    try std.testing.expectEqual(@as(u32, 2), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, if (with_id) 17 else 0), feature.id());

    var lines = try decodeLines(feature);
    defer freeLines(&lines);
    const expected0 = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 } };
    try expectLinesEqual(lines, &.{&expected0});
}

fn testMultilinestringBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    if (with_id) try fbuilder.setId(17);
    try fbuilder.addLinestring(3);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });

    try fbuilder.addLinestring(2);
    try fbuilder.setPoint(allocator, .{ .x = 1, .y = 2 });
    try fbuilder.setPoint(allocator, .{ .x = 2, .y = 1 });

    if (with_prop) {
        var epv = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer epv.deinit();
        try fbuilder.addProperty(allocator, "foo", epv);
    }

    try fbuilder.commit(allocator);

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    try std.testing.expectEqualStrings("test", layer.name());
    try std.testing.expectEqual(@as(u32, 2), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, if (with_id) 17 else 0), feature.id());

    var lines = try decodeLines(feature);
    defer freeLines(&lines);
    const expected0 = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 } };
    const expected1 = [_]vtzero.Point{ .{ .x = 1, .y = 2 }, .{ .x = 2, .y = 1 } };
    try expectLinesEqual(lines, &.{ &expected0, &expected1 });
}

test "linestring builder without id/without properties" {
    try testLinestringBuilder(false, false);
}

test "linestring builder without id/with properties" {
    try testLinestringBuilder(false, true);
}

test "linestring builder with id/without properties" {
    try testLinestringBuilder(true, false);
}

test "linestring builder with id/with properties" {
    try testLinestringBuilder(true, true);
}

test "Calling add_linestring() with bad values throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    // SECTION("0")
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addLinestring(0));
    // SECTION("1")
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addLinestring(1));
    // SECTION("2^29")
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addLinestring(@as(u32, 1) << 29));
}

test "Multilinestring builder without id/without properties" {
    try testMultilinestringBuilder(false, false);
}

test "Multilinestring builder without id/with properties" {
    try testMultilinestringBuilder(false, true);
}

test "Multilinestring builder with id/without properties" {
    try testMultilinestringBuilder(true, false);
}

test "Multilinestring builder with id/with properties" {
    try testMultilinestringBuilder(true, true);
}

test "Calling add_linestring() twice throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addLinestring(3);
    try std.testing.expectError(error.IncompleteGeometry, fbuilder.addLinestring(2));
}

test "Calling linestring_feature_builder::set_point() throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
}

test "Calling linestring_feature_builder::set_point() with same point throws" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addLinestring(2);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 });
    try std.testing.expectError(error.ZeroLengthSegment, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
}

test "Calling linestring_feature_builder::set_point() too often throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addLinestring(2);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 20 });
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 30, .y = 20 }));
}

test "Add linestring from container" {
    const allocator = std.testing.allocator;
    const points = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 } };
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    {
        var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.addLinestring(@intCast(points.len));
        for (points) |pt| try fbuilder.setPoint(allocator, pt);
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    const feature = (try layer.nextFeature()) orelse unreachable;
    var lines = try decodeLines(feature);
    defer freeLines(&lines);
    try expectLinesEqual(lines, &.{&points});
}

test "Add linestring from iterator with wrong count throws assert" {
    // C++ test exists but is compiled out upstream; keep name for parity.
    // Zig equivalent: declare a count, provide fewer points, then commit => incomplete geometry.
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addLinestring(3);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    // missing 3rd point
    try std.testing.expectError(error.IncompleteGeometry, fbuilder.commit(allocator));
}

test "Adding several linestrings with feature rollback in the middle" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);

    {
        var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(1);
        try fbuilder.addLinestring(2);
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 });
        try fbuilder.setPoint(allocator, .{ .x = 20, .y = 20 });
        try fbuilder.commit(allocator);
    }

    {
        var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(2);
        try fbuilder.addLinestring(2);
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 });
        // second identical point -> error, feature not committed
        _ = fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }) catch |err| {
            try std.testing.expectEqual(error.ZeroLengthSegment, err);
        };
        // no commit
    }

    {
        var fbuilder = vtzero.LinestringFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(3);
        try fbuilder.addLinestring(2);
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
        try fbuilder.setPoint(allocator, .{ .x = 20, .y = 10 });
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    try std.testing.expectEqualStrings("test", layer.name());
    try std.testing.expectEqual(@as(usize, 2), layer.numFeatures());

    const feat1 = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, 1), feat1.id());
    const feat2 = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, 3), feat2.id());
}

