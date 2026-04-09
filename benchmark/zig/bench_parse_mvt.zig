const std = @import("std");
const vtzero = @import("vtzero");

const GeometryChecksumHandler = struct {
    checksum: u64 = 0,

    pub fn points_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.checksum +%= n;
    }
    pub fn points_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.x)));
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.y)));
    }
    pub fn points_end(self: *GeometryChecksumHandler) void {
        self.checksum +%= 1;
    }
    pub fn linestring_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.checksum +%= n;
    }
    pub fn linestring_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.x)));
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.y)));
    }
    pub fn linestring_end(self: *GeometryChecksumHandler) void {
        self.checksum +%= 3;
    }
    pub fn ring_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.checksum +%= n;
    }
    pub fn ring_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.x)));
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.y)));
    }
    pub fn ring_end(self: *GeometryChecksumHandler, ring_type: vtzero.RingType) void {
        self.checksum +%= @intFromEnum(ring_type);
    }
    pub fn result(self: *GeometryChecksumHandler) u64 {
        return self.checksum;
    }
};

pub fn parseTileBytes(data: []const u8) !u64 {
    var checksum: u64 = 0;
    var tile = vtzero.VectorTile.init(data);
    checksum +%= @intCast(try tile.countLayers());
    while (try tile.nextLayer()) |layer| {
        var mut_layer = layer;
        checksum +%= mut_layer.name().len;
        while (try mut_layer.nextFeature()) |feature| {
            checksum +%= feature.id();
            checksum +%= @intCast(feature.numProperties());
            checksum +%= @intFromEnum(feature.geometryType());
        }
    }
    return checksum;
}

pub fn parseTileBytesDecode(data: []const u8) !u64 {
    var checksum: u64 = 0;
    var tile = vtzero.VectorTile.init(data);
    checksum +%= @intCast(try tile.countLayers());
    while (try tile.nextLayer()) |layer| {
        var mut_layer = layer;
        checksum +%= mut_layer.name().len;
        while (try mut_layer.nextFeature()) |feature| {
            checksum +%= feature.id();
            checksum +%= @intCast(feature.numProperties());
            checksum +%= @intFromEnum(feature.geometryType());
            var handler: GeometryChecksumHandler = .{};
            checksum +%= try vtzero.decodeGeometry(feature.geometry(), &handler);
        }
    }
    return checksum;
}

pub fn main(init: std.process.Init.Minimal) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const alloc = std.heap.page_allocator;

    var args = try std.process.Args.Iterator.initAllocator(init.args, alloc);
    defer args.deinit();
    _ = args.next();

    var decode_mode = false;
    var iters: usize = 1;
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(alloc);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--decode")) {
            decode_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--iters")) {
            const n = args.next() orelse return error.MissingItersValue;
            iters = try std.fmt.parseInt(usize, n, 10);
            continue;
        }
        try paths.append(alloc, arg);
    }

    if (paths.items.len == 0) return error.MissingTilePath;

    var buffers = try alloc.alloc([]u8, paths.items.len);
    defer alloc.free(buffers);
    const cwd = std.Io.Dir.cwd();
    for (paths.items, 0..) |p, i| {
        buffers[i] = try cwd.readFileAlloc(io, p, alloc, .limited(std.math.maxInt(usize)));
    }
    defer {
        for (buffers) |b| alloc.free(b);
    }

    var checksum: u64 = 0;
    const t0 = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..iters) |_| {
        for (buffers) |data| {
            checksum +%= if (decode_mode) try parseTileBytesDecode(data) else try parseTileBytes(data);
        }
    }
    const t1 = std.Io.Clock.awake.now(io).nanoseconds;
    const elapsed_ns: u64 = @intCast(t1 - t0);

    const mode = if (decode_mode) "parse+decode" else "parse-only";
    var stdout_w = std.Io.File.stdout().writerStreaming(io, &.{});
    try stdout_w.interface.print("{s}\t{x}\t{d}\n", .{ mode, checksum, elapsed_ns });
}
