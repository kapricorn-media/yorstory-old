const builtin = @import("builtin");
const std = @import("std");

const bigdata = @import("bigdata");

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
            std.log.err("leaks!", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const argsReq = 2;
    if (args.len != argsReq) {
        std.log.err("Expected {} args, got {}", .{argsReq, args.len});
        return error.BadArgs;
    }

    const dirPath = args[1];
    std.log.info("generating bigdata from directory {s}", .{dirPath});
    const data = try bigdata.generate(dirPath, allocator);
    defer allocator.free(data);

    var file = try std.fs.cwd().createFile("file.bigdata", .{});
    defer file.close();
    try file.writeAll(data);

    std.log.info("bigdata {} bytes", .{data.len});

    var map = std.StringHashMap([]const u8).init(allocator);
    defer map.deinit();
    try bigdata.load(data, &map);
    var it = map.iterator();
    while (it.next()) |kv| {
        std.log.info("{s} - {}", .{kv.key_ptr.*, kv.value_ptr.len});
    }
}