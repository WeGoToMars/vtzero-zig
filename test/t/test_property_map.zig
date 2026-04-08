const std = @import("std");
const vtzero = @import("vtzero");

test "property map" {
    const allocator = std.testing.allocator;

    var tile_builder = vtzero.TileBuilder.init(allocator);
    defer tile_builder.deinit();

    var layer_points = try tile_builder.createLayer("points", 2, 4096);
    {
        var fb = vtzero.PointFeatureBuilder.init(&layer_points);
        defer fb.deinit(allocator);

        try fb.setId(1);
        try fb.addPoints(allocator, 1);
        try fb.setPoint(allocator, .{ .x = 10, .y = 10 });
        try fb.addProperty(allocator, "foo", "bar");
        try fb.addProperty(allocator, "x", "y");
        try fb.addProperty(allocator, "abc", "def");
        try fb.commit(allocator);
    }

    const data = try tile_builder.serialize(allocator);
    defer allocator.free(data);

    var vt = vtzero.VectorTile.init(data);
    try std.testing.expectEqual(@as(usize, 1), try vt.countLayers());
    var layer = (try vt.nextLayer()).?;
    try std.testing.expect(layer.valid());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()).?;
    try std.testing.expect(feature.valid());
    try std.testing.expectEqual(@as(usize, 3), feature.numProperties());

    // Zig equivalent of create_properties_map: materialize to a string->string map.
    var props = std.StringHashMap([]const u8).init(allocator);
    defer props.deinit();

    while (try feature.nextProperty()) |p| {
        const v = try p.value().stringValue();
        try props.put(p.key(), v);
    }

    try std.testing.expectEqual(@as(usize, 3), props.count());
    try std.testing.expectEqualStrings("bar", props.get("foo").?);
    try std.testing.expectEqualStrings("y", props.get("x").?);
    try std.testing.expectEqualStrings("def", props.get("abc").?);
}

