const std = @import("std");

const png = @import("png");
const image = png.image;
const m = png.m;

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.err("leaks!", .{});
        }
    }
    const allocator = gpa.allocator();

    var pixelData = image.PixelData {
        .size = m.Vec2usize.init(4096, 4096),
        .channels = 3,
        .data = undefined,
    };
    pixelData.data = try allocator.alloc(u8, pixelData.size.x * pixelData.size.y * pixelData.channels);
    defer allocator.free(pixelData.data);

    var y: usize = 0;
    while (y < pixelData.size.y) : (y += 1) {
        var x: usize = 0;
        while (x < pixelData.size.x) : (x += 1) {
            const ind = (y * pixelData.size.x + x) * pixelData.channels;
            const invY = pixelData.size.y - y - 1;
            pixelData.data[ind + 0] = @intCast(u8, x % 256);
            pixelData.data[ind + 1] = @intCast(u8, invY % 256);
            pixelData.data[ind + 2] = @intCast(u8, (x / 256) + (invY / 256) * 16);
        }
    }

    const slice = image.PixelDataSlice {
        .topLeft = m.Vec2usize.zero,
        .size = pixelData.size,
    };
    try png.writePngFile("lut.png", pixelData, slice);
}