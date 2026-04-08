const std = @import("std");
const pbf = @import("detail/pbf.zig");

/// Geometry type values from the vector tile spec.
pub const GeomType = enum(u32) {
    UNKNOWN = 0,
    POINT = 1,
    LINESTRING = 2,
    POLYGON = 3,
};

/// Property value tags from the vector tile value message.
pub const PropertyValueType = enum(u32) {
    string_value = 1,
    float_value = 2,
    double_value = 3,
    int_value = 4,
    uint_value = 5,
    sint_value = 6,
    bool_value = 7,
};

pub fn geomTypeName(geom_type: GeomType) []const u8 {
    return switch (geom_type) {
        .UNKNOWN => "unknown",
        .POINT => "point",
        .LINESTRING => "linestring",
        .POLYGON => "polygon",
    };
}

pub fn propertyValueTypeName(value_type: PropertyValueType) []const u8 {
    return switch (value_type) {
        .string_value => "string",
        .float_value => "float",
        .double_value => "double",
        .int_value => "int",
        .uint_value => "uint",
        .sint_value => "sint",
        .bool_value => "bool",
    };
}

pub const StringValueType = struct {
    value: []const u8 = "",
};

pub const FloatValueType = struct {
    value: f32 = 0,
};

pub const DoubleValueType = struct {
    value: f64 = 0,
};

pub const IntValueType = struct {
    value: i64 = 0,
};

pub const UIntValueType = struct {
    value: u64 = 0,
};

pub const SIntValueType = struct {
    value: i64 = 0,
};

pub const BoolValueType = struct {
    value: bool = false,
};

/// Integer point coordinates in tile extent space.
pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
};

/// Polygon ring classification derived from signed ring area.
pub const RingType = enum {
    outer,
    inner,
    invalid,
};

/// Encoded geometry bytes paired with the declared geometry type.
pub const Geometry = struct {
    data: []const u8 = &.{},
    geom_type: GeomType = .UNKNOWN,

    pub fn @"type"(self: Geometry) GeomType {
        return self.geom_type;
    }

    pub fn iterator(self: Geometry) pbf.PackedUInt32Iterator {
        return .init(self.data);
    }
};

/// Wrapper around index values used for key/value table lookups.
pub const IndexValue = struct {
    value_data: ?u32 = null,

    pub fn init(raw_value: u32) IndexValue {
        return .{ .value_data = raw_value };
    }

    pub fn valid(self: IndexValue) bool {
        return self.value_data != null;
    }

    pub fn value(self: IndexValue) u32 {
        return self.value_data orelse std.math.maxInt(u32);
    }
};

/// Pair of key and value indexes for one feature property entry.
pub const IndexValuePair = struct {
    key_index: IndexValue = .{},
    value_index: IndexValue = .{},

    pub fn valid(self: IndexValuePair) bool {
        return self.key_index.valid() and self.value_index.valid();
    }

    pub fn key(self: IndexValuePair) IndexValue {
        return self.key_index;
    }

    pub fn value(self: IndexValuePair) IndexValue {
        return self.value_index;
    }
};
