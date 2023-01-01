const std = @import("std");

const m = @import("math.zig");

pub const bindings = @import("wasm_bindings.zig");

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = scope;

    var buf: [2048]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, format, args) catch {
        const errMsg = "bufPrint failed for format: " ++ format;
        bindings.consoleMessage(true, &errMsg[0], errMsg.len);
        return;
    };

    const isError = switch (message_level) {
        .err, .warn => true, 
        .info, .debug => false,
    };
    bindings.consoleMessage(isError, &message[0], message.len);
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
