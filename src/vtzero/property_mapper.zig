const std = @import("std");
const types = @import("types.zig");
const layer_mod = @import("layer.zig");
const builder_mod = @import("builder.zig");
const property_value_mod = @import("property_value.zig");

pub const IndexValue = types.IndexValue;
pub const IndexValuePair = types.IndexValuePair;
pub const Layer = layer_mod.Layer;
pub const LayerBuilder = builder_mod.LayerBuilder;

/// Maps key/value indexes from a source layer to a destination layer.
pub const PropertyMapper = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    key_map: []IndexValue,
    value_map: []IndexValue,
    /// Views into the source layer's key table (same backing as `layer.collectKeyTable`).
    keys_table: [][]const u8,
    /// Views into the source layer's value table.
    values_table: []property_value_mod.PropertyValue,

    pub fn init(allocator: std.mem.Allocator, layer: Layer, layer_builder: *LayerBuilder) !PropertyMapper {
        const key_map = try allocator.alloc(IndexValue, layer.keyTableSize());
        errdefer allocator.free(key_map);
        const value_map = try allocator.alloc(IndexValue, layer.valueTableSize());
        errdefer allocator.free(value_map);

        @memset(key_map, .{});
        @memset(value_map, .{});

        const keys_table = try layer.collectKeyTable(allocator);
        errdefer allocator.free(keys_table);
        const values_table = try layer.collectValueTable(allocator);
        errdefer allocator.free(values_table);

        return .{
            .allocator = allocator,
            .layer_builder = layer_builder,
            .key_map = key_map,
            .value_map = value_map,
            .keys_table = keys_table,
            .values_table = values_table,
        };
    }

    pub fn deinit(self: *PropertyMapper) void {
        self.allocator.free(self.key_map);
        self.allocator.free(self.value_map);
        self.allocator.free(self.keys_table);
        self.allocator.free(self.values_table);
        self.* = undefined;
    }

    pub fn mapKey(self: *PropertyMapper, index: IndexValue) !IndexValue {
        const idx = index.value();
        var mapped = &self.key_map[idx];
        if (!mapped.valid()) {
            mapped.* = try self.layer_builder.addKeyWithoutDupCheck(self.keys_table[idx]);
        }
        return mapped.*;
    }

    pub fn mapValue(self: *PropertyMapper, index: IndexValue) !IndexValue {
        const idx = index.value();
        var mapped = &self.value_map[idx];
        if (!mapped.valid()) {
            mapped.* = try self.layer_builder.addValueWithoutDupCheck(self.values_table[idx]);
        }
        return mapped.*;
    }

    pub fn map(self: *PropertyMapper, idxs: IndexValuePair) !IndexValuePair {
        return .{
            .key_index = try self.mapKey(idxs.key()),
            .value_index = try self.mapValue(idxs.value()),
        };
    }
};
