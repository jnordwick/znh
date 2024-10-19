const std = @import("std");

pub fn build(b: *std.Build) void {

    // target and compilation options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dependencies
    const zs = b.dependency("zig-string", .{});

    // self lib
    const lib = b.addStaticLibrary(.{
        .name = "znh",
        .root_source_file = b.path("src/znh.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("zig-string", zs.module("zig-string"));
    b.installArtifact(lib);

    // run main - used for runing
    const exe = b.addExecutable(.{
        .name = "znh",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    // test step
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/znh.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
