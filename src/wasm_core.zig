const root = @import("root");
const std = @import("std");

const bindings = @import("wasm_bindings.zig");
const input = @import("wasm_input.zig");
const m = @import("math.zig");

const StateType = if (@hasDecl(root, "State")) root.State else @compileError("no State type");

pub const Memory = struct {
    persistent: [128 * 1024]u8 align(8),
    transient: [64 * 1024]u8 align(8),

    const Self = @This();

    pub fn castPersistent(self: *Self, comptime T: type) *T
    {
        return @ptrCast(*T, &self.persistent[0]);
    }

    pub fn getTransientAllocator(self: *Self) std.heap.FixedBufferAllocator
    {
        return std.heap.FixedBufferAllocator.init(&self.transient);
    }
};

pub var _memory: *Memory align(8) = undefined;

fn buttonToClickType(button: c_int) input.ClickType
{
    return switch (button) {
        0 => input.ClickType.Left,
        1 => input.ClickType.Middle,
        2 => input.ClickType.Right,
        else => input.ClickType.Other,
    };
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    bindings.log(message_level, scope, format, args);
}

export fn onMouseMove(x: c_int, y: c_int) void
{
    var state = _memory.castPersistent(StateType);
    state.mouseState.pos = m.Vec2i.init(x, y);
}

export fn onMouseDown(button: c_int, x: c_int, y: c_int) void
{
    var state = _memory.castPersistent(StateType);
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), true);
}

export fn onMouseUp(button: c_int, x: c_int, y: c_int) void
{
    var state = _memory.castPersistent(StateType);
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), false);
}

export fn onKeyDown(keyCode: c_int) void
{
    var state = _memory.castPersistent(StateType);
    state.keyboardState.addKeyEvent(keyCode, true);
}