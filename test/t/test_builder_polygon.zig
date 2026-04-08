const std = @import("std");
const vtzero = @import("vtzero");

const Rings = std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point));

const PolygonHandler = struct {
    allocator: std.mem.Allocator,
    data: Rings = .empty,

    pub fn deinit(self: *PolygonHandler) void {
        for (self.data.items) |*ring| ring.deinit(self.allocator);
        self.data.deinit(self.allocator);
    }

    pub fn ring_begin(self: *PolygonHandler, count: u32) !void {
        try self.data.append(self.allocator, .empty);
        try self.data.items[self.data.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn ring_point(self: *PolygonHandler, point: vtzero.Point) !void {
        try self.data.items[self.data.items.len - 1].append(self.allocator, point);
    }

    pub fn ring_end(_: *PolygonHandler, _: vtzero.RingType) void {}
};

fn decodeRings(feature: vtzero.Feature) !Rings {
    var handler = PolygonHandler{ .allocator = std.testing.allocator };
    errdefer handler.deinit();
    _ = try vtzero.decodePolygonGeometry(feature.geometry(), &handler);
    const out = handler.data;
    handler.data = .empty;
    handler.deinit();
    return out;
}

fn freeRings(rings: *Rings) void {
    for (rings.items) |*ring| ring.deinit(std.testing.allocator);
    rings.deinit(std.testing.allocator);
}

fn expectRingsEqual(actual: Rings, expected: []const []const vtzero.Point) !void {
    try std.testing.expectEqual(expected.len, actual.items.len);
    for (expected, 0..) |exp_ring, ri| {
        const got = actual.items[ri].items;
        try std.testing.expectEqual(exp_ring.len, got.len);
        for (exp_ring, 0..) |pt, i| try std.testing.expectEqual(pt, got[i]);
    }
}

fn testPolygonBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    {
        var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        if (with_id) try fbuilder.setId(17);

        try fbuilder.addRing(4);
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
        try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
        try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });
        try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });

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
    var rings = try decodeRings(feature);
    defer freeRings(&rings);
    const expected0 = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 }, .{ .x = 10, .y = 20 } };
    try expectRingsEqual(rings, &.{&expected0});
}

fn testMultipolygonBuilder(with_id: bool, with_prop: bool) !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    if (with_id) try fbuilder.setId(17);

    try fbuilder.addRing(4);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });

    try fbuilder.addRing(5);
    try fbuilder.setPoint(allocator, .{ .x = 1, .y = 1 });
    try fbuilder.setPoint(allocator, .{ .x = 2, .y = 1 });
    try fbuilder.setPoint(allocator, .{ .x = 2, .y = 2 });
    try fbuilder.setPoint(allocator, .{ .x = 1, .y = 2 });

    if (with_id) {
        try fbuilder.setPoint(allocator, .{ .x = 1, .y = 1 });
    } else {
        try fbuilder.closeRing(allocator);
    }

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
    var rings = try decodeRings(feature);
    defer freeRings(&rings);
    const expected0 = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 }, .{ .x = 10, .y = 20 } };
    const expected1 = [_]vtzero.Point{ .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 }, .{ .x = 2, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 1, .y = 1 } };
    try expectRingsEqual(rings, &.{ &expected0, &expected1 });
}

test "polygon builder without id/without properties" {
    try testPolygonBuilder(false, false);
}

test "polygon builder without id/with properties" {
    try testPolygonBuilder(false, true);
}

test "polygon builder with id/without properties" {
    try testPolygonBuilder(true, false);
}

test "polygon builder with id/with properties" {
    try testPolygonBuilder(true, true);
}

test "Calling add_ring() with bad values throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addRing(0));
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addRing(1));
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addRing(2));
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addRing(3));
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addRing(@as(u32, 1) << 29));
}

test "Multipolygon builder without id/without properties" {
    try testMultipolygonBuilder(false, false);
}

test "Multipolygon builder without id/with properties" {
    try testMultipolygonBuilder(false, true);
}

test "Multipolygon builder with id/without properties" {
    try testMultipolygonBuilder(true, false);
}

test "Multipolygon builder with id/with properties" {
    try testMultipolygonBuilder(true, true);
}

test "Calling add_ring() twice throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try fbuilder.addRing(4);
    try std.testing.expectError(error.IncompleteGeometry, fbuilder.addRing(4));
}

test "Calling polygon_feature_builder::set_point()/close_ring() throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    // SECTION("set_point")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
    // SECTION("close_ring")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.closeRing(allocator));
}

test "Calling polygon_feature_builder::set_point()/close_ring() too often throws assert" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addRing(4);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 30, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });

    // SECTION("set_point")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.setPoint(allocator, .{ .x = 50, .y = 20 }));
    // SECTION("close_ring")
    try std.testing.expectError(error.InvalidBuilderState, fbuilder.closeRing(allocator));
}

test "Calling polygon_feature_builder::set_point() with same point throws" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try fbuilder.addRing(4);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 });
    try std.testing.expectError(error.ZeroLengthSegment, fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 }));
}

test "Calling polygon_feature_builder::set_point() creating unclosed ring throws" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addRing(4);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 10 });
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 20 });
    try std.testing.expectError(error.UnclosedRing, fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 }));
}

test "Add polygon from container" {
    const allocator = std.testing.allocator;
    const ring = [_]vtzero.Point{ .{ .x = 10, .y = 20 }, .{ .x = 20, .y = 30 }, .{ .x = 30, .y = 40 }, .{ .x = 10, .y = 20 } };
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    {
        var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.addRing(@intCast(ring.len));
        for (ring) |pt| try fbuilder.setPoint(allocator, pt);
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var layer = (try tile.nextLayer()) orelse unreachable;
    const feature = (try layer.nextFeature()) orelse unreachable;
    var rings = try decodeRings(feature);
    defer freeRings(&rings);
    try expectRingsEqual(rings, &.{&ring});
}

test "Add polygon from iterator with wrong count throws assert" {
    // C++ test exists but is compiled out upstream; keep name for parity.
    // Zig equivalent: declare a ring count, provide fewer points, then commit => incomplete geometry.
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PolygonFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);

    try fbuilder.addRing(4);
    try fbuilder.setPoint(allocator, .{ .x = 10, .y = 20 });
    try fbuilder.setPoint(allocator, .{ .x = 20, .y = 30 });
    try fbuilder.setPoint(allocator, .{ .x = 30, .y = 40 });
    // missing closing point
    try std.testing.expectError(error.IncompleteGeometry, fbuilder.commit(allocator));
}

