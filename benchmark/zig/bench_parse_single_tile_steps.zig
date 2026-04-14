const std = @import("std");
const vtzero = @import("vtzero");

const default_tile_path = "vtzero/test/mvt-fixtures/real-world/chicago/13-2100-3045.mvt";

const GeometryChecksumHandler = struct {
    checksum: u64 = 0,

    fn mixCount(self: *GeometryChecksumHandler, n: u32) void {
        self.checksum +%= n;
    }
    fn mixPoint(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.x)));
        self.checksum +%= @as(u64, @bitCast(@as(i64, p.y)));
    }

    pub fn points_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.mixCount(n);
    }
    pub fn points_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.mixPoint(p);
    }
    pub fn points_end(self: *GeometryChecksumHandler) void {
        self.checksum +%= 1;
    }
    pub fn linestring_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.mixCount(n);
    }
    pub fn linestring_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.mixPoint(p);
    }
    pub fn linestring_end(self: *GeometryChecksumHandler) void {
        self.checksum +%= 3;
    }
    pub fn ring_begin(self: *GeometryChecksumHandler, n: u32) void {
        self.mixCount(n);
    }
    pub fn ring_point(self: *GeometryChecksumHandler, p: vtzero.Point) void {
        self.mixPoint(p);
    }
    pub fn ring_end(self: *GeometryChecksumHandler, ring_type: vtzero.RingType) void {
        self.checksum +%= @intFromEnum(ring_type);
    }
    pub fn result(self: *GeometryChecksumHandler) u64 {
        return self.checksum;
    }
};

const TimingTotals = struct {
    total_ns: u64 = 0,
    tile_init_ns: u64 = 0,
    count_layers_ns: u64 = 0,
    next_layer_ns: u64 = 0,
    layer_metadata_ns: u64 = 0,
    next_feature_ns: u64 = 0,
    feature_metadata_ns: u64 = 0,
    property_indexes_ns: u64 = 0,
    geometry_decode_ns: u64 = 0,
};

fn elapsedNs(io: std.Io, start_ns: i96) u64 {
    return @intCast(std.Io.Clock.awake.now(io).nanoseconds - start_ns);
}

fn runInstrumentedParse(io: std.Io, data: []const u8, totals: *TimingTotals) !u64 {
    var checksum: u64 = 0;
    const total_start = std.Io.Clock.awake.now(io).nanoseconds;

    const t_tile_init = std.Io.Clock.awake.now(io).nanoseconds;
    var tile = vtzero.VectorTile.init(data);
    totals.tile_init_ns +%= elapsedNs(io, t_tile_init);

    const t_count_layers = std.Io.Clock.awake.now(io).nanoseconds;
    checksum +%= @intCast(try tile.countLayers());
    totals.count_layers_ns +%= elapsedNs(io, t_count_layers);

    while (true) {
        const t_next_layer = std.Io.Clock.awake.now(io).nanoseconds;
        const maybe_layer = try tile.nextLayer();
        totals.next_layer_ns +%= elapsedNs(io, t_next_layer);

        if (maybe_layer == null) break;
        var layer = maybe_layer.?;

        const t_layer_metadata = std.Io.Clock.awake.now(io).nanoseconds;
        checksum +%= layer.name().len;
        checksum +%= layer.numFeatures();
        checksum +%= layer.keyTableSize();
        checksum +%= layer.valueTableSize();
        totals.layer_metadata_ns +%= elapsedNs(io, t_layer_metadata);

        while (true) {
            const t_next_feature = std.Io.Clock.awake.now(io).nanoseconds;
            const maybe_feature = try layer.nextFeature();
            totals.next_feature_ns +%= elapsedNs(io, t_next_feature);

            if (maybe_feature == null) break;
            var feature = maybe_feature.?;

            const t_feature_metadata = std.Io.Clock.awake.now(io).nanoseconds;
            checksum +%= feature.id();
            checksum +%= @intCast(feature.numProperties());
            checksum +%= @intFromEnum(feature.geometryType());
            totals.feature_metadata_ns +%= elapsedNs(io, t_feature_metadata);

            const t_properties = std.Io.Clock.awake.now(io).nanoseconds;
            while (try feature.nextPropertyIndexes()) |idx| {
                checksum +%= idx.key().value();
                checksum +%= idx.value().value();
            }
            totals.property_indexes_ns +%= elapsedNs(io, t_properties);

            const t_decode = std.Io.Clock.awake.now(io).nanoseconds;
            var handler: GeometryChecksumHandler = .{};
            checksum +%= try vtzero.decodeGeometry(feature.geometry(), &handler);
            totals.geometry_decode_ns +%= elapsedNs(io, t_decode);
        }
    }

    const total_end = std.Io.Clock.awake.now(io).nanoseconds;
    totals.total_ns +%= @intCast(total_end - total_start);
    return checksum;
}

fn printStep(
    w: *std.Io.Writer,
    label: []const u8,
    step_ns: u64,
    total_ns: u64,
    iters: usize,
) !void {
    const ns_per_iter = @as(f64, @floatFromInt(step_ns)) / @as(f64, @floatFromInt(iters));
    const pct_total = if (total_ns == 0)
        0.0
    else
        (@as(f64, @floatFromInt(step_ns)) * 100.0) / @as(f64, @floatFromInt(total_ns));

    try w.print(
        "{s: <20} {d: <10} {d: <12.2} {d: <12.2}\n",
        .{ label, step_ns, ns_per_iter, pct_total },
    );
}

pub fn main(init: std.process.Init.Minimal) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const alloc = std.heap.page_allocator;

    var args = try std.process.Args.Iterator.initAllocator(init.args, alloc);
    defer args.deinit();
    _ = args.next();

    var tile_path: []const u8 = default_tile_path;
    var saw_tile_arg = false;
    var iters: usize = 10_000;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iters")) {
            const n = args.next() orelse return error.MissingItersValue;
            iters = try std.fmt.parseInt(usize, n, 10);
            continue;
        }
        if (saw_tile_arg) return error.OnlySingleTileSupported;
        tile_path = arg;
        saw_tile_arg = true;
    }

    const cwd = std.Io.Dir.cwd();
    const data = try cwd.readFileAlloc(io, tile_path, alloc, .limited(std.math.maxInt(usize)));
    defer alloc.free(data);

    var totals: TimingTotals = .{};
    var checksum: u64 = 0;
    for (0..iters) |_| {
        checksum +%= try runInstrumentedParse(io, data, &totals);
    }

    var stdout_w = std.Io.File.stdout().writerStreaming(io, &.{});
    const out = &stdout_w.interface;
    try out.print("single-tile-steps\tpath={s}\titers={d}\tchecksum={x}\n", .{
        tile_path,
        iters,
        checksum,
    });
    try out.print("{s: <20} {s: <10} {s: <12} {s: <12}\n", .{ "step", "total_ns", "ns_per_iter", "pct_of_total" });
    try out.print("---------------------------------------------------------\n", .{});

    const steps = [_]struct { label: []const u8, ns: u64 }{
        .{ .label = "tile_init", .ns = totals.tile_init_ns },
        .{ .label = "count_layers", .ns = totals.count_layers_ns },
        .{ .label = "next_layer", .ns = totals.next_layer_ns },
        .{ .label = "layer_metadata", .ns = totals.layer_metadata_ns },
        .{ .label = "next_feature", .ns = totals.next_feature_ns },
        .{ .label = "feature_metadata", .ns = totals.feature_metadata_ns },
        .{ .label = "property_indexes", .ns = totals.property_indexes_ns },
        .{ .label = "geometry_decode", .ns = totals.geometry_decode_ns },
        .{ .label = "total_parse", .ns = totals.total_ns },
    };
    for (steps) |s| {
        try printStep(out, s.label, s.ns, totals.total_ns, iters);
    }
}
