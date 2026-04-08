//! Custom unit test runner: prints per-test wall time (monotonic timer) and a short summary.
//! Uses `mode: .simple` in `build.zig` so this binary runs standalone (no `std.zig.Server` protocol).

const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;
const testing = std.testing;

const runner_threaded_io: Io = Io.Threaded.global_single_threaded.io();

/// Round a floating point number to a specified number of significant figures.
fn roundSig(val: f64, figs: i32) f64 {
    if (val == 0) return 0;
    const d = std.math.ceil(std.math.log10(if (val < 0) -val else val));
    const power = @as(f64, @floatFromInt(figs)) - d;
    const magnitude = std.math.pow(f64, 10, power);
    return @round(val * magnitude) / magnitude;
}

const colors = struct {
    const cyan = "\x1b[36m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const magenta = "\x1b[35m";
    const reset = "\x1b[0m";
};

/// Format a duration in nanoseconds as a string with the appropriate unit.
pub fn formatTime(allocator: std.mem.Allocator, ns: i96) ![]u8 {
    const fmt = "{d: >4}";
    if (ns < std.time.ns_per_us) {
        return std.fmt.allocPrint(allocator, colors.cyan ++ fmt ++ " ns" ++ colors.reset, .{@as(u96, @intCast(ns))});
    } else if (ns < std.time.ns_per_ms) {
        return std.fmt.allocPrint(allocator, colors.green ++ fmt ++ " µs" ++ colors.reset, .{roundSig(@as(f64, @floatFromInt(ns)) / std.time.ns_per_us, 3)});
    } else if (ns < std.time.ns_per_s) {
        return std.fmt.allocPrint(allocator, colors.yellow ++ fmt ++ " ms" ++ colors.reset, .{roundSig(@as(f64, @floatFromInt(ns)) / std.time.ns_per_ms, 3)});
    } else if (ns < std.time.ns_per_min) {
        return std.fmt.allocPrint(allocator, colors.red ++ fmt ++ " s" ++ colors.reset, .{roundSig(@as(f64, @floatFromInt(ns)) / std.time.ns_per_s, 3)});
    } else {
        return std.fmt.allocPrint(allocator, colors.magenta ++ fmt ++ " m" ++ colors.reset, .{roundSig(@as(f64, @floatFromInt(ns)) / std.time.ns_per_min, 3)});
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
            try stdout_w.interface.print("[✅] {s} | {s}\n", .{ duration_str, test_fn.name });
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                try stdout_w.interface.print("[⏭️] {s} | {s}\n", .{ duration_str, test_fn.name });
            },
            else => {
                failed += 1;
                try stdout_w.interface.print("[❌] {s} | {s} | {t}\n", .{ duration_str, test_fn.name, err });
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
