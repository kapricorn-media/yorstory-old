const std = @import("std");

const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const StbCallbackData = struct {
    fail: bool,
    writer: std.fs.File.Writer,
};

fn stbCallback(context: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void
{
    const cbData = @ptrCast(*StbCallbackData, @alignCast(@alignOf(*StbCallbackData), context));
    if (cbData.fail) {
        return;
    }

    const dataPtr = data orelse {
        cbData.fail = true;
        return;
    };
    const dataU = @ptrCast([*]u8, dataPtr);
    cbData.writer.writeAll(dataU[0..@intCast(usize, size)]) catch {
        cbData.fail = true;
    };
}

fn writePngFile(filePath: []const u8, width: usize, height: usize, channels: u8, stride: usize, data: []const u8) !void
{
    const cwd = std.fs.cwd();
    const file = try cwd.createFile(filePath, .{});
    defer file.close();

    var cbData = StbCallbackData {
        .fail = false,
        .writer = file.writer(),
    };
    const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, @intCast(c_int, width), @intCast(c_int, height), @intCast(c_int, channels), &data[0], @intCast(c_int, stride));
    if (writeResult == 0) {
        return error.stbWriteFail;
    }
    if (cbData.fail) {
        return error.stbWriteCallbackFail;
    }
}

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.err("leaks!", .{});
        }
    }
    const allocator = gpa.allocator();

    const width = 4096;
    const height = 4096;
    const channels = 3;

    var pixelData = try allocator.alloc(u8, width * height * channels);
    defer allocator.free(pixelData);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const ind = (y * width + x) * channels;
            const invY = height - y - 1;
            pixelData[ind + 0] = @intCast(u8, x % 256);
            pixelData[ind + 1] = @intCast(u8, invY % 256);
            pixelData[ind + 2] = @intCast(u8, (x / 256) + (invY / 256) * 16);
        }
    }

    try writePngFile("lut.png", width, height, channels, width * channels, pixelData);
}