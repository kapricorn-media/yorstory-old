const std = @import("std");

const m = @import("math.zig");
const wasm = @import("wasm.zig");
const wasm_asset = @import("wasm_asset.zig");
const wasm_bindings = @import("wasm_bindings.zig");
const wasm_core = @import("wasm_core.zig");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

pub const log = wasm_core.log;
usingnamespace wasm_core;

fn loadFontDataInternal(atlasSize: c_int, fontDataLen: c_uint, fontSize: f32) !void
{
    std.log.info("loadFontData atlasSize={} fontSize={}", .{atlasSize, fontSize});

    var arenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();

    var fontDataBuf = try allocator.alloc(u8, fontDataLen);
    if (wasm_bindings.fillDataBuffer(&fontDataBuf[0], fontDataBuf.len) != 1) {
        return error.FillDataBuffer;
    }

    var fontData = try allocator.create(wasm_asset.FontLoadData);
    const pixelBytes = try fontData.load(@intCast(usize, atlasSize), fontDataBuf, fontSize, allocator);

    if (wasm_bindings.addReturnValueBuf(&pixelBytes[0], pixelBytes.len) != 1) {
        return error.AddReturnValue;
    }
    const fontDataBytes = std.mem.asBytes(fontData);
    if (wasm_bindings.addReturnValueBuf(&fontDataBytes[0], fontDataBytes.len) != 1) {
        return error.AddReturnValue;
    }
}

// Returns 1 on success, 0 on failure
export fn loadFontData(atlasSize: c_int, fontDataLen: c_uint, fontSize: f32) c_int
{
    loadFontDataInternal(atlasSize, fontDataLen, fontSize) catch |err| {
        std.log.err("loadFontData failed err={}", .{err});
        return 0;
    };
    return 1;
}
