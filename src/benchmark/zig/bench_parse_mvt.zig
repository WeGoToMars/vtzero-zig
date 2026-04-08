const std = @import("std");
const vtzero = @import("vtzero");

const default_dir = "vtzero/test/mvt-fixtures/real-world/bangkok";

fn loadMvtTiles(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8) ![][]u8 {
    const cwd = std.Io.Dir.cwd();
    var dir = try cwd.openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".mvt")) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }

    if (names.items.len == 0) {
        std.debug.print("no .mvt files in directory: {s}\n", .{dir_path});
        return error.NoMvtFiles;
    }

    std.sort.pdq([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var tiles: std.ArrayList([]u8) = .empty;
    errdefer {
        for (tiles.items) |t| allocator.free(t);
        tiles.deinit(allocator);
    }
    for (names.items) |name| {
        const data = try dir.readFileAlloc(io, name, allocator, .limited(32 * 1024 * 1024));
        try tiles.append(allocator, data);
    }

    return try tiles.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var arg_it = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer arg_it.deinit();
    _ = arg_it.next();
    const dir_path: []const u8 = if (arg_it.next()) |p| p[0..p.len] else default_dir;

    const tiles = try loadMvtTiles(allocator, io, dir_path);
    defer {
        for (tiles) |t| allocator.free(t);
        allocator.free(tiles);
    }

    var checksum: u64 = 0;
    var feature_visits: u64 = 0;

    const iters: usize = 200;

    const start_ns: i96 = std.Io.Clock.awake.now(io).nanoseconds;
    for (0..iters) |_| {
        for (tiles) |data| {
            var tile = vtzero.VectorTile.init(data);
            checksum +%= @intCast(try tile.countLayers());
            while (try tile.nextLayer()) |layer| {
                var mut_layer = layer;
                checksum +%= mut_layer.name().len;
                while (try mut_layer.nextFeature()) |feature| {
                    feature_visits +%= 1;
                    checksum +%= feature.id();
                    checksum +%= @intCast(feature.numProperties());
                    checksum +%= @intFromEnum(feature.geometryType());
                }
            }
        }
    }
    const end_ns: i96 = std.Io.Clock.awake.now(io).nanoseconds;
    const elapsed_ns: u64 = @intCast(end_ns - start_ns);

    const features_per_iter: u64 = feature_visits / iters;

    std.debug.print(
        "Zig: dir={s} tiles={d} iters={d} elapsed_ns={d} per_iter_ns={d} features_per_iter={d} checksum={d}\n",
        .{ dir_path, tiles.len, iters, elapsed_ns, elapsed_ns / iters, features_per_iter, checksum },
    );
}
