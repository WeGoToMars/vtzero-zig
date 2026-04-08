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
};

/// Lightweight protobuf reader that iterates fields without copying.
pub const Reader = struct {
    data: []const u8,
    pos: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    /// Returns the next field in message order.
    /// `field.data` is always the raw bytes for that field value.
    pub fn next(self: *Reader) !?Field {
        if (self.pos >= self.data.len) return null;

        const key = try decodeVarintAt(self.data, &self.pos);
        const tag = @as(u32, @intCast(key >> 3));
        if (tag == 0) return error.InvalidTag;

        const wt_num = @as(u3, @truncate(key & 0x7));
        if (std.enums.tagName(WireType, @as(WireType, @enumFromInt(wt_num))) == null) {
            return error.UnsupportedWireType;
        }
        const wire_type: WireType = @enumFromInt(wt_num);

        return switch (wire_type) {
            .varint => blk: {
                const start = self.pos;
                _ = try decodeVarintAt(self.data, &self.pos);
                break :blk Field{ .tag = tag, .wire_type = wire_type, .data = self.data[start..self.pos] };
            },
            .fixed64 => blk: {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += 8;
                break :blk Field{ .tag = tag, .wire_type = wire_type, .data = self.data[start..self.pos] };
            },
            .length_delimited => blk: {
                const len = try decodeVarintAt(self.data, &self.pos);
                if (len > std.math.maxInt(usize)) return error.LengthOverflow;
                const usize_len: usize = @intCast(len);
                if (self.pos + usize_len > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += usize_len;
                break :blk Field{ .tag = tag, .wire_type = wire_type, .data = self.data[start..self.pos] };
            },
            .fixed32 => blk: {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                const start = self.pos;
                self.pos += 4;
                break :blk Field{ .tag = tag, .wire_type = wire_type, .data = self.data[start..self.pos] };
            },
        };
    }
};

pub fn decodeVarint(data: []const u8) !u64 {
    var pos: usize = 0;
    const value = try decodeVarintAt(data, &pos);
    if (pos != data.len) return error.TrailingData;
    return value;
}

/// Decode a varint from `data` at `pos`, updating `pos` to the first byte after it.
pub fn decodeVarintAt(data: []const u8, pos: *usize) !u64 {
    var shift: u6 = 0;
    var value: u64 = 0;

    while (true) {
        if (pos.* >= data.len) return error.UnexpectedEof;
        const byte = data[pos.*];
        pos.* += 1;

        value |= @as(u64, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) return value;

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

pub fn appendVarintManaged(list: *std.array_list.Managed(u8), value: u64) error{OutOfMemory}!void {
    var v = value;
    while (true) {
        var byte: u8 = @truncate(v & 0x7f);
        v >>= 7;
        if (v != 0) byte |= 0x80;
        try list.append(byte);
        if (v == 0) break;
    }
}

/// Fixed-buffer writer for length-prefixed serialization (no heap).
pub const SliceWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn appendByte(self: *SliceWriter, b: u8) error{BufferTooSmall}!void {
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

pub fn appendVarintSliceWriter(w: *SliceWriter, value: u64) error{BufferTooSmall}!void {
    var v = value;
    while (true) {
        var byte: u8 = @truncate(v & 0x7f);
        v >>= 7;
        if (v != 0) byte |= 0x80;
        try w.appendByte(byte);
        if (v == 0) break;
    }
}

pub fn appendLengthDelimitedFieldSliceWriter(w: *SliceWriter, tag: u32, payload: []const u8) error{BufferTooSmall}!void {
    try appendVarintSliceWriter(w, fieldKey(tag, .length_delimited));
    try appendVarintSliceWriter(w, payload.len);
    try w.appendSlice(payload);
}
