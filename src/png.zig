const std = @import("std");

const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

// TODO these are pub because eh
pub const image = @import("image.zig");
pub const m = @import("math.zig");

pub fn writePngFile(filePath: []const u8, data: image.PixelData, slice: image.PixelDataSlice) !void
{
    const cwd = std.fs.cwd();
    const file = try cwd.createFile(filePath, .{});
    defer file.close();

    var cbData = StbCallbackData {
        .fail = false,
        .writer = file.writer(),
    };
    const startIndPixels = slice.topLeft.y * data.size.x + slice.topLeft.x;
    const startIndBytes = startIndPixels * data.channels;
    const stride = data.size.x * data.channels;
    const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, @intCast(c_int, slice.size.x), @intCast(c_int, slice.size.y), @intCast(c_int, data.channels), &data.data[startIndBytes], @intCast(c_int, @intCast(c_int, stride)));
    if (writeResult == 0) {
        return error.stbWriteFail;
    }
    if (cbData.fail) {
        return error.stbWriteCallbackFail;
    }
}

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
