const root = @import("root");
const std = @import("std");

const input = @import("wasm_input.zig");
const m = @import("math.zig");
const wasm_asset = @import("wasm_asset.zig");
const wasm_bindings = @import("wasm_bindings.zig");

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

export fn onInit(width: c_uint, height: c_uint) ?*Memory
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

    const screenSize = m.Vec2usize.init(width, height);
    state.load(remaining, screenSize) catch |err| {
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

export fn onDeviceOrientation(memory: *Memory, alpha: f32, beta: f32, gamma: f32) void
{
    var state = memory.castPersistent(StateType);
    state.deviceState.angles.x = alpha;
    state.deviceState.angles.y = beta;
    state.deviceState.angles.z = gamma;
}

export fn onTextureLoaded(memory: *Memory, textureId: c_uint, width: c_int, height: c_int) void
{
    var state = memory.castPersistent(StateType);
    state.assets.onTextureLoaded(textureId, m.Vec2i.init(width, height)) catch |err| {
        std.log.err("onTextureLoaded error {}", .{err});
    };
}

export fn onFontLoaded(memory: *Memory, atlasTextureId: c_uint, fontDataLen: c_uint) void
{
    var transientAllocator = memory.getTransientAllocator();
    const allocator = transientAllocator.allocator();

    const alignment = @alignOf(wasm_asset.FontLoadData);
    var fontDataBuf = allocator.allocWithOptions(u8, fontDataLen, alignment, null) catch {
        std.log.err("Failed to allocate fontDataBuf", .{});
        return;
    };
    if (wasm_bindings.fillDataBuffer(&fontDataBuf[0], fontDataBuf.len) != 1) {
        std.log.err("fillDataBuffer failed", .{});
        return;
    }
    if (fontDataBuf.len != @sizeOf(wasm_asset.FontLoadData)) {
        std.log.err("FontLoadData size mismatch", .{});
        return;
    }
    const fontData = @ptrCast(*wasm_asset.FontLoadData, fontDataBuf.ptr);

    var state = memory.castPersistent(StateType);
    state.assets.onFontLoaded(atlasTextureId, fontData) catch |err| {
        std.log.err("onFontLoaded error {}", .{err});
    };
}
