const std = @import("std");
const pbf = @import("detail/pbf.zig");
const property_value_mod = @import("property_value.zig");
const feature_mod = @import("feature.zig");
const mvt = @import("mvt_schema.zig");

pub const Feature = feature_mod.Feature;
pub const PropertyValue = property_value_mod.PropertyValue;

/// Layer view with lazy feature iteration and key/value table access helpers.
pub const Layer = struct {
    data: ?[]const u8 = null,
    version_value: u32 = 1,
    extent_value: u32 = 4096,
    num_features_value: usize = 0,
    name_data: ?[]const u8 = null,
    feature_reader: pbf.Reader = .{ .data = &.{} },
    key_table_size_value: usize = 0,
    value_table_size_value: usize = 0,

    /// Parse and validate a layer message.
    pub fn init(data: []const u8) !Layer {
        var result = Layer{
            .data = data,
            .feature_reader = pbf.Reader.init(data),
        };

        var reader = pbf.Reader.init(data);
        while (try reader.next()) |field| {
            switch (field.tag) {
                mvt.Layer.version => {
                    if (field.wire_type != .varint) return error.InvalidLayerField;
                    result.version_value = try pbf.decodeUint32(field.data);
                },
                mvt.Layer.name => {
                    if (field.wire_type != .length_delimited) return error.InvalidLayerField;
                    result.name_data = field.data;
                },
                mvt.Layer.features => {
                    if (field.wire_type != .length_delimited) return error.InvalidLayerField;
                    result.num_features_value += 1;
                },
                mvt.Layer.keys => {
                    if (field.wire_type != .length_delimited) return error.InvalidLayerField;
                    result.key_table_size_value += 1;
                },
                mvt.Layer.values => {
                    if (field.wire_type != .length_delimited) return error.InvalidLayerField;
                    result.value_table_size_value += 1;
                },
                mvt.Layer.extent => {
                    if (field.wire_type != .varint) return error.InvalidLayerField;
                    result.extent_value = try pbf.decodeUint32(field.data);
                },
                // Keep strict vtzero behavior for layer-level unknown fields.
                else => return error.UnknownLayerField,
            }
        }

        // vtzero supports vector tile layer versions 1 and 2.
        if (result.version_value < 1 or result.version_value > 2) return error.UnknownVectorTileVersion;
        // Spec 4.1 requires a layer name.
        if (result.name_data == null) return error.MissingLayerName;
        return result;
    }

    pub fn valid(self: Layer) bool {
        return self.data != null;
    }

    pub fn name(self: Layer) []const u8 {
        return self.name_data orelse "";
    }

    pub fn version(self: Layer) u32 {
        return self.version_value;
    }

    pub fn extent(self: Layer) u32 {
        return self.extent_value;
    }

    pub fn empty(self: Layer) bool {
        return self.num_features_value == 0;
    }

    pub fn numFeatures(self: Layer) usize {
        return self.num_features_value;
    }

    pub fn keyTableSize(self: Layer) usize {
        return self.key_table_size_value;
    }

    pub fn valueTableSize(self: Layer) usize {
        return self.value_table_size_value;
    }

    /// Materialize the key table into caller-owned memory.
    pub fn collectKeyTable(self: Layer, allocator: std.mem.Allocator) ![][]const u8 {
        var keys = try allocator.alloc([]const u8, self.key_table_size_value);
        errdefer allocator.free(keys);

        var reader = pbf.Reader.init(self.data orelse return error.InvalidLayer);
        var index: usize = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.keys and field.wire_type == .length_delimited) {
                keys[index] = field.data;
                index += 1;
            }
        }
        return keys;
    }

    /// Materialize the value table into caller-owned memory.
    pub fn collectValueTable(self: Layer, allocator: std.mem.Allocator) ![]PropertyValue {
        var values = try allocator.alloc(PropertyValue, self.value_table_size_value);
        errdefer allocator.free(values);

        var reader = pbf.Reader.init(self.data orelse return error.InvalidLayer);
        var index: usize = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.values and field.wire_type == .length_delimited) {
                values[index] = PropertyValue.init(field.data);
                index += 1;
            }
        }
        return values;
    }

    /// Lookup one key by table index.
    pub fn key(self: Layer, index: u32) ![]const u8 {
        var reader = pbf.Reader.init(self.data orelse return error.InvalidLayer);
        var current: u32 = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.keys and field.wire_type == .length_delimited) {
                if (current == index) return field.data;
                current += 1;
            }
        }
        return error.IndexOutOfRange;
    }

    /// Lookup one value by table index.
    pub fn value(self: Layer, index: u32) !PropertyValue {
        var reader = pbf.Reader.init(self.data orelse return error.InvalidLayer);
        var current: u32 = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.values and field.wire_type == .length_delimited) {
                if (current == index) return PropertyValue.init(field.data);
                current += 1;
            }
        }
        return error.IndexOutOfRange;
    }

    /// Iterate features in source order.
    pub fn nextFeature(self: *Layer) !?Feature {
        const data = self.data orelse return error.InvalidLayer;
        while (try self.feature_reader.next()) |field| {
            if (field.tag == mvt.Layer.features and field.wire_type == .length_delimited) {
                return try Feature.init(data, self.key_table_size_value, self.value_table_size_value, field.data);
            }
        }
        return null;
    }

    pub fn resetFeature(self: *Layer) void {
        self.feature_reader = pbf.Reader.init(self.data orelse &.{});
    }

    /// Find a feature by id (linear scan).
    pub fn getFeatureById(self: *const Layer, id: u64) !?Feature {
        const data = self.data orelse return error.InvalidLayer;
        var reader = pbf.Reader.init(data);
        while (try reader.next()) |field| {
            if (field.tag != mvt.Layer.features or field.wire_type != .length_delimited) continue;

            var feature_reader = pbf.Reader.init(field.data);
            if (try feature_reader.next()) |feature_field| {
                if (feature_field.tag == mvt.Feature.id and feature_field.wire_type == .varint and try pbf.decodeUint64(feature_field.data) == id) {
                    return try Feature.init(data, self.key_table_size_value, self.value_table_size_value, field.data);
                }
            }
        }
        return null;
    }
};
