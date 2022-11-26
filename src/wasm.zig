const std = @import("std");

const m = @import("math.zig");

pub const bindings = @import("wasm_bindings.zig");

pub fn consoleMessage(isError: bool, message: []const u8) void
{
    bindings.consoleMessage(isError, &message[0], message.len);
}

pub const clearAllText = bindings.clearAllText();

pub fn addTextLine(text: []const u8, topLeft: m.Vec2i, fontSize: i32, hexColor: []const u8,
    fontFamily: []const u8) void
{
    bindings.addTextLine(&text[0], text.len, topLeft.x, topLeft.y, fontSize, &hexColor[0], hexColor.len, &fontFamily[0], fontFamily.len);
}

pub fn setCursor(cursor: []const u8) void
{
    bindings.setCursor(&cursor[0], cursor.len);
}

pub fn getUri(outUri: []u8) usize
{
    return bindings.getUri(&outUri[0], outUri.len);
}

pub fn setUri(uri: []const u8) void
{
    bindings.setUri(&uri[0], uri.len);
}
