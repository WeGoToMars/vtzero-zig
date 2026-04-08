const std = @import("std");
const vtzero = @import("vtzero");

test "add keys to layer using key index built into layer" {
    const max_keys: u32 = 100;
    var tbuilder = vtzero.TileBuilder.init(std.testing.allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);

    var n: u32 = 0;
    while (n < max_keys) : (n += 1) {
        const key = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{n});
        defer std.testing.allocator.free(key);
        const idx = try lbuilder.addKey(key);
        try std.testing.expectEqual(n, idx.value());
    }

    n = 0;
    while (n < max_keys) : (n += 2) {
        const key = try std.fmt.allocPrint(std.testing.allocator, "{d}", .{n});
        defer std.testing.allocator.free(key);
        const idx = try lbuilder.addKey(key);
        try std.testing.expectEqual(n, idx.value());
    }
}

test "add values to layer using value index built into layer" {
    const max_values: u32 = 100;
    const allocator = std.testing.allocator;

    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);

    var n: u32 = 0;
    while (n < max_values) : (n += 1) {
        const value = try std.fmt.allocPrint(allocator, "{d}", .{n});
        defer allocator.free(value);
        var epv = try vtzero.EncodedPropertyValue.fromString(allocator, value);
        defer epv.deinit();
        const idx = try lbuilder.addEncodedValue(epv);
        try std.testing.expectEqual(n, idx.value());
    }

    n = 0;
    while (n < max_values) : (n += 2) {
        const value = try std.fmt.allocPrint(allocator, "{d}", .{n});
        defer allocator.free(value);
        var epv = try vtzero.EncodedPropertyValue.fromString(allocator, value);
        defer epv.deinit();
        const idx = try lbuilder.addEncodedValue(epv);
        try std.testing.expectEqual(n, idx.value());
    }
}

fn testKeyIndex() !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);
    var index = vtzero.index.KeyIndex.init(allocator, &lbuilder);
    defer index.deinit();

    const idx1 = try index.get("foo");
    const idx2 = try index.get("bar");
    const idx3 = try index.get("baz");
    const idx4 = try index.get("foo");
    const idx5 = try index.get("foo");
    const idx6 = try index.get("");
    const idx7 = try index.get("bar");

    try std.testing.expect(idx1.value() != idx2.value());
    try std.testing.expect(idx1.value() != idx3.value());
    try std.testing.expectEqual(idx1.value(), idx4.value());
    try std.testing.expectEqual(idx1.value(), idx5.value());
    try std.testing.expect(idx1.value() != idx6.value());
    try std.testing.expect(idx1.value() != idx7.value());
    try std.testing.expect(idx2.value() != idx3.value());
    try std.testing.expect(idx2.value() != idx4.value());
    try std.testing.expect(idx2.value() != idx5.value());
    try std.testing.expect(idx2.value() != idx6.value());
    try std.testing.expectEqual(idx2.value(), idx7.value());
    try std.testing.expect(idx3.value() != idx4.value());
    try std.testing.expect(idx3.value() != idx5.value());
    try std.testing.expect(idx3.value() != idx6.value());
    try std.testing.expect(idx3.value() != idx7.value());
    try std.testing.expectEqual(idx4.value(), idx5.value());
    try std.testing.expect(idx4.value() != idx6.value());
    try std.testing.expect(idx4.value() != idx7.value());
    try std.testing.expect(idx5.value() != idx6.value());
    try std.testing.expect(idx5.value() != idx7.value());
    try std.testing.expect(idx6.value() != idx7.value());
}

test "key index based on std::unordered_map" {
    try testKeyIndex();
}

test "key index based on std::map" {
    try testKeyIndex();
}

fn testValueIndexInternal() !void {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);
    var index = vtzero.index.ValueIndexInternal.init(allocator, &lbuilder);
    defer index.deinit();

    var e1 = try vtzero.EncodedPropertyValue.fromString(allocator, "foo");
    defer e1.deinit();
    var e2 = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
    defer e2.deinit();
    var e3 = try vtzero.EncodedPropertyValue.fromInt(allocator, 88);
    defer e3.deinit();
    var e4 = try vtzero.EncodedPropertyValue.fromString(allocator, "foo");
    defer e4.deinit();
    var e5 = try vtzero.EncodedPropertyValue.fromInt(allocator, 77);
    defer e5.deinit();
    var e6 = try vtzero.EncodedPropertyValue.fromDouble(allocator, 1.5);
    defer e6.deinit();
    var e7 = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
    defer e7.deinit();

    const idx1 = try index.get(e1);
    const idx2 = try index.get(e2);
    const idx3 = try index.get(e3);
    const idx4 = try index.get(e4);
    const idx5 = try index.get(e5);
    const idx6 = try index.get(e6);
    const idx7 = try index.get(e7);

    try std.testing.expect(idx1.value() != idx2.value());
    try std.testing.expect(idx1.value() != idx3.value());
    try std.testing.expectEqual(idx1.value(), idx4.value());
    try std.testing.expect(idx1.value() != idx5.value());
    try std.testing.expect(idx1.value() != idx6.value());
    try std.testing.expect(idx1.value() != idx7.value());

    try std.testing.expect(idx2.value() != idx3.value());
    try std.testing.expect(idx2.value() != idx4.value());
    try std.testing.expect(idx2.value() != idx5.value());
    try std.testing.expect(idx2.value() != idx6.value());
    try std.testing.expectEqual(idx2.value(), idx7.value());
}

test "internal value index based on std::unordered_map" {
    try testValueIndexInternal();
}

test "internal value index based on std::map" {
    try testValueIndexInternal();
}

test "external value index" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);

    var string_index = vtzero.index.ValueIndexString.init(allocator, &lbuilder);
    defer string_index.deinit();
    var int_index = vtzero.index.ValueIndexInt.init(allocator, &lbuilder);
    defer int_index.deinit();
    var sint_index = vtzero.index.ValueIndexSInt.init(allocator, &lbuilder);
    defer sint_index.deinit();

    const idx1 = try string_index.get("foo");
    const idx2 = try string_index.get("bar");
    const idx3 = try int_index.get(6);
    const idx4 = try sint_index.get(6);
    const idx5 = try string_index.get("foo");
    const idx6 = try int_index.get(6);
    const idx7 = try sint_index.get(2);
    const idx8 = try sint_index.get(5);
    const idx9 = try sint_index.get(6);

    try std.testing.expect(idx1.value() != idx2.value());
    try std.testing.expect(idx1.value() != idx3.value());
    try std.testing.expect(idx1.value() != idx4.value());
    try std.testing.expectEqual(idx1.value(), idx5.value());
    try std.testing.expect(idx1.value() != idx6.value());
    try std.testing.expect(idx1.value() != idx7.value());
    try std.testing.expect(idx1.value() != idx9.value());

    try std.testing.expect(idx3.value() != idx4.value());
    try std.testing.expectEqual(idx3.value(), idx6.value());
    try std.testing.expect(idx4.value() != idx7.value());
    try std.testing.expectEqual(idx4.value(), idx9.value());
    try std.testing.expect(idx8.value() != idx9.value());
}

test "bool value index" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);
    var index = vtzero.index.ValueIndexBool.init(allocator, &lbuilder);
    defer index.deinit();

    const idx1 = try index.get(false);
    const idx2 = try index.get(true);
    const idx3 = try index.get(true);
    const idx4 = try index.get(false);

    try std.testing.expect(idx1.value() != idx2.value());
    try std.testing.expect(idx1.value() != idx3.value());
    try std.testing.expectEqual(idx1.value(), idx4.value());
    try std.testing.expectEqual(idx2.value(), idx3.value());
    try std.testing.expect(idx2.value() != idx4.value());
}

test "small unsigned int value index" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);
    var index = vtzero.index.ValueIndexSmallUInt.init(allocator, &lbuilder);
    defer index.deinit();

    const idx1 = try index.get(12);
    const idx2 = try index.get(4);
    const idx3 = try index.get(0);
    const idx4 = try index.get(100);
    const idx5 = try index.get(4);
    const idx6 = try index.get(12);

    try std.testing.expect(idx1.value() != idx2.value());
    try std.testing.expect(idx1.value() != idx3.value());
    try std.testing.expect(idx1.value() != idx4.value());
    try std.testing.expect(idx1.value() != idx5.value());
    try std.testing.expectEqual(idx1.value(), idx6.value());
    try std.testing.expectEqual(idx2.value(), idx5.value());
}

test "add features using a key index" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);

    var fb = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fb.deinit(allocator);
    try fb.setId(7);
    try fb.addPoint(allocator, .{ .x = 10, .y = 20 });

    // no index
    try fb.addProperty(allocator, "some_key", @as(i64, 12));

    try fb.commit(allocator);
    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);

    var tile = vtzero.VectorTile.init(data);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()).?;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    var feature = (try layer.nextFeature()).?;
    try std.testing.expectEqual(@as(u64, 7), feature.id());
    const property = (try feature.nextProperty()).?;
    try std.testing.expectEqual(@as(i64, 12), try property.value().intValue());
}

test "add features using a value index" {
    const allocator = std.testing.allocator;
    var tbuilder = vtzero.TileBuilder.init(allocator);
    defer tbuilder.deinit();
    var lbuilder = try tbuilder.createLayer("test", 1, 4096);
    const key = try lbuilder.addKey("some_key");

    var fb = vtzero.PointFeatureBuilder.init(&lbuilder);
    defer fb.deinit(allocator);
    try fb.setId(17);
    try fb.addPoint(allocator, .{ .x = 10, .y = 20 });

    // external value index (sint)
    var sint_index = vtzero.index.ValueIndexSInt.init(allocator, &lbuilder);
    defer sint_index.deinit();
    const value_idx = try sint_index.get(12);
    try fb.addProperty(allocator, key, value_idx);

    try fb.commit(allocator);
    const data = try tbuilder.serialize(allocator);
    defer allocator.free(data);

    var tile = vtzero.VectorTile.init(data);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()).?;
    var feature = (try layer.nextFeature()).?;
    const prop = (try feature.nextProperty()).?;
    try std.testing.expectEqual(@as(i64, 12), try prop.value().sintValue());
}
