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
        var reader = pbf.Reader.init(data);
        var properties_seen = false;

        while (try reader.next()) |field| {
            switch (field.tag) {
                mvt.Feature.id => {
                    if (field.wire_type != .varint) return error.InvalidFeatureField;
                    result.id_value = try pbf.decodeUint64(field.data);
                    result.has_id_value = true;
                },
                mvt.Feature.tags => {
                    if (field.wire_type != .length_delimited) return error.InvalidFeatureField;
                    if (properties_seen) return error.DuplicateTagsField;
                    result.properties = field.data;
                    properties_seen = true;
                },
                mvt.Feature.@"type" => {
                    if (field.wire_type != .varint) return error.InvalidFeatureField;
                    const value = try pbf.decodeUint32(field.data);
                    result.geometry_type_value = switch (value) {
                        0 => .UNKNOWN,
                        1 => .POINT,
                        2 => .LINESTRING,
                        3 => .POLYGON,
                        else => return error.UnknownGeometryTypeValue,
                    };
                },
                mvt.Feature.geometry => {
                    if (field.wire_type != .length_delimited) return error.InvalidFeatureField;
                    if (result.geometry_data != null) return error.DuplicateGeometryField;
                    result.geometry_data = field.data;
                },
                else => {},
            }
        }

        // Spec 4.2 requires a geometry field.
        if (result.geometry_data == null) return error.MissingGeometryField;

        var it = pbf.PackedUInt32Iterator.init(result.properties);
        var count: usize = 0;
        while (try it.next()) |_| count += 1;
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
