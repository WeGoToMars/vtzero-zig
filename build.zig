const std = @import("std");
const bench_build = @import("benchmark/build_bench.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("vtzero", .{
        .root_source_file = b.path("src/vtzero.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_build.addSteps(b, target, mod);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/test_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("vtzero", mod);

    const lib_tests = b.addTest(.{
        .name = "test",
        .root_module = test_mod,
        .test_runner = .{
            .path = b.path("test/test_runner.zig"),
            .mode = .simple,
        },
    });

    const run_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const run_kcov = b.addSystemCommand(&.{"kcov"});
    run_kcov.addArg("--clean");
    run_kcov.addPrefixedDirectoryArg("--include-path=", b.path("src"));
    run_kcov.addArg("kcov-out");
    run_kcov.addArtifactArg(lib_tests);

    const coverage_step = b.step("coverage", "Run tests with kcov");
    coverage_step.dependOn(&run_kcov.step);
}
