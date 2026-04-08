const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "default constructed feature" {
    var feature = vtzero.Feature{};
    try std.testing.expect(!feature.valid());
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expect(!feature.hasId());
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, feature.geometryType());
    try std.testing.expect(feature.empty());
    try std.testing.expectEqual(@as(usize, 0), feature.numProperties());
    try std.testing.expectEqual(@as(usize, 0), feature.geometry().data.len);
}

test "read a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    const feature = (try layer.nextFeature()).?;

    try std.testing.expect(feature.valid());
    try std.testing.expect(feature.hasId());
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.LINESTRING, feature.geometryType());
    try std.testing.expectEqual(@as(usize, 4), feature.numProperties());
}

test "iterate over all properties of a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    var feature = (try layer.nextFeature()).?;

    var count: usize = 0;
    var saw_type = false;
    while (try feature.nextProperty()) |p| : (count += 1) {
        if (std.mem.eql(u8, p.key(), "type")) {
            saw_type = true;
            try std.testing.expectEqualStrings("primary", try p.value().stringValue());
        }
    }

    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expect(saw_type);
}

test "iterate over some properties of a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    var feature = (try layer.nextFeature()).?;

    // external iterator
    {
        feature.resetProperty();
        var count: usize = 0;
        while (try feature.nextProperty()) |p| {
            count += 1;
            if (std.mem.eql(u8, p.key(), "oneway")) break;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    // internal iterator (ported from vtzero::feature::for_each_property)
    {
        feature.resetProperty();
        var count: usize = 0;
        while (try feature.nextProperty()) |p| {
            count += 1;
            if (std.mem.eql(u8, p.key(), "oneway")) break;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }
}
