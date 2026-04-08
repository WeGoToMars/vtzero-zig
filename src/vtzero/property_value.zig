const pbf = @import("detail/pbf.zig");
const types = @import("types.zig");
const mvt = @import("mvt_schema.zig");

pub const PropertyValueType = types.PropertyValueType;

/// View over a serialized `Value` message in the layer value table.
pub const PropertyValue = struct {
    data: ?[]const u8 = null,

    pub fn init(data: []const u8) PropertyValue {
        return .{ .data = data };
    }

    pub fn valid(self: PropertyValue) bool {
        return self.data != null;
    }

    /// Determine the value type from the first field in the value message.
    pub fn @"type"(self: PropertyValue) !PropertyValueType {
        const data = self.data orelse return error.InvalidPropertyValue;
        var reader = pbf.Reader.init(data);
        const field = (try reader.next()) orelse return error.MissingTagValue;
        return validPropertyType(field.tag, field.wire_type);
    }

    pub fn stringValue(self: PropertyValue) ![]const u8 {
        return self.getValue(.string_value);
    }

    pub fn floatValue(self: PropertyValue) !f32 {
        return self.getValue(.float_value);
    }

    pub fn doubleValue(self: PropertyValue) !f64 {
        return self.getValue(.double_value);
    }

    pub fn intValue(self: PropertyValue) !i64 {
        return self.getValue(.int_value);
    }

    pub fn uintValue(self: PropertyValue) !u64 {
        return self.getValue(.uint_value);
    }

    pub fn sintValue(self: PropertyValue) !i64 {
        return self.getValue(.sint_value);
    }

    pub fn boolValue(self: PropertyValue) !bool {
        return self.getValue(.bool_value);
    }

    /// Decode the last matching occurrence of `expected` from the message.
    fn getValue(self: PropertyValue, comptime expected: PropertyValueType) !switch (expected) {
        .string_value => []const u8,
        .float_value => f32,
        .double_value => f64,
        .int_value => i64,
        .uint_value => u64,
        .sint_value => i64,
        .bool_value => bool,
    } {
        const data = self.data orelse return error.InvalidPropertyValue;
        var reader = pbf.Reader.init(data);
        var found = false;
        var result: switch (expected) {
            .string_value => []const u8,
            .float_value => f32,
            .double_value => f64,
            .int_value => i64,
            .uint_value => u64,
            .sint_value => i64,
            .bool_value => bool,
        } = switch (expected) {
            .string_value => "",
            .float_value => 0,
            .double_value => 0,
            .int_value => 0,
            .uint_value => 0,
            .sint_value => 0,
            .bool_value => false,
        };

        while (try reader.next()) |field| {
            const pv_type = try validPropertyType(field.tag, field.wire_type);
            if (pv_type == expected) {
                result = switch (expected) {
                    .string_value => field.data,
                    .float_value => try pbf.decodeFloat(field.data),
                    .double_value => try pbf.decodeDouble(field.data),
                    .int_value => try pbf.decodeInt64(field.data),
                    .uint_value => try pbf.decodeUint64(field.data),
                    .sint_value => try pbf.decodeSint64(field.data),
                    .bool_value => try pbf.decodeBool(field.data),
                };
                found = true;
            }
        }

        if (!found) return error.WrongPropertyValueType;
        return result;
    }
};

/// Validate that a value field tag/wire-type pair is legal.
fn validPropertyType(tag: u32, wire_type: pbf.WireType) !PropertyValueType {
    return switch (tag) {
        mvt.Value.string_value => if (wire_type == .length_delimited) .string_value else error.IllegalPropertyValueType,
        mvt.Value.float_value => if (wire_type == .fixed32) .float_value else error.IllegalPropertyValueType,
        mvt.Value.double_value => if (wire_type == .fixed64) .double_value else error.IllegalPropertyValueType,
        mvt.Value.int_value => if (wire_type == .varint) .int_value else error.IllegalPropertyValueType,
        mvt.Value.uint_value => if (wire_type == .varint) .uint_value else error.IllegalPropertyValueType,
        mvt.Value.sint_value => if (wire_type == .varint) .sint_value else error.IllegalPropertyValueType,
        mvt.Value.bool_value => if (wire_type == .varint) .bool_value else error.IllegalPropertyValueType,
        else => error.IllegalPropertyValueType,
    };
}

