const std = @import("std");
const vtzero = @import("vtzero");

pub fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

pub fn loadTestTile(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(
        io,
        "vtzero/test/data/mapbox-streets-v6-14-8714-8017.mvt",
        allocator,
        .limited(32 * 1024 * 1024),
    );
}

pub const DummyPointHandler = struct {
    value: i32 = 0,

    pub fn points_begin(self: *DummyPointHandler, _: u32) void {
        self.value += 1;
    }

    pub fn points_point(self: *DummyPointHandler, _: vtzero.Point) void {
        self.value += 100;
    }

    pub fn points_end(self: *DummyPointHandler) void {
        self.value += 10000;
    }

    pub fn result(self: *const DummyPointHandler) i32 {
        return self.value;
    }
};

pub const DummyLineHandler = struct {
    value: i32 = 0,

    pub fn linestring_begin(self: *DummyLineHandler, _: u32) void {
        self.value += 1;
    }

    pub fn linestring_point(self: *DummyLineHandler, _: vtzero.Point) void {
        self.value += 100;
    }

    pub fn linestring_end(self: *DummyLineHandler) void {
        self.value += 10000;
    }

    pub fn result(self: *const DummyLineHandler) i32 {
        return self.value;
    }
};

pub const DummyPolygonHandler = struct {
    value: i32 = 0,

    pub fn ring_begin(self: *DummyPolygonHandler, _: u32) void {
        self.value += 1;
    }

    pub fn ring_point(self: *DummyPolygonHandler, _: vtzero.Point) void {
        self.value += 100;
    }

    pub fn ring_end(self: *DummyPolygonHandler, _: vtzero.RingType) void {
        self.value += 10000;
    }

    pub fn result(self: *const DummyPolygonHandler) i32 {
        return self.value;
    }
};

pub const AreaPolygonHandler = struct {
    rings: std.ArrayListUnmanaged(std.ArrayListUnmanaged(vtzero.Point)) = .empty,
    areas: std.ArrayListUnmanaged(i64) = .empty,

    pub fn deinit(self: *AreaPolygonHandler, allocator: std.mem.Allocator) void {
        for (self.rings.items) |*ring| ring.deinit(allocator);
        self.rings.deinit(allocator);
        self.areas.deinit(allocator);
    }

    pub fn ring_begin(self: *AreaPolygonHandler, count: u32) !void {
        try self.rings.append(std.testing.allocator, .empty);
        try self.rings.items[self.rings.items.len - 1].ensureTotalCapacity(std.testing.allocator, count);
    }

    pub fn ring_point(self: *AreaPolygonHandler, point: vtzero.Point) !void {
        try self.rings.items[self.rings.items.len - 1].append(std.testing.allocator, point);
    }

    pub fn ring_end(self: *AreaPolygonHandler, area: i64) !void {
        try self.areas.append(std.testing.allocator, area);
    }
};

pub fn packInts(buf: []u8, ints: []const u32) []const u8 {
    var len: usize = 0;
    for (ints) |raw| {
        var value = raw;
        while (true) {
            var byte: u8 = @truncate(value & 0x7f);
            value >>= 7;
            if (value != 0) byte |= 0x80;
            buf[len] = byte;
            len += 1;
            if (value == 0) break;
        }
    }
    return buf[0..len];
}
