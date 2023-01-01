const std = @import("std");
const Allocator = std.mem.Allocator;

const zig_bearssl_build = @import("deps/zig-bearssl/build.zig");
const zig_http_build = @import("deps/zig-http/build.zig");

const PROJECT_NAME = "yorstory";

fn isTermOk(term: std.ChildProcess.Term) bool
{
    switch (term) {
        std.ChildProcess.Term.Exited => |value| {
            return value == 0;
        },
        else => {
            return false;
        }
    }
}

fn checkTermStdout(execResult: std.ChildProcess.ExecResult) ?[]const u8
{
    const ok = isTermOk(execResult.term);
    if (!ok) {
        std.log.err("{}", .{execResult.term});
        if (execResult.stdout.len > 0) {
            std.log.info("{s}", .{execResult.stdout});
        }
        if (execResult.stderr.len > 0) {
            std.log.err("{s}", .{execResult.stderr});
        }
        return null;
    }
    return execResult.stdout;
}

fn execCheckTermStdoutWd(argv: []const []const u8, cwd: ?[]const u8, allocator: Allocator) ?[]const u8
{
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd
    }) catch |err| {
        std.log.err("exec error: {}", .{err});
        return null;
    };
    return checkTermStdout(result);
}

fn execCheckTermStdout(argv: []const []const u8, allocator: Allocator) ?[]const u8
{
    return execCheckTermStdoutWd(argv, null, allocator);
}

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
    if (execCheckTermStdout(genBigdataArgs, allocator) == null) {
        return error.aapt2CompileError;
    }
}

pub fn build(b: *std.build.Builder) void
{
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const isDebug = mode == .Debug;

    const installDirRoot = std.build.InstallDir {
        .custom = "",
    };

    const server = b.addExecutable(PROJECT_NAME, "src/server_main.zig");
    server.setBuildMode(mode);
    server.setTarget(target);
    const configSrc = if (isDebug) "src/config_debug.zig" else "src/config_release.zig";
    server.addPackagePath("config", configSrc);
    server.addPackagePath("png", "src/png.zig");
    zig_bearssl_build.addLib(server, target, "deps/zig-bearssl");
    zig_http_build.addLibClient(server, target, "deps/zig-http");
    zig_http_build.addLibCommon(server, target, "deps/zig-http");
    zig_http_build.addLibServer(server, target, "deps/zig-http");
    server.override_dest_dir = installDirRoot;
    server.install();

    const wasm = b.addSharedLibrary(PROJECT_NAME, "src/wasm_main.zig", .unversioned);
    wasm.setBuildMode(mode);
    wasm.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    wasm.addIncludePath("deps/stb");
    wasm.addCSourceFiles(&[_][]const u8{
        "deps/stb/stb_rect_pack_impl.c",
        "deps/stb/stb_truetype_impl.c",
    }, &[_][]const u8{"-std=c99"});
    wasm.linkLibC();
    wasm.override_dest_dir = installDirRoot;
    wasm.install();

    const wasmWorker = b.addSharedLibrary("worker", "src/wasm_workermain.zig", .unversioned);
    wasmWorker.setBuildMode(mode);
    wasmWorker.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    wasmWorker.addIncludePath("deps/stb");
    wasmWorker.addCSourceFiles(&[_][]const u8{
        "deps/stb/stb_rect_pack_impl.c",
        "deps/stb/stb_truetype_impl.c",
    }, &[_][]const u8{"-std=c99"});
    wasmWorker.linkLibC();
    wasmWorker.override_dest_dir = installDirRoot;
    wasmWorker.install();

    if (!isDebug) {
        const installDirScripts = std.build.InstallDir {
            .custom = "scripts",
        };
        b.installDirectory(.{
            .source_dir = "scripts",
            .install_dir = installDirScripts,
            .install_subdir = "",
        });
    }

    const runTests = b.step("test", "Run tests");
    const testSrcs = [_][]const u8 {
        "src/bigdata.zig",
        "src/math.zig",
    };
    for (testSrcs) |src| {
        const tests = b.addTest(src);
        tests.setBuildMode(mode);
        tests.setTarget(target);
        zig_bearssl_build.addLib(tests, target, "deps/zig-bearssl");
        zig_http_build.addLibClient(tests, target, "deps/zig-http");
        zig_http_build.addLibCommon(tests, target, "deps/zig-http");
        tests.linkLibC();
        runTests.dependOn(&tests.step);
    }

    const installDirTools = std.build.InstallDir {
        .custom = "tools",
    };
    const genLut = b.addExecutable("gen_lut", "src/tools/gen_lut.zig");
    genLut.setBuildMode(mode);
    genLut.setTarget(target);
    genLut.addPackagePath("png", "src/png.zig");
    genLut.addIncludePath("deps/stb");
    genLut.addCSourceFiles(&[_][]const u8{
        "deps/stb/stb_image_write_impl.c"
    }, &[_][]const u8{"-std=c99"});
    genLut.linkLibC();
    genLut.override_dest_dir = installDirTools;
    genLut.install();

    const genBigdata = b.addExecutable("gen_bigdata", "src/tools/gen_bigdata.zig");
    genBigdata.setBuildMode(mode);
    genBigdata.setTarget(target);
    genBigdata.addPackagePath("bigdata", "src/bigdata.zig");
    genBigdata.addIncludePath("deps/stb");
    genBigdata.addCSourceFiles(&[_][]const u8{
        "deps/stb/stb_image_impl.c",
        "deps/stb/stb_image_write_impl.c",
    }, &[_][]const u8{"-std=c99"});
    genBigdata.linkLibC();
    genBigdata.override_dest_dir = installDirTools;
    genBigdata.install();

    const package = b.step("package", "Package");
    package.dependOn(b.getInstallStep());
    package.makeFn = stepPackage;
}
