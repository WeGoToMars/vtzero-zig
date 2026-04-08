pub const types = @import("types.zig");

pub const IndexValue = types.IndexValue;
pub const IndexValuePair = types.IndexValuePair;

const std = @import("std");
const builder_mod = @import("builder.zig");
const encoded_value_mod = @import("encoded_property_value.zig");
const property_value_mod = @import("property_value.zig");

pub const LayerBuilder = builder_mod.LayerBuilder;
pub const EncodedPropertyValue = encoded_value_mod.EncodedPropertyValue;
pub const PropertyValue = property_value_mod.PropertyValue;

/// Cache for mapping property keys to key table indexes.
/// Mirrors the behavior tested in C++ `vtzero::key_index`.
pub const KeyIndex = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.StringHashMapUnmanaged(IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) KeyIndex {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *KeyIndex) void {
        var it = self.map.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: *KeyIndex, key: []const u8) !IndexValue {
        if (self.map.get(key)) |idx| return idx;
        const owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned);
        const idx = try self.layer_builder.addKey(owned);
        try self.map.put(self.allocator, owned, idx);
        return idx;
    }
};

/// Cache for mapping encoded property values to value table indexes.
/// Mirrors the behavior tested in C++ `vtzero::value_index_internal`.
pub const ValueIndexInternal = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.StringHashMapUnmanaged(IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexInternal {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexInternal) void {
        var it = self.map.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn getEncoded(self: *ValueIndexInternal, encoded: []const u8) !IndexValue {
        if (self.map.get(encoded)) |idx| return idx;
        const owned = try self.allocator.dupe(u8, encoded);
        errdefer self.allocator.free(owned);
        const pv = PropertyValue.init(owned);
        const idx = try self.layer_builder.addValue(pv);
        // Store our owned copy as the key; the index value is stable.
        try self.map.put(self.allocator, owned, idx);
        return idx;
    }

    pub fn get(self: *ValueIndexInternal, value: EncodedPropertyValue) !IndexValue {
        return self.getEncoded(value.data());
    }

    pub fn getPropertyValue(self: *ValueIndexInternal, value: PropertyValue) !IndexValue {
        const data = value.data orelse return error.InvalidPropertyValue;
        return self.getEncoded(data);
    }
};

pub const ValueIndexString = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.StringHashMapUnmanaged(IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexString {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexString) void {
        var it = self.map.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: *ValueIndexString, value: []const u8) !IndexValue {
        if (self.map.get(value)) |idx| return idx;
        const owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned);
        var epv = try EncodedPropertyValue.fromString(self.allocator, owned);
        defer epv.deinit();
        const idx = try self.layer_builder.addEncodedValue(epv);
        try self.map.put(self.allocator, owned, idx);
        return idx;
    }
};

pub const ValueIndexInt = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.AutoHashMapUnmanaged(i64, IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexInt {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexInt) void {
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: *ValueIndexInt, value: i64) !IndexValue {
        if (self.map.get(value)) |idx| return idx;
        var epv = try EncodedPropertyValue.fromInt(self.allocator, value);
        defer epv.deinit();
        const idx = try self.layer_builder.addEncodedValue(epv);
        try self.map.put(self.allocator, value, idx);
        return idx;
    }
};

pub const ValueIndexSInt = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.AutoHashMapUnmanaged(i64, IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexSInt {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexSInt) void {
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: *ValueIndexSInt, value: i64) !IndexValue {
        if (self.map.get(value)) |idx| return idx;
        var epv = try EncodedPropertyValue.fromSInt(self.allocator, value);
        defer epv.deinit();
        const idx = try self.layer_builder.addEncodedValue(epv);
        try self.map.put(self.allocator, value, idx);
        return idx;
    }
};

pub const ValueIndexBool = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    idx_false: ?IndexValue = null,
    idx_true: ?IndexValue = null,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexBool {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexBool) void {
        self.* = undefined;
    }

    pub fn get(self: *ValueIndexBool, value: bool) !IndexValue {
        if (value) {
            if (self.idx_true) |idx| return idx;
            var epv = try EncodedPropertyValue.fromBool(self.allocator, true);
            defer epv.deinit();
            const idx = try self.layer_builder.addEncodedValue(epv);
            self.idx_true = idx;
            return idx;
        } else {
            if (self.idx_false) |idx| return idx;
            var epv = try EncodedPropertyValue.fromBool(self.allocator, false);
            defer epv.deinit();
            const idx = try self.layer_builder.addEncodedValue(epv);
            self.idx_false = idx;
            return idx;
        }
    }
};

pub const ValueIndexSmallUInt = struct {
    allocator: std.mem.Allocator,
    layer_builder: *LayerBuilder,
    map: std.AutoHashMapUnmanaged(u32, IndexValue) = .empty,

    pub fn init(allocator: std.mem.Allocator, layer_builder: *LayerBuilder) ValueIndexSmallUInt {
        return .{ .allocator = allocator, .layer_builder = layer_builder };
    }

    pub fn deinit(self: *ValueIndexSmallUInt) void {
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn get(self: *ValueIndexSmallUInt, value: u32) !IndexValue {
        if (self.map.get(value)) |idx| return idx;
        var epv = try EncodedPropertyValue.fromUInt(self.allocator, value);
        defer epv.deinit();
        const idx = try self.layer_builder.addEncodedValue(epv);
        try self.map.put(self.allocator, value, idx);
        return idx;
    }
};

