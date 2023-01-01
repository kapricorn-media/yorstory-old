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

pub fn writePngFile(filePath: []const u8, width: usize, height: usize, channels: u8, stride: usize, data: []const u8) !void
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
