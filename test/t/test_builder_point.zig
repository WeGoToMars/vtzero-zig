const std = @import("std");
const vtzero = @import("vtzero");

const PointHandler = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayListUnmanaged(vtzero.Point) = .empty,

    pub fn deinit(self: *PointHandler) void {
        self.data.deinit(self.allocator);
    }

    pub fn points_begin(self: *PointHandler, count: u32) !void {
        try self.data.ensureTotalCapacity(self.allocator, count);
    }

    pub fn points_point(self: *PointHandler, point: vtzero.Point) !void {
        try self.data.append(self.allocator, point);
    }

    pub fn points_end(_: *PointHandler) void {}
};

fn expectDecodedPoints(feature: vtzero.Feature, expected: []const vtzero.Point) !void {
    var handler = PointHandler{ .allocator = std.testing.allocator };
    defer handler.deinit();
    _ = try vtzero.decodePointGeometry(feature.geometry(), &handler);
    try std.testing.expectEqual(expected.len, handler.data.items.len);
    for (expected, 0..) |pt, i| try std.testing.expectEqual(pt, handler.data.items[i]);
}

fn testPointBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);

    // SECTION("add point using coordinates / property using key/value")
    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        if (with_id) try fbuilder.setId(17);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 });
        if (with_prop) {
            var epv = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
            defer epv.deinit();
            try fbuilder.addProperty(allocator, "foo", epv);
        }
        try fbuilder.commit(allocator);
    }

    // SECTION("add point using vtzero::point / property using key/value")
    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        if (with_id) try fbuilder.setId(17);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 });
        if (with_prop) {
            var epv = try vtzero.EncodedPropertyValue.fromUInt(allocator, 22);
            defer epv.deinit();
            try fbuilder.addProperty(allocator, "foo", epv);
        }
        try fbuilder.commit(allocator);
    }

    // SECTION("add point using mypoint / property using property")
    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        if (with_id) try fbuilder.setId(17);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 });
        if (with_prop) {
            var epv = try vtzero.EncodedPropertyValue.fromDouble(allocator, 3.5);
            defer epv.deinit();
            const p = vtzero.Property{ .key_data = "foo", .value_data = vtzero.PropertyValue.init(epv.data()) };
            try fbuilder.addPropertyObject(allocator, p);
        }
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    try std.testing.expectEqualStrings("test", layer.name());
    try std.testing.expectEqual(@as(u32, 2), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 3), layer.numFeatures());

    const expected = [_]vtzero.Point{.{ .x = 10, .y = 20 }};
    var feature1 = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, if (with_id) 17 else 0), feature1.id());
    try expectDecodedPoints(feature1, &expected);

    var feature2 = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, if (with_id) 17 else 0), feature2.id());
    try expectDecodedPoints(feature2, &expected);

    var feature3 = (try layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, if (with_id) 17 else 0), feature3.id());
    try expectDecodedPoints(feature3, &expected);
}

fn testMultipointBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    if (with_id) try fbuilder.setId(17);
    try fbuilder.addPoints(allocator, 3);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });

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
    const expected = [_]vtzero.Point{
        .{ .x = 10, .y = 20 },
        .{ .x = 20, .y = 30 },
        .{ .x = 30, .y = 40 },
    };
    try expectDecodedPoints(feature, &expected);
}

test "Point builder without id/without properties" {
    try testPointBuilder(false, false);
}

test "Point builder without id/with properties" {
    try testPointBuilder(false, true);
}

test "Point builder with id/without properties" {
    try testPointBuilder(true, false);
}

test "Point builder with id/with properties" {
    try testPointBuilder(true, true);
}

test "Calling add_points() with bad values throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    // SECTION("0")
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addPoints(allocator, 0));
    // SECTION("2^29")
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addPoints(allocator, @as(u32, 1) << 29));
}

test "Multipoint builder without id/without properties" {
    try testMultipointBuilder(false, false);
}

test "Multipoint builder without id/with properties" {
    try testMultipointBuilder(false, true);
}

test "Multipoint builder with id/without properties" {
    try testMultipointBuilder(true, false);
}

test "Multipoint builder with id/with properties" {
    try testMultipointBuilder(true, true);
}

test "Calling add_point() and then other geometry functions throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 });

    // SECTION("add_point()")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 }));
    // SECTION("add_points()")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.addPoints(allocator, 2));
    // SECTION("set_point()")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
}

test "Calling point_feature_builder::set_point() throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
}

test "Calling add_points() and then other geometry functions throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try fbuilder.addPoints(allocator, 2);

    // SECTION("add_point()")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 }));
    // SECTION("add_points()")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.addPoints(allocator, 2));
}

test "Calling point_feature_builder::set_point() too often throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addPoints(allocator, 2);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 20 });
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 30, .y = 20 }));
}

test "Add points from container" {
    const allocator = std.testing.allocator;
    const points = [_]vtzero.Point{
        .{ .x = 10, .y = 20 },
        .{ .x = 20, .y = 30 },
        .{ .x = 30, .y = 40 },
    };

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.addPointsFromContainer(allocator, &points);
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
    try expectDecodedPoints(feature, &points);
}

test "Add points from iterator with wrong count throws assert" {
    // C++ has iterator overloads with an explicit count; Zig doesn't.
    // Closest equivalent: declare a count, provide fewer points, then commit => incomplete geometry.
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addPoints(allocator, 3);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    // missing 3rd point
    try std.testing.expectError(error.IncompleteGeometry, fbuilder.commit(allocator));
}

