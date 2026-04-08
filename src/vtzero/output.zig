const std = @import("std");
const types = @import("types.zig");

pub fn geomTypeName(geom_type: types.GeomType) []const u8 {
    return types.geomTypeName(geom_type);
}

pub fn propertyValueTypeName(value_type: types.PropertyValueType) []const u8 {
    return types.propertyValueTypeName(value_type);
}

pub fn indexValueToString(buf: []u8, value: types.IndexValue) ![]const u8 {
    if (!value.valid()) return "invalid";
    return std.fmt.bufPrint(buf, "{d}", .{value.value()});
}

pub fn indexValuePairToString(buf: []u8, value: types.IndexValuePair) ![]const u8 {
    if (!value.valid()) return "invalid";
    return std.fmt.bufPrint(buf, "[{d},{d}]", .{ value.key().value(), value.value().value() });
}

pub fn pointToString(buf: []u8, point: types.Point) ![]const u8 {
    return std.fmt.bufPrint(buf, "({d},{d})", .{ point.x, point.y });
}
