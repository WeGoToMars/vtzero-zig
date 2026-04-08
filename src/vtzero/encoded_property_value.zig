const std = @import("std");
const pbf = @import("detail/pbf.zig");
const types = @import("types.zig");

pub const PropertyValueType = types.PropertyValueType;

/// Owning encoded property value in vector tile value-message format.
pub const EncodedPropertyValue = struct {
    allocator: std.mem.Allocator,
    data_bytes: []u8,

    pub fn deinit(self: *EncodedPropertyValue) void {
        self.allocator.free(self.data_bytes);
        self.* = undefined;
    }

    pub fn data(self: EncodedPropertyValue) []const u8 {
        return self.data_bytes;
    }

    pub fn fromString(allocator: std.mem.Allocator, value: []const u8) !EncodedPropertyValue {
        return encodeLengthDelimited(allocator, 1, value);
    }

    pub fn fromFloat(allocator: std.mem.Allocator, value: f32) !EncodedPropertyValue {
        var bytes = try allocator.alloc(u8, 1 + 4);
        bytes[0] = (@as(u8, 2) << 3) | 5;
        std.mem.writeInt(u32, bytes[1..5], @bitCast(value), .little);
        return .{ .allocator = allocator, .data_bytes = bytes };
    }

    pub fn fromDouble(allocator: std.mem.Allocator, value: f64) !EncodedPropertyValue {
        var bytes = try allocator.alloc(u8, 1 + 8);
        bytes[0] = (@as(u8, 3) << 3) | 1;
        std.mem.writeInt(u64, bytes[1..9], @bitCast(value), .little);
        return .{ .allocator = allocator, .data_bytes = bytes };
    }

    pub fn fromInt(allocator: std.mem.Allocator, value: i64) !EncodedPropertyValue {
        return encodeVarintField(allocator, 4, @bitCast(value));
    }

    pub fn fromUInt(allocator: std.mem.Allocator, value: u64) !EncodedPropertyValue {
        return encodeVarintField(allocator, 5, value);
    }

    pub fn fromSInt(allocator: std.mem.Allocator, value: i64) !EncodedPropertyValue {
        const encoded = zigzag64(value);
        return encodeVarintField(allocator, 6, encoded);
    }

    pub fn fromBool(allocator: std.mem.Allocator, value: bool) !EncodedPropertyValue {
        return encodeVarintField(allocator, 7, if (value) 1 else 0);
    }
};

fn zigzag64(value: i64) u64 {
    return (@as(u64, @bitCast(value)) << 1) ^ @as(u64, @bitCast(value >> 63));
}

fn encodeVarintField(allocator: std.mem.Allocator, tag: u8, value: u64) !EncodedPropertyValue {
    var tmp: [20]u8 = undefined;
    var len: usize = 0;
    tmp[len] = (tag << 3);
    len += 1;
    len += writeVarint(tmp[len..], value);
    const out = try allocator.alloc(u8, len);
    @memcpy(out, tmp[0..len]);
    return .{ .allocator = allocator, .data_bytes = out };
}

fn encodeLengthDelimited(allocator: std.mem.Allocator, tag: u8, payload: []const u8) !EncodedPropertyValue {
    var len_buf: [10]u8 = undefined;
    const len_len = writeVarint(&len_buf, payload.len);

    const total = 1 + len_len + payload.len;
    var out = try allocator.alloc(u8, total);
    out[0] = (tag << 3) | @intFromEnum(pbf.WireType.length_delimited);
    @memcpy(out[1 .. 1 + len_len], len_buf[0..len_len]);
    @memcpy(out[1 + len_len ..], payload);
    return .{ .allocator = allocator, .data_bytes = out };
}

fn writeVarint(buf: []u8, value_in: anytype) usize {
    const T = @TypeOf(value_in);
    const value_u64: u64 = switch (@typeInfo(T)) {
        .comptime_int => @intCast(value_in),
        .int => if (@typeInfo(T).int.signedness == .signed) @bitCast(@as(i64, @intCast(value_in))) else @intCast(value_in),
        else => @intCast(value_in),
    };

    var value = value_u64;
    var i: usize = 0;
    while (true) {
        var byte: u8 = @truncate(value & 0x7f);
        value >>= 7;
        if (value != 0) byte |= 0x80;
        buf[i] = byte;
        i += 1;
        if (value == 0) break;
    }
    return i;
}
