const std = @import("std");

const default_dir = "vtzero/test/mvt-fixtures/real-world";

const PathRec = struct {
    folder: []const u8,
    path: []const u8,
};

const WorkerResult = struct {
    checksum: u64,
    elapsed_ns: u64,
};

fn reportWorkerFailure(
    io: std.Io,
    term: std.process.Child.Term,
    exe_path: []const u8,
    decode_mode: bool,
    iters: usize,
    argv: []const []const u8,
    worker_stdout: []const u8,
    worker_stderr: []const u8,
) !void {
    var ew = std.Io.File.stderr().writerStreaming(io, &.{});
    const mode_label: []const u8 = if (decode_mode) "parse+decode" else "parse-only";

    switch (term) {
        .exited => |code| try ew.interface.print(
            "worker failed: exe={s} mode={s} iters={d} code={d} argv_len={d}\n",
            .{ exe_path, mode_label, iters, code, argv.len },
        ),
        else => try ew.interface.print(
            "worker failed: exe={s} mode={s} iters={d} term={any} argv_len={d}\n",
            .{ exe_path, mode_label, iters, term, argv.len },
        ),
    }

    for (argv, 0..) |a, idx| {
        try ew.interface.print("  argv[{d}]={s}\n", .{ idx, a });
    }

    const sections = [_]struct { header: []const u8, body: []const u8 }{
        .{ .header = "=== worker stderr ===\n", .body = worker_stderr },
        .{ .header = "=== worker stdout ===\n", .body = worker_stdout },
    };
    for (sections) |s| {
        if (s.body.len == 0) continue;
        try ew.interface.writeAll(s.header);
        try ew.interface.writeAll(s.body);
        if (s.body[s.body.len - 1] != '\n') try ew.interface.writeAll("\n");
    }
}

fn lessThanU64(_: void, a: u64, b: u64) bool {
    return a < b;
}

fn p95Ns(comptime N: usize, vals: [N]u64) u64 {
    var sorted = vals;
    std.sort.pdq(u64, sorted[0..], {}, lessThanU64);
    const idx = @min(N - 1, ((N * 95 + 99) / 100) - 1);
    return sorted[idx];
}

fn medianNs(comptime N: usize, vals: [N]u64) u64 {
    var sorted = vals;
    std.sort.pdq(u64, sorted[0..], {}, lessThanU64);
    return sorted[N / 2];
}

fn parseWorkerOutput(stdout: []const u8, decode_mode: bool) !WorkerResult {
    var lines = std.mem.tokenizeScalar(u8, stdout, '\n');
    const line = lines.next() orelse return error.InvalidWorkerOutput;
    var cols = std.mem.tokenizeScalar(u8, line, '\t');
    const mode = cols.next() orelse return error.InvalidWorkerOutput;
    const checksum_hex = cols.next() orelse return error.InvalidWorkerOutput;
    const elapsed_s = cols.next() orelse return error.InvalidWorkerOutput;

    if (decode_mode and !std.mem.eql(u8, mode, "parse+decode")) return error.InvalidWorkerOutput;
    if (!decode_mode and !std.mem.eql(u8, mode, "parse-only")) return error.InvalidWorkerOutput;

    return .{
        .checksum = try std.fmt.parseInt(u64, checksum_hex, 16),
        .elapsed_ns = try std.fmt.parseInt(u64, elapsed_s, 10),
    };
}

fn runWorker(
    alloc: std.mem.Allocator,
    io: std.Io,
    exe_path: []const u8,
    decode_mode: bool,
    iters: usize,
    paths: []const []const u8,
) !WorkerResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(alloc);

    try argv.append(alloc, exe_path);
    if (decode_mode) try argv.append(alloc, "--decode");
    try argv.append(alloc, "--iters");
    const iters_str = try std.fmt.allocPrint(alloc, "{d}", .{iters});
    defer alloc.free(iters_str);
    try argv.append(alloc, iters_str);
    for (paths) |p| try argv.append(alloc, p);

    const res = try std.process.run(alloc, io, .{
        .argv = argv.items,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    });
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);

    switch (res.term) {
        .exited => |code| if (code == 0) return parseWorkerOutput(res.stdout, decode_mode),
        else => {},
    }

    try reportWorkerFailure(io, res.term, exe_path, decode_mode, iters, argv.items, res.stdout, res.stderr);
    return error.WorkerFailed;
}

const colors = struct {
    const cyan = "\x1b[36m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const magenta = "\x1b[35m";
    const reset = "\x1b[0m";
};

/// Format a speedup factor as a string with the appropriate color
fn formatSpeedup(alloc: std.mem.Allocator, speedup: f64) ![]const u8 {
    const prefix: []const u8 = if (speedup < 0.8) // more than 20% slower
        colors.red
    else if (speedup < 0.95) // between 5% and 20% slower
        colors.magenta
    else if (speedup < 1.05) // within 5% of the reference
        colors.yellow
    else if (speedup < 1.2) // between 5% and 20% faster
        colors.cyan
    else // more than 20% faster
        colors.green;

    return try std.fmt.allocPrint(alloc, "{s}{d:.3}x{s}", .{ prefix, speedup, colors.reset });
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();

    var dir_path: []const u8 = default_dir;
    var zig_bench_path: ?[]const u8 = null;
    var cpp_bench_path: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--zig-bench")) {
            zig_bench_path = args.next() orelse return error.MissingZigBenchPath;
        } else if (std.mem.eql(u8, arg, "--cpp-bench")) {
            cpp_bench_path = args.next() orelse return error.MissingCppBenchPath;
        } else {
            dir_path = arg;
        }
    }

    const zig_exe = zig_bench_path orelse return error.MissingZigBenchPath;
    const cpp_exe = cpp_bench_path orelse return error.MissingCppBenchPath;

    const cwd = std.Io.Dir.cwd();
    var dir = try cwd.openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var recs: std.ArrayList(PathRec) = .empty;
    defer recs.deinit(alloc);

    var it = dir.iterate();
    while (try it.next(io)) |e| {
        switch (e.kind) {
            .file => {
                if (!std.mem.endsWith(u8, e.name, ".mvt")) continue;
                const full = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir_path, e.name });
                try recs.append(alloc, .{ .folder = ".", .path = full });
            },
            .directory => {
                const folder = try alloc.dupe(u8, e.name);
                var sub = try dir.openDir(io, e.name, .{ .iterate = true });
                defer sub.close(io);
                var sit = sub.iterate();
                while (try sit.next(io)) |se| {
                    if (se.kind != .file or !std.mem.endsWith(u8, se.name, ".mvt")) continue;
                    const full = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}", .{ dir_path, e.name, se.name });
                    try recs.append(alloc, .{ .folder = folder, .path = full });
                }
            },
            else => {},
        }
    }

    if (recs.items.len == 0) return error.NoMvtFiles;

    std.sort.pdq(PathRec, recs.items, {}, struct {
        fn lt(_: void, a: PathRec, b: PathRec) bool {
            return switch (std.mem.order(u8, a.folder, b.folder)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.lessThan(u8, a.path, b.path),
            };
        }
    }.lt);

    const iters: usize = 5;
    const repeats: usize = 7;

    var i: usize = 0;
    while (i < recs.items.len) {
        const folder = recs.items[i].folder;
        var j = i + 1;
        while (j < recs.items.len and std.mem.eql(u8, recs.items[j].folder, folder)) j += 1;

        const paths = try alloc.alloc([]const u8, j - i);
        defer alloc.free(paths);
        for (i..j, 0..) |k, idx| paths[idx] = recs.items[k].path;

        var zig_parse_times: [repeats]u64 = undefined;
        var zig_decode_times: [repeats]u64 = undefined;
        var cpp_parse_times: [repeats]u64 = undefined;
        var cpp_decode_times: [repeats]u64 = undefined;

        var zig_parse_checksum: u64 = 0;
        var zig_decode_checksum: u64 = 0;
        var cpp_parse_checksum: u64 = 0;
        var cpp_decode_checksum: u64 = 0;

        for (0..repeats) |r| {
            const decode_first = (r & 1) == 1;

            if (decode_first) {
                const zd = runWorker(alloc, io, zig_exe, true, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=zig mode=decode folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const zp = runWorker(alloc, io, zig_exe, false, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=zig mode=parse folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const cd = runWorker(alloc, io, cpp_exe, true, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=cpp mode=decode folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const cp = runWorker(alloc, io, cpp_exe, false, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=cpp mode=parse folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                zig_decode_times[r] = zd.elapsed_ns;
                zig_parse_times[r] = zp.elapsed_ns;
                cpp_decode_times[r] = cd.elapsed_ns;
                cpp_parse_times[r] = cp.elapsed_ns;
                zig_decode_checksum = zd.checksum;
                zig_parse_checksum = zp.checksum;
                cpp_decode_checksum = cd.checksum;
                cpp_parse_checksum = cp.checksum;
            } else {
                const zp = runWorker(alloc, io, zig_exe, false, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=zig mode=parse folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const zd = runWorker(alloc, io, zig_exe, true, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=zig mode=decode folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const cp = runWorker(alloc, io, cpp_exe, false, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=cpp mode=parse folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                const cd = runWorker(alloc, io, cpp_exe, true, iters, paths) catch |err| {
                    std.debug.print("runWorker failed impl=cpp mode=decode folder={s} repeat={d} err={t}\n", .{ folder, r, err });
                    return err;
                };
                zig_parse_times[r] = zp.elapsed_ns;
                zig_decode_times[r] = zd.elapsed_ns;
                cpp_parse_times[r] = cp.elapsed_ns;
                cpp_decode_times[r] = cd.elapsed_ns;
                zig_parse_checksum = zp.checksum;
                zig_decode_checksum = zd.checksum;
                cpp_parse_checksum = cp.checksum;
                cpp_decode_checksum = cd.checksum;
            }
        }

        const zig_parse_med = medianNs(repeats, zig_parse_times) / iters;
        const zig_decode_med = medianNs(repeats, zig_decode_times) / iters;
        const cpp_parse_med = medianNs(repeats, cpp_parse_times) / iters;
        const cpp_decode_med = medianNs(repeats, cpp_decode_times) / iters;

        std.debug.print(
            "[BENCH] folder={s} mode=parse-only tiles={d} checksum={s} (median/p95 ns) zig={d}/{d} cpp={d}/{d} speedup={s}\n",
            .{
                folder,
                paths.len,
                if (zig_parse_checksum == cpp_parse_checksum) "✓" else "✗",
                zig_parse_med,
                p95Ns(repeats, zig_parse_times) / iters,
                cpp_parse_med,
                p95Ns(repeats, cpp_parse_times) / iters,
                try formatSpeedup(alloc, @as(f64, @floatFromInt(cpp_parse_med)) / @as(f64, @floatFromInt(zig_parse_med))),
            },
        );
        std.debug.print(
            "[BENCH] folder={s} mode=parse+decode tiles={d} checksum={s} | Times: (median/p95 ns) zig={d}/{d} cpp={d}/{d} speedup={s}\n",
            .{
                folder,
                paths.len,
                if (zig_decode_checksum == cpp_decode_checksum) "✓" else "✗",
                zig_decode_med,
                p95Ns(repeats, zig_decode_times) / iters,
                cpp_decode_med,
                p95Ns(repeats, cpp_decode_times) / iters,
                try formatSpeedup(alloc, @as(f64, @floatFromInt(cpp_decode_med)) / @as(f64, @floatFromInt(zig_decode_med))),
            },
        );

        i = j;
    }
}
