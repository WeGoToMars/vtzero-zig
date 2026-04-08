const std = @import("std");
const vtzero = @import("vtzero");

test "default constructed string_value_type" {
    const v = vtzero.StringValueType{};
    try std.testing.expectEqual(@as(usize, 0), v.value.len);
}

test "string_value_type with value" {
    const v = vtzero.StringValueType{ .value = "foo" };
    try std.testing.expectEqual(@as(u8, 'f'), v.value[0]);
    try std.testing.expectEqual(@as(usize, 3), v.value.len);
}

test "default constructed float_value_type" {
    const v = vtzero.FloatValueType{};
    try std.testing.expectEqual(@as(f32, 0.0), v.value);
}

test "float_value_type with value" {
    const v = vtzero.FloatValueType{ .value = 2.7 };
    try std.testing.expectEqual(@as(f32, 2.7), v.value);
}

test "default constructed double_value_type" {
    const v = vtzero.DoubleValueType{};
    try std.testing.expectEqual(@as(f64, 0.0), v.value);
}

test "double_value_type with value" {
    const v = vtzero.DoubleValueType{ .value = 2.7 };
    try std.testing.expectEqual(@as(f64, 2.7), v.value);
}

test "default constructed int_value_type" {
    const v = vtzero.IntValueType{};
    try std.testing.expectEqual(@as(i64, 0), v.value);
}

test "int_value_type with value" {
    const v = vtzero.IntValueType{ .value = 123 };
    try std.testing.expectEqual(@as(i64, 123), v.value);
}

test "default constructed uint_value_type" {
    const v = vtzero.UIntValueType{};
    try std.testing.expectEqual(@as(u64, 0), v.value);
}

test "uint_value_type with value" {
    const v = vtzero.UIntValueType{ .value = 123 };
    try std.testing.expectEqual(@as(u64, 123), v.value);
}

test "default constructed sint_value_type" {
    const v = vtzero.SIntValueType{};
    try std.testing.expectEqual(@as(i64, 0), v.value);
}

test "sint_value_type with value" {
    const v = vtzero.SIntValueType{ .value = -14 };
    try std.testing.expectEqual(@as(i64, -14), v.value);
}

test "default constructed bool_value_type" {
    const v = vtzero.BoolValueType{};
    try std.testing.expect(!v.value);
}

test "bool_value_type with value" {
    const v = vtzero.BoolValueType{ .value = true };
    try std.testing.expect(v.value);
}

test "property_value_type names" {
    try std.testing.expectEqualStrings("string", vtzero.propertyValueTypeName(.string_value));
    try std.testing.expectEqualStrings("float", vtzero.propertyValueTypeName(.float_value));
    try std.testing.expectEqualStrings("double", vtzero.propertyValueTypeName(.double_value));
    try std.testing.expectEqualStrings("int", vtzero.propertyValueTypeName(.int_value));
    try std.testing.expectEqualStrings("uint", vtzero.propertyValueTypeName(.uint_value));
    try std.testing.expectEqualStrings("sint", vtzero.propertyValueTypeName(.sint_value));
    try std.testing.expectEqualStrings("bool", vtzero.propertyValueTypeName(.bool_value));
}

test "default constructed index value" {
    const v = vtzero.IndexValue{};
    try std.testing.expect(!v.valid());
}

test "valid index value" {
    const v = vtzero.IndexValue.init(32);
    try std.testing.expect(v.valid());
    try std.testing.expectEqual(@as(u32, 32), v.value());
}

test "default constructed geometry" {
    const geom = vtzero.Geometry{};
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, geom.type());
    try std.testing.expectEqual(@as(usize, 0), geom.data.len);
}

test "GeomType names" {
    try std.testing.expectEqualStrings("unknown", vtzero.geomTypeName(.UNKNOWN));
    try std.testing.expectEqualStrings("point", vtzero.geomTypeName(.POINT));
    try std.testing.expectEqualStrings("linestring", vtzero.geomTypeName(.LINESTRING));
    try std.testing.expectEqualStrings("polygon", vtzero.geomTypeName(.POLYGON));
}

