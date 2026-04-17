//! Protobuf helpers, replacement for protozero C++ library.

const std = @import("std");

/// Subset of protobuf wire types used by vector tiles.
pub const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    fixed32 = 5,
};

/// Decoded field metadata and a view of the raw value bytes.
pub const Field = struct {
    tag: u32,
    wire_type: WireType,
    data: []const u8,
    varint_value: ?u64 = null,
};

/// Lightweight protobuf reader that iterates fields without copying.
pub const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    /// Advance past a field's value without materializing any value or slice.
    fn skipFieldValue(self: *Reader, wt_num: u3) !void {
        switch (wt_num) {
            @intFromEnum(WireType.varint) => {
                const start = self.pos;
                while (self.pos < self.data.len) {
                    const b = self.data[self.pos];
                    self.pos += 1;
                    if ((b & 0x80) == 0) return;
                    if (self.pos - start >= 10) return error.VarintOverflow;
                }
                return error.UnexpectedEof;
            },
            @intFromEnum(WireType.fixed64) => {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                self.pos += 8;
            },
            @intFromEnum(WireType.length_delimited) => {
                const len = try decodeVarintAt(self.data, &self.pos);
                if (len > std.math.maxInt(usize)) return error.LengthOverflow;
                const usize_len: usize = @intCast(len);
                if (self.pos + usize_len > self.data.len) return error.UnexpectedEof;
                self.pos += usize_len;
            },
            @intFromEnum(WireType.fixed32) => {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                self.pos += 4;
            },
            else => return error.UnsupportedWireType,
        }
    }

    /// Scan forward to the next `length_delimited` field with `target_tag`,
    /// skipping non-matching fields without creating any `Field` struct or slice.
    /// Returns the matched field's payload bytes, or null at end-of-message.
    pub fn skipToTag(self: *Reader, target_tag: u32, target_wire_type: WireType) !?[]const u8 {
        while (self.pos < self.data.len) {
            const key = try decodeVarintAt(self.data, &self.pos);
            const tag = @as(u32, @intCast(key >> 3));
            if (tag == 0) return error.InvalidTag;
            const wt_num = @as(u3, @truncate(key & 0x7));

            if (tag == target_tag and wt_num == @intFromEnum(target_wire_type)) {
                if (target_wire_type == .length_delimited) {
                    const len = try decodeVarintAt(self.data, &self.pos);
                    if (len > std.math.maxInt(usize)) return error.LengthOverflow;
                    const usize_len: usize = @intCast(len);
                    if (self.pos + usize_len > self.data.len) return error.UnexpectedEof;
                    const start = self.pos;
                    self.pos += usize_len;
                    return self.data[start..self.pos];
                }
                return &.{};
            }

            try self.skipFieldValue(wt_num);
        }
        return null;
    }

    /// Returns the next field in message order.
    /// `field.data` is always the raw bytes for that field value.
    pub fn next(self: *Reader) !?Field {
        if (self.pos >= self.data.len) return null;

        const key = try decodeVarintAt(self.data, &self.pos);
        const tag = @as(u32, @intCast(key >> 3));
        if (tag == 0) return error.InvalidTag;

        const wt_num = @as(u3, @truncate(key & 0x7));

        return switch (wt_num) {
            @intFromEnum(WireType.varint) => blk: {
                const start = self.pos;
                const value = try decodeVarintAt(self.data, &self.pos);
                break :blk Field{
                    .tag = tag,
                    .wire_type = .varint,
                    .data = self.data[start..self.pos],
                    .varint_value = value,
                };
            },
            @intFromEnum(WireType.fixed64) => blk: {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += 8;
                break :blk Field{ .tag = tag, .wire_type = .fixed64, .data = self.data[start..self.pos], .varint_value = null };
            },
            @intFromEnum(WireType.length_delimited) => blk: {
                const len = try decodeVarintAt(self.data, &self.pos);
                if (len > std.math.maxInt(usize)) return error.LengthOverflow;
                const usize_len: usize = @intCast(len);
                if (self.pos + usize_len > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += usize_len;
                break :blk Field{ .tag = tag, .wire_type = .length_delimited, .data = self.data[start..self.pos], .varint_value = null };
            },
            @intFromEnum(WireType.fixed32) => blk: {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += 4;
                break :blk Field{ .tag = tag, .wire_type = .fixed32, .data = self.data[start..self.pos], .varint_value = null };
            },
            else => error.UnsupportedWireType,
        };
    }
};

pub fn fieldVarintValue(field: Field) !u64 {
    if (field.wire_type != .varint) return error.InvalidWireType;
    return field.varint_value orelse decodeVarint(field.data);
}

pub fn decodeVarint(data: []const u8) !u64 {
    var pos: usize = 0;
    const value = try decodeVarintAt(data, &pos);
    if (pos != data.len) return error.TrailingData;
    return value;
}

/// Decode a varint from `data` at `pos`, updating `pos` to the first byte after it.
pub fn decodeVarintAt(data: []const u8, pos: *usize) !u64 {
    if (pos.* >= data.len) return error.UnexpectedEof;

    // Fast path: one-byte varints are very common.
    const b0 = data[pos.*];
    if ((b0 & 0x80) == 0) {
        pos.* += 1;
        return b0;
    }

    // Fast path: two-byte varints are the most common multi-byte case.
    if (pos.* + 1 >= data.len) return error.UnexpectedEof;
    const b1 = data[pos.* + 1];
    if ((b1 & 0x80) == 0) {
        pos.* += 2;
        return @as(u64, b0 & 0x7f) | (@as(u64, b1) << 7);
    }

    // 3+ byte varint: seed with bytes 0–1, continue the loop from byte 2.
    var p = pos.* + 2;
    var value: u64 = @as(u64, b0 & 0x7f) | (@as(u64, b1 & 0x7f) << 7);
    var shift: u6 = 14;
    while (true) {
        if (p >= data.len) return error.UnexpectedEof;
        const byte = data[p];
        p += 1;

        value |= @as(u64, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) {
            pos.* = p;
            return value;
        }

        if (shift >= 63) return error.VarintOverflow;
        shift += 7;
    }
}

pub fn decodeUint32(data: []const u8) !u32 {
    const value = try decodeVarint(data);
    return std.math.cast(u32, value) orelse error.IntegerOverflow;
}

pub fn decodeUint64(data: []const u8) !u64 {
    return decodeVarint(data);
}

pub fn decodeInt64(data: []const u8) !i64 {
    const value = try decodeVarint(data);
    return std.math.cast(i64, value) orelse error.IntegerOverflow;
}

pub fn decodeSint64(data: []const u8) !i64 {
    return decodeZigZag64(try decodeVarint(data));
}

pub fn decodeBool(data: []const u8) !bool {
    return (try decodeVarint(data)) != 0;
}

pub fn decodeFloat(data: []const u8) !f32 {
    if (data.len != 4) return error.UnexpectedEof;
    return @bitCast(std.mem.readInt(u32, data[0..4], .little));
}

pub fn decodeDouble(data: []const u8) !f64 {
    if (data.len != 8) return error.UnexpectedEof;
    return @bitCast(std.mem.readInt(u64, data[0..8], .little));
}

pub fn decodeZigZag32(value: u32) i32 {
    const shifted: i32 = @bitCast(value >> 1);
    const mask: i32 = -@as(i32, @intCast(value & 1));
    return shifted ^ mask;
}

pub fn decodeZigZag64(value: u64) i64 {
    const shifted: i64 = @bitCast(value >> 1);
    const mask: i64 = -@as(i64, @intCast(value & 1));
    return shifted ^ mask;
}

/// Iterator for packed `uint32` payloads (for example geometry and tags arrays).
pub const PackedUInt32Iterator = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) PackedUInt32Iterator {
        return .{ .data = data };
    }

    /// Returns the next unpacked integer from the packed sequence.
    pub fn next(self: *PackedUInt32Iterator) !?u32 {
        if (self.pos >= self.data.len) return null;
        const value = try decodeVarintAt(self.data, &self.pos);
        return std.math.cast(u32, value) orelse error.IntegerOverflow;
    }
};

// Encoding

/// Protobuf field key: `(tag << 3) | wire_type`.
pub fn fieldKey(tag: u32, wire: WireType) u64 {
    return (@as(u64, tag) << 3) | @as(u64, @intFromEnum(wire));
}

/// Byte length of `value` when encoded as a protobuf varint.
pub fn varintSerializedLen(value: u64) usize {
    var n: usize = 1;
    var v = value;
    while (v >= 0x80) {
        v >>= 7;
        n += 1;
    }
    return n;
}

/// Byte length of a packed `repeated uint32` payload (each element as a varint).
pub fn packedUInt32SerializedLen(values: []const u32) usize {
    var n: usize = 0;
    for (values) |x| n += varintSerializedLen(x);
    return n;
}

pub fn appendVarintUnmanaged(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(u8), value: u64) !void {
    var v = value;
    while (true) {
        var byte: u8 = @truncate(v & 0x7f);
        v >>= 7;
        if (v != 0) byte |= 0x80;
        try list.append(allocator, byte);
        if (v == 0) break;
    }
}

pub fn appendVarintFieldUnmanaged(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(u8), tag: u32, value: u64) !void {
    try appendVarintUnmanaged(allocator, list, fieldKey(tag, .varint));
    try appendVarintUnmanaged(allocator, list, value);
}

pub fn appendLengthDelimitedFieldUnmanaged(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(u8), tag: u32, payload: []const u8) !void {
    try appendVarintUnmanaged(allocator, list, fieldKey(tag, .length_delimited));
    try appendVarintUnmanaged(allocator, list, payload.len);
    try list.appendSlice(allocator, payload);
}

pub const SliceWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn append(self: *SliceWriter, b: u8) error{BufferTooSmall}!void {
        if (self.pos >= self.buf.len) return error.BufferTooSmall;
        self.buf[self.pos] = b;
        self.pos += 1;
    }

    pub fn appendSlice(self: *SliceWriter, s: []const u8) error{BufferTooSmall}!void {
        const end = self.pos + s.len;
        if (end > self.buf.len) return error.BufferTooSmall;
        @memcpy(self.buf[self.pos..end], s);
        self.pos = end;
    }
};

pub fn appendVarint(writer: anytype, value: u64) !void {
    var v = value;
    while (true) {
        var byte: u8 = @truncate(v & 0x7f);
        v >>= 7;
        if (v != 0) byte |= 0x80;
        try writer.append(byte);
        if (v == 0) break;
    }
}

pub fn appendLengthDelimitedField(writer: anytype, tag: u32, payload: []const u8) !void {
    try appendVarint(writer, fieldKey(tag, .length_delimited));
    try appendVarint(writer, payload.len);
    try writer.appendSlice(payload);
}
