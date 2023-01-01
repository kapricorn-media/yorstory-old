const std = @import("std");

const png = @import("png");

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

    try png.writePngFile("lut.png", width, height, channels, width * channels, pixelData);
}