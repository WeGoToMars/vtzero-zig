const std = @import("std");
const vtzero = @import("vtzero");

test "output GeomType" {
    try std.testing.expectEqualStrings("unknown", vtzero.output.geomTypeName(.UNKNOWN));
    try std.testing.expectEqualStrings("point", vtzero.output.geomTypeName(.POINT));
    try std.testing.expectEqualStrings("linestring", vtzero.output.geomTypeName(.LINESTRING));
    try std.testing.expectEqualStrings("polygon", vtzero.output.geomTypeName(.POLYGON));
}

test "output property_value_type" {
    try std.testing.expectEqualStrings("sint", vtzero.output.propertyValueTypeName(.sint_value));
}

test "output index_value" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("invalid", try vtzero.output.indexValueToString(&buf, vtzero.IndexValue{}));
    try std.testing.expectEqualStrings("5", try vtzero.output.indexValueToString(&buf, vtzero.IndexValue.init(5)));
}

test "output index_value_pair" {
    var buf: [64]u8 = undefined;
    const inv = vtzero.IndexValue{};
    const v2 = vtzero.IndexValue.init(2);
    const v5 = vtzero.IndexValue.init(5);
    try std.testing.expectEqualStrings("invalid", try vtzero.output.indexValuePairToString(&buf, .{ .key_index = inv, .value_index = v2 }));
    try std.testing.expectEqualStrings("[2,5]", try vtzero.output.indexValuePairToString(&buf, .{ .key_index = v2, .value_index = v5 }));
}

test "output point" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("(0,0)", try vtzero.output.pointToString(&buf, .{}));
    try std.testing.expectEqualStrings("(4,7)", try vtzero.output.pointToString(&buf, .{ .x = 4, .y = 7 }));
}

