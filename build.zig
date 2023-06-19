const std = @import("std");
const Allocator = std.mem.Allocator;

const zigkmBuild = @import("deps/zigkm-common/build.zig");

fn stepPackage(self: *std.build.Step) !void
{
    _ = self;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Generating bigdata file archive...", .{});

    const genBigdataArgs = &[_][]const u8 {
        "./zig-out/tools/genbigdata", "./zig-out/server-temp/static", "./zig-out/server/static.bigdata",
    };
    if (zigkmBuild.utils.execCheckTermStdout(genBigdataArgs, allocator) == null) {
        return error.genbigdata;
    }
}

pub fn build(b: *std.build.Builder) !void
{
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const installDirServer = std.build.InstallDir {
        .custom = "server",
    };

    // const testing = b.addExecutable("testing", "src/testing.zig");
    // testing.setBuildMode(mode);
    // testing.setTarget(target);
    // zigkmBuild.addPackages(
    //     "deps/zigkm-common",
    //     &[_]zigkmBuild.Package {.app, .google, .zigimg},
    //     testing
    // );
    // testing.linkLibC();
    // testing.install();

    const server = b.addExecutable("yorstory", "src/server_main.zig");
    server.setBuildMode(mode);
    server.setTarget(target);
    zigkmBuild.addPackages(
        "deps/zigkm-common",
        &[_]zigkmBuild.Package {.app, .http_client, .http_server},
        server
    );
    server.linkLibC();
    server.override_dest_dir = installDirServer;
    server.install();

    const wasm = b.addSharedLibrary("main", "src/wasm_main.zig", .unversioned);
    wasm.setBuildMode(mode);
    wasm.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    zigkmBuild.addPackages("deps/zigkm-common", &[_]zigkmBuild.Package {.app}, wasm);
    wasm.linkLibC();
    wasm.override_dest_dir = installDirServer;
    wasm.install();

    const testSrcs = [_][]const u8 {
        "src/portfolio.zig",
        // "src/testing.zig",
    };
    const runTests = b.step("test", "Run tests");
    for (testSrcs) |testSrc| {
        const t = b.addTest(testSrc);
        t.setBuildMode(mode);
        t.setTarget(target);
        zigkmBuild.addPackages("deps/zigkm-common", &[_]zigkmBuild.Package {.app, .google, .math, .zigimg}, t);
        t.linkLibC();
        runTests.dependOn(&t.step);
    }
    // const testPortfolio = b.addTest("src/portfolio.zig");
    // testPortfolio.setBuildMode(mode);
    // testPortfolio.setTarget(target);
    // zigkmBuild.addPackages("deps/zigkm-common", &[_]zigkmBuild.Package {.math}, testPortfolio);
    // runTests.dependOn(&testPortfolio.step);

    const installDirTools = std.build.InstallDir {
        .custom = "tools",
    };
    // const genLut = b.addExecutable("gen_lut", "src/tools/gen_lut.zig");
    // genLut.setBuildMode(mode);
    // genLut.setTarget(target);
    // genLut.addPackagePath("png", "src/png.zig");
    // genLut.addIncludePath("deps/stb");
    // genLut.addCSourceFiles(&[_][]const u8{
    //     "deps/stb/stb_image_write_impl.c"
    // }, &[_][]const u8{"-std=c99"});
    // genLut.linkLibC();
    // genLut.override_dest_dir = installDirTools;
    // genLut.install();

    const genbigdata = try zigkmBuild.addGenBigdataExe("deps/zigkm-common", b, mode, target);
    genbigdata.override_dest_dir = installDirTools;
    genbigdata.install();

    const packageStep = b.step("package", "Package");
    packageStep.dependOn(b.getInstallStep());
    const installGenbigdataStep = b.addInstallArtifact(genbigdata);
    packageStep.dependOn(&installGenbigdataStep.step);
    packageStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = "deps/zigkm-common/src/app/static",
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);
    packageStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = "static",
        .install_dir = .{.custom = "server-temp/static"},
        .install_subdir = "",
    }).step);
    packageStep.dependOn(&b.addInstallDirectory(.{
        .source_dir = "scripts",
        .install_dir = .{.custom = "server"},
        .install_subdir = "scripts",
    }).step);
    packageStep.makeFn = stepPackage;
}
