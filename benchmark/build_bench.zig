const std = @import("std");

pub fn addSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    mod: *std.Build.Module,
) void {
    const bench_zig_worker_mod = b.createModule(.{
        .root_source_file = b.path("benchmark/zig/bench_parse_mvt.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_zig_worker_mod.addImport("vtzero", mod);

    const bench_zig_worker = b.addExecutable(.{
        .name = "bench-parse-mvt-zig-worker",
        .root_module = bench_zig_worker_mod,
    });

    const bench_single_tile_steps_mod = b.createModule(.{
        .root_source_file = b.path("benchmark/zig/bench_parse_single_tile_steps.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_single_tile_steps_mod.addImport("vtzero", mod);

    const bench_single_tile_steps = b.addExecutable(.{
        .name = "bench-parse-single-tile-steps-zig",
        .root_module = bench_single_tile_steps_mod,
    });

    const bench_harness_mod = b.createModule(.{
        .root_source_file = b.path("benchmark/bench_harness_mvt.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const bench_harness = b.addExecutable(.{
        .name = "bench-parse-mvt-harness",
        .root_module = bench_harness_mod,
    });

    const install_bench_worker = b.addInstallArtifact(bench_zig_worker, .{});
    const install_bench_single_tile_steps = b.addInstallArtifact(bench_single_tile_steps, .{});
    const install_bench_harness = b.addInstallArtifact(bench_harness, .{});

    const cpp_common_mod_options: std.Build.Module.CreateOptions = .{
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
        .link_libcpp = true,
    };

    const bench_cpp_mod = b.createModule(cpp_common_mod_options);
    bench_cpp_mod.addIncludePath(b.path("vtzero/include"));
    bench_cpp_mod.addIncludePath(b.path("vtzero/third_party/protozero/include"));
    bench_cpp_mod.addCSourceFiles(.{
        .root = b.path("benchmark/cpp"),
        .files = &.{"bench_parse_mvt.cpp"},
        .flags = &.{"-std=c++23", "-Wno-system-headers"},
    });

    const bench_cpp_exe = b.addExecutable(.{
        .name = "bench-parse-mvt-cpp",
        .root_module = bench_cpp_mod,
    });

    const bench_cpp_single_mod = b.createModule(cpp_common_mod_options);
    bench_cpp_single_mod.addIncludePath(b.path("vtzero/include"));
    bench_cpp_single_mod.addIncludePath(b.path("vtzero/third_party/protozero/include"));
    bench_cpp_single_mod.addCSourceFiles(.{
        .root = b.path("benchmark/cpp"),
        .files = &.{"bench_parse_single_tile_steps.cpp"},
        .flags = &.{"-std=c++23", "-Wno-system-headers"},
    });

    const bench_cpp_single_exe = b.addExecutable(.{
        .name = "bench-parse-single-tile-steps-cpp",
        .root_module = bench_cpp_single_mod,
    });

    const install_bench_cpp = b.addInstallArtifact(bench_cpp_exe, .{});
    const install_bench_cpp_single = b.addInstallArtifact(bench_cpp_single_exe, .{});

    const run_zig = b.addRunArtifact(bench_harness);
    run_zig.setCwd(b.path(""));
    run_zig.has_side_effects = true;
    run_zig.addArg("--zig-bench");
    run_zig.addArtifactArg(bench_zig_worker);
    run_zig.addArg("--cpp-bench");
    run_zig.addArtifactArg(bench_cpp_exe);

    const bench_step = b.step("bench", "Install + run Zig and C++ MVT parse benchmarks");
    bench_step.dependOn(&install_bench_worker.step);
    bench_step.dependOn(&install_bench_single_tile_steps.step);
    bench_step.dependOn(&install_bench_harness.step);
    bench_step.dependOn(&install_bench_cpp.step);
    bench_step.dependOn(&install_bench_cpp_single.step);
    bench_step.dependOn(&run_zig.step);

    const run_single_tile_steps = b.addRunArtifact(bench_single_tile_steps);
    run_single_tile_steps.setCwd(b.path(""));
    if (b.args) |args| run_single_tile_steps.addArgs(args);

    const bench_single_step = b.step("bench-single-tile", "Run single-tile parse sub-step benchmark");
    bench_single_step.dependOn(&install_bench_single_tile_steps.step);
    bench_single_step.dependOn(&run_single_tile_steps.step);

    const run_single_tile_cpp = b.addRunArtifact(bench_cpp_single_exe);
    run_single_tile_cpp.setCwd(b.path(""));
    if (b.args) |args| run_single_tile_cpp.addArgs(args);

    const bench_single_cpp_step = b.step("bench-single-tile-cpp", "Run C++ single-tile parse sub-step benchmark");
    bench_single_cpp_step.dependOn(&install_bench_cpp_single.step);
    bench_single_cpp_step.dependOn(&run_single_tile_cpp.step);
}
