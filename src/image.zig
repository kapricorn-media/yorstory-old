const m = @import("math.zig");

pub const PixelData = struct {
	size: m.Vec2usize,
	channels: u8,
	data: []u8,
};

pub const PixelDataSlice = struct {
	topLeft: m.Vec2usize,
	size: m.Vec2usize,
};
