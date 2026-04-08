const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

test "open a vector tile with string" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    try std.testing.expect(vtzero.isVectorTile(data));
    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 12), try tile.countLayers());
}

test "open a vector tile with data_view" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const dv: []const u8 = data;
    const tile = vtzero.VectorTile.init(dv);

    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 12), try tile.countLayers());
}

test "open a vector tile with pointer and size" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const ptr: [*]const u8 = data.ptr;
    const slice = ptr[0..data.len];
    const tile = vtzero.VectorTile.init(slice);

    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 12), try tile.countLayers());
}

test "get layer by index" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);

    const layer0 = (try tile.getLayer(0)).?;
    try std.testing.expectEqualStrings("landuse", layer0.name());

    const layer1 = (try tile.getLayer(1)).?;
    try std.testing.expectEqualStrings("waterway", layer1.name());

    const layer11 = (try tile.getLayer(11)).?;
    try std.testing.expectEqualStrings("waterway_label", layer11.name());

    try std.testing.expect((try tile.getLayer(12)) == null);
}

test "get layer by name" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);

    const landuse = (try tile.getLayerByName("landuse")).?;
    try std.testing.expectEqualStrings("landuse", landuse.name());

    const layer = (try tile.getLayerByName("road")).?;
    try std.testing.expectEqualStrings("road", layer.name());

    const poi = (try tile.getLayerByName("poi_label")).?;
    try std.testing.expectEqualStrings("poi_label", poi.name());

    try std.testing.expect((try tile.getLayerByName("unknown")) == null);
}

fn forEachLayer(tile: *vtzero.VectorTile, ctx: anytype, f: anytype) !bool {
    while (try tile.nextLayer()) |layer| {
        if (!f(ctx, layer)) return false;
    }
    return true;
}

test "iterate over layers" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    var tile = vtzero.VectorTile.init(data);
    const expected = [_][]const u8{
        "landuse", "waterway",    "water",       "barrier_line", "building",   "road",
        "bridge",  "place_label", "water_label", "poi_label",    "road_label", "waterway_label",
    };

    // external iterator
    {
        var i: usize = 0;
        while (try tile.nextLayer()) |layer| : (i += 1) {
            try std.testing.expectEqualStrings(expected[i], layer.name());
        }
        try std.testing.expectEqual(expected.len, i);
    }

    // internal iterator
    tile.resetLayer();
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(std.testing.allocator);
    const done = try forEachLayer(&tile, &names, struct {
        fn cb(names_ptr: *std.ArrayList([]const u8), layer: vtzero.Layer) bool {
            // store layer names in the same order
            names_ptr.append(std.testing.allocator, layer.name()) catch return false;
            return true;
        }
    }.cb);
    try std.testing.expect(done);
    try std.testing.expectEqual(expected.len, names.items.len);
    for (expected, 0..) |e, idx| try std.testing.expectEqualStrings(e, names.items[idx]);

    tile.resetLayer();
    var num: usize = 0;
    while (try tile.nextLayer()) |_| num += 1;
    try std.testing.expectEqual(@as(usize, 12), num);
}

test "iterate over some of the layers" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);

    // external iterator
    {
        var tile = vtzero.VectorTile.init(data);
        var num_layers: usize = 0;
        while (try tile.nextLayer()) |layer| {
            num_layers += 1;
            if (std.mem.eql(u8, layer.name(), "water")) break;
        }
        try std.testing.expectEqual(@as(usize, 3), num_layers);
    }

    // internal iterator
    {
        var tile = vtzero.VectorTile.init(data);
        var num_layers: usize = 0;
        const done = try forEachLayer(&tile, &num_layers, struct {
            fn cb(num_layers_ptr: *usize, layer: vtzero.Layer) bool {
                num_layers_ptr.* += 1;
                return !std.mem.eql(u8, layer.name(), "water");
            }
        }.cb);
        try std.testing.expect(!done);
        try std.testing.expectEqual(@as(usize, 3), num_layers);
    }
}
