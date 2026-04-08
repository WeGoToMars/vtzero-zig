const std = @import("std");
const vtzero = @import("vtzero");

test "construct format_exception with const char*" {
    const e = vtzero.exception.FormatException.init("broken");
    try std.testing.expectEqualStrings("broken", e.what());
}

test "construct format_exception with const std::string" {
    var e = try vtzero.exception.FormatException.initDup(std.testing.allocator, "broken");
    defer e.deinit();
    try std.testing.expectEqualStrings("broken", e.what());
}

test "construct geometry_exception with const char*" {
    const e = vtzero.exception.GeometryException.init("broken");
    try std.testing.expectEqualStrings("broken", e.what());
}

test "construct geometry_exception with std::string" {
    var e = try vtzero.exception.GeometryException.initDup(std.testing.allocator, "broken");
    defer e.deinit();
    try std.testing.expectEqualStrings("broken", e.what());
}

test "construct type_exception" {
    const e = vtzero.exception.TypeException{};
    try std.testing.expectEqualStrings("wrong property value type", e.what());
}

test "construct version_exception" {
    var e = try vtzero.exception.VersionException.init(std.testing.allocator, 42);
    defer e.deinit();
    try std.testing.expectEqualStrings("unknown vector tile version: 42", e.what());
}

test "construct out_of_range_exception" {
    var e = try vtzero.exception.OutOfRangeException.init(std.testing.allocator, 99);
    defer e.deinit();
    try std.testing.expectEqualStrings("index out of range: 99", e.what());
}

