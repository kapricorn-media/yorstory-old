const std = @import("std");

const m = @import("math.zig");

pub const ImageDataFormat = enum(u8) {
    Raw       = 0,
    RLE       = 1,
    ZipNoPred = 2,
    ZipPred   = 3,
};

pub const LayerBlendMode = enum {
    Normal,
    Multiply,
};

pub const LayerChannelId = enum(i16) {
    UserMask = -2,
    Alpha    = -1,
    Red      = 0,
    Green    = 1,
    Blue     = 2,
};

pub const LayerChannelData = struct {
    id: LayerChannelId,
    dataFormat: ImageDataFormat,
    data: []const u8,
};

pub const LayerData = struct {
    name: []const u8,
    topLeft: m.Vec2i,
    size: m.Vec2i,
    opacity: u8,
    blendMode: ?LayerBlendMode,
    visible: bool,
    channels: []LayerChannelData,
};

pub const PixelData = struct {
    topLeft: m.Vec2i,
    size: m.Vec2i,
    channels: u8,
    data: []u8,
};

pub const PsdFile = struct {
    allocator: std.mem.Allocator,
    canvasSize: m.Vec2i,
    data: []const u8,
    layers: []LayerData,

    const Self = @This();

    pub fn load(self: *Self, data: []const u8, allocator: std.mem.Allocator) !void
    {
        self.allocator = allocator;
        self.data = data;

        var reader = Reader.init(data);

        // section: header
        const headerRaw = try reader.readStruct(HeaderRaw);
        var header: Header = undefined;
        header.load(headerRaw);

        if (!std.mem.eql(u8, &header.signature, "8BPS")) {
            return error.InvalidSignature;
        }

        if (header.version != 1) {
            return error.InvalidVersion;
        }
        if (header.depth != 8) {
            return error.UnsupportedColorDepth;
        }

        const colorModeRgb = 3;
        if (header.colorMode != colorModeRgb) {
            return error.UnsupportedColorMode;
        }

        self.canvasSize = m.Vec2i.init(header.width, header.height);

        // section: color mode data
        const colorModeData = try reader.readLengthAndBytes(u32);
        _ = colorModeData;

        // section: image resources
        const imageResources = try reader.readLengthAndBytes(u32);
        _ = imageResources;

        // section: layer and mask information
        const layerMaskInfoIndexBefore = reader.index;
        const layerMaskInfo = try reader.readLengthAndBytes(u32);
        if (layerMaskInfo.len > 0) {
            var layerMaskInfoReader = Reader.init(layerMaskInfo);
            const layersInfoLength = try layerMaskInfoReader.readInt(u32);
            _ = layersInfoLength;

            var layerCountSigned = try layerMaskInfoReader.readInt(i16);
            const layerCount: u32 = if (layerCountSigned < 0) @intCast(u32, -layerCountSigned) else @intCast(u32, layerCountSigned);
            self.layers = try allocator.alloc(LayerData, layerCount);

            for (self.layers) |*layer| {
                const top = try layerMaskInfoReader.readInt(i32);
                const left = try layerMaskInfoReader.readInt(i32);
                const bottom = try layerMaskInfoReader.readInt(i32);
                const right = try layerMaskInfoReader.readInt(i32);
                layer.topLeft = m.Vec2i.init(left, top);
                layer.size = m.Vec2i.init(right - left, bottom - top);

                const channels = try layerMaskInfoReader.readInt(u16);
                layer.channels = try allocator.alloc(LayerChannelData, channels);
                for (layer.channels) |*c| {
                    const idInt = try layerMaskInfoReader.readInt(i16);
                    const size = try layerMaskInfoReader.readInt(u32);
                    const id = std.meta.intToEnum(LayerChannelId, idInt) catch |err| {
                        std.log.err("Unknown channel ID {}", .{idInt});
                        return err;
                    };
                    if (size < @sizeOf(u16)) {
                        return error.BadChannelSize;
                    }
                    c.* = LayerChannelData {
                        .id = id,
                        .dataFormat = .Raw,
                        .data = undefined,
                    };
                    c.data.len = size - @sizeOf(u16);
                }

                const LayerMaskData2 = extern struct {
                    blendModeSignature: [4]u8,
                    blendModeKey: [4]u8,
                    opacity: u8,
                    clipping: u8,
                    flags: u8,
                    zero: u8,
                };

                const layerMaskData2 = try layerMaskInfoReader.readStruct(LayerMaskData2);
                if (!std.mem.eql(u8, &layerMaskData2.blendModeSignature, "8BIM")) {
                    return error.InvalidBlendModeSignature;
                }
                layer.opacity = layerMaskData2.opacity;
                layer.blendMode = stringToBlendMode(&layerMaskData2.blendModeKey);
                layer.visible = (layerMaskData2.flags & 0b00000010) == 0;

                layer.name = "";
                const extraData = try layerMaskInfoReader.readLengthAndBytes(u32);
                if (extraData.len > 0) {
                    var extraDataReader = Reader.init(extraData);
                    const maskAdjustmentData = try extraDataReader.readLengthAndBytes(u32);
                    _ = maskAdjustmentData;
                    const blendRangeData = try extraDataReader.readLengthAndBytes(u32);
                    _ = blendRangeData;
                    layer.name = try extraDataReader.readPascalString();
                }
            }

            for (self.layers) |*layer| {
                for (layer.channels) |*c| {
                    const formatInt = try layerMaskInfoReader.readInt(i16);
                    const format = std.meta.intToEnum(ImageDataFormat, formatInt) catch |err| {
                        std.log.err("Unknown data format {}", .{formatInt});
                        return err;
                    };
                    c.dataFormat = format;
                    const dataStart = layerMaskInfoIndexBefore + @sizeOf(u32) + layerMaskInfoReader.index;
                    const dataEnd = dataStart + c.data.len;
                    c.data = data[dataStart..dataEnd];

                    if (!layerMaskInfoReader.hasRemaining(c.data.len)) {
                        return error.OutOfBounds;
                    }
                    layerMaskInfoReader.index += c.data.len;
                }
            }
        }

        // section: image data
        const imageData = reader.remainingBytes();
        _ = imageData;
    }

    pub fn deinit(self: *Self) void
    {
        for (self.layers) |layer| {
            self.allocator.free(layer.channels);
        }
        self.allocator.free(self.layers);
    }

    pub fn getLayerPixelDataRect(self: *Self, layerIndex: usize, topLeft: m.Vec2i, size: m.Vec2i, channel: ?LayerChannelId, allocator: std.mem.Allocator) !PixelData
    {
        const layer = self.layers[layerIndex];

        var pixelData = blk: {
            const topLeftActual = m.max(topLeft, layer.topLeft);
            const bottomRight = m.min(m.add(topLeft, size), m.add(layer.topLeft, layer.size));
            var sizeActual = m.sub(bottomRight, topLeftActual);
            sizeActual = m.max(sizeActual, m.Vec2i.zero);
            break :blk PixelData {
                .topLeft = topLeftActual,
                .size = sizeActual,
                .channels = if (channel == null) 4 else 1, // TODO maybe not 4
                .data = undefined,
            };
        };

        const numBytes = @intCast(usize, pixelData.size.x) * @intCast(usize, pixelData.size.y) * pixelData.channels;
        pixelData.data = try allocator.alloc(u8, numBytes);

        for (layer.channels) |c| {
            if (channel) |cc| {
                if (cc != c.id) {
                    continue;
                }
            }

            var channelOffset: usize = blk: {
                if (channel == null) {
                    break :blk switch (c.id) {
                        .Red => 0,
                        .Green => 1,
                        .Blue => 2,
                        .Alpha => 3,
                        else => continue,
                    };
                } else {
                    break :blk 0;
                }
            };

            switch (c.dataFormat) {
                .Raw => readPixelDataRaw(&pixelData, channelOffset, layer.topLeft, layer.size, c.data),
                .RLE => try readPixelDataLRE(&pixelData, channelOffset, layer.topLeft, layer.size, c.data),
                else => return error.UnsupportedDataFormat,
            }
        }

        return pixelData;
    }

    pub fn getLayerPixelData(self: *Self, layerIndex: usize, channel: ?LayerChannelId, allocator: std.mem.Allocator) !PixelData
    {
        const layer = self.layers[layerIndex];
        return self.getLayerPixelDataRect(layerIndex, layer.topLeft, layer.size, channel, allocator);
    }
};

fn readPixelDataRaw(pixelData: *PixelData, channelOffset: usize, layerTopLeft: m.Vec2i, layerSize: m.Vec2i, data: []const u8) void
{
    const layerWidth = @intCast(usize, layerSize.x);
    const layerOffsetX = @intCast(usize, pixelData.topLeft.x - layerTopLeft.x);
    const layerOffsetY = @intCast(usize, pixelData.topLeft.y - layerTopLeft.y);
    const width = @intCast(usize, pixelData.size.x);
    const height = @intCast(usize, pixelData.size.y);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const inIndex = (layerOffsetY + y) * layerWidth + layerOffsetX + x;
            const outIndex = (y * width + x) * pixelData.channels + channelOffset;
            pixelData.data[outIndex] = data[inIndex];
        }
    }
}

fn readRowLength(rowLengths: []const u8, row: usize) u16
{
    return std.mem.readIntBig(u16, &rowLengths[row * @sizeOf(u16)]);
}

fn readPixelDataLRE(pixelData: *PixelData, channelOffset: usize, layerTopLeft: m.Vec2i, layerSize: m.Vec2i, data: []const u8) !void
{
    const layerWidth = @intCast(usize, layerSize.x);
    const layerHeight = @intCast(usize, layerSize.y);

    const rowLengthsN = layerHeight * @sizeOf(u16);
    if (rowLengthsN > data.len) {
        return error.OutOfBounds;
    }
    const rowLengths = data[0..rowLengthsN];

    const offsetX = @intCast(usize, pixelData.topLeft.x - layerTopLeft.x);
    const offsetY = @intCast(usize, pixelData.topLeft.y - layerTopLeft.y);
    const width = @intCast(usize, pixelData.size.x);
    const height = @intCast(usize, pixelData.size.y);

    var remaining = data[rowLengthsN..];
    var y: usize = 0;
    while (y < layerHeight) : (y += 1) {
        const rowLength = readRowLength(rowLengths, y);
        const rowData = remaining[0..rowLength];
        remaining = remaining[rowLength..];

        const yOut = if (y >= offsetY) y - offsetY else continue;
        if (yOut >= height) continue;

        // Parse data in PackBits format
        // https://en.wikipedia.org/wiki/PackBits
        var x: usize = 0;
        var rowInd: usize = 0;
        while (true) {
            if (rowInd >= rowData.len) {
                break;
            }
            const header = @bitCast(i8, rowData[rowInd]);
            rowInd += 1;

            if (header == -128) {
                continue;
            } else if (header < 0) {
                if (rowInd >= rowData.len) {
                    return error.BadRowData;
                }
                const byte = rowData[rowInd];
                rowInd += 1;
                const repeats = 1 - @intCast(i16, header);
                var i: usize = 0;
                while (i < repeats) : ({i += 1; x += 1;}) {
                    const xOut = if (x >= offsetX) x - offsetX else continue;
                    if (xOut >= width) continue;
                    const outIndex = (yOut * width + xOut) * pixelData.channels + channelOffset;
                    pixelData.data[outIndex] = byte;
                }
            } else if (header >= 0) {
                const n = 1 + @intCast(u16, header);
                if (rowInd + n > rowData.len) {
                    return error.BadRowData;
                }

                var i: usize = 0;
                while (i < n) : ({i += 1; x += 1;}) {
                    const byte = rowData[rowInd + i];
                    const xOut = if (x >= offsetX) x - offsetX else continue;
                    if (xOut >= width) continue;
                    const outIndex = (yOut * width + xOut) * pixelData.channels + channelOffset;
                    pixelData.data[outIndex] = byte;
                }
                rowInd += n;
            }
        }

        if (x != layerWidth) {
            std.log.err("row width mismatch x={} layerWidth={}", .{x, layerWidth});
            return error.RowWidthMismatch;
        }
    }
}

fn stringToBlendMode(str: []const u8) ?LayerBlendMode
{
    const map = std.ComptimeStringMap(LayerBlendMode, .{
        .{ "norm", .Normal },
        .{ "mul ", .Multiply },
    });
    return map.get(str);
}

const HeaderRaw = extern struct {
    signature: [4]u8,
    version: [2]u8,
    reserved: [6]u8,
    channels: [2]u8,
    height: [4]u8,
    width: [4]u8,
    depth: [2]u8,
    colorMode: [2]u8,
};

const Header = struct {
    signature: [4]u8,
    version: u16,
    reserved: [6]u8,
    channels: u16,
    height: i32,
    width: i32,
    depth: u16,
    colorMode: u16,

    fn load(self: *Header, raw: *const HeaderRaw) void
    {
        self.signature = raw.signature;
        self.version = std.mem.readIntBig(u16, &raw.version);
        self.reserved = raw.reserved;
        self.channels = std.mem.readIntBig(u16, &raw.channels);
        self.height = std.mem.readIntBig(i32, &raw.height);
        self.width = std.mem.readIntBig(i32, &raw.width);
        self.depth = std.mem.readIntBig(u16, &raw.depth);
        self.colorMode = std.mem.readIntBig(u16, &raw.colorMode);
    }
};

const Reader = struct {
    data: []const u8,
    index: usize,

    const Self = @This();

    fn init(data: []const u8) Self
    {
        return Self {
            .data = data,
            .index = 0,
        };
    }

    fn remainingBytes(self: *const Self) []const u8
    {
        std.debug.assert(self.index <= self.data.len);
        return self.data[self.index..];
    }

    fn hasRemaining(self: *const Self, size: usize) bool
    {
        return self.index + size <= self.data.len;
    }

    fn readStruct(self: *Self, comptime T: type) !*const T
    {
        std.debug.assert(@typeInfo(T) == .Struct);

        const size = @sizeOf(T);
        if (!self.hasRemaining(size)) {
            return error.OutOfBounds;
        }

        const ptr = @ptrCast(*const T, &self.data[self.index]);
        self.index += size;
        return ptr;
    }

    fn readInt(self: *Self, comptime T: type) !T
    {
        const size = @sizeOf(T);
        if (!self.hasRemaining(size)) {
            return error.OutOfBounds;
        }

        const value = std.mem.readIntBig(T, &self.data[self.index]);
        self.index += size;
        return value;
    }

    fn readLengthAndBytes(self: *Self, comptime LengthType: type) ![]const u8
    {
        const length = try self.readInt(LengthType);
        if (!self.hasRemaining(length)) {
            return error.OutOfBounds;
        }
        const end = self.index + length;
        const slice = self.data[self.index..end];
        self.index = end;
        return slice;
    }

    fn readPascalString(self: *Self) ![]const u8
    {
        return self.readLengthAndBytes(u8);
    }
};

comptime {
    std.debug.assert(@sizeOf(HeaderRaw) == 4 + 2 + 6 + 2 + 4 + 4 + 2 + 2);
}
