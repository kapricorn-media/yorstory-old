const std = @import("std");
const Allocator = std.mem.Allocator;

const zigBearsslBuild = @import("deps/zig-bearssl/build.zig");
const zigHttpBuild = @import("deps/zig-http/build.zig");
const zigkmCommonBuild = @import("deps/zigkm-common/build.zig");

fn stepPackage(self: *std.build.Step) !void
{
    _ = self;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Generating bigdata file archive...", .{});

    const genBigdataArgs = &[_][]const u8 {
        "./zig-out/tools/gen_bigdata", "./static", "./zig-out/static.bigdata",
    };
    if (zigkmCommonBuild.utils.execCheckTermStdout(genBigdataArgs, allocator) == null) {
        return error.aapt2CompileError;
    }
}

pub fn build(b: *std.build.Builder) !void
{
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const installDirServer = std.build.InstallDir {
        .custom = "server",
    };

    const server = b.addExecutable("yorstory", "src/server_main.zig");
    server.setBuildMode(mode);
    server.setTarget(target);
    zigBearsslBuild.addLib(server, target, "deps/zig-bearssl");
    try zigHttpBuild.addLibCommon(server, target, "deps/zig-http");
    try zigHttpBuild.addLibServer(server, target, "deps/zig-http");
    zigkmCommonBuild.addAllPackages("deps/zigkm-common", server);
    server.linkLibC();
    server.override_dest_dir = installDirServer;
    server.install();

    const wasm = b.addSharedLibrary("main", "src/wasm_main.zig", .unversioned);
    wasm.setBuildMode(mode);
    wasm.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    zigkmCommonBuild.addAllPackages("deps/zigkm-common", wasm);
    wasm.linkLibC();
    wasm.override_dest_dir = installDirServer;
    wasm.install();

    // const wasm = b.addSharedLibrary("main", "src/wasm_main.zig", .unversioned);
    // wasm.setBuildMode(mode);
    // wasm.setTarget(.{
    //     .cpu_arch = .wasm32,
    //     .os_tag = .freestanding,
    // });
    // wasm.addIncludePath("deps/stb");
    // wasm.addCSourceFiles(&[_][]const u8{
    //     "deps/stb/stb_rect_pack_impl.c",
    //     "deps/stb/stb_truetype_impl.c",
    // }, &[_][]const u8{"-std=c99"});
    // wasm.linkLibC();
    // wasm.override_dest_dir = installDirServer;
    // wasm.install();

    // const wasmWorker = b.addSharedLibrary("worker", "src/wasm_workermain.zig", .unversioned);
    // wasmWorker.setBuildMode(mode);
    // wasmWorker.setTarget(.{
    //     .cpu_arch = .wasm32,
    //     .os_tag = .freestanding,
    // });
    // wasmWorker.addIncludePath("deps/stb");
    // wasmWorker.addCSourceFiles(&[_][]const u8{
    //     "deps/stb/stb_rect_pack_impl.c",
    //     "deps/stb/stb_truetype_impl.c",
    // }, &[_][]const u8{"-std=c99"});
    // wasmWorker.linkLibC();
    // wasmWorker.override_dest_dir = installDirServer;
    // wasmWorker.install();

    const runTests = b.step("test", "Run tests");
    const testSrcs = [_][]const u8 {
        "src/bigdata.zig",
        "src/math.zig",
    };
    for (testSrcs) |src| {
        const tests = b.addTest(src);
        tests.setBuildMode(mode);
        tests.setTarget(target);
        zigBearsslBuild.addLib(tests, target, "deps/zig-bearssl");
        try zigHttpBuild.addLibClient(tests, target, "deps/zig-http");
        try zigHttpBuild.addLibCommon(tests, target, "deps/zig-http");
        tests.linkLibC();
        runTests.dependOn(&tests.step);
    }

    // const installDirTools = std.build.InstallDir {
    //     .custom = "tools",
    // };
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

    // const genBigdata = b.addExecutable("gen_bigdata", "src/tools/gen_bigdata.zig");
    // genBigdata.setBuildMode(mode);
    // genBigdata.setTarget(target);
    // genBigdata.addPackagePath("bigdata", "src/bigdata.zig");
    // genBigdata.addIncludePath("deps/stb");
    // genBigdata.addCSourceFiles(&[_][]const u8{
    //     "deps/stb/stb_image_impl.c",
    //     "deps/stb/stb_image_write_impl.c",
    // }, &[_][]const u8{"-std=c99"});
    // genBigdata.linkLibC();
    // genBigdata.override_dest_dir = installDirTools;
    // genBigdata.install();

    const package = b.step("package", "Package");
    package.dependOn(b.getInstallStep());
    package.makeFn = stepPackage;
}
