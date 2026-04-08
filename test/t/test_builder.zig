const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

const ByteList = std.array_list.Managed(u8);

// --- helpers (C++ anonymous namespace around vector_tile_equal / next_nonempty_layer) ---

fn nextNonemptyLayer(tile: *vtzero.VectorTile) !?vtzero.Layer {
    while (try tile.nextLayer()) |layer| {
        if (!layer.empty()) return layer;
    }
    return null;
}

fn propertyValueEql(a: vtzero.PropertyValue, b: vtzero.PropertyValue) bool {
    const da = a.data orelse return b.data == null;
    const db = b.data orelse return false;
    return std.mem.eql(u8, da, db);
}

fn vectorTileEqual(allocator: std.mem.Allocator, t1: []const u8, t2: []const u8) !bool {
    var vt1 = vtzero.VectorTile.init(t1);
    var vt2 = vtzero.VectorTile.init(t2);
    while (true) {
        const ol1 = try nextNonemptyLayer(&vt1);
        const ol2 = try nextNonemptyLayer(&vt2);
        const has1 = ol1 != null;
        const has2 = ol2 != null;
        if (!has1 and !has2) return true;
        if (!has1 or !has2) return false;

        const l1 = ol1.?;
        const l2 = ol2.?;
        if (l1.version() != l2.version()) return false;
        if (l1.extent() != l2.extent()) return false;
        if (l1.numFeatures() != l2.numFeatures()) return false;
        if (!std.mem.eql(u8, l1.name(), l2.name())) return false;

        const l1_keys = try l1.collectKeyTable(allocator);
        defer allocator.free(l1_keys);
        const l1_values = try l1.collectValueTable(allocator);
        defer allocator.free(l1_values);

        const l2_keys = try l2.collectKeyTable(allocator);
        defer allocator.free(l2_keys);
        const l2_values = try l2.collectValueTable(allocator);
        defer allocator.free(l2_values);

        var ml1 = l1;
        var ml2 = l2;
        while (true) {
            const f1 = try ml1.nextFeature();
            const f2 = try ml2.nextFeature();
            const fh1 = f1 != null;
            const fh2 = f2 != null;
            if (!fh1 and !fh2) break;
            if (!fh1 or !fh2) return false;

            const sf1 = f1.?;
            const sf2 = f2.?;
            if (sf1.id() != sf2.id()) return false;
            if (sf1.geometryType() != sf2.geometryType()) return false;
            if (sf1.numProperties() != sf2.numProperties()) return false;
            if (!std.mem.eql(u8, sf1.geometry().data, sf2.geometry().data)) return false;

            var pf1 = sf1;
            var pf2 = sf2;
            while (true) {
                const idx1 = try pf1.nextPropertyIndexes();
                const idx2 = try pf2.nextPropertyIndexes();
                const ph1 = idx1 != null;
                const ph2 = idx2 != null;
                if (!ph1 and !ph2) break;
                if (!ph1 or !ph2) return false;

                const idxs1 = idx1.?;
                const idxs2 = idx2.?;
                if (!std.mem.eql(u8, l1_keys[idxs1.key().value()], l2_keys[idxs2.key().value()])) return false;
                if (!propertyValueEql(l1_values[idxs1.value().value()], l2_values[idxs2.value().value()])) return false;
            }
        }
    }
}

/// C++ `points_to_vector` in test_builder.cpp
const PointsToVector = struct {
    points: std.ArrayListUnmanaged(vtzero.Point) = .empty,
    allocator: std.mem.Allocator,

    pub fn points_begin(self: *PointsToVector, count: u32) !void {
        try self.points.ensureTotalCapacity(self.allocator, count);
    }

    pub fn points_point(self: *PointsToVector, point: vtzero.Point) !void {
        try self.points.append(self.allocator, point);
    }

    pub fn points_end(_: *PointsToVector) void {}

    pub fn result(self: *PointsToVector) []const vtzero.Point {
        return self.points.items;
    }

    pub fn deinit(self: *PointsToVector) void {
        self.points.deinit(self.allocator);
    }
};

// --- tests (TEST_CASE names match C++ exactly) ---

test "Create tile from existing layers" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);

    {
        var tile = vtzero.VectorTile.init(buffer);
        var tbuilder = vtzero.TileBuilder.init(allocator);
        defer tbuilder.deinit();
        // SECTION("add_existing_layer(layer)")
        while (try tile.nextLayer()) |layer| {
            try tbuilder.addExistingLayer(layer);
        }
        const data = try tbuilder.serialize(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings(buffer, data);
    }

    {
        var tile = vtzero.VectorTile.init(buffer);
        var tbuilder = vtzero.TileBuilder.init(allocator);
        defer tbuilder.deinit();
        // SECTION("add_existing_layer(data_view)")
        while (try tile.nextLayer()) |layer| {
            try tbuilder.addExistingLayerData(layer.data orelse continue);
        }
        const data = try tbuilder.serialize(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings(buffer, data);
    }
}

test "Create layer based on existing layer" {
    const allocator = std.testing.allocator;
    const orig_tile_buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(orig_tile_buffer);
    const tile = vtzero.VectorTile.init(orig_tile_buffer);
    const layer = (try tile.getLayerByName("place_label")) orelse unreachable;

    const runSerializeAndCheck = (struct {
        fn run(allocator2: std.mem.Allocator, tbuilder: *vtzero.TileBuilder) ![]u8 {
            return try tbuilder.serialize(allocator2);
        }
    }.run);

    const runAppendManaged = (struct {
        fn run(allocator2: std.mem.Allocator, tbuilder: *vtzero.TileBuilder) ![]u8 {
            var out = ByteList.init(allocator2);
            defer out.deinit();
            try tbuilder.serializeAppend(allocator2, &out);
            return try allocator2.dupe(u8, out.items);
        }
    }.run);

    const runAppendCharVecStyle = (struct {
        fn run(allocator2: std.mem.Allocator, tbuilder: *vtzero.TileBuilder) ![]u8 {
            var buffer: std.ArrayList(u8) = .empty;
            defer buffer.deinit(allocator2);
            {
                var managed: ByteList = .init(allocator2);
                defer managed.deinit();
                try tbuilder.serializeAppend(allocator2, &managed);
                try buffer.appendSlice(allocator2, managed.items);
            }
            return try buffer.toOwnedSlice(allocator2);
        }
    }.run);

    const runBoundedStack = (struct {
        fn run(allocator2: std.mem.Allocator, tbuilder: *vtzero.TileBuilder) ![]u8 {
            var buf: [1000]u8 = undefined;
            const n = try tbuilder.serializeBounded(allocator2, &buf);
            return try allocator2.dupe(u8, buf[0..n]);
        }
    }.run);

    const runBoundedHeap = (struct {
        fn run(allocator2: std.mem.Allocator, tbuilder: *vtzero.TileBuilder) ![]u8 {
            const buf = try allocator2.alloc(u8, 1000);
            defer allocator2.free(buf);
            const n = try tbuilder.serializeBounded(allocator2, buf);
            return try allocator2.dupe(u8, buf[0..n]);
        }
    }.run);

    const strategies: []const *const fn (std.mem.Allocator, *vtzero.TileBuilder) anyerror![]u8 = &.{
        runSerializeAndCheck,
        runAppendManaged,
        runAppendCharVecStyle,
        runBoundedStack,
        runBoundedHeap,
    };

    for (strategies) |strategy| {
        var tbuilder = vtzero.TileBuilder.init(allocator);
        defer tbuilder.deinit();
        var lbuilder = try tbuilder.createLayerFromExisting(layer);

        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(42);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 20 });
        try fbuilder.commit(allocator);

        const data = try strategy(allocator, &tbuilder);
        defer allocator.free(data);

        var new_tile = vtzero.VectorTile.init(data);
        const new_layer = (try new_tile.nextLayer()) orelse unreachable;
        try std.testing.expectEqualStrings("place_label", new_layer.name());
        try std.testing.expectEqual(@as(u32, 1), new_layer.version());
        try std.testing.expectEqual(@as(u32, 4096), new_layer.extent());
    }
}

test "Create layer and add keys/values" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("name", 2, 4096);

    const ki1 = try lbuilder.addKeyWithoutDupCheck("key1");
    const ki2 = try lbuilder.addKey("key2");
    const ki3 = try lbuilder.addKey("key1");

    try std.testing.expect(ki1.value() != ki2.value());
    try std.testing.expectEqual(ki1.value(), ki3.value());

    var enc_v1 = try vtzero.EncodedPropertyValue.fromString(allocator, "value1");
    defer enc_v1.deinit();
    const vi1 = try lbuilder.addEncodedValueWithoutDupCheck(enc_v1);

    var value2 = try vtzero.EncodedPropertyValue.fromString(allocator, "value2");
    defer value2.deinit();
    const pv2 = vtzero.PropertyValue.init(value2.data());
    const vi2 = try lbuilder.addValueWithoutDupCheck(pv2);

    var enc_v1_b = try vtzero.EncodedPropertyValue.fromString(allocator, "value1");
    defer enc_v1_b.deinit();
    const vi3 = try lbuilder.addEncodedValue(enc_v1_b);

    var enc_19 = try vtzero.EncodedPropertyValue.fromUInt(allocator, 19);
    defer enc_19.deinit();
    const vi4 = try lbuilder.addEncodedValue(enc_19);

    var enc_19f = try vtzero.EncodedPropertyValue.fromDouble(allocator, 19.0);
    defer enc_19f.deinit();
    const vi5 = try lbuilder.addEncodedValue(enc_19f);

    var enc_22 = try vtzero.EncodedPropertyValue.fromUInt(allocator, 22);
    defer enc_22.deinit();
    const vi6 = try lbuilder.addEncodedValue(enc_22);

    var nineteen = try vtzero.EncodedPropertyValue.fromUInt(allocator, 19);
    defer nineteen.deinit();
    const vi7 = try lbuilder.addValue(vtzero.PropertyValue.init(nineteen.data()));

    try std.testing.expect(vi1.value() != vi2.value());
    try std.testing.expectEqual(vi1.value(), vi3.value());
    try std.testing.expect(vi1.value() != vi4.value());
    try std.testing.expect(vi1.value() != vi5.value());
    try std.testing.expect(vi1.value() != vi6.value());
    try std.testing.expect(vi4.value() != vi5.value());
    try std.testing.expect(vi4.value() != vi6.value());
    try std.testing.expectEqual(vi4.value(), vi7.value());
}

test "Committing a feature succeeds after a geometry was added" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(1);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        try fbuilder.commit(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(2);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        var enc_bar = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer enc_bar.deinit();
        try fbuilder.addProperty(allocator, "foo", enc_bar);
        try fbuilder.commit(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(3);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        var enc_bar = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer enc_bar.deinit();
        try fbuilder.addProperty(allocator, "foo", enc_bar);
        try fbuilder.commit(allocator);

        try fbuilder.commit(allocator);
        try std.testing.expectError(error.FeatureBuilderFinalized, fbuilder.setId(10));

        try std.testing.expectError(error.InvalidBuilderState, fbuilder.addPoint(allocator, .{ .x = 20, .y = 20 }));
        var enc_x = try vtzero.EncodedPropertyValue.fromString(allocator, "y");
        defer enc_x.deinit();
        try std.testing.expectError(error.FeatureBuilderFinalized, fbuilder.addProperty(allocator, "x", enc_x));
    }

    // Mirror C++ SECTION("superfluous rollback()") path too: rollback after commit is allowed,
    // but further mutations are rejected.
    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(4);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        var enc_bar = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer enc_bar.deinit();
        try fbuilder.addProperty(allocator, "foo", enc_bar);
        try fbuilder.commit(allocator);
        fbuilder.rollback(allocator);
        try std.testing.expectError(error.FeatureBuilderFinalized, fbuilder.setId(10));
        try std.testing.expectError(error.FeatureBuilderFinalized, fbuilder.addPoint(allocator, .{ .x = 20, .y = 20 }));
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var vtile = vtzero.VectorTile.init(data);
    var out_layer = (try nextNonemptyLayer(&vtile)) orelse unreachable;

    var n: u64 = 1;
    while (try out_layer.nextFeature()) |feature| {
        try std.testing.expectEqual(n, feature.id());
        n += 1;
    }
    try std.testing.expectEqual(@as(u64, 5), n);
}

test "Committing a feature fails with assert if no geometry was added" {
    const allocator = std.testing.allocator;
    {
        var tbuilder = vtzero.TileBuilder.init(allocator);
        defer tbuilder.deinit();
        var lbuilder = try tbuilder.createLayer("test", 2, 4096);
        // SECTION("explicit immediate commit")
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try std.testing.expectError(error.GeometryNotSet, fbuilder.commit(allocator));
    }
    {
        var tbuilder = vtzero.TileBuilder.init(allocator);
        defer tbuilder.deinit();
        var lbuilder = try tbuilder.createLayer("test", 2, 4096);
        // SECTION("explicit commit after setting id")
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(2);
        try std.testing.expectError(error.GeometryNotSet, fbuilder.commit(allocator));
    }
}

test "Rollback feature" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(1);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        try fbuilder.commit(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(2);
        fbuilder.rollback(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(3);
        fbuilder.rollback(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(4);
        try fbuilder.addPoint(allocator, .{ .x = 20, .y = 20 });
        fbuilder.rollback(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(5);
        try fbuilder.addPoint(allocator, .{ .x = 20, .y = 20 });
        var enc_bar = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer enc_bar.deinit();
        try fbuilder.addProperty(allocator, "foo", enc_bar);
        fbuilder.rollback(allocator);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(6);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(7);
        try fbuilder.addPoint(allocator, .{ .x = 10, .y = 10 });
        var enc_bar = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
        defer enc_bar.deinit();
        try fbuilder.addProperty(allocator, "foo", enc_bar);
    }

    {
        var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
        defer fbuilder.deinit(allocator);
        try fbuilder.setId(8);
        try fbuilder.addPoint(allocator, .{ .x = 30, .y = 30 });
        try fbuilder.commit(allocator);
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    var out_layer = (try nextNonemptyLayer(&tile)) orelse unreachable;

    var feature = (try out_layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, 1), feature.id());

    feature = (try out_layer.nextFeature()) orelse unreachable;
    try std.testing.expectEqual(@as(u64, 8), feature.id());

    try std.testing.expectEqual(@as(?vtzero.Feature, null), try out_layer.nextFeature());
}

test "vector_tile_equal" {
    const allocator = std.testing.allocator;
    try std.testing.expect(try vectorTileEqual(allocator, "", ""));

    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    try std.testing.expectEqual(@as(usize, 269388), buffer.len);
    try std.testing.expect(try vectorTileEqual(allocator, buffer, buffer));

    try std.testing.expect(!(try vectorTileEqual(allocator, buffer, "")));
}

test "Copy tile" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    while (try tile.nextLayer()) |layer| {
        var lbuilder = try tbuilder.createLayerFromExisting(layer);
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            try lbuilder.addFeature(feat);
        }
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    try std.testing.expect(try vectorTileEqual(allocator, buffer, data));
}

test "Copy tile using geometry_feature_builder" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    while (try tile.nextLayer()) |layer| {
        var lbuilder = try tbuilder.createLayerFromExisting(layer);
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            var fbuilder = vtzero.GeometryFeatureBuilder.init(&lbuilder);
            defer fbuilder.deinit(allocator);
            try fbuilder.copyId(feat);
            try fbuilder.setGeometry(feat.geometry());
            var mf = feat;
            try fbuilder.copyProperties(&mf);
            try fbuilder.commit();
        }
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    try std.testing.expect(try vectorTileEqual(allocator, buffer, data));
}

test "Copy tile using geometry_feature_builder and property_mapper" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    while (try tile.nextLayer()) |layer| {
        // C++ `layer_builder{tbuilder, layer}`: same name/version/extent only — empty keys/values;
        // `property_mapper` fills the tables via add_*_without_dup_check (see property_mapper.hpp).
        var lbuilder = try tbuilder.createLayer(layer.name(), layer.version(), layer.extent());
        var mapper = try vtzero.PropertyMapper.init(allocator, layer, &lbuilder);
        defer mapper.deinit();
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            var fbuilder = vtzero.GeometryFeatureBuilder.init(&lbuilder);
            defer fbuilder.deinit(allocator);
            try fbuilder.copyId(feat);
            try fbuilder.setGeometry(feat.geometry());
            var mf = feat;
            try fbuilder.copyPropertiesMapped(&mf, &mapper);
            try fbuilder.commit();
        }
    }

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    try std.testing.expect(try vectorTileEqual(allocator, buffer, data));
}

test "Copy only point geometries using geometry_feature_builder" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    var n: i32 = 0;
    while (try tile.nextLayer()) |layer| {
        var lbuilder = try tbuilder.createLayerFromExisting(layer);
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            var fbuilder = vtzero.GeometryFeatureBuilder.init(&lbuilder);
            defer fbuilder.deinit(allocator);
            try fbuilder.setId(feat.id());
            if (feat.geometry().geom_type == .POINT) {
                try fbuilder.setGeometry(feat.geometry());
                var mf = feat;
                while (try mf.nextProperty()) |prop| {
                    try fbuilder.addProperty(allocator, prop.key(), prop.value());
                }
                try fbuilder.commit();
                n += 1;
            } else {
                fbuilder.rollback(allocator);
            }
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    n = 0;
    var result_tile = vtzero.VectorTile.init(data);
    while (try result_tile.nextLayer()) |layer| {
        var ml = layer;
        while (try ml.nextFeature()) |_| {
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);
}

test "Copy only point geometries using point_feature_builder" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    var n: i32 = 0;
    while (try tile.nextLayer()) |layer| {
        var lbuilder = try tbuilder.createLayerFromExisting(layer);
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
            defer fbuilder.deinit(allocator);
            try fbuilder.copyId(feat);
            if (feat.geometry().geom_type == .POINT) {
                var collector = PointsToVector{ .allocator = allocator };
                const points = try vtzero.decodePointGeometry(feat.geometry(), &collector);
                try fbuilder.addPointsFromContainer(allocator, points);
                collector.deinit();
                var mf = feat;
                try fbuilder.copyProperties(allocator, &mf);
                try fbuilder.commit(allocator);
                n += 1;
            } else {
                fbuilder.rollback(allocator);
            }
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    n = 0;
    var result_tile = vtzero.VectorTile.init(data);
    while (try result_tile.nextLayer()) |layer| {
        var ml = layer;
        while (try ml.nextFeature()) |_| {
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);
}

test "Copy only point geometries using point_feature_builder using property_mapper" {
    const allocator = std.testing.allocator;
    const buffer = try testlib.loadTestTile(testlib.testIo(), allocator);
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();

    var n: i32 = 0;
    while (try tile.nextLayer()) |layer| {
        var lbuilder = try tbuilder.createLayer(layer.name(), layer.version(), layer.extent());
        var mapper = try vtzero.PropertyMapper.init(allocator, layer, &lbuilder);
        defer mapper.deinit();
        var ml = layer;
        while (try ml.nextFeature()) |feat| {
            var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
            defer fbuilder.deinit(allocator);
            try fbuilder.copyId(feat);
            if (feat.geometry().geom_type == .POINT) {
                var collector = PointsToVector{ .allocator = allocator };
                const points = try vtzero.decodePointGeometry(feat.geometry(), &collector);
                try fbuilder.addPointsFromContainer(allocator, points);
                collector.deinit();
                var mf = feat;
                try fbuilder.copyPropertiesMapped(allocator, &mf, &mapper);
                try fbuilder.commit(allocator);
                n += 1;
            } else {
                fbuilder.rollback(allocator);
            }
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);

    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);
    n = 0;
    var result_tile = vtzero.VectorTile.init(data);
    while (try result_tile.nextLayer()) |layer| {
        var ml = layer;
        while (try ml.nextFeature()) |_| {
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(i32, 17), n);
}

test "Build point feature from container with too many points" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    var fbuilder = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fbuilder.deinit(allocator);
    try fbuilder.setId(1);
    // C++ uses a fake container with size 1<<29 and add_points_from_container; same guard as addPoints(1<<29).
    try std.testing.expectError(error.InvalidGeometryCount, fbuilder.addPoints(allocator, @as(u32, 1) << 29));
}

test "Moving a feature builder is allowed" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 2, 4096);
    // C++: auto fbuilder2 = std::move(fbuilder); const fbuilder3{std::move(fbuilder2)};
    const fbuilder2 = vtzero.PointFeatureBuilder.init(&lbuilder);
    var fbuilder3 = fbuilder2;
    defer fbuilder3.deinit(allocator);
}
