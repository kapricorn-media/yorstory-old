const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const bigdata = app.bigdata;

pub usingnamespace app.exports;
pub usingnamespace @import("zigkm-stb").exports; // for stb linking

const drive = @import("drive.zig");

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.err("GPA detected leaks", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len != 3) {
        std.log.err("Expected arguments: <api-key> <existing-bigdata>", .{});
        return error.BadArgs;
    }

    const key = args[1];
    const existingPath = args[2];
    var data: bigdata.Data = undefined;
    try data.loadFromFile(existingPath, allocator);
    defer data.deinit();

    const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
    try drive.fillFromGoogleDrive(folderId, &data, key, allocator);
}
