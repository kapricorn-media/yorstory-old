const std = @import("std");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

const m = @import("math.zig");
const w = @import("wasm_bindings.zig");

pub const TextureLoadEntry = struct {
    id: c_uint,
    url: []const u8,
    wrapMode: c_uint,
    filter: c_uint,
    priority: u32,
};

pub const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    pub fn init() Self
    {
        return Self {
            .id = w.glCreateTexture(),
            .size = m.Vec2i.zero,
        };
    }

    pub fn loaded(self: Self) bool
    {
        return !m.Vec2i.eql(self.size, m.Vec2i.zero);
    }
};

pub const FontCharData = struct {
    uvOffset: m.Vec2,
    uvSize: m.Vec2,
    offset: m.Vec2,
    advanceX: f32,
};

pub const FontData = struct {
    textureId: c_uint,
    size: f32,
    charData: [256]FontCharData,

    const Self = @This();

    pub fn init(fontFile: []const u8, size: f32, allocator: std.mem.Allocator) !Self
    {
        var self = Self {
            .textureId = 0,
            .size = size,
            .charData = undefined,
        };

        const width = 2048;
        const height = 2048;
        var pixelBytes = try allocator.alloc(u8, width * height);
        std.mem.set(u8, pixelBytes, 0);
        var context: stb.stbtt_pack_context = undefined;
        if (stb.stbtt_PackBegin(&context, &pixelBytes[0], width, height, width, 1, null) != 1) {
            return error.stbtt_PackBegin;
        }
        stb.stbtt_PackSetOversampling(&context, 1, 1);

        var charData = try allocator.alloc(stb.stbtt_packedchar, self.charData.len);
        if (stb.stbtt_PackFontRange(&context, &fontFile[0], 0, 64.0, 0, @intCast(c_int, charData.len), &charData[0]) != 1) {
            return error.stbtt_PackFontRange;
        }

        stb.stbtt_PackEnd(&context);

        for (charData) |_, i| {
            self.charData[i] = FontCharData {
                .uvOffset = m.Vec2.init(
                    @intToFloat(f32, charData[i].x0) / width,
                    @intToFloat(f32, height - charData[i].y1) / height, // TODO should do -1 ?
                ),
                .uvSize = m.Vec2.init(
                    @intToFloat(f32, charData[i].x1 - charData[i].x0) / width,
                    @intToFloat(f32, charData[i].y1 - charData[i].y0) / height,
                ),
                .offset = m.Vec2.init(charData[i].xoff, charData[i].yoff),
                .advanceX = charData[i].xadvance,
            };
        }
        self.textureId = w.createTextureWithData(width, height, 1, &pixelBytes[0], pixelBytes.len, w.GL_CLAMP_TO_EDGE, w.GL_LINEAR);

        return self;
    }
};

pub fn Assets(comptime StaticTextureEnum: type, comptime maxDynamicTextures: usize, comptime StaticFontEnum: type) type
{
    const TextureIdType = enum {
        Static,
        DynamicId,
        DynamicUrl,
    };
    const TextureId = union(TextureIdType) {
        Static: StaticTextureEnum,
        DynamicId: usize,
        DynamicUrl: []const u8,
    };

    const T = struct {
        const numStaticTextures = @typeInfo(StaticTextureEnum).Enum.fields.len;
        const maxTotalTextures = numStaticTextures + maxDynamicTextures;

        const numStaticFonts = @typeInfo(StaticFontEnum).Enum.fields.len;

        allocator: std.mem.Allocator,
        staticTextures: [numStaticTextures]TextureData,
        // TODO use BoundedArray?
        dynamicTexturesSize: usize,
        dynamicTextures: [maxDynamicTextures]TextureData,
        textureLoadQueueSize: usize,
        textureLoadQueue: [maxTotalTextures]TextureLoadEntry,
        textureInflight: usize,
        textureIdMap: std.StringHashMap(usize),
        staticFonts: [numStaticFonts]FontData,

        const Self = @This();

        fn getDynamicTextures(self: *Self) []TextureData
        {
            return self.dynamicTextures[0..self.dynamicTexturesSize];
        }

        fn getDynamicTexturesConst(self: Self) []const TextureData
        {
            return self.dynamicTextures[0..self.dynamicTexturesSize];
        }

        fn getDynamicTextureData(self: Self, id: usize) ?TextureData
        {
            if (id >= self.dynamicTexturesSize) {
                return null;
            }
            return self.dynamicTextures[id];
        }

        fn registerStaticTexture(self: *Self, texture: StaticTextureEnum, textureData: TextureData) !void
        {
            self.staticTextures[@enumToInt(texture)] = textureData;
        }

        fn registerDynamicTexture(self: *Self, url: []const u8, textureData: TextureData) !usize
        {
            if (self.dynamicTexturesSize >= self.dynamicTextures.len) {
                return error.FullDynamicTextures;
            }

            const id = self.dynamicTexturesSize;
            self.dynamicTextures[id] = textureData;

            const urlCopy = try self.allocator.dupe(u8, url);
            try self.textureIdMap.put(urlCopy, id);

            self.dynamicTexturesSize += 1;
            return id;
        }

        fn addLoadEntry(self: *Self, id: c_uint, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !void
        {
            if (self.textureLoadQueueSize >= self.textureLoadQueue.len) {
                return error.FullLoadQueue;
            }

            self.textureLoadQueue[self.textureLoadQueueSize] = TextureLoadEntry {
                .id = id,
                .url = url,
                .wrapMode = wrapMode,
                .filter = filter,
                .priority = priority,
            };
            self.textureLoadQueueSize += 1;
        }

        pub fn init(allocator: std.mem.Allocator) Self
        {
            return Self {
                .allocator = allocator,
                .staticTextures = undefined,
                .dynamicTexturesSize = 0,
                .dynamicTextures = undefined,
                .textureLoadQueueSize = 0,
                .textureLoadQueue = undefined,
                .textureInflight = 0,
                .textureIdMap = std.StringHashMap(usize).init(allocator),
                .staticFonts = undefined,
            };
        }

        pub fn getStaticTextureData(self: Self, texture: StaticTextureEnum) TextureData
        {
            return self.staticTextures[@enumToInt(texture)];
        }

        pub fn getTextureData(self: Self, id: TextureId) ?TextureData
        {
            switch (id) {
                .Static => |t| return self.getStaticTextureData(t),
                .DynamicId => |theId| return self.getDynamicTextureData(theId),
                .DynamicUrl => |url| {
                    const theId = self.textureIdMap.get(url) orelse return null;
                    return self.getDynamicTextureData(theId);
                },
            }
        }

        pub fn register(self: *Self, id: TextureId, url: []const u8, wrapMode: c_uint, filter: c_uint, priority: u32) !usize
        {
            const data = TextureData.init();
            try self.addLoadEntry(data.id, url, wrapMode, filter, priority);
            switch (id) {
                .Static => |t| {
                    try self.registerStaticTexture(t, data);
                    return @intCast(usize, 0);
                },
                .DynamicId => |_| {
                    return self.registerDynamicTexture(url, data);
                },
                .DynamicUrl => |_| {
                    return self.registerDynamicTexture(url, data);
                },
            }
        }

        pub fn loadQueued(self: *Self, maxInflight: usize) void
        {
            if (self.textureLoadQueueSize == 0) {
                return;
            }

            const textureInflight = self.textureInflight;
            const maxToAddInflight = if (maxInflight >= textureInflight) maxInflight - textureInflight else 0;
            const numToLoad = std.math.min(maxToAddInflight, self.textureLoadQueueSize);

            var i: usize = 0;
            while (i < numToLoad) : (i += 1) {
                var entryIndex: usize = 0;
                var j: usize = 1;
                while (j < self.textureLoadQueueSize) : (j += 1) {
                    if (self.textureLoadQueue[j].priority < self.textureLoadQueue[entryIndex].priority) {
                        entryIndex = j;
                    }
                }

                const entry = self.textureLoadQueue[entryIndex];
                w.loadTexture(entry.id, &entry.url[0], entry.url.len, entry.wrapMode, entry.filter);
                self.textureInflight += 1;
                self.textureLoadQueue[entryIndex] = self.textureLoadQueue[self.textureLoadQueueSize - 1];
                self.textureLoadQueueSize -= 1;
            }
        }

        pub fn onTextureLoaded(self: *Self, id: c_uint, size: m.Vec2i) !void
        {
            var found = false;
            for (self.staticTextures) |*texture| {
                if (texture.id == id) {
                    texture.size = size;
                    found = true;
                    break;
                }
            }

            for (self.getDynamicTextures()) |*texture| {
                if (texture.id == id) {
                    texture.size = size;
                    found = true;
                    break;
                }
            }

            self.textureInflight -= 1;

            if (!found) {
                return error.TextureNotFound;
            }
        }

        pub fn registerStaticFont(self: *Self, font: StaticFontEnum, fontFile: []const u8, size: f32, allocator: std.mem.Allocator) !void
        {
            self.staticFonts[@enumToInt(font)] = try FontData.init(fontFile, size, allocator);
        }

        pub fn getStaticFontData(self: Self, font: StaticFontEnum) FontData
        {
            return self.staticFonts[@enumToInt(font)];
        }
    };

    return T;
}