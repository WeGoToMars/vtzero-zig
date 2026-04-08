//! Contains the classes and functions to build vector tiles.

const std = @import("std");
const types = @import("types.zig");
const pbf = @import("detail/pbf.zig");
const mvt = @import("mvt_schema.zig");
const impl = @import("builder_impl.zig");
const layer_mod = @import("layer.zig");
const feature_mod = @import("feature.zig");
const property_mod = @import("property.zig");
const property_value_mod = @import("property_value.zig");
const encoded_value_mod = @import("encoded_property_value.zig");
const ByteList = std.array_list.Managed(u8);

pub const GeomType = types.GeomType;
pub const Point = types.Point;
pub const Geometry = types.Geometry;
pub const IndexValue = types.IndexValue;
pub const IndexValuePair = types.IndexValuePair;
pub const Layer = layer_mod.Layer;
pub const Feature = feature_mod.Feature;
pub const Property = property_mod.Property;
pub const PropertyValue = property_value_mod.PropertyValue;
pub const EncodedPropertyValue = encoded_value_mod.EncodedPropertyValue;

const LayerBuilderImpl = impl.LayerBuilderImpl;

const LayerEntry = union(enum) {
    existing: []const u8,
    built: *LayerBuilderImpl,
};

/// Used to build vector tiles. Whenever you are building a new vector
/// tile, start with an object of this class and add layers. After all
/// the data is added, call `serialize()`
pub const TileBuilder = struct {
    allocator: std.mem.Allocator,
    layers: std.ArrayListUnmanaged(LayerEntry) = .empty,

    pub fn init(allocator: std.mem.Allocator) TileBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TileBuilder) void {
        for (self.layers.items) |entry| {
            switch (entry) {
                .existing => {},
                .built => |layer| layer.deinit(),
            }
        }
        self.layers.deinit(self.allocator);
    }

    pub fn addExistingLayerData(self: *TileBuilder, data: []const u8) !void {
        try self.layers.append(self.allocator, .{ .existing = data });
    }

    /// Add a new layer to the vector tile based on an existing layer.
    pub fn addExistingLayer(self: *TileBuilder, layer: Layer) !void {
        try self.addExistingLayerData(layer.data orelse return error.InvalidLayer);
    }

    pub fn createLayer(self: *TileBuilder, name: []const u8, version: u32, extent: u32) !LayerBuilder {
        const layer = try LayerBuilderImpl.init(self.allocator, name, version, extent);
        try self.layers.append(self.allocator, .{ .built = layer });
        return .{ .layer = layer };
    }

    pub fn createLayerFromExisting(self: *TileBuilder, layer: Layer) !LayerBuilder {
        var lb = try self.createLayer(layer.name(), layer.version(), layer.extent());
        // Preserve key/value tables so features can be copied by index.
        try lb.layer.importTablesFromLayerData(layer.data orelse return error.InvalidLayer);
        return lb;
    }

    /// Append encoded vector tile bytes to `out` (existing contents are preserved).
    /// Matches C++ `tile_builder::serialize(TBuffer&)`: estimates output size then appends layers.
    pub fn serializeAppend(self: *const TileBuilder, allocator: std.mem.Allocator, out: *ByteList) !void {
        _ = allocator;
        var estimated: usize = 0;
        for (self.layers.items) |entry| {
            switch (entry) {
                .existing => |bytes| estimated += bytes.len + 8,
                .built => |layer| estimated += layer.estimatedSize(),
            }
        }
        try out.ensureUnusedCapacity(estimated);

        for (self.layers.items) |entry| {
            switch (entry) {
                .existing => |bytes| try appendLengthDelimitedField(out, mvt.Tile.layers, bytes),
                .built => |layer| try layer.appendTileLayerMessage(out),
            }
        }
    }

    pub fn serialize(self: *const TileBuilder, allocator: std.mem.Allocator) ![]u8 {
        var out = ByteList.init(allocator);
        errdefer out.deinit();
        try self.serializeAppend(allocator, &out);
        return out.toOwnedSlice();
    }

    /// Write the encoded tile into `buf` without allocating. Returns the number of bytes written.
    pub fn serializeBounded(self: *const TileBuilder, allocator: std.mem.Allocator, buf: []u8) !usize {
        _ = allocator;
        var w = pbf.SliceWriter{ .buf = buf };
        for (self.layers.items) |entry| {
            switch (entry) {
                .existing => |bytes| try pbf.appendLengthDelimitedFieldSliceWriter(&w, mvt.Tile.layers, bytes),
                .built => |layer| try impl.appendBuiltLayerVectoredSlice(&w, layer),
            }
        }
        return w.pos;
    }
};

/// Builder for one layer.
pub const LayerBuilder = struct {
    layer: *LayerBuilderImpl,

    pub fn addKeyWithoutDupCheck(self: *LayerBuilder, text: []const u8) !IndexValue {
        return self.layer.addKeyWithoutDupCheck(text);
    }

    pub fn addKey(self: *LayerBuilder, text: []const u8) !IndexValue {
        return self.layer.addKey(text);
    }

    pub fn addValueWithoutDupCheck(self: *LayerBuilder, value: PropertyValue) !IndexValue {
        return self.layer.addValueWithoutDupCheck(value.data orelse return error.InvalidPropertyValue);
    }

    pub fn addEncodedValueWithoutDupCheck(self: *LayerBuilder, value: EncodedPropertyValue) !IndexValue {
        return self.layer.addValueWithoutDupCheck(value.data());
    }

    pub fn addValue(self: *LayerBuilder, value: PropertyValue) !IndexValue {
        return self.layer.addValue(value.data orelse return error.InvalidPropertyValue);
    }

    pub fn addEncodedValue(self: *LayerBuilder, value: EncodedPropertyValue) !IndexValue {
        return self.layer.addValue(value.data());
    }

    pub fn addFeature(self: *LayerBuilder, feature: Feature) !void {
        var fb = GeometryFeatureBuilder.init(self);
        defer fb.deinit(self.layer.allocator);
        if (feature.hasId()) try fb.setId(feature.id());
        try fb.setGeometry(feature.geometry());
        var feature_copy = feature;
        // This layer builder is typically created via `createLayerFromExisting()`, which imports
        // the source layer's key/value tables. In that common case, we can copy property indexes
        // directly without resolving key/value bytes.
        while (try feature_copy.nextPropertyIndexes()) |idxs| {
            try fb.addPropertyIndexes(idxs);
        }
        try fb.commit();
    }
};

const PendingGeometry = union(enum) {
    encoded_u32: std.ArrayListUnmanaged(u32),
    raw_bytes: []const u8,
};

/// Explicit state machine for feature builder.
const FeatureLifecycle = enum { building, committed, rolled_back };

const FeatureBuilderCommon = struct {
    layer: *LayerBuilderImpl,
    feature_type: GeomType,
    has_id: bool = false,
    id_value: u64 = 0,
    tags: std.ArrayListUnmanaged(u32) = .empty,
    geometry: ?PendingGeometry = null,
    lifecycle: FeatureLifecycle = .building,

    fn resetGeometryAndTags(self: *FeatureBuilderCommon, allocator: std.mem.Allocator) void {
        self.tags.deinit(allocator);
        self.tags = .empty;
        if (self.geometry) |*g| {
            switch (g.*) {
                .encoded_u32 => |*arr| arr.deinit(allocator),
                .raw_bytes => {},
            }
            self.geometry = null;
        }
    }

    fn deinit(self: *FeatureBuilderCommon, allocator: std.mem.Allocator) void {
        self.resetGeometryAndTags(allocator);
        self.* = undefined;
    }

    fn setId(self: *FeatureBuilderCommon, id: u64) !void {
        if (self.lifecycle != .building) return error.FeatureBuilderFinalized;
        if (self.geometry != null) return error.InvalidBuilderState;
        if (self.tags.items.len != 0) return error.InvalidBuilderState;
        self.has_id = true;
        self.id_value = id;
    }

    fn ensureGeometryEncoded(self: *FeatureBuilderCommon) !*std.ArrayListUnmanaged(u32) {
        if (self.lifecycle != .building) return error.FeatureBuilderFinalized;
        if (self.geometry == null) {
            self.geometry = .{ .encoded_u32 = .empty };
        }
        if (self.geometry.? != .encoded_u32) return error.GeometryAlreadySet;
        return &self.geometry.?.encoded_u32;
    }

    fn ensureProperty(self: *FeatureBuilderCommon, allocator: std.mem.Allocator, key: anytype, value: anytype) !void {
        if (self.lifecycle != .building) return error.FeatureBuilderFinalized;
        if (self.geometry == null) return error.GeometryNotSet;

        const key_index = try resolveKey(self.layer, key);
        const value_index = try resolveValue(self.layer, allocator, value);
        try self.tags.append(allocator, key_index.value());
        try self.tags.append(allocator, value_index.value());
    }

    fn ensurePropertyObject(self: *FeatureBuilderCommon, allocator: std.mem.Allocator, prop: Property) !void {
        if (!prop.valid()) return error.InvalidProperty;
        try self.ensureProperty(allocator, prop.key(), prop.value());
    }

    fn ensurePropertyIndexes(self: *FeatureBuilderCommon, allocator: std.mem.Allocator, idxs: IndexValuePair) !void {
        if (!idxs.valid()) return error.InvalidIndexPair;
        if (self.lifecycle != .building) return error.FeatureBuilderFinalized;
        if (self.geometry == null) return error.GeometryNotSet;
        try self.tags.append(allocator, idxs.key().value());
        try self.tags.append(allocator, idxs.value().value());
    }

    /// Matches C++ `feature_builder::rollback()`: no-op if already committed or rolled back.
    fn rollback(self: *FeatureBuilderCommon, allocator: std.mem.Allocator) void {
        if (self.lifecycle != .building) return;
        self.resetGeometryAndTags(allocator);
        self.has_id = false;
        self.id_value = 0;
        self.lifecycle = .rolled_back;
    }

    fn commit(self: *FeatureBuilderCommon, allocator: std.mem.Allocator) !void {
        if (self.lifecycle != .building) return;
        if (self.geometry == null) return error.GeometryNotSet;

        const geom = self.geometry.?;
        const geometry_payload: []const u8 = switch (geom) {
            .encoded_u32 => |arr| try encodePackedU32(allocator, arr.items),
            .raw_bytes => |bytes| bytes,
        };
        defer switch (geom) {
            .encoded_u32 => allocator.free(geometry_payload),
            .raw_bytes => {},
        };

        try self.layer.appendFeatureMessageStreaming(
            allocator,
            self.has_id,
            self.id_value,
            self.feature_type,
            geometry_payload,
            self.tags.items,
        );
        self.lifecycle = .committed;
    }
};

/// Builder for point features.
pub const PointFeatureBuilder = struct {
    common: FeatureBuilderCommon,
    cursor: Point = .{},
    remaining: u32 = 0,
    used_single: bool = false,

    pub fn init(layer: *LayerBuilder) PointFeatureBuilder {
        return .{
            .common = .{
                .layer = layer.layer,
                .feature_type = .POINT,
            },
        };
    }

    pub fn deinit(self: *PointFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.deinit(allocator);
    }

    pub fn setId(self: *PointFeatureBuilder, id: u64) !void {
        try self.common.setId(id);
    }

    pub fn copyId(self: *PointFeatureBuilder, feature: Feature) !void {
        if (feature.hasId()) try self.setId(feature.id());
    }

    pub fn copyProperties(self: *PointFeatureBuilder, allocator: std.mem.Allocator, feature: *Feature) !void {
        feature.resetProperty();
        // Prefer copying by index to avoid repeatedly resolving key/value bytes.
        while (try feature.nextPropertyIndexes()) |idxs| {
            try self.addPropertyIndexes(allocator, idxs);
        }
    }

    /// Same role as C++ `copy_properties(feature, mapper)`.
    pub fn copyPropertiesMapped(self: *PointFeatureBuilder, allocator: std.mem.Allocator, feature: *Feature, mapper: anytype) !void {
        feature.resetProperty();
        while (try feature.nextPropertyIndexes()) |idxs| {
            const mapped = try mapper.map(idxs);
            try self.addPropertyIndexes(allocator, mapped);
        }
    }

    pub fn addPropertyIndexes(self: *PointFeatureBuilder, allocator: std.mem.Allocator, idxs: IndexValuePair) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.ensurePropertyIndexes(allocator, idxs);
    }

    pub fn rollback(self: *PointFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.rollback(allocator);
        self.cursor = .{};
        self.remaining = 0;
        self.used_single = false;
    }

    /// Matches C++ `add_points_from_container`: throws if `points.len >= 2^29`.
    pub fn addPointsFromContainer(self: *PointFeatureBuilder, allocator: std.mem.Allocator, points: []const Point) !void {
        if (points.len >= (@as(usize, 1) << 29)) return error.InvalidGeometryCount;
        try self.addPoints(allocator, @intCast(points.len));
        for (points) |pt| {
            try self.setPoint(allocator, pt);
        }
    }

    pub fn addPoint(self: *PointFeatureBuilder, allocator: std.mem.Allocator, point: Point) !void {
        if (self.used_single or self.remaining > 0) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        try geom.append(allocator, commandMoveTo(1));
        try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
        try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
        self.cursor = point;
        self.used_single = true;
    }

    pub fn addPoints(self: *PointFeatureBuilder, allocator: std.mem.Allocator, count: u32) !void {
        if (count == 0 or count >= (1 << 29)) return error.InvalidGeometryCount;
        if (self.used_single or self.remaining > 0) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        try geom.append(allocator, commandMoveTo(count));
        self.remaining = count;
    }

    pub fn setPoint(self: *PointFeatureBuilder, allocator: std.mem.Allocator, point: Point) !void {
        if (self.remaining == 0) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        self.remaining -= 1;
        try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
        try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
        self.cursor = point;
    }

    pub fn addProperty(self: *PointFeatureBuilder, allocator: std.mem.Allocator, key: anytype, value: anytype) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.ensureProperty(allocator, key, value);
    }

    pub fn addPropertyObject(self: *PointFeatureBuilder, allocator: std.mem.Allocator, prop: Property) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.ensurePropertyObject(allocator, prop);
    }

    pub fn commit(self: *PointFeatureBuilder, allocator: std.mem.Allocator) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.commit(allocator);
    }
};

/// Builder for linestring features.
pub const LinestringFeatureBuilder = struct {
    common: FeatureBuilderCommon,
    cursor: Point = .{},
    remaining: u32 = 0,
    start_line: bool = false,

    pub fn init(layer: *LayerBuilder) LinestringFeatureBuilder {
        return .{
            .common = .{
                .layer = layer.layer,
                .feature_type = .LINESTRING,
            },
        };
    }

    pub fn deinit(self: *LinestringFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.deinit(allocator);
    }

    pub fn setId(self: *LinestringFeatureBuilder, id: u64) !void {
        try self.common.setId(id);
    }

    pub fn rollback(self: *LinestringFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.rollback(allocator);
        self.cursor = .{};
        self.remaining = 0;
        self.start_line = false;
    }

    pub fn addLinestring(self: *LinestringFeatureBuilder, count: u32) !void {
        if (count <= 1 or count >= (1 << 29)) return error.InvalidGeometryCount;
        if (self.remaining != 0) return error.IncompleteGeometry;
        _ = try self.common.ensureGeometryEncoded();
        self.remaining = count;
        self.start_line = true;
    }

    pub fn setPoint(self: *LinestringFeatureBuilder, allocator: std.mem.Allocator, point: Point) !void {
        if (self.remaining == 0) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        self.remaining -= 1;

        if (self.start_line) {
            try geom.append(allocator, commandMoveTo(1));
            try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
            try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
            try geom.append(allocator, commandLineTo(self.remaining));
            self.start_line = false;
        } else {
            if (point.x == self.cursor.x and point.y == self.cursor.y) return error.ZeroLengthSegment;
            try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
            try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
        }
        self.cursor = point;
    }

    pub fn addProperty(self: *LinestringFeatureBuilder, allocator: std.mem.Allocator, key: anytype, value: anytype) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.ensureProperty(allocator, key, value);
    }

    pub fn commit(self: *LinestringFeatureBuilder, allocator: std.mem.Allocator) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.commit(allocator);
    }
};

/// Builder for polygon features.
pub const PolygonFeatureBuilder = struct {
    common: FeatureBuilderCommon,
    cursor: Point = .{},
    first: Point = .{},
    remaining: u32 = 0,
    start_ring: bool = false,

    pub fn init(layer: *LayerBuilder) PolygonFeatureBuilder {
        return .{
            .common = .{
                .layer = layer.layer,
                .feature_type = .POLYGON,
            },
        };
    }

    pub fn deinit(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.deinit(allocator);
    }

    pub fn setId(self: *PolygonFeatureBuilder, id: u64) !void {
        try self.common.setId(id);
    }

    pub fn rollback(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.rollback(allocator);
        self.cursor = .{};
        self.first = .{};
        self.remaining = 0;
        self.start_ring = false;
    }

    pub fn addRing(self: *PolygonFeatureBuilder, count: u32) !void {
        if (count <= 3 or count >= (1 << 29)) return error.InvalidGeometryCount;
        if (self.remaining != 0) return error.IncompleteGeometry;
        _ = try self.common.ensureGeometryEncoded();
        self.remaining = count;
        self.start_ring = true;
    }

    pub fn setPoint(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator, point: Point) !void {
        if (self.remaining == 0) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        self.remaining -= 1;

        if (self.start_ring) {
            self.first = point;
            try geom.append(allocator, commandMoveTo(1));
            try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
            try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
            try geom.append(allocator, commandLineTo(self.remaining - 1));
            self.start_ring = false;
            self.cursor = point;
            return;
        }

        if (self.remaining == 0) {
            if (point.x != self.first.x or point.y != self.first.y) return error.UnclosedRing;
            try geom.append(allocator, commandClosePath());
            return;
        }

        if (point.x == self.cursor.x and point.y == self.cursor.y) return error.ZeroLengthSegment;
        try geom.append(allocator, encodeZigZag32(point.x - self.cursor.x));
        try geom.append(allocator, encodeZigZag32(point.y - self.cursor.y));
        self.cursor = point;
    }

    pub fn closeRing(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator) !void {
        if (self.remaining != 1) return error.InvalidBuilderState;
        var geom = try self.common.ensureGeometryEncoded();
        self.remaining = 0;
        try geom.append(allocator, commandClosePath());
    }

    pub fn addProperty(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator, key: anytype, value: anytype) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.ensureProperty(allocator, key, value);
    }

    pub fn commit(self: *PolygonFeatureBuilder, allocator: std.mem.Allocator) !void {
        if (self.remaining != 0) return error.IncompleteGeometry;
        try self.common.commit(allocator);
    }
};

/// Builder for directly setting an already-encoded geometry.
pub const GeometryFeatureBuilder = struct {
    common: FeatureBuilderCommon,

    pub fn init(layer: *LayerBuilder) GeometryFeatureBuilder {
        return .{
            .common = .{
                .layer = layer.layer,
                .feature_type = .UNKNOWN,
            },
        };
    }

    pub fn deinit(self: *GeometryFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.deinit(allocator);
    }

    pub fn setId(self: *GeometryFeatureBuilder, id: u64) !void {
        try self.common.setId(id);
    }

    pub fn copyId(self: *GeometryFeatureBuilder, feature: Feature) !void {
        if (feature.hasId()) try self.setId(feature.id());
    }

    pub fn setGeometry(self: *GeometryFeatureBuilder, geometry: Geometry) !void {
        if (self.common.geometry != null) return error.GeometryAlreadySet;
        self.common.feature_type = geometry.geom_type;
        self.common.geometry = .{ .raw_bytes = geometry.data };
    }

    pub fn addProperty(self: *GeometryFeatureBuilder, allocator: std.mem.Allocator, key: anytype, value: anytype) !void {
        try self.common.ensureProperty(allocator, key, value);
    }

    pub fn addPropertyObject(self: *GeometryFeatureBuilder, prop: Property) !void {
        try self.common.ensurePropertyObject(self.common.layer.allocator, prop);
    }

    pub fn addPropertyIndexes(self: *GeometryFeatureBuilder, idxs: IndexValuePair) !void {
        try self.common.ensurePropertyIndexes(self.common.layer.allocator, idxs);
    }

    pub fn copyProperties(self: *GeometryFeatureBuilder, feature: *Feature) !void {
        feature.resetProperty();
        // Prefer copying by index to avoid repeatedly resolving key/value bytes.
        while (try feature.nextPropertyIndexes()) |idxs| {
            try self.addPropertyIndexes(idxs);
        }
    }

    pub fn copyPropertiesMapped(self: *GeometryFeatureBuilder, feature: *Feature, mapper: anytype) !void {
        feature.resetProperty();
        while (try feature.nextPropertyIndexes()) |idxs| {
            const mapped = try mapper.map(idxs);
            try self.addPropertyIndexes(mapped);
        }
    }

    pub fn rollback(self: *GeometryFeatureBuilder, allocator: std.mem.Allocator) void {
        self.common.rollback(allocator);
    }

    pub fn commit(self: *GeometryFeatureBuilder) !void {
        try self.common.commit(self.common.layer.allocator);
    }
};

pub fn commandInteger(id: u32, count: u32) u32 {
    return (id & 0x7) | (count << 3);
}

pub fn commandMoveTo(count: u32) u32 {
    return commandInteger(1, count);
}

pub fn commandLineTo(count: u32) u32 {
    return commandInteger(2, count);
}

pub fn commandClosePath() u32 {
    return commandInteger(7, 1);
}

fn resolveKey(layer: *LayerBuilderImpl, key: anytype) !IndexValue {
    const T = @TypeOf(key);
    if (T == IndexValue) return key;
    if (T == []const u8) return layer.addKey(key);
    if (asBytes(key)) |bytes| return layer.addKey(bytes);
    return error.UnsupportedKeyType;
}

fn resolveValue(layer: *LayerBuilderImpl, allocator: std.mem.Allocator, value: anytype) !IndexValue {
    const T = @TypeOf(value);
    if (T == IndexValue) return value;
    if (T == PropertyValue) return layer.addValue(value.data orelse return error.InvalidPropertyValue);
    if (T == EncodedPropertyValue) return layer.addValue(value.data());
    if (T == []const u8) {
        var encoded = try EncodedPropertyValue.fromString(allocator, value);
        defer encoded.deinit();
        return layer.addValue(encoded.data());
    }
    if (asBytes(value)) |bytes| {
        var encoded = try EncodedPropertyValue.fromString(allocator, bytes);
        defer encoded.deinit();
        return layer.addValue(encoded.data());
    }
    if (T == bool) {
        var encoded = try EncodedPropertyValue.fromBool(allocator, value);
        defer encoded.deinit();
        return layer.addValue(encoded.data());
    }
    switch (@typeInfo(T)) {
        .int => |i| {
            if (i.signedness == .signed) {
                var encoded = try EncodedPropertyValue.fromInt(allocator, @intCast(value));
                defer encoded.deinit();
                return layer.addValue(encoded.data());
            }
            var encoded = try EncodedPropertyValue.fromUInt(allocator, @intCast(value));
            defer encoded.deinit();
            return layer.addValue(encoded.data());
        },
        .float => {
            if (T == f32) {
                var encoded = try EncodedPropertyValue.fromFloat(allocator, value);
                defer encoded.deinit();
                return layer.addValue(encoded.data());
            }
            var encoded = try EncodedPropertyValue.fromDouble(allocator, @floatCast(value));
            defer encoded.deinit();
            return layer.addValue(encoded.data());
        },
        else => return error.UnsupportedValueType,
    }
}

fn asBytes(value: anytype) ?[]const u8 {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) return value;
            if (p.size == .one) {
                switch (@typeInfo(p.child)) {
                    .array => |arr| {
                        if (arr.child != u8) return null;
                        return value[0..arr.len];
                    },
                    else => {},
                }
            }
        },
        else => {},
    }
    return null;
}

fn appendVarintField(out: *ByteList, tag: u32, value: u64) !void {
    try pbf.appendVarintManaged(out, pbf.fieldKey(tag, .varint));
    try pbf.appendVarintManaged(out, value);
}

fn appendLengthDelimitedField(out: *ByteList, tag: u32, payload: []const u8) !void {
    try pbf.appendVarintManaged(out, pbf.fieldKey(tag, .length_delimited));
    try pbf.appendVarintManaged(out, payload.len);
    try out.appendSlice(payload);
}

fn appendVarint(out: *ByteList, value_any: anytype) !void {
    try pbf.appendVarintManaged(out, @intCast(value_any));
}

fn encodePackedU32(allocator: std.mem.Allocator, values: []const u32) ![]u8 {
    var out = ByteList.init(allocator);
    errdefer out.deinit();
    for (values) |v| try appendVarint(&out, v);
    return out.toOwnedSlice();
}

fn encodeZigZag32(value: i32) u32 {
    return (@as(u32, @bitCast(value)) << 1) ^ @as(u32, @bitCast(value >> 31));
}
