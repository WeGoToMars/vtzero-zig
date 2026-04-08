//! Custom unit test runner: prints per-test wall time (monotonic timer) and a short summary.
//! Uses `mode: .simple` in `build.zig` so this binary runs standalone (no `std.zig.Server` protocol).

const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;
const testing = std.testing;

const runner_threaded_io: Io = Io.Threaded.global_single_threaded.io();

pub fn formatTime(allocator: std.mem.Allocator, ns: i96) ![]u8 {
    if (ns < std.time.ns_per_us) {
        return std.fmt.allocPrint(allocator, "{d: >3.0}ns", .{@as(u96, @intCast(ns))});
    } else if (ns < std.time.ns_per_ms) {
        return std.fmt.allocPrint(allocator, "{d: >3.0}µs", .{@as(f64, @floatFromInt(ns)) / std.time.ns_per_us});
    } else if (ns < std.time.ns_per_s) {
        return std.fmt.allocPrint(allocator, "{d: >3.0}ms", .{@as(f64, @floatFromInt(ns)) / std.time.ns_per_ms});
    } else if (ns < std.time.ns_per_min) {
        return std.fmt.allocPrint(allocator, "{d: >3.0}s", .{@as(f64, @floatFromInt(ns)) / std.time.ns_per_s});
    } else {
        return std.fmt.allocPrint(allocator, "{d: >3.0}m", .{@as(f64, @floatFromInt(ns)) / std.time.ns_per_min});
    }
}

pub fn main() void {
    mainInner() catch |err| {
        std.debug.print("test runner error: {t}\n", .{err});
        std.process.exit(1);
    };
}

fn mainInner() !void {
    var stdout_w = Io.File.stdout().writerStreaming(runner_threaded_io, &.{});

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var leaks: usize = 0;

    try stdout_w.interface.print("\n-------------------------------------------\n", .{});
    try stdout_w.interface.print("Running Tests...\n", .{});
    try stdout_w.interface.print("-------------------------------------------\n", .{});

    for (builtin.test_functions) |test_fn| {
        testing.allocator_instance = .{};
        testing.io_instance = .init(testing.allocator, .{});
        defer {
            testing.io_instance.deinit();
            if (testing.allocator_instance.deinit() == .leak) leaks += 1;
        }

        const t0 = Io.Clock.Timestamp.now(runner_threaded_io, .boot);
        const result = test_fn.func();
        const t1 = Io.Clock.Timestamp.now(runner_threaded_io, .boot);
        const duration_ns = t0.durationTo(t1).raw.nanoseconds;
        const duration_str = try formatTime(testing.allocator, duration_ns);
        defer testing.allocator.free(duration_str);

        if (result) |_| {
            passed += 1;
            try stdout_w.interface.print("[PASS] {s} | {s}\n", .{ duration_str, test_fn.name });
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                try stdout_w.interface.print("[SKIP] {s} | {s}\n", .{ duration_str, test_fn.name });
            },
            else => {
                failed += 1;
                try stdout_w.interface.print("[FAIL] {s} | {s} | {t}\n", .{ duration_str, test_fn.name, err });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace);
                }
            },
        }
    }

    try stdout_w.interface.print("-------------------------------------------\n", .{});
    try stdout_w.interface.print(
        "Summary: {} passed, {} skipped, {} failed, {} leak(s)\n\n",
        .{ passed, skipped, failed, leaks },
    );

    if (failed != 0 or leaks != 0) std.process.exit(1);
}
