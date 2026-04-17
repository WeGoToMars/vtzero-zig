const std = @import("std");
const vtzero = @import("vtzero");
const pbf = vtzero.detail.pbf;
const mvt = vtzero.mvt;
const testlib = @import("../include/test.zig");

/// Single-byte protobuf field key `(tag << 3) | wire` when the value fits in one byte.
fn protobufFieldKeyByte(tag: u32, wire: pbf.WireType) u8 {
    const k = pbf.fieldKey(tag, wire);
    std.debug.assert(k <= 127);
    return @truncate(k);
}

/// Protobuf field number not defined on MVT `Feature`, used for forward-compat skip tests.
const feature_unknown_field_tag: u32 = 5;

/// Minimal layer blob: version, name, one key, one value (passes `Layer.init`).
const test_layer_one_key_one_value = [_]u8{
    protobufFieldKeyByte(mvt.Layer.version, .varint),
    0x01, // version = 1
    protobufFieldKeyByte(mvt.Layer.name, .length_delimited),
    0x01,
    'a', // name
    protobufFieldKeyByte(mvt.Layer.keys, .length_delimited),
    0x01,
    'k', // keys[0]
    protobufFieldKeyByte(mvt.Layer.values, .length_delimited),
    0x02,
    protobufFieldKeyByte(mvt.Value.string_value, .length_delimited),
    0x00, // values[0]: Value { string_value = "" }
};

test "default constructed feature" {
    var feature = vtzero.Feature{};
    try std.testing.expect(!feature.valid());
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expect(!feature.hasId());
    try std.testing.expectEqual(vtzero.GeomType.UNKNOWN, feature.geometryType());
    try std.testing.expect(feature.empty());
    try std.testing.expectEqual(@as(usize, 0), feature.numProperties());
    try std.testing.expectEqual(@as(usize, 0), feature.geometry().data.len);
}

test "read a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    const feature = (try layer.nextFeature()).?;

    try std.testing.expect(feature.valid());
    try std.testing.expect(feature.hasId());
    try std.testing.expectEqual(@as(u64, 0), feature.id());
    try std.testing.expectEqual(vtzero.GeomType.LINESTRING, feature.geometryType());
    try std.testing.expectEqual(@as(usize, 4), feature.numProperties());
}

test "iterate over all properties of a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    var feature = (try layer.nextFeature()).?;

    var count: usize = 0;
    var saw_type = false;
    while (try feature.nextProperty()) |p| : (count += 1) {
        if (std.mem.eql(u8, p.key(), "type")) {
            saw_type = true;
            try std.testing.expectEqualStrings("primary", try p.value().stringValue());
        }
    }

    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expect(saw_type);
}

test "iterate over some properties of a feature" {
    const data = try testlib.loadTestTile(testlib.testIo(), std.testing.allocator);
    defer std.testing.allocator.free(data);
    const tile = vtzero.VectorTile.init(data);
    var layer = (try tile.getLayerByName("bridge")).?;
    var feature = (try layer.nextFeature()).?;

    // external iterator
    {
        feature.resetProperty();
        var count: usize = 0;
        while (try feature.nextProperty()) |p| {
            count += 1;
            if (std.mem.eql(u8, p.key(), "oneway")) break;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    // internal iterator (ported from vtzero::feature::for_each_property)
    {
        feature.resetProperty();
        var count: usize = 0;
        while (try feature.nextProperty()) |p| {
            count += 1;
            if (std.mem.eql(u8, p.key(), "oneway")) break;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }
}

/// Minimal valid feature bytes: `geometry` as empty length-delimited payload.
const min_feature_geom = [_]u8{
    protobufFieldKeyByte(mvt.Feature.geometry, .length_delimited),
    0x00, // length = 0
};

test "[pzero] skip() skips the right amount of bytes" {
    var alloc = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var skip_dir = try std.Io.Dir.cwd().openDir(io, "vtzero/third_party/protozero/test/t", .{ .iterate = true });
    defer skip_dir.close(io);

    var walker = try skip_dir.walk(alloc);
    defer walker.deinit();

    var count: usize = 0;
    while (try walker.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.basename, "data")) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".pbf")) continue;
        if (std.mem.indexOf(u8, entry.path, "tags/") != null) continue;

        const raw_data = try skip_dir.readFileAlloc(io, entry.path, alloc, .limited(1024 * 1024));
        defer alloc.free(raw_data);

        // Filter out everything that contains more than one field
        var reader = pbf.Reader.init(raw_data);
        _ = (try reader.next()) orelse continue;
        if ((try reader.next()) != null) continue;

        var buf = try alloc.alloc(u8, raw_data.len + min_feature_geom.len);
        defer alloc.free(buf);

        @memcpy(buf[0..raw_data.len], raw_data);
        @memcpy(buf[raw_data.len..], &min_feature_geom);

        // Protozero tests use tag 1. We change it to feature_unknown_field_tag (5)
        // so it invokes skipFieldValue() instead of parsing as a valid varint id.
        buf[0] = (buf[0] & 7) | @as(u8, @intCast(feature_unknown_field_tag << 3));

        const f = try vtzero.Feature.init(&.{}, 0, 0, buf);
        try std.testing.expect(f.valid());
        count += 1;
    }
    try std.testing.expect(count > 0);
}

test "[pzero] exceptional cases: check that next() throws on unknown field type" {
    var buf = [_]u8{0} ** 32;
    var w = pbf.SliceWriter{ .buf = &buf, .pos = 0 };
    // Start with a valid fixed32 field (wire type 5)
    try pbf.appendVarint(&w, pbf.fieldKey(feature_unknown_field_tag, .fixed32));
    try w.appendSlice(&[_]u8{ 1, 2, 3, 4 });
    try w.appendSlice(&min_feature_geom);

    var data = buf[0..w.pos];
    // Hack the wire type to an unsupported value (5 + 1 = 6)
    data[0] += 1;

    try std.testing.expectError(error.UnsupportedWireType, vtzero.Feature.init(&.{}, 0, 0, data));
}

test "[pzero] exceptional cases: check that skip() throws on short buffer" {
    var buf = [_]u8{0} ** 32;
    var w = pbf.SliceWriter{ .buf = &buf, .pos = 0 };
    try pbf.appendVarint(&w, pbf.fieldKey(feature_unknown_field_tag, .fixed64));
    try w.appendSlice(&[_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 });
    try w.appendSlice(&min_feature_geom);

    // Truncate the fixed64 payload by taking fewer bytes than expected
    // The key is 1 byte, so 1 + 7 = 8 bytes total, omitting the 8th payload byte
    const truncated_data = buf[0..8];
    try std.testing.expectError(error.UnexpectedEof, vtzero.Feature.init(&.{}, 0, 0, truncated_data));
}

test "[pzero] exceptional cases: check that varint decoder throws on overflow" {
    var buf = [_]u8{0} ** 32;
    var w = pbf.SliceWriter{ .buf = &buf, .pos = 0 };
    try pbf.appendVarint(&w, pbf.fieldKey(feature_unknown_field_tag, .varint));
    // 10 varint continuation bytes without a terminator
    try w.appendSlice(&[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 });
    try w.appendSlice(&min_feature_geom);

    try std.testing.expectError(error.VarintOverflow, vtzero.Feature.init(&.{}, 0, 0, buf[0..w.pos]));
}

test "[zig] nextPropertyIndexes rejects key index that does not fit in u32" {
    var tags_payload: [16]u8 = undefined;
    var pw = pbf.SliceWriter{ .buf = &tags_payload, .pos = 0 };
    try pbf.appendVarint(&pw, 0x1_0000_0000);
    try pbf.appendVarint(&pw, 0);

    var feat: [32]u8 = undefined;
    var fw = pbf.SliceWriter{ .buf = &feat, .pos = 0 };
    try pbf.appendVarint(&fw, pbf.fieldKey(mvt.Feature.tags, .length_delimited));
    try pbf.appendVarint(&fw, pw.pos);
    try fw.appendSlice(tags_payload[0..pw.pos]);
    try fw.appendSlice(&min_feature_geom);

    var feature = try vtzero.Feature.init(&test_layer_one_key_one_value, 1, 1, feat[0..fw.pos]);
    try std.testing.expectError(error.IndexOutOfRange, feature.nextPropertyIndexes());
}

test "[zig] nextPropertyIndexes rejects value index that does not fit in u32" {
    var tags_payload: [16]u8 = undefined;
    var pw = pbf.SliceWriter{ .buf = &tags_payload, .pos = 0 };
    try pbf.appendVarint(&pw, 0);
    try pbf.appendVarint(&pw, 0x1_0000_0000);

    var feat: [32]u8 = undefined;
    var fw = pbf.SliceWriter{ .buf = &feat, .pos = 0 };
    try pbf.appendVarint(&fw, pbf.fieldKey(mvt.Feature.tags, .length_delimited));
    try pbf.appendVarint(&fw, pw.pos);
    try fw.appendSlice(tags_payload[0..pw.pos]);
    try fw.appendSlice(&min_feature_geom);

    var feature = try vtzero.Feature.init(&test_layer_one_key_one_value, 1, 1, feat[0..fw.pos]);
    try std.testing.expectError(error.IndexOutOfRange, feature.nextPropertyIndexes());
}

const inflated_key_table_size: usize = 10;
const key_index_past_single_key: u8 = 5;
const value_index_past_single_value: u8 = 5;

test "[zig] nextProperty keyFromLayerData IndexOutOfRange when key index exceeds keys present" {
    const packed_tags_len: u8 = 2;
    const feat = [_]u8{
        protobufFieldKeyByte(mvt.Feature.tags, .length_delimited),
        packed_tags_len,
        key_index_past_single_key,
        0x00, // value index 0
    } ++ min_feature_geom;
    var feature = try vtzero.Feature.init(&test_layer_one_key_one_value, inflated_key_table_size, 1, &feat);
    try std.testing.expectError(error.IndexOutOfRange, feature.nextProperty());
}

test "[zig] nextProperty valueFromLayerData IndexOutOfRange when value index exceeds values present" {
    const packed_tags_len: u8 = 2;
    const feat = [_]u8{
        protobufFieldKeyByte(mvt.Feature.tags, .length_delimited),
        packed_tags_len,
        0x00, // key index 0
        value_index_past_single_value,
    } ++ min_feature_geom;
    var feature = try vtzero.Feature.init(&test_layer_one_key_one_value, 1, inflated_key_table_size, &feat);
    try std.testing.expectError(error.IndexOutOfRange, feature.nextProperty());
}
