const std = @import("std");
const vtzero = @import("vtzero");
const testlib = @import("../include/test.zig");

fn openTile(io: std.Io, allocator: std.mem.Allocator, rel_path: []const u8) ![]u8 {
    const fixtures_dir: []const u8 = if (std.c.getenv("FIXTURES_DIR")) |z|
        std.mem.span(z)
    else
        "vtzero/test/mvt-fixtures/fixtures";

    const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ fixtures_dir, rel_path });
    defer allocator.free(full_path);

    return std.Io.Dir.cwd().readFileAlloc(
        io,
        full_path,
        allocator,
        .limited(32 * 1024 * 1024),
    );
}

fn checkLayer(tile: *vtzero.VectorTile) !vtzero.Feature {
    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqualStrings("hello", layer.name());
    try std.testing.expectEqual(@as(u32, 2), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    return (try layer.nextFeature()) orelse return error.MissingFeature;
}

const PointHandler = struct {
    points: std.ArrayListUnmanaged(vtzero.Point) = .empty,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PointHandler) void {
        self.points.deinit(self.allocator);
    }

    pub fn points_begin(self: *PointHandler, count: u32) !void {
        try self.points.ensureTotalCapacity(self.allocator, count);
    }

    pub fn points_point(self: *PointHandler, point: vtzero.Point) !void {
        try self.points.append(self.allocator, point);
    }

    pub fn points_end(_: *PointHandler) void {}
};

const LinestringHandler = struct {
    lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point)) = .empty,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LinestringHandler) void {
        for (self.lines.items) |*line| line.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    pub fn linestring_begin(self: *LinestringHandler, count: u32) !void {
        try self.lines.append(self.allocator, .empty);
        try self.lines.items[self.lines.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn linestring_point(self: *LinestringHandler, point: vtzero.Point) !void {
        try self.lines.items[self.lines.items.len - 1].append(self.allocator, point);
    }

    pub fn linestring_end(_: *LinestringHandler) void {}
};

const PolygonHandler = struct {
    rings: std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point)) = .empty,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PolygonHandler) void {
        for (self.rings.items) |*ring| ring.deinit(self.allocator);
        self.rings.deinit(self.allocator);
    }

    pub fn ring_begin(self: *PolygonHandler, count: u32) !void {
        try self.rings.append(self.allocator, .empty);
        try self.rings.items[self.rings.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn ring_point(self: *PolygonHandler, point: vtzero.Point) !void {
        try self.rings.items[self.rings.items.len - 1].append(self.allocator, point);
    }

    pub fn ring_end(_: *PolygonHandler, _: vtzero.RingType) void {}
};

const GeomHandler = struct {
    points: std.ArrayListUnmanaged(vtzero.Point) = .empty,
    lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point)) = .empty,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GeomHandler) void {
        self.points.deinit(self.allocator);
        for (self.lines.items) |*line| line.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    pub fn points_begin(self: *GeomHandler, count: u32) !void {
        try self.points.ensureTotalCapacity(self.allocator, count);
    }

    pub fn points_point(self: *GeomHandler, point: vtzero.Point) !void {
        try self.points.append(self.allocator, point);
    }

    pub fn points_end(_: *GeomHandler) void {}

    pub fn linestring_begin(self: *GeomHandler, count: u32) !void {
        try self.lines.append(self.allocator, .empty);
        try self.lines.items[self.lines.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn linestring_point(self: *GeomHandler, point: vtzero.Point) !void {
        try self.lines.items[self.lines.items.len - 1].append(self.allocator, point);
    }

    pub fn linestring_end(_: *GeomHandler) void {}

    pub fn ring_begin(self: *GeomHandler, count: u32) !void {
        try self.lines.append(self.allocator, .empty);
        try self.lines.items[self.lines.items.len - 1].ensureTotalCapacity(self.allocator, count);
    }

    pub fn ring_point(self: *GeomHandler, point: vtzero.Point) !void {
        try self.lines.items[self.lines.items.len - 1].append(self.allocator, point);
    }

    pub fn ring_end(_: *GeomHandler, _: vtzero.RingType) void {}
};

test "MVT test 001: Empty tile" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "001/tile.mvt");
    defer allocator.free(buffer);
    const tile = vtzero.VectorTile.init(buffer);

    try std.testing.expect(tile.empty());
    try std.testing.expectEqual(@as(usize, 0), try tile.countLayers());
}

test "MVT test 002: Tile with single point feature without id" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "002/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    const feature = try checkLayer(&tile);

    try std.testing.expect(!feature.hasId());
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.POINT, feature.geometryType());

    var handler = PointHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodePointGeometry(feature.geometry(), &handler);

    const expected = [_]vtzero.Point{.{ .x = 25, .y = 17 }};
    try std.testing.expectEqualSlices(vtzero.Point, &expected, handler.points.items);
}

test "MVT test 003: Tile with single point with missing geometry type" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "003/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    const feature = try checkLayer(&tile);
    try std.testing.expect(feature.hasId());
    try std.testing.expectEqual(@as(u64, 1), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, feature.geometryType());
}

test "MVT test 004: Tile with single point with missing geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "004/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectError(error.MissingGeometryField, checkLayer(&tile));
}

test "MVT test 005: Tile with single point with broken tags array" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "005/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(!layer.empty());

    try std.testing.expectError(error.UnpairedPropertyIndexes, layer.nextFeature());
}

test "MVT test 006: Tile with single point with invalid GeomType" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "006/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(!layer.empty());

    try std.testing.expectError(error.UnknownGeometryTypeValue, layer.nextFeature());
}

test "MVT test 007: Layer version as string instead of as an int" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "007/tile.mvt");
    defer allocator.free(buffer);
    const tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.InvalidLayerField, tile.getLayer(0));
}

test "MVT test 008: Tile layer extent encoded as string" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "008/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.InvalidLayerField, tile.nextLayer());
}

test "MVT test 009: Tile layer extent missing" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "009/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;

    try std.testing.expectEqualStrings("hello", layer.name());
    try std.testing.expectEqual(@as(u32, 2), layer.version());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(u64, 1), feature.id());
}

test "MVT test 010: Tile layer value is encoded as int, but pretends to be string" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "010/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(!layer.empty());

    const pv = try layer.value(0);
    try std.testing.expectError(error.IllegalPropertyValueType, pv.type());
}

test "MVT test 011: Tile layer value is encoded as unknown type" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "011/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(!layer.empty());

    const pv = try layer.value(0);
    try std.testing.expectError(error.IllegalPropertyValueType, pv.type());
}

test "MVT test 012: Unknown layer version" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "012/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.UnknownVectorTileVersion, tile.nextLayer());
}

test "MVT test 013: Tile with key in table encoded as int" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "013/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.InvalidLayerField, tile.nextLayer());
}

test "MVT test 014: Tile layer without a name" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "014/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.MissingLayerName, tile.nextLayer());
}

test "MVT test 015: Two layers with the same name" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "015/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 2), try tile.countLayers());
    while (try tile.nextLayer()) |layer| {
        try std.testing.expectEqualStrings("hello", layer.name());
    }

    const layer = (try vtzero.VectorTile.init(buffer).getLayerByName("hello")) orelse return error.MissingLayer;
    try std.testing.expectEqualStrings("hello", layer.name());
}

test "MVT test 016: Valid unknown geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "016/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    const feature = try checkLayer(&tile);
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, feature.geometryType());
}

test "MVT test 017: Valid point geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "017/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expect(feature.hasId());
    try std.testing.expectEqual(@as(u64, 1), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.POINT, feature.geometryType());

    const expected = [_]vtzero.Point{.{ .x = 25, .y = 17 }};

    {
        var handler = PointHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodePointGeometry(feature.geometry(), &handler);
        try std.testing.expectEqualSlices(vtzero.Point, &expected, handler.points.items);
    }

    {
        var handler = GeomHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodeGeometry(feature.geometry(), &handler);
        try std.testing.expectEqualSlices(vtzero.Point, &expected, handler.points.items);
    }
}

test "MVT test 018: Valid linestring geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "018/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expectEqual(vtzero.GeomType.LINESTRING, feature.geometryType());
    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 2, .y = 2 },
            .{ .x = 2, .y = 10 },
            .{ .x = 10, .y = 10 },
        },
    };

    {
        var handler = LinestringHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodeLinestringGeometry(feature.geometry(), &handler);
        try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
        for (expected, 0..) |exp, i| {
            try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
        }
    }

    {
        var handler = GeomHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodeGeometry(feature.geometry(), &handler);
        try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
        for (expected, 0..) |exp, i| {
            try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
        }
    }
}

test "MVT test 019: Valid polygon geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "019/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expectEqual(vtzero.GeomType.POLYGON, feature.geometryType());
    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 3, .y = 6 },
            .{ .x = 8, .y = 12 },
            .{ .x = 20, .y = 34 },
            .{ .x = 3, .y = 6 },
        },
    };

    {
        var handler = PolygonHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodePolygonGeometry(feature.geometry(), &handler);
        try std.testing.expectEqual(@as(usize, expected.len), handler.rings.items.len);
        for (expected, 0..) |exp, i| {
            try std.testing.expectEqualSlices(vtzero.Point, exp, handler.rings.items[i].items);
        }
    }

    {
        var handler = GeomHandler{ .allocator = allocator };
        defer handler.deinit();
        _ = try vtzero.decodeGeometry(feature.geometry(), &handler);
        try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
        for (expected, 0..) |exp, i| {
            try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
        }
    }
}

test "MVT test 020: Valid multipoint geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "020/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expectEqual(vtzero.GeomType.POINT, feature.geometryType());
    var handler = PointHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodePointGeometry(feature.geometry(), &handler);

    const expected = [_]vtzero.Point{
        .{ .x = 5, .y = 7 },
        .{ .x = 3, .y = 2 },
    };
    try std.testing.expectEqualSlices(vtzero.Point, &expected, handler.points.items);
}

test "MVT test 021: Valid multilinestring geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "021/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expectEqual(vtzero.GeomType.LINESTRING, feature.geometryType());
    var handler = LinestringHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeLinestringGeometry(feature.geometry(), &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 2, .y = 2 },
            .{ .x = 2, .y = 10 },
            .{ .x = 10, .y = 10 },
        },
        &[_]vtzero.Point{
            .{ .x = 1, .y = 1 },
            .{ .x = 3, .y = 5 },
        },
    };

    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 022: Valid multipolygon geometry" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "022/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    const feature = try checkLayer(&tile);

    try std.testing.expectEqual(vtzero.GeomType.POLYGON, feature.geometryType());
    var handler = PolygonHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodePolygonGeometry(feature.geometry(), &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 0, .y = 0 },
            .{ .x = 10, .y = 0 },
            .{ .x = 10, .y = 10 },
            .{ .x = 0, .y = 10 },
            .{ .x = 0, .y = 0 },
        },
        &[_]vtzero.Point{
            .{ .x = 11, .y = 11 },
            .{ .x = 20, .y = 11 },
            .{ .x = 20, .y = 20 },
            .{ .x = 11, .y = 20 },
            .{ .x = 11, .y = 11 },
        },
        &[_]vtzero.Point{
            .{ .x = 13, .y = 13 },
            .{ .x = 13, .y = 17 },
            .{ .x = 17, .y = 17 },
            .{ .x = 17, .y = 13 },
            .{ .x = 13, .y = 13 },
        },
    };

    try std.testing.expectEqual(@as(usize, expected.len), handler.rings.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.rings.items[i].items);
    }
}

test "MVT test 023: Invalid layer: missing layer name" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "023/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    try std.testing.expectError(error.MissingLayerName, tile.nextLayer());
    try std.testing.expectError(error.MissingLayerName, tile.getLayerByName("foo"));
}

test "MVT test 024: Missing layer version" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "024/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    const layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(u32, 1), layer.version());
}

test "MVT test 025: Layer without features" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "025/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    const layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(layer.empty());
    try std.testing.expectEqual(@as(usize, 0), layer.numFeatures());
}

test "MVT test 026: Extra value type" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "026/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expect(feature.empty());

    const table = try layer.collectValueTable(allocator);
    defer allocator.free(table);
    try std.testing.expectEqual(@as(usize, 1), table.len);
    try std.testing.expect(table[0].valid());
    try std.testing.expectError(error.IllegalPropertyValueType, table[0].type());
}

test "MVT test 027: Layer with unused bool property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "027/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 0), feature.numProperties());

    const vtab = try layer.collectValueTable(allocator);
    defer allocator.free(vtab);
    try std.testing.expectEqual(@as(usize, 1), vtab.len);
    try std.testing.expect(try vtab[0].boolValue());
}

test "MVT test 030: Two geometry fields" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "030/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expect(!layer.empty());
    try std.testing.expectError(error.DuplicateGeometryField, layer.nextFeature());
}

test "MVT test 032: Layer with single feature with string property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "032/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expect(!tile.empty());
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    var prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectEqualStrings("i am a string value", try prop.value().stringValue());

    feature.resetProperty();
    const ii = (try feature.nextPropertyIndexes()) orelse return error.MissingProperty;
    try std.testing.expectEqual(@as(u32, 0), ii.key().value());
    try std.testing.expectEqual(@as(u32, 0), ii.value().value());
    try std.testing.expectEqual(@as(?vtzero.IndexValuePair, null), try feature.nextPropertyIndexes());

    var sum: u32 = 0;
    var count: u32 = 0;
    feature.resetProperty();
    while (try feature.nextPropertyIndexes()) |ivp| {
        sum += ivp.key().value();
        sum += ivp.value().value();
        count += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), sum);
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "MVT test 033: Layer with single feature with float property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "033/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    const prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectApproxEqAbs(@as(f32, 3.1), try prop.value().floatValue(), 0.0001);
}

test "MVT test 034: Layer with single feature with double property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "034/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    const prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectApproxEqAbs(@as(f64, 1.23), try prop.value().doubleValue(), 0.0000001);
}

test "MVT test 035: Layer with single feature with int property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "035/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    const prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectEqual(@as(i64, 6), try prop.value().intValue());
}

test "MVT test 036: Layer with single feature with uint property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "036/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    const prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectEqual(@as(u64, 87948), try prop.value().uintValue());
}

test "MVT test 037: Layer with single feature with sint property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "037/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    const prop = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expectEqualStrings("key1", prop.key());
    try std.testing.expectEqual(@as(i64, 87948), try prop.value().sintValue());
}

test "MVT test 038: Layer with all types of property value" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "038/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    const layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    const vtab = try layer.collectValueTable(allocator);
    defer allocator.free(vtab);

    try std.testing.expectEqual(@as(usize, 7), vtab.len);
    try std.testing.expectEqualStrings("ello", try vtab[0].stringValue());
    try std.testing.expect(try vtab[1].boolValue());
    try std.testing.expectEqual(@as(i64, 6), try vtab[2].intValue());
    try std.testing.expectApproxEqAbs(@as(f64, 1.23), try vtab[3].doubleValue(), 0.0000001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.1), try vtab[4].floatValue(), 0.0001);
    try std.testing.expectEqual(@as(i64, -87948), try vtab[5].sintValue());
    try std.testing.expectEqual(@as(u64, 87948), try vtab[6].uintValue());

    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].boolValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].intValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].doubleValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].floatValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].sintValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[0].uintValue());
    try std.testing.expectError(error.WrongPropertyValueType, vtab[1].stringValue());
}

test "MVT test 039: Default values are actually encoded in the tile" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "039/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(u32, 1), layer.version());
    try std.testing.expectEqualStrings("hello", layer.name());
    try std.testing.expectEqual(@as(u32, 4096), layer.extent());
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());

    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, feature.geometryType());
    try std.testing.expect(feature.empty());

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.UnknownGeometryType, vtzero.decodeGeometry(feature.geometry(), &handler));
}

test "MVT test 040: Feature has tags that point to non-existent Key in the layer." {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "040/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());
    try std.testing.expectError(error.IndexOutOfRange, feature.nextProperty());
}

test "MVT test 040: Feature has tags that point to non-existent Key in the layer decoded using next_property_indexes()." {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "040/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());
    try std.testing.expectError(error.IndexOutOfRange, feature.nextPropertyIndexes());
}

test "MVT test 041: Tags encoded as floats instead of as ints" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "041/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectError(error.IndexOutOfRange, feature.nextProperty());
}

test "MVT test 042: Feature has tags that point to non-existent Value in the layer." {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "042/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);

    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());
    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());
    try std.testing.expectError(error.IndexOutOfRange, feature.nextProperty());
}

test "MVT test 043: A layer with six points that all share the same key but each has a unique value." {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "043/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 6), layer.numFeatures());

    var feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expect(feature.valid());
    try std.testing.expectEqual(@as(usize, 1), feature.numProperties());

    var property = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expect(property.valid());
    try std.testing.expectEqualStrings("poi", property.key());
    try std.testing.expectEqualStrings("swing", try property.value().stringValue());

    feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    try std.testing.expect(feature.valid());
    property = (try feature.nextProperty()) orelse return error.MissingProperty;
    try std.testing.expect(property.valid());
    try std.testing.expectEqualStrings("poi", property.key());
    try std.testing.expectEqualStrings("water_fountain", try property.value().stringValue());
}

test "MVT test 044: Geometry field begins with a ClosePath command, which is invalid" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "044/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.UnexpectedCommand, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 045: Invalid point geometry that includes a MoveTo command and only half of the xy coordinates" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "045/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.TooFewPoints, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 046: Invalid linestring geometry that includes two points in the same position, which is not OGC valid" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "046/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 2, .y = 2 },
            .{ .x = 2, .y = 10 },
            .{ .x = 2, .y = 10 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 047: Invalid polygon with wrong ClosePath count 2 (must be count 1)" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "047/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.InvalidClosePathCount, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 048: Invalid polygon with wrong ClosePath count 0 (must be count 1)" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "048/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.InvalidClosePathCount, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 049: decoding linestring with int32 overflow in x coordinate" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "049/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = std.math.maxInt(i32), .y = 0 },
            .{ .x = std.math.minInt(i32), .y = 1 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 050: decoding linestring with int32 overflow in y coordinate" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "050/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 0, .y = std.math.minInt(i32) },
            .{ .x = -1, .y = std.math.maxInt(i32) },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 051: multipoint with a huge count value, useful for ensuring no over-allocation errors. Example error message \"count too large\"" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "051/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.CountTooLarge, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 052: multipoint with not enough points" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "052/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    // C++ only requires a geometry_exception here (no specific message),
    // so the Zig port accepts any decoder error.
    if (vtzero.decodeGeometry(geometry, &handler)) |_| {
        return error.TestExpectedError;
    } else |_| {}
}

test "MVT test 053: clipped square (exact extent): a polygon that covers the entire tile to the exact boundary" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "053/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 0, .y = 0 },
            .{ .x = 4096, .y = 0 },
            .{ .x = 4096, .y = 4096 },
            .{ .x = 0, .y = 4096 },
            .{ .x = 0, .y = 0 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 054: clipped square (one unit buffer): a polygon that covers the entire tile plus a one unit buffer" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "054/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = -1, .y = -1 },
            .{ .x = 4097, .y = -1 },
            .{ .x = 4097, .y = 4097 },
            .{ .x = -1, .y = 4097 },
            .{ .x = -1, .y = -1 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 055: clipped square (minus one unit buffer): a polygon that almost covers the entire tile minus one unit buffer" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "055/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = 1, .y = 1 },
            .{ .x = 4095, .y = 1 },
            .{ .x = 4095, .y = 4095 },
            .{ .x = 1, .y = 4095 },
            .{ .x = 1, .y = 1 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 056: clipped square (large buffer): a polygon that covers the entire tile plus a 200 unit buffer" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "056/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    _ = try vtzero.decodeGeometry(geometry, &handler);

    const expected = [_][]const vtzero.Point{
        &[_]vtzero.Point{
            .{ .x = -200, .y = -200 },
            .{ .x = 4296, .y = -200 },
            .{ .x = 4296, .y = 4296 },
            .{ .x = -200, .y = 4296 },
            .{ .x = -200, .y = -200 },
        },
    };
    try std.testing.expectEqual(@as(usize, expected.len), handler.lines.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualSlices(vtzero.Point, exp, handler.lines.items[i].items);
    }
}

test "MVT test 057: A point fixture with a gigantic MoveTo command. Can be used to test decoders for memory overallocation situations" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "057/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.CountTooLarge, vtzero.decodeGeometry(geometry, &handler));
}

test "MVT test 058: A linestring fixture with a gigantic LineTo command" {
    const allocator = std.testing.allocator;
    const buffer = try openTile(testlib.testIo(), allocator, "058/tile.mvt");
    defer allocator.free(buffer);
    var tile = vtzero.VectorTile.init(buffer);
    try std.testing.expectEqual(@as(usize, 1), try tile.countLayers());

    var layer = (try tile.nextLayer()) orelse return error.MissingLayer;
    try std.testing.expectEqual(@as(usize, 1), layer.numFeatures());
    const feature = (try layer.nextFeature()) orelse return error.MissingFeature;
    const geometry = feature.geometry();

    var handler = GeomHandler{ .allocator = allocator };
    defer handler.deinit();
    try std.testing.expectError(error.CountTooLarge, vtzero.decodeGeometry(geometry, &handler));
}

