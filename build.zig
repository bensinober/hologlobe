const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // const lodepng_translate_step = b.addTranslateC(.{
    //     .root_source_file = b.path("include/lodepng.h"),
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true, // Link with libc if your C code uses it
    // });

    // target x86_64
    const exe = b.addExecutable(.{
        .name = "hologlobe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.linkLibC();
    exe.linkSystemLibrary("gpiod");
    exe.linkSystemLibrary("ws2811");
    exe.addIncludePath(b.path("include"));

    _ = b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the x86_64 app");
    run_step.dependOn(&run_cmd.step);

    // target armv7
    const arm = b.addExecutable(.{
        .name = "hologlobe-armv7",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .gnueabihf,
            }),
            .optimize = optimize,
        }),
    });
    arm.linkLibC();
    arm.linkSystemLibrary("gpiod");
    arm.addLibraryPath(b.path("lib/armv7"));
    //arm.linkLibrary("ws2811");
    arm.addObjectFile(b.path("lib/armv7/libws2811.a"));
    arm.addIncludePath(b.path("include"));
    _ = b.installArtifact(arm);
    //zigcvMod.addCSourceFile(.{ .file = b.path("libs/asyncarray.cpp"), .flags = &[_][]const u8{"-Wall","-Wextra","-std=c++11", "-stdlib=libc++" } });

    // target aarch64
    const aarch = b.addExecutable(.{
        .name = "hologlobe-aarch64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            .optimize = optimize,
        }),
    });
    aarch.linkLibC();
    aarch.linkSystemLibrary("gpiod");
    aarch.addLibraryPath(b.path("lib/aarch64"));
    aarch.addObjectFile(b.path("lib/aarch64/libws2811.a"));
    aarch.addIncludePath(b.path("include"));
    _ = b.installArtifact(aarch);

    // Creates a step for unit testing.
    // const exe_tests = b.addTest(.{
    //     .root_module = exe,
    // });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}
