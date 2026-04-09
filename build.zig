const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("vtzero", .{
        .root_source_file = b.path("src/vtzero.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ------------------------------------------------------------
    // Benchmark tile parsing
    // ------------------------------------------------------------
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
    const install_bench_harness = b.addInstallArtifact(bench_harness, .{});

    const bench_cpp_compile = b.addSystemCommand(&.{"g++"});
    bench_cpp_compile.addArgs(&.{ "-std=c++17", "-O3", "-march=native", "-mtune=native" });
    bench_cpp_compile.addArg("-I");
    bench_cpp_compile.addDirectoryArg(b.path("vtzero/include"));
    bench_cpp_compile.addArg("-I");
    bench_cpp_compile.addDirectoryArg(b.path("vtzero/third_party/protozero/include"));
    bench_cpp_compile.addFileArg(b.path("benchmark/cpp/bench_parse_mvt.cpp"));
    bench_cpp_compile.addArg("-o");
    const cpp_bench_out = bench_cpp_compile.addOutputFileArg("bench-parse-mvt-cpp");

    const install_bench_cpp = b.addInstallBinFile(cpp_bench_out, "bench-parse-mvt-cpp");

    const run_zig = b.addRunArtifact(bench_harness);
    run_zig.setCwd(b.path(""));
    run_zig.has_side_effects = true;
    run_zig.addArg("--zig-bench");
    run_zig.addArtifactArg(bench_zig_worker);
    run_zig.addArg("--cpp-bench");
    run_zig.addFileArg(cpp_bench_out);

    const bench_step = b.step("bench", "Install + run Zig and C++ MVT parse benchmarks");
    bench_step.dependOn(&install_bench_worker.step);
    bench_step.dependOn(&install_bench_harness.step);
    bench_step.dependOn(&install_bench_cpp.step);
    bench_step.dependOn(&run_zig.step);
    // ------------------------------------------------------------

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("vtzero", mod);

    const lib_tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("test/test_runner.zig"),
            .mode = .simple,
        },
    });

    const run_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
