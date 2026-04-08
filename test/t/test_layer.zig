const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "default constructed layer" {
    var layer = vtzero.Layer{};
    try std.testing.expect(!layer.valid());
    try std.testing.expect(layer.empty());
    try std.testing.expectEqual(@as(usize, 0), layer.numFeatures());

    try std.testing.expectError(error.InvalidLayer, layer.collectKeyTable(std.testing.allocator));
    try std.testing.expectError(error.InvalidLayer, layer.collectValueTable(std.testing.allocator));
    try std.testing.expectError(error.InvalidLayer, layer.key(0));
    try std.testing.expectError(error.InvalidLayer, layer.value(0));

    try std.testing.expectError(error.InvalidLayer, layer.getFeatureById(0));
    try std.testing.expectError(error.InvalidLayer, layer.nextFeature());
    layer.resetFeature();
}

test "read a layer" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;

    try std.testing.expectEqual(@as(u32, 1), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqualStrings("bridge", layer.name());
    try std.testing.expectEqual(@as(usize, 2), layer.numFeatures());

    const allocator = std.testing.allocator;
    const keys = try layer.collectKeyTable(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 4), keys.len);
    try std.testing.expectEqualStrings("class", keys[0]);

    const values = try layer.collectValueTable(allocator);
    defer allocator.free(values);
    try std.testing.expectEqual(@as(usize, 4), values.len);
    try std.testing.expectEqualStrings("main", try values[0].stringValue());

    try std.testing.expectEqualStrings("class", try layer.key(0));
    try std.testing.expectEqualStrings("oneway", try layer.key(1));
    try std.testing.expectEqualStrings("osm_id", try layer.key(2));
    try std.testing.expectEqualStrings("type", try layer.key(3));
    try std.testing.expectError(error.IndexOutOfRange, layer.key(4));

    try std.testing.expectEqualStrings("main", try (try layer.value(0)).stringValue());
    try std.testing.expectEqual(@as(i64, 0), try (try layer.value(1)).intValue());
    try std.testing.expectEqualStrings("primary", try (try layer.value(2)).stringValue());
    try std.testing.expectEqualStrings("tertiary", try (try layer.value(3)).stringValue());
    try std.testing.expectError(error.IndexOutOfRange, layer.value(4));
}

test "access features in a layer by id" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("building")).?;

    try std.testing.expectEqual(@as(usize, 937), layer.numFeatures());
    const feature = (try layer.getFeatureById(122)).?;
    try std.testing.expectEqual(@as(u64, 122), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.POLYGON, feature.geometryType());
    try std.testing.expect(feature.geometry().data.len != 0);
    try std.testing.expect((try layer.getFeatureById(999999)) == null);
    try std.testing.expect((try layer.getFeatureById(844)) == null);
}

fn forEachFeature(layer: *vtzero.Layer, ctx: anytype, f: anytype) !bool {
    while (try layer.nextFeature()) |feature| {
        if (!f(ctx, feature)) return false;
    }
    return true;
}

test "iterate over all features in a layer" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);

    // external iterator
    {
        var layer = (try tile.getLayerByName("building")).?;
        var count: usize = 0;
        while (try layer.nextFeature()) |_| count += 1;
        try std.testing.expectEqual(@as(usize, 937), count);
    }

    // internal iterator (ported from vtzero::layer::for_each_feature)
    {
        var layer = (try tile.getLayerByName("building")).?;
        var count: usize = 0;
        const done = try forEachFeature(&layer, &count, struct {
            fn cb(count_ptr: *usize, _: vtzero.Feature) bool {
                count_ptr.* += 1;
                return true;
            }
        }.cb);
        try std.testing.expect(done);
        try std.testing.expectEqual(@as(usize, 937), count);
    }
}

test "iterate over some features in a layer" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);

    // external iterator
    {
        var layer = (try tile.getLayerByName("building")).?;
        var id_sum: u64 = 0;
        while (try layer.nextFeature()) |feature| {
            if (feature.id() == 10) break;
            id_sum += feature.id();
        }
        const expected: u64 = (10 - 1) * 10 / 2;
        try std.testing.expectEqual(expected, id_sum);

        layer.resetFeature();
        const feature1 = (try layer.nextFeature()).?;
        try std.testing.expectEqual(@as(u64, 1), feature1.id());
    }

    // internal iterator
    {
        var layer = (try tile.getLayerByName("building")).?;
        var id_sum: u64 = 0;
        const done = try forEachFeature(&layer, &id_sum, struct {
            fn cb(sum_ptr: *u64, feature: vtzero.Feature) bool {
                if (feature.id() == 10) return false;
                sum_ptr.* += feature.id();
                return true;
            }
        }.cb);
        try std.testing.expect(!done);
        const expected: u64 = (10 - 1) * 10 / 2;
        try std.testing.expectEqual(expected, id_sum);
    }
}
