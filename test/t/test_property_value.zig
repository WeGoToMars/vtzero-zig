const std = @import("std");
const vtzero = @import("vtzero");

fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn lessThan(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "default constructed property_value" {
    const pv = vtzero.PropertyValue{};
    try std.testing.expect(!pv.valid());
}

test "empty property_value" {
    const empty: []const u8 = &.{};
    const pv = vtzero.PropertyValue.init(empty);
    try std.testing.expect(pv.valid());
    try std.testing.expectError(error.MissingTagValue, pv.type());
}

fn makeEncodedString(value: []const u8) !vtzero.EncodedPropertyValue {
    return try vtzero.EncodedPropertyValue.fromString(std.testing.allocator, value);
}

test "string value" {
    var epv = try makeEncodedString("foo");
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectEqualStrings("foo", try pv.stringValue());
}

test "float value" {
    var epv = try vtzero.EncodedPropertyValue.fromFloat(std.testing.allocator, 1.2);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), try pv.floatValue(), 0.0001);
}

test "double value" {
    var epv = try vtzero.EncodedPropertyValue.fromDouble(std.testing.allocator, 3.4);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectApproxEqAbs(@as(f64, 3.4), try pv.doubleValue(), 0.0001);
}

test "int value" {
    var epv = try vtzero.EncodedPropertyValue.fromInt(std.testing.allocator, 42);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectEqual(@as(i64, 42), try pv.intValue());
}

test "uint value" {
    var epv = try vtzero.EncodedPropertyValue.fromUInt(std.testing.allocator, 99);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectEqual(@as(u64, 99), try pv.uintValue());
}

test "sint value" {
    var epv = try vtzero.EncodedPropertyValue.fromSInt(std.testing.allocator, 42);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expectEqual(@as(i64, 42), try pv.sintValue());
}

test "bool value" {
    var epv = try vtzero.EncodedPropertyValue.fromBool(std.testing.allocator, true);
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    try std.testing.expect(try pv.boolValue());
}

test "property and property_value equality comparisons" {
    const allocator = std.testing.allocator;
    var t = try vtzero.EncodedPropertyValue.fromBool(allocator, true);
    defer t.deinit();
    var f = try vtzero.EncodedPropertyValue.fromBool(allocator, false);
    defer f.deinit();
    var v1 = try vtzero.EncodedPropertyValue.fromInt(allocator, 1);
    defer v1.deinit();
    var vs = try vtzero.EncodedPropertyValue.fromString(allocator, "foo");
    defer vs.deinit();

    try std.testing.expect(std.mem.eql(u8, t.data(), t.data()));
    try std.testing.expect(!std.mem.eql(u8, t.data(), f.data()));
    try std.testing.expect(!std.mem.eql(u8, t.data(), v1.data()));
    try std.testing.expect(!std.mem.eql(u8, t.data(), vs.data()));

    const pv_t1 = vtzero.PropertyValue.init(t.data());
    const pv_t2 = vtzero.PropertyValue.init(t.data());
    const pv_f = vtzero.PropertyValue.init(f.data());
    const pv_v1 = vtzero.PropertyValue.init(v1.data());
    const pv_vs = vtzero.PropertyValue.init(vs.data());
    try std.testing.expect(std.mem.eql(u8, pv_t1.data.?, pv_t2.data.?));
    try std.testing.expect(!std.mem.eql(u8, pv_t1.data.?, pv_f.data.?));
    try std.testing.expect(!std.mem.eql(u8, pv_t1.data.?, pv_v1.data.?));
    try std.testing.expect(!std.mem.eql(u8, pv_t1.data.?, pv_vs.data.?));
}

test "property and property_value ordering" {
    const allocator = std.testing.allocator;
    var t = try vtzero.EncodedPropertyValue.fromBool(allocator, true);
    defer t.deinit();
    var f = try vtzero.EncodedPropertyValue.fromBool(allocator, false);
    defer f.deinit();
    try std.testing.expect(!lessThan(t.data(), f.data()));
    try std.testing.expect(lessThan(f.data(), t.data()));

    var v1 = try vtzero.EncodedPropertyValue.fromInt(allocator, 22);
    defer v1.deinit();
    var v2 = try vtzero.EncodedPropertyValue.fromInt(allocator, 17);
    defer v2.deinit();
    try std.testing.expect(!lessThan(v1.data(), v2.data()));
    try std.testing.expect(lessThan(v2.data(), v1.data()));

    var vsf = try vtzero.EncodedPropertyValue.fromString(allocator, "foo");
    defer vsf.deinit();
    var vsb = try vtzero.EncodedPropertyValue.fromString(allocator, "bar");
    defer vsb.deinit();
    var vsx = try vtzero.EncodedPropertyValue.fromString(allocator, "foobar");
    defer vsx.deinit();
    try std.testing.expect(!lessThan(vsf.data(), vsb.data()));
    try std.testing.expect(lessThan(vsb.data(), vsf.data()));
    try std.testing.expect(lessThan(vsf.data(), vsx.data()));
}

test "default constructed property" {
    const p = vtzero.Property{};
    try std.testing.expect(!p.valid());
    try std.testing.expectEqual(@as(usize, 0), p.key().len);
    try std.testing.expect(!p.value().valid());
}

test "valid property" {
    const allocator = std.testing.allocator;
    var epv = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv.deinit();
    const pv = vtzero.PropertyValue.init(epv.data());
    const p = vtzero.Property{ .key_data = "key", .value_data = pv };
    try std.testing.expectEqualStrings("key", p.key());
    try std.testing.expectEqualStrings("value", try p.value().stringValue());
}

test "create encoded property values from different string types" {
    const allocator = std.testing.allocator;
    var epv1 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv1.deinit();
    var epv2 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv2.deinit();
    var epv3 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv3.deinit();
    var epv4 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv4.deinit();
    var epv5 = try vtzero.EncodedPropertyValue.fromString(allocator, "valuexxxxxxxxx"[0..5]);
    defer epv5.deinit();

    try std.testing.expect(std.mem.eql(u8, epv1.data(), epv2.data()));
    try std.testing.expect(std.mem.eql(u8, epv1.data(), epv3.data()));
    try std.testing.expect(std.mem.eql(u8, epv1.data(), epv4.data()));
    try std.testing.expect(std.mem.eql(u8, epv1.data(), epv5.data()));
}

test "create encoded property values from different floating point types" {
    const allocator = std.testing.allocator;
    var f1 = try vtzero.EncodedPropertyValue.fromFloat(allocator, 3.2);
    defer f1.deinit();
    var f2 = try vtzero.EncodedPropertyValue.fromFloat(allocator, 3.2);
    defer f2.deinit();
    var d1 = try vtzero.EncodedPropertyValue.fromDouble(allocator, 3.2);
    defer d1.deinit();
    var d2 = try vtzero.EncodedPropertyValue.fromDouble(allocator, 3.2);
    defer d2.deinit();

    try std.testing.expect(std.mem.eql(u8, f1.data(), f2.data()));
    try std.testing.expect(std.mem.eql(u8, d1.data(), d2.data()));

    const pvf = vtzero.PropertyValue.init(f1.data());
    const pvd = vtzero.PropertyValue.init(d1.data());
    try std.testing.expectApproxEqAbs(@as(f32, 3.2), try pvf.floatValue(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.2), try pvd.doubleValue(), 0.0001);
}

test "create encoded property values from different integer types" {
    const allocator = std.testing.allocator;
    var int1 = try vtzero.EncodedPropertyValue.fromInt(allocator, 7);
    defer int1.deinit();
    var int2 = try vtzero.EncodedPropertyValue.fromInt(allocator, @as(i64, 7));
    defer int2.deinit();
    var int3 = try vtzero.EncodedPropertyValue.fromInt(allocator, @as(i32, 7));
    defer int3.deinit();
    var int4 = try vtzero.EncodedPropertyValue.fromInt(allocator, @as(i16, 7));
    defer int4.deinit();

    var uint1 = try vtzero.EncodedPropertyValue.fromUInt(allocator, 7);
    defer uint1.deinit();
    var uint2 = try vtzero.EncodedPropertyValue.fromUInt(allocator, @as(u64, 7));
    defer uint2.deinit();
    var uint3 = try vtzero.EncodedPropertyValue.fromUInt(allocator, @as(u32, 7));
    defer uint3.deinit();
    var uint4 = try vtzero.EncodedPropertyValue.fromUInt(allocator, @as(u16, 7));
    defer uint4.deinit();

    var s1 = try vtzero.EncodedPropertyValue.fromSInt(allocator, 7);
    defer s1.deinit();

    try std.testing.expect(std.mem.eql(u8, int1.data(), int2.data()));
    try std.testing.expect(std.mem.eql(u8, int1.data(), int3.data()));
    try std.testing.expect(std.mem.eql(u8, int1.data(), int4.data()));
    try std.testing.expect(std.mem.eql(u8, uint1.data(), uint2.data()));
    try std.testing.expect(std.mem.eql(u8, uint1.data(), uint3.data()));
    try std.testing.expect(std.mem.eql(u8, uint1.data(), uint4.data()));

    try std.testing.expect(!std.mem.eql(u8, int1.data(), uint1.data()));
    try std.testing.expect(!std.mem.eql(u8, int1.data(), s1.data()));
    try std.testing.expect(!std.mem.eql(u8, uint1.data(), s1.data()));

    try std.testing.expectEqual(hashBytes(int1.data()), hashBytes(int2.data()));
    try std.testing.expectEqual(hashBytes(uint1.data()), hashBytes(uint2.data()));

    const pvi = vtzero.PropertyValue.init(int1.data());
    const pvu = vtzero.PropertyValue.init(uint1.data());
    const pvs = vtzero.PropertyValue.init(s1.data());
    try std.testing.expectEqual(try pvi.intValue(), @as(i64, @intCast(try pvu.uintValue())));
    try std.testing.expectEqual(try pvi.intValue(), try pvs.sintValue());
}

test "create encoded property values from different bool types" {
    const allocator = std.testing.allocator;
    var b1 = try vtzero.EncodedPropertyValue.fromBool(allocator, true);
    defer b1.deinit();
    var b2 = try vtzero.EncodedPropertyValue.fromBool(allocator, true);
    defer b2.deinit();
    try std.testing.expect(std.mem.eql(u8, b1.data(), b2.data()));
    try std.testing.expectEqual(hashBytes(b1.data()), hashBytes(b2.data()));
}

test "property equality comparison operator" {
    const allocator = std.testing.allocator;
    var epv1 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv1.deinit();
    var epv2 = try vtzero.EncodedPropertyValue.fromString(allocator, "another value");
    defer epv2.deinit();
    const pv1 = vtzero.PropertyValue.init(epv1.data());
    const pv2 = vtzero.PropertyValue.init(epv2.data());

    const p1 = vtzero.Property{ .key_data = "key", .value_data = pv1 };
    const p2 = vtzero.Property{ .key_data = "key", .value_data = pv1 };
    const p3 = vtzero.Property{ .key_data = "key", .value_data = pv2 };

    try std.testing.expect(std.mem.eql(u8, p1.key(), p2.key()) and std.mem.eql(u8, p1.value().data.?, p2.value().data.?));
    try std.testing.expect(!std.mem.eql(u8, p1.value().data.?, p3.value().data.?));
}

test "property inequality comparison operator" {
    const allocator = std.testing.allocator;
    var epv1 = try vtzero.EncodedPropertyValue.fromString(allocator, "value");
    defer epv1.deinit();
    var epv2 = try vtzero.EncodedPropertyValue.fromString(allocator, "another value");
    defer epv2.deinit();
    const pv1 = vtzero.PropertyValue.init(epv1.data());
    const pv2 = vtzero.PropertyValue.init(epv2.data());

    const p1 = vtzero.Property{ .key_data = "key", .value_data = pv1 };
    const p2 = vtzero.Property{ .key_data = "key", .value_data = pv1 };
    const p3 = vtzero.Property{ .key_data = "key", .value_data = pv2 };
    const p4 = vtzero.Property{ .key_data = "another_key", .value_data = pv2 };

    const eq12 = std.mem.eql(u8, p1.key(), p2.key()) and std.mem.eql(u8, p1.value().data.?, p2.value().data.?);
    try std.testing.expect(eq12);
    try std.testing.expect(!std.mem.eql(u8, p1.value().data.?, p3.value().data.?));
    try std.testing.expect(!std.mem.eql(u8, p3.key(), p4.key()));
}

