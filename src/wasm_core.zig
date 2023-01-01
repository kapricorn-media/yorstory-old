const root = @import("root");
const std = @import("std");

const bindings = @import("wasm_bindings.zig");
const input = @import("wasm_input.zig");
const m = @import("math.zig");

const StateType = if (@hasDecl(root, "State")) root.State else @compileError("no State type");

pub const Memory = struct {
    persistent: [128 * 1024]u8 align(8),
    transient: [256 * 1024 * 1024]u8 align(8),

    const Self = @This();

    pub fn castPersistent(self: *Self, comptime T: type) *T
    {
        return @ptrCast(*T, &self.persistent);
    }

    pub fn getTransientAllocator(self: *Self) std.heap.FixedBufferAllocator
    {
        return std.heap.FixedBufferAllocator.init(&self.transient);
    }
};

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

export fn onInit() ?*Memory
{
    std.log.info("onInit", .{});

    var memory = std.heap.page_allocator.create(Memory) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return null;
    };
    var memoryBytes = std.mem.asBytes(memory);
    std.mem.set(u8, memoryBytes, 0);

    var state = memory.castPersistent(StateType);
    const stateSize = @sizeOf(StateType);
    var remaining = memory.persistent[stateSize..];
    std.log.info("memory - {*}\npersistent store - {} ({} state | {} remaining)\ntransient store - {}\ntotal - {}\nWASM pages - {}", .{memory, memory.persistent.len, stateSize, remaining.len, memory.transient.len, memoryBytes.len, @wasmMemorySize(0)});

    state.load(remaining) catch |err| {
        std.log.err("State init failed, err {}", .{err});
        return null;
    };

    return memory;
}

export fn onMouseMove(memory: *Memory, x: c_int, y: c_int) void
{
    var state = memory.castPersistent(StateType);
    state.mouseState.pos = m.Vec2i.init(x, y);
}

export fn onMouseDown(memory: *Memory, button: c_int, x: c_int, y: c_int) void
{
    var state = memory.castPersistent(StateType);
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), true);
}

export fn onMouseUp(memory: *Memory, button: c_int, x: c_int, y: c_int) void
{
    var state = memory.castPersistent(StateType);
    state.mouseState.addClickEvent(m.Vec2i.init(x, y), buttonToClickType(button), false);
}

export fn onKeyDown(memory: *Memory, keyCode: c_int) void
{
    var state = memory.castPersistent(StateType);
    state.keyboardState.addKeyEvent(keyCode, true);
}

export fn onTextureLoaded(memory: *Memory, textureId: c_uint, width: c_int, height: c_int) void
{
    std.log.info("onTextureLoaded {}: {} x {}", .{textureId, width, height});

    var state = memory.castPersistent(StateType);
    state.assets.onTextureLoaded(textureId, m.Vec2i.init(width, height)) catch |err| {
        std.log.err("onTextureLoaded error {}", .{err});
    };
}

// for stb library link

export fn stb_zig_malloc(size: usize, userData: ?*anyopaque) ?*anyopaque
{
    _ = userData;

    var allocator = std.heap.page_allocator;
    const result = allocator.alloc(u8, size) catch |err| {
        std.log.err("stb_zig_malloc failed with err={} for size={}", .{err, size});
        return null;
    };
    return &result[0];
}

export fn stb_zig_free(ptr: ?*anyopaque, userData: ?*anyopaque) void
{
    _ = ptr; _ = userData;
    // no size = no free. yolo!
}

export fn stb_zig_assert(expression: c_int) void
{
    std.debug.assert(expression != 0);
}

export fn stb_zig_strlen(str: [*c]const i8) usize
{
    return std.mem.len(str);
}

export fn stb_zig_memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque
{
    if (dest) |d| {
        if (src) |s| {
            const dSlice = (@ptrCast([*]u8, d))[0..n];
            const sSlice = (@ptrCast([*]const u8, s))[0..n];
            std.mem.copy(u8, dSlice, sSlice);
        }
    }
    return dest;
}

export fn stb_zig_memset(str: ?*anyopaque, c: c_int, n: usize) ?*anyopaque
{
    if (str) |s| {
        const sSlice = (@ptrCast([*]u8, s))[0..n];
        std.mem.set(u8, sSlice, @intCast(u8, c));
    }
    return str;
}

