const std = @import("std");
const pbf = @import("detail/pbf.zig");
const types = @import("types.zig");
const property_mod = @import("property.zig");
const property_value_mod = @import("property_value.zig");
const mvt = @import("mvt_schema.zig");

pub const GeomType = types.GeomType;
pub const Geometry = types.Geometry;
pub const IndexValuePair = types.IndexValuePair;
pub const Property = property_mod.Property;
pub const PropertyValue = property_value_mod.PropertyValue;

/// Feature view with lazy property iteration.
/// Stores parent layer metadata (raw bytes and table sizes) for key/value lookup.
pub const Feature = struct {
    layer_data: ?[]const u8 = null,
    key_table_size: usize = 0,
    value_table_size: usize = 0,

    id_value: u64 = 0,
    properties: []const u8 = &.{},
    property_pos: usize = 0,
    num_properties_value: usize = 0,
    geometry_data: ?[]const u8 = null,
    geometry_type_value: GeomType = .UNKNOWN,
    has_id_value: bool = false,

    /// Parse and validate a feature message.
    pub fn init(layer_data: []const u8, key_table_size: usize, value_table_size: usize, data: []const u8) !Feature {
        var result = Feature{
            .layer_data = layer_data,
            .key_table_size = key_table_size,
            .value_table_size = value_table_size,
        };
        var properties_seen = false;
        var pos: usize = 0;

        while (pos < data.len) {
            const key = try pbf.decodeVarintAt(data, &pos);
            const tag = @as(u32, @intCast(key >> 3));
            if (tag == 0) return error.InvalidTag;
            const wt_num = @as(u3, @truncate(key & 0x7));

            switch (tag) {
                mvt.Feature.id => {
                    if (wt_num != @intFromEnum(pbf.WireType.varint)) return error.InvalidFeatureField;
                    result.id_value = try pbf.decodeVarintAt(data, &pos);
                    result.has_id_value = true;
                },
                mvt.Feature.tags => {
                    if (wt_num != @intFromEnum(pbf.WireType.length_delimited)) return error.InvalidFeatureField;
                    if (properties_seen) return error.DuplicateTagsField;
                    result.properties = try decodeLengthDelimited(data, &pos);
                    properties_seen = true;
                },
                mvt.Feature.@"type" => {
                    if (wt_num != @intFromEnum(pbf.WireType.varint)) return error.InvalidFeatureField;
                    const value = std.math.cast(u32, try pbf.decodeVarintAt(data, &pos)) orelse return error.IntegerOverflow;
                    result.geometry_type_value = switch (value) {
                        0 => .UNKNOWN,
                        1 => .POINT,
                        2 => .LINESTRING,
                        3 => .POLYGON,
                        else => return error.UnknownGeometryTypeValue,
                    };
                },
                mvt.Feature.geometry => {
                    if (wt_num != @intFromEnum(pbf.WireType.length_delimited)) return error.InvalidFeatureField;
                    if (result.geometry_data != null) return error.DuplicateGeometryField;
                    result.geometry_data = try decodeLengthDelimited(data, &pos);
                },
                else => try skipFieldValue(data, &pos, wt_num),
            }
        }

        // Spec 4.2 requires a geometry field.
        if (result.geometry_data == null) return error.MissingGeometryField;

        // Each varint contributes exactly one byte with MSB cleared.
        // Counting those bytes is faster than fully decoding all packed values.
        var count: usize = 0;
        for (result.properties) |b| {
            if ((b & 0x80) == 0) count += 1;
        }
        // Spec 4.4 stores tags as key/value index pairs.
        if ((count % 2) != 0) return error.UnpairedPropertyIndexes;
        result.num_properties_value = count / 2;

        return result;
    }

    pub fn valid(self: Feature) bool {
        return self.geometry_data != null;
    }

    pub fn id(self: Feature) u64 {
        return self.id_value;
    }

    pub fn hasId(self: Feature) bool {
        return self.has_id_value;
    }

    pub fn geometryType(self: Feature) GeomType {
        return self.geometry_type_value;
    }

    pub fn geometry(self: Feature) Geometry {
        return .{
            .data = self.geometry_data orelse &.{},
            .geom_type = self.geometry_type_value,
        };
    }

    pub fn empty(self: Feature) bool {
        return self.num_properties_value == 0;
    }

    pub fn numProperties(self: Feature) usize {
        return self.num_properties_value;
    }

    pub fn resetProperty(self: *Feature) void {
        self.property_pos = 0;
    }

    /// Return the next key/value index pair from the packed tags array.
    pub fn nextPropertyIndexes(self: *Feature) !?IndexValuePair {
        _ = self.layer_data orelse return error.InvalidFeature;
        if (self.property_pos >= self.properties.len) return null;

        var pos = self.property_pos;
        const key_index = try pbf.decodeVarintAt(self.properties, &pos);
        const value_index = try pbf.decodeVarintAt(self.properties, &pos);
        self.property_pos = pos;

        const ki = std.math.cast(u32, key_index) orelse return error.IndexOutOfRange;
        const vi = std.math.cast(u32, value_index) orelse return error.IndexOutOfRange;

        // Validate against table sizes before callers dereference indexes.
        if (@as(usize, ki) >= self.key_table_size) return error.IndexOutOfRange;
        if (@as(usize, vi) >= self.value_table_size) return error.IndexOutOfRange;

        return .{
            .key_index = .init(ki),
            .value_index = .init(vi),
        };
    }

    pub fn nextProperty(self: *Feature) !?Property {
        const idxs = (try self.nextPropertyIndexes()) orelse return null;
        return .{
            .key_data = try keyFromLayerData(self.layer_data.?, idxs.key().value()),
            .value_data = try valueFromLayerData(self.layer_data.?, idxs.value().value()),
        };
    }
};

fn decodeLengthDelimited(data: []const u8, pos: *usize) ![]const u8 {
    const len = try pbf.decodeVarintAt(data, pos);
    if (len > std.math.maxInt(usize)) return error.LengthOverflow;
    const usize_len: usize = @intCast(len);
    if (pos.* + usize_len > data.len) return error.UnexpectedEof;
    const start = pos.*;
    pos.* += usize_len;
    return data[start..pos.*];
}

fn skipFieldValue(data: []const u8, pos: *usize, wt_num: u3) !void {
    switch (wt_num) {
        @intFromEnum(pbf.WireType.varint) => {
            const start = pos.*;
            while (pos.* < data.len) {
                const b = data[pos.*];
                pos.* += 1;
                if ((b & 0x80) == 0) return;
                if (pos.* - start >= 10) return error.VarintOverflow;
            }
            return error.UnexpectedEof;
        },
        @intFromEnum(pbf.WireType.fixed64) => {
            if (pos.* + 8 > data.len) return error.UnexpectedEof;
            pos.* += 8;
        },
        @intFromEnum(pbf.WireType.length_delimited) => {
            const len = try pbf.decodeVarintAt(data, pos);
            if (len > std.math.maxInt(usize)) return error.LengthOverflow;
            const usize_len: usize = @intCast(len);
            if (pos.* + usize_len > data.len) return error.UnexpectedEof;
            pos.* += usize_len;
        },
        @intFromEnum(pbf.WireType.fixed32) => {
            if (pos.* + 4 > data.len) return error.UnexpectedEof;
            pos.* += 4;
        },
        else => return error.UnsupportedWireType,
    }
}

fn keyFromLayerData(layer_data: []const u8, index: u32) ![]const u8 {
    var reader = pbf.Reader.init(layer_data);
    var current: u32 = 0;
    while (try reader.next()) |field| {
        if (field.tag == mvt.Layer.keys and field.wire_type == .length_delimited) {
            if (current == index) return field.data;
            current += 1;
        }
    }
    return error.IndexOutOfRange;
}

fn valueFromLayerData(layer_data: []const u8, index: u32) !PropertyValue {
    var reader = pbf.Reader.init(layer_data);
    var current: u32 = 0;
    while (try reader.next()) |field| {
        if (field.tag == mvt.Layer.values and field.wire_type == .length_delimited) {
            if (current == index) return PropertyValue.init(field.data);
            current += 1;
        }
    }
    return error.IndexOutOfRange;
}
